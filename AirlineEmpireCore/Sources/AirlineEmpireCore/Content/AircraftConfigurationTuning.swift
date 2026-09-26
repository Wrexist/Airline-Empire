/// Content-owned aircraft product economics. Defaults mirror tuning.json,
/// following the other tuning types and supporting older content bundles.
public struct AircraftConfigurationTuning: Equatable, Codable, Sendable {
    public let firstYield: Double
    public let businessYield: Double
    public let premiumEconomyYield: Double
    public let economyYield: Double
    public let premiumComfortWeight: Double
    public let comfortPerUpgradeLevel: Double
    public let seatChangeCost: Money
    public let equipmentPerSeatPerLevel: Money
    public let wifiPerPassengerPerLevel: Money
    public let diningPerPassengerPerLevel: Money
    public let seatsPerPassengerPerLevel: Money
    public let entertainmentPerPassengerPerLevel: Money

    public init(firstYield: Double = 3.2, businessYield: Double = 1.85,
                premiumEconomyYield: Double = 1.35, economyYield: Double = 1,
                premiumComfortWeight: Double = 0.22, comfortPerUpgradeLevel: Double = 0.025,
                seatChangeCost: Money = .dollars(250), equipmentPerSeatPerLevel: Money = .dollars(120),
                wifiPerPassengerPerLevel: Money = Money(cents: 75),
                diningPerPassengerPerLevel: Money = .dollars(2),
                seatsPerPassengerPerLevel: Money = Money(cents: 50),
                entertainmentPerPassengerPerLevel: Money = Money(cents: 75)) {
        self.firstYield = firstYield
        self.businessYield = businessYield
        self.premiumEconomyYield = premiumEconomyYield
        self.economyYield = economyYield
        self.premiumComfortWeight = premiumComfortWeight
        self.comfortPerUpgradeLevel = comfortPerUpgradeLevel
        self.seatChangeCost = seatChangeCost
        self.equipmentPerSeatPerLevel = equipmentPerSeatPerLevel
        self.wifiPerPassengerPerLevel = wifiPerPassengerPerLevel
        self.diningPerPassengerPerLevel = diningPerPassengerPerLevel
        self.seatsPerPassengerPerLevel = seatsPerPassengerPerLevel
        self.entertainmentPerPassengerPerLevel = entertainmentPerPassengerPerLevel
    }

    public var isValid: Bool {
        let yields = [firstYield, businessYield, premiumEconomyYield, economyYield]
        let costs = [seatChangeCost, equipmentPerSeatPerLevel, wifiPerPassengerPerLevel,
                     diningPerPassengerPerLevel, seatsPerPassengerPerLevel, entertainmentPerPassengerPerLevel]
        return yields.allSatisfy { $0.isFinite && $0 > 0 && $0 <= 100 }
            && (0...1).contains(premiumComfortWeight) && (0...1).contains(comfortPerUpgradeLevel)
            && costs.allSatisfy { $0.cents >= 0 && $0.cents <= Int64.max / 100_000 }
    }

    public static let standard = Self()
    public func yield(for cabin: CabinClass) -> Double {
        switch cabin {
        case .first: firstYield
        case .business: businessYield
        case .premiumEconomy: premiumEconomyYield
        case .economy: economyYield
        }
    }
}
