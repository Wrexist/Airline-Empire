import Foundation
import Testing
@testable import AirlineEmpireCore

@Suite("Save store & manager")
struct SaveStoreTests {
    /// Per-test scratch directory (parallel-safe).
    static func scratch() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ae-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func populatedState() throws -> (GameState, ContentCatalog) {
        let (engine, _, _) = try DemandFixtures.market(fare: Money.dollars(129))
        engine.advance(ticks: Fixtures.ticksPerDay * 20)
        return (engine.state, engine.catalog)
    }

    @Test func saveLoadRoundTripOnDisk() throws {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        let (state, _) = try Self.populatedState()

        try manager.save(state, slot: "1")
        let loaded = try manager.load(slot: "1")
        #expect(loaded.generation == 0)
        #expect(loaded.state == state)
        // Meta was written and is sane.
        let meta = try #require(manager.store.meta(slot: "1"))
        #expect(meta.airlineName == "Anchor Air")
        #expect(meta.savedAtTick == state.clock.tickCount)
        #expect(manager.store.slots() == ["1"])
    }

    @Test func rotationKeepsTwoBackups() throws {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        var (state, catalog) = try Self.populatedState()

        try manager.save(state, slot: "1") // gen A
        let engine = SimulationEngine(state: state, systems: GamePipeline.standard(),
                                      catalog: catalog)
        engine.advance(ticks: Fixtures.ticksPerDay * 3)
        state = engine.state
        try manager.save(state, slot: "1") // gen B
        engine.advance(ticks: Fixtures.ticksPerDay * 3)
        try manager.save(engine.state, slot: "1") // gen C

        let files = manager.store.candidates(slot: "1")
        #expect(files.count == 3)
        // Newest is current; backups hold the two prior generations.
        let current = try manager.load(slot: "1")
        #expect(current.state == engine.state)
    }

    @Test func corruptedCurrentFallsBackToBackup() throws {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        let (stateA, catalog) = try Self.populatedState()
        try manager.save(stateA, slot: "1")
        let engine = SimulationEngine(state: stateA, systems: GamePipeline.standard(),
                                      catalog: catalog)
        engine.advance(ticks: Fixtures.ticksPerDay * 2)
        try manager.save(engine.state, slot: "1")

        // Corrupt the current file (simulated disk damage after valid write).
        let current = manager.store.slotDirectory("1")
            .appendingPathComponent(FileSaveStore.currentName)
        var bytes = try Data(contentsOf: current)
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: current)

        let loaded = try manager.load(slot: "1")
        #expect(loaded.generation == 1)
        #expect(loaded.state == stateA)

        // Corrupt the backup too: nothing left -> honest failure.
        let backup = manager.store.slotDirectory("1")
            .appendingPathComponent(FileSaveStore.backupNames[0])
        try Data("garbage".utf8).write(to: backup)
        #expect(throws: (any Error).self) {
            _ = try manager.load(slot: "1")
        }
    }

    @Test func strayTmpFileDoesNotBreakSaves() throws {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        let (state, _) = try Self.populatedState()
        // Simulate a crash mid-write: stale tmp garbage in the slot dir.
        let directory = manager.store.slotDirectory("1")
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        try Data("half-written".utf8)
            .write(to: directory.appendingPathComponent("current.aesave.tmp"))

        try manager.save(state, slot: "1")
        let loaded = try manager.load(slot: "1")
        #expect(loaded.generation == 0)
        #expect(loaded.state == state)
    }

    @Test func repeatedSaveLoadCyclesOnDiskStayIdentical() throws {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        let catalog = try ContentCatalog.loadBundled()
        var engine = SimulationEngine(state: Fixtures.newState(seed: 12),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(airlineName: "Cycler", kind: .player,
                                                homeAirport: "STV",
                                                startingCash: Money.dollars(90_000_000)))
        for _ in 0..<10 {
            engine.advance(ticks: Fixtures.ticksPerDay)
            try manager.save(engine.state, slot: "cycle")
            engine = SimulationEngine(state: try manager.load(slot: "cycle").state,
                                      systems: GamePipeline.standard(), catalog: catalog)
        }
        let straight = SimulationEngine(state: Fixtures.newState(seed: 12),
                                        systems: GamePipeline.standard(), catalog: catalog)
        _ = straight.applyNow(FoundAirlineCommand(airlineName: "Cycler", kind: .player,
                                                  homeAirport: "STV",
                                                  startingCash: Money.dollars(90_000_000)))
        straight.advance(ticks: Fixtures.ticksPerDay * 10)
        #expect(engine.state == straight.state)
    }
}

@Suite("Migrations")
struct MigrationTests {
    /// Builds a synthetic v9 save: today's payload with the progression
    /// slice stripped and the envelope version set to 9 (checksum intact).
    static func v9Fixture(from state: GameState) throws -> Data {
        let codec = JSONSaveCodec()
        let data = try codec.encode(state)
        var envelopeTree = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let payloadB64 = envelopeTree["payload"] as! String
        var payloadTree = try JSONSerialization.jsonObject(
            with: Data(base64Encoded: payloadB64)!) as! [String: Any]
        payloadTree.removeValue(forKey: "progression")
        let newPayload = try JSONSerialization.data(withJSONObject: payloadTree)
        envelopeTree["payload"] = newPayload.base64EncodedString()
        envelopeTree["formatVersion"] = 9
        envelopeTree["checksum"] = NSNumber(value: StableHash.fnv1a(newPayload))
        return try JSONSerialization.data(withJSONObject: envelopeTree)
    }

    @Test func v9SaveMigratesAndRuns() throws {
        let (engine, _, _) = try DemandFixtures.market(fare: Money.dollars(129))
        engine.advance(ticks: Fixtures.ticksPerDay * 10)
        let v9 = try Self.v9Fixture(from: engine.state)

        let migrated = try JSONSaveCodec().decode(v9)
        // The migrated world matches except for a fresh progression slice.
        #expect(migrated.progression == ProgressionState())
        #expect(migrated.airlines == engine.state.airlines)
        #expect(migrated.clock == engine.state.clock)

        // And it RUNS: continue a migrated world without violations.
        let resumed = SimulationEngine(state: migrated,
                                       systems: GamePipeline.standard(),
                                       catalog: engine.catalog)
        resumed.advance(ticks: Fixtures.ticksPerDay * 20)
        #expect(resumed.state.integrityViolations().isEmpty)
        #expect(resumed.state.progression.counters.flightsCompleted > 0)
    }

    @Test func preChainVersionsRefuseHonestly() throws {
        let (engine, _, _) = try DemandFixtures.market(fare: Money.dollars(129))
        let codec = JSONSaveCodec()
        let data = try codec.encode(engine.state)
        let v8 = String(data: data, encoding: .utf8)!
            .replacingOccurrences(of: "\"formatVersion\":\(SaveFormat.currentVersion)",
                                  with: "\"formatVersion\":8")
        #expect(throws: SaveError.unsupportedVersion(8)) {
            _ = try codec.decode(v8.data(using: .utf8)!)
        }
        #expect(MigrationChain.standard.minimumSupportedVersion == 9)
    }

    @Test func chainContiguityComputed() {
        struct Fake: SaveMigration {
            let fromVersion: Int
            func migrate(_ payload: inout [String: Any]) throws {}
        }
        // Gap: only from currentVersion-3 registered -> minimum stays current-0.
        let gappy = MigrationChain([Fake(fromVersion: SaveFormat.currentVersion - 3)])
        #expect(gappy.minimumSupportedVersion == SaveFormat.currentVersion)
        let contiguous = MigrationChain([
            Fake(fromVersion: SaveFormat.currentVersion - 1),
            Fake(fromVersion: SaveFormat.currentVersion - 2),
        ])
        #expect(contiguous.minimumSupportedVersion == SaveFormat.currentVersion - 2)
    }
}

@Suite("Session autosave")
struct SessionAutosaveTests {
    @Test func autosaveWritesDuringFastForward() async throws {
        let root = SaveStoreTests.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try ContentCatalog.loadBundled()
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        let session = GameSession(state: Fixtures.newState(),
                                  systems: GamePipeline.standard(), catalog: catalog)
        await session.attachSaveManager(manager, autosaveSlot: "auto",
                                        autosaveEveryGameDays: 5)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "AutoSaver", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(50_000_000)))
        await session.advance(ticks: Fixtures.ticksPerDay * 12)

        let loaded = try manager.load(slot: "auto")
        #expect(loaded.state.airlines.values.contains { $0.name == "AutoSaver" })
        // Autosave lags at most the autosave window.
        let nowDay = await session.snapshot.clock.now.dayIndex
        let behindDays = nowDay - loaded.state.clock.now.dayIndex
        #expect(behindDays <= 5)
        let saveError = await session.lastSaveError
        #expect(saveError == nil)

        // Explicit save captures the exact snapshot.
        try await session.saveNow(slot: "manual")
        let manual = try manager.load(slot: "manual")
        let snapshot = await session.snapshot
        #expect(manual.state == snapshot)
    }
}
