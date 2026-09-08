/// A lightweight baseline for one opened campaign, not a second save format.
public struct SessionCheckpoint: Equatable, Sendable {
    public let airline: AirlineID
    public let name: String
    public let day: Int64
    public let cash: Money
    public let flights: Int64
    public let passengers: Int64
    public let routes: Int
    public let aircraft: Int

    public init?(_ state: GameState) {
        guard let player = state.playerAirline else { return nil }
        airline = player.id
        name = player.name
        day = state.clock.now.dayIndex
        cash = state.ledger.balance(of: player.id)
        flights = state.progression.counters.flightsCompleted
        passengers = state.progression.counters.passengersCarried
        routes = state.routes(of: player.id).count
        aircraft = state.fleet(of: player.id).count
    }
}

/// Changes since opening this campaign. Cash movement includes financing
/// and purchases, and must never be labelled operating profit.
public struct SessionReport: Equatable, Sendable {
    public let airlineName: String
    public let days: Int64
    public let cashChange: Money
    public let flights: Int64
    public let passengers: Int64
    public let routeChange: Int
    public let aircraftChange: Int

    public init?(from start: SessionCheckpoint, to end: SessionCheckpoint) {
        guard start.airline == end.airline, end.day >= start.day,
              end.flights >= start.flights, end.passengers >= start.passengers else { return nil }
        airlineName = end.name
        days = end.day - start.day
        cashChange = end.cash - start.cash
        flights = end.flights - start.flights
        passengers = end.passengers - start.passengers
        routeChange = end.routes - start.routes
        aircraftChange = end.aircraft - start.aircraft
    }
}
