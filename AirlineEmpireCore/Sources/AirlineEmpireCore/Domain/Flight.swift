/// A live flight instance. Created by the scheduler shortly before
/// operation, removed after turnaround completes — `GameState.flights`
/// holds only active/imminent flights (docs/DOMAIN_MODEL.md §3), with
/// history condensed into `RouteStats` and the ledger.
public struct Flight: Equatable, Codable, Sendable {
    public let id: FlightID
    public let route: RouteID
    public let aircraft: AircraftID
    public let kind: FlightKind
    public let from: AirportCode
    public let to: AirportCode
    public let distanceKm: Int
    /// Airborne minutes (excludes turnaround).
    public let flightMinutes: Int64
    public let scheduledDeparture: SimTime
    /// Actual planned departure; pushed forward by delays.
    public var departureTime: SimTime
    public var phase: FlightPhase
    /// Set once when the first delay hits (counted once in stats).
    public var wasDelayed: Bool
    /// Seats sold (Phase 7 fills this; ferries stay 0).
    public var passengers: Int

    public init(id: FlightID, route: RouteID, aircraft: AircraftID, kind: FlightKind,
                from: AirportCode, to: AirportCode, distanceKm: Int,
                flightMinutes: Int64, scheduledDeparture: SimTime) {
        self.id = id
        self.route = route
        self.aircraft = aircraft
        self.kind = kind
        self.from = from
        self.to = to
        self.distanceKm = distanceKm
        self.flightMinutes = flightMinutes
        self.scheduledDeparture = scheduledDeparture
        self.departureTime = scheduledDeparture
        self.phase = .scheduled
        self.wasDelayed = false
        self.passengers = 0
    }

    public var delayMinutes: Int64 {
        max(0, departureTime.rawMinutes - scheduledDeparture.rawMinutes)
    }
}

public enum FlightKind: String, Equatable, Codable, Sendable {
    /// Regular passenger service on the route.
    case revenue
    /// Repositioning to the route's origin; full costs, no passengers.
    case ferry
}

/// Flight state machine (docs/ROUTES.md):
/// scheduled → boarding → enRoute → turnaround → (removed).
/// Cancellation removes the flight from `boarding`.
public enum FlightPhase: Equatable, Codable, Sendable {
    case scheduled
    case boarding
    case enRoute(actualDeparture: SimTime)
    case turnaround(until: SimTime)
}
