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
        XCTAssertTrue(app.descendants(matching: .any)["ae-session-report"]
            .waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Since you opened this campaign"].exists)
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
