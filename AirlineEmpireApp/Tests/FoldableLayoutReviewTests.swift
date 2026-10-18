import XCTest
import SwiftUI
import UIKit
import AirlineEmpireCore
@testable import AirlineEmpire

/// iPhone Duo layout evidence (docs/IPHONE_DUO.md). The Duo hands an iPhone
/// app windows no other iPhone does: a short 5.4" outer display and a
/// near-square 7.6" inner one that can report regular width. These host the
/// shell and two dense screens at each of those window shapes, so a layout
/// that only ever assumed a tall phone or a wide iPad fails here, on any
/// runner, without needing the Duo simulator.
///
/// Labelled component viewports, like `AccessibilitySurfaceReviewTests`:
/// not device screenshots, and not proof of a fold transition.
final class FoldableLayoutReviewTests: XCTestCase {
    /// Window shapes in points. Outer 1398×2034 px and inner 1878×2670 px,
    /// both at 3x (apple.com/iphone-duo/specs). The size class of the inner
    /// display is rendered both ways: screens branch on it, and both
    /// branches must hold at this shape. (The shell itself keeps its tab bar
    /// on any iPhone so a fold never rebuilds the tabs — `GameShell`.)
    private struct Canvas {
        let name: String
        let size: CGSize
        let sizeClass: UserInterfaceSizeClass
    }

    private let canvases = [
        Canvas(name: "outer", size: CGSize(width: 466, height: 678), sizeClass: .compact),
        Canvas(name: "inner-compact", size: CGSize(width: 626, height: 890), sizeClass: .compact),
        Canvas(name: "inner-regular", size: CGSize(width: 626, height: 890), sizeClass: .regular),
        Canvas(name: "inner-wide", size: CGSize(width: 890, height: 626), sizeClass: .regular),
    ]

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
    private func capture<V: View>(_ view: V, name: String, canvas: Canvas,
                                  controller: GameController) async throws {
        let content = view
            .environment(controller)
            .environment(Entitlements(arguments: ["-AEUITestFree"]))
            .environment(GameCenter(arguments: ["-AEUITestFree"]))
            .environment(\.horizontalSizeClass, canvas.sizeClass)
        let host = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(origin: .zero, size: canvas.size))
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(host.view.bounds.size, canvas.size, "\(name) must lay out at the \(canvas.name) window size")
        let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds)
        var drawn = false
        let image = renderer.image { _ in
            drawn = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(drawn, "\(name) must render on the \(canvas.name) canvas")
        let attachment = XCTAttachment(image: image)
        attachment.name = "DUO-\(canvas.name)-\(name)-\(Int(canvas.size.width))x\(Int(canvas.size.height))"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
        window.rootViewController = nil
    }

    @MainActor
    func testShellAndDenseScreensAtEveryDuoWindowShape() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = GameController(savesDirectory: root)
        controller.startNewGame(airlineName: "Duo review", home: "ARN", seed: 42, scenario: "founder")
        try await waitForGame(controller)
        defer { controller.setPumping(false) }
        for canvas in canvases {
            try await capture(GameShell(), name: "shell", canvas: canvas, controller: controller)
            try await capture(FinanceView(), name: "finance", canvas: canvas, controller: controller)
            try await capture(NavigationStack { SettingsView() }, name: "settings", canvas: canvas, controller: controller)
        }
    }

    /// The hub's chrome is chosen from the window's shape alone. Pin what
    /// each Duo window gets, so a threshold change cannot quietly hand the
    /// near-square inner display a layout built for a phone on its side.
    func testHubChromeModeForDuoWindows() {
        XCTAssertEqual(HubChromeMode(size: CGSize(width: 466, height: 678)), .portrait, "outer, upright")
        XCTAssertEqual(HubChromeMode(size: CGSize(width: 678, height: 466)), .landscape, "outer, on its side")
        XCTAssertEqual(HubChromeMode(size: CGSize(width: 626, height: 890)), .portrait, "inner, upright")
        // Wide enough for the iPad layout, too short for it: slim chrome.
        XCTAssertEqual(HubChromeMode(size: CGSize(width: 890, height: 626)), .landscape, "inner, on its side")
        // The layouts it must not disturb.
        XCTAssertEqual(HubChromeMode(size: CGSize(width: 852, height: 393)), .landscape, "iPhone on its side")
        XCTAssertEqual(HubChromeMode(size: CGSize(width: 1133, height: 744)), .regular, "iPad mini on its side")
        XCTAssertEqual(HubChromeMode(size: CGSize(width: 834, height: 1194)), .regular, "iPad 11-inch upright")
    }
}
