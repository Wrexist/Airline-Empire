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
    /// True when some aircraft of the current era could fly it — so a market
    /// that is not servable *now* still divides into "buy or lease the right
    /// aircraft" and "a route for a later era". The AE-035 campaign opened
    /// ARN–Addis Ababa (5,850 km, beyond every startup airframe) and watched
    /// it sit unflown for two months; the sheet's warning could not say
    /// which kind of impossible it was.
    public let servableByEra: Bool
    /// The airframe this market is best flown with, of the ones the airline
    /// could operate — its own types if it has any, the era's if not — and
    /// what a month on it would keep after that airframe's lease and the
    /// crew and route payroll the economy charges for having it.
    ///
    /// Nil when nothing available can fly the pair. AE-042 measured why this
    /// has to be part of the answer rather than left to the player: at 9 of
    /// 93 homes a market that keeps $141k a month on a 90-seat regional jet
    /// loses $703k on the 184-seat narrowbody the aircraft market's default
    /// sort offers first (docs/AE042_NEXT_MOVES_BASELINE.md §6).
    public let bestAirframe: AircraftTypeCode?
    /// A month of this market's own operating result on `bestAirframe`, less
    /// that airframe's monthly lease, the crew it carries and the route's own
    /// payroll. Zero when nothing can fly it.
    ///
    /// Airline overhead is deliberately not charged here: the figure answers
    /// "does this route pay for the aircraft it needs", not "what is the
    /// airline worth". Measured against six months of real ledger on seven
    /// pairs, it errs generous by $0.3–0.8M a month
    /// (docs/AE042_NEXT_MOVES_BASELINE.md §3).
    public let monthlyAfterAirframe: Money

    /// Whether the market clears the airframe it needs. The one boundary the
    /// recommendation depends on, and not a tuned one: below it the route
    /// cannot pay for the aircraft that flies it.
    public var paysForItsAirframe: Bool { monthlyAfterAirframe > .zero }

    public init(origin: AirportCode, destination: AirportCode,
                destinationCity: String, distanceKm: Int,
                expectedDailyPassengers: Int, referenceFare: Money,
                incumbents: Int, servableNow: Bool,
                servableByEra: Bool = true,
                bestAirframe: AircraftTypeCode? = nil,
                monthlyAfterAirframe: Money = .zero) {
        self.origin = origin
        self.destination = destination
        self.destinationCity = destinationCity
        self.distanceKm = distanceKm
        self.expectedDailyPassengers = expectedDailyPassengers
        self.referenceFare = referenceFare
        self.incumbents = incumbents
        self.servableNow = servableNow
        self.servableByEra = servableByEra
        self.bestAirframe = bestAirframe
        self.monthlyAfterAirframe = monthlyAfterAirframe
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
    /// What a market would keep in a month on the best airframe available to
    /// this airline, after that airframe's lease and the crew it carries.
    ///
    /// The arithmetic is the flight system's own, ahead of time — the same
    /// `CompetitorAISystem.airframeDayEstimate` the rivals decide on,
    /// corrected in AE-040 and measured against six months of ledger on
    /// seven pairs in AE-042. There is one economy in this game and this is
    /// it; nothing is re-derived here.
    ///
    /// AE-044: the passenger figure is no longer supplied by the caller.
    /// It was one number per market, reused for every candidate airframe, so
    /// past the seat cap every airframe earned the same revenue and paid a
    /// larger cabin's costs — the estimator could not rank airframes at all
    /// (TD-033, docs/AE044_ROOT_CAUSE.md). Each airframe is now priced on
    /// the demand its own service would win, against the incumbents actually
    /// on the pair.
    ///
    /// `incumbents` are the offers already on the pair. The callers below
    /// index every route by market once and pass the slice, because this is
    /// called once per candidate market on a model the map rebuilds every
    /// tick — scanning the route table per market was the shape that made
    /// the ranking expensive in the first place (docs/MAP_ARCHITECTURE.md §11).
    ///
    /// Returns nil when no available airframe can fly the pair.
    func airframeResult(from origin: AirportCode, to destination: AirportCode,
                        distanceKm: Int,
                        candidateSpecs: [AircraftTypeSpec],
                        incumbents: [Route],
                        catalog: ContentCatalog) -> (spec: AircraftTypeSpec, monthly: Money)? {
        guard let originSpec = catalog.airport(origin),
              let destinationSpec = catalog.airport(destination) else { return nil }
        let reputation = playerAirline?.reputation
            .demandMultiplier(tuning: catalog.tuning.reputation) ?? 1.0
        // The two monthly costs the economy charges for having this route at
        // all: the crew on its airframe and the route's own payroll
        // (`EconomySystem`). Airline overhead is deliberately left out — it
        // is charged once for the airline, not once per market — which is
        // why the figure reads a little generous against a real month
        // (docs/AE042_RECOMMENDATION_AUDIT.md §2).
        let payroll = catalog.tuning.finance.payrollPerAircraftMonthly.asDouble
            + catalog.tuning.finance.payrollPerRouteMonthly.asDouble
        var best: (spec: AircraftTypeSpec, monthly: Double)?
        for spec in candidateSpecs {
            guard catalog.routeEligibility(
                from: origin, to: destination,
                aircraftRangeKm: spec.rangeKm,
                aircraftRunwayRequirement: spec.runwayRequirement).isEmpty else { continue }
            let perDay = CompetitorAISystem.airframeDayEstimate(
                origin: originSpec, destination: destinationSpec, distanceKm: distanceKm,
                spec: spec, fareRatio: 1.0, serviceTier: .standard,
                reputationMultiplier: reputation, incumbents: incumbents,
                state: self, catalog: catalog, basis: .profit).value
            let monthly = perDay * 30 - spec.leaseMonthly.asDouble - payroll
            if best == nil || monthly > best!.monthly { best = (spec, monthly) }
        }
        return best.map { ($0.spec, Money(rounding: $0.monthly)) }
    }

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

        let carrierCounts = carrierCountByMarket()
        let routesByMarket = routesByMarket()
        var scored: [(MarketOpportunity, Double, Double)] = []
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

                let incumbents = carrierCounts[Route.market(origin, code)] ?? 0
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
                // The ranking is unchanged by AE-044 — only the economics
                // below it are; the third slot is the unpenalised pool, kept
                // for diagnostics.
                scored.append((opportunity, pool / Double(1 + incumbents), pool))
            }
        }

        let ranked = scored.sorted { lhs, rhs in
            lhs.1 != rhs.1 ? lhs.1 > rhs.1
                : (lhs.0.origin.raw, lhs.0.destination.raw)
                    < (rhs.0.origin.raw, rhs.0.destination.raw)
        }

        // Demand decides the order; paying for its own aircraft decides
        // whether a market is offered at all.
        //
        // AE-042 measured what ranking on passengers alone recommends: at 21
        // of the 93 homes a player can pick, the first suggestion either
        // loses money after the airframe it needs or cannot be flown by
        // anything the era sells. The fare rises with distance and the two
        // movement fees do not, so the densest short pairs — Manchester to
        // London at 96% of revenue in fees, London to Paris at 85% — sort to
        // the top of a passenger ranking and to the bottom of an economic
        // one (docs/AE042_BUG055_ROOT_CAUSE.md). The rivals stopped ranking
        // this way in AE-039 for the same reason.
        //
        // The gate is not a filter: markets that pay come first, and a home
        // with too few of them still sees the rest, so nothing is hidden and
        // no player is stranded without a first route to open. Pricing stops
        // as soon as `limit` qualifying markets are in hand, so the usual
        // cost is a handful of evaluations rather than one per market.
        var qualifying: [MarketOpportunity] = []
        var rest: [MarketOpportunity] = []
        for (opportunity, _, _) in ranked {
            guard qualifying.count < limit else { break }
            let result = airframeResult(
                from: opportunity.origin, to: opportunity.destination,
                distanceKm: opportunity.distanceKm,
                candidateSpecs: candidateSpecs,
                incumbents: routesByMarket[Route.market(opportunity.origin,
                                                        opportunity.destination)] ?? [],
                catalog: catalog)
            let priced = MarketOpportunity(
                origin: opportunity.origin, destination: opportunity.destination,
                destinationCity: opportunity.destinationCity,
                distanceKm: opportunity.distanceKm,
                expectedDailyPassengers: opportunity.expectedDailyPassengers,
                referenceFare: opportunity.referenceFare,
                incumbents: opportunity.incumbents,
                servableNow: opportunity.servableNow,
                servableByEra: opportunity.servableByEra,
                bestAirframe: result?.spec.code,
                monthlyAfterAirframe: result?.monthly ?? .zero)
            if priced.paysForItsAirframe {
                qualifying.append(priced)
            } else if rest.count < limit {
                rest.append(priced)
            }
        }
        return qualifying.count >= limit
            ? qualifying
            : qualifying + rest.prefix(limit - qualifying.count)
    }

    /// Every destination reachable from `origin`, ranked by capturable demand.
    ///
    /// The same arithmetic as `marketOpportunities`, with two differences: the
    /// caller chooses the origin rather than it being one of the airline's
    /// bases, and markets the player already serves are **included** — opening
    /// a second route on a pair is a legitimate move, and the route sheet is
    /// where it would be made.
    ///
    /// This exists because the route sheet needs to rank by demand and show
    /// the figure, and the alternative was making `DemandSystem.demandPool`
    /// public so a SwiftUI view could do the arithmetic itself. That would
    /// have put economics in a view and taken it out of reach of the test
    /// suite; this keeps the seam the whole project is built on.
    public func marketCandidates(from origin: AirportCode,
                                 catalog: ContentCatalog) -> [MarketOpportunity] {
        guard let player = playerAirline, catalog.airport(origin) != nil else {
            return []
        }
        let ownedSpecs = fleet(of: player.id)
            .compactMap { catalog.aircraftType($0.typeCode) }
        let eraSpecs = catalog.orderedAircraftTypeCodes
            .compactMap { catalog.aircraftType($0) }
            .filter { progression.era.allowedCategories.contains($0.category) }
        let date = currentDate
        let quality = DemandSystem.representativeStarterQuality(
            tuning: catalog.tuning.demand)

        let carrierCounts = carrierCountByMarket()
        let routesByMarket = routesByMarket()
        var out: [MarketOpportunity] = []
        for code in catalog.orderedAirportCodes where code != origin {
            guard let distance = catalog.distanceKm(origin, code) else { continue }
            // Per aircraft, never the best range paired with the least
            // demanding runway — the same rule `marketOpportunities` follows,
            // and for the same reason (BUG-006's neighbourhood).
            func eligible(_ specs: [AircraftTypeSpec]) -> Bool {
                specs.contains { spec in
                    catalog.routeEligibility(
                        from: origin, to: code,
                        aircraftRangeKm: spec.rangeKm,
                        aircraftRunwayRequirement: spec.runwayRequirement).isEmpty
                }
            }
            let servable = eligible(ownedSpecs)
            let servableByEra = servable || eligible(eraSpecs)
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
            let fare = DemandSystem.referenceFare(distanceKm: distance,
                                                  tuning: catalog.tuning.demand)
            // The sheet lists every destination on purpose, in demand order —
            // opening a route the numbers dislike is the player's to make.
            // It carries the same airframe verdict `marketOpportunities`
            // gates on, so the screen can say what a market needs rather
            // than leaving the player to find out from the ledger.
            let result = airframeResult(
                from: origin, to: code, distanceKm: distance,
                candidateSpecs: ownedSpecs.isEmpty ? eraSpecs : ownedSpecs,
                incumbents: routesByMarket[Route.market(origin, code)] ?? [],
                catalog: catalog)
            out.append(MarketOpportunity(
                origin: origin, destination: code,
                destinationCity: catalog.airport(code)?.city ?? code.raw,
                distanceKm: distance,
                expectedDailyPassengers: Int((outbound + inbound).rounded()),
                referenceFare: Money(rounding: fare),
                incumbents: carrierCounts[Route.market(origin, code)] ?? 0,
                servableNow: servable, servableByEra: servableByEra,
                bestAirframe: result?.spec.code,
                monthlyAfterAirframe: result?.monthly ?? .zero))
        }
        // Demand first, then reachability, then code — deterministic, and the
        // order the route sheet's own header has always claimed.
        return out.sorted { lhs, rhs in
            if lhs.expectedDailyPassengers != rhs.expectedDailyPassengers {
                return lhs.expectedDailyPassengers > rhs.expectedDailyPassengers
            }
            if lhs.servableNow != rhs.servableNow { return lhs.servableNow }
            return lhs.destination.raw < rhs.destination.raw
        }
    }

    /// How many airlines already fly a city pair, in either direction.
    /// Carrier counts for every served market, in one pass over the routes.
    ///
    /// `airlinesServing` scans every route per call, and the pair loops below
    /// call it once per candidate market — so the cost was
    /// O(origins x airports x routes) on a model that is rebuilt every tick.
    /// The origin cap bounds the pairs, not the scan inside each one.
    func carrierCountByMarket() -> [Route.Market: Int] {
        var carriers: [Route.Market: Set<AirlineID>] = [:]
        for id in orderedRouteIDs {
            guard let route = routes[id] else { continue }
            carriers[route.market, default: []].insert(route.airline)
        }
        return carriers.mapValues(\.count)
    }

    /// Every route, grouped by the market it serves, in one deterministic
    /// pass — the offers an entrant would face, ready for
    /// `DemandSystem.serviceDemand`.
    func routesByMarket() -> [Route.Market: [Route]] {
        var out: [Route.Market: [Route]] = [:]
        for id in orderedRouteIDs {
            guard let route = routes[id] else { continue }
            out[route.market, default: []].append(route)
        }
        return out
    }

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
