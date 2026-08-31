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
    @Environment(\.feedback) private var feedback

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
                    // BUG-036. The canvas is fixed near-black in both
                    // appearances by design (docs/MAP_ARCHITECTURE.md §2), but
                    // the chrome over it is glass and system materials, which
                    // follow the *system* appearance. In light mode that put
                    // pale glass under text hardcoded to white: the "Your
                    // airline begins here" card — the only thing telling a new
                    // player what the dashed lines are — was white on near-white.
                    //
                    // Pinning the environment rather than restyling the chrome:
                    // the map is a dark surface, so the honest fix is to say so
                    // once, here, and let every material and semantic colour
                    // inside resolve against it. Sheets and pushed destinations
                    // are attached outside this ZStack and keep the system
                    // appearance, which is right — they are ordinary surfaces.
                    .environment(\.colorScheme, .dark)
                    .onAppear {
                        frameHomeOnce(model)
                        reportFocus()
                    }
                    // The soundscape follows the camera and the selection.
                    // Reported rather than applied: the bed is re-derived on
                    // the next snapshot, so a pinch does not touch the audio
                    // graph on every gesture frame
                    // (docs/AUDIO_ARCHITECTURE.md §6).
                    .onChange(of: MapZoomLevel(zoom: camera.zoom)) { _, _ in
                        reportFocus()
                    }
                    .onChange(of: selection) { _, _ in reportFocus() }
                    .onDisappear { feedback.clearMapFocus() }
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
            // Double tap before single tap: SwiftUI gives the higher count
            // first refusal, and a single tap still selects after the
            // double-tap window lapses. Declared the other way round the
            // double tap is unreachable.
            .onTapGesture(count: 2) { location in
                camera.zoomIn(about: location, size: size)
            }
            .onTapGesture { location in handleTap(at: location, model: model) }
            .accessibilityElement()
            .accessibilityIdentifier("ae-map-canvas")
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
            .onEnded { value in
                // Reduce Motion means what it says: the map still goes where
                // the finger left it, it just stops there.
                camera.commitPan(size: size,
                                 predicted: value.predictedEndTranslation,
                                 glide: !reduceMotion)
            }
    }

    private func zoomGesture(size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // The anchor is captured on the first change rather than in an
                // onBegan, because MagnifyGesture has no onBegan and the first
                // change still carries a magnification of very nearly 1.
                camera.beginPinch(at: value.startLocation, size: size)
                camera.pinch = value.magnification
            }
            .onEnded { _ in camera.commitZoom(size: size) }
    }

    private func handleTap(at location: CGPoint, model: MapModel) {
        let hit = hitGeometry.hit(at: location)
        withAnimation(AEMotion.content) { selection = hit }
    }

    /// Translates the renderer's zoom ladder into the one Core's soundscape
    /// policy speaks. Two enums rather than one because Core cannot know
    /// about `CGFloat` zoom, and the map cannot own audio policy.
    private func reportFocus() {
        let level = MapZoomLevel(zoom: camera.zoom)
        let focus: SoundscapeFocus = switch level {
        case .world: SoundscapeFocus.world
        case .regional: SoundscapeFocus.regional
        case .local: SoundscapeFocus.local
        }
        feedback.setMapFocus(focus, hasSelection: selection != nil)
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
                     "\(airborne) aircraft in the air",
                     // The camera, so a gesture can be *proved* to have moved
                     // it. Run 59 photographed three "zoom levels" that were
                     // byte-identical: the pinch had done nothing, the test
                     // asserted only that the canvas existed, and the audit
                     // recorded zoom coverage the app never had (BUG-039).
                     // One decimal is enough to see every step of the 1.7×
                     // buttons and the clamps at either end.
                     String(format: "zoom %.1fx", camera.liveZoom)]
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

    /// Where the pinch started on screen, and the world point that was under
    /// it. Together they are what makes the map zoom about the fingers.
    private var pinchAnchor: CGPoint?
    private var pinchWorld: CGPoint?

    static let minZoom: CGFloat = 1
    static let maxZoom: CGFloat = 16

    /// Zoom during a pinch, resisting rather than stopping at the limits.
    ///
    /// A hard clamp is what makes a map feel broken at the ends: the fingers
    /// keep moving and nothing happens, so the gesture reads as dropped. The
    /// exponent turns overshoot into resistance — it still moves, just less —
    /// and `commitZoom` springs it back.
    var liveZoom: CGFloat {
        let raw = zoom * pinch
        if raw > Self.maxZoom { return Self.maxZoom * pow(raw / Self.maxZoom, 0.30) }
        if raw < Self.minZoom { return Self.minZoom * pow(raw / Self.minZoom, 0.30) }
        return raw
    }

    func liveCenter(size: CGSize) -> CGPoint {
        centre(at: liveZoom, size: size, pan: panOffset)
    }

    /// The camera centre for a given zoom, holding the pinch anchor fixed.
    ///
    /// The whole of "zoom about the fingers" is the second branch: solve
    /// `project(world) == anchor` for the centre. `MapProjector.unproject`
    /// was written for this and then never called — the map had the arithmetic
    /// to follow a pinch and zoomed about the screen centre anyway, which is
    /// why the thing under your fingers slid away as you pinched it.
    private func centre(at zoomValue: CGFloat, size: CGSize,
                        pan: CGSize) -> CGPoint {
        let worldWidth = max(1, size.width * zoomValue)
        let worldHeight = max(1, worldWidth / 2)
        var base = center
        if let anchor = pinchAnchor, let world = pinchWorld {
            base = CGPoint(x: world.x - (anchor.x - size.width / 2) / worldWidth,
                           y: world.y - (anchor.y - size.height / 2) / worldHeight)
        }
        return clamp(CGPoint(x: base.x - pan.width / worldWidth,
                             y: base.y - pan.height / worldHeight))
    }

    /// Remember what the fingers landed on, in world space, before the
    /// magnification starts changing the projection under them.
    func beginPinch(at anchor: CGPoint, size: CGSize) {
        guard pinchAnchor == nil else { return }
        let projector = MapProjector(zoom: liveZoom,
                                     center: liveCenter(size: size), size: size)
        pinchAnchor = anchor
        pinchWorld = projector.unproject(anchor)
    }

    /// Fold a finished drag into the camera, and let it coast.
    ///
    /// `predictedEndTranslation` is UIKit's own estimate of where the finger
    /// was heading, which is what a flick expects to do on any map made in the
    /// last fifteen years. Damped to 45%: the full prediction overshoots
    /// badly on a small screen, and a map that sails past what you flicked at
    /// is worse than one that does not coast at all.
    func commitPan(size: CGSize, predicted: CGSize? = nil, glide: Bool = true) {
        let landed = liveCenter(size: size)
        center = landed
        panOffset = .zero
        guard glide, let predicted else { return }
        let worldWidth = max(1, size.width * zoom)
        let worldHeight = max(1, worldWidth / 2)
        let coast = CGSize(width: predicted.width * 0.45,
                           height: predicted.height * 0.45)
        let target = clamp(CGPoint(x: landed.x - coast.width / worldWidth,
                                   y: landed.y - coast.height / worldHeight))
        guard hypot(target.x - landed.x, target.y - landed.y) > 0.0004 else { return }
        withAnimation(.interpolatingSpring(stiffness: 42, damping: 14)) {
            center = target
        }
    }

    /// Fold a finished pinch in, springing back if it was pushed past a limit.
    func commitZoom(size: CGSize) {
        let settled = min(Self.maxZoom, max(Self.minZoom, zoom * pinch))
        let overshot = abs(settled - liveZoom) > 0.001
        // Resolve the anchored centre at the zoom we are actually keeping,
        // so releasing a pinch does not shift what is under the fingers.
        center = centre(at: settled, size: size, pan: .zero)
        pinchAnchor = nil
        pinchWorld = nil
        pinch = 1
        if overshot {
            withAnimation(.interpolatingSpring(stiffness: 180, damping: 18)) {
                zoom = settled
            }
        } else {
            zoom = settled
        }
    }

    func zoomBy(_ factor: CGFloat) {
        withAnimation(AEMotion.selection) {
            zoom = min(Self.maxZoom, max(Self.minZoom, zoom * factor))
        }
    }

    /// Double tap: in by a step, about the point tapped.
    ///
    /// The step is the same 1.7 the on-screen buttons use, so the two ways of
    /// zooming agree. Anchored for the same reason the pinch is — a double tap
    /// on Tokyo should end up looking at Tokyo.
    func zoomIn(about point: CGPoint, size: CGSize) {
        let target = min(Self.maxZoom, zoom * 1.7)
        let projector = MapProjector(zoom: zoom, center: center, size: size)
        let world = projector.unproject(point)
        let worldWidth = max(1, size.width * target)
        let worldHeight = max(1, worldWidth / 2)
        let settled = clamp(CGPoint(
            x: world.x - (point.x - size.width / 2) / worldWidth,
            y: world.y - (point.y - size.height / 2) / worldHeight))
        withAnimation(.interpolatingSpring(stiffness: 120, damping: 16)) {
            zoom = target
            center = settled
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
