import Testing
@testable import AirlineEmpireCore

/// The Finance breakdown must separate operating, financing and capital cash
/// movements, and quote recurring commitments from the contracts the
/// simulation will actually bill.
@Suite("Finance breakdown")
struct FinanceBreakdownTests {
    private func airlineFixture() throws -> (SimulationEngine, AirlineID, ContentCatalog) {
        let catalog = try DemandFixtures.anchorCatalog()
        let engine = SimulationEngine(state: Fixtures.newState(),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(airlineName: "Ledger Air", kind: .player,
                                                homeAirport: "MET",
                                                startingCash: Money.dollars(300_000_000)))
        let airline = engine.state.airlines.values.first!.id
        return (engine, airline, catalog)
    }

    @Test func monthTotalsReadWithoutDraining() throws {
        let (engine, airline, _) = try airlineFixture()
        var state = engine.state
        _ = state.ledger.drainMonthAccumulator(for: airline)
        state.ledger.post(airline: airline, category: .ticketRevenue,
                          amount: .dollars(1_000), at: state.clock.now)
        let first = state.ledger.monthTotals(for: airline)
        let second = state.ledger.monthTotals(for: airline)
        #expect(first == second)
        #expect(first[.ticketRevenue] == Money.dollars(1_000).cents)
        let drained = state.ledger.drainMonthAccumulator(for: airline)
        #expect(drained[.ticketRevenue] == Money.dollars(1_000).cents)
        #expect(state.ledger.monthTotals(for: airline).isEmpty)
    }

    @Test func monthFlowSplitsByClassification() throws {
        let (engine, airline, _) = try airlineFixture()
        var state = engine.state
        // Start from a clean month, so the founding capital does not swamp
        // the capital line.
        _ = state.ledger.drainMonthAccumulator(for: airline)
        state.ledger.post(airline: airline, category: .ticketRevenue,
                          amount: .dollars(1_000), at: state.clock.now)
        state.ledger.post(airline: airline, category: .fuel,
                          amount: .dollars(-300), at: state.clock.now)
        state.ledger.post(airline: airline, category: .loanInterest,
                          amount: .dollars(-50), at: state.clock.now)
        state.ledger.post(airline: airline, category: .aircraftPurchase,
                          amount: .dollars(-5_000), at: state.clock.now)

        let flow = try #require(MonthFlow.make(state.ledger.monthTotals(for: airline)))
        #expect(flow.operatingRevenue == Money.dollars(1_000))
        #expect(flow.operatingExpenses == Money.dollars(-300))
        #expect(flow.operatingProfit == Money.dollars(700))
        #expect(flow.financingCost == Money.dollars(-50))
        #expect(flow.capitalMovements == Money.dollars(-5_000))
        #expect(flow.netCashChange == Money.dollars(-4_350))
        // Cash change and operating profit are different claims.
        #expect(flow.netCashChange != flow.operatingProfit)
    }

    @Test func emptyMonthHasNoFlow() throws {
        let (engine, airline, catalog) = try airlineFixture()
        var state = engine.state
        _ = state.ledger.drainMonthAccumulator(for: airline)
        let breakdown = state.financeBreakdown(for: airline, catalog: catalog)
        #expect(breakdown.monthToDate == nil)
        #expect(breakdown.latestStatement == nil)
        #expect(breakdown.hasNothingToShow)
    }

    @Test func recurringCommitmentsMatchTheContracts() throws {
        let (engine, airline, catalog) = try airlineFixture()
        _ = engine.applyNow(LeaseAircraftCommand(lessee: airline, type: "MR180",
                                                 termMonths: 60))
        _ = engine.applyNow(OpenRouteCommand(airline: airline, origin: "MET",
                                             destination: "COS", dailyRoundTrips: 2,
                                             ticketPrice: Money.dollars(129)))
        #expect(engine.applyNow(TakeLoanCommand(airline: airline,
                                                amount: Money.dollars(10_000_000),
                                                termMonths: 48)) == .applied)
        _ = engine.applyNow(ConfigureAirportFacilitiesCommand(
            airline: airline, airport: "MET", facilities: .init(lounge: 1)))

        let tuning = catalog.tuning.finance
        let airport = catalog.tuning.airportServices
        let spec = try #require(catalog.aircraftType("MR180"))
        let loan = try #require(engine.state.airlines[airline]?.loans.first)
        let recurring = engine.state.financeBreakdown(for: airline, catalog: catalog).recurring

        #expect(recurring.leases == spec.leaseMonthly)
        #expect(recurring.loanPayments == loan.monthlyPayment)
        #expect(recurring.stations == airport.loungeMonthly)
        #expect(recurring.stationsByAirport["MET"] == airport.loungeMonthly)
        #expect(recurring.payroll == tuning.payrollPerAircraftMonthly
            + tuning.payrollPerRouteMonthly)
        #expect(recurring.overhead == tuning.overheadBaseMonthly)
        #expect(recurring.monthlyTotal == recurring.leases + recurring.loanPayments
            + recurring.stations + recurring.payroll + recurring.overhead)
    }

    @Test func breakdownIsDeterministicAndDoesNotMutate() throws {
        let (engine, airline, catalog) = try airlineFixture()
        let before = try engine.state.stateHash()
        let first = engine.state.financeBreakdown(for: airline, catalog: catalog)
        let second = engine.state.financeBreakdown(for: airline, catalog: catalog)
        #expect(first == second)
        #expect(try engine.state.stateHash() == before)
    }

    @Test func latestStatementCrossesTheMonthBoundary() throws {
        let (engine, airline, catalog) = try airlineFixture()
        _ = engine.applyNow(LeaseAircraftCommand(lessee: airline, type: "MR180",
                                                 termMonths: 60))
        _ = engine.applyNow(OpenRouteCommand(airline: airline, origin: "MET",
                                             destination: "COS", dailyRoundTrips: 2,
                                             ticketPrice: Money.dollars(129)))
        let aircraft = engine.state.fleet(of: airline).map(\.id).sorted().first!
        let route = engine.state.routes.values.first!.id
        _ = engine.applyNow(AssignAircraftToRouteCommand(
            airline: airline, route: route, aircraftID: aircraft))
        engine.advance(ticks: Fixtures.ticksPerDay * 35)

        let breakdown = engine.state.financeBreakdown(for: airline, catalog: catalog)
        let latest = try #require(breakdown.latestStatement)
        #expect(latest == engine.state.finance.byAirline[airline]?.latest)
        // A closed month's categories are its statement; this month's are the
        // live accumulator.
        #expect(!latest.byCategory.isEmpty)
        #expect(breakdown.recurring.monthlyTotal > .zero)
    }
}
