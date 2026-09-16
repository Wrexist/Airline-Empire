import XCTest
import AirlineEmpireCore

/// The campaign screen: the chapter, what the next one asks for, the
/// commitments in flight, and the dated record of what has already been done.
final class CampaignProgressUITests: AEUITestCase {
    private func writeFixture() throws -> URL {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: ScenarioBootstrap.newGame(
            scenario: "founder", worldSeed: 42, startYear: 2030),
            systems: GamePipeline.standard(), catalog: catalog)
        XCTAssertEqual(engine.applyNow(FoundAirlineCommand(airlineName: "Pacifica campaign",
            kind: .player, homeAirport: "ARN", startingCash: .dollars(60_000_000))), .applied)
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
        engine.advance(ticks: ticksPerDay * 100)

        var state = engine.state
        let now = state.clock.now
        state.progression.era = .national
        state.progression.activePrograms = [CapabilityProgram(
            code: .fuelHedging, startedAt: now + .days(-30),
            completesAt: now + .days(60), cost: catalog.tuning.progression.capabilityCost)]
        state.progression.missions = [Mission(
            id: 99, sourceEventID: -1,
            kind: .boomRush(region: .europe, targetPassengers: 5_000),
            deadline: now + .days(20), reward: .dollars(500_000), baseline: 78_000)]
        state.progression.milestones = ["firstFlight", "firstOwnedAircraft"]
        state.progression.achievements = ["debtFree"]
        state.progression.record = [
            ProgressionMoment(at: now + .days(-100), kind: .milestone("firstFlight")),
            ProgressionMoment(at: now + .days(-60), kind: .milestone("firstOwnedAircraft")),
            ProgressionMoment(at: now + .days(-41), kind: .eraAdvanced(.regional)),
            ProgressionMoment(at: now + .days(-40), kind: .eraAdvanced(.national)),
            ProgressionMoment(at: now + .days(-30), kind: .achievement("debtFree")),
            ProgressionMoment(at: now + .days(-10),
                              kind: .mission(.flightContract(targetFlights: 20),
                                             reward: .dollars(30_000))),
        ]

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("campaign-\(UUID().uuidString).aesave")
        try JSONSaveCodec().encode(state).write(to: url)
        return url
    }

    func testCampaignProgressJourney() throws {
        let fixture = try writeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        launch(appearance: .dark, arguments: ["-AEUITestDarkAppearance",
                                              "-AEUITestLoadSave", fixture.path])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        XCTAssertTrue(openProgression())

        // The chapter, alive: the era, what the next asks for and opens.
        XCTAssertTrue(app.staticTexts["Next chapter"].exists)
        XCTAssertTrue(app.staticTexts["Active commitments"].exists)
        XCTAssertTrue(app.staticTexts["Campaign log"].exists)
        XCTAssertTrue(app.staticTexts["Honours"].exists)
        checkpoint("CAMPAIGN-01-chapter")

        // A running programme and a running commitment are both visible.
        XCTAssertTrue(app.staticTexts["under way"].exists,
                      "A running capability programme must show as under way")
        XCTAssertTrue(app.staticTexts["1 running"].exists,
                      "The commitments group must count what is running")

        // The record is discoverable and dated, rather than feed-only.
        let earned = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Earned ")).firstMatch
        XCTAssertTrue(scrollUntil(earned, "a dated honour in the record"))
        checkpoint("CAMPAIGN-02-record")
    }

    /// The chapter, the commitments and the log must all survive the largest
    /// reading sizes.
    func testCampaignProgressAtAccessibilitySize() throws {
        let fixture = try writeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        launch(appearance: .light, arguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityL",
            "-AEUITestLoadSave", fixture.path,
        ])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        XCTAssertTrue(openProgression())
        let era = app.staticTexts["ae-progression-era"]
        XCTAssertTrue(era.waitForExistence(timeout: 5))
        XCTAssertTrue(era.isHittable, "The era must stay readable at large text")
        let log = app.staticTexts["Campaign log"]
        XCTAssertTrue(scrollUntil(log, "the campaign log at large text", swipes: 12))
        checkpoint("CAMPAIGN-AX-record")
    }
}
