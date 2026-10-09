import Foundation

// Upgrading the hub from inside the Hub View (docs/HUB_HANDOFF.md §0c):
// where each of the player's facilities stands in the diorama, and what the
// next level would cost and do. The levels, prices and effects are the
// existing airport services (`AirportFacilities`, `AirportService`); this
// only reads them, and buying one is the same
// `ConfigureAirportFacilitiesCommand` the Airport Services screen sends.

/// A facility the player can build at a hub, with a place in the diorama.
public enum HubFacilityKind: String, CaseIterable, Codable, Sendable {
    case lounge, groundServices

    public var service: AirportService {
        switch self {
        case .lounge: .lounge
        case .groundServices: .ground
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
    /// What the current level does; "No effect" at level 0.
    public let effect: String
    public let scope: String
    public let monthlyCents: Int64
    /// Nil at the top level.
    public let next: Next?
    /// Why the next level cannot be bought now (no presence, closed, cash);
    /// nil when it can.
    public let blocked: String?

    public struct Next: Equatable, Codable, Sendable {
        public let level: Int
        public let levelName: String
        public let buildingName: String
        public let effect: String
        public let installationCents: Int64
        public let monthlyCents: Int64
    }

    public var canUpgrade: Bool { next != nil && blocked == nil }
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
        let installed = player.facilities(at: code)
        return HubFacilityKind.allCases.map { kind in
            let service = kind.service
            let level = service.level(in: installed)
            let now = AirportServiceReadModel(service: service, installed: installed, proposed: installed, tuning: tuning)
            var next: HubUpgradeOffer.Next?
            var blocked: String?
            if level < 2 {
                let proposed = service.setting(level + 1, in: installed)
                let quote = AirportServiceReadModel(service: service, installed: installed, proposed: proposed,
                                                    tuning: tuning)
                next = .init(level: level + 1, levelName: AirportService.levelName(level + 1),
                             buildingName: kind.buildingName(level + 1), effect: quote.effect,
                             installationCents: quote.installation.cents, monthlyCents: quote.monthly.cents)
                // The command's own checks, so the card never offers what
                // the simulation would refuse.
                let command = ConfigureAirportFacilitiesCommand(airline: player.id, airport: code, facilities: proposed)
                blocked = command.validate(state: self, catalog: catalog)?.message
            }
            return HubUpgradeOffer(
                kind: kind, title: service.title, level: level, maxLevel: 2,
                levelName: AirportService.levelName(level), buildingName: kind.buildingName(level),
                effect: level == 0 ? "No effect yet" : now.effect, scope: now.scope,
                monthlyCents: now.monthly.cents, next: next, blocked: blocked)
        }
    }
}
