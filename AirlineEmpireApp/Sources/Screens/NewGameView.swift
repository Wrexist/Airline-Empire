import SwiftUI
import AirlineEmpireCore

/// First five minutes (docs/PLAYER_JOURNEY.md §1): name, color-of-choice
/// era later; three curated starts, each a one-line personality.
struct NewGameView: View {
    @Environment(GameController.self) private var controller
    @State private var airlineName = ""
    @State private var selectedStart = CuratedStart.all[0]
    @State private var scenario: ScenarioCode = "entrepreneur"
    @State private var seedText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Your airline") {
                    TextField("Airline name", text: $airlineName)
                        .textInputAutocapitalization(.words)
                }
                Section("Home airport") {
                    ForEach(CuratedStart.all) { start in
                        Button {
                            selectedStart = start
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(start.title).font(.body.weight(.medium))
                                    Text(start.blurb)
                                        .font(.caption)
                                        .foregroundStyle(AETheme.mutedText)
                                }
                                Spacer()
                                if start.id == selectedStart.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AETheme.accent)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section("Difficulty") {
                    if let catalog = try? ContentCatalog.loadBundled() {
                        ForEach(catalog.orderedScenarioCodes, id: \.self) { code in
                            if let spec = catalog.scenarios[code] {
                                Button {
                                    scenario = code
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(spec.name).font(.body.weight(.medium))
                                            Text(spec.blurb)
                                                .font(.caption)
                                                .foregroundStyle(AETheme.mutedText)
                                        }
                                        Spacer()
                                        if scenario == code {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(AETheme.accent)
                                        }
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }
                Section("World seed (optional)") {
                    TextField("Random", text: $seedText)
                        .keyboardType(.numberPad)
                    Text("Same seed, same world — share it for challenge runs.")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                }
                Section {
                    Button("Found the airline") {
                        let seed = UInt64(seedText)
                            ?? UInt64.random(in: 1...UInt64.max / 2)
                        controller.startNewGame(
                            airlineName: airlineName.isEmpty ? "Skyline Air" : airlineName,
                            home: selectedStart.home, seed: seed, scenario: scenario)
                    }
                    .font(.headline)
                }
                if !controller.availableSlots().isEmpty {
                    Section("Continue") {
                        ForEach(controller.availableSlots(), id: \.slot) { entry in
                            Button {
                                controller.loadGame(slot: entry.slot)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(entry.meta?.airlineName ?? "Save \(entry.slot)")
                                    if let meta = entry.meta {
                                        Text("\(meta.gameDateDescription) · \(meta.era)")
                                            .font(.caption)
                                            .foregroundStyle(AETheme.mutedText)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Airline Empire")
        }
    }
}

struct CuratedStart: Identifiable {
    let id: String
    let title: String
    let blurb: String
    let home: AirportCode

    static let all: [CuratedStart] = [
        CuratedStart(id: "safe", title: "Stockholm — Sjövik",
                     blurb: "Quiet Nordic market, loyal travellers, room to learn.",
                     home: "STV"),
        CuratedStart(id: "balanced", title: "Barcelona — Marisol",
                     blurb: "Sun-belt tourism with real competition in season.",
                     home: "BCM"),
        CuratedStart(id: "bold", title: "Singapore — Merlionport",
                     blurb: "Rich crossroads hub. Deep pockets fly here — so do rivals.",
                     home: "SGM"),
    ]
}
