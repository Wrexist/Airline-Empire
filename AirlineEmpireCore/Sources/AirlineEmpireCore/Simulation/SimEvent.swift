/// Events are outputs of the simulation (docs/ARCHITECTURE.md §3.3): facts
/// that happened, consumed by UI feed, notifications, analytics, and
/// achievements. Replaying commands over ticks regenerates them; they are
/// never inputs to game logic.
public struct SimEvent: Equatable, Codable, Sendable {
    /// When the event happened.
    public let at: SimTime
    public let kind: SimEventKind

    public init(at: SimTime, kind: SimEventKind) {
        self.at = at
        self.kind = kind
    }
}

/// Grows case-by-case per phase; cases are never repurposed
/// (docs/ARCHITECTURE.md §12).
public enum SimEventKind: Equatable, Codable, Sendable {
    // Kernel calendar events — the UI digest and cadence-visible moments.
    case dayStarted(GameDate)
    case weekStarted(weekIndex: Int64)
    case monthStarted(year: Int, month: Int)
    case seasonChanged(Season)
    /// A scheduled wake fired (see ScheduleQueue).
    case wakeFired(label: String)
    /// A command was applied successfully. Carried for feed/replay
    /// diagnostics; the command's own effects emit their domain events.
    case commandApplied(name: String)

    // Fleet (Phase 5)
    case airlineFounded(id: AirlineID, name: String)
    case aircraftOrdered(id: AircraftID, type: AircraftTypeCode, deliveryAt: SimTime)
    case aircraftDelivered(id: AircraftID)
    case aircraftSold(id: AircraftID, proceeds: Money)
    case leaseReturned(id: AircraftID, penalty: Money)
    case maintenanceStarted(id: AircraftID, until: SimTime, cost: Money)
    case maintenanceCompleted(id: AircraftID)

    // Routes & flights (Phase 6)
    case routeOpened(id: RouteID, origin: AirportCode, destination: AirportCode)
    case routeClosed(id: RouteID)
    case aircraftAssigned(aircraft: AircraftID, route: RouteID)
    case aircraftUnassigned(aircraft: AircraftID, route: RouteID)
    case flightDeparted(id: FlightID, route: RouteID)
    case flightDelayed(id: FlightID, route: RouteID, delayMinutes: Int64)
    case flightCancelled(id: FlightID, route: RouteID)
    case flightArrived(id: FlightID, route: RouteID, delayMinutes: Int64)

    // Finance & world (Phase 8)
    case loanTaken(airline: AirlineID, amount: Money, rateBasisPoints: Int)
    case loanRepaidEarly(airline: AirlineID, amount: Money)
    case statementClosed(airline: AirlineID, year: Int, month: Int, netProfit: Money)
    case airlineEnteredAdministration(id: AirlineID)
    case airlineCollapsed(id: AirlineID)
}

/// Fixed-capacity ring of recent events plus a lifetime counter.
/// Bounded by rule (docs/DOMAIN_MODEL.md §3): the UI needs recency, history
/// systems keep their own rollups.
public struct BoundedEventLog: Equatable, Codable, Sendable {
    public static let defaultCapacity = 512

    public private(set) var capacity: Int
    public private(set) var recent: [SimEvent]
    public private(set) var totalCount: Int64

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.recent = []
        self.totalCount = 0
    }

    public mutating func append(_ event: SimEvent) {
        totalCount += 1
        recent.append(event)
        if recent.count > capacity {
            recent.removeFirst(recent.count - capacity)
        }
    }

    public mutating func append(contentsOf events: [SimEvent]) {
        for event in events { append(event) }
    }
}
