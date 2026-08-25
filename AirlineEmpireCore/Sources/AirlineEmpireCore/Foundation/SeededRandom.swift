/// Deterministic randomness for the simulation.
///
/// `RNGState` lives inside `GameState` and serializes with saves, so a
/// restored game continues with the exact draw sequence of an uninterrupted
/// one. Streams are independent substreams keyed by label: each system draws
/// only from its own labels, so adding a system never perturbs another's
/// sequence (docs/SIMULATION_ARCHITECTURE.md §2).
///
/// Generator: SplitMix64 — tiny state, excellent statistical quality for
/// game purposes, trivially serializable.
public struct RNGState: Hashable, Codable, Sendable {
    public let worldSeed: UInt64
    /// Current SplitMix64 state per stream label. Absent label = not yet
    /// drawn; the initial state derives from (worldSeed, label).
    public private(set) var streams: [String: UInt64]

    public init(worldSeed: UInt64) {
        self.worldSeed = worldSeed
        self.streams = [:]
    }

    /// Next raw 64-bit value from the named stream.
    public mutating func next(_ stream: String) -> UInt64 {
        var state = streams[stream] ?? StableHash.combine(worldSeed, stream)
        state &+= 0x9E37_79B9_7F4A_7C15
        streams[stream] = state
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform Double in [0, 1).
    public mutating func unitDouble(_ stream: String) -> Double {
        // 53 high bits -> the canonical [0,1) construction.
        Double(next(stream) >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Uniform Int in a closed range.
    public mutating func int(_ stream: String, in range: ClosedRange<Int>) -> Int {
        precondition(range.lowerBound <= range.upperBound)
        let span = UInt64(range.upperBound - range.lowerBound) &+ 1
        // Rejection-free modulo bias is negligible for span << 2^64, but be
        // exact anyway: multiply-shift range reduction (Lemire).
        let value = next(stream).multipliedFullWidth(by: span).high
        return range.lowerBound + Int(value)
    }

    /// Bernoulli draw.
    public mutating func chance(_ stream: String, probability: Double) -> Bool {
        precondition(probability >= 0 && probability <= 1, "Probability out of range")
        return unitDouble(stream) < probability
    }
}
