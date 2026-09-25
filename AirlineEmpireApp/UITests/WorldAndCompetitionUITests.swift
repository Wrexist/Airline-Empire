import XCTest
import AirlineEmpireCore

/// The two World surfaces: events split into current and forecast with the
/// player's exposure, and competitors as a comparison of markets plus one
/// prioritised list of rival moves.
final class WorldAndCompetitionUITests: AEUITestCase {
    /// The retreat campaign (contested London–Paris, a recent rival retreat)
    /// with a storm on now and a boom forecast added.
    private func writeFixture() throws -> URL {
        let source = try XCTUnwrap(Bundle(for: WorldAndCompetitionUITests.self)
            .url(forResource: "rival-pressure-retreat", withExtension: "json"))
        var state = try JSONSaveCodec().decode(Data(contentsOf: source))
        let now = state.clock.now
        var storm = WorldEvent(id: 9001, kind: .storm(region: .europe),
            beginsAt: now + .days(-1), endsAt: now + .days(5), severity: 0.6)
        storm.hasStarted = true
        state.world.activeEvents.append(storm)
        state.world.activeEvents.append(WorldEvent(id: 9002,
            kind: .tourismBoom(region: .europe), beginsAt: now + .days(4),
            endsAt: now + .days(20), severity: 0.4))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("world-\(UUID().uuidString).aesave")
        try JSONSaveCodec().encode(state).write(to: url)
        return url
    }

    private func openWorldCard(_ title: String) -> Bool {
        openTab("World")
        let card = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", title)).firstMatch
        guard scrollUntil(card, "the \(title) card") else { return false }
        card.tap()
        return true
    }

    func testWorldEventsShowCurrentAndForecast() throws {
        let fixture = try writeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        launch(appearance: .dark, arguments: ["-AEUITestDarkAppearance",
                                              "-AEUITestLoadSave", fixture.path])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        XCTAssertTrue(openWorldCard("World events"))

        XCTAssertTrue(app.staticTexts["Your exposure"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Happening now"].exists,
                      "A started storm must sit under Happening now")
        XCTAssertTrue(app.staticTexts["Forecast"].exists,
                      "An unstarted boom must sit under Forecast")
        let exposed = app.descendants(matching: .any)
            .matching(identifier: "ae-event-exposed-route").firstMatch
        XCTAssertTrue(exposed.waitForExistence(timeout: 5),
                      "The player's own affected routes must be listed")
        checkpoint("EVENTS-01-now-forecast-exposure")
    }

    func testCompetitorsCompareRoutesAndPrioritiseMoves() throws {
        let fixture = try writeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        launch(appearance: .dark, arguments: ["-AEUITestDarkAppearance",
                                              "-AEUITestLoadSave", fixture.path])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        XCTAssertTrue(openWorldCard("Competitors"))

        XCTAssertTrue(app.staticTexts["Where you are fighting"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["What rivals did near you"].exists,
                      "Rival moves must lead the screen in one prioritised list")
        let contested = app.descendants(matching: .any)
            .matching(identifier: "ae-contested-route").firstMatch
        XCTAssertTrue(contested.waitForExistence(timeout: 5))
        checkpoint("COMP-01-comparison")

        let move = app.descendants(matching: .any)
            .matching(identifier: "ae-rival-move").firstMatch
        XCTAssertTrue(scrollUntil(move, "a rival move on the player's market"))
        XCTAssertTrue(move.isHittable, "A move on your market opens that route")
        checkpoint("COMP-02-moves")
    }

    /// The comparison and the move list must survive the largest text sizes.
    func testCompetitionAtAccessibilitySize() throws {
        let fixture = try writeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        launch(appearance: .light, arguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityL",
            "-AEUITestLoadSave", fixture.path,
        ])
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        XCTAssertTrue(openWorldCard("Competitors"))
        XCTAssertTrue(app.staticTexts["Where you are fighting"].waitForExistence(timeout: 10))
        let contested = app.descendants(matching: .any)
            .matching(identifier: "ae-contested-route").firstMatch
        XCTAssertTrue(scrollUntil(contested, "a contested market at large text", swipes: 12))
        XCTAssertTrue(contested.isHittable, "A contested market must stay tappable at large text")
        checkpoint("COMP-AX")
    }
}
