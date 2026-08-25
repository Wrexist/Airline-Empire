/// The game's fixed civil calendar: 365-day years (no leap years), real
/// month lengths, epoch is 00:00 on January 1 of the scenario's start year,
/// and the epoch day is defined to be a Monday.
///
/// Deliberately simplified (docs/SIMULATION_ARCHITECTURE.md §1): stable,
/// cheap, and identical on every device. Time zones are a world-layer
/// concern (Phase 4), not a calendar concern.
public enum GameCalendar {
    public static let minutesPerDay: Int64 = 24 * 60
    public static let daysPerYear: Int64 = 365

    /// Month lengths, January first. Sums to 365.
    public static let monthLengths: [Int64] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    /// First day-of-year index (0-based) for each month.
    static let monthStartDays: [Int64] = {
        var starts: [Int64] = []
        var acc: Int64 = 0
        for len in monthLengths {
            starts.append(acc)
            acc += len
        }
        return starts
    }()

    public static func date(at time: SimTime, startYear: Int) -> GameDate {
        let day = time.dayIndex
        precondition(day >= 0, "Simulation time before epoch has no date")
        let year = day.flooredDivision(by: daysPerYear)
        let dayOfYear = day - year * daysPerYear
        // Month lookup: last month whose start day is <= dayOfYear.
        var month = 11
        while monthStartDays[month] > dayOfYear { month -= 1 }
        let dayOfMonth = dayOfYear - monthStartDays[month] + 1
        let minute = time.minuteOfDay
        return GameDate(
            year: startYear + Int(year),
            month: month + 1,
            day: Int(dayOfMonth),
            hour: Int(minute / 60),
            minute: Int(minute % 60),
            weekday: Weekday(rawValue: Int(day % 7))!,
            season: Season(month: month + 1)
        )
    }

    /// Inverse of `date(at:startYear:)` for a midnight date. Used by
    /// scenario bootstrap and tests.
    public static func time(year: Int, month: Int, day: Int, startYear: Int) -> SimTime {
        precondition((1...12).contains(month) && day >= 1 && Int64(day) <= monthLengths[month - 1],
                     "Invalid calendar date")
        precondition(year >= startYear, "Date precedes scenario epoch")
        let days = Int64(year - startYear) * daysPerYear + monthStartDays[month - 1] + Int64(day - 1)
        return SimTime(rawMinutes: days * minutesPerDay)
    }

    /// Zero-based month index (0-11) at a time; cheap monthly-boundary key.
    public static func monthIndex(at time: SimTime) -> Int64 {
        let day = time.dayIndex
        let year = day.flooredDivision(by: daysPerYear)
        let dayOfYear = day - year * daysPerYear
        var month = 11
        while monthStartDays[month] > dayOfYear { month -= 1 }
        return year * 12 + Int64(month)
    }
}

public struct GameDate: Hashable, Codable, Sendable {
    public var year: Int
    public var month: Int      // 1-12
    public var day: Int        // 1-31
    public var hour: Int       // 0-23
    public var minute: Int     // 0-59
    public var weekday: Weekday
    public var season: Season
}

public enum Weekday: Int, Hashable, Codable, Sendable, CaseIterable {
    // Epoch (day 0) is defined as a Monday.
    case monday = 0, tuesday, wednesday, thursday, friday, saturday, sunday
}

public enum Season: String, Hashable, Codable, Sendable, CaseIterable {
    case winter, spring, summer, autumn

    /// Northern-hemisphere convention; regional seasonality profiles
    /// (Phase 4 content) handle hemisphere and market specifics.
    public init(month: Int) {
        switch month {
        case 12, 1, 2: self = .winter
        case 3, 4, 5: self = .spring
        case 6, 7, 8: self = .summer
        default: self = .autumn
        }
    }
}
