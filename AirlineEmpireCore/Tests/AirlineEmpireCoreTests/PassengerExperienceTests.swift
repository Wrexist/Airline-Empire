import Testing
@testable import AirlineEmpireCore

/// The passenger-experience read models: component weights, fleet comfort and
/// the service-policy preview. The preview must be pure, deterministic, and
/// must never imply that choosing a tier buys reputation instantly.
@Suite("Passenger experience and service policy")
struct PassengerExperienceTests {
    @Test func componentWeightsMatchTheBlend() {
        var reputation = Reputation(initial: 0)
        reputation.punctuality = 0.9
        reputation.reliability = 0.8
        reputation.service = 0.7
        reputation.comfort = 0.6
        reputation.valuePerception = 0.5
        let weighted = ReputationComponent.allCases.reduce(0.0) {
            $0 + $1.weight * ReputationComponent.value(of: $1, in: reputation)
        }
        #expect(abs(weighted - reputation.score) < 1e-12)
        let total = ReputationComponent.allCases.reduce(0.0) { $0 + $1.weight }
        #expect(abs(total - 1) < 1e-12)
    }

    @Test func servicePreviewQuotesExactPerPassengerCosts() throws {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        let catalog = try DemandFixtures.anchorCatalog()
        let preview = try #require(ServicePolicyPreview.make(
            airline: airline, tier: .premium, state: engine.state, catalog: catalog))
        #expect(preview.currentTier == .standard)
        #expect(preview.proposedTier == .premium)
        #expect(preview.currentCostPerPassenger == Money.dollars(9))
        #expect(preview.proposedCostPerPassenger == Money.dollars(18))
        #expect(preview.costPerPassengerChange == Money.dollars(9))
        #expect(preview.referenceMonthlyPassengers > 0)
        #expect(preview.estimatedMonthlyCostNow
            == Money.dollars(9) * Int64(preview.referenceMonthlyPassengers))
        #expect(preview.estimatedMonthlyCostProposed
            == Money.dollars(18) * Int64(preview.referenceMonthlyPassengers))
        #expect(preview.estimatedMonthlyCostChange == preview.costPerPassengerChange
            * Int64(preview.referenceMonthlyPassengers))
        #expect(preview.servedRoutes == 1)
        #expect(preview.isChange)
    }

    @Test func selectingTheInstalledTierIsANoChangeQuote() throws {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        let catalog = try DemandFixtures.anchorCatalog()
        let preview = try #require(ServicePolicyPreview.make(
            airline: airline, tier: .standard, state: engine.state, catalog: catalog))
        #expect(!preview.isChange)
        #expect(preview.estimatedMonthlyCostChange == .zero)
        #expect(preview.costPerPassengerChange == .zero)
        #expect(preview.scoreIfServiceSettlesNow == preview.scoreIfServiceSettlesProposed)
        #expect(preview.multiplierIfServiceSettlesNow == preview.multiplierIfServiceSettlesProposed)
    }

    @Test func servicePreviewIsDeterministicAndDoesNotMutate() throws {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        let catalog = try DemandFixtures.anchorCatalog()
        let before = try engine.state.stateHash()
        let first = try #require(ServicePolicyPreview.make(
            airline: airline, tier: .premium, state: engine.state, catalog: catalog))
        let second = try #require(ServicePolicyPreview.make(
            airline: airline, tier: .premium, state: engine.state, catalog: catalog))
        #expect(first == second)
        #expect(try engine.state.stateHash() == before)
    }

    @Test func servicePreviewProjectsTheTierTarget() throws {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        let catalog = try DemandFixtures.anchorCatalog()
        let premium = try #require(ServicePolicyPreview.make(
            airline: airline, tier: .premium, state: engine.state, catalog: catalog))
        #expect(abs(premium.currentServiceTarget - 0.60) < 1e-12)
        #expect(abs(premium.proposedServiceTarget - 0.85) < 1e-12)
        #expect(premium.scoreIfServiceSettlesProposed > premium.scoreIfServiceSettlesNow)
        #expect(premium.multiplierIfServiceSettlesProposed > premium.multiplierIfServiceSettlesNow)

        let basic = try #require(ServicePolicyPreview.make(
            airline: airline, tier: .basic, state: engine.state, catalog: catalog))
        #expect(abs(basic.proposedServiceTarget - 0.35) < 1e-12)
        #expect(basic.scoreIfServiceSettlesProposed < basic.scoreIfServiceSettlesNow)
        #expect(basic.multiplierIfServiceSettlesProposed < basic.multiplierIfServiceSettlesNow)
    }

    @Test func groundExperienceLiftsOnlyThePlayersTarget() {
        let tuning = ReputationTuning.standard
        let lifted = ReputationSystem.serviceTarget(
            for: .premium, isPlayer: true, hasGroundExperience: true, tuning: tuning)
        let plain = ReputationSystem.serviceTarget(
            for: .premium, isPlayer: true, hasGroundExperience: false, tuning: tuning)
        let rival = ReputationSystem.serviceTarget(
            for: .premium, isPlayer: false, hasGroundExperience: true, tuning: tuning)
        #expect(abs(lifted - 0.93) < 1e-9)
        #expect(abs(plain - 0.85) < 1e-9)
        #expect(plain == rival)
    }

    @Test func choosingATierDoesNotChangeReputationToday() throws {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        engine.advance(ticks: Fixtures.ticksPerDay * 3)
        let before = engine.state.airlines[airline]!.reputation.service
        #expect(engine.applyNow(SetServiceTierCommand(airline: airline, tier: .premium)) == .applied)
        #expect(engine.state.airlines[airline]!.reputation.service == before)
        #expect(engine.state.airlines[airline]!.serviceTier == .premium)
    }

    @Test func serviceReputationRespondsGradually() throws {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        #expect(engine.applyNow(SetServiceTierCommand(airline: airline, tier: .premium)) == .applied)
        engine.advance(ticks: Fixtures.ticksPerDay)
        let dayOne = engine.state.airlines[airline]!.reputation.service
        // One daily drift step: 0.6 + 0.05 × (0.85 − 0.6).
        #expect(dayOne > 0.60 && dayOne < 0.63)
        engine.advance(ticks: Fixtures.ticksPerDay * 199)
        let settled = engine.state.airlines[airline]!.reputation.service
        #expect(settled > 0.84)
    }

    @Test func fleetComfortSnapshotMatchesTheReputationTarget() throws {
        let catalog = try DemandFixtures.anchorCatalog()
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        let aircraft = try #require(engine.state.fleet(of: airline).first)
        let spec = try #require(catalog.aircraftType(aircraft.typeCode))
        var cabin = aircraft.cabin(for: spec)
        cabin.setSeats(20, in: .business, capacity: spec.seats)
        cabin.wifi = 1
        cabin.seats = 1
        #expect(engine.applyNow(ConfigureAircraftCommand(
            airline: airline, aircraftID: aircraft.id, configuration: cabin)) == .applied)

        let state = engine.state
        let snapshot = try #require(FleetComfortSnapshot.make(
            airline: airline, state: state, catalog: catalog))
        let target = try #require(ReputationSystem.seatWeightedComfort(
            of: state.fleet(of: airline), catalog: catalog))
        #expect(abs(snapshot.seatWeightedComfort - target) < 1e-12)
        #expect(snapshot.aircraftCount == 1)
        #expect(snapshot.premiumSeatShare > 0)
        #expect(snapshot.upgradeLevelsPerSeat > 0)

        // The comfort component drifts toward this number, never the reverse.
        engine.advance(ticks: Fixtures.ticksPerDay * 120)
        #expect(abs(engine.state.airlines[airline]!.reputation.comfort - target) < 0.02)
    }

    @Test func servicePolicySurvivesSaveAndRestore() throws {
        let catalog = try DemandFixtures.anchorCatalog()
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        #expect(engine.applyNow(SetServiceTierCommand(airline: airline, tier: .premium)) == .applied)
        engine.advance(ticks: Fixtures.ticksPerDay * 41)

        let data = try JSONSaveCodec().encode(engine.state)
        let restored = try JSONSaveCodec().decode(data)
        #expect(restored.airlines[airline]?.serviceTier == .premium)
        let resumed = SimulationEngine(state: restored,
                                       systems: GamePipeline.standard(), catalog: catalog)
        resumed.advance(ticks: Fixtures.ticksPerDay * 49)
        engine.advance(ticks: Fixtures.ticksPerDay * 49)
        #expect(try resumed.state.stateHash() == engine.state.stateHash())
    }
}
