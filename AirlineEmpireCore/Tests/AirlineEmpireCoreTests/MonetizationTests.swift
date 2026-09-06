import Foundation
import Testing
@testable import AirlineEmpireCore

/// The gates, the entitlement clock and the paywall's compliance strings.
///
/// This suite exists because monetization is the one system in this project
/// whose defects cost money in both directions — a gate that leaks gives the
/// game away, a gate that over-locks takes it from someone who paid — and
/// because App Review reads the paywall's strings. All of it is pure, so all
/// of it runs on Linux (docs/APPLE_VALIDATION.md: what is proven here versus
/// assumed on the device).
@Suite("Monetization")
struct MonetizationTests {

    // MARK: - Entitlement

    @Test func freeEntitlementIsNotPro() {
        #expect(ProEntitlement.free.isPro() == false)
        #expect(ProEntitlement.free.access() == .free)
    }

    @Test func lifetimeNeverExpires() {
        let far = Date(timeIntervalSince1970: 4_000_000_000)
        #expect(ProEntitlement.lifetime.isPro(asOf: far))
    }

    @Test func subscriptionLapsesAtExpiry() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entitlement = ProEntitlement(grantedBy: .weekly,
                                         expiresAt: now.addingTimeInterval(60))
        #expect(entitlement.isPro(asOf: now))
        #expect(entitlement.isPro(asOf: now.addingTimeInterval(120)) == false)
    }

    /// A failed card is not a cancellation. Apple keeps retrying for days,
    /// and a player locked out of a campaign in the middle of that has been
    /// punished for their bank's decision.
    @Test func billingRetryKeepsAccess() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let retrying = ProEntitlement(grantedBy: .weekly,
                                      expiresAt: now.addingTimeInterval(-1),
                                      isInBillingRetry: true)
        #expect(retrying.isPro(asOf: now))
    }

    /// Cancelled-but-not-yet-expired still plays. The player paid for the
    /// period; turning it off early would be theft with extra steps.
    @Test func cancelledSubscriptionRunsToTheEndOfItsPeriod() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cancelled = ProEntitlement(grantedBy: .yearly,
                                       expiresAt: now.addingTimeInterval(3600),
                                       willRenew: false)
        #expect(cancelled.isPro(asOf: now))
        #expect(cancelled.isPro(asOf: now.addingTimeInterval(7200)) == false)
    }

    // MARK: - Products

    /// Product identifiers are immutable in App Store Connect once created.
    /// This test is a tripwire: changing one of these strings after a release
    /// silently orphans every existing purchase.
    @Test func productIdentifiersAreStable() {
        #expect(ProProduct.weekly.rawValue == "com.airlineempire.game.pro.weekly")
        #expect(ProProduct.yearly.rawValue == "com.airlineempire.game.pro.yearly")
        #expect(ProProduct.lifetime.rawValue == "com.airlineempire.game.pro.lifetime")
    }

    @Test func lifetimeIsNotASubscription() {
        #expect(ProProduct.lifetime.isSubscription == false)
        #expect(ProProduct.weekly.isSubscription)
        #expect(ProProduct.yearly.isSubscription)
    }

    @Test func weeklyLeadsAndIsTheDefault() {
        let order = ProProduct.allCases.sorted { $0.displayOrder < $1.displayOrder }
        #expect(order.first == .weekly)
        #expect(ProProduct.default == .weekly)
    }

    // MARK: - Gates

    @Test func freeCeilingIsTheRegionalEra() {
        #expect(ContentAccess.free.eraCeiling == .regional)
        #expect(ContentAccess.free.allowsEra(.startup))
        #expect(ContentAccess.free.allowsEra(.regional))
        #expect(ContentAccess.free.allowsEra(.national) == false)
        #expect(ContentAccess.free.nextLockedEra == .national)
    }

    @Test func proHasNoCeiling() {
        for era in Era.allCases { #expect(ContentAccess.pro.allowsEra(era)) }
        #expect(ContentAccess.pro.nextLockedEra == nil)
    }

    @Test func onlyFounderIsFree() {
        #expect(ContentAccess.free.allowsScenario("founder"))
        #expect(ContentAccess.free.allowsScenario("entrepreneur") == false)
        #expect(ContentAccess.free.allowsScenario("magnate") == false)
        #expect(ContentAccess.pro.allowsScenario("magnate"))
    }

    /// The free scenario must be one the catalogue actually ships, or the
    /// free tier has no playable start at all.
    @Test func freeScenarioExistsInTheCatalogue() throws {
        let catalog = try ContentCatalog.loadBundled()
        #expect(catalog.scenarios[ContentAccess.freeScenario] != nil)
    }

    @Test func freeTierKeepsOneSave() {
        #expect(ContentAccess.free.allowsNewSave(existingSaves: 0))
        #expect(ContentAccess.free.allowsNewSave(existingSaves: 1) == false)
        #expect(ContentAccess.pro.allowsNewSave(existingSaves: 12))
    }

    /// The paywall locks no aircraft of its own — the era does, for paying
    /// and free players alike. A free player at the Regional ceiling reaches
    /// large narrowbodies and no further; a Pro player reaches those too
    /// until their airline earns the next era.
    @Test func aircraftAreGatedByEraNotByPurchase() {
        #expect(ContentAccess.free.allowsAircraftCategory(.largeNarrowbody,
                                                          in: .regional))
        #expect(ContentAccess.free.allowsAircraftCategory(.widebody,
                                                          in: .regional) == false)
        // Pro is not a bypass: the same era denies the same aircraft.
        #expect(ContentAccess.pro.allowsAircraftCategory(.widebody,
                                                         in: .regional) == false)
        #expect(ContentAccess.pro.allowsAircraftCategory(.widebody,
                                                         in: .national))
        #expect(ContentAccess.free.reachableCategories.contains(.widebody) == false)
        #expect(ContentAccess.pro.reachableCategories.contains(.largeWidebody))
    }

    // MARK: - The airport radius

    /// The point of nearest-N over home-region: the free game is the same
    /// size wherever it starts. Europe ships 36 airports and the Middle East
    /// ships 4, so a region rule would have made a first-minute choice worth
    /// nine times as much game to one player as to another.
    @Test func theFreeMapIsTheSameSizeFromEveryHome() throws {
        let catalog = try ContentCatalog.loadBundled()
        let expected = ContentAccess.freeAirportRadius + 1  // the home too
        for home in catalog.orderedAirportCodes {
            let servable = ContentAccess.free.servableAirports(home: home,
                                                              catalog: catalog)
            #expect(servable.count == expected,
                    "\(home.raw) sees \(servable.count) airports")
            #expect(servable.contains(home))
        }
    }

    @Test func proServesTheWholeMap() throws {
        let catalog = try ContentCatalog.loadBundled()
        let all = catalog.orderedAirportCodes.count
        let servable = ContentAccess.pro.servableAirports(home: "ARN",
                                                          catalog: catalog)
        #expect(servable.count == all)
        #expect(ContentAccess.pro.lockedAirportCount(home: "ARN",
                                                     catalog: catalog) == 0)
    }

    @Test func lockedAirportCountIsTheRestOfTheMap() throws {
        let catalog = try ContentCatalog.loadBundled()
        let locked = ContentAccess.free.lockedAirportCount(home: "ARN",
                                                           catalog: catalog)
        #expect(locked == catalog.orderedAirportCodes.count
                - ContentAccess.freeAirportRadius - 1)
    }

    // MARK: - Presentation policy

    @Test func proPlayersAreNeverShownAPaywall() {
        for gate in ProGate.allCases {
            #expect(PaywallPolicy.allowsPresentation(
                gate: gate, access: .pro, history: .init()) == false)
        }
        #expect(PaywallPolicy.shouldOfferOnFirstRun(access: .pro,
                                                    history: .init()) == false)
        #expect(PaywallPolicy.shouldNudge(access: .pro, history: .init()) == false)
    }

    /// A player who reached for a locked thing gets an answer every time,
    /// throttle or no throttle. The alternative is a control that silently
    /// does nothing.
    @Test func gatesAlwaysAnswer() {
        let worn = PaywallPolicy.History(hasShownFirstRun: true,
                                         lastPresented: Date(),
                                         declineCount: 99)
        for gate in ProGate.allCases {
            #expect(PaywallPolicy.allowsPresentation(gate: gate, access: .free,
                                                     history: worn))
        }
    }

    @Test func firstRunOfferIsMadeExactlyOnce() {
        var history = PaywallPolicy.History()
        #expect(PaywallPolicy.shouldOfferOnFirstRun(access: .free,
                                                    history: history))
        history = PaywallPolicy.record(history, wasPurchase: false)
        #expect(PaywallPolicy.shouldOfferOnFirstRun(access: .free,
                                                    history: history) == false)
    }

    @Test func theNudgeWaitsAFullBillingPeriod() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let history = PaywallPolicy.History(hasShownFirstRun: true,
                                            lastPresented: now,
                                            declineCount: 1)
        #expect(PaywallPolicy.shouldNudge(access: .free, history: history,
                                          now: now.addingTimeInterval(86_400)) == false)
        #expect(PaywallPolicy.shouldNudge(
            access: .free, history: history,
            now: now.addingTimeInterval(PaywallPolicy.nudgeInterval + 1)))
    }

    /// Four refusals is an answer. After that the app stops asking and Pro
    /// lives in Settings, which is the difference between a game with a
    /// paywall and a game that is a paywall.
    @Test func theNudgeGivesUp() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var history = PaywallPolicy.History(hasShownFirstRun: true)
        for _ in 0..<PaywallPolicy.maxUnpromptedPresentations {
            history = PaywallPolicy.record(history,
                                           at: Date(timeIntervalSince1970: 0),
                                           wasPurchase: false)
        }
        #expect(history.declineCount == PaywallPolicy.maxUnpromptedPresentations)
        #expect(PaywallPolicy.shouldNudge(access: .free, history: history,
                                          now: now) == false)
        // …but the player can still open it themselves, forever.
        #expect(PaywallPolicy.allowsPresentation(gate: .direct, access: .free,
                                                 history: history))
    }

    @Test func aPurchaseIsNotADecline() {
        let history = PaywallPolicy.record(.init(), wasPurchase: true)
        #expect(history.declineCount == 0)
        #expect(history.hasShownFirstRun)
    }

    // MARK: - Paywall copy and compliance

    @Test func statsComeFromTheCatalogue() throws {
        let catalog = try ContentCatalog.loadBundled()
        let stats = PaywallContent.stats(catalog: catalog)
        #expect(stats.count == 4)
        #expect(stats[0].value == "\(Era.allCases.count)")
        #expect(stats[1].value == "\(catalog.orderedAirportCodes.count)")
        #expect(stats[2].value == "\(catalog.orderedAircraftTypeCodes.count)")
        #expect(stats[3].value == "\(WorldRegion.allCases.count)")
    }

    /// Guideline 3.1.2's renewal disclosure, clause by clause. Each of these
    /// is something App Review looks for by name.
    @Test func subscriptionTermsCarryEveryRequiredClause() {
        let terms = PaywallContent.subscriptionTerms
        for clause in ["renew automatically", "24 hours", "Manage or cancel",
                       "Subscriptions", "confirmation of purchase"] {
            #expect(terms.contains(clause), "missing: \(clause)")
        }
    }

    /// The rejection this paywall's visual design invites, closed by a test:
    /// "Your auto-renewable subscription promotes the free trial or
    /// introductory period more clearly and conspicuously than the billed
    /// amount." The commitment line must name the renewal price whether or
    /// not there is an introductory one, and the introductory price may
    /// never appear without it.
    @Test func theCommitmentLineAlwaysNamesTheBilledAmount() {
        let withIntro = PaywallContent.commitment(introductory: "$0.99",
                                                  standard: "$8.99",
                                                  period: "week")
        #expect(withIntro.contains("$8.99"))
        #expect(withIntro.contains("$0.99"))
        #expect(withIntro.contains("Renews automatically"))

        let without = PaywallContent.commitment(introductory: nil,
                                                standard: "$8.99",
                                                period: "week")
        #expect(without.contains("$8.99"))
        #expect(without.contains("$0.99") == false)
    }

    /// The call to action names a number in every state it can be in — no
    /// bare "Continue", which is the button that gets apps rejected and
    /// charges refunded.
    @Test func theCallToActionAlwaysNamesAPrice() {
        #expect(PaywallContent.callToAction(introductory: "$0.99",
                                            standard: "$8.99",
                                            isSubscription: true)
            .contains("$0.99"))
        #expect(PaywallContent.callToAction(introductory: nil,
                                            standard: "$8.99",
                                            isSubscription: true)
            .contains("$8.99"))
        #expect(PaywallContent.callToAction(introductory: nil,
                                            standard: "$49.99",
                                            isSubscription: false)
            .contains("$49.99"))
    }

    @Test func lifetimeIsDescribedAsNotRenewing() {
        let line = PaywallContent.lifetimeCommitment(price: "$49.99")
        #expect(line.contains("$49.99"))
        #expect(line.lowercased().contains("no subscription"))
    }

    /// Every gate has copy of its own, so no player is ever told the game is
    /// locked without being told which door they walked into.
    @Test func everyGateHasItsOwnCopy() {
        var headlines = Set<String>()
        for gate in ProGate.allCases {
            #expect(!gate.headline.isEmpty)
            #expect(!gate.subhead.isEmpty)
            headlines.insert(gate.headline)
        }
        #expect(headlines.count == ProGate.allCases.count)
    }

    @Test func benefitsAreDistinctAndDescribed() {
        let ids = Set(PaywallContent.benefits.map(\.id))
        #expect(ids.count == PaywallContent.benefits.count)
        for benefit in PaywallContent.benefits {
            #expect(!benefit.title.isEmpty)
            #expect(!benefit.detail.isEmpty)
            #expect(!benefit.symbol.isEmpty)
        }
    }
}
