import XCTest

/// The comparison workflow copies this identical harness into both revisions.
/// All measurements use the same earned campaign and simulator, sequentially.
/// Clock measurements include XCTest gesture overhead; they are not frame times.
final class ReleasePerformanceUITests: AEUITestCase {
    override var wantsSunriseWeek: Bool { false }

    private func campaign() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "rival-pressure-late-game", withExtension: "json"))
        app.launchArguments += ["-AEUITestLoadSave", url.path, "-AEUITestDarkAppearance"]
        app.launch()
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        openTab("Home")
    }

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }

    func testCampaignLaunch() throws {
        try campaign()
        app.terminate()
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            app.launch()
        }
    }

    func testMapPanAndZoom() throws {
        try campaign()
        let map = app.descendants(matching: .any)["ae-map-canvas"]
        XCTAssertTrue(map.waitForExistence(timeout: 15))
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app),
                          XCTMemoryMetric(application: app)], options: options) {
            let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.45))
            let end = map.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45))
            start.press(forDuration: 0.05, thenDragTo: end)
            end.press(forDuration: 0.05, thenDragTo: start)
            app.buttons["Zoom in"].tap()
            app.buttons["Zoom out"].tap()
        }
    }

    func testFleetScroll() throws {
        try campaign()
        openTab("Airline")
        app.buttons["Fleet"].tap()
        measureScroll()
    }

    func testMarketScroll() throws {
        try campaign()
        openTab("Airline")
        app.buttons["Fleet"].tap()
        let acquire = app.buttons["Acquire"]
        guard require(acquire, "Acquire"), tapWhenReady(acquire) else { return }
        measureScroll()
    }

    private func measureScroll() {
        let scroll = app.collectionViews.firstMatch.exists
            ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric,
                          XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            scroll.swipeUp()
            scroll.swipeUp()
            scroll.swipeDown()
            scroll.swipeDown()
        }
    }

    func testFastSimulationAndBackgroundRecovery() throws {
        try campaign()
        app.buttons["Sixteen times speed"].tap()
        let sustain = XCTMeasureOptions()
        sustain.iterationCount = 3
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: sustain) {
            Thread.sleep(forTimeInterval: 20)
        }
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        XCTAssertNotNil(waitForTab("Home", timeout: 15))
        XCTAssertTrue(app.buttons["Pause"].isHittable)
        checkpoint("PERF-background-recovery")
    }
}
