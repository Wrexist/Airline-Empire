import XCTest

final class AircraftConfigurationUITests: AEUITestCase {
    func testCabinEditingAndUpgradeNavigationDark() throws {
        launch(appearance: .dark)
        guard foundAirline(seed: "2030"), openAircraftMarket(), leaseAnAircraft(model: "PA-184") else { return }
        guard openAirlineSection("Fleet") else { return }
        let row = app.descendants(matching: .any).matching(identifier: "ae-fleet-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let map = app.descendants(matching: .any).matching(identifier: "ae-aircraft-seat-map").firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        checkpoint("AE049-cabin-dark")
        let plus = app.buttons["ae-cabin-plus-business"]
        for _ in 0..<5 where !plus.isHittable { app.swipeUp() }
        XCTAssertTrue(plus.isHittable)
        plus.tap()
        let apply = app.buttons["ae-cabin-apply"]
        for _ in 0..<5 where !apply.isHittable { app.swipeUp() }
        XCTAssertTrue(apply.isHittable)
        apply.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Apply for")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Aircraft configuration saved"].waitForExistence(timeout: 10))
        checkpoint("AE049-cabin-saved")
        for _ in 0..<8 { app.swipeDown() }
        app.buttons["ae-aircraft-tab-Upgrades"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ae-upgrade-wifi").firstMatch.waitForExistence(timeout: 5))
        checkpoint("AE049-upgrades-dark")
    }

    func testCabinLightAccessibilityLayout() throws {
        launch(appearance: .light, arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        guard foundAirline(seed: "2030"), openAircraftMarket(), leaseAnAircraft(model: "PA-184") else { return }
        guard openAirlineSection("Fleet") else { return }
        let row = app.descendants(matching: .any).matching(identifier: "ae-fleet-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["ae-aircraft-tab-Cabin Layout"].waitForExistence(timeout: 10))
        checkpoint("AE049-cabin-light-accessibility")
    }
}
