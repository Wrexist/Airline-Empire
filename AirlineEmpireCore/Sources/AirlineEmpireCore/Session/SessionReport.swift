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
    /// The status earned at each station, as the save holds it.
    public let hubStatuses: [AirportCode: HubStatus]

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
        hubStatuses = player.hubStatuses ?? [:]
    }
}

/// A station that rose a status during the session: "Stockholm is now a Hub".
public struct HubStatusRise: Equatable, Sendable {
    public let airport: AirportCode
    public let status: HubStatus
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
    /// Statuses earned since opening, by airport; the highest each reached.
    public let statusRises: [HubStatusRise]

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
        // A save from before statuses records them all on its first day:
        // those are not this session's news.
        var rises: [HubStatusRise] = []
        if !start.hubStatuses.isEmpty {
            for airport in end.hubStatuses.keys.sorted() {
                guard let status = end.hubStatuses[airport],
                      status > (start.hubStatuses[airport] ?? .station) else { continue }
                rises.append(HubStatusRise(airport: airport, status: status))
            }
        }
        statusRises = rises
    }
}
