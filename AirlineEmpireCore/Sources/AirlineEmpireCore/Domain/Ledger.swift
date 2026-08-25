/// The financial spine (docs/ARCHITECTURE.md §5): every money movement is a
/// categorized transaction against an airline's account. Balances are
/// authoritative; the recent-transaction ring gives the UI its "where did my
/// money go" trail (full statements/rollups arrive in Phase 8).
public struct Ledger: Equatable, Codable, Sendable {
    public static let defaultRecentCapacity = 1024

    public private(set) var balances: [AirlineID: Money]
    public private(set) var recent: [Transaction]
    public private(set) var totalTransactionCount: Int64
    public private(set) var recentCapacity: Int
    /// Signed cents accumulated per category since the last statement
    /// rollup. Fed at post time so statements never depend on the bounded
    /// `recent` ring.
    public private(set) var monthAccumulator: [AirlineID: [TransactionCategory: Int64]]

    public init(recentCapacity: Int = Ledger.defaultRecentCapacity) {
        precondition(recentCapacity > 0)
        self.balances = [:]
        self.recent = []
        self.totalTransactionCount = 0
        self.recentCapacity = recentCapacity
        self.monthAccumulator = [:]
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
    }

    /// Removes an airline's account (bankruptcy cleanup, Phase 8/10).
    public mutating func closeAccount(_ airline: AirlineID) {
        balances[airline] = nil
        monthAccumulator[airline] = nil
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
    case salaries
    case overhead
    case loanProceeds
    case loanPrincipal
    case loanInterest
}

// Dictionary-key encoding for statements (SE-0320 default implementation).
extension TransactionCategory: CodingKeyRepresentable {}
