import SwiftUI

/// Inline feedback works inside the paywall and inside Settings sheets.
struct PurchaseFeedback: View {
    @Environment(Entitlements.self) private var entitlements

    var body: some View {
        if let outcome = entitlements.lastOutcome {
            VStack(alignment: .leading, spacing: 8) {
                Text(message(outcome))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ae-purchase-feedback")
                Button("Dismiss") { entitlements.lastOutcome = nil }
                    .font(.callout.weight(.semibold))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func message(_ outcome: Entitlements.Outcome) -> String {
        switch outcome {
        case .purchased: "Pro is unlocked. Thank you for supporting Airline Empire."
        case .restored: "Your Pro purchase has been restored."
        case .nothingToRestore:
            "No previous purchase was found for this Apple Account. Check the account used to buy Pro, then try Restore purchases again."
        case .pending:
            "Your purchase is awaiting approval or payment confirmation. You can keep playing. Pro unlocks when Apple confirms it."
        case .failed(let reason): reason
        }
    }
}
