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
        }
    }
}

/// The screen itself, without a navigation stack of its own, so the Dashboard
/// can push it as the explanation behind "Last month".
struct FinanceContent: View {
    @Environment(GameController.self) private var controller
    @State private var showingLoanSheet = false

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
                VStack(spacing: AETheme.spacingM) {
                    if let solvency {
                        SolvencyBanner(model: solvency)
                    }
                    topLine(model)
                    runwayCard(model, solvency: solvency)
                    trendCard(model)
                    statementCard(snapshot: snapshot, player: player.id)
                    loansCard(model, snapshot: snapshot, player: player.id)
                }
                .padding(.horizontal)
                .padding(.bottom, AETheme.spacingL)
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
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                  spacing: AETheme.spacingS) {
            StatTile(label: "Cash", value: Format.money(model.cash),
                     trend: model.cash.isNegative ? .down : .neutral)
            StatTile(label: "Net worth", value: Format.money(model.netWorth))
            StatTile(label: "Debt", value: Format.money(model.totalDebt))
            StatTile(label: "Leverage", value: Format.percent(model.debtRatio),
                     trend: model.debtRatio > 0.6 ? .down : .neutral)
        }
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

    private func statementCard(snapshot: GameState, player: AirlineID) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                if let statement = snapshot.finance.byAirline[player]?.latest {
                    AESectionHeader(
                        text: "\(Format.monthAbbreviation(statement.month)) \(statement.year) statement",
                        systemImage: "doc.text")
                    statementRows(statement)
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
    private func statementRows(_ statement: MonthlyStatement) -> some View {
        // Sorted category rows: every cent classified and visible.
        let rows = statement.byCategory
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .filter { $0.value != 0 }
        ForEach(rows, id: \.key) { category, cents in
            HStack {
                Text(DigestCard.label(for: category)).font(.subheadline)
                Spacer()
                MoneyText(money: Money(cents: cents)).font(.subheadline)
            }
        }
        Divider()
        HStack {
            Text("Operating profit").font(.subheadline.weight(.semibold))
            Spacer()
            MoneyText(money: statement.operatingProfit)
        }
        HStack {
            Text("Net profit").font(.subheadline.weight(.semibold))
            Spacer()
            MoneyText(money: statement.netProfit)
        }
    }

    private func loansCard(_ model: FinanceModel, snapshot: GameState,
                           player: AirlineID) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Loans", systemImage: "banknote")
                if model.loans.isEmpty {
                    Text("Debt-free.").font(.subheadline)
                        .foregroundStyle(AETheme.mutedText)
                } else {
                    ForEach(Array(model.loans.enumerated()), id: \.offset) { _, loan in
                        loanRow(loan, player: player)
                    }
                }
            }
        }
    }

    private func loanRow(_ loan: Loan, player: AirlineID) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(Format.money(loan.principalRemaining))
                    .font(.subheadline.weight(.medium))
                Text("\(Format.decimal(Double(loan.annualRateBasisPoints) / 100, places: 1))% · \(loan.monthsRemaining) months · \(Format.money(loan.monthlyPayment))/mo")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
            }
            Spacer()
            ConfirmableButton(
                title: "Pay off this loan?",
                message: "\(Format.money(loan.principalRemaining)) leaves your cash now, and the \(Format.money(loan.monthlyPayment)) monthly payment stops.",
                confirmTitle: "Pay off", role: nil,
                action: { repay(loan, player: player) }
            ) {
                Text("Pay off").frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .font(.caption)
        }
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
            Form {
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Amount")
                            Spacer()
                            Text("\(Format.money(amount))").monospacedDigit()
                        }
                        Slider(value: $amountMillions, in: 1...200, step: 1)
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Term")
                            Spacer()
                            Text("\(Int(termMonths)) months").monospacedDigit()
                        }
                        Slider(value: $termMonths, in: 6...120, step: 6)
                    }
                }

                if let snapshot = controller.snapshot,
                   let player = snapshot.playerAirline,
                   let catalog = controller.catalog {
                    let ratio = CreditMath.debtRatio(of: player, state: snapshot,
                                                     additional: amount)
                    let rate = CreditMath.offeredRateBasisPoints(
                        debtRatio: ratio, tuning: catalog.tuning.finance)
                    let payment = CreditMath.annuityPayment(
                        principal: amount,
                        monthlyRate: Double(rate) / 10_000 / 12,
                        months: Int(termMonths))
                    let total = payment * Int64(termMonths)
                    Section("What this costs") {
                        // The exact numbers the simulation will charge.
                        LabeledContent("Offered rate",
                                       value: "\(Format.decimal(Double(rate) / 100, places: 1))%")
                        LabeledContent("Monthly payment", value: Format.money(payment))
                        LabeledContent("Total repaid", value: Format.money(total))
                        LabeledContent("Interest over the term",
                                       value: Format.money(total - amount))
                        LabeledContent("Leverage after", value: Format.percent(ratio))
                    }

                    Section {
                        confirm(player: player.id)
                    }
                }
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
