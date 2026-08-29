import SwiftUI
import AirlineEmpireCore

/// The money story (docs/GAME_DESIGN.md §4.9): where it came from, where it
/// went — statements, loans, and the monthly trend.
struct FinanceView: View {
    @Environment(GameController.self) private var controller
    @State private var showingLoanSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let snapshot = controller.snapshot,
                   let player = snapshot.playerAirline,
                   let model = snapshot.financeModel(for: player.id) {
                    VStack(spacing: AETheme.spacingM) {
                        topLine(model)
                        trendCard(model)
                        statementCard(snapshot: snapshot, player: player.id)
                        loansCard(model, player: player.id)
                    }
                    .padding(.horizontal)
                } else {
                    ProgressView()
                }
            }
            .aeScreenBackground()
            .navigationTitle("Finance")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Borrow") { showingLoanSheet = true }
                }
            }
            .sheet(isPresented: $showingLoanSheet) {
                LoanSheet()
            }
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

    private func trendCard(_ model: FinanceModel) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                Text("Monthly net profit").font(.headline)
                if model.monthlySeries.isEmpty {
                    Text("First statement closes at the end of the month.")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.mutedText)
                } else {
                    MonthlyBars(points: model.monthlySeries)
                        .frame(height: 120)
                }
            }
        }
    }

    private func statementCard(snapshot: GameState, player: AirlineID) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                Text("Latest statement").font(.headline)
                if let statement = snapshot.finance.byAirline[player]?.latest {
                    statementRows(statement)
                } else {
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
                Text(label(for: category)).font(.subheadline)
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

    private func loansCard(_ model: FinanceModel, player: AirlineID) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                Text("Loans").font(.headline)
                if model.loans.isEmpty {
                    Text("Debt-free.").font(.subheadline)
                        .foregroundStyle(AETheme.mutedText)
                } else {
                    ForEach(Array(model.loans.enumerated()), id: \.offset) { index, loan in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(Format.money(loan.principalRemaining))
                                    .font(.subheadline.weight(.medium))
                                Text("\(String(format: "%.1f", Double(loan.annualRateBasisPoints) / 100))% · \(loan.monthsRemaining) months · \(Format.money(loan.monthlyPayment))/mo")
                                    .font(.caption)
                                    .foregroundStyle(AETheme.mutedText)
                            }
                            Spacer()
                            Button("Pay off") {
                                controller.submit(RepayLoanCommand(
                                    airline: player, loanIndex: index))
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }

    /// One name per category across the whole app (see DigestCard).
    private func label(for category: TransactionCategory) -> String {
        DigestCard.label(for: category)
    }
}

struct LoanSheet: View {
    @Environment(GameController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @State private var amountMillions = 10.0
    @State private var termMonths = 48.0

    var body: some View {
        NavigationStack {
            Form {
                VStack(alignment: .leading) {
                    Text("Amount: ¤\(Int(amountMillions))M")
                    Slider(value: $amountMillions, in: 1...200, step: 1)
                }
                VStack(alignment: .leading) {
                    Text("Term: \(Int(termMonths)) months")
                    Slider(value: $termMonths, in: 6...120, step: 6)
                }
                if let snapshot = controller.snapshot,
                   let player = snapshot.playerAirline,
                   let catalog = controller.catalog {
                    let amount = Money.dollars(Int64(amountMillions) * 1_000_000)
                    let ratio = CreditMath.debtRatio(of: player, state: snapshot,
                                                     additional: amount)
                    let rate = CreditMath.offeredRateBasisPoints(
                        debtRatio: ratio, tuning: catalog.tuning.finance)
                    let payment = CreditMath.annuityPayment(
                        principal: amount,
                        monthlyRate: Double(rate) / 10_000 / 12,
                        months: Int(termMonths))
                    // The exact numbers the simulation will charge.
                    LabeledContent("Offered rate",
                                   value: "\(String(format: "%.1f", Double(rate) / 100))%")
                    LabeledContent("Monthly payment", value: Format.money(payment))
                    LabeledContent("Debt after", value: Format.percent(ratio))
                }
                Button("Take loan") {
                    if let player = controller.snapshot?.playerAirline?.id {
                        controller.submit(TakeLoanCommand(
                            airline: player,
                            amount: Money.dollars(Int64(amountMillions) * 1_000_000),
                            termMonths: Int(termMonths)))
                    }
                    dismiss()
                }
                .font(.headline)
            }
            .navigationTitle("Borrow")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
