import SwiftUI
import AirlineEmpireCore

/// World & operations: live events, competitors, progression, service —
/// the "what is happening around me" screen group.
struct OperationsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("World events") { WorldEventsView() }
                    NavigationLink("Competitors") { CompetitorsView() }
                    NavigationLink("Progression") { ProgressionView() }
                    NavigationLink("Service & settings") { SettingsView() }
                }
            }
            .navigationTitle("World")
        }
    }
}

struct WorldEventsView: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        List {
            if let snapshot = controller.snapshot {
                let active = snapshot.world.activeEvents
                if active.isEmpty {
                    EmptyStateView(icon: "sun.max", title: "Calm skies",
                                   message: "No world events right now.")
                } else {
                    ForEach(active, id: \.id) { event in
                        VStack(alignment: .leading, spacing: AETheme.spacingXS) {
                            Text(title(for: event.kind))
                                .font(.body.weight(.medium))
                            HStack {
                                if !event.hasStarted {
                                    AEBadge(text: "forecast", color: AETheme.caution,
                                            icon: "clock")
                                }
                                Text("until day \(event.endsAt.dayIndex)")
                                    .font(.caption)
                                    .foregroundStyle(AETheme.mutedText)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("World events")
    }

    private func title(for kind: WorldEventKind) -> String {
        switch kind {
        case .fuelShock: "Fuel market shock"
        case .storm(let region): "Severe weather — \(String(describing: region))"
        case .airportClosure(let airport): "\(airport.raw) closed"
        case .tourismBoom(let region): "Tourism boom — \(String(describing: region))"
        case .strike(let airline): "Strike at airline #\(airline.raw)"
        }
    }
}

struct CompetitorsView: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        List {
            if let snapshot = controller.snapshot {
                ForEach(snapshot.orderedAirlineIDs, id: \.self) { airlineID in
                    if let airline = snapshot.airlines[airlineID], airline.kind == .ai {
                        VStack(alignment: .leading, spacing: AETheme.spacingXS) {
                            HStack {
                                Text(airline.name).font(.body.weight(.medium))
                                Spacer()
                                if airline.status == .collapsed {
                                    AEBadge(text: "collapsed", color: AETheme.negative)
                                }
                            }
                            HStack(spacing: AETheme.spacingS) {
                                AEBadge(text: "\(snapshot.fleet(of: airlineID).count) aircraft",
                                        color: .secondary)
                                AEBadge(text: "\(snapshot.routes(of: airlineID).count) routes",
                                        color: .secondary)
                                AEBadge(text: "rep \(Format.percent(airline.reputation.score))",
                                        color: AETheme.accent)
                                if let profile = airline.aiProfile {
                                    AEBadge(text: profile.archetype.rawValue, color: .purple)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Competitors")
    }
}

struct ProgressionView: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        List {
            if let snapshot = controller.snapshot {
                Section("Era") {
                    Text(String(describing: snapshot.progression.era).capitalized)
                        .font(.headline)
                }
                Section("Capability programs") {
                    ForEach(CapabilityCode.allCases, id: \.self) { code in
                        capabilityRow(code, snapshot: snapshot)
                    }
                }
                if !snapshot.progression.missions.isEmpty {
                    Section("Missions") {
                        ForEach(snapshot.progression.missions, id: \.id) { mission in
                            missionRow(mission)
                        }
                    }
                }
                Section("Milestones") {
                    if snapshot.progression.milestones.isEmpty {
                        Text("The story starts with your first flight.")
                            .foregroundStyle(AETheme.mutedText)
                    }
                    ForEach(snapshot.progression.milestones, id: \.self) { code in
                        Label(code, systemImage: "star.fill")
                    }
                }
                Section("Achievements") {
                    ForEach(snapshot.progression.achievements, id: \.self) { code in
                        Label(code, systemImage: "rosette")
                    }
                }
            }
        }
        .navigationTitle("Progression")
    }

    @ViewBuilder
    private func capabilityRow(_ code: CapabilityCode, snapshot: GameState) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(code.rawValue).font(.body.weight(.medium))
            }
            Spacer()
            if snapshot.progression.hasCapability(code) {
                AEBadge(text: "built", color: AETheme.positive, icon: "checkmark")
            } else if snapshot.progression.activePrograms.contains(where: { $0.code == code }) {
                AEBadge(text: "in progress", color: AETheme.accent, icon: "hammer")
            } else {
                Button("Start") {
                    if let player = snapshot.playerAirline?.id {
                        controller.submit(StartCapabilityProgramCommand(
                            airline: player, code: code))
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func missionRow(_ mission: Mission) -> some View {
        VStack(alignment: .leading, spacing: AETheme.spacingXS) {
            switch mission.kind {
            case .boomRush(let region, let target):
                Text("Boom rush: carry \(target) passengers in \(String(describing: region))")
                    .font(.body.weight(.medium))
            }
            Text("Reward \(Format.money(mission.reward)) · deadline day \(mission.deadline.dayIndex)")
                .font(.caption)
                .foregroundStyle(AETheme.mutedText)
        }
    }
}

struct SettingsView: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        List {
            if let snapshot = controller.snapshot,
               let player = snapshot.playerAirline {
                Section("Service tier") {
                    ForEach(ServiceTier.allCases, id: \.self) { tier in
                        Button {
                            controller.submit(SetServiceTierCommand(
                                airline: player.id, tier: tier))
                        } label: {
                            HStack {
                                Text(tier.rawValue.capitalized)
                                Spacer()
                                if player.serviceTier == tier {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AETheme.accent)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section("Reputation") {
                    reputationRow("Punctuality", player.reputation.punctuality)
                    reputationRow("Reliability", player.reputation.reliability)
                    reputationRow("Service", player.reputation.service)
                    reputationRow("Comfort", player.reputation.comfort)
                    reputationRow("Value", player.reputation.valuePerception)
                }
                Section("Save") {
                    Button("Save now") { controller.saveOnBackground() }
                    Button("Save and quit to menu") {
                        controller.saveOnBackground()
                        controller.quitToMenu()
                    }
                    if let generation = controller.loadedFromBackup {
                        Text("This game was restored from backup #\(generation) — some recent progress may be missing.")
                            .font(.caption)
                            .foregroundStyle(AETheme.caution)
                    }
                }
            }
        }
        .navigationTitle("Airline")
    }

    private func reputationRow(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label)
            Spacer()
            ProgressView(value: value)
                .frame(width: 120)
            Text(Format.percent(value))
                .font(.caption).monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }
}
