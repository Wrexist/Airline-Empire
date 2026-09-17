import XCTest
import AirlineEmpireCore

/// The aircraft market as a comparison: for one route, the era's airframes
/// ranked on what each would keep with the route, its fare and its frequency
/// held still — and every candidate a way into its own purchase terms.
final class AircraftMarketUITests: AEUITestCase {
    /// A player at ARN with one leased PA184 flying ARN–LHR 2×/day, seven
    /// days on so the route has demand of its own to compare against.
    private func writeFixture() throws -> URL {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: ScenarioBootstrap.newGame(
            scenario: "founder", worldSeed: 42, startYear: 2030),
            systems: GamePipeline.standard(), catalog: catalog)
        XCTAssertEqual(engine.applyNow(FoundAirlineCommand(airlineName: "Pacifica market",
            kind: .player, homeAirport: "ARN", startingCash: .dollars(60_000_000))), .applied)
        let player = try XCTUnwrap(engine.state.playerAirline?.id)
        XCTAssertEqual(engine.applyNow(LeaseAircraftCommand(
            lessee: player, type: "PA184", termMonths: 60)), .applied)
        XCTAssertEqual(engine.applyNow(OpenRouteCommand(airline: player, origin: "ARN",
            destination: "LHR", dailyRoundTrips: 2, ticketPrice: .dollars(160))), .applied)
        let route = try XCTUnwrap(engine.state.routes(of: player).first)
        let aircraft = try XCTUnwrap(engine.state.fleet(of: player).first)
        XCTAssertEqual(engine.applyNow(AssignAircraftToRouteCommand(
            airline: player, route: route.id, aircraftID: aircraft.id)), .applied)
        let ticksPerDay = Int(GameCalendar.minutesPerDay / engine.state.meta.tickMinutes)
        engine.advance(ticks: ticksPerDay * 7)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aircraft-market-\(UUID().uuidString).aesave")
        try JSONSaveCodec().encode(engine.state).write(to: url)
        return url
    }

    /// The market's one route-aware entry: opened from a route, it arrives
    /// with that route compared. Reached the way a player reaches it.
    private func openRouteMarket() -> Bool {
        guard openAirlineSection("Routes") else { return false }
        let row = app.descendants(matching: .any)
            .matching(identifier: "ae-route-row").firstMatch
        guard scrollUntil(row, "the route row") else { return false }
        row.tap()
        let find = app.buttons["ae-route-find-aircraft"]
        guard scrollUntil(find, "the route's aircraft market") else { return false }
        find.tap()
        return app.staticTexts["Aircraft market"].waitForExistence(timeout: 10)
    }

    func testAircraftMarketComparesOneRoute() throws {
        let fixture = try writeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        launch(appearance: .dark, arguments: ["-AEUITestDarkAppearance",
                                              "-AEUITestLoadSave", fixture.path])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        XCTAssertTrue(openRouteMarket())

        let panel = app.descendants(matching: .any)
            .matching(identifier: "ae-aircraft-comparison").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10),
                      "A selected route must be compared")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Compare on ")).firstMatch.exists,
                      "The comparison must name the route it is for")
        let rows = app.descendants(matching: .any)
            .matching(identifier: "ae-aircraft-comparison-row")
        XCTAssertGreaterThanOrEqual(rows.count, 2,
                                    "A comparison needs more than one candidate")
        checkpoint("MARKET-01-comparison")

        // The shortlist is a way in, not a second catalogue: a candidate
        // scrolls the list to its own deal terms and commit.
        let candidate = rows.element(boundBy: 0)
        XCTAssertTrue(candidate.isHittable, "A candidate must be tappable")
        candidate.tap()
        XCTAssertTrue(app.buttons["ae-market-lease"].waitForExistence(timeout: 10),
                      "A candidate must open that aircraft's purchase terms")
        checkpoint("MARKET-02-terms")
    }

    /// The comparison has to survive the largest text sizes too.
    func testAircraftMarketComparisonAtAccessibilitySize() throws {
        let fixture = try writeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        launch(appearance: .light, arguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityL",
            "-AEUITestLoadSave", fixture.path,
        ])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        XCTAssertTrue(openRouteMarket())
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Compare on ")).firstMatch
            .waitForExistence(timeout: 10))
        let rows = app.descendants(matching: .any)
            .matching(identifier: "ae-aircraft-comparison-row")
        XCTAssertGreaterThanOrEqual(rows.count, 2)
        let candidate = rows.element(boundBy: 0)
        XCTAssertTrue(scrollUntil(candidate, "a candidate at large text", swipes: 12))
        XCTAssertTrue(candidate.isHittable,
                      "A candidate must stay tappable at large text")
        checkpoint("MARKET-AX")
    }
}
