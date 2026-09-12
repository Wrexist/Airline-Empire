import AirlineEmpireCore

/// The one thing worth doing next, and the control that actually does it
/// (AE-048, docs/ROADMAP_DIRECTION_II.md Phase 27).
///
/// ## It is a derivation, not a state
///
/// Nothing here is stored, remembered or persisted. The move is resolved from
/// the snapshot every time the snapshot changes, which is the only way it can
/// stay honest: a next step that survived a new game, or that went on saying
/// "get an aircraft" after one was bought, would be worse than no next step at
/// all. `GameController` caches the result for exactly one published snapshot,
/// alongside the map model and the network summary, for the same reason they
/// are cached — `body` runs far more often than the world changes.
///
/// ## No SwiftUI here, deliberately
///
/// `GameController` holds the cache and does not import SwiftUI. The tint is
/// therefore a *tone* — a meaning — and the view turns it into a colour. That
/// also keeps the palette in one place rather than spelling `AETheme.caution`
/// into a model.
struct HomeNextMove: Equatable {
    /// What pressing the row does. Every case lands on an existing surface —
    /// a sheet the Airline tab already presents, a destination the map's own
    /// navigation stack already registers, or a command the game already has.
    /// There is no case here that leads nowhere.
    enum Move: Equatable {
        case aircraftMarket
        case openRoute(FirstRouteSuggestion)
        case route(RouteID)
        case aircraft(AircraftID)
        case startClock
        case nextMorning
        case follow(FlightID)
        case briefing
    }

    /// What the row means, in the design system's terms rather than in
    /// colours: the map draws it, and the map owns its palette.
    enum Tone: Equatable {
        case accent
        case positive
        case caution
        case negative
        /// The player's own livery — used when the move is "watch your
        /// airline", so the row is the colour of the aeroplane it points at.
        case livery(Livery)
    }

    let icon: String
    let title: String
    let detail: String
    var tone: Tone = .accent
    /// The icon breathes. Reserved for something that is costing the player
    /// money while it waits — never for a suggestion.
    var attention: Bool = false
    let move: Move
    /// Offered inline under the row, for the one step where a list is the
    /// explanation (opening the first route).
    var suggestions: [FirstRouteSuggestion] = []

    /// The priority. Each case below is a real state the simulation can be
    /// in, and when none of them holds the row simply does not appear — a
    /// cozy builder is allowed to have nothing to nag about.
    static func resolve(snapshot: GameState,
                        model: MapModel,
                        catalog: ContentCatalog?,
                        fleetSummary: FleetSummary?) -> HomeNextMove? {
        guard let player = snapshot.playerAirline else { return nil }

        // 1 · The airline is dying. Nothing else is the next move.
        //
        // The top bar is already saying this; the row is not the alarm, it is
        // the way in — the briefing carries the solvency banner, the month and
        // the routes that are losing money, which is what acting on it means.
        if let catalog,
           let solvency = snapshot.solvencyModel(for: player.id, catalog: catalog),
           solvency.stage == .danger {
            let days = solvency.daysUntilAdministration
            return HomeNextMove(
                icon: "exclamationmark.octagon.fill",
                title: days.map { "Administration in \($0) day\($0 == 1 ? "" : "s")" }
                    ?? "The airline is insolvent",
                detail: "Open the briefing: what is losing money, and what you can sell.",
                tone: .negative, attention: true, move: .briefing)
        }

        // 2 · The first session's arc, from the model that owns it. One
        // onboarding system in this game; this reads it, it does not repeat it.
        if let catalog,
           let onboarding = snapshot.onboardingModel(catalog: catalog),
           let step = onboarding.nextStep {
            return firstSession(step: step, onboarding: onboarding,
                                snapshot: snapshot, player: player)
        }

        // 3 · An aeroplane earning nothing. It bills like a flying one.
        if let idle = snapshot.fleet(of: player.id)
            .first(where: { $0.assignedRoute == nil }) {
            let count = fleetSummary?.idle ?? 1
            return HomeNextMove(
                icon: "pause.circle.fill",
                title: count == 1 ? "One aircraft is idle"
                                  : "\(count) aircraft are idle",
                detail: "Parked costs the same as flying. Give it a route.",
                tone: .caution, attention: true, move: .aircraft(idle.id))
        }

        // 4 · Growth, but only where the ranking says the market pays for the
        // aircraft it needs (BUG-055). Advice that cannot pay is not advice.
        if let catalog {
            let ranked = snapshot.marketOpportunities(catalog: catalog, limit: 4)
            if let best = ranked.first(where: { $0.servableNow && $0.paysForItsAirframe }) {
                return HomeNextMove(
                    icon: "sparkle",
                    title: "\(best.origin.raw) → \(best.destination.raw) is open",
                    detail: "\(best.destinationCity) · about \(best.expectedDailyPassengers) passengers a day, and it pays for its aircraft.",
                    tone: .positive,
                    move: .openRoute(best.asFirstRouteSuggestion))
            }
        }

        // 5 · Nothing needs doing. Watch the world instead — the flight is
        // real, and riding with it is what this map was rebuilt for (AE-046).
        let airborne = model.flights.filter { $0.isPlayer && $0.airborne }
        if let flight = airborne.first {
            return HomeNextMove(
                icon: "scope",
                title: airborne.count == 1 ? "One of yours is in the air"
                                           : "\(airborne.count) of yours are in the air",
                detail: "Ride with \(flight.origin.raw) → \(flight.destination.raw).",
                tone: .livery(player.livery),
                move: .follow(flight.id))
        }

        // 6 · A network with nothing flying on it is a state, and the honest
        // move is to start the clock rather than to invent an errand.
        if snapshot.flights.isEmpty, !snapshot.routes(of: player.id).isEmpty {
            return HomeNextMove(
                icon: "play.circle",
                title: "Nothing is flying",
                detail: "Start the clock and let the schedule run.",
                move: .startClock)
        }

        return nil
    }

    /// The first five minutes, one step at a time, each with the control that
    /// performs it rather than the name of a tab to go and find (BUG-059).
    private static func firstSession(step: OnboardingModel.Step,
                                     onboarding: OnboardingModel,
                                     snapshot: GameState,
                                     player: Airline) -> HomeNextMove {
        let title = Vocab.onboardingStep(step)
        let detail = Vocab.onboardingHint(step)
        let icon = Vocab.onboardingIcon(step)
        switch step {
        case .acquireAircraft:
            return HomeNextMove(icon: icon, title: title, detail: detail,
                                move: .aircraftMarket)
        case .openRoute:
            // The candidates are the move. The row itself opens the best of
            // them, so a player who presses the headline and a player who
            // presses the first candidate land in the same sheet.
            guard let best = onboarding.suggestions.first else {
                return HomeNextMove(icon: icon, title: title, detail: detail,
                                    move: .briefing)
            }
            return HomeNextMove(
                icon: icon, title: title,
                detail: "The dashed arcs are the strongest markets from \(player.homeAirport.raw). Pick one.",
                tone: .positive,
                move: .openRoute(best),
                suggestions: Array(onboarding.suggestions.prefix(2)))
        case .assignAircraft:
            let bare = snapshot.routes(of: player.id)
                .first { $0.assignedAircraft.isEmpty }
            return HomeNextMove(icon: icon, title: title, detail: detail,
                                tone: .caution,
                                move: bare.map { Move.route($0.id) } ?? .briefing)
        case .watchFirstFlight:
            return HomeNextMove(icon: icon, title: title, detail: detail,
                                move: .startClock)
        case .earnFirstRevenue:
            if let flight = snapshot.flights.values.sorted(by: { $0.id < $1.id }).first(where: {
                guard snapshot.routes[$0.route]?.airline == player.id else { return false }
                if case .enRoute = $0.phase { return true }
                return false
            }) {
                return HomeNextMove(icon: "airplane", title: "Watch your first flight",
                                    detail: "Ticket revenue arrives when your passengers land.",
                                    move: .follow(flight.id))
            }
            return HomeNextMove(icon: icon, title: "Waiting for your first arrival",
                                detail: detail, move: .startClock)
        }
    }
}
