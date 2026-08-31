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
        // KRK (Tromsø) has 90 slots/day; grab them with 20-trip routes(40
        // movements each) until exhausted.
        let (_, engine, airline, _) = try RouteFixtures.withAircraft()
        #expect(engine.applyNow(OpenRouteCommand(
            airline: airline, origin: "TOS", destination: "ARN",
            dailyRoundTrips: 20, ticketPrice: Money.dollars(99))) == .applied)
        #expect(engine.applyNow(OpenRouteCommand(
            airline: airline, origin: "TOS", destination: "OSL",
            dailyRoundTrips: 20, ticketPrice: Money.dollars(99))) == .applied)
        // 80 of 90 used; another 20-trip route (40 movements) must fail.
        guard case .rejected(let rejection) = engine.applyNow(OpenRouteCommand(
            airline: airline, origin: "TOS", destination: "CPH",
            dailyRoundTrips: 20, ticketPrice: Money.dollars(99))) else {
            Issue.record("Expected slot rejection"); return
        }
        #expect(rejection.code == "route.noSlots")
        // But a small one fits.
        #expect(engine.applyNow(OpenRouteCommand(
            airline: airline, origin: "TOS", destination: "CPH",
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
