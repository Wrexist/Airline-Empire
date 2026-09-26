/// Airline-owned services at a station. Missing state in older saves means no investment.
public struct AirportFacilities: Equatable, Codable, Sendable {
    public var lounge: Int
    public var groundServices: Int
    public init(lounge: Int = 0, groundServices: Int = 0) {
        self.lounge = lounge; self.groundServices = groundServices
    }
    public var isValid: Bool { (0...2).contains(lounge) && (0...2).contains(groundServices) }
    public func monthlyCost(tuning: AirportFacilityTuning) -> Money {
        tuning.loungeMonthly * Int64(lounge) + tuning.groundMonthly * Int64(groundServices)
    }
    public func installationCost(from old: Self, tuning: AirportFacilityTuning) -> Money {
        tuning.loungeInstallation * Int64(max(0, lounge - old.lounge))
            + tuning.groundInstallation * Int64(max(0, groundServices - old.groundServices))
    }
    public func technicalDisruptionMultiplier(tuning: AirportFacilityTuning) -> Double {
        1 - Double(groundServices) * tuning.groundRiskReductionPerLevel
    }
}

public struct AirportFacilityChange: Equatable, Codable, Sendable {
    public let id: Int64
    public let at: SimTime
    public let airport: AirportCode
    public let previous: AirportFacilities
    public let updated: AirportFacilities
    public let cost: Money
}

extension Airline {
    public func facilities(at airport: AirportCode) -> AirportFacilities {
        airportFacilities?[airport] ?? AirportFacilities()
    }
}

public struct ConfigureAirportFacilitiesCommand: Command, Equatable {
    public static let name = "configureAirportFacilities"
    public let airline: AirlineID
    public let airport: AirportCode
    public let facilities: AirportFacilities
    public init(airline: AirlineID, airport: AirportCode, facilities: AirportFacilities) {
        self.airline = airline; self.airport = airport; self.facilities = facilities
    }
    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard let owner = state.airlines[airline], owner.status == .active, catalog.airport(airport) != nil else {
            return .init(code: "airport.unavailable", message: "Choose an available airport for an active airline.")
        }
        guard facilities.isValid else {
            return .init(code: "airport.invalidFacilities", message: "Choose a service level from 0 to 2.")
        }
        let old = owner.facilities(at: airport)
        let increasing = facilities.lounge > old.lounge || facilities.groundServices > old.groundServices
        if increasing {
            guard airport == owner.homeAirport || state.routes(of: airline).contains(where: { $0.origin == airport || $0.destination == airport }) else {
                return .init(code: "airport.noPresence", message: "Open a route here before investing in this airport.")
            }
            guard !state.world.isAirportClosed(airport, at: state.clock.now) else {
                return .init(code: "airport.closed", message: "Wait until the airport reopens before expanding services.")
            }
        }
        let cost = facilities.installationCost(from: old, tuning: catalog.tuning.airportServices)
        guard cost == .zero || state.ledger.balance(of: airline) >= cost else {
            return .init(code: "airport.insufficientFunds", message: "There is not enough cash for this airport investment.")
        }
        return nil
    }
    public func apply(state: inout GameState, context: SimContext) {
        guard var owner = state.airlines[airline] else { return }
        let old = owner.facilities(at: airport)
        guard old != facilities else { return }
        let cost = facilities.installationCost(from: old, tuning: context.catalog.tuning.airportServices)
        var stations = owner.airportFacilities ?? [:]
        stations[airport] = facilities == AirportFacilities() ? nil : facilities
        owner.airportFacilities = stations
        var history = owner.airportFacilityHistory ?? []
        history.insert(.init(id: (history.first?.id ?? 0) + 1, at: context.current, airport: airport,
            previous: old, updated: facilities, cost: cost), at: 0)
        owner.airportFacilityHistory = Array(history.prefix(100))
        state.airlines[airline] = owner
        if cost > .zero {
            state.ledger.post(airline: airline, category: .overhead, amount: -cost,
                at: context.current, memo: "\(airport.raw) facility installation")
        }
    }
}
