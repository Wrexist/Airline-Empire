import SwiftUI
import AirlineEmpireCore

/// The campaign, told as a story rather than as a wall of codes: the chapter
/// the airline is in, what the next one asks for and opens, what is running
/// now, and what has already been done.
///
/// The screen leads with the player's own position (era, how long, how far),
/// then the work in flight, then the record. The `ProgressionModel` is the one
/// source: the era bar, the mission bars and the log all come from the same
/// arithmetic the simulation resolves against.
struct ProgressionView: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        ScrollView {
            VStack(spacing: AETheme.spacingM) {
                if let snapshot = controller.snapshot,
                   let catalog = controller.catalog,
                   let model = snapshot.progressionModel(catalog: catalog),
                   let player = snapshot.playerAirline {
                    campaignHero(model, snapshot: snapshot)
                    nextChapterCard(model)
                    commitmentsCard(model)
                    ContractBoard()
                    capabilitiesCard(model, player: player.id)
                    honoursCard(model, startYear: snapshot.meta.startYear)
                    campaignLogCard(model, startYear: snapshot.meta.startYear)
                } else {
                    LoadingState(message: "Reading your record")
                        .frame(minHeight: 240)
                }
            }
            .aePageInsets()
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .aeScreenBackground()
        .navigationTitle("Progression")
        .navigationBarTitleDisplayMode(.inline)
        .aeTimeToolbar()
    }

    // MARK: - The chapter

    private func campaignHero(_ model: ProgressionModel, snapshot: GameState) -> some View {
        let dashboard = controller.dashboard
        return AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingM) {
                HStack(alignment: .top, spacing: AETheme.spacingM) {
                    AEClayIcon(systemName: Vocab.eraIcon(model.era),
                               tint: AETheme.accent, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your airline's chapter")
                            .font(.caption).foregroundStyle(AETheme.mutedText)
                        Text(Vocab.era(model.era))
                            .accessibilityIdentifier("ae-progression-era")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text(standing(model, snapshot: snapshot,
                                      destinations: dashboard?.destinationCount ?? 0))
                            .font(.caption).foregroundStyle(AETheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                Text(Vocab.eraDetail(model.era))
                    .font(.subheadline).foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                AEStatGrid {
                    campaignStat("Flights flown", Format.count(model.counters.flightsCompleted))
                    campaignStat("Passengers", Format.count(model.counters.passengersCarried))
                    campaignStat("Destinations", "\(dashboard?.destinationCount ?? 0)")
                    campaignStat("Aircraft", "\(dashboard?.fleetCount ?? 0)")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("The campaign so far")
            }
        }
    }

    /// The one line that makes the era feel lived-in: since when, and how much
    /// has happened in it.
    private func standing(_ model: ProgressionModel, snapshot: GameState,
                          destinations: Int) -> String {
        var parts: [String] = []
        if let since = model.eraSince {
            parts.append("Since \(Format.date(GameCalendar.date(at: since, startYear: snapshot.meta.startYear)))")
        }
        if let dashboard = controller.dashboard {
            parts.append("\(dashboard.routeCount) \(dashboard.routeCount == 1 ? "route" : "routes")")
        }
        parts.append("\(destinations) \(destinations == 1 ? "destination" : "destinations")")
        return parts.joined(separator: " · ")
    }

    private func campaignStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text(label)
                .font(.caption).foregroundStyle(AETheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - The next chapter

    private func nextChapterCard(_ model: ProgressionModel) -> some View {
        AEPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Next chapter", systemImage: "flag.checkered")
                if let next = model.nextEra {
                    HStack(alignment: .firstTextBaseline) {
                        Text("To reach \(Vocab.era(next))")
                            .font(.subheadline.weight(.medium))
                        Spacer(minLength: AETheme.spacingS)
                        Text(Format.percent(model.nextEraProgress))
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(AETheme.mutedText)
                    }
                    ProgressView(value: model.nextEraProgress).tint(AETheme.accent)
                    ForEach(Array(model.nextEraRequirements.enumerated()), id: \.offset) { _, requirement in
                        AEProgressRow(title: Vocab.requirement(requirement.kind),
                                      detail: Vocab.requirementValue(requirement),
                                      fraction: requirement.fraction,
                                      isMet: requirement.isMet)
                    }
                    if !model.nextEraUnlocks.isEmpty {
                        Label("Opens \(model.nextEraUnlocks.map(Vocab.category).joined(separator: ", "))",
                              systemImage: "lock.open")
                            .font(.caption).foregroundStyle(AETheme.positive)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(Vocab.eraDetail(next))
                        .font(.caption).foregroundStyle(AETheme.mutedText)
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

    // MARK: - Active commitments

    private func commitmentsCard(_ model: ProgressionModel) -> some View {
        AEPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingM) {
                HStack(spacing: AETheme.spacingS) {
                    AESectionHeader(text: "Active commitments", systemImage: "target")
                    Spacer(minLength: AETheme.spacingS)
                    if !model.missions.isEmpty {
                        AEBadge(text: "\(model.missions.count) running", color: AETheme.accent)
                    }
                }
                if model.missions.isEmpty {
                    Text("Nothing running. A tourism boom or a monthly contract appears here when the world offers one — and ignoring one costs nothing.")
                        .font(.subheadline).foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(model.missions.enumerated()), id: \.offset) { _, progress in
                        missionRow(progress)
                    }
                }
            }
        }
    }

    private func missionRow(_ progress: ProgressionModel.MissionProgress) -> some View {
        VStack(alignment: .leading, spacing: AETheme.spacingXS) {
            HStack(alignment: .firstTextBaseline, spacing: AETheme.spacingS) {
                Label(Vocab.missionTitle(progress.mission.kind),
                      systemImage: missionIcon(progress.mission.kind))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: AETheme.spacingS)
                AEBadge(text: Format.money(progress.mission.reward),
                        color: AETheme.positive)
            }
            ProgressView(value: progress.fraction).tint(AETheme.accent)
            HStack {
                Text("\(Format.count(progress.current)) of \(Format.count(progress.target))")
                Spacer(minLength: AETheme.spacingS)
                Text(deadlineText(progress.daysRemaining))
                    .foregroundStyle(progress.daysRemaining <= 3
                                     ? AETheme.caution : AETheme.mutedText)
            }
            .font(.caption).monospacedDigit()
            Text(missionNote(progress.mission))
                .font(.caption2).foregroundStyle(AETheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func missionIcon(_ kind: MissionKind) -> String {
        switch kind {
        case .boomRush: "flame.fill"
        case .flightContract: "airplane.departure"
        case .passengerContract: "person.3.fill"
        }
    }

    private func deadlineText(_ daysRemaining: Int) -> String {
        switch daysRemaining {
        case ..<1: "Closes today"
        case 1: "1 day left"
        default: "\(daysRemaining) days left"
        }
    }

    private func missionNote(_ mission: Mission) -> String {
        switch mission.kind {
        case .boomRush(let region, _):
            "Passengers flown on routes touching \(Vocab.region(region)), counted from when it was offered."
        case .flightContract, .passengerContract:
            "Only activity after acceptance counts. It must land before the contract closes."
        }
    }

    // MARK: - Capability programs

    private func capabilitiesCard(_ model: ProgressionModel,
                                  player: AirlineID) -> some View {
        let ordered = model.capabilities.sorted { capabilityRank($0) < capabilityRank($1) }
        return AEPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingM) {
                AESectionHeader(text: "Capability programmes",
                                systemImage: "wrench.and.screwdriver")
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, status in
                    capabilityRow(status, player: player)
                }
            }
        }
    }

    /// Running first, then startable, then what is already built, then the
    /// ones the era has not opened — the order of what a player can act on.
    private func capabilityRank(_ status: ProgressionModel.CapabilityStatus) -> Int {
        switch status.state {
        case .inProgress: 0
        case .available, .unaffordable, .blockedBySlots: 1
        case .built: 2
        case .eraLocked: 3
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
                capabilityBadge(status, player: player)
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
    private func capabilityBadge(_ status: ProgressionModel.CapabilityStatus,
                                 player: AirlineID) -> some View {
        switch status.state {
        case .built:
            AEBadge(text: "built", color: AETheme.positive, icon: "checkmark")
        case .inProgress:
            AEBadge(text: "under way", color: AETheme.accent, icon: "hammer")
        case .eraLocked(let era, _, _):
            AEBadge(text: "\(Vocab.era(era)) era", color: .secondary, icon: "lock")
        case .blockedBySlots:
            AEBadge(text: "at programme limit", color: .secondary, icon: "hourglass")
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
                confirmTitle: "Start programme", role: nil,
                action: {
                    controller.submit(StartCapabilityProgramCommand(
                        airline: player, code: status.code))
                }
            ) {
                Text(Format.money(cost))
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Honours

    private func honoursCard(_ model: ProgressionModel, startYear: Int) -> some View {
        let dates = honourDates(model.record)
        return AEPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Honours", systemImage: "star")
                if model.milestones.isEmpty && model.achievements.isEmpty {
                    Text("The story starts with your first flight.")
                        .font(.subheadline).foregroundStyle(AETheme.mutedText)
                }
                ForEach(model.milestones, id: \.self) { code in
                    honourRow(icon: "star.fill", tint: AETheme.accent,
                              title: Vocab.milestone(code),
                              detail: Vocab.milestoneDetail(code),
                              at: dates.milestones[code], startYear: startYear)
                }
                ForEach(model.achievements, id: \.self) { code in
                    honourRow(icon: "rosette", tint: AETheme.positive,
                              title: Vocab.achievement(code),
                              detail: Vocab.achievementDetail(code),
                              at: dates.achievements[code], startYear: startYear)
                }
            }
        }
    }

    private func honourDates(_ record: [ProgressionMoment])
        -> (milestones: [String: SimTime], achievements: [String: SimTime]) {
        var milestones: [String: SimTime] = [:]
        var achievements: [String: SimTime] = [:]
        for moment in record {
            switch moment.kind {
            case .milestone(let code): milestones[code] = moment.at
            case .achievement(let code): achievements[code] = moment.at
            default: break
            }
        }
        return (milestones, achievements)
    }

    private func honourRow(icon: String, tint: Color, title: String,
                           detail: String, at time: SimTime?, startYear: Int) -> some View {
        HStack(alignment: .top, spacing: AETheme.spacingS) {
            Image(systemName: icon)
                .font(.subheadline).foregroundStyle(tint)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption).foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                if let time {
                    Text("Earned \(Format.date(GameCalendar.date(at: time, startYear: startYear)))")
                        .font(.caption2).foregroundStyle(AETheme.mutedText)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - The record

    private func campaignLogCard(_ model: ProgressionModel, startYear: Int) -> some View {
        let recent = Array(model.record.reversed().prefix(12))
        return AEPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Campaign log",
                                systemImage: "clock.arrow.circlepath")
                if recent.isEmpty {
                    Text("Nothing logged yet. Milestones, programmes, missions and eras are recorded here as they happen, so the story outlives the event feed.")
                        .font(.subheadline).foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(recent.enumerated()), id: \.offset) { _, moment in
                        momentRow(moment, startYear: startYear)
                    }
                    if model.record.count > recent.count {
                        Text("The latest \(recent.count) of \(model.record.count) moments.")
                            .font(.caption2).foregroundStyle(AETheme.mutedText)
                    }
                }
            }
        }
    }

    private func momentRow(_ moment: ProgressionMoment, startYear: Int) -> some View {
        HStack(alignment: .top, spacing: AETheme.spacingS) {
            Image(systemName: Vocab.momentIcon(moment.kind))
                .font(.subheadline).foregroundStyle(AETheme.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(Vocab.momentTitle(moment.kind))
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(Vocab.momentDetail(moment.kind))
                    .font(.caption).foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: AETheme.spacingS)
            Text(Format.date(GameCalendar.date(at: moment.at, startYear: startYear)))
                .font(.caption2).monospacedDigit()
                .foregroundStyle(AETheme.mutedText)
        }
        .accessibilityElement(children: .combine)
    }
}
