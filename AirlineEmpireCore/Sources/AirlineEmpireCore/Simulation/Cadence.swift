/// How often a system runs (docs/SIMULATION_ARCHITECTURE.md §1).
/// A cadence fires when its calendar boundary is crossed within the
/// half-open interval (previous, current] of one tick — exact regardless of
/// tick size, including multi-boundary jumps (which the engine forbids by
/// keeping ticks small, but the math stays correct).
public enum Cadence: String, Codable, Sendable, CaseIterable {
    case everyTick
    case hourly
    case daily
    case weekly
    case monthly

    public func fires(previous: SimTime, current: SimTime, startYear: Int) -> Bool {
        precondition(previous < current, "Cadence evaluated over a non-advancing interval")
        switch self {
        case .everyTick:
            return true
        case .hourly:
            return previous.hourIndex != current.hourIndex
        case .daily:
            return previous.dayIndex != current.dayIndex
        case .weekly:
            return previous.weekIndex != current.weekIndex
        case .monthly:
            return GameCalendar.monthIndex(at: previous) != GameCalendar.monthIndex(at: current)
        }
    }
}
