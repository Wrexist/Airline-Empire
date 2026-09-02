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
            business.append(exp(tuning.priceSensitivityBusiness * (1 - ratio)) * quality)
            leisure.append(exp(tuning.priceSensitivityLeisure * (1 - ratio)) * quality)
        }

        let sumB = business.reduce(0, +)
        let sumL = leisure.reduce(0, +)
        let out = tuning.outsideOptionWeight

        for (index, routeID) in routeIDs.enumerated() {
            var route = state.routes[routeID]!
            let served = pool.business * (sumB > 0 ? business[index] / (out + sumB) : 0)
                + pool.leisure * (sumL > 0 ? leisure[index] / (out + sumL) : 0)
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
        let tuning = catalog.tuning.demand
        guard let firstAircraft = route.assignedAircraft.sorted()
            .compactMap({ state.aircraft[$0] }).first,
            let spec = catalog.aircraftType(firstAircraft.typeCode) else { return nil }

        let trips = Double(min(route.dailyRoundTrips, tuning.scheduleQualityTripCap))
        let schedule = pow(trips / tuning.scheduleQualityReferenceTrips,
                           tuning.scheduleQualityExponent)

        let comfort = tuning.comfortBase + tuning.comfortWeight * spec.comfortBaseline
        let operations = tuning.operationsBase + tuning.operationsWeight
            * (route.stats.completionRate * 0.5 + route.stats.punctuality * 0.5)
        let reputation = state.airlines[route.airline]?.reputation
            .demandMultiplier(tuning: catalog.tuning.reputation) ?? 1.0
        return OfferQualityTerms(schedule: schedule, comfort: comfort,
                                 operations: operations, reputation: reputation)
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
        let out = tuning.outsideOptionWeight
        let business = exp(tuning.priceSensitivityBusiness * (1 - fareRatio)) * quality
        let leisure = exp(tuning.priceSensitivityLeisure * (1 - fareRatio)) * quality
        return pool.business * (business / (out + business))
            + pool.leisure * (leisure / (out + leisure))
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
        let refFare = referenceFare(distanceKm: distance, tuning: tuning)
        var rivalsBusiness = 0.0, rivalsLeisure = 0.0
        for route in incumbents {
            guard let rivalQuality = offerQualityTerms(route: route, state: state,
                                                       catalog: catalog)?.product
            else { continue }
            let ratio = route.ticketPrice.asDouble / refFare
            rivalsBusiness += exp(tuning.priceSensitivityBusiness * (1 - ratio)) * rivalQuality
            rivalsLeisure += exp(tuning.priceSensitivityLeisure * (1 - ratio)) * rivalQuality
        }
        let out = tuning.outsideOptionWeight
        let business = exp(tuning.priceSensitivityBusiness * (1 - fareRatio)) * quality
        let leisure = exp(tuning.priceSensitivityLeisure * (1 - fareRatio)) * quality
        // Each segment: what the entrant takes with the incumbents there,
        // over what it would take alone — the pool scaled by that ratio.
        return pool.business * ((out + business) / (out + business + rivalsBusiness))
            + pool.leisure * ((out + leisure) / (out + leisure + rivalsLeisure))
    }

    /// Service quality of a representative starter operation, used for
    /// pre-flight estimates where no route exists yet: a mid-comfort
    /// aircraft flying the reference frequency with as-yet-unproven
    /// operations and a neutral reputation.
    public static func representativeStarterQuality(tuning: DemandTuning) -> Double {
        let schedule = pow(2.0 / tuning.scheduleQualityReferenceTrips,
                           tuning.scheduleQualityExponent)
        let comfort = tuning.comfortBase + tuning.comfortWeight * 0.55
        let operations = tuning.operationsBase + tuning.operationsWeight * 0.8
        return schedule * comfort * operations
    }

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
