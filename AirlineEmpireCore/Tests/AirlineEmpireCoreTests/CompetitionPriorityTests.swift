import Testing
@testable import AirlineEmpireCore

/// Rival news is prioritised for a screen: a move on the player's own pair
/// outranks a move at an airport they serve, whatever the dates. The ordering
/// lives in Core so the Competitors screen and any other reader agree.
@Suite("Rival move priority")
struct CompetitionPriorityTests {
    private func world() throws -> (SimulationEngine, AirlineID, AirlineID, AirlineID,
                                    ContentCatalog) {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(seed: 909),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(airlineName: "Press Air", kind: .player,
                                                homeAirport: "ARN",
                                                startingCash: Money.dollars(200_000_000)))
        _ = engine.applyNow(FoundAirlineCommand(airlineName: "Aurora Atlantic", kind: .ai,
                                                homeAirport: "LHR",
                                                startingCash: Money.dollars(50_000_000)))
        _ = engine.applyNow(FoundAirlineCommand(airlineName: "SwiftJet", kind: .ai,
                                                homeAirport: "CDG",
                                                startingCash: Money.dollars(50_000_000)))
        let player = try #require(engine.state.playerAirline?.id)
        let aurora = try #require(engine.state.airlines.values
            .first { $0.name == "Aurora Atlantic" }?.id)
        let swift = try #require(engine.state.airlines.values
            .first { $0.name == "SwiftJet" }?.id)
        _ = engine.applyNow(OpenRouteCommand(airline: player, origin: "ARN",
                                             destination: "CDG", dailyRoundTrips: 2,
                                             ticketPrice: Money.dollars(150)))
        return (engine, player, aurora, swift, catalog)
    }

    @Test func aMoveOnYourMarketLeadsAnOlderMoveAtYourAirport() throws {
        let (engine, _, aurora, swift, catalog) = try world()
        var state = engine.state
        let now = state.clock.now
        // Aurora moved at an airport the player serves, ten days ago.
        state.world.recordMarketMove(MarketMove(at: now + .days(-10), airline: aurora,
                                                origin: "ARN", destination: "LHR",
                                                kind: .entered))
        // SwiftJet moved on one of the player's own pairs, twenty days ago.
        state.world.recordMarketMove(MarketMove(at: now + .days(-20), airline: swift,
                                                origin: "ARN", destination: "CDG",
                                                kind: .entered))

        let summary = try #require(state.competitionSummary(catalog: catalog))
        #expect(summary.recentMoves.count == 2)
        let first = try #require(summary.recentMoves.first)
        #expect(first.airline == swift)
        #expect(first.relevance == .onPlayerMarket)
        #expect(first.daysAgo == 20, "Priority beats recency")
        #expect(summary.recentMoves.last?.relevance == .atPlayerAirport)
    }

    @Test func movesOnTheSameRankStayNewestFirst() throws {
        let (engine, _, aurora, swift, catalog) = try world()
        var state = engine.state
        let now = state.clock.now
        state.world.recordMarketMove(MarketMove(at: now + .days(-3), airline: aurora,
                                                origin: "ARN", destination: "CDG",
                                                kind: .entered))
        state.world.recordMarketMove(MarketMove(at: now + .days(-9), airline: swift,
                                                origin: "ARN", destination: "CDG",
                                                kind: .left))
        let summary = try #require(state.competitionSummary(catalog: catalog))
        #expect(summary.recentMoves.map(\.airline) == [aurora, swift])
        #expect(summary.recentMoves.allSatisfy { $0.relevance == .onPlayerMarket })
    }
}
