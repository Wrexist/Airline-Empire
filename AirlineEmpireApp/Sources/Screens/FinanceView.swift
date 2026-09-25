import SwiftUI
import AirlineEmpireCore

/// The money story (docs/GAME_DESIGN.md §4.9): where it came from, where it
/// went — statements, loans, and the monthly trend.
struct FinanceView: View {
    var body: some View {
        NavigationStack {
            FinanceContent()
                .navigationTitle("Finance")
                .navigationBarTitleDisplayMode(.inline)
                .aeTimeToolbar()
                // Finance links to the routes it names. Without these the
                // links are inert on this tab while working from Home, which
                // pushes the same content into a stack that does declare them
                // — the sort of half-wired navigation §34 asks to hunt for.
                .navigationDestination(for: RouteID.self) {
                    RouteDetailView(routeID: $0)
                }
                .navigationDestination(for: AircraftID.self) {
                    AircraftDetailView(aircraftID: $0)
                }
        }
    }
}

/// The screen itself, without a navigation stack of its own, so the Dashboard
/// can push it as the explanation behind "Last month".
struct FinanceContent: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(GameController.self) private var controller
    @State private var showingLoanSheet = false
    /// The loan an open payoff confirmation is about, held by value. Each row
    /// used to own its dialog, keyed by position: when the simulation retired
    /// a loan the rows shifted, and an open dialog could confirm the payoff
    /// of a different loan from the one it described.
    @State private var payingOff: Loan?

    var body: some View {
        ScrollView {
            if let snapshot = controller.snapshot,
               let player = snapshot.playerAirline,
               let model = snapshot.financeModel(for: player.id),
               let catalog = controller.catalog {
                // Derived once and passed down. The pump publishes several
                // snapshots a second and this is an O(world) read model, so
                // resolving it again inside `runwayCard` doubled the cost of
                // every refresh of this screen.
                let solvency = snapshot.solvencyModel(for: player.id, catalog: catalog)
                let breakdown = snapshot.financeBreakdown(for: player.id, catalog: catalog)
                VStack(spacing: AETheme.spacingM) {
                    if let solvency {
                        SolvencyBanner(model: solvency)
                    }
                    topLine(model)
                    // Three questions, in the order an operator asks them:
                    // is the airline earning, where did the cash go, and what
                    // must it find every month.
                    operatingPanel(breakdown, dayOfMonth: snapshot.currentDate.day)
                    cashPanel(breakdown, cash: model.cash)
                    trendCard(model)
                    DisclosureGroup("Cash runway & credit limits") {
                        runwayCard(model, solvency: solvency).padding(.top, 8)
                    }
                    .font(.subheadline)
                    .tint(AETheme.mutedText)
                    .padding(.horizontal, 4)
                    routeExtremes()
                    statementCard(snapshot: snapshot, player: player.id)
                    commitmentsPanel(breakdown)
                    loansCard(model, snapshot: snapshot, player: player.id)
                }
                .aePageInsets()
                // A reading width on iPad, as the other management screens
                // have: full-width in landscape put each label ~1000pt from
                // its amount.
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
            } else {
                LoadingState(message: "Adding it up")
                    .frame(minHeight: 240)
            }
        }
        .aeScreenBackground()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Borrow") { showingLoanSheet = true }
            }
        }
        .sheet(isPresented: $showingLoanSheet) {
            LoanSheet()
        }
    }

    private func topLine(_ model: FinanceModel) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Cash available").font(.subheadline).foregroundStyle(AETheme.mutedText)
                Text(Format.money(model.cash))
                    .accessibilityLabel("Cash available, \(Format.moneyAccessibility(model.cash))")
                    .font(.system(.largeTitle, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(model.cash.isNegative ? AETheme.negative : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                let metricsLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 20))
                metricsLayout {
                    balanceMetric("Net worth", Format.money(model.netWorth))
                    balanceMetric("Debt", Format.money(model.totalDebt))
                    balanceMetric("Leverage", Format.percent(model.debtRatio))
                }
            }
        }
    }

    private func balanceMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(AETheme.mutedText)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Is the airline making money flying aeroplanes? (MASTER PROMPT 4 §15.)
    ///
    /// The tiles above answer "what is the airline worth"; this answers "is it
    /// working", this month to date, from the ledger's own live month
    /// accumulator — the same postings the month-end statement will close
    /// over. The route figure below it is deliberately the *direct*
    /// contribution: it says what the network earns before the company costs
    /// the commitments panel lists, and the two are labelled so they cannot be
    /// read as the same number.
    private func operatingPanel(_ breakdown: FinanceBreakdown, dayOfMonth: Int) -> some View {
        AEPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Operating performance",
                                systemImage: "chart.line.uptrend.xyaxis")
                periodLabel("This month (to date)")
                if let flow = breakdown.monthToDate, flow.hasOperatingActivity {
                    figureRow("Revenue", flow.operatingRevenue)
                    figureRow("Operating costs", flow.operatingExpenses)
                    Divider()
                    figureTotal("Operating profit", flow.operatingProfit)
                    // Leases, payroll, overhead and interest all bill on the
                    // 1st (FleetBillingSystem, EconomySystem) while fares
                    // arrive flight by flight, so every month opens in the
                    // red. Without this line a healthy airline read as a
                    // failing one for the first ten days of every month.
                    if flow.operatingProfit.isNegative && dayOfMonth <= 10 {
                        Text("Leases, payroll and overhead are billed on the 1st; fares build up day by day. An early-month loss is normal — judge the month when it closes.")
                            .font(.caption).foregroundStyle(AETheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Nothing has operated since the last month boundary.")
                        .font(.caption).foregroundStyle(AETheme.mutedText)
                }
                if let network = controller.networkSummary, network.routeCount > 0 {
                    Divider()
                    periodLabel("Routes this month")
                    Text("Direct contribution \(Format.money(network.monthToDateProfit)) after fuel, fees and crew — before maintenance, leases, payroll and overhead.")
                        .font(.caption).foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Cash, which is not the same claim as profit.
    ///
    /// A month can be profitable and still lose cash (buying an aircraft), or
    /// lose money and gain cash (a loan drawdown). Both are shown, and the
    /// note says which movements are which, rather than letting one number
    /// stand in for the other.
    private func cashPanel(_ breakdown: FinanceBreakdown, cash: Money) -> some View {
        AEPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Cash movements",
                                systemImage: "arrow.left.arrow.right")
                if let flow = breakdown.monthToDate {
                    periodLabel("This month (to date)")
                    figureRow("From operations", flow.operatingProfit)
                    figureRow("Capital movements", flow.capitalMovements)
                    figureRow("Loan interest", flow.financingCost)
                    Divider()
                    figureTotal("Net cash change", flow.netCashChange)
                    Text("Cash in hand \(Format.money(cash)). Cash change is not profit: aircraft, loan principal and founding capital move cash without touching operating profit.")
                        .font(.caption).foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Nothing has moved since the last month boundary. Cash in hand \(Format.money(cash)).")
                        .font(.caption).foregroundStyle(AETheme.mutedText)
                }
            }
        }
    }

    private func periodLabel(_ text: String) -> some View {
        Text(text)
            .font(AEType.eyebrow)
            .foregroundStyle(AETheme.mutedText)
            .accessibilityAddTraits(.isHeader)
    }

    // Plain rows, no `children: .combine`: other journeys query the
    // statement's own "Net profit" static text, and merging the row would
    // take that label away. They stack at large text sizes rather than
    // squeezing the figure against its label.
    private func figureRow(_ label: String, _ money: Money) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                MoneyText(money: money).font(.subheadline)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline)
                MoneyText(money: money).font(.subheadline)
            }
        }
    }

    private func figureTotal(_ label: String, _ money: Money) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(label).font(.subheadline.weight(.semibold))
                Spacer()
                MoneyText(money: money).font(.subheadline.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline.weight(.semibold))
                MoneyText(money: money).font(.subheadline.weight(.semibold))
            }
        }
    }

    /// What must be found every month, at today's size and contracts.
    ///
    /// Leases, loan payments and station services are exact charges the
    /// simulation will post; payroll is charged from the fleet and routes
    /// held at the boundary, so it is an estimate and says so. Loan payments
    /// include principal, which reduces debt rather than counting as a cost.
    private func commitmentsPanel(_ breakdown: FinanceBreakdown) -> some View {
        let recurring = breakdown.recurring
        return AEPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Monthly commitments",
                                systemImage: "calendar.badge.clock")
                Text("What the airline must find every month at today's size and contracts.")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                commitmentRow("Aircraft leases", recurring.leases, link: .fleet)
                commitmentRow("Loan payments", recurring.loanPayments, link: nil)
                ForEach(recurring.stationsByAirport.keys.sorted(), id: \.self) { code in
                    NavigationLink {
                        AirportDetailView(code: code, initialSection: .facilities)
                    } label: {
                        commitmentLabel("\(code.raw) services",
                                        recurring.stationsByAirport[code] ?? .zero,
                                        linked: true, tint: AETheme.accent)
                    }
                    .buttonStyle(.aePress)
                }
                commitmentRow("Payroll (estimate)", recurring.payroll, link: nil)
                commitmentRow("Company overhead", recurring.overhead, link: nil)
                Divider()
                figureTotal("Total each month", recurring.monthlyTotal)
                Text("Payroll is charged from the fleet and routes held at the month boundary; leases, station services and loan service bill there too, so they land in the following month's statement. Loan payments include principal, which reduces debt rather than counting as a cost.")
                    .font(.caption2).foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func commitmentRow(_ label: String, _ money: Money, link: FinanceLink?) -> some View {
        if let link {
            NavigationLink {
                destination(for: link)
            } label: {
                commitmentLabel(label, money, linked: true, tint: AETheme.accent)
            }
            .buttonStyle(.aePress)
        } else {
            commitmentLabel(label, money, linked: false, tint: nil)
        }
    }

    private func commitmentLabel(_ label: String, _ money: Money,
                                 linked: Bool, tint: Color?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(label).font(.subheadline).foregroundStyle(tint ?? .primary)
                Spacer()
                moneyWithChevron(money, linked: linked)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline).foregroundStyle(tint ?? .primary)
                moneyWithChevron(money, linked: linked)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func moneyWithChevron(_ money: Money, linked: Bool) -> some View {
        HStack(spacing: AETheme.spacingXS) {
            MoneyText(money: money).font(.subheadline)
            if linked {
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(AETheme.mutedText)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Where an expense's decision lives. Only categories a player can act on
    /// through another screen carry a destination; payroll and overhead do
    /// not, and a link that led somewhere unconnected would be worse than
    /// none.
    private enum FinanceLink { case routes, fleet, service }

    @ViewBuilder
    private func destination(for link: FinanceLink) -> some View {
        switch link {
        case .routes: RoutesList().navigationTitle("Routes").aeTimeToolbar()
        case .fleet: FleetList().navigationTitle("Fleet").aeTimeToolbar()
        case .service: PassengerExperienceView()
        }
    }

    private func financeLink(_ category: TransactionCategory) -> FinanceLink? {
        switch category {
        case .ticketRevenue, .missionReward, .fuel, .airportFees, .crewCosts:
            return .routes
        case .maintenance, .leasePayment, .leasePenalty, .aircraftPurchase, .aircraftSale:
            return .fleet
        case .passengerService:
            return .service
        case .initialCapital, .salaries, .overhead, .loanProceeds, .loanPrincipal, .loanInterest:
            return nil
        }
    }

    /// Which routes are carrying the airline and which are dragging on it.
    ///
    /// §15 asks for best and weakest routes. Both come from the route cards
    /// the controller already caches per tick, so this is a sort rather than a
    /// second derivation — and the figures therefore match the Routes board
    /// exactly.
    @ViewBuilder
    private func routeExtremes() -> some View {
        let ranked = controller.routeCards
            .filter { $0.assignedAircraftCount > 0 }
            .sorted { $0.thisMonthProfit.cents > $1.thisMonthProfit.cents }
        // Two routes are the minimum for "best" and "weakest" to mean
        // anything; with one, the same row would be both.
        if ranked.count >= 2, let best = ranked.first, let worst = ranked.last {
            AEPanel {
                VStack(alignment: .leading, spacing: AETheme.spacingS) {
                    AESectionHeader(text: "Carrying and dragging",
                                    systemImage: "arrow.up.arrow.down")
                    extremeRow("Best", best, tint: AETheme.positive)
                    extremeRow("Weakest", worst,
                               tint: worst.thisMonthProfit.isNegative
                                   ? AETheme.negative : AETheme.mutedText)
                }
            }
        }
    }

    /// One end of the ranking, as a row that pushes to the route it names.
    ///
    /// `tint` colours the city pair, not the money: `MoneyText` sets its own
    /// foreground from the sign of the figure and so overrides anything
    /// inherited. That is deliberate — the profit's colour must follow the
    /// number, never the row it happens to sit in, or a "best" route that is
    /// losing money would be shown in green. The sign is in the text either
    /// way, so the colour only ever confirms what the row already says.
    private func extremeRow(_ label: String, _ card: RouteCardModel,
                            tint: Color) -> some View {
        NavigationLink(value: card.id) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(AEType.caption)
                        .foregroundStyle(AETheme.mutedText)
                    Text("\(card.origin.raw) – \(card.destination.raw)")
                        .font(AEType.code)
                }
                Spacer()
                MoneyText(money: card.thisMonthProfit)
                    .font(AEType.metricCompact)
                Image(systemName: "chevron.right")
                    .font(AEType.caption)
                    .foregroundStyle(AETheme.mutedText)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.aePress)
        .foregroundStyle(tint)
    }

    /// The number that actually decides whether a player is in trouble, and
    /// which the app never computed: how long the cash lasts at this burn.
    private func runwayCard(_ model: FinanceModel,
                            solvency: SolvencyModel?) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "How long the money lasts",
                                systemImage: "hourglass")
                if let solvency {
                    if let months = solvency.monthsOfRunway {
                        HStack {
                            Text("At last month's burn")
                            Spacer()
                            Text("\(Format.decimal(months, places: 1)) months")
                                .monospacedDigit()
                                .foregroundStyle(months < 3 ? AETheme.negative
                                                 : months < 6 ? AETheme.caution
                                                 : AETheme.positive)
                        }
                        .font(.subheadline)
                    } else if model.monthlySeries.isEmpty {
                        Text("No month has closed yet, so there is nothing to forecast from. The first statement lands at the end of the month.")
                            .font(.subheadline)
                            .foregroundStyle(AETheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Label("Last month made money — there is no burn to run out of.",
                              systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(AETheme.positive)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Text("Creditors step in below")
                        Spacer()
                        Text(Format.money(solvency.overdraftFloor)).monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
                }
            }
        }
    }

    private func trendCard(_ model: FinanceModel) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Monthly net profit", systemImage: "chart.bar")
                if model.monthlySeries.isEmpty {
                    Text("First statement closes at the end of the month.")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.mutedText)
                } else {
                    MonthlyBars(points: model.monthlySeries)
                        .frame(height: 160)
                }
            }
        }
    }

    /// The last closed month, grouped so it reads as a P&L rather than a list
    /// of every category in enum order: revenue, operating costs, the
    /// operating line, financing, then the net line. Capital movements sit
    /// behind a disclosure because they are real cash but not profit.
    ///
    /// The header keeps its exact "Mar 2030 statement" shape — a journey
    /// asserts that string — and "Net profit" stays an uncombined label for
    /// the same reason.
    private func statementCard(snapshot: GameState, player: AirlineID) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                if let statement = snapshot.finance.byAirline[player]?.latest {
                    AESectionHeader(
                        text: "\(Format.monthAbbreviation(statement.month)) \(statement.year) statement",
                        systemImage: "doc.text")
                    Text("Closed month · every cent classified")
                        .font(.caption).foregroundStyle(AETheme.mutedText)
                    categoryGroup(statement, .operatingRevenue)
                    categoryGroup(statement, .operatingExpense)
                    Divider()
                    figureTotal("Operating profit", statement.operatingProfit)
                    if !categories(statement, .financing).isEmpty {
                        categoryGroup(statement, .financing)
                    }
                    Divider()
                    figureTotal("Net profit", statement.netProfit)
                    if !categories(statement, .capital).isEmpty {
                        capitalDisclosure(statement)
                    }
                } else {
                    AESectionHeader(text: "Latest statement", systemImage: "doc.text")
                    Text("No closed month yet.")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.mutedText)
                }
            }
        }
    }

    @ViewBuilder
    private func capitalDisclosure(_ statement: MonthlyStatement) -> some View {
        DisclosureGroup("Capital movements (not in profit)") {
            VStack(alignment: .leading, spacing: AETheme.spacingXS) {
                ForEach(categories(statement, .capital), id: \.self) { category in
                    categoryRow(statement, category)
                }
                Text("Aircraft, loan principal and founding capital move cash without touching profit — they are in Cash movements above.")
                    .font(.caption2).foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .font(.subheadline)
        .tint(AETheme.mutedText)
    }

    /// The non-zero categories in one classification, largest magnitude
    /// first, so the biggest cost is the first thing read.
    private func categories(_ statement: MonthlyStatement,
                            _ classification: CategoryClassification) -> [TransactionCategory] {
        statement.byCategory.keys
            .filter {
                $0.classification == classification
                    && (statement.byCategory[$0] ?? 0) != 0
            }
            .sorted {
                abs(statement.byCategory[$0] ?? 0) > abs(statement.byCategory[$1] ?? 0)
            }
    }

    @ViewBuilder
    private func categoryGroup(_ statement: MonthlyStatement,
                               _ classification: CategoryClassification) -> some View {
        let items = categories(statement, classification)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: AETheme.spacingXS) {
                ForEach(items, id: \.self) { category in
                    categoryRow(statement, category)
                }
            }
        }
    }

    @ViewBuilder
    private func categoryRow(_ statement: MonthlyStatement,
                             _ category: TransactionCategory) -> some View {
        let money = statement.total(category)
        if let link = financeLink(category) {
            NavigationLink {
                destination(for: link)
            } label: {
                categoryLabel(category, money, linked: true)
            }
            .buttonStyle(.aePress)
            .accessibilityIdentifier("ae-finance-category-\(category.rawValue)")
        } else {
            categoryLabel(category, money, linked: false)
        }
    }

    private func categoryLabel(_ category: TransactionCategory, _ money: Money,
                               linked: Bool) -> some View {
        HStack {
            Text(DigestCard.label(for: category)).font(.subheadline)
            Spacer()
            MoneyText(money: money).font(.subheadline)
            if linked {
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(AETheme.mutedText)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func loansCard(_ model: FinanceModel, snapshot: GameState,
                           player: AirlineID) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Loans", systemImage: "banknote")
                if model.loans.isEmpty {
                    Text("No outstanding loans").font(.subheadline)
                        .foregroundStyle(AETheme.mutedText)
                } else {
                    ForEach(Array(model.loans.enumerated()), id: \.offset) { _, loan in
                        loanRow(loan, player: player)
                    }
                }
            }
        }
        // One confirmation for the card, presenting the loan it was opened
        // for (`payingOff`), so what it says and what it pays off cannot come
        // apart when the rows shift.
        .confirmationDialog("Pay off this loan?",
                            isPresented: Binding(get: { payingOff != nil },
                                                 set: { if !$0 { payingOff = nil } }),
                            titleVisibility: .visible, presenting: payingOff) { loan in
            Button("Pay off") { repay(loan, player: player) }
                .accessibilityIdentifier("ae-confirm-action")
            Button("Cancel", role: .cancel) {}
        } message: { loan in
            Text("\(Format.money(loan.principalRemaining)) leaves your cash now, and the \(Format.money(loan.monthlyPayment)) monthly payment stops.")
        }
    }

    private func loanRow(_ loan: Loan, player: AirlineID) -> some View {
        // Core refuses a payoff the cash cannot cover. Asked before the tap,
        // as the fleet screen does — the button used to take a confirmation
        // and then fail.
        let blocked = payoffRefusal(loan, player: player)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Format.money(loan.principalRemaining))
                        .font(.subheadline.weight(.medium))
                    Text("\(Format.decimal(Double(loan.annualRateBasisPoints) / 100, places: 1))% · \(loan.monthsRemaining) \(loan.monthsRemaining == 1 ? "month" : "months") · \(Format.money(loan.monthlyPayment))/mo")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                }
                Spacer()
                Button {
                    // Honours the confirmations setting, as `ConfirmableButton`
                    // does; the dialog itself is the card's (`payingOff`).
                    if controller.preferences.confirmDestructive {
                        payingOff = loan
                    } else {
                        repay(loan, player: player)
                    }
                } label: {
                    Text("Pay off").frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .font(.caption)
                .disabled(blocked != nil)
            }
            // The reason alone: the generic "take a loan" advice for a
            // cash shortfall is no advice for paying one off.
            if let blocked {
                RefusalNote(rejection: blocked, detail: .reason)
            }
        }
    }

    /// Whether paying off `loan` would be accepted now. Resolved by value,
    /// like `repay`, because the command addresses loans by index.
    private func payoffRefusal(_ loan: Loan, player: AirlineID) -> CommandRejection? {
        guard let index = controller.snapshot?.airlines[player]?.loans.firstIndex(of: loan)
        else { return nil }
        return controller.precheck(RepayLoanCommand(airline: player, loanIndex: index))
    }

    /// `RepayLoanCommand` addresses a loan **by array index**, and the index
    /// a row was rendered with can be stale by the time it is tapped — the
    /// simulation retires loans on its own schedule. Resolving the index from
    /// the current snapshot at tap time means the worst case is a no-op rather
    /// than paying off somebody else's loan (UIUX_FORENSIC_AUDIT UI-021).
    private func repay(_ loan: Loan, player: AirlineID) {
        guard let current = controller.snapshot?.airlines[player]?.loans,
              let index = current.firstIndex(of: loan) else { return }
        controller.submit(RepayLoanCommand(airline: player, loanIndex: index))
    }
}

/// Borrowing.
///
/// This was already the best transactional surface in the app — it quotes the
/// simulation's own rate, payment and resulting leverage before you commit.
/// What it lacked: the total cost of the debt, and a refusal that arrives
/// before the tap rather than as an alert underneath this sheet.
struct LoanSheet: View {
    @Environment(GameController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @State private var amountMillions = 10.0
    @State private var termMonths = 48.0
    @State private var rejection: CommandRejection?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AETheme.spacingM) {
                    AEPageIntro(title: "Room to grow",
                                subtitle: "Choose your funding. See the full cost before you commit.",
                                icon: "building.columns")
                    requestCard
                    if let snapshot = controller.snapshot,
                       let player = snapshot.playerAirline,
                       let catalog = controller.catalog {
                        quote(snapshot: snapshot, player: player, catalog: catalog)
                        AECard { confirm(player: player.id) }
                    }
                }
                .aePageInsets()
            }
            .aeScreenBackground()
            .navigationTitle("Borrow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var requestCard: some View {
        AECard {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Amount", value: Format.money(amount))
                        .font(.headline).monospacedDigit()
                    Slider(value: $amountMillions, in: 1...200, step: 1)
                        .accessibilityLabel("Loan amount")
                        .accessibilityValue(Format.money(amount))
                }
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Term", value: "\(Int(termMonths)) months")
                        .font(.headline).monospacedDigit()
                    Slider(value: $termMonths, in: 6...120, step: 6)
                        .accessibilityLabel("Loan term")
                        .accessibilityValue("\(Int(termMonths)) months")
                }
            }
            .tint(AETheme.accent)
        }
    }

    private func quote(snapshot: GameState, player: Airline, catalog: ContentCatalog) -> some View {
        let ratio = CreditMath.debtRatio(of: player, state: snapshot, additional: amount)
        let rate = CreditMath.offeredRateBasisPoints(debtRatio: ratio, tuning: catalog.tuning.finance)
        let payment = CreditMath.annuityPayment(principal: amount,
                                               monthlyRate: Double(rate) / 10_000 / 12,
                                               months: Int(termMonths))
        let total = payment * Int64(termMonths)
        return AEPanel {
            VStack(alignment: .leading, spacing: 16) {
                AESectionHeader(text: "What this costs", systemImage: "receipt")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monthly payment").font(.caption).foregroundStyle(AETheme.mutedText)
                    Text(Format.money(payment))
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
                Divider()
                LabeledContent("Offered rate", value: "\(Format.decimal(Double(rate) / 100, places: 1))%")
                LabeledContent("Total repaid", value: Format.money(total))
                LabeledContent("Interest over the term", value: Format.money(total - amount))
                LabeledContent("Leverage after", value: Format.percent(ratio))
            }
        }
    }

    private var amount: Money {
        Money.dollars(Int64(amountMillions) * 1_000_000)
    }

    private func confirm(player: AirlineID) -> some View {
        let command = TakeLoanCommand(airline: player, amount: amount,
                                      termMonths: Int(termMonths))
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
                // Stays open and explains itself if Core refuses.
                if let refusal = controller.submit(command) {
                    rejection = refusal
                    controller.clearRejection()
                } else {
                    dismiss()
                }
            } label: {
                Text("Take this loan")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.aePrimary)
            .disabled(blocked != nil)
        }
    }
}
