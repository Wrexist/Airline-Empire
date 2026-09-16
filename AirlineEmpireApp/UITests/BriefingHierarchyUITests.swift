import XCTest
import AirlineEmpireCore

/// The briefing's decision hierarchy: what needs the player, how the airline
/// is doing, what to do next, then the history — in that order, with the
/// urgent rows linking to the thing they are about.
final class BriefingHierarchyUITests: AEUITestCase {
    /// A fleet with something in every rank.
    private func writeFixture() throws -> URL {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: ScenarioBootstrap.newGame(
            scenario: "founder", worldSeed: 42, startYear: 2030),
            systems: GamePipeline.standard(), catalog: catalog)
        XCTAssertEqual(engine.applyNow(FoundAirlineCommand(airlineName: "Pacifica briefing",
            kind: .player, homeAirport: "ARN", startingCash: .dollars(40_000_000))), .applied)
        let player = try XCTUnwrap(engine.state.playerAirline?.id)
        for _ in 0..<2 {
            XCTAssertEqual(engine.applyNow(LeaseAircraftCommand(
                lessee: player, type: "PA184", termMonths: 60)), .applied)
        }
        XCTAssertEqual(engine.applyNow(OpenRouteCommand(airline: player, origin: "ARN",
            destination: "CDG", dailyRoundTrips: 3, ticketPrice: .dollars(180))), .applied)
        let route = try XCTUnwrap(engine.state.routes(of: player).first)
        let ids = engine.state.fleet(of: player).map(\.id).sorted()
        XCTAssertEqual(engine.applyNow(AssignAircraftToRouteCommand(
            airline: player, route: route.id, aircraftID: ids[0])), .applied)
        XCTAssertEqual(engine.applyNow(OpenRouteCommand(airline: player, origin: "ARN",
            destination: "LHR", dailyRoundTrips: 2, ticketPrice: .dollars(150))), .applied)
        let ticksPerDay = Int(GameCalendar.minutesPerDay / engine.state.meta.tickMinutes)
        engine.advance(ticks: ticksPerDay * 40)

        var state = engine.state
        state.routes[route.id]?.economicsThisMonth.fuelCents = 900_000
        state.aircraft[ids[1]]?.status =
            .ordered(deliveryAt: state.clock.now + .days(20))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("briefing-\(UUID().uuidString).aesave")
        try JSONSaveCodec().encode(state).write(to: url)
        return url
    }

    func testBriefingHierarchyJourney() throws {
        let fixture = try writeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        launch(appearance: .dark, arguments: ["-AEUITestDarkAppearance",
                                              "-AEUITestLoadSave", fixture.path])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        XCTAssertTrue(openBriefing())

        // Urgent first, and it is there when something is wrong.
        let urgent = app.staticTexts["Needs you now"]
        XCTAssertTrue(scrollUntil(urgent, "the urgent section"))
        checkpoint("BRIEF-01-hierarchy")

        // The urgent row opens the aircraft it is about.
        let idle = app.buttons["ae-briefing-idle"]
        XCTAssertTrue(scrollUntil(idle, "the idle-aircraft alert"))
        idle.tap()
        XCTAssertTrue(app.buttons["Change Aircraft"].waitForExistence(timeout: 10),
                      "An urgent alert must open the thing it is about")
        checkpoint("BRIEF-02-linked-alert")
    }

    func testBriefingSectionsAreInDecisionOrder() throws {
        let fixture = try writeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        launch(appearance: .dark, arguments: ["-AEUITestDarkAppearance",
                                              "-AEUITestLoadSave", fixture.path])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        XCTAssertTrue(openBriefing())

        let urgent = app.staticTexts["Needs you now"]
        XCTAssertTrue(scrollUntil(urgent, "the urgent section"))
        let performance = app.staticTexts["How the airline is doing"]
        XCTAssertTrue(scrollUntil(performance, "the performance section", swipes: 12))
        assertBelow(performance, urgent, "Performance follows the urgent section")
        let opportunity = app.staticTexts["Next opportunity"]
        XCTAssertTrue(scrollUntil(opportunity, "the opportunity section", swipes: 16))
        assertBelow(opportunity, performance, "Opportunity follows performance")
        let history = app.staticTexts["The story so far"]
        XCTAssertTrue(scrollUntil(history, "the history section", swipes: 20))
        assertBelow(history, opportunity, "History follows opportunity")
        checkpoint("BRIEF-03-order")
    }

    /// The hierarchy must survive the largest reading sizes.
    func testBriefingAtAccessibilitySize() throws {
        let fixture = try writeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        launch(appearance: .light, arguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityL",
            "-AEUITestLoadSave", fixture.path,
        ])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        XCTAssertTrue(openBriefing())
        let urgent = app.staticTexts["Needs you now"]
        XCTAssertTrue(scrollUntil(urgent, "the urgent section at large text", swipes: 12))
        let idle = app.buttons["ae-briefing-idle"]
        XCTAssertTrue(scrollUntil(idle, "the idle alert at large text", swipes: 12))
        XCTAssertTrue(idle.isHittable, "An urgent alert must stay tappable at large text")
        checkpoint("BRIEF-AX-urgent")
    }
}
