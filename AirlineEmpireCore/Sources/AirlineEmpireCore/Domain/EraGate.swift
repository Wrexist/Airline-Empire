/// Era gate evaluation, as data rather than as a boolean
/// (docs/PROGRESSION.md §2).
///
/// `ProgressionSystem` used to hold this logic privately and answer one
/// question — may the player advance? That is all the simulation needs, and it
/// is not enough for the player: a macro arc whose requirements are invisible
/// is not a progression system, it is a surprise. The UI must be able to say
/// "3 of 8 destinations", and it must say it from the *same* arithmetic that
/// decides the gate, or the two will drift and the screen will lie.
///
/// So the gate is expressed as a list of `EraRequirement`s and "passed" is
/// derived from them. `ProgressionSystem` asks `isPassed`; the progression
/// screen asks `requirements`. One source of truth, two questions.
///
/// Requirement kinds are stable identifiers, not sentences: naming them for a
/// player is presentation, and presentation does not live in Core.
public enum EraRequirementKind: String, Equatable, Sendable, CaseIterable {
    /// Routes whose last closed month made a direct operating profit.
    case profitableRoutes
    /// At least one airframe the airline owns outright (not leased).
    case ownsAircraft
    /// Trailing twelve-month net profit above zero.
    case trailingProfitPositive
    /// Distinct airports served.
    case destinations
    /// Blended reputation score.
    case reputation
    /// Aircraft in the fleet.
    case fleetSize
    /// Distinct world regions touched by the network.
    case worldRegions
}

/// One condition on the way to the next era, with the player's standing
/// against it. Boolean conditions report 1 or 0 against a target of 1 so that
/// every requirement renders the same way.
public struct EraRequirement: Equatable, Sendable {
    public let kind: EraRequirementKind
    public let current: Double
    public let target: Double

    public init(kind: EraRequirementKind, current: Double, target: Double) {
        self.kind = kind
        self.current = current
        self.target = target
    }

    public var isMet: Bool { current >= target }

    /// 0…1 progress toward the target, for a bar. Clamped, and 1 for a target
    /// of zero (a requirement that asks for nothing is already met).
    public var fraction: Double {
        guard target > 0 else { return 1 }
        return min(1, max(0, current / target))
    }
}

public enum EraGate {
    /// The next era after `era`, or nil at the top of the ladder.
    public static func next(after era: Era) -> Era? {
        switch era {
        case .startup: .regional
        case .regional: .national
        case .national: .international
        case .international: .empire
        case .empire: nil
        }
    }

    /// Everything `era` demands, with the player's current standing.
    /// `.startup` is the starting era and demands nothing.
    public static func requirements(for era: Era, player: Airline, state: GameState,
                                    catalog: ContentCatalog,
                                    tuning: ProgressionTuning) -> [EraRequirement] {
        let routes = state.routes(of: player.id)
        let fleet = state.fleet(of: player.id)
        switch era {
        case .startup:
            return []
        case .regional:
            let profitable = routes.filter {
                $0.economicsLastMonth.directOperatingProfit > .zero
            }.count
            let ownsOne = fleet.contains {
                if case .owned = $0.ownership { true } else { false }
            }
            return [
                EraRequirement(kind: .profitableRoutes, current: Double(profitable),
                               target: Double(tuning.regionalProfitableRoutes)),
                EraRequirement(kind: .ownsAircraft, current: ownsOne ? 1 : 0, target: 1),
            ]
        case .national:
            let trailing = trailingNetProfit(player.id, state: state, months: 12)
            return [
                EraRequirement(kind: .trailingProfitPositive,
                               current: trailing > .zero ? 1 : 0, target: 1),
                EraRequirement(kind: .destinations,
                               current: Double(destinations(routes).count),
                               target: Double(tuning.nationalDestinations)),
                EraRequirement(kind: .reputation, current: player.reputation.score,
                               target: tuning.nationalReputationFloor),
            ]
        case .international:
            let trailing = trailingNetProfit(player.id, state: state, months: 12)
            // Serving two world regions IS going international.
            let regions = Set(routes.flatMap { route -> [WorldRegion] in
                [route.origin, route.destination].compactMap {
                    catalog.airport($0)?.region
                }
            })
            return [
                EraRequirement(kind: .trailingProfitPositive,
                               current: trailing > .zero ? 1 : 0, target: 1),
                EraRequirement(kind: .fleetSize, current: Double(fleet.count),
                               target: Double(tuning.internationalFleet)),
                EraRequirement(kind: .worldRegions, current: Double(regions.count),
                               target: 2),
            ]
        case .empire:
            return [
                EraRequirement(kind: .destinations,
                               current: Double(destinations(routes).count),
                               target: Double(tuning.empireDestinations)),
                EraRequirement(kind: .fleetSize, current: Double(fleet.count),
                               target: Double(tuning.empireFleet)),
            ]
        }
    }

    /// Whether the player may advance into `era`. Derived from the same
    /// requirements the UI renders, so the screen and the gate cannot drift.
    public static func isPassed(_ era: Era, player: Airline, state: GameState,
                                catalog: ContentCatalog,
                                tuning: ProgressionTuning) -> Bool {
        requirements(for: era, player: player, state: state, catalog: catalog,
                     tuning: tuning).allSatisfy(\.isMet)
    }

    static func destinations(_ routes: [Route]) -> Set<AirportCode> {
        var set = Set<AirportCode>()
        for route in routes {
            set.insert(route.origin)
            set.insert(route.destination)
        }
        return set
    }

    static func trailingNetProfit(_ airline: AirlineID, state: GameState,
                                  months: Int) -> Money {
        guard let finance = state.finance.byAirline[airline] else { return .zero }
        return finance.statements.suffix(months)
            .reduce(Money.zero) { $0 + $1.netProfit }
    }
}
