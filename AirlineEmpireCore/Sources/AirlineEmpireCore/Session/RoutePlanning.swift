public struct RoutePlan: Equatable, Codable, Sendable {
    public var fare: Money
    public var frequency: Int
    public init(fare: Money, frequency: Int) { self.fare = fare; self.frequency = frequency }
    public init(route: Route) { self.init(fare: route.ticketPrice, frequency: route.dailyRoundTrips) }
}

public struct RoutePlanChange: Equatable, Codable, Sendable {
    public let id: Int64
    public let at: SimTime
    public let previous: RoutePlan
    public let updated: RoutePlan
}

/// Both settings are validated before either one changes or slots are reserved.
public struct ApplyRoutePlanCommand: Command, Equatable {
    public static let name = "applyRoutePlan"
    public let airline: AirlineID
    public let route: RouteID
    public let plan: RoutePlan
    public init(airline: AirlineID, route: RouteID, plan: RoutePlan) {
        self.airline = airline; self.route = route; self.plan = plan
    }
    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        SetRoutePriceCommand(airline: airline, route: route, ticketPrice: plan.fare).validate(state: state, catalog: catalog)
            ?? SetRouteFrequencyCommand(airline: airline, route: route, dailyRoundTrips: plan.frequency).validate(state: state, catalog: catalog)
    }
    public func apply(state: inout GameState, context: SimContext) {
        guard let existing = state.routes[route] else { return }
        let previous = RoutePlan(route: existing)
        guard previous != plan else { return }
        SetRoutePriceCommand(airline: airline, route: route, ticketPrice: plan.fare).apply(state: &state, context: context)
        SetRouteFrequencyCommand(airline: airline, route: route, dailyRoundTrips: plan.frequency).apply(state: &state, context: context)
        var history = existing.planHistory ?? []
        history.insert(RoutePlanChange(id: (history.first?.id ?? 0) + 1, at: context.current, previous: previous, updated: plan), at: 0)
        state.routes[route]?.planHistory = Array(history.prefix(50))
    }
}

public struct RoutePlanPreview: Equatable, Sendable {
    public let revenue: Money
    public let costs: Money
    public let seatsPerDay: Int
    public let passengersPerDay: Double
    public let rotations: Int
    public var profit: Money { revenue - costs }
    public var loadFactor: Double { seatsPerDay > 0 ? passengersPerDay / Double(seatsPerDay) : 0 }

    /// A pure steady-state forecast using DemandSystem and the shared aircraft
    /// estimator. Comparison models one eligible aircraft alone on this route.
    public static func make(routeID: RouteID, plan: RoutePlan, comparisonAircraft: AircraftID? = nil,
                            state: GameState, catalog: ContentCatalog) -> Self? {
        guard let route = state.routes[routeID],
              ApplyRoutePlanCommand(airline: route.airline, route: routeID, plan: plan).validate(state: state, catalog: catalog) == nil else { return nil }
        var copy = state
        if let id = comparisonAircraft {
            guard let aircraft = copy.aircraft[id], aircraft.owner == route.airline, aircraft.isOperational,
                  route.assignedAircraft.contains(id) || state.assignmentCandidates(forRoute: routeID, catalog: catalog).contains(where: { $0.aircraftID == id && $0.isEligible }) else { return nil }
            copy.routes[routeID]?.assignedAircraft = [id]
            copy.aircraft[id]?.assignedRoute = routeID
        }
        let context = SimContext(previous: state.clock.now, current: state.clock.now, tick: .minutes(0),
            catalog: catalog, events: EventCollector(), progressionCeiling: .empire)
        ApplyRoutePlanCommand(airline: route.airline, route: routeID, plan: plan).apply(state: &copy, context: context)
        DemandSystem().update(state: &copy, context: context)
        var revenue = Money.zero, costs = Money.zero, seats = 0, rotations = 0
        var passengers = 0.0
        for id in copy.routes[routeID]?.assignedAircraft ?? [] {
            guard let aircraft = copy.aircraft[id], let spec = catalog.aircraftType(aircraft.typeCode),
                  let quote = AircraftConfigurationPreview.makeAllocated(aircraftID: id, state: copy, catalog: catalog) else { continue }
            let capacity = quote.rotationsPerDay * 2 * aircraft.cabin(for: spec).totalSeats
            revenue = revenue + quote.monthlyRevenue; costs = costs + quote.monthlyCosts
            seats += capacity; passengers += Double(capacity) * quote.loadFactor; rotations += quote.rotationsPerDay
        }
        guard seats > 0 else { return nil }
        return Self(revenue: revenue, costs: costs, seatsPerDay: seats, passengersPerDay: passengers, rotations: rotations)
    }
}
