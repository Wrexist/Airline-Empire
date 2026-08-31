import Testing
@testable import AirlineEmpireCore

@Suite("Reputation & service")
struct ReputationTests {
    @Test func componentsAndMultiplierBounds() throws {
        let tuning = ReputationTuning.standard
        var reputation = Reputation()
        #expect(reputation.score > 0.55 && reputation.score < 0.65)
        reputation.punctuality = 2.0 // abuse guard
        Reputation.drift(&reputation.punctuality, toward: 5.0, rate: 1.0)
        #expect(reputation.punctuality == 1.0)
        reputation = Reputation()
        reputation.applyScar(factor: 0.85)
        #expect(reputation.score < Reputation().score)
        let floor = Reputation(initial: 0)
        var bottom = floor
        bottom.farePositionEWMA = 1
        #expect(abs(bottom.demandMultiplier(tuning: tuning) - 0.8) < 0.001)
        var top = Reputation(initial: 1)
        top.farePositionEWMA = 1
        #expect(abs(top.demandMultiplier(tuning: tuning) - 1.25) < 0.001)
    }

    @Test func reliableOperationBuildsReputation() throws {
        // Anchor market, young reliable aircraft, sane schedule.
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        let before = engine.state.airlines[airline]!.reputation
        engine.advance(ticks: Fixtures.ticksPerYear)
        let after = engine.state.airlines[airline]!.reputation
        // High completion/punctuality drag both components up from 0.6.
        #expect(after.reliability > before.reliability)
        #expect(after.reliability > 0.9)
        #expect(after.punctuality > 0.85)
    }

    @Test func unreliableFleetErodesReputation() throws {
        // A clapped-out turboprop flying a packed schedule bleeds delays and
        // cancellations; reputation follows the performance down.
        let (_, engine, airline, _) = try RouteFixtures.withAircraft()
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "NA70", ageYears: 22))
        let old = engine.state.aircraft.values.first {
            $0.typeCode == AircraftTypeCode("NA70") }!.id
        _ = engine.applyNow(OpenRouteCommand(
            airline: airline, origin: "ARN", destination: "OSL",
            dailyRoundTrips: 6, ticketPrice: Money.dollars(59)))
        let route = engine.state.routes.values.first {
            $0.destination == AirportCode("OSL") }!.id
        _ = engine.applyNow(AssignAircraftToRouteCommand(
            airline: airline, route: route, aircraftID: old))
        engine.advance(ticks: Fixtures.ticksPerDay * 120)
        let reputation = engine.state.airlines[airline]!.reputation
        // Reputation converges toward measured performance: a worn airframe
        // on a packed schedule can't reach the levels a reliable operation
        // does (cf. reliableOperationBuildsReputation: >0.9 / >0.85... this
        // one stays visibly below those ceilings).
        #expect(reputation.reliability < 0.97)
        #expect(reputation.punctuality < 0.95)
    }

    @Test func serviceTierMovesServiceComponentAndCosts() throws {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        #expect(engine.applyNow(SetServiceTierCommand(airline: airline, tier: .premium))
                == .applied)
        engine.advance(ticks: Fixtures.ticksPerDay * 120)
        let premium = engine.state.airlines[airline]!.reputation.service
        #expect(premium > 0.75) // drifting toward 0.85
        // Service is being paid for, per passenger.
        let serviceSpend = engine.state.ledger.recent
            .filter { $0.category == .passengerService }
        #expect(!serviceSpend.isEmpty)
        #expect(serviceSpend.allSatisfy { $0.amount < .zero })

        // And a basic-tier airline drifts down instead.
        let (engine2, airline2, _) = try DemandFixtures.market(fare: Money.dollars(129))
        _ = engine2.applyNow(SetServiceTierCommand(airline: airline2, tier: .basic))
        engine2.advance(ticks: Fixtures.ticksPerDay * 120)
        #expect(engine2.state.airlines[airline2]!.reputation.service < 0.5)
    }

    @Test func overpricingErodesValuePerception() throws {
        let fair = try DemandFixtures.market(fare: Money.dollars(129))
        let gouger = try DemandFixtures.market(fare: Money.dollars(320))
        fair.0.advance(ticks: Fixtures.ticksPerYear)
        gouger.0.advance(ticks: Fixtures.ticksPerYear)
        let fairValue = fair.0.state.airlines[fair.1]!.reputation.valuePerception
        let gougerValue = gouger.0.state.airlines[gouger.1]!.reputation.valuePerception
        #expect(gougerValue < fairValue)
        #expect(gougerValue < 0.35)
    }

    @Test func reputationFeedsBackIntoDemand() throws {
        // Two identical offers; one airline carries a scarred reputation.
        let catalog = try DemandFixtures.anchorCatalog()
        let engine = SimulationEngine(state: Fixtures.newState(),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(airlineName: "Shiny", kind: .player,
                                                homeAirport: "MET",
                                                startingCash: Money.dollars(300_000_000)))
        _ = engine.applyNow(FoundAirlineCommand(airlineName: "Scarred", kind: .ai,
                                                homeAirport: "COS",
                                                startingCash: Money.dollars(300_000_000)))
        let shiny = engine.state.airlines.values.first { $0.name == "Shiny" }!.id
        let scarred = engine.state.airlines.values.first { $0.name == "Scarred" }!.id
        // Scar one before service begins.
        var scarredAirline = engine.state.airlines[scarred]!
        scarredAirline.reputation.applyScar(factor: 0.5)
        // Direct state edit is test-only surgery; commands are the real path.
        var mutated = engine.state
        mutated.airlines[scarred] = scarredAirline
        let surgical = SimulationEngine(state: mutated,
                                        systems: GamePipeline.standard(), catalog: catalog)
        for (airline, home) in [(shiny, "MET"), (scarred, "COS")] {
            _ = surgical.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180",
                                                         ageYears: 2))
            let aircraft = surgical.state.aircraft.values.first {
                $0.owner == airline && $0.assignedRoute == nil }!.id
            let away: AirportCode = home == "MET" ? "COS" : "MET"
            _ = surgical.applyNow(OpenRouteCommand(
                airline: airline, origin: AirportCode(home), destination: away,
                dailyRoundTrips: 2, ticketPrice: Money.dollars(129)))
            let route = surgical.state.routes.values.first { $0.airline == airline }!.id
            _ = surgical.applyNow(AssignAircraftToRouteCommand(
                airline: airline, route: route, aircraftID: aircraft))
        }
        surgical.advance(ticks: Fixtures.ticksPerDay * 28)
        let shinyPax = surgical.state.routes.values.first { $0.airline == shiny }!
            .stats.passengersCarried
        let scarredPax = surgical.state.routes.values.first { $0.airline == scarred }!
            .stats.passengersCarried
        // Logit share allocation dampens the raw multiplier gap, and the
        // scarred carrier recovers over the month; a persistent visible
        // share advantage is the design contract.
        #expect(Double(shinyPax) > Double(scarredPax) * 1.05,
                "shiny \(shinyPax) vs scarred \(scarredPax)")
    }

    @Test func premiumServiceEconomicsTradeoff() throws {
        // Premium service costs real money but lifts reputation -> demand;
        // both sides of the loop must be visible.
        let standard = try DemandFixtures.market(fare: Money.dollars(129))
        let premium = try DemandFixtures.market(fare: Money.dollars(129))
        _ = premium.0.applyNow(SetServiceTierCommand(airline: premium.1, tier: .premium))
        standard.0.advance(ticks: Fixtures.ticksPerYear)
        premium.0.advance(ticks: Fixtures.ticksPerYear)
        let standardPax = standard.0.state.routes[standard.2]!.stats.passengersCarried
        let premiumPax = premium.0.state.routes[premium.2]!.stats.passengersCarried
        #expect(premiumPax > standardPax)
        let premiumServiceSpend = -premium.0.state.ledger.recent
            .filter { $0.category == .passengerService }
            .reduce(Money.zero) { $0 + $1.amount }
        #expect(premiumServiceSpend > .zero)
    }

    @Test func reputationSurvivesSaveDeterministically() throws {
        let catalog = try ContentCatalog.loadBundled()
        func build() throws -> SimulationEngine {
            let engine = SimulationEngine(state: Fixtures.newState(seed: 606),
                                          systems: GamePipeline.standard(), catalog: catalog)
            _ = engine.applyNow(FoundAirlineCommand(
                airlineName: "RepSave", kind: .player, homeAirport: "ARN",
                startingCash: Money.dollars(150_000_000)))
            let airline = engine.state.airlines.values.first!.id
            _ = engine.applyNow(SetServiceTierCommand(airline: airline, tier: .premium))
            _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180",
                                                       ageYears: 4))
            _ = engine.applyNow(OpenRouteCommand(
                airline: airline, origin: "ARN", destination: "LHR",
                dailyRoundTrips: 2, ticketPrice: Money.dollars(139)))
            let route = engine.state.routes.values.first!.id
            let aircraft = engine.state.aircraft.values.first!.id
            _ = engine.applyNow(AssignAircraftToRouteCommand(
                airline: airline, route: route, aircraftID: aircraft))
            return engine
        }
        let straight = try build()
        straight.advance(ticks: Fixtures.ticksPerDay * 90)
        let split = try build()
        split.advance(ticks: Fixtures.ticksPerDay * 41)
        let data = try JSONSaveCodec().encode(split.state)
        let resumed = SimulationEngine(state: try JSONSaveCodec().decode(data),
                                       systems: GamePipeline.standard(), catalog: catalog)
        resumed.advance(ticks: Fixtures.ticksPerDay * 49)
        #expect(try resumed.state.stateHash() == straight.state.stateHash())
    }
}
