import XCTest
import SwiftUI
import UIKit
import AirlineEmpireCore
@testable import AirlineEmpire

/// Native hosted layout evidence. These are labelled component viewports,
/// not device screenshots or proof that an OS accessibility setting was toggled.
final class AccessibilitySurfaceReviewTests: XCTestCase {
    @MainActor
    private func waitForGame(_ controller: GameController) async throws {
        for _ in 0..<500 {
            if controller.snapshot?.playerAirline != nil {
                controller.setPumping(false)
                controller.setSpeed(.paused)
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Review campaign did not load")
    }

    @MainActor
    private func capture<V: View>(_ view: V, name: String, controller: GameController,
                                  width: CGFloat, dark: Bool, typeSize: DynamicTypeSize = .accessibility3,
                                  height: CGFloat = 812) async throws {
        let content = view
            .environment(controller)
            .environment(Entitlements(arguments: ["-AEUITestFree"]))
            .environment(\.dynamicTypeSize, typeSize)
            .environment(\.legibilityWeight, .bold)
            .environment(\.colorScheme, dark ? .dark : .light)
            .preferredColorScheme(dark ? .dark : .light)
        let host = UIHostingController(rootView: content)
        host.traitOverrides.accessibilityContrast = .high
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(1000))
        let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds)
        var drawn = false
        let image = renderer.image { _ in
            drawn = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(drawn, "Native view hierarchy must render before capture")
        let attachment = XCTAttachment(image: image)
        attachment.name = "AX-COMPONENT-\(name)-\(Int(width))pt-\(dark ? "dark" : "light")"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
        window.rootViewController = nil
    }

    @MainActor
    func testFreshSecondaryLayoutsWithAccessibilityEnvironment() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = GameController(savesDirectory: root)
        controller.startNewGame(airlineName: "Fresh review", home: "ARN", seed: 42, scenario: "founder")
        try await waitForGame(controller)
        defer { controller.setPumping(false) }
        for dark in [false, true] {
            for width in [CGFloat(375), CGFloat(507)] {
                try await capture(FinanceView(), name: "finance", controller: controller, width: width, dark: dark)
                try await capture(LoanSheet(), name: "borrow", controller: controller, width: width, dark: dark)
                try await capture(NavigationStack { SettingsView() }, name: "settings", controller: controller, width: width, dark: dark)
                try await capture(NavigationStack { WorldEventsView() }, name: "world-events", controller: controller, width: width, dark: dark)
                try await capture(NavigationStack { ReputationDetailView() }, name: "reputation", controller: controller, width: width, dark: dark)
            }
        }
    }

    @MainActor
    func testEarnedCollapseAndRecoveryWithAccessibleText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try ContentCatalog.loadBundled()
        // A deliberately underfunded test scenario. The actual lease charges,
        // insolvency, administration and collapse all come from the engine.
        let engine = SimulationEngine(state: ScenarioBootstrap.newGame(
            scenario: "founder", worldSeed: 42, startYear: 2030),
            systems: GamePipeline.standard(), catalog: catalog)
        XCTAssertEqual(engine.applyNow(FoundAirlineCommand(airlineName: "Overextended",
            kind: .player, homeAirport: "ARN", startingCash: .dollars(3_000_000))), .applied)
        let player = try XCTUnwrap(engine.state.playerAirline?.id)
        for _ in 0..<3 {
            XCTAssertEqual(engine.applyNow(LeaseAircraftCommand(lessee: player,
                type: "MR180", termMonths: 60)), .applied)
        }
        engine.advance(ticks: 96 * 365 * 3)
        XCTAssertTrue(engine.state.progression.gameOver, "The simulation must actually collapse the airline")
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        try manager.save(engine.state, slot: "collapse-review")
        let controller = GameController(savesDirectory: root)
        controller.loadGame(slot: "collapse-review")
        try await waitForGame(controller)
        XCTAssertTrue(controller.snapshot?.progression.gameOver == true)
        try await capture(GameOverView(), name: "earned-collapse", controller: controller, width: 375, dark: true)
        controller.quitToMenu()
        XCTAssertFalse(controller.hasGame)
        XCTAssertEqual(controller.availableSlots().count, 1, "Returning to the menu must retain the old campaign")
        try await capture(NewGameView(), name: "recovery-menu", controller: controller, width: 375, dark: true)
    }
    @MainActor
    func testAircraftConfigurationAtAccessibleSizes() async throws {
        XCTAssertNotNil(UIImage(systemName: "chair.lounge.fill"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: ScenarioBootstrap.newGame(
            scenario: "founder", worldSeed: 42, startYear: 2030),
            systems: GamePipeline.standard(), catalog: catalog)
        XCTAssertEqual(engine.applyNow(FoundAirlineCommand(airlineName: "Pacifica review",
            kind: .player, homeAirport: "ARN", startingCash: .dollars(10_000_000))), .applied)
        let player = try XCTUnwrap(engine.state.playerAirline?.id)
        XCTAssertEqual(engine.applyNow(LeaseAircraftCommand(lessee: player, type: "PA184", termMonths: 60)), .applied)
        let aircraft = try XCTUnwrap(engine.state.fleet(of: player).first)
        let spec = try XCTUnwrap(catalog.aircraftType(aircraft.typeCode))
        var cabin = aircraft.cabin(for: spec)
        cabin.setSeats(12, in: .first, capacity: spec.seats)
        cabin.setSeats(24, in: .business, capacity: spec.seats)
        cabin.setSeats(16, in: .premiumEconomy, capacity: spec.seats)
        cabin.wifi = 1; cabin.dining = 1; cabin.seats = 1
        XCTAssertEqual(engine.applyNow(ConfigureAircraftCommand(airline: player, aircraftID: aircraft.id, configuration: cabin)), .applied)
        XCTAssertEqual(engine.applyNow(OpenRouteCommand(airline: player, origin: "ARN", destination: "CDG",
            dailyRoundTrips: 3, ticketPrice: .dollars(180))), .applied)
        let route = try XCTUnwrap(engine.state.routes(of: player).first)
        XCTAssertEqual(engine.applyNow(AssignAircraftToRouteCommand(airline: player, route: route.id, aircraftID: aircraft.id)), .applied)
        XCTAssertEqual(engine.applyNow(ApplyRoutePlanCommand(airline: player, route: route.id,
            plan: RoutePlan(fare: .dollars(200), frequency: 4))), .applied)
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        try manager.save(engine.state, slot: "aircraft-review")
        let controller = GameController(savesDirectory: root)
        controller.loadGame(slot: "aircraft-review")
        try await waitForGame(controller)
        defer { controller.setPumping(false) }
        let installed = try XCTUnwrap(controller.snapshot?.aircraft[aircraft.id])
        let state = try XCTUnwrap(controller.snapshot)
        let reviewedRoute = try XCTUnwrap(state.routes[route.id])
        for dark in [false, true] {
            for section in RouteManagementSection.allCases {
                try await capture(NavigationStack { RouteDetailView(routeID: route.id, initialSection: section) },
                    name: "route-\(section.rawValue)", controller: controller, width: 393, dark: dark,
                    typeSize: .large, height: 1400)
            }
            try await capture(ScrollView {
                RoutePlanEditor(route: reviewedRoute, snapshot: state, catalog: catalog,
                    draft: .constant(RoutePlan(fare: .dollars(200), frequency: 4)))
            }, name: "route-planner-AX5", controller: controller, width: 375, dark: dark, typeSize: .accessibility5)
            try await capture(ScrollView {
                AircraftConfigurationEditor(aircraft: installed, spec: spec, snapshot: state,
                    catalog: catalog, section: .cabin, draft: .constant(nil))
                    .padding(12)
            }, name: "aircraft-full-cabin-iphone-width", controller: controller,
                width: 393, dark: dark, typeSize: .large, height: 2200)
            try await capture(ScrollView {
                AircraftConfigurationEditor(aircraft: installed, spec: spec, snapshot: state,
                    catalog: catalog, section: .upgrades, draft: .constant(nil))
                    .padding(12)
            }, name: "aircraft-full-upgrades-iphone-width", controller: controller,
                width: 393, dark: dark, typeSize: .large, height: 2200)
            try await capture(NavigationStack { AircraftDetailView(aircraftID: aircraft.id) },
                name: "aircraft-overview", controller: controller, width: 393, dark: dark, typeSize: .large)
            try await capture(ScrollView {
                AircraftConfigurationEditor(aircraft: installed, spec: spec, snapshot: state,
                    catalog: catalog, section: .cabin, draft: .constant(nil))
            }, name: "aircraft-cabin-AX5", controller: controller, width: 375, dark: dark, typeSize: .accessibility5)
            try await capture(ScrollView {
                AircraftConfigurationEditor(aircraft: installed, spec: spec, snapshot: state,
                    catalog: catalog, section: .upgrades, draft: .constant(nil))
            }, name: "aircraft-upgrades-AX5", controller: controller, width: 375, dark: dark, typeSize: .accessibility5)
        }
    }

    @MainActor
    func testAirportManagementAtAccessibleSizes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: ScenarioBootstrap.newGame(
            scenario: "founder", worldSeed: 42, startYear: 2030), systems: GamePipeline.standard(), catalog: catalog)
        XCTAssertEqual(engine.applyNow(FoundAirlineCommand(airlineName: "Pacifica",
            kind: .player, homeAirport: "ARN", startingCash: .dollars(10_000_000))), .applied)
        let id = try XCTUnwrap(engine.state.playerAirline?.id)
        XCTAssertEqual(engine.applyNow(LeaseAircraftCommand(lessee: id, type: "PA184", termMonths: 60)), .applied)
        let aircraft = try XCTUnwrap(engine.state.fleet(of: id).first)
        XCTAssertEqual(engine.applyNow(OpenRouteCommand(airline: id, origin: "ARN", destination: "CDG",
            dailyRoundTrips: 3, ticketPrice: .dollars(180))), .applied)
        let route = try XCTUnwrap(engine.state.routes(of: id).first)
        XCTAssertEqual(engine.applyNow(AssignAircraftToRouteCommand(airline: id, route: route.id, aircraftID: aircraft.id)), .applied)
        XCTAssertEqual(engine.applyNow(ConfigureAirportFacilitiesCommand(airline: id, airport: "ARN", facilities: .init(lounge: 1))), .applied)
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        try manager.save(engine.state, slot: "airport-review")
        let controller = GameController(savesDirectory: root)
        controller.loadGame(slot: "airport-review")
        try await waitForGame(controller)
        defer { controller.setPumping(false) }
        let state = try XCTUnwrap(controller.snapshot), player = try XCTUnwrap(state.playerAirline)
        for dark in [false, true] {
            for section in AirportManagementSection.allCases {
                try await capture(NavigationStack { AirportDetailView(code: "ARN", initialSection: section) },
                    name: "airport-\(section.rawValue)", controller: controller, width: 393, dark: dark,
                    typeSize: .large, height: 1600)
            }
            try await capture(ScrollView {
                AirportFacilityEditor(airport: "ARN", player: player, snapshot: state, catalog: catalog,
                    draft: .constant(AirportFacilities(lounge: 2, groundServices: 1))).padding(12)
            }, name: "airport-full-investment", controller: controller, width: 393, dark: dark,
                typeSize: .large, height: 1500)
            try await capture(NavigationStack { AirportDetailView(code: "ARN") },
                name: "airport-overview-AX5", controller: controller, width: 375, dark: dark,
                typeSize: .accessibility5, height: 1600)
            try await capture(ScrollView {
                AirportFacilityEditor(airport: "ARN", player: player, snapshot: state, catalog: catalog,
                    draft: .constant(nil)).padding(12)
            }, name: "airport-services-AX5", controller: controller, width: 375, dark: dark,
                typeSize: .accessibility5, height: 2400)
        }
    }

}
