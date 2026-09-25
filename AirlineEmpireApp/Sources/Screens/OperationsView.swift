import SwiftUI
import AirlineEmpireCore

/// World & operations: live events, competitors, progression — the "what is
/// happening around me" screen group.
///
/// Settings left this hub for the Home toolbar: saving and quitting the game
/// do not belong behind a lightning bolt, and while they lived here they were
/// also behind the system *More* list on iPhone (UIUX_FORENSIC_AUDIT UI-001).
struct OperationsView: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        NavigationStack {
            // A hub, not a table of contents. Each destination says what is
            // inside it *and* what is currently going on in there.
            ScrollView {
                VStack(spacing: AETheme.spacingM) {
                    AEPageIntro(title: "A world of opportunity", subtitle: "Read the conditions. Know your rivals. Find your next opening.",
                                icon: "globe.europe.africa.fill")
                    hubLink(title: "World events", icon: "bolt.horizontal.fill",
                            subtitle: "Storms, fuel shocks and what they are doing to your network",
                            badge: eventBadge, live: eventLive) {
                        WorldEventsView()
                    }
                    hubLink(title: "Competitors", icon: "person.2.fill",
                            subtitle: "Who else is flying, and how they are doing",
                            badge: competitorBadge, live: competitorLive) {
                        CompetitorsView()
                    }
                    hubLink(title: "Progression", icon: "chart.line.uptrend.xyaxis",
                            subtitle: "Your era, capability programs and missions",
                            badge: progressionBadge) {
                        ProgressionView()
                    }
                    hubLink(title: "Airports", icon: "building.2.fill",
                            subtitle: "Every market in the world, with its demand and its slots",
                            badge: nil) {
                        AirportBrowserView()
                    }
                    conditions
                }
                .aePageInsets()
                // A reading width on iPad, like the other management screens.
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
            }
            .aeScreenBackground()
            .navigationTitle("World")
            .navigationBarTitleDisplayMode(.inline)
            .aeTimeToolbar()
        }
    }

    /// The two world figures that were only ever on Home.
    ///
    /// Four navigation rows left roughly half the screen empty (AE-033 audit
    /// §6.6), and fuel and the economic index are *world* facts — the two
    /// numbers moving underneath every route in the game — that a player had
    /// to go to their own dashboard to read. Putting them at the foot of the
    /// hub fills the space with the thing the screen is about rather than
    /// with decoration. Home keeps its copies: they belong in both places for
    /// different reasons, one as world weather and one as a cost you carry.
    @ViewBuilder
    private var conditions: some View {
        // The controller's cached model, not a fresh `dashboardModel()` —
        // that walks the routes, fleet and asset valuation on every pass.
        if let dashboard = controller.dashboard {
            AEMetricStrip([
                AEMetric("fuel per ton",
                         Format.money(dashboard.fuelPricePerTon)),
                AEMetric("economy",
                         Format.decimal(dashboard.economicIndex, places: 2),
                         tint: dashboard.economicIndex >= 1
                             ? AETheme.positive : AETheme.caution),
            ])
            .accessibilityElement(children: .contain)
            .accessibilityLabel("World conditions")
        }
    }

    /// Live state on the card, so the hub answers "is anything happening?"
    /// without opening all four.
    private var eventBadge: (String, Color)? {
        guard let snapshot = controller.snapshot else { return nil }
        let active = snapshot.world.activeEvents.filter { $0.hasStarted }.count
        guard active > 0 else { return nil }
        return ("\(active) active", AETheme.caution)
    }

    /// The current event by name, not just a count — the hub's badge said
    /// "2 active" and the AE-033 audit's EXP-05 finding was exactly that the
    /// cards describe their category instead of the world (a live fact per
    /// card, derived from real state, never invented).
    private var eventLive: String? {
        guard let snapshot = controller.snapshot,
              let event = snapshot.world.activeEvents.first(where: \.hasStarted)
        else { return nil }
        return "Now: \(Vocab.worldEvent(event.kind, state: snapshot))"
    }

    /// What the competition is doing to *this* airline, not merely who is
    /// biggest: the same headline Home carries, else the rival that touches
    /// the player's network most (AE-037; the AE-033 audit's EXP-05 asked
    /// for one live fact per card, and "biggest rival, 1 route" was live
    /// but never about the player).
    private var competitorLive: String? {
        guard let summary = controller.competitionSummary else { return nil }
        if let headline = summary.headline { return Vocab.headline(headline) }
        guard let biggest = summary.biggestRival, biggest.routes > 0 else { return nil }
        if biggest.sharedAirports > 0 {
            return "\(biggest.name) shares \(biggest.sharedAirports) airport\(biggest.sharedAirports == 1 ? "" : "s") with you · \(biggest.routes) route\(biggest.routes == 1 ? "" : "s")"
        }
        return "Biggest rival: \(biggest.name), \(biggest.routes) route\(biggest.routes == 1 ? "" : "s") — nowhere near you"
    }

    private var competitorBadge: (String, Color)? {
        guard let summary = controller.competitionSummary else { return nil }
        if summary.trailingRoutes > 0 {
            return ("losing \(summary.trailingRoutes)", AETheme.negative)
        }
        if summary.contestedRoutes > 0 {
            return ("\(summary.contestedRoutes) contested", AETheme.caution)
        }
        let alive = summary.rivals.filter { $0.status == .active }.count
        return ("\(alive) flying", AETheme.mutedText)
    }

    private var progressionBadge: (String, Color)? {
        // Cached per snapshot by the controller, as the Progression screen
        // itself now reads it.
        guard let model = controller.progressionModel else { return nil }
        if let mission = model.missions.first {
            return ("mission · \(Format.days(mission.daysRemaining)) left", AETheme.accent)
        }
        guard model.nextEra != nil else { return ("Empire", AETheme.positive) }
        return ("\(Format.percent(model.nextEraProgress)) to next era", AETheme.mutedText)
    }
}

private extension OperationsView {
    /// One destination in the hub: an icon that says which, a subtitle that
    /// says why, a badge that says what is happening, and a whole-card tap
    /// target.
    func hubLink<Destination: View>(
        title: String,
        icon: String,
        subtitle: String,
        badge: (String, Color)?,
        live: String? = nil,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: AETheme.spacingM) {
                AEClayIcon(systemName: icon, tint: badge?.1 ?? AETheme.accent, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    AEChipRow {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let badge {
                            AEBadge(text: badge.0, color: badge.1)
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let live {
                        Text(live)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AETheme.accent)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AETheme.mutedText)
                    .accessibilityHidden(true)
            }
            .padding(AETheme.spacingM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(AETheme.cardShape)
            .aeClay(in: AETheme.cardShape)
        }
        .buttonStyle(.aePress)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// World events, with the only thing that turns an event into a decision:
/// which of *your* routes it touches (docs/GAME_DESIGN.md §4.12 — "every event
/// creates a decision, never a pure toll").
struct WorldEventsView: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        ScrollView {
            VStack(spacing: AETheme.spacingM) {
                if let snapshot = controller.snapshot, let catalog = controller.catalog {
                    let active = snapshot.world.activeEvents
                    let onNow = active.filter(\.hasStarted)
                    let forecast = active.filter { !$0.hasStarted }
                    if active.isEmpty {
                        EmptyStateView(icon: "sun.max", title: "Calm skies",
                                       message: "No storms, no shocks, no closures. A good time to expand.")
                    } else {
                        // What it means for *this* airline first, then the
                        // disruption split into what is here and what is
                        // coming — the two are acted on differently.
                        exposureCard(onNow: onNow, forecast: forecast,
                                     snapshot: snapshot, catalog: catalog)
                        if !onNow.isEmpty {
                            sectionHeader("Happening now", "exclamationmark.triangle",
                                          id: "ae-events-now")
                            ForEach(onNow, id: \.id) { event in
                                eventCard(event, snapshot: snapshot, catalog: catalog)
                            }
                        }
                        if !forecast.isEmpty {
                            sectionHeader("Forecast", "clock", id: "ae-events-forecast")
                            ForEach(forecast, id: \.id) { event in
                                eventCard(event, snapshot: snapshot, catalog: catalog)
                            }
                        }
                    }
                } else {
                    LoadingState(message: "Reading the weather")
                        .frame(minHeight: 240)
                }
            }
            .aePageInsets()
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .aeScreenBackground()
        .navigationTitle("World events")
        .navigationBarTitleDisplayMode(.inline)
        .aeTimeToolbar()
        .navigationDestination(for: RouteID.self) { RouteDetailView(routeID: $0) }
        // Route Detail links onward to its assigned aircraft, so a stack that
        // can push it must be able to push that too — otherwise the link is
        // silently inert two screens in (tasks/BUGS.md BUG-030).
        .navigationDestination(for: AircraftID.self) {
            AircraftDetailView(aircraftID: $0)
        }
    }

    private func sectionHeader(_ title: String, _ icon: String, id: String) -> some View {
        AESectionHeader(text: title, systemImage: icon)
            .accessibilityIdentifier(id)
    }

    /// The player's real exposure across every live event: which of their
    /// routes are in a path and how much flying that is. Counts, not
    /// estimates — no disruption and no saving is claimed (the event's own
    /// effect line says what the simulation does with it).
    private func exposureCard(onNow: [WorldEvent], forecast: [WorldEvent],
                              snapshot: GameState, catalog: ContentCatalog) -> some View {
        let routes = affectedRoutes(onNow + forecast, snapshot: snapshot, catalog: catalog)
        let roundTrips = routes.reduce(0) { $0 + $1.dailyRoundTrips }
        return AEPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Your exposure",
                                systemImage: "exclamationmark.circle")
                if routes.isEmpty {
                    Label("None of your routes are in a path.", systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.positive)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(routes.count) of your routes \(routes.count == 1 ? "is" : "are") in a path — \(roundTrips) round \(roundTrips == 1 ? "trip" : "trips") a day.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(routes, id: \.id) { route in
                        NavigationLink(value: route.id) {
                            HStack {
                                Text(Vocab.pair(route.origin, route.destination))
                                    .font(.subheadline)
                                Spacer()
                                Text("\(route.dailyRoundTrips)×/day")
                                    .font(.caption).monospacedDigit()
                                    .foregroundStyle(AETheme.mutedText)
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundStyle(AETheme.mutedText)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.aePress)
                        .accessibilityIdentifier("ae-event-exposed-route")
                    }
                }
            }
        }
        // `.contain` keeps each exposed route's own identifier queryable;
        // without it the panel's identifier overwrites every child's and the
        // route links become unaddressable (run 35136273799).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ae-events-exposure")
    }

    /// The player's routes across several events, each counted once — a route
    /// in two storms is one route with one schedule.
    private func affectedRoutes(_ events: [WorldEvent], snapshot: GameState,
                                catalog: ContentCatalog) -> [Route] {
        var byID: [RouteID: Route] = [:]
        for event in events {
            for route in affectedRoutes(event, snapshot: snapshot, catalog: catalog) {
                byID[route.id] = route
            }
        }
        return byID.values.sorted { $0.id < $1.id }
    }

    private func eventCard(_ event: WorldEvent, snapshot: GameState,
                           catalog: ContentCatalog) -> some View {
        let affected = affectedRoutes(event, snapshot: snapshot, catalog: catalog)
        return AECard(tint: event.hasStarted && !affected.isEmpty
                      ? AETheme.caution.opacity(0.16) : nil) {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                HStack(spacing: AETheme.spacingS) {
                    Image(systemName: Vocab.worldEventIcon(event.kind))
                        .font(.title3)
                        .foregroundStyle(event.hasStarted ? AETheme.caution : AETheme.mutedText)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Vocab.worldEvent(event.kind, state: snapshot))
                            .font(.headline)
                        Text(timing(event, snapshot: snapshot))
                            .font(.caption)
                            .foregroundStyle(AETheme.mutedText)
                    }
                    Spacer(minLength: 0)
                    if !event.hasStarted {
                        AEBadge(text: "forecast", color: AETheme.caution, icon: "clock")
                    }
                }
                // How hard it bites. `severity` was carried on every event and
                // shown nowhere, so a mild storm and a severe one read
                // identically (MASTER PROMPT 4 §16).
                AEBadge(text: Vocab.severity(event.severity),
                        color: Vocab.severityColor(event.severity),
                        icon: "gauge.with.dots.needle.bottom.50percent")
                Text(Vocab.worldEventEffect(event.kind))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                if affected.isEmpty {
                    Label("None of your routes touch this.",
                          systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.positive)
                } else {
                    let roundTrips = affected.reduce(0) { $0 + $1.dailyRoundTrips }
                    Text("\(affected.count) of your routes \(affected.count == 1 ? "is" : "are") in its path — \(roundTrips) round \(roundTrips == 1 ? "trip" : "trips") a day:")
                        .font(.subheadline.weight(.medium))
                    ForEach(affected, id: \.id) { route in
                        NavigationLink(value: route.id) {
                            HStack {
                                Text("\(route.origin.raw) – \(route.destination.raw)")
                                    .font(.subheadline)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(AETheme.mutedText)
                            }
                            .frame(minHeight: 44)
                        }
                    }
                }
            }
        }
    }

    /// Which of the player's routes this event actually reaches.
    private func affectedRoutes(_ event: WorldEvent, snapshot: GameState,
                                catalog: ContentCatalog) -> [Route] {
        guard let player = snapshot.playerAirline else { return [] }
        let routes = snapshot.routes(of: player.id)
        switch event.kind {
        case .fuelShock:
            return routes   // every flight burns fuel
        case .storm(let region), .tourismBoom(let region):
            return routes.filter { MissionMath.touchesRegion($0, region, catalog: catalog) }
        case .airportClosure(let airport):
            return routes.filter { $0.origin == airport || $0.destination == airport }
        case .strike(let airline):
            return airline == player.id ? routes : []
        }
    }

    private func timing(_ event: WorldEvent, snapshot: GameState) -> String {
        let now = snapshot.clock.now
        let endDate = GameCalendar.date(at: event.endsAt, startYear: snapshot.meta.startYear)
        if !event.hasStarted {
            let days = Int(max(0, event.beginsAt.rawMinutes - now.rawMinutes)
                / GameCalendar.minutesPerDay)
            return days == 0 ? "Starts today" : "Starts in \(Format.days(days))"
        }
        let days = Int(max(0, event.endsAt.rawMinutes - now.rawMinutes)
            / GameCalendar.minutesPerDay)
        return days == 0 ? "Ends today" : "Until \(Format.longDate(endDate)) · \(Format.days(days)) left"
    }
}

/// Rivals as characters rather than as a table: what kind of airline each one
/// is, how it plays, and — the reason this screen exists — where it meets
/// you: the pairs you both fly, whether you are winning them, and what it
/// did near you this month (AE-037). Ordered by how much of your network
/// each one touches, not alphabetically.
struct CompetitorsView: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        ScrollView {
            VStack(spacing: AETheme.spacingM) {
                if let snapshot = controller.snapshot,
                   let summary = controller.competitionSummary {
                    if summary.rivals.isEmpty {
                        EmptyStateView(icon: "person.2.slash", title: "No rivals",
                                       message: "This world has no competing airlines.")
                    } else {
                        // The player's own fights and the news near them lead;
                        // the cast of rivals follows, as characters.
                        overview(summary)
                        whereYouAreFighting(summary)
                        rivalMoves(summary, snapshot: snapshot)
                        archetypeLegend(summary)
                        ForEach(summary.rivals, id: \.airline) { rival in
                            rivalCard(rival)
                        }
                    }
                } else {
                    LoadingState(message: "Scouting the competition")
                        .frame(minHeight: 240)
                }
            }
            .aePageInsets()
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .aeScreenBackground()
        .navigationTitle("Competitors")
        .navigationBarTitleDisplayMode(.inline)
        .aeTimeToolbar()
        .navigationDestination(for: RouteID.self) { RouteDetailView(routeID: $0) }
        .navigationDestination(for: AircraftID.self) { AircraftDetailView(aircraftID: $0) }
    }

    /// The network's competitive position in one strip.
    private func overview(_ summary: CompetitionSummary) -> some View {
        AEMetricStrip([
            AEMetric("contested routes", "\(summary.contestedRoutes)",
                     tint: summary.contestedRoutes > 0 ? AETheme.caution : nil,
                     emphasised: true),
            AEMetric("leading", "\(summary.leadingRoutes)",
                     tint: summary.leadingRoutes > 0 ? AETheme.positive : nil),
            AEMetric("losing", "\(summary.trailingRoutes)",
                     tint: summary.trailingRoutes > 0 ? AETheme.negative : nil),
            AEMetric("rivals flying", "\(summary.rivals.filter { $0.status == .active }.count)"),
        ])
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Competitive position")
    }

    /// Every contested pair as a comparison rather than a sentence: the
    /// standing, a bar of today's passengers by carrier, the strongest rival
    /// beside the player, what separates them, and — when the player is
    /// behind — the response the simulation's own arithmetic supports.
    ///
    /// All of it is `MarketCompetition`: the demand engine's split from this
    /// morning, its own attractiveness terms for the edge, and the
    /// scheduler's spare rotations for the response. Nothing estimates what a
    /// rival will do next.
    @ViewBuilder
    private func whereYouAreFighting(_ summary: CompetitionSummary) -> some View {
        if !summary.contested.isEmpty {
            AEPanel {
                VStack(alignment: .leading, spacing: AETheme.spacingM) {
                    AESectionHeader(text: "Where you are fighting",
                                    systemImage: "arrow.left.arrow.right")
                    Text("Share of today's passengers, after the demand engine's own split.")
                        .font(.caption).foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(summary.contested, id: \.routeID) { market in
                        contestedRow(market)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ae-contested-markets")
        }
    }

    private func contestedRow(_ market: MarketCompetition) -> some View {
        NavigationLink(value: market.routeID) {
            VStack(alignment: .leading, spacing: AETheme.spacingXS) {
                HStack(spacing: AETheme.spacingS) {
                    Text(Vocab.pair(market.origin, market.destination))
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: AETheme.spacingS)
                    Text(standingWord(market))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(standingTint(market.standing))
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundStyle(AETheme.mutedText)
                }
                shareBar(market)
                shareLabels(market)
                    .font(.caption2).monospacedDigit()
                if let edge = Vocab.edge(market) {
                    Text(edge)
                        .font(.caption2).foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let response = Vocab.competitiveResponse(market) {
                    Text(response)
                        .font(.caption2).foregroundStyle(AETheme.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.aePress)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityStanding(market))
        .accessibilityIdentifier("ae-contested-route")
    }

    /// Today's passengers by carrier: the player in the app's accent, each
    /// rival in its own livery. One glance at who is winning.
    private func shareBar(_ market: MarketCompetition) -> some View {
        let playerShare = market.playerShareToday ?? 0
        let rivals = market.rivals.map { ($0.shareToday ?? 0, Vocab.liveryColor($0.livery)) }
        let total = playerShare + rivals.reduce(0) { $0 + $1.0 }
        return GeometryReader { geometry in
            HStack(spacing: 1) {
                if total <= 0 {
                    Rectangle().fill(AETheme.surfaceRim.opacity(0.5))
                } else {
                    Rectangle().fill(AETheme.accent)
                        .frame(width: geometry.size.width * playerShare / total)
                    ForEach(Array(rivals.enumerated()), id: \.offset) { _, segment in
                        Rectangle().fill(segment.1)
                            .frame(width: geometry.size.width * segment.0 / total)
                    }
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func shareLabels(_ market: MarketCompetition) -> some View {
        if let share = market.playerShareToday {
            HStack {
                Text("You \(Format.percent(share))")
                Spacer(minLength: AETheme.spacingS)
                if let strongest = market.rivals.first, let theirShare = strongest.shareToday {
                    Text("\(strongest.name) \(Format.percent(theirShare))")
                        .foregroundStyle(AETheme.mutedText)
                }
            }
        } else {
            Text(standingWord(market))
                .foregroundStyle(AETheme.mutedText)
        }
    }

    private func accessibilityStanding(_ market: MarketCompetition) -> String {
        let base = Vocab.standing(market) ?? Vocab.pair(market.origin, market.destination)
        guard let response = Vocab.competitiveResponse(market) else { return base }
        return "\(base) \(response)"
    }

    /// The last thirty days of rival moves that touch this airline, on the
    /// player's own pairs first (Core's priority) and newest first within a
    /// rank. Each move on one of the player's routes opens it.
    @ViewBuilder
    private func rivalMoves(_ summary: CompetitionSummary, snapshot: GameState) -> some View {
        if !summary.recentMoves.isEmpty {
            AEPanel {
                VStack(alignment: .leading, spacing: AETheme.spacingS) {
                    AESectionHeader(text: "What rivals did near you",
                                    systemImage: "person.2.fill")
                    Text("The last thirty days, on your markets first.")
                        .font(.caption).foregroundStyle(AETheme.mutedText)
                    ForEach(Array(summary.recentMoves.prefix(6).enumerated()),
                            id: \.offset) { _, move in
                        moveRow(move, snapshot: snapshot)
                    }
                    if summary.recentMoves.count > 6 {
                        Text("+\(summary.recentMoves.count - 6) more in the last thirty days.")
                            .font(.caption2).foregroundStyle(AETheme.mutedText)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ae-rival-moves")
        }
    }

    @ViewBuilder
    private func moveRow(_ move: RivalMove, snapshot: GameState) -> some View {
        let label = HStack(spacing: AETheme.spacingS) {
            Image(systemName: move.kind == .entered ? "plus.circle" : "minus.circle")
                .font(.caption).foregroundStyle(moveTint(move))
                .accessibilityHidden(true)
            Text(Vocab.move(move))
                .font(.subheadline)
                .foregroundStyle(moveTint(move))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        if let route = playerRoute(for: move, snapshot: snapshot) {
            NavigationLink(value: route) {
                label.frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.aePress)
            .accessibilityIdentifier("ae-rival-move")
        } else {
            label.frame(minHeight: 44, alignment: .leading)
        }
    }

    private func moveTint(_ move: RivalMove) -> Color {
        guard move.relevance == .onPlayerMarket else { return AETheme.mutedText }
        return move.kind == .entered ? AETheme.caution : AETheme.positive
    }

    /// The player's own route on the pair a move is about, when the move is on
    /// one of their markets. An airport-level move has no route of ours.
    private func playerRoute(for move: RivalMove, snapshot: GameState) -> RouteID? {
        guard move.relevance != .atPlayerAirport,
              let player = snapshot.playerAirline?.id else { return nil }
        return snapshot.routes(of: player).first {
            $0.origin == move.origin && $0.destination == move.destination
        }?.id
    }

    private func standingWord(_ market: MarketCompetition) -> String {
        let share = market.playerShareToday.map { " · \(Format.percent($0))" } ?? ""
        switch market.standing {
        case .leading: return "leading\(share)"
        case .trailing: return "losing\(share)"
        case .even: return "even\(share)"
        case .tooEarly: return "new"
        case .alone: return ""
        }
    }

    private func standingTint(_ standing: MarketCompetition.Standing) -> Color {
        switch standing {
        case .leading: AETheme.positive
        case .trailing: AETheme.negative
        default: AETheme.mutedText
        }
    }

    /// What each kind of rival does, once, for the kinds actually present.
    ///
    /// This sentence used to sit under every rival's name, beside a badge that
    /// already named the kind — five rivals, five repetitions of four
    /// possible lines. Collapsed by default: the badge is enough to scan by,
    /// and the explanation is one tap away (AUD-04).
    @ViewBuilder
    private func archetypeLegend(_ summary: CompetitionSummary) -> some View {
        let present = AIArchetype.allCases.filter { kind in
            summary.rivals.contains { $0.archetype == kind && $0.status != .collapsed }
        }
        if !present.isEmpty {
            AECard {
                DisclosureGroup("How each kind of rival behaves") {
                    VStack(alignment: .leading, spacing: AETheme.spacingS) {
                        ForEach(present, id: \.self) { kind in
                            HStack(alignment: .firstTextBaseline, spacing: AETheme.spacingS) {
                                AEBadge(text: Vocab.archetype(kind), color: AETheme.fare)
                                Text(Vocab.archetypeDetail(kind))
                                    .font(.caption)
                                    .foregroundStyle(AETheme.mutedText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, AETheme.spacingS)
                }
                .font(.subheadline.weight(.medium))
                .tint(AETheme.mutedText)
            }
            .accessibilityIdentifier("ae-rival-legend")
        }
    }

    private func rivalCard(_ rival: RivalStanding) -> some View {
        AECard(tint: rival.marketsWherePlayerTrails > 0
                      ? AETheme.caution.opacity(0.12)
                      : rival.sharedMarkets > 0 ? AETheme.accent.opacity(0.12) : nil) {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                HStack {
                    AEClayIcon(systemName: "airplane", tint: Vocab.liveryColor(rival.livery), size: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rival.name).font(.headline)
                    }
                    Spacer(minLength: AETheme.spacingS)
                    if rival.status == .collapsed {
                        AEBadge(text: "collapsed", color: AETheme.negative,
                                icon: "xmark.octagon")
                    } else if let archetype = rival.archetype {
                        AEBadge(text: Vocab.archetype(archetype), color: AETheme.fare)
                    }
                }
                if rival.status != .collapsed {
                    HStack(spacing: AETheme.spacingS) {
                        AEBadge(text: "\(rival.fleet) aircraft", color: .secondary)
                        AEBadge(text: "\(rival.routes) \(rival.routes == 1 ? "route" : "routes")",
                                color: .secondary)
                        AEBadge(text: "rep \(Format.percent(rival.reputationScore))",
                                color: AETheme.accent)
                    }
                    if rival.sharedMarkets > 0 {
                        Label(overlapLine(rival), systemImage: "arrow.left.arrow.right")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(rival.marketsWherePlayerTrails > 0
                                             ? AETheme.negative : AETheme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if rival.routes == 0 {
                        // Run 112 photographed a rival with no aircraft and no
                        // routes described as sharing an airport with the
                        // player: its home. Grounded is the fact.
                        Text("Grounded — flying nothing at the moment.")
                            .font(.subheadline)
                            .foregroundStyle(AETheme.mutedText)
                    } else if rival.sharedAirports > 0 {
                        // Short, because it repeats: most rivals in a
                        // mid-game world share an airport and no route, and
                        // the full sentence under each one was the prose the
                        // audit flagged (AUD-04). What it means is in the
                        // overview above.
                        Text("Shares \(rival.sharedAirports) airport\(rival.sharedAirports == 1 ? "" : "s") · no shared routes")
                            .font(.subheadline)
                            .foregroundStyle(AETheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No overlap with your network")
                            .font(.subheadline)
                            .foregroundStyle(AETheme.mutedText)
                    }
                    if rival.marketsEnteredRecently > 0 || rival.marketsLeftRecently > 0 {
                        Text(growthLine(rival))
                            .font(.caption)
                            .foregroundStyle(AETheme.mutedText)
                    }
                } else {
                    Text("Their routes and slots are back on the market.")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.mutedText)
                }
                // What they did near you lives above, in one prioritised list:
                // per-card copies of the same moves made the news hard to scan
                // and repeated it once per rival.
            }
        }
        .accessibilityIdentifier("ae-rival-card")
    }

    private func overlapLine(_ rival: RivalStanding) -> String {
        let markets = "\(rival.sharedMarkets) market\(rival.sharedMarkets == 1 ? "" : "s")"
        if rival.marketsWherePlayerTrails > 0 {
            return rival.marketsWherePlayerTrails == rival.sharedMarkets
                ? "You compete on \(markets) and are losing \(rival.sharedMarkets == 1 ? "it" : "all of them")."
                : "You compete on \(markets) and are losing \(rival.marketsWherePlayerTrails)."
        }
        return "You compete on \(markets)."
    }

    private func growthLine(_ rival: RivalStanding) -> String {
        var parts: [String] = []
        if rival.marketsEnteredRecently > 0 {
            parts.append("opened \(rival.marketsEnteredRecently) route\(rival.marketsEnteredRecently == 1 ? "" : "s")")
        }
        if rival.marketsLeftRecently > 0 {
            parts.append("dropped \(rival.marketsLeftRecently)")
        }
        return "This month: " + parts.joined(separator: ", ") + "."
    }
}

/// What "Economy 1.03" means — the drill-down behind an unlabelled index.
struct EconomyDetailView: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        ScrollView {
            VStack(spacing: AETheme.spacingM) {
                if let snapshot = controller.snapshot {
                    AECard {
                        VStack(alignment: .leading, spacing: AETheme.spacingS) {
                            AESectionHeader(text: "The world economy",
                                            systemImage: "chart.line.uptrend.xyaxis")
                            Text(Format.decimal(snapshot.world.economicIndex, places: 2))
                                .font(.largeTitle.weight(.semibold))
                                .monospacedDigit()
                            Text(economyDescription(snapshot.world.economicIndex))
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("1.00 is a normal year. The index runs a slow multi-year cycle and moves business demand and loan rates with it.")
                                .font(.caption)
                                .foregroundStyle(AETheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                            Divider()
                            HStack {
                                Text("Heading toward").font(.subheadline)
                                Spacer()
                                Text(Format.decimal(snapshot.world.economicCycleTarget, places: 2))
                                    .monospacedDigit()
                                    .font(.subheadline)
                            }
                            Text(snapshot.world.economicCycleTarget > snapshot.world.economicIndex
                                 ? "The cycle is turning up. Cheap aircraft and weak rivals are about to get more expensive."
                                 : "The cycle is turning down. Leverage taken now will be repaid in a thinner market.")
                                .font(.caption)
                                .foregroundStyle(AETheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    AEPanel {
                        VStack(alignment: .leading, spacing: AETheme.spacingS) {
                            AESectionHeader(text: "Fuel", systemImage: "fuelpump")
                            HStack {
                                Text("Price per tonne").font(.subheadline)
                                Spacer()
                                Text(Format.money(snapshot.world.fuelPricePerTon))
                                    .font(.subheadline).monospacedDigit()
                            }
                            Text("Fuel is the volatile line in every route's costs. A fuel-hedging program caps what a shock can do to you.")
                                .font(.caption)
                                .foregroundStyle(AETheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    LoadingState(message: "Reading the market")
                        .frame(minHeight: 240)
                }
            }
            .aePageInsets()
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .aeScreenBackground()
        .navigationTitle("Economy")
        .navigationBarTitleDisplayMode(.inline)
        .aeTimeToolbar()
    }

    private func economyDescription(_ index: Double) -> String {
        switch index {
        case ..<0.9: "A downturn. Business travel is thin and everyone is discounting."
        case 0.9..<0.98: "Soft. Demand is below a normal year."
        case 0.98..<1.02: "A normal year."
        case 1.02...1.1: "Strong. Business demand is above trend."
        default: "A boom. Demand is running well ahead of a normal year."
        }
    }
}

/// Settings, at last: the app previously had none — no sound, no haptics, no
/// auto-pause (which `docs/CORE_LOOP.md` §2 specifies as settable), and no
/// confirmations toggle (UIUX_FORENSIC_AUDIT UI-023).
struct SettingsView: View {
    @Environment(GameController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @State private var exportDocument: CampaignDocument?
    @State private var showingExport = false
    @State private var exportInProgress = false
    @State private var exportFailure: String?

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    var body: some View {
        @Bindable var preferences = controller.preferences
        return List {
            ProSection()
            GameCenterSection()

            Section("Playing") {
                Toggle("Pause when money runs short", isOn: $preferences.autoPauseOnDanger)
                Text("Fast-forward stops itself when your airline drops below the overdraft floor, so a collapse never happens while you are looking away.")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
                Toggle("Confirm destructive actions", isOn: $preferences.confirmDestructive)
                // Every control that reads the setting, not just the three
                // that are strictly destructive: `ConfirmableButton` and the
                // aircraft market's commit both skip their question when off.
                Text("Asks first before aircraft purchases, leases, sales and returns, route closures, loan payoffs, new programmes, contracts and rescue offers. Off, they act on the first tap.")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
            }

            Section("Sound") {
                Toggle("Mute everything", isOn: $preferences.muteAll)
                if !preferences.muteAll {
                    LabeledContent("Overall") {
                        Slider(value: $preferences.masterVolume, in: 0...1)
                            .frame(maxWidth: 150)
                            .accessibilityLabel("Overall volume")
                            .accessibilityValue(Format.percent(preferences.masterVolume))
                    }
                    Toggle("Sound effects", isOn: $preferences.sound)
                    if preferences.sound {
                        LabeledContent("Effects volume") {
                            Slider(value: $preferences.soundVolume, in: 0...1)
                                .frame(maxWidth: 150)
                                .accessibilityLabel("Sound effects volume")
                                .accessibilityValue(Format.percent(preferences.soundVolume))
                        }
                    }
                    Toggle("Music", isOn: $preferences.music)
                    if preferences.music {
                        LabeledContent("Music volume") {
                            Slider(value: $preferences.musicVolume, in: 0...1)
                                .frame(maxWidth: 150)
                                .accessibilityLabel("Music volume")
                                .accessibilityValue(Format.percent(preferences.musicVolume))
                        }
                    }
                    Text("Four slow beds that follow the airline's situation — planning, operating, and trouble. There is no melody and nothing repeats on a short cycle.")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                    Toggle("World ambience", isOn: $preferences.ambience)
                    if preferences.ambience {
                        LabeledContent("Ambience volume") {
                            Slider(value: $preferences.ambienceVolume, in: 0...1)
                                .frame(maxWidth: 150)
                                .accessibilityLabel("World ambience volume")
                                .accessibilityValue(Format.percent(preferences.ambienceVolume))
                        }
                    }
                    Text("A quiet bed under the map that thickens as more of your aircraft are in the air. Off by default — the game is complete without it.")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                }
                if !controller.feedback.missingAssets.isEmpty {
                    Text("\(controller.feedback.missingAssets.count) sounds are missing from this build and will play silently.")
                        .font(.caption)
                        .foregroundStyle(AETheme.caution)
                }
            }

            Section("Feel") {
                Toggle("Haptics", isOn: $preferences.haptics)
                Text("Nothing the simulation does on its own schedule vibrates the phone — only your own actions, and the few things you must not miss.")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
            }
            .onChange(of: preferences.muteAll) { _, _ in controller.audioSettingsChanged() }
            .onChange(of: preferences.masterVolume) { _, _ in controller.audioSettingsChanged() }
            .onChange(of: preferences.sound) { _, _ in controller.audioSettingsChanged() }
            .onChange(of: preferences.soundVolume) { _, _ in controller.audioSettingsChanged() }
            .onChange(of: preferences.music) { _, _ in controller.audioSettingsChanged() }
            .onChange(of: preferences.musicVolume) { _, _ in controller.audioSettingsChanged() }
            .onChange(of: preferences.ambience) { _, _ in controller.audioSettingsChanged() }
            .onChange(of: preferences.ambienceVolume) { _, _ in controller.audioSettingsChanged() }

            Section("Your airline") {
                NavigationLink("Passenger experience and reputation") { PassengerExperienceView() }
            }

            Section("Save") {
                Button("Save now") { controller.saveNow() }
                Button("Save and quit to menu") {
                    Task { await controller.saveAndQuit() }
                }
                .disabled(controller.isSavingAndQuitting)
                if case .failed(let reason) = controller.lastSaveOutcome {
                    Text(reason + " Your game is still open. Free some device storage and try Save now again.")
                        .font(.caption)
                        .foregroundStyle(AETheme.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Export campaign backup") {
                    exportInProgress = true
                    Task {
                        defer { exportInProgress = false }
                        do {
                            exportDocument = try await controller.exportCampaign()
                            showingExport = true
                        } catch { exportFailure = error.localizedDescription }
                    }
                }
                .disabled(exportInProgress)
                .accessibilityIdentifier("ae-export-campaign")
                if let generation = controller.loadedFromBackup {
                    Text("This game was restored from backup #\(generation) — some recent progress may be missing.")
                        .font(.caption)
                        .foregroundStyle(AETheme.caution)
                }
                if let failure = controller.quietSaveFailure {
                    Text("The last automatic save did not complete: \(failure). Use Save now.")
                        .font(.caption)
                        .foregroundStyle(AETheme.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("The game saves every game day and whenever you leave the app. Export a backup to keep a copy outside the app; import it from the main menu.")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("ae-app-version")
                if let seed = controller.snapshot?.meta.worldSeed {
                    LabeledContent("World seed", value: String(seed))
                }
                Text("Your game runs on this device. Apple handles Pro payments. RevenueCat validates and reports purchases using an anonymous customer ID. If you sign in to Game Center, achievements and leaderboard scores go to Apple's Game Center under your Game Center settings. Gameplay stays on your device, with no advertising or cross-app tracking.")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
            }
        }
        .aeScreenBackground()
        .navigationTitle("Settings")
        .accessibilityIdentifier("ae-settings-list")
        .fileExporter(isPresented: $showingExport, document: exportDocument,
                      contentType: .data, defaultFilename: "AirlineEmpire-Backup.aesave") { result in
            if case .failure(let error) = result { exportFailure = error.localizedDescription }
        }
        .alert("Could not export backup", isPresented: Binding(
            get: { exportFailure != nil }, set: { if !$0 { exportFailure = nil } })) {
            Button("OK", role: .cancel) { exportFailure = nil }
        } message: { Text(exportFailure ?? "") }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
