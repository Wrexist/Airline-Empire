/// Passenger experience and reputation read models.
///
/// Everything a screen needs to explain *what moves reputation* and *what a
/// service-tier decision costs* lives here, in Core, computed from the same
/// simulation the engine runs. Views format these values; they never re-derive
/// an effect of their own (docs/UI_ARCHITECTURE.md §2).
///
/// The tier is a recurring per-passenger cost and a *target* the service
/// component drifts toward over weeks. Nothing in this file changes a
/// reputation score when a tier is chosen — the drift is the simulation's job.

/// The five terms of `Reputation.score`, with the weights the blend uses.
///
/// `Reputation.score` holds the arithmetic (design constants, not tuning —
/// docs/GAME_BALANCE.md §5). These names expose the same weights so a screen
/// can say "punctuality is a quarter of the score" without restating it, and
/// `PassengerExperienceTests.componentWeightsMatchTheBlend` pins the two
/// together so neither can drift from the other unnoticed.
public enum ReputationComponent: String, CaseIterable, Sendable {
    case punctuality, reliability, service, comfort, value

    public var weight: Double {
        switch self {
        case .punctuality: 0.25
        case .reliability: 0.25
        case .service: 0.20
        case .comfort: 0.15
        case .value: 0.15
        }
    }

    /// The component's own 0…1 value on an airline's reputation.
    public static func value(of component: ReputationComponent,
                             in reputation: Reputation) -> Double {
        switch component {
        case .punctuality: reputation.punctuality
        case .reliability: reputation.reliability
        case .service: reputation.service
        case .comfort: reputation.comfort
        case .value: reputation.valuePerception
        }
    }
}

/// What the fleet's Comfort component is made of.
///
/// `ReputationSystem` drifts the comfort component toward the seat-weighted
/// `passengerComfort` of the fleet — cabin layout plus onboard upgrades, from
/// the configuration the player actually flies. Aircraft age does not enter
/// comfort; it enters reliability. This read model exists so the screen can
/// say that plainly instead of the stale "newer and larger cabins score
/// better" the old copy carried.
public struct FleetComfortSnapshot: Equatable, Sendable {
    public let aircraftCount: Int
    /// Seat-weighted cabin comfort, identical to the value the reputation
    /// system drifts toward (`ReputationSystem.seatWeightedComfort`).
    public let seatWeightedComfort: Double
    /// Seat-weighted share of seats in first/business/premium economy.
    public let premiumSeatShare: Double
    /// Seat-weighted onboard upgrade levels per seat: Wi-Fi, dining, seat
    /// comfort and entertainment, each 0…2.
    public let upgradeLevelsPerSeat: Double

    public static func make(airline: AirlineID, state: GameState,
                            catalog: ContentCatalog) -> Self? {
        let fleet = state.fleet(of: airline)
        guard !fleet.isEmpty else { return nil }
        var seats = 0.0, comfort = 0.0, premiumSeats = 0.0, upgradeLevels = 0.0
        for aircraft in fleet {
            guard let spec = catalog.aircraftType(aircraft.typeCode) else { continue }
            let cabin = aircraft.cabin(for: spec)
            let count = Double(cabin.totalSeats)
            guard count > 0 else { continue }
            seats += count
            comfort += count * aircraft.passengerComfort(for: spec, tuning: catalog.tuning.cabin)
            premiumSeats += Double(cabin.first + cabin.business + cabin.premiumEconomy)
            upgradeLevels += count * Double(cabin.wifi + cabin.dining + cabin.seats + cabin.entertainment)
        }
        guard seats > 0 else { return nil }
        return Self(aircraftCount: fleet.count,
                    seatWeightedComfort: comfort / seats,
                    premiumSeatShare: premiumSeats / seats,
                    upgradeLevelsPerSeat: upgradeLevels / seats)
    }
}

/// A deterministic, read-only quote for a proposed airline-wide service tier.
///
/// Nothing here mutates the world: the demand allocation runs on a value copy
/// and no command is submitted. Every number is either exact tuning
/// (per-passenger cost, tier target) or a stated estimate (monthly cost at the
/// reference passenger volume, and the reputation the service component is
/// heading toward).
///
/// It deliberately reports **no** immediate demand change. A tier moves the
/// service component's target; reputation drifts toward it at the simulation's
/// own rate. The projected multiplier is what demand settles at *if* service
/// reaches the target and the other four components stay where they are.
public struct ServicePolicyPreview: Equatable, Sendable {
    public let currentTier: ServiceTier
    public let proposedTier: ServiceTier

    public let currentCostPerPassenger: Money
    public let proposedCostPerPassenger: Money
    public var costPerPassengerChange: Money {
        proposedCostPerPassenger - currentCostPerPassenger
    }

    /// Seat-limited passengers over a 30-day reference month at today's
    /// demand, fares and aircraft assignment.
    public let referenceMonthlyPassengers: Int
    public let estimatedMonthlyCostNow: Money
    public let estimatedMonthlyCostProposed: Money
    public var estimatedMonthlyCostChange: Money {
        estimatedMonthlyCostProposed - estimatedMonthlyCostNow
    }

    /// The service component each tier drifts toward (0…1).
    public let currentServiceTarget: Double
    public let proposedServiceTarget: Double
    /// The airline's actual service component today.
    public let currentService: Double

    public let currentScore: Double
    /// Reputation if service settled at the tier's target with the other four
    /// components held where they are today.
    public let scoreIfServiceSettlesNow: Double
    public let scoreIfServiceSettlesProposed: Double

    /// The engine's demand multiplier today, and its projection once service
    /// settles under each tier.
    public let currentDemandMultiplier: Double
    public let multiplierIfServiceSettlesNow: Double
    public let multiplierIfServiceSettlesProposed: Double

    /// Whether the ground-experience capability is lifting the target by 8
    /// points. A player who has not built it has no bump.
    public let groundExperienceBonus: Bool
    /// Routes with operational aircraft that contribute to the volume estimate.
    public let servedRoutes: Int

    public var isChange: Bool { currentTier != proposedTier }

    public static func make(airline: AirlineID, tier: ServiceTier, state: GameState,
                            catalog: ContentCatalog) -> Self? {
        guard let owner = state.airlines[airline], owner.status == .active else { return nil }
        let tuning = catalog.tuning.reputation
        let isPlayer = state.isPlayer(airline)
        let hasGroundExperience = isPlayer && state.playerHasCapability(.groundExperience)

        let passengers = referenceMonthlyPassengers(airline: airline, state: state, catalog: catalog)
        let currentPerPax = tuning.serviceCostPerPax(owner.serviceTier)
        let proposedPerPax = tuning.serviceCostPerPax(tier)

        let currentTarget = ReputationSystem.serviceTarget(
            for: owner.serviceTier, isPlayer: isPlayer,
            hasGroundExperience: hasGroundExperience, tuning: tuning)
        let proposedTarget = ReputationSystem.serviceTarget(
            for: tier, isPlayer: isPlayer,
            hasGroundExperience: hasGroundExperience, tuning: tuning)

        let routes = state.routes(of: airline).filter { route in
            route.assignedAircraft.contains { state.aircraft[$0]?.isOperational == true }
        }

        return Self(
            currentTier: owner.serviceTier,
            proposedTier: tier,
            currentCostPerPassenger: currentPerPax,
            proposedCostPerPassenger: proposedPerPax,
            referenceMonthlyPassengers: passengers,
            estimatedMonthlyCostNow: currentPerPax * Int64(passengers),
            estimatedMonthlyCostProposed: proposedPerPax * Int64(passengers),
            currentServiceTarget: currentTarget,
            proposedServiceTarget: proposedTarget,
            currentService: owner.reputation.service,
            currentScore: owner.reputation.score,
            scoreIfServiceSettlesNow: projectedScore(owner.reputation, service: currentTarget),
            scoreIfServiceSettlesProposed: projectedScore(owner.reputation, service: proposedTarget),
            currentDemandMultiplier: owner.reputation.demandMultiplier(tuning: tuning),
            multiplierIfServiceSettlesNow: projectedMultiplier(owner.reputation, service: currentTarget, tuning: tuning),
            multiplierIfServiceSettlesProposed: projectedMultiplier(owner.reputation, service: proposedTarget, tuning: tuning),
            groundExperienceBonus: hasGroundExperience,
            servedRoutes: routes.count)
    }

    /// Seat-limited passengers the airline would board over 30 days, read from
    /// the demand engine's own allocation on a value copy. The world is not
    /// touched: the same aircraft configuration preview the aircraft screen
    /// uses is the single source for carried passengers.
    public static func referenceMonthlyPassengers(airline: AirlineID, state: GameState,
                                                  catalog: ContentCatalog) -> Int {
        var copy = state
        let context = SimContext(previous: state.clock.now, current: state.clock.now,
            tick: .minutes(0), catalog: catalog, events: EventCollector(),
            progressionCeiling: .empire)
        DemandSystem().update(state: &copy, context: context)
        var total = 0
        for aircraft in state.fleet(of: airline)
        where aircraft.isOperational && aircraft.assignedRoute != nil {
            if let quote = AircraftConfigurationPreview.makeAllocated(
                aircraftID: aircraft.id, state: copy, catalog: catalog) {
                total += quote.monthlyPassengers
            }
        }
        return total
    }

    private static func projectedScore(_ reputation: Reputation, service: Double) -> Double {
        reputation.score + ReputationComponent.service.weight
            * (min(1, max(0, service)) - reputation.service)
    }

    private static func projectedMultiplier(_ reputation: Reputation, service: Double,
                                            tuning: ReputationTuning) -> Double {
        var copy = reputation
        copy.service = min(1, max(0, service))
        return copy.demandMultiplier(tuning: tuning)
    }
}
