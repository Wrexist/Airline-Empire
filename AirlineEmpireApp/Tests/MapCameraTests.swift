import XCTest
import SwiftUI
import AirlineEmpireCore
@testable import AirlineEmpire

final class MapCameraTests: XCTestCase {
    private let phone = MapViewport(size: CGSize(width: 393, height: 852), top: 190, bottom: 220)
    private let regional = [CGPoint(x: 0.49, y: 0.16), CGPoint(x: 0.71, y: 0.34),
                            CGPoint(x: 0.52, y: 0.27)]

    private func assertFit(_ points: [CGPoint], in viewport: MapViewport,
                           file: StaticString = #filePath, line: UInt = #line) {
        let camera = MapCamera()
        camera.viewport = viewport
        camera.frame(points: points, animated: false)
        let projector = MapProjector(zoom: camera.liveZoom,
            center: camera.liveCenter(size: viewport.size), size: viewport.size)
        for point in points {
            let screen = projector.project(MapPoint(x: Double(point.x), y: Double(point.y)))
            XCTAssertTrue(viewport.usable.insetBy(dx: -1, dy: -1).contains(screen),
                          "Airport \(point) projects to \(screen), outside \(viewport.usable)", file: file, line: line)
        }
    }

    func testRegionalGlobalAndSeparatedAirportsFitPhoneAndBothIPadOrientations() {
        let networks = [regional,
            [CGPoint(x: 0.03, y: 0.20), CGPoint(x: 0.96, y: 0.73), CGPoint(x: 0.5, y: 0.14)],
            [CGPoint(x: 0.12, y: 0.3), CGPoint(x: 0.88, y: 0.58)],
            [CGPoint(x: 0.55, y: 0.16)]]
        let viewports = [phone,
            MapViewport(size: CGSize(width: 1024, height: 1366), top: 190, bottom: 250),
            MapViewport(size: CGSize(width: 1366, height: 1024), top: 190, bottom: 250)]
        for viewport in viewports { for points in networks { assertFit(points, in: viewport) } }
    }

    func testPortraitUsesLatitudePixelsAndCentersAboveTheBottomPanel() {
        let fit = phone.fit(points: regional)
        // Old latitude formula returned 2.22x for this network, leaving the
        // geographic band stranded in the lower half of a tall screen.
        XCTAssertGreaterThan(fit.zoom, 3.5)
        let projector = MapProjector(zoom: fit.zoom, center: fit.center, size: phone.size)
        let midpoint = projector.project(MapPoint(x: 0.60, y: 0.25))
        XCTAssertEqual(midpoint.x, phone.usable.midX, accuracy: 0.001)
        XCTAssertEqual(midpoint.y, phone.usable.midY, accuracy: 0.001)
    }

    func testSingleAirportKeepsRegionalContextAndEmptyNetworkIsFinite() {
        let single = phone.fit(points: [CGPoint(x: 0.55, y: 0.17)])
        XCTAssertLessThan(single.zoom, MapCamera.maxZoom)
        XCTAssertGreaterThan(single.zoom, 5)
        let empty = phone.fit(points: [])
        XCTAssertTrue(empty.center.x.isFinite && empty.center.y.isFinite && empty.zoom.isFinite)
    }

    func testSlowPanDoesNotAddMomentumAndLeavesFitMode() {
        let camera = MapCamera()
        camera.viewport = phone
        camera.frame(points: regional, animated: false)
        let before = camera.center, zoom = camera.zoom
        let translation = CGSize(width: 35, height: 24)
        camera.commitPan(size: phone.size, translation: translation, predicted: translation)
        XCTAssertEqual(camera.center.x, before.x - 35 / (phone.size.width * zoom), accuracy: 0.00001)
        XCTAssertEqual(camera.center.y, before.y - 48 / (phone.size.width * zoom), accuracy: 0.00001)
        XCTAssertFalse(camera.isNetworkFramed)
        XCTAssertFalse(camera.isMoving)
    }

    func testPinchKeepsTheWorldPointUnderTheFingers() {
        let camera = MapCamera()
        camera.viewport = phone
        camera.frame(points: regional, animated: false)
        let anchor = CGPoint(x: 150, y: 390)
        let before = MapProjector(zoom: camera.zoom, center: camera.center, size: phone.size).unproject(anchor)
        camera.beginPinch(at: anchor, size: phone.size)
        camera.pinch = 1.6
        camera.commitZoom(size: phone.size)
        let after = MapProjector(zoom: camera.zoom, center: camera.center, size: phone.size).unproject(anchor)
        XCTAssertEqual(before.x, after.x, accuracy: 0.00001)
        XCTAssertEqual(before.y, after.y, accuracy: 0.00001)
        XCTAssertFalse(camera.isNetworkFramed)
    }

    func testDoubleTapAndZoomLimitsRespectReducedMotion() {
        let camera = MapCamera()
        camera.prefersReducedMotion = true
        camera.viewport = phone
        camera.frame(points: regional, animated: false)
        let anchor = CGPoint(x: 150, y: 390)
        let before = MapProjector(zoom: camera.zoom, center: camera.center, size: phone.size).unproject(anchor)
        camera.zoomIn(about: anchor, size: phone.size)
        let after = MapProjector(zoom: camera.zoom, center: camera.center, size: phone.size).unproject(anchor)
        XCTAssertEqual(before.x, after.x, accuracy: 0.00001)
        XCTAssertEqual(before.y, after.y, accuracy: 0.00001)
        camera.zoomBy(100)
        XCTAssertEqual(camera.zoom, MapCamera.maxZoom)
        camera.zoomBy(0.0001)
        XCTAssertEqual(camera.zoom, MapCamera.minZoom)
        XCTAssertFalse(camera.isMoving)
    }

    func testFollowUsesClearRegionAndReleasesWithoutJumping() {
        let camera = MapCamera()
        camera.prefersReducedMotion = true
        camera.viewport = phone
        camera.beginFollow(FlightID(raw: 1))
        for point in [CGPoint(x: 0.5, y: 0.3), CGPoint(x: 0.6, y: 0.35)] {
            let center = camera.liveCenter(size: phone.size, at: Date(), focus: point)
            let projected = MapProjector(zoom: camera.zoom, center: center, size: phone.size)
                .project(MapPoint(x: Double(point.x), y: Double(point.y)))
            XCTAssertEqual(projected.x, phone.usable.midX, accuracy: 0.001)
            XCTAssertEqual(projected.y, phone.usable.midY, accuracy: 0.001)
        }
        let last = CGPoint(x: 0.6, y: 0.35)
        let before = camera.liveCenter(size: phone.size, at: Date(), focus: last)
        camera.stopFollowing(landingAt: last)
        XCTAssertNil(camera.followed)
        XCTAssertEqual(camera.liveCenter(size: phone.size).x, before.x, accuracy: 0.001)
        XCTAssertEqual(camera.liveCenter(size: phone.size).y, before.y, accuracy: 0.001)
    }

    func testFrameNetworkReleasesFollowAndClearsTransientGestures() {
        let camera = MapCamera()
        camera.prefersReducedMotion = true
        camera.viewport = phone
        camera.beginFollow(FlightID(raw: 1))
        camera.panOffset = CGSize(width: 20, height: 20)
        camera.pinch = 1.2
        camera.frame(points: regional)
        XCTAssertNil(camera.followed)
        XCTAssertEqual(camera.panOffset, .zero)
        XCTAssertEqual(camera.pinch, 1)
        XCTAssertTrue(camera.isNetworkFramed)
        XCTAssertFalse(camera.isMoving)
    }
}
