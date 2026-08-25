import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Crash-safe file persistence (docs/PERSISTENCE_ARCHITECTURE.md §2–§4):
/// per-slot directories holding `current.aesave` plus two rolled backups
/// and a cosmetic `meta.json` for the load screen. The write protocol is
/// tmp → fsync → rotate → atomic rename, so a kill at any step leaves at
/// least one intact prior save.
public final class FileSaveStore: Sendable {
    public static let currentName = "current.aesave"
    public static let backupNames = ["backup-1.aesave", "backup-2.aesave"]
    public static let metaName = "meta.json"

    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func slotDirectory(_ slot: String) -> URL {
        rootDirectory.appendingPathComponent("slot-\(slot)", isDirectory: true)
    }

    /// Atomic save with backup rotation.
    public func save(_ data: Data, slot: String, meta: SlotMeta) throws {
        let fm = FileManager.default
        let directory = slotDirectory(slot)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        // 1. Write + fsync the temp file.
        let tmp = directory.appendingPathComponent("current.aesave.tmp")
        try data.write(to: tmp)
        if let handle = try? FileHandle(forWritingTo: tmp) {
            try? handle.synchronize()
            try? handle.close()
        }

        // 2. Rotate: backup-1 -> backup-2, current -> backup-1 (renames are
        //    atomic on APFS/ext4; missing sources are fine).
        let current = directory.appendingPathComponent(Self.currentName)
        let backup1 = directory.appendingPathComponent(Self.backupNames[0])
        let backup2 = directory.appendingPathComponent(Self.backupNames[1])
        _ = rename(backup1.path, backup2.path)
        _ = rename(current.path, backup1.path)

        // 3. Atomic promote.
        guard rename(tmp.path, current.path) == 0 else {
            throw SaveError.corruptPayload("Atomic rename failed for \(current.path)")
        }

        // 4. Cosmetic metadata last (derivable; corruption harmless).
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try? (try encoder.encode(meta)).write(to: directory.appendingPathComponent(Self.metaName))
    }

    /// Save file candidates, newest first: current, then backups.
    public func candidates(slot: String) -> [(generation: Int, url: URL)] {
        let directory = slotDirectory(slot)
        var result: [(Int, URL)] = [(0, directory.appendingPathComponent(Self.currentName))]
        for (index, name) in Self.backupNames.enumerated() {
            result.append((index + 1, directory.appendingPathComponent(name)))
        }
        return result.filter { FileManager.default.fileExists(atPath: $0.1.path) }
    }

    public func meta(slot: String) -> SlotMeta? {
        let url = slotDirectory(slot).appendingPathComponent(Self.metaName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SlotMeta.self, from: data)
    }

    /// Slots present on disk (directory names `slot-<name>`), sorted.
    public func slots() -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: rootDirectory.path)
        else { return [] }
        return entries.compactMap { name in
            name.hasPrefix("slot-") ? String(name.dropFirst(5)) : nil
        }.sorted()
    }

    public func deleteSlot(_ slot: String) throws {
        try FileManager.default.removeItem(at: slotDirectory(slot))
    }
}

/// Load-screen metadata; cosmetic and derivable from the save itself.
public struct SlotMeta: Equatable, Codable, Sendable {
    public let airlineName: String
    public let gameDateDescription: String
    public let netWorthCents: Int64
    public let savedAtTick: Int64
    public let era: String

    public init(airlineName: String, gameDateDescription: String,
                netWorthCents: Int64, savedAtTick: Int64, era: String) {
        self.airlineName = airlineName
        self.gameDateDescription = gameDateDescription
        self.netWorthCents = netWorthCents
        self.savedAtTick = savedAtTick
        self.era = era
    }
}

/// The result of a slot load: which generation actually loaded, so the UI
/// can be honest about recovered backups (docs/PERSISTENCE_ARCHITECTURE §6).
public struct LoadResult {
    public let state: GameState
    /// 0 = current save; 1/2 = recovered from that backup generation.
    public let generation: Int
}

/// Orchestrates codec + store + migrations (docs/PERSISTENCE_ARCHITECTURE).
public final class SaveManager: Sendable {
    public let store: FileSaveStore
    public let codec: JSONSaveCodec

    public init(store: FileSaveStore, codec: JSONSaveCodec = JSONSaveCodec()) {
        self.store = store
        self.codec = codec
    }

    public func save(_ state: GameState, slot: String) throws {
        let data = try codec.encode(state)
        try store.save(data, slot: slot, meta: Self.meta(for: state))
    }

    /// Tries current, then backups; the first intact generation wins.
    public func load(slot: String) throws -> LoadResult {
        var lastError: Error = SaveError.corruptPayload("No save files in slot \(slot)")
        for (generation, url) in store.candidates(slot: slot) {
            do {
                let data = try Data(contentsOf: url)
                let state = try codec.decode(data)
                return LoadResult(state: state, generation: generation)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func meta(for state: GameState) -> SlotMeta {
        let date = state.currentDate
        let player = state.playerAirline
        let netWorth = player.map { airline in
            CreditMath.assets(of: airline.id, state: state)
                - CreditMath.totalDebt(of: airline)
        } ?? .zero
        return SlotMeta(
            airlineName: player?.name ?? "—",
            gameDateDescription: String(format: "%04d-%02d-%02d", date.year, date.month, date.day),
            netWorthCents: netWorth.cents,
            savedAtTick: state.clock.tickCount,
            era: "\(state.progression.era)")
    }
}
