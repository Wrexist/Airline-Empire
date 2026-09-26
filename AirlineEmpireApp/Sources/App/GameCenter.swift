import Foundation
import GameKit
import Observation
import UIKit
import AirlineEmpireCore

/// The app's one owner of Game Center (docs/GAME_CENTER.md).
///
/// Optional in every sense. The game has no account and needs none: a
/// player who never signs in to Game Center loses nothing, nothing waits on
/// it, and nothing here can stop a session starting. That is why sign-in is
/// never raised on its own — Apple hands over a sign-in screen at launch, and
/// putting it over a new player's first minute (next to the first-run offer)
/// would be the worst possible moment. It is kept and shown only when the
/// player asks, from Settings.
///
/// What is reported comes from `GameCenterCatalog` in Core, which is where
/// the mapping is tested. This object only talks to GameKit.
@MainActor
@Observable
final class GameCenter {

    enum Status: Equatable {
        /// Not yet answered by GameKit.
        case checking
        /// Game Center is available and the player can sign in.
        case signedOut
        case signedIn(displayName: String)
        /// Restricted by the device, parental controls, or an error.
        case unavailable
        /// A UI-test process. GameKit's sign-in sheet would land over the
        /// first tap of every journey in `UITests/`, for the reason
        /// `Entitlements` pins UI tests to Pro.
        case disabled
    }

    private(set) var status: Status = .checking

    var isSignedIn: Bool {
        if case .signedIn = status { return true }
        return false
    }

    /// GameKit's own sign-in screen, held until the player asks for it.
    @ObservationIgnored private var pendingSignIn: UIViewController?

    /// What was last reported, so a snapshot four times a second does not
    /// become four reports a second.
    @ObservationIgnored private var reportedFingerprint: Int?

    /// The latest progress, kept so signing in mid-campaign can report
    /// everything already earned without waiting for the next milestone.
    @ObservationIgnored private var latestProgression: ProgressionState?
    @ObservationIgnored private var latestScores: [(GameCenterCatalog.Leaderboard, Int)] = []

    private let isEnabled: Bool

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        isEnabled = !arguments.contains { $0.hasPrefix("-AEUITest") }
    }

    // MARK: - Authentication

    func start() {
        guard isEnabled else {
            status = .disabled
            return
        }
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            // GameKit calls this on the main thread, but says so nowhere the
            // compiler can see; hop explicitly rather than assume.
            Task { @MainActor in
                self?.authenticationChanged(signIn: viewController, error: error)
            }
        }
    }

    private func authenticationChanged(signIn: UIViewController?, error: Error?) {
        if let signIn {
            pendingSignIn = signIn
            status = .signedOut
            return
        }
        pendingSignIn = nil
        let player = GKLocalPlayer.local
        guard player.isAuthenticated else {
            status = error == nil ? .signedOut : .unavailable
            return
        }
        status = .signedIn(displayName: player.displayName)
        // Everything earned so far, now that there is someone to report to.
        // Game Center ignores a report for an achievement already complete,
        // so this is what makes a reinstall or a second device converge.
        reportedFingerprint = nil
        if let latestProgression { reportAchievements(latestProgression) }
        submitScores()
    }

    /// Shows GameKit's sign-in screen, if it gave us one.
    ///
    /// When it did not — the player cancelled it once this launch, which
    /// GameKit remembers — the only way back is the system Settings app,
    /// and `settingsHint` says so.
    func signIn() {
        guard let pendingSignIn,
              let presenter = Self.topViewController() else { return }
        presenter.present(pendingSignIn, animated: true)
    }

    var canPresentSignIn: Bool { pendingSignIn != nil }

    /// Opens Game Center's own achievements and leaderboards.
    func openDashboard() {
        guard isSignedIn else { return }
        GKAccessPoint.shared.trigger(state: .dashboard) {}
    }

    // MARK: - Reporting

    /// Reports every achievement this campaign has earned, when that set has
    /// changed since the last report.
    func reportAchievements(_ progression: ProgressionState) {
        latestProgression = progression
        guard isSignedIn else { return }
        let fingerprint = GameCenterCatalog.fingerprint(of: progression)
        guard fingerprint != reportedFingerprint else { return }
        let earned = GameCenterCatalog.earned(by: progression)
        guard !earned.isEmpty else {
            reportedFingerprint = fingerprint
            return
        }
        let reports = earned.map { entry -> GKAchievement in
            let achievement = GKAchievement(identifier: entry.id)
            achievement.percentComplete = 100
            // The game already celebrates each of these with its own
            // overlay, at the moment it happens. Game Center's banner on top
            // of it would announce the same thing twice, in two voices.
            achievement.showsCompletionBanner = false
            return achievement
        }
        Task { @MainActor in
            do {
                try await GKAchievement.report(reports)
                reportedFingerprint = fingerprint
            } catch {
                // Offline, most likely. Leaving the fingerprint stale means
                // the next change — or the next sign-in — reports again.
            }
        }
    }

    /// Records the campaign's current scores for the next submission.
    func noteScores(_ scores: [(GameCenterCatalog.Leaderboard, Int)]) {
        latestScores = scores
    }

    /// Submits the recorded scores. Called when the app leaves the
    /// foreground rather than per tick: a leaderboard is a standing, and one
    /// submission per session is plenty for a number that only ever grows.
    func submitScores() {
        guard isSignedIn, !latestScores.isEmpty else { return }
        let player = GKLocalPlayer.local
        let scores = latestScores
        Task { @MainActor in
            for (board, value) in scores where value > 0 {
                try? await GKLeaderboard.submitScore(
                    value, context: 0, player: player,
                    leaderboardIDs: [board.id])
            }
        }
    }

    // MARK: - Presentation

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
