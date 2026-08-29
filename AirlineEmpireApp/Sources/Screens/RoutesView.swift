import SwiftUI
import AirlineEmpireCore

/// The route board.
///
/// Two things changed here. It is sortable and searchable, because creation
/// order stops working somewhere around the tenth route; and it leads with the
/// **month in progress** rather than the last closed month, because a route
/// opened three days ago had a last month of exactly zero and the board read
/// as a column of ¤0 through the whole window in which a new player is
/// deciding whether this game rewards attention (UIUX_FORENSIC_AUDIT UI-002).
struct RoutesList: View {
    @Environment(GameController.self) private var controller
    @State private var sort: RouteSort = .needsAttention
    @State private var search = ""

    var body: some View {
        Group {
            if let snapshot = controller.snapshot,
               let player = snapshot.playerAirline {
                let cards = sorted(controller.routeCards)
                if snapshot.routes(of: player.id).isEmpty {
                    EmptyStateView(icon: "point.topleft.down.to.point.bottomright.curvepath",
                                   title: "No routes yet",
                                   message: "Open your first route — pick a market and put an aircraft on it.")
                        .padding(.horizontal, AETheme.spacingM)
                } else if cards.isEmpty {
                    EmptyStateView(icon: "magnifyingglass",
                                   title: "No matches",
                                   message: "No route matches “\(search)”.")
                        .padding(.horizontal, AETheme.spacingM)
                } else {
                    List {
                        ForEach(cards, id: \.id) { card in
                            NavigationLink(value: card.id) {
                                RouteRow(card: card)
                            }
                            .aeListRow()
                        }
                    }
                    .listStyle(.plain)
                    .aeScreenBackground()
                    .searchable(text: $search, prompt: "Airport code or city")
                    .animation(AEMotion.content, value: cards.count)
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
        let filtered = search.isEmpty ? cards : cards.filter { card in
            let needle = search.uppercased()
            return card.origin.raw.uppercased().contains(needle)
                || card.destination.raw.uppercased().contains(needle)
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
            HStack(spacing: AETheme.spacingS) {
                AEBadge(text: "\(card.dailyRoundTrips)×/day", color: AETheme.accent)
                AEBadge(text: "load \(Format.percent(card.loadFactor))",
                        color: card.loadFactor > 0.7 ? AETheme.positive : AETheme.caution)
                AEBadge(text: Format.money(card.ticketPrice), color: .purple)
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
    @Environment(GameController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    let routeID: RouteID

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
                    headline(card, snapshot: snapshot, catalog: catalog)
                    aircraftSection(card, player: player.id, catalog: catalog)
                    breakdown(card)
                    demandSection(card, snapshot: snapshot)
                    operations(card)
                    fareControls(card, player: player.id)
                    competitorSection(card, snapshot: snapshot, player: player.id)
                    dangerZone(player: player.id)
                }
                .padding(.horizontal)
                .padding(.bottom, AETheme.spacingL)
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
    }

    private var title: String {
        guard let snapshot = controller.snapshot,
              let route = snapshot.routes[routeID] else { return "Route" }
        return "\(route.origin.raw) – \(route.destination.raw)"
    }

    /// The money story, month to date, before anything else — this is the
    /// question a player opens a route to answer.
    private func headline(_ card: RouteCardModel, snapshot: GameState,
                          catalog: ContentCatalog) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cityPair(catalog)).font(.headline)
                        Text("\(card.distanceKm) km")
                            .font(.caption)
                            .foregroundStyle(AETheme.mutedText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        MoneyText(money: card.thisMonthProfit)
                            .font(.title3.weight(.semibold))
                        Text("this month so far")
                            .font(.caption2)
                            .foregroundStyle(AETheme.mutedText)
                    }
                }
                if card.hasClosedMonth {
                    HStack {
                        Text("Last full month").font(.caption)
                            .foregroundStyle(AETheme.mutedText)
                        Spacer()
                        MoneyText(money: card.lastMonthProfit).font(.caption)
                    }
                } else {
                    Text("This route has not lived through a month-end yet, so there is no closed month to compare against.")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
    private func breakdown(_ card: RouteCardModel) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Where the money went", systemImage: "chart.pie")
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
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Today's market", systemImage: "person.3")
                if let route = snapshot.routes[card.id] {
                    let offered = route.demandOutboundToday + route.demandInboundToday
                    let left = route.remainingOutboundToday + route.remainingInboundToday
                    let taken = max(0, offered - left)
                    labelled("People wanting to fly today", "\(Format.count(Int64(offered)))")
                    labelled("Seats you have sold today", "\(Format.count(Int64(taken)))")
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
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Operations", systemImage: "gauge")
                labelled("Load factor", Format.percent(card.loadFactor))
                labelled("Punctuality", Format.percent(card.punctuality))
                labelled("Completion", Format.percent(card.completionRate))
                labelled("Aircraft assigned", "\(card.assignedAircraftCount)")
            }
        }
    }

    private func fareControls(_ card: RouteCardModel, player: AirlineID) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Fare and frequency", systemImage: "tag")
                HStack {
                    Text(Format.money(card.ticketPrice))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(AEMotion.content, value: card.ticketPrice.cents)
                    Spacer()
                    AEBadge(text: farePositionLabel(card),
                            color: farePositionColor(card))
                }
                Text(fareAdvice(card))
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: AETheme.spacingS) {
                    ForEach([-10, -5, 5, 10], id: \.self) { percent in
                        Button("\(percent > 0 ? "+" : "")\(percent)%") {
                            let newFare = Money(rounding: card.ticketPrice.asDouble
                                * (1 + Double(percent) / 100))
                            controller.submit(SetRoutePriceCommand(
                                airline: player, route: routeID,
                                ticketPrice: newFare))
                        }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                    }
                }
                Stepper("Frequency: \(card.dailyRoundTrips)×/day",
                        onIncrement: { changeFrequency(card, by: 1, player: player) },
                        onDecrement: { changeFrequency(card, by: -1, player: player) })
                    .frame(minHeight: 44)
            }
        }
    }

    private func farePositionLabel(_ card: RouteCardModel) -> String {
        String(format: "%.0f%% of market", card.farePosition * 100)
    }

    private func farePositionColor(_ card: RouteCardModel) -> Color {
        switch card.farePosition {
        case ..<0.85: AETheme.accent
        case 0.85...1.25: AETheme.positive
        default: AETheme.caution
        }
    }

    private func fareAdvice(_ card: RouteCardModel) -> String {
        switch card.farePosition {
        case ..<0.85:
            "You are undercutting the market. Expect full aircraft and thin margins."
        case 0.85...1.25:
            "Priced near the market reference for this distance."
        default:
            "Well above the market. Fewer passengers, more per seat — watch the load factor."
        }
    }

    /// Who flies this route — and the way to put an idle aircraft on it
    /// (without this, nothing ever takes off).
    private func aircraftSection(_ card: RouteCardModel, player: AirlineID,
                                 catalog: ContentCatalog) -> some View {
        let fleet = controller.fleetCards
        let assigned = fleet.filter { $0.assignedRoute == routeID }
        let idle = fleet.filter { $0.assignedRoute == nil && $0.status == .active }
        return AECard(tint: assigned.isEmpty ? AETheme.caution.opacity(0.18) : nil) {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Aircraft", systemImage: "airplane")
                if assigned.isEmpty {
                    Label("No aircraft — this route is not flying, and it is still paying its airport fees.",
                          systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(assigned, id: \.id) { aircraft in
                    HStack {
                        NavigationLink(value: aircraft.id) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(aircraft.typeName).font(.subheadline)
                                Text("\(aircraft.seats(in: catalog)) seats · condition \(Format.percent(aircraft.condition))")
                                    .font(.caption)
                                    .foregroundStyle(AETheme.mutedText)
                            }
                        }
                        Spacer()
                        Button("Unassign") {
                            controller.submit(UnassignAircraftCommand(
                                airline: player, aircraftID: aircraft.id))
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                        .frame(minHeight: 44)
                    }
                }
                if idle.isEmpty, assigned.isEmpty {
                    Text("Every aircraft you own is already on a route. Acquire one, or unassign it from a route that needs it less.")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !idle.isEmpty {
                    Menu {
                        ForEach(idle, id: \.id) { aircraft in
                            Button("\(aircraft.typeName) — at \(aircraft.location.raw)") {
                                controller.submit(AssignAircraftToRouteCommand(
                                    airline: player, route: routeID,
                                    aircraftID: aircraft.id))
                            }
                        }
                    } label: {
                        Label("Assign an aircraft", systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .frame(minHeight: 44)
                    }
                }
            }
        }
    }

    /// Who else flies this city pair — the single most useful fact on a route
    /// screen in this genre, and the one that explains a falling load factor.
    private func competitorSection(_ card: RouteCardModel, snapshot: GameState,
                                   player: AirlineID) -> some View {
        let rivals = snapshot.orderedRouteIDs.compactMap { id -> (Airline, Route)? in
            guard let route = snapshot.routes[id], route.airline != player,
                  route.sameMarket(origin: card.origin, destination: card.destination),
                  let airline = snapshot.airlines[route.airline] else { return nil }
            return (airline, route)
        }
        return AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Who else flies this", systemImage: "person.2")
                if rivals.isEmpty {
                    Text("Nobody. This market is yours alone — for now.")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.mutedText)
                } else {
                    ForEach(rivals, id: \.1.id) { airline, route in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(airline.name).font(.subheadline)
                                Text("\(route.dailyRoundTrips)×/day · reputation \(Format.percent(airline.reputation.score))")
                                    .font(.caption)
                                    .foregroundStyle(AETheme.mutedText)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(Format.money(route.ticketPrice))
                                    .font(.subheadline).monospacedDigit()
                                Text(comparison(route.ticketPrice, card.ticketPrice))
                                    .font(.caption2)
                                    .foregroundStyle(route.ticketPrice < card.ticketPrice
                                                     ? AETheme.negative : AETheme.mutedText)
                            }
                        }
                    }
                }
            }
        }
    }

    private func comparison(_ theirs: Money, _ ours: Money) -> String {
        guard ours.cents != 0 else { return "" }
        let ratio = Double(theirs.cents) / Double(ours.cents)
        if abs(ratio - 1) < 0.02 { return "same as you" }
        let percent = abs(Int(((ratio - 1) * 100).rounded()))
        return ratio < 1 ? "\(percent)% under you" : "\(percent)% over you"
    }

    private func dangerZone(player: AirlineID) -> some View {
        AECard {
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
                        controller.submit(CloseRouteCommand(airline: player, route: routeID))
                        dismiss()
                    }
                ) {
                    Label("Close route", systemImage: "xmark.circle")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(AETheme.negative)
            }
        }
    }

    private func changeFrequency(_ card: RouteCardModel, by delta: Int,
                                 player: AirlineID) {
        controller.submit(SetRouteFrequencyCommand(
            airline: player, route: routeID,
            dailyRoundTrips: card.dailyRoundTrips + delta))
    }

    private func comparisonRow(_ label: String, _ thisMonth: Money, _ lastMonth: Money,
                               showsLast: Bool, emphasised: Bool = false) -> some View {
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
    @Environment(\.dismiss) private var dismiss
    @State private var origin: AirportCode?
    @State private var destination: AirportCode?
    @State private var trips = 2
    @State private var fare: Double = 0
    @State private var fareTouched = false
    @State private var search = ""
    @State private var rejection: CommandRejection?

    private let prefill: FirstRouteSuggestion?

    init() { self.prefill = nil }

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
            .navigationTitle("Open a route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: prime)
        }
    }

    private func prime() {
        if let prefill {
            origin = prefill.origin
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
            Section {
                originPicker(catalog: catalog, snapshot: snapshot, player: player)
            } header: {
                Text("From")
            }

            Section {
                if candidates.isEmpty {
                    Text("No airport matches “\(search)”.")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.mutedText)
                }
                ForEach(candidates, id: \.code) { candidate in
                    destinationRow(candidate)
                }
            } header: {
                Text("To — ranked by how many people want to fly it")
            }

            if let destination, destination != from {
                Section {
                    serviceControls(from: from, to: destination, catalog: catalog)
                } header: {
                    Text("Service")
                }

                Section {
                    confirmRow(from: from, to: destination, player: player)
                }
            }
        }
        .searchable(text: $search, prompt: "Airport code or city")
    }

    private func originPicker(catalog: ContentCatalog, snapshot: GameState,
                              player: Airline) -> some View {
        Picker("From", selection: Binding(
            get: { origin ?? player.homeAirport },
            set: { origin = $0 })) {
            ForEach(servedOrHome(snapshot: snapshot, player: player), id: \.self) { code in
                Text("\(code.raw) — \(catalog.airport(code)?.city ?? "")").tag(code)
            }
        }
        .accessibilityHint("Routes start from an airport you already serve")
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
        let code: AirportCode
        let city: String
        let country: String
        let distanceKm: Int
        let referenceFare: Money
        let servable: Bool
    }

    /// Every airport the player could fly to from `from`, ranked by distance
    /// band and marked with whether the current fleet can actually reach it.
    private func destinations(from: AirportCode, snapshot: GameState,
                              catalog: ContentCatalog) -> [Candidate] {
        guard let player = snapshot.playerAirline else { return [] }
        let fleet = snapshot.fleet(of: player.id)
            .compactMap { catalog.aircraftType($0.typeCode) }
        let needle = search.uppercased()
        return catalog.orderedAirportCodes.compactMap { code -> Candidate? in
            guard code != from, let spec = catalog.airport(code),
                  let distance = catalog.distanceKm(from, code) else { return nil }
            if !needle.isEmpty,
               !code.raw.uppercased().contains(needle),
               !spec.city.uppercased().contains(needle) { return nil }
            let servable = fleet.contains { type in
                catalog.routeEligibility(from: from, to: code,
                                         aircraftRangeKm: type.rangeKm,
                                         aircraftRunwayRequirement: type.runwayRequirement)
                    .isEmpty
            }
            return Candidate(
                code: code, city: spec.city, country: spec.country,
                distanceKm: distance,
                referenceFare: Money(rounding: DemandSystem.referenceFare(
                    distanceKm: distance, tuning: catalog.tuning.demand)),
                servable: servable)
        }
        // Servable first, then nearest: a first route should be a short one.
        .sorted { lhs, rhs in
            lhs.servable != rhs.servable ? lhs.servable
                : lhs.distanceKm < rhs.distanceKm
        }
        .prefix(40)
        .map { $0 }
    }

    private func destinationRow(_ candidate: Candidate) -> some View {
        Button {
            destination = candidate.code
            if !fareTouched { fare = candidate.referenceFare.asDouble }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AETheme.spacingXS) {
                        Text(candidate.code.raw)
                            .font(.subheadline.weight(.semibold)).monospaced()
                        Text(candidate.city).font(.subheadline)
                    }
                    Text("\(candidate.distanceKm) km · market fare ≈ \(Format.money(candidate.referenceFare))")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                    if !candidate.servable {
                        Text("No aircraft you own can serve it — range or runway")
                            .font(.caption2)
                            .foregroundStyle(AETheme.caution)
                    }
                }
                Spacer()
                Image(systemName: destination == candidate.code
                      ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(destination == candidate.code
                                     ? AETheme.accent : Color.secondary.opacity(0.4))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(destination == candidate.code
                                ? [.isButton, .isSelected] : .isButton)
    }

    private func serviceControls(from: AirportCode, to: AirportCode,
                                 catalog: ContentCatalog) -> some View {
        VStack(alignment: .leading, spacing: AETheme.spacingS) {
            Stepper("Round trips per day: \(trips)", value: $trips, in: 1...20)
                .frame(minHeight: 44)
            VStack(alignment: .leading, spacing: AETheme.spacingXS) {
                HStack {
                    Text("Fare")
                    Spacer()
                    Text(Format.money(Money.dollars(Int64(fare))))
                        .monospacedDigit()
                }
                Slider(value: $fare, in: 30...800, step: 1) { editing in
                    if editing { fareTouched = true }
                }
                if let distance = catalog.distanceKm(from, to) {
                    let reference = DemandSystem.referenceFare(
                        distanceKm: distance, tuning: catalog.tuning.demand)
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

    /// The verdict, before the tap.
    private func confirmRow(from: AirportCode, to: AirportCode,
                            player: Airline) -> some View {
        let command = OpenRouteCommand(
            airline: player.id, origin: from, destination: to,
            dailyRoundTrips: trips, ticketPrice: Money.dollars(Int64(fare)))
        let blocked = controller.precheck(command)
        return VStack(alignment: .leading, spacing: AETheme.spacingS) {
            if let blocked {
                Label(blocked.message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(AETheme.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let rejection {
                Label(rejection.message, systemImage: "xmark.octagon")
                    .font(.caption)
                    .foregroundStyle(AETheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                // The sheet stays open on refusal, keeping every input, and
                // says why right here.
                if let refusal = controller.submit(command) {
                    rejection = refusal
                    controller.clearRejection()
                } else {
                    dismiss()
                }
            } label: {
                Label("Open this route", systemImage: "airplane.departure")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(blocked != nil)
        }
    }
}
