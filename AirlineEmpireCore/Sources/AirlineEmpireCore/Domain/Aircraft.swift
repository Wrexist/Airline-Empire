import Foundation

/// A fleet aircraft: a real simulation entity with lifecycle, condition,
/// and economics (docs/AIRCRAFT.md). Static performance data lives in its
/// `AircraftTypeSpec`.
public struct Aircraft: Equatable, Codable, Sendable {
    public let id: AircraftID
    public let typeCode: AircraftTypeCode
    public var owner: AirlineID
    public var ownership: AircraftOwnership
    public var status: AircraftStatus
    /// Current (or delivery-target) airport.
    public var location: AirportCode
    /// Route the aircraft serves; nil = unassigned (Phase 6 assigns).
    public var assignedRoute: RouteID?
    /// Age in days, including age at acquisition for used airframes.
    public var ageDays: Int
    /// Physical state 0…1; decays with time and flying, restored by checks.
    public var condition: Double
    /// Lifetime flying, drives maintenance economics (accrues from Phase 6).
    public var totalFlightHours: Double

    public init(id: AircraftID, typeCode: AircraftTypeCode, owner: AirlineID,
                ownership: AircraftOwnership, status: AircraftStatus,
                location: AirportCode, assignedRoute: RouteID? = nil,
                ageDays: Int, condition: Double, totalFlightHours: Double = 0) {
        self.id = id
        self.typeCode = typeCode
        self.owner = owner
        self.ownership = ownership
        self.status = status
        self.location = location
        self.assignedRoute = assignedRoute
        self.ageDays = ageDays
        self.condition = condition
        self.totalFlightHours = totalFlightHours
    }

    public var ageYears: Double { Double(ageDays) / Double(GameCalendar.daysPerYear) }

    /// Available to be assigned to routes / scheduled to fly.
    public var isOperational: Bool {
        if case .active = status { true } else { false }
    }

    /// Dispatch reliability now: baseline eroded by wear and age, floored so
    /// no aircraft becomes unflyable garbage (recovery is designed —
    /// docs/GAME_BALANCE.md §5).
    public func currentReliability(type: AircraftTypeSpec, tuning: FleetTuning) -> Double {
        let conditionPenalty = (1 - condition) * tuning.reliabilityConditionWeight
        let agePenalty = ageYears * tuning.reliabilityAgePenaltyPerYear
        return max(tuning.reliabilityFloor, type.reliabilityBaseline - conditionPenalty - agePenalty)
    }
}

public enum AircraftOwnership: Equatable, Codable, Sendable {
    /// Book value depreciates monthly toward a residual floor.
    case owned(bookValue: Money)
    /// Fixed monthly rate billed by FleetBillingSystem; early return incurs
    /// a penalty while months remain.
    case leased(monthlyRate: Money, termMonthsRemaining: Int)

    public var isLeased: Bool {
        if case .leased = self { true } else { false }
    }
}

public enum AircraftStatus: Equatable, Codable, Sendable {
    /// New order awaiting delivery (FleetSystem delivers on the due day).
    case ordered(deliveryAt: SimTime)
    case active
    /// Grounded for a maintenance check until the given time.
    case inMaintenance(until: SimTime)
}

/// Fleet pricing/wear math — pure functions over spec + tuning so tests and
/// UI quote the exact numbers the simulation uses (explainability pillar).
public enum FleetEconomics {
    /// Market price of a used airframe of the given age/condition.
    /// Depreciates geometrically from list toward a residual floor, then
    /// adjusts for physical condition.
    public static func usedPrice(type: AircraftTypeSpec, ageYears: Double,
                                 condition: Double, tuning: FleetTuning) -> Money {
        let depreciated = depreciatedValue(type: type, ageYears: ageYears, tuning: tuning)
        let conditionFactor = tuning.usedPriceConditionFloor
            + (1 - tuning.usedPriceConditionFloor) * condition
        return Money(rounding: depreciated.asDouble * conditionFactor)
    }

    /// Straight depreciation curve (no condition adjustment): what an owned
    /// airframe's book value trends toward.
    public static func depreciatedValue(type: AircraftTypeSpec, ageYears: Double,
                                        tuning: FleetTuning) -> Money {
        let floor = type.listPrice.asDouble * tuning.residualValueFraction
        let curve = type.listPrice.asDouble
            * pow(1 - tuning.annualDepreciationRate, ageYears)
        return Money(rounding: max(floor, curve))
    }

    /// Sale proceeds: used-market price minus liquidity friction (the
    /// buy/sell spread that kills fleet-flipping — docs/GAME_BALANCE.md §7).
    public static func saleValue(type: AircraftTypeSpec, ageYears: Double,
                                 condition: Double, tuning: FleetTuning) -> Money {
        Money(rounding: usedPrice(type: type, ageYears: ageYears, condition: condition,
                                  tuning: tuning).asDouble * (1 - tuning.saleFriction))
    }

    /// Deterministic condition of a used-market airframe by age: buyers know
    /// what they get; scatter would add noise, not decisions.
    public static func usedMarketCondition(ageYears: Double, tuning: FleetTuning) -> Double {
        max(tuning.usedMarketConditionFloor,
            1.0 - ageYears * tuning.usedMarketConditionLossPerYear)
    }

    /// Cost of a maintenance check: hours-equivalent of the type's reserve
    /// rate, scaled up as the airframe ages.
    public static func maintenanceCheckCost(type: AircraftTypeSpec, ageYears: Double,
                                            tuning: FleetTuning) -> Money {
        let ageMultiplier = 1.0 + ageYears * tuning.maintenanceAgeCostGrowthPerYear
        return Money(rounding: type.maintenancePerFlightHour.asDouble
            * tuning.maintenanceCheckHoursEquivalent * ageMultiplier)
    }
}

