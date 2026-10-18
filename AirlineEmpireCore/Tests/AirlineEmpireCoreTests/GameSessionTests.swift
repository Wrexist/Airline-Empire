import Foundation
import Testing
@testable import AirlineEmpireCore

@Suite("Game session")
struct GameSessionTests {
    @Test func pausedPumpRunsNothing() async {
        let session = GameSession(state: Fixtures.newState(), systems: [])
        let ticks = await session.pump(elapsedSeconds: 100)
        #expect(ticks == 0)
        #expect(await session.snapshot.clock.tickCount == 0)
    }

    @Test func speedControlsTickRate() async {
        let session = GameSession(state: Fixtures.newState(), systems: [])
        await session.setSpeed(.x1)
        // At 1x: 4 game-min/real-s -> one 15-min tick per 3.75s.
        #expect(await session.pump(elapsedSeconds: 3.0) == 0)   // 12 game-min pending
        #expect(await session.pump(elapsedSeconds: 0.75) == 1)  // reaches 15
        #expect(await session.snapshot.clock.now.rawMinutes == 15)

        await session.setSpeed(.x16)
        // 64 game-min/s -> 7.5s = 480 game-min = 32 ticks.
        #expect(await session.pump(elapsedSeconds: 7.5) == 32)
        #expect(await session.snapshot.clock.now.rawMinutes == 15 + 480)
    }

    @Test func fractionAccumulatesAcrossPumps() async {
        let session = GameSession(state: Fixtures.newState(), systems: [])
        await session.setSpeed(.x4) // 16 game-min/s
        var total = 0
        for _ in 0..<10 { total += await session.pump(elapsedSeconds: 0.4) } // 4s -> 64 min
        #expect(total == 4)
        #expect(await session.snapshot.clock.now.rawMinutes == 60) // 4 min still pending
    }

    /// The fraction is the presentation clock's second hand (BUG-058): the
    /// map reads `clock.now + pendingGameMinutes` as continuous game time, so
    /// dropping it on pause would move every aircraft backwards at the
    /// instant the player pressed pause.
    @Test func pauseKeepsPendingFraction() async {
        let session = GameSession(state: Fixtures.newState(), systems: [])
        await session.setSpeed(.x1)
        _ = await session.pump(elapsedSeconds: 3.0) // 12 game-min pending, no tick
        #expect(await session.pendingGameMinutes == 12)
        await session.setSpeed(.paused)
        #expect(await session.pendingGameMinutes == 12) // the world stops where it is
        _ = await session.pump(elapsedSeconds: 10)      // paused: nothing accumulates
        #expect(await session.pendingGameMinutes == 12)
        await session.setSpeed(.x1)
        // Resume completes the tick the pause interrupted rather than
        // restarting it: 12 pending + 3 more minutes reaches 15.
        #expect(await session.pump(elapsedSeconds: 0.75) == 1)
    }

    @Test func submitWhilePausedAppliesImmediately() async {
        let session = GameSession(state: Fixtures.newState(), systems: [])
        let result = await session.submit(
            ScheduleWakeCommand(label: "note", at: SimTime(rawMinutes: 60)))
        #expect(result == .applied)
        #expect(await session.snapshot.schedule.entries.count == 1)
    }

    /// A running game applies a command at once too. It used to queue it for
    /// the next tick boundary and return nil, so the screen kept showing the
    /// world without it (a second tap bought a second aircraft) and a pause
    /// or save in that window never saw it (audit 2026-10-18 §2.4).
    @Test func submitWhileRunningAppliesImmediately() async {
        let session = GameSession(state: Fixtures.newState(), systems: [])
        await session.setSpeed(.x1)
        let result = await session.submit(
            ScheduleWakeCommand(label: "note", at: SimTime(rawMinutes: 60)))
        #expect(result == .applied)
        #expect(await session.snapshot.schedule.entries.count == 1)
        await session.advance(ticks: 1)
        #expect(await session.snapshot.schedule.entries.count == 1)
    }

    /// The exact window the queue lost: a purchase made mid-tick while
    /// running, then pause and an immediate save. The purchase is in the
    /// snapshot straight away and in the save.
    @Test func commandSubmittedWhileRunningSurvivesPauseAndSave() async throws {
        let root = SaveStoreTests.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: 9),
                                  systems: GamePipeline.standard(), catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Queue Air", kind: .player, homeAirport: "ARN",
            startingCash: Money.dollars(120_000_000)))
        let player = try #require(await session.snapshot.playerAirline).id
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        await session.attachSaveManager(manager, autosaveSlot: "auto")

        await session.setSpeed(.x1)
        _ = await session.pump(elapsedSeconds: 1) // 4 game-min pending: mid-tick
        let ticksBefore = await session.snapshot.clock.tickCount
        let result = await session.submit(BuyUsedAircraftCommand(
            buyer: player, type: "MR180", ageYears: 8))
        #expect(result == .applied)
        #expect(await session.snapshot.fleet(of: player).count == 1)
        #expect(await session.snapshot.clock.tickCount == ticksBefore)

        await session.setSpeed(.paused)
        try await session.saveNow(slot: "manual")
        let saved = try manager.load(slot: "manual").state
        let snapshot = await session.snapshot
        #expect(saved.fleet(of: player).count == 1)
        #expect(saved == snapshot)
    }

    @Test func advanceToNextMorningLandsAtMidnight() async {
        let session = GameSession(state: Fixtures.newState(), systems: [])
        await session.advance(ticks: 10) // 150 min into day 0
        await session.advanceToNextMorning()
        let now = await session.snapshot.clock.now
        #expect(now.rawMinutes == GameCalendar.minutesPerDay)
        // From exactly midnight, next morning is the NEXT midnight.
        await session.advanceToNextMorning()
        #expect(await session.snapshot.clock.now.rawMinutes == 2 * GameCalendar.minutesPerDay)
    }

    @Test func snapshotStreamDeliversInitialState() async {
        let session = GameSession(state: Fixtures.newState(), systems: [])
        let stream = await session.snapshots()
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.clock.tickCount == 0)
    }

    @Test func eventStreamDeliversSimEvents() async {
        let session = GameSession(state: Fixtures.newState(), systems: [])
        let stream = await session.events()
        await session.advance(ticks: Fixtures.ticksPerDay) // crosses one day boundary
        var received: [SimEvent] = []
        for await event in stream {
            received.append(event)
            if case .dayStarted = event.kind { break }
        }
        #expect(received.contains { if case .dayStarted = $0.kind { true } else { false } })
    }
}
