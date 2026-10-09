import XCTest
import UIKit

/// Captures the 3D Hub View in each of the reference clip's shots
/// (docs/HUB_VIEW_3D.md §1) from an earned campaign, so the render can be
/// compared frame for frame with the reference. Both in landscape: the
/// reference's aspect on iPad, and the hub holds an iPhone on its side.
final class HubViewUITests: AEUITestCase {
    override var wantsSunriseWeek: Bool { false }

    private func open(extra: [String] = []) throws {
        let bundle = Bundle(for: HubViewUITests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "store-campaign", withExtension: "json"))
        // Held at boarding: the reference's gate shot is the boarding moment
        // (queue, tug at the nose, passengers on the walkway).
        app.launchArguments.append(contentsOf: ["-AEUITestLoadSave", url.path, "-AEUITestProbes",
                                                "-AEUITestOpenHub", "-AEUITestHubStage", "boarding"] + extra)
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        app.activate()
        require(app.descendants(matching: .any)["ae-hub-scene"], "hub scene", timeout: 90)
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
        // The insights panel over the night overview: movements, alerts.
        let insights = app.buttons["ae-hub-insights"]
        require(insights, "insights button")
        insights.tap()
        Thread.sleep(forTimeInterval: 2)
        frame("HUB-07-insights")
        XCTAssertTrue(app.descendants(matching: .any)["ae-hub-insights-panel"].exists)
        // The routes page: each route's load factor, trips and profit.
        let routes = app.buttons["Routes"]
        if routes.exists {
            routes.tap()
            Thread.sleep(forTimeInterval: 1.5)
            frame("HUB-08-insights-routes")
        }
        // Upgrading from the hub, in daylight: the Airline page's lounge
        // row opens the upgrade card and flies to the site on the roof.
        let daylight = app.buttons["ae-hub-daylight"]
        if daylight.exists {
            daylight.tap()
            Thread.sleep(forTimeInterval: 2)
        }
        let airline = app.buttons["Airline"]
        if airline.exists {
            airline.tap()
            Thread.sleep(forTimeInterval: 1)
        }
        let lounge = app.buttons["ae-hub-facility-lounge"]
        require(lounge, "lounge row")
        lounge.tap()
        Thread.sleep(forTimeInterval: 3)
        frame("HUB-09-upgrade")
        XCTAssertTrue(app.descendants(matching: .any)["ae-hub-upgrade-card"].exists)
        // Order it (two taps: arm, confirm) and watch it go up.
        var build = app.buttons["ae-hub-upgrade-build"]
        if !build.exists {
            build = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Build'")).firstMatch
        }
        if build.exists && build.isEnabled {
            build.tap()
            Thread.sleep(forTimeInterval: 0.6)
            build.tap()
            Thread.sleep(forTimeInterval: 2.2)
            frame("HUB-10-construction")
            Thread.sleep(forTimeInterval: 5)
            frame("HUB-11-built")
        }
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
