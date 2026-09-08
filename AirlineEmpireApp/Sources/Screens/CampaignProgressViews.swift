import SwiftUI
import AirlineEmpireCore

struct NextEraBriefing: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        if let model = controller.progressionModel, let next = model.nextEra {
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
                LabeledContent("Game days", value: "\(report.days)")
                LabeledContent("Flights completed", value: "\(report.flights)")
                LabeledContent("Passengers carried", value: "\(report.passengers)")
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
