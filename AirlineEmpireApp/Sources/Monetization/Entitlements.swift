import Foundation
import Observation
import StoreKit
import AirlineEmpireCore

/// The app's one owner of purchases (docs/MONETIZATION.md §7).
///
/// StoreKit lives here and nowhere else, for the reason every other Apple
/// framework in this project is fenced off the same way: Core has to build
/// and test on Linux, and the *rules* about what a purchase is worth already
/// live there (`ProEntitlement`, `ContentAccess`). This object's whole job is
/// to turn Apple's transactions into that value type and to hold the
/// products the paywall renders.
///
/// It is deliberately not a singleton. `GameController` is the composition
/// root's other half; both are created once by the scene and injected, which
/// is what lets a UI test run the whole app with `-AEUITestPro` and
/// photograph the late game without a sandbox account.
@MainActor
@Observable
final class Entitlements {

    // MARK: - State the UI reads

    /// What the player currently owns. Starts free and stays free until
    /// StoreKit says otherwise, which is the right way round: a first launch
    /// with no network must open a playable free game, not a spinner.
    private(set) var entitlement: ProEntitlement = .free

    /// The loaded App Store products, by tier. Empty until `load()` returns —
    /// the paywall renders a skeleton rather than inventing prices.
    private(set) var products: [ProProduct: Product] = [:]

    /// Whether this account may still take an introductory offer. One per
    /// subscription group per Apple Account, ever, which is why it is a
    /// single flag rather than one per product.
    private(set) var isEligibleForIntroOffer = false

    /// Why the product load failed, if it did. Surfaced on the paywall so a
    /// player on a plane sees "prices unavailable offline" instead of an
    /// empty sheet with a dead button.
    private(set) var loadFailure: String?

    private(set) var isLoadingProducts = false

    /// A purchase or restore in flight. The buy button must not be tappable
    /// twice — a double purchase is a double charge and a refund request.
    private(set) var isPurchasing = false

    /// The gate the paywall is currently open for, or `nil` if it is closed.
    /// Held here rather than in a view so any screen can raise it and only
    /// `RootView` has to present it.
    var presentedGate: ProGate?

    /// The last purchase outcome worth telling the player about.
    var lastOutcome: Outcome?

    /// The presentation history, persisted across launches.
    private(set) var paywallHistory: PaywallPolicy.History

    /// The access rules in force. Everything in the game asks this, and
    /// nothing in the game asks which product paid for it.
    var access: ContentAccess { entitlement.access() }

    var isPro: Bool { entitlement.isPro() }

    enum Outcome: Equatable {
        case purchased(ProProduct)
        case restored
        case nothingToRestore
        case pending
        case failed(String)
    }

    // MARK: - Setup

    private let defaults: UserDefaults
    private var updatesTask: Task<Void, Never>?

    /// Forces an entitlement without a transaction, for UI tests only.
    ///
    /// The same shape as the launch arguments `RootView` already uses for
    /// dark appearance and the audio probe: a launch argument rather than a
    /// build flag, so the binary under test is the shipping binary, and no
    /// player will ever pass one.
    ///
    /// **A UI test run is Pro by default**, and that default is load-bearing
    /// rather than lazy. Every journey in `UITests/` founds an airline and
    /// then drives the game; the first-run paywall would open a sheet over
    /// the first tap of all of them, and five test files would start failing
    /// for a reason that has nothing to do with what they assert. So a test
    /// process is unlocked unless it says otherwise: `-AEUITestFree` opts
    /// into the free tier for the journeys that are *about* the gates, and
    /// `-AEUITestPro` states the default explicitly where a test wants to be
    /// read as deliberate.
    ///
    /// The cost is that the free tier is only exercised by tests that ask for
    /// it. That is a known gap, recorded in `docs/APPLE_VALIDATION.md` rather
    /// than papered over.
    private let testingOverride: ProEntitlement?

    init(defaults: UserDefaults = .standard,
         arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        let isUITest = arguments.contains { $0.hasPrefix("-AEUITest") }
        if arguments.contains("-AEUITestFree") {
            self.testingOverride = .free
        } else if isUITest || arguments.contains("-AEUITestPro") {
            self.testingOverride = .lifetime
        } else {
            self.testingOverride = nil
        }
        self.paywallHistory = Self.loadHistory(from: defaults)
        if let testingOverride { entitlement = testingOverride }
    }

    deinit { updatesTask?.cancel() }

    /// Whether StoreKit is the source of truth for this process.
    ///
    /// False only for a UI-test run pinned to Pro, which must not have its
    /// pretend entitlement overwritten by an empty `currentEntitlements`. A
    /// run pinned to *free* still talks to StoreKit — against the scheme's
    /// test configuration — so a UI test can drive a real purchase all the
    /// way from the paywall to an unlocked game.
    private var readsStoreKit: Bool { testingOverride?.isPro() != true }

    /// Starts the transaction listener and loads products.
    ///
    /// The listener is started *before* the first entitlement refresh, and
    /// that order matters: a transaction that completes while the app is
    /// launching — an Ask to Buy approval, a purchase made on another device,
    /// an interrupted purchase Apple is retrying — arrives on `updates` and
    /// would be lost in the gap otherwise. A lost transaction is a player who
    /// paid and did not get the game.
    func start() async {
        guard readsStoreKit else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                await self.apply(update)
            }
        }
        await refreshEntitlement()
        await loadProducts()
    }

    // MARK: - Products

    func loadProducts() async {
        guard readsStoreKit else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(
                for: ProProduct.allCases.map(\.rawValue))
            var byTier: [ProProduct: Product] = [:]
            for product in loaded {
                if let tier = ProProduct(rawValue: product.id) { byTier[tier] = product }
            }
            products = byTier
            loadFailure = byTier.isEmpty
                ? "Prices are unavailable right now." : nil
            await refreshIntroEligibility()
        } catch {
            // Offline is the common case for a game that advertises itself as
            // playable with no network at all, so this is a normal state and
            // not an error the player did anything about.
            loadFailure = "Prices are unavailable right now. "
                + "Check your connection and try again."
        }
    }

    private func refreshIntroEligibility() async {
        // Asked of the weekly plan because it carries the offer, but the
        // answer is a property of the subscription *group*: taking the intro
        // on any plan spends it for all of them.
        guard let subscription = products[.weekly]?.subscription else {
            isEligibleForIntroOffer = false
            return
        }
        isEligibleForIntroOffer = await subscription.isEligibleForIntroOffer
    }

    // MARK: - Buying

    func purchase(_ tier: ProProduct) async {
        guard !isPurchasing, let product = products[tier] else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await apply(verification)
                if isPro {
                    lastOutcome = .purchased(tier)
                    recordPaywall(wasPurchase: true)
                    presentedGate = nil
                }
            case .pending:
                // Ask to Buy, or a payment method needing action. The
                // transaction will arrive on `Transaction.updates` if and
                // when it is approved, which is why the listener is not
                // optional.
                lastOutcome = .pending
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            lastOutcome = .failed(error.localizedDescription)
        }
    }

    /// Restores previous purchases.
    ///
    /// Apple requires this button on any app selling non-consumables, and
    /// `Transaction.currentEntitlements` is usually enough on its own —
    /// `AppStore.sync()` prompts for a password, so it runs first only
    /// because a player who tapped Restore has told us the quiet path already
    /// failed them.
    func restore() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
        } catch {
            // A cancelled password prompt lands here; the refresh below is
            // still worth doing, so this is not surfaced as a failure.
        }
        await refreshEntitlement()
        lastOutcome = isPro ? .restored : .nothingToRestore
        if isPro { presentedGate = nil }
    }

    // MARK: - Entitlement

    private func apply(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            // An unverified transaction is not a purchase. Nothing is
            // granted, and nothing is finished — leaving it unfinished means
            // StoreKit offers it again rather than the player silently losing
            // whatever it was.
            return
        }
        await transaction.finish()
        await refreshEntitlement()
    }

    /// Rebuilds the entitlement from what Apple currently says is owned.
    ///
    /// `currentEntitlements` is the whole truth on purpose: it already
    /// excludes expired subscriptions, refunded purchases and revoked family
    /// sharing, so this method never has to decide those. What it adds is the
    /// two facts the *UI* needs and the transaction does not carry — whether
    /// a renewal is being retried, and whether it will renew at all.
    private func refreshEntitlement() async {
        guard readsStoreKit else { return }
        var owned: ProProduct?
        var expiry: Date?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  let tier = ProProduct(rawValue: transaction.productID) else { continue }
            // Lifetime outranks everything and can never lapse, so it wins
            // outright — a player who owns it and also has a stale
            // subscription must not inherit that subscription's expiry.
            if tier == .lifetime {
                owned = .lifetime
                expiry = nil
                break
            }
            owned = tier
            expiry = transaction.expirationDate
        }

        guard let owned else {
            entitlement = .free
            return
        }

        var retrying = false
        var willRenew = true
        if owned.isSubscription,
           let subscription = products[owned]?.subscription,
           let statuses = try? await subscription.status {
            for status in statuses {
                if status.state == .inBillingRetryPeriod || status.state == .inGracePeriod {
                    retrying = true
                }
                if case .verified(let renewal) = status.renewalInfo {
                    willRenew = renewal.willAutoRenew
                }
            }
        }

        entitlement = ProEntitlement(grantedBy: owned, expiresAt: expiry,
                                     isInBillingRetry: retrying,
                                     willRenew: willRenew)
    }

    // MARK: - Paywall presentation

    /// Raises the paywall for `gate`, if the policy allows it.
    ///
    /// Returns whether it was raised, so a caller that was about to perform a
    /// gated action knows whether it has been handled.
    @discardableResult
    func present(_ gate: ProGate) -> Bool {
        guard PaywallPolicy.allowsPresentation(gate: gate, access: access,
                                               history: paywallHistory) else {
            return false
        }
        presentedGate = gate
        return true
    }

    /// The once-only offer made after the first airline is founded.
    func offerOnFirstRunIfDue() {
        guard PaywallPolicy.shouldOfferOnFirstRun(access: access,
                                                  history: paywallHistory) else { return }
        presentedGate = .direct
    }

    /// The periodic, unprompted nudge — the only way the app raises the
    /// paywall on its own after the first run.
    ///
    /// Called when the app returns to the foreground rather than on a timer
    /// inside a session: a sheet that interrupts someone mid-decision is
    /// worse than one that greets them on the way in, and coming back to the
    /// game is the moment a player is between things anyway. Bounded twice
    /// over by the policy — never sooner than a billing period, and never at
    /// all after four refusals.
    func nudgeIfDue() {
        guard presentedGate == nil else { return }
        guard PaywallPolicy.shouldNudge(access: access,
                                        history: paywallHistory) else { return }
        presentedGate = .direct
    }

    /// Called whenever the sheet closes, however it closed.
    ///
    /// A purchase dismisses the sheet by clearing `presentedGate`, so this
    /// runs for a buyer too — and counting that as a refusal would be wrong
    /// twice over: it is the opposite of what happened, and if the player
    /// later lapses they would resume with a spent nudge budget they never
    /// used. `purchase()` has already recorded the conversion by then, so the
    /// only thing left to do here is nothing.
    func paywallDismissed() {
        guard !isPro else { return }
        recordPaywall(wasPurchase: false)
    }

    private func recordPaywall(wasPurchase: Bool) {
        paywallHistory = PaywallPolicy.record(paywallHistory,
                                              wasPurchase: wasPurchase)
        Self.save(paywallHistory, to: defaults)
    }

    // MARK: - Prices, as strings the paywall can render

    /// The renewal price, localised by StoreKit. Never assembled from a
    /// number in this repository: a hard-coded "$8.99" is wrong in every
    /// storefront that is not the United States, and Apple rejects paywalls
    /// whose displayed price disagrees with the product.
    func displayPrice(_ tier: ProProduct) -> String? {
        products[tier]?.displayPrice
    }

    /// The billing unit, singular ("week", "year"), for the price line.
    func periodName(_ tier: ProProduct) -> String {
        guard let period = products[tier]?.subscription?.subscriptionPeriod else {
            return ""
        }
        switch period.unit {
        case .day: return period.value == 7 ? "week" : "day"
        case .week: return "week"
        case .month: return period.value == 12 ? "year" : "month"
        case .year: return "year"
        @unknown default: return ""
        }
    }

    /// The introductory price, if this account may still take one.
    func introductoryPrice(_ tier: ProProduct) -> String? {
        guard isEligibleForIntroOffer,
              let offer = products[tier]?.subscription?.introductoryOffer else {
            return nil
        }
        return offer.displayPrice
    }

    /// The sentence stating what will be charged, and when. Core owns the
    /// wording; this only supplies the localised numbers.
    func commitmentLine(_ tier: ProProduct) -> String? {
        guard let price = displayPrice(tier) else { return nil }
        guard tier.isSubscription else {
            return PaywallContent.lifetimeCommitment(price: price)
        }
        return PaywallContent.commitment(introductory: introductoryPrice(tier),
                                         standard: price,
                                         period: periodName(tier))
    }

    /// The buy button's title.
    func callToAction(_ tier: ProProduct) -> String {
        guard let price = displayPrice(tier) else { return "Unlock Pro" }
        return PaywallContent.callToAction(
            introductory: tier.isSubscription ? introductoryPrice(tier) : nil,
            standard: price, isSubscription: tier.isSubscription)
    }

    /// The badge on a plan card, or `nil` for no badge.
    ///
    /// Only two of the three ever carry one, and they carry *different* ones.
    /// Both the yearly and the lifetime beat a year of weekly billing by
    /// around ninety percent, so giving both a gold "SAVE n%" pill would put
    /// two near-identical claims side by side — which reads as decoration and
    /// sells neither. The yearly gets the number, because a subscription is
    /// the thing a percentage is a fair comparison for; the lifetime gets the
    /// verdict.
    func badge(_ tier: ProProduct) -> String? {
        switch tier {
        case .weekly: return nil
        case .lifetime: return products[.lifetime] == nil ? nil : "BEST VALUE"
        case .yearly:
            guard let percent = savingsVersusWeekly(.yearly) else { return nil }
            return "SAVE \(percent)%"
        }
    }

    /// What a tier saves against paying weekly for the same year, as a whole
    /// percent.
    ///
    /// Computed from the loaded products rather than written down, so it
    /// cannot drift from the prices and cannot be wrong in a storefront where
    /// the two tiers are priced differently relative to each other. Returns
    /// `nil` when it would be nothing to boast about, because a "SAVE 2%"
    /// badge is worse than no badge.
    func savingsVersusWeekly(_ tier: ProProduct) -> Int? {
        guard tier != .weekly,
              let weekly = products[.weekly]?.price,
              let price = products[tier]?.price, weekly > 0 else { return nil }
        // A year of weekly billing is 52 renewals. Lifetime is compared
        // against the same year: claiming it against an infinite horizon
        // would be an unfalsifiable number, which is not a claim worth
        // putting on a card.
        let yearOfWeekly = weekly * 52
        guard yearOfWeekly > price else { return nil }
        // Through `Double` for the rounding only: `Decimal` has no
        // `rounded()`, and the result is a badge, not a ledger entry.
        let fraction = (yearOfWeekly - price) / yearOfWeekly
        let percent = Int((NSDecimalNumber(decimal: fraction).doubleValue * 100)
            .rounded())
        return percent >= 20 ? percent : nil
    }

    /// The small print under a plan's price. Honest anchoring: the
    /// comparison is stated in full, never implied by a bigger number.
    func footnote(_ tier: ProProduct) -> String? {
        switch tier {
        case .weekly:
            return nil
        case .yearly:
            guard let product = products[.yearly] else { return nil }
            return product.priceFormatStyle.format(product.price / 52)
                + " per week, billed yearly"
        case .lifetime:
            // The comparison that actually sells this tier, said as a
            // duration rather than as a second percentage: how long the
            // weekly plan takes to cost the same. Rounded down, so the claim
            // is conservative rather than flattering.
            guard let weekly = products[.weekly]?.price,
                  let lifetime = products[.lifetime]?.price, weekly > 0 else {
                return nil
            }
            let weeks = Int((NSDecimalNumber(decimal: lifetime / weekly)
                .doubleValue).rounded(.down))
            guard weeks >= 2 else { return nil }
            return "About \(weeks) weeks of Pro Weekly — then never again"
        }
    }

    // MARK: - History persistence

    private enum Key {
        static let history = "ae.paywallHistory"
    }

    private static func loadHistory(from defaults: UserDefaults) -> PaywallPolicy.History {
        guard let data = defaults.data(forKey: Key.history),
              let decoded = try? JSONDecoder().decode(PaywallPolicy.History.self,
                                                      from: data) else {
            return PaywallPolicy.History()
        }
        return decoded
    }

    private static func save(_ history: PaywallPolicy.History,
                             to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: Key.history)
    }
}
