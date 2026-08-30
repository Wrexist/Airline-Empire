/// An airline — player-controlled or AI-controlled, same type, same rules
/// (docs/ARCHITECTURE.md §3.1). Cash lives in the `Ledger`, not here, so
/// every balance change stays traceable.
public struct Airline: Equatable, Codable, Sendable {
    public let id: AirlineID
    public var name: String
    public let kind: AirlineKind
    public let homeAirport: AirportCode
    public let foundedAt: SimTime
    public var loans: [Loan]
    public var status: AirlineStatus
    /// Administrations survived; the second collapse is final
    /// (docs/GAME_DESIGN.md §5).
    public var administrationCount: Int
    /// Consecutive days below the overdraft floor (solvency tracking).
    public var daysInsolvent: Int
    public var reputation: Reputation
    /// The airline's colour (docs/GAME_DESIGN.md §4.1). Identity, not
    /// mechanics: nothing in the simulation reads it. It is state rather than
    /// a UI preference because it belongs to the airline — it has to survive
    /// a save, and a rival's livery has to be as real as the player's.
    public var livery: Livery
    public var serviceTier: ServiceTier
    /// Present on AI airlines only; the player has no profile.
    public var aiProfile: AIProfile?
    /// Same-day ops counters, reset daily by ReputationSystem.
    public var opsToday: DailyOps

    public init(id: AirlineID, name: String, kind: AirlineKind,
                homeAirport: AirportCode, foundedAt: SimTime) {
        self.id = id
        self.name = name
        self.kind = kind
        self.homeAirport = homeAirport
        self.foundedAt = foundedAt
        self.loans = []
        self.status = .active
        self.administrationCount = 0
        self.daysInsolvent = 0
        self.reputation = Reputation()
        self.livery = .default
        self.serviceTier = .standard
        self.aiProfile = nil
        self.opsToday = DailyOps()
    }
}

public enum AirlineStatus: Equatable, Codable, Sendable {
    case active
    /// Terminal state: the airline failed for good.
    case collapsed
}

/// An airline's colour, as a name rather than a hex string.
///
/// A closed set, for two reasons: the map has to keep every carrier
/// distinguishable against a dark ocean, which a free colour picker cannot
/// promise; and a named palette survives a save without encoding a colour
/// space. Rendering is the app's business — Core only knows which one.
public enum Livery: String, Equatable, Codable, Sendable, CaseIterable {
    case azure
    case ember
    case jade
    case crimson
    case violet
    case slate
    case gold
    case teal

    /// What an airline gets when nobody chose: the app's own accent.
    public static let `default` = Livery.azure

    /// A deterministic livery for a rival, so the same seed paints the same
    /// world and no two rivals in a standard cast collide.
    public static func forCompetitor(index: Int) -> Livery {
        let palette = Livery.allCases.filter { $0 != .default }
        return palette[abs(index) % palette.count]
    }
}

public enum AirlineKind: String, Equatable, Codable, Sendable {
    case player
    case ai   // strategy profile attaches in Phase 10
}
