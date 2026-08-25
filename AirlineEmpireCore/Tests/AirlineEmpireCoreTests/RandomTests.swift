import Foundation
import Testing
@testable import AirlineEmpireCore

@Suite("Deterministic randomness")
struct RandomTests {
    @Test func sameSeedSameSequence() {
        var a = RNGState(worldSeed: 7)
        var b = RNGState(worldSeed: 7)
        for _ in 0..<100 {
            #expect(a.next("s") == b.next("s"))
        }
    }

    @Test func differentSeedsDiffer() {
        var a = RNGState(worldSeed: 7)
        var b = RNGState(worldSeed: 8)
        let av = (0..<10).map { _ in a.next("s") }
        let bv = (0..<10).map { _ in b.next("s") }
        #expect(av != bv)
    }

    @Test func substreamIndependence() {
        // Stream "a" produces the same sequence whether or not "b" is drawn
        // between draws — the core guarantee that lets systems be added
        // without perturbing others (docs/SIMULATION_ARCHITECTURE.md §2).
        var pure = RNGState(worldSeed: 99)
        let expected = (0..<50).map { _ in pure.next("a") }

        var interleaved = RNGState(worldSeed: 99)
        var actual: [UInt64] = []
        for i in 0..<50 {
            if i % 3 == 0 { _ = interleaved.next("b") }
            actual.append(interleaved.next("a"))
            if i % 2 == 0 { _ = interleaved.next("c.other") }
        }
        #expect(actual == expected)
    }

    @Test func serializationResumesSequence() throws {
        var original = RNGState(worldSeed: 1234)
        _ = (0..<25).map { _ in original.next("x") }
        _ = (0..<5).map { _ in original.next("y") }

        let data = try JSONEncoder().encode(original)
        var restored = try JSONDecoder().decode(RNGState.self, from: data)

        for _ in 0..<25 {
            #expect(original.next("x") == restored.next("x"))
            #expect(original.next("y") == restored.next("y"))
            #expect(original.next("z.fresh") == restored.next("z.fresh"))
        }
    }

    @Test func unitDoubleInRange() {
        var rng = RNGState(worldSeed: 5)
        var sum = 0.0
        for _ in 0..<2000 {
            let v = rng.unitDouble("u")
            #expect(v >= 0 && v < 1)
            sum += v
        }
        // Loose sanity: mean of 2000 uniforms is near 0.5.
        #expect(abs(sum / 2000 - 0.5) < 0.05)
    }

    @Test func intInRangeCoversBounds() {
        var rng = RNGState(worldSeed: 6)
        var seen = Set<Int>()
        for _ in 0..<1000 {
            let v = rng.int("i", in: 1...6)
            #expect((1...6).contains(v))
            seen.insert(v)
        }
        #expect(seen == Set(1...6))
    }

    @Test func chanceExtremes() {
        var rng = RNGState(worldSeed: 7)
        for _ in 0..<100 {
            let never = rng.chance("c", probability: 0)
            let always = rng.chance("c", probability: 1)
            #expect(!never)
            #expect(always)
        }
    }

    @Test func stableHashIsStable() {
        // Pinned values: if these change, every save checksum and RNG
        // substream in existence breaks — the test is the tripwire.
        #expect(StableHash.fnv1a("") == 0xcbf2_9ce4_8422_2325)
        #expect(StableHash.fnv1a("a") == 0xaf63_dc4c_8601_ec8c)
        let derived = StableHash.combine(42, "demand.leisure")
        #expect(derived == StableHash.combine(42, "demand.leisure"))
        #expect(derived != StableHash.combine(43, "demand.leisure"))
        #expect(derived != StableHash.combine(42, "demand.business"))
    }
}
