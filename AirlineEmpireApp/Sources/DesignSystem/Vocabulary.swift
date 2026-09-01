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

    // MARK: - Livery

    /// Core names a livery; the app decides what that looks like. The values
    /// are chosen to stay apart from one another on the map's dark ocean and
    /// to hold up against both appearances.
    static func liveryColor(_ livery: Livery) -> Color {
        switch livery {
        case .azure: AETheme.accent
        case .ember: Color(red: 0.95, green: 0.55, blue: 0.20)
        case .jade: Color(red: 0.16, green: 0.70, blue: 0.48)
        case .crimson: Color(red: 0.87, green: 0.24, blue: 0.32)
        case .violet: Color(red: 0.56, green: 0.36, blue: 0.87)
        case .slate: Color(red: 0.49, green: 0.56, blue: 0.65)
        case .gold: Color(red: 0.86, green: 0.70, blue: 0.20)
        case .teal: Color(red: 0.16, green: 0.62, blue: 0.68)
        }
    }

    static func livery(_ livery: Livery) -> String {
        switch livery {
        case .azure: "Azure"
        case .ember: "Ember"
        case .jade: "Jade"
        case .crimson: "Crimson"
        case .violet: "Violet"
        case .slate: "Slate"
        case .gold: "Gold"
        case .teal: "Teal"
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
        // The humanize fallback mangles codes with digits ("Passengers100k"),
        // and these four exist in ProgressionSystem today.
        case "passengers100k": "100,000 passengers"
        case "passengers1m": "One million passengers"
        case "destinations10": "Ten destinations"
        case "fleet10": "A fleet of ten"
        default: humanize(code)
        }
    }

    /// What a milestone *means*, for the celebration overlay. The generic
    /// "Milestone reached." said nothing at the one moment the game had the
    /// player's full attention; the first flight, in particular, is also the
    /// first ticket money — the loop's proof — and the overlay is where that
    /// gets said (GAME_EXPERIENCE_PRIORITY.md, game-feel #1).
    static func milestoneDetail(_ code: String) -> String {
        switch code {
        case "firstFlight":
            "Your first flight has landed — the first ticket revenue is in the bank."
        case "firstOwnedAircraft":
            "Bought outright. No lessor, no monthly bill."
        case "firstProfitableMonth":
            "The airline made more than it spent this month."
        case "firstMillionMonth":
            "A seven-figure month. The machine works."
        case "firstIntercontinental":
            "Your network now crosses an ocean."
        case "passengers100k":
            "One hundred thousand passengers flown."
        case "passengers1m":
            "One million passengers flown."
        case "destinations10":
            "Ten destinations on the map."
        case "fleet10":
            "Ten aircraft in the fleet."
        default: "Milestone reached."
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

// MARK: - Route verdicts

extension Vocab {
    /// A route's economics as one sentence (MASTER PROMPT 4 §13).
    ///
    /// The standing and the drivers are decided in Core, from the route's own
    /// recorded figures; this only chooses words for them. That split is the
    /// point — the claim is testable on Linux, and the phrasing can be
    /// rewritten without anyone re-deriving what causes what.
    ///
    /// Nil when Core declined to attribute a cause. A screen that always shows
    /// a reason trains the player to ignore reasons.
    static func routeVerdict(_ verdict: RouteVerdict) -> String? {
        switch verdict.standing {
        case .idle:
            return "No aircraft assigned, so this route is not flying."
        case .tooEarly:
            return "Too new to judge — the first flights have not landed yet."
        case .earning, .losing:
            guard let primary = verdict.primary else {
                // Losing with nothing out of the ordinary is a real state and
                // deserves an honest answer rather than an invented culprit.
                return verdict.standing == .losing
                    ? "Losing money, with no single cause standing out."
                    : nil
            }
            let lead = verdict.standing == .earning ? "Earning" : "Losing money"
            let because = driver(primary)
            guard let second = verdict.secondary else {
                return "\(lead) — \(because)."
            }
            return "\(lead) — \(because), and \(driver(second))."
        }
    }

    /// One driver as a clause, to be read after "Earning" or "Losing money".
    ///
    /// Each clause states a figure and no judgement, because the lead word
    /// already carries the polarity. That is why `.loadFactor` and
    /// `.strongDemand` produce the same words: 80% full is 80% full, and
    /// whether it reads as the cause of a profit or of a loss is settled by
    /// the sentence it lands in, not by this function. Core decided which
    /// driver dominates (`RouteVerdict`); this only chooses the wording, so
    /// the phrasing can be rewritten without anyone re-deriving what causes
    /// what.
    private static func driver(_ driver: RouteVerdict.Driver) -> String {
        switch driver {
        case .loadFactor(let value):
            return "aircraft are flying \(Format.percent(value)) full"
        case .fareBelowMarket(let position):
            return "the fare is \(Format.percent(1 - position)) below the market"
        case .fareAboveMarket(let position):
            return "the fare is \(Format.percent(position - 1)) above the market"
        case .fees(let share):
            return "airport fees take \(Format.percent(share)) of the revenue"
        case .fuel(let share):
            return "fuel takes \(Format.percent(share)) of the revenue"
        case .cancellations(let rate):
            return "only \(Format.percent(rate)) of flights are completing"
        case .strongDemand(let value):
            return "aircraft are flying \(Format.percent(value)) full"
        }
    }
}

extension Vocab {
    /// A world event's severity as a word (MASTER PROMPT 4 §16).
    ///
    /// `WorldEvent.severity` is 0…1 "within the kind's semantics" — so it is
    /// not comparable across kinds, and rendering it as a percentage would
    /// invite exactly the comparison it cannot support ("this storm is 70%,
    /// that strike is 40%, so the storm is worse"). Bands say what a player
    /// can actually use: how hard this one is going to bite.
    static func severity(_ value: Double) -> String {
        switch value {
        case ..<0.34: "Mild"
        case ..<0.67: "Moderate"
        default: "Severe"
        }
    }

    /// The colour for a severity band. Never the only carrier — the word is
    /// always shown beside it.
    static func severityColor(_ value: Double) -> Color {
        switch value {
        case ..<0.34: AETheme.mutedText
        case ..<0.67: AETheme.caution
        default: AETheme.negative
        }
    }
}

extension Vocab {
    /// Why an aircraft cannot take a route (MASTER PROMPT 5 §23).
    ///
    /// Core's `AssignmentCandidate.Blocker` decides; this only chooses words.
    /// Each reads as a fact about *this* pairing rather than a refusal, because
    /// it is shown beside a disabled row the player has not tapped yet — "you
    /// cannot do that" is the wrong tense for something nobody has tried.
    static func blocker(_ blocker: AssignmentCandidate.Blocker) -> String {
        switch blocker {
        case .notDelivered:
            return "Not delivered yet"
        case .alreadyAssigned:
            return "Already on a route"
        case .beyondRange(let rangeKm, let distanceKm):
            // The shortfall, not the two figures. "1,600 km range, 4,452 km
            // route" makes the reader do the subtraction; "2,852 km short"
            // is the same fact already used.
            return "\(Format.grouped(Int64(distanceKm - rangeKm))) km beyond its range"
        case .runwayTooSmall(let airport, _, _):
            return "\(airport.raw) cannot take this aircraft"
        }
    }

    /// What is worth knowing about an assignment Core would allow.
    ///
    /// Nil when Core had nothing to say — which is most of the time, and is
    /// the point. A picker where every row carries a caption ranks nothing.
    static func assignmentNote(_ note: AssignmentCandidate.Note?) -> String? {
        switch note {
        case nil:
            return nil
        case .inMaintenance:
            return "In a maintenance check — it can be assigned now and will fly when the check finishes"
        case .tightRange(let marginKm):
            return "Only \(Format.grouped(Int64(marginKm))) km of range to spare"
        case .seatsShortOfDemand(let seats, let demand):
            return "\(Format.grouped(Int64(seats))) seats a day against \(Format.grouped(Int64(demand))) passengers wanting to fly"
        case .seatsAboveDemand(let seats, let demand):
            return "\(Format.grouped(Int64(seats))) seats a day for \(Format.grouped(Int64(demand))) passengers — it would fly light"
        case .strongMatch:
            return "Good fit for this route"
        }
    }

    /// The tint for a note. Never the only carrier: the sentence above always
    /// says the same thing in words.
    static func assignmentNoteColor(_ note: AssignmentCandidate.Note?) -> Color {
        switch note {
        case nil: AETheme.mutedText
        case .strongMatch: AETheme.positive
        case .inMaintenance, .tightRange, .seatsAboveDemand: AETheme.caution
        case .seatsShortOfDemand: AETheme.mutedText
        }
    }
}

extension Vocab {
    /// What an aircraft type is bought to do (MASTER PROMPT 5 §10).
    ///
    /// `Vocab.category` gives the taxonomy ("Regional jet"); this gives the
    /// use. A new player reading "Regional jet · 88 seats · 2,750 km" has to
    /// already know the industry to turn that into a decision.
    static func role(_ role: AircraftRole) -> String {
        switch role {
        case .shortFieldRegional: "Short-field regional"
        case .regionalConnector: "Regional connector"
        case .shortHaulWorkhorse: "Short-haul workhorse"
        case .highCapacityNarrowbody: "High-capacity narrowbody"
        case .longHaulWidebody: "Long-haul widebody"
        case .flagshipLongHaul: "Flagship long-haul"
        }
    }

    /// One sentence on what the role is good for, and what it costs you.
    ///
    /// Every line names a genuine trade rather than selling the aeroplane.
    /// The regional entries say the quiet part — small aircraft are not cheap
    /// aircraft, they are expensive per passenger and you buy them for reach,
    /// not for economy (see `SeatEfficiencyBand`).
    static func roleDetail(_ role: AircraftRole) -> String {
        switch role {
        case .shortFieldRegional:
            "Reaches small airports nothing else can use. Costs the most fuel per passenger of anything you can buy."
        case .regionalConnector:
            "Jet speed on thin routes that would leave a narrowbody half empty — and the thirstiest per seat in the catalogue."
        case .shortHaulWorkhorse:
            "Dense short and medium routes. The best fuel per passenger in the game, which is why airlines are built on these."
        case .highCapacityNarrowbody:
            "The same routes with more seats, for when demand has outgrown a narrowbody."
        case .longHaulWidebody:
            "Intercontinental reach, at a fuel cost per seat between a narrowbody and a regional jet."
        case .flagshipLongHaul:
            "The most seats and the most range you can field. Only pays on dense long routes."
        }
    }

    /// Fuel per passenger, as a band rather than a ratio.
    static func seatEfficiency(_ band: SeatEfficiencyBand) -> String {
        switch band {
        case .best: "Excellent fuel per seat"
        case .strong: "Good fuel per seat"
        case .moderate: "Average fuel per seat"
        case .thirsty: "Thirsty per seat"
        }
    }

    /// The tint for an efficiency band. The words above always accompany it.
    static func seatEfficiencyColor(_ band: SeatEfficiencyBand) -> Color {
        switch band {
        case .best: AETheme.positive
        case .strong: AETheme.positive.opacity(0.8)
        case .moderate: AETheme.mutedText
        case .thirsty: AETheme.caution
        }
    }
}

extension Vocab {
    /// Fleet filter labels (MASTER PROMPT 5 §17).
    ///
    /// "Idle" is the load-bearing one: it means airworthy, unassigned and
    /// costing money — not "in a check" and not "still on order", neither of
    /// which the player can do anything about today. Lumping those in is what
    /// turns an idle count from a to-do list into a number.
    static func fleetStatus(_ status: FleetFilter.Status) -> String {
        switch status {
        case .all: "All"
        case .assigned: "Flying"
        case .idle: "Idle"
        case .inMaintenance: "In check"
        case .onOrder: "On order"
        }
    }

    static func fleetOwnership(_ ownership: FleetFilter.Ownership) -> String {
        switch ownership {
        case .all: "All"
        case .owned: "Owned"
        case .leased: "Leased"
        }
    }

    /// An airport, said the way people say airports: "Sjövik (Stockholm)" —
    /// the field's own name first, the city it serves in brackets, the way a
    /// traveller says "Arlanda" and clarifies with "(Stockholm)".
    ///
    /// The catalog names airports "City Fieldname" ("Stockholm Sjövik"), so
    /// the leading city is stripped rather than repeated. An airport whose
    /// name does not follow that shape keeps its full name; one with no
    /// distinct field name is just its city.
    static func airportDisplay(name: String, city: String) -> String {
        var field = name
        if !city.isEmpty, name.hasPrefix(city),
           name.count > city.count {
            field = String(name.dropFirst(city.count))
                .trimmingCharacters(in: .whitespaces)
        }
        if field.isEmpty || field == city { return city }
        if city.isEmpty { return field }
        return "\(field) (\(city))"
    }

    static func airportDisplay(_ spec: AirportSpec) -> String {
        airportDisplay(name: spec.name, city: spec.city)
    }
}
