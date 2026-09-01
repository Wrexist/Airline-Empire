/// Mutable world-layer state (docs/DOMAIN_MODEL.md §2 runtime slice).
/// Only what changes at runtime lives here; static airport data stays in
/// `ContentCatalog`. Entries are created lazily on first use so saves stay
/// proportional to the world the player actually touches.
public struct WorldState: Equatable, Codable, Sendable {
    public var airportRuntimes: [AirportCode: AirportRuntime]
    /// Jet fuel spot price per metric tonne (cent resolution matters for
    /// the daily walk; per-kg cents were too coarse to move).
    public var fuelPricePerTon: Money
    /// Macro-economy index (1.0 = neutral). Business demand reacts more
    /// strongly than leisure. Driven by WorldSystem's regime cycle.
    public var economicIndex: Double
    /// The level the economy is currently drifting toward (regime).
    public var economicCycleTarget: Double
    /// Live world events (forecast + active), bounded by rate limits.
    public var activeEvents: [WorldEvent]
    public var nextEventID: Int64
    /// Deterministic trigger cooldowns, keyed by label ("major",
    /// "strike.<id>"), value = dayIndex of last occurrence.
    public var eventCooldowns: [String: Int64]
    /// Who entered and left which city pair, most recent last — the
    /// competitive record the event log cannot keep. `routeOpened` names no
    /// airline and `routeClosed` names a route that no longer exists, so a
    /// rival's entry into the player's market was classified as nobody's
    /// business and its retreat could never be attributed at all; both were
    /// gone from the 512-event ring within a day of flying anyway
    /// (docs/RIVAL_PRESSURE_AUDIT.md §4). Bounded by rule.
    public var marketMoves: [MarketMove]

    public init(airportRuntimes: [AirportCode: AirportRuntime] = [:],
                fuelPricePerTon: Money = Money(cents: 65_000),
                economicIndex: Double = 1.0,
                economicCycleTarget: Double = 1.0) {
        self.airportRuntimes = airportRuntimes
        self.fuelPricePerTon = fuelPricePerTon
        self.economicIndex = economicIndex
        self.economicCycleTarget = economicCycleTarget
        self.activeEvents = []
        self.nextEventID = 1
        self.eventCooldowns = [:]
        self.marketMoves = []
    }

    // MARK: Market moves

    public static let marketMoveCapacity = 64

    /// Records an entry into or exit from a city pair. Every airline's, so
    /// the ledger is a fact about the world and the player's view is a
    /// filter over it, not the other way round.
    public mutating func recordMarketMove(_ move: MarketMove) {
        marketMoves.append(move)
        if marketMoves.count > Self.marketMoveCapacity {
            marketMoves.removeFirst(marketMoves.count - Self.marketMoveCapacity)
        }
    }

    // MARK: Slots

    /// Daily aircraft-movement slots an airline holds at an airport.
    public func slotsHeld(by airline: AirlineID, at airport: AirportCode) -> Int {
        airportRuntimes[airport]?.slotAllocations[airline] ?? 0
    }

    public func slotsUsed(at airport: AirportCode) -> Int {
        airportRuntimes[airport]?.totalSlotsAllocated ?? 0
    }

    /// Attempts to allocate `count` additional daily slots against the
    /// airport's capacity. Rejection leaves state untouched.
    public mutating func allocateSlots(airline: AirlineID, airport: AirportCode,
                                       count: Int, capacityPerDay: Int) -> SlotError? {
        precondition(capacityPerDay > 0)
        guard count > 0 else { return .invalidCount(count) }
        let used = slotsUsed(at: airport)
        guard used + count <= capacityPerDay else {
            return .capacityExceeded(requested: count, available: capacityPerDay - used)
        }
        var runtime = airportRuntimes[airport] ?? AirportRuntime()
        runtime.slotAllocations[airline, default: 0] += count
        airportRuntimes[airport] = runtime
        return nil
    }

    /// Releases up to `count` slots held by the airline. Releasing more than
    /// held is a caller bug, not a player action — rejected, state untouched.
    public mutating func releaseSlots(airline: AirlineID, airport: AirportCode,
                                      count: Int) -> SlotError? {
        guard count > 0 else { return .invalidCount(count) }
        guard var runtime = airportRuntimes[airport],
              let held = runtime.slotAllocations[airline], held >= count else {
            return .releasingUnheldSlots(requested: count,
                                         held: slotsHeld(by: airline, at: airport))
        }
        if held == count {
            runtime.slotAllocations[airline] = nil
        } else {
            runtime.slotAllocations[airline] = held - count
        }
        // Drop empty runtimes so untouched airports don't accrete in saves.
        airportRuntimes[airport] = runtime.isEmpty ? nil : runtime
        return nil
    }

    /// Invariant sweep, folded into `GameState.integrityViolations()`.
    func integrityViolations() -> [String] {
        var violations: [String] = []
        for (code, runtime) in airportRuntimes {
            for (airline, slots) in runtime.slotAllocations where slots <= 0 {
                violations.append("Airport \(code): airline \(airline.raw) holds \(slots) slots")
            }
        }
        return violations
    }
}

public struct AirportRuntime: Equatable, Codable, Sendable {
    public var slotAllocations: [AirlineID: Int]

    public init(slotAllocations: [AirlineID: Int] = [:]) {
        self.slotAllocations = slotAllocations
    }

    public var totalSlotsAllocated: Int {
        slotAllocations.values.reduce(0, +)
    }

    var isEmpty: Bool {
        slotAllocations.isEmpty
    }
}

public enum SlotError: Equatable, Sendable {
    case invalidCount(Int)
    case capacityExceeded(requested: Int, available: Int)
    case releasingUnheldSlots(requested: Int, held: Int)
}

/// One airline entering or leaving one city pair.
public struct MarketMove: Equatable, Codable, Sendable {
    public enum Kind: String, Equatable, Codable, Sendable {
        case entered
        case left
    }

    public let at: SimTime
    public let airline: AirlineID
    public let origin: AirportCode
    public let destination: AirportCode
    public let kind: Kind

    public init(at: SimTime, airline: AirlineID, origin: AirportCode,
                destination: AirportCode, kind: Kind) {
        self.at = at
        self.airline = airline
        self.origin = origin
        self.destination = destination
        self.kind = kind
    }

    public var market: Route.Market { Route.market(origin, destination) }
}
