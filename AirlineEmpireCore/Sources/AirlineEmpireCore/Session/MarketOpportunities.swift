/// "Where should I fly next?", answered once.
///
/// `OnboardingModel` has always answered a narrow version of this — the two
/// best first routes from home, for a player with nothing. The map needs the
/// same question answered continuously and from the whole network: an empty
/// early-game map has nothing to show without it, and the demand overlay is
/// exactly this ranking drawn as geography.
///
/// Rather than let the map grow a second copy that drifts from the one the
/// onboarding card shows, the ranking lives here and both callers use it.
/// It is a pure derivation — no state, nothing persisted, and it never
/// mutates the world.

/// A market the player could open but has not.
public struct MarketOpportunity: Equatable, Sendable {
    public let origin: AirportCode
    public let destination: AirportCode
    public let destinationCity: String
    public let distanceKm: Int
    /// Passengers a representative starter service could expect to capture
    /// per day across both directions at the reference fare — the share the
    /// logit split actually awards, not the raw market pool, which is several
    /// times larger and would overstate the market (BUG-006).
    public let expectedDailyPassengers: Int
    /// The market reference fare at this distance (what "normal" costs).
    public let referenceFare: Money
    /// How many airlines already serve this city pair. Zero is an open
    /// market; three is a fight.
    public let incumbents: Int
    /// True when at least one aircraft the player owns could fly it today.
    /// False means the market is real but out of reach for this fleet.
    public let servableNow: Bool

    public init(origin: AirportCode, destination: AirportCode,
                destinationCity: String, distanceKm: Int,
                expectedDailyPassengers: Int, referenceFare: Money,
                incumbents: Int, servableNow: Bool) {
        self.origin = origin
        self.destination = destination
        self.destinationCity = destinationCity
        self.distanceKm = distanceKm
        self.expectedDailyPassengers = expectedDailyPassengers
        self.referenceFare = referenceFare
        self.incumbents = incumbents
        self.servableNow = servableNow
    }

    /// A first-route suggestion is an opportunity with the extra fields
    /// stripped; the onboarding card wants the narrower shape.
    public var asFirstRouteSuggestion: FirstRouteSuggestion {
        FirstRouteSuggestion(origin: origin, destination: destination,
                             destinationCity: destinationCity,
                             distanceKm: distanceKm,
                             expectedDailyPassengers: expectedDailyPassengers,
                             referenceFare: referenceFare)
    }
}

extension GameState {
    /// The best markets the player could open, ranked by capturable demand.
    ///
    /// Origins are the airports the player already touches (home included),
    /// because a route has to start where the airline has a presence.
    /// City pairs already served by the player are excluded — they are not
    /// opportunities, they are the network.
    ///
    /// Deterministic: ties break on origin then destination code, so the same
    /// world always proposes the same markets in the same order.
    public func marketOpportunities(catalog: ContentCatalog,
                                    limit: Int = 8) -> [MarketOpportunity] {
        guard limit > 0, let player = playerAirline else { return [] }

        // Where the airline can start from, and what it already flies.
        //
        // Origins are the airline's *bases* — home, plus anywhere it has built
        // three or more routes — not every airport it happens to touch. That
        // is how an airline actually expands, and it is also what makes this
        // affordable: scanning every spoke against all eighty airports was
        // 14 ms a call at late-game scale, on a model rebuilt every tick
        // (docs/MAP_ARCHITECTURE.md §11).
        var touchCounts: [AirportCode: Int] = [:]
        var served: Set<Route.Market> = []
        for route in routes(of: player.id) {
            touchCounts[route.origin, default: 0] += 1
            touchCounts[route.destination, default: 0] += 1
            served.insert(route.market)
        }
        var origins: Set<AirportCode> = [player.homeAirport]
        for (code, count) in touchCounts where count >= 3 { origins.insert(code) }
        // A hard ceiling, so a very large airline cannot make this expensive
        // again: the biggest bases first, ties on code for determinism.
        if origins.count > 5 {
            origins = Set(origins.sorted {
                let a = touchCounts[$0] ?? 0, b = touchCounts[$1] ?? 0
                return a != b ? a > b : $0.raw < $1.raw
            }.prefix(5))
        }
        guard catalog.airport(player.homeAirport) != nil else { return [] }

        // Capability basis: what the fleet can fly, or — for an airline with
        // no aircraft yet — what this era would let it buy.
        let ownedSpecs = fleet(of: player.id)
            .compactMap { catalog.aircraftType($0.typeCode) }
        let eraSpecs = catalog.orderedAircraftTypeCodes
            .compactMap { catalog.aircraftType($0) }
            .filter { progression.era.allowedCategories.contains($0.category) }
        let candidateSpecs = ownedSpecs.isEmpty ? eraSpecs : ownedSpecs
        guard !candidateSpecs.isEmpty else { return [] }

        let date = currentDate
        let quality = DemandSystem.representativeStarterQuality(
            tuning: catalog.tuning.demand)

        var scored: [(MarketOpportunity, Double)] = []
        for origin in origins.sorted(by: { $0.raw < $1.raw }) {
            for code in catalog.orderedAirportCodes where code != origin {
                guard !served.contains(Route.market(origin, code)),
                      let distance = catalog.distanceKm(origin, code)
                else { continue }
                // Per aircraft, never the best range paired with the least
                // demanding runway: that chimera proposes routes no single
                // aircraft can serve, and every assignment would be rejected.
                let servable = candidateSpecs.contains { spec in
                    catalog.routeEligibility(
                        from: origin, to: code,
                        aircraftRangeKm: spec.rangeKm,
                        aircraftRunwayRequirement: spec.runwayRequirement).isEmpty
                }
                guard servable || ownedSpecs.isEmpty else { continue }

                let outbound = DemandSystem.expectedCapturedPassengers(
                    pool: DemandSystem.demandPool(from: origin, to: code, date: date,
                                                  economicIndex: world.economicIndex,
                                                  catalog: catalog),
                    fareRatio: 1.0, quality: quality, tuning: catalog.tuning.demand)
                let inbound = DemandSystem.expectedCapturedPassengers(
                    pool: DemandSystem.demandPool(from: code, to: origin, date: date,
                                                  economicIndex: world.economicIndex,
                                                  catalog: catalog),
                    fareRatio: 1.0, quality: quality, tuning: catalog.tuning.demand)
                let pool = outbound + inbound
                guard pool > 0 else { continue }

                let incumbents = airlinesServing(origin, code)
                let fare = DemandSystem.referenceFare(distanceKm: distance,
                                                      tuning: catalog.tuning.demand)
                let opportunity = MarketOpportunity(
                    origin: origin, destination: code,
                    destinationCity: catalog.airport(code)?.city ?? code.raw,
                    distanceKm: distance,
                    expectedDailyPassengers: Int(pool.rounded()),
                    referenceFare: Money(rounding: fare),
                    incumbents: incumbents,
                    servableNow: servable)
                // A contested market is worth less than an open one of the
                // same size; the player still sees it, just ranked lower.
                scored.append((opportunity, pool / Double(1 + incumbents)))
            }
        }

        return scored
            .sorted { lhs, rhs in
                lhs.1 != rhs.1 ? lhs.1 > rhs.1
                    : (lhs.0.origin.raw, lhs.0.destination.raw)
                        < (rhs.0.origin.raw, rhs.0.destination.raw)
            }
            .prefix(limit)
            .map(\.0)
    }

    /// How many airlines already fly a city pair, in either direction.
    public func airlinesServing(_ a: AirportCode, _ b: AirportCode) -> Int {
        var carriers = Set<AirlineID>()
        for id in orderedRouteIDs {
            guard let route = routes[id], route.sameMarket(origin: a, destination: b)
            else { continue }
            carriers.insert(route.airline)
        }
        return carriers.count
    }
}

extension Route {
    /// A direction-free city pair, so "already served" is not fooled by a
    /// route stored the other way round.
    public struct Market: Hashable, Sendable {
        public let a: AirportCode
        public let b: AirportCode
    }

    public static func market(_ x: AirportCode, _ y: AirportCode) -> Market {
        x.raw <= y.raw ? Market(a: x, b: y) : Market(a: y, b: x)
    }

    public var market: Market { Route.market(origin, destination) }
}
