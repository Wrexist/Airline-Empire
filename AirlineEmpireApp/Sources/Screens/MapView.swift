import SwiftUI
import AirlineEmpireCore

/// The interactive world map (docs/UI_ARCHITECTURE.md §3): renders `MapModel`
/// — Core-computed positions, arcs, and interpolated flights — on a zoomable
/// Canvas. Renderer-only: no gameplay math here.
///
/// ## What changed
///
/// The design documents call the map "the emotional centerpiece" and "the
/// primary lens", and it was a scatter plot: no land, nothing marking home,
/// no legend, and no actions at all — you could select an airport and then do
/// nothing with it, so `docs/CORE_LOOP.md` §6's "open a route in ≤4 taps
/// *from the map*" was impossible (UIUX_FORENSIC_AUDIT UI-009).
///
/// Now there is a world under the network (`WorldOutline`), home is marked,
/// the legend says what the colours mean, a selected airport can start a route
/// or open the one you already fly, and pan and zoom compose instead of
/// replacing one another.
struct MapScreen: View {
    @Environment(GameController.self) private var controller
    @State private var zoom: CGFloat = 1.6
    @State private var center = CGPoint(x: 0.42, y: 0.32)
    @State private var gestureZoom: CGFloat = 1
    @State private var gestureOffset = CGSize.zero
    @State private var selectedAirport: AirportCode?
    @State private var routeSheet: RouteDraft?
    @State private var hasFramedHome = false

    /// Pan and zoom applied live during a gesture, without committing.
    private var liveZoom: CGFloat { min(12, max(1, zoom * gestureZoom)) }

    private func liveCenter(size: CGSize) -> CGPoint {
        let worldWidth = size.width * liveZoom
        let worldHeight = worldWidth / 2
        return CGPoint(
            x: min(1, max(0, center.x - gestureOffset.width / max(1, worldWidth))),
            y: min(1, max(0, center.y - gestureOffset.height / max(1, worldHeight))))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if let snapshot = controller.snapshot, let catalog = controller.catalog,
                   let model = controller.mapModel {
                    let home = snapshot.playerAirline?.homeAirport
                    ZStack(alignment: .bottom) {
                        MapCanvas(model: model, zoom: liveZoom,
                                  center: liveCenter(size: geometry.size),
                                  home: home,
                                  selectedAirport: selectedAirport)
                            .background(AETheme.mapBackground)
                            .contentShape(Rectangle())
                            // `.gesture` twice replaced the first with the
                            // second; composing them is what makes pan and
                            // zoom both work.
                            .gesture(
                                SimultaneousGesture(dragGesture(size: geometry.size),
                                                    zoomGesture))
                            .onTapGesture { location in
                                select(at: location, model: model,
                                       size: geometry.size)
                            }

                        VStack(spacing: AETheme.spacingS) {
                            Spacer()
                            if let code = selectedAirport {
                                AirportCallout(
                                    code: code,
                                    dismiss: { withAnimation(.snappy) { selectedAirport = nil } },
                                    openRoute: { routeSheet = RouteDraft(suggestion: $0) })
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            } else {
                                MapLegend()
                                    .transition(.opacity)
                            }
                        }
                        .padding(AETheme.spacingM)

                        VStack {
                            HStack {
                                Spacer()
                                zoomControls(home: home, model: model)
                            }
                            Spacer()
                        }
                        .padding(AETheme.spacingM)
                    }
                    // Tapping an airport should feel like the panel rises to
                    // meet you, and tapping away like it leaves.
                    .aeAnimation(AEMotion.content, value: selectedAirport)
                    .sensoryFeedback(.selection, trigger: selectedAirport)
                    .ignoresSafeArea(edges: .bottom)
                    .onAppear {
                        // Open on the player's own network, not on a hardcoded
                        // slice of Europe.
                        if !hasFramedHome, let home, let airport = catalog.airport(home) {
                            let point = MapPoint(coordinate: airport.coordinate)
                            center = CGPoint(x: point.x, y: point.y)
                            zoom = 3.2
                            hasFramedHome = true
                        }
                    }
                } else {
                    LoadingState(message: "Drawing the world")
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { SpeedControl() }
            }
            .sheet(item: $routeSheet) { draft in
                OpenRouteSheet(suggestion: draft.suggestion)
            }
            // The callout links to a route the player already flies.
            .navigationDestination(for: RouteID.self) { RouteDetailView(routeID: $0) }
        }
    }

    /// Zoom without pinching, which is the only way this map was reachable for
    /// anyone who cannot make that gesture.
    private func zoomControls(home: AirportCode?, model: MapModel) -> some View {
        VStack(spacing: 1) {
            Button { withAnimation(.snappy) { zoom = min(12, zoom * 1.6) } } label: {
                Image(systemName: "plus").frame(width: 44, height: 44)
            }
            Divider().frame(width: 28)
            Button { withAnimation(.snappy) { zoom = max(1, zoom / 1.6) } } label: {
                Image(systemName: "minus").frame(width: 44, height: 44)
            }
            Divider().frame(width: 28)
            Button {
                withAnimation(.snappy) { frameNetwork(model: model, home: home) }
            } label: {
                Image(systemName: "scope").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Frame my network")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .aeGlass(in: RoundedRectangle(cornerRadius: AETheme.cornerRadius,
                                      style: .continuous))
    }

    /// Fits the player's own airports, which is the view a player wants and
    /// had no way to ask for.
    private func frameNetwork(model: MapModel, home: AirportCode?) {
        let mine = model.airports.filter { $0.servedByPlayer || $0.code == home }
        guard !mine.isEmpty else { return }
        let xs = mine.map(\.position.x)
        let ys = mine.map(\.position.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 1
        center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        // The 2:1 world means the y span counts double in normalised terms.
        let span = max(maxX - minX, (maxY - minY) * 2, 0.02)
        zoom = min(12, max(1, 0.85 / span))
    }

    // MARK: Interaction

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                // Live translation, so the map tracks the finger exactly —
                // the old handler scaled by 1/zoom *and* 0.05, so panning at
                // low zoom barely moved.
                gestureOffset = value.translation
            }
            .onEnded { _ in
                center = liveCenter(size: size)
                gestureOffset = .zero
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in gestureZoom = value.magnification }
            .onEnded { _ in
                zoom = liveZoom
                gestureZoom = 1
            }
    }

    private func select(at location: CGPoint, model: MapModel, size: CGSize) {
        let projector = MapProjector(zoom: liveZoom, center: liveCenter(size: size),
                                     size: size)
        var best: (AirportCode, CGFloat)?
        for airport in model.airports {
            let point = projector.project(airport.position)
            let distance = hypot(point.x - location.x, point.y - location.y)
            if distance < 32, distance < (best?.1 ?? .infinity) {
                best = (airport.code, distance)
            }
        }
        withAnimation(.snappy) { selectedAirport = best?.0 }
    }
}

/// Normalized map space → screen points.
struct MapProjector {
    let zoom: CGFloat
    let center: CGPoint
    let size: CGSize

    func project(_ point: MapPoint) -> CGPoint {
        // World aspect 2:1 (equirectangular); fit width.
        let worldWidth = size.width * zoom
        let worldHeight = worldWidth / 2
        let x = (CGFloat(point.x) - center.x) * worldWidth + size.width / 2
        let y = (CGFloat(point.y) - center.y) * worldHeight + size.height / 2
        return CGPoint(x: x, y: y)
    }
}

struct MapCanvas: View {
    let model: MapModel
    let zoom: CGFloat
    let center: CGPoint
    let home: AirportCode?
    let selectedAirport: AirportCode?

    var body: some View {
        Canvas { context, canvasSize in
            let projector = MapProjector(zoom: zoom, center: center, size: canvasSize)

            // The world, under the network. `AETheme.mapLand` was declared and
            // never used, so the map was dots on a flat navy rectangle with no
            // way to tell the Atlantic from the Pacific.
            for landmass in WorldOutline.landmasses {
                var path = Path()
                for (index, point) in landmass.enumerated() {
                    let projected = projector.project(point)
                    if index == 0 { path.move(to: projected) }
                    else { path.addLine(to: projected) }
                }
                path.closeSubpath()
                context.fill(path, with: .color(AETheme.mapLand))
                context.stroke(path, with: .color(AETheme.mapCoast), lineWidth: 0.6)
            }

            // Routes next (under the markers). LOD: rival routes fade at
            // low zoom to keep the picture readable.
            for route in model.routes {
                var path = Path()
                var first = true
                for point in route.arc {
                    let projected = projector.project(point)
                    if first { path.move(to: projected); first = false }
                    else { path.addLine(to: projected) }
                }
                let color = route.isPlayer
                    ? (route.profitable ? AETheme.playerRoute : AETheme.caution)
                    : AETheme.rivalRoute
                // Frequency is in the model and was never drawn; a trunk route
                // should look like one.
                let weight = min(3.2, 1.2 + CGFloat(route.dailyRoundTrips) * 0.22)
                let width: CGFloat = route.isPlayer ? weight : (zoom > 3 ? 1.0 : 0.5)
                context.stroke(path, with: .color(color.opacity(route.isPlayer ? 0.9 : 0.45)),
                               lineWidth: width)
            }

            // Airports. LOD by prominence: small fields appear as you zoom.
            for airport in model.airports {
                let isHome = airport.code == home
                let visible = airport.servedByPlayer || isHome
                    || airport.prominence > 0.35
                    || zoom > 3
                guard visible else { continue }
                let point = projector.project(airport.position)
                guard point.x > -20, point.x < canvasSize.width + 20,
                      point.y > -20, point.y < canvasSize.height + 20 else { continue }
                let radius: CGFloat = 2.5 + CGFloat(airport.prominence) * 3
                    + (airport.servedByPlayer ? 1.5 : 0) + (isHome ? 1.5 : 0)
                let rect = CGRect(x: point.x - radius, y: point.y - radius,
                                  width: radius * 2, height: radius * 2)
                let color: Color = airport.closed ? AETheme.negative
                    : isHome ? AETheme.ember
                    : airport.servedByPlayer ? AETheme.playerRoute : .white.opacity(0.7)
                context.fill(Path(ellipseIn: rect), with: .color(color))
                if isHome {
                    // Home gets a ring of its own, so "where am I" is never a
                    // question on this screen.
                    context.stroke(Path(ellipseIn: rect.insetBy(dx: -5, dy: -5)),
                                   with: .color(AETheme.ember.opacity(0.8)),
                                   lineWidth: 1.5)
                }
                if airport.code == selectedAirport {
                    context.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)),
                                   with: .color(.white), lineWidth: 1.5)
                }
                if zoom > 2.5 || airport.servedByPlayer || isHome {
                    context.draw(Text(airport.code.raw)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85)),
                        at: CGPoint(x: point.x, y: point.y - radius - 8))
                }
            }

            // Live aircraft on top.
            for flight in model.flights where flight.airborne {
                let point = projector.project(flight.position)
                guard point.x > -20, point.x < canvasSize.width + 20,
                      point.y > -20, point.y < canvasSize.height + 20 else { continue }
                var symbol = context
                symbol.translateBy(x: point.x, y: point.y)
                symbol.rotate(by: .degrees(flight.heading))
                symbol.draw(Text(Image(systemName: "airplane"))
                    .font(.system(size: flight.isPlayer ? 13 : 10))
                    .foregroundStyle(flight.isPlayer ? AETheme.playerRoute : .gray),
                    at: .zero)
            }
        }
        .accessibilityLabel("World map")
        .accessibilityValue(summary)
    }

    /// The map is a `Canvas`, which VoiceOver cannot read into. A summary is
    /// not a substitute for the picture, but it is the difference between
    /// "some drawing" and knowing what the network is.
    private var summary: String {
        let mine = model.routes.filter(\.isPlayer)
        let airborne = model.flights.filter { $0.isPlayer && $0.airborne }.count
        let served = model.airports.filter(\.servedByPlayer).count
        return "\(mine.count) of your routes across \(served) airports, \(airborne) aircraft in the air."
    }
}

/// What the colours mean. There was no legend, so a red dot or an amber line
/// was a mystery.
struct MapLegend: View {
    var body: some View {
        HStack(spacing: AETheme.spacingM) {
            key(AETheme.ember, "Home")
            key(AETheme.playerRoute, "Yours")
            key(AETheme.caution, "Losing money")
            key(AETheme.rivalRoute, "Rivals")
        }
        .padding(.horizontal, AETheme.spacingM)
        .padding(.vertical, AETheme.spacingS)
        .aeGlass(in: Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: amber is home, cyan is yours, orange is losing money, grey is rivals")
    }

    private func key(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2)
        }
        .foregroundStyle(.white.opacity(0.85))
    }
}

/// Selection now leads somewhere (docs/CORE_LOOP.md §6: opening a route from
/// the map). Before, it was a panel of facts with no actions on it at all.
struct AirportCallout: View {
    @Environment(GameController.self) private var controller
    let code: AirportCode
    let dismiss: () -> Void
    let openRoute: (FirstRouteSuggestion) -> Void

    var body: some View {
        AECard {
            if let catalog = controller.catalog,
               let spec = catalog.airport(code),
               let snapshot = controller.snapshot {
                VStack(alignment: .leading, spacing: AETheme.spacingS) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(spec.name) (\(code.raw))").font(.headline)
                            Text("\(spec.city), \(spec.country)")
                                .font(.caption)
                                .foregroundStyle(AETheme.mutedText)
                        }
                        Spacer(minLength: AETheme.spacingS)
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(AETheme.mutedText)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }
                    HStack(spacing: AETheme.spacingXS) {
                        AEChip(icon: "airplane",
                               text: "slots \(snapshot.world.slotsUsed(at: code))/\(spec.slotCapacityPerDay)")
                        AEChip(icon: "road.lanes", text: Vocab.runwayDetail(spec.runwayClass))
                        if snapshot.world.isAirportClosed(code, at: snapshot.clock.now) {
                            AEChip(icon: "xmark.octagon.fill", text: "Closed")
                        }
                    }
                    if let home = snapshot.playerAirline?.homeAirport,
                       let distance = catalog.distanceKm(home, code), code != home {
                        Text("\(distance) km from \(home.raw)")
                            .font(.caption)
                            .foregroundStyle(AETheme.mutedText)
                    }
                    actions(snapshot: snapshot, catalog: catalog, spec: spec)
                }
            }
        }
    }

    @ViewBuilder
    private func actions(snapshot: GameState, catalog: ContentCatalog,
                         spec: AirportSpec) -> some View {
        if let player = snapshot.playerAirline {
            let existing = snapshot.routes(of: player.id).filter {
                $0.origin == code || $0.destination == code
            }
            if !existing.isEmpty {
                ForEach(existing, id: \.id) { route in
                    NavigationLink(value: route.id) {
                        HStack {
                            Text("\(route.origin.raw) – \(route.destination.raw)")
                                .font(.subheadline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(AETheme.mutedText)
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            if code != player.homeAirport,
               let distance = catalog.distanceKm(player.homeAirport, code) {
                Button {
                    openRoute(FirstRouteSuggestion(
                        origin: player.homeAirport, destination: code,
                        destinationCity: spec.city, distanceKm: distance,
                        expectedDailyPassengers: 0,
                        referenceFare: Money(rounding: DemandSystem.referenceFare(
                            distanceKm: distance, tuning: catalog.tuning.demand))))
                } label: {
                    Label("Open a route from \(player.homeAirport.raw)",
                          systemImage: "plus.circle")
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// A route the player is about to open, identified so it can drive a sheet.
/// `FirstRouteSuggestion` lives in Core and conforming it to `Identifiable`
/// from here would be a retroactive conformance — a warning, and CI builds
/// with warnings as errors.
struct RouteDraft: Identifiable {
    let id = UUID()
    let suggestion: FirstRouteSuggestion
}
