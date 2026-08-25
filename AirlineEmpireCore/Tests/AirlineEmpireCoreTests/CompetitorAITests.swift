import Testing
@testable import AirlineEmpireCore

enum AIFixtures {
    /// Player + N competitors in the real world, all through commands.
    static func world(competitors: Int, seed: UInt64 = 42) throws
        -> (SimulationEngine, AirlineID) {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(seed: seed),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Player Air", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(150_000_000)))
        let player = engine.state.airlines.values.first!.id
        WorldSetup.createCompetitors(engine: engine, count: competitors,
                                     playerHome: "STV")
        return (engine, player)
    }
}

@Suite("Competitor AI")
struct CompetitorAITests {
    @Test func worldSetupFoundsDistinctCompetitors() throws {
        let (engine, player) = try AIFixtures.world(competitors: 5)
        let ais = engine.state.airlines.values.filter { $0.kind == .ai }
        #expect(ais.count == 5)
        #expect(Set(ais.map(\.name)).count == 5)
        #expect(Set(ais.map(\.homeAirport)).count == 5)
        #expect(ais.allSatisfy { $0.aiProfile != nil })
        #expect(ais.allSatisfy { $0.homeAirport != engine.state.airlines[player]!.homeAirport })
        // Each has its starter aircraft.
        for ai in ais {
            #expect(engine.state.fleet(of: ai.id).count == 1)
        }
    }

    @Test func aiOpensRoutesAndOperates() throws {
        let (engine, _) = try AIFixtures.world(competitors: 4)
        engine.advance(ticks: Fixtures.ticksPerDay * 60)
        let ais = engine.state.airlines.values.filter { $0.kind == .ai }
        var operating = 0
        for ai in ais {
            let routes = engine.state.routes(of: ai.id)
            if !routes.isEmpty { operating += 1 }
            for route in routes {
                #expect(route.ticketPrice > .zero)
            }
        }
        #expect(operating >= 3, "Most AIs should be flying within 60 days")
        // Revenue is actually flowing to AI airlines.
        let aiRevenue = engine.state.ledger.recent.contains {
            $0.category == .ticketRevenue
                && engine.state.airlines[$0.airline]?.kind == .ai
        }
        #expect(aiRevenue)
        #expect(engine.state.integrityViolations().isEmpty)
    }

    @Test func archetypesPriceDifferently() throws {
        let (engine, _) = try AIFixtures.world(competitors: 5)
        engine.advance(ticks: Fixtures.ticksPerDay * 90)
        var ratios: [AIArchetype: Double] = [:]
        for ai in engine.state.airlines.values where ai.kind == .ai {
            guard let profile = ai.aiProfile else { continue }
            let routes = engine.state.routes(of: ai.id)
            guard !routes.isEmpty else { continue }
            let avg = routes.map {
                $0.ticketPrice.asDouble / DemandSystem.referenceFare(
                    distanceKm: $0.distanceKm, tuning: engine.catalog.tuning.demand)
            }.reduce(0, +) / Double(routes.count)
            ratios[profile.archetype] = avg
        }
        if let lcc = ratios[.lowCost], let premium = ratios[.premium] {
            #expect(lcc < premium, "LCC \(lcc) should undercut premium \(premium)")
        }
    }

    @Test func aiRespondsToUndercutting() throws {
        // Player invades an AI market with a dumped fare; the AI must react
        // within a few decision cycles.
        let (engine, player) = try AIFixtures.world(competitors: 3)
        engine.advance(ticks: Fixtures.ticksPerDay * 45)
        guard let aiRoute = engine.state.routes.values.first(where: {
            engine.state.airlines[$0.airline]?.kind == .ai
        }) else {
            Issue.record("No AI route to attack"); return
        }
        let originalFare = aiRoute.ticketPrice
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: player, type: "MR180", ageYears: 5))
        let attacker = engine.state.aircraft.values.first {
            $0.owner == player && $0.assignedRoute == nil }!.id
        let dumped = Money(rounding: originalFare.asDouble * 0.6)
        let open = engine.applyNow(OpenRouteCommand(
            airline: player, origin: aiRoute.origin, destination: aiRoute.destination,
            dailyRoundTrips: 2, ticketPrice: dumped))
        guard open == .applied else { return } // slot-starved corner: skip
        let playerRoute = engine.state.routes.values.first {
            $0.airline == player
                && $0.sameMarket(origin: aiRoute.origin, destination: aiRoute.destination)
        }!.id
        _ = engine.applyNow(AssignAircraftToRouteCommand(
            airline: player, route: playerRoute, aircraftID: attacker))

        engine.advance(ticks: Fixtures.ticksPerDay * 21) // ≥ 2 decision cycles
        let after = engine.state.routes[aiRoute.id]
        // The AI either cut its fare or (conceivably) closed the route.
        if let after {
            #expect(after.ticketPrice < originalFare,
                    "AI held \(after.ticketPrice.cents) vs original \(originalFare.cents)")
        }
    }

    @Test func healthyAIGrowsItsFleet() throws {
        let (engine, _) = try AIFixtures.world(competitors: 3)
        engine.advance(ticks: Fixtures.ticksPerYear * 2)
        let ais = engine.state.airlines.values.filter { $0.kind == .ai && $0.status == .active }
        // At least one competitor should have expanded beyond its starter.
        let grew = ais.contains { engine.state.fleet(of: $0.id).count > 1 }
        #expect(grew, "No AI grew in two years")
        // And none exceeded the fleet cap.
        for ai in ais {
            #expect(engine.state.fleet(of: ai.id).count
                    <= engine.catalog.tuning.ai.maxFleetPerAirline)
        }
    }

    @Test func longSimulationStaysHealthy() throws {
        // 3 years, 5 AI airlines + player: no corruption, no runaway, no
        // pathological world states (Master Prompt 10 long-run check).
        let (engine, _) = try AIFixtures.world(competitors: 5, seed: 1234)
        for _ in 0..<36 {
            engine.advance(ticks: Fixtures.ticksPerDay * 30)
            #expect(engine.state.integrityViolations().isEmpty)
        }
        // Live flight population stays bounded.
        #expect(engine.state.flights.count < 2000)
        // Balances are finite and sane (no runaway money printer).
        for airline in engine.state.airlines.values {
            let balance = engine.state.ledger.balance(of: airline.id)
            #expect(balance.cents > -100_000_000_000) // > -1B
            #expect(balance.cents < 10_000_000_000_000) // < 100B
        }
        // The market did SOMETHING: routes exist, flights completed.
        let totalCompleted = engine.state.routes.values
            .reduce(Int64(0)) { $0 + $1.stats.flightsCompleted }
        #expect(totalCompleted > 1000)
    }

    @Test func aiWorldIsDeterministic() throws {
        func run() throws -> UInt64 {
            let (engine, _) = try AIFixtures.world(competitors: 4, seed: 777)
            engine.advance(ticks: Fixtures.ticksPerDay * 200)
            return try engine.state.stateHash()
        }
        #expect(try run() == run())
    }

    @Test func aiPlaysByPlayerRules() throws {
        // No AI may hold negative-priced tickets, phantom aircraft, or
        // routes without slots — the validators they share with the player
        // make these impossible; this asserts the outcome after a year.
        let (engine, _) = try AIFixtures.world(competitors: 5)
        engine.advance(ticks: Fixtures.ticksPerYear)
        for route in engine.state.routes.values {
            #expect(route.ticketPrice > .zero)
            let held = engine.state.world.slotsHeld(by: route.airline, at: route.origin)
            #expect(held >= Route.dailySlotMovements(roundTrips: route.dailyRoundTrips))
        }
        for aircraft in engine.state.aircraft.values {
            #expect(engine.state.airlines[aircraft.owner] != nil)
        }
    }

    @Test func playerProfileRejected() throws {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(),
                                      systems: [], catalog: catalog)
        guard case .rejected(let rejection) = engine.applyNow(FoundAirlineCommand(
            airlineName: "Cheater", kind: .player, homeAirport: "STV",
            startingCash: .zero, aiProfile: AIProfile(archetype: .lowCost))) else {
            Issue.record("Expected rejection"); return
        }
        #expect(rejection.code == "airline.playerWithProfile")
    }
}
