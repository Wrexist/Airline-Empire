/// Builds a fresh `GameState` from scenario parameters
/// (docs/ARCHITECTURE.md §8). Scenario *content* (starting airport, cash,
/// difficulty) arrives with the content catalog in Phase 4; the kernel-level
/// bootstrap fixes world identity: seed, epoch, tick size.
public enum ScenarioBootstrap {
    /// Standard tick size (decision D-007). Stored into the save's meta;
    /// existing saves keep the tick they were created with.
    public static let standardTickMinutes: Int64 = 15

    public static func newGame(scenario: ScenarioCode, worldSeed: UInt64, startYear: Int) -> GameState {
        GameState(
            meta: GameMeta(scenario: scenario, worldSeed: worldSeed,
                           startYear: startYear, tickMinutes: standardTickMinutes),
            clock: ClockState(),
            rng: RNGState(worldSeed: worldSeed)
        )
    }
}
