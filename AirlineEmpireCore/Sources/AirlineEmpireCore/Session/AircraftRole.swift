import Foundation

/// What an aircraft type is *for* (MASTER PROMPT 5 §10).
///
/// `AircraftCategory` is a taxonomy: it says a type is a "regional jet",
/// which tells a player who already knows the industry everything and a new
/// player nothing. A role says what the aeroplane is bought to do.
///
/// **This is honestly a restatement of the category, and worth saying so.**
/// The derivation below is one-to-one, because in this catalog nothing else
/// separates types within a class — the three narrowbodies sit inside 600 km
/// and 22 seats of each other. The value here is the wording and the
/// `SeatEfficiencyBand` beside it, not a cleverer classification; if a later
/// catalog gives a category two genuinely different uses (a long-thin
/// narrowbody against a high-frequency shuttle, say), this is where that
/// split belongs, and it can be made without touching a screen.
public enum AircraftRole: String, Equatable, Sendable, CaseIterable {
    /// Small, slow, and able to use runways nothing else can.
    case shortFieldRegional
    /// Thin routes at jet speed, where a narrowbody would fly half empty.
    case regionalConnector
    /// The backbone: dense short and medium routes.
    case shortHaulWorkhorse
    /// The same routes, more seats, when demand has outgrown a narrowbody.
    case highCapacityNarrowbody
    /// Intercontinental reach.
    case longHaulWidebody
    /// The largest thing the airline can fly, on its densest long routes.
    case flagshipLongHaul
}

/// Fuel burned per seat carried, banded against the best in the catalog.
///
/// This is the aircraft economics fact that actually decides a fleet, and it
/// is the one the market never showed. It is also much larger than anyone
/// looking at the per-type numbers would guess: a turboprop burns roughly
/// **72% more fuel per seat-kilometre than a large narrowbody**, and regional
/// jets are the thirstiest per seat of anything in the catalog. Small
/// aeroplanes are not cheap aeroplanes; they buy access to routes and runways
/// that bigger ones cannot use, and the fuel bill per passenger is the price.
///
/// Banded rather than printed as a ratio because the decision is "is this
/// class expensive to run per passenger", not a number to compare to three
/// decimal places.
public enum SeatEfficiencyBand: Equatable, Sendable {
    /// Within 15% of the most efficient type in the catalog.
    case best
    case strong
    case moderate
    /// More than 60% worse per seat than the best available.
    case thirsty
}

extension AircraftTypeSpec {
    /// What this type is bought to do.
    public var role: AircraftRole {
        // Spelled out rather than written with leading dots: a `switch`
        // expression whose branches are implicit members needs a contextual
        // type, and this toolchain has refused that before in this project
        // (see `AircraftSilhouette.Planform.of`).
        switch category {
        case .turboprop: AircraftRole.shortFieldRegional
        case .regionalJet: AircraftRole.regionalConnector
        case .narrowbody: AircraftRole.shortHaulWorkhorse
        case .largeNarrowbody: AircraftRole.highCapacityNarrowbody
        case .widebody: AircraftRole.longHaulWidebody
        case .largeWidebody: AircraftRole.flagshipLongHaul
        }
    }

    /// Fuel burn per seat-kilometre. The comparable efficiency figure —
    /// `fuelBurnKgPerKm` alone says a widebody is thirsty, which is true and
    /// useless, because it is also carrying three times the passengers.
    public var fuelBurnPerSeatKm: Double {
        fuelBurnKgPerKm / Double(max(1, seats))
    }
}

extension ContentCatalog {
    /// The lowest fuel burn per seat-km any type in the catalog achieves.
    /// The reference point for every band; nil for an empty catalog.
    public var bestFuelBurnPerSeatKm: Double? {
        orderedAircraftTypeCodes
            .compactMap { aircraftTypes[$0]?.fuelBurnPerSeatKm }
            .min()
    }

    /// How expensive this type is to fly per passenger, against the best the
    /// catalog offers. Nil when there is nothing to compare against.
    public func seatEfficiency(of spec: AircraftTypeSpec) -> SeatEfficiencyBand? {
        guard let best = bestFuelBurnPerSeatKm, best > 0 else { return nil }
        let ratio = spec.fuelBurnPerSeatKm / best
        switch ratio {
        case ..<1.15: return .best
        case ..<1.35: return .strong
        case ..<1.6: return .moderate
        default: return .thirsty
        }
    }
}
