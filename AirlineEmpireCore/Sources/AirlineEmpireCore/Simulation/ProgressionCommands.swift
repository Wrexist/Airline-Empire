/// Progression commands (Phase 12).

/// Starts a capability program: money + calendar time buying a rule change
/// (docs/PROGRESSION.md §4). Player-only; unlocked from the National era.
public struct StartCapabilityProgramCommand: Command, Equatable {
    public static let name = "startCapabilityProgram"

    public let airline: AirlineID
    public let code: CapabilityCode

    public init(airline: AirlineID, code: CapabilityCode) {
        self.airline = airline
        self.code = code
    }

    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard let a = state.airlines[airline], a.status == .active else {
            return CommandRejection(code: "airline.unknown", message: "Unknown airline")
        }
        guard a.kind == .player else {
            return CommandRejection(code: "progression.playerOnly",
                                    message: "Capability programs are player decisions")
        }
        let tuning = catalog.tuning.progression
        if state.progression.era < .national {
            return CommandRejection(code: "progression.eraLocked",
                                    message: "Capability programs open in the National era")
        }
        if state.progression.hasCapability(code) {
            return CommandRejection(code: "progression.alreadyCompleted",
                                    message: "This capability is already built")
        }
        if state.progression.activePrograms.contains(where: { $0.code == code }) {
            return CommandRejection(code: "progression.alreadyRunning",
                                    message: "This program is already underway")
        }
        if state.progression.activePrograms.count >= tuning.maxActivePrograms {
            return CommandRejection(code: "progression.tooManyPrograms",
                                    message: "At most \(tuning.maxActivePrograms) programs at once")
        }
        if state.ledger.balance(of: airline) < tuning.capabilityCost {
            return CommandRejection(code: "progression.insufficientFunds",
                                    message: "Program costs \(tuning.capabilityCost.cents / 100)")
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        let tuning = context.catalog.tuning.progression
        state.ledger.post(airline: airline, category: .overhead,
                          amount: -tuning.capabilityCost, at: context.current,
                          memo: "Capability: \(code.rawValue)")
        state.progression.activePrograms.append(CapabilityProgram(
            code: code, startedAt: context.current,
            completesAt: context.current + .days(Int64(tuning.capabilityDurationDays)),
            cost: tuning.capabilityCost))
    }
}
