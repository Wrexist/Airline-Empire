import Foundation

/// Map read model (docs/UI_ARCHITECTURE.md §3): everything the map renderer
/// draws, computed in Core so positions, arcs, and live-flight
/// interpolation are tested headlessly. The renderer projects and draws;
/// it never computes gameplay-adjacent values.
public struct MapModel: Equatable, Sendable {
    public let airports: [MapAirport]
    public let routes: [MapRoute]
    public let flights: [MapFlight]

    public struct MapAirport: Equatable, Sendable {
        public let code: AirportCode
        public let name: String
        public let city: String
        public let position: MapPoint
        /// 0…1 size tier for level-of-detail (population-derived).
        public let prominence: Double
        public let servedByPlayer: Bool
        public let closed: Bool
    }

    public struct MapRoute: Equatable, Sendable {
        public let id: RouteID
        public let airline: AirlineID
        public let isPlayer: Bool
        public let from: MapPoint
        public let to: MapPoint
        /// Great-circle waypoints from `from` to `to` (inclusive), ready to
        /// draw as a polyline — correct curvature and date-line handling.
        public let arc: [MapPoint]
        public let dailyRoundTrips: Int
        public let profitable: Bool
        /// The operator's colours, so the map can tell four carriers apart
        /// instead of drawing every rival in the same grey.
        public let livery: Livery
    }

    public struct MapFlight: Equatable, Sendable {
        public let id: FlightID
        public let airline: AirlineID
        public let isPlayer: Bool
        public let position: MapPoint
        /// Course in degrees clockwise from north (icon rotation).
        public let heading: Double
        public let airborne: Bool
        public let livery: Livery
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

    static func centralAngle(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * atan2(h.squareRoot(), (1 - h).squareRoot())
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
    /// Presentation-only interpolation: airborne flights place along the
    /// great circle by elapsed flight-time fraction — never fed back into
    /// the simulation (docs/UI_ARCHITECTURE.md §3).
    public func mapModel(catalog: ContentCatalog) -> MapModel {
        let player = playerAirline?.id
        let playerAirports: Set<AirportCode> = player.map { id in
            var set = Set<AirportCode>()
            for route in routes(of: id) {
                set.insert(route.origin)
                set.insert(route.destination)
            }
            return set
        } ?? []

        let maxPopulation = Double(catalog.orderedAirportCodes
            .compactMap { catalog.airports[$0]?.demographics.populationThousands }
            .max() ?? 1)
        let airports = catalog.orderedAirportCodes.compactMap { code -> MapModel.MapAirport? in
            guard let spec = catalog.airports[code] else { return nil }
            return MapModel.MapAirport(
                code: code, name: spec.name, city: spec.city,
                position: MapPoint(coordinate: spec.coordinate),
                prominence: Double(spec.demographics.populationThousands) / maxPopulation,
                servedByPlayer: playerAirports.contains(code),
                closed: world.isAirportClosed(code, at: clock.now))
        }

        let mapRoutes = orderedRouteIDs.compactMap { routeID -> MapModel.MapRoute? in
            guard let route = self.routes[routeID],
                  let origin = catalog.airport(route.origin),
                  let destination = catalog.airport(route.destination) else { return nil }
            return MapModel.MapRoute(
                id: routeID, airline: route.airline,
                isPlayer: route.airline == player,
                from: MapPoint(coordinate: origin.coordinate),
                to: MapPoint(coordinate: destination.coordinate),
                arc: MapMath.arc(from: origin.coordinate, to: destination.coordinate),
                dailyRoundTrips: route.dailyRoundTrips,
                profitable: route.economicsLastMonth.directOperatingProfit > .zero,
                livery: airlines[route.airline]?.livery ?? .default)
        }

        let mapFlights = orderedFlightIDs.compactMap { flightID -> MapModel.MapFlight? in
            guard let flight = flights[flightID],
                  let from = catalog.airport(flight.from),
                  let to = catalog.airport(flight.to) else { return nil }
            switch flight.phase {
            case .enRoute(let actualDeparture):
                let elapsed = Double(clock.now.rawMinutes - actualDeparture.rawMinutes)
                let fraction = min(1, max(0, elapsed / Double(flight.flightMinutes)))
                let position = MapMath.greatCirclePoint(
                    from: from.coordinate, to: to.coordinate, fraction: fraction)
                let ahead = MapMath.greatCirclePoint(
                    from: from.coordinate, to: to.coordinate,
                    fraction: min(1, fraction + 0.02))
                let owner = aircraft[flight.aircraft]?.owner
                return MapModel.MapFlight(
                    id: flightID, airline: owner ?? AirlineID(raw: 0),
                    isPlayer: owner == player,
                    position: MapPoint(coordinate: position),
                    heading: MapMath.heading(from: position, to: ahead),
                    airborne: true,
                    livery: owner.flatMap { airlines[$0]?.livery } ?? .default)
            case .boarding, .turnaround:
                let owner = aircraft[flight.aircraft]?.owner
                return MapModel.MapFlight(
                    id: flightID, airline: owner ?? AirlineID(raw: 0),
                    isPlayer: owner == player,
                    position: MapPoint(coordinate: from.coordinate),
                    heading: MapMath.heading(from: from.coordinate, to: to.coordinate),
                    airborne: false,
                    livery: owner.flatMap { airlines[$0]?.livery } ?? .default)
            case .scheduled:
                return nil
            }
        }

        return MapModel(airports: airports, routes: mapRoutes, flights: mapFlights)
    }
}
