import SwiftUI
import AirlineEmpireCore

/// "While you were away" (AE-050, docs/ROADMAP_DIRECTION_II.md Phase 29): the
/// account of an offline catch-up, shown once when the player comes back.
///
/// Built from the evening digest's parts — the same panel, badges, money
/// rows, "Why?" breakdown and event rows — because it is the same kind of
/// thing: what happened, and why the cash moved. Every number comes from
/// Core's `OfflineCatchUpReport`; this view only formats. It leads with the
/// hub, because a building that opened while the player was away is the news
/// they will care about first (docs/HUB_PROGRESSION_PLAN.md §6.4).
struct AwayReportSheet: View {
    let report: OfflineCatchUpReport
    @Environment(GameController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AETheme.spacingM) {
                    header
                    if !hubLines.isEmpty { hubPanel }
                    if report.ticksRun > 0 { moneyPanel }
                    if let note { notePanel(note) }
                    if !report.notableEvents.isEmpty { newsPanel }
                }
                .padding(AETheme.spacingM)
            }
            .navigationTitle("While you were away")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") { dismiss() }
                        .accessibilityIdentifier("ae-away-continue")
                }
            }
            // The event rows lead to the route or aircraft they are about.
            .navigationDestination(for: RouteID.self) { RouteDetailView(routeID: $0) }
            .navigationDestination(for: AircraftID.self) { AircraftDetailView(aircraftID: $0) }
        }
        .accessibilityIdentifier("ae-away-report")
        .aeSheetFeedback()
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("You were away \(Self.realAbsence(report.awaySeconds)).")
                .font(.headline)
            if report.ticksRun > 0 {
                Text("\(Self.gameTime(report.gameMinutesAdvanced)) passed: \(Format.longDate(report.startDate)) \(Format.clock(report.startDate)) to \(Format.longDate(report.endDate)) \(Format.clock(report.endDate)).")
                    .font(.subheadline)
                    .foregroundStyle(AETheme.mutedText)
            } else {
                Text("The world waited for you.")
                    .font(.subheadline)
                    .foregroundStyle(AETheme.mutedText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    // MARK: The hub

    private struct HubLine: Identifiable {
        let id: String
        let icon: String
        let text: String
        let airport: AirportCode
    }

    /// Openings and statuses first, then the works still going, so "the
    /// hangar opened" is never pushed under "the crew base is half built".
    private var hubLines: [HubLine] {
        var lines: [HubLine] = []
        for (index, event) in report.hubEvents.enumerated() {
            switch event.kind {
            case .facilityOpened(_, let airport, let service, let level):
                lines.append(HubLine(
                    id: "opened-\(index)", icon: "building.2.fill",
                    text: "\(HubFacilityKind(service: service).buildingName(level)) opened at \(airport.raw)",
                    airport: airport))
            case .hubStatusRaised(_, let airport, let status):
                lines.append(HubLine(
                    id: "status-\(index)", icon: "flag.fill",
                    text: "\(airport.raw) is now your \(status.title.lowercased())",
                    airport: airport))
            default:
                continue
            }
        }
        if let snapshot = controller.snapshot, let player = snapshot.playerAirline {
            let now = snapshot.clock.now
            for build in (player.facilityConstructions ?? []).sorted(by: { $0.completesAt < $1.completesAt }) {
                let minutes = max(0, (build.completesAt - now).minutes)
                let days = Int((minutes + GameCalendar.minutesPerDay - 1) / GameCalendar.minutesPerDay)
                lines.append(HubLine(
                    id: "works-\(build.airport.raw)-\(build.service)", icon: "hammer.fill",
                    text: "\(HubFacilityKind(service: build.service).buildingName(build.level)) at \(build.airport.raw): opens in \(Format.days(max(1, days)))",
                    airport: build.airport))
            }
        }
        return lines
    }

    private var hubPanel: some View {
        AEPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                Text("Your hubs").font(.headline)
                ForEach(hubLines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: AETheme.spacingS) {
                        Image(systemName: line.icon)
                            .font(.caption)
                            .foregroundStyle(AETheme.accent)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text(line.text)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let airport = hubLines.first?.airport {
                    // The ceremony of anything that opened plays when the hub
                    // is next opened (§6.5), so the button is the way to it.
                    // The hub itself needs iOS 18 (`GameShell`).
                    if #available(iOS 18.0, *) {
                        Button("See \(airport.raw)") { openHub(airport) }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("ae-away-open-hub")
                    }
                }
            }
        }
        .accessibilityIdentifier("ae-away-hub")
    }

    /// The hub is a full-screen cover on the shell, which cannot rise while
    /// this sheet is still on its way down.
    private func openHub(_ airport: AirportCode) {
        controller.dismissAwayReport()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            controller.openHub(airport)
        }
    }

    // MARK: Money

    private var moneyPanel: some View {
        AEPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your airline").font(.headline)
                    Spacer()
                    MoneyText(money: report.cashChange)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(report.cashChange.isNegative ? AETheme.negative : AETheme.positive)
                }
                HStack(spacing: AETheme.spacingS) {
                    AEBadge(text: "\(Format.count(report.flightsCompleted)) flown",
                            color: AETheme.positive, icon: "airplane")
                    if report.flightsCancelled > 0 {
                        AEBadge(text: "\(report.flightsCancelled) cancelled",
                                color: AETheme.negative, icon: "exclamationmark.triangle")
                    }
                    if report.maintenanceChecks > 0 {
                        AEBadge(text: report.maintenanceChecks == 1 ? "1 check" : "\(report.maintenanceChecks) checks",
                                color: AETheme.caution, icon: "wrench")
                    }
                }
                Text("\(Format.count(report.passengersCarried)) passengers flew with you.")
                    .font(.subheadline)
                    .foregroundStyle(AETheme.mutedText)
                row("Earned", report.revenue)
                row("Spent", report.expenses)
                Button(expanded ? "Hide detail" : "Why?") {
                    withAnimation(reduceMotion ? nil : AEMotion.selection) { expanded.toggle() }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityIdentifier("ae-away-why")
                if expanded {
                    ForEach(sortedCategories, id: \.0) { category, amount in
                        row(DigestCard.label(for: category), amount)
                    }
                }
            }
        }
        .accessibilityIdentifier("ae-away-money")
    }

    private func row(_ title: String, _ amount: Money) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            MoneyText(money: amount).font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }

    /// Same order as the digest: largest credit first, largest cost last.
    private var sortedCategories: [(TransactionCategory, Money)] {
        report.byCategory
            .map { ($0.key, $0.value) }
            .sorted { $0.1.cents != $1.1.cents ? $0.1.cents > $1.1.cents
                                               : $0.0.rawValue < $1.0.rawValue }
    }

    // MARK: Why it stopped

    private var note: String? {
        switch report.stopReason {
        case .solvency:
            return "Time stopped early: your cash is at the overdraft floor. The world waited rather than let the administration countdown run without you. Finance has your options."
        case .deadline:
            return "Time stopped early: a mission or contract you hold is about to close. Its last day is yours to play."
        case .airlineInactive:
            return "Nothing ran: your airline is not operating."
        case nil:
            guard report.wasCapped else { return nil }
            let cap = controller.catalog?.tuning.offline.capGameDays
                ?? OfflineCatchUpTuning.standard.capGameDays
            return "Catch-up covers at most \(Format.days(cap)) of game time, however long you are away."
        }
    }

    private func notePanel(_ text: String) -> some View {
        AEPanel {
            HStack(alignment: .firstTextBaseline, spacing: AETheme.spacingS) {
                Image(systemName: report.stopReason == nil ? "clock" : "pause.circle")
                    .foregroundStyle(report.stopReason == .solvency ? AETheme.caution : AETheme.accent)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("ae-away-note")
    }

    // MARK: News

    private var newsPanel: some View {
        AEPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                Text("News").font(.headline)
                ForEach(Array(report.notableEvents.suffix(12).reversed().enumerated()),
                        id: \.offset) { _, event in
                    EventRow(event: event, player: controller.snapshot?.playerAirline?.id,
                             snapshot: controller.snapshot)
                }
            }
        }
    }

    // MARK: Phrases

    /// "40 minutes", "9 hours", "3 days".
    static func realAbsence(_ seconds: Double) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes < 120 { return minutes == 1 ? "1 minute" : "\(minutes) minutes" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours) hours" }
        return Format.days(hours / 24)
    }

    /// "40 min", "6h", "2 days, 3 hours" of game time.
    static func gameTime(_ minutes: Int64) -> String {
        let days = Int(minutes / GameCalendar.minutesPerDay)
        guard days > 0 else { return Format.duration(minutes: minutes) }
        let hours = Int((minutes % GameCalendar.minutesPerDay) / 60)
        guard hours > 0 else { return Format.days(days) }
        return "\(Format.days(days)), \(hours == 1 ? "1 hour" : "\(hours) hours")"
    }
}
