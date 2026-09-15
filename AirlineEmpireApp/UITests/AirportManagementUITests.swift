import XCTest
import AirlineEmpireCore

final class AirportManagementUITests: AEUITestCase {
    func testAirportInsufficientCash() throws {
        let url = try XCTUnwrap(Bundle(for: AirportManagementUITests.self)
            .url(forResource: "rival-pressure-retreat", withExtension: "json"))
        let codec = JSONSaveCodec()
        var state = try codec.decode(Data(contentsOf: url))
        let player = try XCTUnwrap(state.playerAirline)
        // Stress fixture only: leave one dollar, retaining the real network and save format.
        state.ledger.post(airline: player.id, category: .overhead,
            amount: .dollars(1) - state.ledger.balance(of: player.id), at: state.clock.now,
            memo: "Airport affordability test setup")
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("airport-low-cash.aesave")
        try codec.encode(state).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        launch(appearance: .dark, arguments: ["-AEUITestDarkAppearance", "-AEUITestLoadSave", fixture.path])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        openTab("World")
        let airports = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Airports")).firstMatch
        for _ in 0..<5 where !airports.isHittable { app.swipeUp() }
        XCTAssertTrue(airports.waitForExistence(timeout: 10)); airports.tap()
        let row = app.descendants(matching: .any).matching(identifier: "ae-airport-row-ARN").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        let services = app.buttons["ae-airport-tab-Services"]
        XCTAssertTrue(services.waitForExistence(timeout: 10)); services.tap()
        let lounge = app.buttons["ae-airport-lounge-1"]
        revealControl(lounge); lounge.tap()
        XCTAssertTrue(lounge.isSelected)
        let apply = app.buttons["ae-airport-investment-apply"]
        revealControl(apply)
        XCTAssertFalse(apply.isEnabled)
        XCTAssertTrue(app.staticTexts["There is not enough cash for this airport investment."].exists)
        checkpoint("SERVICES-insufficient-cash")
        let reset = app.buttons["ae-airport-investment-reset"]
        revealControl(reset); reset.tap()
        revealControl(app.buttons["ae-airport-lounge-0"])
        XCTAssertTrue(app.buttons["ae-airport-lounge-0"].isSelected)
    }

    func testAirportInvestmentJourney() throws {
        let save = try XCTUnwrap(Bundle(for: AirportManagementUITests.self)
            .url(forResource: "rival-pressure-retreat", withExtension: "json"))
        launch(appearance: .dark, arguments: ["-AEUITestDarkAppearance", "-AEUITestLoadSave", save.path])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        openTab("World")
        let airports = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Airports")).firstMatch
        for _ in 0..<5 where !airports.isHittable { app.swipeUp() }
        XCTAssertTrue(airports.waitForExistence(timeout: 10)); airports.tap()
        let row = app.descendants(matching: .any).matching(identifier: "ae-airport-row-ARN").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        XCTAssertTrue(app.buttons["ae-airport-tab-Overview"].waitForExistence(timeout: 10))
        checkpoint("AIRPORT-overview")
        app.buttons["ae-airport-tab-Services"].tap()
        checkpoint("SERVICES-01-initial")
        let lounge = app.buttons["ae-airport-lounge-1"]
        revealControl(lounge)
        lounge.tap()
        XCTAssertTrue(lounge.isSelected)
        checkpoint("SERVICES-02-one-proposed")
        let reset = app.buttons["ae-airport-investment-reset"]
        revealControl(reset); reset.tap()
        revealControl(lounge)
        XCTAssertFalse(lounge.isSelected)
        lounge.tap()
        XCTAssertTrue(lounge.isSelected)
        let ground = app.buttons["ae-airport-ground-1"]
        revealControl(ground)
        ground.tap()
        XCTAssertTrue(ground.isSelected)
        checkpoint("SERVICES-03-multiple-proposed")
        let apply = app.buttons["ae-airport-investment-apply"]
        revealControl(apply)
        XCTAssertTrue(apply.isHittable); XCTAssertTrue(apply.isEnabled)
        checkpoint("AIRPORT-investment-preview")
        checkpoint("SERVICES-04-preview")
        apply.tap()
        let confirm = app.buttons["Confirm Airport Upgrades"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        checkpoint("SERVICES-05-confirmation")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Airport investment saved"].waitForExistence(timeout: 10))
        checkpoint("SERVICES-06-applied")
        for _ in 0..<8 { app.swipeDown() }
        let network = app.buttons["ae-airport-tab-Your Network"]
        network.tap(); checkpoint("AIRPORT-network")
        let competition = app.buttons["ae-airport-tab-Competition"]
        if !competition.isHittable { network.swipeLeft() }
        competition.tap(); checkpoint("AIRPORT-competition")
        let history = app.buttons["ae-airport-tab-History"]
        if !history.isHittable { competition.swipeLeft() }
        history.tap()
        XCTAssertTrue(app.staticTexts["Airport investment history"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Confirmed facility changes will appear here."].exists)
        checkpoint("AIRPORT-history")
        // Return to the installed controls: leaving a section must not lose a saved plan.
        history.swipeRight()
        let facilities = app.buttons["ae-airport-tab-Services"]
        if !facilities.isHittable { network.swipeRight() }
        facilities.tap()
        revealControl(lounge)
        XCTAssertTrue(lounge.isSelected)
        // Persist through the player's save flow, terminate, and reopen the saved slot.
        guard openBriefing() else { return }
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        let saveAndQuit = app.buttons["Save and quit to menu"]
        guard scrollUntil(saveAndQuit, "Save airport services"), tapWhenReady(saveAndQuit) else { return }
        XCTAssertTrue(app.descendants(matching: .any)["ae-session-report"].waitForExistence(timeout: 15))
        app.terminate()
        if let index = app.launchArguments.firstIndex(of: "-AEUITestLoadSave") {
            app.launchArguments.removeSubrange(index...index + 1)
        }
        app.launch()
        let resume = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ae-menu-continue-")).firstMatch
        guard revealMenuControl(resume, "Restore airport investment"), tapWhenReady(resume) else { return }
        openTab("World")
        let airportList = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Airports")).firstMatch
        for _ in 0..<5 where !airportList.isHittable { app.swipeUp() }
        XCTAssertTrue(airportList.waitForExistence(timeout: 10)); airportList.tap()
        let restoredRow = app.descendants(matching: .any).matching(identifier: "ae-airport-row-ARN").firstMatch
        XCTAssertTrue(restoredRow.waitForExistence(timeout: 10)); restoredRow.tap()
        XCTAssertTrue(app.buttons["ae-airport-tab-Services"].waitForExistence(timeout: 10))
        app.buttons["ae-airport-tab-Services"].tap()
        revealControl(lounge)
        XCTAssertTrue(lounge.isSelected)
        revealControl(ground)
        XCTAssertTrue(ground.isSelected)
        checkpoint("SERVICES-restored-after-restart")
    }

    private func revealControl(_ element: XCUIElement) {
        for _ in 0..<18 {
            let frame = element.exists ? element.frame : .zero
            // Hittability alone includes controls partially behind the floating tab bar.
            let top = app.frame.minY + 120
            let bottom = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 24 : app.frame.maxY - 40
            if !frame.isEmpty, frame.minY >= top, frame.maxY <= bottom, element.isHittable {
                XCTAssertTrue(waitUntilStill(element))
                return
            }
            let upward = frame.isEmpty || frame.minY >= top
            let x = frame.isEmpty ? app.frame.midX : min(app.frame.maxX - 40, max(app.frame.minX + 40, frame.midX))
            let startY = upward ? bottom - 30 : top + 30
            let endY = startY + (upward ? -240.0 : 240.0)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: x, dy: startY))
                .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: x, dy: endY)),
                       withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTFail("Airport control did not become fully visible: \(element.identifier)")
    }
}
