public struct AirportServiceReadModel: Equatable, Sendable {
    public let current: Int
    public let proposed: Int
    public let installation: Money
    public let monthly: Money
    public let effect: String
    public let scope: String
    /// Game days until the proposed level opens; 0 when nothing is built.
    public let buildDays: Int
    public init(service: AirportService, installed: AirportFacilities,
                proposed: AirportFacilities, tuning: AirportFacilityTuning, ops: OpsTuning = .standard) {
        current = service.level(in: installed)
        self.proposed = service.level(in: proposed)
        installation = service.installation(from: current, to: self.proposed, tuning: tuning)
        monthly = service.monthly(atLevel: self.proposed, tuning: tuning)
        buildDays = service.buildDays(from: current, to: self.proposed, tuning: tuning)
        (effect, scope) = Self.describe(service, level: self.proposed, tuning: tuning, ops: ops)
    }

    /// What a building does at a level, and where it applies.
    public static func describe(_ service: AirportService, level: Int, tuning: AirportFacilityTuning,
                                ops: OpsTuning = .standard) -> (effect: String, scope: String) {
        switch service {
        case .lounge:
            return ("Up to +\(Int((Double(level) * tuning.loungeComfortPerLevel * 100).rounded())) comfort points here",
                    "Route comfort averages both airports and shares the aircraft comfort cap.")
        case .ground:
            let cut = Int((Double(level) * tuning.groundRiskReductionPerLevel * 100).rounded())
            return ("\(cut)% lower technical disruption risk",
                    "Your departures here. Weather risk and turnaround time are unchanged.")
        case .hangar:
            guard level > 0 else { return ("Checks take 3 days, wherever the aircraft is", "Aircraft on your routes through this airport.") }
            let days = tuning.hangarCheckDays[safe: level - 1] ?? 3
            let factor = tuning.hangarCheckCostFactor[safe: level - 1] ?? 1
            let saving = Int(((1 - factor) * 100).rounded())
            return ("Checks take \(days) day\(days == 1 ? "" : "s")\(saving > 0 ? " and cost \(saving)% less" : "")",
                    "Aircraft on your routes through this airport.")
        case .crewBase:
            let standard = OperatingWindow.standard(ops)
            guard level > 0 else {
                return ("Operating day \(clock(standard.startMinute))–\(clock(standard.endMinute))", "Routes from this airport.")
            }
            let window = OperatingWindow.withCrewBase(ops, tuning: tuning)
            let start = window.startMinute, end = window.endMinute
            let saving = Int(((1 - tuning.crewBaseCrewCostFactor) * 100).rounded())
            return ("Operating day \(clock(start))–\(clock(end)), crews \(saving)% cheaper",
                    "Routes from this airport: more rotations fit in a day.")
        }
    }

    private static func clock(_ minutes: Int64) -> String {
        let m = minutes % (24 * 60)
        let h = m / 60, mm = m % 60
        return (h < 10 ? "0" : "") + "\(h):" + (mm < 10 ? "0" : "") + "\(mm)"
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
