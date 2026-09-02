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

    /// One airport considered from where an airframe sits: scored, or the
    /// reason it was not.
    public struct MarketCandidate: Equatable, Sendable {
        public enum Verdict: Equatable, Sendable {
            case scored(Double)
            case regionExcluded
            case ineligible
            case alreadyServed
            case noSlots
            /// Too few passengers for an entrant (`minViableDailyDemand`).
            case belowFloor(Double)
            /// Enough passengers, but one airframe would lose money on it.
            case unprofitable(Double)
        }
        public let destination: AirportCode
        public let distanceKm: Int
        /// Position in the distance-ordered list from the origin, from 1.
        public let nearestRank: Int
        public let verdict: Verdict

        public var score: Double? {
            if case .scored(let value) = verdict { return value }
            return nil
        }
    }

    /// The airports an airline would consider from `origin` — the horizon —
    /// in the order the AI walks them.
    ///
    /// The nearest airports by great-circle distance, `candidateMarketLimit`
    /// of them — sixteen as built, twenty-four since AE-039. Measured
    /// (docs/HORIZON_AUDIT.md §3): with the passenger ranking no size
    /// brought a rival to a European start; with the airframe-day ranking,
    /// sixteen still could not see Stockholm from Istanbul (rank 22),
    /// twenty-four could, and thirty-two put larger markets ahead of it
    /// again. The smallest size that reaches the curated first start.
    public static func horizon(from origin: AirportCode, catalog: ContentCatalog,
                               tuning: AITuning) -> [(AirportSpec, Int)] {
        catalog.nearestAirports(to: origin, limit: tuning.candidateMarketLimit)
    }

    /// Every candidate in the horizon from `origin`, with its verdict — the
    /// AI's own evaluation, exposed so a diagnostic or a test can ask why a
    /// market was or was not chosen without a second implementation.
    /// `limit` overrides the horizon size (a diagnostic asks for the whole
    /// world to see what lies beyond).
    public static func candidateMarkets(from origin: AirportCode, airline: Airline,
                                        spec: AircraftTypeSpec, profile: AIProfile,
                                        state: GameState, catalog: ContentCatalog,
                                        tuning: AITuning,
                                        limit: Int? = nil) -> [MarketCandidate] {
        guard let originSpec = catalog.airport(origin) else { return [] }
        // The offer this airline would put on a new pair: a starter
        // operation at its archetype's fare, carrying its own reputation.
        let entrantQuality = DemandSystem.representativeStarterQuality(
            tuning: catalog.tuning.demand)
            * airline.reputation.demandMultiplier(tuning: catalog.tuning.reputation)
        let considered = limit.map { catalog.nearestAirports(to: origin, limit: $0) }
            ?? horizon(from: origin, catalog: catalog, tuning: tuning)
        var out: [MarketCandidate] = []
        out.reserveCapacity(considered.count)
        for (rank, (destinationSpec, distance)) in considered.enumerated() {
            let destination = destinationSpec.code
            func candidate(_ verdict: MarketCandidate.Verdict) -> MarketCandidate {
                MarketCandidate(destination: destination, distanceKm: distance,
                                nearestRank: rank + 1, verdict: verdict)
            }
            if profile.homeRegionOnly && destinationSpec.region != originSpec.region {
                out.append(candidate(.regionExcluded)); continue
            }
            guard catalog.routeEligibility(from: origin, to: destination,
                                           aircraftRangeKm: spec.rangeKm,
                                           aircraftRunwayRequirement: spec.runwayRequirement)
                .isEmpty else { out.append(candidate(.ineligible)); continue }
            // Already served by us?
            if state.routes.values.contains(where: {
                $0.airline == airline.id
                    && $0.sameMarket(origin: origin, destination: destination)
            }) { out.append(candidate(.alreadyServed)); continue }
            // Slots for the initial frequency at both ends?
            let movements = Route.dailySlotMovements(roundTrips: tuning.initialRoundTrips)
            if state.world.slotsUsed(at: origin) + movements > originSpec.slotCapacityPerDay
                || state.world.slotsUsed(at: destination) + movements
                    > destinationSpec.slotCapacityPerDay {
                out.append(candidate(.noSlots)); continue
            }

            let pool = DemandSystem.demandPool(from: origin, to: destination,
                                               date: state.currentDate,
                                               economicIndex: state.world.economicIndex,
                                               catalog: catalog)
            let incumbents = state.routes.values.filter {
                $0.sameMarket(origin: origin, destination: destination)
            }
            let passengers = DemandSystem.poolAvailableToEntrant(
                pool: pool, fareRatio: profile.priceFactor, quality: entrantQuality,
                incumbents: incumbents, state: state, catalog: catalog)
            guard passengers >= tuning.minViableDailyDemand else {
                out.append(candidate(.belowFloor(passengers))); continue
            }
            let score = airframeDayProfit(
                distanceKm: distance, passengersPerDay: passengers, spec: spec,
                fareRatio: profile.priceFactor, serviceTier: airline.serviceTier,
                origin: originSpec, destination: destinationSpec, state: state,
                catalog: catalog)
            guard score > 0 else { out.append(candidate(.unprofitable(score))); continue }
            out.append(candidate(.scored(score)))
        }
        return out
    }

    /// What one airframe of `spec` would earn on a market per day, in
    /// dollars: the passengers it can carry at the archetype's fare, less
    /// the fuel, fees, crew, maintenance and service the flight system
    /// posts per flight (`FlightOpsSystem`), for as many rotations as the
    /// scheduler's own day allows.
    ///
    /// AE-039 measured that ranking by passengers alone made every hub
    /// chase its shortest large pairs first — a 370 km pair with 2,000
    /// passengers outranked a 1,400 km pair with 700 forever, though one
    /// airframe fills on either and earns twice the fare on the longer —
    /// so second-tier cities never came up, at any horizon size
    /// (docs/HORIZON_AUDIT.md §3). This is the question `employ` is
    /// actually asking: where does this airframe earn the most?
    public static func airframeDayProfit(distanceKm: Int, passengersPerDay: Double,
                                         spec: AircraftTypeSpec, fareRatio: Double,
                                         serviceTier: ServiceTier,
                                         origin: AirportSpec, destination: AirportSpec,
                                         state: GameState, catalog: ContentCatalog) -> Double {
        let ops = catalog.tuning.ops
        let rotations = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
            distanceKm: distanceKm, spec: spec, ops: ops)
        guard rotations > 0 else { return 0 }
        let flights = Double(rotations * 2)
        let carried = min(passengersPerDay, flights * Double(spec.seats))
        let fare = DemandSystem.referenceFare(distanceKm: distanceKm,
                                             tuning: catalog.tuning.demand) * fareRatio
        let revenue = carried * fare

        let blockHours = Double(FlightSchedulingSystem.flightMinutes(
            distanceKm: distanceKm, cruiseSpeedKmh: spec.cruiseSpeedKmh,
            overheadMinutes: ops.flightOverheadMinutes)) / 60
        let fuel = flights * spec.fuelBurnKgPerKm * Double(distanceKm) / 1000
            * state.world.fuelPricePerTon.asDouble
        let movementFees = flights * (origin.movementFee.asDouble + destination.movementFee.asDouble)
        // Passenger fees are charged at the arrival airport; half the
        // passengers land at each end.
        let passengerFees = carried / 2
            * (origin.passengerFee.asDouble + destination.passengerFee.asDouble)
        let crew = flights * blockHours
            * (Double(spec.crewCockpit) * ops.crewCostPerBlockHourCockpit.asDouble
               + Double(spec.crewCabin) * ops.crewCostPerBlockHourCabin.asDouble)
        let maintenance = flights * blockHours * spec.maintenancePerFlightHour.asDouble
        let service = carried * catalog.tuning.reputation.serviceCostPerPax(serviceTier).asDouble
        return revenue - fuel - movementFees - passengerFees - crew - maintenance - service
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
        var best: MarketCandidate?
        for candidate in Self.candidateMarkets(from: origin, airline: airline, spec: spec,
                                               profile: profile, state: state,
                                               catalog: context.catalog, tuning: tuning) {
            guard let score = candidate.score else { continue }
            if best == nil || score > best!.score! {
                best = candidate
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
        undercutResponseThreshold: 0.12, candidateMarketLimit: 24,
        minViableDailyDemand: 140, initialRoundTrips: 2,
        maxFleetPerAirline: 40)
}
