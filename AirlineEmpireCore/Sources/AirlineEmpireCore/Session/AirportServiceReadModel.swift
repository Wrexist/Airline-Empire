/// The service catalogue and deterministic per-card quote. No UI-owned effects.
public enum AirportService: String, CaseIterable, Sendable {
    case lounge, ground
    public func level(in configuration: AirportFacilities) -> Int {
        switch self { case .lounge: configuration.lounge; case .ground: configuration.groundServices }
    }
    public func setting(_ level: Int, in configuration: AirportFacilities) -> AirportFacilities {
        var result = configuration
        switch self { case .lounge: result.lounge = level; case .ground: result.groundServices = level }
        return result
    }
    public var title: String {
        switch self { case .lounge: "Passenger lounge"; case .ground: "Ground services" }
    }
    public static func levelName(_ level: Int) -> String {
        switch level { case 0: "None"; case 1: "Standard"; default: "Premium" }
    }
}

public struct AirportServiceReadModel: Equatable, Sendable {
    public let current: Int
    public let proposed: Int
    public let installation: Money
    public let monthly: Money
    public let effect: String
    public let scope: String
    public init(service: AirportService, installed: AirportFacilities,
                proposed: AirportFacilities, tuning: AirportFacilityTuning) {
        current = service.level(in: installed)
        self.proposed = service.level(in: proposed)
        let next = service.setting(self.proposed, in: AirportFacilities())
        let old = service.setting(current, in: AirportFacilities())
        installation = next.installationCost(from: old, tuning: tuning)
        monthly = next.monthlyCost(tuning: tuning)
        switch service {
        case .lounge:
            effect = "Up to +\(Int((Double(self.proposed) * tuning.loungeComfortPerLevel * 100).rounded())) comfort points here"
            scope = "Route comfort averages both airports and shares the aircraft comfort cap."
        case .ground:
            effect = "\(Int(((1 - next.technicalDisruptionMultiplier(tuning: tuning)) * 100).rounded()))% lower technical disruption risk"
            scope = "Your departures here. Weather risk and turnaround time are unchanged."
        }
    }
}

public struct AirportServiceCommitment: Equatable, Sendable {
    public let airport: AirportCode
    public let monthly: Money
}

extension Airline {
    public func airportServiceCommitments(tuning: AirportFacilityTuning) -> [AirportServiceCommitment] {
        (airportFacilities ?? [:]).keys.sorted().compactMap { code in
            let cost = facilities(at: code).monthlyCost(tuning: tuning)
            return cost > .zero ? AirportServiceCommitment(airport: code, monthly: cost) : nil
        }
    }
}
