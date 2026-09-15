import XCTest

final class AirportManagementUITests: AEUITestCase {
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
        app.buttons["ae-airport-tab-Facilities"].tap()
        let lounge = app.buttons["ae-airport-lounge-1"]
        revealControl(lounge)
        lounge.tap()
        XCTAssertTrue(lounge.isSelected)
        let ground = app.buttons["ae-airport-ground-1"]
        revealControl(ground)
        ground.tap()
        XCTAssertTrue(ground.isSelected)
        checkpoint("AIRPORT-facilities-draft")
        let apply = app.buttons["ae-airport-investment-apply"]
        revealControl(apply)
        XCTAssertTrue(apply.isHittable); XCTAssertTrue(apply.isEnabled)
        checkpoint("AIRPORT-investment-preview")
        apply.tap()
        let confirm = app.buttons["Confirm Airport Investment"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.staticTexts["Airport investment saved"].waitForExistence(timeout: 10))
        checkpoint("AIRPORT-investment-saved")
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
        let facilities = app.buttons["ae-airport-tab-Facilities"]
        if !facilities.isHittable { network.swipeRight() }
        facilities.tap()
        revealControl(lounge)
        XCTAssertTrue(lounge.isSelected)
    }

    private func revealControl(_ element: XCUIElement) {
        for _ in 0..<10 {
            let frame = element.exists ? element.frame : .zero
            // Hittability alone includes controls partially behind the floating tab bar.
            let top = app.frame.minY + 120, bottom = app.frame.maxY - 160
            if !frame.isEmpty, frame.minY >= top, frame.maxY <= bottom, element.isHittable {
                XCTAssertTrue(waitUntilStill(element))
                return
            }
            if !frame.isEmpty && frame.minY < top { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTFail("Airport control did not become fully visible: \(element.identifier)")
    }
}
