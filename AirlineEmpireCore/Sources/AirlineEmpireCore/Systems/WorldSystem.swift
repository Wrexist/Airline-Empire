import Foundation

/// Daily world dynamics (docs/ECONOMY.md): fuel price and the macro cycle.
/// Deterministic seeded processes; clamped so the world stays playable.
public struct WorldSystem: SimulationSystem {
    public let id = "world"
    public let cadence = Cadence.daily

    public init() {}

    public func update(state: inout GameState, context: SimContext) {
        let tuning = context.catalog.tuning.world

        // Fuel: mean-reverting geometric walk around the content base price,
        // scaled by any active fuel shock (docs/EVENTS.md).
        let base = context.catalog.tuning.ops.baseFuelPricePerTon.asDouble
            * state.world.fuelShockFactor(at: context.current)
        let price = state.world.fuelPricePerTon.asDouble
        let noise = (state.rng.unitDouble("world.fuel") - 0.5) * 2 // [-1, 1)
        let drift = tuning.fuelMeanReversion * (log(base) - log(price))
        let next = price * exp(drift + tuning.fuelDailyVolatility * noise)
        let hardBase = context.catalog.tuning.ops.baseFuelPricePerTon.asDouble
        let clamped = min(hardBase * tuning.fuelMaxFactor,
                          max(hardBase * tuning.fuelMinFactor, next))
        state.world.fuelPricePerTon = Money(rounding: clamped)

        // Economy: regime-switching drift. The target flips between boom
        // and downturn rarely; the index drifts toward it with small noise —
        // multi-year cycles the player can read and position against.
        if state.rng.chance("world.regime", probability: tuning.economyRegimeSwitchDailyChance) {
            state.world.economicCycleTarget =
                state.world.economicCycleTarget >= 1.0
                ? tuning.economyLowTarget : tuning.economyHighTarget
        }
        let economyNoise = (state.rng.unitDouble("world.economy") - 0.5) * 2
        var index = state.world.economicIndex
        index += tuning.economyReversion * (state.world.economicCycleTarget - index)
        index += tuning.economyDailyVolatility * economyNoise
        state.world.economicIndex = min(tuning.economyHighTarget + 0.1,
                                        max(tuning.economyLowTarget - 0.1, index))
    }
}
