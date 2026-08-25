import Testing
@testable import AirlineEmpireCore

@Suite("Simulation engine")
struct EngineTests {
    @Test func clockAdvancesByTick() {
        let engine = SimulationEngine(state: Fixtures.newState(), systems: [])
        engine.advance(ticks: 4)
        #expect(engine.state.clock.now.rawMinutes == 60)
        #expect(engine.state.clock.tickCount == 4)
    }

    @Test func pipelineRunsInRegisteredOrder() {
        let recorder = Recorder()
        let systems: [any SimulationSystem] = [
            RecordingSystem(id: "first", cadence: .everyTick, recorder: recorder),
            RecordingSystem(id: "second", cadence: .everyTick, recorder: recorder),
            RecordingSystem(id: "third", cadence: .everyTick, recorder: recorder),
        ]
        let engine = SimulationEngine(state: Fixtures.newState(), systems: systems)
        engine.advance(ticks: 2)
        #expect(recorder.entries == ["first", "second", "third", "first", "second", "third"])
    }

    @Test func cadenceDispatchCountsOverOneYear() {
        let recorder = Recorder()
        let systems: [any SimulationSystem] = [
            RecordingSystem(id: "tick", cadence: .everyTick, recorder: recorder),
            RecordingSystem(id: "hour", cadence: .hourly, recorder: recorder),
            RecordingSystem(id: "day", cadence: .daily, recorder: recorder),
            RecordingSystem(id: "week", cadence: .weekly, recorder: recorder),
            RecordingSystem(id: "month", cadence: .monthly, recorder: recorder),
        ]
        let engine = SimulationEngine(state: Fixtures.newState(), systems: systems)
        engine.advance(ticks: Fixtures.ticksPerYear)
        #expect(recorder.count(of: "tick") == Fixtures.ticksPerYear)
        #expect(recorder.count(of: "hour") == 24 * 365)
        #expect(recorder.count(of: "day") == 365)
        #expect(recorder.count(of: "week") == 52)   // 365 days = 52 boundaries after epoch week
        #expect(recorder.count(of: "month") == 12)
    }

    @Test func calendarEventsEmitted() {
        let engine = SimulationEngine(state: Fixtures.newState(), systems: [])
        engine.advance(ticks: Fixtures.ticksPerDay * 31) // through Feb 1
        let kinds = engine.state.eventLog.recent.map(\.kind)
        let dayStarts = kinds.filter { if case .dayStarted = $0 { true } else { false } }
        #expect(dayStarts.count == 31)
        #expect(kinds.contains(.weekStarted(weekIndex: 1)))
        #expect(kinds.contains(.monthStarted(year: 2030, month: 2)))
    }

    @Test func seasonChangeEmittedAtMarch() {
        let engine = SimulationEngine(state: Fixtures.newState(), systems: [])
        engine.advance(ticks: Fixtures.ticksPerDay * (31 + 28))
        #expect(engine.state.eventLog.recent.map(\.kind).contains(.seasonChanged(.spring)))
    }

    @Test func chunkInvariance() throws {
        // The same total ticks produce identical state regardless of call
        // pattern (docs/SIMULATION_ARCHITECTURE.md §6).
        let a = SimulationEngine(state: Fixtures.newState(), systems: [StochasticSystem()])
        a.advance(ticks: Fixtures.ticksPerDay * 30)

        let b = SimulationEngine(state: Fixtures.newState(), systems: [StochasticSystem()])
        for _ in 0..<(Fixtures.ticksPerDay * 30) { b.advance(ticks: 1) }

        let c = SimulationEngine(state: Fixtures.newState(), systems: [StochasticSystem()])
        var remaining = Fixtures.ticksPerDay * 30
        var step = 1
        while remaining > 0 { // irregular chunks
            let n = min(step, remaining)
            c.advance(ticks: n)
            remaining -= n
            step = step % 7 + 3
        }

        #expect(try a.state.stateHash() == b.state.stateHash())
        #expect(try a.state.stateHash() == c.state.stateHash())
    }

    @Test func dualRunDeterminism() throws {
        let a = SimulationEngine(state: Fixtures.newState(seed: 777), systems: [StochasticSystem()])
        let b = SimulationEngine(state: Fixtures.newState(seed: 777), systems: [StochasticSystem()])
        a.advance(ticks: Fixtures.ticksPerDay * 90)
        b.advance(ticks: Fixtures.ticksPerDay * 90)
        #expect(try a.state.stateHash() == b.state.stateHash())

        let other = SimulationEngine(state: Fixtures.newState(seed: 778), systems: [StochasticSystem()])
        other.advance(ticks: Fixtures.ticksPerDay * 90)
        #expect(try a.state.stateHash() != other.state.stateHash())
    }

    @Test func addingSystemDoesNotPerturbOthersDraws() throws {
        // A new system with its own streams must not change an existing
        // system's random draws (substream independence at engine level).
        let recorder1 = Recorder()
        let lone = SimulationEngine(
            state: Fixtures.newState(seed: 31),
            systems: [RecordingSystem(id: "sysA", cadence: .hourly, recorder: recorder1, drawsRandom: true)])
        lone.advance(ticks: 200)
        let loneStream = lone.state.rng.streams["sysA.noise"]

        let recorder2 = Recorder()
        let paired = SimulationEngine(
            state: Fixtures.newState(seed: 31),
            systems: [
                RecordingSystem(id: "sysB", cadence: .everyTick, recorder: recorder2, drawsRandom: true),
                RecordingSystem(id: "sysA", cadence: .hourly, recorder: recorder2, drawsRandom: true),
            ])
        paired.advance(ticks: 200)
        #expect(paired.state.rng.streams["sysA.noise"] == loneStream)
    }

    @Test func commandsApplyAtNextBoundaryInOrder() {
        let engine = SimulationEngine(state: Fixtures.newState(), systems: [])
        engine.enqueue(ScheduleWakeCommand(label: "first", at: SimTime(rawMinutes: 30)))
        engine.enqueue(ScheduleWakeCommand(label: "second", at: SimTime(rawMinutes: 30)))
        #expect(engine.state.schedule.entries.isEmpty) // nothing before boundary

        engine.advance(ticks: 1)
        #expect(engine.lastCommandResults == [.applied, .applied])
        // Both fired? due=30, first tick reaches 15 -> still queued.
        #expect(engine.state.schedule.entries.map(\.kind) ==
                [.wake(label: "first"), .wake(label: "second")])

        engine.advance(ticks: 1) // reaches 30, wakes fire in submission order
        let wakes = engine.state.eventLog.recent.compactMap { event -> String? in
            if case .wakeFired(let label) = event.kind { label } else { nil }
        }
        #expect(wakes == ["first", "second"])
        #expect(engine.state.schedule.entries.isEmpty)
    }

    @Test func rejectedCommandChangesNothing() throws {
        let engine = SimulationEngine(state: Fixtures.newState(), systems: [])
        engine.advance(ticks: 4) // now = 60
        let before = try engine.state.stateHash()

        let result = engine.applyNow(ScheduleWakeCommand(label: "late", at: SimTime(rawMinutes: 60)))
        #expect(result == .rejected(CommandRejection(
            code: "wake.inPast", message: "Reminder time has already passed")))
        #expect(try engine.state.stateHash() == before)

        let empty = engine.applyNow(ScheduleWakeCommand(label: "", at: SimTime(rawMinutes: 999)))
        guard case .rejected(let rejection) = empty else {
            Issue.record("Expected rejection")
            return
        }
        #expect(rejection.code == "wake.emptyLabel")
    }

    @Test func commandAppliedEventLogged() {
        let engine = SimulationEngine(state: Fixtures.newState(), systems: [])
        _ = engine.applyNow(ScheduleWakeCommand(label: "x", at: SimTime(rawMinutes: 500)))
        #expect(engine.state.eventLog.recent.map(\.kind)
            .contains(.commandApplied(name: "scheduleWake")))
    }

    @Test func eventLogStaysBounded() {
        // Two years produce 866 calendar events (2×(365+52+12+4)), which
        // overflows the 512-entry ring; the counter keeps the full total.
        let engine = SimulationEngine(state: Fixtures.newState(), systems: [])
        engine.advance(ticks: Fixtures.ticksPerYear * 2)
        #expect(engine.state.eventLog.recent.count == BoundedEventLog.defaultCapacity)
        #expect(engine.state.eventLog.totalCount == 866)
    }
}
