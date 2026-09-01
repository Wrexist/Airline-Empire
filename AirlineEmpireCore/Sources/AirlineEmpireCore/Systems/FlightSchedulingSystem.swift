/// Daily schedule materialization (docs/ROUTES.md): turns each route's
/// frequency + assigned aircraft into concrete `Flight` entities for the
/// day just started. Runs before `FlightOpsSystem` in the pipeline.
///
/// Deterministic by construction: routes in sorted order, aircraft in
/// sorted order, arithmetic-only departure times.
public struct FlightSchedulingSystem: SimulationSystem {
    public let id = "flightScheduling"
    public let cadence = Cadence.daily

    public init() {}

    public func update(state: inout GameState, context: SimContext) {
        let ops = context.catalog.tuning.ops
        let dayStart = SimTime(rawMinutes: state.clock.now.dayIndex * GameCalendar.minutesPerDay)

        for routeID in state.orderedRouteIDs {
            let route = state.routes[routeID]!
            guard let spec = routeAircraftSpec(route, state: state, catalog: context.catalog)
            else { continue }

            let flightMinutes = Self.flightMinutes(distanceKm: route.distanceKm,
                                                   cruiseSpeedKmh: spec.cruiseSpeedKmh,
                                                   overheadMinutes: ops.flightOverheadMinutes)
            let roundTripBlock = 2 * (flightMinutes + Int64(spec.turnaroundMinutes))

            // Aircraft able to fly today, in deterministic order.
            var usable: [AircraftID] = []
            for aircraftID in route.assignedAircraft.sorted() {
                guard let aircraft = state.aircraft[aircraftID], aircraft.isOperational
                else { continue }
                if aircraft.location == route.origin || aircraft.location == route.destination {
                    usable.append(aircraftID)
                } else if aircraft.activeFlight == nil,
                          !hasPendingFlight(aircraftID, state: state) {
                    // Reposition with a real ferry flight to the origin.
                    scheduleFerry(for: aircraftID, route: route, spec: spec,
                                  dayStart: dayStart, ops: ops,
                                  state: &state, context: context)
                }
            }
            guard !usable.isEmpty else { continue }

            let capacityPerAircraft = Self.roundTripsPerAircraftPerDay(
                distanceKm: route.distanceKm, spec: spec, ops: ops)
            let totalTrips = min(route.dailyRoundTrips, capacityPerAircraft * usable.count)
            guard totalTrips > 0 else { continue }

            // Round-robin trips across aircraft; back-to-back rotations from
            // the start of the operating day.
            var tripsFor: [AircraftID: Int] = [:]
            for trip in 0..<totalTrips {
                let aircraftID = usable[trip % usable.count]
                tripsFor[aircraftID, default: 0] += 1
            }
            for aircraftID in usable {
                guard let trips = tripsFor[aircraftID] else { continue }
                let startsAtOrigin = state.aircraft[aircraftID]!.location == route.origin
                for tripIndex in 0..<trips {
                    let base = dayStart + .minutes(
                        ops.operatingDayStartMinute + Int64(tripIndex) * roundTripBlock)
                    let (firstFrom, firstTo) = startsAtOrigin
                        ? (route.origin, route.destination)
                        : (route.destination, route.origin)
                    makeFlight(route: route, aircraft: aircraftID, from: firstFrom,
                               to: firstTo, departure: base,
                               flightMinutes: flightMinutes, state: &state)
                    makeFlight(route: route, aircraft: aircraftID, from: firstTo,
                               to: firstFrom,
                               departure: base + .minutes(flightMinutes + Int64(spec.turnaroundMinutes)),
                               flightMinutes: flightMinutes, state: &state)
                }
            }
        }
    }

    /// How many round trips one airframe of `spec` can fly on a route of this
    /// length in one operating day — the figure the materialisation above
    /// caps a route's frequency with. Public so that a planner (the AI, a
    /// screen) can ask "can this route use another aircraft?" with the
    /// scheduler's own arithmetic rather than a second copy of it.
    public static func roundTripsPerAircraftPerDay(distanceKm: Int, spec: AircraftTypeSpec,
                                                   ops: OpsTuning) -> Int {
        let flightMinutes = flightMinutes(distanceKm: distanceKm,
                                          cruiseSpeedKmh: spec.cruiseSpeedKmh,
                                          overheadMinutes: ops.flightOverheadMinutes)
        let roundTripBlock = 2 * (flightMinutes + Int64(spec.turnaroundMinutes))
        return max(0, Int(ops.operatingDayMinutes / roundTripBlock))
    }

    /// Cruise time + fixed overhead, whole minutes.
    static func flightMinutes(distanceKm: Int, cruiseSpeedKmh: Int,
                              overheadMinutes: Int64) -> Int64 {
        Int64((Double(distanceKm) / Double(cruiseSpeedKmh) * 60).rounded()) + overheadMinutes
    }

    /// The spec used for route timing: the first assigned aircraft's type
    /// (mixed-type routes time to their first aircraft; refinement tracked
    /// for Phase 7+ if mixed fleets prove common).
    private func routeAircraftSpec(_ route: Route, state: GameState,
                                   catalog: ContentCatalog) -> AircraftTypeSpec? {
        for aircraftID in route.assignedAircraft.sorted() {
            if let aircraft = state.aircraft[aircraftID] {
                return catalog.aircraftType(aircraft.typeCode)
            }
        }
        return nil
    }

    private func hasPendingFlight(_ aircraftID: AircraftID, state: GameState) -> Bool {
        state.flights.values.contains { $0.aircraft == aircraftID }
    }

    private func scheduleFerry(for aircraftID: AircraftID, route: Route,
                               spec: AircraftTypeSpec, dayStart: SimTime,
                               ops: OpsTuning, state: inout GameState,
                               context: SimContext) {
        let aircraft = state.aircraft[aircraftID]!
        guard let from = context.catalog.airport(aircraft.location),
              let to = context.catalog.airport(route.origin) else { return }
        let distance = Geo.distanceKm(from: from.coordinate, to: to.coordinate)
        guard distance <= spec.rangeKm else { return } // unferryable; stays put
        let minutes = Self.flightMinutes(distanceKm: distance,
                                         cruiseSpeedKmh: spec.cruiseSpeedKmh,
                                         overheadMinutes: ops.flightOverheadMinutes)
        let id = state.meta.idAllocator.allocateFlightID()
        state.flights[id] = Flight(
            id: id, route: route.id, aircraft: aircraftID, kind: .ferry,
            from: aircraft.location, to: route.origin, distanceKm: distance,
            flightMinutes: minutes,
            scheduledDeparture: dayStart + .minutes(ops.operatingDayStartMinute))
    }

    private func makeFlight(route: Route, aircraft: AircraftID, from: AirportCode,
                            to: AirportCode, departure: SimTime,
                            flightMinutes: Int64, state: inout GameState) {
        let id = state.meta.idAllocator.allocateFlightID()
        state.flights[id] = Flight(
            id: id, route: route.id, aircraft: aircraft, kind: .revenue,
            from: from, to: to, distanceKm: route.distanceKm,
            flightMinutes: flightMinutes, scheduledDeparture: departure)
    }
}
