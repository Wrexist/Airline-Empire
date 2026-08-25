/// Kernel-level commands. Gameplay commands (routes, fleet, finance) arrive
/// with their systems in later phases; the kernel owns exactly one: a
/// player-visible reminder wake ("notify me at date X"), which is also the
/// canonical exercise of the command pipeline.
public struct ScheduleWakeCommand: Command, Equatable {
    public static let name = "scheduleWake"

    public let label: String
    public let at: SimTime

    public init(label: String, at: SimTime) {
        self.label = label
        self.at = at
    }

    public func validate(state: GameState) -> CommandRejection? {
        if label.isEmpty {
            return CommandRejection(code: "wake.emptyLabel", message: "A reminder needs a label")
        }
        if at <= state.clock.now {
            return CommandRejection(code: "wake.inPast", message: "Reminder time has already passed")
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        state.schedule.schedule(.wake(label: label), at: at)
    }
}
