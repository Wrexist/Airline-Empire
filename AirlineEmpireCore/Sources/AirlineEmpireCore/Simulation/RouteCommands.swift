/// Route commands (Phase 6). Slot allocations happen here — a route holds
/// its movements from opening until closing, so congested airports are a
/// real strategic constraint, not a scheduling afterthought.

public struct OpenRouteCommand: Command, Equatable {
    public static let name = "openRoute"

    public let airline: AirlineID
    public let origin: AirportCode
    public let destination: AirportCode
    public let dailyRoundTrips: Int
    public let ticketPrice: Money

    public init(airline: AirlineID, origin: AirportCode, destination: AirportCode,
                dailyRoundTrips: Int, ticketPrice: Money) {
        self.airline = airline
        self.origin = origin
        self.destination = destination
        self.dailyRoundTrips = dailyRoundTrips
        self.ticketPrice = ticketPrice
    }

    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard state.airlines[airline] != nil else {
            return CommandRejection(code: "route.unknownAirline", message: "Unknown airline")
        }
        guard let originSpec = catalog.airport(origin) else {
            return CommandRejection(code: "route.unknownAirport",
                                    message: "Unknown airport \(origin)")
        }
        guard let destSpec = catalog.airport(destination) else {
            return CommandRejection(code: "route.unknownAirport",
                                    message: "Unknown airport \(destination)")
        }
        if origin == destination {
            return CommandRejection(code: "route.sameAirport",
                                    message: "A route needs two different airports")
        }
        let distance = Geo.distanceKm(from: originSpec.coordinate, to: destSpec.coordinate)
        if distance < catalog.tuning.minRouteDistanceKm {
            return CommandRejection(code: "route.tooShort",
                                    message: "\(distance) km is ground-transport territory")
        }
        if state.routes.values.contains(where: {
            $0.airline == airline && $0.sameMarket(origin: origin, destination: destination)
        }) {
            return CommandRejection(code: "route.duplicate",
                                    message: "You already serve this city pair")
        }
        if !(1...20).contains(dailyRoundTrips) {
            return CommandRejection(code: "route.badFrequency",
                                    message: "Frequency must be 1–20 round trips per day")
        }
        if ticketPrice <= .zero {
            return CommandRejection(code: "route.badPrice",
                                    message: "Ticket price must be positive")
        }
        let movements = Route.dailySlotMovements(roundTrips: dailyRoundTrips)
        if state.world.slotsUsed(at: origin) + movements > originSpec.slotCapacityPerDay {
            return CommandRejection(code: "route.noSlots",
                                    message: "\(origin) has no free slots for this frequency")
        }
        if state.world.slotsUsed(at: destination) + movements > destSpec.slotCapacityPerDay {
            return CommandRejection(code: "route.noSlots",
                                    message: "\(destination) has no free slots for this frequency")
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        let originSpec = context.catalog.airport(origin)!
        let destSpec = context.catalog.airport(destination)!
        let movements = Route.dailySlotMovements(roundTrips: dailyRoundTrips)
        let originError = state.world.allocateSlots(
            airline: airline, airport: origin, count: movements,
            capacityPerDay: originSpec.slotCapacityPerDay)
        let destError = state.world.allocateSlots(
            airline: airline, airport: destination, count: movements,
            capacityPerDay: destSpec.slotCapacityPerDay)
        precondition(originError == nil && destError == nil, "Validated slot availability")

        let id = state.meta.idAllocator.allocateRouteID()
        state.routes[id] = Route(
            id: id, airline: airline, origin: origin, destination: destination,
            distanceKm: Geo.distanceKm(from: originSpec.coordinate, to: destSpec.coordinate),
            dailyRoundTrips: dailyRoundTrips, ticketPrice: ticketPrice)
        context.emit(.routeOpened(id: id, origin: origin, destination: destination))
        state.world.recordMarketMove(MarketMove(
            at: state.clock.now, airline: airline, origin: origin,
            destination: destination, kind: .entered))
        context.emit(.marketEntered(airline: airline, origin: origin,
                                    destination: destination))
    }
}

public struct CloseRouteCommand: Command, Equatable {
    public static let name = "closeRoute"

    public let airline: AirlineID
    public let route: RouteID

    public init(airline: AirlineID, route: RouteID) {
        self.airline = airline
        self.route = route
    }

    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard let r = state.routes[route], r.airline == airline else {
            return CommandRejection(code: "route.notYours", message: "No such route")
        }
        // Airborne aircraft must land first; ground phases cancel cleanly.
        let airborne = state.flights.values.contains { flight in
            guard flight.route == route else { return false }
            if case .enRoute = flight.phase { return true }
            return false
        }
        if airborne {
            return CommandRejection(code: "route.flightsAirborne",
                                    message: "Wait for airborne flights to land before closing")
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        let r = state.routes[route]!
        // Cancel not-yet-departed flights (scheduled/boarding/turnaround).
        for flightID in state.orderedFlightIDs {
            guard let flight = state.flights[flightID], flight.route == route else { continue }
            if var aircraft = state.aircraft[flight.aircraft], aircraft.activeFlight == flightID {
                aircraft.activeFlight = nil
                state.aircraft[flight.aircraft] = aircraft
            }
            state.flights[flightID] = nil
        }
        for aircraftID in r.assignedAircraft {
            if var aircraft = state.aircraft[aircraftID] {
                aircraft.assignedRoute = nil
                state.aircraft[aircraftID] = aircraft
            }
        }
        let movements = Route.dailySlotMovements(roundTrips: r.dailyRoundTrips)
        _ = state.world.releaseSlots(airline: airline, airport: r.origin, count: movements)
        _ = state.world.releaseSlots(airline: airline, airport: r.destination, count: movements)
        state.routes[route] = nil
        context.emit(.routeClosed(id: route))
        state.world.recordMarketMove(MarketMove(
            at: state.clock.now, airline: airline, origin: r.origin,
            destination: r.destination, kind: .left))
        context.emit(.marketLeft(airline: airline, origin: r.origin,
                                 destination: r.destination))
    }
}

public struct SetRoutePriceCommand: Command, Equatable {
    public static let name = "setRoutePrice"

    public let airline: AirlineID
    public let route: RouteID
    public let ticketPrice: Money

    public init(airline: AirlineID, route: RouteID, ticketPrice: Money) {
        self.airline = airline
        self.route = route
        self.ticketPrice = ticketPrice
    }

    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard let r = state.routes[route], r.airline == airline else {
            return CommandRejection(code: "route.notYours", message: "No such route")
        }
        if ticketPrice <= .zero {
            return CommandRejection(code: "route.badPrice",
                                    message: "Ticket price must be positive")
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        state.routes[route]!.ticketPrice = ticketPrice
    }
}

public struct SetRouteFrequencyCommand: Command, Equatable {
    public static let name = "setRouteFrequency"

    public let airline: AirlineID
    public let route: RouteID
    public let dailyRoundTrips: Int

    public init(airline: AirlineID, route: RouteID, dailyRoundTrips: Int) {
        self.airline = airline
        self.route = route
        self.dailyRoundTrips = dailyRoundTrips
    }

    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard let r = state.routes[route], r.airline == airline else {
            return CommandRejection(code: "route.notYours", message: "No such route")
        }
        if !(1...20).contains(dailyRoundTrips) {
            return CommandRejection(code: "route.badFrequency",
                                    message: "Frequency must be 1–20 round trips per day")
        }
        let delta = Route.dailySlotMovements(roundTrips: dailyRoundTrips)
            - Route.dailySlotMovements(roundTrips: r.dailyRoundTrips)
        if delta > 0 {
            let originSpec = catalog.airport(r.origin)!
            let destSpec = catalog.airport(r.destination)!
            if state.world.slotsUsed(at: r.origin) + delta > originSpec.slotCapacityPerDay
                || state.world.slotsUsed(at: r.destination) + delta > destSpec.slotCapacityPerDay {
                return CommandRejection(code: "route.noSlots",
                                        message: "No free slots for the added frequency")
            }
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        var r = state.routes[route]!
        let delta = Route.dailySlotMovements(roundTrips: dailyRoundTrips)
            - Route.dailySlotMovements(roundTrips: r.dailyRoundTrips)
        if delta > 0 {
            let originSpec = context.catalog.airport(r.origin)!
            let destSpec = context.catalog.airport(r.destination)!
            _ = state.world.allocateSlots(airline: airline, airport: r.origin,
                                          count: delta,
                                          capacityPerDay: originSpec.slotCapacityPerDay)
            _ = state.world.allocateSlots(airline: airline, airport: r.destination,
                                          count: delta,
                                          capacityPerDay: destSpec.slotCapacityPerDay)
        } else if delta < 0 {
            _ = state.world.releaseSlots(airline: airline, airport: r.origin, count: -delta)
            _ = state.world.releaseSlots(airline: airline, airport: r.destination, count: -delta)
        }
        r.dailyRoundTrips = dailyRoundTrips
        state.routes[route] = r
    }
}

public struct AssignAircraftToRouteCommand: Command, Equatable {
    public static let name = "assignAircraftToRoute"

    public let airline: AirlineID
    public let route: RouteID
    public let aircraftID: AircraftID

    public init(airline: AirlineID, route: RouteID, aircraftID: AircraftID) {
        self.airline = airline
        self.route = route
        self.aircraftID = aircraftID
    }

    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard let r = state.routes[route], r.airline == airline else {
            return CommandRejection(code: "route.notYours", message: "No such route")
        }
        guard let aircraft = state.aircraft[aircraftID], aircraft.owner == airline else {
            return CommandRejection(code: "fleet.notYourAircraft",
                                    message: "No such aircraft in your fleet")
        }
        if aircraft.assignedRoute != nil {
            return CommandRejection(code: "fleet.alreadyAssigned",
                                    message: "Aircraft already serves a route")
        }
        if case .ordered = aircraft.status {
            return CommandRejection(code: "fleet.notDelivered",
                                    message: "Aircraft has not been delivered yet")
        }
        let spec = catalog.aircraftType(aircraft.typeCode)!
        if r.distanceKm > spec.rangeKm {
            return CommandRejection(code: "route.beyondRange",
                                    message: "\(spec.model) range \(spec.rangeKm) km < route \(r.distanceKm) km")
        }
        for end in [r.origin, r.destination] {
            if catalog.airport(end)!.runwayClass < spec.runwayRequirement {
                return CommandRejection(code: "route.runwayTooSmall",
                                        message: "\(end) cannot handle a \(spec.model)")
            }
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        var r = state.routes[route]!
        var aircraft = state.aircraft[aircraftID]!
        aircraft.assignedRoute = route
        state.aircraft[aircraftID] = aircraft
        r.assignedAircraft = (r.assignedAircraft + [aircraftID]).sorted()
        state.routes[route] = r
        context.emit(.aircraftAssigned(aircraft: aircraftID, route: route))
    }
}

public struct UnassignAircraftCommand: Command, Equatable {
    public static let name = "unassignAircraft"

    public let airline: AirlineID
    public let aircraftID: AircraftID

    public init(airline: AirlineID, aircraftID: AircraftID) {
        self.airline = airline
        self.aircraftID = aircraftID
    }

    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard let aircraft = state.aircraft[aircraftID], aircraft.owner == airline else {
            return CommandRejection(code: "fleet.notYourAircraft",
                                    message: "No such aircraft in your fleet")
        }
        guard aircraft.assignedRoute != nil else {
            return CommandRejection(code: "fleet.notAssigned",
                                    message: "Aircraft is not serving a route")
        }
        if aircraft.activeFlight != nil {
            return CommandRejection(code: "fleet.inFlight",
                                    message: "Wait for the current flight to finish")
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        var aircraft = state.aircraft[aircraftID]!
        let routeID = aircraft.assignedRoute!
        aircraft.assignedRoute = nil
        state.aircraft[aircraftID] = aircraft
        if var r = state.routes[routeID] {
            r.assignedAircraft.removeAll { $0 == aircraftID }
            state.routes[routeID] = r
        }
        // Remove this aircraft's not-yet-active flights on the route.
        for flightID in state.orderedFlightIDs {
            guard let flight = state.flights[flightID],
                  flight.aircraft == aircraftID, flight.phase == .scheduled else { continue }
            state.flights[flightID] = nil
        }
        context.emit(.aircraftUnassigned(aircraft: aircraftID, route: routeID))
    }
}
