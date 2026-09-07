import Foundation

/// What the player has bought, and what it is worth to them right now
/// (docs/MONETIZATION.md §2).
///
/// This type lives in Core, not the app, for the same reason `AudioSettings`
/// does: the *rules* — which product grants what, when a lapsed subscription
/// stops granting it, what a player keeps after cancelling — are the part
/// that can be wrong in a way a player notices and a refund follows, and
/// Linux is where this project can actually test things. StoreKit stays in
/// the app layer and hands this type across the seam
/// (docs/ARCHITECTURE.md — Core is platform-agnostic).
///
/// There is exactly one entitlement in the product: Pro. Three products grant
/// it (`ProProduct`), and nothing in the game asks *which* one — a weekly
/// subscriber and a lifetime owner see an identical game. That is a design
/// commitment, not an implementation detail: the moment a tier buys more
/// aircraft than another tier, the game has a pay-to-win axis and
/// `docs/GAME_DESIGN.md` §2's "no paying to skip" pillar is gone.
public struct ProEntitlement: Equatable, Sendable, Codable {
    /// The product currently granting Pro, or `nil` for a free player.
    public let grantedBy: ProProduct?

    /// When the grant lapses. `nil` means it does not — either the player is
    /// free (nothing to lapse) or they own Lifetime.
    public let expiresAt: Date?

    /// Apple is still trying to collect a renewal (billing retry / grace
    /// period). Access is deliberately *kept* here: the player has not
    /// cancelled, their card has failed, and locking them out of a campaign
    /// mid-run over a bank decline is how a recoverable payment becomes a
    /// one-star review.
    public let isInBillingRetry: Bool

    /// The subscription is set not to renew. Access continues to `expiresAt`;
    /// this is only so the UI can say so plainly rather than letting the
    /// player discover it when the game re-locks.
    public let willRenew: Bool

    public init(grantedBy: ProProduct?, expiresAt: Date? = nil,
                isInBillingRetry: Bool = false, willRenew: Bool = true) {
        self.grantedBy = grantedBy
        self.expiresAt = expiresAt
        self.isInBillingRetry = isInBillingRetry
        self.willRenew = willRenew
    }

    /// No purchase. The starting state, and the state a save is played in
    /// until StoreKit says otherwise.
    public static let free = ProEntitlement(grantedBy: nil)

    /// A permanent grant. Also what a StoreKit test configuration produces,
    /// and what the UI-test fixture uses.
    public static let lifetime = ProEntitlement(grantedBy: .lifetime)

    /// Whether the game should be unlocked, as of `now`.
    ///
    /// Takes the clock as a parameter rather than reading `Date()` so this is
    /// a pure function — expiry is exactly the behaviour worth testing, and a
    /// test cannot wait a week.
    public func isPro(asOf now: Date = Date()) -> Bool {
        guard grantedBy != nil else { return false }
        guard let expiresAt else { return true }
        // Billing retry outlives the expiry date by design; see the property.
        return now < expiresAt || isInBillingRetry
    }

    /// The access rules this entitlement resolves to.
    public func access(asOf now: Date = Date()) -> ContentAccess {
        isPro(asOf: now) ? .pro : .free
    }
}

/// The three things that can be bought (docs/MONETIZATION.md §3).
///
/// Raw values are the App Store Connect product identifiers, which is why
/// they are spelled out rather than derived from the bundle id: a product id
/// is immutable once created in App Store Connect, and a string built at
/// runtime from something refactorable is a product that silently stops
/// loading after a rename.
public enum ProProduct: String, CaseIterable, Sendable, Codable {
    /// The impulse tier, and the default selection on the paywall.
    ///
    /// Weekly is 82% of every subscription plan sold in games (RevenueCat,
    /// *State of Subscription Apps 2026*), against 13% annual — this is the
    /// shape the market converts on, and the reason it leads.
    case weekly = "com.airlineempire.game.pro.weekly"
    /// The anchor. Its job on the paywall is to make the weekly price
    /// legible as a yearly number, which is also what keeps the disclosure
    /// honest.
    case yearly = "com.airlineempire.game.pro.yearly"
    /// The escape hatch, and the reason it exists: games' median revenue per
    /// payer over a full year is $11.22 (RevenueCat, ibid.) — weekly churn
    /// is brutal, and a player who would have cancelled in three weeks is
    /// worth more, and complains less, as a one-time buyer.
    case lifetime = "com.airlineempire.game.pro.lifetime"

    /// The App Store Connect subscription group. One group, so the three
    /// plans upgrade and downgrade between each other instead of stacking —
    /// and so a player can only ever take one introductory offer, which is
    /// Apple's rule and worth designing around rather than discovering.
    public static let subscriptionGroup = "Airline Empire Pro"

    /// Non-consumables do not renew and are not part of the group.
    public var isSubscription: Bool { self != .lifetime }

    /// Top-to-bottom order on the paywall. Weekly first because it is the
    /// default and the default must be the one under the thumb.
    public var displayOrder: Int {
        switch self {
        case .weekly: 0
        case .yearly: 1
        case .lifetime: 2
        }
    }

    /// The plan the paywall pre-selects.
    public static let `default`: ProProduct = .weekly

    /// Player-facing name. Lives here rather than in the view so the paywall,
    /// the settings screen and the docs generator cannot disagree.
    public var displayName: String {
        switch self {
        case .weekly: "Pro Weekly"
        case .yearly: "Pro Yearly"
        case .lifetime: "Pro Lifetime"
        }
    }

    /// The line under the name. Deliberately states the renewal behaviour of
    /// every tier including the one that has none — "never renews" is the
    /// whole pitch of Lifetime, and Apple requires the other two to say so.
    public var renewalDescription: String {
        switch self {
        case .weekly: "1 week · renews weekly"
        case .yearly: "12 months · renews yearly"
        case .lifetime: "One-time · never renews"
        }
    }
}
