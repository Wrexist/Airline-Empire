import Testing
@testable import AirlineEmpireCore

/// The rival candidate horizon, asked through the AI's own evaluation
/// (`CompetitorAISystem.candidateMarkets`) — AE-039, docs/HORIZON_AUDIT.md.
@Suite("Horizon")
struct HorizonTests {

    /// A world with the standard cast around a Stockholm player, a few
    /// days in so every rival has its starter airframe.
    static func world(seed: UInt64 = 2039, home: AirportCode = "ARN",
                      days: Int = 3) throws -> (GameState, ContentCatalog) {
        let catalog = try ContentCatalog.loadBundled()
        let spec = try #require(catalog.scenario("entrepreneur"))
        let engine = SimulationEngine(
            state: ScenarioBootstrap.newGame(scenario: "entrepreneur", worldSeed: seed,
                                             startYear: spec.startYear),
            systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Horizon Air", kind: .player, homeAirport: home,
            startingCash: spec.playerStartingCash))
        WorldSetup.createCompetitors(engine: engine, count: spec.competitorCount,
                                     playerHome: home, startingCash: spec.competitorStartingCash)
        let ticksPerDay = Int(GameCalendar.minutesPerDay / ScenarioBootstrap.standardTickMinutes)
        engine.advance(ticks: ticksPerDay * days)
        return (engine.state, catalog)
    }

    static func rival(named name: String, in state: GameState) throws -> (Airline, AircraftTypeSpec, AIProfile, ContentCatalog) {
        let catalog = try ContentCatalog.loadBundled()
        let airline = try #require(state.airlines.values.first { $0.name == name })
        let profile = try #require(airline.aiProfile)
        let spec = try #require(state.fleet(of: airline.id)
            .compactMap { catalog.aircraftType($0.typeCode) }
            .max { $0.rangeKm < $1.rangeKm })
        return (airline, spec, profile, catalog)
    }

    // HORIZON-01: the horizon as shipped — the nearest airports by
    // distance, in distance order, and nothing beyond it.
    @Test func theShippedHorizonIsTheNearestAirportsInDistanceOrder() throws {
        let (state, catalog) = try Self.world()
        let (aurora, spec, profile, _) = try Self.rival(named: "Aurora Atlantic", in: state)
        let tuning = catalog.tuning.ai
        let candidates = CompetitorAISystem.candidateMarkets(
            from: aurora.homeAirport, airline: aurora, spec: spec, profile: profile,
            state: state, catalog: catalog, tuning: tuning)
        #expect(candidates.count == tuning.candidateMarketLimit)
        #expect(candidates.map(\.nearestRank) == Array(1...tuning.candidateMarketLimit))
        let distances = candidates.map(\.distanceKm)
        #expect(distances == distances.sorted())
        // Stockholm is not in London's sixteen (MEASURED rank 27).
        #expect(!candidates.contains { $0.destination == "ARN" })
        let whole = CompetitorAISystem.candidateMarkets(
            from: aurora.homeAirport, airline: aurora, spec: spec, profile: profile,
            state: state, catalog: catalog, tuning: tuning, limit: catalog.orderedAirportCodes.count)
        let stockholm = try #require(whole.first { $0.destination == "ARN" })
        #expect(stockholm.nearestRank > tuning.candidateMarketLimit)
        #expect(stockholm.score != nil)
    }

    // HORIZON-02: a candidate beyond the shipped sixteen is absent from the
    // shipped evaluation and present, with the same gates applied, when the
    // horizon is widened — the mechanism the AE-039 sweep measured with.
    // Stockholm from Istanbul (MEASURED rank 22) is such a candidate.
    @Test func wideningTheHorizonAdmitsACandidateWithTheSameGates() throws {
        let (state, catalog) = try Self.world()
        let (pacific, spec, profile, _) = try Self.rival(named: "PacificBlue", in: state)
        #expect(pacific.homeAirport == "IST")
        let tuning = catalog.tuning.ai
        let shipped = CompetitorAISystem.candidateMarkets(
            from: pacific.homeAirport, airline: pacific, spec: spec, profile: profile,
            state: state, catalog: catalog, tuning: tuning)
        #expect(!shipped.contains { $0.destination == "ARN" })
        let wider = CompetitorAISystem.candidateMarkets(
            from: pacific.homeAirport, airline: pacific, spec: spec, profile: profile,
            state: state, catalog: catalog, tuning: tuning, limit: 24)
        let stockholm = try #require(wider.first { $0.destination == "ARN" })
        #expect(stockholm.nearestRank > tuning.candidateMarketLimit && stockholm.nearestRank <= 24)
        // Admitted, and scored by the same rule as everything inside the
        // sixteen: eligible for the airframe, and worth what an airframe
        // day sells there.
        #expect(catalog.routeEligibility(from: "IST", to: "ARN", aircraftRangeKm: spec.rangeKm,
                                         aircraftRunwayRequirement: spec.runwayRequirement).isEmpty)
        #expect(stockholm.score != nil)
        // The first sixteen are the same list either way.
        #expect(wider.prefix(tuning.candidateMarketLimit).map(\.destination) == shipped.map(\.destination))
    }

    // HORIZON-03: beyond the airframe's range the candidate is ineligible,
    // whatever the horizon.
    @Test func aCandidateBeyondRangeIsIneligibleNotScored() throws {
        let (state, catalog) = try Self.world()
        let (swift, spec, profile, _) = try Self.rival(named: "SwiftJet", in: state)
        #expect(spec.rangeKm < 2_000, "the regional cast flies turboprops")
        let whole = CompetitorAISystem.candidateMarkets(
            from: swift.homeAirport, airline: swift, spec: spec, profile: profile,
            state: state, catalog: catalog, tuning: catalog.tuning.ai,
            limit: catalog.orderedAirportCodes.count)
        let beyond = whole.filter { $0.distanceKm > spec.rangeKm }
        #expect(!beyond.isEmpty)
        #expect(beyond.allSatisfy { $0.verdict == .ineligible || $0.verdict == .regionExcluded })
        #expect(beyond.allSatisfy { $0.score == nil })
    }

    // HORIZON-04: inside range, the real eligibility rules still decide —
    // the regional archetype never leaves its region.
    @Test func aCandidateInsideRangeStillPassesTheRealRules() throws {
        let (state, catalog) = try Self.world()
        let (swift, spec, profile, _) = try Self.rival(named: "SwiftJet", in: state)
        #expect(profile.homeRegionOnly)
        let whole = CompetitorAISystem.candidateMarkets(
            from: swift.homeAirport, airline: swift, spec: spec, profile: profile,
            state: state, catalog: catalog, tuning: catalog.tuning.ai,
            limit: catalog.orderedAirportCodes.count)
        let homeRegion = catalog.airport(swift.homeAirport)?.region
        let abroad = whole.filter { catalog.airport($0.destination)?.region != homeRegion }
        #expect(!abroad.isEmpty)
        #expect(abroad.allSatisfy { $0.verdict == .regionExcluded })
        // And every scored candidate is one the route validator would accept.
        for candidate in whole where candidate.score != nil {
            #expect(catalog.routeEligibility(from: swift.homeAirport, to: candidate.destination,
                                             aircraftRangeKm: spec.rangeKm,
                                             aircraftRunwayRequirement: spec.runwayRequirement).isEmpty)
            #expect(catalog.airport(candidate.destination)?.region == homeRegion)
        }
    }

    // HORIZON-05: a scored candidate has passed the passenger floor with the
    // demand engine's entrant pool and carries the airframe-day profit that
    // pool earns at the archetype's fare; a contested pair's pool is below
    // the pair's whole pool, an open pair's is all of it.
    @Test func aScoredCandidateCarriesTheEntrantPool() throws {
        let (state, catalog) = try Self.world(days: 60)
        let (aurora, spec, profile, _) = try Self.rival(named: "Aurora Atlantic", in: state)
        let tuning = catalog.tuning.ai
        let quality = DemandSystem.representativeStarterQuality(tuning: catalog.tuning.demand)
            * aurora.reputation.demandMultiplier(tuning: catalog.tuning.reputation)
        let candidates = CompetitorAISystem.candidateMarkets(
            from: aurora.homeAirport, airline: aurora, spec: spec, profile: profile,
            state: state, catalog: catalog, tuning: tuning)
        var checked = 0
        for candidate in candidates {
            guard let score = candidate.score else { continue }
            let pool = DemandSystem.demandPool(from: aurora.homeAirport, to: candidate.destination,
                                               date: state.currentDate,
                                               economicIndex: state.world.economicIndex,
                                               catalog: catalog)
            let incumbents = state.routes.values.filter {
                $0.sameMarket(origin: aurora.homeAirport, destination: candidate.destination)
            }
            let passengers = DemandSystem.poolAvailableToEntrant(
                pool: pool, fareRatio: profile.priceFactor, quality: quality,
                incumbents: incumbents, state: state, catalog: catalog)
            #expect(passengers >= tuning.minViableDailyDemand)
            if !incumbents.isEmpty { #expect(passengers < pool.total) } else { #expect(abs(passengers - pool.total) < 0.001) }
            let expected = CompetitorAISystem.airframeDayValue(
                distanceKm: candidate.distanceKm, passengersPerDay: passengers, spec: spec,
                fareRatio: profile.priceFactor, serviceTier: aurora.serviceTier,
                origin: try #require(catalog.airport(aurora.homeAirport)),
                destination: try #require(catalog.airport(candidate.destination)),
                state: state, catalog: catalog)
            #expect(abs(score - expected) < 0.001)
            #expect(score > 0)
            checked += 1
        }
        #expect(checked >= 5)
    }
}

/// The airframe-day estimator against the ledger (on its profit basis —
/// the measured alternative, kept for the diagnostic), and its cost.
@Suite("Airframe-day value")
struct AirframeDayProfitTests {

    /// The estimator is the flight system's own arithmetic ahead of time: on
    /// a route that actually flew a month, it should land within the same
    /// order as the closed month's direct operating profit per day. Not a
    /// tight bound — the real month carries disruptions, a ramp, and a load
    /// that is not always full — but the same sign and the same scale.
    @Test func theEstimateIsTheSameScaleAsARealMonth() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let spec = try #require(catalog.scenario("entrepreneur"))
        let session = GameSession(
            state: ScenarioBootstrap.newGame(scenario: "entrepreneur", worldSeed: 2039,
                                             startYear: spec.startYear),
            systems: GamePipeline.standard(), catalog: catalog)
        #expect(await session.beginScenario(spec, airlineName: "Estimate Air", home: "ARN") == .applied)
        var state = await session.snapshot
        let player = try #require(state.playerAirline).id
        #expect(await session.submit(LeaseAircraftCommand(lessee: player, type: "PA184", termMonths: 60)) == .applied)
        let distance = try #require(catalog.distanceKm("ARN", "LHR"))
        let reference = DemandSystem.referenceFare(distanceKm: distance, tuning: catalog.tuning.demand)
        #expect(await session.submit(OpenRouteCommand(
            airline: player, origin: "ARN", destination: "LHR", dailyRoundTrips: 2,
            ticketPrice: Money(rounding: reference))) == .applied)
        state = await session.snapshot
        let route = try #require(state.routes(of: player).first)
        let aircraft = try #require(state.fleet(of: player).first)
        #expect(await session.submit(AssignAircraftToRouteCommand(
            airline: player, route: route.id, aircraftID: aircraft.id)) == .applied)

        // Through the first full month: February's closed statement is
        // January's whole month of flying.
        let ticksPerDay = Int(GameCalendar.minutesPerDay / ScenarioBootstrap.standardTickMinutes)
        while await session.snapshot.currentDate.month < 3 {
            await session.advance(ticks: ticksPerDay)
        }
        state = await session.snapshot
        let flown = try #require(state.routes[route.id])
        let realPerDay = flown.economicsLastMonth.directOperatingProfit.asDouble / 28

        let type = try #require(catalog.aircraftType("PA184"))
        let origin = try #require(catalog.airport("ARN"))
        let destination = try #require(catalog.airport("LHR"))
        let pool = DemandSystem.demandPool(from: "ARN", to: "LHR", date: state.currentDate,
                                           economicIndex: state.world.economicIndex, catalog: catalog)
        let quality = try #require(DemandSystem.offerQualityTerms(route: flown, state: state, catalog: catalog)).product
        let passengers = DemandSystem.expectedCapturedPassengers(
            pool: pool, fareRatio: 1.0, quality: quality, tuning: catalog.tuning.demand)
        // The estimator plans an airframe day at the rotations asked of it;
        // the route flies two, so ask for two. (Scaling a full-day estimate
        // by rotations is wrong: passengers do not scale with seats.)
        let estimatePerDay = CompetitorAISystem.airframeDayValue(
            distanceKm: distance, passengersPerDay: passengers, spec: type, fareRatio: 1.0,
            serviceTier: .standard, origin: origin, destination: destination,
            state: state, catalog: catalog, rotationsPerDay: flown.dailyRoundTrips, basis: .profit)
        print("AIRFRAME-DAY ARN-LHR: real last month \(flown.economicsLastMonth.directOperatingProfit.compact) (\(Int(realPerDay))/day) · estimate \(Int(estimatePerDay))/day at \(flown.dailyRoundTrips) rotations · passengers \(Int(passengers)) load \(String(format: "%.0f%%", flown.stats.loadFactor * 100))")
        #expect(realPerDay > 0 && estimatePerDay > 0)
        #expect(estimatePerDay > realPerDay * 0.5 && estimatePerDay < realPerDay * 2.0,
                "estimate \(Int(estimatePerDay)) vs real \(Int(realPerDay)) per day")
    }

    /// The whole candidate evaluation from a hub, timed: this is what one
    /// rival decision costs, and the horizon multiplies it.
    @Test func evaluatingAHorizonIsCheap() throws {
        let (state, catalog) = try HorizonTests.world(days: 60)
        let (aurora, spec, profile, _) = try HorizonTests.rival(named: "Aurora Atlantic", in: state)
        let tuning = catalog.tuning.ai
        func time(limit: Int?, runs: Int) -> Double {
            let start = ContinuousClock.now
            var sink = 0
            for _ in 0..<runs {
                sink += CompetitorAISystem.candidateMarkets(
                    from: aurora.homeAirport, airline: aurora, spec: spec, profile: profile,
                    state: state, catalog: catalog, tuning: tuning, limit: limit).count
            }
            let elapsed = ContinuousClock.now - start
            #expect(sink > 0)
            let seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
            return seconds / Double(runs) * 1e6
        }
        let shipped = time(limit: nil, runs: 200)
        let wider = time(limit: 32, runs: 200)
        let whole = time(limit: catalog.orderedAirportCodes.count, runs: 200)
        print("HORIZON-COST per evaluation: \(Int(shipped)) µs at \(tuning.candidateMarketLimit) · \(Int(wider)) µs at 32 · \(Int(whole)) µs at \(catalog.orderedAirportCodes.count)")
        // A decision is weekly per rival; even the whole world is far under
        // a millisecond of budget per day of simulation.
        #expect(whole < 20_000)
    }
}
