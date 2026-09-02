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

    // HORIZON-05: a scored candidate carries the entrant-pool score the
    // demand engine gives it, and a contested pair scores below an open
    // one of the same pool.
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
            let expected = DemandSystem.poolAvailableToEntrant(
                pool: pool, fareRatio: profile.priceFactor, quality: quality,
                incumbents: incumbents, state: state, catalog: catalog)
            #expect(abs(score - expected) < 0.001)
            #expect(score >= tuning.minViableDailyDemand)
            if !incumbents.isEmpty { #expect(score < pool.total) } else { #expect(abs(score - pool.total) < 0.001) }
            checked += 1
        }
        #expect(checked >= 5)
    }
}
