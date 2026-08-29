import SwiftUI
import AirlineEmpireCore

/// The command-center home (docs/CORE_LOOP.md §4): current state at a
/// glance, the ops feed, and the time controls.
struct DashboardView: View {
    @Environment(GameController.self) private var controller
    @State private var guidedRoute: FirstRouteSuggestion?
    @State private var showingGuidedSheet = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AETheme.spacingM) {
                    if let snapshot = controller.snapshot,
                       let dashboard = snapshot.dashboardModel() {
                        header(snapshot: snapshot, dashboard: dashboard)

                        // The warning cascade, above everything else it could
                        // possibly be less important than (UI-005).
                        if let player = snapshot.playerAirline?.id,
                           let catalog = controller.catalog,
                           let solvency = snapshot.solvencyModel(for: player,
                                                                 catalog: catalog) {
                            SolvencyBanner(
                                model: solvency,
                                autoPaused: controller.autoPauseReason == .solvencyDanger)
                        }

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
                            DigestCard(digest: digest, player: player, snapshot: snapshot)
                        }
                        UpcomingCard(snapshot: snapshot, catalog: controller.catalog)
                        statGrid(dashboard)
                        eventsFeed(snapshot: snapshot)
                    } else {
                        LoadingState(message: "Preparing your airline")
                            .frame(minHeight: 240)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, AETheme.spacingM)
            }
            .aeScreenBackground()
            .navigationTitle(controller.snapshot?.playerAirline?.name ?? "…")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { autoPauseBar }
            .toolbar {
                ToolbarItem(placement: .principal) { SpeedControl() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingGuidedSheet) {
                if let guidedRoute {
                    OpenRouteSheet(suggestion: guidedRoute)
                } else {
                    OpenRouteSheet()
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack { SettingsView() }
            }
        }
    }

    @ViewBuilder
    private var autoPauseBar: some View {
        if let reason = controller.autoPauseReason {
            AutoPauseNotice(reason: reason) { controller.dismissAutoPause() }
                .padding(.horizontal, AETheme.spacingM)
                .padding(.bottom, AETheme.spacingS)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func header(snapshot: GameState, dashboard: DashboardModel) -> some View {
        AECard {
            HStack {
                if let livery = snapshot.playerAirline?.livery {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Vocab.liveryColor(livery))
                        .frame(width: 4)
                        .frame(maxHeight: 38)
                        .accessibilityHidden(true)
                        .padding(.trailing, AETheme.spacingXS)
                }
                VStack(alignment: .leading, spacing: AETheme.spacingXS) {
                    Text(Format.date(snapshot.currentDate))
                        .font(.headline).monospacedDigit()
                        // The date advances while you watch at 4× and 16×.
                        // Rolling digits read as time passing; a hard swap
                        // reads as a glitch.
                        .contentTransition(.numericText())
                        .aeAnimation(AEMotion.content, value: snapshot.currentDate.day)
                    Text("\(Format.clock(snapshot.currentDate)) · \(Vocab.season(snapshot.currentDate.season)) · \(Vocab.era(dashboard.era)) era")
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

    /// Six numbers, each of which opens the screen that explains it.
    ///
    /// `docs/UI_ARCHITECTURE.md` §6 asks for "every number tappable to its
    /// explanation"; these were inert labels, so a player reading "Reputation
    /// 61%" had no way to find out which of the five components moved.
    private func statGrid(_ dashboard: DashboardModel) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                  spacing: AETheme.spacingS) {
            NavigationLink(value: DashboardRoute.fleet) {
                StatTile(label: "Fleet", value: "\(dashboard.fleetCount)")
            }
            NavigationLink(value: DashboardRoute.routes) {
                StatTile(label: "Routes", value: "\(dashboard.routeCount)")
            }
            NavigationLink(value: DashboardRoute.reputation) {
                StatTile(label: "Reputation",
                         value: Format.percent(dashboard.reputationScore))
            }
            NavigationLink(value: DashboardRoute.finance) {
                StatTile(label: "Last month",
                         value: dashboard.lastMonthNetProfit.map(Format.money) ?? "—",
                         trend: (dashboard.lastMonthNetProfit?.isNegative ?? false)
                             ? .down : .up)
            }
            StatTile(label: "Fuel /t", value: Format.money(dashboard.fuelPricePerTon))
            NavigationLink(value: DashboardRoute.economy) {
                StatTile(label: "Economy",
                         value: Format.decimal(dashboard.economicIndex, places: 2),
                         trend: dashboard.economicIndex >= 1 ? .up : .down)
            }
        }
        .buttonStyle(.aePress)
        .navigationDestination(for: DashboardRoute.self) { route in
            switch route {
            case .fleet:
                FleetList().navigationTitle("Fleet").aeTimeToolbar()
            case .routes:
                RoutesList().navigationTitle("Routes").aeTimeToolbar()
            case .reputation:
                ReputationDetailView()
            case .finance:
                FinanceContent().navigationTitle("Finance").aeTimeToolbar()
            case .economy:
                EconomyDetailView()
            }
        }
        // The pushed screens above link onward, so this stack has to know the
        // same destinations the Network tab does.
        .navigationDestination(for: RouteID.self) { RouteDetailView(routeID: $0) }
        .navigationDestination(for: AircraftID.self) { AircraftDetailView(aircraftID: $0) }
    }

    private func eventsFeed(snapshot: GameState) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Operations feed", systemImage: "dot.radiowaves.left.and.right")
                if controller.recentEvents.isEmpty {
                    Text("Quiet skies. Open a route to get moving.")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.mutedText)
                        .transition(.opacity)
                } else {
                    // Newest first, sliding in from the top: the feed is the
                    // one part of the dashboard that is a live stream, and it
                    // should read like one.
                    ForEach(Array(controller.recentEvents.suffix(14).reversed()
                        .enumerated()), id: \.offset) { _, event in
                        EventRow(event: event,
                                 player: snapshot.playerAirline?.id,
                                 snapshot: snapshot)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .aeAnimation(AEMotion.content, value: controller.recentEvents.count)
        }
    }
}

/// Where a dashboard number leads.
enum DashboardRoute: Hashable { case fleet, routes, reputation, finance, economy }

/// The forward hook (docs/PLAYER_JOURNEY.md §2: a session should end on
/// "your second aircraft arrives Tuesday").
///
/// Every ingredient was already in the snapshot — delivery dates on ordered
/// aircraft, mission deadlines, forecast world events — and no screen ever
/// said any of it (UIUX_FORENSIC_AUDIT UI-024).
struct UpcomingCard: View {
    let snapshot: GameState
    let catalog: ContentCatalog?

    private struct Item: Identifiable {
        let id: String
        let icon: String
        let text: String
        let when: String
    }

    var body: some View {
        let items = upcoming
        if !items.isEmpty {
            AECard {
                VStack(alignment: .leading, spacing: AETheme.spacingS) {
                    AESectionHeader(text: "Coming up", systemImage: "calendar")
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: AETheme.spacingS) {
                            Image(systemName: item.icon)
                                .font(.caption)
                                .foregroundStyle(AETheme.accent)
                                .frame(width: 16)
                                .accessibilityHidden(true)
                            Text(item.text).font(.subheadline)
                            Spacer(minLength: AETheme.spacingS)
                            Text(item.when)
                                .font(.caption).monospacedDigit()
                                .foregroundStyle(AETheme.mutedText)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var upcoming: [Item] {
        guard let player = snapshot.playerAirline else { return [] }
        var items: [Item] = []
        let now = snapshot.clock.now

        for aircraft in snapshot.fleet(of: player.id) {
            guard case .ordered(let arrival) = aircraft.status else { continue }
            let days = Int(max(0, arrival.rawMinutes - now.rawMinutes)
                / GameCalendar.minutesPerDay)
            let name = catalog?.aircraftType(aircraft.typeCode)
                .map { "\($0.manufacturer) \($0.model)" } ?? "An aircraft"
            items.append(Item(id: "delivery-\(aircraft.id.raw)",
                              icon: "shippingbox.fill",
                              text: "\(name) is delivered",
                              when: days == 0 ? "today" : "in \(Format.days(days))"))
        }

        for aircraft in snapshot.fleet(of: player.id) {
            guard case .inMaintenance(let until) = aircraft.status else { continue }
            let days = Int(max(0, until.rawMinutes - now.rawMinutes)
                / GameCalendar.minutesPerDay)
            let name = catalog?.aircraftType(aircraft.typeCode)
                .map { "\($0.manufacturer) \($0.model)" } ?? "An aircraft"
            items.append(Item(id: "maintenance-\(aircraft.id.raw)",
                              icon: "wrench.fill",
                              text: "\(name) is back from maintenance",
                              when: days == 0 ? "today" : "in \(Format.days(days))"))
        }

        for mission in snapshot.progression.missions {
            let days = Int(max(0, mission.deadline.rawMinutes - now.rawMinutes)
                / GameCalendar.minutesPerDay)
            items.append(Item(id: "mission-\(mission.id)",
                              icon: "target",
                              text: "A mission closes — \(Format.money(mission.reward)) on offer",
                              when: days == 0 ? "today" : "in \(Format.days(days))"))
        }

        for event in snapshot.world.activeEvents where !event.hasStarted {
            let days = Int(max(0, event.beginsAt.rawMinutes - now.rawMinutes)
                / GameCalendar.minutesPerDay)
            items.append(Item(id: "event-\(event.id)",
                              icon: Vocab.worldEventIcon(event.kind),
                              text: Vocab.worldEvent(event.kind, state: snapshot),
                              when: days == 0 ? "today" : "in \(Format.days(days))"))
        }

        return Array(items.prefix(4))
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
    let snapshot: GameState
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
                    .frame(minHeight: 44)
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
                    EventRow(event: event, player: player, snapshot: snapshot)
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
                            .frame(minHeight: 44)
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
                        .fixedSize(horizontal: false, vertical: true)
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
            "Network tab → Fleet → Acquire. Leasing keeps cash free early on."
        case .openRoute:
            "Pick one of the suggested markets below, or browse the map."
        case .assignAircraft:
            "Network tab → Routes → open the route → Assign an aircraft."
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
    /// Lets a flight event name its route and a strike name its airline —
    /// event payloads carry ids, and an id is not news.
    var snapshot: GameState? = nil

    var body: some View {
        if let text = description {
            // An event about something you own leads to that thing.
            // `docs/UI_ARCHITECTURE.md` §2 asks for "tap → the delayed
            // flight"; the feed was a wall of unreachable text
            // (UIUX_FORENSIC_AUDIT UI-011).
            switch subject {
            case .route(let id):
                NavigationLink(value: id) { line(text) }
                    .buttonStyle(.aePress)
            case .aircraft(let id):
                NavigationLink(value: id) { line(text) }
                    .buttonStyle(.aePress)
            case .none:
                line(text)
            }
        }
    }

    /// What this event is about, when it is about something the player can
    /// open. Nil for world news and for anything already deleted — a link to
    /// a route that has been closed is a dead end, not a shortcut.
    private var subject: Subject {
        switch event.kind {
        case .flightDeparted(_, let route), .flightArrived(_, let route, _),
             .flightDelayed(_, let route, _), .flightCancelled(_, let route),
             .routeOpened(let route, _, _):
            return liveRoute(route).map(Subject.route) ?? .none
        case .aircraftDelivered(let id), .aircraftOrdered(let id, _, _),
             .maintenanceStarted(let id, _, _), .maintenanceCompleted(let id):
            return liveAircraft(id).map(Subject.aircraft) ?? .none
        default:
            return .none
        }
    }

    private enum Subject {
        case route(RouteID)
        case aircraft(AircraftID)
        case none
    }

    /// Only the player's own, and only while it still exists.
    private func liveRoute(_ id: RouteID) -> RouteID? {
        guard let snapshot, let route = snapshot.routes[id],
              route.airline == player else { return nil }
        return id
    }

    private func liveAircraft(_ id: AircraftID) -> AircraftID? {
        guard let snapshot, let aircraft = snapshot.aircraft[id],
              aircraft.owner == player else { return nil }
        return id
    }

    private func line(_ text: String) -> some View {
        HStack(alignment: .top, spacing: AETheme.spacingS) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .fontWeight(isAlarm ? .semibold : .regular)
                .foregroundStyle(isAlarm ? AETheme.negative : .primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if case .none = subject {
                EmptyView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(AETheme.mutedText)
                    .accessibilityHidden(true)
            }
            Text(Format.clock(clockDate))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(AETheme.mutedText)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var clockDate: GameDate {
        guard let snapshot else { return GameCalendar.date(at: event.at, startYear: 2030) }
        return GameCalendar.date(at: event.at, startYear: snapshot.meta.startYear)
    }

    /// Events the player must not miss get emphasis, not just a line.
    private var isAlarm: Bool {
        switch event.kind {
        case .airlineEnteredAdministration(let id), .airlineCollapsed(let id):
            return id == player
        case .flightCancelled:
            return true
        default:
            return false
        }
    }

    private var tint: Color {
        if isAlarm { return AETheme.negative }
        switch event.kind {
        case .flightArrived, .aircraftDelivered, .missionCompleted,
             .milestoneReached, .achievementUnlocked, .eraAdvanced,
             .capabilityCompleted:
            return AETheme.positive
        case .flightDelayed, .worldEventStarted, .worldEventForecast,
             .maintenanceStarted:
            return AETheme.caution
        default:
            return AETheme.mutedText
        }
    }

    /// Names a route from its id — the departure and arrival lines that
    /// `PLAYER_JOURNEY` §1 promises are worthless as "Flight departed".
    private func routeName(_ id: RouteID) -> String? {
        guard let route = snapshot?.routes[id] else { return nil }
        return "\(route.origin.raw)–\(route.destination.raw)"
    }

    private var description: String? {
        switch event.kind {
        // The first flight leaving and landing is the payoff of the first five
        // minutes, and it used to render nothing at all (UI-003).
        case .flightDeparted(_, let route):
            routeName(route).map { "\($0) departed" }
        case .flightArrived(_, let route, let delay):
            routeName(route).map { name in
                delay > 15 ? "\(name) landed \(delay) min late" : "\(name) landed"
            }
        case .flightDelayed(_, let route, let minutes):
            routeName(route).map { "\($0) delayed \(minutes) min" }
                ?? "A flight is delayed \(minutes) min"
        case .flightCancelled(_, let route):
            routeName(route).map { "\($0) cancelled" } ?? "A flight was cancelled"
        case .aircraftDelivered(let id):
            aircraftName(id).map { "\($0) delivered" } ?? "Aircraft delivered"
        case .aircraftOrdered(let id, _, _):
            aircraftName(id).map { "\($0) ordered" } ?? "Aircraft ordered"
        case .maintenanceStarted(let id, _, let cost):
            "\(aircraftName(id) ?? "An aircraft") is grounded for maintenance — \(Format.money(cost))"
        case .maintenanceCompleted(let id):
            "\(aircraftName(id) ?? "An aircraft") is back in service"
        case .routeOpened(_, let origin, let destination):
            "Route opened: \(origin.raw)–\(destination.raw)"
        case .milestoneReached(let code):
            "Milestone: \(Vocab.milestone(code))"
        case .achievementUnlocked(let code):
            "Achievement: \(Vocab.achievement(code))"
        case .eraAdvanced(let era):
            "A new era: \(Vocab.era(era))"
        case .capabilityCompleted(let code):
            "\(Vocab.capability(code)) is now in place"
        case .worldEventStarted(_, let kind):
            Vocab.worldEvent(kind, state: snapshot)
        case .worldEventForecast(let kind, _):
            "Forecast: \(Vocab.worldEvent(kind, state: snapshot).lowercasedFirst)"
        case .worldEventEnded(_, let kind):
            "Over: \(Vocab.worldEvent(kind, state: snapshot).lowercasedFirst)"
        case .missionOffered(_, _, _, let reward):
            "Mission offered — reward \(Format.money(reward))"
        case .missionCompleted(_, let reward):
            "Mission complete! \(Format.money(reward))"
        case .missionExpired:
            "A mission expired"
        case .statementClosed(_, _, let month, let net):
            "\(Format.monthAbbreviation(month)) closed: \(Format.money(net))"
        // The most important warning in the game: the player is failing but
        // is not dead yet (BUG-004 — this case rendered nothing at all).
        case .airlineEnteredAdministration(let id):
            id == player
                ? "Your airline has entered administration — idle aircraft were sold to pay creditors"
                : "\(Vocab.airlineName(id, state: snapshot)) has entered administration"
        case .airlineCollapsed(let id):
            id == player ? "Your airline has collapsed"
                : "\(Vocab.airlineName(id, state: snapshot)) has collapsed"
        case .loanTaken(_, let amount, _):
            "Loan drawn: \(Format.money(amount))"
        case .loanRepaidEarly(_, let amount):
            "Loan paid off: \(Format.money(amount))"
        default:
            nil
        }
    }

    private func aircraftName(_ id: AircraftID) -> String? {
        guard let snapshot, let aircraft = snapshot.aircraft[id] else { return nil }
        return aircraft.typeCode.raw
    }

    private var icon: String {
        switch event.kind {
        case .flightDeparted: "airplane.departure"
        case .flightArrived: "airplane.arrival"
        case .flightDelayed, .flightCancelled: "exclamationmark.triangle"
        case .aircraftDelivered, .aircraftOrdered: "airplane.circle"
        case .maintenanceStarted, .maintenanceCompleted: "wrench"
        case .routeOpened: "point.topleft.down.to.point.bottomright.curvepath"
        case .milestoneReached, .achievementUnlocked, .eraAdvanced,
             .capabilityCompleted: "star"
        case .missionOffered, .missionCompleted, .missionExpired: "target"
        case .worldEventStarted(_, let kind), .worldEventEnded(_, let kind):
            Vocab.worldEventIcon(kind)
        case .worldEventForecast(let kind, _): Vocab.worldEventIcon(kind)
        case .statementClosed: "doc.text"
        case .loanTaken, .loanRepaidEarly: "banknote"
        case .airlineEnteredAdministration, .airlineCollapsed: "exclamationmark.octagon"
        default: "circle"
        }
    }
}

private extension String {
    /// "Fuel market shock" → "fuel market shock", for use mid-sentence.
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
