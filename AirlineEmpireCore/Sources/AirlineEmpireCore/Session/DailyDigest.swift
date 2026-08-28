/// The evening digest (docs/CORE_LOOP.md §3, docs/PLAYER_JOURNEY.md §1
/// step 4): "a small profit or loss with its *why*" — the beat that closes
/// the decide → watch → understand loop at the end of each game day.
///
/// Derived entirely from the ledger's timestamped transaction ring and the
/// event log. No per-day state is accumulated and nothing new is persisted,
/// so the save format is untouched (v10) — a digest is a *view* of what
/// already happened, never a second copy of it.
///
/// Both rings are bounded (`Ledger.defaultRecentCapacity`,
/// `BoundedEventLog.defaultCapacity`), so a very large network can post more
/// in one day than either retains, and an entity deleted mid-day can leave a
/// flight event unattributable. Every such case is reported through
/// `isComplete` rather than quietly under-counting: a digest that lies about
/// money or flights is worse than one that admits it is partial.

public struct DailyDigestModel: Equatable, Sendable {
    public let date: GameDate
    public let dayIndex: Int64

    /// Signed money moved today, by category (positive credits the airline).
    public let byCategory: [TransactionCategory: Money]
    public let revenue: Money
    /// Negative: what the day cost to operate and run.
    public let expenses: Money
    /// Revenue + expenses; the number the player reads first.
    public let netCashChange: Money

    public let flightsCompleted: Int
    public let flightsCancelled: Int
    /// Events from today worth a line in the digest, oldest first.
    public let notableEvents: [SimEvent]

    /// False when the transaction ring may have dropped part of today, so
    /// the figures are a floor rather than the whole day.
    public let isComplete: Bool

    /// Whether anything happened worth showing the player.
    public var hasContent: Bool {
        !byCategory.isEmpty || flightsCompleted > 0 || flightsCancelled > 0
            || !notableEvents.isEmpty
    }
}

extension GameState {
    /// The digest for a given game day (defaults to the day in progress).
    /// Pass `clock.now.dayIndex - 1` at a day boundary for "yesterday",
    /// which is what an evening digest actually summarizes.
    ///
    /// Returns nil for a day that cannot have a digest: an airline that does
    /// not exist, or — BUG-008 — a day before the game began. The second case
    /// is not hypothetical: on the very first day `clock.now.dayIndex` is 0,
    /// so the caller asking for "yesterday" asks for day −1, which used to
    /// reach `GameCalendar.date(at:)` and trip its `day >= 0` precondition.
    /// That is a crash on the first screen after founding an airline, which is
    /// how it shipped in 1.0.0 (1) and how TestFlight found it.
    ///
    /// Nil rather than an empty digest, deliberately: a day that never
    /// happened is not a day where nothing happened, and every caller already
    /// handles nil because an unknown airline returns it too.
    public func dailyDigest(for airline: AirlineID,
                            day: Int64? = nil) -> DailyDigestModel? {
        guard airlines[airline] != nil else { return nil }
        let dayIndex = day ?? clock.now.dayIndex
        guard dayIndex >= 0 else { return nil }
        let dayStart = SimTime(rawMinutes: dayIndex * GameCalendar.minutesPerDay)
        let dayEnd = SimTime(rawMinutes: (dayIndex + 1) * GameCalendar.minutesPerDay)

        var byCategory: [TransactionCategory: Money] = [:]
        var revenueCents: Int64 = 0
        var expenseCents: Int64 = 0
        for transaction in ledger.recent
        where transaction.airline == airline
            && transaction.at >= dayStart && transaction.at < dayEnd {
            let existing = byCategory[transaction.category] ?? .zero
            byCategory[transaction.category] = existing + transaction.amount
            if transaction.amount.cents >= 0 {
                revenueCents += transaction.amount.cents
            } else {
                expenseCents += transaction.amount.cents
            }
        }

        // The ring only loses the oldest entries. If it is full and its
        // oldest surviving transaction already falls inside this day, then
        // earlier ones from the same day were evicted.
        let ringFull = ledger.recent.count >= ledger.recentCapacity
        let oldestRetained = ledger.recent.first?.at
        let isComplete = !ringFull || (oldestRetained.map { $0 < dayStart } ?? true)

        // The event ring is bounded independently of the ledger's, so a day
        // can be complete in money and truncated in news. Both must hold.
        let eventRingFull = eventLog.recent.count >= eventLog.capacity
        let oldestEvent = eventLog.recent.first?.at
        let eventsComplete = !eventRingFull || (oldestEvent.map { $0 < dayStart } ?? true)

        var completed = 0
        var cancelled = 0
        var notable: [SimEvent] = []
        // A flight event whose route was deleted during the day (the player
        // closed it, or its airline collapsed) cannot be attributed, so it can
        // neither be counted nor safely shown (BUG-007).
        var unattributableFlights = false
        for event in eventLog.recent
        where event.at >= dayStart && event.at < dayEnd {
            switch event.kind {
            case .flightArrived:
                let subject = subjectAirline(of: event)
                if subject == airline { completed += 1 }
                else if subject == nil { unattributableFlights = true }
            case .flightCancelled:
                let subject = subjectAirline(of: event)
                if subject == airline { cancelled += 1 }
                else if subject == nil { unattributableFlights = true }
            // Individual departures and arrivals are the day's texture, not
            // its story; the story is what changed.
            case .flightDeparted, .flightDelayed, .dayStarted, .weekStarted,
                 .monthStarted, .wakeFired, .commandApplied, .aircraftAssigned,
                 .aircraftUnassigned:
                continue
            default:
                if isFeedEvent(event, for: airline) { notable.append(event) }
            }
        }

        return DailyDigestModel(
            date: GameCalendar.date(at: dayStart, startYear: meta.startYear),
            dayIndex: dayIndex,
            byCategory: byCategory,
            revenue: Money(cents: revenueCents),
            expenses: Money(cents: expenseCents),
            netCashChange: Money(cents: revenueCents + expenseCents),
            flightsCompleted: completed,
            flightsCancelled: cancelled,
            notableEvents: notable,
            isComplete: isComplete && eventsComplete && !unattributableFlights)
    }
}
