import Testing
@testable import AirlineEmpireCore

@Suite("World events")
struct WorldEventTests {
    /// Injects an event into a copy of the engine's state — test-only
    /// surgery for effect verification; generation paths are tested
    /// separately.
    static func engineWithEvent(_ kind: WorldEventKind, days: Int64,
                                severity: Double, from engine: SimulationEngine)
        -> SimulationEngine {
        var state = engine.state
        let now = state.clock.now
        var event = WorldEvent(id: state.world.nextEventID, kind: kind,
                               beginsAt: now, endsAt: now + .days(days),
                               severity: severity)
        event.hasStarted = true
        state.world.nextEventID += 1
        state.world.activeEvents.append(event)
        return SimulationEngine(state: state, systems: engine.systems,
                                catalog: engine.catalog)
    }

    @Test func eventsOccurExpireAndStayBounded() throws {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(seed: 31),
                                      systems: [WorldEventSystem()], catalog: catalog)
        var maxConcurrentRegional = 0
        var sawStorm = false
        var sawEnd = false
        for _ in 0..<(5 * 365) {
            engine.advance(ticks: Fixtures.ticksPerDay)
            let regional = engine.state.world.activeEvents.filter {
                switch $0.kind {
                case .storm, .tourismBoom, .airportClosure: true
                default: false
                }
            }.count
            maxConcurrentRegional = max(maxConcurrentRegional, regional)
            let kinds = engine.state.eventLog.recent.map(\.kind)
            if kinds.contains(where: {
                if case .worldEventStarted(_, .storm) = $0 { true } else { false }
            }) { sawStorm = true }
            if kinds.contains(where: {
                if case .worldEventEnded = $0 { true } else { false }
            }) { sawEnd = true }
        }
        #expect(sawStorm, "No storm in five years")
        #expect(sawEnd, "Events never ended")
        #expect(maxConcurrentRegional <= catalog.tuning.events.maxActiveRegionalEvents + 1)
        // Population stays small forever (expiry works).
        #expect(engine.state.world.activeEvents.count < 8)
    }

    @Test func stormsCarryForecastLead() throws {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(seed: 8),
                                      systems: [WorldEventSystem()], catalog: catalog)
        var forecastSeen = false
        for _ in 0..<(5 * 365) {
            engine.advance(ticks: Fixtures.ticksPerDay)
            for event in engine.state.eventLog.recent {
                if case .worldEventForecast(.storm, let beginsAt) = event.kind {
                    #expect(beginsAt.rawMinutes > event.at.rawMinutes)
                    forecastSeen = true
                }
            }
            if forecastSeen { break }
        }
        #expect(forecastSeen)
    }

    @Test func fuelShockRaisesPrices() throws {
        let catalog = try ContentCatalog.loadBundled()
        let base = SimulationEngine(state: Fixtures.newState(seed: 5),
                                    systems: [WorldSystem()], catalog: catalog)
        base.advance(ticks: Fixtures.ticksPerDay * 60)
        let calm = base.state.world.fuelPricePerTon

        let shocked = Self.engineWithEvent(.fuelShock, days: 60, severity: 0.8, from: base)
        shocked.advance(ticks: Fixtures.ticksPerDay * 60)
        let shockedPrice = shocked.state.world.fuelPricePerTon
        #expect(shockedPrice.asDouble > calm.asDouble * 1.3,
                "shock \(shockedPrice.cents) vs calm \(calm.cents)")
    }

    @Test func airportClosureGroundsAndRecovers() throws {
        let (_, engine, _, _, route) = try FlightOpsTests.operating(trips: 2)
        engine.advance(ticks: Fixtures.ticksPerDay * 5)
        let before = engine.state.routes[route]!.stats

        let closed = Self.engineWithEvent(.airportClosure(airport: "ARN"),
                                          days: 2, severity: 1, from: engine)
        closed.advance(ticks: Fixtures.ticksPerDay * 2)
        let during = closed.state.routes[route]!.stats
        // Nothing completed while the origin was shut; cancellations accrued.
        #expect(during.flightsCompleted <= before.flightsCompleted + 1)
        #expect(during.flightsCancelled > before.flightsCancelled)

        closed.advance(ticks: Fixtures.ticksPerDay * 5)
        let after = closed.state.routes[route]!.stats
        #expect(after.flightsCompleted > during.flightsCompleted, "Ops must resume")
        #expect(closed.state.integrityViolations().isEmpty)
    }

    @Test func strikeStopsOneAirlineOnly() throws {
        let catalog = try DemandFixtures.anchorCatalog()
        let engine = SimulationEngine(state: Fixtures.newState(),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(airlineName: "Struck", kind: .player,
                                                homeAirport: "MET",
                                                startingCash: Money.dollars(300_000_000)))
        _ = engine.applyNow(FoundAirlineCommand(airlineName: "Flying", kind: .ai,
                                                homeAirport: "COS",
                                                startingCash: Money.dollars(300_000_000)))
        let struck = engine.state.airlines.values.first { $0.name == "Struck" }!.id
        let flying = engine.state.airlines.values.first { $0.name == "Flying" }!.id
        for (airline, home) in [(struck, "MET"), (flying, "COS")] {
            _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180",
                                                       ageYears: 2))
            let aircraft = engine.state.aircraft.values.first {
                $0.owner == airline && $0.assignedRoute == nil }!.id
            let away: AirportCode = home == "MET" ? "COS" : "MET"
            _ = engine.applyNow(OpenRouteCommand(
                airline: airline, origin: AirportCode(home), destination: away,
                dailyRoundTrips: 2, ticketPrice: Money.dollars(129)))
            let route = engine.state.routes.values.first { $0.airline == airline }!.id
            _ = engine.applyNow(AssignAircraftToRouteCommand(
                airline: airline, route: route, aircraftID: aircraft))
        }
        engine.advance(ticks: Fixtures.ticksPerDay * 5)
        let struckBefore = engine.state.routes.values.first { $0.airline == struck }!
            .stats.flightsCompleted
        let flyingBefore = engine.state.routes.values.first { $0.airline == flying }!
            .stats.flightsCompleted

        let strikeEngine = Self.engineWithEvent(.strike(airline: struck), days: 3,
                                                severity: 1, from: engine)
        strikeEngine.advance(ticks: Fixtures.ticksPerDay * 3)
        let struckDuring = strikeEngine.state.routes.values.first { $0.airline == struck }!
            .stats.flightsCompleted
        let flyingDuring = strikeEngine.state.routes.values.first { $0.airline == flying }!
            .stats.flightsCompleted
        #expect(struckDuring <= struckBefore + 1, "Struck airline kept flying")
        #expect(flyingDuring > flyingBefore, "Unaffected airline was grounded too")
    }

    @Test func tourismBoomLiftsRouteDemand() throws {
        let (engine, _, route) = try DemandFixtures.market(fare: Money.dollars(129))
        engine.advance(ticks: Fixtures.ticksPerDay * 10)
        let normal = engine.state.routes[route]!.demandOutboundToday

        // COS is in .europe in the anchor catalog.
        let boom = Self.engineWithEvent(.tourismBoom(region: .europe), days: 60,
                                        severity: 0.35, from: engine)
        boom.advance(ticks: Fixtures.ticksPerDay * 10)
        let boosted = boom.state.routes[route]!.demandOutboundToday
        #expect(Double(boosted) > Double(normal) * 1.05,
                "boom \(boosted) vs normal \(normal)")
    }

    @Test func stormsRaiseDisruptions() throws {
        let (_, engine, _, _, route) = try FlightOpsTests.operating(trips: 4)
        engine.advance(ticks: Fixtures.ticksPerDay * 10)
        let before = engine.state.routes[route]!.stats

        // Permanent violent storm over Europe (both endpoints).
        let stormy = Self.engineWithEvent(.storm(region: .europe), days: 30,
                                          severity: 1.0, from: engine)
        stormy.advance(ticks: Fixtures.ticksPerDay * 30)
        let after = stormy.state.routes[route]!.stats
        let disrupted = (after.flightsCancelled - before.flightsCancelled)
            + (after.flightsDelayed - before.flightsDelayed)
        let flights = after.totalFlights - before.totalFlights
        // ~60%+ disruption probability with double storm exposure: a large
        // share of flights must be delayed or cancelled.
        #expect(flights > 0)
        #expect(Double(disrupted) > Double(flights) * 0.3,
                "disrupted \(disrupted) of \(flights)")
    }

    @Test func eventsAreDeterministicAndSaveSafe() throws {
        let catalog = try ContentCatalog.loadBundled()
        func run() throws -> UInt64 {
            let engine = SimulationEngine(state: Fixtures.newState(seed: 99),
                                          systems: GamePipeline.standard(), catalog: catalog)
            _ = engine.applyNow(FoundAirlineCommand(
                airlineName: "Evented", kind: .player, homeAirport: "MIA",
                startingCash: Money.dollars(100_000_000)))
            engine.advance(ticks: Fixtures.ticksPerYear * 2)
            return try engine.state.stateHash()
        }
        #expect(try run() == run())

        // Save/restore mid-events continues identically.
        let engine = SimulationEngine(state: Fixtures.newState(seed: 99),
                                      systems: GamePipeline.standard(), catalog: catalog)
        engine.advance(ticks: Fixtures.ticksPerYear)
        let data = try JSONSaveCodec().encode(engine.state)
        let resumed = SimulationEngine(state: try JSONSaveCodec().decode(data),
                                       systems: GamePipeline.standard(), catalog: catalog)
        resumed.advance(ticks: Fixtures.ticksPerYear)
        engine.advance(ticks: Fixtures.ticksPerYear)
        #expect(try resumed.state.stateHash() == engine.state.stateHash())
    }
}
