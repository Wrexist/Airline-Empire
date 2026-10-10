import XCTest
import UIKit
import AirlineEmpireCore

/// Captures the 3D Hub View in each of the reference clip's shots
/// (docs/HUB_VIEW_3D.md §1) from an earned campaign, so the render can be
/// compared frame for frame with the reference. Both in landscape: the
/// reference's aspect on iPad, and the hub holds an iPhone on its side.
final class HubViewUITests: AEUITestCase {
    override var wantsSunriseWeek: Bool { false }

    private func open(extra: [String] = []) throws {
        let bundle = Bundle(for: HubViewUITests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "store-campaign", withExtension: "json"))
        // Held at boarding: the reference's gate shot is the boarding moment
        // (queue, tug at the nose, passengers on the walkway).
        app.launchArguments.append(contentsOf: ["-AEUITestLoadSave", url.path, "-AEUITestProbes",
                                                "-AEUITestOpenHub", "-AEUITestHubStage", "boarding"] + extra)
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        app.activate()
        require(app.descendants(matching: .any)["ae-hub-scene"], "hub scene", timeout: 90)
        require(app.descendants(matching: .any)["ae-hub-timeline"], "turnaround timeline", timeout: 20)
        // Let geometry upload and the camera settle.
        Thread.sleep(forTimeInterval: 6)
    }

    /// The whole screen, in the orientation the player sees. `app.screenshot()`
    /// returns a landscape iPad cropped into a portrait buffer.
    private func frame(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = Self.logPrefix + name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func shot(_ name: String, _ id: String) {
        let button = app.buttons["ae-hub-shot-\(id)"]
        require(button, "shot button \(id)")
        button.tap()
        Thread.sleep(forTimeInterval: 4)
        frame(name)
    }

    func testHubShotsMatchTheReference() throws {
        try open()
        frame("HUB-01-overview")
        XCTAssertTrue(app.descendants(matching: .any)["ae-hub-kpis"].exists)
        shot("HUB-02-gate", "gate")
        shot("HUB-03-terminal", "terminal")
        shot("HUB-04-district", "district")
        let night = app.buttons["ae-hub-night"]
        require(night, "night toggle")
        night.tap()
        Thread.sleep(forTimeInterval: 3)
        frame("HUB-05-district-night")
        shot("HUB-06-overview-night", "overview")
        // The insights panel over the night overview: movements, alerts.
        let insights = app.buttons["ae-hub-insights"]
        require(insights, "insights button")
        insights.tap()
        Thread.sleep(forTimeInterval: 2)
        frame("HUB-07-insights")
        XCTAssertTrue(app.descendants(matching: .any)["ae-hub-insights-panel"].exists)
        // The routes page: each route's load factor, trips and profit.
        let routes = app.buttons["Routes"]
        if routes.exists {
            routes.tap()
            Thread.sleep(forTimeInterval: 1.5)
            frame("HUB-08-insights-routes")
        }
        // Upgrading from the hub, in daylight: the lounge site's tag on the
        // terminal roof opens the upgrade card and flies to the site. One
        // tap on the world, as a player would; the Insights › Airline row
        // is the fallback.
        insights.tap()
        Thread.sleep(forTimeInterval: 1)
        let daylight = app.buttons["ae-hub-daylight"]
        if daylight.exists {
            daylight.tap()
            Thread.sleep(forTimeInterval: 2)
        }
        let site = app.descendants(matching: .any)["ae-hub-site-lounge"]
        if site.waitForExistence(timeout: 5) {
            site.tap()
        } else {
            insights.tap()
            Thread.sleep(forTimeInterval: 1)
            app.buttons["Airline"].tap()
            Thread.sleep(forTimeInterval: 1)
            let lounge = app.buttons["ae-hub-facility-lounge"]
            require(lounge, "lounge row")
            lounge.tap()
        }
        Thread.sleep(forTimeInterval: 3)
        frame("HUB-09-upgrade")
        XCTAssertTrue(app.descendants(matching: .any)["ae-hub-upgrade-card"].exists)
        // Order it (two taps: arm, confirm): the works go up on the site and
        // the card follows them until it opens, days later.
        var build = app.buttons["ae-hub-upgrade-build"]
        if !build.exists {
            build = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Build'")).firstMatch
        }
        if build.exists && build.isEnabled {
            build.tap()
            Thread.sleep(forTimeInterval: 0.6)
            build.tap()
            Thread.sleep(forTimeInterval: 2.2)
            frame("HUB-10-ordered")
            Thread.sleep(forTimeInterval: 5)
            frame("HUB-11-works")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// Buildings take game days (docs/HUB_PROGRESSION_PLAN.md): a Regional
    /// era hub mid-build shows every stage of the works at once, the lounge's
    /// opening plays as a ceremony, and the hangar's card follows its build.
    func testHubBuildingsGoUpOverTime() throws {
        let bundle = Bundle(for: HubViewUITests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "store-campaign", withExtension: "json"))
        let codec = JSONSaveCodec()
        var state = try codec.decode(Data(contentsOf: url))
        var player = try XCTUnwrap(state.playerAirline)
        let home = player.homeAirport
        let day = state.clock.now.dayIndex * GameCalendar.minutesPerDay
        func works(_ service: AirportService, to level: Int, progress: Double, days: Int64) -> FacilityConstruction {
            let started = day - Int64(Double(days) * progress) * GameCalendar.minutesPerDay
            return FacilityConstruction(airport: home, service: service, level: level, fromLevel: level - 1,
                                        startedAt: SimTime(rawMinutes: started),
                                        completesAt: SimTime(rawMinutes: started + days * GameCalendar.minutesPerDay),
                                        cost: .zero)
        }
        state.progression.era = .regional
        player.airportFacilities = [home: AirportFacilities(lounge: 1, groundServices: 0)]
        player.facilityConstructions = [
            works(.lounge, to: 2, progress: 0.6, days: 14),      // crane over the roof
            works(.ground, to: 1, progress: 0.1, days: 7),       // hoarding
            works(.hangar, to: 1, progress: 0.35, days: 30),     // groundworks
            works(.crewBase, to: 1, progress: 0.85, days: 21),   // cladding
        ]
        state.airlines[player.id] = player
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("hub-buildings.aesave")
        try codec.encode(state).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }

        app.launchArguments.append(contentsOf: ["-AEUITestLoadSave", fixture.path, "-AEUITestProbes",
                                                "-AEUITestOpenHub", "-AEUITestHubCeremony", "lounge"])
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        app.activate()
        require(app.descendants(matching: .any)["ae-hub-scene"], "hub scene", timeout: 90)
        // The lounge's opening: the camera flies to it, it rises, the toast.
        require(app.descendants(matching: .any)["ae-hub-toast"], "opening toast", timeout: 40)
        Thread.sleep(forTimeInterval: 1.4)
        frame("HUB-12-ceremony")
        Thread.sleep(forTimeInterval: 5)
        frame("HUB-13-opened")
        XCTAssertTrue(app.descendants(matching: .any)["ae-hub-upgrade-progress"].exists)
        // Every stage of the works from the overview.
        let close = app.buttons["Close upgrade"]
        if close.exists { close.tap() }
        Thread.sleep(forTimeInterval: 1)
        shot("HUB-14-works", "overview")
        // The status and the hub's story in Insights › Airline, then the
        // hangar's card from its row: its stage, progress and opening day.
        let insights = app.buttons["ae-hub-insights"]
        require(insights, "insights button")
        insights.tap()
        Thread.sleep(forTimeInterval: 1)
        let airline = app.buttons["Airline"]
        require(airline, "Airline tab")
        airline.tap()
        Thread.sleep(forTimeInterval: 1.5)
        frame("HUB-15-status")
        XCTAssertTrue(app.descendants(matching: .any)["ae-hub-status"].exists)
        let hangar = app.buttons["ae-hub-facility-hangar"]
        for _ in 0..<3 where !hangar.isHittable { app.descendants(matching: .any)["ae-hub-insights-panel"].swipeUp() }
        if hangar.waitForExistence(timeout: 5) {
            hangar.tap()
            Thread.sleep(forTimeInterval: 3)
            frame("HUB-16-hangar-works")
            XCTAssertTrue(app.descendants(matching: .any)["ae-hub-upgrade-progress"].exists)
        }
        XCUIDevice.shared.orientation = .portrait
    }

    func testCloseReturnsToTheMap() throws {
        try open()
        let close = app.buttons["ae-hub-close"]
        require(close, "close button")
        close.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ae-hub-scene"].waitForNonExistence(timeout: 10))
        XCUIDevice.shared.orientation = .portrait
    }
}
