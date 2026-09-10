import XCTest

/// A capture journey, deliberately separate from regression and performance suites.
/// The workflow generates the save with ae-rival-probe using ordinary game commands.
/// No balances, fleets, milestones or route figures are manufactured for the artwork.
final class StoreScreenshotUITests: AEUITestCase {
    override var wantsSunriseWeek: Bool { false }
    private var capturedShots = 0

    func testCaptureStoreStory() throws {
        defer {
            if capturedShots != 10 { capture("DIAGNOSTIC-incomplete-store-capture") }
            XCTAssertEqual(capturedShots, 10, "Every storyboard source must be photographed.")
        }
        let bundle = Bundle(for: StoreScreenshotUITests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "store-campaign", withExtension: "json"),
                                "Generate the intended store campaign before capturing marketing images")
        launch(appearance: .dark, arguments: ["-AEUITestLoadSave", url.path,
                                             "-AEUITestDarkAppearance"])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        openTab("Home")
        // The workflow advances the real engine to noon before saving. Keeping
        // it paused gives every screen the same moment, without timing UI taps.
        shot("01-network")

        guard openAirlineSection("Fleet") else { return }
        shot("02-fleet")
        guard openAircraftMarket() else { return }
        shot("02b-market")
        app.navigationBars.buttons.firstMatch.tap()

        guard openAirlineSection("Routes") else { return }
        shot("03b-routes")
        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@ AND label CONTAINS %@",
            "ae-route-row", "ARN", "IST")).firstMatch
        guard scrollUntil(row, "the Stockholm to Istanbul route"), tapWhenReady(row) else { return }
        shot("03-route")

        openTab("Finance")
        shot("04-finance")

        openTab("World")
        shot("05b-world")
        let rivals = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Competitors")).firstMatch
        guard require(rivals, "the competitors entry"), tapWhenReady(rivals) else { return }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ae-rival-card")
            .firstMatch.waitForExistence(timeout: 10))
        shot("05-rivals")
        app.navigationBars.buttons.firstMatch.tap()

        guard openProgression() else { return }
        shot("06-progression")
        app.navigationBars.buttons.firstMatch.tap()
        guard openBriefing() else { return }
        shot("06b-briefing")
        closeBriefing()
    }

    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 1)
        let systemBanner = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .staticTexts["Ready for Apple Intelligence"]
        if systemBanner.exists { systemBanner.swipeUp(); Thread.sleep(forTimeInterval: 1) }
        capture("STORE-" + name)
        capturedShots += 1
    }
}
