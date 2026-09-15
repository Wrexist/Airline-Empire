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
        for _ in 0..<5 where !lounge.isHittable { app.swipeUp() }
        XCTAssertTrue(lounge.isHittable); lounge.tap()
        let ground = app.buttons["ae-airport-ground-1"]
        for _ in 0..<5 where !ground.isHittable { app.swipeUp() }
        XCTAssertTrue(ground.isHittable); ground.tap()
        checkpoint("AIRPORT-facilities-draft")
        let apply = app.buttons["ae-airport-investment-apply"]
        for _ in 0..<8 where !apply.isHittable { app.swipeUp() }
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
        for _ in 0..<5 where !lounge.isHittable { app.swipeUp() }
        XCTAssertTrue(lounge.isSelected)
    }
}
