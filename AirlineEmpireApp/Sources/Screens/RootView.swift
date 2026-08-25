import SwiftUI
import AirlineEmpireCore

struct RootView: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        if !controller.hasGame {
            NewGameView()
        } else if controller.snapshot?.progression.gameOver == true {
            GameOverView()
        } else {
            GameTabs()
        }
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
        .alert(item: rejectionBinding) { rejection in
            Alert(title: Text("Not possible"),
                  message: Text(rejection.message),
                  dismissButton: .default(Text("OK")) { controller.clearRejection() })
        }
    }

    private var rejectionBinding: Binding<IdentifiedRejection?> {
        Binding(
            get: { controller.lastRejection.map(IdentifiedRejection.init) },
            set: { _ in controller.clearRejection() })
    }
}

struct IdentifiedRejection: Identifiable {
    let rejection: CommandRejection
    var id: String { rejection.code }
    var message: String { rejection.message }

    init(_ rejection: CommandRejection) {
        self.rejection = rejection
    }
}

struct GameOverView: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        VStack(spacing: AETheme.spacingL) {
            Image(systemName: "airplane.arrival")
                .font(.system(size: 56))
                .foregroundStyle(AETheme.mutedText)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
