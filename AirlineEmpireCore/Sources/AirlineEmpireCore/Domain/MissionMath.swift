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
            let current = regionPassengers(region, player: player, state: state,
                                           catalog: catalog)
            return max(0, current - mission.baseline)
        }
    }

    /// What the mission is asking for.
    public static func target(of mission: Mission) -> Int64 {
        switch mission.kind {
        case .boomRush(_, let target): target
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
}
