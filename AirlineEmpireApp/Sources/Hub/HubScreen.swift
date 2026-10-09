import SwiftUI
import RealityKit
import AirlineEmpireCore

/// Feature switch for the 1.1 Hub View (docs/HUB_VIEW_3D.md §8).
enum AEFeature {
    static let hubView3D = true
}

@available(iOS 18.0, *)
private struct HubSceneView: UIViewRepresentable {
    let scene: HubSceneController

    func makeUIView(context: Context) -> ARView { scene.arView }
    func updateUIView(_ view: ARView, context: Context) {}
}

/// The 3D hub: the player's airport as an isometric clay diorama under a
/// light glass dashboard (docs/HUB_VIEW_3D.md). On iPhone it holds the
/// phone in landscape (`AEOrientation`); the hub switcher swaps the airport
/// in place.
@available(iOS 18.0, *)
struct HubScreen: View {
    let airport: AirportCode
    @Environment(GameController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @State private var model: HubScreenModel?
    /// Another airport of the network, chosen in the hub switcher.
    @State private var switched: AirportCode?

    private var code: AirportCode { switched ?? airport }

    private static var isUITest: Bool {
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-AEUITest") }
    }

    var body: some View {
        ZStack {
            Color(uiColor: HubPalette.day.background).ignoresSafeArea()
            if let model {
                HubDashboard(model: model, dismiss: { dismiss() })
                    .id(model.airport)
                    .transition(.opacity)
            } else {
                ProgressView().tint(HubChromeStyle.accent)
            }
        }
        .animation(.smooth(duration: 0.45), value: model?.airport)
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
        .statusBarHidden(false)
        .onAppear {
            AEOrientation.lockLandscape()
            start()
        }
        .onChange(of: controller.snapshotReceivedAt) { refresh() }
        .onChange(of: controller.mapRevision) { refresh() }
        .onChange(of: controller.lastRejection) { _, rejection in
            if let rejection { model?.upgradeRejected(rejection.message) }
        }
        .onDisappear {
            model?.scene.pause(true)
            AEOrientation.unlock()
        }
    }

    private func start() {
        if let model {
            model.scene.pause(false)
            return
        }
        guard let state = controller.snapshot, let catalog = controller.catalog,
              let spec = catalog.airport(code) else { return }
        let facilities = state.playerAirline?.airportFacilities?[code] ?? AirportFacilities()
        let made = HubScreenModel(airport: code, spec: spec, facilities: facilities, uiTest: Self.isUITest)
        // The inspector opens beside the scene where there is room for it;
        // on a phone it waits to be asked for (tap a jet or its callout).
        made.showsInspector = !AEOrientation.isPhone && UIScreen.main.bounds.width >= 760
        made.switchHub = { next in switchTo(next) }
        // Upgrades from the hub are the Airport Services screen's command,
        // with the one facility moved up a level.
        let game = controller, hub = code
        made.requestUpgrade = { kind, level in
            guard let player = game.snapshot?.playerAirline else {
                return CommandRejection(code: "airport.unavailable", message: "Start an airline first.")
            }
            let facilities = kind.service.setting(level, in: player.facilities(at: hub))
            return game.submit(ConfigureAirportFacilitiesCommand(airline: player.id, airport: hub,
                                                                 facilities: facilities))
        }
        model = made
        made.refresh(state: state, catalog: catalog)
        if let shot = Self.launchShot { made.select(shot) }
        if ProcessInfo.processInfo.arguments.contains("-AEUITestHubNight") { made.setLighting(.night) }
    }

    private func switchTo(_ next: AirportCode) {
        guard next != code else { return }
        model?.scene.pause(true)
        switched = next
        model = nil
        start()
    }

    /// `-AEUITestHubShot gate` opens on a given shot, for the captures.
    private static var launchShot: HubShot? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-AEUITestHubShot"), i + 1 < args.count else { return nil }
        return HubShot(rawValue: args[i + 1])
    }

    private func refresh() {
        guard let model, let state = controller.snapshot, let catalog = controller.catalog else { return }
        model.refresh(state: state, catalog: catalog)
    }
}

@available(iOS 18.0, *)
private struct HubDashboard: View {
    @Bindable var model: HubScreenModel
    let dismiss: () -> Void

    var body: some View {
        GeometryReader { geo in
            let mode = HubChromeMode(size: geo.size)
            ZStack(alignment: .topLeading) {
                HubSceneView(scene: model.scene)
                    .ignoresSafeArea()

                // World-anchored callouts, tags, labels, pins and pills, in
                // the scene's own full-screen coordinates.
                GeometryReader { full in
                    ForEach(model.projected) { item in
                        let point = item.anchor.kind == .callout
                            ? calloutCenter(item.point, size: full.size, insets: geo.safeAreaInsets, mode: mode)
                            : item.point
                        anchored(item, mode: mode)
                            .position(x: point.x, y: point.y)
                            .allowsHitTesting(isTappable(item.anchor.kind))
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
                .ignoresSafeArea()
                .animation(HubMotion.snap, value: model.projected.map(\.id))

                switch mode {
                case .regular: regular(geo.size)
                case .landscape: landscape(geo.size)
                case .portrait: portrait()
                }

                panels(mode)

                // Confirmation that something was built.
                if let toast = model.toast {
                    HubToastView(toast: toast)
                        .padding(.top, mode.topBarHeight + 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(HubMotion.panel, value: model.showsInspector)
            .animation(HubMotion.panel, value: model.focus)
            .animation(HubMotion.panel, value: model.panel)
            .animation(HubMotion.panel, value: model.toast)
        }
    }

    // MARK: Layouts

    /// iPad: the reference's layout. KPI cards and shots top left, the
    /// inspector top right, timeline and board along the bottom.
    private func regular(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            HubTopBar(model: model, mode: .regular, dismiss: dismiss)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    HubKPIRow(model: model)
                    HubShotPicker(model: model)
                }
                Spacer(minLength: 0)
                HubControls(model: model)
                if model.showsInspector, model.panel != .insights, let occupant = model.focusedOccupant {
                    HubInspector(model: model, occupant: occupant)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 12) {
                // The reference's timeline runs most of the way across a
                // wide screen.
                HubTimeline(model: model, compact: size.width < 1_000)
                    .frame(maxWidth: max(640, size.width * 0.58))
                Spacer(minLength: 0)
                if model.panel != .insights {
                    HubBoard(model: model)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(14)
        }
    }

    /// iPhone on its side: one slim bar with the shots in it, compact KPI
    /// chips, the controls down the right, a slim timeline, and the board
    /// behind a button.
    private func landscape(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            HubTopBar(model: model, mode: .landscape, narrow: size.width < 790, dismiss: dismiss)
            HStack(alignment: .top, spacing: 8) {
                HubKPIRow(model: model, compact: true)
                Spacer(minLength: 0)
                if model.showsInspector, model.panel != .insights, let occupant = model.focusedOccupant {
                    ScrollView(.vertical, showsIndicators: false) {
                        HubInspector(model: model, occupant: occupant, compact: true)
                    }
                    .frame(maxHeight: max(160, size.height - HubChromeMode.landscape.topBarHeight - 24))
                    .fixedSize(horizontal: true, vertical: false)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                HubControls(model: model, compact: true)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 10) {
                HubTimeline(model: model, compact: true, slim: true)
                    .frame(maxWidth: min(520, size.width * 0.56))
                Spacer(minLength: 0)
                if model.panel != .insights {
                    flightsButton.transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    /// A narrow window (iPad split view): stacked.
    private func portrait() -> some View {
        VStack(spacing: 0) {
            HubTopBar(model: model, mode: .portrait, dismiss: dismiss)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HubKPIRow(model: model).padding(.horizontal, 2).padding(.vertical, 6)
                    }
                    HubShotPicker(model: model, compact: true)
                }
                Spacer(minLength: 0)
                HubControls(model: model)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                if model.showsInspector, model.panel != .insights, let occupant = model.focusedOccupant {
                    HubInspector(model: model, occupant: occupant)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HubTimeline(model: model, compact: true)
            }
            .padding(12)
        }
    }

    private var flightsButton: some View {
        Button {
            withAnimation(HubMotion.snap) { model.toggle(.board) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle").font(.system(size: 13, weight: .semibold))
                Text("Flights").font(.system(size: 12, weight: .semibold))
                Text("\(model.count(.departures) + model.count(.arrivals))")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 16)
                    .background(HubChromeStyle.accent, in: Capsule())
                if model.count(.delays) > 0 {
                    Text("\(model.count(.delays)) late")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minHeight: 16)
                        .background(HubChromeStyle.warn, in: Capsule())
                }
            }
            .foregroundStyle(model.panel == .board ? HubChromeStyle.accent : HubChromeStyle.ink)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .hubGlass(radius: 19, padding: 0)
        }
        .buttonStyle(HubPressStyle())
        .accessibilityIdentifier("ae-hub-flights")
    }

    // MARK: Panels

    @ViewBuilder
    private func panels(_ mode: HubChromeMode) -> some View {
        if let panel = model.panel {
            if case .upgrade(let kind) = panel {
                // The upgrade card beside its site: the scene stays live so
                // the construction can be watched.
                HubUpgradeCard(model: model, kind: kind, mode: mode)
                    .padding(.top, mode.topBarHeight + 10)
                    .padding(.trailing, mode == .landscape ? 60 : 64)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if panel == .insights {
                // A side panel: the scene stays live and touchable beside it.
                HubInsightsPanel(model: model, mode: mode)
                    .padding(.top, mode.topBarHeight + 10)
                    .padding(.bottom, mode == .landscape ? 8 : 14)
                    .padding(.trailing, mode == .landscape ? 60 : 64)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                // A dropdown: a tap anywhere else closes it. Not under the
                // iPad's search field, which stays live while results show.
                if !(panel == .search && mode == .regular) {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(HubMotion.snap) { model.panel = nil } }
                }
                HubDropdown(model: model, panel: panel, mode: mode)
                    .padding(.top, panel == .board ? 0 : mode.topBarHeight + 8)
                    .padding(.bottom, panel == .board ? 56 : 0)
                    .padding(.leading, panel == .search && mode == .regular ? 210 : 14)
                    .padding(.trailing, panel == .layers ? (mode == .landscape ? 60 : 64) : 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(panel, mode))
                    .transition(.scale(scale: 0.94, anchor: anchor(panel, mode)).combined(with: .opacity))
            }
        }
    }

    private func alignment(_ panel: HubPanel, _ mode: HubChromeMode) -> Alignment {
        switch panel {
        case .search: mode == .regular ? .topLeading : .topTrailing
        case .board: .bottomTrailing
        default: .topTrailing
        }
    }

    private func anchor(_ panel: HubPanel, _ mode: HubChromeMode) -> UnitPoint {
        switch panel {
        case .search: mode == .regular ? .top : .topTrailing
        case .board: .bottomTrailing
        default: .topTrailing
        }
    }

    // MARK: World anchors

    /// The callout floats over its aircraft but never under the chrome:
    /// held between the KPI row and the timeline, and clear of the inspector
    /// (reference shot B shows it whole, over the jet). Full-screen points.
    private func calloutCenter(_ anchor: CGPoint, size: CGSize, insets: EdgeInsets, mode: HubChromeMode) -> CGPoint {
        // The compact callout on a phone is one line and a bar.
        let half = mode == .landscape ? CGSize(width: 110, height: 30) : CGSize(width: 118, height: 80)
        let chromeTop: CGFloat = mode == .regular ? 214 : mode == .landscape ? 104 : 250
        let chromeBottom: CGFloat = mode == .regular ? 170 : mode == .landscape ? 110 : 190
        let chromeRight: CGFloat = mode == .regular && model.showsInspector ? 330
            : mode == .landscape ? (model.showsInspector ? 312 : 64) : 12
        let top = insets.top + chromeTop + half.height
        let bottom = size.height - insets.bottom - chromeBottom - half.height
        let left = insets.leading + 12 + half.width
        let right = size.width - insets.trailing - chromeRight - half.width
        let x = min(max(anchor.x, left), max(left, right))
        let y = min(max(anchor.y - 60 - half.height, top), max(top, bottom))
        return CGPoint(x: x, y: y)
    }

    private func isTappable(_ kind: HubAnchor.Kind) -> Bool {
        switch kind {
        case .callout, .tag, .route, .facility: true
        case .pin, .pill: false
        }
    }

    @ViewBuilder
    private func anchored(_ item: HubProjectedAnchor, mode: HubChromeMode) -> some View {
        switch item.anchor.kind {
        case .callout:
            if let occupant = model.focusedOccupant {
                HubCallout(occupant: occupant, compact: mode == .landscape)
                    .onTapGesture { withAnimation(HubMotion.panel) { model.showsInspector = true } }
            }
        case .pin(let label):
            HubPin(label: label).offset(y: -24)
        case .pill(let label, let image):
            HubPill(label: label, systemImage: image)
        case .tag(let tag):
            HubStandTagView(tag: tag)
                .offset(y: -12)
                .onTapGesture {
                    withAnimation(HubMotion.panel) {
                        model.setFocus(tag.standIndex)
                        model.select(.gate)
                        model.showsInspector = true
                    }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Gate \(tag.gate), \(tag.code), \(tag.stage)")
        case .route(let tag):
            HubRouteLabel(tag: tag)
                .onTapGesture { withAnimation(HubMotion.panel) { model.highlight(tag.routeID) } }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Route to \(tag.code), \(tag.detail)")
        case .facility(let tag):
            HubFacilityTagView(tag: tag)
                .offset(y: -14)
                .onTapGesture { withAnimation(HubMotion.panel) { model.openUpgrade(tag.kind) } }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("\(tag.title), \(tag.levelName). \(tag.next)")
                .accessibilityIdentifier("ae-hub-site-\(tag.kind.rawValue)")
        }
    }
}
