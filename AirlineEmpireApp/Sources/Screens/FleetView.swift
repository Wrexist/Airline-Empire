import SwiftUI
import AirlineEmpireCore

/// The fleet.
///
/// Sortable, with totals, and with the two destructive actions — sell and
/// return — no longer reachable only by an unconfirmed swipe on an asset worth
/// tens of millions (UIUX_FORENSIC_AUDIT UI-006). Every aircraft now has a
/// detail screen, because `reliability` and `totalFlightHours` were computed
/// in Core and displayed nowhere (UI-018).
struct FleetList: View {
    @Environment(GameController.self) private var controller
    @State private var sort: FleetSort = .status
    @State private var filter = FleetFilter()
    /// See `RoutesList.openRoute` — the same reasoning.
    var acquireAircraft: (() -> Void)?

    var body: some View {
        Group {
            if let catalog = controller.catalog {
                // Sort first, then filter: `matching` preserves order, so the
                // rows a filter leaves are in the same sequence they had in
                // the full list. Filtering first and sorting after would give
                // the same set in the same order here, but only by accident —
                // this way the property is the filter's, and it is tested.
                let all = sorted(controller.fleetCards)
                let cards = all.matching(filter)
                if all.isEmpty {
                    EmptyStateView(icon: "airplane",
                                   title: "No aircraft",
                                   message: "Buy or lease your first aircraft to start flying. Leasing keeps cash free while you learn a market.",
                                   actionTitle: acquireAircraft == nil ? nil : "Browse the market",
                                   action: acquireAircraft)
                        .padding(.horizontal, AETheme.spacingM)
                        .aeEmptyStatePlacement()
                } else {
                    List {
                        if let summary = controller.fleetSummary {
                            FleetSummaryRow(summary: summary)
                                .aeListRow()
                        }
                        // The bar only appears once there are enough aircraft
                        // for scanning to be work. At four aeroplanes a filter
                        // is a control that costs a row and saves nothing.
                        if all.count >= 8 {
                            FleetFilterBar(filter: $filter,
                                           categories: all.presentCategories)
                                .aeListRow()
                        }
                        if cards.isEmpty {
                            // A filter that matches nothing must say so and
                            // offer the way back. An empty list under an
                            // active filter is otherwise indistinguishable
                            // from a fleet that has vanished.
                            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                                Text("No aircraft match this filter.")
                                    .font(AEType.body)
                                Button("Show all \(all.count)") {
                                    filter = FleetFilter()
                                }
                                .buttonStyle(.aeSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, AETheme.spacingM)
                            .aeListRow()
                        }
                        ForEach(cards, id: \.id) { card in
                            NavigationLink(value: card.id) {
                                FleetRow(card: card, catalog: catalog)
                            }
                            .aeListRow()
                            // Same rule as the routes board: the first cell
                            // is the fleet summary, so `cells.firstMatch` is
                            // not an aircraft.
                            .accessibilityIdentifier("ae-fleet-row")
                        }
                    }
                    .listStyle(.plain)
                    .aeScreenBackground()
                    .aeAnimation(AEMotion.content, value: cards.count)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { sortMenu }
                    }
                }
            } else {
                LoadingState(message: "Loading your fleet")
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(FleetSort.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort fleet")
        .accessibilityValue(sort.title)
    }

    private func sorted(_ cards: [FleetCardModel]) -> [FleetCardModel] {
        switch sort {
        case .status:
            // Idle first: an unassigned aircraft is a lease burning for nothing.
            return cards.sorted { statusRank($0) < statusRank($1) }
        case .type:
            return cards.sorted { $0.typeName < $1.typeName }
        case .age:
            return cards.sorted { $0.ageYears > $1.ageYears }
        case .condition:
            return cards.sorted { $0.condition < $1.condition }
        }
    }

    private func statusRank(_ card: FleetCardModel) -> Int {
        if card.assignedRoute == nil && card.status.isActive { return 0 }
        if card.status.isInMaintenance { return 1 }
        if card.status.isOnOrder { return 2 }
        return 3
    }
}

/// The filter bar (MASTER PROMPT 5 §17).
///
/// Three controls, each showing what it would leave. The counts are the point:
/// "Idle" beside a number tells the player whether the filter is worth tapping
/// before they tap it, and an option that would return nothing is disabled
/// rather than hidden — a control that silently disappears is harder to
/// understand than one that is visibly empty.
///
/// It filters; it does not compute. `FleetFilter` in Core decides what matches
/// what, and `FleetFilterTests` holds it to partitioning the fleet exactly
/// once, so the counts here and the rows below cannot disagree.
struct FleetFilterBar: View {
    @Binding var filter: FleetFilter
    let categories: [AircraftCategory]
    @Environment(GameController.self) private var controller

    private var cards: [FleetCardModel] { controller.fleetCards }

    private func count(status: FleetFilter.Status) -> Int {
        cards.matching(FleetFilter(status: status,
                                   ownership: filter.ownership,
                                   category: filter.category)).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingS) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AETheme.spacingXS) {
                    ForEach(FleetFilter.Status.allCases, id: \.self) { status in
                        let hits = count(status: status)
                        Button {
                            filter.status = status
                        } label: {
                            Text("\(Vocab.fleetStatus(status)) \(hits)")
                                .font(AEType.badge)
                        }
                        .buttonStyle(.aeTertiary)
                        .disabled(hits == 0 && status != .all)
                        .opacity(hits == 0 && status != .all ? 0.4 : 1)
                        .overlay(alignment: .bottom) {
                            // Selection is carried by a rule as well as by
                            // the button's own tint, so it does not depend on
                            // colour alone.
                            if filter.status == status {
                                Capsule().fill(AETheme.accent).frame(height: 2)
                            }
                        }
                        .accessibilityLabel("\(Vocab.fleetStatus(status)), \(hits) aircraft")
                        .accessibilityAddTraits(filter.status == status
                                                ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 2)
            }
            HStack(spacing: AETheme.spacingS) {
                Picker("Ownership", selection: $filter.ownership) {
                    ForEach(FleetFilter.Ownership.allCases, id: \.self) { option in
                        Text(Vocab.fleetOwnership(option)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                if categories.count > 1 {
                    Menu {
                        Button("All types") { filter.category = nil }
                        ForEach(categories, id: \.self) { category in
                            Button(Vocab.category(category)) {
                                filter.category = category
                            }
                        }
                    } label: {
                        Label(filter.category.map(Vocab.category) ?? "All types",
                              systemImage: "line.3.horizontal.decrease")
                            .font(AEType.caption)
                            .frame(minHeight: 44)
                    }
                    .accessibilityLabel("Filter by aircraft type")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fleet filters")
    }
}

/// What the fleet costs and what it is, before the individual rows — the
/// question "am I over-fleeted?" had no answer anywhere in the app.
/// The fleet in one strip (MASTER PROMPT 4 §9).
///
/// This used to derive its own aggregates from the card array in a view body.
/// Two problems: the same arithmetic also lived on Home and the Routes board,
/// free to disagree; and `averageAge` divided by *every* card including
/// aircraft still on order, whose age is near zero — so ordering a new
/// aeroplane made the fleet look younger than it was. The numbers now come
/// from `FleetSummary` in Core, which counts delivered aircraft for age and
/// condition and is tested against the cards it summarises.
struct FleetSummaryRow: View {
    let summary: FleetSummary

    private var metrics: [AEMetric] {
        var list: [AEMetric] = [
            AEMetric("aircraft", "\(summary.total)"),
            AEMetric("flying", "\(summary.assigned)",
                     tint: summary.assigned > 0 ? AETheme.positive : nil),
            // Idle aircraft are the number a player can act on: they cost the
            // same as flying ones and earn nothing.
            AEMetric("idle", "\(summary.idle)",
                     tint: summary.idle > 0 ? AETheme.caution : nil),
            AEMetric("in use", summary.utilization.map(Format.percent) ?? "—"),
            AEMetric("avg age", summary.averageAgeYears
                        .map { "\(Format.decimal($0, places: 0)) y" } ?? "—"),
            AEMetric("condition",
                     summary.averageCondition.map(Format.percent) ?? "—",
                     tint: (summary.averageCondition ?? 1) < 0.6
                         ? AETheme.caution : nil),
        ]
        if summary.inMaintenance > 0 {
            list.append(AEMetric("in check", "\(summary.inMaintenance)",
                                 tint: AETheme.caution))
        }
        if summary.onOrder > 0 {
            list.append(AEMetric("on order", "\(summary.onOrder)"))
        }
        if summary.leasedCount > 0 {
            list.append(AEMetric("leases/mo",
                                 Format.money(summary.monthlyLeaseCost)))
        }
        return list
    }

    var body: some View {
        AEMetricStrip(metrics)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fleet summary")
    }
}

struct FleetRow: View {
    let card: FleetCardModel
    let catalog: ContentCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingXS) {
            HStack(spacing: AETheme.spacingS) {
                Image(systemName: Vocab.categoryIcon(card.category))
                    .font(.caption)
                    .foregroundStyle(AETheme.accent)
                    .accessibilityHidden(true)
                Text(card.typeName).font(.body.weight(.semibold))
                Spacer()
                statusBadge
            }
            HStack(spacing: AETheme.spacingS) {
                AEBadge(text: "\(Format.decimal(card.ageYears, places: 0))y",
                        color: .secondary)
                AEBadge(text: "cond \(Format.percent(card.condition))",
                        color: card.condition > 0.8 ? AETheme.positive : AETheme.caution)
                switch card.ownershipDescription {
                case .owned(let book):
                    AEBadge(text: "owned · \(Format.money(book))", color: AETheme.owned)
                case .leased(let rate, _):
                    AEBadge(text: "lease \(Format.money(rate))/mo", color: AETheme.leased)
                }
                if card.assignedRoute == nil, card.status.isActive {
                    AEBadge(text: "idle", color: AETheme.caution, icon: "pause")
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch card.status {
        case .active:
            AEBadge(text: "at \(card.location.raw)", color: AETheme.positive)
        case .ordered:
            AEBadge(text: "on order", color: AETheme.accent, icon: "shippingbox")
        case .inMaintenance:
            AEBadge(text: "maintenance", color: AETheme.caution, icon: "wrench")
        }
    }
}

/// One aircraft, in full — including the reliability and hours Core has always
/// computed and no screen ever showed, and both destructive actions behind a
/// confirmation with the money attached.
struct AircraftDetailView: View {
    @Environment(GameController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    let aircraftID: AircraftID

    var body: some View {
        ScrollView {
            if let snapshot = controller.snapshot,
               let player = snapshot.playerAirline,
               let catalog = controller.catalog,
               let card = controller.fleetCard(aircraftID),
               let spec = catalog.aircraftType(card.typeCode) {
                VStack(spacing: AETheme.spacingM) {
                    identity(card, spec: spec)
                    assignment(card, snapshot: snapshot, player: player.id, catalog: catalog)
                    condition(card, spec: spec)
                    ownership(card, spec: spec, player: player.id)
                }
                .padding(.horizontal)
                .padding(.bottom, AETheme.spacingL)
            } else {
                EmptyStateView(icon: "airplane.slash", title: "Aircraft gone",
                               message: "This aircraft is no longer in your fleet.")
                    .padding()
            }
        }
        .aeScreenBackground()
        .navigationTitle(controller.snapshot.flatMap { snapshot in
            controller.catalog.flatMap { catalog in
                snapshot.aircraft[aircraftID].flatMap { catalog.aircraftType($0.typeCode) }
            }
        }.map { "\($0.manufacturer) \($0.model)" } ?? "Aircraft")
        .navigationBarTitleDisplayMode(.inline)
        .aeTimeToolbar()
    }

    /// The airline's livery, falling back to the accent before an airline
    /// exists — this view is reachable only inside a game, but a colour that
    /// resolves through an optional should say what it does when it cannot.
    private var livery: Color {
        // `Airline.livery` is non-optional, so `?.livery.map(_:)` would bind
        // `map` inside the optional chain and not compile. Bind, then convert.
        guard let livery = controller.snapshot?.playerAirline?.livery else {
            return AETheme.accent
        }
        return Vocab.liveryColor(livery)
    }

    private func identity(_ card: FleetCardModel, spec: AircraftTypeSpec) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                HStack(spacing: AETheme.spacingS) {
                    // §10 asks for an aircraft visual here. The silhouette is
                    // the airline's own livery colour, so a player's fleet
                    // reads as theirs rather than as generic stock.
                    AircraftShape(category: card.category)
                        .fill(livery)
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(spec.manufacturer) \(spec.model)").font(.headline)
                        Text(Vocab.role(spec.role))
                            .font(AEType.secondary)
                            .foregroundStyle(AETheme.mutedText)
                    }
                    Spacer()
                }
                AEChipRow {
                    AEChip(icon: "person.2.fill", text: "\(spec.seats) seats")
                    AEChip(icon: "arrow.left.and.right", text: "\(spec.rangeKm) km")
                    // Was `fuelBurnKgPerKm` whole — which says a widebody is
                    // thirsty, which is true and useless, because it is also
                    // carrying three times the passengers. The band compares
                    // per seat, against the best in the catalogue, which is
                    // the comparison a fleet decision actually turns on.
                    if let band = controller.catalog?.seatEfficiency(of: spec) {
                        AEChip(icon: "fuelpump.fill",
                               text: Vocab.seatEfficiency(band))
                    }
                }
                Text("Needs a \(Vocab.runway(spec.runwayRequirement).lowercased()) · cruises at \(spec.cruiseSpeedKmh) km/h · \(spec.turnaroundMinutes) min turnaround")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func assignment(_ card: FleetCardModel, snapshot: GameState,
                            player: AirlineID, catalog: ContentCatalog) -> some View {
        AECard(tint: card.assignedRoute == nil && card.status.isActive
               ? AETheme.caution.opacity(0.16) : nil) {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Assignment", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                if let routeID = card.assignedRoute, let route = snapshot.routes[routeID] {
                    NavigationLink(value: routeID) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(route.origin.raw) – \(route.destination.raw)")
                                    .font(.subheadline.weight(.medium))
                                Text("\(route.dailyRoundTrips)×/day")
                                    .font(.caption)
                                    .foregroundStyle(AETheme.mutedText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(AETheme.mutedText)
                        }
                        .frame(minHeight: 44)
                    }
                    Button("Unassign") {
                        controller.submit(UnassignAircraftCommand(
                            airline: player, aircraftID: card.id))
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                } else if card.status.isOnOrder {
                    Label("On order — it cannot fly until it is delivered.",
                          systemImage: "shippingbox")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.mutedText)
                } else {
                    // An unassigned aircraft in a check used to be described
                    // as "idle", which reads as the player's fault and as
                    // something they could fix by finding it a route. It is
                    // neither: it is in the hangar because Core put it there.
                    // The route it flies next can still be chosen now, which
                    // is why the picker sits under both messages.
                    if card.status.isInMaintenance {
                        Label("In a maintenance check at \(card.location.raw). It can be given its next route now.",
                              systemImage: "wrench")
                            .font(AEType.body)
                            .foregroundStyle(AETheme.caution)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Label("Idle at \(card.location.raw). It earns nothing here, and a leased aircraft still bills.",
                              systemImage: "pause.circle")
                            .font(AEType.body)
                            .foregroundStyle(AETheme.caution)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    routePicker(card, snapshot: snapshot, player: player,
                                catalog: catalog)
                }
            }
        }
    }

    /// Where this aeroplane could go next (MASTER PROMPT 5 §23, §24).
    ///
    /// The old picker listed routes with no aircraft at all and nothing else.
    /// Two problems, in opposite directions. It offered routes this aircraft
    /// could not reach — no range check, no runway check — so the player
    /// picked one and Core refused the tap the app had just invited. And it
    /// hid every route that already had an aeroplane, although Core appends
    /// to `assignedAircraft` quite happily, so adding a second aircraft to a
    /// busy route was unreachable from the screen that owns the aircraft.
    ///
    /// Both lists now come from `assignmentCandidates`, which mirrors the
    /// command validator and is tested against it. Ineligible routes are
    /// shown, disabled, with the reason — a picker that silently omits them
    /// answers "why isn't my new route in this list?" with nothing.
    @ViewBuilder
    private func routePicker(_ card: FleetCardModel, snapshot: GameState,
                             player: AirlineID,
                             catalog: ContentCatalog) -> some View {
        let candidates = snapshot.assignmentCandidates(forAircraft: card.id,
                                                       catalog: catalog)
        let eligible = candidates.filter(\.isEligible)
        let blocked = candidates.filter { !$0.isEligible }
        if candidates.isEmpty {
            Text("You have no routes yet. Open one, and this aircraft can fly it.")
                .font(AEType.secondary)
                .foregroundStyle(AETheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            if !eligible.isEmpty {
                Menu {
                    ForEach(eligible, id: \.routeID) { candidate in
                        if let route = snapshot.routes[candidate.routeID] {
                            Button {
                                controller.submit(AssignAircraftToRouteCommand(
                                    airline: player, route: candidate.routeID,
                                    aircraftID: card.id))
                            } label: {
                                // The note rides along in the menu label
                                // because a Menu row has nowhere else to put
                                // it, and the fit is the whole reason to
                                // prefer one route over another.
                                if let note = Vocab.assignmentNote(candidate.note) {
                                    Text("\(route.origin.raw) – \(route.destination.raw) — \(note)")
                                } else {
                                    Text("\(route.origin.raw) – \(route.destination.raw)")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Assign to a route", systemImage: "plus")
                        .font(AEType.body.weight(.medium))
                        .frame(minHeight: 44)
                }
            }
            if !blocked.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(blocked, id: \.routeID) { candidate in
                        if let route = snapshot.routes[candidate.routeID],
                           let blocker = candidate.blocker {
                            HStack(spacing: AETheme.spacingXS) {
                                Text("\(route.origin.raw) – \(route.destination.raw)")
                                    .font(AEType.caption)
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

    private func condition(_ card: FleetCardModel, spec: AircraftTypeSpec) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Condition and history", systemImage: "wrench.and.screwdriver")
                gauge("Condition", card.condition,
                      tint: card.condition > 0.8 ? AETheme.positive : AETheme.caution)
                gauge("Reliability", card.reliability,
                      tint: card.reliability > 0.95 ? AETheme.positive : AETheme.caution)
                labelled("Age", "\(Format.decimal(card.ageYears, places: 1)) years")
                labelled("Flight hours",
                         Format.count(Int64(card.totalFlightHours.rounded())))
                labelled("Maintenance",
                         "\(Format.money(spec.maintenancePerFlightHour)) per flight hour")
                Text(card.condition < 0.7
                     ? "Condition this low means more delays and more time on the ground. Selling it while it still has value is a real option."
                     : "Condition falls with hours flown and is restored by scheduled maintenance.")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func ownership(_ card: FleetCardModel, spec: AircraftTypeSpec,
                           player: AirlineID) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Ownership", systemImage: "doc.text")
                switch card.ownershipDescription {
                case .owned(let book):
                    // A blank right-hand column in a card where every other
                    // row carries a number reads as missing data rather than
                    // as an answer.
                    labelled("Ownership", "Owned outright")
                    labelled("Book value", Format.money(book))
                    Text("Selling returns roughly its market value, which falls with age and condition.")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    destructive(
                        title: "Sell this aircraft?",
                        message: "You receive roughly \(Format.money(book)) and lose the airframe. This cannot be undone.",
                        confirmTitle: "Sell",
                        label: "Sell aircraft", icon: "banknote",
                        command: SellAircraftCommand(seller: player, aircraftID: card.id))
                case .leased(let rate, let months):
                    labelled("Leased", "\(Format.money(rate))/month")
                    labelled("Months remaining", "\(months)")
                    labelled("Committed", Format.money(rate * Int64(months)))
                    Text("Returning it early costs a penalty, but stops the monthly bill.")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    destructive(
                        title: "Return this aircraft?",
                        message: "You stop paying \(Format.money(rate)) a month and pay an early-return penalty. This cannot be undone.",
                        confirmTitle: "Return",
                        label: "Return to lessor", icon: "arrow.uturn.left",
                        command: ReturnLeasedAircraftCommand(lessee: player,
                                                             aircraftID: card.id))
                }
            }
        }
    }

    private func destructive(title: String, message: String, confirmTitle: String,
                             label: String, icon: String,
                             command: any Command) -> some View {
        let blocked = controller.precheck(command)
        return VStack(alignment: .leading, spacing: AETheme.spacingXS) {
            ConfirmableButton(title: title, message: message,
                              confirmTitle: confirmTitle, role: .destructive,
                              action: {
                                  // `precheck` ran at render time and the
                                  // simulation has been advancing since, so
                                  // the refusal is real. Leaving the screen
                                  // on it would report the sale as done.
                                  if controller.submit(command) == nil { dismiss() }
                              }) {
                Label(label, systemImage: icon).frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(AETheme.negative)
            .disabled(blocked != nil)
            if let blocked {
                Text(blocked.message)
                    .font(.caption2)
                    .foregroundStyle(AETheme.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func gauge(_ label: String, _ value: Double, tint: Color) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            ProgressView(value: value).tint(tint).frame(width: 110)
            Text(Format.percent(value))
                .font(.caption).monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(Format.percent(value))")
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

/// The aircraft market.
///
/// It used to show three prices and no balance, so the biggest financial
/// commitments in the game were one unguarded tap and a refusal the player
/// could not see because it was raised underneath this very sheet
/// (UIUX_FORENSIC_AUDIT UI-006). Now cash is on screen, every price says what
/// it leaves behind, unaffordable options are disabled with the reason, and
/// era-locked types explain themselves instead of showing nothing.
struct AircraftShopSheet: View {
    @Environment(GameController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var usedAge = 8
    @State private var leaseTermMonths = 60
    @State private var sort: Sort = .seats
    @State private var hidesLocked = false
    /// Which way in is picked, per aircraft. Lives here because the picker
    /// and the commit button are separate List rows (see `ShopCommitButton`)
    /// that must see the same choice. Absent means the default, lease.
    @State private var deals: [AircraftTypeCode: ShopDeal] = [:]

    /// Fourteen types with seven attributes each, and no way to order them,
    /// was a catalogue rather than a market (UIUX_FORENSIC_AUDIT UI-017).
    enum Sort: String, CaseIterable, Hashable {
        case seats, range, efficiency, price

        var title: String {
            switch self {
            case .seats: "Seats"
            case .range: "Range"
            // "Fuel per seat" rendered as "Fuel per s…" in the segmented
            // control at default type size (seen in run 60's market frame) —
            // four segments share one row, and this was the longest.
            case .efficiency: "Fuel/seat"
            case .price: "Price"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let catalog = controller.catalog,
                   let snapshot = controller.snapshot,
                   let player = snapshot.playerAirline {
                    List {
                        Section {
                            wallet(snapshot: snapshot, player: player.id)
                        }
                        Section("Show") {
                            Picker("Sort", selection: $sort) {
                                ForEach(Sort.allCases, id: \.self) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            Toggle("Hide what this era cannot buy", isOn: $hidesLocked)
                        }
                        Section("Terms") {
                            Stepper("Used aircraft age: \(usedAge) \(usedAge == 1 ? "year" : "years")",
                                    value: $usedAge,
                                    in: 1...catalog.tuning.fleet.maxUsedPurchaseAgeYears)
                                .frame(minHeight: 44)
                            Stepper("Lease term: \(leaseTermMonths) months",
                                    value: $leaseTermMonths, in: 12...120, step: 12)
                                .frame(minHeight: 44)
                        }
                        ForEach(types(catalog: catalog, snapshot: snapshot),
                                id: \.code) { spec in
                            Section {
                                shopRow(spec, catalog: catalog, snapshot: snapshot,
                                        player: player.id)
                                // The commit is its own row on purpose: a row
                                // whose only button is default-styled makes
                                // the whole row the tap target (the pattern
                                // every working control in this sheet uses).
                                if !locked(spec, snapshot: snapshot) {
                                    ShopCommitButton(
                                        facts: facts(spec, catalog: catalog,
                                                     snapshot: snapshot,
                                                     player: player.id),
                                        deal: deals[spec.code] ?? .lease)
                                }
                            }
                        }
                    }
                } else {
                    LoadingState(message: "Loading the market")
                }
            }
            .aeScreenBackground()
            .navigationTitle("Aircraft market")
            // Buying an aircraft is the most expensive thing a player does.
            // The sheet says so on the way in and out; the purchase itself is
            // voiced by `aircraftOrdered`/`aircraftDelivered` from Core.
            .aeSheetFeedback()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// The market, ordered the way the player asked and filtered to what they
    /// can actually act on.
    private func types(catalog: ContentCatalog,
                       snapshot: GameState) -> [AircraftTypeSpec] {
        let allowed = snapshot.progression.era.allowedCategories
        let specs = catalog.orderedAircraftTypeCodes
            .compactMap { catalog.aircraftTypes[$0] }
            .filter { !hidesLocked || allowed.contains($0.category) }
        switch sort {
        case .seats:
            return specs.sorted { $0.seats > $1.seats }
        case .range:
            return specs.sorted { $0.rangeKm > $1.rangeKm }
        case .efficiency:
            // Burn per seat is the number that actually decides a fleet, and
            // it was nowhere in the app.
            return specs.sorted {
                $0.fuelBurnKgPerKm / Double($0.seats)
                    < $1.fuelBurnKgPerKm / Double($1.seats)
            }
        case .price:
            return specs.sorted { $0.listPrice.cents < $1.listPrice.cents }
        }
    }

    private func wallet(snapshot: GameState, player: AirlineID) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Your cash").font(.caption).foregroundStyle(AETheme.mutedText)
                MoneyText(money: snapshot.ledger.balance(of: player))
                    .font(.title3.weight(.semibold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("Era").font(.caption).foregroundStyle(AETheme.mutedText)
                Text(Vocab.era(snapshot.progression.era))
                    .font(.subheadline.weight(.medium))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The silhouette, the name, and the lock — laid out by how much room
    /// the type size leaves.
    ///
    /// Side by side at normal sizes. At an accessibility size the name wraps
    /// to three lines and a vertically centred silhouette landed in the
    /// middle of the word, with the "later era" badge overlapping the last
    /// line (AE-033 audit §6.3) — so above that threshold the silhouette and
    /// the badge take their own row and the name gets the full width. Top
    /// alignment in the horizontal case for the same reason at one step down:
    /// a two-line name should hang off the top of the glyph, not straddle it.
    @ViewBuilder
    private func shopRowHeader(_ spec: AircraftTypeSpec,
                               locked: Bool) -> some View {
        // The silhouette, not a generic glyph. `AircraftShape` was written for
        // exactly this — its own doc comment says "a fleet row, a detail
        // header" — and until now only the map used the underlying path. A
        // regional jet and a widebody looked identical in the one screen where
        // telling them apart is the entire decision (MASTER PROMPT 4 §11).
        let silhouette = AircraftShape(category: spec.category)
            .fill(locked ? AnyShapeStyle(AETheme.mutedText)
                         : AnyShapeStyle(AETheme.accent))
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)
        let names = VStack(alignment: .leading, spacing: 1) {
            Text("\(spec.manufacturer) \(spec.model)")
                .font(AEType.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            // The role, not the category. "Regional jet" is a taxonomy a
            // player has to already know; "Regional connector" is what the
            // aeroplane is bought to do (MASTER PROMPT 5 §10).
            Text(Vocab.role(spec.role))
                .font(AEType.secondary).foregroundStyle(AETheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        let badge = Group {
            if locked {
                AEBadge(text: "later era", color: .secondary, icon: "lock")
            }
        }

        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                HStack(spacing: AETheme.spacingS) {
                    silhouette
                    Spacer()
                    badge
                }
                names
            }
        } else {
            HStack(alignment: .top, spacing: AETheme.spacingS) {
                silhouette
                names
                Spacer()
                badge
            }
        }
    }

    private func shopRow(_ spec: AircraftTypeSpec, catalog: ContentCatalog,
                         snapshot: GameState, player: AirlineID) -> some View {
        let isLocked = locked(spec, snapshot: snapshot)
        // The bars are comparative against the whole catalogue, locked types
        // included: "184 of a possible 422 seats" is a fact about the world,
        // and the bars must not re-scale when the era filter flips.
        let all = catalog.orderedAircraftTypeCodes
            .compactMap { catalog.aircraftTypes[$0] }
        let maxSeats = all.map(\.seats).max() ?? spec.seats
        let maxRange = all.map(\.rangeKm).max() ?? spec.rangeKm
        return VStack(alignment: .leading, spacing: AETheme.spacingS) {
            shopRowHeader(spec, locked: isLocked)
            // The spec as bars, not prose: three chips of digits made every
            // aircraft read the same, and comparing was the whole point of
            // the screen. A bar against the catalogue's best is legible at a
            // glance — the trading-card read.
            specBar("Seats", value: "\(spec.seats)", icon: "person.2.fill",
                    fraction: Double(spec.seats) / Double(max(maxSeats, 1)),
                    tint: AETheme.accent)
            specBar("Range", value: "\(spec.rangeKm) km",
                    icon: "arrow.left.and.right",
                    fraction: Double(spec.rangeKm) / Double(max(maxRange, 1)),
                    tint: AETheme.owned)
            if let band = catalog.seatEfficiency(of: spec) {
                specBar("Fuel/seat", value: Vocab.seatEfficiency(band),
                        icon: "fuelpump.fill",
                        fraction: efficiencyFraction(band),
                        tint: efficiencyTint(band))
            }
            // What it is for, and what that costs — the question a market
            // card exists to answer and the one the spec sheet never did.
            Text(Vocab.roleDetail(spec.role))
                .font(AEType.caption)
                .foregroundStyle(AETheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            if isLocked {
                // A locked row used to show nothing at all, so the player
                // could not plan toward it.
                Text("Unlocks in the \(Vocab.era(unlockEra(for: spec.category))) era. \(Vocab.eraDetail(unlockEra(for: spec.category))).")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ShopDealPicker(
                    facts: facts(spec, catalog: catalog, snapshot: snapshot,
                                 player: player),
                    deal: Binding(get: { deals[spec.code] ?? .lease },
                                  set: { deals[spec.code] = $0 }))
            }
        }
        .padding(.vertical, 2)
    }

    private func locked(_ spec: AircraftTypeSpec,
                        snapshot: GameState) -> Bool {
        !snapshot.progression.era.allowedCategories.contains(spec.category)
    }

    /// The shared per-aircraft facts both deal rows read.
    private func facts(_ spec: AircraftTypeSpec, catalog: ContentCatalog,
                       snapshot: GameState,
                       player: AirlineID) -> ShopDealFacts {
        ShopDealFacts(
            spec: spec, usedAge: usedAge, leaseTermMonths: leaseTermMonths,
            usedPrice: FleetEconomics.usedPrice(
                type: spec, ageYears: Double(usedAge),
                condition: FleetEconomics.usedMarketCondition(
                    ageYears: Double(usedAge), tuning: catalog.tuning.fleet),
                tuning: catalog.tuning.fleet),
            cash: snapshot.ledger.balance(of: player),
            player: player)
    }

    /// One spec line: name, a bar against the catalogue's best, the number.
    private func specBar(_ label: String, value: String, icon: String,
                         fraction: Double, tint: Color) -> some View {
        HStack(spacing: AETheme.spacingS) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(AETheme.mutedText)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(label)
                .font(AEType.caption)
                .foregroundStyle(AETheme.mutedText)
                .frame(width: 62, alignment: .leading)
            Capsule()
                .fill(AETheme.cardBackground)
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(tint.gradient)
                            .frame(width: geo.size.width
                                   * min(max(fraction, 0.04), 1))
                    }
                }
            Text(value)
                .font(AEType.caption.weight(.medium)).monospacedDigit()
                .frame(minWidth: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    /// The band as a bar. Ordinal, not measured — the band already threw the
    /// raw number away, and these fractions only have to keep its order.
    private func efficiencyFraction(_ band: SeatEfficiencyBand) -> Double {
        switch band {
        case .best: 1.0
        case .strong: 0.72
        case .moderate: 0.45
        case .thirsty: 0.22
        }
    }

    private func efficiencyTint(_ band: SeatEfficiencyBand) -> Color {
        switch band {
        case .best, .strong: AETheme.positive
        case .moderate: AETheme.caution
        case .thirsty: AETheme.negative
        }
    }

    /// The first era whose allowed categories include this one.
    private func unlockEra(for category: AircraftCategory) -> Era {
        Era.allCases.first { $0.allowedCategories.contains(category) } ?? .empire
    }
}

/// The deal: three ways to get the same aircraft, as one decision.
///
/// The previous market stacked "Buy new / Buy used / Lease" as three thin
/// text rows — three separate 44 pt taps for what is really one choice with
/// three answers, and the screen's own audit called it boring to buy from
/// (AE-034, run 86's frames). Now the ways in are *cards you pick between*:
/// tap a deal to try it on — the consequence line and the wallet bar answer
/// "then what?" before any commitment — and one full-width signature button
/// commits it. Picking is free and reversible; only the big button spends
/// money, which is also why it is the only control here that confirms.
///
/// Lease is the default everywhere because it is the game's own advice —
/// the onboarding checklist says "Leasing keeps cash free early on" — and
/// because the CTA then carries `ae-market-lease` from first render, which
/// the UI journeys scroll to.
enum ShopDeal: CaseIterable, Hashable { case new, used, lease }

/// Everything the deal views need to answer for one aircraft, in one place —
/// the picker and the commit button live in *different List rows* (see
/// `ShopCommitButton`) and must agree on every fact.
struct ShopDealFacts {
    let spec: AircraftTypeSpec
    let usedAge: Int
    let leaseTermMonths: Int
    let usedPrice: Money
    let cash: Money
    let player: AirlineID

    func price(for option: ShopDeal) -> Money {
        switch option {
        case .new: spec.listPrice
        case .used: usedPrice
        case .lease: spec.leaseMonthly
        }
    }

    func caption(for option: ShopDeal) -> String {
        switch option {
        case .new: "New"
        case .used: "Used \(usedAge)y"
        case .lease: "Lease"
        }
    }

    func subtitle(for option: ShopDeal) -> String {
        switch option {
        case .new: "in \(Format.days(spec.deliveryLeadDays))"
        case .used: "flies now"
        case .lease: "per month"
        }
    }

    func tint(for option: ShopDeal) -> Color {
        switch option {
        case .new: AETheme.accent
        case .used: AETheme.owned
        case .lease: AETheme.leased
        }
    }

    func consequenceIcon(for option: ShopDeal) -> String {
        switch option {
        case .new: "shippingbox.fill"
        case .used: "bolt.fill"
        case .lease: "calendar"
        }
    }

    func consequenceText(for option: ShopDeal) -> String {
        switch option {
        case .new:
            "Factory fresh, best condition — delivered in \(Format.days(spec.deliveryLeadDays))."
        case .used:
            "On the apron today, in used condition."
        case .lease:
            "No cash down. \(Format.money(spec.leaseMonthly * Int64(leaseTermMonths))) over \(leaseTermMonths) months."
        }
    }

    func ctaTitle(for option: ShopDeal) -> String {
        switch option {
        case .new: "Order it new"
        case .used: "Buy it today"
        case .lease: "Sign the lease"
        }
    }

    /// The word the confirmation dialog leads with and confirms with. These
    /// are a UI-test contract ("Lease?" / "Lease", "Buy used (8y)?"); the
    /// friendlier verbs live on the button, not in the dialog.
    func confirmWord(for option: ShopDeal) -> String {
        switch option {
        case .new: "Buy new"
        case .used: "Buy used (\(usedAge)y)"
        case .lease: "Lease"
        }
    }

    func name(for option: ShopDeal) -> String {
        switch option {
        case .new: "buy-new"
        case .used: "buy-used"
        case .lease: "lease"
        }
    }

    func dialogMessage(for option: ShopDeal) -> String {
        switch option {
        case .new, .used:
            "\(Format.money(price(for: option))) now, leaving \(Format.money(cash - price(for: option)))."
        case .lease:
            "\(Format.money(spec.leaseMonthly)) every month for \(leaseTermMonths) months. Returning early costs a penalty."
        }
    }

    func command(for option: ShopDeal) -> any Command {
        switch option {
        case .new:
            BuyNewAircraftCommand(buyer: player, type: spec.code)
        case .used:
            BuyUsedAircraftCommand(buyer: player, type: spec.code,
                                   ageYears: usedAge)
        case .lease:
            LeaseAircraftCommand(lessee: player, type: spec.code,
                                 termMonths: leaseTermMonths)
        }
    }
}

/// The three deal cards and the consequence line for the picked one.
struct ShopDealPicker: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    let facts: ShopDealFacts
    @Binding var deal: ShopDeal

    var body: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingS) {
            if typeSize.isAccessibilitySize {
                // Three cards share a row only while their text fits; at
                // accessibility sizes each gets the full width.
                VStack(spacing: AETheme.spacingS) {
                    ForEach(ShopDeal.allCases, id: \.self) { card(for: $0) }
                }
            } else {
                HStack(spacing: AETheme.spacingS) {
                    ForEach(ShopDeal.allCases, id: \.self) { card(for: $0) }
                }
            }
            consequence
        }
        .aeAnimation(AEMotion.selection, value: deal)
        // Trying a deal on is a real decision the world should acknowledge,
        // quietly — the same select cue the rest of the app speaks.
        .aeFeedback(.uiSelect, on: deal)
    }

    private func card(for option: ShopDeal) -> some View {
        let selected = deal == option
        return Button {
            deal = option
        } label: {
            VStack(spacing: 2) {
                Text(facts.caption(for: option))
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(selected ? facts.tint(for: option)
                                              : AETheme.mutedText)
                Text(Format.money(facts.price(for: option)))
                    .font(AEType.body.weight(.bold)).monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(facts.subtitle(for: option))
                    .font(.caption2)
                    .foregroundStyle(AETheme.mutedText)
            }
            .padding(.vertical, AETheme.spacingS)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AETheme.cornerRadiusSmall,
                                 style: .continuous)
                    .fill(selected ? facts.tint(for: option).opacity(0.12)
                                   : AETheme.cardBackground.opacity(0.6)))
            .overlay(
                RoundedRectangle(cornerRadius: AETheme.cornerRadiusSmall,
                                 style: .continuous)
                    .strokeBorder(selected ? facts.tint(for: option)
                                           : Color.clear,
                                  lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        // Borderless, not plain or default: several buttons share this List
        // row, and borderless is the style Lists hit-test per button.
        .buttonStyle(.borderless)
        .accessibilityIdentifier("ae-deal-\(facts.name(for: option))")
        .accessibilityLabel("\(facts.caption(for: option)), \(Format.money(facts.price(for: option))), \(facts.subtitle(for: option))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// One line that answers "and then what?" for the selected deal, plus —
    /// for the cash deals — a wallet bar showing what stays in the bank.
    @ViewBuilder
    private var consequence: some View {
        HStack(spacing: AETheme.spacingS - 2) {
            Image(systemName: facts.consequenceIcon(for: deal))
                .font(.caption)
                .foregroundStyle(facts.tint(for: deal))
                .accessibilityHidden(true)
            Text(facts.consequenceText(for: deal))
                .font(AEType.caption)
                .foregroundStyle(AETheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        if deal != .lease, facts.cash.cents > 0 {
            let after = facts.cash - facts.price(for: deal)
            let fraction = Double(max(after.cents, 0)) / Double(facts.cash.cents)
            HStack(spacing: AETheme.spacingS) {
                Text("Bank after")
                    .font(.caption2)
                    .foregroundStyle(AETheme.mutedText)
                Capsule()
                    .fill(AETheme.cardBackground)
                    .frame(height: 5)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill((fraction < 0.15 ? AETheme.caution
                                                       : AETheme.positive).gradient)
                                .frame(width: geo.size.width
                                       * min(max(fraction, 0.02), 1))
                        }
                    }
                Text(Format.money(after))
                    .font(.caption2.weight(.medium)).monospacedDigit()
                    .foregroundStyle(after.cents < 0 ? AETheme.negative
                                                     : .primary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Leaves \(Format.money(after)) in the bank")
        }
    }
}

/// The signature — deliberately its own List row.
///
/// Runs 88 and 90 photographed twenty-four synthetic taps landing inert on
/// a CTA that shared its row with the deal cards, across every button-style
/// arrangement tried. A row whose only button is default-styled is the one
/// List pattern where the *entire row* is the button's tap target — the
/// pattern every Toggle and Stepper row in this sheet already relies on —
/// so the commit lives alone in its row and cannot be missed, by a finger
/// or by the test runner.
struct ShopCommitButton: View {
    @Environment(GameController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    let facts: ShopDealFacts
    let deal: ShopDeal

    var body: some View {
        let command = facts.command(for: deal)
        let blocked = controller.precheck(command)
        VStack(alignment: .leading, spacing: 2) {
            ConfirmableButton(
                title: "\(facts.confirmWord(for: deal))?",
                message: facts.dialogMessage(for: deal),
                confirmTitle: facts.confirmWord(for: deal), role: nil,
                // Dismiss on success, like every other sheet in the app —
                // the payoff is the aircraft in the fleet, not this sheet.
                action: {
                    if controller.submit(command) == nil { dismiss() }
                }
            ) {
                Label(facts.ctaTitle(for: deal), systemImage: "signature")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AETheme.accent, in: Capsule())
                    .opacity(blocked != nil ? 0.45 : 1)
            }
            // The stable name a UI test scrolls to. It follows the selected
            // deal, so "ae-market-lease" is this row whenever Lease is
            // picked — which it is by default.
            .accessibilityIdentifier("ae-market-\(facts.name(for: deal))")
            .disabled(blocked != nil)
            if let blocked {
                Text(blocked.message)
                    .font(.caption2)
                    .foregroundStyle(AETheme.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
