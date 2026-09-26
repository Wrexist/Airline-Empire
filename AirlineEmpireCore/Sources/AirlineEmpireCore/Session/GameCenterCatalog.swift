import Foundation

/// What Airline Empire reports to Game Center, as data
/// (docs/GAME_CENTER.md).
///
/// Game Center adds no rules. Every achievement below is something
/// `ProgressionSystem` already awards and the celebration overlay already
/// shows; every leaderboard is a number the simulation already counts. This
/// file only names them the way App Store Connect needs them named, so the
/// mapping — which is the part that can be wrong in a way players notice
/// (an achievement that never unlocks, a leaderboard that ranks the wrong
/// thing) — is a pure function a Linux test can hold still.
///
/// GameKit itself lives in the app layer, for the reason StoreKit does: Core
/// builds and tests on Linux.
public enum GameCenterCatalog {

    // MARK: - Achievements

    /// One Game Center achievement and where it comes from.
    public struct Achievement: Equatable, Sendable, Identifiable {
        /// The App Store Connect achievement ID. Immutable once created there.
        public let id: String
        /// What earns it, in Core's own terms.
        public let source: Source
        /// Game Center points. Apple caps one achievement at 100 and the whole
        /// game at 1,000.
        public let points: Int
        /// The title shown in Game Center. The app's own vocabulary uses the
        /// same words, so the two surfaces never name one thing twice.
        public let title: String

        public enum Source: Equatable, Sendable, Hashable {
            /// A code in `ProgressionState.milestones`.
            case milestone(String)
            /// A code in `ProgressionState.achievements`.
            case achievement(String)
            /// Reaching an era.
            case era(Era)
        }
    }

    /// Prefix shared by every ID, so they sort together in App Store Connect
    /// and cannot collide with a future product or leaderboard.
    public static let achievementPrefix = "com.airlineempire.game.achievement."
    public static let leaderboardPrefix = "com.airlineempire.game.leaderboard."

    /// Every achievement, in the order App Store Connect should list them.
    ///
    /// Points follow effort, and sum to 1,000 exactly — Apple's ceiling — so
    /// no future achievement can be added without deciding what it is worth
    /// against these. `pointsSumToTheCeiling` holds that.
    public static let achievements: [Achievement] = [
        // The first hour. Small, because everyone who plays gets them.
        a("firstFlight", .milestone("firstFlight"), 20, "First flight"),
        a("firstOwnedAircraft", .milestone("firstOwnedAircraft"), 15, "First aircraft of your own"),
        a("firstProfitableMonth", .milestone("firstProfitableMonth"), 25, "First profitable month"),
        a("eraRegional", .era(.regional), 30, "Regional carrier"),
        // The free game's ceiling. Reachable without Pro.
        a("fleet10", .milestone("fleet10"), 40, "A fleet of ten"),
        a("destinations10", .milestone("destinations10"), 40, "Ten destinations"),
        a("passengers100k", .milestone("passengers100k"), 50, "100,000 passengers"),
        a("firstMillionMonth", .milestone("firstMillionMonth"), 60, "First million-dollar month"),
        // The later eras.
        a("eraNational", .era(.national), 60, "National airline"),
        a("firstIntercontinental", .milestone("firstIntercontinental"), 70, "First intercontinental route"),
        a("eraInternational", .era(.international), 80, "International airline"),
        a("passengers1m", .milestone("passengers1m"), 90, "One million passengers"),
        a("eraEmpire", .era(.empire), 100, "Airline empire"),
        // The playstyle achievements. Hard, and each a different way to play.
        a("debtFree", .achievement("debtFree"), 80, "Debt free"),
        a("weatherProof", .achievement("weatherProof"), 80, "Weatherproof"),
        a("valueLegend", .achievement("valueLegend"), 80, "Value legend"),
        a("purist", .achievement("purist"), 80, "Single-family purist"),
    ]

    private static func a(_ suffix: String, _ source: Achievement.Source,
                          _ points: Int, _ title: String) -> Achievement {
        Achievement(id: achievementPrefix + suffix, source: source,
                    points: points, title: title)
    }

    /// Apple's limits, stated where the catalogue is.
    public static let maxPointsPerAchievement = 100
    public static let maxTotalPoints = 1_000

    /// The achievements this campaign has earned.
    ///
    /// Reported in full every time rather than as a diff: Game Center
    /// ignores a report for something already complete, and re-reporting
    /// everything is what makes an offline session, a reinstall or a second
    /// device converge without any record of what was sent before.
    public static func earned(by progression: ProgressionState) -> [Achievement] {
        let milestones = Set(progression.milestones)
        let unlocked = Set(progression.achievements)
        return achievements.filter { achievement in
            switch achievement.source {
            case .milestone(let code): milestones.contains(code)
            case .achievement(let code): unlocked.contains(code)
            case .era(let era): progression.era >= era
            }
        }
    }

    /// Something cheap and `Hashable` that changes exactly when `earned`
    /// would, so the app can report on change instead of on every tick.
    public static func fingerprint(of progression: ProgressionState) -> Int {
        var hasher = Hasher()
        hasher.combine(progression.era)
        hasher.combine(progression.milestones.count)
        hasher.combine(progression.achievements.count)
        return hasher.finalize()
    }

    // MARK: - Leaderboards

    /// A classic, all-time, high-score leaderboard.
    public struct Leaderboard: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        /// How App Store Connect should format the score.
        public let unit: String
    }

    public static let passengers = Leaderboard(
        id: leaderboardPrefix + "passengers", title: "Passengers flown",
        unit: "passengers")
    public static let destinations = Leaderboard(
        id: leaderboardPrefix + "destinations", title: "Largest network",
        unit: "destinations")
    public static let fleet = Leaderboard(
        id: leaderboardPrefix + "fleet", title: "Largest fleet",
        unit: "aircraft")

    public static let leaderboards: [Leaderboard] = [passengers, destinations, fleet]

    /// This campaign's score on each leaderboard.
    ///
    /// Counts only, never money. Cash and airline value depend on the
    /// starting scenario — Magnate begins with several times Founder's — so a
    /// money leaderboard would rank scenario choice, not play. Passengers,
    /// network and fleet are all earned in the world the same way from any
    /// start. Aircraft still on order do not count: they are a commitment,
    /// not a fleet.
    public static func scores(for airline: AirlineID,
                              in state: GameState) -> [(Leaderboard, Int)] {
        let routes = state.routes(of: airline)
        var airports = Set<AirportCode>()
        for route in routes {
            airports.insert(route.origin)
            airports.insert(route.destination)
        }
        let delivered = state.fleet(of: airline).filter { !$0.status.isOnOrder }.count
        let carried = Int(clamping: state.progression.counters.passengersCarried)
        return [
            (passengers, carried),
            (destinations, airports.count),
            (fleet, delivered),
        ]
    }
}
