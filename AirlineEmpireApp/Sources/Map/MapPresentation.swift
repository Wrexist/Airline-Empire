import SwiftUI
import AirlineEmpireCore

/// Everything the map decides that is *not* a game rule
/// (docs/MAP_ARCHITECTURE.md §4): where a point lands on screen, what is worth
/// drawing at this zoom, which labels fit, what the finger hit, and where an
/// aircraft is between two simulation ticks.
///
/// It lives outside the view so it can be reasoned about — and, where it is
/// pure geometry, exercised — rather than being buried in a `Canvas` closure.
/// It reads `MapModel` and never `GameState`: the renderer's whole world is
/// the read model Core hands it.

// MARK: - Projection

/// Normalised map space → screen points.
///
/// Equirectangular, aspect 2:1, fitted to width. `zoom` is how many viewport
/// widths the whole world spans; `center` is the normalised point held at the
/// middle of the viewport.
struct MapProjector {
    let zoom: CGFloat
    let center: CGPoint
    let size: CGSize

    var worldWidth: CGFloat { size.width * zoom }
    var worldHeight: CGFloat { worldWidth / 2 }

    func project(_ point: MapPoint) -> CGPoint {
        CGPoint(x: (CGFloat(point.x) - center.x) * worldWidth + size.width / 2,
                y: (CGFloat(point.y) - center.y) * worldHeight + size.height / 2)
    }

    /// Screen point back to normalised map space — needed to zoom about the
    /// pinch anchor rather than about the centre, which is the difference
    /// between a map that follows your fingers and one that fights them.
    func unproject(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - size.width / 2) / worldWidth + center.x,
                y: (point.y - size.height / 2) / worldHeight + center.y)
    }

    /// Whether a projected point is worth drawing, with a margin so a marker
    /// straddling the edge is not clipped mid-symbol.
    func isVisible(_ point: CGPoint, margin: CGFloat = 40) -> Bool {
        point.x > -margin && point.x < size.width + margin
            && point.y > -margin && point.y < size.height + margin
    }
}

// MARK: - Zoom

/// What the map is being used for at this magnification
/// (docs/MAP_ARCHITECTURE.md §7). Information density follows this, not raw
/// scale — zooming in should reveal *different* things, not merely bigger
/// ones.
enum MapZoomLevel: Int, Comparable {
    /// The whole network as a shape. Major airports, player routes, events.
    case world = 0
    /// A continent. Regional airports appear, rival routes gain weight.
    case regional
    /// A market. Every airport, labels, richer aircraft.
    case local

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    init(zoom: CGFloat) {
        switch zoom {
        case ..<2.6: self = .world
        case 2.6..<6.0: self = .regional
        default: self = .local
        }
    }
}

// MARK: - Interpolated flight

/// A flight's position for *this frame*.
///
/// `MapModel` gives a flight's progress at the tick it was built. The pump
/// publishes four snapshots a second, so at 1× that is a new position every
/// game-minute and motion is already smooth — but at 16× a two-hour flight
/// gets about seven updates, and the aircraft stutters across the ocean.
///
/// So the renderer advances a *copy* of the fraction by the real time elapsed
/// since the snapshot, converted to game minutes at the current speed, and
/// re-syncs the moment a new snapshot arrives. Standard client-side
/// prediction: the simulation is never asked, never told, and never affected.
/// Paused means `gameMinutesPerRealSecond` is zero, so nothing moves — which
/// is the behaviour the pause button promises.
struct InterpolatedFlight {
    let flight: MapModel.MapFlight
    let position: MapPoint
    let heading: Double
    let progress: Double

    static func advance(_ flight: MapModel.MapFlight,
                        by realSeconds: Double,
                        speed: SimSpeed,
                        origin: Coordinate,
                        destination: Coordinate) -> InterpolatedFlight {
        guard flight.airborne, flight.flightMinutes > 0, realSeconds > 0,
              speed != .paused else {
            return InterpolatedFlight(flight: flight, position: flight.position,
                                      heading: flight.heading,
                                      progress: flight.progress)
        }
        let gameMinutes = realSeconds * speed.gameMinutesPerRealSecond
        // Never run past arrival: the simulation decides when a flight lands,
        // and a marker that reaches the airport early would be lying.
        let advanced = min(1, flight.progress
                           + gameMinutes / Double(flight.flightMinutes))
        let position = MapMath.greatCirclePoint(from: origin, to: destination,
                                                fraction: advanced)
        let ahead = MapMath.greatCirclePoint(from: origin, to: destination,
                                             fraction: min(1, advanced + 0.02))
        return InterpolatedFlight(
            flight: flight, position: MapPoint(coordinate: position),
            heading: MapMath.heading(from: position, to: ahead),
            progress: advanced)
    }
}

// MARK: - The antimeridian

/// Antimeridian handling lives in `MapMath` (Core), because it is geometry
/// rather than drawing and because Core is where it can be tested. These
/// forward, so the renderer reads in screen-space terms.
enum MapGeodesy {
    /// Stays in `MapPoint` rather than converting to `CGPoint`: an unwrapped
    /// arc is still normalised map space — it just may run past 0…1 — and
    /// moving it into screen-space types early only invites mixing `CGFloat`
    /// with the `Double` offsets it has to be added to.
    static func unwrap(_ points: [MapPoint]) -> [MapPoint] {
        MapMath.unwrap(points)
    }

    static func worldOffsets(for points: [MapPoint]) -> [Double] {
        MapMath.worldOffsets(for: points)
    }
}

// MARK: - Opening a route

/// A route the player is about to open, identified so it can drive a sheet.
///
/// `FirstRouteSuggestion` lives in Core and conforming it to `Identifiable`
/// from the app would be a retroactive conformance — a warning, and CI builds
/// with warnings as errors. Lives here rather than in the map screen because
/// the airport browser presents the same sheet; it moved with the map files
/// once and vanished with them, which is how the whole module failed to
/// compile.
struct RouteDraft: Identifiable {
    let id = UUID()
    let suggestion: FirstRouteSuggestion
}

// MARK: - Level of detail

/// What the map shows at a given zoom, and how strongly.
///
/// One place, so "why did that airport disappear" has an answer, and so the
/// legend and the renderer cannot disagree about what is on screen.
struct MapDetailPolicy {
    let level: MapZoomLevel
    let zoom: CGFloat

    /// Airports below this tier are not drawn unless the player touches them.
    /// The player's own network is never hidden — at any zoom, on any level,
    /// their airline stays visible. That is the promise the map makes.
    var minimumTier: MapModel.AirportTier {
        switch level {
        case .world: MapModel.AirportTier.major
        case .regional: MapModel.AirportTier.regional
        case .local: MapModel.AirportTier.small
        }
    }

    func shows(_ airport: MapModel.MapAirport) -> Bool {
        airport.servedByPlayer || airport.isPlayerHome || airport.closed
            || airport.tier >= minimumTier
    }

    /// Marker radius in points. Tier drives most of it; a hub and the home
    /// base get a little more because they are the map's anchors.
    func radius(_ airport: MapModel.MapAirport) -> CGFloat {
        let base: CGFloat = switch airport.tier {
        case .global: 5.0
        case .major: 4.0
        case .regional: 3.0
        case .small: 2.2
        }
        let presence: CGFloat = airport.isPlayerHome ? 2.4
            : airport.isPlayerHub ? 1.6
            : airport.servedByPlayer ? 0.9 : 0
        // Grow gently with zoom so a local view does not look like a world
        // view with bigger empty space.
        let zoomGain = min(1.6, 1 + (zoom - 1) * 0.06)
        return (base + presence) * zoomGain
    }

    /// Rival routes fade out at world zoom, where they are noise, and gain
    /// presence as the player looks closer at a region.
    var rivalRouteOpacity: Double {
        switch level {
        case .world: 0.16
        case .regional: 0.30
        case .local: 0.42
        }
    }

    /// Aircraft are drawn as directional wedges when a planform would be a
    /// smudge, and as silhouettes once there is room for one.
    var simplifiedAircraft: Bool { level == .world }

    func aircraftSize(isPlayer: Bool) -> CGFloat {
        let base: CGFloat = switch level {
        case .world: 9
        case .regional: 13
        case .local: 18
        }
        return isPlayer ? base : base * 0.78
    }

    /// At 16× the world changes faster than a reader can follow. Rival
    /// aircraft are the first thing to go: they are the least informative
    /// moving objects on screen, and dropping them keeps the player's own
    /// fleet legible.
    func showsRivalAircraft(speed: SimSpeed) -> Bool {
        !(speed == .x16 && level == .world)
    }
}

// MARK: - Labels

/// A label the renderer intends to draw.
struct MapLabel {
    let text: String
    let point: CGPoint
    let priority: Int
    let isPlayer: Bool
    let emphasis: Bool
}

enum MapLabelLayout {
    /// Chooses which airport labels to draw.
    ///
    /// The old rule was `zoom > 2.5 || servedByPlayer`, which is either
    /// nothing or every label in Europe on top of each other. This ranks by
    /// what the player needs to read — the selection, then their own network,
    /// then the biggest airports — and then refuses any label whose box
    /// overlaps one already placed. Greedy by priority, which is the standard
    /// answer and is stable frame to frame because the ranking is.
    static func place(_ airports: [(MapModel.MapAirport, CGPoint)],
                      level: MapZoomLevel,
                      selected: AirportCode?,
                      limit: Int) -> [MapLabel] {
        let ranked = airports
            .map { (airport, point) in
                (airport, point, priority(airport, selected: selected, level: level))
            }
            .filter { $0.2 > 0 }
            .sorted { lhs, rhs in
                lhs.2 != rhs.2 ? lhs.2 > rhs.2 : lhs.0.code.raw < rhs.0.code.raw
            }

        var placed: [CGRect] = []
        var labels: [MapLabel] = []
        for (airport, point, priority) in ranked {
            guard labels.count < limit else { break }
            // Approximate the text box; exact metrics are not worth a layout
            // pass per frame, and the padding absorbs the error.
            let width = CGFloat(airport.code.raw.count) * 7.0 + 10
            let box = CGRect(x: point.x - width / 2, y: point.y - 20,
                             width: width, height: 14)
            guard !placed.contains(where: { $0.intersects(box) }) else { continue }
            placed.append(box)
            labels.append(MapLabel(
                text: airport.code.raw, point: CGPoint(x: point.x, y: point.y - 13),
                priority: priority,
                isPlayer: airport.servedByPlayer || airport.isPlayerHome,
                emphasis: airport.isPlayerHome || airport.code == selected))
        }
        return labels
    }

    /// Zero means "never label this one".
    private static func priority(_ airport: MapModel.MapAirport,
                                 selected: AirportCode?,
                                 level: MapZoomLevel) -> Int {
        if airport.code == selected { return 1000 }
        if airport.isPlayerHome { return 900 }
        if airport.closed { return 850 }
        if airport.isPlayerHub { return 800 }
        if airport.servedByPlayer { return 700 }
        switch level {
        case .world:
            return airport.tier == .global ? 500 : 0
        case .regional:
            return airport.tier >= .major ? 400 + airport.tier.rawValue : 0
        case .local:
            return 300 + airport.tier.rawValue * 10
        }
    }
}

// MARK: - Hit testing

/// What the player just tapped.
/// Hashable, not merely Equatable: `aeAnimation(value:)` takes `some Hashable`
/// (it erases to `AnyHashable`), and the selection panel animates on the
/// selection. Same lesson `Celebration` taught this project earlier today.
enum MapHit: Hashable {
    case airport(AirportCode)
    case route(RouteID)
    case aircraft(FlightID)
}

enum MapHitTester {
    /// Resolves a tap, nearest-first within a tolerance.
    ///
    /// Order matters and is deliberate: **aircraft, then airports, then
    /// routes.** An aircraft is the smallest and most transient thing on the
    /// map, so it must win where it overlaps; a route line passes under
    /// hundreds of pixels and would otherwise swallow every tap near it.
    static func hit(at location: CGPoint,
                    airports: [(MapModel.MapAirport, CGPoint)],
                    flights: [(InterpolatedFlight, CGPoint)],
                    routes: [(MapModel.MapRoute, [CGPoint])],
                    tolerance: CGFloat = 26) -> MapHit? {
        var best: (MapHit, CGFloat)?

        for (flight, point) in flights {
            let distance = hypot(point.x - location.x, point.y - location.y)
            if distance < tolerance, distance < (best?.1 ?? .infinity) {
                best = (.aircraft(flight.flight.id), distance)
            }
        }
        if let best { return best.0 }

        for (airport, point) in airports {
            let distance = hypot(point.x - location.x, point.y - location.y)
            if distance < tolerance, distance < (best?.1 ?? .infinity) {
                best = (.airport(airport.code), distance)
            }
        }
        if let best { return best.0 }

        // Routes last, and on a tighter tolerance: a line is a big target.
        for (route, points) in routes {
            guard points.count >= 2 else { continue }
            for index in 0..<(points.count - 1) {
                let distance = distanceToSegment(location, points[index],
                                                 points[index + 1])
                if distance < tolerance * 0.5, distance < (best?.1 ?? .infinity) {
                    best = (.route(route.id), distance)
                }
            }
        }
        return best?.0
    }

    /// Perpendicular distance from a point to a line segment.
    static func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        // Clamped projection: the nearest point on the segment, not the line.
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

// MARK: - Overlays

/// What the map is being asked to explain (docs/MAP_ARCHITECTURE.md §8).
///
/// One at a time, deliberately. Every overlay answers one strategic question,
/// and stacking them answers none of them.
enum MapOverlay: String, CaseIterable, Identifiable, Hashable {
    case network
    case opportunity
    case profitability
    case competition
    case disruption

    var id: String { rawValue }

    var title: String {
        switch self {
        case .network: "Network"
        case .opportunity: "Demand"
        case .profitability: "Profit"
        case .competition: "Rivals"
        case .disruption: "Risk"
        }
    }

    var icon: String {
        switch self {
        case .network: "point.topleft.down.to.point.bottomright.curvepath"
        case .opportunity: "sparkle.magnifyingglass"
        case .profitability: "chart.line.uptrend.xyaxis"
        case .competition: "person.2.fill"
        case .disruption: "exclamationmark.triangle.fill"
        }
    }

    /// The question it exists to answer. Shown on the layer control, because
    /// an overlay whose purpose has to be guessed will not be used.
    var question: String {
        switch self {
        case .network: "What does my airline look like?"
        case .opportunity: "Where should I fly next?"
        case .profitability: "Which routes are making money?"
        case .competition: "Where am I fighting someone?"
        case .disruption: "Where are operations at risk?"
        }
    }
}
