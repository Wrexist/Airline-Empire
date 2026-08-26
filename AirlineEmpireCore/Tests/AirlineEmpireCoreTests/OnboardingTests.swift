import Testing
@testable import AirlineEmpireCore

/// The guided first-route beat (docs/PLAYER_JOURNEY.md §1): the checklist
/// derives every step from real state, the suggestions are eligible and
/// demand-ranked, and the whole model is a pure deterministic read.
@Suite("Onboarding read model")
struct OnboardingTests {
    /// A brand-new airline in the real world, nothing done yet.
    private func freshGame() throws -> (SimulationEngine, AirlineID) {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(seed: 11),
                                      systems: GamePipeline.standard(),
                                      catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "First Flight", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(60_000_000)))
        return (engine, engine.state.airlines.values.first!.id)
    }

    @Test func newGameStartsAtStepOneWithSuggestions() throws {
        let (engine, _) = try freshGame()
        let model = try #require(engine.state.onboardingModel(catalog: engine.catalog))
        #expect(model.completed.isEmpty)
        #expect(model.nextStep == .acquireAircraft)
        #expect(!model.isComplete)

        // Two demand-hinted candidates from home, best first.
        #expect(model.suggestions.count == 2)
        for suggestion in model.suggestions {
            #expect(suggestion.origin == "STV")
            #expect(suggestion.expectedDailyDemand > 0)
            #expect(suggestion.referenceFare > .zero)
            #expect(!suggestion.destinationCity.isEmpty)
            // Every candidate must actually be openable this era.
            let spec = engine.catalog.aircraftType("MR180")!
            #expect(engine.catalog.routeEligibility(
                from: suggestion.origin, to: suggestion.destination,
                aircraftRangeKm: spec.rangeKm,
                aircraftRunwayRequirement: spec.runwayRequirement).isEmpty)
        }
        #expect(model.suggestions[0].expectedDailyDemand
            >= model.suggestions[1].expectedDailyDemand)
    }

    @Test func modelIsDeterministicAndPure() throws {
        let (engine, _) = try freshGame()
        let hashBefore = try engine.state.stateHash()
        let first = engine.state.onboardingModel(catalog: engine.catalog)
        let second = engine.state.onboardingModel(catalog: engine.catalog)
        let hashAfter = try engine.state.stateHash()
        #expect(first == second)
        #expect(hashAfter == hashBefore)
    }

    @Test func stepsCompleteAsThePlayerActuallyPlays() throws {
        let (engine, player) = try freshGame()
        let catalog = engine.catalog

        // Step 1: buy an aircraft.
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: player, type: "MR180",
                                                   ageYears: 10))
        var model = try #require(engine.state.onboardingModel(catalog: catalog))
        #expect(model.isDone(.acquireAircraft))
        #expect(model.nextStep == .openRoute)
        #expect(!model.suggestions.isEmpty)

        // Step 2: open the top suggested route.
        let target = model.suggestions[0].destination
        let fare = model.suggestions[0].referenceFare
        #expect(engine.applyNow(OpenRouteCommand(
            airline: player, origin: "STV", destination: target,
            dailyRoundTrips: 2, ticketPrice: fare)) == .applied)
        model = try #require(engine.state.onboardingModel(catalog: catalog))
        #expect(model.isDone(.openRoute))
        #expect(model.nextStep == .assignAircraft)
        // Training wheels off: no more suggestions once a route exists.
        #expect(model.suggestions.isEmpty)

        // Step 3: put the aircraft on it.
        let route = engine.state.routes(of: player).first!.id
        let aircraft = engine.state.fleet(of: player).first!.id
        #expect(engine.applyNow(AssignAircraftToRouteCommand(
            airline: player, route: route, aircraftID: aircraft)) == .applied)
        model = try #require(engine.state.onboardingModel(catalog: catalog))
        #expect(model.isDone(.assignAircraft))
        #expect(model.nextStep == .watchFirstFlight)

        // Steps 4-5: let the world run; flying and earning finish the arc.
        engine.advance(ticks: Fixtures.ticksPerDay * 3)
        model = try #require(engine.state.onboardingModel(catalog: catalog))
        #expect(model.isDone(.watchFirstFlight))
        #expect(model.isDone(.earnFirstRevenue))
        #expect(model.isComplete)
        #expect(model.nextStep == nil)
    }

    @Test func noPlayerNoModel() throws {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(seed: 3),
                                      systems: GamePipeline.standard(),
                                      catalog: catalog)
        #expect(engine.state.onboardingModel(catalog: catalog) == nil)
    }
}
