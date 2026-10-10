import XCTest
import UIKit

/// Captures the 3D Hub View in each of the reference clip's shots
/// (docs/HUB_VIEW_3D.md §1) from an earned campaign, so the render can be
/// compared frame for frame with the reference. iPad in landscape (the
/// reference's aspect), iPhone in portrait.
final class HubViewUITests: AEUITestCase {
    override var wantsSunriseWeek: Bool { false }

    private func open(extra: [String] = []) throws {
        let bundle = Bundle(for: HubViewUITests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "store-campaign", withExtension: "json"))
        app.launchArguments.append(contentsOf: ["-AEUITestLoadSave", url.path, "-AEUITestProbes",
                                                "-AEUITestOpenHub"] + extra)
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        app.launch()
        app.activate()
        require(app.descendants(matching: .any)["ae-hub-scene"], "hub scene", timeout: 45)
        require(app.descendants(matching: .any)["ae-hub-timeline"], "turnaround timeline", timeout: 20)
        // Let geometry upload and the camera settle.
        Thread.sleep(forTimeInterval: 6)
    }

    /// The whole screen, in the orientation the player sees. `app.screenshot()`
    /// returns a landscape iPad cropped into a portrait buffer.
    private func frame(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = Self.logPrefix + name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func shot(_ name: String, _ id: String) {
        let button = app.buttons["ae-hub-shot-\(id)"]
        require(button, "shot button \(id)")
        button.tap()
        Thread.sleep(forTimeInterval: 4)
        frame(name)
    }

    func testHubShotsMatchTheReference() throws {
        try open()
        frame("HUB-01-overview")
        XCTAssertTrue(app.descendants(matching: .any)["ae-hub-kpis"].exists)
        shot("HUB-02-gate", "gate")
        shot("HUB-03-terminal", "terminal")
        shot("HUB-04-district", "district")
        let night = app.buttons["ae-hub-night"]
        require(night, "night toggle")
        night.tap()
        Thread.sleep(forTimeInterval: 3)
        frame("HUB-05-district-night")
        shot("HUB-06-overview-night", "overview")
        XCUIDevice.shared.orientation = .portrait
    }

    func testCloseReturnsToTheMap() throws {
        try open()
        let close = app.buttons["ae-hub-close"]
        require(close, "close button")
        close.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ae-hub-scene"].waitForNonExistence(timeout: 10))
        XCUIDevice.shared.orientation = .portrait
    }
}
