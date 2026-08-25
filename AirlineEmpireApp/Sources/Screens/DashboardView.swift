import SwiftUI
import AirlineEmpireCore

/// The command-center home (docs/CORE_LOOP.md §4): current state at a
/// glance, the ops feed, and the time controls.
struct DashboardView: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AETheme.spacingM) {
                    if let snapshot = controller.snapshot,
                       let dashboard = snapshot.dashboardModel() {
                        header(snapshot: snapshot, dashboard: dashboard)
                        statGrid(dashboard)
                        eventsFeed
                    } else {
                        ProgressView()
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle(controller.snapshot?.dashboardModel()?.airlineName ?? "…")
            .toolbar {
                ToolbarItem(placement: .principal) { SpeedControl() }
            }
        }
    }

    private func header(snapshot: GameState, dashboard: DashboardModel) -> some View {
        AECard {
            HStack {
                VStack(alignment: .leading, spacing: AETheme.spacingXS) {
                    Text(Format.date(snapshot.currentDate))
                        .font(.headline).monospacedDigit()
                    Text("\(Format.clock(snapshot.currentDate)) · \(String(describing: snapshot.currentDate.season)) · era: \(String(describing: dashboard.era))")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: AETheme.spacingXS) {
                    MoneyText(money: dashboard.cash).font(.headline)
                    Text("net worth \(Format.money(dashboard.netWorth))")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                }
            }
        }
    }

    private func statGrid(_ dashboard: DashboardModel) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                  spacing: AETheme.spacingS) {
            StatTile(label: "Fleet", value: "\(dashboard.fleetCount)")
            StatTile(label: "Routes", value: "\(dashboard.routeCount)")
            StatTile(label: "Reputation",
                     value: Format.percent(dashboard.reputationScore))
            StatTile(label: "Last month",
                     value: dashboard.lastMonthNetProfit.map(Format.money) ?? "—",
                     trend: (dashboard.lastMonthNetProfit?.isNegative ?? false)
                         ? .down : .up)
            StatTile(label: "Fuel /t", value: Format.money(dashboard.fuelPricePerTon))
            StatTile(label: "Economy",
                     value: String(format: "%.2f", dashboard.economicIndex),
                     trend: dashboard.economicIndex >= 1 ? .up : .down)
        }
    }

    private var eventsFeed: some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                Text("Operations feed").font(.headline)
                if controller.recentEvents.isEmpty {
                    Text("Quiet skies. Open a route to get moving.")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.mutedText)
                } else {
                    ForEach(Array(controller.recentEvents.suffix(12).reversed()
                        .enumerated()), id: \.offset) { _, event in
                        EventRow(event: event)
                    }
                }
            }
        }
    }
}

/// One feed line per SimEvent; unhandled kinds render nothing rather than
/// noise (curation over completeness).
struct EventRow: View {
    let event: SimEvent

    var body: some View {
        if let text = description {
            HStack(alignment: .top, spacing: AETheme.spacingS) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
                    .frame(width: 16)
                Text(text).font(.subheadline)
                Spacer(minLength: 0)
            }
        }
    }

    private var description: String? {
        switch event.kind {
        case .flightDelayed(_, _, let minutes):
            "Flight delayed \(minutes) min"
        case .flightCancelled:
            "Flight cancelled"
        case .aircraftDelivered:
            "Aircraft delivered"
        case .maintenanceStarted:
            "Aircraft grounded for maintenance"
        case .milestoneReached(let code):
            "Milestone: \(code)"
        case .achievementUnlocked(let code):
            "Achievement: \(code)"
        case .eraAdvanced(let era):
            "New era: \(String(describing: era))"
        case .worldEventStarted(_, let kind):
            worldEventText(kind, started: true)
        case .worldEventForecast(let kind, _):
            worldEventText(kind, started: false)
        case .missionOffered(_, _, _, let reward):
            "Mission offered — reward \(Format.money(reward))"
        case .missionCompleted(_, let reward):
            "Mission complete! \(Format.money(reward))"
        case .statementClosed(_, _, let month, let net):
            "Month \(month) closed: \(Format.money(net))"
        case .airlineCollapsed:
            "An airline has collapsed"
        case .loanTaken(_, let amount, _):
            "Loan drawn: \(Format.money(amount))"
        default:
            nil
        }
    }

    private func worldEventText(_ kind: WorldEventKind, started: Bool) -> String {
        let prefix = started ? "" : "Forecast: "
        switch kind {
        case .fuelShock: return prefix + "fuel market shock"
        case .storm(let region): return prefix + "severe weather over \(String(describing: region))"
        case .airportClosure(let airport): return prefix + "\(airport.raw) closed"
        case .tourismBoom(let region): return prefix + "tourism boom in \(String(describing: region))"
        case .strike: return prefix + "crew strike"
        }
    }

    private var icon: String {
        switch event.kind {
        case .flightDelayed, .flightCancelled: "exclamationmark.triangle"
        case .aircraftDelivered: "airplane.circle"
        case .milestoneReached, .achievementUnlocked, .eraAdvanced: "star"
        case .missionOffered, .missionCompleted: "target"
        case .worldEventStarted, .worldEventForecast: "bolt"
        case .statementClosed: "doc.text"
        default: "circle"
        }
    }
}
