/// Simulation time: whole game-minutes since the scenario epoch.
///
/// All gameplay time flows through this type; wall-clock time never enters
/// the simulation (docs/SIMULATION_ARCHITECTURE.md §1). Int64 so overflow is
/// unreachable in any realistic playthrough.
public struct SimTime: Hashable, Codable, Comparable, Sendable {
    public var rawMinutes: Int64

    public init(rawMinutes: Int64) {
        self.rawMinutes = rawMinutes
    }

    public static let epoch = SimTime(rawMinutes: 0)

    public static func < (lhs: SimTime, rhs: SimTime) -> Bool {
        lhs.rawMinutes < rhs.rawMinutes
    }

    public static func + (lhs: SimTime, rhs: SimDuration) -> SimTime {
        SimTime(rawMinutes: lhs.rawMinutes + rhs.minutes)
    }

    public static func - (lhs: SimTime, rhs: SimTime) -> SimDuration {
        SimDuration(minutes: lhs.rawMinutes - rhs.rawMinutes)
    }

    public static func += (lhs: inout SimTime, rhs: SimDuration) {
        lhs.rawMinutes += rhs.minutes
    }

    /// Whole game-days elapsed since epoch (day 0 = the first day).
    public var dayIndex: Int64 { rawMinutes.flooredDivision(by: GameCalendar.minutesPerDay) }

    /// Whole game-hours elapsed since epoch.
    public var hourIndex: Int64 { rawMinutes.flooredDivision(by: 60) }

    /// Whole game-weeks elapsed since epoch (week 0 starts at epoch).
    public var weekIndex: Int64 { dayIndex.flooredDivision(by: 7) }

    /// Minute within the current day, 0..<1440.
    public var minuteOfDay: Int64 {
        let m = rawMinutes % GameCalendar.minutesPerDay
        return m >= 0 ? m : m + GameCalendar.minutesPerDay
    }
}

/// A span of game time in whole minutes. Signed so differences are exact.
public struct SimDuration: Hashable, Codable, Comparable, Sendable {
    public var minutes: Int64

    public init(minutes: Int64) {
        self.minutes = minutes
    }

    public static func minutes(_ m: Int64) -> SimDuration { SimDuration(minutes: m) }
    public static func hours(_ h: Int64) -> SimDuration { SimDuration(minutes: h * 60) }
    public static func days(_ d: Int64) -> SimDuration { SimDuration(minutes: d * GameCalendar.minutesPerDay) }

    public static func < (lhs: SimDuration, rhs: SimDuration) -> Bool {
        lhs.minutes < rhs.minutes
    }
}

extension Int64 {
    /// Floored (toward negative infinity) division; Swift's `/` truncates
    /// toward zero, which is wrong for pre-epoch times.
    func flooredDivision(by divisor: Int64) -> Int64 {
        let q = self / divisor
        return (self % divisor != 0 && (self < 0) != (divisor < 0)) ? q - 1 : q
    }
}
