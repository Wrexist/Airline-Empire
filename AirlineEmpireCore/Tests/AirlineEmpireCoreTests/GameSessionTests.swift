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

    @Test func pauseDropsPendingFraction() async {
        let session = GameSession(state: Fixtures.newState(), systems: [])
        await session.setSpeed(.x1)
        _ = await session.pump(elapsedSeconds: 3.0) // 12 game-min pending, no tick
        await session.setSpeed(.paused)
        await session.setSpeed(.x1)
        #expect(await session.pump(elapsedSeconds: 3.0) == 0) // fraction was cleared
        #expect(await session.pump(elapsedSeconds: 0.75) == 1)
    }

    @Test func submitWhilePausedAppliesImmediately() async {
        let session = GameSession(state: Fixtures.newState(), systems: [])
        let result = await session.submit(
            ScheduleWakeCommand(label: "note", at: SimTime(rawMinutes: 60)))
        #expect(result == .applied)
        #expect(await session.snapshot.schedule.entries.count == 1)
    }

    @Test func submitWhileRunningAppliesAtBoundary() async {
        let session = GameSession(state: Fixtures.newState(), systems: [])
        await session.setSpeed(.x1)
        let result = await session.submit(
            ScheduleWakeCommand(label: "note", at: SimTime(rawMinutes: 60)))
        #expect(result == nil)
        #expect(await session.snapshot.schedule.entries.isEmpty)
        await session.advance(ticks: 1)
        #expect(await session.snapshot.schedule.entries.count == 1)
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
