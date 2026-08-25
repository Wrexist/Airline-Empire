import Foundation
import Testing
@testable import AirlineEmpireCore

@Suite("Save format")
struct PersistenceTests {
    @Test func roundTripEquality() throws {
        let engine = SimulationEngine(state: Fixtures.newState(seed: 55), systems: [StochasticSystem()])
        engine.advance(ticks: Fixtures.ticksPerDay * 10)

        let codec = JSONSaveCodec()
        let data = try codec.encode(engine.state)
        let restored = try codec.decode(data)
        #expect(restored == engine.state)
    }

    @Test func savedGameContinuesIdentically() throws {
        // THE core persistence guarantee (docs/SIMULATION_ARCHITECTURE.md §6):
        // save mid-run, restore, continue -> byte-identical to uninterrupted.
        let uninterrupted = SimulationEngine(state: Fixtures.newState(seed: 2024),
                                             systems: [StochasticSystem()])
        uninterrupted.advance(ticks: Fixtures.ticksPerDay * 40)

        let firstHalf = SimulationEngine(state: Fixtures.newState(seed: 2024),
                                         systems: [StochasticSystem()])
        firstHalf.advance(ticks: Fixtures.ticksPerDay * 17)
        let saved = try JSONSaveCodec().encode(firstHalf.state)

        let resumed = SimulationEngine(state: try JSONSaveCodec().decode(saved),
                                       systems: [StochasticSystem()])
        resumed.advance(ticks: Fixtures.ticksPerDay * 23)

        #expect(try resumed.state.stateHash() == uninterrupted.state.stateHash())
        #expect(resumed.state == uninterrupted.state)
    }

    @Test func checksumDetectsCorruption() throws {
        let codec = JSONSaveCodec()
        let data = try codec.encode(Fixtures.newState())
        var envelope = try JSONDecoder().decode(SaveEnvelope.self, from: data)
        // Flip one payload byte.
        var payload = envelope.payload
        payload[payload.count / 2] ^= 0xFF
        envelope = SaveEnvelopeTamper.replacePayloadKeepChecksum(envelope, payload: payload)
        let tampered = try JSONEncoder().encode(envelope)
        #expect(throws: SaveError.checksumMismatch) {
            _ = try codec.decode(tampered)
        }
    }

    @Test func badMagicRejected() throws {
        let codec = JSONSaveCodec()
        let data = try codec.encode(Fixtures.newState())
        let string = String(data: data, encoding: .utf8)!
            .replacingOccurrences(of: "AESAVE", with: "NOTIT!")
        #expect(throws: SaveError.badMagic) {
            _ = try codec.decode(string.data(using: .utf8)!)
        }
    }

    @Test func futureVersionRejectedHonestly() throws {
        let codec = JSONSaveCodec()
        let data = try codec.encode(Fixtures.newState())
        let string = String(data: data, encoding: .utf8)!
            .replacingOccurrences(of: "\"formatVersion\":1", with: "\"formatVersion\":999")
        // Checksum still matches (payload untouched) so the version check is
        // what must fire.
        #expect(throws: SaveError.unsupportedVersion(999)) {
            _ = try codec.decode(string.data(using: .utf8)!)
        }
    }

    @Test func garbageInputFailsCleanly() {
        #expect(throws: SaveError.self) {
            _ = try JSONSaveCodec().decode(Data("not a save".utf8))
        }
    }

    @Test func deterministicEncoding() throws {
        // Sorted-keys JSON: same state -> same bytes -> stable stateHash.
        let state = Fixtures.newState(seed: 11)
        let a = try JSONSaveCodec().encode(state)
        let b = try JSONSaveCodec().encode(state)
        #expect(a == b)
        #expect(try state.stateHash() == state.stateHash())
    }

    @Test func repeatedSaveLoadCycles() throws {
        // Ten save/load cycles interleaved with simulation: no drift, no
        // accumulation, allocator/sequence counters preserved.
        var engine = SimulationEngine(state: Fixtures.newState(seed: 8), systems: [StochasticSystem()])
        let codec = JSONSaveCodec()
        for _ in 0..<10 {
            engine.advance(ticks: Fixtures.ticksPerDay)
            let data = try codec.encode(engine.state)
            engine = SimulationEngine(state: try codec.decode(data), systems: [StochasticSystem()])
        }
        let cycled = engine.state

        let straight = SimulationEngine(state: Fixtures.newState(seed: 8), systems: [StochasticSystem()])
        straight.advance(ticks: Fixtures.ticksPerDay * 10)
        #expect(cycled == straight.state)
    }
}

/// Rebuilds an envelope with a tampered payload but the ORIGINAL checksum,
/// simulating on-disk corruption after a valid write.
enum SaveEnvelopeTamper {
    static func replacePayloadKeepChecksum(_ envelope: SaveEnvelope, payload: Data) -> SaveEnvelope {
        // SaveEnvelope recomputes checksums in init, so round-trip through
        // JSON with a literal edit instead.
        let encoder = JSONEncoder()
        let data = try! encoder.encode(envelope)
        var object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["payload"] = payload.base64EncodedString()
        let tampered = try! JSONSerialization.data(withJSONObject: object)
        return try! JSONDecoder().decode(SaveEnvelope.self, from: tampered)
    }
}
