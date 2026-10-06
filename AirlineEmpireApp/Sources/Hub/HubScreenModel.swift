import SwiftUI
import Observation
import AirlineEmpireCore

/// The Hub View's state: which airport, which shot, which stand is in focus,
/// and the latest read of the simulation. One per presentation.
@MainActor
@Observable
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

    func refresh(state: GameState, catalog: ContentCatalog) {
        guard let next = state.hubSnapshot(airport: airport, catalog: catalog, layout: layout) else { return }
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
