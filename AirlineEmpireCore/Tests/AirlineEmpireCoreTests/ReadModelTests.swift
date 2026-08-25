import Testing
@testable import AirlineEmpireCore

@Suite("UI read models")
struct ReadModelTests {
    @Test func dashboardReflectsWorld() throws {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        engine.advance(ticks: Fixtures.ticksPerDay * 40)
        let dashboard = try #require(engine.state.dashboardModel())
        #expect(dashboard.airlineName == "Anchor Air")
        #expect(dashboard.fleetCount == 1)
        #expect(dashboard.routeCount == 1)
        #expect(dashboard.destinationCount == 2)
        #expect(dashboard.cash == engine.state.ledger.balance(of: airline))
        #expect(dashboard.lastMonthNetProfit != nil)
        #expect(!dashboard.gameOver)
        // Net worth = assets - debt, and with no loans >= cash floor of 0.
        #expect(dashboard.netWorth > .zero)
    }

    @Test func routeCardExplainsItself() throws {
        let (engine, airline, route) = try DemandFixtures.market(fare: Money.dollars(129))
        engine.advance(ticks: Fixtures.ticksPerDay * 40)
        let cards = engine.state.routeCards(for: airline, catalog: engine.catalog)
        #expect(cards.count == 1)
        let card = cards[0]
        #expect(card.id == route)
        #expect(card.loadFactor > 0.3)
        #expect(abs(card.farePosition - 1.0) < 0.15) // ¤129 near reference
        // The breakdown ties out with the profit figure exactly.
        #expect(card.lastMonthProfit == card.lastMonthBreakdown.directOperatingProfit)
        #expect(card.lastMonthProfit > .zero)
    }

    @Test func fleetCardCarriesLiveDerivedState() throws {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        engine.advance(ticks: Fixtures.ticksPerDay * 30)
        let cards = engine.state.fleetCards(for: airline, catalog: engine.catalog)
        #expect(cards.count == 1)
        let card = cards[0]
        #expect(card.typeName == "Meridian MR-180")
        #expect(card.condition > 0 && card.condition <= 1)
        #expect(card.reliability > 0.85)
        #expect(card.totalFlightHours > 50)
        if case .owned(let book) = card.ownershipDescription {
            #expect(book > .zero)
        } else {
            Issue.record("Fixture buys used (owned)")
        }
    }

    @Test func financeModelMatchesLedgerAndStatements() throws {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        _ = engine.applyNow(TakeLoanCommand(airline: airline,
                                            amount: Money.dollars(20_000_000),
                                            termMonths: 36))
        engine.advance(ticks: Fixtures.ticksPerDay * 70)
        let model = try #require(engine.state.financeModel(for: airline))
        #expect(model.cash == engine.state.ledger.balance(of: airline))
        #expect(model.loans.count == 1)
        #expect(model.totalDebt > .zero)
        #expect(model.debtRatio > 0 && model.debtRatio < 1)
        #expect(model.monthlySeries.count >= 2)
        for point in model.monthlySeries {
            #expect(point.netProfit.cents <= point.revenue.cents)
            #expect(point.expenses <= .zero)
        }
    }
}
