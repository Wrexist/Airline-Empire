import XCTest

final class FreeTierUITests: AEUITestCase {
    override var usesProFixture: Bool { false }
    override var wantsSunriseWeek: Bool { false }

    /// Captures genuine purchase UI using the scheme's StoreKit products.
    /// This verifies disclosure and navigation, without making a purchase.
    func testPaywallDisclosuresAndReviewCaptures() {
        launch(appearance: .light, arguments: ["-AEUITestFree"])
        guard foundAirline(), openBriefing() else { return }
        let settings = app.buttons["Settings"]
        guard require(settings, "Settings"), tapWhenReady(settings) else { return }
        let pro = app.buttons["ae-settings-pro"]
        guard scrollUntil(pro, "Airline Empire Pro"), tapWhenReady(pro) else { return }

        for tier in ["weekly", "yearly", "lifetime"] {
            let plan = app.buttons["ae-paywall-plan-com.airlineempire.game.pro.\(tier)"]
            guard scrollUntil(plan, "the \(tier) plan"), tapWhenReady(plan) else { return }
            let buy = app.buttons["ae-paywall-buy"]
            guard scrollUntil(buy, "the purchase disclosure and button") else { return }
            let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                buy.exists && buy.isEnabled
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 20), .completed,
                           "Real StoreKit test products must load before photographing the paywall")
            let commitment = app.staticTexts["ae-paywall-commitment"]
            XCTAssertTrue(commitment.exists)
            XCTAssertFalse(commitment.label.isEmpty)
            _ = waitUntilStill(buy)
            capture("IAP-\(tier)")
        }
        let restore = app.buttons["ae-paywall-restore"]
        XCTAssertTrue(scrollUntil(restore, "Restore Purchases and legal links"))
        XCTAssertTrue(app.buttons["Terms of Use"].exists)
        XCTAssertTrue(app.buttons["Privacy Policy"].exists)
    }

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
