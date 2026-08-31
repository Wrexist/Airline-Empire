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
    /// Owned here, one per map screen: the cached geometry the frames replay.
    /// Plain state (not observable) — the draw reads and writes it without
    /// invalidating the view that is drawing.
    @State private var renderCache = MapRenderCache()
    /// Draw-cost and label-churn totals, collected only under
    /// `-AEUITestProbes` and published through the canvas's accessibility
    /// value so a UI test can drag the real map and read real numbers.
    @State private var drawStats = MapDrawStats()
    private var probesEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-AEUITestProbes")
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if let snapshot = controller.snapshot, let model = controller.mapModel {
                    ZStack {
                        // The canvas bleeds past the bottom safe area so the
                        // world runs under the floating tab bar; the chrome
                        // deliberately does not. They used to share one
                        // `ignoresSafeArea` on this ZStack, and the tab bar
                        // was drawn straight over the idle hint — "Tap an
                        // airport, a route or an aircraft." was on screen and
                        // unreadable in every frame that had it (AE-033 audit
                        // §6.1). It hid for a whole phase because the taller
                        // "Your airline begins here" card clears the bar, and
                        // the short hint only appears once a player has routes.
                        canvas(model: model, snapshot: snapshot, size: geometry.size)
                            .ignoresSafeArea(edges: .bottom)
                        chrome(model: model, snapshot: snapshot)
                    }
                    // Every edge, deliberately. A bare `Color` background
                    // bleeds into the safe areas on its own; the moment it is
                    // wrapped in a modifier it stops, and run 75 photographed
                    // the consequence — a white status-bar strip above the
                    // near-black map, where run 74 had the map's own dark.
                    .background(AETheme.mapBackground.ignoresSafeArea())
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
                                        : 0,
                                     tick: referenceDate,
                                     settle: camera.settleGeneration,
                                     cache: renderCache)
                let drawStart = probesEnabled ? DispatchTime.now() : nil
                frame.draw(into: &context, size: canvasSize)
                if let drawStart {
                    let ms = Double(DispatchTime.now().uptimeNanoseconds
                                    - drawStart.uptimeNanoseconds) / 1e6
                    drawStats.record(drawMs: ms, labels: frame.placedLabels)
                }
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
        // The probe's totals ride the same channel as the zoom, and only
        // under the flag: the value a VoiceOver user hears never carries
        // engineering numbers.
        if probesEnabled {
            parts.append(drawStats.summary)
            parts.append(renderCache.counterSummary)
        }
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
    /// Bumped whenever a camera *intent* completes — a drag or pinch
    /// commits, a zoom button or double tap fires, the network is framed.
    /// The label memory re-decides on this signal rather than per frame
    /// (docs/MAP_RUNTIME_BASELINE.md §3): during the gesture the choices
    /// are frozen and only move with the world.
    private(set) var settleGeneration = 0

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
        settleGeneration += 1
        let landed = liveCenter(size: size)
        center = landed
        panOffset = .zero
        guard glide, let predicted else { return }
        // liveZoom, not zoom: during a combined pinch-drag the pinch may not
        // have committed yet, and a coast scaled by the wrong world width
        // overshoots by the pinch factor (baseline §4).
        let worldWidth = max(1, size.width * liveZoom)
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
        settleGeneration += 1
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
        settleGeneration += 1
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
        settleGeneration += 1
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
        settleGeneration += 1
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
    private var routeTransform: CGAffineTransform = .identity
    private var selectedRoute: (MapModel.MapRoute, [CGPoint])?

    func store(_ geometry: MapFrame.Geometry) {
        airports = geometry.airports
        flights = geometry.flights
        routes = geometry.routes
        routeTransform = geometry.routeTransform
        selectedRoute = geometry.selectedRoute
    }

    func hit(at location: CGPoint) -> MapHit? {
        // Route polylines live in the route cache's screen space; the tap is
        // carried to them through the inverse of the transform they are
        // displayed under — the same agreement as before ("hit what was
        // drawn"), tested from the other side. The tolerance is a screen
        // quantity, so it is scaled into cache space alongside the point.
        let inverse = routeTransform.inverted()
        let scale = max(0.0001, sqrt(abs(routeTransform.a * routeTransform.d)))
        var cacheRoutes = routes
        if let selectedRoute {
            // The selected route was drawn per frame in current screen
            // space; bring it into the same space as the rest.
            cacheRoutes.append((selectedRoute.0,
                                selectedRoute.1.map { $0.applying(inverse) }))
        }
        return MapHitTester.hit(at: location, airports: airports,
                                flights: flights,
                                routes: cacheRoutes,
                                routeLocation: location.applying(inverse),
                                routeTolerance: 26 / scale)
    }
}
