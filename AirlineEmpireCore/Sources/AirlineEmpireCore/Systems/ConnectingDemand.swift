import Foundation

// Connecting passengers through a designated hub (docs/HUB_PROGRESSION_PLAN.md
// §4 #6, §5 Phase E): the spill term the demand engine's pool split reserved
// in D-010. Demand between two of an airline's spokes that no nonstop
// served, A→C, flows through its hub B when the day's own timetable connects
// A→B with B→C — the mid-game turn from lines on a map to a network.
//
// Passengers stay aggregates (docs/DOMAIN_MODEL.md): a connecting flow is a
// count on each of its two legs, never a traveller with an itinerary.

/// One day's connecting traffic through a hub: travellers from `origin` to
/// `destination` changing planes at `hub` on the airline's own flights.
public struct ConnectingFlow: Equatable, Codable, Sendable {
    public let origin: AirportCode
    public let hub: AirportCode
    public let destination: AirportCode
    /// The legs flown: origin–hub, then hub–destination.
    public let inbound: RouteID
    public let outbound: RouteID
    public let passengers: Int
    /// What one traveller pays for both legs together, before cabin yield.
    public let fare: Money
    /// Arrivals from the origin with an onward departure inside the window.
    public let connections: Int
    /// The average wait at the hub over those connections, minutes.
    public let averageWaitMinutes: Int

    public init(origin: AirportCode, hub: AirportCode, destination: AirportCode, inbound: RouteID,
                outbound: RouteID, passengers: Int, fare: Money, connections: Int, averageWaitMinutes: Int) {
        self.origin = origin; self.hub = hub; self.destination = destination
        self.inbound = inbound; self.outbound = outbound
        self.passengers = passengers; self.fare = fare
        self.connections = connections; self.averageWaitMinutes = averageWaitMinutes
    }
}

/// Connecting travellers booked through one hub, this month and last.
/// Booked rather than flown: the count the day's connections were sold at.
public struct HubTransferTally: Equatable, Codable, Sendable {
    public var thisMonth: Int64
    public var lastMonth: Int64
    /// Their through fares, cents.
    public var revenueThisMonthCents: Int64
    public var revenueLastMonthCents: Int64
    public var lifetime: Int64

    public init(thisMonth: Int64 = 0, lastMonth: Int64 = 0, revenueThisMonthCents: Int64 = 0,
                revenueLastMonthCents: Int64 = 0, lifetime: Int64 = 0) {
        self.thisMonth = thisMonth; self.lastMonth = lastMonth
        self.revenueThisMonthCents = revenueThisMonthCents
        self.revenueLastMonthCents = revenueLastMonthCents
        self.lifetime = lifetime
    }

    /// The month boundary: this month becomes last month's comparable figure.
    mutating func closeMonth() {
        lastMonth = thisMonth
        revenueLastMonthCents = revenueThisMonthCents
        thisMonth = 0
        revenueThisMonthCents = 0
    }
}

extension Airline {
    /// The airline's designated hubs: every airport with its transfer centre
    /// open, sorted.
    public var designatedHubs: [AirportCode] {
        (airportFacilities ?? [:]).filter { $0.value.transferCentre > 0 }.keys.sorted()
    }
}

extension Route {
    /// The day's demand this way that is the route's own city pair, without
    /// the travellers connecting onto it.
    func localDemand(outbound: Bool) -> Int {
        let demand = outbound ? demandOutboundToday : demandInboundToday
        return demand - (connectionsToday?.direction(outbound: outbound).booked ?? 0)
    }
}

// MARK: - The spill term

extension DemandSystem {
    /// One direction of one route.
    struct Leg: Hashable {
        let route: RouteID
        /// Origin to destination.
        let outbound: Bool
    }

    /// A leg's flights today: the seats they offer, when each leaves and
    /// when each lands (raw simulation minutes).
    struct LegDay {
        var seats = 0
        var departures: [Int64] = []
        var arrivals: [Int64] = []
    }

    /// How well a day's arrivals from A meet the departures to C at the hub.
    struct ConnectionTiming: Equatable {
        /// Itineraries that work: arrivals with an onward departure inside
        /// the window, at most the departures some arrival reaches.
        let connections: Int
        /// The average shortest wait over the arrivals that connect.
        let averageWait: Double
    }

    /// Arrivals and departures matched in the window `[minimum, maximum]`
    /// minutes after landing. Both lists are small (a leg's flights in one
    /// day), so the plain double loop is the cheap form.
    static func timing(arrivals: [Int64], departures: [Int64], minimum: Int64,
                       maximum: Int64) -> ConnectionTiming {
        var connectedArrivals = 0
        var waits = 0.0
        for arrival in arrivals {
            var best: Int64?
            for departure in departures {
                let wait = departure - arrival
                guard wait >= minimum, wait <= maximum else { continue }
                if best == nil || wait < best! { best = wait }
            }
            if let best {
                connectedArrivals += 1
                waits += Double(best)
            }
        }
        var reachedDepartures = 0
        for departure in departures where arrivals.contains(where: {
            departure - $0 >= minimum && departure - $0 <= maximum
        }) {
            reachedDepartures += 1
        }
        let connections = min(connectedArrivals, reachedDepartures)
        return ConnectionTiming(connections: connections,
                                averageWait: connectedArrivals > 0 ? waits / Double(connectedArrivals) : 0)
    }

    /// The spill term: today's connecting traffic through `airline`'s hubs.
    ///
    /// For every pair of the airline's spokes A and C at a hub B, where it
    /// does not fly A–C itself and B is no long way round:
    ///
    /// 1. **Residual.** A→C's demand pool less every nonstop's allocation
    ///    today (any airline) and what earlier hubs already carried. What a
    ///    connection can win is only demand nobody served, so a nonstop
    ///    never loses a passenger to it and the pool is never exceeded.
    /// 2. **Quality.** The day's timetable at B: arrivals from A with a
    ///    departure to C between the minimum connect time and the longest
    ///    layover. Their number prices the schedule as frequency does for a
    ///    nonstop; the average wait and the change of planes discount it;
    ///    the weaker leg's comfort, operations and reputation carry over.
    /// 3. **Fare.** The two legs' fares less the through-fare discount,
    ///    against the A→C reference fare, in the engine's own utility.
    /// 4. **Share.** That offer against staying at home, per segment, over
    ///    the residual — then capped by the seats both legs still have
    ///    after their own passengers. Connections fill empty seats; they
    ///    never bump a local traveller.
    ///
    /// Pairs are taken largest pool first, at most `transferMarketsPerHub`
    /// a hub from at most `transferSpokesPerHub` spokes, so the day's cost
    /// is bounded by the caps, not the network. Deterministic: sorted
    /// iteration everywhere, no random draws.
    ///
    /// Rivals do not connect passengers yet: the competitor AI builds no hub
    /// buildings, and this only runs for the player. When rivals hub, their
    /// flows join the same residual bookkeeping.
    ///
    /// `hubs` limits the run to those hubs (a payoff estimate); the flows
    /// the airline already carries today through any other hub count as
    /// served.
    static func connectingSpill(airline airlineID: AirlineID, hubs only: [AirportCode]? = nil,
                                state: GameState, catalog: ContentCatalog) -> [ConnectingFlow] {
        guard let airline = state.airlines[airlineID], airline.kind == .player,
              airline.status == .active else { return [] }
        let hubs = only ?? airline.designatedHubs
        guard !hubs.isEmpty else { return [] }
        let tuning = catalog.tuning.airportServices
        let demandTuning = catalog.tuning.demand
        let today = state.clock.now.dayIndex
        let date = state.currentDate

        // The day's timetable on the airline's own legs.
        var legDays: [Leg: LegDay] = [:]
        for flightID in state.orderedFlightIDs {
            guard let flight = state.flights[flightID], flight.kind == .revenue,
                  flight.scheduledDeparture.dayIndex == today,
                  let route = state.routes[flight.route], route.airline == airlineID,
                  let aircraft = state.aircraft[flight.aircraft],
                  let spec = catalog.aircraftType(aircraft.typeCode) else { continue }
            let leg = Leg(route: route.id, outbound: flight.from == route.origin)
            let departure = flight.scheduledDeparture.rawMinutes
            var day = legDays[leg] ?? LegDay()
            day.seats += aircraft.cabin(for: spec).totalSeats
            day.departures.append(departure)
            day.arrivals.append(departure + flight.flightMinutes)
            legDays[leg] = day
        }
        guard !legDays.isEmpty else { return [] }

        // Every airline's nonstops by city pair, and the pairs the airline
        // flies itself (its travellers take its own nonstop).
        func pairKey(_ a: AirportCode, _ b: AirportCode) -> String {
            a < b ? a.raw + "-" + b.raw : b.raw + "-" + a.raw
        }
        var nonstops: [String: [RouteID]] = [:]
        var ownPairs: Set<String> = []
        for routeID in state.orderedRouteIDs {
            guard let route = state.routes[routeID] else { continue }
            let key = pairKey(route.origin, route.destination)
            nonstops[key, default: []].append(routeID)
            if route.airline == airlineID { ownPairs.insert(key) }
        }
        func direct(from a: AirportCode, to c: AirportCode) -> Int {
            (nonstops[pairKey(a, c)] ?? []).reduce(0) { total, id in
                guard let route = state.routes[id] else { return total }
                return total + max(0, route.localDemand(outbound: route.origin == a))
            }
        }

        // Served already: flows through hubs outside this run.
        var spilled: [String: Double] = [:]
        for flow in airline.connectingFlowsToday ?? [] where !hubs.contains(flow.hub) {
            spilled[flow.origin.raw + ">" + flow.destination.raw, default: 0] += Double(flow.passengers)
        }
        // Seats each leg has left after the demand already on it.
        var spare: [Leg: Int] = [:]
        func spareSeats(_ leg: Leg) -> Int {
            if let known = spare[leg] { return known }
            guard let route = state.routes[leg.route], let day = legDays[leg] else { return 0 }
            let demand = leg.outbound ? route.demandOutboundToday : route.demandInboundToday
            let seats = max(0, day.seats - demand)
            spare[leg] = seats
            return seats
        }
        // A leg's non-schedule quality and cabin yield, once each.
        var legQuality: [RouteID: (quality: Double, fareYield: Double)] = [:]
        func quality(_ route: Route) -> (quality: Double, fareYield: Double)? {
            if let known = legQuality[route.id] { return known }
            guard let terms = offerQualityTerms(route: route, state: state, catalog: catalog) else { return nil }
            let value = (quality: terms.comfort * terms.operations * terms.reputation,
                         fareYield: cabinYield(route: route, state: state, catalog: catalog))
            legQuality[route.id] = value
            return value
        }

        /// A city pair worth connecting: two spokes by index, its pool today.
        struct Candidate {
            let from: Int
            let to: Int
            let pool: SegmentDemand
            let distanceKm: Int
        }

        var flows: [ConnectingFlow] = []
        for hub in hubs.sorted() {
            // One leg a spoke, the first route to it; up to the cap.
            var spokes: [(spoke: AirportCode, route: Route)] = []
            var seen: Set<AirportCode> = []
            for route in state.operatingRoutes(of: airlineID) where route.servesAirport(hub) {
                let spoke = route.origin == hub ? route.destination : route.origin
                guard !seen.contains(spoke) else { continue }
                seen.insert(spoke)
                spokes.append((spoke, route))
                if spokes.count >= tuning.transferSpokesPerHub { break }
            }
            guard spokes.count >= 2 else { continue }

            // City pairs worth connecting, largest pool first.
            var candidates: [Candidate] = []
            for i in spokes.indices {
                for j in spokes.indices where j != i {
                    let a = spokes[i].spoke, c = spokes[j].spoke
                    guard !ownPairs.contains(pairKey(a, c)),
                          let distance = catalog.distanceKm(a, c),
                          distance >= catalog.tuning.minRouteDistanceKm,
                          Double(spokes[i].route.distanceKm + spokes[j].route.distanceKm)
                            <= tuning.transferMaximumDetour * Double(distance) else { continue }
                    let boost = catalog.airport(c).map {
                        state.world.tourismBoost(for: $0.region, at: state.clock.now)
                    } ?? 0
                    let pool = demandPool(from: a, to: c, date: date,
                                          economicIndex: state.world.economicIndex,
                                          tourismBoost: boost, catalog: catalog)
                    guard pool.total > 0 else { continue }
                    candidates.append(Candidate(from: i, to: j, pool: pool, distanceKm: distance))
                }
            }
            candidates.sort { lhs, rhs in
                if lhs.pool.total != rhs.pool.total { return lhs.pool.total > rhs.pool.total }
                let l = (spokes[lhs.from].spoke, spokes[lhs.to].spoke)
                let r = (spokes[rhs.from].spoke, spokes[rhs.to].spoke)
                return l.0 != r.0 ? l.0 < r.0 : l.1 < r.1
            }

            for candidate in candidates.prefix(tuning.transferMarketsPerHub) {
                let a = spokes[candidate.from].spoke, c = spokes[candidate.to].spoke
                let first = spokes[candidate.from].route, second = spokes[candidate.to].route
                let inbound = Leg(route: first.id, outbound: first.origin == a)
                let outbound = Leg(route: second.id, outbound: second.origin == hub)
                guard let arriving = legDays[inbound], let leaving = legDays[outbound] else { continue }
                let matched = Self.timing(arrivals: arriving.arrivals.sorted(), departures: leaving.departures.sorted(),
                                          minimum: tuning.transferMinimumConnectMinutes,
                                          maximum: tuning.transferMaximumLayoverMinutes)
                guard matched.connections > 0 else { continue }
                let seats = min(spareSeats(inbound), spareSeats(outbound))
                guard seats > 0 else { continue }
                let key = a.raw + ">" + c.raw
                let residual = candidate.pool.total - Double(direct(from: a, to: c)) - (spilled[key] ?? 0)
                guard residual > 0, let one = quality(first), let two = quality(second) else { continue }

                // The connection as an offer, in the engine's own terms.
                let trips = Double(min(matched.connections, demandTuning.scheduleQualityTripCap))
                let schedule = pow(trips / demandTuning.scheduleQualityReferenceTrips,
                                   demandTuning.scheduleQualityExponent)
                let window = Double(tuning.transferMaximumLayoverMinutes - tuning.transferMinimumConnectMinutes)
                let lateness = min(1, max(0, (matched.averageWait - Double(tuning.transferMinimumConnectMinutes)) / window))
                let offer = schedule * (1 - tuning.transferLayoverPenalty * lateness)
                    * tuning.transferConnectionQuality * min(one.quality, two.quality)
                let through = (first.ticketPrice + second.ticketPrice).asDouble * (1 - tuning.transferThroughFareDiscount)
                let ratio = through * (one.fareYield + two.fareYield) / 2
                    / referenceFare(distanceKm: candidate.distanceKm, tuning: demandTuning)
                let business = utility(fareRatio: ratio, quality: offer, sensitivity: demandTuning.priceSensitivityBusiness)
                let leisure = utility(fareRatio: ratio, quality: offer, sensitivity: demandTuning.priceSensitivityLeisure)
                // Segment shares of what is left, weighted as the pool is.
                let won = residual * (candidate.pool.business * share(offer: business, everyOffer: business, tuning: demandTuning)
                    + candidate.pool.leisure * share(offer: leisure, everyOffer: leisure, tuning: demandTuning))
                    / candidate.pool.total
                let passengers = min(Int(won.rounded(.down)), seats)
                guard passengers > 0 else { continue }
                let leftIn = spareSeats(inbound) - passengers, leftOut = spareSeats(outbound) - passengers
                spare[inbound] = leftIn
                spare[outbound] = leftOut
                spilled[key, default: 0] += Double(passengers)
                flows.append(ConnectingFlow(origin: a, hub: hub, destination: c, inbound: first.id,
                                            outbound: second.id, passengers: passengers,
                                            fare: Money(rounding: through), connections: matched.connections,
                                            averageWaitMinutes: Int(matched.averageWait.rounded())))
            }
        }
        return flows
    }
}

// MARK: - The system

/// Daily: books the spill term's connecting travellers onto both legs of
/// their journeys (`DemandSystem.connectingSpill`).
///
/// Runs after the scheduler, on the same tick and before anything boards:
/// connection quality is read from the day's own timetable, so it only
/// exists once today's flights do. The direct split (`DemandSystem`, #2)
/// has already set each route's own demand; this adds the connections on
/// top and keeps the bookkeeping that proves the pools are conserved.
///
/// A network without a transfer centre is untouched: no route, flight or
/// airline field changes, and no random draw is taken.
public struct ConnectingDemandSystem: SimulationSystem {
    public let id = "connectingDemand"
    public let cadence = Cadence.daily

    public init() {}

    public func update(state: inout GameState, context: SimContext) {
        // Yesterday's connections went with yesterday's demand; anything a
        // route still holds from before today's split is cleared.
        for routeID in state.orderedRouteIDs where state.routes[routeID]?.connectionsToday != nil {
            state.routes[routeID]?.connectionsToday = nil
        }
        for airlineID in state.orderedAirlineIDs {
            if state.airlines[airlineID]?.connectingFlowsToday != nil {
                state.airlines[airlineID]?.connectingFlowsToday = nil
            }
            let flows = DemandSystem.connectingSpill(airline: airlineID, state: state, catalog: context.catalog)
            guard !flows.isEmpty else { continue }
            Self.book(flows, airline: airlineID, state: &state)
        }
    }

    /// Adds `flows` to their legs' demand and the hubs' tallies. Each flow's
    /// through fare is split between its legs by distance, exactly: the
    /// second leg takes what the first leaves, so no cent is lost.
    static func book(_ flows: [ConnectingFlow], airline airlineID: AirlineID, state: inout GameState) {
        var booked: [DemandSystem.Leg: (passengers: Int, cents: Int64)] = [:]
        var tallies = state.airlines[airlineID]?.hubTransfers ?? [:]
        for flow in flows {
            guard let first = state.routes[flow.inbound], let second = state.routes[flow.outbound] else { continue }
            let near = Double(first.distanceKm), far = Double(second.distanceKm)
            let firstFare = Money(rounding: flow.fare.asDouble * near / max(1, near + far))
            let secondFare = flow.fare - firstFare
            for (leg, fare) in [(DemandSystem.Leg(route: first.id, outbound: first.origin == flow.origin), firstFare),
                                (DemandSystem.Leg(route: second.id, outbound: second.origin == flow.hub), secondFare)] {
                let sum = booked[leg] ?? (passengers: 0, cents: 0)
                booked[leg] = (sum.passengers + flow.passengers, sum.cents + fare.cents * Int64(flow.passengers))
            }
            var tally = tallies[flow.hub] ?? HubTransferTally()
            tally.thisMonth += Int64(flow.passengers)
            tally.revenueThisMonthCents += flow.fare.cents * Int64(flow.passengers)
            tally.lifetime += Int64(flow.passengers)
            tallies[flow.hub] = tally
        }
        let legs = booked.keys.sorted { $0.route != $1.route ? $0.route < $1.route : ($0.outbound && !$1.outbound) }
        for leg in legs {
            guard let sum = booked[leg], sum.passengers > 0, var route = state.routes[leg.route] else { continue }
            var load = route.connectionsToday ?? ConnectingLoad()
            var direction = load.direction(outbound: leg.outbound)
            let total = direction.fare.cents * Int64(direction.booked) + sum.cents
            direction.booked += sum.passengers
            direction.remaining += sum.passengers
            // The leg's average share, to the nearest cent.
            direction.fare = Money(cents: (total + Int64(direction.booked) / 2) / Int64(direction.booked))
            load.set(direction, outbound: leg.outbound)
            route.connectionsToday = load
            if leg.outbound {
                route.demandOutboundToday += sum.passengers
                route.remainingOutboundToday += sum.passengers
            } else {
                route.demandInboundToday += sum.passengers
                route.remainingInboundToday += sum.passengers
            }
            state.routes[leg.route] = route
        }
        state.airlines[airlineID]?.hubTransfers = tallies
        state.airlines[airlineID]?.connectingFlowsToday = flows
    }
}

extension GameState {
    /// What a transfer centre at `airport` would connect on today's schedule
    /// for `airline`, on top of its hubs already open: the payoff a card can
    /// quote from the engine's own arithmetic. Pure.
    public func connectingFlowsIfHub(at airport: AirportCode, airline: AirlineID,
                                     catalog: ContentCatalog) -> [ConnectingFlow] {
        var copy = self
        guard var owner = copy.airlines[airline] else { return [] }
        var stations = owner.airportFacilities ?? [:]
        var here = stations[airport] ?? AirportFacilities()
        here.transferCentre = max(1, here.transferCentre)
        stations[airport] = here
        owner.airportFacilities = stations
        copy.airlines[airline] = owner
        return DemandSystem.connectingSpill(airline: airline, hubs: [airport], state: copy, catalog: catalog)
    }
}
