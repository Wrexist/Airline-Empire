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
    /// See `RoutesList.openRoute` — the same reasoning.
    var acquireAircraft: (() -> Void)?

    var body: some View {
        Group {
            if let catalog = controller.catalog {
                let cards = sorted(controller.fleetCards)
                if cards.isEmpty {
                    EmptyStateView(icon: "airplane",
                                   title: "No aircraft",
                                   message: "Buy or lease your first aircraft to start flying. Leasing keeps cash free while you learn a market.",
                                   actionTitle: acquireAircraft == nil ? nil : "Browse the market",
                                   action: acquireAircraft)
                        .padding(.horizontal, AETheme.spacingM)
                } else {
                    List {
                        if let summary = controller.fleetSummary {
                            FleetSummaryRow(summary: summary)
                                .aeListRow()
                        }
                        ForEach(cards, id: \.id) { card in
                            NavigationLink(value: card.id) {
                                FleetRow(card: card, catalog: catalog)
                            }
                            .aeListRow()
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

    var body: some View {
        AEMetricStrip {
            AECompactMetric(label: "aircraft", value: "\(summary.total)")
            AECompactMetric(label: "flying", value: "\(summary.assigned)",
                            tint: summary.assigned > 0 ? AETheme.positive : nil)
            // Idle aircraft are the number a player can act on: they cost the
            // same as flying ones and earn nothing.
            AECompactMetric(label: "idle", value: "\(summary.idle)",
                            tint: summary.idle > 0 ? AETheme.caution : nil)
            AECompactMetric(label: "in use",
                            value: summary.utilization.map(Format.percent) ?? "—")
            AECompactMetric(label: "avg age",
                            value: summary.averageAgeYears
                                .map { "\(Format.decimal($0, places: 0)) y" } ?? "—")
            AECompactMetric(label: "condition",
                            value: summary.averageCondition.map(Format.percent) ?? "—",
                            tint: (summary.averageCondition ?? 1) < 0.6
                                ? AETheme.caution : nil)
            if summary.inMaintenance > 0 {
                AECompactMetric(label: "in check",
                                value: "\(summary.inMaintenance)",
                                tint: AETheme.caution)
            }
            if summary.onOrder > 0 {
                AECompactMetric(label: "on order", value: "\(summary.onOrder)")
            }
            if summary.leasedCount > 0 {
                AECompactMetric(label: "leases/mo",
                                value: Format.money(summary.monthlyLeaseCost))
            }
        }
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

    private func identity(_ card: FleetCardModel, spec: AircraftTypeSpec) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                HStack(spacing: AETheme.spacingS) {
                    Image(systemName: Vocab.categoryIcon(card.category))
                        .font(.title2)
                        .foregroundStyle(AETheme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(spec.manufacturer) \(spec.model)").font(.headline)
                        Text(Vocab.category(card.category))
                            .font(.caption)
                            .foregroundStyle(AETheme.mutedText)
                    }
                    Spacer()
                }
                HStack(spacing: AETheme.spacingXS) {
                    AEChip(icon: "person.2.fill", text: "\(spec.seats) seats")
                    AEChip(icon: "arrow.left.and.right", text: "\(spec.rangeKm) km")
                    AEChip(icon: "fuelpump.fill",
                           text: "\(Format.decimal(spec.fuelBurnKgPerKm, places: 1)) kg/km")
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
                    Label("Idle at \(card.location.raw). It earns nothing here, and a leased aircraft still bills.",
                          systemImage: "pause.circle")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.caution)
                        .fixedSize(horizontal: false, vertical: true)
                    let open = snapshot.routes(of: player)
                        .filter { $0.assignedAircraft.isEmpty }
                    if !open.isEmpty {
                        Menu {
                            ForEach(open, id: \.id) { route in
                                Button("\(route.origin.raw) – \(route.destination.raw)") {
                                    controller.submit(AssignAircraftToRouteCommand(
                                        airline: player, route: route.id,
                                        aircraftID: card.id))
                                }
                            }
                        } label: {
                            Label("Put it on a route that has none",
                                  systemImage: "plus")
                                .font(.subheadline.weight(.medium))
                                .frame(minHeight: 44)
                        }
                    }
                }
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
    @State private var usedAge = 8
    @State private var leaseTermMonths = 60
    @State private var sort: Sort = .seats
    @State private var hidesLocked = false

    /// Fourteen types with seven attributes each, and no way to order them,
    /// was a catalogue rather than a market (UIUX_FORENSIC_AUDIT UI-017).
    enum Sort: String, CaseIterable, Hashable {
        case seats, range, efficiency, price

        var title: String {
            switch self {
            case .seats: "Seats"
            case .range: "Range"
            case .efficiency: "Fuel per seat"
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

    private func shopRow(_ spec: AircraftTypeSpec, catalog: ContentCatalog,
                         snapshot: GameState, player: AirlineID) -> some View {
        let locked = !snapshot.progression.era.allowedCategories.contains(spec.category)
        let usedPrice = FleetEconomics.usedPrice(
            type: spec, ageYears: Double(usedAge),
            condition: FleetEconomics.usedMarketCondition(
                ageYears: Double(usedAge), tuning: catalog.tuning.fleet),
            tuning: catalog.tuning.fleet)
        return VStack(alignment: .leading, spacing: AETheme.spacingS) {
            HStack(spacing: AETheme.spacingS) {
                Image(systemName: Vocab.categoryIcon(spec.category))
                    .foregroundStyle(locked ? AETheme.mutedText : AETheme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(spec.manufacturer) \(spec.model)")
                        .font(.body.weight(.semibold))
                    Text(Vocab.category(spec.category))
                        .font(.caption).foregroundStyle(AETheme.mutedText)
                }
                Spacer()
                if locked {
                    AEBadge(text: "later era", color: .secondary, icon: "lock")
                }
            }
            HStack(spacing: AETheme.spacingXS) {
                AEChip(icon: "person.2.fill", text: "\(spec.seats) seats")
                AEChip(icon: "arrow.left.and.right", text: "\(spec.rangeKm) km")
                AEChip(icon: "fuelpump.fill",
                       text: "\(Format.decimal(spec.fuelBurnKgPerKm / Double(max(1, spec.seats)), places: 3)) kg/km per seat")
            }

            if locked {
                // A locked row used to show nothing at all, so the player
                // could not plan toward it.
                Text("Unlocks in the \(Vocab.era(unlockEra(for: spec.category))) era. \(Vocab.eraDetail(unlockEra(for: spec.category))).")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("New aircraft arrive after \(Format.days(spec.deliveryLeadDays)); used and leased fly immediately.")
                    .font(.caption2)
                    .foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                purchase("Buy new", price: spec.listPrice, snapshot: snapshot,
                         player: player, detail: "Delivered in \(Format.days(spec.deliveryLeadDays))",
                         command: BuyNewAircraftCommand(buyer: player, type: spec.code))
                purchase("Buy used (\(usedAge)y)", price: usedPrice, snapshot: snapshot,
                         player: player, detail: "Flies immediately, in used condition",
                         command: BuyUsedAircraftCommand(buyer: player, type: spec.code,
                                                         ageYears: usedAge))
                purchase("Lease", price: spec.leaseMonthly, snapshot: snapshot,
                         player: player, isMonthly: true,
                         detail: "\(Format.money(spec.leaseMonthly * Int64(leaseTermMonths))) over \(leaseTermMonths) months",
                         command: LeaseAircraftCommand(lessee: player, type: spec.code,
                                                       termMonths: leaseTermMonths))
            }
        }
        .padding(.vertical, 2)
    }

    /// One purchase option: what it costs, what it leaves, and Core's own
    /// verdict on whether it can be done — before the tap.
    private func purchase(_ title: String, price: Money, snapshot: GameState,
                          player: AirlineID, isMonthly: Bool = false,
                          detail: String, command: any Command) -> some View {
        let blocked = controller.precheck(command)
        let cash = snapshot.ledger.balance(of: player)
        let after = isMonthly ? nil : cash - price
        return VStack(alignment: .leading, spacing: 2) {
            ConfirmableButton(
                title: "\(title)?",
                message: isMonthly
                    ? "\(Format.money(price)) every month for \(leaseTermMonths) months. Returning early costs a penalty."
                    : "\(Format.money(price)) now, leaving \(Format.money(after ?? cash)).",
                confirmTitle: title, role: nil,
                // Dismiss on success, like every other sheet in the app.
                // Without it the largest single action in the game left the
                // player looking at the identical row, with the only evidence
                // a wallet figure scrolled off the top and a feed line on a
                // different tab.
                action: {
                    if controller.submit(command) == nil { dismiss() }
                }
            ) {
                HStack {
                    Text(title).font(.subheadline.weight(.medium))
                    Spacer()
                    Text(isMonthly ? "\(Format.money(price))/mo" : Format.money(price))
                        .font(.subheadline).monospacedDigit()
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .disabled(blocked != nil)
            Text(blocked?.message ?? detail)
                .font(.caption2)
                .foregroundStyle(blocked != nil ? AETheme.caution : AETheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The first era whose allowed categories include this one.
    private func unlockEra(for category: AircraftCategory) -> Era {
        Era.allCases.first { $0.allowedCategories.contains(category) } ?? .empire
    }
}
