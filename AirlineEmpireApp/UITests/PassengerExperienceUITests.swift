import XCTest

/// The passenger-experience journey: the tier selection is a draft, reset
/// restores the installed tier, the apply is confirmed, and the choice
/// survives a save and relaunch.
final class PassengerExperienceUITests: AEUITestCase {
    private func openPassengerExperience() {
        XCTAssertTrue(openBriefing())
        let link = app.buttons["ae-stat-reputation"]
        for _ in 0..<6 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let score = app.descendants(matching: .any)
            .matching(identifier: "ae-reputation-score").firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: 10))
    }

    private func fixtureURL() throws -> URL {
        try XCTUnwrap(Bundle(for: PassengerExperienceUITests.self)
            .url(forResource: "rival-pressure-retreat", withExtension: "json"))
    }

    func testPassengerExperienceJourney() throws {
        launch(appearance: .dark, arguments: ["-AEUITestDarkAppearance",
                                              "-AEUITestLoadSave", try fixtureURL().path])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        openPassengerExperience()
        checkpoint("PAX-01-initial")

        // Choosing a tier must preview, not submit: the installed tier stays
        // current while the chosen one is only proposed.
        let premium = app.buttons["ae-service-tier-premium"]
        let standard = app.buttons["ae-service-tier-standard"]
        scrollFullyIntoView(premium, "the premium tier")
        premium.tap()
        XCTAssertTrue(premium.isSelected)
        XCTAssertFalse(standard.isSelected,
                       "Choosing a tier must leave the installed tier unselected")
        XCTAssertEqual(standard.value as? String, "Currently installed")
        checkpoint("PAX-02-proposed")

        let forecast = app.descendants(matching: .any)
            .matching(identifier: "ae-service-forecast").firstMatch
        XCTAssertTrue(forecast.waitForExistence(timeout: 10))
        let gradual = app.descendants(matching: .any)
            .matching(identifier: "ae-service-gradual-note").firstMatch
        XCTAssertTrue(gradual.waitForExistence(timeout: 10),
                      "A cost-raising tier must say the reputation response is gradual")
        checkpoint("PAX-03-forecast")

        // Reset restores the installed tier and clears the proposal.
        let reset = app.buttons["ae-service-reset"]
        scrollFullyIntoView(reset, "Reset Changes")
        XCTAssertTrue(reset.isHittable && reset.isEnabled)
        reset.tap()
        // Reset does not move the scroll position, and Reset sits near the
        // bottom, so the tier panel is above the fold. Return to the top
        // first: the score is the topmost element, so its hittability is an
        // honest "we are at the top" signal and it stops the swipe before one
        // too many could pull the sheet down.
        let score = app.descendants(matching: .any)
            .matching(identifier: "ae-reputation-score").firstMatch
        for _ in 0..<14 {
            if score.exists && score.isHittable { break }
            app.swipeDown()
            Thread.sleep(forTimeInterval: 0.3)
        }
        scrollFullyIntoView(premium, "the premium tier after reset")
        XCTAssertFalse(premium.isSelected)
        XCTAssertTrue(standard.isSelected)
        checkpoint("PAX-04-reset")

        // Apply opens a confirmation before the economic commitment.
        premium.tap()
        XCTAssertTrue(premium.isSelected)
        let apply = app.buttons["ae-service-apply"]
        scrollFullyIntoView(apply, "Apply Service Tier")
        XCTAssertTrue(apply.isHittable && apply.isEnabled)
        apply.tap()
        let confirm = app.buttons["Apply Service Tier"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        checkpoint("PAX-05-confirmation")
        confirm.tap()
        let saved = app.descendants(matching: .any)
            .matching(identifier: "ae-service-saved").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        checkpoint("PAX-06-applied")

        // Persist through the player's own save flow, terminate and reopen.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["ae-briefing-close"].waitForExistence(timeout: 10))
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let saveAndQuit = app.buttons["Save and quit to menu"]
        XCTAssertTrue(scrollUntil(saveAndQuit, "Save passenger experience"))
        saveAndQuit.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ae-session-report"].waitForExistence(timeout: 15))
        app.terminate()
        if let index = app.launchArguments.firstIndex(of: "-AEUITestLoadSave") {
            app.launchArguments.removeSubrange(index...index + 1)
        }
        app.launch()
        let resume = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "ae-menu-continue-")).firstMatch
        XCTAssertTrue(revealMenuControl(resume, "Restore passenger experience"))
        resume.tap()
        openPassengerExperience()
        let restored = app.buttons["ae-service-tier-premium"]
        scrollFullyIntoView(restored, "the restored premium tier")
        XCTAssertTrue(restored.isSelected, "The applied tier must survive a relaunch")
        XCTAssertEqual(restored.value as? String, "Currently installed")
        checkpoint("PAX-07-restored")
    }

    /// The two controls a player must reach at the largest text sizes.
    func testPassengerExperienceAtAccessibilitySize() throws {
        launch(appearance: .light, arguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityL",
            "-AEUITestLoadSave", try fixtureURL().path,
        ])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        openPassengerExperience()
        let premium = app.buttons["ae-service-tier-premium"]
        scrollFullyIntoView(premium, "the premium tier at accessibility size")
        premium.tap()
        XCTAssertTrue(premium.isSelected)
        checkpoint("PAX-AX-proposed")

        let apply = app.buttons["ae-service-apply"]
        scrollFullyIntoView(apply, "Apply Service Tier at accessibility size")
        XCTAssertTrue(apply.isHittable && apply.isEnabled,
                      "The Apply action must be reachable at an accessibility text size")
        checkpoint("PAX-AX-apply")
        let reset = app.buttons["ae-service-reset"]
        scrollFullyIntoView(reset, "Reset Changes at accessibility size")
        XCTAssertTrue(reset.isHittable,
                      "Reset must be reachable at an accessibility text size")
        checkpoint("PAX-AX-reset")
    }
}
