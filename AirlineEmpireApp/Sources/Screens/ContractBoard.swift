import SwiftUI
import AirlineEmpireCore

struct ContractBoard: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        if let state = controller.snapshot, state.progression.hasMilestone("firstFlight") {
            let offers = ContractOffer.offers(in: state)
            AECard {
                VStack(alignment: .leading, spacing: AETheme.spacingS) {
                    Text("Optional contracts").font(.headline)
                    Text("Choose one per calendar month. Complete it within 28 game days for a bonus. There is no deposit or penalty for missing the target.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(offers, id: \.choice) { offer in
                        VStack(alignment: .leading, spacing: AETheme.spacingXS) {
                            Text(title(offer.kind)).font(.subheadline.weight(.semibold))
                            Text("Completion bonus: \(Format.money(offer.reward))")
                                .font(.caption)
                            ConfirmableButton(title: "Accept this contract?",
                                              message: "\(title(offer.kind)) in 28 game days. Earn \(Format.money(offer.reward)). Only activity after acceptance counts. This uses this month's offer.",
                                              confirmTitle: "Accept contract", role: nil,
                                              action: { controller.submit(AcceptContractCommand(choice: offer.choice)) }) {
                                Text("Accept \(offer.choice == .flights ? "flight" : "passenger") contract")
                                    .frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("ae-contract-\(offer.choice.rawValue)")
                        }
                    }
                    if offers.isEmpty {
                        Text("Finish the active contract and return in a new calendar month for another offer.")
                            .font(.subheadline)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func title(_ kind: MissionKind) -> String {
        switch kind {
        case .flightContract(let target): "Complete \(Format.count(target)) flights"
        case .passengerContract(let target): "Carry \(Format.count(target)) passengers"
        case .boomRush: "Tourism opportunity"
        }
    }
}
