/// Player progression (docs/PROGRESSION.md): eras, milestones, achievements,
/// capability programs, missions. Progression is capability and scale, not
/// numbers — every unlock changes what decisions exist.
public struct ProgressionState: Equatable, Codable, Sendable {
    public var era: Era
    /// Codes in the order reached (append-only).
    public var milestones: [String]
    public var achievements: [String]
    public var counters: ProgressionCounters
    public var activePrograms: [CapabilityProgram]
    /// Completed capability codes (raw values), append-only.
    public var completedPrograms: [String]
    public var missions: [Mission]
    public var nextMissionID: Int64
    /// Consecutive days with value perception above the legend bar.
    public var valueStreakDays: Int
    /// Terminal: the player's airline collapsed for good.
    public var gameOver: Bool

    public init() {
        era = .startup
        milestones = []
        achievements = []
        counters = ProgressionCounters()
        activePrograms = []
        completedPrograms = []
        missions = []
        nextMissionID = 1
        valueStreakDays = 0
        gameOver = false
    }

    public func hasCapability(_ code: CapabilityCode) -> Bool {
        completedPrograms.contains(code.rawValue)
    }

    public func hasMilestone(_ code: String) -> Bool {
        milestones.contains(code)
    }
}

public struct ProgressionCounters: Equatable, Codable, Sendable {
    public var passengersCarried: Int64
    public var flightsCompleted: Int64
    public var loansTaken: Int64

    public init(passengersCarried: Int64 = 0, flightsCompleted: Int64 = 0,
                loansTaken: Int64 = 0) {
        self.passengersCarried = passengersCarried
        self.flightsCompleted = flightsCompleted
        self.loansTaken = loansTaken
    }
}

/// The macro arc (docs/PROGRESSION.md §2). Gates check demonstrated
/// competence, not raw money.
public enum Era: Int, Codable, Sendable, CaseIterable, Comparable {
    case startup = 0
    case regional
    case national
    case international
    case empire

    public static func < (lhs: Era, rhs: Era) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Aircraft classes the PLAYER may acquire in this era (depth arrives
    /// gradually; AI carriers are established and exempt).
    public var allowedCategories: [AircraftCategory] {
        switch self {
        case .startup: [.turboprop, .regionalJet, .narrowbody]
        case .regional: [.turboprop, .regionalJet, .narrowbody, .largeNarrowbody]
        case .national: [.turboprop, .regionalJet, .narrowbody, .largeNarrowbody, .widebody]
        case .international, .empire: AircraftCategory.allCases
        }
    }
}

/// Rule-changing long-term investments (docs/PROGRESSION.md §4).
public enum CapabilityCode: String, Codable, Sendable, CaseIterable {
    /// Turnarounds 15% faster → more rotations fit in a day.
    case efficientTurnarounds
    /// Fuel bills capped near the base price: pay min(spot, 1.05 × base).
    case fuelHedging
    /// Disruption recovery: dispatch disruption probability × 0.8.
    case networkOpsCenter
    /// Ground product: service reputation target +0.08.
    case groundExperience
}

public struct CapabilityProgram: Equatable, Codable, Sendable {
    /// Capability programs open in the National era
    /// (docs/PROGRESSION.md §4). Named here rather than written into
    /// `StartCapabilityProgramCommand.validate` alone, so the progression
    /// screen can show "opens in the National era" instead of offering a
    /// button whose only outcome is a refusal.
    public static let unlockEra: Era = .national

    public let code: CapabilityCode
    public let startedAt: SimTime
    public let completesAt: SimTime
    public let cost: Money

    public init(code: CapabilityCode, startedAt: SimTime, completesAt: SimTime,
                cost: Money) {
        self.code = code
        self.startedAt = startedAt
        self.completesAt = completesAt
        self.cost = cost
    }
}

/// A world-generated optional objective (docs/PROGRESSION.md §3): an offer,
/// never a chore — ignoring it costs nothing.
public struct Mission: Equatable, Codable, Sendable {
    public let id: Int64
    /// World event that spawned it (no duplicates per event).
    public let sourceEventID: Int64
    public let kind: MissionKind
    public let deadline: SimTime
    public let reward: Money
    /// Progress baseline captured at offer time.
    public let baseline: Int64

    public init(id: Int64, sourceEventID: Int64, kind: MissionKind,
                deadline: SimTime, reward: Money, baseline: Int64) {
        self.id = id
        self.sourceEventID = sourceEventID
        self.kind = kind
        self.deadline = deadline
        self.reward = reward
        self.baseline = baseline
    }
}

public enum MissionKind: Equatable, Codable, Sendable {
    /// Carry `targetPassengers` on routes serving the boom region before
    /// the deadline.
    case boomRush(region: WorldRegion, targetPassengers: Int64)
}

public struct ProgressionTuning: Equatable, Codable, Sendable {
    public let capabilityCost: Money
    public let capabilityDurationDays: Int
    public let maxActivePrograms: Int
    /// Era gate thresholds.
    public let regionalProfitableRoutes: Int
    public let nationalDestinations: Int
    public let nationalReputationFloor: Double
    public let internationalFleet: Int
    public let empireDestinations: Int
    public let empireFleet: Int
    /// Achievements.
    public let valueLegendThreshold: Double
    public let valueLegendDays: Int
    public let weatherProofFlights: Int64
    public let weatherProofCompletionRate: Double
    /// Missions.
    public let boomRushTargetFactor: Double
    public let boomRushRewardPerPax: Money
    /// The least a completed mission can pay. Per-pax rewards scale with the
    /// player's capacity in the boom's region, and an *unserved* region
    /// bottoms out at the 500-passenger floor target — $20k, measured against
    /// $1.8M/$5.4M months in the AE-035 campaign. The mission asking for the
    /// biggest change (enter a new region) paid the least; the floor makes
    /// the invitation worth answering without letting big-capacity booms
    /// swamp a month.
    public let boomRushRewardFloor: Money

    public init(capabilityCost: Money, capabilityDurationDays: Int,
                maxActivePrograms: Int, regionalProfitableRoutes: Int,
                nationalDestinations: Int, nationalReputationFloor: Double,
                internationalFleet: Int, empireDestinations: Int, empireFleet: Int,
                valueLegendThreshold: Double, valueLegendDays: Int,
                weatherProofFlights: Int64, weatherProofCompletionRate: Double,
                boomRushTargetFactor: Double, boomRushRewardPerPax: Money,
                boomRushRewardFloor: Money = Money.dollars(250_000)) {
        self.capabilityCost = capabilityCost
        self.capabilityDurationDays = capabilityDurationDays
        self.maxActivePrograms = maxActivePrograms
        self.regionalProfitableRoutes = regionalProfitableRoutes
        self.nationalDestinations = nationalDestinations
        self.nationalReputationFloor = nationalReputationFloor
        self.internationalFleet = internationalFleet
        self.empireDestinations = empireDestinations
        self.empireFleet = empireFleet
        self.valueLegendThreshold = valueLegendThreshold
        self.valueLegendDays = valueLegendDays
        self.weatherProofFlights = weatherProofFlights
        self.weatherProofCompletionRate = weatherProofCompletionRate
        self.boomRushTargetFactor = boomRushTargetFactor
        self.boomRushRewardPerPax = boomRushRewardPerPax
        self.boomRushRewardFloor = boomRushRewardFloor
    }

    public static let standard = ProgressionTuning(
        capabilityCost: Money.dollars(12_000_000), capabilityDurationDays: 90,
        maxActivePrograms: 2, regionalProfitableRoutes: 3,
        nationalDestinations: 8, nationalReputationFloor: 0.55,
        internationalFleet: 8, empireDestinations: 20, empireFleet: 20,
        valueLegendThreshold: 0.8, valueLegendDays: 90,
        weatherProofFlights: 500, weatherProofCompletionRate: 0.97,
        boomRushTargetFactor: 0.6, boomRushRewardPerPax: Money.dollars(40),
        boomRushRewardFloor: Money.dollars(250_000))
}

extension GameState {
    public var playerAirline: Airline? {
        airlines.values.first { $0.kind == .player }
    }

    public func playerHasCapability(_ code: CapabilityCode) -> Bool {
        progression.hasCapability(code)
    }

    public func isPlayer(_ airline: AirlineID) -> Bool {
        airlines[airline]?.kind == .player
    }
}
