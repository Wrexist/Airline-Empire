import SwiftUI
import Observation
import AirlineEmpireCore

/// The dashboard's floating panels: one open at a time.
enum HubPanel: Equatable {
    case insights, alerts, profile, hubs, layers, search, board
    /// The upgrade card for one facility site.
    case upgrade(HubFacilityKind)
}

/// A short confirmation that slides in under the top bar.
struct HubToast: Equatable, Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    let detail: String
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
        case .facility: self = .overview
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
    var panel: HubPanel? {
        didSet {
            // Leaving an upgrade card lets the overview's overlays back.
            if case .upgrade = oldValue, panel != oldValue { scene.leaveFacility() }
        }
    }
    var insightsTab: HubInsightsTab = .overview
    var inspectorPage: HubInspectorPage = .flight
    var searchQuery = ""
    private(set) var overlays: Set<HubOverlay> = Set(HubOverlay.allCases)
    private(set) var highlightedRoute: RouteID?
    /// Set by the screen: opens another airport of the network.
    var switchHub: ((AirportCode) -> Void)?
    /// Set by the screen: sends the facility change to the simulation (the
    /// same command the Airport Services screen sends); nil when accepted
    /// for now, or why it was refused.
    var requestUpgrade: ((HubFacilityKind, Int) -> CommandRejection?)?
    /// The facility whose next level has been ordered and not yet seen in a
    /// snapshot.
    private(set) var pendingUpgrade: HubFacilityKind?
    private(set) var upgradeError: String?
    private(set) var toast: HubToast?

    var upgradeOffers: [HubUpgradeOffer] { snapshot?.upgrades ?? [] }

    func offer(_ kind: HubFacilityKind) -> HubUpgradeOffer? {
        upgradeOffers.first { $0.kind == kind }
    }

    /// Opens a facility's upgrade card and flies the camera to its site.
    func openUpgrade(_ kind: HubFacilityKind) {
        upgradeError = nil
        panel = .upgrade(kind)
        shot = .overview
        scene.showFacility(kind)
    }

    /// Orders the next level of `kind`. The building goes up when the
    /// simulation has applied it (`refresh`).
    func build(_ kind: HubFacilityKind) {
        guard let offer = offer(kind), let next = offer.next, offer.canUpgrade, pendingUpgrade == nil else { return }
        upgradeError = nil
        if let rejection = requestUpgrade?(kind, next.level) {
            upgradeError = rejection.message
        } else {
            pendingUpgrade = kind
            scene.showFacility(kind)
        }
    }

    /// The simulation refused the pending order after accepting it for now.
    func upgradeRejected(_ message: String) {
        guard pendingUpgrade != nil else { return }
        pendingUpgrade = nil
        upgradeError = message
    }

    private func announce(_ offer: HubUpgradeOffer) {
        let toast = HubToast(systemImage: offer.kind == .lounge ? "sofa.fill" : "box.truck.fill",
                             title: "\(offer.buildingName) open at \(airport.raw)",
                             detail: offer.effect)
        self.toast = toast
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if self?.toast?.id == toast.id {
                withAnimation(HubMotion.panel) { self?.toast = nil }
            }
        }
    }

    /// A panel down the right side (insights, an upgrade card) is open:
    /// the inspector steps aside for it.
    var sidePanelOpen: Bool {
        switch panel {
        case .insights, .upgrade: true
        default: false
        }
    }

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
        scene.onTapFacility = { [weak self] kind in
            withAnimation(HubMotion.panel) { self?.openUpgrade(kind) }
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
        groundServices = state.playerAirline?.facilities(at: airport).groundServices ?? groundServices
        // A level that went up since the last read: the building is going
        // up in the world now; say so, and settle the pending order.
        if let previous = snapshot {
            for offer in next.upgrades {
                guard let before = previous.upgrades.first(where: { $0.kind == offer.kind }),
                      offer.level > before.level else { continue }
                if pendingUpgrade == offer.kind { pendingUpgrade = nil }
                withAnimation(HubMotion.panel) { announce(offer) }
            }
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
