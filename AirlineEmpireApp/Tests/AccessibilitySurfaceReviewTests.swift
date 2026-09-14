import XCTest
import SwiftUI
import UIKit
import AirlineEmpireCore
@testable import AirlineEmpire

/// Native hosted layout evidence. These are labelled component viewports,
/// not device screenshots or proof that an OS accessibility setting was toggled.
final class AccessibilitySurfaceReviewTests: XCTestCase {
    @MainActor
    private func waitForGame(_ controller: GameController) async throws {
        for _ in 0..<500 {
            if controller.snapshot?.playerAirline != nil {
                controller.setPumping(false)
                controller.setSpeed(.paused)
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Review campaign did not load")
    }

    @MainActor
    private func capture<V: View>(_ view: V, name: String, controller: GameController,
                                  width: CGFloat, dark: Bool) async throws {
        let content = view
            .environment(controller)
            .environment(Entitlements(arguments: ["-AEUITestFree"]))
            .environment(\.dynamicTypeSize, .accessibility3)
            .environment(\.legibilityWeight, .bold)
            .environment(\.colorSchemeContrast, .increased)
            .environment(\.accessibilityReduceMotion, true)
            .environment(\.accessibilityReduceTransparency, true)
            .environment(\.colorScheme, dark ? .dark : .light)
            .preferredColorScheme(dark ? .dark : .light)
        let host = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 812))
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds)
        var drawn = false
        let image = renderer.image { _ in
            drawn = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(drawn, "Native view hierarchy must render before capture")
        let attachment = XCTAttachment(image: image)
        attachment.name = "AX-COMPONENT-\(name)-\(Int(width))pt-\(dark ? "dark" : "light")"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
        window.rootViewController = nil
    }

    @MainActor
    func testFreshSecondaryLayoutsWithAccessibilityEnvironment() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = GameController(savesDirectory: root)
        controller.startNewGame(airlineName: "Fresh review", home: "ARN", seed: 42, scenario: "founder")
        try await waitForGame(controller)
        defer { controller.setPumping(false) }
        for dark in [false, true] {
            for width in [CGFloat(375), CGFloat(507)] {
                try await capture(FinanceView(), name: "finance", controller: controller, width: width, dark: dark)
                try await capture(LoanSheet(), name: "borrow", controller: controller, width: width, dark: dark)
                try await capture(NavigationStack { SettingsView() }, name: "settings", controller: controller, width: width, dark: dark)
                try await capture(NavigationStack { WorldEventsView() }, name: "world-events", controller: controller, width: width, dark: dark)
                try await capture(NavigationStack { ReputationDetailView() }, name: "reputation", controller: controller, width: width, dark: dark)
            }
        }
    }

    @MainActor
    func testEarnedCollapseAndRecoveryWithReducedMotion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try ContentCatalog.loadBundled()
        // A deliberately underfunded test scenario. The actual lease charges,
        // insolvency, administration and collapse all come from the engine.
        let engine = SimulationEngine(state: ScenarioBootstrap.newGame(
            scenario: "founder", worldSeed: 42, startYear: 2030),
            systems: GamePipeline.standard(), catalog: catalog)
        XCTAssertEqual(engine.applyNow(FoundAirlineCommand(airlineName: "Overextended",
            kind: .player, homeAirport: "ARN", startingCash: .dollars(3_000_000))), .applied)
        let player = try XCTUnwrap(engine.state.playerAirline?.id)
        for _ in 0..<3 {
            XCTAssertEqual(engine.applyNow(LeaseAircraftCommand(lessee: player,
                type: "MR180", termMonths: 60)), .applied)
        }
        engine.advance(ticks: 96 * 365 * 3)
        XCTAssertTrue(engine.state.progression.gameOver, "The simulation must actually collapse the airline")
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        try manager.save(engine.state, slot: "collapse-review")
        let controller = GameController(savesDirectory: root)
        controller.loadGame(slot: "collapse-review")
        try await waitForGame(controller)
        XCTAssertTrue(controller.snapshot?.progression.gameOver == true)
        try await capture(GameOverView(), name: "earned-collapse", controller: controller, width: 375, dark: true)
        controller.quitToMenu()
        XCTAssertFalse(controller.hasGame)
        XCTAssertEqual(controller.availableSlots().count, 1, "Returning to the menu must retain the old campaign")
        try await capture(NewGameView(), name: "recovery-menu", controller: controller, width: 375, dark: true)
    }
}
