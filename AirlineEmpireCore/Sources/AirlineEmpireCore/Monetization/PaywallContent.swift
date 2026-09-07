import Foundation

/// Everything the paywall says, as data (docs/MONETIZATION.md §5).
///
/// The copy lives in Core rather than in the SwiftUI view for two reasons.
/// The dull one is that `PaywallView` is a layout and this is a script, and
/// mixing them is how a price ends up written in three places. The sharp one
/// is that a paywall's copy is a *compliance surface*: Apple rejects
/// submissions whose subscription screen "promotes the free trial or
/// introductory period more clearly and conspicuously than the billed
/// amount", and it rejects screens missing the title, the length, the price
/// or the two links. Those are properties of strings, and strings in a value
/// type can be asserted by a test that runs on Linux in a second. A paywall
/// nobody can test is a paywall discovered by App Review.
public enum PaywallContent {

    // MARK: - The counter bar

    /// The four numbers across the top of the paywall.
    ///
    /// Derived from the catalogue, never typed. The listing has already been
    /// wrong about its own content once (`docs/ASO.md` §3 keeps the mapping
    /// from claim to code for exactly this reason), and a paywall that
    /// promises 94 airports to a build carrying 80 is a refund with a
    /// screenshot attached.
    public struct Stat: Equatable, Sendable {
        public let value: String
        public let label: String
    }

    public static func stats(catalog: ContentCatalog) -> [Stat] {
        [
            Stat(value: "\(Era.allCases.count)", label: "ERAS"),
            Stat(value: "\(catalog.orderedAirportCodes.count)", label: "AIRPORTS"),
            Stat(value: "\(catalog.orderedAircraftTypeCodes.count)", label: "AIRCRAFT"),
            Stat(value: "\(WorldRegion.allCases.count)", label: "REGIONS"),
        ]
    }

    // MARK: - The benefit grid

    public struct Benefit: Equatable, Sendable, Identifiable {
        public let id: String
        /// SF Symbol name.
        public let symbol: String
        public let title: String
        public let detail: String
    }

    /// What Pro unlocks, in the order it is worth.
    ///
    /// Every line is a system that exists in this repository — the era arc,
    /// the airport catalogue, `AircraftCategory.widebody`, `CapabilityCode`,
    /// `scenarios.json`, the save slots, `ProgressionState.achievements`.
    /// Nothing here is a roadmap item written in the present tense, which is
    /// the single fastest way to earn a one-star review that is also correct.
    public static let benefits: [Benefit] = [
        Benefit(id: "eras", symbol: "chart.line.uptrend.xyaxis",
                title: "Three more eras",
                detail: "National, International and Empire — the arc from a "
                    + "regional carrier to a global one."),
        Benefit(id: "world", symbol: "globe.europe.africa",
                title: "The whole world",
                detail: "All 94 airports across nine regions, instead of the "
                    + "twenty nearest your home."),
        Benefit(id: "widebody", symbol: "airplane",
                title: "Widebodies and long-haul",
                detail: "The largest aircraft in the catalogue, and the "
                    + "oceans they are for."),
        Benefit(id: "capability", symbol: "gearshape.2",
                title: "Capability programs",
                detail: "Fuel hedging, a network ops centre, faster "
                    + "turnarounds, a better ground product."),
        Benefit(id: "scenarios", symbol: "flag.2.crossed",
                title: "Every scenario",
                detail: "Entrepreneur and Magnate — different money, "
                    + "different market, less margin for error."),
        Benefit(id: "saves", symbol: "square.stack.3d.up",
                title: "Unlimited airlines",
                detail: "Keep this one and start another. A different home, "
                    + "a different seed, a different world."),
        Benefit(id: "achievements", symbol: "rosette",
                title: "Every achievement",
                detail: "Value Legend, Weather Proof and the rest of the "
                    + "long-run challenges."),
        Benefit(id: "noads", symbol: "hand.raised.slash",
                title: "No ads, ever",
                detail: "No timers, no premium currency, nothing to wait "
                    + "out. As it is in the free game."),
    ]

    // MARK: - The free game, stated plainly

    /// The line above the plans.
    ///
    /// It says what is free before it says what costs money, because that is
    /// both true and the better pitch: a player who believes the free game is
    /// real starts one, and games' download-to-trial rate is decided there.
    public static let freeGamePitch =
        "Airline Empire is free to fly — the whole simulation, the full "
        + "ledger, rivals that fight back. No ads, no timers, no energy. "
        + "Pro opens the rest of the world."

    // MARK: - Required disclosure

    /// The renewal terms block, verbatim from Apple's own guidance
    /// (App Store Review Guideline 3.1.2 and the "Offering Auto-Renewable
    /// Subscriptions" checklist).
    ///
    /// It is a constant rather than a builder because every clause in it is
    /// load-bearing: charge point, auto-renew, the 24-hour cancellation
    /// window, the 24-hour charge window, where to manage it, and what
    /// happens to an unused trial. Editing this for tone is how a submission
    /// gets rejected.
    public static let subscriptionTerms =
        "Payment is charged to your Apple Account at confirmation of "
        + "purchase. Subscriptions renew automatically unless cancelled at "
        + "least 24 hours before the end of the current period; your account "
        + "is charged for renewal within 24 hours of the period ending. "
        + "Manage or cancel in Settings → Apple Account → Subscriptions. Pro "
        + "Lifetime is a one-time purchase and does not renew."

    /// The sentence directly above the buy button, stating what will actually
    /// be charged and when.
    ///
    /// The `introductory` argument is the localised price of the intro offer
    /// (`$0.99`), `standard` the localised renewal price (`$8.99`), and
    /// `period` its unit (`week`). All three come from StoreKit rather than
    /// from this file: a price typed into a game is a price that is wrong in
    /// 174 storefronts, and Apple rejects hard-coded prices that disagree
    /// with the product.
    ///
    /// Note the order. The introductory price is named once; the price the
    /// player will keep paying is named with equal weight and in the same
    /// sentence. That ordering is the fix for the specific rejection this
    /// screen's design invites — a reference paywall that renders "Start 7
    /// days free" at three times the size of the price is describing a
    /// rejection, not a design.
    public static func commitment(introductory: String?, standard: String,
                                  period: String) -> String {
        guard let introductory else {
            return "\(standard) per \(period). Renews automatically until you cancel."
        }
        return "\(introductory) for your first \(period), then \(standard) "
            + "per \(period). Renews automatically until you cancel."
    }

    /// The same sentence for a product that does not renew.
    public static func lifetimeCommitment(price: String) -> String {
        "\(price), once. No subscription, no renewal, yours permanently."
    }

    /// The call to action.
    ///
    /// It names the amount being charged today. "Start 7 days free" and
    /// "Continue" both outperform this in a vacuum and both bury the number,
    /// which is the thing App Review reads the screen for — and the thing a
    /// player reads their bank statement for a week later. The refund and the
    /// rejection are the same defect.
    public static func callToAction(introductory: String?,
                                    standard: String,
                                    isSubscription: Bool) -> String {
        if !isSubscription { return "Unlock Pro — \(standard)" }
        if let introductory { return "Start for \(introductory)" }
        return "Subscribe — \(standard)"
    }

    /// The reassurance row under the button. Three claims, all of which the
    /// product actually honours.
    public static let assurances = ["Cancel any time", "No ads, ever",
                                    "No pay-to-win"]

    /// The dismissal. Phrased as the thing it is — the free game is not a
    /// punishment and should not read like one.
    public static let decline = "Not now — keep flying for free"

    // MARK: - Links

    /// Apple requires functional links to both, in the app, on the screen
    /// that sells the subscription. Missing either is guideline 3.1.2.
    public static let termsURL =
        URL(string: "https://wrexist.github.io/airline-empire/terms")!
    public static let privacyURL =
        URL(string: "https://wrexist.github.io/airline-empire/privacy")!
}
