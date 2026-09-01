import Foundation
import Testing
@testable import AirlineEmpireCore

/// The two saves the UI journeys open under `-AEUITestLoadSave`
/// (tasks/TECH_DEBT.md TD-028). They were written by `ae-rival-probe` from
/// the seed-2039 fight campaign; these tests pin what each one must say so
/// a regenerated fixture cannot silently photograph a different world.
@Suite("Rival pressure fixtures")
struct RivalPressureFixtureTests {
    private func load(_ name: String) throws -> GameState {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()   // AirlineEmpireCoreTests
            .deletingLastPathComponent()               // Tests
            .deletingLastPathComponent()               // AirlineEmpireCore
            .deletingLastPathComponent()               // repo
        let url = root.appendingPathComponent("AirlineEmpireApp/UITests/Fixtures/\(name).json")
        return try JSONSaveCodec().decode(try Data(contentsOf: url))
    }

    @Test("The day-249 save opens on the morning after a rival's retreat")
    func retreatFixture() throws {
        let state = try load("rival-pressure-retreat")
        let catalog = try ContentCatalog.loadBundled()
        let summary = try #require(state.competitionSummary(catalog: catalog))
        print("RETREAT-FIXTURE date \(state.currentDate) headline \(String(describing: summary.headline)) moves \(summary.recentMoves.count) contested \(summary.contestedRoutes)")
        guard case .rivalLeftYourMarket(let move) = summary.headline else {
            Issue.record("expected a retreat headline, got \(String(describing: summary.headline))")
            return
        }
        #expect(move.daysAgo <= 2)
        #expect(move.relevance == .onPlayerMarket)
    }

    @Test("The day-1825 save is a contested late game")
    func lateGameFixture() throws {
        let state = try load("rival-pressure-late-game")
        let catalog = try ContentCatalog.loadBundled()
        let summary = try #require(state.competitionSummary(catalog: catalog))
        print("LATE-FIXTURE date \(state.currentDate) headline \(String(describing: summary.headline)) rivals \(summary.rivals.count) contested \(summary.contestedRoutes)")
        #expect(summary.contestedRoutes >= 1)
        #expect(summary.rivals.filter { $0.status == .active }.count >= 3)
        #expect(summary.headline != nil)
    }
}
