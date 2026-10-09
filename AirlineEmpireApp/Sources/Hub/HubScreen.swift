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
/// light glass dashboard (docs/HUB_VIEW_3D.md).
@available(iOS 18.0, *)
struct HubScreen: View {
    let airport: AirportCode
    @Environment(GameController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @State private var model: HubScreenModel?

    private static var isUITest: Bool {
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-AEUITest") }
    }

    var body: some View {
        ZStack {
            Color(uiColor: HubPalette.day.background).ignoresSafeArea()
            if let model {
                HubDashboard(model: model, dismiss: { dismiss() })
            } else {
                ProgressView().tint(HubChromeStyle.accent)
            }
        }
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
        .statusBarHidden(false)
        .onAppear(perform: start)
        .onChange(of: controller.snapshotReceivedAt) { refresh() }
        .onChange(of: controller.mapRevision) { refresh() }
        .onDisappear { model?.scene.pause(true) }
    }

    private func start() {
        if let model {
            model.scene.pause(false)
            return
        }
        guard let state = controller.snapshot, let catalog = controller.catalog,
              let spec = catalog.airport(airport) else { return }
        let facilities = state.playerAirline?.airportFacilities?[airport] ?? AirportFacilities()
        let made = HubScreenModel(airport: airport, spec: spec, facilities: facilities, uiTest: Self.isUITest)
        model = made
        made.showsInspector = UIScreen.main.bounds.width >= 760
        made.refresh(state: state, catalog: catalog)
        if let shot = Self.launchShot { made.select(shot) }
        if ProcessInfo.processInfo.arguments.contains("-AEUITestHubNight") { made.setLighting(.night) }
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
            let wide = geo.size.width >= 760
            ZStack(alignment: .topLeading) {
                HubSceneView(scene: model.scene)
                    .ignoresSafeArea()

                // World-anchored callouts, pins and pills.
                ForEach(model.projected) { item in
                    let point = item.anchor.kind == .callout ? calloutCenter(item.point, size: geo.size, wide: wide)
                        : item.point
                    anchored(item)
                        .position(x: point.x, y: point.y)
                        .allowsHitTesting(item.anchor.kind == .callout)
                }

                VStack(spacing: 0) {
                    HubTopBar(model: model, wide: wide, dismiss: dismiss)
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 10) {
                            if wide {
                                HubKPIRow(snapshot: model.snapshot)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HubKPIRow(snapshot: model.snapshot).padding(.horizontal, 2).padding(.vertical, 6)
                                }
                            }
                            HubShotPicker(model: model, compact: !wide)
                        }
                        Spacer(minLength: 0)
                        if wide, model.showsInspector, let occupant = model.focusedOccupant {
                            HubControls(model: model)
                            HubInspector(model: model, occupant: occupant)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        } else {
                            HubControls(model: model)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                    Spacer(minLength: 0)

                    if wide {
                        HStack(alignment: .bottom, spacing: 12) {
                            // The reference's timeline runs most of the way
                            // across a wide screen.
                            HubTimeline(model: model, compact: geo.size.width < 1_000)
                                .frame(maxWidth: max(640, geo.size.width * 0.58))
                            Spacer(minLength: 0)
                            HubBoard(model: model)
                        }
                        .padding(14)
                    } else {
                        VStack(spacing: 10) {
                            if model.showsInspector, let occupant = model.focusedOccupant {
                                HubInspector(model: model, occupant: occupant)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            HubTimeline(model: model, compact: true)
                        }
                        .padding(12)
                    }
                }
            }
            .animation(.smooth(duration: 0.3), value: model.showsInspector)
            .animation(.smooth(duration: 0.3), value: model.focus)
        }
    }

    /// The callout floats over its aircraft but never under the chrome:
    /// held between the KPI row and the timeline, and clear of the inspector
    /// (reference shot B shows it whole, over the jet).
    private func calloutCenter(_ anchor: CGPoint, size: CGSize, wide: Bool) -> CGPoint {
        let half = CGSize(width: 118, height: 80)
        let top = (wide ? 214 : 250) + half.height
        let bottom = size.height - (wide ? 170 : 190) - half.height
        let left = 12 + half.width
        let right = (wide && model.showsInspector ? size.width - 330 : size.width - 12) - half.width
        let x = min(max(anchor.x, left), max(left, right))
        let y = min(max(anchor.y - 60 - half.height, top), max(top, bottom))
        return CGPoint(x: x, y: y)
    }

    @ViewBuilder
    private func anchored(_ item: HubProjectedAnchor) -> some View {
        switch item.anchor.kind {
        case .callout:
            if let occupant = model.focusedOccupant {
                HubCallout(occupant: occupant)
                    .onTapGesture { model.showsInspector = true }
            }
        case .pin(let label):
            HubPin(label: label).offset(y: -24)
        case .pill(let label, let image):
            HubPill(label: label, systemImage: image)
        }
    }
}
