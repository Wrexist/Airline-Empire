/// The single façade the app talks to (docs/UI_ARCHITECTURE.md §1): owns the
/// engine on one actor, converts real elapsed time into ticks by speed, and
/// publishes snapshots and events.
///
/// Real-time pumping is driven from outside (`pump(elapsedSeconds:)`) so the
/// session contains no timers itself — the app shell attaches a display-link
/// or scheduled task, tests call `pump` with exact values. This keeps every
/// speed/pause behavior deterministic and testable (banned-API rules,
/// docs/TECHNICAL_STANDARDS.md §3).
public actor GameSession {
    public private(set) var speed: SimSpeed
    private let engine: SimulationEngine
    /// Fractional tick accumulator: real seconds already consumed but not
    /// yet amounting to a whole tick at the current speed.
    private var pendingGameMinutes: Double = 0

    private var saveManager: SaveManager?
    private var autosaveSlot = "auto"
    private var autosaveEveryGameDays: Int64 = 7
    private var lastAutosaveDay: Int64 = 0
    /// Most recent autosave failure, if any (surfaced by the UI).
    public private(set) var lastSaveError: String?

    private var snapshotContinuations: [Int: AsyncStream<GameState>.Continuation] = [:]
    private var eventContinuations: [Int: AsyncStream<SimEvent>.Continuation] = [:]
    private var nextSubscriptionID = 0
    private var deliveredEventCount: Int64

    public init(state: GameState, systems: [any SimulationSystem],
                catalog: ContentCatalog = .empty, speed: SimSpeed = .paused) {
        self.engine = SimulationEngine(state: state, systems: systems, catalog: catalog)
        self.speed = speed
        self.deliveredEventCount = state.eventLog.totalCount
    }

    // MARK: State access

    public var snapshot: GameState { engine.state }

    public func snapshots() -> AsyncStream<GameState> {
        AsyncStream { continuation in
            nextSubscriptionID += 1
            let id = nextSubscriptionID
            snapshotContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSnapshotContinuation(id) }
            }
            continuation.yield(engine.state)
        }
    }

    public func events() -> AsyncStream<SimEvent> {
        AsyncStream { continuation in
            nextSubscriptionID += 1
            let id = nextSubscriptionID
            eventContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeEventContinuation(id) }
            }
        }
    }

    // MARK: Persistence

    /// Attaches persistence: explicit saves plus periodic autosaves during
    /// fast-forward (docs/PERSISTENCE_ARCHITECTURE.md §4).
    public func attachSaveManager(_ manager: SaveManager, autosaveSlot: String = "auto",
                                  autosaveEveryGameDays: Int64 = 7) {
        self.saveManager = manager
        self.autosaveSlot = autosaveSlot
        self.autosaveEveryGameDays = max(1, autosaveEveryGameDays)
        self.lastAutosaveDay = engine.state.clock.now.dayIndex
    }

    /// Saves the current snapshot to a slot (also used on backgrounding).
    public func saveNow(slot: String) throws {
        guard let saveManager else { throw SaveError.corruptPayload("No save manager attached") }
        try saveManager.save(engine.state, slot: slot)
    }

    private func autosaveIfDue() {
        guard let saveManager else { return }
        let day = engine.state.clock.now.dayIndex
        guard day - lastAutosaveDay >= autosaveEveryGameDays else { return }
        do {
            try saveManager.save(engine.state, slot: autosaveSlot)
            lastAutosaveDay = day
            lastSaveError = nil
        } catch {
            // Never crash gameplay over IO; surface and retry next window.
            lastAutosaveDay = day
            lastSaveError = "\(error)"
        }
    }

    // MARK: Control

    public func setSpeed(_ newSpeed: SimSpeed) {
        speed = newSpeed
        if newSpeed == .paused {
            // Dropping the fraction on pause keeps resume behavior
            // independent of when the pause happened.
            pendingGameMinutes = 0
        }
    }

    /// Converts elapsed real time into ticks at the current speed and
    /// advances the engine. Returns the number of ticks run.
    @discardableResult
    public func pump(elapsedSeconds: Double) -> Int {
        precondition(elapsedSeconds >= 0 && elapsedSeconds.isFinite)
        guard speed != .paused else { return 0 }
        pendingGameMinutes += elapsedSeconds * speed.gameMinutesPerRealSecond
        let tickMinutes = Double(engine.state.meta.tickMinutes)
        let ticks = Int(pendingGameMinutes / tickMinutes)
        guard ticks > 0 else { return 0 }
        pendingGameMinutes -= Double(ticks) * tickMinutes
        advance(ticks: ticks)
        return ticks
    }

    /// Advances exactly `ticks` ticks regardless of speed (used by
    /// "advance to next morning" and by tests).
    public func advance(ticks: Int) {
        // Chunked so long fast-forwards keep draining commands at
        // boundaries (docs/SIMULATION_ARCHITECTURE.md §3).
        var remaining = ticks
        let chunk = Int(GameCalendar.minutesPerDay / engine.state.meta.tickMinutes)
        while remaining > 0 {
            let step = min(chunk, remaining)
            engine.advance(ticks: step)
            remaining -= step
            autosaveIfDue()
            publish()
        }
    }

    /// Runs the simulation to the start of the next game day.
    public func advanceToNextMorning() {
        let now = engine.state.clock.now
        let nextMidnight = (now.dayIndex + 1) * GameCalendar.minutesPerDay
        let minutes = nextMidnight - now.rawMinutes
        advance(ticks: Int(minutes / engine.state.meta.tickMinutes))
    }

    /// Submits a command. While paused it applies immediately (the player
    /// may act with the world stopped); while running it applies at the next
    /// tick boundary and the result reports as `.applied` optimistically
    /// only through the events stream — so callers get the definitive
    /// result: enqueued commands return nil and surface via events.
    public func submit(_ command: any Command) -> CommandResult? {
        if speed == .paused {
            let result = engine.applyNow(command)
            publish()
            return result
        } else {
            engine.enqueue(command)
            return nil
        }
    }

    // MARK: Publishing

    private func publish() {
        let state = engine.state
        for continuation in snapshotContinuations.values {
            continuation.yield(state)
        }
        // Deliver only events not yet streamed (log is bounded; a consumer
        // that falls a full ring behind misses old events by design).
        let missed = state.eventLog.totalCount - deliveredEventCount
        if missed > 0 {
            let available = min(Int(missed), state.eventLog.recent.count)
            for event in state.eventLog.recent.suffix(available) {
                for continuation in eventContinuations.values {
                    continuation.yield(event)
                }
            }
            deliveredEventCount = state.eventLog.totalCount
        }
    }

    private func removeSnapshotContinuation(_ id: Int) {
        snapshotContinuations[id] = nil
    }

    private func removeEventContinuation(_ id: Int) {
        eventContinuations[id] = nil
    }
}

/// Presentation-facing speeds (docs/CORE_LOOP.md §2): at 1× a game-day takes
/// six real minutes.
public enum SimSpeed: String, Codable, Sendable, CaseIterable {
    case paused
    case x1
    case x4
    case x16

    public var gameMinutesPerRealSecond: Double {
        switch self {
        case .paused: 0
        case .x1: 4      // 1440 game-min / 360 real-s
        case .x4: 16
        case .x16: 64
        }
    }
}

