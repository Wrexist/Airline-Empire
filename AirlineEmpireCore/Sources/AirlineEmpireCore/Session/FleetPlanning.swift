/// Read-only planning facts shared by route discovery and aircraft shopping.
public struct RouteFleetNeed: Equatable, Sendable {
    public enum Reason: String, Sendable { case unassigned, frequency, seats }
    public let routeID: RouteID
    public let reason: Reason
    public let dailySeatShortfall: Int
}

extension GameState {
    public func idleAircraft(from: AirportCode, to: AirportCode,
                             catalog: ContentCatalog) -> [Aircraft] {
        guard let player = playerAirline else { return [] }
        return fleet(of: player.id).filter { aircraft in
            guard aircraft.assignedRoute == nil, aircraft.isReadyToFly,
                  let spec = catalog.aircraftType(aircraft.typeCode) else { return false }
            return catalog.routeEligibility(from: from, to: to,
                aircraftRangeKm: spec.rangeKm,
                aircraftRunwayRequirement: spec.runwayRequirement).isEmpty
        }.sorted { $0.id < $1.id }
    }

    public func fleetNeeds(catalog: ContentCatalog) -> [RouteFleetNeed] {
        guard let player = playerAirline else { return [] }
        return routes(of: player.id).compactMap { route -> RouteFleetNeed? in
            let demand = route.demandOutboundToday + route.demandInboundToday
            guard !route.assignedAircraft.isEmpty else {
                return RouteFleetNeed(routeID: route.id, reason: .unassigned,
                                      dailySeatShortfall: demand)
            }
            let ready = route.assignedAircraft.compactMap { aircraft[$0] }
                .filter(\.isOperational)
            // Match the scheduler's representative-airframe capacity calculation.
            guard let first = route.assignedAircraft.sorted().compactMap({ aircraft[$0] }).first,
                  let spec = catalog.aircraftType(first.typeCode) else { return nil }
            let rotations = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
                distanceKm: route.distanceKm, spec: spec, ops: catalog.tuning.ops)
            let trips = min(route.dailyRoundTrips, rotations * ready.count)
            let shortfall = max(0, demand - trips * spec.seats * 2)
            if trips < route.dailyRoundTrips {
                return RouteFleetNeed(routeID: route.id, reason: .frequency,
                                      dailySeatShortfall: shortfall)
            }
            if shortfall > 0 {
                return RouteFleetNeed(routeID: route.id, reason: .seats,
                                      dailySeatShortfall: shortfall)
            }
            return nil
        }.sorted {
            if ($0.reason == .unassigned) != ($1.reason == .unassigned) {
                return $0.reason == .unassigned
            }
            if $0.dailySeatShortfall != $1.dailySeatShortfall {
                return $0.dailySeatShortfall > $1.dailySeatShortfall
            }
            return $0.routeID < $1.routeID
        }
    }

    /// Fit ranks range/runway-compatible types by capacity, then recurring cost.
    /// It is not a profit forecast and never changes the player's fleet.
    public func aircraftFits(route: Route, catalog: ContentCatalog,
                             era: Era) -> [AircraftTypeSpec] {
        let observedDemand = route.demandOutboundToday + route.demandInboundToday
        let demand = observedDemand > 0 ? observedDemand
            : marketCandidates(from: route.origin, catalog: catalog)
                .first(where: { $0.destination == route.destination })?.expectedDailyPassengers ?? 0
        let specs = catalog.orderedAircraftTypeCodes.compactMap { catalog.aircraftType($0) }
            .filter { era.allowedCategories.contains($0.category)
                && catalog.routeEligibility(from: route.origin, to: route.destination,
                    aircraftRangeKm: $0.rangeKm,
                    aircraftRunwayRequirement: $0.runwayRequirement).isEmpty }
        func mismatch(_ spec: AircraftTypeSpec) -> Int {
            guard demand > 0 else { return 0 }
            let trips = min(route.dailyRoundTrips,
                FlightSchedulingSystem.roundTripsPerAircraftPerDay(
                    distanceKm: route.distanceKm, spec: spec, ops: catalog.tuning.ops))
            return abs(demand - trips * spec.seats * 2)
        }
        return specs.sorted {
            if mismatch($0) != mismatch($1) { return mismatch($0) < mismatch($1) }
            if $0.leaseMonthly != $1.leaseMonthly { return $0.leaseMonthly < $1.leaseMonthly }
            return $0.code.raw < $1.code.raw
        }
    }
}
