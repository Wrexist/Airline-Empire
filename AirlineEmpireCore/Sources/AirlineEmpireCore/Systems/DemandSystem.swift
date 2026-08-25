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
        let tuning = catalog.tuning.demand
        guard let firstAircraft = route.assignedAircraft.sorted()
            .compactMap({ state.aircraft[$0] }).first,
            let spec = catalog.aircraftType(firstAircraft.typeCode) else { return nil }

        // Frequency helps with hard diminishing returns beyond ~4/day
        // (docs/GAME_BALANCE.md §5 anti-frequency-spam).
        let trips = Double(min(route.dailyRoundTrips, tuning.scheduleQualityTripCap))
        let schedule = pow(trips / tuning.scheduleQualityReferenceTrips,
                           tuning.scheduleQualityExponent)

        let comfort = tuning.comfortBase + tuning.comfortWeight * spec.comfortBaseline
        let operations = tuning.operationsBase + tuning.operationsWeight
            * (route.stats.completionRate * 0.5 + route.stats.punctuality * 0.5)
        let reputation = state.airlines[route.airline]?.reputation
            .demandMultiplier(tuning: catalog.tuning.reputation) ?? 1.0
        return schedule * comfort * operations * reputation
    }

    /// Distance-anchored reference fare the market prices against.
    static func referenceFare(distanceKm: Int, tuning: DemandTuning) -> Double {
        tuning.fareBase + tuning.farePerKm * Double(distanceKm)
    }

    /// The day's directional demand pool, by segment.
    /// `tourismBoost` is the destination-region event boost (0 = none).
    static func demandPool(from: AirportCode, to: AirportCode, date: GameDate,
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
