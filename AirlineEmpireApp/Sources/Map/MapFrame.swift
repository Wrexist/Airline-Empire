import SwiftUI
import AirlineEmpireCore

/// One frame of the map (docs/MAP_ARCHITECTURE.md §5).
///
/// A struct rather than a pile of closures inside `Canvas`, because the draw
/// has ten ordered layers and a hit-test that has to agree with them. It is
/// built, drawn, and thrown away every frame; the only thing that outlives it
/// is `geometry`, which the view keeps so a tap resolves against what was
/// actually on screen.
struct MapFrame {
    let model: MapModel
    let snapshot: GameState
    let projector: MapProjector
    let policy: MapDetailPolicy
    let overlay: MapOverlay
    let selection: MapHit?
    let speed: SimSpeed
    /// Real seconds since the snapshot, for flight interpolation.
    let elapsed: TimeInterval

    /// What the frame drew, in screen space.
    struct Geometry {
        var airports: [(MapModel.MapAirport, CGPoint)] = []
        var flights: [(InterpolatedFlight, CGPoint)] = []
        var routes: [(MapModel.MapRoute, [CGPoint])] = []
    }

    private(set) var geometry = Geometry()

    /// Built once per frame. Interpolating fifty flights was doing a linear
    /// scan of eighty airports twice each, thirty times a second.
    private let airportsByCode: [AirportCode: MapModel.MapAirport]

    init(model: MapModel, snapshot: GameState, projector: MapProjector,
         policy: MapDetailPolicy, overlay: MapOverlay, selection: MapHit?,
         speed: SimSpeed, elapsed: TimeInterval) {
        self.model = model
        self.snapshot = snapshot
        self.projector = projector
        self.policy = policy
        self.overlay = overlay
        self.selection = selection
        self.speed = speed
        self.elapsed = elapsed
        self.airportsByCode = Dictionary(
            model.airports.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var playerLivery: Livery {
        snapshot.playerAirline?.livery ?? .default
    }

    private var playerColor: Color { Vocab.liveryColor(playerLivery) }

    // MARK: - Draw

    mutating func draw(into context: inout GraphicsContext, size: CGSize) {
        drawOcean(&context, size: size)
        drawGraticule(&context)
        drawLand(&context)
        drawEventRegions(&context)
        drawOpportunities(&context)
        drawRoutes(&context)
        drawAirports(&context)
        drawFlights(&context)
        drawLabels(&context)
    }

    // MARK: - Geography

    /// Deep water with a little atmosphere in it. A flat fill is what made the
    /// old map read as a background rather than a place.
    private func drawOcean(_ context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .color(AETheme.mapBackground))
        // A very soft vertical lift, brighter around the equator, so the plane
        // has depth without anything on it being harder to read.
        context.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [AETheme.mapDeep, AETheme.mapBackground,
                              AETheme.mapDeep]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    }

    private func drawGraticule(_ context: inout GraphicsContext) {
        // The grid earns its place by giving the eye something to measure a
        // great circle against; it stays faint enough to never be read as data.
        var grid = Path()
        for offset in projector.visibleWorldOffsets {
            for line in WorldGeometry.graticule {
                appendPolyline(line, offset: offset, to: &grid)
            }
        }
        context.stroke(grid, with: .color(AETheme.mapGraticule), lineWidth: 0.5)

        var equator = Path()
        for offset in projector.visibleWorldOffsets {
            appendPolyline(WorldGeometry.equator, offset: offset, to: &equator)
        }
        context.stroke(equator, with: .color(AETheme.mapGraticule.opacity(1.6)),
                       lineWidth: 0.7)
    }

    private func drawLand(_ context: inout GraphicsContext) {
        for offset in projector.visibleWorldOffsets {
            for landmass in WorldGeometry.landmasses {
                var path = Path()
                appendPolyline(landmass, offset: offset, to: &path)
                path.closeSubpath()
                context.fill(path, with: .color(AETheme.mapLand))
                context.stroke(path, with: .color(AETheme.mapCoast), lineWidth: 0.7)
            }
            // Inland water, over the land it sits in. Drawn in the ocean's
            // own colour rather than a third tone: a lake is the same
            // substance as the sea, and giving it its own value would add a
            // band to a palette deliberately kept narrow
            // (docs/MAP_ARCHITECTURE.md §2).
            for lake in WorldGeometry.lakes {
                var path = Path()
                appendPolyline(lake, offset: offset, to: &path)
                path.closeSubpath()
                context.fill(path, with: .color(AETheme.mapBackground))
                context.stroke(path, with: .color(AETheme.mapCoast.opacity(0.6)),
                               lineWidth: 0.5)
            }
        }
    }

    // MARK: - Events

    /// Events get geography: a soft field over the airports they reach, so
    /// "a storm over Southeast Asia" is a place rather than a sentence.
    private func drawEventRegions(_ context: inout GraphicsContext) {
        guard overlay == .disruption || overlay == .network else { return }
        for event in model.events where !event.isGlobal {
            let points = event.affectedAirports
                .compactMap { airportsByCode[$0]?.position }
                .map(projector.project)
            guard !points.isEmpty else { continue }
            let tint = eventTint(event)
            let radius: CGFloat = event.hasStarted ? 26 : 18
            for point in points where projector.isVisible(point, margin: 60) {
                let rect = CGRect(x: point.x - radius, y: point.y - radius,
                                  width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .radialGradient(
                    Gradient(colors: [tint.opacity(event.hasStarted ? 0.30 : 0.16),
                                      tint.opacity(0)]),
                    center: point, startRadius: 0, endRadius: radius))
            }
        }
    }

    private func eventTint(_ event: MapModel.MapEvent) -> Color {
        switch event.kind {
        case .storm: AETheme.negative
        case .airportClosure: AETheme.negative
        case .strike: AETheme.caution
        case .tourismBoom: AETheme.positive
        case .fuelShock: AETheme.caution
        }
    }

    // MARK: - Opportunities

    /// Where the player could go. This is what fills an early-game map, and
    /// it is also the demand overlay — the same ranking, drawn.
    private func drawOpportunities(_ context: inout GraphicsContext) {
        guard overlay == .opportunity || model.routes.filter(\.isPlayer).isEmpty
        else { return }
        for opportunity in model.opportunities {
            let unwrapped = MapGeodesy.unwrap([opportunity.from, opportunity.to])
            guard let a = unwrapped.first, let b = unwrapped.last else { continue }
            let from = projector.project(a)
            let to = projector.project(b)
            guard projector.isVisible(from, margin: 120)
                    || projector.isVisible(to, margin: 120) else { continue }
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            // Dashed and dim: a proposal, never mistaken for a route that
            // exists.
            context.stroke(path,
                           with: .color(AETheme.positive.opacity(
                            opportunity.servableNow ? 0.42 : 0.18)),
                           style: StrokeStyle(lineWidth: 1.1, dash: [4, 5]))
            let radius: CGFloat = 5
            context.stroke(
                Path(ellipseIn: CGRect(x: to.x - radius, y: to.y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .color(AETheme.positive.opacity(0.55)), lineWidth: 1)
        }
    }

    // MARK: - Routes

    private mutating func drawRoutes(_ context: inout GraphicsContext) {
        // Rivals first so the player's network always draws on top of theirs.
        for route in model.routes where !route.isPlayer {
            drawRoute(route, into: &context, isPlayer: false)
        }
        for route in model.routes where route.isPlayer {
            drawRoute(route, into: &context, isPlayer: true)
        }
    }

    private mutating func drawRoute(_ route: MapModel.MapRoute,
                                    into context: inout GraphicsContext,
                                    isPlayer: Bool) {
        guard showsRoute(route) else { return }
        // Unwrapped so a Pacific crossing does not draw a line back across the
        // whole map (BUG-012), and drawn in each world copy it reaches into.
        let unwrapped = MapGeodesy.unwrap(route.arc)
        guard !unwrapped.isEmpty else { return }

        let isSelected = selection == .route(route.id)
        let style = routeStyle(route, isPlayer: isPlayer, isSelected: isSelected)
        var drawnForHitTest: [CGPoint]?

        for offset in MapGeodesy.worldOffsets(for: unwrapped) {
            let points = unwrapped.map {
                projector.project(MapPoint(x: $0.x + offset, y: $0.y))
            }
            guard points.contains(where: { projector.isVisible($0, margin: 120) })
            else { continue }

            var path = Path()
            for (index, point) in points.enumerated() {
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            // A selected route gets a halo underneath rather than a colour
            // change, so it reads as *chosen* without losing what its colour
            // was saying.
            if isSelected {
                context.stroke(path, with: .color(.white.opacity(0.55)),
                               style: StrokeStyle(lineWidth: style.width + 4,
                                                  lineCap: .round, lineJoin: .round))
            }
            context.stroke(path, with: .color(style.color.opacity(style.opacity)),
                           style: StrokeStyle(lineWidth: style.width, lineCap: .round,
                                              lineJoin: .round, dash: style.dash))
            if drawnForHitTest == nil { drawnForHitTest = points }
        }

        // Every drawn route is selectable, rivals included — the competition
        // overlay is not much use if you cannot tap what it shows you.
        if let drawnForHitTest { geometry.routes.append((route, drawnForHitTest)) }
    }

    private func showsRoute(_ route: MapModel.MapRoute) -> Bool {
        if route.isPlayer { return true }
        switch overlay {
        case .competition: return true
        case .network, .disruption: return policy.level >= .regional
        case .opportunity, .profitability: return false
        }
    }

    private struct RouteStyle {
        let color: Color
        let width: CGFloat
        let opacity: Double
        let dash: [CGFloat]
    }

    /// Health drives weight, opacity and dash as well as colour, so the map
    /// is readable without relying on hue — and so a grounded route looks
    /// *stopped* rather than merely differently coloured.
    private func routeStyle(_ route: MapModel.MapRoute, isPlayer: Bool,
                            isSelected: Bool) -> RouteStyle {
        guard isPlayer else {
            return RouteStyle(color: Vocab.liveryColor(route.livery),
                              width: policy.level >= .regional ? 1.0 : 0.7,
                              opacity: policy.rivalRouteOpacity, dash: [])
        }
        // Frequency reads as weight: a trunk route should look like one.
        let weight = min(3.4, 1.3 + CGFloat(route.dailyRoundTrips) * 0.24)
        switch overlay {
        case .profitability:
            return RouteStyle(color: profitColor(route.health),
                              width: weight, opacity: 0.95, dash: [])
        default:
            break
        }
        switch route.health {
        case .grounded:
            return RouteStyle(color: AETheme.mutedText, width: 1.4,
                              opacity: 0.7, dash: [3, 4])
        case .disrupted:
            return RouteStyle(color: AETheme.negative, width: weight,
                              opacity: 0.9, dash: [7, 3])
        case .weak:
            return RouteStyle(color: AETheme.caution, width: weight,
                              opacity: 0.85, dash: [])
        case .healthy:
            return RouteStyle(color: playerColor, width: weight,
                              opacity: 0.9, dash: [])
        case .strong:
            return RouteStyle(color: playerColor, width: weight + 0.8,
                              opacity: 1.0, dash: [])
        }
    }

    private func profitColor(_ health: MapModel.RouteHealth) -> Color {
        switch health {
        case .strong: AETheme.positive
        case .healthy: AETheme.positive.opacity(0.7)
        case .weak: AETheme.caution
        case .disrupted, .grounded: AETheme.negative
        }
    }

    // MARK: - Airports

    private mutating func drawAirports(_ context: inout GraphicsContext) {
        for airport in model.airports {
            guard policy.shows(airport) else { continue }
            let point = projector.project(airport.position)
            guard projector.isVisible(point) else { continue }
            geometry.airports.append((airport, point))

            let radius = policy.radius(airport)
            let isSelected = selection == .airport(airport.code)

            // Overlay-specific field behind the marker, so a heat reading and
            // the airport itself never fight for the same pixels.
            if let field = overlayField(airport) {
                let r = radius * 5
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r,
                                           width: r * 2, height: r * 2)),
                    with: .radialGradient(
                        Gradient(colors: [field.opacity(0.36), field.opacity(0)]),
                        center: point, startRadius: 0, endRadius: r))
            }

            // Home carries a ring; a hub a softer one. "Where am I" should
            // never be a question on this screen.
            if airport.isPlayerHome {
                strokeCircle(&context, at: point, radius: radius + 5,
                             color: AETheme.ember.opacity(0.85), width: 1.6)
                strokeCircle(&context, at: point, radius: radius + 9,
                             color: AETheme.ember.opacity(0.28), width: 1)
            } else if airport.isPlayerHub {
                strokeCircle(&context, at: point, radius: radius + 4,
                             color: playerColor.opacity(0.55), width: 1.2)
            }
            if isSelected {
                strokeCircle(&context, at: point, radius: radius + 7,
                             color: .white, width: 1.6)
            }

            let fill: Color = airport.closed ? AETheme.negative
                : airport.isPlayerHome ? AETheme.ember
                : airport.servedByPlayer ? playerColor
                : airport.competitorHubCount > 0 ? AETheme.rivalRoute.opacity(0.9)
                : .white.opacity(0.62)
            fillCircle(&context, at: point, radius: radius, color: fill)

            // A closed airport gets a cross, because a red dot among coloured
            // dots is not a signal anybody can rely on.
            if airport.closed {
                var cross = Path()
                let arm = radius + 3
                cross.move(to: CGPoint(x: point.x - arm, y: point.y - arm))
                cross.addLine(to: CGPoint(x: point.x + arm, y: point.y + arm))
                cross.move(to: CGPoint(x: point.x + arm, y: point.y - arm))
                cross.addLine(to: CGPoint(x: point.x - arm, y: point.y + arm))
                context.stroke(cross, with: .color(AETheme.negative), lineWidth: 1.4)
            }
        }
    }

    /// The heat behind an airport for the current overlay, or nil when this
    /// overlay has nothing to say about airports.
    private func overlayField(_ airport: MapModel.MapAirport) -> Color? {
        switch overlay {
        case .network:
            return nil
        case .opportunity:
            // Only markets the player could actually open glow.
            let relevant = model.opportunities.contains {
                $0.destination == airport.code || $0.origin == airport.code
            }
            return relevant ? AETheme.positive : nil
        case .profitability:
            guard airport.servedByPlayer else { return nil }
            let routes = model.routes.filter {
                $0.isPlayer && ($0.origin == airport.code || $0.destination == airport.code)
            }
            guard !routes.isEmpty else { return nil }
            let weak = routes.filter { $0.health <= .weak }.count
            return weak > routes.count / 2 ? AETheme.caution : AETheme.positive
        case .competition:
            guard airport.competitorCount > 0 else { return nil }
            return airport.competitorHubCount > 0
                ? AETheme.negative : AETheme.rivalRoute
        case .disruption:
            if airport.closed { return AETheme.negative }
            if airport.slotPressure > 0.85 { return AETheme.caution }
            return airport.weatherRisk == .severe || airport.weatherRisk == .high
                ? AETheme.caution.opacity(0.6) : nil
        }
    }

    // MARK: - Flights

    private mutating func drawFlights(_ context: inout GraphicsContext) {
        for flight in model.flights {
            guard flight.isPlayer || policy.showsRivalAircraft(speed: speed) else {
                continue
            }
            guard overlay != .opportunity || flight.isPlayer else { continue }

            let interpolated = interpolate(flight)
            let point = projector.project(interpolated.position)
            guard projector.isVisible(point) else { continue }
            // Airborne only. A parked aircraft draws a 2pt dot *at its
            // airport's own position*, and the hit tester gives every flight a
            // 26pt target and tests flights first — so a parked aircraft made
            // its airport permanently untappable, starting with the home base,
            // which almost always has one (tasks/BUGS.md BUG-020).
            //
            // The ordering rationale in `MapHitTester` — that an aircraft is
            // the smallest and most transient thing on the map, so it must win
            // where it overlaps — is about an aircraft *in flight*. It was
            // never an argument for a stationary dot outranking the airport
            // underneath it. Parked aircraft are reachable through the airport
            // card, which is the better route to them anyway.
            if flight.airborne { geometry.flights.append((interpolated, point)) }

            let size = policy.aircraftSize(isPlayer: flight.isPlayer)
            let color = flight.isPlayer
                ? Vocab.liveryColor(flight.livery)
                : Vocab.liveryColor(flight.livery).opacity(0.5)

            if selection == .aircraft(flight.id) {
                strokeCircle(&context, at: point, radius: size * 0.9,
                             color: .white, width: 1.4)
            }

            // Parked aircraft sit as a small dot at their stand rather than a
            // silhouette on the ground, which reads as flying.
            guard flight.airborne else {
                fillCircle(&context, at: point, radius: 2, color: color.opacity(0.8))
                continue
            }

            let path = AircraftSilhouette.placed(
                flight.category, at: point, heading: interpolated.heading,
                size: size, simplified: policy.simplifiedAircraft)
            // A dark outline keeps a light livery readable over land.
            context.stroke(path, with: .color(AETheme.mapBackground.opacity(0.85)),
                           lineWidth: 1.6)
            context.fill(path, with: .color(color))

            // A late flight carries a warning dot; the map should show trouble
            // where trouble is, not only in the feed.
            if flight.isPlayer, flight.delayMinutes > 20 {
                fillCircle(&context, at: CGPoint(x: point.x + size * 0.5,
                                                 y: point.y - size * 0.5),
                           radius: 2.2, color: AETheme.caution)
            }
        }
    }

    private func interpolate(_ flight: MapModel.MapFlight) -> InterpolatedFlight {
        guard let catalog = catalogAirports(flight) else {
            return InterpolatedFlight(flight: flight, position: flight.position,
                                      heading: flight.heading,
                                      progress: flight.progress)
        }
        return InterpolatedFlight.advance(flight, by: elapsed, speed: speed,
                                          origin: catalog.0, destination: catalog.1)
    }

    /// Endpoint coordinates for interpolation, from the model's own airports
    /// so the renderer never reaches into the content catalog.
    private func catalogAirports(_ flight: MapModel.MapFlight)
        -> (Coordinate, Coordinate)? {
        guard let from = airportsByCode[flight.origin],
              let to = airportsByCode[flight.destination] else { return nil }
        return (from.position.coordinate, to.position.coordinate)
    }

    // MARK: - Labels

    private func drawLabels(_ context: inout GraphicsContext) {
        // A statement rather than an `if case` expression: pattern-matching
        // conditions in expression position are the kind of thing that either
        // compiles or teaches you something, and this file has no business
        // finding out.
        var selectedCode: AirportCode?
        if case .airport(let code) = selection { selectedCode = code }
        let labels = MapLabelLayout.place(
            geometry.airports, level: policy.level, selected: selectedCode,
            limit: policy.level == .world ? 14 : 28)
        for label in labels {
            let color: Color = label.emphasis ? AETheme.ember
                : label.isPlayer ? playerColor.opacity(0.95)
                : .white.opacity(0.72)
            context.draw(
                Text(label.text)
                    .font(.system(size: label.emphasis ? 11 : 10,
                                  weight: label.isPlayer ? .semibold : .medium))
                    .foregroundStyle(color),
                at: label.point)
        }
    }

    // MARK: - Primitives

    private func appendPolyline(_ points: [MapPoint], offset: Double = 0,
                                to path: inout Path) {
        var started = false
        for point in points {
            let projected = projector.project(MapPoint(x: point.x + offset,
                                                       y: point.y))
            if !started {
                path.move(to: projected)
                started = true
            } else {
                path.addLine(to: projected)
            }
        }
    }

    private func fillCircle(_ context: inout GraphicsContext, at point: CGPoint,
                            radius: CGFloat, color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                            width: radius * 2, height: radius * 2)),
                     with: .color(color))
    }

    private func strokeCircle(_ context: inout GraphicsContext, at point: CGPoint,
                              radius: CGFloat, color: Color, width: CGFloat) {
        context.stroke(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                              width: radius * 2, height: radius * 2)),
                       with: .color(color), lineWidth: width)
    }
}

extension MapPoint {
    /// Back to latitude/longitude, for the interpolator.
    var coordinate: Coordinate {
        Coordinate(latitude: 90 - y * 180, longitude: x * 360 - 180)
    }
}
