/// Rescue financing uses the existing loan payment, early-payoff and
/// administration rules. It never grants equity, free money or immunity.
public struct RescueOffer: Equatable, Sendable {
    public let principal: Money
    public let monthlyPayment: Money
    public static let annualRateBasisPoints = 1_500
    public static let termMonths = 24

    public static func available(in state: GameState, catalog: ContentCatalog) -> RescueOffer? {
        guard let player = state.playerAirline, player.status == .active,
              player.administrationCount == 0, player.rescueDecision == .unreviewed,
              player.daysInsolvent > 0 else { return nil }
        let cash = state.ledger.balance(of: player.id)
        guard cash < Money(cents: catalog.tuning.finance.overdraftFloorCents),
              cash >= .dollars(-18_000_000) else { return nil }
        let principal = max(.dollars(5_000_000), .dollars(2_000_000) - cash)
        let payment = CreditMath.annuityPayment(
            principal: principal,
            monthlyRate: Double(annualRateBasisPoints) / 10_000 / 12,
            months: termMonths)
        return RescueOffer(principal: principal, monthlyPayment: payment)
    }
}

public struct DecideRescueCommand: Command, Equatable {
    public static let name = "decideRescue"
    public let accept: Bool
    public init(accept: Bool) { self.accept = accept }

    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard RescueOffer.available(in: state, catalog: catalog) != nil else {
            return CommandRejection(code: "finance.rescueUnavailable",
                                    message: "This rescue offer is no longer available.")
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        guard var player = state.playerAirline,
              let offer = RescueOffer.available(in: state, catalog: context.catalog) else { return }
        player.rescueDecision = accept ? .accepted : .declined
        if accept {
            player.loans.append(Loan(
                principalRemaining: offer.principal,
                annualRateBasisPoints: RescueOffer.annualRateBasisPoints,
                monthlyPayment: offer.monthlyPayment,
                monthsRemaining: RescueOffer.termMonths, takenAt: context.current))
            player.daysInsolvent = 0
            state.ledger.post(airline: player.id, category: .loanProceeds,
                              amount: offer.principal, at: context.current,
                              memo: "One-time investor rescue financing")
            state.progression.counters.loansTaken += 1
            context.emit(.loanTaken(airline: player.id, amount: offer.principal,
                                   rateBasisPoints: RescueOffer.annualRateBasisPoints))
        }
        state.airlines[player.id] = player
    }
}
