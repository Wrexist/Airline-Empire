/// What the game should be *heard* to be doing (docs/AUDIO_ARCHITECTURE.md).
///
/// This file contains no audio. It contains the decision of which sounds a
/// moment deserves — and that decision is a pure function of simulation
/// events, the state that produced them, the clock speed, and what has
/// already been heard recently.
///
/// It lives in Core for the same reason `MapModel` does: the app formats,
/// Core decides. Concretely it buys three things that a director living
/// inside a SwiftUI view could not have:
///
/// 1. **It is testable on Linux.** Priority, aggregation, cooldown and the
///    16x policy are exercised by the same suite as the economy, with no
///    simulator and nothing to listen to.
/// 2. **First-time moments survive a save.** "Your first flight has landed"
///    is seeded from persisted route statistics rather than from a flag the
///    presentation layer keeps, so loading a mature airline cannot replay the
///    beginning of the game at somebody (docs/AUDIO_ARCHITECTURE.md §6).
/// 3. **It cannot desynchronise from the feed.** The cues are derived from
///    the very `SimEvent`s the ops feed renders, so the game never says one
///    thing on screen and another in the speakers.
///
/// Nothing here mutates the world, allocates an ID, or reads a clock of its
/// own: the caller supplies monotonic time, which is what makes the cooldowns
/// exact under test.

// MARK: - Taxonomy

/// What a sound is *about*. Drives asset organisation, mixing, and which
/// settings toggle silences it.
public enum AudioCategory: String, Hashable, Sendable, CaseIterable {
    /// Direct response to a touch. Must be immediate and very quiet.
    case ui
    /// The airline's own machinery: aircraft, maintenance, assignment.
    case operations
    /// Opening, changing and closing routes — the strategic layer.
    case routes
    /// Money moving.
    case finance
    /// The world acting on the player: weather, strikes, fuel, booms.
    case world
    /// Progress the player earned.
    case progression
    /// Things that can end the game.
    case critical
}

/// How much a cue is allowed to interrupt.
///
/// Ordered worst-to-best on purpose so `>=` reads as "at least this
/// important", and so a batch can be sorted by simply sorting the values.
public enum AudioPriority: Int, Hashable, Sendable, Comparable, CaseIterable {
    /// Background texture. Never interrupts anything, first to be dropped.
    case ambient = 0
    /// Nice to hear, fine to lose — most UI.
    case subtle
    /// The ordinary business of running an airline.
    case normal
    /// The player should not miss this.
    case important
    /// The game may be about to end. Always plays, never rate-limited.
    case critical

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Every sound the game can ask for, named for what it *means* rather than
/// for the file that happens to implement it.
///
/// A view says `play(.routeOpened)`. It never says `play("whoosh_3.wav")`,
/// which is how a sound library becomes impossible to re-design.
public enum AudioCue: String, Hashable, Sendable, CaseIterable {

    // MARK: Interface — raised by views, never by the simulation

    case uiSelect
    case uiNavigate
    case uiConfirm
    case uiCancel
    case uiSheetOpen
    case uiSheetClose
    case uiToggle
    case uiError

    // MARK: Fleet

    case aircraftOrdered
    case aircraftDelivered
    case aircraftSold
    case leaseReturned
    case aircraftAssigned
    case aircraftUnassigned
    case maintenanceStarted
    case maintenanceCompleted

    // MARK: Routes

    case routeOpened
    case routeClosed

    // MARK: Flights

    case flightDeparted
    case flightArrived
    case flightDelayed
    case flightCancelled
    /// Several departures in one batch, heard once. See `aggregate`.
    case departureFlurry
    /// Several arrivals in one batch, heard once.
    case arrivalFlurry
    /// Several cancellations at once — a bad morning, said in one sound.
    case disruptionFlurry

    // MARK: The first times

    case firstRoute
    case firstDeparture
    case firstArrival
    case firstRevenue

    // MARK: Money

    case monthClosedProfit
    case monthClosedLoss
    case loanTaken
    case loanRepaid

    // MARK: World

    case worldEventForecast
    case stormStarted
    case strikeStarted
    case fuelShockStarted
    case boomStarted
    case airportClosed
    case worldEventEnded

    // MARK: Progression

    case missionOffered
    case missionCompleted
    case missionExpired
    case milestoneReached
    case achievementUnlocked
    case capabilityCompleted
    case eraAdvanced

    // MARK: The end

    case administrationEntered
    case collapse
    case gameOver

    // MARK: Ambience

    case ambienceOperations
    case ambienceWorld

    public var category: AudioCategory {
        switch self {
        case .uiSelect, .uiNavigate, .uiConfirm, .uiCancel, .uiSheetOpen,
             .uiSheetClose, .uiToggle, .uiError:
            return .ui
        case .aircraftOrdered, .aircraftDelivered, .aircraftSold, .leaseReturned,
             .aircraftAssigned, .aircraftUnassigned, .maintenanceStarted,
             .maintenanceCompleted, .flightDeparted, .flightArrived,
             .flightDelayed, .flightCancelled, .departureFlurry,
             .arrivalFlurry, .disruptionFlurry, .firstDeparture, .firstArrival:
            return .operations
        case .routeOpened, .routeClosed, .firstRoute:
            return .routes
        case .monthClosedProfit, .monthClosedLoss, .loanTaken, .loanRepaid,
             .firstRevenue:
            return .finance
        case .worldEventForecast, .stormStarted, .strikeStarted,
             .fuelShockStarted, .boomStarted, .airportClosed, .worldEventEnded:
            return .world
        case .missionOffered, .missionCompleted, .missionExpired,
             .milestoneReached, .achievementUnlocked, .capabilityCompleted,
             .eraAdvanced:
            return .progression
        case .administrationEntered, .collapse, .gameOver:
            return .critical
        case .ambienceOperations, .ambienceWorld:
            return .world
        }
    }

    public var priority: AudioPriority {
        switch self {
        case .ambienceOperations, .ambienceWorld:
            return .ambient

        case .uiSelect, .uiNavigate, .uiToggle, .uiSheetOpen, .uiSheetClose,
             .flightDeparted, .flightArrived, .aircraftUnassigned,
             .maintenanceStarted, .maintenanceCompleted, .worldEventEnded,
             .missionOffered, .missionExpired:
            return .subtle

        case .uiConfirm, .uiCancel, .uiError, .aircraftAssigned,
             .aircraftOrdered, .aircraftSold, .leaseReturned, .routeClosed,
             .flightDelayed, .flightCancelled, .departureFlurry,
             .arrivalFlurry, .loanRepaid, .worldEventForecast,
             .boomStarted:
            return .normal

        case .routeOpened, .aircraftDelivered, .disruptionFlurry,
             .monthClosedProfit, .monthClosedLoss, .loanTaken,
             .stormStarted, .strikeStarted, .fuelShockStarted, .airportClosed,
             .missionCompleted, .milestoneReached, .achievementUnlocked,
             .capabilityCompleted:
            return .important

        // The first times are the emotional spine of the opening hour, and
        // an era change is the largest thing that happens to an airline.
        case .firstRoute, .firstDeparture, .firstArrival, .firstRevenue,
             .eraAdvanced:
            return .important

        case .administrationEntered, .collapse, .gameOver:
            return .critical
        }
    }

    /// The base name of the asset that voices this cue, without extension.
    ///
    /// The *name* is Core's business even though the *file* is the app's:
    /// keeping it here makes "every cue can be voiced" a property a Linux
    /// test can assert, and lets `scripts/audio/check-assets.py` fail CI when
    /// a cue is added without a sound. A cue whose file is missing is a
    /// silent failure at runtime — the worst kind for an audio system, since
    /// nothing crashes and nobody notices until a player says the game went
    /// quiet.
    public var assetName: String {
        switch self {
        case .uiSelect: return "ui_select"
        case .uiNavigate: return "ui_navigate"
        case .uiConfirm: return "ui_confirm"
        case .uiCancel: return "ui_cancel"
        case .uiSheetOpen: return "ui_sheet_open"
        case .uiSheetClose: return "ui_sheet_close"
        case .uiToggle: return "ui_toggle"
        case .uiError: return "ui_error"

        case .aircraftOrdered: return "aircraft_ordered"
        case .aircraftDelivered: return "aircraft_delivered"
        case .aircraftSold: return "aircraft_sold"
        case .leaseReturned: return "lease_returned"
        case .aircraftAssigned: return "aircraft_assigned"
        case .aircraftUnassigned: return "aircraft_unassigned"
        case .maintenanceStarted: return "maintenance_started"
        case .maintenanceCompleted: return "maintenance_completed"

        case .routeOpened: return "route_opened"
        case .routeClosed: return "route_closed"

        case .flightDeparted: return "flight_departed"
        case .flightArrived: return "flight_arrived"
        case .flightDelayed: return "flight_delayed"
        case .flightCancelled: return "flight_cancelled"
        case .departureFlurry: return "departure_flurry"
        case .arrivalFlurry: return "arrival_flurry"
        case .disruptionFlurry: return "disruption_flurry"

        case .firstRoute: return "first_route"
        case .firstDeparture: return "first_departure"
        case .firstArrival: return "first_arrival"
        case .firstRevenue: return "first_revenue"

        case .monthClosedProfit: return "month_profit"
        case .monthClosedLoss: return "month_loss"
        case .loanTaken: return "loan_taken"
        case .loanRepaid: return "loan_repaid"

        case .worldEventForecast: return "world_forecast"
        case .stormStarted: return "world_storm"
        case .strikeStarted: return "world_strike"
        case .fuelShockStarted: return "world_fuel_shock"
        case .boomStarted: return "world_boom"
        case .airportClosed: return "world_airport_closed"
        case .worldEventEnded: return "world_event_ended"

        case .missionOffered: return "mission_offered"
        case .missionCompleted: return "mission_completed"
        case .missionExpired: return "mission_expired"
        case .milestoneReached: return "milestone"
        case .achievementUnlocked: return "achievement"
        case .capabilityCompleted: return "capability_completed"
        case .eraAdvanced: return "era_advanced"

        case .administrationEntered: return "administration"
        case .collapse: return "collapse"
        case .gameOver: return "game_over"

        case .ambienceOperations: return "ambience_operations"
        case .ambienceWorld: return "ambience_world"
        }
    }

    /// True for the two cues that play as a continuous bed rather than once.
    public var isLoop: Bool {
        switch self {
        case .ambienceOperations, .ambienceWorld: return true
        default: return false
        }
    }

    /// Shortest real-time gap, in seconds, between two plays of this cue.
    ///
    /// Zero means "as often as it happens" — correct for a cue the player
    /// caused by touching something, where suppression would read as a
    /// dropped input. Operational cues carry a real gap because the
    /// simulation can emit dozens of them in one pump.
    public var cooldown: Double {
        switch priority {
        case .critical: return 0
        case .ambient: return 0
        default: break
        }
        switch category {
        case .ui: return 0.05
        case .operations: return 2.5
        case .routes, .finance, .progression: return 0.5
        case .world: return 4
        case .critical: return 0
        }
    }

    /// True for the handful of cues that exist to be heard exactly once in a
    /// campaign. They ignore cooldown and can never be dropped by the batch
    /// cap.
    public var isMilestone: Bool {
        switch self {
        case .firstRoute, .firstDeparture, .firstArrival, .firstRevenue:
            return true
        default:
            return false
        }
    }
}

// MARK: - Speed policy

extension SimSpeed {
    /// How many *individual* operational cues a single batch may produce at
    /// this speed. Beyond it, flights are heard as one aggregate.
    ///
    /// At 16x a busy network can depart twenty aircraft inside one quarter-
    /// second pump. Playing twenty sounds is not information, it is noise, so
    /// the individual cues are suppressed entirely and the flurry carries the
    /// meaning (docs/AUDIO_ARCHITECTURE.md §5).
    public var individualFlightCueBudget: Int {
        switch self {
        case .paused: return 0
        case .x1: return 3
        case .x4: return 1
        case .x16: return 0
        }
    }

    /// Total cues allowed out of one batch, whatever their kind. Milestone
    /// and critical cues are counted but never cut.
    public var cueBudget: Int {
        switch self {
        case .paused: return 4
        case .x1: return 4
        case .x4: return 3
        case .x16: return 2
        }
    }
}

// MARK: - The director

/// Turns a batch of simulation events into the sounds worth playing.
///
/// Held by the presentation layer, one per game. Constructing it from a state
/// establishes the baseline: everything the airline has *already* done is
/// treated as heard, which is what stops a loaded save from replaying its own
/// history (docs/AUDIO_ARCHITECTURE.md §6, tasks/BUGS.md BUG-013).
public struct AudioDirector: Sendable {

    /// The once-per-campaign moments, seeded from persisted state rather than
    /// remembered by the UI — so they are correct across save, load, quit and
    /// a second game in the same app run.
    public struct Milestones: Equatable, Sendable {
        public var hasRoute: Bool
        public var hasDeparted: Bool
        public var hasArrived: Bool
        public var hasEarned: Bool

        /// True once every first time has happened. The director uses this to
        /// stop looking: after the opening hour of a campaign these can never
        /// change again, and the check walks every route and every live
        /// flight — four times a second, for the rest of the game.
        public var allSeen: Bool {
            hasRoute && hasDeparted && hasArrived && hasEarned
        }

        public init(hasRoute: Bool = false, hasDeparted: Bool = false,
                    hasArrived: Bool = false, hasEarned: Bool = false) {
            self.hasRoute = hasRoute
            self.hasDeparted = hasDeparted
            self.hasArrived = hasArrived
            self.hasEarned = hasEarned
        }

        /// Reads the airline's own books. `RouteStats` is persisted, so a
        /// save carries the answers with it.
        public init(state: GameState) {
            guard let player = state.playerAirline else {
                self.init()
                return
            }
            let routes = state.routes(of: player.id)
            let anyAirborne = state.flights.values.contains { flight in
                guard case .enRoute = flight.phase else { return false }
                return state.routes[flight.route]?.airline == player.id
            }
            self.init(
                hasRoute: !routes.isEmpty,
                hasDeparted: anyAirborne
                    || routes.contains { $0.stats.flightsCompleted > 0 },
                hasArrived: routes.contains { $0.stats.flightsCompleted > 0 },
                hasEarned: routes.contains { $0.stats.passengersCarried > 0 })
        }
    }

    public private(set) var milestones: Milestones
    /// Monotonic time of the last play, per cue.
    private var lastPlayed: [AudioCue: Double] = [:]

    public init(milestones: Milestones) {
        self.milestones = milestones
    }

    public init(state: GameState) {
        self.init(milestones: Milestones(state: state))
    }

    /// The sounds this batch of events deserves.
    ///
    /// - Parameters:
    ///   - events: everything the session published since the last call.
    ///   - state: the world those events produced, for the milestone checks.
    ///   - speed: the clock the player set, which decides how much detail
    ///     survives.
    ///   - now: monotonic seconds. Supplied rather than read so cooldowns are
    ///     exact under test and the director stays pure.
    ///
    /// Returns cues in descending priority, deduplicated, rate-limited and
    /// capped. Never returns the same cue twice.
    public mutating func cues(for events: [SimEvent], state: GameState,
                              speed: SimSpeed, now: Double) -> [AudioCue] {
        // 1. Map. One pass, counting the flight events so they can be
        //    aggregated rather than played one at a time.
        var candidates: [AudioCue] = []
        var departures = 0, arrivals = 0, disruptions = 0
        for event in events {
            switch event.kind {
            case .flightDeparted: departures += 1
            case .flightArrived: arrivals += 1
            case .flightCancelled: disruptions += 1
            default: break
            }
            if let cue = AudioCue.for(event.kind) { candidates.append(cue) }
        }

        // 2. The first times, from the world rather than from the events —
        //    so they are still right if the event that caused them fell out
        //    of a full ring, and still silent on a loaded save.
        candidates.append(contentsOf: newMilestoneCues(state: state))

        // 3. Aggregate. A flurry replaces the individuals it summarises,
        //    which is why this runs before the budget rather than after: at
        //    16x the individuals are gone and the flurry is the whole story.
        candidates = aggregate(candidates, departures: departures,
                               arrivals: arrivals, disruptions: disruptions,
                               speed: speed)

        // 4. Dedup, keeping the first occurrence.
        var seen = Set<AudioCue>()
        candidates = candidates.filter { seen.insert($0).inserted }

        // 5. Rate-limit. A cue still inside its cooldown is dropped, unless
        //    it is critical or a once-ever milestone.
        candidates = candidates.filter { cue in
            if cue.priority == .critical || cue.isMilestone { return true }
            guard let last = lastPlayed[cue] else { return true }
            return now - last >= cue.cooldown
        }

        // 6. Rank and cap. Sorting is by priority then by the cue's own name,
        //    so a tie is broken the same way every time and the same batch
        //    always sounds the same.
        candidates.sort { lhs, rhs in
            lhs.priority != rhs.priority
                ? lhs.priority > rhs.priority
                : lhs.rawValue < rhs.rawValue
        }
        var budget = speed.cueBudget
        var chosen: [AudioCue] = []
        for cue in candidates {
            // Critical and milestone cues are never the ones that get cut.
            // Losing "your first flight has landed" to a busy quarter-second
            // is losing the moment the game is built around.
            if cue.priority == .critical || cue.isMilestone {
                chosen.append(cue)
                continue
            }
            guard budget > 0 else { continue }
            budget -= 1
            chosen.append(cue)
        }

        for cue in chosen { lastPlayed[cue] = now }
        return chosen
    }

    /// Milestone cues become due the moment the world says they happened,
    /// and each is marked so it can never become due again.
    private mutating func newMilestoneCues(state: GameState) -> [AudioCue] {
        // The overwhelmingly common case, and the whole reason for `allSeen`:
        // a campaign spends its first twenty minutes here and the next twenty
        // hours past it.
        guard !milestones.allSeen else { return [] }
        let now = Milestones(state: state)
        var cues: [AudioCue] = []
        if now.hasRoute, !milestones.hasRoute { cues.append(.firstRoute) }
        if now.hasDeparted, !milestones.hasDeparted { cues.append(.firstDeparture) }
        if now.hasArrived, !milestones.hasArrived { cues.append(.firstArrival) }
        if now.hasEarned, !milestones.hasEarned { cues.append(.firstRevenue) }
        // Latch forward only. A route closed back to zero must not re-arm
        // "your first route", which would make the sound a lie the second
        // time anyone heard it.
        milestones.hasRoute = milestones.hasRoute || now.hasRoute
        milestones.hasDeparted = milestones.hasDeparted || now.hasDeparted
        milestones.hasArrived = milestones.hasArrived || now.hasArrived
        milestones.hasEarned = milestones.hasEarned || now.hasEarned
        return cues
    }

    /// Replaces repetitive flight cues with a single summary once there are
    /// more of them than the speed allows to be heard individually.
    private func aggregate(_ cues: [AudioCue], departures: Int, arrivals: Int,
                           disruptions: Int, speed: SimSpeed) -> [AudioCue] {
        let budget = speed.individualFlightCueBudget
        var out = cues
        func collapse(_ individual: AudioCue, _ flurry: AudioCue, count: Int) {
            guard count > budget else { return }
            out.removeAll { $0 == individual }
            out.append(flurry)
        }
        collapse(.flightDeparted, .departureFlurry, count: departures)
        collapse(.flightArrived, .arrivalFlurry, count: arrivals)
        collapse(.flightCancelled, .disruptionFlurry, count: disruptions)
        return out
    }
}

// MARK: - Event mapping

extension AudioCue {
    /// The cue a simulation event asks for, or nil when it asks for silence.
    ///
    /// Most events map to nothing, and that is the design: `dayStarted` fires
    /// every game day, `commandApplied` fires for every command, and a game
    /// that pinged at each would be unplayable. Silence is a tool
    /// (docs/AUDIO_ARCHITECTURE.md §2).
    ///
    /// A named factory rather than `init?(_:)`: an unlabelled initialiser on a
    /// `String`-raw-valued enum is ambiguous against the synthesised
    /// `init?(rawValue:)`, and the compiler resolves it to the wrong one.
    public static func `for`(_ kind: SimEventKind) -> AudioCue? {
        switch kind {
        case .aircraftOrdered: return .aircraftOrdered
        case .aircraftDelivered: return .aircraftDelivered
        case .aircraftSold: return .aircraftSold
        case .leaseReturned: return .leaseReturned
        case .maintenanceStarted: return .maintenanceStarted
        case .maintenanceCompleted: return .maintenanceCompleted

        case .routeOpened: return .routeOpened
        case .routeClosed: return .routeClosed
        case .aircraftAssigned: return .aircraftAssigned
        case .aircraftUnassigned: return .aircraftUnassigned

        case .flightDeparted: return .flightDeparted
        case .flightArrived: return .flightArrived
        case .flightDelayed: return .flightDelayed
        case .flightCancelled: return .flightCancelled

        case .loanTaken: return .loanTaken
        case .loanRepaidEarly: return .loanRepaid
        case .statementClosed(_, _, _, let netProfit):
            return netProfit.isNegative ? .monthClosedLoss : .monthClosedProfit
        case .airlineEnteredAdministration: return .administrationEntered
        case .airlineCollapsed: return .collapse

        case .worldEventForecast: return .worldEventForecast
        case .worldEventStarted(_, let kind):
            switch kind {
            case .storm: return .stormStarted
            case .strike: return .strikeStarted
            case .fuelShock: return .fuelShockStarted
            case .tourismBoom: return .boomStarted
            case .airportClosure: return .airportClosed
            }
        case .worldEventEnded: return .worldEventEnded

        case .eraAdvanced: return .eraAdvanced
        case .milestoneReached: return .milestoneReached
        case .achievementUnlocked: return .achievementUnlocked
        case .capabilityCompleted: return .capabilityCompleted
        case .missionOffered: return .missionOffered
        case .missionCompleted: return .missionCompleted
        case .missionExpired: return .missionExpired
        case .gameOver: return .gameOver

        // Deliberately silent: calendar ticks, command receipts, and the
        // founding of the airline (the app plays its own confirmation there,
        // synchronised with the screen the player is looking at).
        case .dayStarted, .weekStarted, .monthStarted, .seasonChanged,
             .wakeFired, .commandApplied, .airlineFounded:
            return nil
        }
    }
}

// MARK: - Haptics

public enum HapticStyle: String, Equatable, Sendable, CaseIterable {
    case selection
    case light
    case medium
    case heavy
    case success
    case warning
    case error
}

extension AudioCue {
    /// What this cue should feel like, or nil for the great majority that
    /// should feel like nothing at all.
    public var haptic: HapticStyle? {
        switch self {
        // Interface: the player's own finger, so the lightest possible
        // acknowledgement and nothing more.
        case .uiSelect, .uiNavigate, .uiToggle:
            return .selection
        case .uiSheetOpen, .uiSheetClose:
            return nil          // The sheet's own movement is the feedback.
        case .uiConfirm:
            return .light
        case .uiCancel:
            return nil
        case .uiError:
            return .error

        // Commitments. A route and an aircraft are the two things a player
        // spends real money and real time on; they get weight.
        case .routeOpened:
            return .medium
        case .aircraftDelivered:
            return .heavy
        case .aircraftOrdered, .aircraftAssigned:
            return .medium
        case .aircraftSold, .leaseReturned, .routeClosed, .aircraftUnassigned:
            return .light

        // The first times. The whole point of the opening hour.
        case .firstRoute, .firstDeparture:
            return .medium
        case .firstArrival, .firstRevenue:
            return .success

        // Progression.
        case .missionCompleted, .milestoneReached, .achievementUnlocked,
             .capabilityCompleted:
            return .success
        case .eraAdvanced:
            return .heavy

        // Trouble the player must not scroll past.
        case .flightCancelled, .disruptionFlurry, .monthClosedLoss,
             .stormStarted, .strikeStarted, .fuelShockStarted, .airportClosed:
            return .warning
        case .administrationEntered, .collapse, .gameOver:
            return .error

        // Everything else — every routine flight, every forecast, every
        // month that merely went fine — is silent to the hand on purpose.
        default:
            return nil
        }
    }
}

