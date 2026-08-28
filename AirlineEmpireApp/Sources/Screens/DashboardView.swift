import SwiftUI
import AirlineEmpireCore

/// The command-center home (docs/CORE_LOOP.md §4): current state at a
/// glance, the ops feed, and the time controls.
struct DashboardView: View {
    @Environment(GameController.self) private var controller
    @State private var guidedRoute: FirstRouteSuggestion?
    @State private var showingGuidedSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AETheme.spacingM) {
                    if let snapshot = controller.snapshot,
                       let dashboard = snapshot.dashboardModel() {
                        header(snapshot: snapshot, dashboard: dashboard)
                        if let catalog = controller.catalog,
                           let onboarding = snapshot.onboardingModel(catalog: catalog),
                           !onboarding.isComplete {
                            OnboardingCard(model: onboarding) { suggestion in
                                guidedRoute = suggestion
                                showingGuidedSheet = true
                            }
                        }
                        // The evening digest (docs/CORE_LOOP.md §3): yesterday
                        // closed, with its reasons. Rendered from the snapshot
                        // so fast-forward updates it instead of queueing modals.
                        //
                        // `yesterday` is nil on the first day, because there is
                        // no yesterday to summarize. Core also refuses a
                        // negative day now (BUG-008) — this states the intent
                        // at the call site rather than leaning on that.
                        if let player = snapshot.playerAirline?.id,
                           let yesterday = snapshot.clock.now.previousDayIndex,
                           let digest = snapshot.dailyDigest(for: player, day: yesterday),
                           digest.hasContent {
                            DigestCard(digest: digest, player: player)
                        }
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
            .sheet(isPresented: $showingGuidedSheet) {
                if let guidedRoute {
                    OpenRouteSheet(suggestion: guidedRoute)
                } else {
                    OpenRouteSheet()
                }
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
                        EventRow(event: event,
                                 player: controller.snapshot?.playerAirline?.id)
                    }
                }
            }
        }
    }
}

/// The evening digest (docs/CORE_LOOP.md §3, docs/PLAYER_JOURNEY.md §1
/// step 4): yesterday's profit or loss *with its why* — the beat that
/// closes decide → watch → understand. Every number comes from
/// `DailyDigestModel`; this view only formats.
struct DigestCard: View {
    let digest: DailyDigestModel
    /// Needed so the player's own administration or collapse is not rendered
    /// as a rival's, losing its alarm styling.
    let player: AirlineID
    @State private var expanded = false

    var body: some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Yesterday").font(.headline)
                        Text(Format.date(digest.date))
                            .font(.caption)
                            .foregroundStyle(AETheme.mutedText)
                    }
                    Spacer()
                    MoneyText(money: digest.netCashChange)
                        .font(.title3.weight(.semibold))
                }
                HStack(spacing: AETheme.spacingS) {
                    AEBadge(text: "\(digest.flightsCompleted) flown",
                            color: AETheme.positive, icon: "airplane")
                    if digest.flightsCancelled > 0 {
                        AEBadge(text: "\(digest.flightsCancelled) cancelled",
                                color: AETheme.negative,
                                icon: "exclamationmark.triangle")
                    }
                    Button(expanded ? "Hide detail" : "Why?") {
                        withAnimation(.snappy) { expanded.toggle() }
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                }
                if expanded {
                    ForEach(sortedCategories, id: \.0) { category, amount in
                        HStack {
                            Text(Self.label(for: category)).font(.subheadline)
                            Spacer()
                            MoneyText(money: amount).font(.subheadline)
                        }
                    }
                    if !digest.isComplete {
                        // Never present a partial day as a whole one.
                        Text("Your network posts more transactions than one day of history holds — these figures cover part of the day. The monthly statement is exact.")
                            .font(.caption)
                            .foregroundStyle(AETheme.caution)
                    }
                }
                ForEach(Array(digest.notableEvents.prefix(3).enumerated()),
                        id: \.offset) { _, event in
                    EventRow(event: event, player: player)
                }
            }
        }
    }

    private var sortedCategories: [(TransactionCategory, Money)] {
        digest.byCategory
            .map { ($0.key, $0.value) }
            .sorted { $0.1.cents != $1.1.cents ? $0.1.cents > $1.1.cents
                                               : $0.0.rawValue < $1.0.rawValue }
    }

    /// Shared with FinanceView's statement rows so one category never has
    /// two names in the same app.
    static func label(for category: TransactionCategory) -> String {
        switch category {
        case .ticketRevenue: "Ticket revenue"
        case .missionReward: "Mission rewards"
        case .fuel: "Fuel"
        case .airportFees: "Airport fees"
        case .crewCosts: "Crew"
        case .maintenance: "Maintenance"
        case .leasePayment: "Leases"
        case .leasePenalty: "Lease penalties"
        case .passengerService: "Onboard service"
        case .salaries: "Payroll"
        case .overhead: "Overhead"
        case .loanInterest: "Loan interest"
        case .loanPrincipal: "Loan principal"
        case .loanProceeds: "Loan drawdowns"
        case .initialCapital: "Capital"
        case .aircraftPurchase: "Aircraft purchases"
        case .aircraftSale: "Aircraft sales"
        }
    }
}

/// The guided first-route beat (docs/PLAYER_JOURNEY.md §1): a checklist of
/// real actions, with demand-hinted route candidates when it's time to open
/// one. Teaching is doing — the card disappears once the arc completes.
struct OnboardingCard: View {
    let model: OnboardingModel
    let openSuggestion: (FirstRouteSuggestion) -> Void

    var body: some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                Text("Get your airline flying").font(.headline)
                ForEach(OnboardingModel.Step.allCases, id: \.self) { step in
                    stepRow(step)
                }
                if model.nextStep == .openRoute, !model.suggestions.isEmpty {
                    Text("Strong first markets from your home airport:")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                    ForEach(model.suggestions, id: \.destination) { suggestion in
                        Button {
                            openSuggestion(suggestion)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(suggestion.origin.raw) → \(suggestion.destination.raw) · \(suggestion.destinationCity)")
                                        .font(.subheadline.weight(.medium))
                                    Text("≈\(suggestion.expectedDailyPassengers) passengers/day for a typical service · \(suggestion.distanceKm) km · fares near \(Format.money(suggestion.referenceFare))")
                                        .font(.caption)
                                        .foregroundStyle(AETheme.mutedText)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(AETheme.mutedText)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(AETheme.accent)
                    }
                }
            }
        }
    }

    private func stepRow(_ step: OnboardingModel.Step) -> some View {
        let done = model.isDone(step)
        let isNext = model.nextStep == step
        return HStack(spacing: AETheme.spacingS) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? AETheme.positive
                                 : isNext ? AETheme.accent : AETheme.mutedText)
            VStack(alignment: .leading, spacing: 1) {
                Text(title(step))
                    .font(.subheadline.weight(isNext ? .semibold : .regular))
                    .foregroundStyle(done ? AETheme.mutedText : .primary)
                if isNext {
                    Text(hint(step))
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title(step)), \(done ? "done" : isNext ? "next step" : "not started")")
    }

    private func title(_ step: OnboardingModel.Step) -> String {
        switch step {
        case .acquireAircraft: "Get an aircraft"
        case .openRoute: "Open your first route"
        case .assignAircraft: "Put the aircraft on the route"
        case .watchFirstFlight: "Un-pause and watch it fly"
        case .earnFirstRevenue: "Earn your first ticket revenue"
        }
    }

    private func hint(_ step: OnboardingModel.Step) -> String {
        switch step {
        case .acquireAircraft:
            "Fleet tab → Acquire. Leasing keeps cash free early on."
        case .openRoute:
            "Pick one of the suggested markets below, or browse the map."
        case .assignAircraft:
            "Open the route in the Routes tab and tap Assign an aircraft."
        case .watchFirstFlight:
            "Set speed to 1× — boarding, taxi, and the map crossing are real."
        case .earnFirstRevenue:
            "Revenue posts as flights land. Watch the feed below."
        }
    }
}

/// One feed line per SimEvent; unhandled kinds render nothing rather than
/// noise (curation over completeness).
struct EventRow: View {
    let event: SimEvent
    /// Distinguishes "your airline" from "a rival" in shared news.
    var player: AirlineID? = nil

    var body: some View {
        if let text = description {
            HStack(alignment: .top, spacing: AETheme.spacingS) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(isAlarm ? AETheme.negative : AETheme.mutedText)
                    .frame(width: 16)
                Text(text)
                    .font(.subheadline)
                    .fontWeight(isAlarm ? .semibold : .regular)
                    .foregroundStyle(isAlarm ? AETheme.negative : .primary)
                Spacer(minLength: 0)
            }
        }
    }

    /// Events the player must not miss get emphasis, not just a line.
    private var isAlarm: Bool {
        switch event.kind {
        case .airlineEnteredAdministration(let id), .airlineCollapsed(let id):
            return id == player
        default:
            return false
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
        // The most important warning in the game: the player is failing but
        // is not dead yet (BUG-004 — this case rendered nothing at all).
        case .airlineEnteredAdministration(let id):
            id == player
                ? "Your airline has entered administration — sell aircraft or raise cash now"
                : "A rival has entered administration"
        case .airlineCollapsed(let id):
            id == player ? "Your airline has collapsed" : "A rival airline has collapsed"
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
        case .airlineEnteredAdministration, .airlineCollapsed: "exclamationmark.octagon"
        default: "circle"
        }
    }
}
