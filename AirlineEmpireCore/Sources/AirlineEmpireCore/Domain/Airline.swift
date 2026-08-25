/// An airline — player-controlled or AI-controlled, same type, same rules
/// (docs/ARCHITECTURE.md §3.1). Cash lives in the `Ledger`, not here, so
/// every balance change stays traceable.
public struct Airline: Equatable, Codable, Sendable {
    public let id: AirlineID
    public var name: String
    public let kind: AirlineKind
    public let homeAirport: AirportCode
    public let foundedAt: SimTime

    public init(id: AirlineID, name: String, kind: AirlineKind,
                homeAirport: AirportCode, foundedAt: SimTime) {
        self.id = id
        self.name = name
        self.kind = kind
        self.homeAirport = homeAirport
        self.foundedAt = foundedAt
    }
}

public enum AirlineKind: String, Equatable, Codable, Sendable {
    case player
    case ai   // strategy profile attaches in Phase 10
}
