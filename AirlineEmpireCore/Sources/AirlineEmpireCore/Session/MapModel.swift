import Foundation

/// Map read model (docs/MAP_ARCHITECTURE.md, docs/UI_ARCHITECTURE.md §3):
/// everything the map renderer draws, computed in Core so positions, arcs,
/// classifications and live-flight interpolation are tested headlessly. The
/// renderer projects and draws; it never computes gameplay-adjacent values.
///
/// The model answers the strategic questions the map screen exists to answer —
/// where am I, where is my aircraft, what is working, who am I fighting, what
/// is at risk, where should I go next — so a renderer never has to reach past
/// it into `GameState` and re-derive an answer of its own.
public struct MapModel: Equatable, Sendable {
    public let airports: [MapAirport]
    public let routes: [MapRoute]
    public let flights: [MapFlight]
    public let events: [MapEvent]
    /// Best unopened markets, so an early-game map has something to say and
    /// the demand overlay has something to draw.
    public let opportunities: [MapOpportunity]
    public let playerHome: AirportCode?
    /// The simulation minute the model was built at; the renderer measures its
    /// own interpolation from here.
    public let builtAt: SimTime

    /// How much an airport matters, which is what decides its size, its label
    /// priority, and whether it is drawn at all when zoomed out.
    ///
    /// Derived from what the content pack already says — catchment, slot
    /// capacity and runway class — rather than a hand-kept list, so adding an
    /// airport to `airports.json` classifies it automatically.
    public enum AirportTier: Int, Equatable, Sendable, Comparable, CaseIterable {
        case small = 0
        case regional
        case major
        case global

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// What a route looks like it is doing. Never colour alone in the
    /// renderer — this drives weight and pattern too.
    public enum RouteHealth: Int, Equatable, Sendable, Comparable, CaseIterable {
        /// No aircraft assigned: paying fees, flying nothing.
        case grounded = 0
        /// An airport on it is shut, or its completion rate has collapsed.
        case disrupted
        /// Losing money, or flying half-empty.
        case weak
        case healthy
        /// Full and profitable.
        case strong

        /// The ladder is ordered on purpose — worst first — so "at least this
        /// bad" is expressible. Callers ask `health <= .weak` for "needs
        /// attention"; without the ordering each of them would spell out the
        /// same set of cases and one of them would eventually forget one.
        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public struct MapAirport: Equatable, Sendable {
        public let code: AirportCode
        public let name: String
        public let city: String
        public let country: String
        public let region: WorldRegion
        public let position: MapPoint
        /// 0…1 catchment size, for level-of-detail and marker scale.
        public let prominence: Double
        public let tier: AirportTier
        public let servedByPlayer: Bool
        /// The player's own base.
        public let isPlayerHome: Bool
        /// Somewhere the player has built real presence (three or more
        /// routes) — a hub in behaviour rather than by declaration, since
        /// the game has no hub mechanic yet (D-010).
        public let isPlayerHub: Bool
        public let playerRouteCount: Int
        /// Rivals with at least one route touching here.
        public let competitorCount: Int
        /// Rivals *based* here — this is somebody's fortress.
        public let competitorHubCount: Int
        /// 0…1 of the airport's daily movements already claimed.
        public let slotPressure: Double
        public let weatherRisk: WeatherRisk
        public let closed: Bool
    }

    public struct MapRoute: Equatable, Sendable {
        public let id: RouteID
        public let airline: AirlineID
        public let isPlayer: Bool
        public let origin: AirportCode
        public let destination: AirportCode
        public let from: MapPoint
        public let to: MapPoint
        /// Great-circle waypoints from `from` to `to` (inclusive), ready to
        /// draw as a polyline — correct curvature and date-line handling.
        public let arc: [MapPoint]
        public let dailyRoundTrips: Int
        public let loadFactor: Double
        public let health: RouteHealth
        /// The operator's colours, so the map can tell four carriers apart
        /// instead of drawing every rival in the same grey.
        public let livery: Livery
    }

    public struct MapFlight: Equatable, Sendable {
        public let id: FlightID
        public let route: RouteID
        public let aircraft: AircraftID
        public let airline: AirlineID
        public let isPlayer: Bool
        public let origin: AirportCode
        public let destination: AirportCode
        public let position: MapPoint
        /// Course in degrees clockwise from north (icon rotation).
        public let heading: Double
        public let airborne: Bool
        /// 0…1 along the great circle at `builtAt`. The renderer advances a
        /// *copy* of this between snapshots for smooth motion; the simulation
        /// never reads it back.
        public let progress: Double
        /// Total scheduled flying time, which is what lets the renderer know
        /// how fast the fraction should advance per game minute.
        public let flightMinutes: Int64
        public let category: AircraftCategory
        public let delayMinutes: Int64
        public let isFerry: Bool
        public let livery: Livery
    }

    /// A world event, placed. Events had no geography on screen at all, which
    /// made "a storm over Southeast Asia" a line of text rather than a thing
    /// happening somewhere.
    public struct MapEvent: Equatable, Sendable {
        public let id: Int64
        public let kind: WorldEventKind
        public let hasStarted: Bool
        public let severity: Double
        public let beginsAt: SimTime
        public let endsAt: SimTime
        /// Airports inside the event's reach. Empty for a global event such
        /// as a fuel shock, which the renderer shows as a banner rather than
        /// as a place.
        public let affectedAirports: [AirportCode]
        /// True when the event has no location — global, not regional.
        public let isGlobal: Bool
        /// Player routes it touches; the number that makes an event a
        /// decision rather than a headline.
        public let affectedPlayerRoutes: [RouteID]
    }

    /// A market the player could open, positioned for drawing.
    public struct MapOpportunity: Equatable, Sendable {
        public let origin: AirportCode
        public let destination: AirportCode
        public let from: MapPoint
        public let to: MapPoint
        public let expectedDailyPassengers: Int
        public let distanceKm: Int
        /// The market fare at this distance, so a "open a route here" tap can
        /// pre-fill the sheet with a sane number rather than zero.
        public let referenceFare: Money
        public let incumbents: Int
        public let servableNow: Bool
    }
}

extension MapModel {
    /// Positions a ranked market for drawing.
    public static func opportunity(_ market: MarketOpportunity,
                                   catalog: ContentCatalog) -> MapOpportunity? {
        guard let a = catalog.airport(market.origin),
              let b = catalog.airport(market.destination) else { return nil }
        return MapOpportunity(
            origin: market.origin, destination: market.destination,
            from: MapPoint(coordinate: a.coordinate),
            to: MapPoint(coordinate: b.coordinate),
            expectedDailyPassengers: market.expectedDailyPassengers,
            distanceKm: market.distanceKm, referenceFare: market.referenceFare,
            incumbents: market.incumbents, servableNow: market.servableNow)
    }
}

/// Equirectangular map space: x 0…1 (west→east from -180°), y 0…1
/// (north→south from +90°). Renderers scale to their viewport.
public struct MapPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(coordinate: Coordinate) {
        self.x = (coordinate.longitude + 180) / 360
        self.y = (90 - coordinate.latitude) / 180
    }
}

public enum MapMath {
    /// Great-circle intermediate point (slerp on the unit sphere).
    public static func greatCirclePoint(from a: Coordinate, to b: Coordinate,
                                        fraction: Double) -> Coordinate {
        let lat1 = a.latitude * .pi / 180, lon1 = a.longitude * .pi / 180
        let lat2 = b.latitude * .pi / 180, lon2 = b.longitude * .pi / 180
        let d = centralAngle(a, b)
        guard d > 1e-9 else { return a }
        let sinD = sin(d)
        let f1 = sin((1 - fraction) * d) / sinD
        let f2 = sin(fraction * d) / sinD
        let x = f1 * cos(lat1) * cos(lon1) + f2 * cos(lat2) * cos(lon2)
        let y = f1 * cos(lat1) * sin(lon1) + f2 * cos(lat2) * sin(lon2)
        let z = f1 * sin(lat1) + f2 * sin(lat2)
        return Coordinate(latitude: atan2(z, (x * x + y * y).squareRoot()) * 180 / .pi,
                          longitude: atan2(y, x) * 180 / .pi)
    }

    /// Initial course at `from` toward `to`, degrees clockwise from north.
    public static func heading(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Course of a great-circle route at `fraction` along it, degrees
    /// clockwise from north.
    ///
    /// Sampling a point slightly ahead is the obvious way to do this and is
    /// wrong at exactly one place: the end. `fraction` is clamped to 1 while a
    /// flight waits for the next snapshot, so `fraction + 0.02` is also 1, and
    /// `heading(from:to:)` given two identical coordinates has no direction to
    /// report — it returns 0, and the aircraft snaps to due north on arrival.
    /// At the end of the route, measure the leg just travelled instead.
    public static func heading(alongRouteFrom origin: Coordinate,
                               to destination: Coordinate,
                               at fraction: Double) -> Double {
        let here = greatCirclePoint(from: origin, to: destination, fraction: fraction)
        if fraction >= 1 {
            let behind = greatCirclePoint(from: origin, to: destination,
                                          fraction: max(0, fraction - 0.02))
            return heading(from: behind, to: here)
        }
        let ahead = greatCirclePoint(from: origin, to: destination,
                                     fraction: min(1, fraction + 0.02))
        return heading(from: here, to: ahead)
    }

    static func centralAngle(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * atan2(h.squareRoot(), (1 - h).squareRoot())
    }

    /// Great circles cross the 180th meridian; equirectangular map space does
    /// not. A Tokyo–Los Angeles arc runs off the right edge of the world and
    /// back on at the left, so its x values jump from ~0.99 to ~0.01 between
    /// two consecutive waypoints — and a renderer that draws the raw polyline
    /// puts a straight line back across the entire map (BUG-012).
    ///
    /// `unwrap` walks the arc accumulating whole-world offsets so x stays
    /// continuous even when it leaves 0…1. The renderer then draws the
    /// unwrapped line once per world copy it reaches into.
    ///
    /// This lives in Core rather than in the renderer because it is geometry,
    /// not drawing — and because Core's own comment has always claimed correct
    /// date-line handling, which was true of the points and not of the line
    /// through them.
    public static func unwrap(_ points: [MapPoint]) -> [MapPoint] {
        guard var previous = points.first else { return [] }
        var offset: Double = 0
        var out: [MapPoint] = [previous]
        for point in points.dropFirst() {
            let delta = point.x - previous.x
            // Half a world between adjacent waypoints means the arc wrapped,
            // not that it crossed the planet in one step.
            if delta > 0.5 { offset -= 1 } else if delta < -0.5 { offset += 1 }
            out.append(MapPoint(x: point.x + offset, y: point.y))
            previous = point
        }
        return out
    }

    /// The world copies worth drawing for an unwrapped polyline: always the
    /// original, plus a shifted copy when the line runs off an edge.
    public static func worldOffsets(for points: [MapPoint]) -> [Double] {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max()
        else { return [0] }
        var offsets: [Double] = [0]
        if minX < 0 { offsets.append(1) }
        if maxX > 1 { offsets.append(-1) }
        return offsets
    }

    /// Arc polyline with enough segments to look smooth at any zoom.
    public static func arc(from a: Coordinate, to b: Coordinate,
                           segments: Int = 24) -> [MapPoint] {
        precondition(segments >= 1)
        return (0...segments).map { step in
            MapPoint(coordinate: greatCirclePoint(
                from: a, to: b, fraction: Double(step) / Double(segments)))
        }
    }
}

extension GameState {
    /// Builds the full map model for the current snapshot.
    ///
    /// Presentation-only interpolation: airborne flights place along the great
    /// circle by elapsed flight-time fraction — never fed back into the
    /// simulation (docs/UI_ARCHITECTURE.md §3).
    ///
    /// One pass over routes builds every per-airport tally, so the whole model
    /// is O(airports + routes + flights) rather than O(airports × routes).
    public func mapModel(catalog: ContentCatalog,
                         opportunityLimit: Int = 6) -> MapModel {
        let player = playerAirline?.id
        let home = playerAirline?.homeAirport

        // --- One pass over routes: everything per-airport comes from here.
        var playerAirports: Set<AirportCode> = []
        var playerRouteCounts: [AirportCode: Int] = [:]
        var competitorsAt: [AirportCode: Set<AirlineID>] = [:]
        for id in orderedRouteIDs {
            guard let route = routes[id] else { continue }
            for code in [route.origin, route.destination] {
                if route.airline == player {
                    playerAirports.insert(code)
                    playerRouteCounts[code, default: 0] += 1
                } else {
                    competitorsAt[code, default: []].insert(route.airline)
                }
            }
        }
        // A rival "based" somewhere is one whose home airport it is.
        var competitorHomes: [AirportCode: Int] = [:]
        for id in orderedAirlineIDs {
            guard let airline = airlines[id], airline.kind == .ai,
                  airline.status == .active else { continue }
            competitorHomes[airline.homeAirport, default: 0] += 1
        }

        let populations = catalog.orderedAirportCodes
            .compactMap { catalog.airports[$0]?.demographics.populationThousands }
        let maxPopulation = Double(populations.max() ?? 1)
        let maxSlots = Double(catalog.orderedAirportCodes
            .compactMap { catalog.airports[$0]?.slotCapacityPerDay }.max() ?? 1)

        let airports = catalog.orderedAirportCodes.compactMap { code -> MapModel.MapAirport? in
            guard let spec = catalog.airports[code] else { return nil }
            let prominence = maxPopulation > 0
                ? Double(spec.demographics.populationThousands) / maxPopulation : 0
            let playerRoutes = playerRouteCounts[code] ?? 0
            let capacity = max(1, spec.slotCapacityPerDay)
            return MapModel.MapAirport(
                code: code, name: spec.name, city: spec.city, country: spec.country,
                region: spec.region,
                position: MapPoint(coordinate: spec.coordinate),
                prominence: prominence,
                tier: MapModel.tier(for: spec, prominence: prominence,
                                    maxSlots: maxSlots),
                servedByPlayer: playerAirports.contains(code),
                isPlayerHome: code == home,
                // Three routes is the point at which a station stops being a
                // destination and starts being a base you plan around.
                isPlayerHub: playerRoutes >= 3,
                playerRouteCount: playerRoutes,
                competitorCount: competitorsAt[code]?.count ?? 0,
                competitorHubCount: competitorHomes[code] ?? 0,
                slotPressure: min(1, Double(world.slotsUsed(at: code)) / Double(capacity)),
                weatherRisk: spec.weatherRisk,
                closed: world.isAirportClosed(code, at: clock.now))
        }

        let closedAirports = Set(airports.filter(\.closed).map(\.code))

        let mapRoutes = orderedRouteIDs.compactMap { routeID -> MapModel.MapRoute? in
            guard let route = routes[routeID],
                  let origin = catalog.airport(route.origin),
                  let destination = catalog.airport(route.destination) else { return nil }
            let disrupted = closedAirports.contains(route.origin)
                || closedAirports.contains(route.destination)
            return MapModel.MapRoute(
                id: routeID, airline: route.airline,
                isPlayer: route.airline == player,
                origin: route.origin, destination: route.destination,
                from: MapPoint(coordinate: origin.coordinate),
                to: MapPoint(coordinate: destination.coordinate),
                arc: MapMath.arc(from: origin.coordinate, to: destination.coordinate),
                dailyRoundTrips: route.dailyRoundTrips,
                loadFactor: route.stats.loadFactor,
                health: MapModel.health(of: route, disrupted: disrupted),
                livery: airlines[route.airline]?.livery ?? .default)
        }

        let mapFlights = orderedFlightIDs.compactMap { flightID -> MapModel.MapFlight? in
            guard let flight = flights[flightID],
                  let from = catalog.airport(flight.from),
                  let to = catalog.airport(flight.to),
                  let aircraft = aircraft[flight.aircraft],
                  let spec = catalog.aircraftType(aircraft.typeCode) else { return nil }
            let owner = aircraft.owner
            let livery = airlines[owner]?.livery ?? .default

            func build(position: Coordinate, heading: Double,
                       airborne: Bool, progress: Double) -> MapModel.MapFlight {
                MapModel.MapFlight(
                    id: flightID, route: flight.route, aircraft: flight.aircraft,
                    airline: owner, isPlayer: owner == player,
                    origin: flight.from, destination: flight.to,
                    position: MapPoint(coordinate: position), heading: heading,
                    airborne: airborne, progress: progress,
                    flightMinutes: flight.flightMinutes, category: spec.category,
                    delayMinutes: flight.delayMinutes,
                    isFerry: flight.kind == .ferry, livery: livery)
            }

            switch flight.phase {
            case .enRoute(let actualDeparture):
                let elapsed = Double(clock.now.rawMinutes - actualDeparture.rawMinutes)
                let fraction = min(1, max(0, elapsed / Double(max(1, flight.flightMinutes))))
                let position = MapMath.greatCirclePoint(
                    from: from.coordinate, to: to.coordinate, fraction: fraction)
                return build(position: position,
                             heading: MapMath.heading(alongRouteFrom: from.coordinate,
                                                      to: to.coordinate,
                                                      at: fraction),
                             airborne: true, progress: fraction)
            case .boarding, .turnaround:
                return build(position: from.coordinate,
                             heading: MapMath.heading(from: from.coordinate,
                                                      to: to.coordinate),
                             airborne: false, progress: 0)
            case .scheduled:
                return nil
            }
        }

        // --- Events, placed.
        let playerRoutesByID = orderedRouteIDs.compactMap { routes[$0] }
            .filter { $0.airline == player }
        let mapEvents = world.activeEvents.map { event -> MapModel.MapEvent in
            let affected: [AirportCode]
            var isGlobal = false
            switch event.kind {
            case .fuelShock:
                affected = []
                isGlobal = true
            case .storm(let region), .tourismBoom(let region):
                affected = catalog.orderedAirportCodes.filter {
                    catalog.airports[$0]?.region == region
                }
            case .airportClosure(let code):
                affected = [code]
            case .strike(let airline):
                affected = orderedRouteIDs.compactMap { routes[$0] }
                    .filter { $0.airline == airline }
                    .flatMap { [$0.origin, $0.destination] }
                    .reduce(into: [AirportCode]()) { list, code in
                        if !list.contains(code) { list.append(code) }
                    }
            }
            let affectedSet = Set(affected)
            // A strike grounds the airline that is striking, not everyone who
            // happens to fly out of the same airports. Sharing a hub with a
            // struck rival is normal at any large airport, and reporting it as
            // a disruption of the player's routes made the overlay claim a
            // problem that does not exist (Vocab.worldEventEffect says as much:
            // a strike affects that airline's flights).
            let strikesAnotherAirline: Bool
            if case .strike(let striking) = event.kind {
                strikesAnotherAirline = striking != player
            } else {
                strikesAnotherAirline = false
            }
            let touched: [RouteID]
            if isGlobal {
                touched = playerRoutesByID.map(\.id)
            } else if strikesAnotherAirline {
                touched = []
            } else {
                touched = playerRoutesByID.filter {
                    affectedSet.contains($0.origin) || affectedSet.contains($0.destination)
                }.map(\.id)
            }
            return MapModel.MapEvent(
                id: event.id, kind: event.kind, hasStarted: event.hasStarted,
                severity: event.severity, beginsAt: event.beginsAt,
                endsAt: event.endsAt, affectedAirports: affected,
                isGlobal: isGlobal, affectedPlayerRoutes: touched)
        }

        let mapOpportunities = opportunityLimit == 0 ? []
            : marketOpportunities(catalog: catalog, limit: opportunityLimit)
                .compactMap { MapModel.opportunity($0, catalog: catalog) }

        return MapModel(airports: airports, routes: mapRoutes, flights: mapFlights,
                        events: mapEvents, opportunities: mapOpportunities,
                        playerHome: home, builtAt: clock.now)
    }
}

extension MapModel {
    /// Classification from what the content pack already knows: how big the
    /// airport is, how big its city is, and whether the runway can take the
    /// aeroplanes.
    ///
    /// **The city alone is not the airport.** This used to rank on
    /// `prominence` — metro population over the largest metro — and nothing
    /// else, which put Frankfurt, Amsterdam, Dubai and Copenhagen in the same
    /// tier as Gothenburg: "small field", on 1,100–1,500 slots a day against
    /// Gothenburg's 150. Tokyo's catchment is genuinely fifteen times
    /// Frankfurt's, so on population Frankfurt *is* small; as an airport it is
    /// one of the busiest on earth. The map's whole label ladder hangs off
    /// this, so the effect was not cosmetic: the tier sets the zoom at which
    /// an airport's name appears, and three of Europe's biggest hubs stayed
    /// hidden until the deepest zoom while smaller cities showed at a glance.
    /// It surfaced only when the first automated frame ever to open an
    /// airport panel photographed Arlanda captioned "small field"
    /// (AE-033 audit §6.11).
    ///
    /// So the score is the larger of the two claims to importance — the city's
    /// catchment, or the airport's own capacity — rather than the city's
    /// alone. Capacity is discounted slightly so that a city of real size
    /// still outranks a big-but-empty field on equal slots. The runway gates
    /// stay exactly as they were: a huge catchment with a short runway is not
    /// a global hub, it is a market nobody can serve properly.
    static func tier(for spec: AirportSpec, prominence: Double,
                     maxSlots: Double) -> AirportTier {
        let capacityShare = maxSlots > 0
            ? Double(spec.slotCapacityPerDay) / maxSlots : 0
        let score = max(prominence, capacityShare * 0.95)
        if score >= 0.70, spec.runwayClass >= .veryLarge {
            return .global
        }
        if score >= 0.45 {
            return spec.runwayClass >= .large ? .major : .regional
        }
        return score >= 0.18 ? .regional : .small
    }

    /// What a route looks like it is doing, from the figures the simulation
    /// already keeps. Grounded outranks everything: a route with no aircraft
    /// is not "unprofitable", it is not operating.
    static func health(of route: Route, disrupted: Bool) -> RouteHealth {
        if route.assignedAircraft.isEmpty { return .grounded }
        if disrupted { return .disrupted }
        let profit = route.economicsThisMonth.directOperatingProfit
        let closed = route.economicsLastMonth.directOperatingProfit
        // The month in progress is the live signal; the closed month is the
        // fallback while this one is still a rounding error.
        let money = route.economicsThisMonth == RouteMonthEconomics() ? closed : profit
        if route.stats.totalFlights > 0, route.stats.completionRate < 0.75 {
            return .disrupted
        }
        if money.isNegative || route.stats.loadFactor < 0.45 { return .weak }
        if route.stats.loadFactor >= 0.78 && money > .zero { return .strong }
        return .healthy
    }
}
