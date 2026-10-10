import Foundation

// Building the hub from inside the Hub View (docs/HUB_HANDOFF.md §0c,
// docs/HUB_PROGRESSION_PLAN.md): where each of the player's buildings stands
// in the diorama, what the next level would cost, take and do, how far a
// construction has got, and the status the station has earned. The levels,
// prices and effects are the airport services (`AirportFacilities`,
// `AirportService`); this only reads them, and ordering one is the same
// `ConfigureAirportFacilitiesCommand` the Airport Services screen sends.

/// A building the player can put up at a hub, with a place in the diorama.
public enum HubFacilityKind: String, CaseIterable, Codable, Sendable {
    case lounge, groundServices, hangar, crewBase

    public var service: AirportService {
        switch self {
        case .lounge: .lounge
        case .groundServices: .ground
        case .hangar: .hangar
        case .crewBase: .crewBase
        }
    }

    public init(service: AirportService) {
        switch service {
        case .lounge: self = .lounge
        case .ground: self = .groundServices
        case .hangar: self = .hangar
        case .crewBase: self = .crewBase
        }
    }

    /// The building each level puts on the site.
    public func buildingName(_ level: Int) -> String {
        switch (self, level) {
        case (.lounge, 0): "Lounge site"
        case (.lounge, 1): "Airline lounge"
        case (.lounge, _): "Flagship lounge"
        case (.groundServices, 0): "Shared handling"
        case (.groundServices, 1): "Your ground crew depot"
        case (.groundServices, _): "Electric ground fleet"
        case (.hangar, 0): "Hangar site"
        case (.hangar, 1): "Line maintenance hangar"
        case (.hangar, _): "Heavy maintenance hangar"
        case (.crewBase, 0): "Crew base site"
        case (.crewBase, _): "Crew base and hotel"
        }
    }
}

/// Where a facility stands: a footprint and the height of the ground (or
/// roof) under it.
public struct HubFacilitySite: Equatable, Codable, Sendable {
    public let kind: HubFacilityKind
    public let footprint: HubRect
    public let elevation: Double

    public init(kind: HubFacilityKind, footprint: HubRect, elevation: Double) {
        self.kind = kind
        self.footprint = footprint
        self.elevation = elevation
    }

    public var center: HubVec { HubVec(footprint.center.x, elevation, footprint.center.z) }
}

/// What a building going up looks like at a moment of its construction
/// (docs/HUB_PROGRESSION_PLAN.md §6.4). Derived from progress, so a save
/// reopened mid-build shows the same stage.
public enum HubConstructionStage: Int, Codable, Sendable, CaseIterable, Comparable {
    case hoarding = 0
    case groundworks
    case frame
    case cladding

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(progress: Double) {
        switch progress {
        case ..<0.2: self = .hoarding
        case ..<0.45: self = .groundworks
        case ..<0.75: self = .frame
        default: self = .cladding
        }
    }

    public var title: String {
        switch self {
        case .hoarding: "Hoarding up"
        case .groundworks: "Groundworks"
        case .frame: "Crane up"
        case .cladding: "Cladding"
        }
    }
}

/// What the next level of a facility would cost and do, and whether it can
/// be bought now.
public struct HubUpgradeOffer: Equatable, Codable, Sendable, Identifiable {
    public let kind: HubFacilityKind
    public var id: HubFacilityKind { kind }
    public let title: String
    public let level: Int
    public let maxLevel: Int
    public let levelName: String
    public let buildingName: String
    /// What the current level does; "No effect yet" at level 0.
    public let effect: String
    public let scope: String
    public let monthlyCents: Int64
    /// Nil at the top level and while building.
    public let next: Next?
    /// Why the next level cannot be bought now (no presence, closed, cash,
    /// era); nil when it can.
    public let blocked: String?
    /// Set while the player's era is below the building's: the plot shows
    /// what is coming and when.
    public var lockedUntil: Era? = nil
    /// Set while a level is being built.
    public var construction: Construction? = nil
    /// The hangar at work: the player's aircraft in for a check here, by
    /// type, so the bay shows the actual jet.
    public var inCheck: [AircraftCategory] = []

    public struct Next: Equatable, Codable, Sendable {
        public let level: Int
        public let levelName: String
        public let buildingName: String
        public let effect: String
        public let installationCents: Int64
        public let monthlyCents: Int64
        /// Game days from order to opening.
        public var buildDays: Int = 0
        /// What it would have done for the player, from the simulation's own
        /// arithmetic; nil when there is no honest number.
        public var payoff: String? = nil
    }

    public struct Construction: Equatable, Codable, Sendable {
        /// The level that opens.
        public let level: Int
        public let buildingName: String
        public let progress: Double
        public let daysLeft: Int
        public let opensOn: GameDate
        public var stage: HubConstructionStage { HubConstructionStage(progress: progress) }
    }

    public var canUpgrade: Bool { next != nil && blocked == nil }
    public var isBuilding: Bool { construction != nil }
    public var isLocked: Bool { lockedUntil != nil }
}

/// The station's status, the next one and what it takes.
public struct HubStatusProgress: Equatable, Codable, Sendable {
    public let status: HubStatus
    public let next: HubStatus?
    public let requirements: [Requirement]

    public struct Requirement: Equatable, Codable, Sendable {
        public let title: String
        public let isMet: Bool
    }

    public static let empty = HubStatusProgress(status: .station, next: nil, requirements: [])
}

/// A dated line in a hub's own story (docs/HUB_PROGRESSION_PLAN.md §6.7).
public struct HubTimelineEntry: Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case founded, opened, status }
    public let at: SimTime
    public let date: GameDate
    public let kind: Kind
    public let title: String
}

extension HubLayout {
    /// Height of the terminal's roof slab, where the lounge pavilion stands.
    public static let terminalRoofTop = 16.6

    public func site(_ kind: HubFacilityKind) -> HubFacilitySite? {
        facilitySites.first { $0.kind == kind }
    }
}

extension GameState {
    /// The player's facilities at `airport`, each with its next level.
    /// Empty without a player airline.
    public func hubUpgradeOffers(airport code: AirportCode, catalog: ContentCatalog) -> [HubUpgradeOffer] {
        guard let player = playerAirline, catalog.airport(code) != nil else { return [] }
        let tuning = catalog.tuning.airportServices
        let ops = catalog.tuning.ops
        let installed = player.facilities(at: code)
        let planned = player.plannedFacilities(at: code)
        return HubFacilityKind.allCases.map { kind in
            let service = kind.service
            let level = service.level(in: installed)
            let now = AirportServiceReadModel(service: service, installed: installed, proposed: installed,
                                              tuning: tuning, ops: ops)
            var next: HubUpgradeOffer.Next?
            var blocked: String?
            var construction: HubUpgradeOffer.Construction?
            if let build = player.construction(at: code, of: service) {
                construction = .init(level: build.level, buildingName: kind.buildingName(build.level),
                                     progress: build.progress(at: clock.now), daysLeft: build.daysLeft(at: clock.now),
                                     opensOn: GameCalendar.date(at: build.completesAt, startYear: meta.startYear))
            } else if level < service.maxLevel {
                let proposed = service.setting(level + 1, in: planned)
                let quote = AirportServiceReadModel(service: service, installed: installed,
                                                    proposed: service.setting(level + 1, in: installed),
                                                    tuning: tuning, ops: ops)
                next = .init(level: level + 1, levelName: service.levelName(level + 1),
                             buildingName: kind.buildingName(level + 1), effect: quote.effect,
                             installationCents: quote.installation.cents, monthlyCents: quote.monthly.cents,
                             buildDays: quote.buildDays,
                             payoff: payoff(of: service, level: level + 1, at: code, airline: player.id, catalog: catalog))
                // The command's own checks, so the card never offers what
                // the simulation would refuse.
                let command = ConfigureAirportFacilitiesCommand(airline: player.id, airport: code, facilities: proposed)
                blocked = command.validate(state: self, catalog: catalog)?.message
            }
            var inCheck: [AircraftCategory] = []
            if service == .hangar, level > 0 {
                for aircraft in fleet(of: player.id) where aircraft.status.isInMaintenance && hangarLevel(serving: aircraft) > 0 {
                    let route = aircraft.assignedRoute.flatMap { routes[$0] }
                    let here = route.map { $0.origin == code || $0.destination == code } ?? (aircraft.location == code)
                    if here, let spec = catalog.aircraftType(aircraft.typeCode) { inCheck.append(spec.category) }
                }
            }
            return HubUpgradeOffer(
                kind: kind, title: service.title, level: level, maxLevel: service.maxLevel,
                levelName: service.levelName(level), buildingName: kind.buildingName(level),
                effect: level == 0 ? "No effect yet" : now.effect, scope: now.scope,
                monthlyCents: now.monthly.cents, next: next, blocked: blocked,
                lockedUntil: progression.era < service.unlockEra ? service.unlockEra : nil,
                construction: construction, inCheck: inCheck)
        }
    }

    /// What a level would have done here, in the player's terms. Only the
    /// buildings whose gain the simulation can count say anything.
    func payoff(of service: AirportService, level: Int, at airport: AirportCode,
                airline: AirlineID, catalog: ContentCatalog) -> String? {
        let tuning = catalog.tuning.airportServices
        let ops = catalog.tuning.ops
        let routes = routes(of: airline).filter { $0.origin == airport || $0.destination == airport }
        switch service {
        case .hangar:
            let fleet = catalog.tuning.fleet
            let current = airlines[airline].map { $0.facilities(at: airport).hangar } ?? 0
            let base = current > 0 ? (tuning.hangarCheckDays[safe: current - 1] ?? fleet.maintenanceCheckDays)
                : fleet.maintenanceCheckDays
            let days = min(base, tuning.hangarCheckDays[safe: level - 1] ?? base)
            let factorNow = current > 0 ? (tuning.hangarCheckCostFactor[safe: current - 1] ?? 1) : 1
            let factorNext = tuning.hangarCheckCostFactor[safe: level - 1] ?? factorNow
            var aircraftCount = 0
            var savedDays = 0.0, savedCost = 0.0
            for route in routes {
                for id in route.assignedAircraft.sorted() {
                    guard let aircraft = aircraft[id], let spec = catalog.aircraftType(aircraft.typeCode) else { continue }
                    aircraftCount += 1
                    let hours = FlightSchedulingSystem.blockHoursPerDay(
                        route: route, aircraftID: id, state: self, spec: spec, ops: ops, facilities: tuning) ?? 0
                    let perDay = FleetEconomics.conditionPerDay(blockHoursPerDay: hours, fleet: fleet, ops: ops)
                    guard perDay > 0 else { continue }
                    let interval = (1 - fleet.maintenanceConditionThreshold) / perDay
                    let checks = Double(GameCalendar.daysPerYear) / (interval + Double(base))
                    savedDays += checks * Double(base - days)
                    let check = FleetEconomics.maintenanceCheckCost(type: spec, ageYears: aircraft.ageYears, tuning: fleet)
                    savedCost += checks * check.asDouble * max(0, factorNow - factorNext)
                }
            }
            guard aircraftCount > 0 else { return "No aircraft fly through here yet." }
            let saved = Int(savedDays.rounded())
            var parts: [String] = []
            if saved > 0 { parts.append("\(saved) aircraft-day\(saved == 1 ? "" : "s")") }
            if savedCost >= 1 { parts.append("\(Self.dollars(savedCost)) of checks") }
            guard !parts.isEmpty else { return nil }
            return "About \(parts.joined(separator: " and ")) back a year across your \(aircraftCount) aircraft here."
        case .crewBase:
            guard !routes.isEmpty else { return "No routes from here yet." }
            let longer = OperatingWindow.withCrewBase(ops, tuning: tuning).minutes
            var room = 0
            for route in routes {
                guard let first = route.assignedAircraft.sorted().first,
                      let type = aircraft[first].flatMap({ catalog.aircraftType($0.typeCode) }) else { continue }
                let turnaround = turnaroundMinutes(spec: type, airline: airline)
                let now = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
                    distanceKm: route.distanceKm, spec: type, ops: ops, turnaroundMinutes: turnaround)
                let then = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
                    distanceKm: route.distanceKm, spec: type, ops: ops,
                    operatingMinutes: longer, turnaroundMinutes: turnaround)
                room += (then - now) * route.assignedAircraft.count
            }
            let count = routes.count
            guard room > 0 else {
                return "Crews \(Int(((1 - tuning.crewBaseCrewCostFactor) * 100).rounded()))% cheaper on your \(count) route\(count == 1 ? "" : "s") here; no extra rotation fits yet."
            }
            return "Room for +\(room) rotation\(room == 1 ? "" : "s") a day on your \(count) route\(count == 1 ? "" : "s") here."
        case .lounge, .ground:
            return nil
        }
    }

    /// "$1.2M", "$450k": a figure for a sentence.
    static func dollars(_ value: Double) -> String {
        if value >= 1_000_000 { return "$" + String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return "$\(Int((value / 1_000).rounded()))k" }
        return "$\(Int(value.rounded()))"
    }

    /// The player's status at this airport, the next one and what it takes.
    public func hubStatusProgress(airport code: AirportCode) -> HubStatusProgress {
        guard let player = playerAirline else { return .empty }
        let status = max(player.hubStatus(at: code), earnedHubStatus(at: code, airline: player.id))
        guard let next = status.next else { return HubStatusProgress(status: status, next: nil, requirements: []) }
        let requirements = hubStatusRequirements(next, at: code, airline: player.id)
            .map { HubStatusProgress.Requirement(title: $0.title, isMet: $0.isMet) }
        return HubStatusProgress(status: status, next: next, requirements: requirements)
    }

    /// This airport's story for the player, oldest first: founding, the
    /// buildings that opened and the statuses earned.
    public func hubTimeline(airport code: AirportCode) -> [HubTimelineEntry] {
        guard let player = playerAirline else { return [] }
        func date(_ t: SimTime) -> GameDate { GameCalendar.date(at: t, startYear: meta.startYear) }
        var entries: [HubTimelineEntry] = []
        if player.homeAirport == code {
            entries.append(.init(at: player.foundedAt, date: date(player.foundedAt), kind: .founded,
                                 title: "\(player.name) founded here"))
        }
        for moment in progression.record {
            switch moment.kind {
            case .facilityOpened(let airport, let service, let level) where airport == code:
                entries.append(.init(at: moment.at, date: date(moment.at), kind: .opened,
                                     title: HubFacilityKind(service: service).buildingName(level) + " opened"))
            case .hubStatus(let airport, let status) where airport == code:
                entries.append(.init(at: moment.at, date: date(moment.at), kind: .status,
                                     title: "Became a \(status.title.lowercased())"))
            default:
                break
            }
        }
        return entries
    }
}
