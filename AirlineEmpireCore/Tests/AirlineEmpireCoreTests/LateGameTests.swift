import Testing
@testable import AirlineEmpireCore

/// Late-game and long-horizon validation (V3 prompt §19, §P). The existing
/// suites reach three to four game-years; a shipped save can run for
/// decades. These tests answer "what breaks if nobody stops playing?" —
/// unbounded growth, drifting state, dead or runaway worlds, aging fleets.
@Suite("Late game and long horizons")
struct LateGameTests {
    /// Player + rivals operating a real network, built through commands.
    private func decadeWorld(seed: UInt64, routes: Int)
        throws -> (SimulationEngine, AirlineID) {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(seed: seed),
                                      systems: GamePipeline.standard(),
                                      catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Long Haul", kind: .player, homeAirport: "ARN",
            startingCash: Money.dollars(400_000_000)))
        let player = engine.state.airlines.values.first!.id
        WorldSetup.createCompetitors(engine: engine, count: 3, playerHome: "ARN")

        let targets = engine.state.onboardingModel(catalog: catalog,
                                                   suggestionLimit: routes)?
            .suggestions ?? []
        for suggestion in targets {
            _ = engine.applyNow(BuyUsedAircraftCommand(buyer: player,
                                                       type: "MR180", ageYears: 4))
            guard let aircraft = engine.state.fleet(of: player)
                .last(where: { $0.assignedRoute == nil })?.id else { continue }
            _ = engine.applyNow(OpenRouteCommand(
                airline: player, origin: suggestion.origin,
                destination: suggestion.destination, dailyRoundTrips: 2,
                ticketPrice: suggestion.referenceFare))
            guard let route = engine.state.routes(of: player).last?.id else { continue }
            _ = engine.applyNow(AssignAircraftToRouteCommand(
                airline: player, route: route, aircraftID: aircraft))
        }
        return (engine, player)
    }

    /// A decade of continuous play must not grow the state without bound:
    /// every history in the game is deliberately capped, and a save that
    /// grows forever is a save that eventually stops loading.
    @Test func aDecadeOfPlayKeepsStateBounded() throws {
        let (engine, player) = try decadeWorld(seed: 4242, routes: 5)
        let codec = JSONSaveCodec()

        engine.advance(ticks: Fixtures.ticksPerYear)
        let earlySize = try codec.encode(engine.state).count
        let earlyFlights = engine.state.flights.count

        engine.advance(ticks: Fixtures.ticksPerYear * 9)   // ten years total
        let state = engine.state

        // Nothing is corrupt after a decade.
        #expect(state.integrityViolations().isEmpty)

        // Every bounded collection is still bounded.
        #expect(state.eventLog.recent.count <= BoundedEventLog.defaultCapacity)
        #expect(state.eventLog.totalCount > Int64(BoundedEventLog.defaultCapacity))
        #expect(state.ledger.recent.count <= Ledger.defaultRecentCapacity)
        for airlineID in state.orderedAirlineIDs {
            let statements = state.finance.byAirline[airlineID]?.statements ?? []
            #expect(statements.count <= 24, "statement history is unbounded")
        }

        // Live flights are a function of the network, not of elapsed time.
        #expect(state.flights.count < max(64, earlyFlights * 4))

        // The save cannot balloon: ten years must stay within a small
        // multiple of one year, since all history is capped.
        let lateSize = try codec.encode(state).count
        #expect(lateSize < earlySize * 3,
                "save grew from \(earlySize) to \(lateSize) bytes over nine years")

        // And it still round-trips.
        let restored = try codec.decode(codec.encode(state))
        #expect(try restored.stateHash() == state.stateHash())
        _ = player
    }

    /// The world must still be a game after a decade: somebody is flying,
    /// money is neither infinite nor uniformly zero.
    @Test func theWorldStaysAliveAndSaneForADecade() throws {
        let (engine, player) = try decadeWorld(seed: 99, routes: 6)
        engine.advance(ticks: Fixtures.ticksPerYear * 10)
        let state = engine.state

        let active = state.orderedAirlineIDs
            .compactMap { state.airlines[$0] }
            .filter { $0.status == .active }
        #expect(!active.isEmpty, "every airline in the world died")

        // Somebody is still operating routes and carrying passengers.
        let operating = state.orderedRouteIDs.compactMap { state.routes[$0] }
        #expect(!operating.isEmpty)
        #expect(operating.contains { $0.stats.passengersCarried > 0 })

        // No runaway: nobody has accumulated an absurd fortune. A decade of
        // compounding is fine; a money printer is not.
        for airline in active {
            let worth = CreditMath.assets(of: airline.id, state: state)
            #expect(worth < Money.dollars(500_000_000_000),
                    "\(airline.name) net worth ran away: \(worth.cents)")
        }

        // Reputation stays a probability for everyone, always.
        for airline in state.airlines.values {
            #expect(airline.reputation.score >= 0 && airline.reputation.score <= 1)
        }

        // The player's own read models still render after ten years.
        if state.airlines[player]?.status == .active {
            #expect(state.dashboardModel() != nil)
            #expect(state.financeModel(for: player) != nil)
        }
    }

    /// Fleets age for real: after a decade the metal is old, but condition,
    /// reliability, and value must stay inside their domains — no NaN, no
    /// negative book value, no immortal aircraft.
    @Test func agingFleetsStayWithinTheirDomains() throws {
        let (engine, player) = try decadeWorld(seed: 7, routes: 4)
        engine.advance(ticks: Fixtures.ticksPerYear * 10)
        let state = engine.state
        let catalog = engine.catalog

        var sawAged = false
        for aircraft in state.orderedAircraftIDs.compactMap({ state.aircraft[$0] }) {
            let spec = try #require(catalog.aircraftType(aircraft.typeCode))
            #expect(aircraft.ageYears > 0)
            #expect(aircraft.ageYears.isFinite)
            #expect(aircraft.condition > 0 && aircraft.condition <= 1)
            let reliability = aircraft.currentReliability(type: spec,
                                                          tuning: catalog.tuning.fleet)
            #expect(reliability > 0 && reliability <= 1)
            #expect(aircraft.totalFlightHours >= 0)
            if case .owned(let book) = aircraft.ownership {
                #expect(book >= .zero, "book value went negative with age")
            }
            if aircraft.ageYears > 10 { sawAged = true }
        }
        #expect(sawAged, "a decade passed but no aircraft aged past ten years")

        // Fleet cards still render for an aged fleet.
        if state.airlines[player]?.status == .active {
            for card in state.fleetCards(for: player, catalog: catalog) {
                #expect(card.condition > 0 && card.condition <= 1)
                #expect(card.reliability > 0 && card.reliability <= 1)
            }
        }
    }

    /// Long-horizon determinism: the flagship invariant has to survive a
    /// decade, not just a season.
    @Test func aDecadeIsDeterministic() throws {
        let (first, _) = try decadeWorld(seed: 20260826, routes: 4)
        let (second, _) = try decadeWorld(seed: 20260826, routes: 4)
        first.advance(ticks: Fixtures.ticksPerYear * 10)
        second.advance(ticks: Fixtures.ticksPerYear * 10)
        #expect(try first.state.stateHash() == second.state.stateHash())
    }

    /// Saving and resuming repeatedly over years must equal one unbroken
    /// run — the property a player exercises every single session.
    @Test func repeatedSaveResumeOverYearsEqualsAnUnbrokenRun() throws {
        let codec = JSONSaveCodec()
        let (straight, _) = try decadeWorld(seed: 3131, routes: 4)
        let (chunked, _) = try decadeWorld(seed: 3131, routes: 4)

        straight.advance(ticks: Fixtures.ticksPerYear * 5)

        // Same five years, but quit and reload at every year boundary.
        var current = chunked
        for _ in 0..<5 {
            current.advance(ticks: Fixtures.ticksPerYear)
            let reloaded = try codec.decode(codec.encode(current.state))
            current = SimulationEngine(state: reloaded,
                                       systems: GamePipeline.standard(),
                                       catalog: current.catalog)
        }
        #expect(try straight.state.stateHash() == current.state.stateHash())
    }
}
