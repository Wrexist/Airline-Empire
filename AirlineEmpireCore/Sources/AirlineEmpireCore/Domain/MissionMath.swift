/// Mission progress, in one place (docs/PROGRESSION.md §3).
///
/// `ProgressionSystem` measures a boom rush as passengers carried on
/// region-touching routes since the offer's baseline, and resolves the mission
/// against that number. The progression screen has to show the *same* number —
/// a bar that fills at a different rate from the thing it is a bar for is
/// worse than no bar. So the measurement lives here and both callers ask it.
public enum MissionMath {
    /// Passengers carried toward `mission`, measured the way the mission is
    /// resolved. Never negative.
    public static func progress(of mission: Mission, player: Airline,
                                state: GameState,
                                catalog: ContentCatalog) -> Int64 {
        switch mission.kind {
        case .boomRush(let region, _):
            // The open routes' lifetime counters, plus those of the routes
            // that closed since the offer (banked as each closed), less what
            // the open routes had carried at the offer. Every term only
            // grows, so progress never goes backwards when a route closes.
            let current = regionPassengers(region, player: player, state: state,
                                           catalog: catalog)
            return max(0, current + (mission.bankedPassengers ?? 0) - mission.baseline)
        case .flightContract:
            return max(0, state.progression.counters.flightsCompleted - mission.baseline)
        case .passengerContract:
            return max(0, state.progression.counters.passengersCarried - mission.baseline)
        }
    }

    /// What the mission is asking for.
    public static func target(of mission: Mission) -> Int64 {
        switch mission.kind {
        case .boomRush(_, let target): target
        case .flightContract(let target), .passengerContract(let target): target
        }
    }

    /// Lifetime passengers on the player's routes that touch `region`.
    /// Also the baseline captured when a mission is offered.
    public static func regionPassengers(_ region: WorldRegion, player: Airline,
                                        state: GameState,
                                        catalog: ContentCatalog) -> Int64 {
        state.routes(of: player.id)
            .filter { touchesRegion($0, region, catalog: catalog) }
            .reduce(Int64(0)) { $0 + $1.stats.passengersCarried }
    }

    public static func touchesRegion(_ route: Route, _ region: WorldRegion,
                                     catalog: ContentCatalog) -> Bool {
        [route.origin, route.destination].contains { code in
            catalog.airport(code)?.region == region
        }
    }

    /// Seats a route puts on sale a day: the round trips its airframes can
    /// fly (`FlightSchedulingSystem.flyableRoundTrips`), both legs, each trip
    /// at the cabin of the airframe the scheduler's round robin gives it.
    /// A boom rush's target is set from this; it assumed 150 seats a trip
    /// at the requested frequency, which a turboprop route could never fill
    /// and a widebody route cleared in days.
    public static func dailySeatsOffered(_ route: Route, state: GameState,
                                         catalog: ContentCatalog) -> Int {
        let seats = route.assignedAircraft.sorted().compactMap { id -> Int? in
            guard let aircraft = state.aircraft[id], !aircraft.status.isOnOrder,
                  let spec = catalog.aircraftType(aircraft.typeCode) else { return nil }
            return aircraft.cabin(for: spec).totalSeats
        }
        guard !seats.isEmpty else { return 0 }
        let trips = FlightSchedulingSystem.flyableRoundTrips(route: route, state: state,
                                                             catalog: catalog)
        return (0..<trips).reduce(0) { $0 + 2 * seats[$1 % seats.count] }
    }

    /// Cancellations on the player's routes over the airline's life: the
    /// open routes' counts plus those banked as routes closed.
    public static func lifetimeCancellations(player: Airline, state: GameState) -> Int64 {
        state.routes(of: player.id).reduce(state.progression.counters.cancelledOnClosedRoutes ?? 0) {
            $0 + $1.stats.flightsCancelled
        }
    }
}
