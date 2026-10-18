import Foundation
import Testing
@testable import AirlineEmpireCore

@Suite("Rescue financing and optional contracts")
struct RescueAndContractTests {
    private func distressed() throws -> SimulationEngine {
        let (original, id, _) = try DemandFixtures.market(fare: .dollars(129))
        var state = original.state
        state.ledger.post(airline: id, category: .overhead,
                          amount: .dollars(-3_000_000) - state.ledger.balance(of: id),
                          at: state.clock.now, memo: "Test distress")
        state.airlines[id]?.daysInsolvent = 1
        return SimulationEngine(state: state, systems: [EconomySystem()], catalog: original.catalog)
    }

    @Test func acceptedRescueIsDebtAndCannotBeRepeatedAfterReload() throws {
        let engine = try distressed()
        let id = try #require(engine.state.playerAirline?.id)
        let offer = try #require(RescueOffer.available(in: engine.state, catalog: engine.catalog))
        let before = engine.state.ledger.balance(of: id)
        #expect(engine.applyNow(DecideRescueCommand(accept: true)) == .applied)
        #expect(engine.state.ledger.balance(of: id) == before + offer.principal)
        let loan = try #require(engine.state.playerAirline?.loans.last)
        #expect(loan.monthlyPayment == offer.monthlyPayment)
        #expect(loan.principalRemaining == offer.principal)
        let restored = try JSONSaveCodec().decode(JSONSaveCodec().encode(engine.state))
        #expect(restored.playerAirline?.rescueDecision == .accepted)
        #expect(DecideRescueCommand(accept: true).validate(state: restored, catalog: engine.catalog) != nil)
        engine.advance(ticks: Fixtures.ticksPerDay * 32)
        let repaying = try #require(engine.state.playerAirline?.loans.last)
        #expect(repaying.principalRemaining < loan.principalRemaining)
        #expect(repaying.monthsRemaining < loan.monthsRemaining)
    }

    @Test func declinePersistsWithoutChangingCashOrLoans() throws {
        let engine = try distressed()
        let before = engine.state
        #expect(engine.applyNow(DecideRescueCommand(accept: false)) == .applied)
        let restored = try JSONSaveCodec().decode(JSONSaveCodec().encode(engine.state))
        #expect(restored.playerAirline?.rescueDecision == .declined)
        #expect(restored.ledger == before.ledger)
        #expect(restored.playerAirline?.loans == before.playerAirline?.loans)
        #expect(RescueOffer.available(in: restored, catalog: engine.catalog) == nil)
    }

    @Test func rescueCannotFollowAdministrationOrCoverUnlimitedLosses() throws {
        let engine = try distressed()
        var state = engine.state
        let id = try #require(state.playerAirline?.id)
        state.airlines[id]?.administrationCount = 1
        #expect(RescueOffer.available(in: state, catalog: engine.catalog) == nil)
        state.airlines[id]?.administrationCount = 0
        state.ledger.post(airline: id, category: .overhead, amount: .dollars(-20_000_000),
                          at: state.clock.now, memo: "Beyond rescue cap")
        #expect(RescueOffer.available(in: state, catalog: engine.catalog) == nil)
    }

    @Test func legacySaveDefaultsRescueWithoutLosingDebt() throws {
        let engine = try distressed()
        #expect(engine.applyNow(DecideRescueCommand(accept: true)) == .applied)
        var tree = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.state)) as? [String: Any])
        var airlines = try #require(tree["airlines"] as? [String: Any])
        for key in airlines.keys {
            var airline = try #require(airlines[key] as? [String: Any])
            airline.removeValue(forKey: "rescueDecision")
            airlines[key] = airline
        }
        tree["airlines"] = airlines
        let envelope = SaveEnvelope(formatVersion: 12, contentVersion: "0", savedAtTick: 0,
                                    payload: try JSONSerialization.data(withJSONObject: tree))
        let restored = try JSONSaveCodec().decode(JSONEncoder().encode(envelope))
        #expect(restored.playerAirline?.rescueDecision == .unreviewed)
        #expect(restored.playerAirline?.loans == engine.state.playerAirline?.loans)
        #expect(restored.ledger == engine.state.ledger)
    }

    @Test(arguments: ContractChoice.allCases)
    func contractsCountOnlyNewActivityAndPayExactlyOnce(choice: ContractChoice) throws {
        let (original, id, _) = try DemandFixtures.market(fare: .dollars(129))
        var state = original.state
        state.progression.milestones.append("firstFlight")
        state.progression.counters.flightsCompleted = 1_000
        state.progression.counters.passengersCarried = 100_000
        let engine = SimulationEngine(state: state, systems: [ProgressionSystem()], catalog: original.catalog)
        #expect(engine.applyNow(AcceptContractCommand(choice: choice)) == .applied)
        let mission = try #require(engine.state.progression.missions.first)
        let player = try #require(engine.state.playerAirline)
        #expect(MissionMath.progress(of: mission, player: player,
                                    state: engine.state, catalog: engine.catalog) == 0)
        #expect(ContractOffer.offers(in: engine.state).isEmpty)
        var restored = try JSONSaveCodec().decode(JSONSaveCodec().encode(engine.state))
        let target = MissionMath.target(of: mission)
        switch choice {
        case .flights: restored.progression.counters.flightsCompleted += target
        case .passengers: restored.progression.counters.passengersCarried += target
        }
        let completing = SimulationEngine(state: restored, systems: [ProgressionSystem()], catalog: engine.catalog)
        let cash = restored.ledger.balance(of: id)
        completing.advance(ticks: Fixtures.ticksPerDay)
        #expect(completing.state.progression.missions.isEmpty)
        #expect(completing.state.ledger.balance(of: id) == cash + mission.reward)
        completing.advance(ticks: Fixtures.ticksPerDay)
        #expect(completing.state.ledger.balance(of: id) == cash + mission.reward)
        #expect(ContractOffer.offers(in: completing.state).isEmpty)
    }

    /// GAME_AUDIT_2026-10-18 §6: a flight contract asked for 30 flights per
    /// aircraft in 28 days — about a week of one airframe's ordinary flying —
    /// so the bonus paid for doing nothing differently. The target is now
    /// about 110% of what the airline actually flew over the last four weeks;
    /// the reward is unchanged.
    @Test func contractTargetsAskForGrowthOverTheLastFourWeeks() throws {
        let (engine, _, _) = try DemandFixtures.market(fare: .dollars(129))
        // Five weeks of the full pipeline fill the four-week history.
        engine.advance(ticks: Fixtures.ticksPerDay * 35)
        let state = engine.state
        let recent = state.progression.recentActivity
        #expect(recent.days == ProgressionState.activityWindowDays)
        try #require(recent.flights > 0)

        let offers = ContractOffer.offers(in: state)
        let flights = try #require(offers.first { $0.choice == .flights })
        guard case .flightContract(let target) = flights.kind else {
            Issue.record("expected a flight contract, got \(flights.kind)"); return
        }
        let pace = Double(recent.flights) / Double(recent.days)
            * Double(ContractOffer.durationDays)
        #expect(target == Int64((pace * ContractOffer.growthFactor).rounded(.up)))
        // More than the airline flew in the last 28 days, and far more than
        // the week of flying the old 30-per-aircraft figure asked for.
        #expect(target > recent.flights)
        #expect(target > 30)
        // One aircraft: the reward basis is the old figure, unchanged.
        #expect(flights.reward == .dollars(30 * 1_500))
    }

    @Test func contractTargetsFallBackToTheOldFloorAndScaleShortHistory() throws {
        let (original, _, _) = try DemandFixtures.market(fare: .dollars(129))
        var state = original.state
        state.progression.milestones.append("firstFlight")

        // No history — day one, or a save from before the marks: the old
        // per-aircraft figures.
        state.progression.activityMarks = nil
        var offers = ContractOffer.offers(in: state)
        #expect(offers.first { $0.choice == .flights }?.kind == .flightContract(targetFlights: 30))
        #expect(offers.first { $0.choice == .passengers }?.kind
                == .passengerContract(targetPassengers: 5_000))

        // A week of history at 10 flights and 1,000 passengers a day is
        // scaled to the contract's four weeks before the 10% stretch.
        state.progression.activityMarks = (0...7).map {
            ActivityMark(flights: Int64($0) * 10, passengers: Int64($0) * 1_000)
        }
        offers = ContractOffer.offers(in: state)
        #expect(offers.first { $0.choice == .flights }?.kind == .flightContract(
            targetFlights: Int64((280.0 * ContractOffer.growthFactor).rounded(.up))))
        #expect(offers.first { $0.choice == .passengers }?.kind == .passengerContract(
            targetPassengers: Int64((28_000.0 * ContractOffer.growthFactor).rounded(.up))))
    }

    @Test func ignoredOffersAndExpiredContractsCostNothing() throws {
        let (original, id, _) = try DemandFixtures.market(fare: .dollars(129))
        var state = original.state
        #expect(ContractOffer.offers(in: state).isEmpty)
        state.progression.milestones.append("firstFlight")
        let untouched = state
        #expect(ContractOffer.offers(in: state).count == 2)
        #expect(state == untouched)
        let engine = SimulationEngine(state: state, systems: [ProgressionSystem()], catalog: original.catalog)
        #expect(engine.applyNow(AcceptContractCommand(choice: .flights)) == .applied)
        let cash = engine.state.ledger.balance(of: id)
        engine.advance(ticks: Fixtures.ticksPerDay * 32)
        #expect(engine.state.progression.missions.isEmpty)
        #expect(engine.state.ledger.balance(of: id) == cash)
        #expect(ContractOffer.offers(in: engine.state).count == 2)
    }

    @Test func activityAfterDeadlineDoesNotEarnAReward() throws {
        let (original, id, _) = try DemandFixtures.market(fare: .dollars(129))
        var state = original.state
        state.progression.missions = [Mission(id: 800, sourceEventID: -800,
            kind: .flightContract(targetFlights: 10), deadline: state.clock.now,
            reward: .dollars(15_000), baseline: 0)]
        state.progression.counters.flightsCompleted = 10
        let engine = SimulationEngine(state: state, systems: [ProgressionSystem()], catalog: original.catalog)
        engine.advance(ticks: Fixtures.ticksPerDay)
        #expect(engine.state.progression.missions.isEmpty)
        #expect(engine.state.ledger.balance(of: id) == state.ledger.balance(of: id))
    }

    @Test func middayAcceptanceQuotesAnExactSettlementBoundary() throws {
        let (original, _, _) = try DemandFixtures.market(fare: .dollars(129))
        var state = original.state
        state.clock.now += .minutes(12 * 60)
        state.progression.milestones.append("firstFlight")
        let offer = try #require(ContractOffer.offers(in: state).first)
        #expect(offer.deadline.minuteOfDay == 0)
        #expect(offer.deadline.dayIndex == state.clock.now.dayIndex + 28)
        let engine = SimulationEngine(state: state, systems: [], catalog: original.catalog)
        #expect(engine.applyNow(AcceptContractCommand(choice: offer.choice)) == .applied)
        #expect(engine.state.progression.missions.first?.deadline == offer.deadline)
    }
}
