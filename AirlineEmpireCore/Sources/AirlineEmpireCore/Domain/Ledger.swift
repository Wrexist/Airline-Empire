/// The financial spine (docs/ARCHITECTURE.md §5): every money movement is a
/// categorized transaction against an airline's account. Balances are
/// authoritative; the recent-transaction ring gives the UI its "where did my
/// money go" trail (full statements/rollups arrive in Phase 8).
public struct Ledger: Equatable, Codable, Sendable {
    public static let defaultRecentCapacity = 1024
    /// Days each airline's own window keeps: today and yesterday, which is
    /// what the evening digest reads.
    public static let dayWindowLength: Int64 = 2

    public private(set) var balances: [AirlineID: Money]
    public private(set) var recent: [Transaction]
    public private(set) var totalTransactionCount: Int64
    public private(set) var recentCapacity: Int
    /// Signed cents accumulated per category since the last statement
    /// rollup. Fed at post time so statements never depend on the bounded
    /// `recent` ring.
    public private(set) var monthAccumulator: [AirlineID: [TransactionCategory: Int64]]
    /// Each airline's own per-day totals for the last `dayWindowLength`
    /// days (TD-032). `recent` is one ring for every airline, so a world
    /// full of rival flights evicted the player's morning before the day was
    /// out and the digest could only call the day partial. This window is
    /// per airline and counts days, not transactions, so it holds the whole
    /// day whatever the traffic. Stored optional so a save from before it
    /// (format 15) decodes.
    private var dayWindows: [AirlineID: [LedgerDay]]?
    /// When the windows began recording — the first posting of a new game,
    /// or the first after a pre-window save was loaded.
    private var dayWindowStart: SimTime?

    public init(recentCapacity: Int = Ledger.defaultRecentCapacity) {
        precondition(recentCapacity > 0)
        self.balances = [:]
        self.recent = []
        self.totalTransactionCount = 0
        self.recentCapacity = recentCapacity
        self.monthAccumulator = [:]
        self.dayWindows = [:]
        self.dayWindowStart = nil
    }

    public func balance(of airline: AirlineID) -> Money {
        balances[airline] ?? .zero
    }

    /// Posts a transaction. Positive amounts credit the airline, negative
    /// amounts debit it. The single mutation path for money.
    public mutating func post(airline: AirlineID, category: TransactionCategory,
                              amount: Money, at time: SimTime, memo: String? = nil) {
        balances[airline, default: .zero] = balance(of: airline) + amount
        monthAccumulator[airline, default: [:]][category, default: 0] += amount.cents
        totalTransactionCount += 1
        recent.append(Transaction(at: time, airline: airline, category: category,
                                  amount: amount, memo: memo))
        if recent.count > recentCapacity {
            recent.removeFirst(recent.count - recentCapacity)
        }
        recordDay(airline: airline, category: category, cents: amount.cents, at: time)
    }

    /// One airline's money on one game day, if its window can vouch for the
    /// whole day: recording began before the day did, and the day is not
    /// older than the window keeps. Nil means "only the shared `recent` ring
    /// can answer" — a day before the window existed, or one it has dropped.
    /// A covered day with no postings is an empty `LedgerDay`, not nil.
    public func dayTotals(of airline: AirlineID, day: Int64) -> LedgerDay? {
        guard let start = dayWindowStart,
              start.rawMinutes <= day * GameCalendar.minutesPerDay else { return nil }
        let window = dayWindows?[airline] ?? []
        if let newest = window.last, day <= newest.dayIndex - Self.dayWindowLength {
            return nil
        }
        return window.first { $0.dayIndex == day } ?? LedgerDay(dayIndex: day)
    }

    private mutating func recordDay(airline: AirlineID, category: TransactionCategory,
                                    cents: Int64, at time: SimTime) {
        if dayWindowStart == nil { dayWindowStart = time }
        // Moved out and back so the dictionary is uniquely referenced while
        // it is mutated, instead of being copied on every posting.
        var windows = dayWindows ?? [:]
        dayWindows = nil
        let day = time.dayIndex
        if windows[airline, default: []].last?.dayIndex != day {
            windows[airline, default: []].append(LedgerDay(dayIndex: day))
            windows[airline, default: []].removeAll { $0.dayIndex <= day - Self.dayWindowLength }
        }
        let last = windows[airline, default: []].count - 1
        windows[airline, default: []][last].add(category, cents: cents)
        dayWindows = windows
    }

    /// Removes an airline's account (bankruptcy cleanup, Phase 8/10).
    public mutating func closeAccount(_ airline: AirlineID) {
        balances[airline] = nil
        monthAccumulator[airline] = nil
        // The day window stays: it is two days of totals, it stops growing
        // with the postings, and it is what the digest of the airline's last
        // day reads (the shared ring keeps those transactions too).
    }

    /// The current month's signed totals, for a screen that wants "this month
    /// so far" without consuming it. The statement rollup owns the drain; this
    /// is a read.
    public func monthTotals(for airline: AirlineID) -> [TransactionCategory: Int64] {
        monthAccumulator[airline] ?? [:]
    }

    /// Hands over and clears an airline's month accumulator (statement
    /// rollup).
    public mutating func drainMonthAccumulator(for airline: AirlineID)
        -> [TransactionCategory: Int64] {
        let totals = monthAccumulator[airline] ?? [:]
        monthAccumulator[airline] = nil
        return totals
    }
}

/// One airline's postings on one game day, totalled per category and split
/// by sign, so a digest can say both what came in and what went out exactly
/// as it would by summing the individual transactions.
public struct LedgerDay: Equatable, Codable, Sendable {
    public let dayIndex: Int64
    /// Sum of non-negative postings per category, in cents.
    public private(set) var credits: [TransactionCategory: Int64]
    /// Sum of negative postings per category, in cents (negative).
    public private(set) var debits: [TransactionCategory: Int64]

    init(dayIndex: Int64) {
        self.dayIndex = dayIndex
        self.credits = [:]
        self.debits = [:]
    }

    mutating func add(_ category: TransactionCategory, cents: Int64) {
        if cents >= 0 {
            credits[category, default: 0] += cents
        } else {
            debits[category, default: 0] += cents
        }
    }
}

public struct Transaction: Equatable, Codable, Sendable {
    public let at: SimTime
    public let airline: AirlineID
    public let category: TransactionCategory
    /// Signed: positive = money in, negative = money out.
    public let amount: Money
    public let memo: String?

    public init(at: SimTime, airline: AirlineID, category: TransactionCategory,
                amount: Money, memo: String? = nil) {
        self.at = at
        self.airline = airline
        self.category = category
        self.amount = amount
        self.memo = memo
    }
}

/// Grows per phase; cases never repurposed (save compatibility).
public enum TransactionCategory: String, Codable, Sendable, CaseIterable {
    case initialCapital
    case aircraftPurchase
    case aircraftSale
    case leasePayment
    case leasePenalty
    case maintenance
    case fuel
    case airportFees
    case crewCosts
    case ticketRevenue
    case missionReward
    case passengerService
    case salaries
    case overhead
    case loanProceeds
    case loanPrincipal
    case loanInterest
}

// Dictionary-key encoding for statements (SE-0320 default implementation).
extension TransactionCategory: CodingKeyRepresentable {}
