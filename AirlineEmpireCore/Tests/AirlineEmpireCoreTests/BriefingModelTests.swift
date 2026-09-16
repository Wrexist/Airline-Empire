import Testing
@testable import AirlineEmpireCore

/// The briefing's decision hierarchy. The order is the product claim: what
/// may kill the airline first, then what is costing money now, then a route
/// merely losing a month. It must also read correctly on a fresh airline and
/// on a mature one.
@Suite("Briefing hierarchy")
struct BriefingModelTests {
    private func founded() throws -> (SimulationEngine, AirlineID, ContentCatalog) {
        let catalog = try DemandFixtures.anchorCatalog()
        let engine = SimulationEngine(state: Fixtures.newState(),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(airlineName: "Briefed Air", kind: .player,
                                                homeAirport: "MET",
                                                startingCash: Money.dollars(300_000_000)))
        let airline = engine.state.airlines.values.first!.id
        return (engine, airline, catalog)
    }

    @Test func noAirlineNoBriefing() throws {
        let catalog = try DemandFixtures.anchorCatalog()
        #expect(Fixtures.newState().briefingModel(catalog: catalog) == nil)
    }

    @Test func theFirstSessionArcLeadsWhileItRuns() throws {
        let (engine, airline, catalog) = try founded()
        var model = try #require(engine.state.briefingModel(catalog: catalog))
        #expect(model.firstSession == .acquireAircraft)
        #expect(!model.isFirstSessionComplete)
        #expect(model.alerts.isEmpty, "A new airline has nothing wrong with it yet")

        _ = engine.applyNow(LeaseAircraftCommand(lessee: airline, type: "MR180",
                                                 termMonths: 60))
        model = try #require(engine.state.briefingModel(catalog: catalog))
        #expect(model.firstSession == .openRoute)
    }

    @Test func idleAircraftOutranksALosingRoute() throws {
        let (engine, airline, route) = try DemandFixtures.market(fare: Money.dollars(129))
        let catalog = try DemandFixtures.anchorCatalog()
        // A second aircraft with nowhere to go.
        _ = engine.applyNow(LeaseAircraftCommand(lessee: airline, type: "MR180",
                                                 termMonths: 60))
        var state = engine.state
        // Make the flying route lose money this month.
        state.routes[route]?.economicsThisMonth.fuelCents = 100_000

        let model = try #require(state.briefingModel(catalog: catalog))
        let idle = try #require(model.alerts.first { if case .idleAircraft = $0.kind { true } else { false } })
        let losing = try #require(model.alerts.first { if case .losingRoutes = $0.kind { true } else { false } })
        #expect(idle.severity == .warning)
        #expect(losing.severity == .watch)
        // Warning sorts above watch: an idle aircraft bills, a losing month
        // is a trend.
        #expect(model.alerts.first?.kind == idle.kind)
    }

    @Test func insolvencyIsCriticalAndFirst() throws {
        let (engine, airline, catalog) = try founded()
        var state = engine.state
        let finance = catalog.tuning.finance
        let balance = state.ledger.balance(of: airline)
        state.ledger.post(airline: airline, category: .overhead,
                          amount: Money(cents: finance.overdraftFloorCents - balance.cents - 1),
                          at: state.clock.now)
        state.airlines[airline]?.daysInsolvent = finance.administrationGraceDays

        let model = try #require(state.briefingModel(catalog: catalog))
        let first = try #require(model.alerts.first)
        #expect(first.severity == .critical)
        guard case .insolvency(let days, let fatal) = first.kind else {
            Issue.record("expected the insolvency alert first, got \(first.kind)")
            return
        }
        #expect(days == 0)
        #expect(!fatal)
    }

    @Test func healthyAssignedFleetHasNothingToNagAbout() throws {
        let (engine, _, _) = try DemandFixtures.market(fare: Money.dollars(129))
        let catalog = try DemandFixtures.anchorCatalog()
        let model = try #require(engine.state.briefingModel(catalog: catalog))
        #expect(model.alerts.isEmpty)
    }

    @Test func performanceMatchesTheSummariesItComposes() throws {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        let catalog = try DemandFixtures.anchorCatalog()
        let state = engine.state
        let model = try #require(state.briefingModel(catalog: catalog))
        #expect(model.performance.dashboard.cash == state.ledger.balance(of: airline))
        #expect(model.performance.network.liveFlights
            == state.networkSummary(for: airline).liveFlights)
        #expect(model.performance.fleet.total == state.fleet(of: airline).count)
        #expect(model.performance.dashboard.fleetCount == state.fleet(of: airline).count)
    }

    @Test func briefingIsDeterministicAndDoesNotMutate() throws {
        let (engine, _, _) = try DemandFixtures.market(fare: Money.dollars(129))
        let catalog = try DemandFixtures.anchorCatalog()
        let before = try engine.state.stateHash()
        let first = engine.state.briefingModel(catalog: catalog)
        let second = engine.state.briefingModel(catalog: catalog)
        #expect(first == second)
        #expect(try engine.state.stateHash() == before)
    }
}
