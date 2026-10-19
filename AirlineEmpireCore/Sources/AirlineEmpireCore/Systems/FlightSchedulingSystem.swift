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
        // And when each is free again — asked by long-haul routes only, so
        // read once, on the first.
        var freeTimes: [AircraftID: SimTime]?

        for routeID in state.orderedRouteIDs {
            let route = state.routes[routeID]!
            guard let spec = routeAircraftSpec(route, state: state, catalog: context.catalog)
            else { continue }

            let flightMinutes = Self.flightMinutes(distanceKm: route.distanceKm,
                                                   cruiseSpeedKmh: spec.cruiseSpeedKmh,
                                                   overheadMinutes: ops.flightOverheadMinutes)
            // The turnaround flight operations will hold the aircraft for at
            // each end, and the day its crews work: a crew base stretches it.
            let turns = state.turnarounds(spec: spec, on: route,
                                          tuning: context.catalog.tuning.airportServices)
            let window = state.operatingWindow(for: route, catalog: context.catalog)
            let roundTripBlock = 2 * flightMinutes + turns.roundTrip

            // Aircraft able to fly today, in deterministic order.
            var usable: [AircraftID] = []
            for aircraftID in route.assignedAircraft.sorted() {
                guard let aircraft = state.aircraft[aircraftID],
                      Self.fliesToday(aircraft, fleet: context.catalog.tuning.fleet, now: state.clock.now)
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

            // Long haul: a round trip longer than the window flies as one
            // rotation over days rather than back to back inside the day.
            if roundTripBlock > window.minutes {
                let free = freeTimes ?? Self.freeTimes(state: state, catalog: context.catalog)
                freeTimes = free
                scheduleRotations(route: route, usable: usable, flightMinutes: flightMinutes,
                                  turns: turns, window: window, dayStart: dayStart,
                                  pendingEnds: pendingEnds, freeTimes: free,
                                  state: &state, context: context)
                continue
            }

            let capacityPerAircraft = Self.roundTripsPerAircraftPerDay(
                distanceKm: route.distanceKm, spec: spec, ops: ops,
                operatingMinutes: window.minutes, turnaroundMinutes: turns.atDestination,
                returnTurnaroundMinutes: turns.atOrigin)
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
                        window.startMinute + Int64(tripIndex) * roundTripBlock)
                    let (firstFrom, firstTo) = startsAtOrigin
                        ? (route.origin, route.destination)
                        : (route.destination, route.origin)
                    makeFlight(route: route, aircraft: aircraftID, from: firstFrom,
                               to: firstTo, departure: base,
                               flightMinutes: flightMinutes, state: &state)
                    makeFlight(route: route, aircraft: aircraftID, from: firstTo,
                               to: firstFrom,
                               departure: base + .minutes(flightMinutes + turns.at(firstTo, on: route)),
                               flightMinutes: flightMinutes, state: &state)
                }
            }
        }
    }

    /// Long haul (docs/ROUTES.md): a route whose round trip — two legs and
    /// two turns — outlasts the operating window flies as a rotation over
    /// days. A free aircraft leaves at the window's opening, lands when it
    /// lands, turns, and comes back on the first departure the window allows
    /// at the far end: the same evening, or the next morning when it lands in
    /// the night. Departures stay inside the window; arrivals land overnight.
    /// The aircraft completes one round trip every `Rotation.days` days, and
    /// the route starts at most its frequency of rotations a day, first come
    /// first served in aircraft order — so two aircraft on a two-day
    /// rotation give the route a departure every day.
    ///
    /// Both legs are planned when the rotation starts: the return may leave
    /// on a later day, and until it has, the aircraft is busy.
    private func scheduleRotations(route: Route, usable: [AircraftID], flightMinutes: Int64,
                                   turns: RouteTurnarounds, window: OperatingWindow,
                                   dayStart: SimTime, pendingEnds: [AircraftID: AirportCode],
                                   freeTimes: [AircraftID: SimTime],
                                   state: inout GameState, context: SimContext) {
        let catalog = context.catalog
        let cycle = Self.rotation(flightMinutes: flightMinutes, turns: turns, window: window)
        guard cycle.isFlyable else { return }
        let departure = dayStart + .minutes(window.startMinute)
        // An aircraft home a little after the opening — a late return —
        // still takes today's rotation: its legs board when it is ready, as
        // a late short-haul leg does, well inside the expiry. Later than
        // this it waits for tomorrow.
        let latestFree = departure + .minutes(catalog.tuning.ops.scheduledFlightExpiryMinutes / 2)
        var started = 0
        for aircraftID in usable where started < route.dailyRoundTrips {
            guard let aircraft = state.aircraft[aircraftID] else { continue }
            // Where the aircraft will be once its pending legs have flown.
            let startsAt = pendingEnds[aircraftID] ?? aircraft.location
            guard startsAt == route.origin || startsAt == route.destination else { continue }
            // Still away, or not home in time: mid-rotation.
            if let free = freeTimes[aircraftID], free > latestFree { continue }
            // One that would wear down to its check threshold at the far end
            // stays home; `FleetSystem` sends it for the check there. One
            // whose check ends today comes out of it as new.
            let condition = aircraft.status.isInMaintenance ? 1 : aircraft.condition
            guard Self.completesRotation(condition: condition, rotation: cycle,
                                         flightMinutes: flightMinutes, fleet: catalog.tuning.fleet,
                                         ops: catalog.tuning.ops) else { continue }
            let far = startsAt == route.origin ? route.destination : route.origin
            let ready = departure + .minutes(flightMinutes + turns.at(far, on: route))
            makeFlight(route: route, aircraft: aircraftID, from: startsAt, to: far,
                       departure: departure, flightMinutes: flightMinutes, state: &state)
            makeFlight(route: route, aircraft: aircraftID, from: far, to: startsAt,
                       departure: Self.nextDeparture(atOrAfter: ready, in: window),
                       flightMinutes: flightMinutes, state: &state)
            started += 1
        }
    }

    /// How one airframe cycles a route (docs/ROUTES.md).
    public struct Rotation: Equatable, Sendable {
        /// Round trips one cycle flies: back to back inside the window on a
        /// day route, one on a long-haul rotation, none when the route
        /// cannot be flown.
        public let roundTrips: Int
        /// Days one cycle takes: one on a day route; one to
        /// `maxRotationDays` on long haul, whose legs land overnight.
        public let days: Int
        /// One round trip outlasts the operating window: long haul.
        public let isLongHaul: Bool

        public init(roundTrips: Int, days: Int, isLongHaul: Bool) {
            self.roundTrips = roundTrips
            self.days = days
            self.isLongHaul = isLongHaul
        }

        /// A long-haul round trip that would take longer than
        /// `maxRotationDays`: never planned, and refused at assignment.
        public static let unflyable = Rotation(roundTrips: 0, days: 1, isLongHaul: true)

        public var isFlyable: Bool { roundTrips > 0 }
        /// Round trips a day, as a fraction: a two-day rotation is 0.5.
        public var tripsPerDay: Double { Double(roundTrips) / Double(max(1, days)) }
    }

    /// The longest long-haul rotation the scheduler plans. Beyond it an
    /// aircraft would spend most of a week away for one round trip; the
    /// assignment is refused (`route.tooLongForDay`).
    public static let maxRotationDays = 3

    /// How many round trips one airframe of `spec` can fly on a route of this
    /// length back to back inside one operating day — the figure the
    /// materialisation above caps a day route's frequency with. Public so
    /// that a planner (the AI, a screen) can ask "can this route use another
    /// aircraft?" with the scheduler's own arithmetic rather than a second
    /// copy of it.
    ///
    /// Zero when one round trip outlasts the window: long haul, which flies
    /// as a rotation over days (`rotation`) rather than inside the day. The
    /// rivals plan day routes only, on this figure.
    ///
    /// `operatingMinutes` and `turnaroundMinutes` default to the standard day
    /// and the type's turnaround; a crew base and the turnaround programme
    /// change them for one airline (see `rotationsPerDay`).
    /// `returnTurnaroundMinutes` is the turn at the route's other end when it
    /// differs — a dedicated pier at one end.
    public static func roundTripsPerAircraftPerDay(distanceKm: Int, spec: AircraftTypeSpec,
                                                   ops: OpsTuning,
                                                   operatingMinutes: Int64? = nil,
                                                   turnaroundMinutes: Int64? = nil,
                                                   returnTurnaroundMinutes: Int64? = nil) -> Int {
        let flightMinutes = flightMinutes(distanceKm: distanceKm,
                                          cruiseSpeedKmh: spec.cruiseSpeedKmh,
                                          overheadMinutes: ops.flightOverheadMinutes)
        let turnaround = turnaroundMinutes ?? Int64(spec.turnaroundMinutes)
        let roundTripBlock = 2 * flightMinutes + turnaround + (returnTurnaroundMinutes ?? turnaround)
        return max(0, Int((operatingMinutes ?? ops.operatingDayMinutes) / roundTripBlock))
    }

    /// How one airframe of `spec` cycles a route of this length: round trips
    /// back to back inside the window, or — when one round trip outlasts it —
    /// a long-haul rotation of one round trip every few days. The arithmetic
    /// `update` and every estimate share; the defaults are
    /// `roundTripsPerAircraftPerDay`'s.
    public static func rotation(distanceKm: Int, spec: AircraftTypeSpec, ops: OpsTuning,
                                window: OperatingWindow? = nil,
                                turnaroundMinutes: Int64? = nil,
                                returnTurnaroundMinutes: Int64? = nil) -> Rotation {
        let turnaround = turnaroundMinutes ?? Int64(spec.turnaroundMinutes)
        return rotation(
            flightMinutes: flightMinutes(distanceKm: distanceKm, cruiseSpeedKmh: spec.cruiseSpeedKmh,
                                         overheadMinutes: ops.flightOverheadMinutes),
            turns: RouteTurnarounds(atOrigin: returnTurnaroundMinutes ?? turnaround,
                                    atDestination: turnaround),
            window: window ?? .standard(ops))
    }

    /// The rotation `spec` flies on `route` for the route's operator: the
    /// route's operating window and the turn at each end, as `update` plans
    /// them.
    public static func rotation(spec: AircraftTypeSpec, on route: Route,
                                state: GameState, catalog: ContentCatalog) -> Rotation {
        rotation(flightMinutes: flightMinutes(distanceKm: route.distanceKm,
                                              cruiseSpeedKmh: spec.cruiseSpeedKmh,
                                              overheadMinutes: catalog.tuning.ops.flightOverheadMinutes),
                 turns: state.turnarounds(spec: spec, on: route, tuning: catalog.tuning.airportServices),
                 window: state.operatingWindow(for: route, catalog: catalog))
    }

    /// A long-haul rotation is timed from the origin: out at the window's
    /// opening, back on the first departure the window allows after the turn
    /// at the far end, and out again at the first opening after the turn at
    /// home. Its days are the days between the two openings.
    static func rotation(flightMinutes: Int64, turns: RouteTurnarounds,
                         window: OperatingWindow) -> Rotation {
        let block = 2 * flightMinutes + turns.roundTrip
        guard block > window.minutes else {
            return Rotation(roundTrips: Int(window.minutes / max(1, block)), days: 1, isLongHaul: false)
        }
        let leaves = SimTime(rawMinutes: window.startMinute)
        let back = nextDeparture(atOrAfter: leaves + .minutes(flightMinutes + turns.atDestination),
                                 in: window)
        let home = back + .minutes(flightMinutes + turns.atOrigin)
        let span = (home - leaves).minutes
        let days = Int((span + GameCalendar.minutesPerDay - 1) / GameCalendar.minutesPerDay)
        guard days <= maxRotationDays else { return .unflyable }
        return Rotation(roundTrips: 1, days: max(1, days), isLongHaul: true)
    }

    /// The first moment at or after `time` a departure may leave: `time`
    /// itself inside an operating window — the one that opened the day
    /// before too, when a crew base runs it past midnight — else the next
    /// opening.
    static func nextDeparture(atOrAfter time: SimTime, in window: OperatingWindow) -> SimTime {
        let day = time.dayIndex
        for opening in [day - 1, day].map({ $0 * GameCalendar.minutesPerDay + window.startMinute })
        where time.rawMinutes >= opening && time.rawMinutes < opening + window.minutes {
            return time
        }
        let opening = day * GameCalendar.minutesPerDay + window.startMinute
        return SimTime(rawMinutes: time.rawMinutes < opening ? opening : opening + GameCalendar.minutesPerDay)
    }

    /// Minutes one round trip of `spec` on `route` holds an airframe for the
    /// route's operator: two legs and the turn at each end — the block the
    /// materialisation above plans each day-route rotation in.
    public static func roundTripMinutes(spec: AircraftTypeSpec, on route: Route,
                                        state: GameState, catalog: ContentCatalog) -> Int64 {
        let minutes = flightMinutes(distanceKm: route.distanceKm,
                                    cruiseSpeedKmh: spec.cruiseSpeedKmh,
                                    overheadMinutes: catalog.tuning.ops.flightOverheadMinutes)
        return 2 * minutes + state.turnarounds(spec: spec, on: route,
                                               tuning: catalog.tuning.airportServices).roundTrip
    }

    /// Round trips one airframe of `spec` could fly back to back on `route`
    /// in a day for the route's operator: the route's own operating window (a
    /// crew base lengthens it) and the turn at each end, as `update` plans
    /// them.
    ///
    /// Zero on long haul, which `rotation(spec:on:state:catalog:)` times
    /// instead: the rivals, who plan day routes only, ask this.
    public static func roundTripsPerDay(spec: AircraftTypeSpec, on route: Route,
                                        state: GameState, catalog: ContentCatalog) -> Int {
        let turns = state.turnarounds(spec: spec, on: route, tuning: catalog.tuning.airportServices)
        return roundTripsPerAircraftPerDay(
            distanceKm: route.distanceKm, spec: spec, ops: catalog.tuning.ops,
            operatingMinutes: state.operatingWindow(for: route, catalog: catalog).minutes,
            turnaroundMinutes: turns.atDestination, returnTurnaroundMinutes: turns.atOrigin)
    }

    /// Round trips per day a route's assigned airframes can fly at most,
    /// whatever its frequency: every assigned airframe not still on order,
    /// at `update`'s per-aircraft capacity — timed, as `update` times it, by
    /// the route's first assigned aircraft's type in the route's operating
    /// window. Zero with nothing assigned, and on long haul
    /// (`rotationCapacityPerDay` has the fraction).
    public static func rotationCapacity(route: Route, state: GameState,
                                        catalog: ContentCatalog) -> Int {
        let assigned = route.assignedAircraft.sorted().compactMap { state.aircraft[$0] }
        guard let first = assigned.first,
              let spec = catalog.aircraftType(first.typeCode) else { return 0 }
        let airframes = assigned.filter { !$0.status.isOnOrder }.count
        return roundTripsPerDay(spec: spec, on: route, state: state, catalog: catalog) * airframes
    }

    /// The round trips a route actually offers a day: its frequency, capped
    /// by what its airframes can rotate (`rotationCapacity`) — the same cap
    /// `update` materialises the day with. Zero on long haul;
    /// `flyableTripsPerDay` is the figure for every route.
    public static func flyableRoundTrips(route: Route, state: GameState,
                                         catalog: ContentCatalog) -> Int {
        min(route.dailyRoundTrips, rotationCapacity(route: route, state: state, catalog: catalog))
    }

    /// Round trips a day a route's airframes can fly at most, as a fraction:
    /// `rotationCapacity` on a day route; on long haul each airframe flies
    /// one round trip a rotation, so two aircraft on a two-day rotation fly
    /// one a day. Zero with nothing assigned.
    public static func rotationCapacityPerDay(route: Route, state: GameState,
                                              catalog: ContentCatalog) -> Double {
        let assigned = route.assignedAircraft.sorted().compactMap { state.aircraft[$0] }
        guard let first = assigned.first,
              let spec = catalog.aircraftType(first.typeCode) else { return 0 }
        let cycle = Self.rotation(spec: spec, on: route, state: state, catalog: catalog)
        guard cycle.isLongHaul else {
            return Double(rotationCapacity(route: route, state: state, catalog: catalog))
        }
        return cycle.tripsPerDay * Double(assigned.filter { !$0.status.isOnOrder }.count)
    }

    /// The round trips a route actually offers a day, as a fraction: its
    /// frequency capped by `rotationCapacityPerDay`. Exactly
    /// `flyableRoundTrips` on a day route; a long-haul route flown by one
    /// aircraft on a two-day rotation offers half a round trip a day.
    ///
    /// The demand engine prices a route's schedule with this. It used the
    /// requested frequency, so twenty round trips asked of one aeroplane
    /// that can fly three bought the schedule quality of twenty — while
    /// flying three and holding the slots of twenty.
    public static func flyableTripsPerDay(route: Route, state: GameState,
                                          catalog: ContentCatalog) -> Double {
        min(Double(route.dailyRoundTrips),
            rotationCapacityPerDay(route: route, state: state, catalog: catalog))
    }

    /// Days of one direction's demand a departure on this route sells: one
    /// on a route flown every day; on long haul flown less than daily, the
    /// days between departures — passengers bound for a day without one take
    /// the next, so one aircraft on a two-day rotation sells two days' worth
    /// a departure, seats permitting. What makes the estimates' seats a day
    /// (`flyableTripsPerDay` × 2 × seats) the seats flight operations sells.
    public static func demandDaysPerDeparture(route: Route, state: GameState,
                                              catalog: ContentCatalog) -> Double {
        let trips = flyableTripsPerDay(route: route, state: state, catalog: catalog)
        return trips > 0 && trips < 1 ? 1 / trips : 1
    }

    /// Whether the aircraft will be airworthy when today's flying starts.
    /// `FleetSystem` runs after the scheduler on the same tick: an aircraft
    /// whose check finishes today flies today, and one whose wear will send
    /// it to the hangar today gets no flights — scheduling it left a day of
    /// legs that could not board and expired as cancellations.
    public static func fliesToday(_ aircraft: Aircraft, fleet: FleetTuning, now: SimTime) -> Bool {
        switch aircraft.status {
        case .active:
            return max(0, aircraft.condition - fleet.dailyConditionDecay) >= fleet.maintenanceConditionThreshold
        case .inMaintenance(let until):
            return until <= now
        case .ordered:
            return false
        }
    }

    /// Whether an airframe at `condition` flies a whole long-haul rotation
    /// and comes home at or above the check threshold: the rotation's days
    /// of decay and both legs' wear (docs/AIRCRAFT.md). The scheduler starts
    /// no rotation that would leave the aircraft due for its check at the far
    /// end, and `FleetSystem` sends one that cannot fly another for its check
    /// at home.
    public static func completesRotation(condition: Double, rotation: Rotation, flightMinutes: Int64,
                                         fleet: FleetTuning, ops: OpsTuning) -> Bool {
        let wear = Double(rotation.days) * fleet.dailyConditionDecay
            + 2 * Double(flightMinutes) / 60 * ops.wearPerFlightHour
        return condition - wear >= fleet.maintenanceConditionThreshold
    }

    /// Round trips the scheduler allots one airframe on a route: the type's
    /// daily maximum, capped by the aircraft's even share of the route's
    /// requested frequency. Zero on long haul — `tripsPerDay` has the
    /// fraction. The same arithmetic that materialises the schedule, exposed
    /// so a read model can size a check interval without a second copy of it.
    public static func rotationsPerDay(route: Route, aircraftID: AircraftID,
                                       state: GameState, spec: AircraftTypeSpec,
                                       ops: OpsTuning,
                                       facilities: AirportFacilityTuning = .standard) -> Int? {
        let active = route.assignedAircraft.sorted()
            .compactMap { state.aircraft[$0] }.filter(\.isOperational)
        guard let index = active.firstIndex(where: { $0.id == aircraftID }) else { return nil }
        let turns = state.turnarounds(spec: spec, on: route, tuning: facilities)
        let maximum = roundTripsPerAircraftPerDay(
            distanceKm: route.distanceKm, spec: spec, ops: ops,
            operatingMinutes: state.hasCrewBase(on: route)
                ? OperatingWindow.withCrewBase(ops, tuning: facilities).minutes : nil,
            turnaroundMinutes: turns.atDestination, returnTurnaroundMinutes: turns.atOrigin)
        return min(maximum, max(0, (route.dailyRoundTrips + active.count - 1 - index) / active.count))
    }

    /// Round trips a day the scheduler gives one airframe on a route, as a
    /// fraction: `rotationsPerDay` on a day route; on long haul one round
    /// trip a rotation for as many airframes — in aircraft order, as
    /// `update` starts them — as the route's frequency takes, and none for
    /// the rest.
    public static func tripsPerDay(route: Route, aircraftID: AircraftID,
                                   state: GameState, spec: AircraftTypeSpec,
                                   ops: OpsTuning,
                                   facilities: AirportFacilityTuning = .standard) -> Double? {
        let active = route.assignedAircraft.sorted()
            .compactMap { state.aircraft[$0] }.filter(\.isOperational)
        guard let index = active.firstIndex(where: { $0.id == aircraftID }),
              let rotations = rotationsPerDay(route: route, aircraftID: aircraftID, state: state,
                                              spec: spec, ops: ops, facilities: facilities)
        else { return nil }
        let window: OperatingWindow = state.hasCrewBase(on: route)
            ? .withCrewBase(ops, tuning: facilities) : .standard(ops)
        let cycle = Self.rotation(
            flightMinutes: flightMinutes(distanceKm: route.distanceKm, cruiseSpeedKmh: spec.cruiseSpeedKmh,
                                         overheadMinutes: ops.flightOverheadMinutes),
            turns: state.turnarounds(spec: spec, on: route, tuning: facilities), window: window)
        guard cycle.isLongHaul else { return Double(rotations) }
        let each = cycle.tripsPerDay
        return min(each, max(0, Double(route.dailyRoundTrips) - Double(index) * each))
    }

    /// Block hours that airframe flies per day at those round trips.
    public static func blockHoursPerDay(route: Route, aircraftID: AircraftID,
                                        state: GameState, spec: AircraftTypeSpec,
                                        ops: OpsTuning,
                                        facilities: AirportFacilityTuning = .standard) -> Double? {
        guard let trips = tripsPerDay(route: route, aircraftID: aircraftID,
                                      state: state, spec: spec, ops: ops,
                                      facilities: facilities)
        else { return nil }
        let minutes = flightMinutes(distanceKm: route.distanceKm,
                                    cruiseSpeedKmh: spec.cruiseSpeedKmh,
                                    overheadMinutes: ops.flightOverheadMinutes)
        return trips * 2 * Double(minutes) / 60
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

    /// When each aircraft with pending legs is next free: the end of the turn
    /// after its last one, a flying leg timed from its actual departure and
    /// the rest from their planned one. The latest of an aircraft's legs
    /// whatever order they are read in, so the pick is deterministic.
    static func freeTimes(state: GameState, catalog: ContentCatalog) -> [AircraftID: SimTime] {
        var free: [AircraftID: SimTime] = [:]
        for flight in state.flights.values {
            guard let aircraft = state.aircraft[flight.aircraft],
                  let spec = catalog.aircraftType(aircraft.typeCode) else { continue }
            let turn = state.turnaroundMinutes(spec: spec, airline: aircraft.owner, at: flight.to,
                                               tuning: catalog.tuning.airportServices)
            let end: SimTime
            switch flight.phase {
            case .scheduled, .boarding:
                end = flight.departureTime + .minutes(flight.flightMinutes + turn)
            case .enRoute(let departed):
                end = departed + .minutes(flight.flightMinutes + turn)
            case .turnaround(let until):
                end = until
            }
            if let known = free[flight.aircraft], known >= end { continue }
            free[flight.aircraft] = end
        }
        return free
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

extension GameState {
    /// The long-haul rotation an aircraft's route flies — timed as the
    /// scheduler times it, by the route's first assigned aircraft — with the
    /// minutes of each leg; nil on a day route or off route.
    public func longHaulRotation(of aircraft: Aircraft, catalog: ContentCatalog)
        -> (rotation: FlightSchedulingSystem.Rotation, flightMinutes: Int64)? {
        guard let routeID = aircraft.assignedRoute, let route = routes[routeID],
              let first = route.assignedAircraft.sorted().compactMap({ self.aircraft[$0] }).first,
              let spec = catalog.aircraftType(first.typeCode) else { return nil }
        let rotation = FlightSchedulingSystem.rotation(spec: spec, on: route, state: self, catalog: catalog)
        guard rotation.isLongHaul else { return nil }
        return (rotation, FlightSchedulingSystem.flightMinutes(
            distanceKm: route.distanceKm, cruiseSpeedKmh: spec.cruiseSpeedKmh,
            overheadMinutes: catalog.tuning.ops.flightOverheadMinutes))
    }

    /// Whether the aircraft has a leg still to leave, planned or boarding —
    /// on long haul, a rotation it is still away on.
    public func hasLegsAhead(_ aircraftID: AircraftID) -> Bool {
        flights.values.contains {
            $0.aircraft == aircraftID && ($0.phase == .scheduled || $0.phase == .boarding)
        }
    }
}
