/// Read models for the two things the simulation knew and the player did not:
/// how close the airline is to failing, and what the macro arc is asking for
/// next (docs/UIUX_FORENSIC_AUDIT.md UI-005, UI-008).
///
/// Both are pure derivations of the snapshot. Nothing here is persisted and
/// nothing here is new state — `SolvencySystem` was already running the
/// countdown and `EraGate` was already deciding the gate; these models only
/// make what they know legible.

// MARK: - Solvency

/// How close the airline is to administration, and to the collapse after it.
///
/// `SolvencySystem` increments `daysInsolvent` every day the balance sits
/// below the overdraft floor and restructures the airline at
/// `administrationGraceDays`. Before this model existed the player's first
/// notice of any of it was a line in the feed *after* their fleet had been
/// fire-sold, which is the opposite of "every consequence is traceable"
/// (docs/GAME_DESIGN.md pillar 2).
public struct SolvencyModel: Equatable, Sendable {
    /// How alarmed the player should be, in the order a player escalates.
    public enum Stage: Int, Equatable, Sendable, Comparable {
        /// Above water, and not burning through the balance fast enough to
        /// matter yet.
        case healthy = 0
        /// Overdrawn, or burning cash fast enough that the runway is short.
        /// Nothing is happening *yet* — this is the window to act in.
        case watch
        /// Below the overdraft floor: the administration countdown is running.
        case danger

        public static func < (lhs: Stage, rhs: Stage) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let cash: Money
    /// The balance below which the countdown runs (negative).
    public let overdraftFloor: Money
    /// Consecutive days already spent below the floor.
    public let daysInsolvent: Int
    /// Days below the floor that trigger administration.
    public let graceDays: Int
    /// Days left before restructuring, or nil when the countdown is not
    /// running. `1` means the next day boundary restructures the airline;
    /// `0` means it is due at the very next daily tick.
    public let daysUntilAdministration: Int?
    /// Administrations already survived. One is the limit; the next failure
    /// is terminal (docs/GAME_DESIGN.md §5).
    public let administrationCount: Int
    /// Months of cash left at the last closed month's net burn, or nil when
    /// the last month was profitable or no month has closed. A forecast, not
    /// a promise — it assumes the coming months look like the last one.
    public let monthsOfRunway: Double?
    public let stage: Stage

    /// True when the next failure ends the game rather than restructuring it.
    public var nextFailureIsFatal: Bool { administrationCount >= 1 }
}

extension GameState {
    /// The solvency picture for an airline; nil when there is no such airline.
    public func solvencyModel(for airline: AirlineID,
                              catalog: ContentCatalog) -> SolvencyModel? {
        guard let a = airlines[airline] else { return nil }
        let tuning = catalog.tuning.finance
        let cash = ledger.balance(of: airline)
        let floor = Money(cents: tuning.overdraftFloorCents)

        let belowFloor = cash.cents < tuning.overdraftFloorCents
        let remaining = belowFloor
            ? max(0, tuning.administrationGraceDays - a.daysInsolvent)
            : nil

        // Runway is only meaningful against a month that actually lost money.
        let lastNet = finance.byAirline[airline]?.latest?.netProfit
        let runway: Double? = {
            guard let lastNet, lastNet.isNegative, cash > .zero else { return nil }
            return cash.asDouble / abs(lastNet.asDouble)
        }()

        let stage: SolvencyModel.Stage
        if belowFloor {
            stage = .danger
        } else if cash.isNegative || (runway.map { $0 < 3 } ?? false) {
            stage = .watch
        } else {
            stage = .healthy
        }

        return SolvencyModel(
            cash: cash, overdraftFloor: floor,
            daysInsolvent: a.daysInsolvent,
            graceDays: tuning.administrationGraceDays,
            daysUntilAdministration: remaining,
            administrationCount: a.administrationCount,
            monthsOfRunway: runway,
            stage: stage)
    }
}

// MARK: - Progression

/// The macro arc, told as state rather than as codes: which era, what the
/// next one asks for and how far along each requirement is, which capability
/// programs are running and when they land, and how each mission is going.
public struct ProgressionModel: Equatable, Sendable {
    public let era: Era
    /// nil at the top of the ladder.
    public let nextEra: Era?
    /// What `nextEra` demands, with current standing. Empty at the top.
    public let nextEraRequirements: [EraRequirement]

    public let capabilities: [CapabilityStatus]
    public let missions: [MissionProgress]
    public let milestones: [String]
    public let achievements: [String]

    /// 0…1 across the next era's requirements; 1 when there is no next era.
    public var nextEraProgress: Double {
        guard !nextEraRequirements.isEmpty else { return 1 }
        return nextEraRequirements.reduce(0) { $0 + $1.fraction }
            / Double(nextEraRequirements.count)
    }

    public struct CapabilityStatus: Equatable, Sendable {
        public enum State: Equatable, Sendable {
            case available(cost: Money, days: Int)
            /// `fraction` is 0…1 through the program's own duration.
            case inProgress(completesAt: SimTime, daysRemaining: Int, fraction: Double)
            case built
            /// Available, but the airline is already running its limit.
            case blockedBySlots(cost: Money, days: Int)
            /// The era gate has not opened yet. The screen used to offer a
            /// Start button here whose only possible outcome was a refusal.
            case eraLocked(unlocksAt: Era, cost: Money, days: Int)
            /// Affordable in principle, not today.
            case unaffordable(cost: Money, shortfall: Money, days: Int)
        }

        public let code: CapabilityCode
        public let state: State

        /// Whether `StartCapabilityProgramCommand` would be accepted right
        /// now. The button's enabled state, in one place.
        public var isStartable: Bool {
            if case .available = state { true } else { false }
        }
    }

    public struct MissionProgress: Equatable, Sendable {
        public let mission: Mission
        public let current: Int64
        public let target: Int64
        public let daysRemaining: Int
        public var fraction: Double {
            guard target > 0 else { return 1 }
            return min(1, max(0, Double(current) / Double(target)))
        }
    }
}

extension GameState {
    /// The player's progression picture; nil before an airline exists.
    public func progressionModel(catalog: ContentCatalog) -> ProgressionModel? {
        guard let player = playerAirline else { return nil }
        let tuning = catalog.tuning.progression
        let now = clock.now
        let next = EraGate.next(after: progression.era)
        let requirements = next.map {
            EraGate.requirements(for: $0, player: player, state: self,
                                 catalog: catalog, tuning: tuning)
        } ?? []

        // The order below mirrors StartCapabilityProgramCommand.validate, so
        // "startable" here and "accepted" there are the same question.
        let atProgramLimit = progression.activePrograms.count >= tuning.maxActivePrograms
        let cash = ledger.balance(of: player.id)
        let cost = tuning.capabilityCost
        let days = tuning.capabilityDurationDays
        let capabilities = CapabilityCode.allCases.map { code -> ProgressionModel.CapabilityStatus in
            if progression.hasCapability(code) {
                return .init(code: code, state: .built)
            }
            if let program = progression.activePrograms.first(where: { $0.code == code }) {
                let total = Double(program.completesAt.rawMinutes - program.startedAt.rawMinutes)
                let done = Double(now.rawMinutes - program.startedAt.rawMinutes)
                let fraction = total > 0 ? min(1, max(0, done / total)) : 1
                let minutesLeft = max(0, program.completesAt.rawMinutes - now.rawMinutes)
                return .init(code: code, state: .inProgress(
                    completesAt: program.completesAt,
                    daysRemaining: Int(minutesLeft / GameCalendar.minutesPerDay),
                    fraction: fraction))
            }
            if progression.era < CapabilityProgram.unlockEra {
                return .init(code: code, state: .eraLocked(
                    unlocksAt: CapabilityProgram.unlockEra, cost: cost, days: days))
            }
            if atProgramLimit {
                return .init(code: code, state: .blockedBySlots(cost: cost, days: days))
            }
            if cash < cost {
                return .init(code: code, state: .unaffordable(
                    cost: cost, shortfall: cost - cash, days: days))
            }
            return .init(code: code, state: .available(cost: cost, days: days))
        }

        let missions = progression.missions.map { mission -> ProgressionModel.MissionProgress in
            let minutesLeft = max(0, mission.deadline.rawMinutes - now.rawMinutes)
            // Measured by MissionMath, which is also what resolves the
            // mission — so the bar and the payout agree.
            return .init(mission: mission,
                         current: MissionMath.progress(of: mission, player: player,
                                                       state: self, catalog: catalog),
                         target: MissionMath.target(of: mission),
                         daysRemaining: Int(minutesLeft / GameCalendar.minutesPerDay))
        }

        return ProgressionModel(
            era: progression.era, nextEra: next, nextEraRequirements: requirements,
            capabilities: capabilities, missions: missions,
            milestones: progression.milestones,
            achievements: progression.achievements)
    }
}
