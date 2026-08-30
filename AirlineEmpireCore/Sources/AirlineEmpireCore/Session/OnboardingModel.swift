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

    /// Public because the suggestion is not only Core's to make: the map's
    /// airport callout and the airport browser both offer "open a route from
    /// here", and they hand the same pre-filled shape to the route sheet.
    public init(origin: AirportCode, destination: AirportCode,
                destinationCity: String, distanceKm: Int,
                expectedDailyPassengers: Int, referenceFare: Money) {
        self.origin = origin
        self.destination = destination
        self.destinationCity = destinationCity
        self.distanceKm = distanceKm
        self.expectedDailyPassengers = expectedDailyPassengers
        self.referenceFare = referenceFare
    }
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

    /// Best first routes, from the one ranking the whole game uses
    /// (`marketOpportunities`). This was a private near-copy of that
    /// function; two rankings of "where should I fly" that can disagree is
    /// one ranking too many, and the map needs the general form anyway.
    private func firstRouteSuggestions(for player: Airline,
                                       catalog: ContentCatalog,
                                       limit: Int) -> [FirstRouteSuggestion] {
        marketOpportunities(catalog: catalog, limit: limit)
            .map(\.asFirstRouteSuggestion)
    }
}
