import Foundation

/// Versioned save format (docs/PERSISTENCE_ARCHITECTURE.md). Phase 3 ships
/// the codec + envelope so save-safe state transitions are testable from the
/// first kernel build; stores, slots, backups, and migrations land in
/// Phase 13 behind this same format.
public enum SaveFormat {
    public static let magic = "AESAVE"
    /// Bumps on ANY change to the encoded shape of `GameState` (D-004).
    /// History: v1 kernel-only (Phase 3); v2 added `world` (Phase 4);
    /// v3 added `airlines`/`aircraft`/`ledger` (Phase 5); v4 added
    /// `routes`/`flights` + Aircraft.activeFlight + world fuel price (Phase 6);
    /// v5 added route demand/load fields + world economicIndex (Phase 7);
    /// v6 added loans/status, finance statements, route economics, world
    /// cycle fields (Phase 8).
    /// Pre-release policy (docs/PERSISTENCE_ARCHITECTURE.md §5): superseded
    /// pre-release versions are refused, not migrated, until first TestFlight.
    public static let currentVersion = 6
}

public struct SaveEnvelope: Codable, Sendable {
    public let magic: String
    public let formatVersion: Int
    public let contentVersion: String
    public let savedAtTick: Int64
    public let checksum: UInt64
    public let payload: Data

    init(formatVersion: Int, contentVersion: String, savedAtTick: Int64, payload: Data) {
        self.magic = SaveFormat.magic
        self.formatVersion = formatVersion
        self.contentVersion = contentVersion
        self.savedAtTick = savedAtTick
        self.checksum = StableHash.fnv1a(payload)
        self.payload = payload
    }
}

public enum SaveError: Error, Equatable, Sendable {
    case badMagic
    case checksumMismatch
    case unsupportedVersion(Int)
    case corruptPayload(String)
}

/// JSON codec with deterministic output (sorted keys) — same bytes for the
/// same state, which the state-hash determinism tests rely on.
public struct JSONSaveCodec: Sendable {
    public init() {}

    public func encode(_ state: GameState, contentVersion: String = "0") throws -> Data {
        let payloadEncoder = JSONEncoder()
        payloadEncoder.outputFormatting = [.sortedKeys]
        let payload = try payloadEncoder.encode(state)
        let envelope = SaveEnvelope(
            formatVersion: SaveFormat.currentVersion,
            contentVersion: contentVersion,
            savedAtTick: state.clock.tickCount,
            payload: payload)
        let envelopeEncoder = JSONEncoder()
        envelopeEncoder.outputFormatting = [.sortedKeys]
        return try envelopeEncoder.encode(envelope)
    }

    public func decode(_ data: Data) throws -> GameState {
        let envelope: SaveEnvelope
        do {
            envelope = try JSONDecoder().decode(SaveEnvelope.self, from: data)
        } catch {
            throw SaveError.corruptPayload("Envelope undecodable: \(error)")
        }
        guard envelope.magic == SaveFormat.magic else { throw SaveError.badMagic }
        guard envelope.checksum == StableHash.fnv1a(envelope.payload) else {
            throw SaveError.checksumMismatch
        }
        guard envelope.formatVersion == SaveFormat.currentVersion else {
            // The migration chain (Phase 13) hooks in here; until a second
            // version exists, older versions are honestly unsupported.
            throw SaveError.unsupportedVersion(envelope.formatVersion)
        }
        do {
            return try JSONDecoder().decode(GameState.self, from: envelope.payload)
        } catch {
            throw SaveError.corruptPayload("State undecodable: \(error)")
        }
    }
}

extension GameState {
    /// Stable content hash of the full state — the determinism oracle used
    /// by dual-run and save/restore tests.
    public func stateHash() throws -> UInt64 {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return StableHash.fnv1a(try encoder.encode(self))
    }
}
