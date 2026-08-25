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
    public var serviceTier: ServiceTier
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
        self.serviceTier = .standard
        self.opsToday = DailyOps()
    }
}

public enum AirlineStatus: Equatable, Codable, Sendable {
    case active
    /// Terminal state: the airline failed for good.
    case collapsed
}

public enum AirlineKind: String, Equatable, Codable, Sendable {
    case player
    case ai   // strategy profile attaches in Phase 10
}
