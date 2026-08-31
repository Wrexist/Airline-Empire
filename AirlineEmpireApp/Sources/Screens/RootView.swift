import SwiftUI
import AirlineEmpireCore

struct RootView: View {
    @Environment(GameController.self) private var controller
    /// Read only to publish it below, for the UI tests.
    @Environment(\.colorScheme) private var colorScheme

    /// The appearance the app is *actually* rendering in, as something a UI
    /// test can query.
    ///
    /// This exists because a UI test cannot otherwise tell. AE-032 set
    /// `XCUIDevice.shared.appearance = .dark`, captured five screens, named
    /// them "dark", and every one rendered light — the switch had not taken.
    /// The test still passed, because it only asserted that content existed.
    /// That is worse than no check: it manufactures evidence for a claim
    /// nobody verified.
    ///
    /// An identifier rather than a launch flag, because the question is what
    /// the app *did*, not what it was asked to do. Costs one identifier on a
    /// container that has no other, changes no behaviour, and makes
    /// "validated in dark mode" a statement a test can fail.
    private var appearanceIdentifier: String {
        colorScheme == .dark ? "ae-appearance-dark" : "ae-appearance-light"
    }

    var body: some View {
        // Crossfaded rather than swapped. These three are the only whole-screen
        // changes in the app — founding an airline, and losing one — and both
        // are moments. A hard cut makes them feel like a bug.
        ZStack {
            switch state {
            case .newGame:
                NewGameView().transition(.opacity)
            case .gameOver:
                GameOverView()
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            case .playing:
                GameShell().transition(.opacity)
            }
        }
        .aeAnimation(AEMotion.screen, value: state)
        // A UI-test affordance, and deliberately a narrow one.
        //
        // `XCUIDevice.shared.appearance = .dark` is the faithful way to test
        // dark mode — it switches the simulator, so what is captured is what a
        // player changing Appearance in Settings would get. On the CI runner
        // it does not take: three launches with up to six seconds of settle
        // each, and the shell still renders light.
        //
        // The choice was then between no dark coverage at all and coverage of
        // a slightly weaker claim. This is the weaker claim: it proves the app
        // *renders* correctly in dark, and says nothing about whether it
        // follows the system setting. `AEUITestCase` names every screenshot
        // taken this way `darkforced` rather than `dark`, so the weaker
        // evidence can never be read as the stronger.
        //
        // Reads a launch argument, not a build flag: the shipping binary is
        // the one under test, and no player will ever pass this.
        .preferredColorScheme(
            ProcessInfo.processInfo.arguments.contains("-AEUITestDarkAppearance")
                ? .dark : nil)
        .accessibilityIdentifier(appearanceIdentifier)
        // The audio pipeline's state, as something a UI test can read.
        //
        // ~58 WAV files ship and none had ever been proven to reach a running
        // engine: `prepare()` swallows every failure by design (silence must
        // not crash the game), which also means a broken pipeline is
        // indistinguishable from a working one from the outside. This probe
        // is the one place the difference is visible to automation. Gated on
        // a launch argument so neither players nor VoiceOver ever meet it.
        .overlay(alignment: .topLeading) {
            if ProcessInfo.processInfo.arguments.contains("-AEUITestProbes") {
                Color.clear
                    .frame(width: 2, height: 2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("ae-audio-status")
                    .accessibilityValue(
                        "engine \(controller.feedback.engineIsRunning ? "running" : "stopped"), "
                        + "\(controller.feedback.missingAssets.count) assets missing")
                    .allowsHitTesting(false)
            }
        }
        // Every presentation the whole app can raise lives here, above the
        // three screen states — a rejection alert mounted on the tab view
        // could not appear over a sheet, and could not appear on the menu at
        // all, which is how "could not open that save" reached nobody
        // (UIUX_FORENSIC_AUDIT UI-004).
        .alert(rejectionTitle, isPresented: rejectionPresented,
               presenting: controller.lastRejection.map(Rejections.present)) { _ in
            Button("OK", role: .cancel) { controller.clearRejection() }
        } message: { presentation in
            Text(presentation.body)
        }
        .alert("Could not start", isPresented: startupFailurePresented,
               presenting: controller.startupFailure) { _ in
            Button("OK", role: .cancel) { controller.clearStartupFailure() }
        } message: { message in
            Text(message)
        }
    }

    private enum Screen: Equatable { case newGame, gameOver, playing }

    private var state: Screen {
        if !controller.hasGame { return .newGame }
        if controller.snapshot?.progression.gameOver == true { return .gameOver }
        return .playing
    }

    /// The refusal's own title, so the alert names what was refused rather
    /// than announcing "Not possible" for everything from an empty wallet to a
    /// runway that is too short.
    private var rejectionTitle: String {
        controller.lastRejection.map { Rejections.present($0).title } ?? "Not possible"
    }

    private var rejectionPresented: Binding<Bool> {
        Binding(
            get: { controller.lastRejection != nil },
            set: { presented in if !presented { controller.clearRejection() } })
    }

    private var startupFailurePresented: Binding<Bool> {
        Binding(
            get: { controller.startupFailure != nil },
            set: { presented in if !presented { controller.clearStartupFailure() } })
    }
}

/// The playing shell.
///
/// ## Why five tabs and not six
///
/// It was six — Home, Map, Routes, Fleet, Finance, World — and iOS shows four
/// plus an automatic *More* list once a tab bar passes five. Finance and World
/// therefore sat one level deeper than everything else, inside a system list
/// that looks nothing like the rest of the game, and the only route to saving
/// or quitting ran through it (UIUX_FORENSIC_AUDIT UI-001).
///
/// Routes and Fleet are the two halves of one question — what you fly, and
/// where you fly it — so they became one **Network** tab with a segmented
/// switch. Settings left the World hub for the Home toolbar, where a player
/// looks for settings. Nothing lost a level; two things gained one.
struct GameShell: View {
    @Environment(GameController.self) private var controller
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: Tab = .home

    enum Tab: Hashable, CaseIterable {
        case home, map, network, finance, world

        var title: String {
            switch self {
            case .home: "Home"
            case .map: "Map"
            case .network: "Network"
            case .finance: "Finance"
            case .world: "World"
            }
        }

        var icon: String {
            switch self {
            case .home: "house"
            case .map: "globe"
            case .network: "point.topleft.down.to.point.bottomright.curvepath"
            case .finance: "chart.bar"
            case .world: "bolt"
            }
        }
    }

    var body: some View {
        Group {
            // iPad and landscape get a sidebar rather than a phone tab bar
            // (docs/UI_ARCHITECTURE.md §2 — the adaptive shell that was
            // specified and never built, UI-013).
            if sizeClass == .regular {
                NavigationSplitView {
                    List(selection: sidebarSelection) {
                        ForEach(Tab.allCases, id: \.self) { tab in
                            Label(tab.title, systemImage: tab.icon).tag(tab)
                        }
                    }
                    .navigationTitle(controller.snapshot?.playerAirline?.name ?? "Airline Empire")
                    .listStyle(.sidebar)
                } detail: {
                    screen(for: selection)
                }
            } else {
                TabView(selection: $selection) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        screen(for: tab)
                            .tabItem { Label(tab.title, systemImage: tab.icon) }
                            .tag(tab)
                    }
                }
                .tint(AETheme.accent)
            }
        }
        // Above whichever tab is open: a milestone should not depend on the
        // player happening to be on the Home screen when it lands.
        .overlay(alignment: .top) {
            if let celebration = controller.celebration {
                CelebrationOverlay(celebration: celebration)
            }
        }
        .aeAnimation(AEMotion.content, value: controller.celebration)
        // A save the player asked for must say whether it worked (UI-012).
        .alert("Save", isPresented: saveOutcomePresented,
               presenting: controller.lastSaveOutcome) { _ in
            Button("OK", role: .cancel) { controller.clearSaveOutcome() }
        } message: { outcome in
            switch outcome {
            case .saved: Text("Your airline is saved.")
            case .failed(let message): Text(message)
            }
        }
    }

    @ViewBuilder
    private func screen(for tab: Tab) -> some View {
        switch tab {
        case .home: DashboardView()
        case .map: MapScreen()
        case .network: NetworkView()
        case .finance: FinanceView()
        case .world: OperationsView()
        }
    }

    /// A sidebar binds an optional selection; the shell always has a tab, so
    /// clearing the sidebar selection simply keeps the current one.
    private var sidebarSelection: Binding<Tab?> {
        Binding(get: { selection },
                set: { newValue in if let newValue { selection = newValue } })
    }

    private var saveOutcomePresented: Binding<Bool> {
        Binding(
            get: { controller.lastSaveOutcome != nil },
            set: { presented in if !presented { controller.clearSaveOutcome() } })
    }
}

struct GameOverView: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        ScrollView {
            VStack(spacing: AETheme.spacingL) {
                Image(systemName: "airplane.arrival")
                    .font(.system(size: 56))
                    .foregroundStyle(AETheme.mutedText)
                    .symbolEffect(.pulse)
                    .accessibilityHidden(true)
                Text("The airline has collapsed")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let dashboard = controller.snapshot?.dashboardModel() {
                    Text("\(dashboard.airlineName) flew its last flight in the \(Vocab.era(dashboard.era)) era.")
                        .foregroundStyle(AETheme.mutedText)
                        .multilineTextAlignment(.center)
                }

                // The post-mortem (docs/PLAYER_JOURNEY.md §6): what the run
                // was, and what ended it. One number was not a post-mortem.
                if let snapshot = controller.snapshot,
                   let player = snapshot.playerAirline {
                    RunSummaryCard(snapshot: snapshot, player: player)
                }

                // Without a way out this screen is a dead end (BUG-003).
                Button("Start a new airline") {
                    controller.quitToMenu()
                }
                .buttonStyle(.aePrimary)
                .padding(.top, AETheme.spacingS)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AETheme.spacingM)
            .padding(.vertical, AETheme.spacingL)
        }
        .background(AEGameBackdrop())
    }
}

/// The run, told back to the player: how big it got, what it earned across its
/// whole life, the best month and the best route, what it achieved, and the
/// seed — so the world that beat them can be played again.
struct RunSummaryCard: View {
    let snapshot: GameState
    let player: Airline

    var body: some View {
        VStack(spacing: AETheme.spacingM) {
            if let finance = snapshot.financeModel(for: player.id) {
                AECard {
                    VStack(alignment: .leading, spacing: AETheme.spacingS) {
                        AESectionHeader(text: "The run", systemImage: "flag.checkered")
                        summaryRow("Lifetime net profit") {
                            MoneyText(money: finance.lifetimeNetProfit)
                        }
                        if let best = bestMonth(finance) {
                            summaryRow("Best month") {
                                HStack(spacing: AETheme.spacingXS) {
                                    Text(String(format: "%04d-%02d", best.year, best.month))
                                        .font(.caption).foregroundStyle(AETheme.mutedText)
                                    MoneyText(money: best.netProfit)
                                }
                            }
                        }
                        summaryRow("Airports served") {
                            Text(Format.count(Int64(snapshot.dashboardModel()?
                                .destinationCount ?? 0)))
                                .monospacedDigit()
                        }
                        summaryRow("Flights flown") {
                            Text(Format.count(snapshot.progression.counters.flightsCompleted))
                                .monospacedDigit()
                        }
                        summaryRow("Passengers carried") {
                            Text(Format.count(snapshot.progression.counters.passengersCarried))
                                .monospacedDigit()
                        }
                    }
                }
            }

            if !snapshot.progression.milestones.isEmpty
                || !snapshot.progression.achievements.isEmpty {
                AECard {
                    VStack(alignment: .leading, spacing: AETheme.spacingS) {
                        AESectionHeader(text: "What it did", systemImage: "star")
                        ForEach(snapshot.progression.milestones, id: \.self) { code in
                            Label(Vocab.milestone(code), systemImage: "star.fill")
                                .font(.subheadline)
                        }
                        ForEach(snapshot.progression.achievements, id: \.self) { code in
                            Label(Vocab.achievement(code), systemImage: "rosette")
                                .font(.subheadline)
                        }
                    }
                }
            }

            AECard {
                VStack(alignment: .leading, spacing: AETheme.spacingS) {
                    AESectionHeader(text: "This world", systemImage: "globe")
                    Text("Seed \(String(snapshot.meta.worldSeed))")
                        .font(.subheadline.monospaced())
                    Text("Start a new airline with this seed to fly the same world again — the same markets, the same rivals, the same weather.")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func bestMonth(_ finance: FinanceModel) -> FinanceModel.MonthPoint? {
        finance.monthlySeries.max { $0.netProfit.cents < $1.netProfit.cents }
    }

    private func summaryRow<Value: View>(_ label: String,
                                         @ViewBuilder value: () -> Value) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            value().font(.subheadline)
        }
    }
}
