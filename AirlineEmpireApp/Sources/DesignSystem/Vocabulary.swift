import SwiftUI
import AirlineEmpireCore

/// The player's vocabulary (docs/UIUX_FORENSIC_AUDIT.md UI-020).
///
/// Core's enums are model vocabulary: `northAmerica`, `efficientTurnarounds`,
/// `veryLarge`, `firstProfitableMonth`. Those names are correct in a domain
/// model and wrong on a screen — the game was telling players
/// "Milestone: firstProfitableMonth" and "Tourism boom — southeastAsia".
///
/// Naming is presentation, so it lives here rather than in Core, and it lives
/// in *one* file so that a region has the same name on the map, in the feed,
/// in a mission and in an event list. Every screen goes through `Vocab`;
/// nothing calls `String(describing:)` or `rawValue` on a model enum again.
enum Vocab {

    // MARK: - World

    static func region(_ region: WorldRegion) -> String {
        switch region {
        case .northAmerica: "North America"
        case .southAmerica: "South America"
        case .europe: "Europe"
        case .middleEast: "the Middle East"
        case .africa: "Africa"
        case .southAsia: "South Asia"
        case .eastAsia: "East Asia"
        case .southeastAsia: "Southeast Asia"
        case .oceania: "Oceania"
        }
    }

    static func season(_ season: Season) -> String {
        switch season {
        case .winter: "Winter"
        case .spring: "Spring"
        case .summer: "Summer"
        case .autumn: "Autumn"
        }
    }

    static func weatherRisk(_ risk: WeatherRisk) -> String {
        switch risk {
        case .low: "Calm skies"
        case .moderate: "Some storms"
        case .high: "Rough weather"
        case .severe: "Storm belt"
        }
    }

    static func runway(_ runway: RunwayClass) -> String {
        switch runway {
        case .small: "Short runway"
        case .medium: "Medium runway"
        case .large: "Long runway"
        case .veryLarge: "Very long runway"
        }
    }

    /// What a runway class means for the player's fleet, which is the only
    /// reason the class is on screen at all.
    static func runwayDetail(_ runway: RunwayClass) -> String {
        switch runway {
        case .small: "Turboprops only"
        case .medium: "Up to regional jets"
        case .large: "Up to narrowbodies"
        case .veryLarge: "Widebodies welcome"
        }
    }

    // MARK: - Fleet

    static func category(_ category: AircraftCategory) -> String {
        switch category {
        case .turboprop: "Turboprop"
        case .regionalJet: "Regional jet"
        case .narrowbody: "Narrowbody"
        case .largeNarrowbody: "Large narrowbody"
        case .widebody: "Widebody"
        case .largeWidebody: "Large widebody"
        }
    }

    /// A glyph per class, so a fleet list reads as aircraft rather than as
    /// rows. SF Symbols only — the project ships no custom art yet.
    static func categoryIcon(_ category: AircraftCategory) -> String {
        switch category {
        case .turboprop, .regionalJet: "airplane"
        case .narrowbody, .largeNarrowbody: "airplane.departure"
        case .widebody, .largeWidebody: "airplane.circle.fill"
        }
    }

    static func serviceTier(_ tier: ServiceTier) -> String {
        switch tier {
        case .basic: "Basic"
        case .standard: "Standard"
        case .premium: "Premium"
        }
    }

    /// What choosing a tier actually does, so the choice is informed.
    static func serviceTierDetail(_ tier: ServiceTier) -> String {
        switch tier {
        case .basic:
            "Cheapest per passenger. Service reputation drifts down; fine for a value carrier that is honest about it."
        case .standard:
            "The middle. Costs and expectations both sit at the market's level."
        case .premium:
            "Most expensive per passenger, and the only tier that lifts service reputation far. Premium fares need it."
        }
    }

    // MARK: - Airlines

    static func archetype(_ archetype: AIArchetype) -> String {
        switch archetype {
        case .lowCost: "Low-cost"
        case .premium: "Premium"
        case .regional: "Regional"
        case .conservative: "Conservative"
        case .expansionist: "Expansionist"
        }
    }

    /// How this rival plays, so a competitor reads as a character.
    static func archetypeDetail(_ archetype: AIArchetype) -> String {
        switch archetype {
        case .lowCost: "Undercuts on fare and expects volume to follow"
        case .premium: "Charges up and defends the product"
        case .regional: "Sticks to short markets it knows"
        case .conservative: "Grows slowly, rarely overreaches"
        case .expansionist: "Opens markets fast, worries later"
        }
    }

    // MARK: - Progression

    static func era(_ era: Era) -> String {
        switch era {
        case .startup: "Startup"
        case .regional: "Regional"
        case .national: "National"
        case .international: "International"
        case .empire: "Empire"
        }
    }

    static func eraDetail(_ era: Era) -> String {
        switch era {
        case .startup: "One aircraft, one route, everything to prove"
        case .regional: "A real regional carrier — large narrowbodies open up"
        case .national: "Widebodies, and capability programs open"
        case .international: "The whole catalogue; the world is the market"
        case .empire: "A network other airlines plan around"
        }
    }

    static func capability(_ code: CapabilityCode) -> String {
        switch code {
        case .efficientTurnarounds: "Efficient turnarounds"
        case .fuelHedging: "Fuel hedging"
        case .networkOpsCenter: "Network operations centre"
        case .groundExperience: "Ground experience"
        }
    }

    /// What the program changes about the way the game plays — the reason it
    /// is a capability and not a percentage.
    static func capabilityDetail(_ code: CapabilityCode) -> String {
        switch code {
        case .efficientTurnarounds:
            "Turnarounds run 15% faster, so more rotations fit into a day on every route you fly."
        case .fuelHedging:
            "Fuel bills cap near the base price. A fuel shock stops being a threat to the whole airline."
        case .networkOpsCenter:
            "Disruptions are 20% less likely to spread, so one late aircraft stops ruining its own day."
        case .groundExperience:
            "Service reputation aims eight points higher, which is what premium fares need to hold."
        }
    }

    static func capabilityIcon(_ code: CapabilityCode) -> String {
        switch code {
        case .efficientTurnarounds: "timer"
        case .fuelHedging: "fuelpump"
        case .networkOpsCenter: "antenna.radiowaves.left.and.right"
        case .groundExperience: "sparkles"
        }
    }

    /// Era-gate requirements, named for the player.
    static func requirement(_ kind: EraRequirementKind) -> String {
        switch kind {
        case .profitableRoutes: "Routes that made money last month"
        case .ownsAircraft: "An aircraft you own outright"
        case .trailingProfitPositive: "Profitable over the last twelve months"
        case .destinations: "Airports served"
        case .reputation: "Reputation"
        case .fleetSize: "Aircraft in the fleet"
        case .worldRegions: "World regions you fly in"
        }
    }

    /// A requirement's standing, formatted the way its kind wants to be read.
    static func requirementValue(_ requirement: EraRequirement) -> String {
        switch requirement.kind {
        case .ownsAircraft, .trailingProfitPositive:
            return requirement.isMet ? "Yes" : "Not yet"
        case .reputation:
            return "\(Format.percent(requirement.current)) of \(Format.percent(requirement.target))"
        case .profitableRoutes, .destinations, .fleetSize, .worldRegions:
            return "\(Int(requirement.current)) of \(Int(requirement.target))"
        }
    }

    /// Milestones and achievements are stable string codes in Core. Unknown
    /// codes fall back to a de-camel-cased form rather than showing nothing,
    /// so a future milestone is merely unpolished instead of broken.
    static func milestone(_ code: String) -> String {
        switch code {
        case "firstFlight": "First flight"
        case "firstOwnedAircraft": "First aircraft of your own"
        case "firstProfitableMonth": "First profitable month"
        case "firstMillionMonth": "First million-dollar month"
        case "firstIntercontinental": "First intercontinental route"
        default: humanize(code)
        }
    }

    static func achievement(_ code: String) -> String {
        switch code {
        case "valueLegend": "Value legend"
        case "purist": "Single-family purist"
        case "debtFree": "Debt free"
        case "weatherProof": "Weatherproof"
        default: humanize(code)
        }
    }

    static func achievementDetail(_ code: String) -> String {
        switch code {
        case "valueLegend": "Held an outstanding value reputation for a full season"
        case "purist": "Built the whole fleet from one manufacturer"
        case "debtFree": "Ran a real airline with no debt at all"
        case "weatherProof": "Kept completion above 97% across hundreds of flights"
        default: "Unlocked"
        }
    }

    /// `firstProfitableMonth` → "First profitable month". The fallback for a
    /// code this file has not been taught yet.
    static func humanize(_ code: String) -> String {
        var out = ""
        for (index, character) in code.enumerated() {
            if index == 0 {
                out.append(Character(character.uppercased()))
            } else if character.isUppercase {
                out.append(" ")
                out.append(Character(character.lowercased()))
            } else {
                out.append(character)
            }
        }
        return out
    }

    // MARK: - Events

    static func worldEvent(_ kind: WorldEventKind, state: GameState? = nil) -> String {
        switch kind {
        case .fuelShock:
            return "Fuel market shock"
        case .storm(let where_):
            return "Severe weather over \(Vocab.region(where_))"
        case .airportClosure(let airport):
            return "\(airport.raw) closed"
        case .tourismBoom(let where_):
            return "Tourism boom in \(Vocab.region(where_))"
        case .strike(let airline):
            return "Crew strike at \(Vocab.airlineName(airline, state: state))"
        }
    }

    /// What the event is doing to the airline, in one clause.
    static func worldEventEffect(_ kind: WorldEventKind) -> String {
        switch kind {
        case .fuelShock: "Fuel costs more on every flight you operate."
        case .storm: "Flights through the region are delayed and cancelled more often."
        case .airportClosure: "Nothing can operate here until it reopens."
        case .tourismBoom: "Leisure demand into and out of the region is up."
        case .strike: "That airline's flights are disrupted."
        }
    }

    static func worldEventIcon(_ kind: WorldEventKind) -> String {
        switch kind {
        case .fuelShock: "fuelpump.fill"
        case .storm: "cloud.bolt.rain.fill"
        case .airportClosure: "xmark.octagon.fill"
        case .tourismBoom: "sun.max.fill"
        case .strike: "person.2.slash.fill"
        }
    }

    /// An airline's actual name where the model has only an id. Falls back to
    /// something readable rather than printing the raw identifier.
    static func airlineName(_ id: AirlineID, state: GameState?) -> String {
        state?.airlines[id]?.name ?? "a rival airline"
    }
}
