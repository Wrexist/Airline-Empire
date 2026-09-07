import Foundation
import Testing
@testable import AirlineEmpireCore

@Suite("Launch readiness")
struct LaunchReadinessTests {
    @Test func checksummedSaveWithInvalidClockIsRejected() throws {
        let codec = JSONSaveCodec()
        let data = try codec.encode(Fixtures.newState())
        var envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let base64 = try #require(envelope["payload"] as? String)
        var payload = try #require(JSONSerialization.jsonObject(with: #require(Data(base64Encoded: base64))) as? [String: Any])
        var meta = try #require(payload["meta"] as? [String: Any])
        meta["tickMinutes"] = 0
        payload["meta"] = meta
        let bytes = try JSONSerialization.data(withJSONObject: payload)
        envelope["payload"] = bytes.base64EncodedString()
        envelope["checksum"] = NSNumber(value: StableHash.fnv1a(bytes))
        let damaged = try JSONSerialization.data(withJSONObject: envelope)
        #expect(throws: (any Error).self) { _ = try codec.decode(damaged) }
    }

    @Test func separateCampaignAutosavesNeverOverwriteLegacyOrEachOther() async throws {
        let root = SaveStoreTests.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        let legacy = Fixtures.newState(seed: 1)
        try manager.save(legacy, slot: "auto")
        for (slot, seed) in [("alpha", UInt64(2)), ("beta", UInt64(3))] {
            let session = GameSession(state: Fixtures.newState(seed: seed), systems: [])
            await session.attachSaveManager(manager, autosaveSlot: slot, autosaveEveryGameDays: 1)
            await session.advance(ticks: Fixtures.ticksPerDay * 3)
            let snapshot = await session.snapshot
            #expect(try manager.load(slot: slot).state == snapshot)
        }
        #expect(try manager.load(slot: "auto").state == legacy)
        #expect(manager.store.slots() == ["alpha", "auto", "beta"])
        let alpha = try manager.load(slot: "alpha").state
        let beta = try manager.load(slot: "beta").state
        #expect(alpha != beta)
    }

    @Test func rotationFailureReportsErrorAndPreservesCurrentSave() throws {
        let root = SaveStoreTests.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        let original = Fixtures.newState(seed: 4)
        try manager.save(original, slot: "one")
        let blocked = manager.store.slotDirectory("one").appendingPathComponent("backup-1.aesave")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try Data("block rotation".utf8).write(to: blocked.appendingPathComponent("child"))
        try Data("older generation".utf8).write(to: manager.store.slotDirectory("one")
            .appendingPathComponent("backup-2.aesave"))
        #expect(throws: (any Error).self) {
            try manager.save(Fixtures.newState(seed: 5), slot: "one")
        }
        #expect(try manager.load(slot: "one").state == original)
    }

    @Test func futureSaveNeverFallsBackAndOverwritesNewerProgress() throws {
        let root = SaveStoreTests.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        let state = Fixtures.newState()
        try manager.save(state, slot: "one")
        try manager.save(state, slot: "one")
        let current = manager.store.slotDirectory("one").appendingPathComponent(FileSaveStore.currentName)
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: current)) as? [String: Any])
        envelope["formatVersion"] = SaveFormat.currentVersion + 1
        try JSONSerialization.data(withJSONObject: envelope).write(to: current)
        #expect(throws: SaveError.unsupportedVersion(SaveFormat.currentVersion + 1)) {
            _ = try manager.load(slot: "one")
        }
    }

    @Test func lapsedLateGameKeepsFlyingButCannotBuyPaidClasses() throws {
        let (original, player, _) = try DemandFixtures.market(fare: .dollars(129))
        var state = original.state
        state.progression.era = .international
        let engine = SimulationEngine(state: state, systems: GamePipeline.standard(), catalog: original.catalog)
        engine.progressionCeiling = .regional
        let before = state.progression.counters.flightsCompleted
        engine.advance(ticks: Fixtures.ticksPerDay * 3)
        #expect(engine.state.progression.counters.flightsCompleted > before)
        #expect(engine.state.progression.era == .international)
        let beforeRejected = engine.state
        let result = engine.applyNow(BuyUsedAircraftCommand(buyer: player, type: "MR300", ageYears: 8))
        guard case .rejected(let rejection) = result else { Issue.record("Paid acquisition allowed"); return }
        #expect(rejection.code == "access.proRequired")
        #expect(engine.state == beforeRejected)
    }

    @Test func everyTimeControlRespectsExpansionCeiling() async throws {
        let (original, _, _) = try DemandFixtures.market(fare: .dollars(129))
        let session = GameSession(state: original.state, systems: GamePipeline.standard(), catalog: original.catalog)
        await session.setProgressionCeiling(.startup)
        await session.setSpeed(.x16)
        _ = await session.pump(elapsedSeconds: 60)
        await session.advanceToNextMorning()
        await session.advance(ticks: Fixtures.ticksPerDay * 4)
        let state = await session.snapshot
        #expect(state.clock.tickCount > Fixtures.ticksPerDay * 4)
        #expect(state.progression.era == .startup)
        #expect(state.progression.counters.flightsCompleted > 0)
    }

    @Test func gracePeriodHasAnExactEndAndMissingSubscriptionExpiryIsNotLifetime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let grace = ProEntitlement(grantedBy: .weekly, expiresAt: now.addingTimeInterval(-60),
            isInBillingRetry: true, gracePeriodExpiresAt: now.addingTimeInterval(60))
        #expect(grace.isPro(asOf: now))
        #expect(!grace.isPro(asOf: now.addingTimeInterval(60)))
        #expect(!ProEntitlement(grantedBy: .weekly).isPro(asOf: now))
        #expect(!ContentAccess.free.allowsAircraftCategory(.widebody, in: .international))
    }
}
