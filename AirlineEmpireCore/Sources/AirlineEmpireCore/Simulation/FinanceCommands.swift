/// Finance commands (Phase 8).

public struct TakeLoanCommand: Command, Equatable {
    public static let name = "takeLoan"

    public let airline: AirlineID
    public let amount: Money
    public let termMonths: Int

    public init(airline: AirlineID, amount: Money, termMonths: Int) {
        self.airline = airline
        self.amount = amount
        self.termMonths = termMonths
    }

    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard let borrower = state.airlines[airline], borrower.status == .active else {
            return CommandRejection(code: "finance.unknownAirline", message: "Unknown airline")
        }
        let tuning = catalog.tuning.finance
        if amount < Money(cents: tuning.minLoanCents) {
            return CommandRejection(code: "finance.loanTooSmall",
                                    message: "Minimum loan is \(tuning.minLoanCents / 100)")
        }
        if !(6...tuning.maxLoanTermMonths).contains(termMonths) {
            return CommandRejection(code: "finance.badTerm",
                                    message: "Loan terms run 6–\(tuning.maxLoanTermMonths) months")
        }
        if borrower.loans.count >= tuning.maxConcurrentLoans {
            return CommandRejection(code: "finance.tooManyLoans",
                                    message: "At most \(tuning.maxConcurrentLoans) loans at once")
        }
        let ratio = CreditMath.debtRatio(of: borrower, state: state, additional: amount)
        if ratio > tuning.maxDebtRatio {
            return CommandRejection(code: "finance.overLeveraged",
                                    message: "Lenders refuse: debt would reach \(Int(ratio * 100))% of assets")
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        var borrower = state.airlines[airline]!
        let tuning = context.catalog.tuning.finance
        let ratio = CreditMath.debtRatio(of: borrower, state: state, additional: amount)
        let rate = CreditMath.offeredRateBasisPoints(debtRatio: ratio, tuning: tuning)
        let monthlyRate = Double(rate) / 10_000 / 12
        let payment = CreditMath.annuityPayment(principal: amount,
                                                monthlyRate: monthlyRate,
                                                months: termMonths)
        borrower.loans.append(Loan(principalRemaining: amount,
                                   annualRateBasisPoints: rate,
                                   monthlyPayment: payment,
                                   monthsRemaining: termMonths,
                                   takenAt: context.current))
        state.airlines[airline] = borrower
        state.ledger.post(airline: airline, category: .loanProceeds, amount: amount,
                          at: context.current, memo: "Loan drawdown")
        if state.isPlayer(airline) {
            state.progression.counters.loansTaken += 1
        }
        context.emit(.loanTaken(airline: airline, amount: amount, rateBasisPoints: rate))
    }
}

/// Early full payoff of one loan (index into the airline's loan list).
public struct RepayLoanCommand: Command, Equatable {
    public static let name = "repayLoan"

    public let airline: AirlineID
    public let loanIndex: Int

    public init(airline: AirlineID, loanIndex: Int) {
        self.airline = airline
        self.loanIndex = loanIndex
    }

    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard let borrower = state.airlines[airline] else {
            return CommandRejection(code: "finance.unknownAirline", message: "Unknown airline")
        }
        guard borrower.loans.indices.contains(loanIndex) else {
            return CommandRejection(code: "finance.noSuchLoan", message: "No such loan")
        }
        let owed = borrower.loans[loanIndex].principalRemaining
        if state.ledger.balance(of: airline) < owed {
            return CommandRejection(code: "finance.insufficientFunds",
                                    message: "Full payoff needs \(owed.cents / 100)")
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        var borrower = state.airlines[airline]!
        let loan = borrower.loans.remove(at: loanIndex)
        state.airlines[airline] = borrower
        state.ledger.post(airline: airline, category: .loanPrincipal,
                          amount: -loan.principalRemaining, at: context.current,
                          memo: "Early payoff")
        context.emit(.loanRepaidEarly(airline: airline, amount: loan.principalRemaining))
    }
}
