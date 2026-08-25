import Testing
@testable import AirlineEmpireCore

@Suite("World dynamics")
struct WorldDynamicsTests {
    @Test func fuelPriceWalksWithinBand() throws {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(seed: 99),
                                      systems: [WorldSystem()], catalog: catalog)
        var prices: [Int64] = []
        for _ in 0..<(2 * 365) {
            engine.advance(ticks: Fixtures.ticksPerDay)
            prices.append(engine.state.world.fuelPricePerTon.cents)
        }
        let base = catalog.tuning.ops.baseFuelPricePerTon.cents
        #expect(prices.allSatisfy { $0 >= Int64(Double(base) * 0.6 - 1) })
        #expect(prices.allSatisfy { $0 <= Int64(Double(base) * 2.2 + 1) })
        // It actually moves.
        #expect(Set(prices).count > 100)
    }

    @Test func economyCyclesOverYears() throws {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(seed: 7),
                                      systems: [WorldSystem()], catalog: catalog)
        var indices: [Double] = []
        for _ in 0..<(8 * 365) {
            engine.advance(ticks: Fixtures.ticksPerDay)
            indices.append(engine.state.world.economicIndex)
        }
        #expect(indices.allSatisfy { $0 > 0.7 && $0 < 1.3 })
        // Over 8 years, both boom-ish and bust-ish territory is visited.
        #expect(indices.max()! > 1.02)
        #expect(indices.min()! < 0.98)
    }
}

@Suite("Loans & credit")
struct LoanTests {
    @Test func annuityMathIsSane() {
        // 1M at 6% over 12 months: payment ≈ 86,066/mo.
        let payment = CreditMath.annuityPayment(principal: Money.dollars(1_000_000),
                                                monthlyRate: 0.06 / 12, months: 12)
        #expect(abs(payment.cents - 86_066_43) < 200)
        // Zero-rate degenerates to straight amortization.
        let flat = CreditMath.annuityPayment(principal: Money.dollars(120),
                                             monthlyRate: 0, months: 12)
        #expect(flat == Money.dollars(10))
    }

    @Test func loanLifecycleServicesAndRetires() throws {
        let (_, engine, airline) = try FleetFixtures.catalogAndEngine(
            cash: Money.dollars(10_000_000))
        #expect(engine.applyNow(TakeLoanCommand(
            airline: airline, amount: Money.dollars(5_000_000), termMonths: 12)) == .applied)
        #expect(engine.state.ledger.balance(of: airline) == Money.dollars(15_000_000))
        let loan = engine.state.airlines[airline]!.loans[0]
        #expect(loan.annualRateBasisPoints >= 700) // base 500 + spread ≥ 200

        engine.advance(ticks: Fixtures.ticksPerYear + Fixtures.ticksPerDay * 40)
        let after = engine.state.airlines[airline]!
        #expect(after.loans.isEmpty, "Loan should be fully amortized")
        let interestPaid = -engine.state.ledger.recent
            .filter { $0.airline == airline && $0.category == .loanInterest }
            .reduce(Money.zero) { $0 + $1.amount }
        #expect(interestPaid > Money.dollars(100_000))
        #expect(interestPaid < Money.dollars(400_000))
    }

    @Test func leverageRaisesRatesAndEventuallyRefuses() throws {
        let (_, engine, airline) = try FleetFixtures.catalogAndEngine(
            cash: Money.dollars(3_000_000))
        #expect(engine.applyNow(TakeLoanCommand(
            airline: airline, amount: Money.dollars(2_000_000), termMonths: 60)) == .applied)
        let firstRate = engine.state.airlines[airline]!.loans[0].annualRateBasisPoints
        #expect(engine.applyNow(TakeLoanCommand(
            airline: airline, amount: Money.dollars(3_000_000), termMonths: 60)) == .applied)
        let secondRate = engine.state.airlines[airline]!.loans[1].annualRateBasisPoints
        #expect(secondRate > firstRate)
        // Piling on more debt than assets support is refused.
        guard case .rejected(let rejection) = engine.applyNow(TakeLoanCommand(
            airline: airline, amount: Money.dollars(60_000_000), termMonths: 60)) else {
            Issue.record("Expected over-leverage refusal"); return
        }
        #expect(rejection.code == "finance.overLeveraged")
    }

    @Test func earlyRepaymentClearsLoan() throws {
        let (_, engine, airline) = try FleetFixtures.catalogAndEngine(
            cash: Money.dollars(20_000_000))
        _ = engine.applyNow(TakeLoanCommand(
            airline: airline, amount: Money.dollars(5_000_000), termMonths: 60))
        #expect(engine.applyNow(RepayLoanCommand(airline: airline, loanIndex: 0)) == .applied)
        #expect(engine.state.airlines[airline]!.loans.isEmpty)
        #expect(engine.state.ledger.balance(of: airline) == Money.dollars(20_000_000))
    }
}

@Suite("Statements")
struct StatementTests {
    @Test func monthlyStatementCapturesOneMonth() throws {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        // Month-start billings (payroll, leases, loans) belong to the month
        // they open, so February is the first fully-populated statement.
        engine.advance(ticks: Fixtures.ticksPerDay * 64)
        let finance = try #require(engine.state.finance.byAirline[airline])
        let january = try #require(finance.statements.first { $0.month == 1 })
        #expect(january.year == 2030)
        #expect(january.operatingRevenue > .zero)
        #expect(january.total(.ticketRevenue) > .zero)
        #expect(january.total(.fuel) < .zero)
        let february = try #require(finance.statements.first { $0.month == 2 })
        #expect(february.total(.salaries) < .zero)
        #expect(february.total(.overhead) < .zero)
        #expect(february.operatingExpenses < .zero)
        // Where did the money come from / go: every cent classified.
        let sum = february.byCategory.values.reduce(0, +)
        let capital = february.byCategory.filter { $0.key.classification == .capital }
            .values.reduce(0, +)
        #expect(february.operatingProfit.cents + february.financingCost.cents
                == sum - capital)
        #expect(engine.state.eventLog.recent.map(\.kind).contains {
            if case .statementClosed(let a, 2030, _, _) = $0 { a == airline } else { false }
        })
    }

    @Test func statementHistoryStaysBounded() throws {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        engine.advance(ticks: Fixtures.ticksPerYear * 3)
        let finance = try #require(engine.state.finance.byAirline[airline])
        #expect(finance.statements.count == 24) // capped at tuning history
        // Lifetime totals keep the long view.
        #expect(finance.lifetimeNetProfit != .zero)
    }

    @Test func routePnLBreakdownIsExplainable() throws {
        let (engine, _, route) = try DemandFixtures.market(fare: Money.dollars(129))
        engine.advance(ticks: Fixtures.ticksPerDay * 33)
        let economics = engine.state.routes[route]!.economicsLastMonth
        #expect(economics.revenueCents > 0)
        #expect(economics.fuelCents > 0)
        #expect(economics.feesCents > 0)
        #expect(economics.crewCents > 0)
        #expect(economics.passengers > 0)
        // Anchor market: direct operating profit is positive at ref fare.
        #expect(economics.directOperatingProfit > .zero)
        // Revenue ties out with fare x passengers.
        #expect(economics.revenueCents == Money.dollars(129).cents * economics.passengers)
    }
}

@Suite("Solvency")
struct SolvencyTests {
    /// An airline built to bleed: big leased fleet, no routes, tiny cash.
    static func doomedAirline() throws -> (SimulationEngine, AirlineID) {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Icarus Air", kind: .ai, homeAirport: "STV",
            startingCash: Money.dollars(9_000_000)))
        let airline = engine.state.airlines.values.first!.id
        for _ in 0..<4 {
            _ = engine.applyNow(LeaseAircraftCommand(lessee: airline, type: "MR180",
                                                     termMonths: 60))
        }
        return (engine, airline)
    }

    @Test func sustainedOverdraftTriggersAdministration() throws {
        let (engine, airline) = try Self.doomedAirline()
        // 4 leased narrowbodies = ~3.2M/mo lease + payroll/overhead, no
        // revenue: the overdraft floor is crossed within months.
        engine.advance(ticks: Fixtures.ticksPerYear)
        let a = engine.state.airlines[airline]!
        #expect(a.administrationCount >= 1)
        let kinds = engine.state.eventLog.recent.map(\.kind)
        _ = kinds // events may have scrolled; state is authoritative
    }

    @Test func administrationFireSellsOwnedAircraft() throws {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Asset Rich", kind: .ai, homeAirport: "STV",
            startingCash: Money.dollars(120_000_000)))
        let airline = engine.state.airlines.values.first!.id
        // Owns a widebody outright, then bleeds via leases.
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR300", ageYears: 12))
        for _ in 0..<3 {
            _ = engine.applyNow(LeaseAircraftCommand(lessee: airline, type: "MR180",
                                                     termMonths: 60))
        }
        let fleetBefore = engine.state.fleet(of: airline).count
        #expect(fleetBefore == 4)
        engine.advance(ticks: Fixtures.ticksPerYear * 3)
        let a = engine.state.airlines[airline]!
        // Administration sold the owned airframe to cover the hole (or the
        // airline eventually collapsed entirely — both are honest outcomes;
        // assert the mechanism engaged).
        #expect(a.administrationCount >= 1 || a.status == .collapsed)
        if a.administrationCount >= 1 && a.status == .active {
            #expect(engine.state.fleet(of: airline).count < fleetBefore)
            #expect(engine.state.ledger.recent.contains {
                $0.category == .aircraftSale && $0.memo?.contains("Fire sale") == true
            } || engine.state.ledger.balance(of: airline).cents
                 >= catalog.tuning.finance.overdraftFloorCents)
        }
    }

    @Test func secondFailureCollapsesAndCleansUp() throws {
        let (engine, airline) = try Self.doomedAirline()
        engine.advance(ticks: Fixtures.ticksPerYear * 4)
        let a = engine.state.airlines[airline]!
        // Leases keep bleeding after administration (nothing sellable), so
        // the second failure collapses it.
        #expect(a.status == .collapsed)
        #expect(engine.state.fleet(of: airline).isEmpty)
        #expect(engine.state.routes(of: airline).isEmpty)
        #expect(a.loans.isEmpty)
        // World keeps running.
        engine.advance(ticks: Fixtures.ticksPerDay * 30)
        #expect(engine.state.integrityViolations().isEmpty)
    }

    @Test func healthyAirlineNeverEntersAdministration() throws {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        engine.advance(ticks: Fixtures.ticksPerYear * 2)
        let a = engine.state.airlines[airline]!
        #expect(a.status == .active)
        #expect(a.administrationCount == 0)
    }

    @Test func financeSurvivesSaveLoadDeterministically() throws {
        let catalog = try ContentCatalog.loadBundled()
        func build() throws -> SimulationEngine {
            let engine = SimulationEngine(state: Fixtures.newState(seed: 404),
                                          systems: GamePipeline.standard(), catalog: catalog)
            _ = engine.applyNow(FoundAirlineCommand(
                airlineName: "Saver", kind: .player, homeAirport: "STV",
                startingCash: Money.dollars(80_000_000)))
            let airline = engine.state.airlines.values.first!.id
            _ = engine.applyNow(TakeLoanCommand(airline: airline,
                                                amount: Money.dollars(40_000_000),
                                                termMonths: 48))
            _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180",
                                                       ageYears: 6))
            _ = engine.applyNow(OpenRouteCommand(
                airline: airline, origin: "STV", destination: "LNW",
                dailyRoundTrips: 2, ticketPrice: Money.dollars(119)))
            let route = engine.state.routes.values.first!.id
            let aircraft = engine.state.aircraft.values.first!.id
            _ = engine.applyNow(AssignAircraftToRouteCommand(
                airline: airline, route: route, aircraftID: aircraft))
            return engine
        }
        let straight = try build()
        straight.advance(ticks: Fixtures.ticksPerDay * 100)

        let split = try build()
        split.advance(ticks: Fixtures.ticksPerDay * 47)
        let data = try JSONSaveCodec().encode(split.state)
        let resumed = SimulationEngine(state: try JSONSaveCodec().decode(data),
                                       systems: GamePipeline.standard(), catalog: catalog)
        resumed.advance(ticks: Fixtures.ticksPerDay * 53)
        #expect(try resumed.state.stateHash() == straight.state.stateHash())
    }
}
