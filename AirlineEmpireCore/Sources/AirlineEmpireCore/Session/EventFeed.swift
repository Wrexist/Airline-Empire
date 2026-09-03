/// Event feed classification (docs/UI_ARCHITECTURE.md §2).
///
/// Events are emitted for every airline in the world — the player's rivals
/// close statements, take loans, and cancel flights through exactly the same
/// systems. A player-facing feed that renders the raw stream therefore shows
/// rivals' private books as if they were the player's own (BUG-004).
///
/// Ownership lives on the entities, not on the event payloads (an event
/// carries an `AircraftID`, not its owner), so classification needs state.
/// It is resolved at publish time, against the exact state that produced the
/// event — never later, when the aircraft may have been sold.

extension GameState {
    /// The airline whose business this event describes; nil for world-wide
    /// news (weather, fuel markets, the calendar) that concerns everyone.
    public func subjectAirline(of event: SimEvent) -> AirlineID? {
        switch event.kind {
        // Calendar and diagnostics: the world's clock, nobody's business.
        case .dayStarted, .weekStarted, .monthStarted, .seasonChanged,
             .wakeFired, .commandApplied:
            return nil

        // World events hit everyone.
        case .worldEventForecast, .worldEventStarted, .worldEventEnded:
            return nil

        // Airline-level facts carry their subject directly.
        case .airlineFounded(let id, _),
             .airlineEnteredAdministration(let id),
             .airlineCollapsed(let id):
            return id
        case .loanTaken(let airline, _, _),
             .loanRepaidEarly(let airline, _),
             .statementClosed(let airline, _, _, _),
             .marketEntered(let airline, _, _),
             .marketLeft(let airline, _, _):
            return airline

        // Fleet events name an aircraft; its owner is the subject.
        case .aircraftOrdered(let id, _, _),
             .aircraftDelivered(let id),
             .aircraftSold(let id, _),
             .leaseReturned(let id, _),
             .maintenanceStarted(let id, _, _),
             .maintenanceCompleted(let id):
            return aircraft[id]?.owner

        // Route and flight events resolve through the route's operator.
        case .routeOpened(let id, _, _), .routeClosed(let id):
            return routes[id]?.airline
        case .aircraftAssigned(_, let route),
             .aircraftUnassigned(_, let route),
             .flightDeparted(_, let route),
             .flightDelayed(_, let route, _),
             .flightCancelled(_, let route),
             .flightArrived(_, let route, _):
            return routes[route]?.airline

        // Progression is the player's own arc (ProgressionSystem only runs
        // for the player airline).
        case .eraAdvanced, .milestoneReached, .achievementUnlocked,
             .capabilityCompleted, .missionOffered, .missionCompleted,
             .missionExpired, .gameOver:
            return playerAirline?.id
        }
    }

    /// Whether this event's subject can only be known by resolving an entity
    /// — an aircraft, route, or flight — rather than from the payload itself.
    ///
    /// The distinction matters because those entities can be *gone* by the
    /// time an event is classified: an airline collapsing closes its routes
    /// and liquidates its fleet within the same tick chunk, so the flight and
    /// route events it emitted moments earlier no longer resolve. Such an
    /// event has an *unknown* owner, which is not the same as belonging to
    /// nobody (BUG-007).
    public func isEntityScoped(_ event: SimEvent) -> Bool {
        switch event.kind {
        case .aircraftOrdered, .aircraftDelivered, .aircraftSold, .leaseReturned,
             .maintenanceStarted, .maintenanceCompleted,
             .routeOpened, .routeClosed, .aircraftAssigned, .aircraftUnassigned,
             .flightDeparted, .flightDelayed, .flightCancelled, .flightArrived:
            return true
        default:
            return false
        }
    }

    /// Whether an airline's operations feed should carry this event: its own
    /// business, world news, and the publicly-visible fate of a rival.
    /// A rival's delayed flight or closed statement is private; a rival
    /// entering administration or collapsing is industry news.
    public func isFeedEvent(_ event: SimEvent, for airline: AirlineID) -> Bool {
        guard let subject = subjectAirline(of: event) else {
            // An entity event whose owner no longer resolves is unknown, not
            // world news. Admitting it here would put a collapsing rival's
            // flights into the player's feed — the very leak BUG-004 fixed.
            if isEntityScoped(event) { return false }
            // World news, minus the pure-diagnostic kernel chatter.
            switch event.kind {
            case .wakeFired, .commandApplied: return false
            default: return true
            }
        }
        if subject == airline { return true }
        switch event.kind {
        case .airlineFounded, .airlineEnteredAdministration, .airlineCollapsed:
            return true
        // A rival entering or leaving a city pair is news exactly when it is
        // *your* city pair: the demand engine splits that market between you
        // from the next morning. Their moves elsewhere stay their business
        // (docs/RIVAL_PRESSURE_AUDIT.md §4 — the noise budget).
        case .marketEntered(_, let origin, let destination),
             .marketLeft(_, let origin, let destination):
            return routes.values.contains {
                $0.airline == airline
                    && $0.sameMarket(origin: origin, destination: destination)
            }
        default:
            return false
        }
    }
}
