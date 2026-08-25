import Testing
@testable import AirlineEmpireCore

@Suite("SimTime & calendar")
struct TimeTests {
    @Test func epochDateIsJanuaryFirstMonday() {
        let date = GameCalendar.date(at: .epoch, startYear: 2030)
        #expect(date.year == 2030)
        #expect(date.month == 1)
        #expect(date.day == 1)
        #expect(date.hour == 0)
        #expect(date.minute == 0)
        #expect(date.weekday == .monday)
        #expect(date.season == .winter)
    }

    @Test func monthLengthsSumToYear() {
        #expect(GameCalendar.monthLengths.reduce(0, +) == GameCalendar.daysPerYear)
    }

    @Test func monthBoundaries() {
        // Last minute of January.
        let jan31 = SimTime(rawMinutes: 31 * GameCalendar.minutesPerDay - 1)
        let d1 = GameCalendar.date(at: jan31, startYear: 2030)
        #expect((d1.month, d1.day, d1.hour, d1.minute) == (1, 31, 23, 59))
        // First minute of February.
        let feb1 = SimTime(rawMinutes: 31 * GameCalendar.minutesPerDay)
        let d2 = GameCalendar.date(at: feb1, startYear: 2030)
        #expect((d2.month, d2.day) == (2, 1))
        // No leap years: Feb 28 -> Mar 1.
        let mar1 = SimTime(rawMinutes: (31 + 28) * GameCalendar.minutesPerDay)
        let d3 = GameCalendar.date(at: mar1, startYear: 2030)
        #expect((d3.month, d3.day) == (3, 1))
    }

    @Test func yearRollover() {
        let lastMinute = SimTime(rawMinutes: 365 * GameCalendar.minutesPerDay - 1)
        let d1 = GameCalendar.date(at: lastMinute, startYear: 2030)
        #expect((d1.year, d1.month, d1.day) == (2030, 12, 31))
        let newYear = SimTime(rawMinutes: 365 * GameCalendar.minutesPerDay)
        let d2 = GameCalendar.date(at: newYear, startYear: 2030)
        #expect((d2.year, d2.month, d2.day) == (2031, 1, 1))
    }

    @Test func dateTimeRoundTrip() {
        for (y, m, d) in [(2030, 1, 1), (2030, 2, 28), (2031, 12, 31), (2045, 7, 15)] {
            let time = GameCalendar.time(year: y, month: m, day: d, startYear: 2030)
            let date = GameCalendar.date(at: time, startYear: 2030)
            #expect((date.year, date.month, date.day) == (y, m, d))
        }
    }

    @Test func weekdayCycles() {
        let day8 = SimTime(rawMinutes: 7 * GameCalendar.minutesPerDay)
        #expect(GameCalendar.date(at: day8, startYear: 2030).weekday == .monday)
        let day6 = SimTime(rawMinutes: 5 * GameCalendar.minutesPerDay)
        #expect(GameCalendar.date(at: day6, startYear: 2030).weekday == .saturday)
    }

    @Test func longRunStability() {
        // 50 game-years in, dates still derive exactly.
        let time = GameCalendar.time(year: 2080, month: 6, day: 15, startYear: 2030)
        let date = GameCalendar.date(at: time, startYear: 2030)
        #expect((date.year, date.month, date.day, date.season) == (2080, 6, 15, .summer))
    }

    @Test func seasonMapping() {
        #expect(Season(month: 12) == .winter)
        #expect(Season(month: 2) == .winter)
        #expect(Season(month: 3) == .spring)
        #expect(Season(month: 8) == .summer)
        #expect(Season(month: 11) == .autumn)
    }

    @Test func cadenceFiringAtBoundaries() {
        let tick = SimDuration.minutes(15)
        // Tick crossing an hour boundary.
        let before = SimTime(rawMinutes: 55)
        let after = before + tick
        #expect(Cadence.hourly.fires(previous: before, current: after, startYear: 2030))
        #expect(!Cadence.daily.fires(previous: before, current: after, startYear: 2030))
        // Tick crossing midnight fires hourly + daily.
        let night = SimTime(rawMinutes: GameCalendar.minutesPerDay - 15)
        let morning = night + tick
        #expect(Cadence.hourly.fires(previous: night, current: morning, startYear: 2030))
        #expect(Cadence.daily.fires(previous: night, current: morning, startYear: 2030))
        // Day 7 boundary fires weekly.
        let endOfWeek = SimTime(rawMinutes: 7 * GameCalendar.minutesPerDay - 15)
        #expect(Cadence.weekly.fires(previous: endOfWeek, current: endOfWeek + tick, startYear: 2030))
        // Feb 1 boundary fires monthly.
        let endOfJan = SimTime(rawMinutes: 31 * GameCalendar.minutesPerDay - 15)
        #expect(Cadence.monthly.fires(previous: endOfJan, current: endOfJan + tick, startYear: 2030))
        // Mid-month tick does not.
        let midMonth = SimTime(rawMinutes: 10 * GameCalendar.minutesPerDay + 300)
        #expect(!Cadence.monthly.fires(previous: midMonth, current: midMonth + tick, startYear: 2030))
    }

    @Test func flooredDivisionMatchesExpectations() {
        #expect(Int64(-1).flooredDivision(by: 1440) == -1)
        #expect(Int64(0).flooredDivision(by: 1440) == 0)
        #expect(Int64(1439).flooredDivision(by: 1440) == 0)
        #expect(Int64(1440).flooredDivision(by: 1440) == 1)
    }
}

@Suite("Money")
struct MoneyTests {
    @Test func roundingHalfAwayFromZero() {
        // 2.375 is dyadic, so 2.375 * 100 == 237.5 exactly: a true tie.
        #expect(Money(rounding: 2.375).cents == 238)
        #expect(Money(rounding: -2.375).cents == -238)
        #expect(Money(rounding: 2.3749).cents == 237)
        #expect(Money(rounding: -2.3749).cents == -237)
        #expect(Money(rounding: 0.0).cents == 0)
    }

    @Test func arithmetic() {
        let a = Money.dollars(10)
        let b = Money(cents: 250)
        #expect((a + b).cents == 1250)
        #expect((a - b).cents == 750)
        #expect((b * 4).cents == 1000)
        #expect((-b).cents == -250)
        #expect(b < a)
        #expect((a - a) == .zero)
    }
}
