import XCTest
import StoreKitTest

final class FreeTierUITests: AEUITestCase {
    override var usesProFixture: Bool { false }
    override var wantsSunriseWeek: Bool { false }

    /// Captures genuine purchase UI using the scheme's StoreKit products.
    /// This verifies disclosure and navigation, without making a purchase.
    func testPaywallDisclosuresAndReviewCaptures() throws {
        try verifyPaywall(arguments: [], capturePrefix: "IAP-")
    }

    func testPaywallPurchaseVisibleWithAccessibilityText() throws {
        try verifyPaywall(arguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityL",
        ], capturePrefix: "KEY-00-paywall-accessibility-")
    }

    private func verifyPaywall(arguments: [String], capturePrefix: String) throws {
        // The scheme's Run action does not configure xcodebuild's Test action.
        // Activate the real StoreKit test server before launching the app.
        let store = try SKTestSession(configurationFileNamed: "AirlineEmpire")
        store.resetToDefaultState()
        store.clearTransactions()
        store.storefront = "USA"
        store.locale = Locale(identifier: "en_US")
        defer { store.clearTransactions(); store.resetToDefaultState() }
        launch(appearance: .light, arguments: ["-AEUITestFree"] + arguments)
        guard foundAirline(), openBriefing() else { return }
        let settings = app.buttons["Settings"]
        guard require(settings, "Settings"), tapWhenReady(settings) else { return }
        let pro = app.buttons["ae-settings-pro"]
        guard scrollUntil(pro, "Airline Empire Pro"), tapWhenReady(pro) else { return }

        let buy = app.buttons["ae-paywall-buy"]
        let initiallyVisible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            buy.exists && buy.isEnabled && buy.isHittable
        }, object: nil)
        let initialResult = XCTWaiter.wait(for: [initiallyVisible], timeout: 20)
        if initialResult != .completed {
            capture("KEY-00-\(capturePrefix)on-open-failure")
            print("PAYWALL purchase exists=\(buy.exists) enabled=\(buy.isEnabled) hittable=\(buy.isHittable) label=\(buy.label)")
        }
        XCTAssertEqual(initialResult, .completed,
                      "Purchase must be visible when the paywall opens, without scrolling")
        _ = waitUntilStill(buy)
        XCTAssertTrue(app.frame.contains(buy.frame),
                      "The whole purchase button must fit inside the initial viewport")
        capture("KEY-00-\(capturePrefix)on-open")

        let paywallScroll = app.scrollViews["ae-paywall-content"]
        for tier in ["weekly", "yearly", "lifetime"] {
            let plan = app.buttons["ae-paywall-plan-com.airlineempire.game.pro.\(tier)"]
            guard scrollPaywallUntil(plan, "the \(tier) plan", in: paywallScroll) else { return }
            // XCTest can report a card behind the fixed checkout as hittable.
            // Tap only the portion we have verified is above that checkout.
            let visiblePlan = plan.frame.intersection(paywallViewport(in: paywallScroll))
            guard !visiblePlan.isNull, visiblePlan.height >= 32 else {
                XCTFail("The plan must have a visible tap target above checkout")
                return
            }
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: visiblePlan.midX - app.frame.minX,
                                     dy: visiblePlan.midY - app.frame.minY)).tap()
            let selected = app.staticTexts["ae-paywall-selected-plan"]
            let expectedName = ["weekly": "Pro Weekly", "yearly": "Pro Yearly",
                                "lifetime": "Pro Lifetime"][tier]!
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                selected.exists && selected.label == expectedName
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed,
                           "Selecting a plan must update checkout without starting a purchase")
            XCTAssertTrue(buy.isHittable,
                          "The purchase button must remain visible while selecting plans")
            let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                buy.exists && buy.isEnabled
            }, object: nil)
            let loadingResult = XCTWaiter.wait(for: [loaded], timeout: 20)
            if loadingResult != .completed { capture("KEY-00-IAP-products-unavailable") }
            XCTAssertEqual(loadingResult, .completed,
                           "Real StoreKit test products must load before photographing the paywall")
            let commitment = app.staticTexts["ae-paywall-commitment"]
            XCTAssertTrue(commitment.exists)
            XCTAssertFalse(commitment.label.isEmpty)
            XCTAssertTrue(app.frame.contains(commitment.frame),
                          "The full billing disclosure must stay visible with the button")
            XCTAssertLessThanOrEqual(commitment.frame.maxY, buy.frame.minY)
            _ = waitUntilStill(buy)
            capture("\(capturePrefix)\(tier)")
        }
        let restore = app.buttons["ae-paywall-restore"]
        XCTAssertTrue(scrollPaywallUntil(restore, "Restore Purchases and legal links",
                                        in: paywallScroll))
        XCTAssertTrue(app.buttons["Terms of Use"].exists)
        XCTAssertTrue(app.buttons["Privacy Policy"].exists)
    }

    private func paywallViewport(in scroll: XCUIElement) -> CGRect {
        let frame = scroll.frame.intersection(app.frame)
        // The label is padded 16 points inside the fixed checkout.
        let bottom = min(frame.maxY,
                         app.staticTexts["ae-paywall-selected-plan"].frame.minY - 20)
        return CGRect(x: frame.minX + 8, y: frame.minY + 8,
                      width: max(0, frame.width - 16),
                      height: max(0, bottom - frame.minY - 8))
    }

    private func scrollPaywallUntil(_ element: XCUIElement, _ what: String,
                                    in scroll: XCUIElement) -> Bool {
        for _ in 0..<30 {
            if element.exists && element.isHittable, element.frame.height > 0,
               element.frame.intersection(paywallViewport(in: scroll)).height >= min(32, element.frame.height) {
                _ = waitUntilStill(element)
                if element.frame.intersection(paywallViewport(in: scroll)).height >= min(32, element.frame.height) {
                    return true
                }
            }
            // safeAreaInset reserves content space, but XCTest still reports
            // the scroll view's frame behind checkout. At accessibility size
            // a 75%-height gesture starts on the fixed footer and cannot scroll.
            // Restrict the gesture to the visible content above the plan label.
            let checkoutTop = app.staticTexts["ae-paywall-selected-plan"].frame.minY
            let visibleHeight = min(scroll.frame.maxY, checkoutTop) - scroll.frame.minY
            guard visibleHeight > 44 else { break }
            let top = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            top.withOffset(CGVector(dx: 0, dy: visibleHeight * 0.65))
                .press(forDuration: 0.05,
                       thenDragTo: top.withOffset(CGVector(dx: 0, dy: visibleHeight * 0.25)))
        }
        capture("KEY-00-paywall-missing-\(what)")
        XCTFail("\(what) must remain reachable above the fixed purchase area")
        return false
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
