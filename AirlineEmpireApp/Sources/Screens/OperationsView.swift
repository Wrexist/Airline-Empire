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
                VStack(spacing: AETheme.spacingS) {
                    hubLink(title: "World events", icon: "bolt.horizontal.fill",
                            subtitle: "Storms, fuel shocks and what they are doing to your network",
                            badge: eventBadge) {
                        WorldEventsView()
                    }
                    hubLink(title: "Competitors", icon: "person.2.fill",
                            subtitle: "Who else is flying, and how they are doing",
                            badge: competitorBadge) {
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
                }
                .padding(.horizontal, AETheme.spacingM)
                .padding(.top, AETheme.spacingS)
                .padding(.bottom, AETheme.spacingL)
            }
            .aeScreenBackground()
            .navigationTitle("World")
            .navigationBarTitleDisplayMode(.inline)
            .aeTimeToolbar()
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

    private var competitorBadge: (String, Color)? {
        guard let snapshot = controller.snapshot else { return nil }
        let alive = snapshot.airlines.values.filter {
            $0.kind == .ai && $0.status == .active
        }.count
        return ("\(alive) flying", AETheme.mutedText)
    }

    private var progressionBadge: (String, Color)? {
        guard let snapshot = controller.snapshot, let catalog = controller.catalog,
              let model = snapshot.progressionModel(catalog: catalog) else { return nil }
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
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: AETheme.spacingM) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(AETheme.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AETheme.spacingS) {
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
            .aeGlass(in: AETheme.cardShape,
                     interactive: true)
        }
        .buttonStyle(.plain)
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
                    if active.isEmpty {
                        EmptyStateView(icon: "sun.max", title: "Calm skies",
                                       message: "No storms, no shocks, no closures. A good time to expand.")
                    } else {
                        ForEach(active, id: \.id) { event in
                            eventCard(event, snapshot: snapshot, catalog: catalog)
                        }
                    }
                } else {
                    LoadingState(message: "Reading the weather")
                        .frame(minHeight: 240)
                }
            }
            .padding(.horizontal, AETheme.spacingM)
            .padding(.vertical, AETheme.spacingS)
        }
        .aeScreenBackground()
        .navigationTitle("World events")
        .navigationBarTitleDisplayMode(.inline)
        .aeTimeToolbar()
        .navigationDestination(for: RouteID.self) { RouteDetailView(routeID: $0) }
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
                    Text("\(affected.count) of your routes \(affected.count == 1 ? "is" : "are") in its path:")
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
        return days == 0 ? "Ends today" : "Until \(Format.date(endDate)) · \(Format.days(days)) left"
    }
}

/// Rivals as characters rather than as a table: what kind of airline each one
/// is, how it plays, and — the reason this screen exists — how many markets
/// you are both in.
struct CompetitorsView: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        ScrollView {
            VStack(spacing: AETheme.spacingM) {
                if let snapshot = controller.snapshot, let player = snapshot.playerAirline {
                    let rivals = snapshot.orderedAirlineIDs.compactMap { id -> Airline? in
                        guard let airline = snapshot.airlines[id], airline.kind == .ai
                        else { return nil }
                        return airline
                    }
                    if rivals.isEmpty {
                        EmptyStateView(icon: "person.2.slash", title: "No rivals",
                                       message: "This world has no competing airlines.")
                    } else {
                        ForEach(rivals.sorted(by: rivalOrder), id: \.id) { rival in
                            rivalCard(rival, snapshot: snapshot, player: player)
                        }
                    }
                } else {
                    LoadingState(message: "Scouting the competition")
                        .frame(minHeight: 240)
                }
            }
            .padding(.horizontal, AETheme.spacingM)
            .padding(.vertical, AETheme.spacingS)
        }
        .aeScreenBackground()
        .navigationTitle("Competitors")
        .navigationBarTitleDisplayMode(.inline)
        .aeTimeToolbar()
    }

    /// Live rivals first, biggest first; the collapsed sink to the bottom.
    private func rivalOrder(_ lhs: Airline, _ rhs: Airline) -> Bool {
        if (lhs.status == .collapsed) != (rhs.status == .collapsed) {
            return rhs.status == .collapsed
        }
        return lhs.name < rhs.name
    }

    private func rivalCard(_ rival: Airline, snapshot: GameState,
                           player: Airline) -> some View {
        let overlap = sharedMarkets(rival, snapshot: snapshot, player: player)
        return AECard(tint: overlap > 0 ? AETheme.accent.opacity(0.12) : nil) {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                HStack {
                    Circle()
                        .fill(Vocab.liveryColor(rival.livery))
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rival.name).font(.headline)
                        if let profile = rival.aiProfile {
                            Text(Vocab.archetypeDetail(profile.archetype))
                                .font(.caption)
                                .foregroundStyle(AETheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: AETheme.spacingS)
                    if rival.status == .collapsed {
                        AEBadge(text: "collapsed", color: AETheme.negative,
                                icon: "xmark.octagon")
                    } else if let profile = rival.aiProfile {
                        AEBadge(text: Vocab.archetype(profile.archetype), color: AETheme.fare)
                    }
                }
                if rival.status != .collapsed {
                    HStack(spacing: AETheme.spacingS) {
                        AEBadge(text: "\(snapshot.fleet(of: rival.id).count) aircraft",
                                color: .secondary)
                        AEBadge(text: "\(snapshot.routes(of: rival.id).count) routes",
                                color: .secondary)
                        AEBadge(text: "rep \(Format.percent(rival.reputation.score))",
                                color: AETheme.accent)
                    }
                    if overlap > 0 {
                        Label(overlap == 1
                              ? "You compete on 1 market."
                              : "You compete on \(overlap) markets.",
                              systemImage: "arrow.left.arrow.right")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AETheme.accent)
                    } else {
                        Text("You do not fly anywhere they fly.")
                            .font(.subheadline)
                            .foregroundStyle(AETheme.mutedText)
                    }
                } else {
                    Text("Their routes and slots are back on the market.")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.mutedText)
                }
            }
        }
    }

    private func sharedMarkets(_ rival: Airline, snapshot: GameState,
                               player: Airline) -> Int {
        let mine = snapshot.routes(of: player.id)
        let theirs = snapshot.routes(of: rival.id)
        return mine.filter { route in
            theirs.contains { $0.sameMarket(origin: route.origin,
                                            destination: route.destination) }
        }.count
    }
}

/// The macro arc, made legible.
///
/// This was the least readable screen in the app: capabilities named
/// `efficientTurnarounds` with no description, cost, duration or progress; a
/// Start button that was always enabled even in the eras where the command can
/// only refuse; milestones and achievements printed as raw codes; and nothing
/// at all about what the next era requires (UIUX_FORENSIC_AUDIT UI-008).
struct ProgressionView: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        ScrollView {
            VStack(spacing: AETheme.spacingM) {
                if let snapshot = controller.snapshot,
                   let catalog = controller.catalog,
                   let model = snapshot.progressionModel(catalog: catalog),
                   let player = snapshot.playerAirline {
                    eraCard(model)
                    missionsCard(model)
                    capabilitiesCard(model, player: player.id)
                    honoursCard(model)
                } else {
                    LoadingState(message: "Reading your record")
                        .frame(minHeight: 240)
                }
            }
            .padding(.horizontal, AETheme.spacingM)
            .padding(.vertical, AETheme.spacingS)
        }
        .aeScreenBackground()
        .navigationTitle("Progression")
        .navigationBarTitleDisplayMode(.inline)
        .aeTimeToolbar()
    }

    private func eraCard(_ model: ProgressionModel) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Era", systemImage: "flag")
                Text(Vocab.era(model.era)).font(.title3.weight(.semibold))
                Text(Vocab.eraDetail(model.era))
                    .font(.subheadline)
                    .foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                if let next = model.nextEra {
                    Divider()
                    HStack {
                        Text("To reach \(Vocab.era(next))")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(Format.percent(model.nextEraProgress))
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(AETheme.mutedText)
                    }
                    ForEach(Array(model.nextEraRequirements.enumerated()), id: \.offset) { _, requirement in
                        AEProgressRow(title: Vocab.requirement(requirement.kind),
                                      detail: Vocab.requirementValue(requirement),
                                      fraction: requirement.fraction,
                                      isMet: requirement.isMet)
                    }
                    Text(Vocab.eraDetail(next))
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label("There is no era above this one. The network is the goal now.",
                          systemImage: "crown")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.positive)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func missionsCard(_ model: ProgressionModel) -> some View {
        if !model.missions.isEmpty {
            AECard {
                VStack(alignment: .leading, spacing: AETheme.spacingS) {
                    AESectionHeader(text: "Missions", systemImage: "target")
                    ForEach(Array(model.missions.enumerated()), id: \.offset) { _, progress in
                        VStack(alignment: .leading, spacing: AETheme.spacingXS) {
                            AEProgressRow(title: missionTitle(progress.mission),
                                          detail: "\(Format.count(progress.current)) / \(Format.count(progress.target))",
                                          fraction: progress.fraction,
                                          icon: "target")
                            Text("\(Format.money(progress.mission.reward)) · \(Format.days(progress.daysRemaining)) left")
                                .font(.caption)
                                .foregroundStyle(progress.daysRemaining <= 3
                                                 ? AETheme.caution : AETheme.mutedText)
                        }
                    }
                    Text("Missions are offers, never chores — ignoring one costs nothing.")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                }
            }
        }
    }

    private func missionTitle(_ mission: Mission) -> String {
        switch mission.kind {
        case .boomRush(let region, let target):
            "Carry \(Format.count(target)) passengers in \(Vocab.region(region))"
        }
    }

    private func capabilitiesCard(_ model: ProgressionModel,
                                  player: AirlineID) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingM) {
                AESectionHeader(text: "Capability programs", systemImage: "wrench.and.screwdriver")
                ForEach(Array(model.capabilities.enumerated()), id: \.offset) { _, status in
                    capabilityRow(status, player: player)
                }
            }
        }
    }

    private func capabilityRow(_ status: ProgressionModel.CapabilityStatus,
                               player: AirlineID) -> some View {
        VStack(alignment: .leading, spacing: AETheme.spacingXS) {
            HStack(spacing: AETheme.spacingS) {
                Image(systemName: Vocab.capabilityIcon(status.code))
                    .foregroundStyle(AETheme.accent)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(Vocab.capability(status.code))
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: AETheme.spacingS)
                trailing(status, player: player)
            }
            Text(Vocab.capabilityDetail(status.code))
                .font(.caption)
                .foregroundStyle(AETheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            if case .inProgress(_, let days, let fraction) = status.state {
                ProgressView(value: fraction).tint(AETheme.accent)
                Text("\(Format.days(days)) to go")
                    .font(.caption2)
                    .foregroundStyle(AETheme.mutedText)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func trailing(_ status: ProgressionModel.CapabilityStatus,
                          player: AirlineID) -> some View {
        switch status.state {
        case .built:
            AEBadge(text: "built", color: AETheme.positive, icon: "checkmark")
        case .inProgress:
            AEBadge(text: "under way", color: AETheme.accent, icon: "hammer")
        case .eraLocked(let era, _, _):
            AEBadge(text: "\(Vocab.era(era)) era", color: .secondary, icon: "lock")
        case .blockedBySlots:
            AEBadge(text: "at program limit", color: .secondary, icon: "hourglass")
        case .unaffordable(let cost, let shortfall, _):
            VStack(alignment: .trailing, spacing: 1) {
                AEBadge(text: Format.money(cost), color: AETheme.caution)
                Text("\(Format.money(shortfall)) short")
                    .font(.caption2)
                    .foregroundStyle(AETheme.caution)
            }
        case .available(let cost, let days):
            ConfirmableButton(
                title: "Start \(Vocab.capability(status.code))?",
                message: "\(Format.money(cost)) now, and \(Format.days(days)) before it takes effect.",
                confirmTitle: "Start program", role: nil,
                action: {
                    controller.submit(StartCapabilityProgramCommand(
                        airline: player, code: status.code))
                }
            ) {
                Text("\(Format.money(cost))")
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    private func honoursCard(_ model: ProgressionModel) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Milestones and achievements",
                                systemImage: "star")
                if model.milestones.isEmpty && model.achievements.isEmpty {
                    Text("The story starts with your first flight.")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.mutedText)
                }
                ForEach(model.milestones, id: \.self) { code in
                    Label(Vocab.milestone(code), systemImage: "star.fill")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.accent)
                }
                ForEach(model.achievements, id: \.self) { code in
                    VStack(alignment: .leading, spacing: 1) {
                        Label(Vocab.achievement(code), systemImage: "rosette")
                            .font(.subheadline)
                            .foregroundStyle(AETheme.positive)
                        Text(Vocab.achievementDetail(code))
                            .font(.caption)
                            .foregroundStyle(AETheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Reputation, with what moves each component — the screen behind the
/// dashboard's "Reputation 61%", which used to be an inert label.
struct ReputationDetailView: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        ScrollView {
            VStack(spacing: AETheme.spacingM) {
                if let snapshot = controller.snapshot,
                   let player = snapshot.playerAirline {
                    AECard {
                        VStack(alignment: .leading, spacing: AETheme.spacingS) {
                            AESectionHeader(text: "Overall", systemImage: "star.circle")
                            Text(Format.percent(player.reputation.score))
                                .font(.largeTitle.weight(.semibold))
                                .monospacedDigit()
                            Text("Reputation multiplies how attractive your fares look. It moves slowly in both directions — a good history buys grace, never immunity.")
                                .font(.subheadline)
                                .foregroundStyle(AETheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    AECard {
                        VStack(alignment: .leading, spacing: AETheme.spacingM) {
                            AESectionHeader(text: "What it is made of",
                                            systemImage: "chart.bar.doc.horizontal")
                            component("Punctuality", player.reputation.punctuality,
                                      "Flights that leave and arrive on time. Tight schedules and old aircraft hurt it.")
                            component("Reliability", player.reputation.reliability,
                                      "Flights you complete rather than cancel. Storms and groundings hurt it.")
                            component("Service", player.reputation.service,
                                      "Your onboard product. Set by the service tier you pay for.")
                            component("Comfort", player.reputation.comfort,
                                      "The aircraft themselves. Newer and larger cabins score better.")
                            component("Value", player.reputation.valuePerception,
                                      "Whether the fare feels worth it. Charging above the market without the product to match costs you here.")
                        }
                    }
                    AECard {
                        VStack(alignment: .leading, spacing: AETheme.spacingS) {
                            AESectionHeader(text: "Service tier", systemImage: "cup.and.saucer")
                            ForEach(ServiceTier.allCases, id: \.self) { tier in
                                serviceTierRow(tier, player: player)
                            }
                        }
                    }
                } else {
                    LoadingState(message: "Reading your reputation")
                        .frame(minHeight: 240)
                }
            }
            .padding(.horizontal, AETheme.spacingM)
            .padding(.vertical, AETheme.spacingS)
        }
        .aeScreenBackground()
        .navigationTitle("Reputation")
        .navigationBarTitleDisplayMode(.inline)
        .aeTimeToolbar()
    }

    private func component(_ label: String, _ value: Double,
                           _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: AETheme.spacingXS) {
            HStack {
                Text(label).font(.subheadline.weight(.medium))
                Spacer()
                Text(Format.percent(value))
                    .font(.subheadline).monospacedDigit()
                    .foregroundStyle(value >= 0.6 ? AETheme.positive : AETheme.caution)
            }
            ProgressView(value: value)
                .tint(value >= 0.6 ? AETheme.positive : AETheme.caution)
            Text(detail)
                .font(.caption)
                .foregroundStyle(AETheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(Format.percent(value)). \(detail)")
    }

    private func serviceTierRow(_ tier: ServiceTier, player: Airline) -> some View {
        let isSelected = player.serviceTier == tier
        return Button {
            controller.submit(SetServiceTierCommand(airline: player.id, tier: tier))
        } label: {
            HStack(alignment: .top, spacing: AETheme.spacingS) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AETheme.accent : Color.secondary.opacity(0.5))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Vocab.serviceTier(tier))
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    Text(Vocab.serviceTierDetail(tier))
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
                    AECard {
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
            .padding(.horizontal, AETheme.spacingM)
            .padding(.vertical, AETheme.spacingS)
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
        case 0.98...1.02: "A normal year."
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

    var body: some View {
        @Bindable var preferences = controller.preferences
        return List {
            Section("Playing") {
                Toggle("Pause when money runs short", isOn: $preferences.autoPauseOnDanger)
                Text("Fast-forward stops itself when your airline drops below the overdraft floor, so a collapse never happens while you are looking away.")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
                Toggle("Confirm destructive actions", isOn: $preferences.confirmDestructive)
                Text("Selling an aircraft, returning a lease and closing a route ask first.")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
            }

            Section("Sound and feel") {
                Toggle("Sound effects", isOn: $preferences.sound)
                if preferences.sound {
                    LabeledContent("Volume") {
                        Slider(value: $preferences.soundVolume, in: 0...1)
                            .frame(maxWidth: 160)
                            .accessibilityLabel("Sound effects volume")
                            .accessibilityValue(Format.percent(preferences.soundVolume))
                    }
                }
                Toggle("Ambience", isOn: $preferences.ambience)
                if preferences.ambience {
                    LabeledContent("Ambience volume") {
                        Slider(value: $preferences.ambienceVolume, in: 0...1)
                            .frame(maxWidth: 160)
                            .accessibilityLabel("Ambience volume")
                            .accessibilityValue(Format.percent(preferences.ambienceVolume))
                    }
                }
                Text("A quiet bed of air under the world. Off by default — the game is designed to be complete without it.")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
                Toggle("Haptics", isOn: $preferences.haptics)
                Text("Nothing the simulation does on its own schedule vibrates the phone. Only your own actions, and the few things you must not miss.")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
                // Shown only when something is actually wrong. A missing sound
                // is otherwise indistinguishable from a working one, so the
                // build gets somewhere to say so.
                if !controller.feedback.missingAssets.isEmpty {
                    Text("\(controller.feedback.missingAssets.count) sounds are missing from this build and will play silently.")
                        .font(.caption)
                        .foregroundStyle(AETheme.caution)
                }
            }
            .onChange(of: preferences.sound) { _, _ in controller.audioSettingsChanged() }
            .onChange(of: preferences.ambience) { _, _ in controller.audioSettingsChanged() }
            .onChange(of: preferences.ambienceVolume) { _, _ in controller.audioSettingsChanged() }

            Section("Your airline") {
                NavigationLink("Reputation and service") { ReputationDetailView() }
            }

            Section("Save") {
                Button("Save now") { controller.saveNow() }
                Button("Save and quit to menu") {
                    controller.saveNow()
                    controller.quitToMenu()
                }
                if let generation = controller.loadedFromBackup {
                    Text("This game was restored from backup #\(generation) — some recent progress may be missing.")
                        .font(.caption)
                        .foregroundStyle(AETheme.caution)
                }
                Text("The game also saves itself every week of game time and whenever you leave the app.")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
            }

            Section("About") {
                LabeledContent("Airline Empire", value: "1.0")
                if let seed = controller.snapshot?.meta.worldSeed {
                    LabeledContent("World seed", value: String(seed))
                }
                Text("Everything happens on this device. The game makes no network requests and collects nothing.")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
            }
        }
        .aeScreenBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
