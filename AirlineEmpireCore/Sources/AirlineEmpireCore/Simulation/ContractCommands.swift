/// Optional, modest bonuses for operating an airline. One acceptance per
/// calendar month, with the decision and progress stored in existing slices.
public enum ContractChoice: String, CaseIterable, Codable, Hashable, Sendable {
    case flights, passengers
}

public struct ContractOffer: Equatable, Sendable {
    public let choice: ContractChoice
    public let kind: MissionKind
    public let reward: Money
    public let baseline: Int64
    public let deadline: SimTime
    public static let durationDays: Int64 = 28
    static let cooldownKey = "contract.lastAcceptedMonth"

    static func month(in state: GameState) -> Int64 {
        Int64(state.currentDate.year) * 12 + Int64(state.currentDate.month)
    }

    public static func offers(in state: GameState) -> [ContractOffer] {
        guard let player = state.playerAirline, player.status == .active,
              state.progression.hasMilestone("firstFlight"),
              state.world.eventCooldowns[cooldownKey] != month(in: state),
              !state.progression.missions.contains(where: {
                  switch $0.kind {
                  case .boomRush: false
                  case .flightContract, .passengerContract: true
                  }
              }) else { return [] }
        let fleet = Int64(min(20, max(1, state.fleet(of: player.id).count)))
        let flights = min(300, fleet * 30)
        let passengers = fleet * 5_000
        // Missions settle at midnight. Publish that exact deadline instead
        // of promising a partial final day the daily resolver cannot honor.
        let deadline = SimTime(rawMinutes: (state.clock.now.dayIndex + durationDays)
                               * GameCalendar.minutesPerDay)
        return [
            ContractOffer(choice: .flights, kind: .flightContract(targetFlights: flights),
                          reward: .dollars(flights * 1_500),
                          baseline: state.progression.counters.flightsCompleted, deadline: deadline),
            ContractOffer(choice: .passengers, kind: .passengerContract(targetPassengers: passengers),
                          reward: .dollars(passengers * 2),
                          baseline: state.progression.counters.passengersCarried, deadline: deadline)
        ]
    }
}

public struct AcceptContractCommand: Command, Equatable {
    public static let name = "acceptContract"
    public let choice: ContractChoice
    public init(choice: ContractChoice) { self.choice = choice }

    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard ContractOffer.offers(in: state).contains(where: { $0.choice == choice }) else {
            return CommandRejection(code: "progression.contractUnavailable",
                                    message: "Finish your current contract and wait until the next calendar month for another offer.")
        }
        return nil
    }

    public func apply(state: inout GameState, context: SimContext) {
        guard let offer = ContractOffer.offers(in: state).first(where: { $0.choice == choice }) else { return }
        let month = ContractOffer.month(in: state)
        let mission = Mission(id: state.progression.nextMissionID,
                              sourceEventID: -10_000_000 - month,
                              kind: offer.kind,
                              deadline: offer.deadline,
                              reward: offer.reward, baseline: offer.baseline)
        state.progression.nextMissionID += 1
        state.progression.missions.append(mission)
        state.world.eventCooldowns[ContractOffer.cooldownKey] = month
        context.emit(.missionOffered(id: mission.id, kind: mission.kind,
                                   deadline: mission.deadline, reward: mission.reward))
    }
}
