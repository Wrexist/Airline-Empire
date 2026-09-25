/// The money story, split into the three questions a player actually asks:
/// what the airline earned, what moved its cash, and what it must find every
/// month whether or not it flies.
///
/// Everything here is derived from the ledger and the closed statements — no
/// history is reconstructed beyond the retained statement coverage, and cash
/// movement is never presented as profit. `MonthFlow` separates operating,
/// financing and capital movements precisely so a screen can say "cash change
/// is not profit" with the numbers in front of it.

/// One month's cash movement by category, split by P&L classification.
public struct MonthFlow: Equatable, Sendable {
    /// Signed cents per category (credits positive).
    public let byCategory: [TransactionCategory: Money]
    public let operatingRevenue: Money
    /// Negative; the magnitude a screen shows as a cost.
    public let operatingExpenses: Money
    /// Loan interest — below the operating line.
    public let financingCost: Money
    /// Balance-sheet movements: aircraft, loans and founding capital. Real
    /// cash, but not profit.
    public let capitalMovements: Money

    public init(byCategory: [TransactionCategory: Money],
                operatingRevenue: Money, operatingExpenses: Money,
                financingCost: Money, capitalMovements: Money) {
        self.byCategory = byCategory
        self.operatingRevenue = operatingRevenue
        self.operatingExpenses = operatingExpenses
        self.financingCost = financingCost
        self.capitalMovements = capitalMovements
    }

    public var operatingProfit: Money { operatingRevenue + operatingExpenses }

    /// False when the only postings this month were capital or financing —
    /// an airline that has taken capital but not yet flown.
    public var hasOperatingActivity: Bool {
        operatingRevenue != .zero || operatingExpenses != .zero
    }

    /// Every category summed: the change in cash over the month, which is
    /// profit only when nothing capital moved.
    public var netCashChange: Money {
        operatingRevenue + operatingExpenses + financingCost + capitalMovements
    }

    /// Nil when the airline has posted nothing since the last month boundary.
    public static func make(_ totals: [TransactionCategory: Int64]) -> MonthFlow? {
        guard !totals.isEmpty else { return nil }
        var byCategory: [TransactionCategory: Money] = [:]
        var revenue = Money.zero
        var expenses = Money.zero
        var financing = Money.zero
        var capital = Money.zero
        for (category, cents) in totals {
            let money = Money(cents: cents)
            byCategory[category] = money
            switch category.classification {
            case .operatingRevenue: revenue = revenue + money
            case .operatingExpense: expenses = expenses + money
            case .financing: financing = financing + money
            case .capital: capital = capital + money
            }
        }
        return MonthFlow(byCategory: byCategory, operatingRevenue: revenue,
                         operatingExpenses: expenses, financingCost: financing,
                         capitalMovements: capital)
    }
}

/// What the airline must pay every month at today's size and contracts.
///
/// Leases, loan payments and station services are exact recurring charges the
/// simulation will post at the next boundary. Payroll is charged from the
/// fleet and route counts at that boundary, so it is an estimate at today's
/// count — labelled as one. Loan payments include principal, which is a
/// balance-sheet movement, not a cost.
public struct RecurringCommitments: Equatable, Sendable {
    public let leases: Money
    public let loanPayments: Money
    public let stations: Money
    public let stationsByAirport: [AirportCode: Money]
    /// Charged from fleet and route counts at the month boundary.
    public let payroll: Money
    public let overhead: Money

    public init(leases: Money, loanPayments: Money, stations: Money,
                stationsByAirport: [AirportCode: Money], payroll: Money,
                overhead: Money) {
        self.leases = leases
        self.loanPayments = loanPayments
        self.stations = stations
        self.stationsByAirport = stationsByAirport
        self.payroll = payroll
        self.overhead = overhead
    }

    public var monthlyTotal: Money {
        leases + loanPayments + stations + payroll + overhead
    }

    public static func make(airline: AirlineID, state: GameState,
                            catalog: ContentCatalog) -> RecurringCommitments {
        let tuning = catalog.tuning.finance
        var leases = Money.zero
        for aircraft in state.fleet(of: airline) {
            if case .leased(let rate, _) = aircraft.ownership { leases = leases + rate }
        }
        let loanPayments = (state.airlines[airline]?.loans ?? [])
            .reduce(Money.zero) { $0 + $1.monthlyPayment }
        var stations = Money.zero
        var byAirport: [AirportCode: Money] = [:]
        let serviceCommitments = state.airlines[airline]?
            .airportServiceCommitments(tuning: catalog.tuning.airportServices) ?? []
        for commitment in serviceCommitments {
            stations = stations + commitment.monthly
            byAirport[commitment.airport] = commitment.monthly
        }
        // Aircraft still on order draw no payroll (EconomySystem), so the
        // commitment the screen quotes leaves them out too.
        let crewed = state.fleet(of: airline).filter { !$0.status.isOnOrder }.count
        let payroll = tuning.payrollPerAircraftMonthly * Int64(crewed)
            + tuning.payrollPerRouteMonthly * Int64(state.routes(of: airline).count)
        return RecurringCommitments(
            leases: leases, loanPayments: loanPayments, stations: stations,
            stationsByAirport: byAirport, payroll: payroll,
            overhead: tuning.overheadBaseMonthly)
    }
}

/// The Finance screen's three groups in one value: this month so far, the last
/// closed statement, and the recurring commitments.
public struct FinanceBreakdown: Equatable, Sendable {
    /// Since the last month boundary; nil when nothing has posted.
    public let monthToDate: MonthFlow?
    /// The most recent closed month, if one has closed.
    public let latestStatement: MonthlyStatement?
    public let recurring: RecurringCommitments

    public init(monthToDate: MonthFlow?, latestStatement: MonthlyStatement?,
                recurring: RecurringCommitments) {
        self.monthToDate = monthToDate
        self.latestStatement = latestStatement
        self.recurring = recurring
    }

    /// True when no month has closed and nothing has posted since founding —
    /// the first day of a new airline.
    public var hasNothingToShow: Bool {
        monthToDate == nil && latestStatement == nil
    }
}

extension GameState {
    /// The Finance read model. Pure; the same ledger and statements the
    /// simulation writes.
    public func financeBreakdown(for airline: AirlineID,
                                 catalog: ContentCatalog) -> FinanceBreakdown {
        FinanceBreakdown(
            monthToDate: MonthFlow.make(ledger.monthTotals(for: airline)),
            latestStatement: finance.byAirline[airline]?.latest,
            recurring: RecurringCommitments.make(airline: airline, state: self,
                                                 catalog: catalog))
    }
}
