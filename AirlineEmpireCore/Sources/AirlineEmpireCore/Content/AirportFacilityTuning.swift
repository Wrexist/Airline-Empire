public struct AirportFacilityTuning: Equatable, Codable, Sendable {
    public let loungeInstallation: Money
    public let groundInstallation: Money
    public let loungeMonthly: Money
    public let groundMonthly: Money
    public let loungeComfortPerLevel: Double
    public let groundRiskReductionPerLevel: Double
    public init(loungeInstallation: Money = .dollars(150_000), groundInstallation: Money = .dollars(100_000),
                loungeMonthly: Money = .dollars(15_000), groundMonthly: Money = .dollars(10_000),
                loungeComfortPerLevel: Double = 0.04, groundRiskReductionPerLevel: Double = 0.10) {
        self.loungeInstallation = loungeInstallation; self.groundInstallation = groundInstallation
        self.loungeMonthly = loungeMonthly; self.groundMonthly = groundMonthly
        self.loungeComfortPerLevel = loungeComfortPerLevel
        self.groundRiskReductionPerLevel = groundRiskReductionPerLevel
    }
    public static let standard = Self()
    public var isValid: Bool {
        [loungeInstallation, groundInstallation, loungeMonthly, groundMonthly].allSatisfy { $0.cents >= 0 && $0.cents <= 1_000_000_000_000 }
            && (0...0.25).contains(loungeComfortPerLevel) && (0...0.4).contains(groundRiskReductionPerLevel)
    }
}
