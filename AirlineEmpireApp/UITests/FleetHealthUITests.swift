import XCTest
import AirlineEmpireCore

/// The fleet health board: it names the aircraft that want a decision, keeps
/// the ones that cannot fly separate, and every row still opens the aircraft's
/// own actions.
final class FleetHealthUITests: AEUITestCase {
    /// Eight leased narrowbodies on one route, staged so the board has one of
    /// each state: idle, lease ending, low condition, in a check, on order.
    private func writeFixture() throws -> URL {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: ScenarioBootstrap.newGame(
            scenario: "founder", worldSeed: 42, startYear: 2030),
            systems: GamePipeline.standard(), catalog: catalog)
        XCTAssertEqual(engine.applyNow(FoundAirlineCommand(airlineName: "Pacifica fleet",
            kind: .player, homeAirport: "ARN", startingCash: .dollars(40_000_000))), .applied)
        let player = try XCTUnwrap(engine.state.playerAirline?.id)
        for _ in 0..<8 {
            XCTAssertEqual(engine.applyNow(LeaseAircraftCommand(
                lessee: player, type: "PA184", termMonths: 60)), .applied)
        }
        XCTAssertEqual(engine.applyNow(OpenRouteCommand(airline: player, origin: "ARN",
            destination: "CDG", dailyRoundTrips: 3, ticketPrice: .dollars(180))), .applied)
        let route = try XCTUnwrap(engine.state.routes(of: player).first)
        let ids = engine.state.fleet(of: player).map(\.id).sorted()
        for id in ids.prefix(4) {
            XCTAssertEqual(engine.applyNow(AssignAircraftToRouteCommand(
                airline: player, route: route.id, aircraftID: id)), .applied)
        }
        let ticksPerDay = Int(GameCalendar.minutesPerDay / engine.state.meta.tickMinutes)
        engine.advance(ticks: ticksPerDay * 20)

        var state = engine.state
        state.aircraft[ids[4]]?.ownership = .leased(
            monthlyRate: .dollars(500_000), termMonthsRemaining: 2)
        state.aircraft[ids[5]]?.status = .inMaintenance(until: state.clock.now + .days(4))
        state.aircraft[ids[6]]?.condition = 0.77
        state.aircraft[ids[7]]?.status = .ordered(deliveryAt: state.clock.now + .days(30))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fleet-health-\(UUID().uuidString).aesave")
        try JSONSaveCodec().encode(state).write(to: url)
        return url
    }

    func testFleetHealthBoardJourney() throws {
        let fixture = try writeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        launch(appearance: .dark, arguments: ["-AEUITestDarkAppearance",
                                              "-AEUITestLoadSave", fixture.path])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        XCTAssertTrue(openAirlineSection("Fleet"))

        let board = app.descendants(matching: .any)
            .matching(identifier: "ae-fleet-health").firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 10))
        checkpoint("FLEET-01-board")

        // A decision is separated from something the player cannot fly.
        XCTAssertTrue(app.staticTexts["NEEDS A DECISION"].exists,
                      "The board must group the actionable aircraft")
        XCTAssertTrue(app.staticTexts["UNAVAILABLE"].exists,
                      "The board must keep what cannot fly separate")

        // Every board row is a real destination: the idle aircraft's screen.
        let row = app.descendants(matching: .any)
            .matching(identifier: "ae-fleet-health-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let frame = row.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        XCTAssertTrue(app.buttons["Change Aircraft"].waitForExistence(timeout: 10),
                      "A board row must open that aircraft's own screen")
        checkpoint("FLEET-02-aircraft")

        // The board did not displace the filter it sits beside. The back
        // control by name: `firstMatch` on this bar is the time button.
        let back = app.navigationBars.buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        let filter = app.buttons["ae-fleet-status-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(filter.frame.height, 60)
        guard tapWhenReady(filter) else { return }
        let idle = app.buttons["ae-fleet-status-idle"]
        XCTAssertTrue(idle.waitForExistence(timeout: 5))
        idle.tap()
        XCTAssertEqual(filter.value as? String, "Idle")
        checkpoint("FLEET-03-filter-idle")
        let reset = app.buttons["ae-fleet-reset-filters"]
        if reset.waitForExistence(timeout: 5) { reset.tap() }
    }

    /// The board and the filter must both survive the largest text sizes.
    func testFleetBoardAtAccessibilitySize() throws {
        let fixture = try writeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        launch(appearance: .light, arguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityL",
            "-AEUITestLoadSave", fixture.path,
        ])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        XCTAssertTrue(openAirlineSection("Fleet"))
        let board = app.descendants(matching: .any)
            .matching(identifier: "ae-fleet-health").firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 10))
        checkpoint("FLEET-AX-board")
        let row = app.descendants(matching: .any)
            .matching(identifier: "ae-fleet-health-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable, "A board row must stay tappable at large text")
        let filter = app.buttons["ae-fleet-status-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        XCTAssertTrue(filter.isHittable, "The fleet filter must stay reachable at large text")
        checkpoint("FLEET-AX-reachable")
    }
}
