/// "Which aircraft should fly this route?", answered comparably.
///
/// The market has always listed every type with its own numbers. What it has
/// never done is price them against the route in front of the player, so a
/// 90-seat regional jet and a 184-seat narrowbody read as two cards of facts
/// rather than two answers to one question.
///
/// The comparison holds three things constant, because a comparison that lets
/// them move is not one:
///
/// - **the route** — distance, both airports, their runways;
/// - **the fare** — the route's own ticket price against the reference fare,
///   not each airframe's notion of a good price;
/// - **the frequency** — the route's own daily round trips, so a faster
///   airframe cannot win by flying more of them.
///
/// The demand engine's own split is the shared allocation: the same
/// `DemandSystem.serviceDemand` the simulation flies, with the incumbents
/// actually on the pair in the way. Airline overhead is deliberately out, so
/// the figure answers "does this route pay for the aircraft that flies it",
/// not "what is the airline worth" — the same boundary `MarketOpportunity`
/// uses.
///
/// Fit (range, runway, era) is a filter, not a ranking: a type that cannot
/// fly the route is absent rather than last. The rank is the money, and every
/// candidate carries the fleet it needs to hold the frequency, so a large
/// airframe that needs two of itself to fly the schedule cannot read as the
/// cheapest.

/// One route, one fare, one frequency: what each airframe an era sells would
/// keep on that route.
public struct AircraftMarketComparison: Equatable, Sendable {
    /// One candidate airframe, priced on this route as the route is.
    public struct Candidate: Equatable, Sendable, Identifiable {
        public var id: AircraftTypeCode { spec.code }
        public let spec: AircraftTypeSpec
        /// Rotations one aircraft of this type can fly in a day at this
        /// route's distance and runways — the scheduler's own arithmetic.
        public let rotationsPerAircraft: Int
        /// Aircraft of this type the route's daily frequency needs. One when
        /// a single airframe can fly it; more when the type is too slow.
        public let aircraftNeeded: Int
        /// Passengers one aircraft of this type could carry a day at its own
        /// achievable frequency, both directions.
        public let capacityPerAircraftPerDay: Int
        /// Passengers a day the route's held frequency offers on this type,
        /// both directions.
        public let frequencySeatsPerDay: Int
        /// Passengers a day the route's whole market wants today, across both
        /// carriers and both directions.
        public let demandToday: Int
        /// A month of the route's operating result on this type, less the
        /// lease, the crew and the route payroll the economy charges for it.
        /// The figure the shortlist is ranked on.
        public let monthlyAfterAirframe: Money

        public init(spec: AircraftTypeSpec, rotationsPerAircraft: Int,
                    aircraftNeeded: Int, capacityPerAircraftPerDay: Int,
                    frequencySeatsPerDay: Int, demandToday: Int,
                    monthlyAfterAirframe: Money) {
            self.spec = spec
            self.rotationsPerAircraft = rotationsPerAircraft
            self.aircraftNeeded = aircraftNeeded
            self.capacityPerAircraftPerDay = capacityPerAircraftPerDay
            self.frequencySeatsPerDay = frequencySeatsPerDay
            self.demandToday = demandToday
            self.monthlyAfterAirframe = monthlyAfterAirframe
        }

        /// Whether the type's own rotations cover the frequency, so one
        /// aircraft is enough.
        public var coversFrequencyAlone: Bool { aircraftNeeded <= 1 }
        /// Whether the route's frequency on this type can carry today's
        /// demand. Seats, not a profit claim.
        public var carriesTodayDemand: Bool {
            spec.seats > 0 && frequencySeatsPerDay >= demandToday
        }
    }

    public let routeID: RouteID
    public let origin: AirportCode
    public let destination: AirportCode
    public let distanceKm: Int
    /// The route's own fare — held constant across candidates.
    public let fare: Money
    /// The distance-anchored reference fare the demand engine prices against.
    public let referenceFare: Money
    /// The route's daily round trips — held constant across candidates.
    public let dailyRoundTrips: Int
    /// Passengers a day this route itself carries today — the player's own
    /// allocation, not the market's.
    public let demandToday: Int
    /// Passengers a day the whole market wants on the pair today, both
    /// directions and every carrier — the same pool for every candidate,
    /// because the route is held constant.
    public let marketDemandToday: Int
    /// Every eligible type the era sells, best monthly result first.
    public let candidates: [Candidate]
    /// The types worth comparing head to head, at most `shortlistLimit`.
    public let shortlist: [Candidate]

    init(routeID: RouteID, origin: AirportCode, destination: AirportCode,
         distanceKm: Int, fare: Money, referenceFare: Money,
         dailyRoundTrips: Int, demandToday: Int, marketDemandToday: Int,
         candidates: [Candidate], shortlistLimit: Int) {
        self.routeID = routeID
        self.origin = origin
        self.destination = destination
        self.distanceKm = distanceKm
        self.fare = fare
        self.referenceFare = referenceFare
        self.dailyRoundTrips = dailyRoundTrips
        self.demandToday = demandToday
        self.marketDemandToday = marketDemandToday
        self.candidates = candidates
        self.shortlist = Array(candidates.prefix(max(0, shortlistLimit)))
    }
}

extension GameState {
    /// How many airframes the market and the list both bother to compare.
    public static let aircraftMarketShortlistLimit = 4

    /// The comparison of every eligible airframe on one route, or nil when
    /// the route is not this airline's.
    public func aircraftMarketComparison(
        routeID: RouteID, catalog: ContentCatalog,
        era: Era, shortlistLimit: Int = GameState.aircraftMarketShortlistLimit
    ) -> AircraftMarketComparison? {
        guard let player = playerAirline, let route = routes[routeID],
              route.airline == player.id else { return nil }
        return aircraftMarketComparison(route: route, player: player,
                                        catalog: catalog, era: era,
                                        shortlistLimit: shortlistLimit)
    }

    /// The comparison for a route the caller already holds.
    func aircraftMarketComparison(
        route: Route, player: Airline, catalog: ContentCatalog,
        era: Era, shortlistLimit: Int = GameState.aircraftMarketShortlistLimit
    ) -> AircraftMarketComparison {
        let tuning = catalog.tuning
        let reference = DemandSystem.referenceFare(distanceKm: route.distanceKm,
                                                   tuning: tuning.demand)
        // The route's own fare, against the same anchor the demand engine
        // uses. A free route prices at the anchor rather than dividing by
        // zero; a route does not exist at zero fare, but a comparison should
        // not trap on it either.
        let fareRatio = reference > 0 && route.ticketPrice.cents > 0
            ? route.ticketPrice.asDouble / reference : 1
        let reputation = player.reputation.demandMultiplier(tuning: tuning.reputation)
        let serviceTier = player.serviceTier
        let demandToday = route.demandOutboundToday + route.demandInboundToday
        // The player's own route is the subject of the comparison, not a
        // competitor in it: the incumbents are everyone else on the pair.
        let incumbents = routesByMarket()[route.market]?
            .filter { $0.airline != player.id } ?? []
        let frequency = max(1, route.dailyRoundTrips)
        // The two monthly costs the economy charges for having the route at
        // all, per aircraft and once for the route — the same pair
        // `MarketOpportunity` subtracts, so the screens agree.
        let payrollPerAircraft = tuning.finance.payrollPerAircraftMonthly.asDouble
        let payrollPerRoute = tuning.finance.payrollPerRouteMonthly.asDouble

        guard let originSpec = catalog.airport(route.origin),
              let destinationSpec = catalog.airport(route.destination) else {
            return AircraftMarketComparison(
                routeID: route.id, origin: route.origin, destination: route.destination,
                distanceKm: route.distanceKm, fare: route.ticketPrice,
                referenceFare: Money(rounding: reference), dailyRoundTrips: frequency,
                demandToday: demandToday, marketDemandToday: 0,
                candidates: [], shortlistLimit: shortlistLimit)
        }

        var candidates: [AircraftMarketComparison.Candidate] = []
        var marketPool = 0.0
        for code in catalog.orderedAircraftTypeCodes {
            guard let spec = catalog.aircraftType(code),
                  era.allowedCategories.contains(spec.category),
                  catalog.routeEligibility(
                      from: route.origin, to: route.destination,
                      aircraftRangeKm: spec.rangeKm,
                      aircraftRunwayRequirement: spec.runwayRequirement).isEmpty
            else { continue }
            let rotationsPerAircraft = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
                distanceKm: route.distanceKm, spec: spec, ops: tuning.ops)
            guard rotationsPerAircraft > 0 else { continue }
            // Integer ceiling: the aircraft the route's own frequency takes.
            let aircraftNeeded = (frequency + rotationsPerAircraft - 1)
                / rotationsPerAircraft
            // The market sees the route's own frequency on this type; the
            // costs are the flights that frequency posts, and the fixed
            // charges scale with the aircraft it takes to fly them.
            let estimate = CompetitorAISystem.airframeDayEstimate(
                origin: originSpec, destination: destinationSpec,
                distanceKm: route.distanceKm, spec: spec,
                fareRatio: fareRatio, serviceTier: serviceTier,
                reputationMultiplier: reputation, incumbents: incumbents,
                rotationsPerDay: frequency, state: self, catalog: catalog,
                basis: .profit)
            // The pool is the market's, not the candidate's: the route and
            // fare are held, so every candidate reads the same demand.
            marketPool = max(marketPool, estimate.demand.poolPerDay)
            let monthly = estimate.value * 30
                - spec.leaseMonthly.asDouble * Double(aircraftNeeded)
                - payrollPerAircraft * Double(aircraftNeeded)
                - payrollPerRoute
            candidates.append(AircraftMarketComparison.Candidate(
                spec: spec, rotationsPerAircraft: rotationsPerAircraft,
                aircraftNeeded: aircraftNeeded,
                capacityPerAircraftPerDay: rotationsPerAircraft * spec.seats * 2,
                // The frequency is held, so the seats it offers are the
                // route's own schedule on this type's cabin.
                frequencySeatsPerDay: frequency * spec.seats * 2,
                demandToday: demandToday,
                monthlyAfterAirframe: Money(rounding: monthly)))
        }
        // The money decides, then the fleet it takes, then the smaller cabin
        // — a tie on both is a tie the code breaks so the order never moves.
        candidates.sort { lhs, rhs in
            if lhs.monthlyAfterAirframe != rhs.monthlyAfterAirframe {
                return lhs.monthlyAfterAirframe > rhs.monthlyAfterAirframe
            }
            if lhs.aircraftNeeded != rhs.aircraftNeeded {
                return lhs.aircraftNeeded < rhs.aircraftNeeded
            }
            if lhs.spec.seats != rhs.spec.seats { return lhs.spec.seats < rhs.spec.seats }
            return lhs.spec.code.raw < rhs.spec.code.raw
        }
        return AircraftMarketComparison(
            routeID: route.id, origin: route.origin, destination: route.destination,
            distanceKm: route.distanceKm, fare: route.ticketPrice,
            referenceFare: Money(rounding: reference), dailyRoundTrips: frequency,
            demandToday: demandToday, marketDemandToday: Int(marketPool.rounded()),
            candidates: candidates, shortlistLimit: shortlistLimit)
    }
}
