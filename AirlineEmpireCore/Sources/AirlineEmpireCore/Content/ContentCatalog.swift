import Foundation

/// Immutable, validated game content (docs/ARCHITECTURE.md §6). Loaded once
/// at startup; passed by reference; never part of `GameState` — saves refer
/// to content by stable codes.
public final class ContentCatalog: Sendable {
    public let version: String
    public let airports: [AirportCode: AirportSpec]
    public let seasonality: [SeasonalityCode: SeasonalityProfile]
    public let tuning: Tuning

    /// Airport codes in stable sorted order — the iteration order for any
    /// deterministic sweep over airports.
    public let orderedAirportCodes: [AirportCode]

    public init(version: String, airports: [AirportSpec],
                seasonality: [SeasonalityProfile], tuning: Tuning) throws {
        var airportMap: [AirportCode: AirportSpec] = [:]
        var seasonMap: [SeasonalityCode: SeasonalityProfile] = [:]
        var problems: [String] = []

        for profile in seasonality {
            if seasonMap[profile.code] != nil {
                problems.append("Duplicate seasonality profile: \(profile.code)")
            }
            if profile.leisureMonthly.count != 12 {
                problems.append("Profile \(profile.code) has \(profile.leisureMonthly.count) months")
            }
            if !profile.leisureMonthly.allSatisfy({ $0 > 0 && $0.isFinite }) {
                problems.append("Profile \(profile.code) has non-positive multipliers")
            }
            seasonMap[profile.code] = profile
        }

        for airport in airports {
            if airportMap[airport.code] != nil {
                problems.append("Duplicate airport code: \(airport.code)")
            }
            if airport.code.raw.isEmpty || airport.name.isEmpty {
                problems.append("Airport with empty code or name: \(airport.code)")
            }
            if !airport.coordinate.isValid {
                problems.append("Airport \(airport.code) has invalid coordinates")
            }
            if airport.slotCapacityPerDay <= 0 || airport.terminalCapacityPerDay <= 0 {
                problems.append("Airport \(airport.code) has non-positive capacity")
            }
            if airport.movementFee.isNegative || airport.passengerFee.isNegative {
                problems.append("Airport \(airport.code) has negative fees")
            }
            if !airport.demographics.indicesValid || airport.demographics.populationThousands <= 0 {
                problems.append("Airport \(airport.code) has invalid demographics")
            }
            if !(-14 * 60...14 * 60).contains(airport.utcOffsetMinutes) {
                problems.append("Airport \(airport.code) has impossible UTC offset")
            }
            if seasonMap[airport.seasonality] == nil {
                problems.append("Airport \(airport.code) references unknown seasonality \(airport.seasonality)")
            }
            airportMap[airport.code] = airport
        }

        guard problems.isEmpty else {
            throw ContentError.invalid(problems)
        }
        self.version = version
        self.airports = airportMap
        self.seasonality = seasonMap
        self.tuning = tuning
        self.orderedAirportCodes = airportMap.keys.sorted()
    }

    // MARK: Lookup

    public func airport(_ code: AirportCode) -> AirportSpec? {
        airports[code]
    }

    public func airports(in region: WorldRegion) -> [AirportSpec] {
        orderedAirportCodes.compactMap { airports[$0] }.filter { $0.region == region }
    }

    /// Distance between two known airports, whole km.
    public func distanceKm(_ a: AirportCode, _ b: AirportCode) -> Int? {
        guard let sa = airports[a], let sb = airports[b] else { return nil }
        return Geo.distanceKm(from: sa.coordinate, to: sb.coordinate)
    }

    /// Nearest other airports by great-circle distance, ascending.
    public func nearestAirports(to code: AirportCode, limit: Int) -> [(AirportSpec, Int)] {
        guard let origin = airports[code] else { return [] }
        return orderedAirportCodes
            .compactMap { airports[$0] }
            .filter { $0.code != code }
            .map { ($0, Geo.distanceKm(from: origin.coordinate, to: $0.coordinate)) }
            .sorted { ($0.1, $0.0.code) < ($1.1, $1.0.code) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Route eligibility

    /// Static-world eligibility of a route (docs/AIRPORTS.md). Dynamic
    /// constraints (slots free today, aircraft availability) are checked by
    /// the systems that own that state.
    public func routeEligibility(from origin: AirportCode, to destination: AirportCode,
                                 aircraftRangeKm: Int,
                                 aircraftRunwayRequirement: RunwayClass) -> [RouteIneligibility] {
        var reasons: [RouteIneligibility] = []
        guard let a = airports[origin] else { return [.unknownAirport(origin)] }
        guard let b = airports[destination] else { return [.unknownAirport(destination)] }
        if origin == destination {
            return [.sameAirport]
        }
        let distance = Geo.distanceKm(from: a.coordinate, to: b.coordinate)
        if distance < tuning.minRouteDistanceKm {
            reasons.append(.belowMinimumDistance(distance: distance, minimum: tuning.minRouteDistanceKm))
        }
        if distance > aircraftRangeKm {
            reasons.append(.beyondAircraftRange(distance: distance, range: aircraftRangeKm))
        }
        if a.runwayClass < aircraftRunwayRequirement {
            reasons.append(.runwayTooSmall(airport: origin, has: a.runwayClass, needs: aircraftRunwayRequirement))
        }
        if b.runwayClass < aircraftRunwayRequirement {
            reasons.append(.runwayTooSmall(airport: destination, has: b.runwayClass, needs: aircraftRunwayRequirement))
        }
        return reasons
    }
}

public enum RouteIneligibility: Equatable, Sendable {
    case unknownAirport(AirportCode)
    case sameAirport
    case belowMinimumDistance(distance: Int, minimum: Int)
    case beyondAircraftRange(distance: Int, range: Int)
    case runwayTooSmall(airport: AirportCode, has: RunwayClass, needs: RunwayClass)
}

public enum ContentError: Error, Sendable {
    case invalid([String])
    case missingResource(String)
}

/// World-level balance constants (docs/GAME_BALANCE.md; content, not code).
public struct Tuning: Equatable, Codable, Sendable {
    /// Routes shorter than this are ground-transport territory.
    public let minRouteDistanceKm: Int

    public init(minRouteDistanceKm: Int) {
        self.minRouteDistanceKm = minRouteDistanceKm
    }
}

// MARK: Loading from bundled resources

extension ContentCatalog {
    struct AirportsFile: Codable {
        let version: String
        let airports: [AirportSpec]
    }

    struct SeasonalityFile: Codable {
        let profiles: [SeasonalityProfile]
    }

    /// Loads and validates the shipped content. Fails loudly on any defect
    /// (docs/ARCHITECTURE.md §6): broken content is a build/test failure,
    /// never a runtime surprise.
    public static func loadBundled() throws -> ContentCatalog {
        let decoder = JSONDecoder()
        let airportsFile = try decoder.decode(AirportsFile.self, from: resourceData("airports"))
        let seasonalityFile = try decoder.decode(SeasonalityFile.self, from: resourceData("seasonality"))
        let tuning = try decoder.decode(Tuning.self, from: resourceData("tuning"))
        return try ContentCatalog(version: airportsFile.version,
                                  airports: airportsFile.airports,
                                  seasonality: seasonalityFile.profiles,
                                  tuning: tuning)
    }

    private static func resourceData(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw ContentError.missingResource("\(name).json")
        }
        return try Data(contentsOf: url)
    }
}
