/// The deterministic heart: owns a `GameState`, a fixed system pipeline, and
/// a pending command queue, and advances time tick by tick
/// (docs/SIMULATION_ARCHITECTURE.md §3).
///
/// Not thread-safe by itself — `GameSession` (an actor) is the only caller
/// in production; tests drive it directly on one thread.
public final class SimulationEngine {
    public private(set) var state: GameState
    public let systems: [any SimulationSystem]
    public let catalog: ContentCatalog

    /// Commands submitted since the last tick boundary, in submission order.
    private var pendingCommands: [any Command] = []
    /// Results for the most recent `advance` call, aligned with the drained
    /// command order (submission order).
    public private(set) var lastCommandResults: [CommandResult] = []

    private let collector = EventCollector()

    public init(state: GameState, systems: [any SimulationSystem],
                catalog: ContentCatalog = .empty) {
        let ids = systems.map(\.id)
        precondition(Set(ids).count == ids.count, "Duplicate system ids: \(ids)")
        self.state = state
        self.systems = systems
        self.catalog = catalog
    }

    /// Enqueues a command; it applies at the next tick boundary
    /// (docs/SIMULATION_ARCHITECTURE.md §3 — a defined point keeps replays
    /// exact regardless of when the UI submitted).
    public func enqueue(_ command: any Command) {
        pendingCommands.append(command)
    }

    /// Validates and applies a command immediately *between* ticks.
    /// Used by `GameSession` while paused, so the player can act without the
    /// world moving; equivalent to enqueue + zero-length boundary.
    @discardableResult
    public func applyNow(_ command: any Command) -> CommandResult {
        let context = SimContext(previous: state.clock.now, current: state.clock.now,
                                 tick: SimDuration(minutes: 0), catalog: catalog,
                                 events: collector)
        let result = process(command, context: context)
        state.eventLog.append(contentsOf: collector.drain())
        return result
    }

    /// Advances the world by `tickCount` ticks. Chunk-invariant: advancing
    /// 96 ticks in one call equals 96 calls of one tick (verified by tests).
    public func advance(ticks tickCount: Int) {
        precondition(tickCount >= 0)
        lastCommandResults.removeAll(keepingCapacity: true)
        let tick = SimDuration(minutes: state.meta.tickMinutes)

        for _ in 0..<tickCount {
            let previous = state.clock.now
            state.clock.now += tick
            state.clock.tickCount += 1
            let context = SimContext(previous: previous, current: state.clock.now,
                                     tick: tick, catalog: catalog, events: collector)

            // 1. Drain commands queued before this boundary.
            if !pendingCommands.isEmpty {
                let batch = pendingCommands
                pendingCommands.removeAll(keepingCapacity: true)
                for command in batch {
                    lastCommandResults.append(process(command, context: context))
                }
            }

            // 2. Calendar events (before systems, so daily systems run
            //    "on the day that just started" with the event already logged).
            emitCalendarEvents(previous: previous, context: context)

            // 3. Scheduled wakes due by now.
            for entry in state.schedule.popDue(at: state.clock.now) {
                switch entry.kind {
                case .wake(let label):
                    context.emit(.wakeFired(label: label))
                }
            }

            // 4. Systems, in registered (documented) pipeline order.
            for system in systems where system.cadence.fires(
                previous: previous, current: state.clock.now, startYear: state.meta.startYear) {
                system.update(state: &state, context: context)
            }

            // 5. Collect events; integrity in debug builds.
            state.eventLog.append(contentsOf: collector.drain())
            assert(state.integrityViolations().isEmpty,
                   "Integrity violations: \(state.integrityViolations())")
        }
    }

    /// Events the UI digest builds on; emitted exactly when their boundary
    /// is crossed, independent of tick size.
    private func emitCalendarEvents(previous: SimTime, context: SimContext) {
        let now = state.clock.now
        let startYear = state.meta.startYear
        guard previous.dayIndex != now.dayIndex else { return }
        let date = GameCalendar.date(at: now, startYear: startYear)
        context.emit(.dayStarted(date))
        if previous.weekIndex != now.weekIndex {
            context.emit(.weekStarted(weekIndex: now.weekIndex))
        }
        if GameCalendar.monthIndex(at: previous) != GameCalendar.monthIndex(at: now) {
            context.emit(.monthStarted(year: date.year, month: date.month))
            let previousSeason = GameCalendar.date(at: previous, startYear: startYear).season
            if previousSeason != date.season {
                context.emit(.seasonChanged(date.season))
            }
        }
    }

    private func process(_ command: any Command, context: SimContext) -> CommandResult {
        if let rejection = command.validate(state: state, catalog: catalog) {
            return .rejected(rejection)
        }
        command.apply(state: &state, context: context)
        context.emit(.commandApplied(name: type(of: command).name))
        return .applied
    }
}
