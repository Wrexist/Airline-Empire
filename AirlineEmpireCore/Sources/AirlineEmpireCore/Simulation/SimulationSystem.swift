/// A simulation system: a stateless value that advances one aspect of the
/// world (docs/SIMULATION_ARCHITECTURE.md §4). All state lives in
/// `GameState`; systems never call each other; registration order is the
/// documented pipeline order.
public protocol SimulationSystem: Sendable {
    /// Stable identifier; used in diagnostics and (by convention) as the
    /// prefix of the system's RNG stream labels.
    var id: String { get }
    var cadence: Cadence { get }
    func update(state: inout GameState, context: SimContext)
}

/// Per-tick context handed to systems and commands. Everything a system may
/// consult beyond `GameState`; deliberately small — systems that need more
/// probably want state or content instead.
public struct SimContext: Sendable {
    /// Tick interval endpoints: the update covers (previous, current].
    public let previous: SimTime
    public let current: SimTime
    public let tick: SimDuration
    /// Static game content (never part of GameState).
    public let catalog: ContentCatalog
    /// Event sink for this update. Events are appended to the state's log
    /// (and streamed to the UI) after the system returns.
    public let events: EventCollector

    public init(previous: SimTime, current: SimTime, tick: SimDuration,
                catalog: ContentCatalog, events: EventCollector) {
        self.previous = previous
        self.current = current
        self.tick = tick
        self.catalog = catalog
        self.events = events
    }

    public func emit(_ kind: SimEventKind) {
        events.append(SimEvent(at: current, kind: kind))
    }
}

/// Reference sink so `SimContext` can stay a value while collecting.
/// Confined to the engine's single-threaded update; never escapes a tick.
public final class EventCollector: @unchecked Sendable {
    private(set) var events: [SimEvent] = []

    public init() {}

    func append(_ event: SimEvent) {
        events.append(event)
    }

    func drain() -> [SimEvent] {
        let drained = events
        events.removeAll(keepingCapacity: true)
        return drained
    }
}
