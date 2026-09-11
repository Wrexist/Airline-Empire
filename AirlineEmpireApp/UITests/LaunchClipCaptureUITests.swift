import XCTest

/// Real simulator footage from an earned campaign; never synthetic UI or balances.
final class LaunchClipCaptureUITests: AEUITestCase {
    override var wantsSunriseWeek: Bool { false }

    func testRecordLaunchClips() throws {
        let bundle = Bundle(for: LaunchClipCaptureUITests.self)
        let save = try XCTUnwrap(bundle.url(forResource: "store-campaign", withExtension: "json"))
        launch(appearance: .dark, arguments: ["-AEUITestLoadSave", save.path,
                                             "-AEUITestDarkAppearance"])
        guard let home = waitForTab("Home", timeout: 30), tapWhenReady(home) else { return }
        let normal = app.buttons["Normal speed"]
        guard require(normal, "the live simulation speed"), tapWhenReady(normal) else { return }
        hold("network")
        guard tapWhenReady(app.buttons["Pause"]) else { return }

        guard openAirlineSection("Fleet") else { return }
        hold("fleet")
        guard openAirlineSection("Routes") else { return }
        let route = app.descendants(matching: .any).matching(identifier: "ae-route-row").firstMatch
        guard require(route, "an earned route"), tapWhenReady(route) else { return }
        hold("route")

        openTab("Finance")
        hold("finance")
    }

    private func hold(_ name: String) {
        // Leave room for the cut to exclude navigation and transient system banners.
        Thread.sleep(forTimeInterval: 3)
        let banner = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .staticTexts["Ready for Apple Intelligence"]
        if banner.exists { banner.swipeUp(); Thread.sleep(forTimeInterval: 2) }
        print("AECLIP \(name) START \(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 16)
        capture("CLIP-" + name)
        print("AECLIP \(name) END \(Date().timeIntervalSince1970)")
    }
}
