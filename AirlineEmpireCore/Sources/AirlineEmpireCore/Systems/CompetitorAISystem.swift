/// AI airline decision-making (docs/AI.md). Each AI gets one decision slot
/// per `decisionIntervalDays`, staggered by airline ID so the market moves
/// continuously rather than in lockstep. All actions are ordinary commands
/// run through their own validators — a rejected decision simply doesn't
/// happen, exactly as for the player.
public struct CompetitorAISystem: SimulationSystem {
    public let id = "competitorAI"
    public let cadence = Cadence.daily

    public init() {}

    public func update(state: inout GameState, context: SimContext) {
        let tuning = context.catalog.tuning.ai
        for airlineID in state.orderedAirlineIDs {
            guard let airline = state.airlines[airlineID],
                  airline.kind == .ai, airline.status == .active,
                  let profile = airline.aiProfile,
                  (state.clock.now.dayIndex + airlineID.raw)
                      % Int64(tuning.decisionIntervalDays) == 0
            else { continue }
            decide(airlineID: airlineID, profile: profile,
                   state: &state, context: context, tuning: tuning)
        }
    }

    // MARK: Decision procedure (priority-ordered)

    private func decide(airlineID: AirlineID, profile: AIProfile,
                        state: inout GameState, context: SimContext, tuning: AITuning) {
        let runway = cashRunwayMonths(airlineID, state: state, context: context)

        // 1. Survival: deep trouble -> shed the worst loss-maker and idle metal.
        if runway < tuning.retrenchRunwayMonths {
            retrench(airlineID, state: &state, context: context)
            return
        }

        // 2. Put idle aircraft to work.
        if let idle = state.fleet(of: airlineID).first(where: {
            $0.isOperational && $0.assignedRoute == nil && $0.activeFlight == nil
        }) {
            employ(idle, airlineID: airlineID, profile: profile,
                   state: &state, context: context, tuning: tuning)
            return
        }

        // 3. Tune the network: pricing responses and frequency.
        manageRoutes(airlineID, profile: profile, state: &state,
                     context: context, tuning: tuning)

        // 4. Grow when healthy.
        if runway >= profile.expandRunwayMonths,
           state.fleet(of: airlineID).count < tuning.maxFleetPerAirline {
            acquireAircraft(airlineID, profile: profile, state: &state,
                            context: context)
        }
    }

    // MARK: Health

    private func cashRunwayMonths(_ airlineID: AirlineID, state: GameState,
                                  context: SimContext) -> Double {
        let balance = state.ledger.balance(of: airlineID).asDouble
        let costs: Double
        if let statement = state.finance.byAirline[airlineID]?.latest {
            costs = max(1, -statement.operatingExpenses.asDouble
                - statement.financingCost.asDouble)
        } else {
            // Pre-statement estimate: overhead + payroll + lease burden.
            let finance = context.catalog.tuning.finance
            var estimate = finance.overheadBaseMonthly.asDouble
            for aircraft in state.fleet(of: airlineID) {
                estimate += finance.payrollPerAircraftMonthly.asDouble
                if case .leased(let rate, _) = aircraft.ownership {
                    estimate += rate.asDouble
                }
            }
            costs = max(1, estimate)
        }
        return balance / costs
    }

    private func retrench(_ airlineID: AirlineID, state: inout GameState,
                          context: SimContext) {
        // Close the biggest loss-maker (closed month figures).
        let routes = state.routes(of: airlineID)
        if let worst = routes.min(by: {
            $0.economicsLastMonth.directOperatingProfit < $1.economicsLastMonth.directOperatingProfit
        }), worst.economicsLastMonth.directOperatingProfit < .zero {
            issue(CloseRouteCommand(airline: airlineID, route: worst.id),
                  state: &state, context: context)
        }
        // Shed idle metal: return leases, sell owned.
        for aircraft in state.fleet(of: airlineID)
        where aircraft.assignedRoute == nil && aircraft.isOperational
            && aircraft.activeFlight == nil {
            if aircraft.ownership.isLeased {
                issue(ReturnLeasedAircraftCommand(lessee: airlineID, aircraftID: aircraft.id),
                      state: &state, context: context)
            } else {
                issue(SellAircraftCommand(seller: airlineID, aircraftID: aircraft.id),
                      state: &state, context: context)
            }
        }
    }

    // MARK: Network

    private func employ(_ aircraft: Aircraft, airlineID: AirlineID, profile: AIProfile,
                        state: inout GameState, context: SimContext, tuning: AITuning) {
        // Prefer thickening an existing route that is running hot — but only
        // one whose assigned aircraft cannot already fly its frequency. A
        // route pinned at full load is hot forever, and a route at the
        // frequency cap absorbed every airframe its airline ever bought:
        // measured over five years, no rival opened a second route and one
        // carried sixteen aircraft on a pair that could use ten
        // (docs/RIVAL_PRESSURE_AUDIT.md §3, BUG-042).
        if let hot = state.routes(of: airlineID).first(where: {
            $0.stats.loadFactor > tuning.expandLoadFactor && $0.stats.seatsFlown > 0
                && routeNeedsAnotherAircraft($0, state: state, context: context)
        }), routeServableBy(aircraft, route: hot, state: state, context: context) {
            issue(AssignAircraftToRouteCommand(airline: airlineID, route: hot.id,
                                               aircraftID: aircraft.id),
                  state: &state, context: context)
            return
        }
        // Otherwise open the best new market from an airport we sit at.
        guard let spec = context.catalog.aircraftType(aircraft.typeCode) else { return }
        let airline = state.airlines[airlineID]!
        guard let candidate = bestMarket(from: aircraft.location, airline: airline,
                                         spec: spec, profile: profile,
                                         state: state, context: context, tuning: tuning)
        else { return }
        let reference = DemandSystem.referenceFare(
            distanceKm: candidate.distanceKm, tuning: context.catalog.tuning.demand)
        let fare = Money(rounding: reference * profile.priceFactor)
        if issue(OpenRouteCommand(airline: airlineID, origin: aircraft.location,
                                  destination: candidate.destination,
                                  dailyRoundTrips: tuning.initialRoundTrips,
                                  ticketPrice: fare),
                 state: &state, context: context) {
            if let route = state.routes.values.first(where: {
                $0.airline == airlineID
                    && $0.sameMarket(origin: aircraft.location,
                                     destination: candidate.destination)
            }) {
                issue(AssignAircraftToRouteCommand(airline: airlineID, route: route.id,
                                                   aircraftID: aircraft.id),
                      state: &state, context: context)
            }
        }
    }

    private struct MarketCandidate {
        let destination: AirportCode
        let distanceKm: Int
        let score: Double
    }

    /// Deterministic candidate scoring: the pool an entrant could plan
    /// against with the incumbents' real offers in the way, gated by
    /// eligibility and archetype geography.
    ///
    /// Until AE-038 the score halved per incumbent (`pool / (n + 1)`), and
    /// the seed scan measured what that did: across 240 two-year campaigns
    /// from eight homes, no rival ever entered a pair the player flew
    /// except New York–Chicago, the one pair large enough to win at half
    /// value — even from Singapore, where five rivals had the player's
    /// home in their candidate set (docs/RIVALS_THAT_COME_TO_YOU_AUDIT.md).
    /// The demand engine gives a second entrant nearer two thirds than a
    /// half, so the AI now asks the engine, and an open pair still scores
    /// exactly as before.
    private func bestMarket(from origin: AirportCode, airline: Airline,
                            spec: AircraftTypeSpec, profile: AIProfile,
                            state: GameState, context: SimContext,
                            tuning: AITuning) -> MarketCandidate? {
        let catalog = context.catalog
        guard let originSpec = catalog.airport(origin) else { return nil }
        // The offer this airline would put on a new pair: a starter
        // operation at its archetype's fare, carrying its own reputation.
        let entrantQuality = DemandSystem.representativeStarterQuality(
            tuning: catalog.tuning.demand)
            * airline.reputation.demandMultiplier(tuning: catalog.tuning.reputation)
        var best: MarketCandidate?
        for (destinationSpec, distance) in catalog.nearestAirports(
            to: origin, limit: tuning.candidateMarketLimit) {
            let destination = destinationSpec.code
            if profile.homeRegionOnly && destinationSpec.region != originSpec.region {
                continue
            }
            guard catalog.routeEligibility(from: origin, to: destination,
                                           aircraftRangeKm: spec.rangeKm,
                                           aircraftRunwayRequirement: spec.runwayRequirement)
                .isEmpty else { continue }
            // Already served by us?
            if state.routes.values.contains(where: {
                $0.airline == airline.id
                    && $0.sameMarket(origin: origin, destination: destination)
            }) { continue }
            // Slots for the initial frequency at both ends?
            let movements = Route.dailySlotMovements(roundTrips: tuning.initialRoundTrips)
            if state.world.slotsUsed(at: origin) + movements > originSpec.slotCapacityPerDay
                || state.world.slotsUsed(at: destination) + movements
                    > destinationSpec.slotCapacityPerDay { continue }

            let pool = DemandSystem.demandPool(from: origin, to: destination,
                                               date: state.currentDate,
                                               economicIndex: state.world.economicIndex,
                                               catalog: catalog)
            let incumbents = state.routes.values.filter {
                $0.sameMarket(origin: origin, destination: destination)
            }
            let score = DemandSystem.poolAvailableToEntrant(
                pool: pool, fareRatio: profile.priceFactor, quality: entrantQuality,
                incumbents: incumbents, state: state, catalog: catalog)
            guard score >= tuning.minViableDailyDemand else { continue }
            if best == nil || score > best!.score {
                best = MarketCandidate(destination: destination,
                                       distanceKm: distance, score: score)
            }
        }
        return best
    }

    /// Whether the route's frequency target exceeds what its assigned
    /// aircraft can fly in a day — the scheduler's own capacity arithmetic.
    private func routeNeedsAnotherAircraft(_ route: Route, state: GameState,
                                           context: SimContext) -> Bool {
        let assigned = route.assignedAircraft.sorted().compactMap { state.aircraft[$0] }
        guard let first = assigned.first,
              let spec = context.catalog.aircraftType(first.typeCode) else { return true }
        let perAircraft = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
            distanceKm: route.distanceKm, spec: spec, ops: context.catalog.tuning.ops)
        guard perAircraft > 0 else { return false }
        return perAircraft * assigned.count < route.dailyRoundTrips
    }

    private func routeServableBy(_ aircraft: Aircraft, route: Route,
                                 state: GameState, context: SimContext) -> Bool {
        guard let spec = context.catalog.aircraftType(aircraft.typeCode) else { return false }
        if route.distanceKm > spec.rangeKm { return false }
        for end in [route.origin, route.destination] {
            guard let airport = context.catalog.airport(end) else { return false }
            if airport.runwayClass < spec.runwayRequirement { return false }
        }
        return true
    }

    private func manageRoutes(_ airlineID: AirlineID, profile: AIProfile,
                              state: inout GameState, context: SimContext,
                              tuning: AITuning) {
        for route in state.routes(of: airlineID) {
            // Pricing response to competitors on the same market.
            let rivals = state.routes.values.filter {
                $0.airline != airlineID
                    && $0.sameMarket(origin: route.origin, destination: route.destination)
            }
            if let cheapest = rivals.map(\.ticketPrice).min(),
               cheapest.asDouble < route.ticketPrice.asDouble
                   * (1 - tuning.undercutResponseThreshold) {
                let reference = DemandSystem.referenceFare(
                    distanceKm: route.distanceKm, tuning: context.catalog.tuning.demand)
                let response = Money(rounding: profile.priceResponse(
                    referenceFare: reference, competitorFare: cheapest.asDouble))
                if response != route.ticketPrice {
                    issue(SetRoutePriceCommand(airline: airlineID, route: route.id,
                                               ticketPrice: response),
                          state: &state, context: context)
                }
            }

            // Frequency: push winners, trim losers.
            guard route.stats.seatsFlown > 500 else { continue }
            if route.stats.loadFactor > tuning.expandLoadFactor,
               route.dailyRoundTrips < 20 {
                issue(SetRouteFrequencyCommand(airline: airlineID, route: route.id,
                                               dailyRoundTrips: route.dailyRoundTrips + 1),
                      state: &state, context: context)
            } else if route.stats.loadFactor < tuning.shrinkLoadFactor {
                if route.dailyRoundTrips > 1 {
                    issue(SetRouteFrequencyCommand(airline: airlineID, route: route.id,
                                                   dailyRoundTrips: route.dailyRoundTrips - 1),
                          state: &state, context: context)
                } else if route.economicsLastMonth.directOperatingProfit < .zero {
                    issue(CloseRouteCommand(airline: airlineID, route: route.id),
                          state: &state, context: context)
                }
            }
        }
    }

    // MARK: Fleet

    private func acquireAircraft(_ airlineID: AirlineID, profile: AIProfile,
                                 state: inout GameState, context: SimContext) {
        let catalog = context.catalog
        // Cheapest type in the preferred categories (deterministic order).
        let candidates = catalog.orderedAircraftTypeCodes
            .compactMap { catalog.aircraftTypes[$0] }
            .filter { profile.preferredCategories.contains($0.category) }
            .sorted { ($0.listPrice, $0.code) < ($1.listPrice, $1.code) }
        guard let type = candidates.first else { return }

        if profile.prefersLeasing {
            if issue(LeaseAircraftCommand(lessee: airlineID, type: type.code,
                                          termMonths: 60),
                     state: &state, context: context) { return }
        }
        if issue(BuyUsedAircraftCommand(buyer: airlineID, type: type.code,
                                        ageYears: profile.usedAgeYears),
                 state: &state, context: context) { return }

        // Can't afford it outright: borrow if the archetype tolerates debt.
        let airline = state.airlines[airlineID]!
        let price = FleetEconomics.usedPrice(
            type: type, ageYears: Double(profile.usedAgeYears),
            condition: FleetEconomics.usedMarketCondition(
                ageYears: Double(profile.usedAgeYears), tuning: catalog.tuning.fleet),
            tuning: catalog.tuning.fleet)
        let need = price - state.ledger.balance(of: airlineID)
            + Money(rounding: price.asDouble * 0.2)
        guard need > .zero,
              CreditMath.debtRatio(of: airline, state: state, additional: need)
                  <= profile.maxComfortableDebtRatio else { return }
        if issue(TakeLoanCommand(airline: airlineID, amount: need, termMonths: 72),
                 state: &state, context: context) {
            _ = issue(BuyUsedAircraftCommand(buyer: airlineID, type: type.code,
                                             ageYears: profile.usedAgeYears),
                      state: &state, context: context)
        }
    }

    /// Runs a command through its own validator — the same path as the
    /// player, minus the engine queue (systems act at their pipeline slot).
    @discardableResult
    private func issue(_ command: some Command, state: inout GameState,
                       context: SimContext) -> Bool {
        guard command.validate(state: state, catalog: context.catalog) == nil else {
            return false
        }
        command.apply(state: &state, context: context)
        return true
    }
}

public struct AITuning: Equatable, Codable, Sendable {
    public let decisionIntervalDays: Int
    public let retrenchRunwayMonths: Double
    public let expandLoadFactor: Double
    public let shrinkLoadFactor: Double
    public let undercutResponseThreshold: Double
    public let candidateMarketLimit: Int
    /// Minimum expected own-share daily demand to open a market.
    public let minViableDailyDemand: Double
    public let initialRoundTrips: Int
    public let maxFleetPerAirline: Int

    public init(decisionIntervalDays: Int, retrenchRunwayMonths: Double,
                expandLoadFactor: Double, shrinkLoadFactor: Double,
                undercutResponseThreshold: Double, candidateMarketLimit: Int,
                minViableDailyDemand: Double, initialRoundTrips: Int,
                maxFleetPerAirline: Int) {
        self.decisionIntervalDays = decisionIntervalDays
        self.retrenchRunwayMonths = retrenchRunwayMonths
        self.expandLoadFactor = expandLoadFactor
        self.shrinkLoadFactor = shrinkLoadFactor
        self.undercutResponseThreshold = undercutResponseThreshold
        self.candidateMarketLimit = candidateMarketLimit
        self.minViableDailyDemand = minViableDailyDemand
        self.initialRoundTrips = initialRoundTrips
        self.maxFleetPerAirline = maxFleetPerAirline
    }

    public static let standard = AITuning(
        decisionIntervalDays: 7, retrenchRunwayMonths: 1.5,
        expandLoadFactor: 0.82, shrinkLoadFactor: 0.35,
        undercutResponseThreshold: 0.12, candidateMarketLimit: 16,
        minViableDailyDemand: 140, initialRoundTrips: 2,
        maxFleetPerAirline: 40)
}
