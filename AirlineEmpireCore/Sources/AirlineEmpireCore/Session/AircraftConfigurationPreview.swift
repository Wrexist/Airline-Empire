/// A steady-state 30-day planning quote. Demand is allocated by the live
/// demand system on a value copy; costs use the shared airframe estimator.
public struct AircraftConfigurationPreview: Equatable, Sendable {
    public let monthlyRevenue: Money
    public let monthlyCosts: Money
    public let loadFactor: Double
    public let rotationsPerDay: Int
    public var monthlyProfit: Money { monthlyRevenue - monthlyCosts }

    public static func make(aircraftID: AircraftID, configuration: AircraftConfiguration,
                            state: GameState, catalog: ContentCatalog) -> Self? {
        guard var aircraft = state.aircraft[aircraftID], aircraft.isOperational,
              let spec = catalog.aircraftType(aircraft.typeCode),
              configuration.isValid(capacity: spec.seats),
              let routeID = aircraft.assignedRoute, let route = state.routes[routeID],
              let airline = state.airlines[aircraft.owner],
              let origin = catalog.airport(route.origin), let destination = catalog.airport(route.destination) else { return nil }
        var copy = state
        aircraft.configuration = configuration
        copy.aircraft[aircraftID] = aircraft
        let context = SimContext(previous: state.clock.now, current: state.clock.now,
            tick: .minutes(0), catalog: catalog, events: EventCollector(), progressionCeiling: .empire)
        DemandSystem().update(state: &copy, context: context)
        guard let forecast = copy.routes[routeID] else { return nil }
        let active = route.assignedAircraft.sorted().compactMap { copy.aircraft[$0] }.filter(\.isOperational)
        guard let index = active.firstIndex(where: { $0.id == aircraftID }) else { return nil }
        let maximum = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
            distanceKm: route.distanceKm, spec: spec, ops: catalog.tuning.ops)
        let rotations = min(maximum, max(0, (route.dailyRoundTrips + active.count - 1 - index) / active.count))
        let capacity = Double(rotations * 2 * configuration.totalSeats)
        let routeCapacity = active.reduce(0.0) { sum, item in
            guard let type = catalog.aircraftType(item.typeCode) else { return sum }
            return sum + Double(item.cabin(for: type).totalSeats)
        }
        let share = Double(configuration.totalSeats) / max(1, routeCapacity)
        let passengers = min(capacity, Double(forecast.demandOutboundToday + forecast.demandInboundToday) * share)
        let ratio = route.ticketPrice.asDouble * configuration.yieldMultiplier(tuning: catalog.tuning.cabin)
            / DemandSystem.referenceFare(distanceKm: route.distanceKm, tuning: catalog.tuning.demand)
        func value(_ basis: CompetitorAISystem.RankingBasis) -> Double {
            CompetitorAISystem.airframeDayValue(distanceKm: route.distanceKm,
                passengersPerDay: passengers, spec: spec, fareRatio: ratio,
                serviceTier: airline.serviceTier, origin: origin, destination: destination,
                state: state, catalog: catalog, rotationsPerDay: rotations, basis: basis)
        }
        let revenue = value(.revenue)
        let flightHours = Double(rotations * 2) * Double(FlightSchedulingSystem.flightMinutes(
            distanceKm: route.distanceKm, cruiseSpeedKmh: spec.cruiseSpeedKmh,
            overheadMinutes: catalog.tuning.ops.flightOverheadMinutes)) / 60
        let ageReserve = FleetEconomics.expectedMaintenancePerDay(type: spec, ageYears: aircraft.ageYears,
            blockHoursPerDay: flightHours, fleet: catalog.tuning.fleet, ops: catalog.tuning.ops)
            - FleetEconomics.expectedMaintenancePerDay(type: spec, ageYears: 0,
            blockHoursPerDay: flightHours, fleet: catalog.tuning.fleet, ops: catalog.tuning.ops)
        let lease: Double
        switch aircraft.ownership { case .leased(let rate, _): lease = rate.asDouble; case .owned: lease = 0 }
        let costs = (revenue - value(.profit) + passengers * configuration.serviceCostPerPassenger(tuning: catalog.tuning.cabin).asDouble + ageReserve) * 30 + lease
        return Self(monthlyRevenue: Money(rounding: revenue * 30), monthlyCosts: Money(rounding: costs),
                    loadFactor: capacity > 0 ? passengers / capacity : 0, rotationsPerDay: rotations)
    }
}
