/// FNV-1a 64-bit: the project's stable hash for anything persisted or
/// deterministic (RNG substream derivation, save checksums, state hashes).
/// Swift's `Hashable.hashValue` is process-seeded and is banned for these
/// uses (docs/TECHNICAL_STANDARDS.md §3).
public enum StableHash {
    public static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    public static let prime: UInt64 = 0x0000_0100_0000_01b3

    public static func fnv1a(_ bytes: some Sequence<UInt8>, seed: UInt64 = offsetBasis) -> UInt64 {
        var hash = seed
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }

    public static func fnv1a(_ string: String, seed: UInt64 = offsetBasis) -> UInt64 {
        fnv1a(string.utf8, seed: seed)
    }

    /// Combines a numeric seed with a label into a substream seed.
    ///
    /// Always starts from the offset basis: seeding FNV with the seed value
    /// itself degenerates (seed ^ own-low-byte collapses small seeds to the
    /// same hash), which the RNG tests caught in Phase 3.
    public static func combine(_ seed: UInt64, _ label: String) -> UInt64 {
        var hash = offsetBasis
        withUnsafeBytes(of: seed.littleEndian) { raw in
            hash = fnv1a(raw, seed: hash)
        }
        return fnv1a(label.utf8, seed: hash)
    }
}
