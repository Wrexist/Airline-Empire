/// A forward-looking experience profile from the same components used by
/// ReputationSystem. It is a quality estimate, not a passenger survey.
public struct AircraftPassengerExperience: Equatable, Sendable {
    public let comfort: Double
    public let reliability: Double
    public let punctuality: Double
    public let service: Double
    /// ReputationSystem uses the equal mean of these four quality terms
    /// when evaluating the value passengers receive for their fare.
    public var happiness: Double { (comfort + reliability + punctuality + service) / 4 }

    public init(aircraft: Aircraft, configuration: AircraftConfiguration,
                spec: AircraftTypeSpec, state: GameState, catalog: ContentCatalog) {
        comfort = min(1, spec.comfortBaseline + configuration.comfortBonus(tuning: catalog.tuning.cabin))
        reliability = aircraft.currentReliability(type: spec, tuning: catalog.tuning.fleet)
        let airline = state.airlines[aircraft.owner]
        if let id = aircraft.assignedRoute, let route = state.routes[id], route.stats.flightsCompleted > 0 {
            punctuality = route.stats.punctuality
        } else {
            punctuality = airline?.reputation.punctuality ?? 0.6
        }
        var serviceTarget = catalog.tuning.reputation.serviceTarget(airline?.serviceTier ?? .basic)
        if state.isPlayer(aircraft.owner), state.playerHasCapability(.groundExperience) {
            serviceTarget = min(1, serviceTarget + 0.08)
        }
        service = serviceTarget
    }
}
