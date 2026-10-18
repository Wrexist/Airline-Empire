import Foundation
import Testing
@testable import AirlineEmpireCore

/// A world where long haul can be watched leg by leg: a home airport and two
/// destinations on the equator, 9,000 and 12,000 km away, served by widebodies
/// that never lose reliability, with no world events — so every leg flies
/// when it was planned and what a test sees is the schedule's own timing.
enum LongHaulFixtures {
    static let home: AirportCode = "LHH"
    /// 9,000 km from home: one round trip a day, home overnight.
    static let nineThousand: AirportCode = "LHN"
    /// 12,000 km from home: one round trip every two days.
    static let twelveThousand: AirportCode = "LHT"

    static func airport(_ code: String, longitude: Double, region: WorldRegion) -> AirportSpec {
        AirportSpec(
            code: AirportCode(code), name: "\(code) International", city: code, country: "Testland",
            region: region, coordinate: Coordinate(latitude: 0, longitude: longitude),
            utcOffsetMinutes: 0, runwayClass: .veryLarge, slotCapacityPerDay: 400,
            terminalCapacityPerDay: 60_000, movementFee: Money.dollars(1_000),
            passengerFee: Money.dollars(15),
            demographics: Demographics(populationThousands: 8_000, businessIndex: 0.6,
                                       leisureIndex: 0.6, tourismIndex: 0.6, cargoIndex: 0.5),
            seasonality: "flat", weatherRisk: .low)
    }

    /// The MR-300's figures, on an airframe whose dispatch never fails.
    static let widebody = AircraftTypeSpec(
        code: "LH9", manufacturer: "Test", model: "Long Nine", category: .widebody,
        seats: 298, rangeKm: 11_400, cruiseSpeedKmh: 905, fuelBurnKgPerKm: 6.7,
        listPrice: Money.dollars(285_000_000), leaseMonthly: Money.dollars(2_000_000),
        maintenancePerFlightHour: Money.dollars(1_900), crewCockpit: 3, crewCabin: 9,
        reliabilityBaseline: 1.0, runwayRequirement: .veryLarge, comfortBaseline: 0.66,
        turnaroundMinutes: 75, deliveryLeadDays: 540)

    /// The MR-410's figures, likewise.
    static let largeWidebody = AircraftTypeSpec(
        code: "LH12", manufacturer: "Test", model: "Long Twelve", category: .largeWidebody,
        seats: 408, rangeKm: 13_900, cruiseSpeedKmh: 915, fuelBurnKgPerKm: 8.8,
        listPrice: Money.dollars(410_000_000), leaseMonthly: Money.dollars(2_850_000),
        maintenancePerFlightHour: Money.dollars(2_600), crewCockpit: 3, crewCabin: 12,
        reliabilityBaseline: 1.0, runwayRequirement: .veryLarge, comfortBaseline: 0.68,
        turnaroundMinutes: 90, deliveryLeadDays: 720)

    /// Widebody range at a turboprop's pace: there and back to 9,000 km takes
    /// four days, longer than any rotation the scheduler plans.
    static let crawler = AircraftTypeSpec(
        code: "SLW", manufacturer: "Test", model: "Crawler", category: .widebody,
        seats: 200, rangeKm: 13_000, cruiseSpeedKmh: 220, fuelBurnKgPerKm: 5.0,
        listPrice: Money.dollars(200_000_000), leaseMonthly: Money.dollars(1_000_000),
        maintenancePerFlightHour: Money.dollars(1_000), crewCockpit: 2, crewCabin: 6,
        reliabilityBaseline: 1.0, runwayRequirement: .veryLarge, comfortBaseline: 0.5,
        turnaroundMinutes: 60, deliveryLeadDays: 180)

    static func catalog() throws -> ContentCatalog {
        let base = try ContentCatalog.loadBundled().tuning
        // Reliability that never erodes: every dispatch roll passes.
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
        // A degree of longitude on the equator is 111.19 km.
        return try ContentCatalog(
            version: "long-haul",
            airports: [airport("LHH", longitude: 0, region: .europe),
                       airport("LHN", longitude: 80.94, region: .southeastAsia),
                       airport("LHT", longitude: 107.92, region: .eastAsia)],
            seasonality: [TestAirports.flatProfile],
            aircraftTypes: [widebody, largeWidebody, crawler], tuning: tuning)
    }

    /// The player at home in the International era with `count` leased
    /// aircraft of `type` on one route to `destination` at the reference
    /// fare — assigned to it unless `assign` is false — before the first
    /// midnight.
    static func world(to destination: AirportCode, type: AircraftTypeCode,
                      aircraft count: Int = 1, frequency: Int = 1, assign: Bool = true) throws
        -> (catalog: ContentCatalog, engine: SimulationEngine, airline: AirlineID,
            route: RouteID, fleet: [AircraftID]) {
        let catalog = try catalog()
        let systems = GamePipeline.standard().filter { $0.id != "worldEvents" }
        let founding = SimulationEngine(state: Fixtures.newState(), systems: systems, catalog: catalog)
        #expect(founding.applyNow(FoundAirlineCommand(
            airlineName: "Long Haul Air", kind: .player, homeAirport: home,
            startingCash: Money.dollars(900_000_000))) == .applied)
        var state = founding.state
        state.progression.era = .international  // every class of aircraft
        let engine = SimulationEngine(state: state, systems: systems, catalog: catalog)
        let airline = try #require(engine.state.playerAirline).id
        for _ in 0..<count {
            #expect(engine.applyNow(LeaseAircraftCommand(lessee: airline, type: type,
                                                         termMonths: 24)) == .applied)
        }
        let distance = try #require(catalog.distanceKm(home, destination))
        #expect(engine.applyNow(OpenRouteCommand(
            airline: airline, origin: home, destination: destination, dailyRoundTrips: frequency,
            ticketPrice: Money(rounding: DemandSystem.referenceFare(
                distanceKm: distance, tuning: catalog.tuning.demand)))) == .applied)
        let route = try #require(engine.state.routes(of: airline).first).id
        let fleet = engine.state.fleet(of: airline).map(\.id).sorted()
        for id in fleet where assign {
            #expect(engine.applyNow(AssignAircraftToRouteCommand(
                airline: airline, route: route, aircraftID: id)) == .applied)
        }
        return (catalog, engine, airline, route, fleet)
    }

    /// Advances `days` midnights and returns the days a rotation left home
    /// at the window's opening; on the way, checks that every leg planned
    /// leaves inside the operating window.
    static func homeDepartureDays(_ engine: SimulationEngine, route routeID: RouteID,
                                  days: Int) -> [Int64] {
        var out: [Int64] = []
        for _ in 0..<days {
            engine.advance(ticks: Fixtures.ticksPerDay)
            let state = engine.state
            guard let route = state.routes[routeID] else { return out }
            let window = state.operatingWindow(for: route, catalog: engine.catalog)
            let dayStart = state.clock.now.dayIndex * GameCalendar.minutesPerDay
            for flight in state.flights.values
            where flight.route == routeID && flight.kind == .revenue && flight.phase == .scheduled {
                #expect(flight.scheduledDeparture.minuteOfDay >= window.startMinute
                        && flight.scheduledDeparture.minuteOfDay < window.endMinute,
                        "a leg planned to leave at \(flight.scheduledDeparture.minuteOfDay) min")
            }
            let opening = SimTime(rawMinutes: dayStart + window.startMinute)
            if state.flights.values.contains(where: {
                $0.route == routeID && $0.from == home && $0.scheduledDeparture == opening
            }) {
                out.append(state.clock.now.dayIndex)
            }
        }
        return out
    }
}

/// Long haul (docs/ROUTES.md): a round trip longer than the operating day
/// flies as a rotation over days instead of never flying at all.
@Suite("Long haul")
struct LongHaulTests {
    private func context(_ state: GameState, _ catalog: ContentCatalog) -> SimContext {
        .init(previous: state.clock.now, current: state.clock.now, tick: .minutes(0),
              catalog: catalog, events: EventCollector(), progressionCeiling: .empire)
    }

    private func flightMinutes(_ spec: AircraftTypeSpec, _ distanceKm: Int,
                               _ catalog: ContentCatalog) -> Int64 {
        FlightSchedulingSystem.flightMinutes(distanceKm: distanceKm, cruiseSpeedKmh: spec.cruiseSpeedKmh,
                                             overheadMinutes: catalog.tuning.ops.flightOverheadMinutes)
    }

    // MARK: The rotation arithmetic

    @Test("Day routes keep their arithmetic; every long-haul pairing in the catalogue gets a rotation")
    func dayRoutesKeepTheirArithmetic() throws {
        let catalog = try ContentCatalog.loadBundled()
        let ops = catalog.tuning.ops
        var longHaul = 0
        for spec in catalog.orderedAircraftTypeCodes.compactMap({ catalog.aircraftType($0) }) {
            for distance in stride(from: 300, through: spec.rangeKm, by: 250) {
                let trips = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
                    distanceKm: distance, spec: spec, ops: ops)
                let rotation = FlightSchedulingSystem.rotation(distanceKm: distance, spec: spec, ops: ops)
                if trips > 0 {
                    #expect(rotation == .init(roundTrips: trips, days: 1, isLongHaul: false))
                } else {
                    longHaul += 1
                    #expect(rotation.isLongHaul && rotation.isFlyable)
                    #expect((1...FlightSchedulingSystem.maxRotationDays).contains(rotation.days))
                    #expect(rotation.tripsPerDay == 1 / Double(rotation.days))
                }
            }
        }
        #expect(longHaul > 20, "the catalogue's widebodies reach past the day")
    }

    @Test("A departure waits for the operating window, and leaves inside it at once")
    func nextDepartureRespectsTheWindow() {
        let standard = OperatingWindow(startMinute: 360, minutes: 1_080)
        func next(_ minutes: Int64, _ window: OperatingWindow) -> Int64 {
            FlightSchedulingSystem.nextDeparture(atOrAfter: SimTime(rawMinutes: minutes), in: window).rawMinutes
        }
        #expect(next(60, standard) == 360)            // 01:00 waits for 06:00
        #expect(next(1_380, standard) == 1_380)       // 23:00 leaves at once
        #expect(next(1_470, standard) == 1_800)       // 00:30 waits for the next morning
        // A crew base runs the window past midnight: 05:00–01:00.
        let based = OperatingWindow(startMinute: 300, minutes: 1_200)
        #expect(next(1_470, based) == 1_470)          // 00:30 is still yesterday's window
        #expect(next(1_560, based) == 1_740)          // 02:00 waits for 05:00
    }

    // MARK: Flying it

    @Test("A 9,000 km widebody route flies a round trip every day and earns")
    func nineThousandKilometresFliesAndEarns() throws {
        let (catalog, engine, _, routeID, _) = try LongHaulFixtures.world(
            to: LongHaulFixtures.nineThousand, type: "LH9")
        let route = try #require(engine.state.routes[routeID])
        let spec = LongHaulFixtures.widebody
        #expect((8_990...9_010).contains(route.distanceKm))
        let rotation = FlightSchedulingSystem.rotation(spec: spec, on: route, state: engine.state,
                                                       catalog: catalog)
        #expect(rotation.isLongHaul)
        #expect(rotation.days == 1)
        #expect(FlightSchedulingSystem.roundTripsPerDay(spec: spec, on: route, state: engine.state,
                                                        catalog: catalog) == 0,
                "longer than the day: no back-to-back rotation fits")

        // The first day's plan: out at the opening, back after the turn the
        // same evening, landing after midnight.
        engine.advance(ticks: Fixtures.ticksPerDay)
        let minutes = flightMinutes(spec, route.distanceKm, catalog)
        let dayStart = SimTime(rawMinutes: engine.state.clock.now.dayIndex * GameCalendar.minutesPerDay)
        let legs = engine.state.flights.values.filter { $0.route == routeID }
            .sorted { $0.scheduledDeparture < $1.scheduledDeparture }
        try #require(legs.count == 2)
        #expect(legs[0].from == LongHaulFixtures.home)
        #expect(legs[0].scheduledDeparture == dayStart + .minutes(catalog.tuning.ops.operatingDayStartMinute))
        #expect(legs[1].from == LongHaulFixtures.nineThousand)
        #expect(legs[1].scheduledDeparture
                == legs[0].scheduledDeparture + .minutes(minutes + Int64(spec.turnaroundMinutes)))
        #expect((legs[1].scheduledDeparture + .minutes(minutes)).dayIndex == dayStart.dayIndex + 1)

        // Every day after: one rotation, every leg leaving inside the window.
        let days = LongHaulFixtures.homeDepartureDays(engine, route: routeID, days: 9)
        #expect(days == Array(2...10))
        let flown = try #require(engine.state.routes[routeID])
        #expect(flown.stats.flightsCancelled == 0)
        // Eight whole rotations and the ninth's outbound leg; its return
        // lands on the morning of day 10.
        #expect(flown.stats.flightsCompleted == 17)
        #expect(flown.stats.passengersCarried > 0)
        #expect(flown.economicsThisMonth.revenueCents > 0)
        #expect(flown.economicsThisMonth.directOperatingProfit > .zero,
                "a full widebody day route at the reference fare clears fuel, fees and crew")
    }

    @Test("A 12,000 km route flies a round trip every other day, and daily with two aircraft")
    func twelveThousandKilometresFliesEveryOtherDay() throws {
        let (catalog, engine, _, routeID, _) = try LongHaulFixtures.world(
            to: LongHaulFixtures.twelveThousand, type: "LH12")
        let route = try #require(engine.state.routes[routeID])
        let rotation = FlightSchedulingSystem.rotation(spec: LongHaulFixtures.largeWidebody, on: route,
                                                       state: engine.state, catalog: catalog)
        #expect(rotation.isLongHaul && rotation.days == 2)
        #expect(rotation.tripsPerDay == 0.5)
        #expect(FlightSchedulingSystem.flyableTripsPerDay(route: route, state: engine.state,
                                                          catalog: catalog) == 0.5)
        #expect(FlightSchedulingSystem.demandDaysPerDeparture(route: route, state: engine.state,
                                                              catalog: catalog) == 2)

        let days = LongHaulFixtures.homeDepartureDays(engine, route: routeID, days: 10)
        #expect(days == [1, 3, 5, 7, 9])
        let flown = try #require(engine.state.routes[routeID])
        #expect(flown.stats.flightsCancelled == 0)
        // Four whole rotations and the fifth's outbound leg.
        #expect(flown.stats.flightsCompleted == 9)
        #expect(flown.economicsThisMonth.revenueCents > 0)

        // A second aircraft takes the days between: a departure every day.
        let (_, pair, _, pairRoute, _) = try LongHaulFixtures.world(
            to: LongHaulFixtures.twelveThousand, type: "LH12", aircraft: 2)
        let pairing = try #require(pair.state.routes[pairRoute])
        #expect(FlightSchedulingSystem.flyableTripsPerDay(route: pairing, state: pair.state,
                                                          catalog: catalog) == 1)
        #expect(LongHaulFixtures.homeDepartureDays(pair, route: pairRoute, days: 10) == Array(1...10))
        let pairFlown = try #require(pair.state.routes[pairRoute])
        #expect(pairFlown.stats.flightsCompleted >= 15)
    }

    @Test("A departure flown every other day sells both days' demand")
    func everyOtherDaySellsTheDayBetween() throws {
        let (catalog, engine, _, routeID, _) = try LongHaulFixtures.world(
            to: LongHaulFixtures.twelveThousand, type: "LH12")
        engine.advance(ticks: Fixtures.ticksPerDay)
        let route = try #require(engine.state.routes[routeID])
        let demand = route.demandOutboundToday
        try #require(demand > 0)
        #expect(FlightOpsSystem.backlog(on: route, outbound: true, state: engine.state,
                                        catalog: catalog) == demand)
        engine.advance(ticks: 25)  // 06:15: the outbound leg is away
        let away = try #require(engine.state.flights.values.first {
            $0.route == routeID && $0.from == LongHaulFixtures.home
        })
        if case .enRoute = away.phase {} else { Issue.record("expected the outbound leg airborne") }
        #expect(away.passengers == min(LongHaulFixtures.largeWidebody.seats, 2 * demand))

        // With a departure every day there is no day between to sell.
        let (_, pair, _, pairRoute, _) = try LongHaulFixtures.world(
            to: LongHaulFixtures.twelveThousand, type: "LH12", aircraft: 2)
        pair.advance(ticks: Fixtures.ticksPerDay)
        let daily = try #require(pair.state.routes[pairRoute])
        #expect(FlightOpsSystem.backlog(on: daily, outbound: true,
                                        state: pair.state, catalog: catalog) == 0)
    }

    @Test("A leg that crosses midnight lands, posts its costs on the next day and chains into its rotation")
    func legsCrossingMidnight() throws {
        let (_, engine, airline, routeID, fleet) = try LongHaulFixtures.world(
            to: LongHaulFixtures.nineThousand, type: "LH9")
        let aircraftID = try #require(fleet.first)
        engine.advance(ticks: Fixtures.ticksPerDay * 2)  // day 2, 00:00
        // Day 2's own return leg is planned by now too: the earliest leg
        // back is day 1's (dictionary order is not a time order).
        let overnight = try #require(engine.state.flights.values
            .filter { $0.route == routeID && $0.from == LongHaulFixtures.nineThousand }
            .min { $0.scheduledDeparture < $1.scheduledDeparture })
        guard case .enRoute(let departed) = overnight.phase else {
            Issue.record("the return leg should be airborne at midnight"); return
        }
        #expect(departed.dayIndex == 1)
        #expect((departed + .minutes(overnight.flightMinutes)).dayIndex == 2)

        engine.advance(ticks: 25)  // 06:15 on day 2
        let state = engine.state
        let route = try #require(state.routes[routeID])
        #expect(route.stats.flightsCompleted == 2, "both of day 1's legs, the second after midnight")
        #expect(state.flights[overnight.id] == nil)
        // Its fuel was booked when it landed, on day 2; its tickets on day 1.
        #expect((state.ledger.dayTotals(of: airline, day: 2)?.debits[.fuel] ?? 0) < 0)
        #expect((state.ledger.dayTotals(of: airline, day: 1)?.credits[.ticketRevenue] ?? 0) > 0)
        // And the aircraft it brought home has left on day 2's rotation.
        let next = try #require(state.flights.values.first {
            $0.aircraft == aircraftID && $0.from == LongHaulFixtures.home
        })
        #expect(next.scheduledDeparture.dayIndex == 2)
        if case .enRoute = next.phase {} else { Issue.record("day 2's outbound leg should be away") }
    }

    // MARK: Maintenance

    @Test("One that could not fly a rotation above the threshold goes in at home, with nothing cancelled")
    func checkStartsAtHomeBeforeARotation() throws {
        let (catalog, engine, _, routeID, fleet) = try LongHaulFixtures.world(
            to: LongHaulFixtures.twelveThousand, type: "LH12")
        let aircraftID = try #require(fleet.first)
        let tuning = catalog.tuning.fleet
        var state = engine.state
        // Airworthy today, not for two days and two long legs.
        state.aircraft[aircraftID]?.condition = tuning.maintenanceConditionThreshold
            + tuning.dailyConditionDecay * 1.5
        let worn = SimulationEngine(state: state, systems: engine.systems, catalog: catalog)
        worn.advance(ticks: Fixtures.ticksPerDay)
        let aircraft = try #require(worn.state.aircraft[aircraftID])
        #expect(aircraft.status.isInMaintenance)
        #expect(aircraft.location == LongHaulFixtures.home)
        #expect(!worn.state.flights.values.contains { $0.aircraft == aircraftID })
        #expect(worn.state.eventLog.recent.contains {
            if case .maintenanceStarted(let id, _, _) = $0.kind { id == aircraftID } else { false }
        })
        worn.advance(ticks: Fixtures.ticksPerDay * 6)
        let after = try #require(worn.state.routes[routeID])
        #expect(after.stats.flightsCancelled == 0)
        // Back from the check, it flies again.
        #expect(after.stats.flightsCompleted > 0)
    }

    @Test("A check that falls due on a rotation waits until the aircraft is home")
    func checkWaitsUntilHome() throws {
        let (catalog, engine, _, _, fleet) = try LongHaulFixtures.world(
            to: LongHaulFixtures.twelveThousand, type: "LH12")
        let aircraftID = try #require(fleet.first)
        engine.advance(ticks: Fixtures.ticksPerDay + 48)  // day 1, 12:00: out on the first leg
        var away = engine.state
        #expect(away.hasLegsAhead(aircraftID))
        away.aircraft[aircraftID]?.condition = catalog.tuning.fleet.maintenanceConditionThreshold - 0.01
        var deferred = away
        FleetSystem().update(state: &deferred, context: context(deferred, catalog))
        #expect(deferred.aircraft[aircraftID]?.status == .active,
                "a check at the far end would cancel the return leg")
        var home = away
        home.flights = home.flights.filter { $0.value.aircraft != aircraftID }
        FleetSystem().update(state: &home, context: context(home, catalog))
        #expect(home.aircraft[aircraftID]?.status.isInMaintenance == true)
    }

    @Test("The check estimate counts a long-haul airframe's half a round trip a day")
    func checkEstimateUsesTheFraction() throws {
        let (catalog, engine, _, routeID, fleet) = try LongHaulFixtures.world(
            to: LongHaulFixtures.twelveThousand, type: "LH12")
        let aircraftID = try #require(fleet.first)
        let route = try #require(engine.state.routes[routeID])
        let spec = LongHaulFixtures.largeWidebody
        let ops = catalog.tuning.ops
        let trips = try #require(FlightSchedulingSystem.tripsPerDay(
            route: route, aircraftID: aircraftID, state: engine.state, spec: spec, ops: ops,
            facilities: catalog.tuning.airportServices))
        #expect(trips == 0.5)
        let hours = try #require(FlightSchedulingSystem.blockHoursPerDay(
            route: route, aircraftID: aircraftID, state: engine.state, spec: spec, ops: ops,
            facilities: catalog.tuning.airportServices))
        #expect(abs(hours - Double(flightMinutes(spec, route.distanceKm, catalog)) / 60) < 1e-9)
        let airline = try #require(engine.state.playerAirline).id
        let row = try #require(engine.state.fleetBoard(for: airline, catalog: catalog).rows
            .first { $0.card.id == aircraftID })
        #expect(row.checkDueInDays != nil)
    }

    // MARK: Saves

    @Test("A save taken mid-rotation continues identically")
    func aSaveMidRotationContinues() throws {
        let (catalog, source, _, routeID, fleet) = try LongHaulFixtures.world(
            to: LongHaulFixtures.twelveThousand, type: "LH12")
        source.advance(ticks: Fixtures.ticksPerDay + 92)  // day 1, 23:00: the return leg is away
        let aircraftID = try #require(fleet.first)
        #expect(source.state.flights.values.contains {
            if case .enRoute = $0.phase { $0.aircraft == aircraftID } else { false }
        })
        let restored = SimulationEngine(
            state: try JSONSaveCodec().decode(JSONSaveCodec().encode(source.state)),
            systems: source.systems, catalog: catalog)
        #expect(restored.state == source.state)
        source.advance(ticks: Fixtures.ticksPerDay * 5)
        restored.advance(ticks: Fixtures.ticksPerDay * 5)
        #expect(restored.state == source.state)
        let continued = try #require(restored.state.routes[routeID])
        #expect(continued.stats.flightsCompleted >= 5)
    }

    // MARK: What the player is shown

    @Test("Route and airframe estimates price long haul at its fraction of a round trip")
    func estimatesUseTheFraction() throws {
        let (catalog, engine, _, routeID, fleet) = try LongHaulFixtures.world(
            to: LongHaulFixtures.twelveThousand, type: "LH12")
        engine.advance(ticks: Fixtures.ticksPerDay)
        let state = engine.state
        let route = try #require(state.routes[routeID])
        let quote = try #require(RoutePlanPreview.make(routeID: routeID, plan: RoutePlan(route: route),
                                                       state: state, catalog: catalog))
        #expect(quote.tripsPerDay == 0.5)
        #expect(quote.seatsPerDay == LongHaulFixtures.largeWidebody.seats)
        #expect(quote.revenue > .zero)
        let aircraftID = try #require(fleet.first)
        let airframe = try #require(state.aircraft[aircraftID])
        let preview = try #require(AircraftConfigurationPreview.make(
            aircraftID: aircraftID, configuration: airframe.cabin(for: LongHaulFixtures.largeWidebody),
            state: state, catalog: catalog))
        #expect(preview.tripsPerDay == 0.5)

        // The shop's comparison: half a round trip per airframe, two for a daily frequency.
        let comparison = try #require(state.aircraftMarketComparison(routeID: routeID, catalog: catalog,
                                                                     era: .international))
        let candidate = try #require(comparison.candidates.first { $0.spec.code == "LH12" })
        #expect(candidate.tripsPerAircraft == 0.5)
        #expect(candidate.aircraftNeeded == 2)

        // Market opportunities: the pair pays something toward its airframe
        // rather than nothing at all.
        let spec = LongHaulFixtures.largeWidebody
        let result = try #require(state.airframeResult(
            from: LongHaulFixtures.home, to: LongHaulFixtures.twelveThousand,
            distanceKm: route.distanceKm, candidateSpecs: [spec], incumbents: [], catalog: catalog))
        let fixed = spec.leaseMonthly + catalog.tuning.finance.payrollPerAircraftMonthly
            + catalog.tuning.finance.payrollPerRouteMonthly
        #expect(result.monthly > Money(cents: -fixed.cents))
    }

    // MARK: Assignment

    @Test("A long-haul pairing is accepted and says how it flies")
    func longHaulAssignmentIsAccepted() throws {
        let (catalog, engine, airline, _, _) = try LongHaulFixtures.world(
            to: LongHaulFixtures.twelveThousand, type: "LH12")
        #expect(engine.applyNow(LeaseAircraftCommand(lessee: airline, type: "LH12", termMonths: 24)) == .applied)
        let spare = try #require(engine.state.fleet(of: airline).first { $0.assignedRoute == nil })
        let route = try #require(engine.state.routes(of: airline).first)
        #expect(AssignAircraftToRouteCommand(airline: airline, route: route.id, aircraftID: spare.id)
            .validate(state: engine.state, catalog: catalog) == nil)
        let candidate = engine.state.candidate(aircraft: spare, route: route, catalog: catalog)
        #expect(candidate.isEligible)
        #expect(candidate.note == .longHaul(rotationDays: 2))
    }

    @Test("A rotation longer than the scheduler plans is refused, by model and validator alike")
    func rotationBeyondTheLimitIsRefused() throws {
        let (catalog, engine, airline, _, _) = try LongHaulFixtures.world(
            to: LongHaulFixtures.nineThousand, type: "SLW", assign: false)
        let crawler = try #require(engine.state.fleet(of: airline).first)
        let route = try #require(engine.state.routes(of: airline).first)
        #expect(route.distanceKm <= LongHaulFixtures.crawler.rangeKm, "precondition: range alone allows it")
        #expect(!FlightSchedulingSystem.rotation(spec: LongHaulFixtures.crawler, on: route,
                                                 state: engine.state, catalog: catalog).isFlyable)
        #expect(AssignAircraftToRouteCommand(airline: airline, route: route.id, aircraftID: crawler.id)
            .validate(state: engine.state, catalog: catalog)?.code == "route.tooLongForDay")
        let candidate = engine.state.candidate(aircraft: crawler, route: route, catalog: catalog)
        guard case .rotationTooLong(let roundTrip, let maxDays)? = candidate.blocker else {
            Issue.record("expected rotationTooLong, got \(String(describing: candidate.blocker))")
            return
        }
        #expect(maxDays == FlightSchedulingSystem.maxRotationDays)
        #expect(roundTrip > Int64(maxDays) * GameCalendar.minutesPerDay / 2)
        #expect(candidate.note == nil)
    }
}
