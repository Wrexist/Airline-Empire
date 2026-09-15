import XCTest

final class RouteManagementUITests: AEUITestCase {
    func testRoutePlannerAndSections() throws {
        launch(appearance: .dark, arguments: ["-AEUITestDarkAppearance"])
        guard foundAirline(seed: "2030"), openAircraftMarket(), leaseAnAircraft(model: "PA-184"),
              openRouteBySearch(city: "Paris", code: "CDG"), assignFirstAircraft() else { return }
        try exercisePlanner()
    }

    func testRoutePlannerFromSavedCampaign() throws {
        let save = try XCTUnwrap(Bundle(for: RouteManagementUITests.self)
            .url(forResource: "rival-pressure-retreat", withExtension: "json"))
        launch(appearance: .dark, arguments: ["-AEUITestDarkAppearance", "-AEUITestLoadSave", save.path])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        guard openAirlineSection("Routes") else { return }
        let row = app.descendants(matching: .any).matching(identifier: "ae-route-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["ae-route-tab-Overview"].waitForExistence(timeout: 10))
        try exercisePlanner()
    }

    private func exercisePlanner() throws {
        for _ in 0..<8 { app.swipeDown() }
        checkpoint("ROUTE-overview-dark")
        let planning = app.buttons["ae-route-tab-Pricing & Schedule"]
        XCTAssertTrue(planning.waitForExistence(timeout: 8))
        planning.tap()
        let fare = app.buttons["ae-route-fare-5"]
        for _ in 0..<5 where !fare.isHittable { app.swipeUp() }
        XCTAssertTrue(fare.isHittable)
        fare.tap()
        checkpoint("ROUTE-pricing-draft")
        let apply = app.buttons["ae-route-plan-apply"]
        for _ in 0..<7 where !apply.isHittable { app.swipeUp() }
        XCTAssertTrue(apply.isHittable)
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        let confirm = app.buttons["Confirm Route Plan"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Route plan saved"].waitForExistence(timeout: 10))
        checkpoint("ROUTE-plan-saved")
        for _ in 0..<8 { app.swipeDown() }
        app.buttons["ae-route-tab-Aircraft"].tap()
        let comparison = app.descendants(matching: .any).matching(identifier: "ae-route-aircraft-comparison").firstMatch
        for _ in 0..<6 where !comparison.isHittable { app.swipeUp() }
        XCTAssertTrue(comparison.isHittable)
        comparison.tap()
        let aircraftChoice = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "#", "seats")).firstMatch
        XCTAssertTrue(aircraftChoice.waitForExistence(timeout: 5))
        aircraftChoice.tap()
        XCTAssertTrue(app.buttons["Open cabin & upgrades"].waitForExistence(timeout: 5))
        checkpoint("ROUTE-aircraft-comparison")
        for _ in 0..<8 { app.swipeDown() }
        let competition = app.buttons["ae-route-tab-Competition"]
        if !competition.isHittable { app.buttons["ae-route-tab-Aircraft"].swipeLeft() }
        competition.tap()
        checkpoint("ROUTE-competition")
        for _ in 0..<4 { app.swipeDown() }
        let history = app.buttons["ae-route-tab-History"]
        if !history.isHittable { competition.swipeLeft() }
        history.tap()
        XCTAssertTrue(app.staticTexts["Plan history"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No route plans changed yet. Your next confirmed change will appear here."].exists)
        checkpoint("ROUTE-history")
    }
}
