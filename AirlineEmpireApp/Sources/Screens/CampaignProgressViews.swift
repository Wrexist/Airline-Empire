import SwiftUI
import AirlineEmpireCore

struct NextEraBriefing: View {
    @Environment(GameController.self) private var controller
    @Environment(Entitlements.self) private var entitlements

    var body: some View {
        if let model = controller.progressionModel, let next = model.nextEra {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                NavigationLink { ProgressionView() } label: {
                    AECard {
                        VStack(alignment: .leading, spacing: AETheme.spacingS) {
                            Text("Towards \(Vocab.era(next))").font(.headline)
                            ProgressView(value: model.nextEraProgress)
                            if let requirement = model.nextEraRequirements.first(where: { !$0.isMet }) {
                                Text(Vocab.requirement(requirement.kind)).font(.subheadline)
                                Text(Vocab.requirementValue(requirement))
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(next > controller.eraCeiling
                                     ? "Requirements met. Pro unlocks the next era."
                                     : "Requirements met. Your next daily review can unlock this era.")
                                    .font(.subheadline)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ae-next-era-guidance")
                // Beside the card, not inside it: the card is one link, and
                // a button in a link's label is a tap that does two things.
                if next > controller.eraCeiling, !entitlements.isPro {
                    EraProOffer(era: next)
                }
            }
        }
    }
}

/// How an era past the free ceiling opens, shown where that era is
/// described (docs/MONETIZATION.md §4).
///
/// Pro is more world, so this says so once and plainly: one line that the
/// free game carries on, and one small button. No countdown, no shortcut —
/// the requirements still have to be met with Pro as without it. Callers
/// show it only to a player without Pro.
struct EraProOffer: View {
    @Environment(Entitlements.self) private var entitlements
    let era: Era

    var body: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingXS) {
            Text("The \(Vocab.era(era)) era opens with Pro. Your airline keeps flying free either way.")
                .font(.caption)
                .foregroundStyle(AETheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                entitlements.present(.eraCeiling)
            } label: {
                Label("Open it with Pro", systemImage: "crown.fill")
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(AETheme.ember)
            .accessibilityIdentifier("ae-era-pro-offer")
        }
    }
}

struct SessionReportCard: View {
    let report: SessionReport
    let nextMove: String?

    var body: some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                Label("\(report.airlineName) saved", systemImage: "checkmark.circle")
                    .font(.headline)
                Text("Since you opened this campaign")
                    .font(.caption).foregroundStyle(.secondary)
                // Grouped: a long session carries tens of thousands of
                // passengers, and "48213" read as a code, not a count.
                LabeledContent("Game days", value: Format.count(report.days))
                LabeledContent("Flights completed", value: Format.count(report.flights))
                LabeledContent("Passengers carried", value: Format.count(report.passengers))
                LabeledContent("Cash change", value: Format.money(report.cashChange))
                LabeledContent("Net routes added", value: "\(report.routeChange)")
                LabeledContent("Net aircraft added", value: "\(report.aircraftChange)")
                Text("Cash change includes aircraft purchases, loans and operating costs. It is not profit.")
                    .font(.caption).foregroundStyle(.secondary)
                if let nextMove {
                    Divider()
                    Text("Next time: \(nextMove)").font(.subheadline)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("ae-session-report")
    }
}
