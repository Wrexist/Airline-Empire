import Testing
import Foundation
@testable import AirlineEmpireCore

/// AE-044 / TD-033: the estimator's demand term must respond to the service
/// the airframe would actually offer, and it must do so with the demand
/// engine's own allocation rather than a second model.
///
/// Before this phase `CompetitorAISystem.airframeDayValue` took
/// `passengersPerDay` as a caller-supplied constant: one figure per market,
/// reused for every candidate airframe. Past the seat cap every airframe
/// therefore earned identical revenue and paid a larger cabin's costs, so the
/// estimator preferred the smallest airframe that cleared the cap whatever
/// the market was — and picked the wrong one at six of the seven homes AE-043
/// flew (docs/AE044_ROOT_CAUSE.md).
///
/// These tests are written against the *rule*, not against those seven
/// routes: the routes are regression evidence and live in
/// docs/AE044_AIRFRAME_VALUE_AUDIT.md.
@Suite("Service demand")
struct ServiceDemandTests {

    // MARK: Fixtures

    /// The anchor market: two identical 4M-population cities 1,100 km apart,
    /// flat seasonality, so nothing but the variable under test moves.
    static func anchor() throws -> (ContentCatalog, GameState, AirportSpec, AirportSpec) {
        let catalog = try DemandFixtures.anchorCatalog()
        let engine = SimulationEngine(state: Fixtures.newState(),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Anchor Air", kind: .player, homeAirport: "MET",
            startingCash: Money.dollars(300_000_000)))
        let origin = try #require(catalog.airport("MET"))
        let destination = try #require(catalog.airport("COS"))
        return (catalog, engine.state, origin, destination)
    }

    static func demand(_ type: AircraftTypeCode, trips: Int, catalog: ContentCatalog,
                       state: GameState, incumbents: [Route] = [],
                       fareRatio: Double = 1.0) throws -> DemandSystem.ServiceDemand {
        let spec = try #require(catalog.aircraftType(type))
        return DemandSystem.serviceDemand(
            origin: "MET", destination: "COS", spec: spec, roundTripsPerDay: trips,
            fareRatio: fareRatio, incumbents: incumbents, state: state, catalog: catalog)
    }

    /// One incumbent on MET–COS: a second airline flying `type` at `trips`
    /// a day at the reference fare, through real commands.
    static func withIncumbents(_ count: Int, type: AircraftTypeCode = "KT95",
                               trips: Int = 2) throws -> (ContentCatalog, GameState) {
        let catalog = try DemandFixtures.anchorCatalog()
        let engine = SimulationEngine(state: Fixtures.newState(),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Anchor Air", kind: .player, homeAirport: "MET",
            startingCash: Money.dollars(300_000_000)))
        let distance = try #require(catalog.distanceKm("MET", "COS"))
        let fare = Money(rounding: DemandSystem.referenceFare(
            distanceKm: distance, tuning: catalog.tuning.demand))
        for index in 0..<count {
            let name = "Incumbent \(index + 1)"
            guard engine.applyNow(FoundAirlineCommand(
                airlineName: name, kind: .ai, homeAirport: "MET",
                startingCash: Money.dollars(300_000_000),
                aiProfile: AIProfile(archetype: .regional))) == .applied,
                let airline = engine.state.airlines.values.first(where: { $0.name == name })
            else { continue }
            _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline.id, type: type, ageYears: 2))
            guard let aircraft = engine.state.fleet(of: airline.id).first else { continue }
            _ = engine.applyNow(OpenRouteCommand(
                airline: airline.id, origin: "MET", destination: "COS",
                dailyRoundTrips: trips, ticketPrice: fare))
            guard let route = engine.state.routes(of: airline.id).first else { continue }
            _ = engine.applyNow(AssignAircraftToRouteCommand(
                airline: airline.id, route: route.id, aircraftID: aircraft.id))
        }
        return (catalog, engine.state)
    }

    static func incumbentRoutes(_ state: GameState) -> [Route] {
        state.orderedRouteIDs.compactMap { state.routes[$0] }
            .filter { $0.sameMarket(origin: "MET", destination: "COS") }
    }

    // MARK: 1 — capacity

    /// SERVICEDEMAND-01: the airframe is *in* the demand answer. A larger
    /// cabin both attracts a larger share (comfort is a term of
    /// `offerQualityTerms`) and boards more of it (the per-flight seat cap).
    ///
    /// The old estimator returned the same passenger figure for both, which
    /// is the whole of TD-033.
    @Test func offeredCapacityChangesTheDemandTheAirframeCarries() throws {
        let (catalog, state, _, _) = try Self.anchor()
        let small = try Self.demand("KT72", trips: 2, catalog: catalog, state: state)
        let large = try Self.demand("PA184", trips: 2, catalog: catalog, state: state)

        #expect(large.seatsPerDay > small.seatsPerDay)
        #expect(large.carriedPerDay > small.carriedPerDay,
                "a 184-seat cabin carries no more than a 74-seat one — the demand term is not responding to the airframe")
        // The share too, not only the cap: PA184's cabin is more comfortable.
        #expect(large.capturedPerDay > small.capturedPerDay)
    }

    /// SERVICEDEMAND-02: and it is NOT proportional. The demand model has
    /// diminishing returns — a bigger cabin does not multiply the market —
    /// so an estimator that assumed `2x seats = 2x passengers` would be as
    /// wrong in the other direction.
    @Test func moreCapacityIsNotProportionallyMorePassengers() throws {
        let (catalog, state, _, _) = try Self.anchor()
        let small = try Self.demand("KT72", trips: 2, catalog: catalog, state: state)
        let large = try Self.demand("PA184", trips: 2, catalog: catalog, state: state)
        let seatRatio = large.seatsPerDay / small.seatsPerDay          // 2.49x
        let paxRatio = large.carriedPerDay / small.carriedPerDay
        #expect(paxRatio < seatRatio,
                "carried passengers scaled \(paxRatio)x on \(seatRatio)x the seats — that is proportional, and the demand model is not")
        // The share itself barely moves: the cabin is one term of four.
        #expect(large.capturedPerDay / small.capturedPerDay < 1.2)
    }

    /// SERVICEDEMAND-02b: the new primitive must *reduce* to the one it
    /// replaced. Asked about the exact service `representativeStarterQuality`
    /// describes — a 0.55 cabin, two round trips, an unproven operations
    /// record, a neutral reputation — `serviceDemand` must return what
    /// `expectedCapturedPassengers` returns for both directions. If these
    /// ever disagree there are two demand models again.
    @Test func theNewPrimitiveReducesToTheOldOneOnTheServiceItDescribed() throws {
        let (catalog, state, _, _) = try Self.anchor()
        let tuning = catalog.tuning.demand
        // MR180's cabin is exactly the 0.55 the old constant assumed.
        let spec = try #require(catalog.aircraftType("MR180"))
        #expect(spec.comfortBaseline == 0.55)
        let quality = DemandSystem.representativeStarterQuality(tuning: tuning)
        func captured(_ from: AirportCode, _ to: AirportCode) -> Double {
            DemandSystem.expectedCapturedPassengers(
                pool: DemandSystem.demandPool(from: from, to: to, date: state.currentDate,
                                              economicIndex: state.world.economicIndex,
                                              catalog: catalog),
                fareRatio: 1.0, quality: quality, tuning: tuning)
        }
        let old = captured("MET", "COS") + captured("COS", "MET")
        let new = DemandSystem.serviceDemand(
            origin: "MET", destination: "COS", spec: spec, roundTripsPerDay: 2,
            fareRatio: 1.0, operationsScore: DemandSystem.unprovenOperationsScore,
            reputationMultiplier: 1.0, incumbents: [], state: state, catalog: catalog)
        #expect(abs(new.capturedPerDay - old) < 1e-9,
                "serviceDemand \(new.capturedPerDay) against expectedCapturedPassengers \(old) for the same offer")
    }

    // MARK: 2 — frequency

    /// SERVICEDEMAND-03: frequency is service, and service wins share —
    /// through `offerQualityTerms.schedule`, the engine's own term, with the
    /// engine's own diminishing returns.
    @Test func frequencyRaisesCapturedDemandWithDiminishingReturns() throws {
        let (catalog, state, _, _) = try Self.anchor()
        let tuning = catalog.tuning.demand
        let once = try Self.demand("PA184", trips: 1, catalog: catalog, state: state)
        let twice = try Self.demand("PA184", trips: 2, catalog: catalog, state: state)
        let fourTimes = try Self.demand("PA184", trips: 4, catalog: catalog, state: state)

        #expect(once.capturedPerDay < twice.capturedPerDay)
        #expect(twice.capturedPerDay < fourTimes.capturedPerDay)
        // And sub-proportional at every step: doubling the frequency buys
        // far less than double the passengers, because schedule quality
        // rises as `trips ^ 0.35` and the share it buys is concave in that.
        // (MEASURED: each doubling adds ~6 points of share, not 100%.)
        #expect(twice.capturedPerDay < once.capturedPerDay * 1.3)
        #expect(fourTimes.capturedPerDay < twice.capturedPerDay * 1.3)
        // And it stops entirely at the anti-spam cap.
        let atCap = try Self.demand("PA184", trips: tuning.scheduleQualityTripCap,
                                    catalog: catalog, state: state)
        let beyondCap = try Self.demand("PA184", trips: tuning.scheduleQualityTripCap + 4,
                                        catalog: catalog, state: state)
        #expect(abs(atCap.capturedPerDay - beyondCap.capturedPerDay) < 0.001,
                "frequency past the trip cap still buys share")
    }

    // MARK: 3 — competition

    /// SERVICEDEMAND-04: incumbents take demand away from an entrant, by the
    /// same logit denominator `DemandSystem.allocate` uses. The player path
    /// used to ignore them entirely: the same $22,065/day whether the pair
    /// was empty or had three carriers (docs/AE044_AIRFRAME_VALUE_AUDIT.md §3).
    @Test func incumbentsTakeDemandFromAnEntrant() throws {
        let (emptyCatalog, emptyState, _, _) = try Self.anchor()
        let alone = try Self.demand("PA184", trips: 2, catalog: emptyCatalog, state: emptyState)

        var previous = alone.capturedPerDay
        for count in 1...3 {
            let (catalog, state) = try Self.withIncumbents(count)
            let contested = try Self.demand("PA184", trips: 2, catalog: catalog, state: state,
                                            incumbents: Self.incumbentRoutes(state))
            #expect(contested.capturedPerDay < previous,
                    "\(count) incumbent(s) left the entrant at least as much as \(count - 1) did")
            previous = contested.capturedPerDay
        }
        // An incumbent with no aircraft attracts nobody, exactly as in
        // `allocate`, so it must not shrink the entrant's share either.
        let (catalog, state) = try Self.withIncumbents(1)
        var grounded = state
        for id in grounded.orderedRouteIDs where grounded.routes[id]?.airline != state.playerAirline?.id {
            grounded.routes[id]?.assignedAircraft = []
        }
        let againstGrounded = try Self.demand("PA184", trips: 2, catalog: catalog,
                                              state: grounded,
                                              incumbents: Self.incumbentRoutes(grounded))
        #expect(abs(againstGrounded.capturedPerDay - alone.capturedPerDay) < 0.001,
                "a route with no aircraft is competing for passengers")
    }

    // MARK: 4 — it is the engine's own allocation

    /// SERVICEDEMAND-05: the load-bearing test. `serviceDemand` must not be
    /// an approximation of `DemandSystem.allocate` — it must *be* it. Fly a
    /// route for one day and compare the demand the engine allocated with
    /// what the estimator said before it flew.
    ///
    /// The engine floors each direction (`Int(served.rounded(.down))`), so
    /// the estimate is allowed to be up to two passengers above the
    /// allocation and no amount below it.
    @Test(arguments: [(AircraftTypeCode("KT72"), 0), ("KT95", 1), ("PA184", 2), ("MR180", 0)])
    func theEstimateIsTheEnginesOwnAllocation(type: AircraftTypeCode,
                                              incumbents: Int) async throws {
        let catalog = try DemandFixtures.anchorCatalog()
        let engine = SimulationEngine(state: Fixtures.newState(),
                                      systems: GamePipeline.standard(), catalog: catalog)
        let distance = try #require(catalog.distanceKm("MET", "COS"))
        let fare = Money(rounding: DemandSystem.referenceFare(
            distanceKm: distance, tuning: catalog.tuning.demand))
        func fly(_ name: String, kind: AirlineKind, type: AircraftTypeCode,
                 trips: Int) -> Route? {
            guard engine.applyNow(FoundAirlineCommand(
                airlineName: name, kind: kind, homeAirport: "MET",
                startingCash: Money.dollars(400_000_000),
                aiProfile: kind == .ai ? AIProfile(archetype: .regional) : nil)) == .applied,
                let airline = engine.state.airlines.values.first(where: { $0.name == name })
            else { return nil }
            _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline.id, type: type, ageYears: 2))
            guard let aircraft = engine.state.fleet(of: airline.id).first,
                  engine.applyNow(OpenRouteCommand(
                    airline: airline.id, origin: "MET", destination: "COS",
                    dailyRoundTrips: trips, ticketPrice: fare)) == .applied,
                  let route = engine.state.routes(of: airline.id).first else { return nil }
            _ = engine.applyNow(AssignAircraftToRouteCommand(
                airline: airline.id, route: route.id, aircraftID: aircraft.id))
            return engine.state.routes[route.id]
        }
        for index in 0..<incumbents {
            _ = fly("Incumbent \(index + 1)", kind: .ai, type: "KT95", trips: 2)
        }
        let subjectRoute = try #require(fly("Subject Air", kind: .player, type: type, trips: 3))

        // The estimate, taken before anything flies.
        let spec = try #require(catalog.aircraftType(type))
        let state = engine.state
        let others = state.orderedRouteIDs.compactMap { state.routes[$0] }
            .filter { $0.sameMarket(origin: "MET", destination: "COS")
                && $0.id != subjectRoute.id }
        let reputation = state.airlines[subjectRoute.airline]?.reputation
            .demandMultiplier(tuning: catalog.tuning.reputation) ?? 1
        let estimate = DemandSystem.serviceDemand(
            origin: "MET", destination: "COS", spec: spec, roundTripsPerDay: 3,
            fareRatio: 1.0,
            // A route with no history reports a perfect operations record,
            // which is what the engine will read on day one.
            operationsScore: 1.0, reputationMultiplier: reputation,
            incumbents: others, state: state, catalog: catalog)

        // One day of the real pipeline.
        engine.advance(ticks: Fixtures.ticksPerDay)
        let flown = try #require(engine.state.routes[subjectRoute.id])
        let allocated = Double(flown.demandOutboundToday + flown.demandInboundToday)
        #expect(allocated > 0)
        let gap = estimate.capturedPerDay - allocated
        print("ALLOCATION-CHECK \(type.raw) inc=\(incumbents) estimate=\(estimate.capturedPerDay) engine=\(allocated) gap=\(gap)")
        // Two bounds, both from known arithmetic rather than tolerance
        // taste. Above: the engine floors each direction
        // (`Int(served.rounded(.down))`), so it can be up to two passengers
        // below the exact figure. Below: the estimate is read from the state
        // before the day runs and the engine allocates after `WorldSystem`
        // has moved `economicIndex` that morning, which is worth a few
        // thousandths of a passenger (MEASURED: −0.0013 on MR180).
        #expect(gap > -0.05 && gap < 2,
                "\(type.raw) with \(incumbents) incumbent(s): estimate \(estimate.capturedPerDay) against the engine's \(allocated) — outside the band the engine's per-direction flooring allows")
    }

    // MARK: 5 — it reaches the value the estimator ranks on

    /// SERVICEDEMAND-06: `airframeDayEstimate` must carry the airframe's own
    /// demand into the value, not a market constant. Two airframes on one
    /// market must not receive the same passenger figure.
    @Test func airframeDayValueIsFedAirframeSpecificDemand() throws {
        let (catalog, state, origin, destination) = try Self.anchor()
        let distance = try #require(catalog.distanceKm("MET", "COS"))
        func estimate(_ type: AircraftTypeCode) throws
            -> CompetitorAISystem.AirframeDayEstimate {
            let spec = try #require(catalog.aircraftType(type))
            return CompetitorAISystem.airframeDayEstimate(
                origin: origin, destination: destination, distanceKm: distance,
                spec: spec, fareRatio: 1.0, serviceTier: .standard,
                state: state, catalog: catalog, basis: .profit)
        }
        let small = try estimate("KT72")
        let large = try estimate("PA184")
        #expect(small.demand.capturedPerDay != large.demand.capturedPerDay,
                "two airframes on one market still receive the same passenger estimate")
        #expect(large.demand.carriedPerDay > small.demand.carriedPerDay)
        // And the demand it is priced on is the demand for the rotations it
        // is costed at — the two halves describe one operation.
        #expect(large.demand.seatsPerDay
                == Double(large.rotationsPerDay * 2 * catalog.aircraftType("PA184")!.seats))
    }

    // MARK: 6 — the ranking agrees with the ledger

    /// SERVICEDEMAND-07: on a controlled fixture, the estimator's ordering of
    /// two airframes matches what a month of real flying pays. The old
    /// estimator inverted it: on the anchor market it preferred the smaller
    /// cabin because past the seat cap both were credited with the same
    /// passengers and only the larger paid for its size.
    @Test func theEstimatedOrderingMatchesTheLedgersOnAControlledFixture() async throws {
        let catalog = try DemandFixtures.anchorCatalog()
        let distance = try #require(catalog.distanceKm("MET", "COS"))
        let origin = try #require(catalog.airport("MET"))
        let destination = try #require(catalog.airport("COS"))
        let fare = Money(rounding: DemandSystem.referenceFare(
            distanceKm: distance, tuning: catalog.tuning.demand))
        let contenders: [AircraftTypeCode] = ["KT95", "PA184"]

        /// A month of the route's own direct result, less service and
        /// maintenance — exactly what `.profit` estimates, per day.
        func ledgerPerDay(_ type: AircraftTypeCode) throws -> Double {
            let engine = SimulationEngine(state: Fixtures.newState(),
                                          systems: GamePipeline.standard(), catalog: catalog)
            _ = engine.applyNow(FoundAirlineCommand(
                airlineName: "Ledger Air", kind: .player, homeAirport: "MET",
                startingCash: Money.dollars(400_000_000)))
            let airline = try #require(engine.state.airlines.values.first).id
            _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: type, ageYears: 2))
            let aircraft = try #require(engine.state.fleet(of: airline).first).id
            let spec = try #require(catalog.aircraftType(type))
            let rotations = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
                distanceKm: distance, spec: spec, ops: catalog.tuning.ops)
            _ = engine.applyNow(OpenRouteCommand(
                airline: airline, origin: "MET", destination: "COS",
                dailyRoundTrips: rotations, ticketPrice: fare))
            let route = try #require(engine.state.routes(of: airline).first).id
            _ = engine.applyNow(AssignAircraftToRouteCommand(
                airline: airline, route: route, aircraftID: aircraft))
            engine.advance(ticks: Fixtures.ticksPerDay * 28)
            let flown = try #require(engine.state.routes[route])
            let month = flown.economicsThisMonth
            let service = Double(month.passengers)
                * catalog.tuning.reputation.serviceCostPerPax(.standard).asDouble
            return (Double(month.revenueCents - month.fuelCents - month.feesCents
                           - month.crewCents) / 100 - service) / 28
        }

        func estimated(_ type: AircraftTypeCode) throws -> Double {
            let spec = try #require(catalog.aircraftType(type))
            return CompetitorAISystem.airframeDayEstimate(
                origin: origin, destination: destination, distanceKm: distance,
                spec: spec, fareRatio: 1.0, serviceTier: .standard,
                state: Fixtures.newState(), catalog: catalog, basis: .profit).value
        }

        let ledger = try contenders.map { ($0, try ledgerPerDay($0)) }
        let estimate = try contenders.map { ($0, try estimated($0)) }
        let ledgerBest = try #require(ledger.max { $0.1 < $1.1 }).0
        let estimateBest = try #require(estimate.max { $0.1 < $1.1 }).0
        #expect(estimateBest == ledgerBest,
                "estimator picks \(estimateBest.raw) (\(estimate)) where the ledger pays best on \(ledgerBest.raw) (\(ledger))")
    }

    // MARK: 7 & 8 — purity

    /// SERVICEDEMAND-08: deterministic. Same world, same question, same
    /// answer — every time, and across a state rebuilt from scratch.
    @Test func theEstimateIsDeterministic() throws {
        let (catalog, state, origin, destination) = try Self.anchor()
        let distance = try #require(catalog.distanceKm("MET", "COS"))
        let spec = try #require(catalog.aircraftType("PA184"))
        func once(_ state: GameState) -> Double {
            CompetitorAISystem.airframeDayEstimate(
                origin: origin, destination: destination, distanceKm: distance,
                spec: spec, fareRatio: 1.0, serviceTier: .standard,
                state: state, catalog: catalog, basis: .profit).value
        }
        let first = once(state)
        for _ in 0..<20 { #expect(once(state) == first) }
        let (_, rebuilt, _, _) = try Self.anchor()
        #expect(once(rebuilt) == first)
    }

    /// SERVICEDEMAND-09: no side effects. The estimator is called for every
    /// candidate market of every rival on every decision day; if it moved the
    /// world or drew from the RNG the simulation would not be reproducible.
    @Test func theEstimateHasNoSideEffects() throws {
        let (catalog, state, origin, destination) = try Self.anchor()
        let distance = try #require(catalog.distanceKm("MET", "COS"))
        let spec = try #require(catalog.aircraftType("PA184"))
        let before = state
        for _ in 0..<10 {
            _ = CompetitorAISystem.airframeDayEstimate(
                origin: origin, destination: destination, distanceKm: distance,
                spec: spec, fareRatio: 1.0, serviceTier: .standard,
                state: state, catalog: catalog, basis: .profit)
            _ = DemandSystem.serviceDemand(
                origin: "MET", destination: "COS", spec: spec, roundTripsPerDay: 3,
                fareRatio: 1.0, incumbents: [], state: state, catalog: catalog)
        }
        #expect(state.rng == before.rng, "the estimator consumed randomness")
        #expect(state.routes == before.routes)
        #expect(state.aircraft == before.aircraft)
        #expect(state.flights == before.flights)
        #expect(state.clock == before.clock)
        #expect(state.ledger == before.ledger)
        #expect(state.world == before.world)
    }

    // MARK: 9 — one estimator, two callers

    /// SERVICEDEMAND-10: the player's recommendation and the rival's market
    /// choice go through the *same* derivation. Not "produce similar
    /// numbers" — the same function, so they cannot drift.
    @Test func thePlayerAndTheRivalsUseTheSameDemandLogic() throws {
        let catalog = try ContentCatalog.loadBundled()
        let scenario = try #require(catalog.scenario("entrepreneur"))
        let engine = SimulationEngine(
            state: ScenarioBootstrap.newGame(scenario: "entrepreneur", worldSeed: 2030,
                                             startYear: scenario.startYear),
            systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Both Air", kind: .player, homeAirport: "HAM",
            startingCash: scenario.playerStartingCash))
        let state = engine.state
        let origin = try #require(catalog.airport("HAM"))
        let destination = try #require(catalog.airport("LHR"))
        let distance = try #require(catalog.distanceKm("HAM", "LHR"))
        let spec = try #require(catalog.aircraftType("PA184"))
        let reputation = try #require(state.playerAirline).reputation
            .demandMultiplier(tuning: catalog.tuning.reputation)

        // The player's own economics for this airframe on this market.
        let viaPlayer = state.airframeResult(
            from: "HAM", to: "LHR", distanceKm: distance,
            candidateSpecs: [spec], incumbents: [], catalog: catalog)
        let payroll = catalog.tuning.finance.payrollPerAircraftMonthly.asDouble
            + catalog.tuning.finance.payrollPerRouteMonthly.asDouble
        let direct = CompetitorAISystem.airframeDayEstimate(
            origin: origin, destination: destination, distanceKm: distance,
            spec: spec, fareRatio: 1.0, serviceTier: .standard,
            reputationMultiplier: reputation, incumbents: [],
            state: state, catalog: catalog, basis: .profit).value
        let expected = Money(rounding: direct * 30 - spec.leaseMonthly.asDouble - payroll)
        #expect(viaPlayer?.monthly == expected,
                "the player's recommendation no longer prices an airframe the way the shared estimator does")

        // And the rival's candidate score is that same function's value.
        let profile = AIProfile(archetype: .conservative)
        let airline = try #require(state.playerAirline)
        let candidates = CompetitorAISystem.candidateMarkets(
            from: "HAM", airline: airline, spec: spec, profile: profile,
            state: state, catalog: catalog, tuning: catalog.tuning.ai)
        let scored = try #require(candidates.first { $0.score != nil })
        let destinationSpec = try #require(catalog.airport(scored.destination))
        let rebuilt = CompetitorAISystem.airframeDayEstimate(
            origin: origin, destination: destinationSpec, distanceKm: scored.distanceKm,
            spec: spec, fareRatio: profile.priceFactor, serviceTier: airline.serviceTier,
            reputationMultiplier: airline.reputation.demandMultiplier(
                tuning: catalog.tuning.reputation),
            incumbents: state.routes.values.filter {
                $0.sameMarket(origin: "HAM", destination: scored.destination)
            }.sorted { $0.id.raw < $1.id.raw },
            state: state, catalog: catalog).value
        #expect(scored.score == rebuilt,
                "the rival's market score is no longer the shared estimator's value")
    }

    // MARK: 10 — what AE-041 and AE-042 decided must still hold

    /// SERVICEDEMAND-11: AE-041 measured four rival configurations over 150
    /// campaigns and kept airframe-day **revenue** at a horizon of **16**.
    /// AE-044 changed what the demand term is; it did not touch either
    /// decision, and this fails loudly if a later phase does so silently.
    @Test func theRivalStrategyIsStillRevenueAtSixteen() throws {
        let catalog = try ContentCatalog.loadBundled()
        #expect(CompetitorAISystem.rankingBasis == .revenue,
                "the shipped rival ranking basis is no longer revenue (AE-041)")
        #expect(catalog.tuning.ai.candidateMarketLimit == 16,
                "the rival horizon is no longer 16 (AE-039, AE-041)")
        #expect(catalog.tuning.ai.initialRoundTrips == 2)
        #expect(catalog.tuning.ai.minViableDailyDemand == 140)
    }
}
