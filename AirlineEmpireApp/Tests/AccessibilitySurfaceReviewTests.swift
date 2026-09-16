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
                                  height: CGFloat = 812, settleMilliseconds: Int = 1000) async throws {
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
        try await Task.sleep(for: .milliseconds(settleMilliseconds))
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
                try await capture(NavigationStack { PassengerExperienceView() }, name: "reputation", controller: controller, width: width, dark: dark)
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
                    typeSize: .large, height: 1600, settleMilliseconds: 3000)
            }
            try await capture(ScrollView {
                AirportFacilityEditor(airport: "ARN", player: player, snapshot: state, catalog: catalog,
                    draft: .constant(AirportFacilities(lounge: 2, groundServices: 1))).padding(12)
            }, name: "SERVICES-03-full-investment", controller: controller, width: 393, dark: dark,
                typeSize: .large, height: 1500, settleMilliseconds: 3000)
            let widths: [CGFloat] = [320, 430, 834]
            for width in widths {
                try await capture(ScrollView {
                    AirportFacilityEditor(airport: "ARN", player: player, snapshot: state, catalog: catalog,
                        draft: .constant(AirportFacilities(lounge: 1, groundServices: 2)))
                        .environment(\.horizontalSizeClass, width >= 800 ? .regular : .compact).padding(12)
                }, name: "SERVICES-04-negative-\(width >= 800 ? "08-iPad" : "phone")-\(dark ? "10-dark" : "09-light")",
                    controller: controller, width: width, dark: dark, typeSize: .large, height: 1700, settleMilliseconds: 3000)
            }
            try await capture(NavigationStack { AirportDetailView(code: "ARN") },
                name: "airport-overview-AX5", controller: controller, width: 375, dark: dark,
                typeSize: .accessibility5, height: 1600, settleMilliseconds: 3000)
            try await capture(ScrollView {
                AirportFacilityEditor(airport: "ARN", player: player, snapshot: state, catalog: catalog,
                    draft: .constant(nil)).padding(12)
            }, name: "SERVICES-07-AX5", controller: controller, width: 375, dark: dark,
                typeSize: .accessibility5, height: 2200, settleMilliseconds: 3000)
            try await capture(ScrollViewReader { proxy in
                ScrollView {
                    VStack {
                        AirportFacilityEditor(airport: "ARN", player: player, snapshot: state, catalog: catalog,
                            draft: .constant(AirportFacilities(lounge: 2, groundServices: 1))).padding(12)
                        Color.clear.frame(height: 160).id("airport-review-end")
                    }
                }.task {
                    // Use the layout's actual end anchor, not UIScrollView's lazy estimate.
                    for _ in 0..<12 {
                        try? await Task.sleep(for: .milliseconds(200))
                        proxy.scrollTo("airport-review-end", anchor: .bottom)
                    }
                }
            }, name: "SERVICES-07-AX5-actions", controller: controller, width: 375, dark: dark,
                typeSize: .accessibility5, height: 1600, settleMilliseconds: 3000)
        }
    }

    /// The passenger-experience screen with a proposal selected, so the review
    /// state (current vs proposed, forecast, apply/reset) is what is captured
    /// rather than the installed state.
    @MainActor
    func testPassengerExperienceAtAccessibleSizes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: ScenarioBootstrap.newGame(
            scenario: "founder", worldSeed: 42, startYear: 2030),
            systems: GamePipeline.standard(), catalog: catalog)
        XCTAssertEqual(engine.applyNow(FoundAirlineCommand(airlineName: "Pacifica review",
            kind: .player, homeAirport: "ARN", startingCash: .dollars(25_000_000))), .applied)
        let player = try XCTUnwrap(engine.state.playerAirline?.id)
        XCTAssertEqual(engine.applyNow(LeaseAircraftCommand(lessee: player, type: "PA184", termMonths: 60)), .applied)
        let aircraft = try XCTUnwrap(engine.state.fleet(of: player).first)
        let spec = try XCTUnwrap(catalog.aircraftType(aircraft.typeCode))
        var cabin = aircraft.cabin(for: spec)
        cabin.setSeats(12, in: .first, capacity: spec.seats)
        cabin.setSeats(24, in: .business, capacity: spec.seats)
        cabin.setSeats(16, in: .premiumEconomy, capacity: spec.seats)
        cabin.wifi = 1; cabin.dining = 1; cabin.seats = 1
        XCTAssertEqual(engine.applyNow(ConfigureAircraftCommand(
            airline: player, aircraftID: aircraft.id, configuration: cabin)), .applied)
        XCTAssertEqual(engine.applyNow(OpenRouteCommand(airline: player, origin: "ARN",
            destination: "CDG", dailyRoundTrips: 3, ticketPrice: .dollars(180))), .applied)
        let route = try XCTUnwrap(engine.state.routes(of: player).first)
        XCTAssertEqual(engine.applyNow(AssignAircraftToRouteCommand(
            airline: player, route: route.id, aircraftID: aircraft.id)), .applied)
        XCTAssertEqual(engine.applyNow(ApplyRoutePlanCommand(airline: player, route: route.id,
            plan: RoutePlan(fare: .dollars(200), frequency: 4))), .applied)
        XCTAssertEqual(engine.applyNow(ConfigureAirportFacilitiesCommand(
            airline: player, airport: "ARN", facilities: .init(lounge: 1))), .applied)
        let ticksPerDay = Int(GameCalendar.minutesPerDay / engine.state.meta.tickMinutes)
        engine.advance(ticks: ticksPerDay * 45)
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        try manager.save(engine.state, slot: "pax-review")
        let controller = GameController(savesDirectory: root)
        controller.loadGame(slot: "pax-review")
        try await waitForGame(controller)
        defer { controller.setPumping(false) }
        let state = try XCTUnwrap(controller.snapshot)
        let reputation = try XCTUnwrap(state.playerAirline?.reputation)
        XCTAssertTrue(reputation.punctuality > 0 && reputation.comfort > 0)

        for dark in [false, true] {
            // Full screen at a phone width, tall enough to hold the whole
            // review state. The screen scrolls itself; the capture window is
            // the viewport, so nothing is nested.
            try await capture(PassengerExperienceView(initialDraft: .premium),
                name: "PAX-03-full-\(dark ? "dark" : "light")", controller: controller,
                width: 393, dark: dark, typeSize: .large, height: 2600, settleMilliseconds: 3000)
            // Large Dynamic Type: the drivers reflow to one column, so the
            // window is taller and the forecast/action area is captured from
            // the same top-of-screen frame the device journey also inspects.
            try await capture(PassengerExperienceView(initialDraft: .premium),
                name: "PAX-07-AX5-\(dark ? "dark" : "light")", controller: controller,
                width: 375, dark: dark, typeSize: .accessibility5, height: 2600, settleMilliseconds: 3000)
            // Regular width.
            try await capture(PassengerExperienceView(initialDraft: .premium),
                name: "PAX-08-iPad-\(dark ? "dark" : "light")", controller: controller,
                width: 834, dark: dark, typeSize: .large, height: 2200, settleMilliseconds: 3000)
        }
    }

    /// A fleet with one of everything the board distinguishes: idle, closing
    /// on a check, a lease ending, in a check, and on order.
    @MainActor
    func testFleetBoardAtAccessibleSizes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: ScenarioBootstrap.newGame(
            scenario: "founder", worldSeed: 42, startYear: 2030),
            systems: GamePipeline.standard(), catalog: catalog)
        XCTAssertEqual(engine.applyNow(FoundAirlineCommand(airlineName: "Pacifica fleet review",
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

        // Test-only surgery to stage each board state, on a value copy.
        var state = engine.state
        state.aircraft[ids[4]]?.ownership = .leased(
            monthlyRate: .dollars(500_000), termMonthsRemaining: 2)
        state.aircraft[ids[5]]?.status = .inMaintenance(until: state.clock.now + .days(4))
        state.aircraft[ids[6]]?.condition = 0.77
        state.aircraft[ids[7]]?.status = .ordered(deliveryAt: state.clock.now + .days(30))
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        try manager.save(state, slot: "fleet-review")
        let controller = GameController(savesDirectory: root)
        controller.loadGame(slot: "fleet-review")
        try await waitForGame(controller)
        defer { controller.setPumping(false) }
        let loaded = try XCTUnwrap(controller.snapshot)
        let board = loaded.fleetBoard(for: try XCTUnwrap(loaded.playerAirline?.id), catalog: catalog)
        XCTAssertFalse(board.needsDecision.isEmpty)
        XCTAssertFalse(board.unavailable.isEmpty)

        for dark in [false, true] {
            try await capture(NavigationStack { FleetList() },
                name: "FLEET-03-board-\(dark ? "dark" : "light")", controller: controller,
                width: 393, dark: dark, typeSize: .large, height: 1700, settleMilliseconds: 2500)
            try await capture(NavigationStack { FleetList() },
                name: "FLEET-08-iPad-\(dark ? "dark" : "light")", controller: controller,
                width: 834, dark: dark, typeSize: .large, height: 1700, settleMilliseconds: 2500)
            try await capture(NavigationStack { FleetList() },
                name: "FLEET-07-AX5-\(dark ? "dark" : "light")", controller: controller,
                width: 375, dark: dark, typeSize: .accessibility5, height: 2200, settleMilliseconds: 2500)
        }
    }

    /// Finance with a closed month, a loan and a station commitment, so the
    /// operating, cash and commitment groups are all populated.
    @MainActor
    func testFinanceBreakdownAtAccessibleSizes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: ScenarioBootstrap.newGame(
            scenario: "founder", worldSeed: 42, startYear: 2030),
            systems: GamePipeline.standard(), catalog: catalog)
        XCTAssertEqual(engine.applyNow(FoundAirlineCommand(airlineName: "Pacifica ledger",
            kind: .player, homeAirport: "ARN", startingCash: .dollars(30_000_000))), .applied)
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
        engine.advance(ticks: ticksPerDay * 35)
        XCTAssertNotNil(engine.state.finance.byAirline[player]?.latest)
        XCTAssertEqual(engine.applyNow(TakeLoanCommand(airline: player,
            amount: .dollars(5_000_000), termMonths: 48)), .applied)
        XCTAssertEqual(engine.applyNow(ConfigureAirportFacilitiesCommand(
            airline: player, airport: "ARN", facilities: .init(lounge: 1))), .applied)
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        try manager.save(engine.state, slot: "finance-review")
        let controller = GameController(savesDirectory: root)
        controller.loadGame(slot: "finance-review")
        try await waitForGame(controller)
        defer { controller.setPumping(false) }
        let loaded = try XCTUnwrap(controller.snapshot)
        let breakdown = loaded.financeBreakdown(for: try XCTUnwrap(loaded.playerAirline?.id),
                                                catalog: catalog)
        XCTAssertNotNil(breakdown.latestStatement)
        XCTAssertGreaterThan(breakdown.recurring.monthlyTotal, .zero)

        for dark in [false, true] {
            try await capture(FinanceView(),
                name: "FIN-01-breakdown-\(dark ? "dark" : "light")", controller: controller,
                width: 393, dark: dark, typeSize: .large, height: 2000, settleMilliseconds: 2500)
            try await capture(FinanceView(),
                name: "FIN-08-iPad-\(dark ? "dark" : "light")", controller: controller,
                width: 834, dark: dark, typeSize: .large, height: 2000, settleMilliseconds: 2500)
            try await capture(FinanceView(),
                name: "FIN-07-AX5-\(dark ? "dark" : "light")", controller: controller,
                width: 375, dark: dark, typeSize: .accessibility5, height: 2200, settleMilliseconds: 2500)
        }
    }

    /// Progression with a lived-in campaign: a closed month behind it, a
    /// capability programme running, a mission in progress and a log with
    /// dated moments.
    @MainActor
    func testCampaignProgressAtAccessibleSizes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
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

        // Test-only surgery to stage a campaign mid-arc.
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
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        try manager.save(state, slot: "campaign-review")
        let controller = GameController(savesDirectory: root)
        controller.loadGame(slot: "campaign-review")
        try await waitForGame(controller)
        defer { controller.setPumping(false) }
        let loaded = try XCTUnwrap(controller.snapshot)
        let model = try XCTUnwrap(loaded.progressionModel(catalog: catalog))
        XCTAssertEqual(model.era, .national)
        XCTAssertEqual(model.record.count, 6)

        for dark in [false, true] {
            try await capture(NavigationStack { ProgressionView() },
                name: "CAMPAIGN-01-\(dark ? "dark" : "light")", controller: controller,
                width: 393, dark: dark, typeSize: .large, height: 2200, settleMilliseconds: 2500)
            try await capture(NavigationStack { ProgressionView() },
                name: "CAMPAIGN-08-iPad-\(dark ? "dark" : "light")", controller: controller,
                width: 834, dark: dark, typeSize: .large, height: 2200, settleMilliseconds: 2500)
            try await capture(NavigationStack { ProgressionView() },
                name: "CAMPAIGN-07-AX5-\(dark ? "dark" : "light")", controller: controller,
                width: 375, dark: dark, typeSize: .accessibility5, height: 2200, settleMilliseconds: 2500)
        }
    }

}
