import Testing
@testable import AirlineEmpireCore

/// Route/flight fixtures: airline with an active used narrowbody at STV.
enum RouteFixtures {
    static func withAircraft() throws -> (ContentCatalog, SimulationEngine, AirlineID, AircraftID) {
        let (catalog, engine, airline) = try FleetFixtures.catalogAndEngine()
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180", ageYears: 3))
        let aircraft = engine.state.aircraft.values.first!.id
        return (catalog, engine, airline, aircraft)
    }

    @discardableResult
    static func openStvLnw(_ engine: SimulationEngine, _ airline: AirlineID,
                           trips: Int = 2) -> RouteID {
        let result = engine.applyNow(OpenRouteCommand(
            airline: airline, origin: "ARN", destination: "LHR",
            dailyRoundTrips: trips, ticketPrice: Money.dollars(129)))
        precondition(result == .applied, "\(result)")
        return engine.state.routes.values.first { $0.origin == AirportCode("ARN") }!.id
    }
}

@Suite("Route management")
struct RouteManagementTests {
    @Test func openingAllocatesSlotsAndComputesDistance() throws {
        let (catalog, engine, airline, _) = try RouteFixtures.withAircraft()
        let route = RouteFixtures.openStvLnw(engine, airline, trips: 3)
        let r = try #require(engine.state.routes[route])
        #expect(r.distanceKm == catalog.distanceKm("ARN", "LHR"))
        // 3 round trips = 6 daily movements at each end.
        #expect(engine.state.world.slotsHeld(by: airline, at: "ARN") == 6)
        #expect(engine.state.world.slotsHeld(by: airline, at: "LHR") == 6)
        #expect(engine.state.eventLog.recent.map(\.kind)
            .contains(.routeOpened(id: route, origin: "ARN", destination: "LHR")))
    }

    @Test func openRejections() throws {
        let (_, engine, airline, _) = try RouteFixtures.withAircraft()
        func code(_ c: OpenRouteCommand) -> String? {
            if case .rejected(let r) = engine.applyNow(c) { r.code } else { nil }
        }
        #expect(code(.init(airline: airline, origin: "ARN", destination: "ARN",
                           dailyRoundTrips: 1, ticketPrice: Money.dollars(99)))
                == "route.sameAirport")
        #expect(code(.init(airline: airline, origin: "ARN", destination: "XXX",
                           dailyRoundTrips: 1, ticketPrice: Money.dollars(99)))
                == "route.unknownAirport")
        #expect(code(.init(airline: airline, origin: "ARN", destination: "LHR",
                           dailyRoundTrips: 0, ticketPrice: Money.dollars(99)))
                == "route.badFrequency")
        #expect(code(.init(airline: airline, origin: "ARN", destination: "LHR",
                           dailyRoundTrips: 1, ticketPrice: .zero)) == "route.badPrice")
        RouteFixtures.openStvLnw(engine, airline)
        #expect(code(.init(airline: airline, origin: "LHR", destination: "ARN",
                           dailyRoundTrips: 1, ticketPrice: Money.dollars(99)))
                == "route.duplicate")
    }

    @Test func slotScarcityBlocksOpening() throws {
        // TOS (Tromsø) has 150 slots/day — the calibrated floor for a small
        // field. Fill it with 20-trip routes (40 movements each) until a
        // fourth cannot fit.
        let (_, engine, airline, _) = try RouteFixtures.withAircraft()
        for destination in ["ARN", "OSL", "CPH"] as [AirportCode] {
            #expect(engine.applyNow(OpenRouteCommand(
                airline: airline, origin: "TOS", destination: destination,
                dailyRoundTrips: 20, ticketPrice: Money.dollars(99))) == .applied)
        }
        // 120 of 150 used; another 20-trip route (40 movements) must fail.
        guard case .rejected(let rejection) = engine.applyNow(OpenRouteCommand(
            airline: airline, origin: "TOS", destination: "HEL",
            dailyRoundTrips: 20, ticketPrice: Money.dollars(99))) else {
            Issue.record("Expected slot rejection"); return
        }
        #expect(rejection.code == "route.noSlots")
        // But a small one fits (130 of 150).
        #expect(engine.applyNow(OpenRouteCommand(
            airline: airline, origin: "TOS", destination: "HEL",
            dailyRoundTrips: 5, ticketPrice: Money.dollars(99))) == .applied)
    }

    @Test func frequencyChangeAdjustsSlots() throws {
        let (_, engine, airline, _) = try RouteFixtures.withAircraft()
        let route = RouteFixtures.openStvLnw(engine, airline, trips: 2)
        #expect(engine.applyNow(SetRouteFrequencyCommand(
            airline: airline, route: route, dailyRoundTrips: 5)) == .applied)
        #expect(engine.state.world.slotsHeld(by: airline, at: "ARN") == 10)
        #expect(engine.applyNow(SetRouteFrequencyCommand(
            airline: airline, route: route, dailyRoundTrips: 1)) == .applied)
        #expect(engine.state.world.slotsHeld(by: airline, at: "ARN") == 2)
    }

    @Test func closingReleasesEverything() throws {
        let (_, engine, airline, aircraft) = try RouteFixtures.withAircraft()
        let route = RouteFixtures.openStvLnw(engine, airline)
        _ = engine.applyNow(AssignAircraftToRouteCommand(
            airline: airline, route: route, aircraftID: aircraft))
        #expect(engine.applyNow(CloseRouteCommand(airline: airline, route: route)) == .applied)
        #expect(engine.state.routes.isEmpty)
        #expect(engine.state.flights.isEmpty)
        #expect(engine.state.world.slotsHeld(by: airline, at: "ARN") == 0)
        #expect(engine.state.aircraft[aircraft]!.assignedRoute == nil)
    }

    @Test func assignmentValidation() throws {
        let (_, engine, airline, aircraft) = try RouteFixtures.withAircraft()
        let route = RouteFixtures.openStvLnw(engine, airline)
        // Turboprop NA70 (1450 km) can't fly STV-LNW (~1440+ km? it can);
        // use a clearly-too-far route: STV-NYH (~6300 km) narrowbody fails.
        _ = engine.applyNow(OpenRouteCommand(
            airline: airline, origin: "ARN", destination: "JFK",
            dailyRoundTrips: 1, ticketPrice: Money.dollars(399)))
        let farRoute = engine.state.routes.values.first {
            $0.destination == AirportCode("JFK") }!.id
        guard case .rejected(let r1) = engine.applyNow(AssignAircraftToRouteCommand(
            airline: airline, route: farRoute, aircraftID: aircraft)) else {
            Issue.record("Range should reject"); return
        }
        #expect(r1.code == "route.beyondRange")

        #expect(engine.applyNow(AssignAircraftToRouteCommand(
            airline: airline, route: route, aircraftID: aircraft)) == .applied)
        guard case .rejected(let r2) = engine.applyNow(AssignAircraftToRouteCommand(
            airline: airline, route: farRoute, aircraftID: aircraft)) else {
            Issue.record("Double assignment should reject"); return
        }
        #expect(r2.code == "fleet.alreadyAssigned")
    }

    @Test func runwayLimitBlocksAssignment() throws {
        let (_, base, airline, _) = try RouteFixtures.withAircraft()
        // Widebodies are era-locked since Phase 12; this test is about
        // runways, so fast-forward the era (test surgery).
        var advanced = base.state
        advanced.progression.era = .international
        let engine = SimulationEngine(state: advanced,
                                      systems: GamePipeline.standard(),
                                      catalog: base.catalog)
        // Widebody to Tromsø (small runway).
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR300", ageYears: 5))
        let widebody = engine.state.aircraft.values.first {
            $0.typeCode == AircraftTypeCode("MR300") }!.id
        _ = engine.applyNow(OpenRouteCommand(
            airline: airline, origin: "ARN", destination: "TOS",
            dailyRoundTrips: 1, ticketPrice: Money.dollars(89)))
        let route = engine.state.routes.values.first {
            $0.destination == AirportCode("TOS") }!.id
        guard case .rejected(let rejection) = engine.applyNow(AssignAircraftToRouteCommand(
            airline: airline, route: route, aircraftID: widebody)) else {
            Issue.record("Runway should reject"); return
        }
        #expect(rejection.code == "route.runwayTooSmall")
    }
}

@Suite("Flight operations")
struct FlightOpsTests {
    /// A full operating setup: route STV-LNW, one MR180 assigned, at STV.
    static func operating(trips: Int = 2) throws
        -> (ContentCatalog, SimulationEngine, AirlineID, AircraftID, RouteID) {
        let (catalog, engine, airline, aircraft) = try RouteFixtures.withAircraft()
        let route = RouteFixtures.openStvLnw(engine, airline, trips: trips)
        let result = engine.applyNow(AssignAircraftToRouteCommand(
            airline: airline, route: route, aircraftID: aircraft))
        precondition(result == .applied)
        return (catalog, engine, airline, aircraft, route)
    }

    @Test func fullDayLifecycleCompletesTrips() throws {
        let (_, engine, _, aircraft, route) = try Self.operating(trips: 2)
        engine.advance(ticks: Fixtures.ticksPerDay * 3)
        let stats = engine.state.routes[route]!.stats
        // 2 round trips/day = 4 legs/day; over ~2 operated days with high
        // reliability, most complete (some may be delayed or cancelled).
        #expect(stats.totalFlights >= 6)
        #expect(stats.completionRate > 0.8)
        let kinds = engine.state.eventLog.recent.map(\.kind)
        #expect(kinds.contains { if case .flightDeparted = $0 { true } else { false } })
        #expect(kinds.contains { if case .flightArrived = $0 { true } else { false } })
        // The aircraft ends up parked at an endpoint, not stuck.
        let location = engine.state.aircraft[aircraft]!.location
        #expect(location == AirportCode("ARN") || location == AirportCode("LHR"))
    }

    @Test func operatingCostsArePosted() throws {
        let (_, engine, _, _, _) = try Self.operating()
        engine.advance(ticks: Fixtures.ticksPerDay * 2)
        let categories = Set(engine.state.ledger.recent.map(\.category))
        #expect(categories.contains(.fuel))
        #expect(categories.contains(.airportFees))
        #expect(categories.contains(.crewCosts))
        // Every cost posting is negative (revenue, since Phase 7, offsets
        // them — profitability is asserted in the demand suite).
        for tx in engine.state.ledger.recent
            where [.fuel, .airportFees, .crewCosts].contains(tx.category) {
            #expect(tx.amount < .zero)
        }
    }

    @Test func fuelCostMatchesFormula() throws {
        let (catalog, engine, _, _, route) = try Self.operating(trips: 1)
        engine.advance(ticks: Fixtures.ticksPerDay * 2)
        let spec = catalog.aircraftType("MR180")!
        let distance = engine.state.routes[route]!.distanceKm
        // The world fuel price walks daily, so compare against the current
        // price with a small tolerance (the charge used the arrival-day
        // price at most two days earlier).
        let expected = spec.fuelBurnKgPerKm * Double(distance) / 1000
            * engine.state.world.fuelPricePerTon.asDouble
        let fuelTx = try #require(engine.state.ledger.recent.first { $0.category == .fuel })
        let charged = -fuelTx.amount.asDouble
        #expect(abs(charged - expected) / expected < 0.05,
                "charged \(charged) vs expected \(expected)")
    }

    @Test func aircraftInFlightIsExclusive() throws {
        // The same airframe never serves two live flights (multi-aircraft
        // state corruption guard, Master Prompt 6).
        let (_, engine, _, _, _) = try Self.operating(trips: 6)
        for _ in 0..<(Fixtures.ticksPerDay * 2) {
            engine.advance(ticks: 1)
            var seen: Set<AircraftID> = []
            for flight in engine.state.flights.values {
                let busy: Bool
                switch flight.phase {
                case .boarding, .enRoute, .turnaround: busy = true
                case .scheduled: busy = false
                }
                if busy {
                    #expect(!seen.contains(flight.aircraft),
                            "Aircraft double-booked at \(engine.state.clock.now.rawMinutes)")
                    seen.insert(flight.aircraft)
                }
            }
        }
    }

    @Test func twoAircraftOperateSimultaneously() throws {
        let (_, engine, airline, _, route) = try Self.operating(trips: 6)
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180", ageYears: 4))
        let second = engine.state.aircraft.values.first { $0.assignedRoute == nil }!.id
        #expect(engine.applyNow(AssignAircraftToRouteCommand(
            airline: airline, route: route, aircraftID: second)) == .applied)
        engine.advance(ticks: Fixtures.ticksPerDay * 3)
        let stats = engine.state.routes[route]!.stats
        // Two aircraft roughly double single capacity (4-5 trips/day/frame).
        #expect(stats.totalFlights >= 20)
        #expect(engine.state.integrityViolations().isEmpty)
    }

    @Test func ferryRepositionsAircraft() throws {
        let (_, engine, airline, _) = try RouteFixtures.withAircraft()
        // Route between two airports the aircraft is NOT at.
        _ = engine.applyNow(OpenRouteCommand(
            airline: airline, origin: "LHR", destination: "CDG",
            dailyRoundTrips: 2, ticketPrice: Money.dollars(79)))
        let route = engine.state.routes.values.first!.id
        let aircraft = engine.state.aircraft.values.first!.id
        #expect(engine.state.aircraft[aircraft]!.location == AirportCode("ARN"))
        #expect(engine.applyNow(AssignAircraftToRouteCommand(
            airline: airline, route: route, aircraftID: aircraft)) == .applied)
        engine.advance(ticks: Fixtures.ticksPerDay * 3)
        // Ferry moved it into the rotation; it now serves LNW-PRV.
        let location = engine.state.aircraft[aircraft]!.location
        #expect(location == AirportCode("LHR") || location == AirportCode("CDG"))
        #expect(engine.state.routes[route]!.stats.flightsCompleted > 0)
    }

    /// The ferry used to head for the route's origin or nowhere: with the
    /// origin beyond the aircraft's range, it stayed put for good, silently,
    /// though the destination was within reach.
    @Test func ferryHeadsForTheEndItCanReach() throws {
        let base = try ContentCatalog.loadBundled()
        // On the equator: home to near ~1,110 km, home to far ~3,340 km,
        // near to far ~2,220 km.
        let home = TestAirports.make(code: "HOM", latitude: 0, longitude: 0, slotCapacity: 400)
        let near = TestAirports.make(code: "NER", latitude: 0, longitude: 10, slotCapacity: 400)
        let far = TestAirports.make(code: "FAR", latitude: 0, longitude: 30, slotCapacity: 400)
        let jet = AircraftTypeSpec(
            code: "JET", manufacturer: "Test", model: "Jet", category: .narrowbody,
            seats: 150, rangeKm: 3000, cruiseSpeedKmh: 800, fuelBurnKgPerKm: 2.5,
            listPrice: Money.dollars(50_000_000), leaseMonthly: Money.dollars(400_000),
            maintenancePerFlightHour: Money.dollars(800), crewCockpit: 2, crewCabin: 4,
            reliabilityBaseline: 1.0, runwayRequirement: .large, comfortBaseline: 0.5,
            turnaroundMinutes: 40, deliveryLeadDays: 180)
        let catalog = try ContentCatalog(
            version: "ferry", airports: [home, near, far],
            seasonality: [TestAirports.flatProfile], aircraftTypes: [jet],
            tuning: base.tuning)
        let engine = SimulationEngine(
            state: Fixtures.newState(),
            systems: GamePipeline.standard().filter { $0.id != "worldEvents" },
            catalog: catalog)
        #expect(engine.applyNow(FoundAirlineCommand(
            airlineName: "Ferry Air", kind: .player, homeAirport: "HOM",
            startingCash: Money.dollars(300_000_000))) == .applied)
        let airline = try #require(engine.state.playerAirline).id
        #expect(engine.applyNow(LeaseAircraftCommand(
            lessee: airline, type: "JET", termMonths: 12)) == .applied)
        let aircraft = try #require(engine.state.aircraft.values.first).id
        #expect(engine.applyNow(OpenRouteCommand(
            airline: airline, origin: "FAR", destination: "NER",
            dailyRoundTrips: 1, ticketPrice: Money.dollars(199))) == .applied)
        let route = try #require(engine.state.routes.values.first).id
        #expect(engine.applyNow(AssignAircraftToRouteCommand(
            airline: airline, route: route, aircraftID: aircraft)) == .applied)

        engine.advance(ticks: Fixtures.ticksPerDay * 3)
        let location = try #require(engine.state.aircraft[aircraft]).location
        #expect(location == AirportCode("NER") || location == AirportCode("FAR"))
        let stats = try #require(engine.state.routes[route]).stats
        #expect(stats.flightsCompleted > 0)
    }

    @Test func maintenanceGroundingPausesFlying() throws {
        let (_, engine, airline, _, route) = try Self.operating(trips: 4)
        // Wear the aircraft down fast by flying many days. Track each
        // maintenance visit's CONSECUTIVE grounded streak: a flight already
        // boarded/airborne when grounding hits may legitimately complete
        // into the first fully-grounded day of a visit; beyond that,
        // nothing may fly.
        var totalGroundedDays = 0
        var streak = 0
        var flownWhileGrounded = false
        for _ in 0..<200 {
            let before = engine.state.routes[route]!.stats.flightsCompleted
            engine.advance(ticks: Fixtures.ticksPerDay)
            let grounded: Bool
            if let ac = engine.state.aircraft.values.first(where: { $0.owner == airline }),
               case .inMaintenance = ac.status {
                grounded = true
            } else {
                grounded = false
            }
            if grounded {
                totalGroundedDays += 1
                streak += 1
                let after = engine.state.routes[route]!.stats.flightsCompleted
                if streak > 2 && after > before { flownWhileGrounded = true }
            } else {
                streak = 0
            }
        }
        #expect(totalGroundedDays > 0, "Aircraft never hit maintenance in 200 days")
        #expect(!flownWhileGrounded)
    }

    @Test func disruptionsHappenAtRealisticRates() throws {
        // An old, worn airframe has reliability near the floor (0.85):
        // over many legs, delays and cancellations must both appear.
        let (_, engine, airline, _) = try RouteFixtures.withAircraft()
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "NA70", ageYears: 22))
        let old = engine.state.aircraft.values.first {
            $0.typeCode == AircraftTypeCode("NA70") }!.id
        _ = engine.applyNow(OpenRouteCommand(
            airline: airline, origin: "ARN", destination: "OSL",
            dailyRoundTrips: 6, ticketPrice: Money.dollars(59)))
        let route = engine.state.routes.values.first {
            $0.destination == AirportCode("OSL") }!.id
        _ = engine.applyNow(AssignAircraftToRouteCommand(
            airline: airline, route: route, aircraftID: old))
        engine.advance(ticks: Fixtures.ticksPerDay * 60)
        let stats = engine.state.routes[route]!.stats
        #expect(stats.totalFlights > 100)
        #expect(stats.flightsCancelled > 0)
        #expect(stats.flightsDelayed > 0)
        // ~15% disruption/leg, 20% of those cancel outright, and delay
        // cascades expire displaced flights on this zero-padding schedule —
        // a worn airframe flying back-to-back is SUPPOSED to bleed
        // cancellations. It must still mostly operate.
        #expect(stats.completionRate > 0.7)
        #expect(stats.punctuality < 0.995)
    }

    /// A route flown at its full daily frequency must fly every leg, day
    /// after day. The last leg of such a day lands after midnight (each leg
    /// boards on the tick its aircraft frees up and leaves a tick later), so
    /// the midnight scheduler read the airport that leg had left and put the
    /// next morning's first departure at the wrong end: one cancellation a
    /// day, at 10:00, for as long as the route flew.
    @Test func fullFrequencyRouteFliesEveryLegDayAfterDay() throws {
        let real = try ContentCatalog.loadBundled()
        // ~701 km apart on the equator: 70 min in the air plus 20 overhead
        // at 600 km/h, so with a 45-minute turn four rotations fill the day.
        let west = TestAirports.make(code: "WST", latitude: 0, longitude: 0, slotCapacity: 400)
        let east = TestAirports.make(code: "EST", latitude: 0, longitude: 6.3, slotCapacity: 400)
        let shuttle = AircraftTypeSpec(
            code: "SHT", manufacturer: "Test", model: "Shuttle", category: .narrowbody,
            seats: 150, rangeKm: 3000, cruiseSpeedKmh: 600, fuelBurnKgPerKm: 2.5,
            listPrice: Money.dollars(50_000_000), leaseMonthly: Money.dollars(400_000),
            maintenancePerFlightHour: Money.dollars(800), crewCockpit: 2, crewCabin: 4,
            reliabilityBaseline: 1.0, runwayRequirement: .large, comfortBaseline: 0.5,
            turnaroundMinutes: 45, deliveryLeadDays: 180)
        // Reliability that never erodes, and no world events: every dispatch
        // roll passes, so any cancellation here is the schedule's own.
        let base = real.tuning
        let fleet = FleetTuning(
            annualDepreciationRate: base.fleet.annualDepreciationRate,
            residualValueFraction: base.fleet.residualValueFraction,
            saleFriction: base.fleet.saleFriction,
            usedPriceConditionFloor: base.fleet.usedPriceConditionFloor,
            usedMarketConditionFloor: base.fleet.usedMarketConditionFloor,
            usedMarketConditionLossPerYear: base.fleet.usedMarketConditionLossPerYear,
            maxUsedPurchaseAgeYears: base.fleet.maxUsedPurchaseAgeYears,
            dailyConditionDecay: base.fleet.dailyConditionDecay,
            maintenanceConditionThreshold: base.fleet.maintenanceConditionThreshold,
            maintenanceCheckDays: base.fleet.maintenanceCheckDays,
            maintenanceCheckHoursEquivalent: base.fleet.maintenanceCheckHoursEquivalent,
            maintenanceAgeCostGrowthPerYear: base.fleet.maintenanceAgeCostGrowthPerYear,
            reliabilityConditionWeight: 0, reliabilityAgePenaltyPerYear: 0,
            reliabilityFloor: base.fleet.reliabilityFloor,
            minLeaseTermMonths: base.fleet.minLeaseTermMonths,
            maxLeaseTermMonths: base.fleet.maxLeaseTermMonths,
            earlyLeaseReturnPenaltyMonths: base.fleet.earlyLeaseReturnPenaltyMonths)
        let tuning = Tuning(
            minRouteDistanceKm: base.minRouteDistanceKm, fleet: fleet, ops: base.ops,
            demand: base.demand, finance: base.finance, world: base.world,
            reputation: base.reputation, ai: base.ai, events: base.events,
            progression: base.progression, aircraftConfiguration: base.cabin,
            airportFacilities: base.airportServices)
        let catalog = try ContentCatalog(
            version: "shuttle", airports: [west, east],
            seasonality: [TestAirports.flatProfile], aircraftTypes: [shuttle],
            tuning: tuning)
        let engine = SimulationEngine(
            state: Fixtures.newState(),
            systems: GamePipeline.standard().filter { $0.id != "worldEvents" },
            catalog: catalog)

        #expect(engine.applyNow(FoundAirlineCommand(
            airlineName: "Shuttle Air", kind: .player, homeAirport: "WST",
            startingCash: Money.dollars(300_000_000))) == .applied)
        let airline = try #require(engine.state.playerAirline).id
        #expect(engine.applyNow(LeaseAircraftCommand(
            lessee: airline, type: "SHT", termMonths: 12)) == .applied)
        let aircraft = try #require(engine.state.aircraft.values.first).id
        let trips = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
            distanceKm: Geo.distanceKm(from: west.coordinate, to: east.coordinate),
            spec: shuttle, ops: catalog.tuning.ops)
        #expect(trips >= 2)
        #expect(engine.applyNow(OpenRouteCommand(
            airline: airline, origin: "WST", destination: "EST",
            dailyRoundTrips: trips, ticketPrice: Money.dollars(99))) == .applied)
        let route = try #require(engine.state.routes.values.first).id
        #expect(engine.applyNow(AssignAircraftToRouteCommand(
            airline: airline, route: route, aircraftID: aircraft)) == .applied)

        // By the second midnight, the first day's last leg is still in the
        // air: the moment the scheduler used to misread.
        engine.advance(ticks: Fixtures.ticksPerDay * 2)
        let today = engine.state.clock.now.dayIndex
        #expect(engine.state.flights.values.contains {
            $0.aircraft == aircraft && $0.scheduledDeparture.dayIndex < today
        }, "The fixture should end its day after midnight")

        engine.advance(ticks: Fixtures.ticksPerDay * 4)
        let stats = try #require(engine.state.routes[route]).stats
        #expect(stats.flightsCancelled == 0)
        // Five flown days; every leg but the last one still airborne.
        #expect(stats.flightsCompleted >= Int64(2 * trips * 4))
    }

    @Test func closedRouteStopsCleanly() throws {
        let (_, engine, airline, aircraft, route) = try Self.operating(trips: 2)
        engine.advance(ticks: Fixtures.ticksPerDay + 40) // mid-day, flights live
        // Wait until nothing is airborne (close rejects while enRoute).
        var closed = false
        for _ in 0..<Fixtures.ticksPerDay * 2 {
            if engine.applyNow(CloseRouteCommand(airline: airline, route: route)) == .applied {
                closed = true
                break
            }
            engine.advance(ticks: 1)
        }
        #expect(closed)
        #expect(engine.state.flights.isEmpty)
        #expect(engine.state.aircraft[aircraft]!.activeFlight == nil)
        #expect(engine.state.integrityViolations().isEmpty)
        // World keeps running fine afterwards.
        engine.advance(ticks: Fixtures.ticksPerDay * 2)
        #expect(engine.state.integrityViolations().isEmpty)
    }

    /// Closing a route while its flight turns around used to delete a flight
    /// that had flown — paid for, fuelled, landed — with its completion never
    /// recorded: the player's flight and passenger counters (and the missions
    /// and contracts read from them) lost it.
    @Test func closingDuringTurnaroundStillCountsTheFlight() throws {
        let (_, engine, airline, _, route) = try Self.operating(trips: 2)
        var turning: Flight?
        for _ in 0..<(Fixtures.ticksPerDay * 3) {
            engine.advance(ticks: 1)
            turning = engine.state.flights.values.first {
                if case .turnaround = $0.phase { $0.route == route } else { false }
            }
            if turning != nil { break }
        }
        let flight = try #require(turning, "No flight reached its turnaround")
        let before = engine.state.progression.counters

        #expect(engine.applyNow(CloseRouteCommand(airline: airline, route: route)) == .applied)
        let after = engine.state.progression.counters
        #expect(after.flightsCompleted == before.flightsCompleted + 1)
        #expect(after.passengersCarried == before.passengersCarried + Int64(flight.passengers))
        #expect(engine.state.flights.isEmpty)
        #expect(engine.state.integrityViolations().isEmpty)
    }

    @Test func operationsSurviveSaveLoadMidFlight() throws {
        let (catalog, engine, _, _, _) = try Self.operating(trips: 3)
        // Land exactly mid-day with flights in various phases.
        engine.advance(ticks: Fixtures.ticksPerDay + Fixtures.ticksPerDay / 2)
        let hasLiveFlights = !engine.state.flights.isEmpty
        #expect(hasLiveFlights)

        let saved = try JSONSaveCodec().encode(engine.state)
        let resumed = SimulationEngine(state: try JSONSaveCodec().decode(saved),
                                       systems: GamePipeline.standard(), catalog: catalog)
        resumed.advance(ticks: Fixtures.ticksPerDay * 5)
        engine.advance(ticks: Fixtures.ticksPerDay * 5)
        #expect(try resumed.state.stateHash() == engine.state.stateHash())
    }

    @Test func dualRunDeterminismWithFullPipeline() throws {
        func run() throws -> UInt64 {
            let (_, engine, airline, aircraft, route) = try Self.operating(trips: 3)
            _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "AV90", ageYears: 8))
            let rj = engine.state.aircraft.values.first {
                $0.typeCode == AircraftTypeCode("AV90") }!.id
            _ = engine.applyNow(OpenRouteCommand(
                airline: airline, origin: "ARN", destination: "CPH",
                dailyRoundTrips: 3, ticketPrice: Money.dollars(89)))
            let second = engine.state.routes.values.first {
                $0.destination == AirportCode("CPH") }!.id
            _ = engine.applyNow(AssignAircraftToRouteCommand(
                airline: airline, route: second, aircraftID: rj))
            _ = (route, aircraft)
            engine.advance(ticks: Fixtures.ticksPerDay * 45)
            return try engine.state.stateHash()
        }
        #expect(try run() == run())
    }
}
