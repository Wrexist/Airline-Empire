import Foundation

public enum CabinClass: String, Codable, CaseIterable, Sendable {
    case first, business, premiumEconomy, economy

    public var title: String {
        switch self {
        case .first: "First Class"
        case .business: "Business Class"
        case .premiumEconomy: "Premium Economy"
        case .economy: "Economy Class"
        }
    }
    /// Integer economy-seat equivalents keep every layout exactly packable.
    public var space: Int {
        switch self { case .first: 4; case .business: 2; case .premiumEconomy: 2; case .economy: 1 }
    }
    public var yield: Double {
        switch self { case .first: 3.2; case .business: 1.85; case .premiumEconomy: 1.35; case .economy: 1 }
    }
}

public enum AircraftUpgrade: String, Codable, CaseIterable, Sendable {
    case wifi, dining, seats, entertainment
    public var title: String {
        switch self { case .wifi: "Wi-Fi"; case .dining: "Food & Beverage"; case .seats: "Seat Comfort"; case .entertainment: "Entertainment" }
    }
    public var levels: [String] {
        switch self {
        case .wifi: ["None", "Basic", "Full"]
        case .dining: ["Basic", "Standard", "Premium"]
        case .seats: ["Standard", "Improved", "Premium"]
        case .entertainment: ["None", "Screens", "Streaming"]
        }
    }
    public var explanation: String {
        switch self {
        case .wifi: "Help passengers stay connected in the air."
        case .dining: "Make the journey memorable with better onboard dining."
        case .seats: "Invest in comfort passengers feel on every flight."
        case .entertainment: "Give passengers more ways to enjoy the journey."
        }
    }
}

public struct AircraftConfiguration: Equatable, Codable, Sendable {
    public var first: Int
    public var business: Int
    public var premiumEconomy: Int
    public var economy: Int
    public var wifi: Int
    public var dining: Int
    public var seats: Int
    public var entertainment: Int

    public init(capacity: Int) {
        first = 0; business = 0; premiumEconomy = 0; economy = capacity
        wifi = 0; dining = 0; seats = 0; entertainment = 0
    }
    public subscript(cabin: CabinClass) -> Int {
        get { switch cabin { case .first: first; case .business: business; case .premiumEconomy: premiumEconomy; case .economy: economy } }
        set { switch cabin { case .first: first = newValue; case .business: business = newValue; case .premiumEconomy: premiumEconomy = newValue; case .economy: economy = newValue } }
    }
    public subscript(upgrade: AircraftUpgrade) -> Int {
        get { switch upgrade { case .wifi: wifi; case .dining: dining; case .seats: seats; case .entertainment: entertainment } }
        set { switch upgrade { case .wifi: wifi = newValue; case .dining: dining = newValue; case .seats: seats = newValue; case .entertainment: entertainment = newValue } }
    }
    public var totalSeats: Int { CabinClass.allCases.reduce(0) { $0 + self[$1] } }
    public var usedSpace: Int { CabinClass.allCases.reduce(0) { $0 + self[$1] * $1.space } }
    public func isValid(capacity: Int) -> Bool {
        // Bound before arithmetic so malformed commands cannot overflow.
        guard capacity > 0, capacity <= 10_000,
              CabinClass.allCases.allSatisfy({ (0...capacity).contains(self[$0]) }),
              AircraftUpgrade.allCases.allSatisfy({ (0...2).contains(self[$0]) }) else { return false }
        return totalSeats > 0 && usedSpace == capacity
    }
    public mutating func setSeats(_ count: Int, in cabin: CabinClass, capacity: Int) {
        guard cabin != .economy, isValid(capacity: capacity) else { return }
        let available = economy + self[cabin] * cabin.space
        self[cabin] = min(max(0, count), available / cabin.space)
        economy = available - self[cabin] * cabin.space
    }
    public var yieldMultiplier: Double {
        guard totalSeats > 0 else { return 1 }
        return CabinClass.allCases.reduce(0.0) { $0 + Double(self[$1]) * $1.yield } / Double(totalSeats)
    }
    public var comfortBonus: Double {
        let premium = Double(first + business + premiumEconomy) / Double(max(1, totalSeats))
        return premium * 0.22 + Double(wifi + dining + seats + entertainment) * 0.025
    }
    /// Recurring upgrades are billed per boarded passenger, alongside service tier.
    public var serviceCostPerPassenger: Money {
        Money(rounding: Double(wifi) * 0.75 + Double(dining) * 2 + Double(seats) * 0.5 + Double(entertainment) * 0.75)
    }
    public func installationCost(from old: Self, capacity: Int) -> Money {
        let changedSeats = CabinClass.allCases.reduce(0) { $0 + abs(self[$1] - old[$1]) }
        let equipment = AircraftUpgrade.allCases.reduce(0) { $0 + max(0, self[$1] - old[$1]) }
        return Money.dollars(Int64(changedSeats * 250 + equipment * capacity * 120))
    }
}

public struct AircraftConfigurationChange: Equatable, Codable, Sendable {
    public let id: Int64
    public let at: SimTime
    public let configuration: AircraftConfiguration
    public let cost: Money
}

extension Aircraft {
    public func cabin(for spec: AircraftTypeSpec) -> AircraftConfiguration {
        guard let configuration, configuration.isValid(capacity: spec.seats) else {
            return AircraftConfiguration(capacity: spec.seats)
        }
        return configuration
    }
    public func passengerComfort(for spec: AircraftTypeSpec) -> Double {
        min(1, spec.comfortBaseline + cabin(for: spec).comfortBonus)
    }
}

public struct ConfigureAircraftCommand: Command, Equatable {
    public static let name = "configureAircraft"
    public let airline: AirlineID
    public let aircraftID: AircraftID
    public let configuration: AircraftConfiguration
    public init(airline: AirlineID, aircraftID: AircraftID, configuration: AircraftConfiguration) {
        self.airline = airline; self.aircraftID = aircraftID; self.configuration = configuration
    }
    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard let aircraft = state.aircraft[aircraftID], aircraft.owner == airline,
              let spec = catalog.aircraftType(aircraft.typeCode) else {
            return .init(code: "aircraft.notOwned", message: "Choose an aircraft in your fleet.")
        }
        guard aircraft.isReadyToFly else {
            return .init(code: "aircraft.notReady", message: "Wait until this aircraft is on the ground and available before refitting.")
        }
        guard configuration.isValid(capacity: spec.seats) else {
            return .init(code: "aircraft.invalidCabin", message: "The cabin must use exactly the aircraft's available space.")
        }
        let cost = configuration.installationCost(from: aircraft.cabin(for: spec), capacity: spec.seats)
        guard state.ledger.balance(of: airline) >= cost else {
            return .init(code: "aircraft.refitFunds", message: "There is not enough cash for this refit.")
        }
        return nil
    }
    public func apply(state: inout GameState, context: SimContext) {
        guard var aircraft = state.aircraft[aircraftID], let spec = context.catalog.aircraftType(aircraft.typeCode) else { return }
        let old = aircraft.cabin(for: spec)
        guard old != configuration else { return }
        let cost = configuration.installationCost(from: old, capacity: spec.seats)
        aircraft.configuration = configuration
        var history = aircraft.configurationHistory ?? []
        history.append(.init(id: (history.last?.id ?? 0) + 1, at: context.current, configuration: configuration, cost: cost))
        aircraft.configurationHistory = Array(history.suffix(50))
        state.aircraft[aircraftID] = aircraft
        state.ledger.post(airline: airline, category: .maintenance, amount: -cost,
                          at: context.current, memo: "Cabin refit \(aircraftID)")
    }
}
