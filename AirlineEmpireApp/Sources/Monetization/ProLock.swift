import SwiftUI
import AirlineEmpireCore

/// The bar that appears when an airline outgrows what the player has bought.
///
/// It is a bar and not a modal, and the difference is the whole point. The
/// airline is intact: every screen still reads, every command still works,
/// the ledger is still there. What stopped is time, and the bar says exactly
/// that — no countdown, no dark overlay, no "your progress is at risk". A
/// player who declines here still has a game to look at, which is the
/// difference between a wall and a hostage situation.
struct EraCeilingBar: View {
    @Environment(GameController.self) private var controller
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.dynamicTypeSize) private var typeSize

    private var reachedEra: Era? { controller.snapshot?.progression.era }

    var body: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingS) {
            HStack(spacing: AETheme.spacingS) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(AETheme.ember)
                Text(title)
                    .font(AEType.sectionTitle)
                Spacer(minLength: 0)
            }
            Text("Your airline earned it — the clock is what needs Pro. "
                 + "Everything you have built is still here and still saved.")
                .font(AEType.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                entitlements.present(.eraCeiling)
            } label: {
                Text(entitlements.displayPrice(.weekly) == nil
                     ? "See Pro" : "Continue with Pro")
                    .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
            }
            .buttonStyle(.aePrimary)
            .accessibilityIdentifier("ae-era-wall-cta")
        }
        .padding(AETheme.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(AETheme.ember.opacity(0.5)).frame(height: 1)
        }
        .accessibilityIdentifier("ae-era-wall")
    }

    private var title: String {
        guard let reachedEra else { return "The next era needs Pro" }
        return "\(EraNames.title(reachedEra)) era reached"
    }
}

/// Era names for the interface. `Era` is a Core enum with no display strings
/// — Core has no opinion about English — so the app supplies them once here
/// rather than in each screen that needs one.
enum EraNames {
    static func title(_ era: Era) -> String {
        switch era {
        case .startup: "Startup"
        case .regional: "Regional"
        case .national: "National"
        case .international: "International"
        case .empire: "Empire"
        }
    }
}

// MARK: - Lock affordances

/// The badge that marks a control as Pro.
///
/// Deliberately small and gold rather than a padlock over a greyed-out row.
/// A greyed row reads as broken; a badged row reads as *more game*, which is
/// what it is — and the row stays tappable, because a control that does
/// nothing when tapped is the exact defect this codebase has three bug
/// numbers for (BUG-029, BUG-030, BUG-032).
struct ProBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "crown.fill").font(.system(size: 8))
            Text("PRO")
        }
        .font(AEType.badge)
        .foregroundStyle(.black)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(AETheme.ember, in: Capsule())
        .accessibilityLabel("Requires Pro")
    }
}

// MARK: - Settings

/// The Pro section of Settings.
///
/// Apple requires a Restore Purchases control and functional Terms and
/// Privacy links to be reachable from inside the app, not only from the
/// paywall — a player who has dismissed the paywall must still be able to
/// restore. It doubles as the permanent, un-nagging way in: once the nudge
/// gives up after four refusals (`PaywallPolicy`), this row is the only place
/// the app ever mentions Pro again.
struct ProSection: View {
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section("Airline Empire Pro") {
            if entitlements.isPro {
                status
            } else {
                Button {
                    entitlements.present(.direct)
                } label: {
                    Label("See what Pro unlocks", systemImage: "crown.fill")
                }
                .accessibilityIdentifier("ae-settings-pro")

                Text("Free keeps the whole simulation and the first two eras. "
                     + "Pro opens the rest of the world.")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
            }

            Button {
                Task { await entitlements.restore() }
            } label: {
                Label("Restore purchases", systemImage: "arrow.clockwise")
            }
            .disabled(entitlements.isPurchasing)
            .accessibilityIdentifier("ae-settings-restore")

            if entitlements.entitlement.grantedBy?.isSubscription == true {
                // Deep link into the system sheet rather than a paragraph
                // explaining where Settings keeps subscriptions. Apple asks
                // for the path to be obvious; this is the shortest one.
                Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                    Label("Manage subscription", systemImage: "creditcard")
                }
            }

            Button("Terms of Use") { openURL(PaywallContent.termsURL) }
            Button("Privacy Policy") { openURL(PaywallContent.privacyURL) }
        }
    }

    @ViewBuilder
    private var status: some View {
        let entitlement = entitlements.entitlement
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(entitlement.grantedBy?.displayName ?? "Pro")
                    .font(AEType.body.weight(.semibold))
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
            }
        } icon: {
            Image(systemName: "crown.fill").foregroundStyle(AETheme.ember)
        }
        .accessibilityIdentifier("ae-settings-pro-active")
    }

    /// What the player's own subscription is doing, stated rather than left
    /// to be discovered when the game re-locks.
    private var statusDetail: String {
        let entitlement = entitlements.entitlement
        if entitlement.grantedBy == .lifetime {
            return "Yours permanently. Nothing renews."
        }
        if entitlement.isInBillingRetry {
            return "A renewal payment did not go through. Your game is still "
                + "unlocked while Apple retries."
        }
        guard let expires = entitlement.expiresAt else { return "Active." }
        let date = expires.formatted(date: .abbreviated, time: .omitted)
        return entitlement.willRenew ? "Renews \(date)." : "Ends \(date)."
    }
}
