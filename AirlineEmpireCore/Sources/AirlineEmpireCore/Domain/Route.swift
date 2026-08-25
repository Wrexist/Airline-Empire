/// A route: the atomic strategic object (docs/GAME_DESIGN.md §4.5).
/// Round-trip service between two airports with a frequency, a fare, and
/// assigned aircraft.
public struct Route: Equatable, Codable, Sendable {
    public let id: RouteID
    public let airline: AirlineID
    public let origin: AirportCode
    public let destination: AirportCode
    /// Fixed at opening from world geometry (whole km, deterministic).
    public let distanceKm: Int
    /// Target round trips per day across all assigned aircraft. The
    /// scheduler materializes at most what assigned aircraft can actually
    /// fly; the shortfall shows in `stats`.
    public var dailyRoundTrips: Int
    /// One-way economy fare per passenger.
    public var ticketPrice: Money
    /// Sorted aircraft IDs serving this route.
    public var assignedAircraft: [AircraftID]
    public var stats: RouteStats

    public init(id: RouteID, airline: AirlineID, origin: AirportCode,
                destination: AirportCode, distanceKm: Int, dailyRoundTrips: Int,
                ticketPrice: Money, assignedAircraft: [AircraftID] = [],
                stats: RouteStats = RouteStats()) {
        self.id = id
        self.airline = airline
        self.origin = origin
        self.destination = destination
        self.distanceKm = distanceKm
        self.dailyRoundTrips = dailyRoundTrips
        self.ticketPrice = ticketPrice
        self.assignedAircraft = assignedAircraft
        self.stats = stats
    }

    /// Daily airport movements this route consumes at EACH endpoint
    /// (one departure + one arrival per round trip).
    public static func dailySlotMovements(roundTrips: Int) -> Int {
        roundTrips * 2
    }

    public func servesAirport(_ code: AirportCode) -> Bool {
        origin == code || destination == code
    }

    /// True if the two routes cover the same city pair in either direction.
    public func sameMarket(origin o: AirportCode, destination d: AirportCode) -> Bool {
        (origin == o && destination == d) || (origin == d && destination == o)
    }
}

/// Operational counters; punctuality inputs for Phase 9. Lifetime counters
/// (bounded by being counters, not logs).
public struct RouteStats: Equatable, Codable, Sendable {
    public var flightsCompleted: Int64
    public var flightsCancelled: Int64
    public var flightsDelayed: Int64
    public var totalDelayMinutes: Int64

    public init(flightsCompleted: Int64 = 0, flightsCancelled: Int64 = 0,
                flightsDelayed: Int64 = 0, totalDelayMinutes: Int64 = 0) {
        self.flightsCompleted = flightsCompleted
        self.flightsCancelled = flightsCancelled
        self.flightsDelayed = flightsDelayed
        self.totalDelayMinutes = totalDelayMinutes
    }

    public var totalFlights: Int64 { flightsCompleted + flightsCancelled }

    /// Share of flights that operated (not cancelled); 1.0 with no history.
    public var completionRate: Double {
        totalFlights == 0 ? 1.0 : Double(flightsCompleted) / Double(totalFlights)
    }

    /// Share of completed flights that left on time; 1.0 with no history.
    public var punctuality: Double {
        flightsCompleted == 0 ? 1.0
            : Double(flightsCompleted - min(flightsDelayed, flightsCompleted))
                / Double(flightsCompleted)
    }
}
