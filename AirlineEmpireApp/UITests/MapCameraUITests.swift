import XCTest
import UIKit

/// Native camera interaction checks using an earned, paused campaign.
/// No purchase, distribution, or test-only camera control is involved.
final class MapCameraUITests: AEUITestCase {
    override var wantsSunriseWeek: Bool { false }
    private var map: XCUIElement { app.descendants(matching: .any)["ae-map-canvas"] }
    private var value: String { map.value as? String ?? "" }

    private func numbers(_ pattern: String) -> [Double] {
        let text = value
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return [] }
        return (1..<match.numberOfRanges).compactMap {
            Range(match.range(at: $0), in: text).flatMap { Double(text[$0]) }
        }
    }

    private func eventually(_ message: String, _ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 12), .completed,
                       "\(message). Map: \(value)")
    }

    private func assertFitted() {
        eventually("Every home/served airport must fit between the measured controls") {
            let counts = self.numbers(#"framed (\d+)/(\d+)"#)
            return counts.count == 2 && counts[1] > 0 && counts[0] == counts[1]
        }
        XCTAssertTrue(app.buttons["Frame my network"].isHittable)
        XCTAssertTrue(app.buttons["Zoom in"].isHittable)
        XCTAssertTrue(app.buttons["Zoom out"].isHittable)
    }

    private func openCampaign() throws {
        XCUIDevice.shared.orientation = .portrait
        let bundle = Bundle(for: MapCameraUITests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "store-campaign", withExtension: "json"))
        // The map always renders dark. Pin the app's test appearance instead
        // of opening simulator Settings while Xcode is launching the app.
        app.launchArguments.append(contentsOf: ["-AEUITestLoadSave", url.path,
                                                "-AEUITestProbes", "-AEUITestDarkAppearance"])
        app.launch()
        app.activate()
        XCTAssertNotNil(waitForTab("Home", timeout: 30))
        openTab("Home")
        XCTAssertTrue(map.waitForExistence(timeout: 15))
        assertFitted()
    }

    func testFitPanZoomAndFollowOnPortraitMap() throws {
        try openCampaign()
        checkpoint("MAP-01-portrait-network")
        let openingZoom = try XCTUnwrap(numbers(#"zoom ([0-9]+(?:\.[0-9]+)?)x"#).first)
        app.buttons["Zoom in"].tap()
        eventually("Zoom in must change the camera") {
            (self.numbers(#"zoom ([0-9]+(?:\.[0-9]+)?)x"#).first ?? 0) > openingZoom
        }
        app.buttons["Zoom out"].tap()
        Thread.sleep(forTimeInterval: 1)

        let before = numbers(#"camera ([0-9]+(?:\.[0-9]+)?) ([0-9]+(?:\.[0-9]+)?)"#)
        let clear = numbers(#"usable ([0-9]+(?:\.[0-9]+)?) ([0-9]+(?:\.[0-9]+)?) ([0-9]+(?:\.[0-9]+)?) ([0-9]+(?:\.[0-9]+)?)"#)
        XCTAssertEqual(clear.count, 4)
        let y = clear[1] + clear[3] / 2
        let origin = map.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: clear[0] + clear[2] * 0.7, dy: y))
        let end = origin.withOffset(CGVector(dx: clear[0] + clear[2] * 0.3, dy: y))
        start.press(forDuration: 0.1, thenDragTo: end)
        eventually("A drag must move the camera") {
            let after = self.numbers(#"camera ([0-9]+(?:\.[0-9]+)?) ([0-9]+(?:\.[0-9]+)?)"#)
            return after.count == 2 && before.count == 2 && abs(after[0] - before[0]) > 0.01
        }
        checkpoint("MAP-02-after-pan")
        app.buttons["Frame my network"].tap()
        assertFitted()

        let beforePinch = try XCTUnwrap(numbers(#"zoom ([0-9]+(?:\.[0-9]+)?)x"#).first)
        map.pinch(withScale: 1.5, velocity: 1)
        eventually("The actual pinch recognizer must zoom") {
            (self.numbers(#"zoom ([0-9]+(?:\.[0-9]+)?)x"#).first ?? 0) > beforePinch
        }
        let beforeDoubleTap = try XCTUnwrap(numbers(#"zoom ([0-9]+(?:\.[0-9]+)?)x"#).first)
        origin.withOffset(CGVector(dx: clear[0] + clear[2] / 2, dy: y)).doubleTap()
        eventually("Double tap must zoom") {
            (self.numbers(#"zoom ([0-9]+(?:\.[0-9]+)?)x"#).first ?? 0) > beforeDoubleTap
        }
        checkpoint("MAP-03-after-pinch-and-double-tap")
        app.buttons["Frame my network"].tap()
        assertFitted()

        let menu = app.buttons["ae-follow-flight-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let flight = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier != %@",
            "ae-follow-flight-", "ae-follow-flight-menu")).firstMatch
        XCTAssertTrue(flight.waitForExistence(timeout: 5))
        flight.tap()
        eventually("Following must hold the aircraft in the clear map region") {
            self.value.contains("following") && (self.numbers(#"focusError ([0-9]+(?:\.[0-9]+)?)"#).first ?? 999) < 2
        }
        let focusBefore = self.numbers(#"focus ([0-9]+(?:\.[0-9]+)?) ([0-9]+(?:\.[0-9]+)?)"#)
        app.buttons["Normal speed"].tap()
        eventually("Follow must track a moving aircraft, not just select one") {
            let focusAfter = self.numbers(#"focus ([0-9]+(?:\.[0-9]+)?) ([0-9]+(?:\.[0-9]+)?)"#)
            return focusBefore.count == 2 && focusAfter.count == 2
                && (abs(focusAfter[0] - focusBefore[0]) + abs(focusAfter[1] - focusBefore[1])) > 0.00002
                && (self.numbers(#"focusError ([0-9]+(?:\.[0-9]+)?)"#).first ?? 999) < 2
        }
        app.buttons["Pause"].tap()
        checkpoint("MAP-04-following")
        // Fit must win over follow, rather than immediately snapping back.
        app.buttons["Frame my network"].tap()
        eventually("Frame network must release follow") { !self.value.contains("following") }
        assertFitted()
        checkpoint("MAP-05-network-after-follow")
        menu.tap()
        XCTAssertTrue(flight.waitForExistence(timeout: 5))
        flight.tap()
        eventually("Follow can be started again") { self.value.contains("following") }
        let followClear = numbers(#"usable ([0-9]+(?:\.[0-9]+)?) ([0-9]+(?:\.[0-9]+)?) ([0-9]+(?:\.[0-9]+)?) ([0-9]+(?:\.[0-9]+)?)"#)
        XCTAssertEqual(followClear.count, 4)
        let followY = followClear[1] + followClear[3] / 2
        origin.withOffset(CGVector(dx: followClear[0] + followClear[2] * 0.7, dy: followY))
            .press(forDuration: 0.1, thenDragTo: origin.withOffset(
                CGVector(dx: followClear[0] + followClear[2] * 0.3, dy: followY)))
        eventually("Dragging must release follow") { !self.value.contains("following") }
        checkpoint("MAP-08-pan-releases-follow")
    }

    func testIPadRotationRefitsNetworkWithoutResettingManualPan() throws {
        try openCampaign()
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2)
        assertFitted()
        checkpoint("MAP-06-ipad-landscape")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 2)
        assertFitted()
        checkpoint("MAP-07-ipad-portrait")
        let origin = map.coordinate(withNormalizedOffset: .zero)
        let clear = numbers(#"usable ([0-9]+(?:\.[0-9]+)?) ([0-9]+(?:\.[0-9]+)?) ([0-9]+(?:\.[0-9]+)?) ([0-9]+(?:\.[0-9]+)?)"#)
        XCTAssertEqual(clear.count, 4)
        let y = clear[1] + clear[3] / 2
        origin.withOffset(CGVector(dx: clear[0] + clear[2] * 0.7, dy: y))
            .press(forDuration: 0.1, thenDragTo: origin.withOffset(
                CGVector(dx: clear[0] + clear[2] * 0.3, dy: y)))
        Thread.sleep(forTimeInterval: 1)
        let manual = numbers(#"camera ([0-9]+(?:\.[0-9]+)?) ([0-9]+(?:\.[0-9]+)?)"#)
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(numbers(#"camera ([0-9]+(?:\.[0-9]+)?) ([0-9]+(?:\.[0-9]+)?)"#), manual,
                       "Rotation must preserve a manually positioned camera")
        app.buttons["Frame my network"].tap()
        assertFitted()
    }
}
