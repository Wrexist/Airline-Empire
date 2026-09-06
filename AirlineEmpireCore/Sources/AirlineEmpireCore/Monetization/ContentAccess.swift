import Foundation

/// Where the free game ends and Pro begins (docs/MONETIZATION.md §4).
///
/// Every gate in the product is decided here, by a value type with no
/// dependencies, so that "what does a free player get" is one readable file
/// and a Linux test rather than a condition scattered across nine screens.
///
/// The design rule the gates obey: **nothing here makes the free game worse.**
/// A free player gets a complete, un-nagged, un-timed airline — the whole
/// simulation, the full ledger, every explainer, rivals that fight back — and
/// runs out of *world*, not out of patience. There is no energy meter, no
/// premium currency and no paid shortcut, because `docs/GAME_DESIGN.md` §1
/// names "waiting for timers, or paying to skip waiting" as explicitly not
/// the fantasy, and a paywall does not get to overrule the design bible.
public struct ContentAccess: Equatable, Sendable {
    public let isPro: Bool

    public static let free = ContentAccess(isPro: false)
    public static let pro = ContentAccess(isPro: true)

    public init(isPro: Bool) {
        self.isPro = isPro
    }

    // MARK: - The free tier's dimensions

    /// The last era a free airline can enter.
    ///
    /// Regional rather than Startup, and that is the single most important
    /// number in this file. `docs/PROGRESSION.md` §5 budgets 2–4 hours to
    /// reach the end of Regional, which is long enough for the map to fill
    /// in, for a first profitable season, and for the network to start
    /// feeling *owned* — which is the emotional payload `docs/GAME_DESIGN.md`
    /// §1 says the game is for. The wall then lands on the player's own
    /// ambition rather than on a stranger's demo.
    ///
    /// A one-era free tier was considered and rejected: it walls the player
    /// during the tutorial, before the game has made its case, and games'
    /// download-to-trial rate (4.4% median) is set by whether the free slice
    /// was convincing, not by how often the wall appeared.
    public static let freeEraCeiling: Era = .regional

    /// The scenario a free airline can start.
    ///
    /// Founder is the gentlest of the three (`Resources/scenarios.json`), so
    /// the free tier is the *easiest* configuration rather than a hobbled
    /// one. Entrepreneur and Magnate are difficulty choices, and selling a
    /// difficulty is selling replay, not selling advantage.
    public static let freeScenario: ScenarioCode = "founder"

    /// How many saved airlines a free player keeps. One, because a second
    /// save is a second campaign and a second campaign is the thing Pro is.
    public static let freeSaveSlots = 1

    /// How many airports a free airline may fly to, counted as the nearest
    /// others to its home.
    ///
    /// Nearest-N rather than "the home region", which was the first design:
    /// the regions are wildly uneven — Europe has 36 airports and the Middle
    /// East has 4 — so a region rule would have made the size of the free
    /// game depend on a choice the player makes in the first thirty seconds,
    /// before they could possibly know it mattered. Twenty nearest is the
    /// same free game from every home airport on the map, and it is also what
    /// a regional airline *is*.
    public static let freeAirportRadius = 20

    // MARK: - Gates

    /// The highest era this player may enter. Pro has no ceiling.
    public var eraCeiling: Era {
        isPro ? .empire : Self.freeEraCeiling
    }

    /// Whether progression may advance into `era`.
    public func allowsEra(_ era: Era) -> Bool {
        era <= eraCeiling
    }

    /// The era immediately past the free ceiling — the one the wall is about.
    /// `nil` for Pro, which has nothing past its ceiling.
    public var nextLockedEra: Era? {
        guard !isPro else { return nil }
        return Era(rawValue: Self.freeEraCeiling.rawValue + 1)
    }

    /// Whether a campaign may be started on this scenario.
    public func allowsScenario(_ code: ScenarioCode) -> Bool {
        isPro || code == Self.freeScenario
    }

    /// Whether an airline may be founded when `existingSaves` already exist.
    ///
    /// Takes a count rather than the slot list because the rule is about how
    /// many, and a rule that reads its own inputs is a rule that can be
    /// tested without a filesystem.
    public func allowsNewSave(existingSaves: Int) -> Bool {
        isPro || existingSaves < Self.freeSaveSlots
    }

    /// Whether the player may acquire this aircraft class, given the era
    /// their airline has actually reached.
    ///
    /// Deliberately delegates the class question entirely to `Era`: the
    /// paywall does not lock a single aircraft type of its own. Free players
    /// reach Regional, so they fly everything up to a large narrowbody —
    /// widebodies are behind the *era*, exactly as they are for a player who
    /// bought the game on day one and has not earned them yet. One rule, one
    /// explanation, and no aircraft that is visible-but-purchasable-for-cash.
    public func allowsAircraftCategory(_ category: AircraftCategory,
                                       in era: Era) -> Bool {
        era.allowedCategories.contains(category)
    }

    /// The aircraft classes this tier can ever reach, at any era.
    public var reachableCategories: [AircraftCategory] {
        eraCeiling.allowedCategories
    }

    /// The airports a free airline may serve: its home, plus the
    /// `freeAirportRadius` nearest to it. Pro serves the whole map.
    ///
    /// Returned as a set the caller holds for the session rather than
    /// recomputed per row — `nearestAirports` sorts the world, and the
    /// airport browser draws 94 rows.
    public func servableAirports(home: AirportCode,
                                 catalog: ContentCatalog) -> Set<AirportCode> {
        guard !isPro else { return Set(catalog.orderedAirportCodes) }
        var codes: Set<AirportCode> = [home]
        for (spec, _) in catalog.nearestAirports(to: home,
                                                 limit: Self.freeAirportRadius) {
            codes.insert(spec.code)
        }
        return codes
    }

    /// How many airports are behind the paywall for this home airport — the
    /// number the lock affordance says out loud, so it is never "some".
    public func lockedAirportCount(home: AirportCode,
                                   catalog: ContentCatalog) -> Int {
        catalog.orderedAirportCodes.count
            - servableAirports(home: home, catalog: catalog).count
    }
}

/// The set of things a free player is stopped by, as a value the UI can
/// switch on to say *which* wall this is.
///
/// A single generic "Unlock Pro" sheet converts worse than one that names the
/// thing the player just reached for, and — more to the point — a player who
/// taps Magnate and gets a sentence about eras has been told the game is
/// randomly locked rather than deliberately shaped.
public enum ProGate: Equatable, Sendable, Hashable, CaseIterable, Identifiable {
    /// `sheet(item:)` needs identity, and the case *is* the identity.
    /// Declared here rather than as a retroactive conformance in the app so
    /// the app layer owns no conformances for Core's types.
    public var id: Self { self }

    /// The airline finished the Regional era and cannot enter the next one.
    case eraCeiling
    /// A locked starting scenario was chosen.
    case scenario
    /// A second campaign was started.
    case saveSlot
    /// A route was drawn to an airport outside the free radius.
    case airport
    /// Opened from Settings or the menu with nothing specific in mind.
    case direct

    /// The headline the paywall wears when it was raised by this gate.
    public var headline: String {
        switch self {
        case .eraCeiling: "Your airline has outgrown the region"
        case .scenario: "A harder airline to build"
        case .saveSlot: "Run more than one airline"
        case .airport: "The rest of the world is waiting"
        case .direct: "Build the whole empire"
        }
    }

    /// One sentence under the headline, naming what was just reached for.
    /// Kept short: the benefit grid does the selling, this only has to make
    /// the player feel understood rather than blocked.
    public var subhead: String {
        switch self {
        case .eraCeiling:
            "You have run a regional carrier profitably. National, "
            + "International and Empire are where it becomes an empire."
        case .scenario:
            "Founder is the gentle start. Entrepreneur and Magnate change "
            + "the money, the market and the margin for error."
        case .saveSlot:
            "Keep this airline and start another — a different home, a "
            + "different strategy, a different world seed."
        case .airport:
            "A free airline flies its own region. Pro opens all 94 airports "
            + "across nine world regions."
        case .direct:
            "Airline Empire is free to fly — the whole simulation, no ads, "
            + "no timers. Pro opens the rest of the world."
        }
    }
}
