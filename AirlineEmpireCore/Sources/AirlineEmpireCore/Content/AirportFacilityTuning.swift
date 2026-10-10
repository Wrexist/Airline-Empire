/// Prices, build times and effects of the buildings an airline puts up at a
/// station (docs/HUB_PROGRESSION_PLAN.md §4). Every field after the first six
/// is optional in content, so older bundles load with the defaults.
public struct AirportFacilityTuning: Equatable, Codable, Sendable {
    /// Lounge and ground services: per level.
    public let loungeInstallation: Money
    public let groundInstallation: Money
    public let loungeMonthly: Money
    public let groundMonthly: Money
    public let loungeComfortPerLevel: Double
    public let groundRiskReductionPerLevel: Double
    /// Game days to build each level.
    public let loungeBuildDays: [Int]
    public let groundBuildDays: [Int]

    /// Maintenance hangar, by level: price of the level, upkeep at it, days to
    /// build it, check length for aircraft flying through, check cost factor.
    public let hangarInstallation: [Money]
    public let hangarMonthly: [Money]
    public let hangarBuildDays: [Int]
    public let hangarCheckDays: [Int]
    public let hangarCheckCostFactor: [Double]

    /// Crew base: the operating day on routes from it starts this much
    /// earlier and runs this much longer, and crews there cost less.
    public let crewBaseInstallation: Money
    public let crewBaseMonthly: Money
    public let crewBaseBuildDays: Int
    public let crewBaseEarlierStartMinutes: Int64
    public let crewBaseExtraMinutes: Int64
    public let crewBaseCrewCostFactor: Double

    // Priced for an 18–36 month payback at a typical hub (tasks/DECISIONS.md
    // D-017): the lounge at about eight routes, the hangar at about ten
    // aircraft flying through, the crew base on crew savings alone.
    public init(loungeInstallation: Money = .dollars(750_000), groundInstallation: Money = .dollars(500_000),
                loungeMonthly: Money = .dollars(15_000), groundMonthly: Money = .dollars(10_000),
                loungeComfortPerLevel: Double = 0.04, groundRiskReductionPerLevel: Double = 0.10,
                loungeBuildDays: [Int] = [7, 14], groundBuildDays: [Int] = [7, 14],
                hangarInstallation: [Money] = [.dollars(2_500_000), .dollars(2_500_000)],
                hangarMonthly: [Money] = [.dollars(40_000), .dollars(70_000)],
                hangarBuildDays: [Int] = [30, 60], hangarCheckDays: [Int] = [2, 1],
                hangarCheckCostFactor: [Double] = [0.8, 0.65],
                crewBaseInstallation: Money = .dollars(2_500_000), crewBaseMonthly: Money = .dollars(60_000),
                crewBaseBuildDays: Int = 21, crewBaseEarlierStartMinutes: Int64 = 60,
                crewBaseExtraMinutes: Int64 = 120, crewBaseCrewCostFactor: Double = 0.9) {
        self.loungeInstallation = loungeInstallation; self.groundInstallation = groundInstallation
        self.loungeMonthly = loungeMonthly; self.groundMonthly = groundMonthly
        self.loungeComfortPerLevel = loungeComfortPerLevel
        self.groundRiskReductionPerLevel = groundRiskReductionPerLevel
        self.loungeBuildDays = loungeBuildDays; self.groundBuildDays = groundBuildDays
        self.hangarInstallation = hangarInstallation; self.hangarMonthly = hangarMonthly
        self.hangarBuildDays = hangarBuildDays; self.hangarCheckDays = hangarCheckDays
        self.hangarCheckCostFactor = hangarCheckCostFactor
        self.crewBaseInstallation = crewBaseInstallation; self.crewBaseMonthly = crewBaseMonthly
        self.crewBaseBuildDays = crewBaseBuildDays
        self.crewBaseEarlierStartMinutes = crewBaseEarlierStartMinutes
        self.crewBaseExtraMinutes = crewBaseExtraMinutes
        self.crewBaseCrewCostFactor = crewBaseCrewCostFactor
    }
    public static let standard = Self()

    private enum CodingKeys: String, CodingKey {
        case loungeInstallation, groundInstallation, loungeMonthly, groundMonthly
        case loungeComfortPerLevel, groundRiskReductionPerLevel, loungeBuildDays, groundBuildDays
        case hangarInstallation, hangarMonthly, hangarBuildDays, hangarCheckDays, hangarCheckCostFactor
        case crewBaseInstallation, crewBaseMonthly, crewBaseBuildDays, crewBaseEarlierStartMinutes
        case crewBaseExtraMinutes, crewBaseCrewCostFactor
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.standard
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try c.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        self.init(
            loungeInstallation: try value(.loungeInstallation, d.loungeInstallation),
            groundInstallation: try value(.groundInstallation, d.groundInstallation),
            loungeMonthly: try value(.loungeMonthly, d.loungeMonthly),
            groundMonthly: try value(.groundMonthly, d.groundMonthly),
            loungeComfortPerLevel: try value(.loungeComfortPerLevel, d.loungeComfortPerLevel),
            groundRiskReductionPerLevel: try value(.groundRiskReductionPerLevel, d.groundRiskReductionPerLevel),
            loungeBuildDays: try value(.loungeBuildDays, d.loungeBuildDays),
            groundBuildDays: try value(.groundBuildDays, d.groundBuildDays),
            hangarInstallation: try value(.hangarInstallation, d.hangarInstallation),
            hangarMonthly: try value(.hangarMonthly, d.hangarMonthly),
            hangarBuildDays: try value(.hangarBuildDays, d.hangarBuildDays),
            hangarCheckDays: try value(.hangarCheckDays, d.hangarCheckDays),
            hangarCheckCostFactor: try value(.hangarCheckCostFactor, d.hangarCheckCostFactor),
            crewBaseInstallation: try value(.crewBaseInstallation, d.crewBaseInstallation),
            crewBaseMonthly: try value(.crewBaseMonthly, d.crewBaseMonthly),
            crewBaseBuildDays: try value(.crewBaseBuildDays, d.crewBaseBuildDays),
            crewBaseEarlierStartMinutes: try value(.crewBaseEarlierStartMinutes, d.crewBaseEarlierStartMinutes),
            crewBaseExtraMinutes: try value(.crewBaseExtraMinutes, d.crewBaseExtraMinutes),
            crewBaseCrewCostFactor: try value(.crewBaseCrewCostFactor, d.crewBaseCrewCostFactor))
    }

    public var isValid: Bool {
        let money = [loungeInstallation, groundInstallation, loungeMonthly, groundMonthly,
                     crewBaseInstallation, crewBaseMonthly] + hangarInstallation + hangarMonthly
        let days = loungeBuildDays + groundBuildDays + hangarBuildDays + [crewBaseBuildDays]
        return money.allSatisfy { $0.cents >= 0 && $0.cents <= 1_000_000_000_000 }
            && (0...0.25).contains(loungeComfortPerLevel) && (0...0.4).contains(groundRiskReductionPerLevel)
            && loungeBuildDays.count == 2 && groundBuildDays.count == 2
            && [hangarInstallation.count, hangarMonthly.count, hangarBuildDays.count,
                hangarCheckDays.count, hangarCheckCostFactor.count].allSatisfy { $0 == 2 }
            && days.allSatisfy { (0...730).contains($0) }
            && hangarCheckDays.allSatisfy { (1...30).contains($0) }
            && hangarCheckCostFactor.allSatisfy { (0.1...1).contains($0) }
            && (0...180).contains(crewBaseEarlierStartMinutes) && (0...360).contains(crewBaseExtraMinutes)
            && crewBaseExtraMinutes >= crewBaseEarlierStartMinutes
            && (0.1...1).contains(crewBaseCrewCostFactor)
    }
}
