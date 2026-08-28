/// The guided first-route beat (docs/PLAYER_JOURNEY.md §1): a checklist the
/// UI shows a brand-new airline, derived entirely from existing state — no
/// persisted onboarding flags, so saves are untouched and the checklist is
/// always honest about what the player has actually done.

public struct OnboardingModel: Equatable, Sendable {
    /// The first-five-minutes arc, in teaching order. Teaching is doing:
    /// every step is a real game action, not a tutorial wall.
    public enum Step: String, CaseIterable, Sendable {
        case acquireAircraft
        case openRoute
        case assignAircraft
        case watchFirstFlight
        case earnFirstRevenue
    }

    public let completed: Set<Step>
    /// First incomplete step in teaching order; nil when done.
    public let nextStep: Step?
    /// Highlighted first-route candidates from home (empty once a route
    /// exists — the training wheels come off).
    public let suggestions: [FirstRouteSuggestion]

    public var isComplete: Bool { nextStep == nil }
    public func isDone(_ step: Step) -> Bool { completed.contains(step) }
}

/// A demand-hinted route candidate (docs/PLAYER_JOURNEY.md §1 step 2:
/// "two highlighted candidates with visible demand hints").
public struct FirstRouteSuggestion: Equatable, Sendable {
    public let origin: AirportCode
    public let destination: AirportCode
    public let destinationCity: String
    public let distanceKm: Int
    /// Passengers a typical starter service could expect to carry per day
    /// across both directions at the reference fare — the share the logit
    /// split actually awards, not the raw market pool, which is several
    /// times larger and would overstate the market (BUG-006). A hint, not
    /// a promise: competition and pricing decide the rest.
    public let expectedDailyPassengers: Int
    /// The market reference fare at this distance (what "normal" costs).
    public let referenceFare: Money
}

extension GameState {
    /// Onboarding checklist for the player airline; nil before one exists.
    /// Pure derivation — calling it never mutates anything.
    public func onboardingModel(catalog: ContentCatalog,
                                suggestionLimit: Int = 2) -> OnboardingModel? {
        guard let player = playerAirline else { return nil }
        let fleet = fleet(of: player.id)
        let routes = routes(of: player.id)

        var completed: Set<OnboardingModel.Step> = []
        if !fleet.isEmpty { completed.insert(.acquireAircraft) }
        if !routes.isEmpty { completed.insert(.openRoute) }
        if routes.contains(where: { !$0.assignedAircraft.isEmpty }) {
            completed.insert(.assignAircraft)
        }
        let hasLiveFlight = flights.values.contains { flight in
            self.routes[flight.route]?.airline == player.id
        }
        if hasLiveFlight || routes.contains(where: { $0.stats.totalFlights > 0 }) {
            completed.insert(.watchFirstFlight)
        }
        if routes.contains(where: {
            $0.stats.passengersCarried > 0
                || $0.economicsThisMonth.revenueCents > 0
                || $0.economicsLastMonth.revenueCents > 0
        }) {
            completed.insert(.earnFirstRevenue)
        }

        let next = OnboardingModel.Step.allCases.first { !completed.contains($0) }
        let suggestions = completed.contains(.openRoute)
            ? []
            : firstRouteSuggestions(for: player, catalog: catalog,
                                    limit: suggestionLimit)
        return OnboardingModel(completed: completed, nextStep: next,
                               suggestions: suggestions)
    }

    /// Best first routes from home: eligible for what the player flies (or
    /// could buy this era), ranked by today's round-trip demand pool.
    /// Deterministic: ties break on destination code.
    private func firstRouteSuggestions(for player: Airline,
                                       catalog: ContentCatalog,
                                       limit: Int) -> [FirstRouteSuggestion] {
        guard limit > 0, catalog.airport(player.homeAirport) != nil else { return [] }

        // Capability basis: the fleet if one exists, otherwise the best the
        // current era lets the player acquire.
        let ownedSpecs = fleet(of: player.id)
            .compactMap { catalog.aircraftType($0.typeCode) }
        let candidateSpecs = ownedSpecs.isEmpty
            ? catalog.orderedAircraftTypeCodes
                .compactMap { catalog.aircraftType($0) }
                .filter { progression.era.allowedCategories.contains($0.category) }
            : ownedSpecs
        guard !candidateSpecs.isEmpty else { return [] }

        let home = player.homeAirport
        let date = currentDate
        var scored: [(FirstRouteSuggestion, Double)] = []
        for code in catalog.orderedAirportCodes where code != home {
            // Per aircraft, never the best range paired with the least
            // demanding runway: that chimera suggests routes no single
            // aircraft can serve, and every assignment would then be rejected.
            guard candidateSpecs.contains(where: { spec in
                catalog.routeEligibility(
                    from: home, to: code,
                    aircraftRangeKm: spec.rangeKm,
                    aircraftRunwayRequirement: spec.runwayRequirement).isEmpty
            }), let distance = catalog.distanceKm(home, code)
            else { continue }
            let quality = DemandSystem.representativeStarterQuality(
                tuning: catalog.tuning.demand)
            let outbound = DemandSystem.expectedCapturedPassengers(
                pool: DemandSystem.demandPool(from: home, to: code, date: date,
                                              economicIndex: world.economicIndex,
                                              catalog: catalog),
                fareRatio: 1.0, quality: quality, tuning: catalog.tuning.demand)
            let inbound = DemandSystem.expectedCapturedPassengers(
                pool: DemandSystem.demandPool(from: code, to: home, date: date,
                                              economicIndex: world.economicIndex,
                                              catalog: catalog),
                fareRatio: 1.0, quality: quality, tuning: catalog.tuning.demand)
            let pool = outbound + inbound
            let fare = DemandSystem.referenceFare(distanceKm: distance,
                                                  tuning: catalog.tuning.demand)
            scored.append((FirstRouteSuggestion(
                origin: home, destination: code,
                destinationCity: catalog.airport(code)?.city ?? code.raw,
                distanceKm: distance,
                expectedDailyPassengers: Int(pool.rounded()),
                referenceFare: Money(rounding: fare)), pool))
        }
        return scored
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1
                                   : $0.0.destination < $1.0.destination }
            .prefix(limit)
            .map(\.0)
    }
}
