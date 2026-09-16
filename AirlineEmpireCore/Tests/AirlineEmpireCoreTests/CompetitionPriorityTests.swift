import Testing
@testable import AirlineEmpireCore

/// Rival news is prioritised for a screen: a move on the player's own pair
/// outranks a move at an airport they serve, whatever the dates. The ordering
/// lives in Core so the Competitors screen and any other reader agree.
@Suite("Rival move priority")
struct CompetitionPriorityTests {
    /// A player already flying ARN–CDG, with two rivals founded but idle, and
    /// two days on the clock so staged moves can be both recent and after the
    /// player's own entry.
    private func world() throws -> (SimulationEngine, AirlineID, AirlineID, ContentCatalog) {
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
        engine.advance(ticks: Fixtures.ticksPerDay * 2)
        return (engine, aurora, swift, catalog)
    }

    @Test func aMoveOnYourMarketLeadsANewerMoveAtYourAirport() throws {
        let (engine, aurora, swift, catalog) = try world()
        var state = engine.state
        let now = state.clock.now
        // SwiftJet moved on the player's own pair a day ago.
        let onMarket = now + .days(-1)
        state.world.recordMarketMove(MarketMove(at: onMarket, airline: swift,
                                                origin: "ARN", destination: "CDG",
                                                kind: .entered))
        // Aurora moved at an airport the player serves this morning.
        let atAirport = now + .hours(-6)
        state.world.recordMarketMove(MarketMove(at: atAirport, airline: aurora,
                                                origin: "ARN", destination: "LHR",
                                                kind: .entered))

        let summary = try #require(state.competitionSummary(catalog: catalog))
        let marketMove = try #require(summary.recentMoves.first { $0.at == onMarket })
        let airportMove = try #require(summary.recentMoves.first { $0.at == atAirport })
        #expect(marketMove.relevance == .onPlayerMarket)
        #expect(airportMove.relevance == .atPlayerAirport)
        let marketIndex = try #require(summary.recentMoves.firstIndex(of: marketMove))
        let airportIndex = try #require(summary.recentMoves.firstIndex(of: airportMove))
        #expect(marketIndex < airportIndex, "Priority beats recency")
    }

    @Test func movesOnTheSameRankStayNewestFirst() throws {
        let (engine, aurora, swift, catalog) = try world()
        var state = engine.state
        let now = state.clock.now
        let older = now + .hours(-36)
        let newer = now + .hours(-12)
        state.world.recordMarketMove(MarketMove(at: older, airline: swift,
                                                origin: "ARN", destination: "CDG",
                                                kind: .left))
        state.world.recordMarketMove(MarketMove(at: newer, airline: aurora,
                                                origin: "ARN", destination: "CDG",
                                                kind: .entered))
        let summary = try #require(state.competitionSummary(catalog: catalog))
        let newerMove = try #require(summary.recentMoves.first { $0.at == newer })
        let olderMove = try #require(summary.recentMoves.first { $0.at == older })
        #expect(newerMove.relevance == .onPlayerMarket)
        #expect(olderMove.relevance == .onPlayerMarket)
        let newerIndex = try #require(summary.recentMoves.firstIndex(of: newerMove))
        let olderIndex = try #require(summary.recentMoves.firstIndex(of: olderMove))
        #expect(newerIndex < olderIndex)
    }

    /// A rival that enters and leaves in the same instant (two commands in one
    /// tick) must read as the exit: the head of the list is the move recorded
    /// last. Sorting only by time left this to the array's order, and an entry
    /// followed by an exit came out as "they arrived" (run 35136273799).
    @Test func movesInTheSameInstantListTheLaterRecordedFirst() throws {
        let (engine, _, swift, catalog) = try world()
        var state = engine.state
        let now = state.clock.now
        state.world.recordMarketMove(MarketMove(at: now, airline: swift,
                                                origin: "ARN", destination: "CDG",
                                                kind: .entered))
        state.world.recordMarketMove(MarketMove(at: now, airline: swift,
                                                origin: "ARN", destination: "CDG",
                                                kind: .left))
        let summary = try #require(state.competitionSummary(catalog: catalog))
        let sameInstant = summary.recentMoves.filter { $0.at == now && $0.airline == swift }
        #expect(sameInstant.count == 2)
        #expect(sameInstant.first?.kind == .left,
                "The move recorded last heads a same-instant pair")
        guard case .rivalLeftYourMarket = summary.headline else {
            Issue.record("expected an exit headline, got \(String(describing: summary.headline))")
            return
        }
    }
}
