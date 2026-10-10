/// Daily: opens the buildings whose construction is done and records the hub
/// statuses airlines have earned (docs/HUB_PROGRESSION_PLAN.md §3, §7).
///
/// Runs before the scheduler, so a crew base or hangar that opens today
/// shapes today's flying and today's checks.
public struct FacilityConstructionSystem: SimulationSystem {
    public let id = "facilityConstruction"
    public let cadence = Cadence.daily

    public init() {}

    public func update(state: inout GameState, context: SimContext) {
        for airlineID in state.orderedAirlineIDs {
            guard var airline = state.airlines[airlineID], airline.status == .active else { continue }
            let player = airline.kind == .player
            var opened: [FacilityConstruction] = []
            if let builds = airline.facilityConstructions {
                var pending: [FacilityConstruction] = []
                for build in builds {
                    if build.completesAt <= context.current { opened.append(build) } else { pending.append(build) }
                }
                for build in opened {
                    var stations = airline.airportFacilities ?? [:]
                    let installed = airline.facilities(at: build.airport)
                    let level = max(build.level, build.service.level(in: installed))
                    stations[build.airport] = build.service.setting(level, in: installed)
                    airline.airportFacilities = stations
                }
                airline.facilityConstructions = pending.isEmpty ? nil : pending
            }
            state.airlines[airlineID] = airline
            for build in opened {
                context.emit(.facilityOpened(airline: airlineID, airport: build.airport,
                                             service: build.service, level: build.level))
                if player {
                    state.progression.note(.facilityOpened(build.airport, build.service, level: build.level),
                                           at: context.current)
                }
            }
            assessHubStatuses(airlineID, state: &state, context: context)
        }
    }

    /// Records each status the airline has newly earned. The first
    /// assessment of an airline (a new game, or a save from before statuses)
    /// takes what is already earned as given, without fanfare.
    private func assessHubStatuses(_ airlineID: AirlineID, state: inout GameState, context: SimContext) {
        guard let airline = state.airlines[airlineID] else { return }
        let first = airline.hubStatuses == nil
        var statuses = airline.hubStatuses ?? [:]
        var raised: [(AirportCode, HubStatus)] = []
        for airport in Self.presence(of: airline, state: state) {
            let earned = state.earnedHubStatus(at: airport, airline: airlineID)
            let recorded = statuses[airport] ?? .station
            guard earned > recorded else { continue }
            statuses[airport] = earned
            if !first { raised.append((airport, earned)) }
        }
        guard first || !raised.isEmpty else { return }
        state.airlines[airlineID]?.hubStatuses = statuses
        for (airport, status) in raised {
            context.emit(.hubStatusRaised(airline: airlineID, airport: airport, status: status))
            if airline.kind == .player {
                state.progression.note(.hubStatus(airport, status), at: context.current)
            }
        }
    }

    /// Airports where the airline is at home, flies, or has built, sorted.
    static func presence(of airline: Airline, state: GameState) -> [AirportCode] {
        var airports: Set<AirportCode> = [airline.homeAirport]
        for route in state.routes(of: airline.id) {
            airports.insert(route.origin); airports.insert(route.destination)
        }
        airports.formUnion((airline.airportFacilities ?? [:]).keys)
        return airports.sorted()
    }

    /// Opens everything under construction at once. For tests that are about
    /// what a building does, not how long it takes.
    static func openAll(_ state: inout GameState) {
        for id in state.orderedAirlineIDs {
            guard var airline = state.airlines[id], let builds = airline.facilityConstructions else { continue }
            for build in builds {
                var stations = airline.airportFacilities ?? [:]
                stations[build.airport] = build.service.setting(build.level, in: airline.facilities(at: build.airport))
                airline.airportFacilities = stations
            }
            airline.facilityConstructions = nil
            state.airlines[id] = airline
        }
    }
}

// MARK: - What the buildings change

/// The part of the day an aircraft's rotations are planned in.
public struct OperatingWindow: Equatable, Sendable {
    /// Minute of the day the first departure leaves.
    public let startMinute: Int64
    public let minutes: Int64
    public var endMinute: Int64 { startMinute + minutes }

    public static func standard(_ ops: OpsTuning) -> Self {
        Self(startMinute: ops.operatingDayStartMinute, minutes: ops.operatingDayMinutes)
    }
    /// Crews based at the route's end start earlier and stay later.
    public static func withCrewBase(_ ops: OpsTuning, tuning: AirportFacilityTuning) -> Self {
        Self(startMinute: max(0, ops.operatingDayStartMinute - tuning.crewBaseEarlierStartMinutes),
             minutes: ops.operatingDayMinutes + tuning.crewBaseExtraMinutes)
    }
}

extension GameState {
    /// Whether the route's operator has a crew base open at either end.
    public func hasCrewBase(on route: Route) -> Bool {
        guard let owner = airlines[route.airline] else { return false }
        return owner.facilities(at: route.origin).crewBase > 0
            || owner.facilities(at: route.destination).crewBase > 0
    }

    public func operatingWindow(for route: Route, catalog: ContentCatalog) -> OperatingWindow {
        let ops = catalog.tuning.ops
        return hasCrewBase(on: route)
            ? .withCrewBase(ops, tuning: catalog.tuning.airportServices)
            : .standard(ops)
    }

    /// Crew cost multiplier on a route's flights.
    public func crewCostFactor(on route: Route, catalog: ContentCatalog) -> Double {
        hasCrewBase(on: route) ? catalog.tuning.airportServices.crewBaseCrewCostFactor : 1
    }

    /// Minutes an aircraft of `spec` spends on the ground between legs for
    /// this airline. The scheduler and flight operations share it, so a
    /// faster turnaround is a rotation the scheduler can plan.
    public func turnaroundMinutes(spec: AircraftTypeSpec, airline: AirlineID) -> Int64 {
        var minutes = Int64(spec.turnaroundMinutes)
        if isPlayer(airline), playerHasCapability(.efficientTurnarounds) {
            minutes = Int64((Double(minutes) * 0.85).rounded())
        }
        return minutes
    }

    /// The best hangar the owner has where this aircraft flies: either end of
    /// its route, or where it stands when unassigned.
    public func hangarLevel(serving aircraft: Aircraft) -> Int {
        guard let owner = airlines[aircraft.owner] else { return 0 }
        var airports = [aircraft.location]
        if let routeID = aircraft.assignedRoute, let route = routes[routeID] {
            airports = [route.origin, route.destination]
        }
        return airports.map { owner.facilities(at: $0).hangar }.max() ?? 0
    }
}
