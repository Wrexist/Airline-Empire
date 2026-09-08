import XCTest

/// A capture journey, deliberately separate from regression and performance suites.
/// The workflow generates the save with ae-rival-probe using ordinary game commands.
/// No balances, fleets, milestones or route figures are manufactured for the artwork.
final class StoreScreenshotUITests: AEUITestCase {
    override var wantsSunriseWeek: Bool { false }

    func testCaptureStoreStory() throws {
        let bundle = Bundle(for: StoreScreenshotUITests.self)
        let fixture = bundle.url(forResource: "store-campaign", withExtension: "json")
            ?? bundle.url(forResource: "rival-pressure-late-game", withExtension: "json")
        let url = try XCTUnwrap(fixture)
        launch(appearance: .dark, arguments: ["-AEUITestLoadSave", url.path,
                                             "-AEUITestDarkAppearance"])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        openTab("Home")
        guard setSpeed("Sixteen times speed") else { return }
        Thread.sleep(forTimeInterval: 8)
        guard setSpeed("Pause") else { return }
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
            "ae-route-row", "LHR", "CDG")).firstMatch
        guard scrollUntil(row, "the London to Paris route"), tapWhenReady(row) else { return }
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
    }

    /// These are idempotent selections. A system notification may intercept a tap.
    private func setSpeed(_ label: String) -> Bool {
        for _ in 0..<2 {
            let button = app.buttons.matching(identifier: label).firstMatch
            guard require(button, label), button.isHittable else { return false }
            if button.isSelected { return true }
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.app.buttons.matching(identifier: label).firstMatch.isSelected
            }, object: nil)
            if XCTWaiter.wait(for: [selected], timeout: 8) == .completed { return true }
            let banner = XCUIApplication(bundleIdentifier: "com.apple.springboard")
                .staticTexts["Ready for Apple Intelligence"]
            if banner.exists { banner.swipeUp() }
        }
        XCTFail("The capture journey could not select \(label).")
        return false
    }
}
