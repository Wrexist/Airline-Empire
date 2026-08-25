/// Monthly financial statements per airline (docs/ECONOMY.md §Phase 8).
/// Built by `StatementRollupSystem` from the ledger's month accumulator;
/// bounded history (ring) + lifetime totals keep saves small forever.
public struct FinanceState: Equatable, Codable, Sendable {
    public var byAirline: [AirlineID: AirlineFinance]

    public init(byAirline: [AirlineID: AirlineFinance] = [:]) {
        self.byAirline = byAirline
    }

    public mutating func append(_ statement: MonthlyStatement, for airline: AirlineID,
                                keeping historyMonths: Int) {
        var finance = byAirline[airline] ?? AirlineFinance()
        finance.lifetimeOperatingProfit = finance.lifetimeOperatingProfit
            + statement.operatingProfit
        finance.lifetimeNetProfit = finance.lifetimeNetProfit + statement.netProfit
        finance.statements.append(statement)
        if finance.statements.count > historyMonths {
            finance.statements.removeFirst(finance.statements.count - historyMonths)
        }
        byAirline[airline] = finance
    }
}

public struct AirlineFinance: Equatable, Codable, Sendable {
    /// Newest last; bounded to `statementHistoryMonths`.
    public var statements: [MonthlyStatement]
    public var lifetimeOperatingProfit: Money
    public var lifetimeNetProfit: Money

    public init(statements: [MonthlyStatement] = [],
                lifetimeOperatingProfit: Money = .zero,
                lifetimeNetProfit: Money = .zero) {
        self.statements = statements
        self.lifetimeOperatingProfit = lifetimeOperatingProfit
        self.lifetimeNetProfit = lifetimeNetProfit
    }

    public var latest: MonthlyStatement? { statements.last }
}

public struct MonthlyStatement: Equatable, Codable, Sendable {
    public let year: Int
    public let month: Int
    /// Signed cents per category (credits positive).
    public let byCategory: [TransactionCategory: Int64]

    public init(year: Int, month: Int, byCategory: [TransactionCategory: Int64]) {
        self.year = year
        self.month = month
        self.byCategory = byCategory
    }

    public func total(_ category: TransactionCategory) -> Money {
        Money(cents: byCategory[category] ?? 0)
    }

    public var operatingRevenue: Money {
        sum(where: { $0.classification == .operatingRevenue })
    }

    public var operatingExpenses: Money {
        sum(where: { $0.classification == .operatingExpense })
    }

    public var operatingProfit: Money {
        operatingRevenue + operatingExpenses // expenses are negative
    }

    public var financingCost: Money {
        sum(where: { $0.classification == .financing })
    }

    public var netProfit: Money {
        operatingProfit + financingCost
    }

    private func sum(where include: (TransactionCategory) -> Bool) -> Money {
        var cents: Int64 = 0
        for (category, amount) in byCategory where include(category) {
            cents += amount
        }
        return Money(cents: cents)
    }
}

/// P&L classification of every money category. Exhaustive switch: adding a
/// category without classifying it is a compile error — the statement can
/// never silently mis-bucket money.
public enum CategoryClassification: Sendable {
    case operatingRevenue
    case operatingExpense
    case financing
    /// Balance-sheet movements excluded from P&L.
    case capital
}

extension TransactionCategory {
    public var classification: CategoryClassification {
        switch self {
        case .ticketRevenue:
            .operatingRevenue
        case .fuel, .airportFees, .crewCosts, .maintenance, .leasePayment,
             .leasePenalty, .salaries, .overhead:
            .operatingExpense
        case .loanInterest:
            .financing
        case .initialCapital, .aircraftPurchase, .aircraftSale, .loanProceeds,
             .loanPrincipal:
            .capital
        }
    }
}
