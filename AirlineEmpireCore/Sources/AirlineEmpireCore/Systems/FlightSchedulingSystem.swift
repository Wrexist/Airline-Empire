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
        // Read before today's flights exist: where yesterday's plan leaves
        // each aircraft once its pending legs have flown.
        let pendingEnds = Self.pendingDestinations(state: state)

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
                    // Reposition with a real ferry flight to the route.
                    scheduleFerry(for: aircraftID, route: route,
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
                // The day starts where the aircraft will be, not where it
                // stands at midnight. A full day of back-to-back rotations
                // ends after midnight — each leg boards on the tick its
                // aircraft frees up and leaves a tick later, and arrivals and
                // turnarounds round up to whole ticks — so the last leg is
                // often still airborne here and `location` is the airport it
                // left. Planning from there put the first departure at the
                // wrong end, where it expired as a cancellation at 10:00 on
                // every day the route flew its full frequency.
                let startsAt = pendingEnds[aircraftID] ?? state.aircraft[aircraftID]!.location
                let startsAtOrigin = startsAt == route.origin
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

    /// Round trips the scheduler allots one airframe on a route: the type's
    /// daily maximum, capped by the aircraft's even share of the route's
    /// requested frequency. The same arithmetic that materialises the
    /// schedule, exposed so a read model can size a check interval without a
    /// second copy of it.
    public static func rotationsPerDay(route: Route, aircraftID: AircraftID,
                                       state: GameState, spec: AircraftTypeSpec,
                                       ops: OpsTuning) -> Int? {
        let active = route.assignedAircraft.sorted()
            .compactMap { state.aircraft[$0] }.filter(\.isOperational)
        guard let index = active.firstIndex(where: { $0.id == aircraftID }) else { return nil }
        let maximum = roundTripsPerAircraftPerDay(distanceKm: route.distanceKm,
                                                  spec: spec, ops: ops)
        return min(maximum, max(0, (route.dailyRoundTrips + active.count - 1 - index) / active.count))
    }

    /// Block hours that airframe flies per day at those rotations.
    public static func blockHoursPerDay(route: Route, aircraftID: AircraftID,
                                        state: GameState, spec: AircraftTypeSpec,
                                        ops: OpsTuning) -> Double? {
        guard let rotations = rotationsPerDay(route: route, aircraftID: aircraftID,
                                              state: state, spec: spec, ops: ops)
        else { return nil }
        let minutes = flightMinutes(distanceKm: route.distanceKm,
                                    cruiseSpeedKmh: spec.cruiseSpeedKmh,
                                    overheadMinutes: ops.flightOverheadMinutes)
        return Double(rotations * 2) * Double(minutes) / 60
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

    /// The airport each aircraft's latest pending flight lands at, for the
    /// aircraft that have one. Flights in id order and a strict comparison
    /// keep the pick deterministic should two share a departure time.
    static func pendingDestinations(state: GameState) -> [AircraftID: AirportCode] {
        var latest: [AircraftID: Flight] = [:]
        for flightID in state.orderedFlightIDs {
            guard let flight = state.flights[flightID] else { continue }
            if let known = latest[flight.aircraft],
               known.scheduledDeparture > flight.scheduledDeparture { continue }
            latest[flight.aircraft] = flight
        }
        return latest.mapValues { $0.to }
    }

    /// The airframe's own type flies its ferry, to whichever end of the route
    /// is nearer and within its range (the origin on a tie). The ferry used
    /// to take the range and speed of the route's first aircraft, and always
    /// headed for the origin — so an aircraft the destination was within
    /// reach of stayed put, silently, for good.
    private func scheduleFerry(for aircraftID: AircraftID, route: Route,
                               dayStart: SimTime, ops: OpsTuning,
                               state: inout GameState, context: SimContext) {
        let aircraft = state.aircraft[aircraftID]!
        guard let spec = context.catalog.aircraftType(aircraft.typeCode),
              let from = context.catalog.airport(aircraft.location) else { return }
        var nearest: (airport: AirportCode, distanceKm: Int)?
        for end in [route.origin, route.destination] {
            guard let airport = context.catalog.airport(end) else { continue }
            let distance = Geo.distanceKm(from: from.coordinate, to: airport.coordinate)
            guard distance <= spec.rangeKm else { continue }
            if let best = nearest, best.distanceKm <= distance { continue }
            nearest = (end, distance)
        }
        guard let target = nearest else { return } // neither end in range; stays put
        let minutes = Self.flightMinutes(distanceKm: target.distanceKm,
                                         cruiseSpeedKmh: spec.cruiseSpeedKmh,
                                         overheadMinutes: ops.flightOverheadMinutes)
        let id = state.meta.idAllocator.allocateFlightID()
        state.flights[id] = Flight(
            id: id, route: route.id, aircraft: aircraftID, kind: .ferry,
            from: aircraft.location, to: target.airport, distanceKm: target.distanceKm,
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
