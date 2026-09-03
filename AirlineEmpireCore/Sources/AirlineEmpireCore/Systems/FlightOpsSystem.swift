/// Per-tick flight state machine (docs/ROUTES.md):
/// scheduled → boarding → enRoute → turnaround → removed.
/// The simulation drives every transition — no UI timers, ever.
public struct FlightOpsSystem: SimulationSystem {
    public let id = "flightOps"
    public let cadence = Cadence.everyTick

    public init() {}

    public func update(state: inout GameState, context: SimContext) {
        let ops = context.catalog.tuning.ops
        let now = context.current

        for flightID in state.orderedFlightIDs {
            guard var flight = state.flights[flightID] else { continue }
            guard var aircraft = state.aircraft[flight.aircraft] else { continue }

            switch flight.phase {
            case .scheduled:
                // A flight that could not board (grounded/busy airframe)
                // expires as a cancellation — no stale-flight pileups.
                if now >= flight.departureTime + .minutes(ops.scheduledFlightExpiryMinutes) {
                    cancel(flightID, flight: flight, aircraft: &aircraft,
                           state: &state, context: context)
                    state.aircraft[flight.aircraft] = aircraft
                    continue
                }
                // Boarding starts when it's time AND the airframe is free
                // and airworthy AND the world permits it (closed airports
                // and struck airlines board nothing; expiry cancels).
                let boardingStart = flight.departureTime + .minutes(-ops.boardingMinutes)
                let worldBlocks = state.world.isAirportClosed(flight.from, at: now)
                    || state.world.isAirportClosed(flight.to, at: now)
                    || state.world.strikeActive(for: aircraft.owner, at: now)
                if now >= boardingStart, aircraft.isReadyToFly, !worldBlocks,
                   aircraft.location == flight.from {
                    flight.phase = .boarding
                    aircraft.activeFlight = flightID
                    if flight.kind == .revenue, var route = state.routes[flight.route] {
                        // Sell from today's remaining directional demand.
                        let spec = context.catalog.aircraftType(aircraft.typeCode)!
                        let outbound = flight.from == route.origin
                        let remaining = outbound ? route.remainingOutboundToday
                                                 : route.remainingInboundToday
                        let sold = min(spec.seats, max(0, remaining))
                        flight.passengers = sold
                        if outbound {
                            route.remainingOutboundToday = remaining - sold
                        } else {
                            route.remainingInboundToday = remaining - sold
                        }
                        state.routes[flight.route] = route
                    }
                }

            case .boarding:
                if now >= flight.departureTime {
                    let spec = context.catalog.aircraftType(aircraft.typeCode)!
                    let reliability = aircraft.currentReliability(
                        type: spec, tuning: context.catalog.tuning.fleet)
                    var disruptionProbability = 1 - reliability
                    if state.isPlayer(aircraft.owner),
                       state.playerHasCapability(.networkOpsCenter) {
                        disruptionProbability *= 0.8
                    }
                    // Active storms over either endpoint raise disruption.
                    for endpoint in [flight.from, flight.to] {
                        if let airport = context.catalog.airport(endpoint),
                           let storm = state.world.activeStorm(in: airport.region, at: now) {
                            disruptionProbability += context.catalog.tuning.events
                                .stormDisruptionBoost * storm
                        }
                    }
                    disruptionProbability = min(0.95, disruptionProbability)
                    if state.rng.chance("flightOps.dispatch", probability: disruptionProbability) {
                        if state.rng.chance("flightOps.cancel",
                                            probability: ops.cancellationShareOfDisruptions) {
                            cancel(flightID, flight: flight, aircraft: &aircraft,
                                   state: &state, context: context)
                            state.aircraft[flight.aircraft] = aircraft
                            continue
                        } else {
                            let delay = Int64(state.rng.int(
                                "flightOps.delay",
                                in: ops.delayMinutesMin...ops.delayMinutesMax))
                            flight.departureTime = flight.departureTime + .minutes(delay)
                            if !flight.wasDelayed {
                                flight.wasDelayed = true
                                context.emit(.flightDelayed(id: flightID, route: flight.route,
                                                            delayMinutes: flight.delayMinutes))
                            }
                        }
                    } else {
                        flight.phase = .enRoute(actualDeparture: now)
                        if flight.kind == .revenue, flight.passengers > 0,
                           var route = state.routes[flight.route] {
                            let revenue = route.ticketPrice * Int64(flight.passengers)
                            state.ledger.post(
                                airline: aircraft.owner, category: .ticketRevenue,
                                amount: revenue, at: now,
                                memo: "\(flight.passengers) pax \(flight.from)-\(flight.to)")
                            route.economicsThisMonth.revenueCents += revenue.cents
                            route.economicsThisMonth.passengers += Int64(flight.passengers)
                            state.routes[flight.route] = route
                        }
                        context.emit(.flightDeparted(id: flightID, route: flight.route))
                    }
                }

            case .enRoute(let actualDeparture):
                if now >= actualDeparture + .minutes(flight.flightMinutes) {
                    arrive(flightID, flight: &flight, aircraft: &aircraft,
                           state: &state, context: context)
                }

            case .turnaround(let until):
                if now >= until {
                    aircraft.activeFlight = nil
                    state.flights[flightID] = nil
                    state.aircraft[flight.aircraft] = aircraft
                    if flight.kind == .revenue, var route = state.routes[flight.route] {
                        route.stats.flightsCompleted += 1
                        route.stats.passengersCarried += Int64(flight.passengers)
                        let spec = context.catalog.aircraftType(aircraft.typeCode)!
                        route.stats.seatsFlown += Int64(spec.seats)
                        if flight.wasDelayed {
                            route.stats.flightsDelayed += 1
                            route.stats.totalDelayMinutes += flight.delayMinutes
                        }
                        state.routes[flight.route] = route
                        if var airline = state.airlines[aircraft.owner] {
                            airline.opsToday.completed += 1
                            if flight.wasDelayed { airline.opsToday.delayed += 1 }
                            let isPlayer = airline.kind == .player
                            state.airlines[aircraft.owner] = airline
                            if isPlayer {
                                state.progression.counters.flightsCompleted += 1
                                state.progression.counters.passengersCarried
                                    += Int64(flight.passengers)
                            }
                        }
                    }
                    continue
                }
            }

            state.flights[flightID] = flight
            state.aircraft[flight.aircraft] = aircraft
        }
    }

    private func cancel(_ flightID: FlightID, flight: Flight, aircraft: inout Aircraft,
                        state: inout GameState, context: SimContext) {
        if aircraft.activeFlight == flightID { aircraft.activeFlight = nil }
        state.flights[flightID] = nil
        if flight.kind == .revenue, var route = state.routes[flight.route] {
            route.stats.flightsCancelled += 1
            state.routes[flight.route] = route
        }
        if flight.kind == .revenue, var airline = state.airlines[aircraft.owner] {
            airline.opsToday.cancelled += 1
            state.airlines[aircraft.owner] = airline
        }
        context.emit(.flightCancelled(id: flightID, route: flight.route))
    }

    private func arrive(_ flightID: FlightID, flight: inout Flight,
                        aircraft: inout Aircraft, state: inout GameState,
                        context: SimContext) {
        let catalog = context.catalog
        let ops = catalog.tuning.ops
        let spec = catalog.aircraftType(aircraft.typeCode)!

        aircraft.location = flight.to
        let blockHours = Double(flight.flightMinutes) / 60
        aircraft.totalFlightHours += blockHours
        aircraft.condition = max(0, aircraft.condition - blockHours * ops.wearPerFlightHour)

        // Operating costs, posted by category so route P&L stays explainable.
        let owner = aircraft.owner
        let fuelTons = spec.fuelBurnKgPerKm * Double(flight.distanceKm) / 1000
        var effectiveFuelPrice = state.world.fuelPricePerTon.asDouble
        if state.isPlayer(owner), state.playerHasCapability(.fuelHedging) {
            // Hedged: pay at most 105% of the base price.
            let cap = catalog.tuning.ops.baseFuelPricePerTon.asDouble * 1.05
            effectiveFuelPrice = min(effectiveFuelPrice, cap)
        }
        let fuelCost = Money(rounding: fuelTons * effectiveFuelPrice)
        state.ledger.post(airline: owner, category: .fuel, amount: -fuelCost,
                          at: context.current, memo: "Fuel \(flight.from)-\(flight.to)")

        // Movements are charged for what landed: the airport's quoted fee
        // scales with the aircraft's seats (AE-040 — a 68-seat turboprop
        // paid the same as a 180-seat narrowbody and could not clear its
        // fees on any route in the world, docs/FEE_ECONOMY_BASELINE.md).
        var fees = Money.zero
        if let fromSpec = catalog.airport(flight.from) {
            fees = fees + fromSpec.movementFee(for: spec, ops: ops)
        }
        if let toSpec = catalog.airport(flight.to) {
            fees = fees + toSpec.movementFee(for: spec, ops: ops)
            fees = fees + toSpec.passengerFee * Int64(flight.passengers)
        }
        state.ledger.post(airline: owner, category: .airportFees, amount: -fees,
                          at: context.current, memo: "Fees \(flight.from)-\(flight.to)")

        let crewCost = Money(rounding: blockHours
            * (Double(spec.crewCockpit) * ops.crewCostPerBlockHourCockpit.asDouble
               + Double(spec.crewCabin) * ops.crewCostPerBlockHourCabin.asDouble))
        state.ledger.post(airline: owner, category: .crewCosts, amount: -crewCost,
                          at: context.current, memo: "Crew \(flight.from)-\(flight.to)")

        // Onboard service cost per passenger by the airline's tier.
        if flight.kind == .revenue, flight.passengers > 0,
           let airline = state.airlines[owner] {
            let perPax = catalog.tuning.reputation.serviceCostPerPax(airline.serviceTier)
            let serviceCost = perPax * Int64(flight.passengers)
            state.ledger.post(airline: owner, category: .passengerService,
                              amount: -serviceCost, at: context.current,
                              memo: "Service \(flight.from)-\(flight.to)")
        }

        if var route = state.routes[flight.route] {
            route.economicsThisMonth.fuelCents += fuelCost.cents
            route.economicsThisMonth.feesCents += fees.cents
            route.economicsThisMonth.crewCents += crewCost.cents
            state.routes[flight.route] = route
        }

        var turnaroundMinutes = Int64(spec.turnaroundMinutes)
        if state.isPlayer(owner), state.playerHasCapability(.efficientTurnarounds) {
            turnaroundMinutes = Int64((Double(turnaroundMinutes) * 0.85).rounded())
        }
        let until = context.current + .minutes(turnaroundMinutes)
        flight.phase = .turnaround(until: until)
        context.emit(.flightArrived(id: flightID, route: flight.route,
                                    delayMinutes: flight.delayMinutes))
    }
}
