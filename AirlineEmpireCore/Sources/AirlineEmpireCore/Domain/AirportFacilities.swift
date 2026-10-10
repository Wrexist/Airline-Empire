/// Airline-owned services at a station. Missing state in older saves means no investment.
public struct AirportFacilities: Equatable, Codable, Sendable {
    public var lounge: Int
    public var groundServices: Int
    /// Maintenance hangar, 0–2 (Regional era): checks for aircraft flying
    /// through here are shorter, and cheaper at the top level.
    public var hangar: Int
    /// Crew base, 0–1 (Regional era): a longer operating day and cheaper crews
    /// on routes from here.
    public var crewBase: Int

    public init(lounge: Int = 0, groundServices: Int = 0, hangar: Int = 0, crewBase: Int = 0) {
        self.lounge = lounge; self.groundServices = groundServices
        self.hangar = hangar; self.crewBase = crewBase
    }

    private enum CodingKeys: String, CodingKey { case lounge, groundServices, hangar, crewBase }

    // Saves from before the hangar and crew base have neither.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lounge = try c.decode(Int.self, forKey: .lounge)
        groundServices = try c.decode(Int.self, forKey: .groundServices)
        hangar = try c.decodeIfPresent(Int.self, forKey: .hangar) ?? 0
        crewBase = try c.decodeIfPresent(Int.self, forKey: .crewBase) ?? 0
    }

    public var isValid: Bool {
        AirportService.allCases.allSatisfy { (0...$0.maxLevel).contains($0.level(in: self)) }
    }
    public var isEmpty: Bool { self == AirportFacilities() }
    /// How many buildings stand here, whatever their level.
    public var buildingCount: Int {
        AirportService.allCases.filter { $0.level(in: self) > 0 }.count
    }
    public func monthlyCost(tuning: AirportFacilityTuning) -> Money {
        AirportService.allCases.reduce(Money.zero) { $0 + $1.monthly(atLevel: $1.level(in: self), tuning: tuning) }
    }
    public func installationCost(from old: Self, tuning: AirportFacilityTuning) -> Money {
        AirportService.allCases.reduce(Money.zero) {
            $0 + $1.installation(from: $1.level(in: old), to: $1.level(in: self), tuning: tuning)
        }
    }
    public func technicalDisruptionMultiplier(tuning: AirportFacilityTuning) -> Double {
        1 - Double(groundServices) * tuning.groundRiskReductionPerLevel
    }
}

/// The buildings an airline can put up at a station, and what each level
/// costs, takes and needs.
public enum AirportService: String, CaseIterable, Codable, Sendable {
    case lounge, ground, hangar, crewBase

    public func level(in configuration: AirportFacilities) -> Int {
        switch self {
        case .lounge: configuration.lounge
        case .ground: configuration.groundServices
        case .hangar: configuration.hangar
        case .crewBase: configuration.crewBase
        }
    }
    public func setting(_ level: Int, in configuration: AirportFacilities) -> AirportFacilities {
        var result = configuration
        switch self {
        case .lounge: result.lounge = level
        case .ground: result.groundServices = level
        case .hangar: result.hangar = level
        case .crewBase: result.crewBase = level
        }
        return result
    }
    public var title: String {
        switch self {
        case .lounge: "Passenger lounge"
        case .ground: "Ground services"
        case .hangar: "Maintenance hangar"
        case .crewBase: "Crew base"
        }
    }
    public var maxLevel: Int {
        switch self {
        case .lounge, .ground, .hangar: 2
        case .crewBase: 1
        }
    }
    /// The era a player needs before ordering the first level. Rivals are
    /// established carriers and exempt, as with aircraft classes.
    public var unlockEra: Era {
        switch self {
        case .lounge, .ground: .startup
        case .hangar, .crewBase: .regional
        }
    }
    public static func levelName(_ level: Int) -> String {
        switch level { case 0: "None"; case 1: "Standard"; default: "Premium" }
    }
    /// Level names for the building itself.
    public func levelName(_ level: Int) -> String {
        switch (self, level) {
        case (_, 0): "None"
        case (.crewBase, _): "Open"
        case (.hangar, 1): "Line maintenance"
        case (.hangar, _): "Heavy maintenance"
        default: Self.levelName(level)
        }
    }

    /// Up-front price of building `to` from `from`; nothing when scaling back.
    public func installation(from: Int, to: Int, tuning: AirportFacilityTuning) -> Money {
        guard to > from else { return .zero }
        return (from + 1...to).reduce(Money.zero) { $0 + installation(level: $1, tuning: tuning) }
    }
    /// The price of one level, built on the one below.
    public func installation(level: Int, tuning: AirportFacilityTuning) -> Money {
        guard level > 0 else { return .zero }
        switch self {
        case .lounge: return tuning.loungeInstallation
        case .ground: return tuning.groundInstallation
        case .hangar: return tuning.hangarInstallation[safe: level - 1] ?? .zero
        case .crewBase: return level == 1 ? tuning.crewBaseInstallation : .zero
        }
    }
    /// Upkeep a month with the building at `level`.
    public func monthly(atLevel level: Int, tuning: AirportFacilityTuning) -> Money {
        guard level > 0 else { return .zero }
        switch self {
        case .lounge: return tuning.loungeMonthly * Int64(level)
        case .ground: return tuning.groundMonthly * Int64(level)
        case .hangar: return tuning.hangarMonthly[safe: level - 1] ?? .zero
        case .crewBase: return tuning.crewBaseMonthly
        }
    }
    /// Game days to build `to` from `from`.
    public func buildDays(from: Int, to: Int, tuning: AirportFacilityTuning) -> Int {
        guard to > from else { return 0 }
        let table: [Int]
        switch self {
        case .lounge: table = tuning.loungeBuildDays
        case .ground: table = tuning.groundBuildDays
        case .hangar: table = tuning.hangarBuildDays
        case .crewBase: table = [tuning.crewBaseBuildDays]
        }
        return (from + 1...to).reduce(0) { $0 + (table[safe: $1 - 1] ?? 0) }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// A building going up: paid on order, open from the start of `completesAt`'s
/// day. Missing in older saves means nothing is being built.
public struct FacilityConstruction: Equatable, Codable, Sendable {
    public let airport: AirportCode
    public let service: AirportService
    /// The level it opens at.
    public let level: Int
    /// The level standing while it builds.
    public let fromLevel: Int
    public let startedAt: SimTime
    public let completesAt: SimTime
    public let cost: Money

    public init(airport: AirportCode, service: AirportService, level: Int, fromLevel: Int,
                startedAt: SimTime, completesAt: SimTime, cost: Money) {
        self.airport = airport; self.service = service; self.level = level; self.fromLevel = fromLevel
        self.startedAt = startedAt; self.completesAt = completesAt; self.cost = cost
    }

    /// 0 when ordered, 1 on opening day.
    public func progress(at now: SimTime) -> Double {
        let total = Double((completesAt - startedAt).minutes)
        guard total > 0 else { return 1 }
        return min(1, max(0, Double((now - startedAt).minutes) / total))
    }
    /// Whole days until it opens; 0 on opening day.
    public func daysLeft(at now: SimTime) -> Int {
        max(0, Int(completesAt.dayIndex - now.dayIndex))
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
    /// What stands and works at a station today.
    public func facilities(at airport: AirportCode) -> AirportFacilities {
        airportFacilities?[airport] ?? AirportFacilities()
    }
    /// What will stand once every building ordered here has opened.
    public func plannedFacilities(at airport: AirportCode) -> AirportFacilities {
        var planned = facilities(at: airport)
        for build in facilityConstructions ?? [] where build.airport == airport {
            planned = build.service.setting(max(build.level, build.service.level(in: planned)), in: planned)
        }
        return planned
    }
    public func construction(at airport: AirportCode, of service: AirportService) -> FacilityConstruction? {
        facilityConstructions?.first { $0.airport == airport && $0.service == service }
    }
    /// The status this airline has earned at a station; `.station` where it
    /// has none on record.
    public func hubStatus(at airport: AirportCode) -> HubStatus {
        hubStatuses?[airport] ?? (airport == homeAirport ? .base : .station)
    }
}

public struct ConfigureAirportFacilitiesCommand: Command, Equatable {
    public static let name = "configureAirportFacilities"
    public let airline: AirlineID
    public let airport: AirportCode
    /// The station as it should stand once building finishes. Levels above
    /// the plan are ordered and built over game days; levels below it close
    /// at once, with no refund.
    public let facilities: AirportFacilities
    public init(airline: AirlineID, airport: AirportCode, facilities: AirportFacilities) {
        self.airline = airline; self.airport = airport; self.facilities = facilities
    }
    public func validate(state: GameState, catalog: ContentCatalog) -> CommandRejection? {
        guard let owner = state.airlines[airline], owner.status == .active, catalog.airport(airport) != nil else {
            return .init(code: "airport.unavailable", message: "Choose an available airport for an active airline.")
        }
        guard facilities.isValid else {
            return .init(code: "airport.invalidFacilities", message: "Choose a level each building has.")
        }
        let planned = owner.plannedFacilities(at: airport)
        var increasing = false
        for service in AirportService.allCases {
            let target = service.level(in: facilities), plan = service.level(in: planned)
            guard target != plan else { continue }
            if owner.construction(at: airport, of: service) != nil {
                return .init(code: "airport.underConstruction",
                             message: "The \(service.title.lowercased()) here is under construction. Wait for it to open.")
            }
            if target > plan {
                increasing = true
                if state.isPlayer(airline), state.progression.era < service.unlockEra {
                    return .init(code: "airport.eraLocked",
                                 message: "The \(service.title.lowercased()) unlocks in the \(service.unlockEra.title) era.")
                }
            }
        }
        if increasing {
            guard airport == owner.homeAirport || state.routes(of: airline).contains(where: { $0.origin == airport || $0.destination == airport }) else {
                return .init(code: "airport.noPresence", message: "Open a route here before investing in this airport.")
            }
            guard !state.world.isAirportClosed(airport, at: state.clock.now) else {
                return .init(code: "airport.closed", message: "Wait until the airport reopens before expanding services.")
            }
        }
        let cost = facilities.installationCost(from: planned, tuning: catalog.tuning.airportServices)
        guard cost == .zero || state.ledger.balance(of: airline) >= cost else {
            return .init(code: "airport.insufficientFunds", message: "There is not enough cash for this airport investment.")
        }
        return nil
    }
    public func apply(state: inout GameState, context: SimContext) {
        guard var owner = state.airlines[airline] else { return }
        let planned = owner.plannedFacilities(at: airport)
        guard planned != facilities else { return }
        let tuning = context.catalog.tuning.airportServices
        let cost = facilities.installationCost(from: planned, tuning: tuning)
        var installed = owner.facilities(at: airport)
        var builds = owner.facilityConstructions ?? []
        let today = SimTime(rawMinutes: context.current.dayIndex * GameCalendar.minutesPerDay)
        for service in AirportService.allCases {
            let target = service.level(in: facilities), current = service.level(in: installed)
            // A building this order leaves as planned keeps its construction.
            guard target != service.level(in: planned) else { continue }
            if target < current {
                installed = service.setting(target, in: installed)
            } else if target > current {
                let days = service.buildDays(from: current, to: target, tuning: tuning)
                if days == 0 {
                    installed = service.setting(target, in: installed)
                } else {
                    builds.append(FacilityConstruction(
                        airport: airport, service: service, level: target, fromLevel: current,
                        startedAt: context.current, completesAt: today + .days(Int64(days)),
                        cost: service.installation(from: current, to: target, tuning: tuning)))
                }
            }
        }
        var stations = owner.airportFacilities ?? [:]
        stations[airport] = installed.isEmpty ? nil : installed
        owner.airportFacilities = stations
        owner.facilityConstructions = builds.isEmpty ? nil : builds
        var history = owner.airportFacilityHistory ?? []
        history.insert(.init(id: (history.first?.id ?? 0) + 1, at: context.current, airport: airport,
            previous: planned, updated: facilities, cost: cost), at: 0)
        owner.airportFacilityHistory = Array(history.prefix(100))
        state.airlines[airline] = owner
        if cost > .zero {
            state.ledger.post(airline: airline, category: .overhead, amount: -cost,
                at: context.current, memo: "\(airport.raw) facility installation")
        }
    }
}

// MARK: - Hub status

/// What a station means to an airline, earned from what it built and flies
/// there — never bought, never lost (docs/HUB_PROGRESSION_PLAN.md §3).
/// Later eras add Hub, Gateway and Flagship above these.
public enum HubStatus: Int, Codable, Sendable, CaseIterable, Comparable {
    case station = 0
    case base
    case mainBase

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .station: "Station"
        case .base: "Base"
        case .mainBase: "Main base"
        }
    }
    public var next: HubStatus? { HubStatus(rawValue: rawValue + 1) }
}

/// One requirement towards the next status, with how far along it is.
public struct HubStatusRequirement: Equatable, Sendable {
    public let title: String
    public let isMet: Bool
}

extension GameState {
    /// Aircraft of this airline flying routes that touch the airport.
    public func aircraftServing(_ airport: AirportCode, airline: AirlineID) -> Int {
        routes(of: airline).filter { $0.origin == airport || $0.destination == airport }
            .reduce(0) { $0 + $1.assignedAircraft.count }
    }

    /// What it takes to reach `status` at this airport, today.
    public func hubStatusRequirements(_ status: HubStatus, at airport: AirportCode,
                                      airline: AirlineID) -> [HubStatusRequirement] {
        guard let owner = airlines[airline] else { return [] }
        let built = owner.facilities(at: airport)
        switch status {
        case .station:
            return []
        case .base:
            if airport == owner.homeAirport {
                return [.init(title: "Your home airport", isMet: true)]
            }
            let flying = aircraftServing(airport, airline: airline)
            return [.init(title: "3 aircraft fly here (\(min(flying, 3)) of 3)", isMet: flying >= 3),
                    .init(title: "One building open", isMet: built.buildingCount >= 1)]
        case .mainBase:
            return [.init(title: "Base status", isMet: owner.hubStatus(at: airport) >= .base
                          || hubStatusRequirements(.base, at: airport, airline: airline).allSatisfy(\.isMet)),
                    .init(title: "Maintenance hangar open", isMet: built.hangar >= 1),
                    .init(title: "Crew base open", isMet: built.crewBase >= 1)]
        }
    }

    /// The highest status the airline meets at this airport today.
    public func earnedHubStatus(at airport: AirportCode, airline: AirlineID) -> HubStatus {
        var earned = HubStatus.station
        while let next = earned.next,
              hubStatusRequirements(next, at: airport, airline: airline).allSatisfy(\.isMet) {
            earned = next
        }
        return earned
    }
}

extension Era {
    /// For the facility command's messages; the app names eras itself.
    var title: String {
        switch self {
        case .startup: "Startup"
        case .regional: "Regional"
        case .national: "National"
        case .international: "International"
        case .empire: "Empire"
        }
    }
}
