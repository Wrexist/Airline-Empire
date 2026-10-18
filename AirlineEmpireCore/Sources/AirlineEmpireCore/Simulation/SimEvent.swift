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
    /// `airline` is the seller. The aircraft is deleted in the same command
    /// that emits this, so its owner cannot be looked up afterwards; without
    /// the payload the player's own sale was classified as nobody's business
    /// and never reached their feed. Optional: events in older saves lack it.
    case aircraftSold(id: AircraftID, proceeds: Money, airline: AirlineID? = nil)
    /// `airline` is the lessee — same reason, same optionality.
    case leaseReturned(id: AircraftID, penalty: Money, airline: AirlineID? = nil)
    case maintenanceStarted(id: AircraftID, until: SimTime, cost: Money)
    case maintenanceCompleted(id: AircraftID)

    // Routes & flights (Phase 6)
    case routeOpened(id: RouteID, origin: AirportCode, destination: AirportCode)
    case routeClosed(id: RouteID)
    /// Competition (AE-037). `routeOpened` carries no airline and
    /// `routeClosed` names a route already deleted, so neither can say *who*
    /// entered or left *whose* market. These can, and they are the only
    /// route events a rival's business is allowed to put in the player's
    /// feed — when the pair is one the player flies.
    case marketEntered(airline: AirlineID, origin: AirportCode, destination: AirportCode)
    case marketLeft(airline: AirlineID, origin: AirportCode, destination: AirportCode)
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

    // Living world (Phase 11)
    case worldEventForecast(kind: WorldEventKind, beginsAt: SimTime)
    case worldEventStarted(id: Int64, kind: WorldEventKind)
    case worldEventEnded(id: Int64, kind: WorldEventKind)

    // Progression (Phase 12)
    case eraAdvanced(era: Era)
    case milestoneReached(code: String)
    case achievementUnlocked(code: String)
    case capabilityCompleted(code: CapabilityCode)
    case missionOffered(id: Int64, kind: MissionKind, deadline: SimTime, reward: Money)
    case missionCompleted(id: Int64, reward: Money)
    case missionExpired(id: Int64)
    case gameOver

    // Hub buildings (docs/HUB_PROGRESSION_PLAN.md)
    case facilityOpened(airline: AirlineID, airport: AirportCode, service: AirportService, level: Int)
    case hubStatusRaised(airline: AirlineID, airport: AirportCode, status: HubStatus)
}

/// Fixed-capacity ring of recent events plus a lifetime counter.
/// Bounded by rule (docs/DOMAIN_MODEL.md §3): the UI needs recency, history
/// systems keep their own rollups.
///
/// Beside the shared ring, a second ring keeps the player's feed (TD-032).
/// The shared ring is one window for the whole world, and a busy world posts
/// more than 512 events in a day — mostly rivals' flights — so the player's
/// own news (a rival entering their market, their own sale, a closure at
/// their hub) was gone from it by the next morning. The feed ring holds only
/// what `isFeedEvent` admits for the player, minus the per-flight and
/// calendar texture nobody reads back, so rival traffic cannot evict it.
public struct BoundedEventLog: Equatable, Codable, Sendable {
    public static let defaultCapacity = 512
    /// The feed ring's size. The player's own arrivals are its largest
    /// source — one per leg flown — so this covers a full day for any fleet
    /// below ~170 aircraft and weeks of everything else.
    public static let feedCapacity = 1024

    public private(set) var capacity: Int
    public private(set) var recent: [SimEvent]
    public private(set) var totalCount: Int64
    /// Stored optional so a save from before the feed (format 15) decodes;
    /// read through `playerFeed`.
    private var feedEvents: [SimEvent]?
    /// When the feed began recording: game start, or the first tick after a
    /// pre-feed save was loaded. Before it, the feed knows nothing.
    private var feedStart: SimTime?

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.recent = []
        self.totalCount = 0
        self.feedEvents = []
        self.feedStart = nil
    }

    /// The player airline's feed, oldest first: every event `isFeedEvent`
    /// admitted for the player when it happened, except per-flight and
    /// calendar texture (`isFeedTexture`).
    public var playerFeed: [SimEvent] { feedEvents ?? [] }

    /// The time from which `playerFeed` is complete, if it has started.
    public var playerFeedStart: SimTime? { feedStart }

    /// The player's feed events in `[start, end)` — or nil when the feed
    /// cannot vouch for the whole window (it started later, or the ring has
    /// already dropped part of it), so the caller falls back to `recent`.
    public func playerFeedEvents(from start: SimTime, to end: SimTime) -> [SimEvent]? {
        guard let feedStart, feedStart <= start else { return nil }
        let feed = playerFeed
        if feed.count >= Self.feedCapacity, let oldest = feed.first, oldest.at >= start {
            return nil
        }
        return feed.filter { $0.at >= start && $0.at < end }
    }

    /// Kinds the feed ring does not keep even when they are the player's:
    /// the per-flight chatter and calendar ticks a digest skips. Arrivals
    /// and cancellations stay — a digest counts them.
    public static func isFeedTexture(_ kind: SimEventKind) -> Bool {
        switch kind {
        case .flightDeparted, .flightDelayed, .aircraftAssigned, .aircraftUnassigned,
             .dayStarted, .weekStarted, .monthStarted, .wakeFired, .commandApplied:
            return true
        default:
            return false
        }
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

    /// Starts the feed's coverage clock if it has not started.
    mutating func startPlayerFeedIfNeeded(at time: SimTime) {
        guard feedStart == nil else { return }
        feedStart = time
        if feedEvents == nil { feedEvents = [] }
    }

    /// Files one event in the player's feed ring.
    mutating func appendToPlayerFeed(_ event: SimEvent) {
        if feedEvents == nil { feedEvents = [] }
        feedEvents?.append(event)
        if let count = feedEvents?.count, count > Self.feedCapacity {
            feedEvents?.removeFirst(count - Self.feedCapacity)
        }
    }
}

extension GameState {
    /// Appends a batch of just-emitted events to the log, filing the
    /// player's copy in the feed ring as it goes. Classified here — right
    /// after the command or tick that produced them, against the state they
    /// describe — because ownership has to be resolved before the entities
    /// can change hands or disappear.
    mutating func recordEvents(_ events: [SimEvent]) {
        guard !events.isEmpty else { return }
        eventLog.startPlayerFeedIfNeeded(at: clock.now)
        let player = playerAirline?.id
        for event in events {
            eventLog.append(event)
            if let player, !BoundedEventLog.isFeedTexture(event.kind),
               isFeedEvent(event, for: player) {
                eventLog.appendToPlayerFeed(event)
            }
        }
    }
}
