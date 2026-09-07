import Foundation

/// When the paywall is allowed to appear (docs/MONETIZATION.md §6).
///
/// A pure decision over recorded state, for the same reason the gates are:
/// "how often does this game ask me for money" is the question that decides
/// whether the store rating starts with a 4 or a 2, and it should be
/// answerable by reading one function rather than by playing for a week.
///
/// The shape of the policy: **ask once early, answer every time the player
/// asks, and nag on a long fuse.** Games start 81.5% of their trials on the
/// day of install (RevenueCat, *State of Subscription Apps 2026*), so an
/// offer that never appears on day zero is an offer that mostly never
/// converts — but the same report's 1.0% median install-to-paid rate means
/// 99 of every 100 players are people this screen must not follow around.
public struct PaywallPolicy: Equatable, Sendable {

    /// What the app has recorded about previous presentations. Persisted in
    /// `UserDefaults` by the app layer; passed in here so the rule is pure.
    public struct History: Equatable, Sendable, Codable {
        /// Whether the once-only first-run offer has been made.
        public var hasShownFirstRun: Bool
        /// When the paywall was last presented for any reason.
        public var lastPresented: Date?
        /// How many times it has been presented without a purchase. The
        /// nudge stops entirely after `maxUnpromptedPresentations`; a player
        /// who has declined four times has answered.
        public var declineCount: Int

        public init(hasShownFirstRun: Bool = false, lastPresented: Date? = nil,
                    declineCount: Int = 0) {
            self.hasShownFirstRun = hasShownFirstRun
            self.lastPresented = lastPresented
            self.declineCount = declineCount
        }
    }

    /// The soonest an *unprompted* paywall may follow another one.
    ///
    /// Seven days, matched to the weekly billing period rather than chosen
    /// for feel: a player who declines is being asked again no sooner than
    /// the plan they declined would have renewed.
    public static let nudgeInterval: TimeInterval = 7 * 24 * 60 * 60

    /// After this many unpurchased presentations the app stops offering by
    /// itself. Pro remains one tap away in Settings, forever.
    public static let maxUnpromptedPresentations = 4

    /// Whether a paywall raised by `gate` may be presented now.
    ///
    /// - Parameters:
    ///   - gate: what raised it.
    ///   - access: the player's current access.
    ///   - history: what has been shown before.
    ///   - now: the clock, injected so the interval is testable.
    public static func allowsPresentation(gate: ProGate,
                                          access: ContentAccess,
                                          history: History,
                                          now: Date = Date()) -> Bool {
        // Pro players are never shown a paywall. Not throttled — never.
        // Showing a paying customer an upsell for the thing they bought is
        // the defect that makes people cancel.
        guard !access.isPro else { return false }

        switch gate {
        case .direct:
            // The player opened it themselves, from Settings or a lock badge.
            // Always honoured: this is a request, not an interruption.
            return true

        case .eraCeiling, .scenario, .saveSlot, .airport:
            // The player reached for something that is not theirs. Answering
            // that with silence would leave a control that does nothing,
            // which this codebase has shipped before and written bugs about
            // (BUG-029, BUG-030, BUG-032). Always honoured, and deliberately
            // exempt from the nudge throttle — the throttle exists to stop
            // the *app* from asking, not to stop the game from explaining
            // itself when the player asks.
            return true
        }
    }

    /// Whether the once-only first-run offer should be made.
    ///
    /// Called after the first airline is founded, not before. The player has
    /// by then named an airline, chosen a livery and picked a home airport —
    /// three decisions and about a minute — so the offer lands on something
    /// they have already begun rather than on a stranger's splash screen.
    /// Founding first also means the decline path leads straight into a real
    /// game instead of into an empty menu.
    public static func shouldOfferOnFirstRun(access: ContentAccess,
                                             history: History) -> Bool {
        !access.isPro && !history.hasShownFirstRun
    }

    /// Whether a periodic, unprompted nudge is due.
    ///
    /// The only path by which the app raises the paywall on its own after the
    /// first run. Bounded twice over — by interval and by count — so it can
    /// never become the pattern the free game promises it is not.
    public static func shouldNudge(access: ContentAccess, history: History,
                                   now: Date = Date()) -> Bool {
        guard !access.isPro, history.hasShownFirstRun else { return false }
        guard history.declineCount < maxUnpromptedPresentations else { return false }
        guard let last = history.lastPresented else { return true }
        return now.timeIntervalSince(last) >= nudgeInterval
    }

    /// Folds a presentation into the history.
    ///
    /// `wasPurchase` distinguishes a decline from a conversion so the count
    /// only ever measures refusals; a player who bought is out of this system
    /// altogether by way of `access.isPro`.
    public static func record(_ history: History, at now: Date = Date(),
                              wasPurchase: Bool) -> History {
        var next = history
        next.hasShownFirstRun = true
        next.lastPresented = now
        if !wasPurchase { next.declineCount += 1 }
        return next
    }
}
