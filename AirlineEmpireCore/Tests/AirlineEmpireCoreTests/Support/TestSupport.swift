import Foundation
@testable import AirlineEmpireCore

/// Shared fixtures for kernel tests.
enum Fixtures {
    static func newState(seed: UInt64 = 42, startYear: Int = 2030) -> GameState {
        ScenarioBootstrap.newGame(scenario: "test", worldSeed: seed, startYear: startYear)
    }

    static let ticksPerDay = Int(GameCalendar.minutesPerDay / ScenarioBootstrap.standardTickMinutes)
    static let ticksPerYear = ticksPerDay * Int(GameCalendar.daysPerYear)
}

/// Thread-safe recorder for observing engine behavior from test systems.
/// Production systems are stateless (docs/SIMULATION_ARCHITECTURE.md §4);
/// this is a test double for observing the pipeline itself.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [String] = []

    var entries: [String] {
        lock.lock(); defer { lock.unlock() }
        return _entries
    }

    func record(_ entry: String) {
        lock.lock(); defer { lock.unlock() }
        _entries.append(entry)
    }

    func count(of entry: String) -> Int {
        entries.filter { $0 == entry }.count
    }
}

/// Records every invocation; optionally draws from its RNG stream so runs
/// perturb state (for determinism tests).
struct RecordingSystem: SimulationSystem {
    let id: String
    let cadence: Cadence
    let recorder: Recorder
    var drawsRandom = false

    func update(state: inout GameState, context: SimContext) {
        recorder.record(id)
        if drawsRandom {
            _ = state.rng.next("\(id).noise")
        }
    }
}

/// A deterministic-but-stochastic system used by determinism, chunking, and
/// save/restore tests: draws randomness and schedules wakes.
struct StochasticSystem: SimulationSystem {
    let id = "test.stochastic"
    let cadence = Cadence.hourly

    func update(state: inout GameState, context: SimContext) {
        if state.rng.chance("\(id).wake", probability: 0.25) {
            let delay = Int64(state.rng.int("\(id).delay", in: 60...720))
            state.schedule.schedule(.wake(label: "w\(state.clock.tickCount)"),
                                    at: state.clock.now + .minutes(delay))
        }
    }
}
