import Foundation

/// Daily passenger demand engine (docs/ECONOMY.md).
///
/// For every market (unordered airport pair) with service, computes the
/// day's demand pool per direction from demographics × distance gravity ×
/// seasonality × weekday × world economy, then splits it across competing
/// offers (and the "don't travel" outside option) by attractiveness:
/// exponential price utility around a distance-based reference fare, times
/// schedule quality, operational performance, and cabin comfort.
///
/// Results land on each route as today's bookable demand; the flight-ops
/// boarding step consumes it. Demand is conserved: a passenger booked on
/// one route is never double-counted elsewhere.
public struct DemandSystem: SimulationSystem {
    public let id = "demand"
    public let cadence = Cadence.daily

    public init() {}

    public func update(state: inout GameState, context: SimContext) {
        let catalog = context.catalog
        let date = state.currentDate

        // Group served routes by market, deterministically.
        var markets: [String: [RouteID]] = [:]
        for routeID in state.orderedRouteIDs {
            let route = state.routes[routeID]!
            let key = [route.origin.raw, route.destination.raw].sorted().joined(separator: "-")
            markets[key, default: []].append(routeID)
        }

        for key in markets.keys.sorted() {
            let routeIDs = markets[key]!
            guard let first = state.routes[routeIDs[0]] else { continue }
            let a = first.origin
            let b = first.destination

            for (from, to) in [(a, b), (b, a)] {
                let boost: Double
                if let destination = catalog.airport(to) {
                    boost = state.world.tourismBoost(for: destination.region,
                                                     at: state.clock.now)
                } else {
                    boost = 0
                }
                let pool = Self.demandPool(from: from, to: to, date: date,
                                           economicIndex: state.world.economicIndex,
                                           tourismBoost: boost,
                                           catalog: catalog)
                allocate(pool: pool, from: from, to: to, routeIDs: routeIDs,
                         state: &state, catalog: catalog)
            }
        }
    }

    private func allocate(pool: SegmentDemand, from: AirportCode, to: AirportCode,
                          routeIDs: [RouteID], state: inout GameState,
                          catalog: ContentCatalog) {
        let tuning = catalog.tuning.demand
        guard let distance = catalog.distanceKm(from, to) else { return }
        let refFare = Self.referenceFare(distanceKm: distance, tuning: tuning)

        // Attractiveness per offer and segment.
        var business: [Double] = []
        var leisure: [Double] = []
        for routeID in routeIDs {
            let route = state.routes[routeID]!
            guard let quality = offerQuality(route: route, state: state, catalog: catalog)
            else {
                business.append(0)
                leisure.append(0)
                continue
            }
            let ratio = route.ticketPrice.asDouble / refFare
            business.append(Self.utility(fareRatio: ratio, quality: quality,
                                         sensitivity: tuning.priceSensitivityBusiness))
            leisure.append(Self.utility(fareRatio: ratio, quality: quality,
                                        sensitivity: tuning.priceSensitivityLeisure))
        }

        let sumB = business.reduce(0, +)
        let sumL = leisure.reduce(0, +)

        for (index, routeID) in routeIDs.enumerated() {
            var route = state.routes[routeID]!
            let served = pool.business * Self.share(offer: business[index],
                                                    everyOffer: sumB, tuning: tuning)
                + pool.leisure * Self.share(offer: leisure[index],
                                            everyOffer: sumL, tuning: tuning)
            let pax = Int((served).rounded(.down))
            if route.origin == from {
                route.demandOutboundToday = pax
                route.remainingOutboundToday = pax
            } else {
                route.demandInboundToday = pax
                route.remainingInboundToday = pax
            }
            state.routes[routeID] = route
        }
    }

    // MARK: The split, in one place

    /// One offer's attractiveness in one segment: the exponential price
    /// utility around the reference fare, times the offer's service quality.
    ///
    /// Extracted in AE-044 so that `allocate`, the pre-flight estimates and
    /// the entrant calculations provably use the *same* expression rather
    /// than four copies of it (docs/AE044_ROOT_CAUSE.md §6).
    static func utility(fareRatio: Double, quality: Double, sensitivity: Double) -> Double {
        exp(sensitivity * (1 - fareRatio)) * quality
    }

    /// The share of one segment's pool an offer wins: its own utility over
    /// the "don't travel" outside option plus `everyOffer`, the summed
    /// utility of every offer on the market **including this one**. The
    /// logit split, and the only one.
    ///
    /// `everyOffer` rather than "the others" on purpose: `allocate` has that
    /// sum already, and reconstructing it as `offer + others` would put a
    /// floating-point subtract-then-add inside the number the simulation
    /// then floors into a passenger count. This form is bit-identical to the
    /// expression AE-044 replaced.
    static func share(offer: Double, everyOffer: Double, tuning: DemandTuning) -> Double {
        guard offer > 0 else { return 0 }
        return offer / (tuning.outsideOptionWeight + everyOffer)
    }

    /// The incumbents' summed utilities on a market, by segment — the
    /// denominator term an entrant faces. Offers that cannot carry anyone
    /// (no assigned aircraft) attract nothing, exactly as in `allocate`.
    static func incumbentUtilities(_ incumbents: [Route], distanceKm: Int,
                                   state: GameState,
                                   catalog: ContentCatalog) -> (business: Double, leisure: Double) {
        let tuning = catalog.tuning.demand
        let refFare = referenceFare(distanceKm: distanceKm, tuning: tuning)
        var business = 0.0, leisure = 0.0
        for route in incumbents {
            guard let quality = offerQualityTerms(route: route, state: state,
                                                  catalog: catalog)?.product else { continue }
            let ratio = route.ticketPrice.asDouble / refFare
            business += utility(fareRatio: ratio, quality: quality,
                                sensitivity: tuning.priceSensitivityBusiness)
            leisure += utility(fareRatio: ratio, quality: quality,
                               sensitivity: tuning.priceSensitivityLeisure)
        }
        return (business, leisure)
    }

    /// Quality multiplier for an offer; nil when the route cannot carry
    /// anyone (no assigned aircraft).
    private func offerQuality(route: Route, state: GameState,
                              catalog: ContentCatalog) -> Double? {
        Self.offerQualityTerms(route: route, state: state, catalog: catalog)?.product
    }

    /// The non-price terms of an offer's attractiveness, kept apart so a
    /// competition read model can say *which* of them is winning a market
    /// with the demand engine's own arithmetic rather than a second opinion
    /// (docs/RIVAL_PRESSURE_AUDIT.md §5). Nil when the route cannot carry
    /// anyone (no assigned aircraft).
    public struct OfferQualityTerms: Equatable, Sendable {
        /// Frequency, with hard diminishing returns beyond ~4/day
        /// (docs/GAME_BALANCE.md §5 anti-frequency-spam).
        public let schedule: Double
        /// The first assigned aircraft's cabin.
        public let comfort: Double
        /// Completion and punctuality, from the route's own record.
        public let operations: Double
        /// The airline's blended reputation as a demand multiplier.
        public let reputation: Double

        public var product: Double { schedule * comfort * operations * reputation }
    }

    public static func offerQualityTerms(route: Route, state: GameState,
                                         catalog: ContentCatalog) -> OfferQualityTerms? {
        guard let firstAircraft = route.assignedAircraft.sorted()
            .compactMap({ state.aircraft[$0] }).first,
            let spec = catalog.aircraftType(firstAircraft.typeCode) else { return nil }
        let reputation = state.airlines[route.airline]?.reputation
            .demandMultiplier(tuning: catalog.tuning.reputation) ?? 1.0
        return offerQualityTerms(
            spec: spec, roundTripsPerDay: route.dailyRoundTrips,
            operationsScore: route.stats.completionRate * 0.5 + route.stats.punctuality * 0.5,
            reputationMultiplier: reputation, tuning: catalog.tuning.demand)
    }

    /// The same four terms for a service that has not been flown yet: an
    /// airframe of `spec` at `roundTripsPerDay`, with an operations record
    /// of `operationsScore` (0…1) and a reputation multiplier.
    ///
    /// AE-044: the route-based entry point above now *is* this one, so a
    /// pre-flight estimate and the demand engine cannot value the same offer
    /// differently (docs/AE044_ROOT_CAUSE.md §6).
    public static func offerQualityTerms(spec: AircraftTypeSpec, roundTripsPerDay: Int,
                                         operationsScore: Double,
                                         reputationMultiplier: Double,
                                         tuning: DemandTuning) -> OfferQualityTerms {
        let trips = Double(min(roundTripsPerDay, tuning.scheduleQualityTripCap))
        let schedule = pow(trips / tuning.scheduleQualityReferenceTrips,
                           tuning.scheduleQualityExponent)
        let comfort = tuning.comfortBase + tuning.comfortWeight * spec.comfortBaseline
        let operations = tuning.operationsBase + tuning.operationsWeight * operationsScore
        return OfferQualityTerms(schedule: schedule, comfort: comfort,
                                 operations: operations, reputation: reputationMultiplier)
    }

    /// Passengers a single operator could expect to carry per day on a
    /// market, at a given fare ratio and service quality — the pool times
    /// the share the logit split actually awards, including the outside
    /// option. The raw pool is market *mass*, not a passenger count: a
    /// lone operator at the reference fare captures roughly a third of it,
    /// so showing the pool to a player overstates the market by ~3x and
    /// invites planning against traffic that will never board (BUG-006).
    public static func expectedCapturedPassengers(
        pool: SegmentDemand, fareRatio: Double, quality: Double,
        tuning: DemandTuning) -> Double {
        guard quality > 0 else { return 0 }
        let business = utility(fareRatio: fareRatio, quality: quality,
                               sensitivity: tuning.priceSensitivityBusiness)
        let leisure = utility(fareRatio: fareRatio, quality: quality,
                              sensitivity: tuning.priceSensitivityLeisure)
        return pool.business * share(offer: business, everyOffer: business, tuning: tuning)
            + pool.leisure * share(offer: leisure, everyOffer: leisure, tuning: tuning)
    }

    /// The pool a new entrant could plan against on a pair, given who is
    /// already flying it: the demand engine's own split, applied to one
    /// hypothetical extra offer against the incumbents' actual fares and
    /// quality, expressed in pool units so it compares directly with an
    /// empty pair's `pool.total`. Empty pair: the whole pool. One incumbent
    /// at the same fare and quality: roughly two thirds of it (the outside
    /// option shrinks as offers multiply), never half — which is what the
    /// competitor AI assumed until AE-038 measured that the halving kept
    /// every rival out of every pair the player flew except the largest
    /// (TD-026, docs/RIVALS_THAT_COME_TO_YOU_AUDIT.md). Incumbents that
    /// cannot carry anyone (no aircraft) attract nothing, as in `allocate`.
    public static func poolAvailableToEntrant(
        pool: SegmentDemand, fareRatio: Double, quality: Double,
        incumbents: [Route], state: GameState, catalog: ContentCatalog) -> Double {
        guard quality > 0, pool.total > 0 else { return 0 }
        let tuning = catalog.tuning.demand
        guard let first = incumbents.first,
              let distance = catalog.distanceKm(first.origin, first.destination)
        else { return pool.total }
        let (rivalsBusiness, rivalsLeisure) = incumbentUtilities(
            incumbents, distanceKm: distance, state: state, catalog: catalog)
        let out = tuning.outsideOptionWeight
        let business = utility(fareRatio: fareRatio, quality: quality,
                               sensitivity: tuning.priceSensitivityBusiness)
        let leisure = utility(fareRatio: fareRatio, quality: quality,
                              sensitivity: tuning.priceSensitivityLeisure)
        // Each segment: what the entrant takes with the incumbents there,
        // over what it would take alone — the pool scaled by that ratio.
        return pool.business * ((out + business) / (out + business + rivalsBusiness))
            + pool.leisure * ((out + leisure) / (out + leisure + rivalsLeisure))
    }

    // MARK: What a service would actually carry

    /// What one airframe flying a market would sell in a day, before it
    /// flies: the market's own pools, the demand engine's own split against
    /// the offers already there, and the seats the day's flights offer.
    ///
    /// `capturedPerDay` is the number `DemandSystem.allocate` would put on
    /// this route if it existed; `carriedPerDay` is what `FlightOpsSystem`
    /// would board, which is the smaller of that and the seats flown.
    public struct ServiceDemand: Equatable, Sendable {
        /// Both directions of the market's raw pool — mass, not passengers.
        public let poolPerDay: Double
        /// The share the logit split awards this offer, both directions.
        public let capturedPerDay: Double
        /// Seats the day's flights put on sale: `roundTrips × 2 × seats`.
        public let seatsPerDay: Double

        public init(poolPerDay: Double, capturedPerDay: Double, seatsPerDay: Double) {
            self.poolPerDay = poolPerDay
            self.capturedPerDay = capturedPerDay
            self.seatsPerDay = seatsPerDay
        }

        /// What the boarding step would actually sell.
        public var carriedPerDay: Double { min(capturedPerDay, seatsPerDay) }
        public var loadFactor: Double {
            seatsPerDay > 0 ? carriedPerDay / seatsPerDay : 0
        }
    }

    /// The demand an entrant's own service would win on a market — the one
    /// authoritative answer to "given *this* aircraft at *this* frequency
    /// against *these* incumbents, how many passengers?".
    ///
    /// It is `allocate` asked before the fact: the same pools, the same
    /// `offerQualityTerms`, the same per-segment logit share, both
    /// directions. MEASURED against the engine day by day over 336
    /// comparisons it lands within 1.4% of the allocation the engine
    /// performs, and on day one — before the world has drifted under it —
    /// 23 of 24 rows fall inside the two-passenger band the engine's own
    /// per-direction `Int(rounded(.down))` predicts
    /// (docs/AE044_AIRFRAME_VALUE_AUDIT.md §4).
    ///
    /// Before AE-044 the estimator took its passenger figure as an input
    /// that did not vary with the aircraft, so past the seat cap every
    /// airframe earned the same revenue and paid a larger cabin's costs —
    /// biased against large aircraft by construction, and wrong at six of
    /// the seven homes AE-043 flew (TD-033,
    /// docs/AE044_ROOT_CAUSE.md §3).
    ///
    /// Pure: reads `state`, mutates nothing, consumes no RNG. It does not
    /// forecast the world after today — no seasonality path, no economic
    /// drift, no tourism boost, and the incumbents keep today's fares and
    /// schedules (docs/AE044_DEMAND_ESTIMATOR_AUDIT.md §5).
    public static func serviceDemand(
        origin: AirportCode, destination: AirportCode, spec: AircraftTypeSpec,
        roundTripsPerDay: Int, fareRatio: Double,
        operationsScore: Double = unprovenOperationsScore,
        reputationMultiplier: Double = 1.0,
        incumbents: [Route], state: GameState,
        catalog: ContentCatalog) -> ServiceDemand {
        let tuning = catalog.tuning.demand
        let seats = Double(max(0, roundTripsPerDay) * 2 * spec.seats)
        guard roundTripsPerDay > 0, let distance = catalog.distanceKm(origin, destination)
        else { return ServiceDemand(poolPerDay: 0, capturedPerDay: 0, seatsPerDay: 0) }

        let quality = offerQualityTerms(
            spec: spec, roundTripsPerDay: roundTripsPerDay,
            operationsScore: operationsScore,
            reputationMultiplier: reputationMultiplier, tuning: tuning).product
        let business = utility(fareRatio: fareRatio, quality: quality,
                               sensitivity: tuning.priceSensitivityBusiness)
        let leisure = utility(fareRatio: fareRatio, quality: quality,
                              sensitivity: tuning.priceSensitivityLeisure)
        let rivals = incumbentUtilities(incumbents, distanceKm: distance,
                                        state: state, catalog: catalog)

        // Both directions: a day's flights carry passengers each way, and
        // the pools are not symmetric — leisure is origin's propensity to
        // travel times the destination's draw.
        var pool = 0.0, captured = 0.0
        for (from, to) in [(origin, destination), (destination, origin)] {
            let segment = demandPool(from: from, to: to, date: state.currentDate,
                                     economicIndex: state.world.economicIndex,
                                     catalog: catalog)
            pool += segment.total
            captured += segment.business
                * share(offer: business, everyOffer: business + rivals.business, tuning: tuning)
                + segment.leisure
                * share(offer: leisure, everyOffer: leisure + rivals.leisure, tuning: tuning)
        }
        return ServiceDemand(poolPerDay: pool, capturedPerDay: captured, seatsPerDay: seats)
    }

    /// Service quality of a representative starter operation, used for
    /// pre-flight estimates where no route exists yet: a mid-comfort
    /// aircraft flying the reference frequency with as-yet-unproven
    /// operations and a neutral reputation.
    public static func representativeStarterQuality(tuning: DemandTuning) -> Double {
        let schedule = pow(2.0 / tuning.scheduleQualityReferenceTrips,
                           tuning.scheduleQualityExponent)
        let comfort = tuning.comfortBase + tuning.comfortWeight * 0.55
        let operations = tuning.operationsBase
            + tuning.operationsWeight * unprovenOperationsScore
        return schedule * comfort * operations
    }

    /// The operations record a service that has not flown yet is credited
    /// with: neither the perfect 1.0 a brand-new `Route.Stats` reports nor a
    /// mature route's measured figure. AE-044 gave the constant a name and
    /// one definition; it is the same 0.8 `representativeStarterQuality` has
    /// always used, and nothing was re-tuned.
    public static let unprovenOperationsScore = 0.8

    /// Distance-anchored reference fare the market prices against.
    /// Public: the route-opening UI shows it so players price against the
    /// same anchor the simulation uses (docs/UI_ARCHITECTURE.md §2).
    public static func referenceFare(distanceKm: Int, tuning: DemandTuning) -> Double {
        tuning.fareBase + tuning.farePerKm * Double(distanceKm)
    }

    /// The day's directional demand pool, by segment.
    /// `tourismBoost` is the destination-region event boost (0 = none).
    /// Public since AE-040 so `ae-fee-baseline` can compare the AI's own
    /// forecast with the ledger; nothing in the app calls it.
    public static func demandPool(from: AirportCode, to: AirportCode, date: GameDate,
                           economicIndex: Double, tourismBoost: Double = 0,
                           catalog: ContentCatalog) -> SegmentDemand {
        guard let origin = catalog.airport(from), let destination = catalog.airport(to)
        else { return SegmentDemand(business: 0, leisure: 0) }
        let tuning = catalog.tuning.demand
        let distance = Double(Geo.distanceKm(from: origin.coordinate, to: destination.coordinate))

        // Gravity: sqrt of population product, attenuated by distance.
        let mass = (Double(origin.demographics.populationThousands)
            * Double(destination.demographics.populationThousands)).squareRoot()
        let attenuation = 1.0 / (1.0 + pow(distance / tuning.attenuationScaleKm,
                                           tuning.attenuationPower))
        let base = tuning.gravityConstant * mass * attenuation

        let business = base * tuning.businessWeight
            * origin.demographics.businessIndex * destination.demographics.businessIndex
            * tuning.weekdayBusinessFactor[date.weekday.rawValue]
            * pow(economicIndex, tuning.economyBusinessExponent)

        let season = catalog.seasonality[destination.seasonality]?
            .leisureMultiplier(month: date.month) ?? 1.0
        let leisure = base * tuning.leisureWeight
            * origin.demographics.leisureIndex * destination.demographics.tourismIndex
            * season * (1 + tourismBoost)
            * tuning.weekdayLeisureFactor[date.weekday.rawValue]
            * pow(economicIndex, tuning.economyLeisureExponent)

        return SegmentDemand(business: business, leisure: leisure)
    }
}

public struct SegmentDemand: Equatable, Sendable {
    public var business: Double
    public var leisure: Double

    public var total: Double { business + leisure }
}
