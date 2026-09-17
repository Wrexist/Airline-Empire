import XCTest

/// A capture journey, deliberately separate from regression and performance suites.
/// The workflow generates the save with ae-rival-probe using ordinary game commands.
/// No balances, fleets, milestones or route figures are manufactured for the artwork.
class StoreScreenshotUITests: AEUITestCase {
    var captureAppearance: XCUIDevice.Appearance { .light }
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
        // Dark review explicitly pins rendering using the existing test flag.
        // This verifies dark layouts, not the simulator's Settings transition.
        let appearanceArguments = captureAppearance == .dark ? ["-AEUITestDarkAppearance"] : []
        launch(appearance: captureAppearance,
               arguments: ["-AEUITestLoadSave", url.path] + appearanceArguments)
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        openTab("Home")
        // The workflow advances the real engine to noon before saving. Keeping
        // it paused gives every screen the same moment, without timing UI taps.
        shot("01-network")

        guard openAirlineSection("Fleet") else { return }
        shot("02-fleet")
        guard verifyFleetControls() else { return }

        guard openAirlineSection("Routes") else { return }
        shot("03b-routes")
        guard verifyNetworkStatistics() else { return }
        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@ AND label CONTAINS %@",
            "ae-route-row", "ARN", "IST")).firstMatch
        guard scrollUntil(row, "the Stockholm to Istanbul route"), tapWhenReady(row) else { return }
        shot("03-route")

        // The market compares airframes only for a route it was opened on,
        // and a route is where the market is entered with one. Capture it
        // from the route rather than from the Fleet tab's unrouted catalogue.
        let find = app.buttons["ae-route-find-aircraft"]
        guard scrollUntil(find, "the route's aircraft market"), tapWhenReady(find) else { return }
        guard verifyMarketComparison() else { return }
        shot("02b-market")
        guard verifyMarketControls() else { return }
        guard dismissMarket() else { return }

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

    // Exercise the controls changed by the compact management layout using
    // the same earned campaign in both appearances and on both device sizes.
    private func verifyFleetControls() -> Bool {
        let statistics = app.buttons.matching(identifier: "ae-fleet-statistics").firstMatch
        guard require(statistics, "expandable fleet statistics"), tapWhenReady(statistics) else { return false }
        XCTAssertTrue(app.staticTexts["Average age"].waitForExistence(timeout: 5))
        guard tapWhenReady(statistics) else { return false }
        let filter = app.buttons["ae-fleet-status-filter"]
        guard require(filter, "the compact fleet status filter") else { return false }
        XCTAssertLessThanOrEqual(filter.frame.height, 60,
                                 "A default-size filter must remain a compact labelled control")
        XCTAssertLessThanOrEqual(app.buttons["ae-fleet-ownership-filter"].frame.height, 60)
        guard tapWhenReady(filter) else { return false }
        let idle = app.buttons["ae-fleet-status-idle"]
        guard require(idle, "the idle filter option"), tapWhenReady(idle) else { return false }
        XCTAssertEqual(filter.value as? String, "Idle")
        let reset = app.buttons["ae-fleet-reset-filters"]
        guard require(reset, "reset fleet filters"), tapWhenReady(reset) else { return false }
        XCTAssertEqual(filter.value as? String, "All")
        return true
    }

    /// The market's comparing shape, which is the frame the store keeps: a
    /// route chosen and the airframes priced on it, same fare and frequency.
    private func verifyMarketComparison() -> Bool {
        let panel = app.descendants(matching: .any)
            .matching(identifier: "ae-aircraft-comparison").firstMatch
        guard require(panel, "the route comparison") else { return false }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Compare on ")).firstMatch.exists,
                      "The comparison must name the route it is for")
        let rows = app.descendants(matching: .any)
            .matching(identifier: "ae-aircraft-comparison-row")
        XCTAssertGreaterThanOrEqual(rows.count, 2,
                                    "A chosen route must compare more than one airframe")
        return true
    }

    private func dismissMarket() -> Bool {
        let done = app.buttons["Done"].firstMatch
        guard require(done, "the market's Done button"), tapWhenReady(done) else { return false }
        return app.navigationBars["Aircraft market"].waitForNonExistence(timeout: 10)
    }

    private func verifyMarketControls() -> Bool {
        let model = app.staticTexts.matching(identifier: "ae-market-model-name").firstMatch
        guard scrollUntil(model, "the aircraft model facts"), tapWhenReady(model) else { return false }
        let modelName = model.label
        let used = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "ae-deal-buy-used", modelName)).firstMatch
        guard scrollUntil(used, "the used deal selector for this aircraft"), tapWhenReady(used) else { return false }
        // The purchase footer is a separate lazy List row. On an iPad sheet
        // it may not exist until scrolled into view; keep the model identity
        // fixed while the list recycles rows.
        let commit = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "ae-market-buy-used", modelName)).firstMatch
        guard scrollUntil(commit, "the selected aircraft's used purchase action") else { return false }
        XCTAssertTrue(commit.isHittable,
                      "Choosing a deal updates its own commit action without purchasing")
        XCTAssertTrue(app.navigationBars["Aircraft market"].exists,
                      "Tapping facts and changing deals must leave the market open")
        return true
    }

    private func verifyNetworkStatistics() -> Bool {
        let statistics = app.buttons.matching(identifier: "ae-network-statistics").firstMatch
        guard require(statistics, "expandable network statistics"), tapWhenReady(statistics) else { return false }
        XCTAssertTrue(app.staticTexts["Losing routes"].waitForExistence(timeout: 5))
        return tapWhenReady(statistics)
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

/// Review the same real campaign in dark appearance without distributing a build.
final class DarkInterfaceReviewUITests: StoreScreenshotUITests {
    override var captureAppearance: XCUIDevice.Appearance { .dark }
}
