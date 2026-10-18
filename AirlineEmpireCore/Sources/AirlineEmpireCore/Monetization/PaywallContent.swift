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
        // Only the achievements that live past the free ceiling. Value
        // Legend and Weather Proof have no era condition in
        // `ProgressionSystem.checkAchievements` — a free airline earns them —
        // so naming them here sold something the free game already gives.
        Benefit(id: "achievements", symbol: "rosette",
                title: "Late-game achievements",
                detail: "Debt Free and Single-Family Purist are earned in the "
                    + "National and International eras."),
        Benefit(id: "noads", symbol: "hand.raised.slash",
                title: "No ads, ever",
                detail: "No timers, no premium currency, nothing to wait "
                    + "out. As it is in the free game."),
    ]

    /// The benefits, led by the one the player just reached for.
    ///
    /// A player who tapped a locked airport should read "The whole world"
    /// first, not third — the same list, in an order that answers the tap.
    /// Gates without a single matching benefit keep the default order.
    public static func benefits(leadingWith gate: ProGate) -> [Benefit] {
        let lead: String?
        switch gate {
        case .airport: lead = "world"
        case .scenario: lead = "scenarios"
        case .saveSlot: lead = "saves"
        case .eraCeiling: lead = "eras"
        case .direct, .firstFlight: lead = nil
        }
        guard let lead, let first = benefits.first(where: { $0.id == lead }) else {
            return benefits
        }
        return [first] + benefits.filter { $0.id != lead }
    }

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

    /// An introductory offer, described by its shape rather than assumed.
    ///
    /// StoreKit's `Product.SubscriptionOffer`, reduced to the facts the copy
    /// needs so Core can phrase it without importing StoreKit. The sentence
    /// used to take only the offer's price and borrow the *renewal* period
    /// for its length — "$0.99 for your first week" — which was true of the
    /// one offer this game launched with and of nothing else. Change the
    /// offer in App Store Connect to three months at $0.99 a month, or a
    /// free week, and the paywall would have stated a price Apple was not
    /// going to charge: guideline 3.1.2, from a dashboard edit with no build.
    public struct IntroductoryOffer: Equatable, Sendable {
        public enum PaymentMode: Equatable, Sendable {
            /// Nothing is charged until the offer ends.
            case freeTrial
            /// `price` is charged at the start of each period, for
            /// `periodCount` periods.
            case payAsYouGo
            /// `price` is charged once, at purchase, for the whole offer.
            case payUpFront
        }

        public enum Unit: Equatable, Sendable {
            case day, week, month, year
        }

        /// The localised offer price, from StoreKit (`$0.99`). Not read for
        /// a free trial, whose price StoreKit renders as a zero amount.
        public let price: String
        public let paymentMode: PaymentMode
        /// One offer period is `periodValue` × `periodUnit`.
        public let periodValue: Int
        public let periodUnit: Unit
        /// How many periods the offer lasts.
        public let periodCount: Int

        public init(price: String, paymentMode: PaymentMode,
                    periodValue: Int, periodUnit: Unit, periodCount: Int) {
            self.price = price
            self.paymentMode = paymentMode
            self.periodValue = periodValue
            self.periodUnit = periodUnit
            self.periodCount = periodCount
        }
    }

    /// What the introductory offer costs and for how long, as a clause:
    /// "$0.99 for your first week", "$0.99 per month for your first 3
    /// months", "$2.99 for your first 3 months", "Free for your first week".
    ///
    /// Every word comes from the offer. The whole length is the period times
    /// the count, whatever the mode — StoreKit reports a free trial and a
    /// pay-up-front offer as one long period, and pay-as-you-go as several
    /// short ones, and the product of the two is right for all three.
    public static func introductoryTerms(_ offer: IntroductoryOffer) -> String {
        let count = max(1, offer.periodCount)
        let whole = span(offer.periodValue * count, offer.periodUnit)
        switch offer.paymentMode {
        case .freeTrial:
            return "Free for your first \(whole.text)"
        case .payUpFront:
            return "\(offer.price) for your first \(whole.text)"
        case .payAsYouGo:
            guard count > 1 else { return "\(offer.price) for your first \(whole.text)" }
            let each = span(offer.periodValue, offer.periodUnit)
            let rate = each.count == 1 ? "per \(each.text)" : "every \(each.text)"
            return "\(offer.price) \(rate) for your first \(whole.text)"
        }
    }

    /// A length of time as the copy says it: "week", "3 months".
    ///
    /// Seven days are a week and twelve months a year, because StoreKit has
    /// reported a one-week period as seven days and the copy should not
    /// change with it.
    static func span(_ value: Int, _ unit: IntroductoryOffer.Unit)
        -> (count: Int, text: String) {
        var value = max(1, value)
        var unit = unit
        if unit == .day, value % 7 == 0 { value /= 7; unit = .week }
        if unit == .month, value % 12 == 0 { value /= 12; unit = .year }
        let name: String
        switch unit {
        case .day: name = "day"
        case .week: name = "week"
        case .month: name = "month"
        case .year: name = "year"
        }
        return (value, value == 1 ? name : "\(value) \(name)s")
    }

    /// The sentence directly above the buy button, stating what will actually
    /// be charged and when.
    ///
    /// `introductory` is the offer this account may still take, if any
    /// (`IntroductoryOffer`), `standard` the localised renewal price
    /// (`$8.99`), and `period` its unit (`week`). Every price comes from
    /// StoreKit rather than from this file: a price typed into a game is a
    /// price that is wrong in 174 storefronts, and Apple rejects hard-coded
    /// prices that disagree with the product.
    ///
    /// Note the order. The introductory price is named once; the price the
    /// player will keep paying is named with equal weight and in the same
    /// sentence. That ordering is the fix for the specific rejection this
    /// screen's design invites — a reference paywall that renders "Start 7
    /// days free" at three times the size of the price is describing a
    /// rejection, not a design.
    public static func commitment(introductory: IntroductoryOffer?, standard: String,
                                  period: String) -> String {
        guard let introductory else {
            return "\(standard) per \(period). Renews automatically until you cancel."
        }
        return "\(introductoryTerms(introductory)), then \(standard) "
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
    ///
    /// With an offer, today's charge is the offer price in either paid mode
    /// — the first instalment, or the whole up-front amount — and nothing
    /// for a free trial, which says so instead of "Start for $0.00". The
    /// commitment line above the button carries the renewal price in every
    /// case.
    public static func callToAction(introductory: IntroductoryOffer?,
                                    standard: String,
                                    isSubscription: Bool) -> String {
        if !isSubscription { return "Unlock Pro — \(standard)" }
        guard let introductory else { return "Subscribe — \(standard)" }
        if introductory.paymentMode == .freeTrial { return "Start free trial" }
        return "Start for \(introductory.price)"
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
        URL(string: "https://wrexist.github.io/Airline-Empire/terms.html")!
    public static let privacyURL =
        URL(string: "https://wrexist.github.io/Airline-Empire/privacy.html")!
}
