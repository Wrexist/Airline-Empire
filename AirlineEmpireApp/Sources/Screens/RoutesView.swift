import SwiftUI
import OSLog
import AirlineEmpireCore

/// The route board.
///
/// Two things changed here. It is sortable and searchable, because creation
/// order stops working somewhere around the tenth route; and it leads with the
/// **month in progress** rather than the last closed month, because a route
/// opened three days ago had a last month of exactly zero and the board read
/// as a column of $0 through the whole window in which a new player is
/// deciding whether this game rewards attention (UIUX_FORENSIC_AUDIT UI-002).
struct RoutesList: View {
    @Environment(GameController.self) private var controller
    @State private var sort: RouteSort = .needsAttention
    @State private var search = ""
    /// Supplied by whichever screen owns the "open a route" sheet, so the
    /// empty state can offer the action it is telling the player to take.
    /// Optional because the Dashboard reaches this list by navigation and has
    /// no sheet of its own to raise.
    var openRoute: (() -> Void)?

    var body: some View {
        Group {
            if let snapshot = controller.snapshot,
               let player = snapshot.playerAirline {
                let cards = sorted(controller.routeCards)
                if snapshot.routes(of: player.id).isEmpty {
                    EmptyStateView(icon: "point.topleft.down.to.point.bottomright.curvepath",
                                   title: "No routes yet",
                                   message: "Open your first route — pick a market and put an aircraft on it.",
                                   actionTitle: openRoute == nil ? nil : "Open a route",
                                   action: openRoute)
                        .padding(.horizontal, AETheme.spacingM)
                        .aeEmptyStatePlacement()
                } else {
                    List {
                        if cards.isEmpty {
                            RouteSearchEmptyState(search: $search)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        // The board had no header at all: a player with forty
                        // routes had to read forty rows to learn whether the
                        // network was making money (MASTER PROMPT 4 §12).
                        // Hidden while searching, when a summary of everything
                        // would describe rows that are not on screen.
                        if let network = controller.networkSummary, search.isEmpty {
                            NetworkSummaryRow(summary: network)
                                .aeListRow()
                        }
                        ForEach(cards, id: \.id) { card in
                            NavigationLink(value: card.id) {
                                RouteRow(card: card)
                            }
                            .aeListRow()
                            // Automation cannot use `cells.firstMatch` here:
                            // the first cell is the network summary, which
                            // navigates nowhere (BUG-038's class).
                            .accessibilityIdentifier("ae-route-row")
                        }
                    }
                    .listStyle(.plain)
                    .aeScreenBackground()
                    // Keep search mounted even when its results are empty.
                    .searchable(text: $search,
                                placement: .navigationBarDrawer(displayMode: .always),
                                prompt: "Airport code or city")
                    .aeAnimation(AEMotion.content, value: cards.count)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { sortMenu }
                    }
                }
            } else {
                LoadingState(message: "Loading your network")
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(RouteSort.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort routes")
        .accessibilityValue(sort.title)
    }

    private func sorted(_ cards: [RouteCardModel]) -> [RouteCardModel] {
        // The prompt says "Airport code or city", and `OpenRouteSheet` in
        // this same file already matches city — so typing a city name here
        // used to produce "No matches" for routes plainly on screen.
        let catalog = controller.catalog
        let filtered = search.isEmpty ? cards : cards.filter { card in
            let needle = search.uppercased()
            if card.origin.raw.uppercased().contains(needle)
                || card.destination.raw.uppercased().contains(needle) {
                return true
            }
            return [card.origin, card.destination].contains { code in
                catalog?.airport(code)?.city.uppercased().contains(needle) == true
            }
        }
        switch sort {
        case .profit:
            return filtered.sorted { $0.thisMonthProfit.cents > $1.thisMonthProfit.cents }
        case .load:
            return filtered.sorted { $0.loadFactor > $1.loadFactor }
        case .name:
            return filtered.sorted {
                ($0.origin.raw, $0.destination.raw) < ($1.origin.raw, $1.destination.raw)
            }
        case .needsAttention:
            // Grounded first, then losing money, then thin loads. The board
            // should open on the routes that want a decision.
            return filtered.sorted { lhs, rhs in
                (attentionRank(lhs), -lhs.thisMonthProfit.cents)
                    < (attentionRank(rhs), -rhs.thisMonthProfit.cents)
            }
        }
    }

    private func attentionRank(_ card: RouteCardModel) -> Int {
        if card.assignedAircraftCount == 0 { return 0 }
        if card.thisMonthProfit.isNegative { return 1 }
        if card.loadFactor < 0.5 { return 2 }
        return 3
    }
}

/// Dismiss search from inside its environment so the next route tap navigates.
private struct RouteSearchEmptyState: View {
    @Environment(\.dismissSearch) private var dismissSearch
    @Binding var search: String

    var body: some View {
        EmptyStateView(icon: "magnifyingglass", title: "No matches",
                       message: "No route matches “\(search)”.",
                       actionTitle: "Clear search") {
            search = ""
            dismissSearch()
        }
    }
}

/// The network in one strip (MASTER PROMPT 4 §12).
///
/// Answers, above the list rather than inside it: how many routes, how many
/// are earning, how many are bleeding, how full the aeroplanes are, and what
/// the month has made so far.
struct NetworkSummaryRow: View {
    let summary: NetworkSummary

    var body: some View {
        AEManagementSummary(title: "Network statistics", metrics: [
            AEMetric("routes", "\(summary.routeCount)"),
            AEMetric("earning", "\(summary.profitableRoutes)", tint: AETheme.positive),
            AEMetric("month to date", Format.money(summary.monthToDateProfit),
                     tint: summary.monthToDateProfit.isNegative ? AETheme.negative : AETheme.positive)
        ], details: [
            AEMetric("Losing routes", "\(summary.losingRoutes)",
                     tint: summary.losingRoutes > 0 ? AETheme.negative : nil),
            AEMetric("Without aircraft", "\(summary.idleRoutes)",
                     tint: summary.idleRoutes > 0 ? AETheme.caution : nil),
            AEMetric("Load factor", summary.averageLoadFactor.map(Format.percent) ?? "\u{2014}"),
            AEMetric("In the air", "\(summary.liveFlights)")
        ], identifier: "ae-network-statistics")
        .accessibilityLabel("Network summary")
    }
}

struct RouteRow: View {
    let card: RouteCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingXS) {
            HStack {
                Text("\(card.origin.raw) – \(card.destination.raw)")
                    .font(.body.weight(.semibold))
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    MoneyText(money: card.thisMonthProfit).font(.subheadline)
                    Text(card.hasClosedMonth ? "this month" : "so far")
                        .font(.caption2)
                        .foregroundStyle(AETheme.mutedText)
                }
            }
            AEChipRow {
                AEBadge(text: "\(card.dailyRoundTrips)×/day", color: AETheme.accent)
                // A route that has never flown has no load factor yet; "load
                // 0%" in the warning colour read as a failing route, not a
                // new one.
                if card.hasFlown {
                    AEBadge(text: "load \(Format.percent(card.loadFactor))",
                            color: card.loadFactor > 0.7 ? AETheme.positive : AETheme.caution)
                } else {
                    AEBadge(text: "load \u{2014}", color: .secondary)
                }
                AEBadge(text: Format.money(card.ticketPrice), color: AETheme.fare)
                if card.assignedAircraftCount == 0 {
                    AEBadge(text: "no aircraft", color: AETheme.negative,
                            icon: "exclamationmark.triangle")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// The route P&L breakdown: "why did this route make or lose money"
/// (docs/ECONOMY.md) — the exact simulation figures, no UI math.
struct RouteDetailView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingAircraftMarket = false
    @State private var section: RouteManagementSection = .overview
    @State private var planDraft: RoutePlan?
    @Environment(GameController.self) private var controller
    @Environment(\.feedback) private var feedback
    @Environment(\.dismiss) private var dismiss
    let routeID: RouteID

    init(routeID: RouteID, initialSection: RouteManagementSection = .overview) {
        self.routeID = routeID
        _section = State(initialValue: initialSection)
    }

    private var context: (GameState, Airline, ContentCatalog, RouteCardModel)? {
        guard let snapshot = controller.snapshot,
              let player = snapshot.playerAirline,
              let catalog = controller.catalog,
              let card = controller.routeCard(routeID)
        else { return nil }
        return (snapshot, player, catalog, card)
    }

    var body: some View {
        ScrollView {
            if let (snapshot, player, catalog, card) = context {
                VStack(spacing: AETheme.spacingM) {
                    FirstFlightProgress()
                    if let route = snapshot.routes[routeID] {
                        RouteOverviewHero(route: route, catalog: catalog) {
                            controller.showRouteOnMap(routeID); dismiss()
                        }
                        RouteManagementTabs(selection: $section)
                        switch section {
                        case .overview:
                            headline(card, snapshot: snapshot, catalog: catalog)
                            RouteFlightStatus(routeID: routeID) {
                                controller.showRouteOnMap(routeID); dismiss()
                            }
                            aircraftSection(card, player: player.id, catalog: catalog,
                                            candidates: snapshot.assignmentCandidates(
                                                forRoute: routeID, catalog: catalog))
                            operations(card)
                            demandSection(card, snapshot: snapshot)
                            Button("Plan fare & schedule") { section = .planning }
                                .buttonStyle(.aePrimary).frame(minHeight: 44)
                        case .planning:
                            RoutePlanEditor(route: route, snapshot: snapshot, catalog: catalog, draft: $planDraft)
                        case .aircraft:
                            aircraftTab(card, route: route, snapshot: snapshot,
                                        player: player.id, catalog: catalog)
                        case .competition:
                            demandSection(card, snapshot: snapshot)
                            competitorSection(card, snapshot: snapshot, player: player.id)
                        case .history:
                            RoutePlanHistoryCard(route: route, startYear: snapshot.meta.startYear)
                            breakdown(card, catalog: catalog)
                            dangerZone(player: player.id)
                        }
                    }
                }
                .frame(maxWidth: 920)
                .aePageInsets()
            } else {
                EmptyStateView(icon: "xmark.circle", title: "Route closed",
                               message: "This route no longer exists.")
                    .padding()
            }
        }
        .aeScreenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .aeTimeToolbar()
        // Route setup may already be a sheet. Continue in its existing stack
        // so purchase alerts do not sit above a second nested sheet (iOS 26
        // presentation-host regression, Apple feedback FB24621651).
        .navigationDestination(isPresented: $showingAircraftMarket) {
            AircraftShopSheet(routeID: routeID, isNavigationDestination: true)
        }
    }

    private var title: String {
        guard let snapshot = controller.snapshot,
              let route = snapshot.routes[routeID] else { return "Route" }
        return "\(route.origin.raw) – \(route.destination.raw)"
    }

    /// The Aircraft tab. Eligibility is asked of Core once per pass and
    /// shared: the section and the comparison each walked the fleet for the
    /// same answer, and the comparison did it twice.
    @ViewBuilder
    private func aircraftTab(_ card: RouteCardModel, route: Route, snapshot: GameState,
                             player: AirlineID, catalog: ContentCatalog) -> some View {
        let candidates = snapshot.assignmentCandidates(forRoute: routeID, catalog: catalog)
        aircraftSection(card, player: player, catalog: catalog, candidates: candidates)
        RouteAircraftComparison(route: route, snapshot: snapshot, catalog: catalog,
                                eligibility: candidates)
    }

    /// Colour follows the standing, never carries it: the sentence already
    /// says which way the route is going.
    private func verdictTint(_ verdict: RouteVerdict) -> Color {
        switch verdict.standing {
        case .earning: AETheme.positive
        case .losing: AETheme.negative
        case .idle: AETheme.caution
        case .tooEarly: AETheme.mutedText
        }
    }

    /// The money story, month to date, before anything else — this is the
    /// question a player opens a route to answer.
    private func headline(_ card: RouteCardModel, snapshot: GameState,
                          catalog: ContentCatalog) -> some View {
        AircraftPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Route performance").font(.headline)
                Text("Direct profit this month").font(.caption).foregroundStyle(AETheme.mutedText)
                MoneyText(money: card.thisMonthProfit).font(.largeTitle.bold())
                if let verdict = Vocab.routeVerdict(card.verdict) {
                    Text(verdict).font(.subheadline).foregroundStyle(verdictTint(card.verdict))
                }
                if card.hasClosedMonth {
                    Text("Last full month: \(Format.money(card.lastMonthProfit))").font(.caption).foregroundStyle(AETheme.mutedText)
                }
                Text("Booked route results. Aircraft leases and company overhead are recorded in Finance.")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
            }
        }
    }

    private func cityPair(_ catalog: ContentCatalog) -> String {
        guard let snapshot = controller.snapshot,
              let route = snapshot.routes[routeID] else { return "Route" }
        let origin = catalog.airport(route.origin)?.city ?? route.origin.raw
        let destination = catalog.airport(route.destination)?.city ?? route.destination.raw
        return "\(origin) – \(destination)"
    }

    /// Where the money went. Month to date is what a young route has; the
    /// closed month sits beside it once there is one.
    private func breakdown(_ card: RouteCardModel, catalog: ContentCatalog) -> some View {
        AEPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Where the money went", systemImage: "chart.pie")
                if typeSize.isAccessibilitySize {
                    // Stacked rows carry their own "Last month" label; the
                    // column headings have no columns to head.
                    Text("This month").font(.caption2)
                        .foregroundStyle(AETheme.mutedText)
                } else {
                    HStack {
                        Spacer()
                        Text("This month").font(.caption2)
                            .foregroundStyle(AETheme.mutedText)
                            .frame(width: 82, alignment: .trailing)
                        if card.hasClosedMonth {
                            Text("Last").font(.caption2)
                                .foregroundStyle(AETheme.mutedText)
                                .frame(width: 82, alignment: .trailing)
                        }
                    }
                }
                comparisonRow("Ticket revenue",
                              Money(cents: card.thisMonthBreakdown.revenueCents),
                              Money(cents: card.lastMonthBreakdown.revenueCents),
                              showsLast: card.hasClosedMonth)
                comparisonRow("Fuel",
                              Money(cents: -card.thisMonthBreakdown.fuelCents),
                              Money(cents: -card.lastMonthBreakdown.fuelCents),
                              showsLast: card.hasClosedMonth)
                comparisonRow("Airport fees",
                              Money(cents: -card.thisMonthBreakdown.feesCents),
                              Money(cents: -card.lastMonthBreakdown.feesCents),
                              showsLast: card.hasClosedMonth)
                // The fee line's reason, from the same content the flight
                // system charges (AE-040): the two movements for this
                // aircraft's size and the passenger charge.
                if let terms = card.feeTerms {
                    Text(Vocab.feeTerms(terms,
                                        origin: catalog.airport(card.origin)?.city ?? card.origin.raw,
                                        destination: catalog.airport(card.destination)?.city ?? card.destination.raw))
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("ae-route-fee-terms")
                }
                comparisonRow("Crew",
                              Money(cents: -card.thisMonthBreakdown.crewCents),
                              Money(cents: -card.lastMonthBreakdown.crewCents),
                              showsLast: card.hasClosedMonth)
                Divider()
                comparisonRow("Direct operating profit", card.thisMonthProfit,
                              card.lastMonthProfit, showsLast: card.hasClosedMonth,
                              emphasised: true)
                Text("\(Format.count(card.thisMonthPassengers)) passengers this month · fleet costs and company overhead are airline-level (see Finance)")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Today's market, which the route has always known and never showed.
    private func demandSection(_ card: RouteCardModel, snapshot: GameState) -> some View {
        AEPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Today's market", systemImage: "person.3")
                if let route = snapshot.routes[card.id] {
                    let offered = route.demandOutboundToday + route.demandInboundToday
                    let left = route.remainingOutboundToday + route.remainingInboundToday
                    let taken = max(0, offered - left)
                    LazyVGrid(columns: instrumentColumns, spacing: 10) {
                        AEInstrument(label: "People wanting to fly today",
                                     value: Format.count(Int64(offered)), icon: "person.2")
                        AEInstrument(label: "Seats you have sold today",
                                     value: Format.count(Int64(taken)), icon: "ticket",
                                     tint: AETheme.positive)
                    }
                    if offered > 0 {
                        ProgressView(value: Double(taken) / Double(offered))
                            .tint(AETheme.accent)
                        Text(left > 0
                             ? "\(Format.count(Int64(left))) are still looking — more frequency or a lower fare would reach them."
                             : "You are carrying everyone this market offers today. More frequency needs more demand, not more seats.")
                            .font(.caption)
                            .foregroundStyle(AETheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func operations(_ card: RouteCardModel) -> some View {
        AEPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingM) {
                AESectionHeader(text: "Flight performance", systemImage: "gauge.with.dots.needle.67percent")
                LazyVGrid(columns: instrumentColumns, spacing: 10) {
                    // Like punctuality and completion below: no flights, no
                    // load factor — not a measured 0%.
                    AEInstrument(label: "Load factor",
                                 value: card.hasFlown ? Format.percent(card.loadFactor) : "—",
                                 icon: "person.2.fill")
                    AEInstrument(label: "Aircraft assigned", value: "\(card.assignedAircraftCount)",
                                 icon: "airplane", tint: AETheme.leased)
                    AEInstrument(label: "Punctuality",
                                 value: card.hasFlown ? Format.percent(card.punctuality) : "—",
                                 icon: "clock", tint: AETheme.positive)
                    AEInstrument(label: "Completion",
                                 value: card.hasFlown ? Format.percent(card.completionRate) : "—",
                                 icon: "checkmark.seal", tint: AETheme.positive)
                }
                labelled("Frequency", card.dailyRoundTrips == 1
                         ? "1 round trip a day"
                         : "\(card.dailyRoundTrips) round trips a day")
                labelled("Distance", "\(Format.count(Int64(card.distanceKm))) km")
            }
        }
    }

    private var instrumentColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
              count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    private func installedSeats(_ card: FleetCardModel, catalog: ContentCatalog) -> Int {
        guard let spec = catalog.aircraftType(card.typeCode) else { return 0 }
        return controller.snapshot?.aircraft[card.id]?.cabin(for: spec).totalSeats ?? spec.seats
    }

    /// Who flies this route — and the way to put an idle aircraft on it
    /// (without this, nothing ever takes off).
    ///
    /// `candidates` is Core's eligibility for this route, which is the whole
    /// point: this list used to be "unassigned and active", which offered
    /// aeroplanes that could not reach the route or land on its runways, and
    /// hid ones in a maintenance check that Core would have accepted. See
    /// `AssignmentEligibility` — the rules live beside the validator they
    /// mirror, and a test fails the day the two disagree.
    private func aircraftSection(_ card: RouteCardModel, player: AirlineID,
                                 catalog: ContentCatalog,
                                 candidates: [AssignmentCandidate]) -> some View {
        let fleet = controller.fleetCards
        let assigned = fleet.filter { $0.assignedRoute == routeID }
        let offerable = candidates.filter { $0.isEligible }
        let unavailable = candidates.filter {
            // Aircraft already on *this* route are listed above as assigned,
            // not repeated here as a reason they cannot be added again.
            if case .alreadyAssigned(let other)? = $0.blocker { return other != routeID }
            return $0.blocker != nil
        }
        return AECard(tint: assigned.isEmpty ? AETheme.caution.opacity(0.18) : nil) {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Aircraft", systemImage: "airplane")
                if assigned.isEmpty {
                    // Airport fees are charged per flight, so an unflown route
                    // pays none; what it does cost is its share of payroll,
                    // billed per open route every month (EconomySystem).
                    Label("No aircraft — this route is not flying. It earns nothing, and its payroll still costs \(Format.money(catalog.tuning.finance.payrollPerRouteMonthly)) a month.",
                          systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(assigned, id: \.id) { aircraft in
                    // Asked before the tap, as the fleet screen does: an
                    // aircraft with a flight under way cannot be taken off
                    // the route, and the button used to find that out by
                    // failing.
                    let unassign = UnassignAircraftCommand(airline: player,
                                                           aircraftID: aircraft.id)
                    let blocked = controller.precheck(unassign)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            NavigationLink(value: aircraft.id) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(aircraft.typeName).font(.subheadline)
                                    Text("\(installedSeats(aircraft, catalog: catalog)) seats · condition \(Format.percent(aircraft.condition))")
                                        .font(.caption)
                                        .foregroundStyle(AETheme.mutedText)
                                }
                            }
                            Spacer()
                            Button("Unassign") {
                                controller.submit(unassign)
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                            .frame(minHeight: 44)
                            .disabled(blocked != nil)
                        }
                        if let blocked {
                            RefusalNote(rejection: blocked, detail: .advice,
                                        tint: AETheme.mutedText)
                        }
                    }
                }
                if offerable.isEmpty, assigned.isEmpty {
                    Text(unavailable.isEmpty
                         ? "You own no aircraft yet. Buy or lease one, and it can fly this route."
                         : "No aircraft you own can fly this route today. The reasons are below.")
                        .font(AEType.caption)
                        .foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !offerable.isEmpty {
                    Menu {
                        ForEach(offerable, id: \.aircraftID) { candidate in
                            if let card = controller.fleetCard(candidate.aircraftID) {
                                Button {
                                    controller.submit(AssignAircraftToRouteCommand(
                                        airline: player, route: routeID,
                                        aircraftID: candidate.aircraftID))
                                } label: {
                                    if let note = Vocab.assignmentNote(candidate.note) {
                                        Text("\(card.typeName) at \(card.location.raw) — \(note)")
                                    } else {
                                        Text("\(card.typeName) at \(card.location.raw)")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Assign an aircraft", systemImage: "plus")
                            .font(AEType.body.weight(.medium))
                            .frame(minHeight: 44)
                    }
                }
                Button { showingAircraftMarket = true } label: {
                    Label("Find an aircraft for this route", systemImage: "airplane.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.aeSecondary)
                .accessibilityIdentifier("ae-route-find-aircraft")
                // The ones that cannot, and why. Listing them is the fix for
                // the original defect: an aeroplane the player owns silently
                // missing from the picker is indistinguishable from a bug.
                if !unavailable.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(unavailable, id: \.aircraftID) { candidate in
                            if let card = controller.fleetCard(candidate.aircraftID),
                               let blocker = candidate.blocker {
                                HStack(spacing: AETheme.spacingXS) {
                                    Text(card.typeName).font(AEType.caption)
                                    Spacer()
                                    Text(Vocab.blocker(blocker))
                                        .font(AEType.caption)
                                        .foregroundStyle(AETheme.mutedText)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    /// Who else flies this city pair, and what it is doing to this route.
    ///
    /// This section used to list rivals' fares and frequencies and stop
    /// there. Measured on the seed-2039 campaign (docs/RIVAL_PRESSURE_AUDIT.md
    /// §3): a player who entered London–Paris under two incumbents held a
    /// third of the market at full load, lost money every month, was answered
    /// with a fare cut and sixteen extra daily rotations — and the screen
    /// could not say whether they were winning, why, or what to do. Now it
    /// says all three, from `MarketCompetition`: the demand engine's own
    /// split, restated.
    private func competitorSection(_ card: RouteCardModel, snapshot: GameState,
                                   player: AirlineID) -> some View {
        let model = controller.catalog.flatMap {
            snapshot.marketCompetition(for: card.id, catalog: $0)
        }
        return AECard(tint: model?.standing == .trailing
                      ? AETheme.caution.opacity(0.12) : nil) {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Who else flies this", systemImage: "person.2")
                if let model, model.isContested {
                    if let standing = Vocab.standing(model) {
                        Text(standing)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(standingTint(model.standing))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("ae-route-standing")
                    }
                    if let share = model.playerShareToday {
                        shareBar(share: share, model: model, snapshot: snapshot)
                    }
                    ForEach(model.rivals, id: \.routeID) { rival in
                        rivalRow(rival, card: card)
                    }
                    if let response = Vocab.competitiveResponse(model) {
                        Label(response, systemImage: "arrow.turn.down.right")
                            .font(.caption)
                            .foregroundStyle(AETheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("ae-route-response")
                    }
                } else {
                    Text("Nobody. This market is yours alone — for now.")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.mutedText)
                }
            }
        }
    }

    private func standingTint(_ standing: MarketCompetition.Standing) -> Color {
        switch standing {
        case .leading: AETheme.positive
        case .trailing: AETheme.negative
        case .even, .tooEarly, .alone: AETheme.mutedText
        }
    }

    /// Today's split of the market, you first, in each carrier's colour.
    private func shareBar(share: Double, model: MarketCompetition,
                          snapshot: GameState) -> some View {
        let mine = Vocab.liveryColor(snapshot.playerAirline?.livery ?? .default)
        return VStack(alignment: .leading, spacing: 2) {
            GeometryReader { proxy in
                HStack(spacing: 1) {
                    Rectangle().fill(mine)
                        .frame(width: max(2, proxy.size.width * share))
                    ForEach(model.rivals, id: \.routeID) { rival in
                        Rectangle().fill(Vocab.liveryColor(rival.livery).opacity(0.7))
                            .frame(width: max(0, proxy.size.width * (rival.shareToday ?? 0)))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            Text("Today's passengers: you \(Format.percent(share)) · \(Format.count(Int64(model.marketDemandToday))) wanted to fly this pair")
                .font(.caption2)
                .foregroundStyle(AETheme.mutedText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your share of today's passengers \(Format.percent(share))")
    }

    private func rivalRow(_ rival: RivalOffer, card: RouteCardModel) -> some View {
        HStack {
            Circle()
                .fill(Vocab.liveryColor(rival.livery))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: AETheme.spacingXS) {
                    Text(rival.name).font(.subheadline)
                    if rival.isBasedOnPair {
                        AEBadge(text: "their hub", color: AETheme.rivalRoute, icon: "house")
                    }
                }
                Text("\(rival.dailyRoundTrips)×/day · reputation \(Format.percent(rival.reputationScore))\(rival.shareToday.map { " · \(Format.percent($0)) of today" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.money(rival.fare))
                    .font(.subheadline).monospacedDigit()
                Text(comparison(rival.fare, card.ticketPrice))
                    .font(.caption2)
                    .foregroundStyle(rival.fare < card.ticketPrice
                                     ? AETheme.negative : AETheme.mutedText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func comparison(_ theirs: Money, _ ours: Money) -> String {
        guard ours.cents != 0 else { return "" }
        let ratio = Double(theirs.cents) / Double(ours.cents)
        if abs(ratio - 1) < 0.02 { return "same as you" }
        let percent = abs(Int(((ratio - 1) * 100).rounded()))
        return ratio < 1 ? "\(percent)% under you" : "\(percent)% over you"
    }

    private func dangerZone(player: AirlineID) -> some View {
        let close = CloseRouteCommand(airline: player, route: routeID)
        // Core will not close a route with flights in the air. Asked before
        // the confirmation rather than after it, so the button says so
        // instead of accepting a confirmed tap and refusing it.
        let blocked = controller.precheck(close)
        return AEPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Close this route", systemImage: "xmark.circle")
                Text("Closing frees the slots at both airports and unassigns its aircraft. It cannot be undone; reopening starts the route's history from nothing.")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                ConfirmableButton(
                    title: "Close this route?",
                    message: "The slots are released and the route's history is lost. This cannot be undone.",
                    confirmTitle: "Close route",
                    role: .destructive,
                    action: {
                        // Only leave if the route actually closed; the
                        // rejection alert is useless behind a dismissed sheet.
                        if controller.submit(close) == nil {
                            dismiss()
                        }
                    }
                ) {
                    Label("Close route", systemImage: "xmark.circle")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(AETheme.negative)
                .disabled(blocked != nil)
                if let blocked {
                    RefusalNote(rejection: blocked, detail: .advice)
                }
            }
        }
    }

    /// Two 82pt columns at ordinary sizes. At accessibility sizes a figure no
    /// longer fits 82pt and broke mid-number, so each row stacks instead —
    /// label, this month, then last month named in words.
    @ViewBuilder
    private func comparisonRow(_ label: String, _ thisMonth: Money, _ lastMonth: Money,
                               showsLast: Bool, emphasised: Bool = false) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(emphasised ? .subheadline.weight(.semibold) : .subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                MoneyText(money: thisMonth)
                    .font(.subheadline)
                if showsLast {
                    Text("Last month \(Format.money(lastMonth))")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack {
                Text(label)
                    .font(emphasised ? .subheadline.weight(.semibold) : .subheadline)
                Spacer()
                MoneyText(money: thisMonth)
                    .font(.subheadline)
                    .frame(width: 82, alignment: .trailing)
                if showsLast {
                    Text(Format.money(lastMonth))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(AETheme.mutedText)
                        .frame(width: 82, alignment: .trailing)
                }
            }
        }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}

extension FleetCardModel {
    /// Seat count for a fleet card, from the catalog the card was built with.
    func seats(in catalog: ContentCatalog) -> Int {
        catalog.aircraftType(typeCode)?.seats ?? 0
    }
}

/// Opening a route.
///
/// Rebuilt around one rule: **nothing here may surprise the player at the
/// confirm step**. It used to be two 80-row pickers and a fare slider, with no
/// range check, no runway check, no slot check, no cost, and no demand — and
/// it dismissed unconditionally on Open, so a rejection destroyed every input
/// and raised an alert underneath a sheet that had already gone
/// (UIUX_FORENSIC_AUDIT UI-004, UI-006).
///
/// Now the destination list is ranked by expected demand and states distance,
/// the market fare and whether the player's own fleet can actually serve it;
/// the Open button carries Core's verdict before it is pressed; and a refusal
/// keeps the sheet open with the reason attached.
struct OpenRouteSheet: View {
    @Environment(GameController.self) private var controller
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.dismiss) private var dismiss
    @State private var origin: AirportCode?
    @State private var destination: AirportCode?
    @State private var trips = PlayerRouteDefaults.dailyRoundTrips
    @State private var fare: Double = 0
    @State private var fareTouched = false
    @State private var search = ""
    @State private var rejection: CommandRejection?
    @State private var filter: RouteDiscoveryFilter = .all
    @State private var createdRoute: RouteID?
    @State private var primed = false
    @State private var opening = false
    @State private var markets: [MarketOpportunity] = []
    /// Idle aircraft that could fly each destination, counted when the
    /// markets are. Every row used to ask Core for its own count — a walk of
    /// the whole fleet per destination, on every pass of `body`.
    @State private var idleCounts: [AirportCode: Int] = [:]

    private enum RouteDiscoveryFilter: String, CaseIterable {
        case all, idle, fleet, uncontested
        var title: String {
            switch self {
            case .all: "All destinations"
            case .idle: "Fits idle aircraft"
            case .fleet: "Fits my fleet"
            case .uncontested: "No competitors"
            }
        }
        var symbol: String {
            switch self {
            case .all: "globe"
            case .idle: "airplane"
            case .fleet: "checkmark.circle"
            case .uncontested: "sparkles"
            }
        }
    }
    /// The airports this player may serve, resolved once.
    ///
    /// Cached in state rather than computed in `destinations`, which runs
    /// inside `body`: the free set is the twenty nearest to home, and finding
    /// them sorts every airport in the catalogue by distance. That is cheap
    /// once and wasteful forty times a scroll — the same O(world)-per-frame
    /// mistake `GameController`'s derived caches exist to stop (UI-016).
    @State private var servableAirports: Set<AirportCode> = []

    private let prefill: FirstRouteSuggestion?
    private var selectedAirport: AirportCode?

    init() { self.prefill = nil }

    init(airport: AirportCode) {
        self.prefill = nil
        self.selectedAirport = airport
    }

    /// Pre-filled from an onboarding suggestion (guided first route).
    init(suggestion: FirstRouteSuggestion) {
        self.prefill = suggestion
    }

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = controller.snapshot,
                   let player = snapshot.playerAirline,
                   let catalog = controller.catalog {
                    content(snapshot: snapshot, player: player, catalog: catalog)
                } else {
                    LoadingState(message: "Loading the world")
                }
            }
            .onChange(of: controller.mapRouteRequest) { _, request in
                if request != nil { dismiss() }
            }
            .navigationTitle("Open a route")
            .disabled(opening)
            .interactiveDismissDisabled(opening)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(opening)
                }
            }
            .onAppear {
                #if DEBUG
                Logger(subsystem: "com.airlineempire.presentation", category: "route-setup")
                    .notice("Route setup appeared; primed: \(primed), has destination: \(destination != nil), has created route: \(createdRoute != nil)")
                #endif
                prime()
            }
            .onChange(of: createdRoute) { _, value in
                #if DEBUG
                Logger(subsystem: "com.airlineempire.presentation", category: "route-setup")
                    .notice("Route setup destination changed; has route: \(value != nil)")
                #endif
            }
            .onChange(of: origin) { refreshMarkets() }
            .onChange(of: filter) {
                guard let destination, let snapshot = controller.snapshot,
                      let catalog = controller.catalog,
                      let from = origin ?? snapshot.playerAirline?.homeAirport else { return }
                if !destinations(from: from, snapshot: snapshot, catalog: catalog)
                    .contains(where: { $0.code == destination }) {
                    self.destination = nil
                    rejection = nil
                }
            }
            // The day, not `currentDate`: that carries the hour and minute,
            // so the ~90 destinations were re-ranked on every tick for a
            // ranking that changes when demand does — at the daily update.
            .onChange(of: controller.snapshot?.clock.now.dayIndex) { refreshMarkets() }
            .onChange(of: controller.snapshot?.orderedAircraftIDs) { refreshMarkets() }
            // An assignment made from the route this sheet just opened
            // changes which aircraft are idle without changing the fleet.
            .onChange(of: controller.fleetSummary?.idle) { refreshMarkets() }
            .onChange(of: controller.snapshot?.orderedRouteIDs) {
                refreshMarkets()
                guard opening, let player = controller.snapshot?.playerAirline,
                      let from = origin, let to = destination,
                      let route = controller.snapshot?.routes(of: player.id).first(where: {
                          $0.sameMarket(origin: from, destination: to)
                      }) else { return }
                opening = false
                createdRoute = route.id
            }
            .onChange(of: controller.lastRejection) {
                guard opening, let failure = controller.lastRejection else { return }
                opening = false
                rejection = failure
                controller.clearRejection()
            }
            .navigationDestination(item: $createdRoute) { routeID in
                RouteDetailView(routeID: routeID)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                                .accessibilityIdentifier("ae-route-setup-done")
                        }
                    }
            }
            .navigationDestination(for: AircraftID.self) { AircraftDetailView(aircraftID: $0) }
            // Buying Pro from inside this sheet opens the rest of the map
            // without closing and reopening it.
            .onChange(of: entitlements.access) { _, _ in
                refreshServableAirports()
            }
            .aeSheetFeedback()
            // The route-creation journey, in three beats
            // (docs/AUDIO_ARCHITECTURE.md §5). Choosing where you fly from is
            // a selection; choosing where you fly *to* is the moment the line
            // between two cities exists, so it resolves upward; and the
            // commit is voiced by `routeOpened` when Core says it happened,
            // not when the button was pressed.
            .aeFeedback(.uiSelect, on: origin)
            .aeFeedback(.uiConfirm, on: destination)
        }
    }

    private func prime() {
        defer { refreshMarkets() }
        refreshServableAirports()
        guard !primed else { return }
        primed = true
        if let selectedAirport, let snapshot = controller.snapshot,
           let player = snapshot.playerAirline, let catalog = controller.catalog {
            if servedOrHome(snapshot: snapshot, player: player).contains(selectedAirport) {
                origin = selectedAirport
            } else {
                origin = player.homeAirport
                destination = selectedAirport
                if let distance = catalog.distanceKm(player.homeAirport, selectedAirport) {
                    fare = DemandSystem.referenceFare(distanceKm: distance,
                                                      tuning: catalog.tuning.demand)
                }
            }
            return
        }
        if let prefill {
            origin = prefill.origin
            // The guided first route is chosen from near home and so is
            // always inside the free set — but "always" is an assumption
            // about another file, and this sheet is the last place that can
            // check it before the player is handed a destination they cannot
            // open.
            guard servableAirports.isEmpty
                    || servableAirports.contains(prefill.destination) else {
                if !fareTouched { fare = prefill.referenceFare.asDouble }
                return
            }
            destination = prefill.destination
            if !fareTouched { fare = prefill.referenceFare.asDouble }
            return
        }
        if origin == nil { origin = controller.snapshot?.playerAirline?.homeAirport }
    }

    @ViewBuilder
    private func content(snapshot: GameState, player: Airline,
                         catalog: ContentCatalog) -> some View {
        let from = origin ?? player.homeAirport
        let candidates = destinations(from: from, snapshot: snapshot, catalog: catalog)
        List {
            // No header here: the picker inside carries the label "From", and
            // a section header saying it again stacked the word on itself
            // (AE-033 audit §6.5).
            if search.isEmpty {
                Section {
                    FirstFlightProgress()
                    originPicker(catalog: catalog, snapshot: snapshot, player: player)
                }
                Section {
                    PlanningFilters(options: RouteDiscoveryFilter.allCases.map {
                        PlanningFilterOption(value: $0, title: $0.title, symbol: $0.symbol)
                    }, selection: $filter)
                    .listRowBackground(Color.clear)
                    Text("Destinations: \(candidates.count) · ranked by passenger demand")
                        .font(.caption).foregroundStyle(AETheme.mutedText)
                }
            } else {
                // Leave room for actual results above the keyboard and the
                // pinned action bar. Clearing search restores the controls.
                Section {
                    HStack {
                        Text("From \(from.raw)")
                        Spacer()
                        Text(filter.title)
                    }
                    .font(.caption).foregroundStyle(AETheme.mutedText)
                }
            }

            Section {
                if candidates.isEmpty {
                    Text("No destinations match your search and filter.")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.mutedText)
                    Button("Reset filters") { search = ""; filter = .all }
                }
                ForEach(candidates, id: \.code) { candidate in
                    destinationRow(candidate)
                }
            } header: {
                Text(search.isEmpty ? "To — ranked by how many people want to fly it" : "Matching destinations")
            }

            if let destination, destination != from {
                Section {
                    serviceControls(from: from, to: destination, catalog: catalog)
                } header: {
                    Text("Service")
                }
            }
        }
        // Pinned to the destination list rather than left to float. iOS 26
        // anchors a bare `.searchable` to the bottom of the sheet, which put
        // the search field *below* the "Open this route" bar: browse, commit,
        // then search (AE-033 audit §6.5). `.navigationBarDrawer` puts it
        // back above the thing it filters.
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Airport code or city")
        .scrollDismissesKeyboard(.interactively)
        // The chosen row's marker fills rather than swaps: at the moment of
        // the tap, the only feedback this sheet gives is that circle.
        .aeAnimation(AEMotion.selection, value: destination)
        // The commit rides the bottom edge rather than living at the foot of
        // the list. It used to be the last row after all ~40 candidates, so a
        // player who picked LNW — the top-ranked suggestion — then had to
        // scroll past every destination they had just rejected to find the
        // button that acts on their choice. The first screenshot of this
        // sheet is what made that visible; the UI test that drives this
        // journey could not find the button either, which is the same finding
        // made by a machine (BUG-038).
        // Always present, even with nothing chosen. It used to appear on
        // selection, which had two costs: the list jumped by the height of a
        // bar at the moment of the tap, and — because the bar covers the row
        // it appears over — the row the player had just chosen was the one it
        // covered. A screenshot caught exactly that: three destinations with
        // empty circles and a commit bar over the fourth, so the sheet showed
        // no selected row at all (tasks/BUGS.md BUG-059). The bar now states
        // the choice itself, so what happens on press is legible whether or
        // not its row is on screen.
        .safeAreaInset(edge: .bottom) {
            Group {
                if let destination, destination != from {
                    confirmRow(from: from, to: destination, player: player)
                } else {
                    waitingRow(from: from)
                }
            }
            .padding(.horizontal, AETheme.spacingM)
            .padding(.vertical, AETheme.spacingS)
            .background(.bar)
        }
        .aeScreenBackground()
    }

    private func originPicker(catalog: ContentCatalog, snapshot: GameState,
                              player: Airline) -> some View {
        Picker("From", selection: Binding(
            get: { origin ?? player.homeAirport },
            set: { origin = $0; destination = nil; rejection = nil; fareTouched = false })) {
            ForEach(servedOrHome(snapshot: snapshot, player: player), id: \.self) { code in
                Text("\(code.raw) — \(catalog.airport(code).map(Vocab.airportDisplay) ?? "")").tag(code)
            }
        }
        .accessibilityHint("Routes start from an airport you already serve")
        .accessibilityIdentifier("ae-route-origin")
    }

    /// You can only start a route where you already have a presence. Offering
    /// all 80 airports invited a route between two cities the airline has
    /// never been to, which is a rejection waiting to happen.
    private func servedOrHome(snapshot: GameState, player: Airline) -> [AirportCode] {
        var codes = Set<AirportCode>([player.homeAirport])
        for route in snapshot.routes(of: player.id) {
            codes.insert(route.origin)
            codes.insert(route.destination)
        }
        return codes.sorted { $0.raw < $1.raw }
    }

    private struct Candidate {
        /// Outside what this player has bought (docs/MONETIZATION.md §4).
        /// Kept in the list rather than filtered out of it: a destination the
        /// player can see, priced and ranked, is an argument for Pro, and a
        /// destination silently missing is a map that looks smaller than it
        /// is.
        var locked = false
        let code: AirportCode
        let name: String
        let city: String
        let country: String
        let distanceKm: Int
        let referenceFare: Money
        let servable: Bool
        let servableByEra: Bool
        /// Passengers a starter service could expect to capture per day
        /// across both directions — the same figure the onboarding card
        /// shows, so the guided path and the manual one agree.
        let expectedDailyPassengers: Int
        /// Airlines already flying this city pair. Core computes this for
        /// every candidate and the sheet used to discard it, so the one thing
        /// §14 asks for that a player cannot see for themselves — who else is
        /// already there — was the one thing missing.
        let incumbents: Int
        let idleCount: Int
    }

    /// Every airport the player could fly to from `from`, ranked by
    /// capturable demand, marked with whether the current fleet can reach it.
    ///
    /// The ranking and the demand figure come from Core
    /// (`marketCandidates(from:catalog:)`), not from arithmetic here. The
    /// first attempt computed the demand in this file and did not compile:
    /// `DemandSystem.demandPool` is internal to Core, which is the module
    /// boundary doing exactly its job. Economics belongs behind it, where the
    /// test suite can reach it.
    private func refreshServableAirports() {
        guard let catalog = controller.catalog,
              let home = controller.snapshot?.playerAirline?.homeAirport else { return }
        servableAirports = entitlements.access.servableAirports(home: home,
                                                               catalog: catalog)
    }

    private func destinations(from: AirportCode, snapshot: GameState,
                              catalog: ContentCatalog) -> [Candidate] {
        let needle = search.uppercased()
        let existingMarkets = Set(snapshot.playerAirline.map { snapshot.routes(of: $0.id).map(\.market) } ?? [])
        return markets
            .compactMap { market -> Candidate? in
                guard !existingMarkets.contains(Route.market(from, market.destination)) else { return nil }
                guard let spec = catalog.airport(market.destination) else { return nil }
                let idleCount = idleCounts[market.destination] ?? 0
                switch filter {
                case .all: break
                case .idle: guard idleCount > 0 else { return nil }
                case .fleet: guard market.servableNow else { return nil }
                case .uncontested: guard market.incumbents == 0 else { return nil }
                }
                if !needle.isEmpty,
                   !market.destination.raw.uppercased().contains(needle),
                   !spec.city.uppercased().contains(needle) { return nil }
                return Candidate(
                    locked: !servableAirports.contains(market.destination),
                    code: market.destination, name: spec.name,
                    city: market.destinationCity,
                    country: spec.country, distanceKm: market.distanceKm,
                    referenceFare: market.referenceFare,
                    servable: market.servableNow,
                    servableByEra: market.servableByEra,
                    expectedDailyPassengers: market.expectedDailyPassengers,
                    incumbents: market.incumbents, idleCount: idleCount)
            }
    }

    private func refreshMarkets() {
        guard let snapshot = controller.snapshot, let catalog = controller.catalog,
              let from = origin ?? snapshot.playerAirline?.homeAirport else { return }
        let ranked = snapshot.marketCandidates(from: from, catalog: catalog)
        var counts: [AirportCode: Int] = [:]
        for market in ranked {
            counts[market.destination] = snapshot.idleAircraft(
                from: from, to: market.destination, catalog: catalog).count
        }
        markets = ranked
        idleCounts = counts
    }

    private func destinationRow(_ candidate: Candidate) -> some View {
        Button {
            // A locked destination answers with the reason it is locked and
            // does not become the selection — selecting it would arm an
            // "Open this route" button whose only possible outcome is a
            // refusal.
            guard !candidate.locked else {
                entitlements.present(.airport)
                return
            }
            destination = candidate.code
            if !fareTouched { fare = candidate.referenceFare.asDouble }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AETheme.spacingXS) {
                        Text(candidate.code.raw)
                            .font(.subheadline.weight(.semibold)).monospaced()
                        Text(Vocab.airportDisplay(name: candidate.name,
                                                  city: candidate.city))
                            .font(.subheadline)
                    }
                    Text("≈\(Format.count(Int64(candidate.expectedDailyPassengers))) passengers/day · \(Format.count(Int64(candidate.distanceKm))) km · fare ≈ \(Format.money(candidate.referenceFare))")
                        .font(AEType.secondary)
                        .foregroundStyle(AETheme.mutedText)
                    if candidate.idleCount > 0 {
                        Label(candidate.idleCount == 1 ? "1 idle aircraft fits" : "\(candidate.idleCount) idle aircraft fit", systemImage: "airplane")
                            .font(.caption).foregroundStyle(AETheme.positive)
                    }
                    // Who is already there. An open market and a contested one
                    // are different decisions at the same demand.
                    Text(candidate.incumbents == 0
                         ? "Nobody flies this yet"
                         : candidate.incumbents == 1
                           ? "1 airline already flies it"
                           : "\(candidate.incumbents) airlines already fly it")
                        .font(AEType.caption)
                        .foregroundStyle(candidate.incumbents == 0
                                         ? AETheme.positive : AETheme.mutedText)
                    if candidate.locked {
                        // A third kind of "not yet", named as plainly as the
                        // other two: this one is not about the fleet or the
                        // era, and pretending otherwise would be a lie the
                        // player can check.
                        Text("Outside your free region — opens with Pro")
                            .font(.caption2)
                            .foregroundStyle(AETheme.ember)
                    } else if !candidate.servable {
                        // Which kind of impossible matters (AE-035's dead
                        // route): "get the right aircraft" is a next action,
                        // "wait for a later era" is an aspiration.
                        Text(candidate.servableByEra
                             ? "Nothing in your fleet can serve it — the market sells aircraft that could"
                             : "Beyond this era's aircraft — a route for a later fleet")
                            .font(.caption2)
                            .foregroundStyle(candidate.servableByEra
                                             ? AETheme.caution : AETheme.mutedText)
                    }
                }
                Spacer()
                if candidate.locked {
                    ProBadge()
                } else {
                    Image(systemName: destination == candidate.code
                          ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(destination == candidate.code
                                         ? AETheme.accent : Color.secondary.opacity(0.4))
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.aePress)
        .accessibilityAddTraits(destination == candidate.code
                                ? [.isButton, .isSelected] : .isButton)
        // A stable name for automation. `app.cells.firstMatch` on this sheet
        // is the From picker, not a destination — which is exactly the tap
        // the journey test made, silently selecting nothing (BUG-038's other
        // half, and the same class as the "Lease term" stepper mismatch).
        .accessibilityIdentifier("ae-route-destination")
    }

    private func serviceControls(from: AirportCode, to: AirportCode,
                                 catalog: ContentCatalog) -> some View {
        let reference = catalog.distanceKm(from, to).map {
            DemandSystem.referenceFare(distanceKm: $0, tuning: catalog.tuning.demand)
        }
        // The market fare grows with distance and passes $800 near 9,000 km,
        // so a fixed 30...800 range clamped a long-haul fare the moment the
        // slider was touched — a $1,100 fare silently became $800. Twice the
        // reference keeps the same headroom above the market on every route.
        let upperFare = max(800, ((reference ?? 0) * 2).rounded())
        return VStack(alignment: .leading, spacing: AETheme.spacingS) {
            Stepper("Round trips per day: \(trips)", value: $trips, in: 1...20)
                .frame(minHeight: 44)
            VStack(alignment: .leading, spacing: AETheme.spacingXS) {
                HStack {
                    Text("Fare")
                    Spacer()
                    Text(Format.money(Money.dollars(Int64(fare))))
                        .monospacedDigit()
                }
                Slider(value: $fare, in: 30...upperFare, step: 1) { editing in
                    if editing { fareTouched = true }
                }
                .accessibilityLabel("Fare")
                .accessibilityValue(Format.money(Money.dollars(Int64(fare))))
                if let reference {
                    Text(fareGuidance(fare: fare, reference: reference))
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func fareGuidance(fare: Double, reference: Double) -> String {
        guard reference > 0 else { return "" }
        let ratio = fare / reference
        let market = "Market reference is \(Format.money(Money(rounding: reference)))."
        switch ratio {
        case ..<0.85: return "\(market) You are undercutting it — full aircraft, thin margins."
        case 0.85...1.25: return "\(market) You are priced with the market."
        default: return "\(market) Well above it — fewer passengers, more per seat."
        }
    }

    /// The bar before a destination is chosen: the same shape, the same
    /// place, saying what it is waiting for rather than vanishing.
    private func waitingRow(from: AirportCode) -> some View {
        HStack(spacing: AETheme.spacingS) {
            Image(systemName: "hand.tap")
                .foregroundStyle(AETheme.mutedText)
                .accessibilityHidden(true)
            Text("Pick where \(from.raw) flies to")
                .font(AEType.body)
                .foregroundStyle(AETheme.mutedText)
            Spacer()
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    /// The verdict, before the tap.
    private func confirmRow(from: AirportCode, to: AirportCode,
                            player: Airline) -> some View {
        let command = OpenRouteCommand(
            airline: player.id, origin: from, destination: to,
            dailyRoundTrips: trips, ticketPrice: Money.dollars(Int64(fare)))
        let blocked = controller.precheck(command)
        // Who could fly it: the fleet, something the era's market sells, or
        // nobody yet. Two spec scans against Core's own eligibility rule —
        // the same arithmetic the destination rows rank by.
        let canServe: (fleet: Bool, era: Bool) = {
            guard let snapshot = controller.snapshot,
                  let catalog = controller.catalog else { return (true, true) }
            let eligible: ([AircraftTypeSpec]) -> Bool = { specs in
                specs.contains { spec in
                    catalog.routeEligibility(
                        from: from, to: to,
                        aircraftRangeKm: spec.rangeKm,
                        aircraftRunwayRequirement: spec.runwayRequirement).isEmpty
                }
            }
            let owned = snapshot.fleet(of: player.id)
                .compactMap { catalog.aircraftType($0.typeCode) }
            let era = catalog.orderedAircraftTypeCodes
                .compactMap { catalog.aircraftType($0) }
                .filter { snapshot.progression.era.allowedCategories.contains($0.category) }
            return (eligible(owned), eligible(era))
        }()
        return VStack(alignment: .leading, spacing: AETheme.spacingS) {
            // The choice, restated where the action is. The rows carry the
            // detail; this carries the decision, and it is the only part
            // guaranteed to be on screen when the button is pressed.
            HStack(spacing: AETheme.spacingXS) {
                Text("\(from.raw) → \(to.raw)")
                    .font(AEType.code)
                Text("\(trips)×/day · \(Format.money(Money.dollars(Int64(fare)))) fare")
                    .font(AEType.secondary)
                    .foregroundStyle(AETheme.mutedText)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            if let blocked {
                RefusalNote(rejection: blocked)
                // A destination outside the free region is more world, not a
                // dead end: the refusal names what opens it, and one tap
                // shows what Pro is (docs/MONETIZATION.md §4). A locked row
                // tapped in the list already does this; a destination handed
                // to the sheet — from a map airport — arrived without it.
                if blocked.code == "access.proRequired" {
                    Button {
                        entitlements.present(.airport)
                    } label: {
                        Label("See what Pro opens", systemImage: "crown.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.aeSecondary)
                    .accessibilityIdentifier("ae-route-pro")
                }
            }
            // Opening a route no aircraft can fly is allowed — a route may
            // precede its aircraft — but it must never be a surprise: the
            // AE-035 campaign opened one and watched it sit unflown for two
            // months with nothing at the commit saying it would.
            if blocked == nil, !canServe.fleet {
                Label(canServe.era
                      ? "Nothing in your fleet can fly this yet — it will wait, unflown, until you acquire an aircraft that can."
                      : "No aircraft of this era can fly this — it will wait, unflown, for a later fleet.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(AETheme.caution)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ae-route-unservable")
            }
            if let rejection {
                RefusalNote(rejection: rejection, systemImage: "xmark.octagon",
                            tint: AETheme.negative)
            }
            Button {
                // The sheet stays open on refusal, keeping every input, and
                // says why right here.
                if let refusal = controller.submit(command) {
                    rejection = refusal
                    controller.clearRejection()
                } else {
                    opening = true
                }
            } label: {
                Label(opening ? "Opening route…" : "Open this route", systemImage: "airplane.departure")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.aePrimary)
            .disabled(blocked != nil || opening)
            .accessibilityIdentifier("ae-route-open")
        }
    }
}

/// A refusal in the player's words, for the space beside the control it
/// disables (MASTER PROMPT 4 §24).
///
/// Core's `message` is written for whoever reads the simulation — "Wait for
/// airborne flights to land before closing", "Unknown airport" — and inline
/// captions were showing it verbatim while the alerts already went through
/// `Rejections`. One mapping, so the two can never tell a player different
/// things about the same refusal.
struct RefusalNote: View {
    enum Detail {
        /// Title, why, and what to try — where there is room for all three.
        case full
        /// "Title. Why." — where the generic next step would be wrong for
        /// this control ("take a loan" is no advice for paying one off).
        case reason
        /// "Title. What to try." — under a small control, where the "why"
        /// only repeats the title.
        case advice
    }

    let rejection: CommandRejection
    var detail: Detail = .full
    var systemImage = "exclamationmark.triangle"
    var tint: Color = AETheme.caution

    var body: some View {
        let refusal = Rejections.present(rejection)
        Label {
            switch detail {
            case .full:
                VStack(alignment: .leading, spacing: 2) {
                    Text(refusal.title).fontWeight(.semibold)
                    Text(refusal.explanation)
                    if let suggestion = refusal.suggestion {
                        Text(suggestion)
                    }
                }
            case .reason:
                Text(refusal.title + ". " + refusal.explanation)
            case .advice:
                Text(refusal.title + ". " + (refusal.suggestion ?? refusal.explanation))
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption)
        .foregroundStyle(tint)
        .fixedSize(horizontal: false, vertical: true)
    }
}
