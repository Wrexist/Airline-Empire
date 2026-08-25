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
