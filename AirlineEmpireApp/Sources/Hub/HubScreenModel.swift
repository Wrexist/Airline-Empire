import SwiftUI
import Observation
import AirlineEmpireCore

/// The dashboard's floating panels: one open at a time.
enum HubPanel: Equatable {
    case insights, alerts, profile, hubs, layers, search, board
}

enum HubInsightsTab: String, CaseIterable, Identifiable {
    case overview = "Overview", routes = "Routes", slots = "Slots", airline = "Airline"
    var id: String { rawValue }
}

/// The inspector's pages, swiped through under the aircraft profile.
enum HubInspectorPage: Int, CaseIterable, Identifiable {
    case flight, aircraft, route, turnaround
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .flight: "Flight"
        case .aircraft: "Aircraft"
        case .route: "Route"
        case .turnaround: "Turnaround"
        }
    }
}

extension HubShot {
    init(_ shot: HubCameraShot) {
        switch shot {
        case .overview: self = .overview
        case .gate: self = .gate
        case .terminal: self = .terminal
        case .district: self = .district
        }
    }
}

/// The Hub View's state: which airport, which shot, which stand is in focus,
/// and the latest read of the simulation. One per presentation.
@MainActor
@Observable
@available(iOS 18.0, *)
final class HubScreenModel {
    enum Lighting: String, CaseIterable {
        case auto, day, night
    }

    let airport: AirportCode
    let layout: HubLayout
    let scene: HubSceneController
    private(set) var snapshot: HubSnapshot?
    private(set) var projected: [HubProjectedAnchor] = []
    private(set) var shot: HubShot = .overview
    private(set) var focus: Int?
    private(set) var lighting: Lighting = .auto

    func select(_ shot: HubShot) {
        self.shot = shot
        scene.show(shot, focus: focus)
    }

    func setFocus(_ index: Int?) {
        guard index != focus else { return }
        focus = index
        if let snapshot { push(snapshot) }
        if shot == .gate { scene.show(.gate, focus: focus) }
    }

    func setLighting(_ value: Lighting) {
        lighting = value
        applyLighting()
    }
    var boardTab: BoardTab = .departures
    var showsInspector = true
    var panel: HubPanel?
    var insightsTab: HubInsightsTab = .overview
    var inspectorPage: HubInspectorPage = .flight
    var searchQuery = ""
    private(set) var overlays: Set<HubOverlay> = Set(HubOverlay.allCases)
    private(set) var highlightedRoute: RouteID?
    /// Set by the screen: opens another airport of the network.
    var switchHub: ((AirportCode) -> Void)?

    /// Opens `panel`, or closes it if it is already open.
    func toggle(_ panel: HubPanel) {
        self.panel = self.panel == panel ? nil : panel
    }

    func setOverlay(_ overlay: HubOverlay, _ on: Bool) {
        if on { overlays.insert(overlay) } else { overlays.remove(overlay) }
        scene.setOverlays(overlays)
    }

    /// Lights one route of the fan (nil for none) and swings the camera
    /// back to the overview, where the fan is drawn.
    func highlight(_ route: RouteID?) {
        highlightedRoute = highlightedRoute == route ? nil : route
        scene.highlightRoute(highlightedRoute)
        if highlightedRoute != nil {
            if !overlays.contains(.routes) { setOverlay(.routes, true) }
            if shot != .overview { select(.overview) }
        }
    }

    var searchResults: [HubSearchResult] {
        snapshot?.search(searchQuery, layout: layout) ?? []
    }

    /// Takes the camera to a search result.
    func choose(_ result: HubSearchResult) {
        switch result.target {
        case .stand(let index):
            setFocus(index)
            select(.gate)
            showsInspector = true
        case .route(let id):
            if highlightedRoute != id { highlight(id) }
        case .shot(let shot):
            select(HubShot(shot))
        }
        searchQuery = ""
        panel = nil
    }

    /// An alert about a stand focuses it; anything else opens the
    /// insights it comes from.
    func open(_ alert: HubAlert) {
        if let stand = alert.standIndex {
            setFocus(stand)
            select(.gate)
            showsInspector = true
            panel = nil
        } else {
            insightsTab = alert.kind == .lowLoad ? .routes : alert.kind == .slots ? .slots : .overview
            panel = .insights
        }
    }

    /// The board row's stand, when the flight is at one.
    func open(_ row: HubBoardRow) {
        if let stand = snapshot?.occupants.first(where: { $0.flight?.code == row.code })?.standIndex {
            setFocus(stand)
            select(.gate)
            showsInspector = true
            panel = nil
        } else if let link = snapshot?.insights.routes.first(where: { $0.other == row.airport }) {
            highlight(link.routeID)
            panel = nil
        }
    }

    var focusedRoute: HubRouteLink? {
        guard let id = focusedOccupant?.routeID else { return nil }
        return snapshot?.insights.routes.first { $0.routeID == id }
    }

    enum BoardTab: String, CaseIterable {
        case departures = "Departures", arrivals = "Arrivals", delays = "Delays"
    }

    private var groundServices = 0

    init(airport: AirportCode, spec: AirportSpec, facilities: AirportFacilities, uiTest: Bool) {
        self.airport = airport
        self.layout = HubLayout.make(airport: spec, facilities: facilities)
        self.scene = HubSceneController(layout: layout, idleDrift: !uiTest)
        self.groundServices = facilities.groundServices
        scene.onProjected = { [weak self] anchors in
            guard let self, anchors != self.projected else { return }
            self.projected = anchors
        }
        scene.onTapAircraft = { [weak self] index in
            self?.setFocus(index)
            self?.showsInspector = true
        }
    }

    /// `-AEUITestHubStage boarding` holds the focused turnaround at one
    /// stage, so the captures show the reference's boarding moment.
    private static let heldStage: HubTurnaroundStage? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-AEUITestHubStage"), i + 1 < args.count else { return nil }
        return HubTurnaroundStage.allCases.first { $0.title.lowercased() == args[i + 1].lowercased() }
    }()

    func refresh(state: GameState, catalog: ContentCatalog) {
        guard var next = state.hubSnapshot(airport: airport, catalog: catalog, layout: layout) else { return }
        if let held = Self.heldStage, let stand = focus ?? next.focusStand {
            next = next.holding(held, progress: 0.45, atStand: stand)
        }
        let first = snapshot == nil
        if let facilities = state.playerAirline?.airportFacilities?[airport] {
            groundServices = facilities.groundServices
        }
        if first {
            focus = next.focusStand
        }
        snapshot = next
        push(next)
        applyLighting()
        if first { scene.show(shot, focus: focus, animated: false) }
    }

    private func push(_ snapshot: HubSnapshot) {
        scene.apply(snapshot, focus: focus, groundServices: groundServices,
                    terminalLoad: snapshot.kpis.terminalLoad)
    }

    private func applyLighting() {
        switch lighting {
        case .auto: scene.setNight(snapshot?.nightFactor ?? 0)
        case .day: scene.setNight(0)
        case .night: scene.setNight(1)
        }
    }

    var isNight: Bool {
        switch lighting {
        case .auto: (snapshot?.nightFactor ?? 0) > 0.5
        case .day: false
        case .night: true
        }
    }

    var focusedOccupant: HubStandOccupant? {
        focus.flatMap { snapshot?.occupant(atStand: $0) }
    }

    var boardRows: [HubBoardRow] {
        guard let snapshot else { return [] }
        switch boardTab {
        case .departures: return snapshot.departures
        case .arrivals: return snapshot.arrivals
        case .delays: return snapshot.delays
        }
    }

    func count(_ tab: BoardTab) -> Int {
        guard let snapshot else { return 0 }
        switch tab {
        case .departures: return snapshot.departures.count
        case .arrivals: return snapshot.arrivals.count
        case .delays: return snapshot.delays.count
        }
    }

    /// Steps forward through the player's aircraft at the hub.
    func focusNext() {
        guard let snapshot else { return }
        let mine = snapshot.occupants.filter { $0.operatorKind == .player }.map(\.standIndex)
        let pool = mine.isEmpty ? snapshot.occupants.map(\.standIndex) : mine
        guard !pool.isEmpty else { return }
        if let focus, let i = pool.firstIndex(of: focus) {
            setFocus(pool[(i + 1) % pool.count])
        } else {
            setFocus(pool.first)
        }
    }
}
