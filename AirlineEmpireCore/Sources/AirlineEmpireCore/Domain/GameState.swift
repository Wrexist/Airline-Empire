/// The entire authoritative game world as one value (docs/ARCHITECTURE.md §3).
///
/// Mutated only by validated commands and the tick pipeline. Later phases
/// add slices (world, airlines, aircraft, routes, flights, ledger,
/// progression) — each addition bumps `SaveFormat.currentVersion` with a
/// migration.
public struct GameState: Equatable, Codable, Sendable {
    public var meta: GameMeta
    public var clock: ClockState
    public var rng: RNGState
    public var schedule: ScheduleQueue
    public var eventLog: BoundedEventLog

    public init(meta: GameMeta, clock: ClockState, rng: RNGState,
                schedule: ScheduleQueue = ScheduleQueue(),
                eventLog: BoundedEventLog = BoundedEventLog(capacity: BoundedEventLog.defaultCapacity)) {
        self.meta = meta
        self.clock = clock
        self.rng = rng
        self.schedule = schedule
        self.eventLog = eventLog
    }

    /// The game date at the current simulation time.
    public var currentDate: GameDate {
        GameCalendar.date(at: clock.now, startYear: meta.startYear)
    }

    /// Debug/test invariant sweep (docs/DOMAIN_MODEL.md §4). Grows with the
    /// domain; returns violations rather than trapping so tests can assert
    /// on specifics.
    public func integrityViolations() -> [String] {
        var violations: [String] = []
        if clock.now.rawMinutes < 0 {
            violations.append("Clock precedes epoch: \(clock.now.rawMinutes)")
        }
        if !schedule.isWellOrdered {
            violations.append("Schedule queue ordering broken")
        }
        return violations
    }
}

/// Save-critical metadata: identity of the world and the rules it runs under.
public struct GameMeta: Equatable, Codable, Sendable {
    public let scenario: ScenarioCode
    public let worldSeed: UInt64
    public let startYear: Int
    /// Tick size is part of the save contract (decision D-007); changing it
    /// requires a migration, so it is state, not a code constant.
    public let tickMinutes: Int64
    public var idAllocator: IDAllocator

    public init(scenario: ScenarioCode, worldSeed: UInt64, startYear: Int,
                tickMinutes: Int64, idAllocator: IDAllocator = IDAllocator()) {
        precondition(tickMinutes > 0 && GameCalendar.minutesPerDay % tickMinutes == 0,
                     "Tick size must divide a day evenly")
        self.scenario = scenario
        self.worldSeed = worldSeed
        self.startYear = startYear
        self.tickMinutes = tickMinutes
        self.idAllocator = idAllocator
    }
}

public struct ClockState: Equatable, Codable, Sendable {
    public var now: SimTime
    /// Ticks advanced since scenario start; convenient for cadence math and
    /// diagnostics.
    public var tickCount: Int64

    public init(now: SimTime = .epoch, tickCount: Int64 = 0) {
        self.now = now
        self.tickCount = tickCount
    }
}
