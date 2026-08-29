import SwiftUI
import AirlineEmpireCore

/// The world map (docs/MAP_ARCHITECTURE.md).
///
/// ## Renderer
///
/// One `SwiftUI.Canvas` inside a `TimelineView`. Immediate-mode: the whole map
/// is a single view drawing a few thousand primitives per frame, rather than a
/// view per airport — which is what makes a SwiftUI map fall over. SpriteKit
/// would add a scene graph and a second run loop for objects that move every
/// frame anyway; Metal is a lot of machinery for ~3–5k path segments. Canvas
/// is the simplest thing that meets the requirement, and it composites on the
/// same path as the rest of the UI.
///
/// ## Layers, back to front
///
/// ocean → graticule → land → event regions → opportunity arcs → rival routes
/// → player routes → airports → flights → labels
///
/// Order is the hierarchy: geography never draws over the network, and the
/// player's airline never draws under a rival's.
struct MapScreen: View {
    @Environment(GameController.self) private var controller
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var camera = MapCamera()
    @State private var selection: MapHit?
    @State private var overlay: MapOverlay = .network
    @State private var routeDraft: RouteDraft?
    @State private var hasFramedHome = false
    /// Frozen geometry from the last draw, so a tap resolves against exactly
    /// what the player saw rather than against a recomputed layout.
    @State private var hitGeometry = MapHitGeometry()

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if let snapshot = controller.snapshot, let model = controller.mapModel {
                    ZStack {
                        canvas(model: model, snapshot: snapshot, size: geometry.size)
                        chrome(model: model, snapshot: snapshot)
                    }
                    .background(AETheme.mapBackground)
                    .onAppear { frameHomeOnce(model) }
                } else {
                    LoadingState(message: "Drawing the world")
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .ignoresSafeArea(edges: .bottom)
            .sheet(item: $routeDraft) { draft in
                OpenRouteSheet(suggestion: draft.suggestion)
            }
            .navigationDestination(for: RouteID.self) { RouteDetailView(routeID: $0) }
            .navigationDestination(for: AircraftID.self) { AircraftDetailView(aircraftID: $0) }
        }
    }

    // MARK: - The canvas

    private func canvas(model: MapModel, snapshot: GameState,
                        size: CGSize) -> some View {
        // Paused stops the clock entirely, so nothing animates and the battery
        // is left alone. Reduce Motion does the same: the map still updates
        // every snapshot, it just stops interpolating between them.
        let animating = controller.speed != .paused && !reduceMotion
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                       paused: !animating)) { timeline in
            Canvas(opaque: true, rendersAsynchronously: false) { context, canvasSize in
                let projector = MapProjector(zoom: camera.liveZoom,
                                             center: camera.liveCenter(size: canvasSize),
                                             size: canvasSize)
                let policy = MapDetailPolicy(level: MapZoomLevel(zoom: camera.liveZoom),
                                             zoom: camera.liveZoom)
                var frame = MapFrame(model: model, snapshot: snapshot,
                                     projector: projector, policy: policy,
                                     overlay: overlay, selection: selection,
                                     speed: controller.speed,
                                     elapsed: animating
                                        ? timeline.date.timeIntervalSince(referenceDate)
                                        : 0)
                frame.draw(into: &context, size: canvasSize)
                // Handing the drawn geometry back is what keeps hit-testing
                // honest — the tap resolves against the frame on screen.
                //
                // Stored straight from the draw, with no hop. `MapHitGeometry`
                // is a plain class and deliberately not `@Observable`, so
                // writing it cannot invalidate the view that is drawing; the
                // hop bought nothing and cost a frame of staleness.
                hitGeometry.store(frame.geometry)
            }
            .contentShape(Rectangle())
            .gesture(SimultaneousGesture(dragGesture(size: size), zoomGesture(size: size)))
            .onTapGesture { location in handleTap(at: location, model: model) }
            .accessibilityElement()
            .accessibilityLabel("World map")
            .accessibilityValue(accessibilitySummary(model))
            .accessibilityHint("Double tap an airport, route or aircraft to select it")
        }
    }

    /// A fixed epoch so `elapsed` is monotonic across frames without storing
    /// a start date that a view rebuild would reset.
    private var referenceDate: Date { controller.snapshotReceivedAt }

    // MARK: - Chrome

    @ViewBuilder
    private func chrome(model: MapModel, snapshot: GameState) -> some View {
        VStack(spacing: 0) {
            MapTopBar(model: model, snapshot: snapshot)
                .padding(.horizontal, AETheme.spacingM)
                .padding(.top, AETheme.spacingS)

            HStack(alignment: .top) {
                MapOverlayPicker(selection: $overlay)
                Spacer()
                MapZoomControls(
                    zoomIn: { camera.zoomBy(1.7) },
                    zoomOut: { camera.zoomBy(1 / 1.7) },
                    frame: { camera.frameNetwork(model) })
            }
            .padding(.horizontal, AETheme.spacingM)
            .padding(.top, AETheme.spacingS)

            Spacer()

            MapSelectionPanel(
                selection: selection,
                model: model,
                snapshot: snapshot,
                overlay: overlay,
                dismiss: { withAnimation(AEMotion.content) { selection = nil } },
                openRoute: { routeDraft = RouteDraft(suggestion: $0) })
                .padding(.horizontal, AETheme.spacingM)
                .padding(.bottom, AETheme.spacingS)
        }
    }

    // MARK: - Interaction

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { camera.panOffset = $0.translation }
            .onEnded { _ in camera.commitPan(size: size) }
    }

    private func zoomGesture(size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { camera.pinch = $0.magnification }
            .onEnded { _ in camera.commitZoom() }
    }

    private func handleTap(at location: CGPoint, model: MapModel) {
        let hit = hitGeometry.hit(at: location)
        withAnimation(AEMotion.content) { selection = hit }
    }

    private func frameHomeOnce(_ model: MapModel) {
        guard !hasFramedHome else { return }
        hasFramedHome = true
        camera.frameNetwork(model)
    }

    private func accessibilitySummary(_ model: MapModel) -> String {
        let mine = model.routes.filter(\.isPlayer).count
        let airborne = model.flights.filter { $0.isPlayer && $0.airborne }.count
        let served = model.airports.filter(\.servedByPlayer).count
        let events = model.events.filter(\.hasStarted).count
        var parts = ["\(mine) routes across \(served) airports",
                     "\(airborne) aircraft in the air"]
        if events > 0 { parts.append("\(events) world events active") }
        if let hit = selection { parts.append(describe(hit, model: model)) }
        return parts.joined(separator: ". ")
    }

    private func describe(_ hit: MapHit, model: MapModel) -> String {
        switch hit {
        case .airport(let code):
            "Selected \(model.airports.first { $0.code == code }?.city ?? code.raw)"
        case .route(let id):
            model.routes.first { $0.id == id }
                .map { "Selected route \($0.origin.raw) to \($0.destination.raw)" }
                ?? "Selected a route"
        case .aircraft(let id):
            model.flights.first { $0.id == id }
                .map { "Selected a flight to \($0.destination.raw)" }
                ?? "Selected an aircraft"
        }
    }
}

// MARK: - Camera

/// Pan and zoom, with the in-flight gesture kept separate from the committed
/// value so a drag never accumulates rounding error into the camera.
@Observable
final class MapCamera {
    var zoom: CGFloat = 2.2
    var center = CGPoint(x: 0.5, y: 0.42)
    var panOffset: CGSize = .zero
    var pinch: CGFloat = 1

    static let minZoom: CGFloat = 1
    static let maxZoom: CGFloat = 16

    var liveZoom: CGFloat {
        min(Self.maxZoom, max(Self.minZoom, zoom * pinch))
    }

    func liveCenter(size: CGSize) -> CGPoint {
        let worldWidth = size.width * liveZoom
        let worldHeight = max(1, worldWidth / 2)
        return clamp(CGPoint(x: center.x - panOffset.width / max(1, worldWidth),
                             y: center.y - panOffset.height / worldHeight))
    }

    func commitPan(size: CGSize) {
        center = liveCenter(size: size)
        panOffset = .zero
    }

    func commitZoom() {
        zoom = liveZoom
        pinch = 1
    }

    func zoomBy(_ factor: CGFloat) {
        withAnimation(AEMotion.selection) {
            zoom = min(Self.maxZoom, max(Self.minZoom, zoom * factor))
        }
    }

    /// Fits the player's own airports — the view a player actually wants and
    /// previously had no way to ask for. Falls back to the whole world for an
    /// airline that has not flown anywhere yet.
    func frameNetwork(_ model: MapModel) {
        let mine = model.airports.filter { $0.servedByPlayer || $0.isPlayerHome }
        guard !mine.isEmpty else {
            withAnimation(AEMotion.content) {
                zoom = 1.4
                center = CGPoint(x: 0.5, y: 0.42)
            }
            return
        }
        let xs = mine.map(\.position.x), ys = mine.map(\.position.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 1
        // The 2:1 world means a degree of latitude covers twice the normalised
        // span of a degree of longitude, so the y extent counts double.
        let span = max(maxX - minX, (maxY - minY) * 2, 0.03)
        withAnimation(AEMotion.content) {
            center = clamp(CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2))
            zoom = min(Self.maxZoom, max(Self.minZoom, 0.8 / span))
        }
    }

    /// Keeps the camera inside the world, and — because the viewport is
    /// shorter than the world is tall at low zoom — lets y breathe a little
    /// rather than pinning the poles to the screen edge.
    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(1, max(0, point.x)), y: min(0.95, max(0.05, point.y)))
    }
}

/// The geometry the last frame actually drew, so a tap hits what was seen.
///
/// Deliberately *not* `@Observable`: it is written from inside the draw and
/// read only on a tap. Observing it would let a frame's own output invalidate
/// the view that produced it, which is a redraw loop nobody would enjoy
/// finding at 30 frames a second.
final class MapHitGeometry {
    private var airports: [(MapModel.MapAirport, CGPoint)] = []
    private var flights: [(InterpolatedFlight, CGPoint)] = []
    private var routes: [(MapModel.MapRoute, [CGPoint])] = []

    func store(_ geometry: MapFrame.Geometry) {
        airports = geometry.airports
        flights = geometry.flights
        routes = geometry.routes
    }

    func hit(at location: CGPoint) -> MapHit? {
        MapHitTester.hit(at: location, airports: airports, flights: flights,
                         routes: routes)
    }
}
