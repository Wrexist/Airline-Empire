import SwiftUI
import AirlineEmpireCore

/// Game Center in Settings: where the player signs in, if they want to, and
/// the way into Game Center's own achievements and leaderboards.
///
/// The only place sign-in is offered (see `GameCenter` for why it is never
/// raised on its own).
struct GameCenterSection: View {
    @Environment(GameCenter.self) private var gameCenter

    var body: some View {
        if gameCenter.status != .disabled {
            Section("Game Center") {
                switch gameCenter.status {
                case .signedIn(let name):
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(AEType.body.weight(.semibold))
                            Text("\(GameCenterCatalog.achievements.count) achievements · \(GameCenterCatalog.leaderboards.count) leaderboards")
                                .font(.caption)
                                .foregroundStyle(AETheme.mutedText)
                        }
                    } icon: {
                        Image(systemName: "gamecontroller.fill")
                            .foregroundStyle(AETheme.positive)
                    }
                    Button {
                        gameCenter.openDashboard()
                    } label: {
                        Label("Achievements and leaderboards", systemImage: "trophy")
                    }
                    .accessibilityIdentifier("ae-settings-game-center")
                case .signedOut:
                    if gameCenter.canPresentSignIn {
                        Button {
                            gameCenter.signIn()
                        } label: {
                            Label("Sign in to Game Center", systemImage: "gamecontroller")
                        }
                        .accessibilityIdentifier("ae-settings-game-center-sign-in")
                    } else {
                        Text("To use Game Center, sign in under Settings → Game Center on this device, then return here.")
                            .font(.caption)
                            .foregroundStyle(AETheme.mutedText)
                    }
                    Text("Optional. Earns achievements for the milestones you already reach, and ranks your airline by passengers, network and fleet. Nothing in the game needs it.")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                case .checking:
                    Label("Checking Game Center…", systemImage: "gamecontroller")
                        .foregroundStyle(AETheme.mutedText)
                case .unavailable:
                    Text("Game Center is not available on this device right now. It may be restricted, or offline.")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                case .disabled:
                    EmptyView()
                }
            }
        }
    }
}
