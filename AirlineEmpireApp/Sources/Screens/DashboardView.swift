import SwiftUI
import AirlineEmpireCore

/// The command-center home (docs/CORE_LOOP.md §4): current state at a
/// glance, the ops feed, and the time controls.
struct DashboardView: View {
    @Environment(GameController.self) private var controller
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The suggestion whose route sheet is up. Item-driven, not a Bool
    /// beside an optional: run 116 photographed the guided sheet opening
    /// *empty* — From Stockholm, nothing picked, the whole ranked list —
    /// because `isPresented` flipped before the optional had landed and the
    /// sheet's `if let` took its else branch; the journey then opened a
    /// route no aircraft could fly. `sheet(item:)` cannot present without
    /// the value (BUG-045).
    @State private var guidedRoute: GuidedRoute?
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
                                guidedRoute = GuidedRoute(suggestion)
                            }
                        } else if let catalog = controller.catalog,
                                  snapshot.playerAirline != nil {
                            // The checklist's replacement, not its ghost. The
                            // AE-033 audit's top finding (EXP-01): the game's
                            // strongest guidance surface went silent exactly
                            // when the player first had freedom. Same ranking
                            // the map coach uses, same guided-route flow the
                            // checklist used.
                            NextMovesCard(snapshot: snapshot, catalog: catalog) { suggestion in
                                guidedRoute = GuidedRoute(suggestion)
                            }
                        }
                        // One competitive fact, only when the world has one
                        // (AE-037). Not a feed: the most decision-relevant
                        // thing a rival did or is doing to this airline.
                        RivalPressureCard()
                        // The pulse comes before the history. This block
                        // used to sit fifth, below yesterday's digest and next
                        // week's calendar — so "how is my airline doing right
                        // now" was two scrolls under "how did it do yesterday"
                        // (MASTER PROMPT 4 §6).
                        pulse(dashboard)
                        statGrid(dashboard)
                        DigestSlot(snapshot: snapshot)
                        UpcomingCard(snapshot: snapshot, catalog: controller.catalog)
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
            .sheet(item: $guidedRoute) { guided in
                OpenRouteSheet(suggestion: guided.suggestion)
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
                // Two columns at reading sizes; one leading column at
                // accessibility sizes, where the pair squeezed each other
                // into ragged two-line wraps (seen in run 60's
                // AccessibilityL Home frame).
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: AETheme.spacingS) {
                        headerDate(snapshot: snapshot, dashboard: dashboard)
                        headerMoney(dashboard: dashboard, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                } else {
                    headerDate(snapshot: snapshot, dashboard: dashboard)
                    Spacer()
                    headerMoney(dashboard: dashboard, alignment: .trailing)
                }
            }
        }
    }

    private func headerDate(snapshot: GameState,
                            dashboard: DashboardModel) -> some View {
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
    }

    private func headerMoney(dashboard: DashboardModel,
                             alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: AETheme.spacingXS) {
            MoneyText(money: dashboard.cash).font(.headline)
            Text("net worth \(Format.money(dashboard.netWorth))")
                .font(.caption)
                .foregroundStyle(AETheme.mutedText)
        }
    }

    /// What the airline is doing *right now*, in one strip.
    ///
    /// Home had no live number at all. `liveFlightCount` was published by Core
    /// and rendered nowhere — the single most alive figure the game has, and
    /// the screen showed fleet size and route count instead, which are the two
    /// numbers that change least. (It was also wrong; see BUG-027.)
    ///
    /// One panel rather than four tiles: these are one picture of one moment,
    /// and four glass cards would read as four separate claims.
    @ViewBuilder
    private func pulse(_ dashboard: DashboardModel) -> some View {
        if let network = controller.networkSummary,
           let fleet = controller.fleetSummary {
            AEMetricStrip([
                AEMetric("in the air", "\(network.liveFlights)",
                         tint: network.liveFlights > 0 ? AETheme.positive : nil,
                         emphasised: true),
                AEMetric("load factor",
                         network.averageLoadFactor.map(Format.percent) ?? "—"),
                AEMetric("aircraft used",
                         fleet.utilization.map(Format.percent) ?? "—",
                         tint: fleet.idle > 0 ? AETheme.caution : nil),
                AEMetric("month to date",
                         Format.money(network.monthToDateProfit),
                         tint: network.monthToDateProfit.isNegative
                             ? AETheme.negative : AETheme.positive),
            ])
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Operations right now")
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
                // No trend until a month has actually closed. The first
                // version fell through to `.up` for nil, so for the whole of
                // the first game-month the dashboard drew a green arrow beside
                // a dash — asserting a positive trend on a number that did not
                // exist yet. Same class of defect as BUG-011.
                StatTile(label: "Last month",
                         value: dashboard.lastMonthNetProfit.map(Format.money) ?? "—",
                         trend: dashboard.lastMonthNetProfit.map {
                             $0.isNegative ? StatTile.Trend.down : StatTile.Trend.up
                         } ?? .neutral)
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
        // same destinations the Airline tab does.
        .navigationDestination(for: RouteID.self) { RouteDetailView(routeID: $0) }
        .navigationDestination(for: AircraftID.self) { AircraftDetailView(aircraftID: $0) }
    }

    private func eventsFeed(snapshot: GameState) -> some View {
        AEPanel {
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
        /// Days until it happens — what the card is ordered by.
        let days: Int
    }

    /// Whether the player has anything that *could* be scheduled. On a fresh
    /// game the answer is no, and the card stays away — the onboarding card
    /// owns that space and a second box saying "nothing yet" would be noise.
    /// Once there is a fleet, silence becomes confusing rather than obvious,
    /// which is when the card starts saying so.
    private var hasOperations: Bool {
        guard let player = snapshot.playerAirline?.id else { return false }
        return !snapshot.fleet(of: player).isEmpty
            || !snapshot.routes(of: player).isEmpty
    }

    var body: some View {
        let items = upcoming
        if items.isEmpty, hasOperations {
            AEPanel {
                VStack(alignment: .leading, spacing: AETheme.spacingS) {
                    AESectionHeader(text: "Coming up", systemImage: "calendar")
                    Text("Nothing scheduled. Deliveries, maintenance and lease expiries appear here.")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if !items.isEmpty {
            AEPanel {
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
                              when: days == 0 ? "today" : "in \(Format.days(days))",
                              days: days))
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
                              when: days == 0 ? "today" : "in \(Format.days(days))",
                              days: days))
        }

        for mission in snapshot.progression.missions {
            let days = Int(max(0, mission.deadline.rawMinutes - now.rawMinutes)
                / GameCalendar.minutesPerDay)
            items.append(Item(id: "mission-\(mission.id)",
                              icon: "target",
                              text: "A mission closes — \(Format.money(mission.reward)) on offer",
                              when: days == 0 ? "today" : "in \(Format.days(days))",
                              days: days))
        }

        for event in snapshot.world.activeEvents where !event.hasStarted {
            let days = Int(max(0, event.beginsAt.rawMinutes - now.rawMinutes)
                / GameCalendar.minutesPerDay)
            items.append(Item(id: "event-\(event.id)",
                              icon: Vocab.worldEventIcon(event.kind),
                              text: Vocab.worldEvent(event.kind, state: snapshot),
                              when: days == 0 ? "today" : "in \(Format.days(days))",
                              days: days))
        }

        // Sorted before the cap: the list is built category by category, so
        // taking the first four dropped a mission closing tomorrow in favour
        // of a delivery two hundred days out — which is the opposite of what
        // a "what's next" card is for.
        return Array(items.sorted { $0.days < $1.days }.prefix(4))
    }
}

/// The evening digest (docs/CORE_LOOP.md §3, docs/PLAYER_JOURNEY.md §1
/// step 4): yesterday's profit or loss *with its why* — the beat that
/// closes decide → watch → understand. Every number comes from
/// `DailyDigestModel`; this view only formats.
/// Yesterday's close, when there is a yesterday and it had content.
///
/// The condition lived inline in `DashboardView.body` as a four-clause `if
/// let`, which is most of why the body was hard to read as an ordering.
struct DigestSlot: View {
    let snapshot: GameState

    var body: some View {
        // `previousDayIndex` is nil on the first day, because there is no
        // yesterday to summarize (Core also refuses a negative day — BUG-008).
        if let player = snapshot.playerAirline?.id,
           let yesterday = snapshot.clock.now.previousDayIndex,
           let digest = snapshot.dailyDigest(for: player, day: yesterday),
           digest.hasContent {
            DigestCard(digest: digest, player: player, snapshot: snapshot)
        }
    }
}

struct DigestCard: View {
    let digest: DailyDigestModel
    /// Needed so the player's own administration or collapse is not rendered
    /// as a rival's, losing its alarm styling.
    let player: AirlineID
    let snapshot: GameState
    @State private var expanded = false

    var body: some View {
        AEPanel {
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
            "Airline tab → Fleet → Acquire. Leasing keeps cash free early on."
        case .openRoute:
            "Pick one of the suggested markets below, or browse the map."
        case .assignAircraft:
            "Airline tab → Routes → open the route → Assign an aircraft."
        case .watchFirstFlight:
            "Set speed to 1× — boarding, taxi, and the map crossing are real."
        case .earnFirstRevenue:
            "Revenue posts as flights land. Watch the feed below."
        }
    }
}

/// "What should I do next?", after the checklist has answered its last step.
///
/// The onboarding card disappears the moment the arc completes, which used to
/// leave Home answering only "how big am I" (EXP-01). This is the surface
/// that takes over: the fleet's one actionable warning (idle aircraft — they
/// bill like flying ones and earn nothing) and the two best open markets from
/// `marketOpportunities`, the same ranking the map's demand coach draws.
/// Tapping a market opens the guided route sheet, exactly as the checklist's
/// suggestions did — one flow, not two that drift.
struct NextMovesCard: View {
    let snapshot: GameState
    let catalog: ContentCatalog
    let openSuggestion: (FirstRouteSuggestion) -> Void

    private var idleCount: Int {
        guard let player = snapshot.playerAirline?.id else { return 0 }
        return snapshot.fleet(of: player)
            .filter { $0.assignedRoute == nil }.count
    }

    private var opportunities: [MarketOpportunity] {
        // Servable markets first: advice the fleet cannot act on today is a
        // wish, not a move. Two at most — a ranked pair is a decision, a
        // longer list is homework.
        let ranked = snapshot.marketOpportunities(catalog: catalog, limit: 4)
        let servable = ranked.filter(\.servableNow)
        return Array((servable.isEmpty ? ranked : servable).prefix(2))
    }

    var body: some View {
        let idle = idleCount
        let markets = opportunities
        if idle > 0 || !markets.isEmpty {
            AECard {
                VStack(alignment: .leading, spacing: AETheme.spacingS) {
                    Text("Next moves").font(.headline)
                    if idle > 0 {
                        HStack(spacing: AETheme.spacingS) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AETheme.caution)
                                .accessibilityHidden(true)
                            Text(idle == 1
                                 ? "One aircraft is idle. It costs the same parked as flying — assign it in Airline → Routes."
                                 : "\(idle) aircraft are idle. They cost the same parked as flying — assign them in Airline → Routes.")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if !markets.isEmpty {
                        Text(idle > 0 ? "Or grow the network:"
                                      : "Strong open markets from your bases:")
                            .font(.caption)
                            .foregroundStyle(AETheme.mutedText)
                        ForEach(markets, id: \.destination) { market in
                            Button {
                                openSuggestion(market.asFirstRouteSuggestion)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(market.origin.raw) → \(market.destination.raw) · \(market.destinationCity)")
                                            .font(.subheadline.weight(.medium))
                                        Text("≈\(market.expectedDailyPassengers) passengers/day · \(market.distanceKm) km · \(market.incumbents == 0 ? "no competition yet" : "\(market.incumbents) rival\(market.incumbents == 1 ? "" : "s") already here")")
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
            .accessibilityIdentifier("ae-next-moves")
        }
    }
}

/// The one thing the competition is doing to this airline, when there is
/// one. Measured before it existed (docs/RIVAL_PRESSURE_AUDIT.md §3): a
/// rival could enter the player's city pair, cut its fare the next morning
/// and climb to twenty rotations a day, and Home said nothing, because the
/// feed drops a rival's route events and price moves emit no event at all.
///
/// Reads `CompetitionSummary.headline` — Core's one pick, by priority — and
/// renders nothing in a quiet world, which is most of the early game. Tapping
/// opens the route it is about, or the Competitors screen.
struct RivalPressureCard: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        if let summary = controller.competitionSummary,
           let headline = summary.headline,
           let snapshot = controller.snapshot {
            AECard(tint: tint(headline).opacity(0.12)) {
                VStack(alignment: .leading, spacing: AETheme.spacingS) {
                    AESectionHeader(text: "Rivals", systemImage: "person.2.fill")
                    // The identifier rides the link, which is the element
                    // XCUITest can see; on the card's container it matched
                    // nothing in run 112 while the card was on screen.
                    if let route = route(for: headline, snapshot: snapshot) {
                        NavigationLink(value: route) { line(headline) }
                            .buttonStyle(.aePress)
                            .accessibilityIdentifier("ae-rival-pressure")
                    } else {
                        NavigationLink { CompetitorsView() } label: { line(headline) }
                            .buttonStyle(.aePress)
                            .accessibilityIdentifier("ae-rival-pressure")
                    }
                }
            }
        }
    }

    private func line(_ headline: CompetitionSummary.Headline) -> some View {
        HStack(alignment: .top, spacing: AETheme.spacingS) {
            Text(Vocab.headline(headline))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(AETheme.mutedText)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    /// The player's route the headline is about, when it is about one.
    private func route(for headline: CompetitionSummary.Headline,
                       snapshot: GameState) -> RouteID? {
        guard let player = snapshot.playerAirline?.id else { return nil }
        switch headline {
        case .rivalEnteredYourMarket(let move), .rivalLeftYourMarket(let move):
            return snapshot.routes(of: player).first {
                $0.sameMarket(origin: move.origin, destination: move.destination)
            }?.id
        case .trailing:
            return controller.competitionSummary?.contested
                .first { $0.standing == .trailing }?.routeID
        case .fighting(let contested) where contested == 1:
            return controller.competitionSummary?.contested.first?.routeID
        case .rivalExpanding, .leading, .fighting:
            return nil
        }
    }

    private func tint(_ headline: CompetitionSummary.Headline) -> Color {
        switch headline {
        case .rivalEnteredYourMarket, .trailing: AETheme.caution
        case .rivalLeftYourMarket, .leading: AETheme.positive
        case .rivalExpanding, .fighting: AETheme.accent
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
        case .marketEntered(_, let origin, let destination),
             .marketLeft(_, let origin, let destination):
            // A rival's move on your pair leads to your route on that pair.
            guard let snapshot, let player else { return .none }
            return snapshot.routes(of: player).first {
                $0.sameMarket(origin: origin, destination: destination)
            }.map { Subject.route($0.id) } ?? .none
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
        case .marketEntered(let airline, _, _):
            return airline == player ? AETheme.mutedText : AETheme.caution
        case .marketLeft(let airline, _, _):
            return airline == player ? AETheme.mutedText : AETheme.positive
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
        // Your own entry is already the line above; a rival's is news only
        // on your pair, which the feed filter has already decided.
        case .marketEntered(let airline, let origin, let destination):
            airline == player ? nil
                : "\(Vocab.airlineName(airline, state: snapshot)) entered your \(Vocab.pair(origin, destination)) market"
        case .marketLeft(let airline, let origin, let destination):
            airline == player ? nil
                : "\(Vocab.airlineName(airline, state: snapshot)) pulled out of \(Vocab.pair(origin, destination)) — the market is yours again"
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
        case .marketEntered, .marketLeft: "person.2.fill"
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

/// A first-route suggestion as a sheet item: `sheet(item:)` needs identity,
/// and Core's value type has none of its own.
private struct GuidedRoute: Identifiable {
    let suggestion: FirstRouteSuggestion
    var id: String { "\(suggestion.origin.raw)-\(suggestion.destination.raw)" }
    init(_ suggestion: FirstRouteSuggestion) { self.suggestion = suggestion }
}
