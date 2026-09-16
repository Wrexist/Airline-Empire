import XCTest
import AirlineEmpireCore

/// The Finance breakdown: operating performance, cash movements and recurring
/// commitments are separate groups, period labels are explicit, an expense
/// links to the screen that owns it, and cash change is not presented as
/// profit.
final class FinanceBreakdownUITests: AEUITestCase {
    /// A month closed, a loan outstanding and one station service installed,
    /// so every group has content.
    private func writeFixture() throws -> URL {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: ScenarioBootstrap.newGame(
            scenario: "founder", worldSeed: 42, startYear: 2030),
            systems: GamePipeline.standard(), catalog: catalog)
        XCTAssertEqual(engine.applyNow(FoundAirlineCommand(airlineName: "Pacifica ledger",
            kind: .player, homeAirport: "ARN", startingCash: .dollars(30_000_000))), .applied)
        let player = try XCTUnwrap(engine.state.playerAirline?.id)
        XCTAssertEqual(engine.applyNow(LeaseAircraftCommand(
            lessee: player, type: "PA184", termMonths: 60)), .applied)
        XCTAssertEqual(engine.applyNow(OpenRouteCommand(airline: player, origin: "ARN",
            destination: "CDG", dailyRoundTrips: 3, ticketPrice: .dollars(180))), .applied)
        let route = try XCTUnwrap(engine.state.routes(of: player).first)
        let aircraft = try XCTUnwrap(engine.state.fleet(of: player).first)
        XCTAssertEqual(engine.applyNow(AssignAircraftToRouteCommand(
            airline: player, route: route.id, aircraftID: aircraft.id)), .applied)
        let ticksPerDay = Int(GameCalendar.minutesPerDay / engine.state.meta.tickMinutes)
        engine.advance(ticks: ticksPerDay * 35)
        XCTAssertEqual(engine.applyNow(TakeLoanCommand(airline: player,
            amount: .dollars(5_000_000), termMonths: 48)), .applied)
        XCTAssertEqual(engine.applyNow(ConfigureAirportFacilitiesCommand(
            airline: player, airport: "ARN", facilities: .init(lounge: 1))), .applied)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("finance-\(UUID().uuidString).aesave")
        try JSONSaveCodec().encode(engine.state).write(to: url)
        return url
    }

    func testFinanceBreakdownJourney() throws {
        let fixture = try writeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        launch(appearance: .dark, arguments: ["-AEUITestDarkAppearance",
                                              "-AEUITestLoadSave", fixture.path])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        openTab("Finance")

        // Three questions, three groups.
        XCTAssertTrue(app.staticTexts["Operating performance"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Cash movements"].exists)
        XCTAssertTrue(app.staticTexts["This month (to date)"].exists)
        let notProfit = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "Cash change is not profit")).firstMatch
        XCTAssertTrue(notProfit.exists,
                      "The cash group must say that cash change is not profit")
        checkpoint("FIN-01-groups")

        // The closed month keeps its statement, and an expense links to the
        // screen that owns the decision.
        let statement = app.staticTexts.matching(NSPredicate(
            format: "label ==[c] %@", "Jan 2030 statement")).firstMatch
        XCTAssertTrue(scrollUntil(statement, "the closed January statement"))
        XCTAssertTrue(app.staticTexts["Net profit"].exists)
        let fuel = app.buttons["ae-finance-category-fuel"]
        XCTAssertTrue(scrollUntil(fuel, "the fuel expense link"))
        fuel.tap()
        XCTAssertTrue(app.navigationBars["Routes"].waitForExistence(timeout: 10),
                      "A linked expense must open the screen that owns it")
        checkpoint("FIN-02-linked-expense")
    }

    /// The three groups and the Borrow action must stay reachable at the
    /// largest reading sizes.
    func testFinanceBreakdownAtAccessibilitySize() throws {
        let fixture = try writeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        launch(appearance: .light, arguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityL",
            "-AEUITestLoadSave", fixture.path,
        ])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        openTab("Finance")
        XCTAssertTrue(app.staticTexts["Operating performance"].waitForExistence(timeout: 10))
        let borrow = app.buttons["Borrow"]
        XCTAssertTrue(borrow.waitForExistence(timeout: 5))
        XCTAssertTrue(borrow.isHittable, "Borrow must stay reachable at large text")
        let commitments = app.staticTexts["Monthly commitments"]
        XCTAssertTrue(scrollUntil(commitments, "the monthly commitments group",
                                  swipes: 12))
        checkpoint("FIN-AX-groups")
    }
}
