import SwiftUI
import AirlineEmpireCore

struct RootView: View {
    @Environment(GameController.self) private var controller

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
                GameTabs().transition(.opacity)
            }
        }
        .animation(AEMotion.screen, value: state)
    }

    private enum Screen: Equatable { case newGame, gameOver, playing }

    private var state: Screen {
        if !controller.hasGame { return .newGame }
        if controller.snapshot?.progression.gameOver == true { return .gameOver }
        return .playing
    }
}

struct GameTabs: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Home", systemImage: "house") }
            MapScreen()
                .tabItem { Label("Map", systemImage: "globe") }
            RoutesView()
                .tabItem { Label("Routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            FleetView()
                .tabItem { Label("Fleet", systemImage: "airplane") }
            FinanceView()
                .tabItem { Label("Finance", systemImage: "chart.bar") }
            OperationsView()
                .tabItem { Label("World", systemImage: "bolt") }
        }
        .tint(AETheme.accent)
        .alert("Not possible", isPresented: rejectionPresented,
               presenting: controller.lastRejection) { _ in
            Button("OK", role: .cancel) { controller.clearRejection() }
        } message: { rejection in
            Text(rejection.message)
        }
    }

    private var rejectionPresented: Binding<Bool> {
        Binding(
            get: { controller.lastRejection != nil },
            set: { presented in if !presented { controller.clearRejection() } })
    }
}

struct GameOverView: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        VStack(spacing: AETheme.spacingL) {
            Image(systemName: "airplane.arrival")
                .font(.system(size: 56))
                .foregroundStyle(AETheme.mutedText)
                .symbolEffect(.pulse)
            Text("The airline has collapsed")
                .font(.title2.weight(.semibold))
            if let dashboard = controller.snapshot?.dashboardModel() {
                Text("\(dashboard.airlineName) flew its last flight. Final era: \(String(describing: dashboard.era)).")
                    .foregroundStyle(AETheme.mutedText)
                    .multilineTextAlignment(.center)
            }
            // The post-mortem trace (docs/PLAYER_JOURNEY.md §6) reads the
            // statement history; v1 shows the ledger-backed story.
            if let snapshot = controller.snapshot,
               let player = snapshot.playerAirline,
               let finance = snapshot.financeModel(for: player.id) {
                AECard {
                    VStack(alignment: .leading, spacing: AETheme.spacingS) {
                        Text("Lifetime result").font(.headline)
                        HStack {
                            Text("Net profit over the airline's life")
                            Spacer()
                            MoneyText(money: finance.lifetimeNetProfit)
                        }
                    }
                }
                .padding(.horizontal)
            }
            // Without a way out this screen is a dead end (BUG-003).
            Button("Start a new airline") {
                controller.quitToMenu()
            }
            .font(.headline)
            .buttonStyle(.borderedProminent)
            .padding(.top, AETheme.spacingS)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, AETheme.spacingM)
        .background(AEGameBackdrop())
    }
}
