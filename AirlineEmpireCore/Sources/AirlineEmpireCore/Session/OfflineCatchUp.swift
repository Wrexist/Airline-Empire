/// Capped offline catch-up (docs/GAME_DIRECTION.md §4, docs/ROADMAP_DIRECTION_II.md
/// Phase 29, AE-050): the world moves on a little while the app is closed,
/// and the player is met with an account of what happened.
///
/// It is not a second simulation mode. `GameSession.catchUp(awaySeconds:)`
/// runs the same ticks the clock would have run, one at a time, so the
/// result is exactly what pressing play for that long would have produced —
/// deterministic, chunk-invariant, and replayable from the save. What this
/// file adds is the three decisions the roadmap names and the account:
///
/// 1. **The rate.** Real time away is credited at a fraction of the slowest
///    play speed: three game minutes per real minute, so a night away is one
///    game day. 1x play runs a game day in six real minutes; catch-up is
///    eighty times gentler, so leaving the game is never a strategy.
/// 2. **The cap.** One game week per return, whatever the absence. A week of
///    catch-up is forty-two minutes of 1x play — or under three at 16x —
///    which is also why a wound-forward device clock buys nothing a player
///    could not get faster by pressing fast-forward.
/// 3. **What may happen.** Ordinary business, good and bad, but nothing
///    terminal and nothing that runs out on the player: the catch-up stops
///    before the solvency countdown can start or advance, and before a held
///    mission or contract reaches its deadline. The world waits for the
///    player at exactly the moment they would want to be there.
///
/// Clock changes are handled by refusing to trust them: a negative absence
/// (the clock moved back), a non-finite one, or one longer than any real
/// absence plausibly is earns nothing, and everything else is capped.

// MARK: - Tuning

/// The numbers that decide whether leaving the game is a strategy. Content,
/// not code (`tuning.json` › `offlineCatchUp`), so the balance battery can
/// move them without a build.
public struct OfflineCatchUpTuning: Equatable, Codable, Sendable {
    /// Game minutes credited per real minute away. Three makes a night of
    /// eight hours one game day.
    public let gameMinutesPerRealMinute: Double
    /// The most game time a single return may advance, in game days.
    public let capGameDays: Int
    /// Absences shorter than this earn nothing — answering a message is not
    /// "time away", and a sheet after every app switch would be noise.
    public let minimumAwayRealMinutes: Double
    /// Longer than this, the anchor or the device clock is wrong rather than
    /// the player away; the absence is ignored instead of capped.
    public let maximumTrustedAwayDays: Double

    public init(gameMinutesPerRealMinute: Double, capGameDays: Int,
                minimumAwayRealMinutes: Double, maximumTrustedAwayDays: Double) {
        self.gameMinutesPerRealMinute = gameMinutesPerRealMinute
        self.capGameDays = capGameDays
        self.minimumAwayRealMinutes = minimumAwayRealMinutes
        self.maximumTrustedAwayDays = maximumTrustedAwayDays
    }

    /// The shipped numbers (docs/ROADMAP_DIRECTION_II.md Phase 29's proposal).
    public static let standard = OfflineCatchUpTuning(
        gameMinutesPerRealMinute: 3, capGameDays: 7,
        minimumAwayRealMinutes: 10, maximumTrustedAwayDays: 400)

    /// Non-negative and finite throughout, and a cap that fits in a day count.
    public var isValid: Bool {
        gameMinutesPerRealMinute.isFinite && gameMinutesPerRealMinute >= 0
            && capGameDays >= 0 && capGameDays <= 366
            && minimumAwayRealMinutes.isFinite && minimumAwayRealMinutes >= 0
            && maximumTrustedAwayDays.isFinite
            && maximumTrustedAwayDays * Double(GameCalendar.minutesPerDay) > minimumAwayRealMinutes
    }
}

// MARK: - Planning

public enum OfflineCatchUp {
    /// The game minutes an absence earns: zero for anything that cannot be
    /// trusted or is too short to count, otherwise the absence at the
    /// tuning's rate, never more than the cap.
    public static func creditedGameMinutes(awaySeconds: Double,
                                           tuning: OfflineCatchUpTuning) -> Int64 {
        guard awaySeconds.isFinite, awaySeconds > 0 else { return 0 }
        let awayMinutes = awaySeconds / 60
        let trusted = tuning.maximumTrustedAwayDays * Double(GameCalendar.minutesPerDay)
        guard awayMinutes >= tuning.minimumAwayRealMinutes, awayMinutes <= trusted else { return 0 }
        let cap = Double(max(0, tuning.capGameDays)) * Double(GameCalendar.minutesPerDay)
        let earned = awayMinutes * max(0, tuning.gameMinutesPerRealMinute)
        return Int64(min(cap, earned).rounded(.down))
    }

    /// Whole ticks the absence earns at this tick size.
    public static func plannedTicks(awaySeconds: Double, tickMinutes: Int64,
                                    tuning: OfflineCatchUpTuning) -> Int {
        guard tickMinutes > 0 else { return 0 }
        return Int(creditedGameMinutes(awaySeconds: awaySeconds, tuning: tuning) / tickMinutes)
    }

    /// Whether the cap, rather than the absence, decided how far the world
    /// moved — the report says so, because "a week passed" and "you were away
    /// for a month" are both true and only one of them is the reason.
    public static func isCapped(awaySeconds: Double, tuning: OfflineCatchUpTuning) -> Bool {
        guard creditedGameMinutes(awaySeconds: awaySeconds, tuning: tuning) > 0 else { return false }
        let cap = Double(max(0, tuning.capGameDays)) * Double(GameCalendar.minutesPerDay)
        return awaySeconds / 60 * tuning.gameMinutesPerRealMinute > cap
    }

    /// Why the next tick must not run while the player is away, or nil when
    /// it may. Asked before every tick, against the world as it stands.
    ///
    /// - The airline is in no state to be run without its owner: gone,
    ///   collapsed, or the game is over.
    /// - It is below the overdraft floor, or the administration countdown
    ///   is already running: the next day boundary would count a day of it.
    ///   The rescue offer exists only inside the countdown, so this also
    ///   keeps that decision with the player.
    /// - A held mission or contract would reach its deadline: it would
    ///   settle as expired at the next daily pass, which is losing something
    ///   for being away.
    static func blocker(in state: GameState, nextTick: SimTime,
                        catalog: ContentCatalog) -> OfflineCatchUpReport.StopReason? {
        guard let player = state.playerAirline, player.status == .active,
              !state.progression.gameOver else { return .airlineInactive }
        if player.daysInsolvent > 0
            || state.ledger.balance(of: player.id).cents < catalog.tuning.finance.overdraftFloorCents {
            return .solvency
        }
        if state.progression.missions.contains(where: { $0.deadline <= nextTick }) {
            return .deadline
        }
        return nil
    }

    /// Whether a tick that has just run started punishing the absence: the
    /// countdown advanced, the airline was restructured or collapsed, or the
    /// game ended. Only a day boundary runs the solvency watch, so the
    /// session only asks this — and only holds the world back for an undo —
    /// on ticks that cross one.
    static func violation(before: GameState, after: GameState) -> OfflineCatchUpReport.StopReason? {
        guard let was = before.playerAirline else { return nil }
        guard let now = after.airlines[was.id] else { return .solvency }
        if now.status != was.status
            || now.administrationCount > was.administrationCount
            || now.daysInsolvent > was.daysInsolvent
            || (after.progression.gameOver && !before.progression.gameOver) {
            return .solvency
        }
        return nil
    }
}

// MARK: - The account

/// What happened while the player was away — an account, not a summary
/// (docs/ROADMAP_DIRECTION_II.md Phase 29, "Trust"): every figure is the
/// sum of what the ticks actually posted, so the player can see *why* their
/// cash moved.
public struct OfflineCatchUpReport: Equatable, Sendable {
    /// Why the catch-up ended before its credit ran out.
    public enum StopReason: String, Equatable, Sendable {
        /// Cash reached the overdraft floor, or the countdown was already
        /// running: the world waited rather than count a day of it.
        case solvency
        /// A mission or contract the player holds was about to close.
        case deadline
        /// No active airline to run.
        case airlineInactive
    }

    /// The absence as measured, in real seconds.
    public let awaySeconds: Double
    /// Game minutes the absence earned (already capped).
    public let creditedGameMinutes: Int64
    /// The cap, not the absence, decided the credit.
    public let wasCapped: Bool
    public let ticksRun: Int
    /// Nil when the whole credit was used.
    public let stopReason: StopReason?

    public let start: SimTime
    public let end: SimTime
    public let startDate: GameDate
    public let endDate: GameDate

    public let flightsCompleted: Int64
    public let flightsCancelled: Int
    public let passengersCarried: Int64
    /// Maintenance checks that began while away — counted rather than listed,
    /// because a large fleet starts several a week.
    public let maintenanceChecks: Int

    /// Signed money posted while away, per category (credits positive).
    public let byCategory: [TransactionCategory: Money]
    public let revenue: Money
    /// Negative: what the time away cost.
    public let expenses: Money
    /// The balance's movement: revenue plus expenses, which is the whole of
    /// it — no command runs while the player is away.
    public let cashChange: Money

    /// The player's news from the time away, oldest first, newest kept when
    /// there was more than the report holds (`maxNotableEvents`).
    public let notableEvents: [SimEvent]
    /// Buildings that opened and hub statuses earned while away
    /// (docs/HUB_PROGRESSION_PLAN.md §6.4: the note leads with construction
    /// news). Kept apart from `notableEvents` so the cap never drops them.
    public let hubEvents: [SimEvent]

    /// The most news lines a report keeps.
    public static let maxNotableEvents = 40

    /// Game time the world actually moved.
    public var gameMinutesAdvanced: Int64 { (end - start).minutes }

    /// Worth putting in front of the player: the world moved, or it was held
    /// for a reason the player should hear.
    public var isWorthShowing: Bool { ticksRun > 0 || stopReason != nil }
}

/// Measures a catch-up tick by tick for `OfflineCatchUpReport`. Internal: the
/// session drives it, and only the finished report is public.
struct OfflineCatchUpTally {
    let player: AirlineID
    let start: SimTime
    let startYear: Int
    let startCash: Money
    let startFlights: Int64
    let startPassengers: Int64

    private var cents: [TransactionCategory: Int64] = [:]
    private var cancelled = 0
    private var checks = 0
    private var notable: [SimEvent] = []
    private var hub: [SimEvent] = []

    init?(state: GameState) {
        guard let player = state.playerAirline else { return nil }
        self.player = player.id
        start = state.clock.now
        startYear = state.meta.startYear
        startCash = state.ledger.balance(of: player.id)
        startFlights = state.progression.counters.flightsCompleted
        startPassengers = state.progression.counters.passengersCarried
    }

    /// What one tick needs to be measured, read before it runs. Small on
    /// purpose: holding the whole state across every tick would make the tick
    /// copy each container it touches.
    struct Mark {
        let now: SimTime
        let monthTotals: [TransactionCategory: Int64]
        let latestStatement: Int?
    }

    func mark(_ state: GameState) -> Mark {
        Mark(now: state.clock.now,
             monthTotals: state.ledger.monthTotals(for: player),
             latestStatement: Self.statementKey(state, player))
    }

    private static func statementKey(_ state: GameState, _ airline: AirlineID) -> Int? {
        state.finance.byAirline[airline]?.latest.map { $0.year * 12 + $0.month }
    }

    mutating func record(from mark: Mark, to state: GameState) {
        // Money, from the month accumulator rather than the shared
        // transaction ring: the ring holds 1,024 postings for the whole
        // world, and a month boundary alone can post more than that. When a
        // month closes inside the tick, what was posted before the rollup is
        // in the new statement and what came after is in the fresh
        // accumulator.
        var delta = state.ledger.monthTotals(for: player)
        if let latest = state.finance.byAirline[player]?.latest,
           Self.statementKey(state, player) != mark.latestStatement {
            for (category, amount) in latest.byCategory { delta[category, default: 0] += amount }
        }
        for (category, amount) in mark.monthTotals { delta[category, default: 0] -= amount }
        for (category, amount) in delta where amount != 0 { cents[category, default: 0] += amount }

        // News, from the player's own feed ring: rival traffic cannot evict
        // it (TD-032), and every event this tick wrote is newer than the
        // tick's start.
        var fresh: [SimEvent] = []
        for event in state.eventLog.playerFeed.reversed() {
            guard event.at > mark.now else { break }
            fresh.append(event)
        }
        for event in fresh.reversed() {
            switch event.kind {
            case .flightArrived:
                continue // counted from the campaign's own counters
            case .flightCancelled:
                cancelled += 1
            case .maintenanceStarted:
                checks += 1
            case .maintenanceCompleted, .flightDeparted, .flightDelayed, .dayStarted,
                 .weekStarted, .monthStarted, .wakeFired, .commandApplied,
                 .aircraftAssigned, .aircraftUnassigned:
                continue
            case .facilityOpened, .hubStatusRaised:
                hub.append(event)
            default:
                notable.append(event)
                if notable.count > OfflineCatchUpReport.maxNotableEvents {
                    notable.removeFirst(notable.count - OfflineCatchUpReport.maxNotableEvents)
                }
            }
        }
    }

    func report(state: GameState, awaySeconds: Double, tuning: OfflineCatchUpTuning,
                ticksRun: Int, stopReason: OfflineCatchUpReport.StopReason?) -> OfflineCatchUpReport {
        var byCategory: [TransactionCategory: Money] = [:]
        var revenue: Int64 = 0
        var expenses: Int64 = 0
        for (category, amount) in cents {
            byCategory[category] = Money(cents: amount)
            if amount >= 0 { revenue += amount } else { expenses += amount }
        }
        let end = state.clock.now
        return OfflineCatchUpReport(
            awaySeconds: awaySeconds,
            creditedGameMinutes: OfflineCatchUp.creditedGameMinutes(awaySeconds: awaySeconds,
                                                                    tuning: tuning),
            wasCapped: OfflineCatchUp.isCapped(awaySeconds: awaySeconds, tuning: tuning),
            ticksRun: ticksRun,
            stopReason: stopReason,
            start: start, end: end,
            startDate: GameCalendar.date(at: start, startYear: startYear),
            endDate: GameCalendar.date(at: end, startYear: startYear),
            flightsCompleted: max(0, state.progression.counters.flightsCompleted - startFlights),
            flightsCancelled: cancelled,
            passengersCarried: max(0, state.progression.counters.passengersCarried - startPassengers),
            maintenanceChecks: checks,
            byCategory: byCategory,
            revenue: Money(cents: revenue),
            expenses: Money(cents: expenses),
            cashChange: state.ledger.balance(of: player) - startCash,
            notableEvents: notable,
            hubEvents: hub)
    }
}
