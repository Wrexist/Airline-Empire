import SwiftUI
import AirlineEmpireCore

/// First five minutes (docs/PLAYER_JOURNEY.md §1): name it, choose where to
/// start, choose how hard, fly.
///
/// ## Why this is not a Form
///
/// It was, and it read like the Settings app: four grouped sections of equal
/// weight, a title bar that ate a third of the screen, and the one button that
/// matters buried in the scroll between "World seed" and "Continue". A player's
/// first screen is the game's only chance to say what kind of game it is.
///
/// The shape now follows the decision, not the data model:
///
///   1. **Name** — one field, given the room a headline deserves.
///   2. **Where** — three cards, each carrying three real signals from
///      `airports.json` (market size, what flies there, weather exposure)
///      instead of one line of prose. The choice has consequences; the card
///      should show them.
///   3. **How hard** — three pills rather than three stacked cards. Difficulty
///      is one decision, so it gets one control, and the selected scenario's
///      real numbers (starting cash, rivals, year) sit underneath.
///   4. **Fly** — pinned to the bottom, always reachable, never scrolled past.
///
/// The seed moved into a disclosure: it matters enormously to the handful of
/// players who share challenge runs and not at all to everyone else, and
/// putting it fourth in a list of five taught every new player that this game
/// is about form-filling.
///
/// Liquid Glass carries it (`aeGlass`, availability-gated to iOS 26 with a
/// material fallback), over the dusk sky the app icon already uses.
struct NewGameView: View {
    @Environment(GameController.self) private var controller
    @State private var airlineName = ""
    @State private var selectedStart = CuratedStart.all[0]
    /// A home chosen from the whole world rather than the three curated ones.
    @State private var customHome: AirportCode?
    @State private var showingAllAirports = false
    @State private var pendingDeletion: String?
    @State private var livery: Livery = .default
    @State private var scenario: ScenarioCode = "entrepreneur"
    @State private var seedText = ""
    @State private var showsSeed = false
    // Loaded once on appear: content parsing and save-slot IO do not belong
    // in the render pass.
    @State private var catalog: ContentCatalog?
    @State private var slots: [(slot: String, meta: SlotMeta?)] = []
    @FocusState private var nameFocused: Bool

    private var deletionPresented: Binding<Bool> {
        Binding(get: { pendingDeletion != nil },
                set: { presented in if !presented { pendingDeletion = nil } })
    }

    private var trimmedName: String {
        airlineName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The name that will actually be used, so the button can show it rather
    /// than making the player wonder what an empty field does.
    private var effectiveName: String {
        trimmedName.isEmpty ? "Skyline Air" : trimmedName
    }

    var body: some View {
        ZStack {
            AEDuskBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: AETheme.spacingL) {
                    masthead
                    nameField
                    liverySection
                    if !slots.isEmpty { continueSection }
                    homeSection
                    difficultySection
                    seedSection
                    // Room for the pinned button, so the last card is never
                    // trapped underneath it.
                    Color.clear.frame(height: AETheme.spacingL)
                }
                .padding(.horizontal, AETheme.spacingM)
                .padding(.top, AETheme.spacingS)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) { foundBar }
        .preferredColorScheme(.dark)
        .confirmationDialog("Delete this save?",
                            isPresented: deletionPresented,
                            titleVisibility: .visible,
                            presenting: pendingDeletion) { slot in
            Button("Delete", role: .destructive) {
                controller.deleteSlot(slot)
                slots = controller.availableSlots()
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { _ in
            Text("That airline and its history are gone for good.")
        }
        .onAppear {
            if catalog == nil { catalog = try? ContentCatalog.loadBundled() }
            slots = controller.availableSlots()
        }
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingXS) {
            Text("FOUND YOUR AIRLINE")
                .font(.caption.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(AETheme.ember)
            Text("Airline Empire")
                .font(.system(.largeTitle, design: .default, weight: .bold))
                .foregroundStyle(.white)
            Text("One aircraft. One route. Everything after that is yours to build.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, AETheme.spacingXS)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 1 · Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingS) {
            SectionLabel("Your airline")
            TextField("", text: $airlineName, prompt: Text("Name your airline")
                .foregroundColor(.white.opacity(0.35)))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($nameFocused)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(AETheme.spacingM)
                .frame(minHeight: 56)
                .aeGlass(in: AETheme.cardShape)
                .accessibilityLabel("Airline name")
                .accessibilityHint("Leave empty to be called Skyline Air")
        }
    }

    // MARK: - 1b · Colours
    //
    // `GAME_DESIGN` §4.1 lists "name/livery color" as the first decision a
    // player makes, and the app never had it (UIUX_FORENSIC_AUDIT UI-026). It
    // sits with the name because it is the same decision — who are you — and
    // it is one row, because it is not a decision with consequences.

    private var liverySection: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingS) {
            SectionLabel("Your colours")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AETheme.spacingS) {
                    ForEach(Livery.allCases, id: \.self) { option in
                        Button {
                            withAnimation(.snappy(duration: 0.22)) { livery = option }
                        } label: {
                            Circle()
                                .fill(Vocab.liveryColor(option))
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if livery == option {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .overlay {
                                    Circle().stroke(.white.opacity(livery == option ? 0.9 : 0.2),
                                                    lineWidth: livery == option ? 2 : 1)
                                }
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.aePress)
                        .accessibilityLabel(Vocab.livery(option))
                        .accessibilityAddTraits(livery == option
                                                ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.vertical, 2)
            }
            Text("\(Vocab.livery(livery)) — your routes and aircraft fly in this colour on the map.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .aeFeedback(.uiSelect, on: livery)
    }

    // MARK: - 2 · Home airport

    private var homeSection: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingS) {
            SectionLabel("Where you start")
            ForEach(CuratedStart.all) { start in
                AEChoiceCard(isSelected: customHome == nil && start.id == selectedStart.id) {
                    withAnimation(.snappy(duration: 0.22)) {
                        selectedStart = start
                        customHome = nil
                    }
                } content: {
                    startCardBody(start)
                }
            }
            // Three curated openings on a world of eighty airports capped
            // replayability at three (UIUX_FORENSIC_AUDIT UI-025). The curated
            // three stay first because they are the ones tuned to teach.
            AEChoiceCard(isSelected: customHome != nil) {
                showingAllAirports = true
            } content: {
                anywhereCardBody
            }
        }
        // Keyed on the resolved home rather than on `selectedStart.id`,
        // which does not change when the player picks from the full airport
        // list — so choosing a curated start made a sound and choosing any of
        // the other seventy-odd made none.
        .aeFeedback(.uiSelect, on: customHome?.raw ?? selectedStart.id)
        .sheet(isPresented: $showingAllAirports) {
            HomeAirportPicker(catalog: catalog) { code in
                withAnimation(.snappy(duration: 0.22)) { customHome = code }
            }
        }
    }

    /// The chosen home, curated or not.
    private var home: AirportCode {
        customHome ?? selectedStart.home
    }

    @ViewBuilder
    private var anywhereCardBody: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingS) {
            HStack(spacing: AETheme.spacingS) {
                Text(customHome.flatMap { catalog?.airport($0)?.city } ?? "Somewhere else")
                    .font(.headline)
                    .foregroundStyle(.white)
                if let customHome {
                    Text(customHome.raw)
                        .font(.caption.weight(.semibold))
                        .monospaced()
                        .foregroundStyle(AETheme.ember)
                }
            }
            Text(customHome == nil
                 ? "Choose any of the world's airports. Some of them are very hard openings — that is the point."
                 : (catalog?.airport(customHome!).map { "\($0.country) · \(Vocab.runwayDetail($0.runwayClass))" } ?? ""))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
            if let customHome, let spec = catalog?.airport(customHome) {
                HStack(spacing: AETheme.spacingXS) {
                    AEChip(icon: "person.2.fill", text: Self.market(spec))
                    AEChip(icon: "briefcase.fill", text: Self.lean(spec))
                    AEChip(icon: "cloud.rain.fill", text: Vocab.weatherRisk(spec.weatherRisk))
                }
            }
        }
    }

    @ViewBuilder
    private func startCardBody(_ start: CuratedStart) -> some View {
        let spec = catalog?.airport(start.home)
        VStack(alignment: .leading, spacing: AETheme.spacingS) {
            HStack(spacing: AETheme.spacingS) {
                Text(spec?.city ?? start.city)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(start.home.raw)
                    .font(.caption.weight(.semibold))
                    .monospaced()
                    .foregroundStyle(AETheme.ember)
            }
            Text(start.blurb)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)

            // Three real signals from the content pack. A start's difficulty
            // is not flavour text — it is market size, who else wants it, and
            // how often weather takes the day off you.
            if let spec {
                HStack(spacing: AETheme.spacingXS) {
                    AEChip(icon: "person.2.fill", text: Self.market(spec))
                    AEChip(icon: "briefcase.fill", text: Self.lean(spec))
                    AEChip(icon: "cloud.rain.fill", text: Vocab.weatherRisk(spec.weatherRisk))
                }
            }
        }
    }

    /// Market size, rounded to something a person reads rather than parses.
    private static func market(_ spec: AirportSpec) -> String {
        let millions = Double(spec.demographics.populationThousands) / 1_000
        return millions >= 10
            ? "\(Format.decimal(millions, places: 0))M catchment"
            : "\(Format.decimal(millions, places: 1))M catchment"
    }

    /// Which half of the market is the bigger prize here.
    private static func lean(_ spec: AirportSpec) -> String {
        spec.demographics.businessIndex >= spec.demographics.leisureIndex
            ? "Business-led" : "Leisure-led"
    }

    // MARK: - 3 · Difficulty

    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingS) {
            SectionLabel("How hard")
            if let catalog {
                HStack(spacing: AETheme.spacingS) {
                    ForEach(catalog.orderedScenarioCodes, id: \.self) { code in
                        if let spec = catalog.scenarios[code] {
                            difficultyPill(code: code, spec: spec)
                        }
                    }
                }
                if let spec = catalog.scenarios[scenario] {
                    scenarioDetail(spec)
                }
            } else {
                ProgressView().tint(.white)
                    .accessibilityLabel("Loading scenarios")
            }
        }
        .aeFeedback(.uiSelect, on: scenario)
    }

    private func difficultyPill(code: ScenarioCode, spec: ScenarioSpec) -> some View {
        let isSelected = code == scenario
        let shape = Capsule(style: .continuous)
        return Button {
            withAnimation(.snappy(duration: 0.22)) { scenario = code }
        } label: {
            Text(spec.name)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.65))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .contentShape(shape)
                .aeGlass(in: shape,
                         tint: isSelected ? AETheme.accent.opacity(0.35) : nil,
                         interactive: true)
                .overlay(shape.stroke(isSelected ? AETheme.accent.opacity(0.75) : .clear,
                                      lineWidth: 1))
        }
        .buttonStyle(.aePress)
        .accessibilityLabel(spec.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// What the chosen difficulty actually changes, in its own numbers.
    private func scenarioDetail(_ spec: ScenarioSpec) -> some View {
        VStack(alignment: .leading, spacing: AETheme.spacingS) {
            Text(spec.blurb)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: AETheme.spacingXS) {
                AEChip(icon: "banknote.fill", text: "\(Format.money(spec.playerStartingCash)) to start")
                AEChip(icon: "airplane.circle.fill", text: "\(spec.competitorCount) rivals")
                AEChip(icon: "calendar", text: String(spec.startYear))
            }
        }
        .padding(AETheme.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aeGlass(in: AETheme.cardShape)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 4 · The seed, for the people who want it

    private var seedSection: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingS) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { showsSeed.toggle() }
            } label: {
                HStack(spacing: AETheme.spacingXS) {
                    Text("World seed")
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(showsSeed ? 90 : 0))
                    Spacer()
                    if !showsSeed && !seedText.isEmpty {
                        Text(seedText).font(.caption.monospaced())
                    }
                }
                .foregroundStyle(.white.opacity(0.7))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.aePress)
            .accessibilityLabel("World seed")
            .accessibilityHint(showsSeed ? "Collapse" : "Expand to set a seed")

            if showsSeed {
                VStack(alignment: .leading, spacing: AETheme.spacingS) {
                    TextField("", text: $seedText, prompt: Text("Random")
                        .foregroundColor(.white.opacity(0.35)))
                        .keyboardType(.numberPad)
                        .font(.body.monospaced())
                        .foregroundStyle(.white)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Seed number")
                    Text("The same seed always grows the same world — share one for a challenge run.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(AETheme.spacingM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .aeGlass(in: AETheme.cardShape)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Continue an existing airline

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingS) {
            SectionLabel("Continue")
            ForEach(slots, id: \.slot) { entry in
                Button {
                    controller.loadGame(slot: entry.slot)
                } label: {
                    HStack(spacing: AETheme.spacingM) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.meta?.airlineName ?? "Save \(entry.slot)")
                                .font(.headline)
                                .foregroundStyle(.white)
                            if let meta = entry.meta {
                                Text("\(meta.gameDateDescription) · \(meta.era) · \(GameController.slotLabel(entry.slot))")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AETheme.ember)
                            .accessibilityHidden(true)
                    }
                    .padding(AETheme.spacingM)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(AETheme.cardShape)
                    .aeGlass(in: AETheme.cardShape,
                             tint: AETheme.ember.opacity(0.16),
                             interactive: true)
                }
                .buttonStyle(.aePress)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Resumes this airline")
                .contextMenu {
                    Button("Delete this save", role: .destructive) {
                        pendingDeletion = entry.slot
                    }
                }
            }
        }
    }

    // MARK: - The one button that matters

    private var foundBar: some View {
        Button {
            nameFocused = false
            let seed = UInt64(seedText) ?? UInt64.random(in: 1...UInt64.max / 2)
            controller.startNewGame(airlineName: effectiveName,
                                    home: home,
                                    seed: seed,
                                    scenario: scenario,
                                    livery: livery)
        } label: {
            HStack(spacing: AETheme.spacingS) {
                Text("Found \(effectiveName)")
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "airplane.departure")
                    .font(.headline)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .contentShape(Capsule(style: .continuous))
            .aeGlass(in: Capsule(style: .continuous),
                     tint: AETheme.accent.opacity(0.55),
                     interactive: true)
        }
        .buttonStyle(.aePress)
        .padding(.horizontal, AETheme.spacingM)
        .padding(.bottom, AETheme.spacingS)
        .accessibilityLabel("Found \(effectiveName)")
        .accessibilityHint("Starts a new game at \(homeCityName)")
    }
}

/// A section heading: small, tracked, and quiet enough that the content is
/// what the eye lands on.
private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(.white.opacity(0.45))
            .accessibilityAddTraits(.isHeader)
    }
}

private extension NewGameView {
    var homeCityName: String {
        customHome.flatMap { catalog?.airport($0)?.city } ?? selectedStart.city
    }
}

/// Any airport in the world as a home, searchable — the alternative to three
/// hardcoded openings.
struct HomeAirportPicker: View {
    @Environment(\.dismiss) private var dismiss
    let catalog: ContentCatalog?
    let select: (AirportCode) -> Void
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List(rows, id: \.self) { code in
                if let spec = catalog?.airport(code) {
                    Button {
                        select(code)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: AETheme.spacingS) {
                                Text(code.raw)
                                    .font(.subheadline.weight(.semibold)).monospaced()
                                Text(spec.city).font(.subheadline)
                            }
                            Text("\(spec.country) · \(Vocab.runwayDetail(spec.runwayClass)) · \(Vocab.weatherRisk(spec.weatherRisk))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.aePress)
                }
            }
            .searchable(text: $search, prompt: "City, country or code")
            .navigationTitle("Choose a home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var rows: [AirportCode] {
        guard let catalog else { return [] }
        let needle = search.uppercased()
        return catalog.orderedAirportCodes.filter { code in
            guard needle.isEmpty else {
                guard let spec = catalog.airport(code) else { return false }
                return code.raw.uppercased().contains(needle)
                    || spec.city.uppercased().contains(needle)
                    || spec.country.uppercased().contains(needle)
            }
            return true
        }
    }
}

struct CuratedStart: Identifiable {
    let id: String
    let title: String
    let city: String
    let blurb: String
    let home: AirportCode

    static let all: [CuratedStart] = [
        CuratedStart(id: "safe", title: "Stockholm — Sjövik", city: "Stockholm",
                     blurb: "A quiet Nordic market with loyal travellers, and room to make mistakes.",
                     home: "STV"),
        CuratedStart(id: "balanced", title: "Barcelona — Marisol", city: "Barcelona",
                     blurb: "Sun-belt tourism that swings hard with the season, and real competition when it does.",
                     home: "BCM"),
        CuratedStart(id: "bold", title: "Singapore — Merlionport", city: "Singapore",
                     blurb: "A rich crossroads hub. Deep pockets fly here — and so do your rivals.",
                     home: "SGM"),
    ]
}
