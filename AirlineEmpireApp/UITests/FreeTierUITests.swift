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
        let caption = app.staticTexts["Since you opened this campaign"]
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            !app.navigationBars["Settings"].exists && caption.isHittable
        }, object: nil)
        let visibilityResult = XCTWaiter.wait(for: [visible], timeout: 10)
        _ = waitUntilStill(caption)
        // Capture failures too. The card's layout container is not a hit
        // target; visibility must be checked on the text the player reads.
        capture("FREE-saved-session-summary")
        XCTAssertEqual(visibilityResult, .completed,
                       "Settings must dismiss before the saved-session recap is usable")
        XCTAssertTrue(caption.exists)
        XCTAssertFalse(app.alerts["Save"].exists, "A save alert must not cover the recap")
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
