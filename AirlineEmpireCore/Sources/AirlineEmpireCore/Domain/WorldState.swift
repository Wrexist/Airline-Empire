/// Mutable world-layer state (docs/DOMAIN_MODEL.md §2 runtime slice).
/// Only what changes at runtime lives here; static airport data stays in
/// `ContentCatalog`. Entries are created lazily on first use so saves stay
/// proportional to the world the player actually touches.
public struct WorldState: Equatable, Codable, Sendable {
    public var airportRuntimes: [AirportCode: AirportRuntime]
    /// Jet fuel spot price. Initialized from tuning; market dynamics move it
    /// from Phase 8/11.
    public var fuelPricePerKg: Money
    /// Macro-economy index (1.0 = neutral). Business demand reacts more
    /// strongly than leisure; the cycle driver arrives in Phase 8/11.
    public var economicIndex: Double

    public init(airportRuntimes: [AirportCode: AirportRuntime] = [:],
                fuelPricePerKg: Money = Money(cents: 65),
                economicIndex: Double = 1.0) {
        self.airportRuntimes = airportRuntimes
        self.fuelPricePerKg = fuelPricePerKg
        self.economicIndex = economicIndex
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
