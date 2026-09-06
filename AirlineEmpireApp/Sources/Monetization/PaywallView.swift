import SwiftUI
import StoreKit
import AirlineEmpireCore

/// The screen that sells Pro (docs/MONETIZATION.md §5).
///
/// Its structure is the argument, in order: what this game is → how big it is
/// → what Pro adds → what it costs → exactly what will be charged → the
/// button. Nothing about the price is hidden behind a scroll, and the
/// commitment sentence sits directly above the button rather than in the
/// footnote, which is where the reference designs put it and where App Review
/// rejects it from ("Your auto-renewable subscription promotes the free trial
/// or introductory period more clearly and conspicuously than the billed
/// amount").
///
/// The copy is all `PaywallContent`, in Core, where a Linux test asserts that
/// the required clauses are present. This file is layout.
struct PaywallView: View {
    /// What raised the sheet. Decides the headline only — the offer is the
    /// same however the player arrived, because a paywall that charges
    /// differently depending on which door you came through is the thing
    /// players screenshot.
    let gate: ProGate

    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements
    @Environment(GameController.self) private var controller
    @Environment(\.openURL) private var openURL

    @State private var selection: ProProduct = .default
    /// The content pack, for the counter bar.
    ///
    /// Not simply `controller.catalog`: that is only populated once a game is
    /// open, and this sheet is raised from the new-game screen too — by the
    /// scenario and save-slot gates. Reading it from the controller alone
    /// meant the paywall lost its strongest element (94 airports, 14
    /// aircraft) on exactly the two entries where the player has not seen the
    /// game yet. Loaded the same way `NewGameView` loads it, once, on appear.
    @State private var catalog: ContentCatalog?

    var body: some View {
        ZStack {
            AEDuskBackdrop()
            content
        }
        .aeSheetFeedback()
        .onAppear {
            catalog = controller.catalog ?? (try? ContentCatalog.loadBundled())
        }
        .toolbar { closeButton }
        .toolbarBackground(.hidden, for: .navigationBar)
        .alert("Restore purchases",
               isPresented: restoreFailedPresented) {
            Button("OK", role: .cancel) { entitlements.lastOutcome = nil }
        } message: {
            Text("No previous purchase was found for this Apple Account. If "
                 + "you bought Pro on another account, sign in with it in "
                 + "Settings and try again.")
        }
    }

    // MARK: - Body

    private var content: some View {
        ScrollView {
            VStack(spacing: AETheme.spacingL) {
                PaywallSky()

                VStack(spacing: AETheme.spacingS) {
                    Text(gate.headline)
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(gate.subhead)
                        .font(AEType.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AETheme.spacingS)

                if let catalog {
                    PaywallStatBar(stats: PaywallContent.stats(catalog: catalog))
                }

                PaywallBenefits()

                plans

                // Everything below is required disclosure and the button it
                // qualifies. Grouped so it can never be separated by an edit.
                VStack(spacing: AETheme.spacingM) {
                    Text(PaywallContent.subscriptionTerms)
                        .font(AEType.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider().overlay(AETheme.glassEdge)

                    commitment
                    callToAction
                    assurances
                }

                declineButton
                legalRow
            }
            .padding(AETheme.spacingM)
            .padding(.bottom, AETheme.spacingL)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Plans

    private var plans: some View {
        VStack(spacing: AETheme.spacingS) {
            ForEach(ProProduct.allCases.sorted { $0.displayOrder < $1.displayOrder },
                    id: \.self) { tier in
                PaywallPlanCard(
                    tier: tier,
                    isSelected: selection == tier,
                    price: entitlements.displayPrice(tier),
                    introductoryPrice: entitlements.introductoryPrice(tier),
                    period: entitlements.periodName(tier),
                    savings: entitlements.savingsVersusWeekly(tier),
                    footnote: entitlements.perWeekEquivalent(tier)) {
                        withAnimation(AEMotion.selection) { selection = tier }
                    }
            }

            if let failure = entitlements.loadFailure {
                HStack(spacing: AETheme.spacingS) {
                    Image(systemName: "wifi.slash")
                    Text(failure)
                    Button("Retry") {
                        Task { await entitlements.loadProducts() }
                    }
                    .buttonStyle(.aeTertiary)
                }
                .font(AEType.secondary)
                .foregroundStyle(.secondary)
                .padding(.top, AETheme.spacingXS)
            }
        }
        .aeFeedback(.uiSelect, on: selection)
    }

    // MARK: - The commitment, the button, and the small print

    /// The sentence that says what will be charged. Directly above the
    /// button, at body size, never in a footnote.
    @ViewBuilder
    private var commitment: some View {
        if let line = entitlements.commitmentLine(selection) {
            Text(line)
                .font(AEType.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ae-paywall-commitment")
        }
    }

    private var callToAction: some View {
        Button {
            Task { await entitlements.purchase(selection) }
        } label: {
            HStack(spacing: AETheme.spacingS) {
                if entitlements.isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(entitlements.callToAction(selection))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.aePrimary)
        .disabled(entitlements.isPurchasing
                  || entitlements.displayPrice(selection) == nil)
        .accessibilityIdentifier("ae-paywall-buy")
    }

    private var assurances: some View {
        AEChipRow {
            ForEach(PaywallContent.assurances, id: \.self) { claim in
                AEChip(icon: "checkmark.seal", text: claim)
            }
        }
    }

    private var declineButton: some View {
        Button(PaywallContent.decline) { dismiss() }
            .buttonStyle(.aeTertiary)
            .accessibilityIdentifier("ae-paywall-decline")
    }

    /// Restore, Terms and Privacy. Apple requires all three to be present and
    /// functional on the screen that sells the subscription; a missing link
    /// is a guideline 3.1.2 rejection on its own.
    private var legalRow: some View {
        AEChipRow {
            Button {
                Task { await entitlements.restore() }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
            }
            .accessibilityIdentifier("ae-paywall-restore")

            Button("Terms of Use") { openURL(PaywallContent.termsURL) }
            Button("Privacy Policy") { openURL(PaywallContent.privacyURL) }
        }
        .font(AEType.secondary)
        .tint(.secondary)
        .disabled(entitlements.isPurchasing)
    }

    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close")
        }
    }

    private var restoreFailedPresented: Binding<Bool> {
        Binding(get: { entitlements.lastOutcome == .nothingToRestore },
                set: { if !$0 { entitlements.lastOutcome = nil } })
    }
}

// MARK: - Presentation

extension View {
    /// Mounts the paywall wherever `Entitlements.presentedGate` is raised.
    ///
    /// Applied once, at the root, for the reason `RootView` already gives
    /// about its alerts: a sheet mounted on a tab could not appear over
    /// another sheet and could not appear on the menu at all, which is how a
    /// message reached nobody (UIUX_FORENSIC_AUDIT UI-004). A paywall that
    /// silently fails to appear is a purchase that silently fails to happen.
    func aePaywall() -> some View {
        modifier(PaywallPresentation())
    }
}

private struct PaywallPresentation: ViewModifier {
    @Environment(Entitlements.self) private var entitlements

    func body(content: Content) -> some View {
        @Bindable var entitlements = entitlements
        return content.sheet(item: $entitlements.presentedGate) { gate in
            NavigationStack {
                PaywallView(gate: gate)
            }
            .presentationDragIndicator(.visible)
            // Dismissal is recorded here rather than in the decline button:
            // a swipe-down is a decline too, and counting only the button
            // would let the nudge fire forever for anyone who swipes.
            .onDisappear { entitlements.paywallDismissed() }
        }
    }
}
