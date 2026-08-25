/// A live world event (docs/DOMAIN_MODEL.md; framework in docs/EVENTS.md).
/// Systemic: triggered from state + seeded randomness with rate limits,
/// applying its effects through the systems that own the affected domain —
/// never as detached popups.
public struct WorldEvent: Equatable, Codable, Sendable {
    public let id: Int64
    public let kind: WorldEventKind
    /// Storms carry a forecast lead: created before they begin.
    public let beginsAt: SimTime
    public let endsAt: SimTime
    /// 0…1 within the kind's semantics.
    public let severity: Double
    /// Set once the start has been announced.
    public var hasStarted: Bool

    public init(id: Int64, kind: WorldEventKind, beginsAt: SimTime,
                endsAt: SimTime, severity: Double) {
        self.id = id
        self.kind = kind
        self.beginsAt = beginsAt
        self.endsAt = endsAt
        self.severity = severity
        self.hasStarted = false
    }

    public func isActive(at time: SimTime) -> Bool {
        beginsAt <= time && time < endsAt
    }
}

/// Grows per expansion; cases never repurposed.
public enum WorldEventKind: Equatable, Codable, Sendable {
    /// Fuel market shock: the walk's reversion target scales by (1+severity).
    case fuelShock
    /// Regional severe weather: extra dispatch disruption on flights
    /// touching the region.
    case storm(region: WorldRegion)
    /// Airport fully closed: nothing boards there (severe-storm escalation).
    case airportClosure(airport: AirportCode)
    /// Destination-region leisure demand up by (1 + boost x severity).
    case tourismBoom(region: WorldRegion)
    /// Airline-wide strike: no boardings for the struck airline.
    case strike(airline: AirlineID)
}

extension WorldState {
    /// Severity of an active storm covering the region, if any.
    public func activeStorm(in region: WorldRegion, at time: SimTime) -> Double? {
        for event in activeEvents where event.isActive(at: time) {
            if case .storm(let r) = event.kind, r == region { return event.severity }
        }
        return nil
    }

    public func isAirportClosed(_ code: AirportCode, at time: SimTime) -> Bool {
        activeEvents.contains { event in
            guard event.isActive(at: time) else { return false }
            if case .airportClosure(let airport) = event.kind { return airport == code }
            return false
        }
    }

    /// Extra leisure multiplier for destinations in the region (0 = none).
    public func tourismBoost(for region: WorldRegion, at time: SimTime) -> Double {
        for event in activeEvents where event.isActive(at: time) {
            if case .tourismBoom(let r) = event.kind, r == region { return event.severity }
        }
        return 0
    }

    public func strikeActive(for airline: AirlineID, at time: SimTime) -> Bool {
        activeEvents.contains { event in
            guard event.isActive(at: time) else { return false }
            if case .strike(let struck) = event.kind { return struck == airline }
            return false
        }
    }

    /// Fuel reversion-target multiplier from an active shock (1 = none).
    public func fuelShockFactor(at time: SimTime) -> Double {
        for event in activeEvents where event.isActive(at: time) {
            if case .fuelShock = event.kind { return 1 + event.severity }
        }
        return 1
    }
}
