import XCTest

final class FreeTierUITests: AEUITestCase {
    override var usesProFixture: Bool { false }
    override var wantsSunriseWeek: Bool { false }

    func testSuccessfulSaveShowsSessionSummary() {
        launch(appearance: .light, arguments: ["-AEUITestFree"])
        guard foundAirline(), openBriefing() else { return }
        let settings = app.buttons["Settings"]
        guard require(settings, "Settings") else { return }
        settings.tap()
        let save = app.buttons["Save and quit to menu"]
        guard scrollUntil(save, "Save and quit to menu") else { return }
        save.tap()
        let report = app.descendants(matching: .any)["ae-session-report"]
        XCTAssertTrue(report.waitForExistence(timeout: 15))
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            !app.navigationBars["Settings"].exists && report.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed,
                       "Settings must dismiss before the saved-session recap is usable")
        XCTAssertTrue(app.staticTexts["Since you opened this campaign"].exists)
        XCTAssertFalse(app.alerts["Save"].exists, "A save alert must not cover the recap")
        _ = waitUntilStill(report)
        capture("FREE-saved-session-summary")
    }

    func testFreePlayerReachesGameWithoutFoundingPaywall() {
        launch(appearance: .light, arguments: ["-AEUITestFree"])
        guard foundAirline() else { return }
        XCTAssertNotNil(waitForTab("Home", timeout: 8))
        XCTAssertFalse(app.buttons["ae-paywall-buy"].exists,
                       "The first Pro offer must wait until the player completes a flight.")
        XCTAssertTrue(app.buttons["Advance to next day"].waitForExistence(timeout: 8))
        capture("FREE-first-airline-before-first-flight")
    }
}
