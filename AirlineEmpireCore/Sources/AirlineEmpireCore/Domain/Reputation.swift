/// Airline reputation: multi-component, slow-moving, always drifting toward
/// current performance (docs/GAME_DESIGN.md §4.10). Good history buys grace,
/// never immunity; bad stretches are recoverable by design.
public struct Reputation: Equatable, Codable, Sendable {
    /// All components 0…1.
    public var punctuality: Double
    /// Completion (not cancelling) + baggage-style dependability.
    public var reliability: Double
    /// Onboard product vs. expectations (driven by service tier).
    public var service: Double
    /// Fleet hardware comfort (seat/cabin quality).
    public var comfort: Double
    /// "Worth the fare": quality relative to price positioning.
    public var valuePerception: Double
    /// EWMA of fare-to-reference ratio; input to value perception.
    public var farePositionEWMA: Double

    public init(initial: Double = 0.6) {
        punctuality = initial
        reliability = initial
        service = initial
        comfort = initial
        valuePerception = initial
        farePositionEWMA = 1.0
    }

    /// Blended 0…1 score (weights in tuning would be over-config; these are
    /// design constants — docs/GAME_BALANCE.md §5).
    public var score: Double {
        0.25 * punctuality + 0.25 * reliability + 0.20 * service
            + 0.15 * comfort + 0.15 * valuePerception
    }

    /// Demand attractiveness multiplier: ×0.8 (dismal) … ×1.25 (excellent);
    /// neutral 0.5-score airline ≈ ×1.02.
    public func demandMultiplier(tuning: ReputationTuning) -> Double {
        tuning.multiplierBase + tuning.multiplierSpan * score
    }

    /// One EWMA step toward a measured/target value.
    static func drift(_ current: inout Double, toward target: Double, rate: Double) {
        current += rate * (target - current)
        current = min(1, max(0, current))
    }

    /// Uniform scar applied by administration/collapse.
    public mutating func applyScar(factor: Double) {
        punctuality *= factor
        reliability *= factor
        service *= factor
        comfort *= factor
        valuePerception *= factor
    }
}

/// Cabin service tier: the per-passenger product investment
/// (docs/GAME_DESIGN.md §4.10).
public enum ServiceTier: String, Codable, Sendable, CaseIterable {
    case basic
    case standard
    case premium
}

/// Same-day operational counters per airline, reset by the daily
/// ReputationSystem after measuring.
public struct DailyOps: Equatable, Codable, Sendable {
    public var completed: Int
    public var cancelled: Int
    public var delayed: Int

    public init(completed: Int = 0, cancelled: Int = 0, delayed: Int = 0) {
        self.completed = completed
        self.cancelled = cancelled
        self.delayed = delayed
    }

    public var flights: Int { completed + cancelled }
}

public struct ReputationTuning: Equatable, Codable, Sendable {
    /// Daily EWMA rate: ~0.05 makes reputation a weeks-scale memory.
    public let driftRate: Double
    /// Slower drift for value perception (positioning reads over months).
    public let valueDriftRate: Double
    public let initialComponent: Double
    public let multiplierBase: Double
    public let multiplierSpan: Double
    public let serviceCostPerPaxBasic: Money
    public let serviceCostPerPaxStandard: Money
    public let serviceCostPerPaxPremium: Money
    public let serviceTargetBasic: Double
    public let serviceTargetStandard: Double
    public let serviceTargetPremium: Double
    /// Reputation multiplier applied by administration (scar).
    public let administrationScar: Double

    public init(driftRate: Double, valueDriftRate: Double, initialComponent: Double,
                multiplierBase: Double, multiplierSpan: Double,
                serviceCostPerPaxBasic: Money, serviceCostPerPaxStandard: Money,
                serviceCostPerPaxPremium: Money, serviceTargetBasic: Double,
                serviceTargetStandard: Double, serviceTargetPremium: Double,
                administrationScar: Double) {
        self.driftRate = driftRate
        self.valueDriftRate = valueDriftRate
        self.initialComponent = initialComponent
        self.multiplierBase = multiplierBase
        self.multiplierSpan = multiplierSpan
        self.serviceCostPerPaxBasic = serviceCostPerPaxBasic
        self.serviceCostPerPaxStandard = serviceCostPerPaxStandard
        self.serviceCostPerPaxPremium = serviceCostPerPaxPremium
        self.serviceTargetBasic = serviceTargetBasic
        self.serviceTargetStandard = serviceTargetStandard
        self.serviceTargetPremium = serviceTargetPremium
        self.administrationScar = administrationScar
    }

    public func serviceCostPerPax(_ tier: ServiceTier) -> Money {
        switch tier {
        case .basic: serviceCostPerPaxBasic
        case .standard: serviceCostPerPaxStandard
        case .premium: serviceCostPerPaxPremium
        }
    }

    public func serviceTarget(_ tier: ServiceTier) -> Double {
        switch tier {
        case .basic: serviceTargetBasic
        case .standard: serviceTargetStandard
        case .premium: serviceTargetPremium
        }
    }

    public static let standard = ReputationTuning(
        driftRate: 0.05, valueDriftRate: 0.02, initialComponent: 0.6,
        multiplierBase: 0.8, multiplierSpan: 0.45,
        serviceCostPerPaxBasic: Money.dollars(4),
        serviceCostPerPaxStandard: Money.dollars(9),
        serviceCostPerPaxPremium: Money.dollars(18),
        serviceTargetBasic: 0.35, serviceTargetStandard: 0.60,
        serviceTargetPremium: 0.85, administrationScar: 0.85)
}
