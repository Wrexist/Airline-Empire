import Foundation
import Testing
@testable import AirlineEmpireCore

/// The Game Center mapping. Everything here is a claim about identifiers
/// App Store Connect will hold forever, or about limits Apple enforces at
/// upload, so each one is a test rather than a comment.
@Suite("Game Center catalogue")
struct GameCenterCatalogTests {

    /// Achievement and leaderboard IDs are immutable in App Store Connect.
    /// Renaming one after release orphans every player's progress on it.
    @Test func identifiersAreStable() {
        let ids = GameCenterCatalog.achievements.map(\.id)
        #expect(ids.contains("com.airlineempire.game.achievement.firstFlight"))
        #expect(ids.contains("com.airlineempire.game.achievement.eraEmpire"))
        #expect(GameCenterCatalog.passengers.id == "com.airlineempire.game.leaderboard.passengers")
        #expect(GameCenterCatalog.destinations.id == "com.airlineempire.game.leaderboard.destinations")
        #expect(GameCenterCatalog.fleet.id == "com.airlineempire.game.leaderboard.fleet")
    }

    @Test func identifiersAreUniqueAndPrefixed() {
        let ids = GameCenterCatalog.achievements.map(\.id)
            + GameCenterCatalog.leaderboards.map(\.id)
        #expect(Set(ids).count == ids.count)
        for achievement in GameCenterCatalog.achievements {
            #expect(achievement.id.hasPrefix(GameCenterCatalog.achievementPrefix))
        }
        for board in GameCenterCatalog.leaderboards {
            #expect(board.id.hasPrefix(GameCenterCatalog.leaderboardPrefix))
        }
        // Apple's identifier limit.
        for id in ids { #expect(id.count <= 100, "\(id) too long") }
    }

    /// Apple rejects a game whose achievements total more than 1,000 points
    /// or where one is worth more than 100. Exactly 1,000 means nothing can
    /// be added later without deciding what it is worth against the rest.
    @Test func pointsSumToTheCeiling() {
        let total = GameCenterCatalog.achievements.map(\.points).reduce(0, +)
        #expect(total == GameCenterCatalog.maxTotalPoints)
        for achievement in GameCenterCatalog.achievements {
            #expect(achievement.points > 0)
            #expect(achievement.points <= GameCenterCatalog.maxPointsPerAchievement)
        }
    }

    @Test func everyLaterEraHasAnAchievement() {
        let eras = GameCenterCatalog.achievements.compactMap { achievement -> Era? in
            if case .era(let era) = achievement.source { return era }
            return nil
        }
        #expect(Set(eras) == Set(Era.allCases.filter { $0 != .startup }))
    }

    /// The drift detector. `ProgressionSystem` awards codes by string
    /// literal, so a milestone added there tomorrow would simply never reach
    /// Game Center and nothing would say so. This reads the source and
    /// requires every awarded code to be in the catalogue.
    @Test func everyAwardedCodeIsInTheCatalogue() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AirlineEmpireCore/Systems/ProgressionSystem.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"(reach|unlock)\("([A-Za-z0-9]+)""#)
        var awarded: [(kind: String, code: String)] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let kind = String(text[Range(match.range(at: 1), in: text)!])
            let code = String(text[Range(match.range(at: 2), in: text)!])
            awarded.append((kind, code))
        }
        try #require(awarded.count >= 10, "found only \(awarded.count) — has the source moved?")

        let sources = Set(GameCenterCatalog.achievements.map(\.source))
        for (kind, code) in awarded {
            let expected: GameCenterCatalog.Achievement.Source =
                kind == "reach" ? .milestone(code) : .achievement(code)
            #expect(sources.contains(expected),
                    "\(kind)(\"\(code)\") has no Game Center achievement")
        }
    }

    @Test func earnedFollowsProgression() {
        var progression = ProgressionState()
        #expect(GameCenterCatalog.earned(by: progression).isEmpty)

        progression.milestones = ["firstFlight", "fleet10"]
        progression.achievements = ["debtFree"]
        progression.era = .national
        let earned = Set(GameCenterCatalog.earned(by: progression).map(\.id))
        let p = GameCenterCatalog.achievementPrefix
        #expect(earned == [p + "firstFlight", p + "fleet10", p + "debtFree",
                           p + "eraRegional", p + "eraNational"])
    }

    @Test func fingerprintChangesWithWhatIsEarned() {
        var progression = ProgressionState()
        let before = GameCenterCatalog.fingerprint(of: progression)
        progression.milestones.append("firstFlight")
        #expect(GameCenterCatalog.fingerprint(of: progression) != before)
        let afterMilestone = GameCenterCatalog.fingerprint(of: progression)
        progression.era = .regional
        #expect(GameCenterCatalog.fingerprint(of: progression) != afterMilestone)
    }

    /// Scores count the world, not money, and a campaign with nothing in it
    /// scores zero rather than failing.
    @Test func scoresCountTheNetwork() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: 77),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Score Air", kind: .player, homeAirport: "ARN",
            startingCash: Money.dollars(500_000_000)))
        var state = await session.snapshot
        let player = try #require(state.playerAirline).id

        let empty = Dictionary(uniqueKeysWithValues:
            GameCenterCatalog.scores(for: player, in: state).map { ($0.0.id, $0.1) })
        #expect(empty[GameCenterCatalog.destinations.id] == 0)
        #expect(empty[GameCenterCatalog.passengers.id] == 0)

        let market = try #require(state.marketOpportunities(catalog: catalog, limit: 1).first)
        _ = await session.submit(OpenRouteCommand(
            airline: player, origin: market.origin, destination: market.destination,
            dailyRoundTrips: 2, ticketPrice: market.referenceFare))
        state = await session.snapshot
        let scored = Dictionary(uniqueKeysWithValues:
            GameCenterCatalog.scores(for: player, in: state).map { ($0.0.id, $0.1) })
        #expect(scored[GameCenterCatalog.destinations.id] == 2)
        #expect(scored[GameCenterCatalog.fleet.id]
                == state.fleet(of: player).filter { !$0.status.isOnOrder }.count)
    }
}
