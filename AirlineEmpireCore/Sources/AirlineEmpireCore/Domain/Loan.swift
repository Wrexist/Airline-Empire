import Foundation

/// A term loan with a fixed annuity payment (docs/ECONOMY.md §Phase 8).
public struct Loan: Equatable, Codable, Sendable {
    public var principalRemaining: Money
    /// Annual rate in basis points (fixed at origination).
    public let annualRateBasisPoints: Int
    public var monthlyPayment: Money
    public var monthsRemaining: Int
    public let takenAt: SimTime

    public init(principalRemaining: Money, annualRateBasisPoints: Int,
                monthlyPayment: Money, monthsRemaining: Int, takenAt: SimTime) {
        self.principalRemaining = principalRemaining
        self.annualRateBasisPoints = annualRateBasisPoints
        self.monthlyPayment = monthlyPayment
        self.monthsRemaining = monthsRemaining
        self.takenAt = takenAt
    }

    public var monthlyRate: Double {
        Double(annualRateBasisPoints) / 10_000 / 12
    }

    /// Interest accrued since the last month boundary — or since drawdown,
    /// if that is later — pro rata at the monthly rate. Loan service charges
    /// interest only at month boundaries (EconomySystem), so an early payoff
    /// owes this with the principal; without it, a loan repaid before its
    /// first boundary cost nothing at all.
    public func accruedInterest(at time: SimTime, startYear: Int) -> Money {
        let date = GameCalendar.date(at: time, startYear: startYear)
        let monthStart = GameCalendar.time(year: date.year, month: date.month, day: 1,
                                           startYear: startYear)
        let heldMinutes = (time - max(monthStart, takenAt)).minutes
        guard heldMinutes > 0 else { return .zero }
        let monthMinutes = GameCalendar.monthLengths[date.month - 1] * GameCalendar.minutesPerDay
        return Money(rounding: principalRemaining.asDouble * monthlyRate
            * Double(heldMinutes) / Double(monthMinutes))
    }

    /// The share of the month that closed at `boundary` this loan was held
    /// for: 1 for a loan drawn before that month began, the drawn share for
    /// one drawn during it. Loan service charges interest once, at the
    /// boundary, and used to charge the whole month whatever the draw date —
    /// a loan taken on the 28th cost as much interest as one taken on the
    /// 1st. Early payoff (`accruedInterest`) already pro-rated the same way.
    public func heldFraction(ofMonthEndingAt boundary: SimTime, startYear: Int) -> Double {
        // The month that closed is the one the minute before the boundary
        // falls in.
        let closed = GameCalendar.date(at: SimTime(rawMinutes: boundary.rawMinutes - 1),
                                       startYear: startYear)
        let monthStart = GameCalendar.time(year: closed.year, month: closed.month, day: 1,
                                           startYear: startYear)
        guard takenAt > monthStart else { return 1 }
        let monthMinutes = GameCalendar.monthLengths[closed.month - 1] * GameCalendar.minutesPerDay
        let heldMinutes = (boundary - takenAt).minutes
        return min(1, max(0, Double(heldMinutes) / Double(monthMinutes)))
    }
}

/// Credit math — pure functions so UI quotes exactly what the simulation
/// charges (explainability pillar).
public enum CreditMath {
    /// Fixed annuity payment for a principal over `months` at `monthlyRate`.
    public static func annuityPayment(principal: Money, monthlyRate: Double,
                                      months: Int) -> Money {
        precondition(months > 0)
        guard monthlyRate > 0 else {
            return Money(rounding: principal.asDouble / Double(months))
        }
        let factor = pow(1 + monthlyRate, Double(months))
        return Money(rounding: principal.asDouble * monthlyRate * factor / (factor - 1))
    }

    /// Total assets used for leverage: positive cash + owned fleet book value.
    public static func assets(of airline: AirlineID, state: GameState) -> Money {
        var total = max(.zero, state.ledger.balance(of: airline))
        for aircraft in state.fleet(of: airline) {
            if case .owned(let book) = aircraft.ownership {
                total = total + book
            }
        }
        return total
    }

    public static func totalDebt(of airline: Airline) -> Money {
        airline.loans.reduce(.zero) { $0 + $1.principalRemaining }
    }

    /// Debt ratio after adding `additional` debt; 1.0 when assets are zero.
    public static func debtRatio(of airline: Airline, state: GameState,
                                 additional: Money = .zero) -> Double {
        let debt = (totalDebt(of: airline) + additional).asDouble
        let assetBase = assets(of: airline.id, state: state).asDouble + additional.asDouble
        guard assetBase > 0 else { return 1.0 }
        return min(1.0, debt / assetBase)
    }

    /// Offered annual rate in basis points: base + leverage-squared spread.
    public static func offeredRateBasisPoints(debtRatio: Double,
                                              tuning: FinanceTuning) -> Int {
        let spread = Double(tuning.spreadBaseBasisPoints)
            + Double(tuning.spreadLeverageBasisPoints) * debtRatio * debtRatio
        return tuning.baseLoanRateBasisPoints + Int(spread.rounded())
    }
}
