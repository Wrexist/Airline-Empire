import SwiftUI
import AirlineEmpireCore

struct RescueOfferCard: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        if let state = controller.snapshot, let catalog = controller.catalog,
           let offer = RescueOffer.available(in: state, catalog: catalog) {
            AECard {
                VStack(alignment: .leading, spacing: AETheme.spacingS) {
                    Text("An investor offers a lifeline").font(.headline)
                    Text("Borrow \(Format.money(offer.principal)) at 15% annual interest for 24 months.")
                    Text("Monthly repayment: \(Format.money(offer.monthlyPayment)). You can repay early in Finance.")
                    Text("This is debt, not a gift. It buys time to repair your airline. Administration and bankruptcy still apply if you keep losing money. This offer is available once, before your first administration.")
                        .font(.caption).foregroundStyle(.secondary)
                    ConfirmableButton(title: "Accept rescue financing?",
                                      message: "Borrow \(Format.money(offer.principal)). Pay \(Format.money(offer.monthlyPayment)) per month for 24 months at 15% annual interest.",
                                      confirmTitle: "Accept financing", role: nil,
                                      action: { controller.submit(DecideRescueCommand(accept: true)) }) {
                        Text("Accept financing").frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("ae-rescue-accept")
                    ConfirmableButton(title: "Decline this rescue?",
                                      message: "The investor will not offer again. Your airline can still recover through its operations, asset sales or ordinary loans.",
                                      confirmTitle: "Decline offer", role: .destructive,
                                      action: { controller.submit(DecideRescueCommand(accept: false)) }) {
                        Text("Decline offer").frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("ae-rescue-decline")
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("ae-rescue-offer")
        }
    }
}
