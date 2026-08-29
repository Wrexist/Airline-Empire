import SwiftUI
import AirlineEmpireCore

/// The warning cascade (docs/PLAYER_JOURNEY.md §6, UIUX_FORENSIC_AUDIT
/// UI-005).
///
/// `SolvencySystem` has always run a daily countdown: below the overdraft
/// floor for `administrationGraceDays` and the airline is restructured — fleet
/// fire-sold, reputation scarred, creditors paid a haircut. None of that was
/// on screen. The player's first notice was one line in the feed, *after* it
/// had happened, which is the exact opposite of the game's own second pillar:
/// the world is never unfair, and every consequence is traceable.
///
/// So: a banner that escalates. Quiet when the runway is short, loud and
/// counting when the countdown is running, and never present when the airline
/// is simply healthy.
struct SolvencyBanner: View {
    let model: SolvencyModel
    /// Shown when the game paused itself for this, so "why did time stop?"
    /// is answered where it happened.
    var autoPaused: Bool = false

    var body: some View {
        if model.stage != .healthy {
            AECard(tint: tint.opacity(0.22)) {
                VStack(alignment: .leading, spacing: AETheme.spacingS) {
                    HStack(spacing: AETheme.spacingS) {
                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundStyle(tint)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title).font(.headline)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(AETheme.mutedText)
                        }
                        Spacer(minLength: 0)
                    }
                    Text(advice)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if autoPaused {
                        Label("Time is paused so you can act.", systemImage: "pause.circle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(tint)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title). \(subtitle). \(advice)")
        }
    }

    private var tint: Color {
        model.stage == .danger ? AETheme.negative : AETheme.caution
    }

    private var icon: String {
        model.stage == .danger ? "exclamationmark.octagon.fill"
            : "exclamationmark.triangle.fill"
    }

    private var title: String {
        switch model.stage {
        case .danger:
            return model.nextFailureIsFatal
                ? "Your airline is about to fail for good"
                : "Your airline is heading into administration"
        case .watch:
            return "Cash is running low"
        case .healthy:
            return ""
        }
    }

    private var subtitle: String {
        switch model.stage {
        case .danger:
            if let days = model.daysUntilAdministration {
                let dayWord = days == 1 ? "day" : "days"
                return "\(Format.money(model.cash)) · \(days) \(dayWord) left"
            }
            return Format.money(model.cash)
        case .watch:
            if let months = model.monthsOfRunway {
                return "\(Format.money(model.cash)) · about \(String(format: "%.1f", months)) months at last month's burn"
            }
            return "\(Format.money(model.cash)) · overdrawn"
        case .healthy:
            return ""
        }
    }

    private var advice: String {
        switch model.stage {
        case .danger:
            let consequence = model.nextFailureIsFatal
                ? "A second failure ends the game — there is no second restructuring."
                : "Administration sells your idle aircraft at fire-sale prices and scars your reputation."
            return "Below \(Format.money(model.overdraftFloor)) for \(model.graceDays) days and creditors step in. \(consequence) Sell or return aircraft, close a loss-making route, or borrow."
        case .watch:
            return "Nothing has happened yet — this is the window to act in. Check which routes are losing money, and whether an idle aircraft is costing you a lease."
        case .healthy:
            return ""
        }
    }
}

/// "Time stopped, and here is why." Fast-forward must never skip the one
/// decision that ends the game (docs/CORE_LOOP.md §2).
struct AutoPauseNotice: View {
    let reason: GameController.AutoPauseReason
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: AETheme.spacingS) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(AETheme.caution)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
            Button("Dismiss", action: dismiss)
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(AETheme.accent)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, AETheme.spacingM)
        .padding(.vertical, AETheme.spacingS)
        .aeGlass(in: Capsule(style: .continuous), tint: AETheme.caution.opacity(0.2))
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        switch reason {
        case .solvencyDanger: "Paused — your airline is running out of money."
        }
    }
}

/// A labelled progress row: what is being asked for, how far along, and the
/// numbers behind the bar. Used by era gates, capability programs and
/// missions, so the three read as one system.
struct AEProgressRow: View {
    let title: String
    let detail: String
    let fraction: Double
    var isMet: Bool = false
    var icon: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: AETheme.spacingS) {
            Image(systemName: isMet ? "checkmark.circle.fill" : (icon ?? "circle"))
                .foregroundStyle(isMet ? AETheme.positive : AETheme.mutedText)
                .accessibilityHidden(true)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: AETheme.spacingXS) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.subheadline.weight(isMet ? .regular : .medium))
                    Spacer(minLength: AETheme.spacingS)
                    Text(detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isMet ? AETheme.positive : AETheme.mutedText)
                }
                if !isMet {
                    ProgressView(value: fraction)
                        .tint(AETheme.accent)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail)\(isMet ? ", complete" : "")")
    }
}

/// A destructive action that asks first, because selling an aircraft or
/// closing a route cannot be undone and the app used to do both on one
/// unguarded tap (UIUX_FORENSIC_AUDIT UI-006).
///
/// Honours the player's own setting: someone who has turned confirmations off
/// has said they know what these buttons do.
struct ConfirmableButton<Label: View>: View {
    @Environment(GameController.self) private var controller
    let title: String
    let message: String
    let confirmTitle: String
    let role: ButtonRole?
    let action: () -> Void
    @ViewBuilder var label: Label

    @State private var asking = false

    var body: some View {
        Button(role: role) {
            if controller.preferences.confirmDestructive {
                asking = true
            } else {
                action()
            }
        } label: {
            label
        }
        .confirmationDialog(title, isPresented: $asking, titleVisibility: .visible) {
            Button(confirmTitle, role: role ?? .destructive, action: action)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}


/// A moment for something earned.
///
/// Milestones, era advances, finished capability programs and completed
/// missions all used to arrive as a single grey line in the feed, which is a
/// strange way to treat the only events in the game that mean "you did it"
/// (UIUX_FORENSIC_AUDIT UI-014). This is deliberately brief and
/// non-blocking — it never takes a tap to dismiss, and it never interrupts
/// what the player is doing.
struct CelebrationOverlay: View {
    @Environment(GameController.self) private var controller
    let celebration: GameController.Celebration

    var body: some View {
        HStack(spacing: AETheme.spacingM) {
            Image(systemName: celebration.icon)
                .font(.title2)
                .foregroundStyle(AETheme.ember)
                .symbolEffect(.bounce, value: celebration.id)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(celebration.title).font(.headline)
                Text(celebration.detail)
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(AETheme.spacingM)
        .aeGlass(in: RoundedRectangle(cornerRadius: AETheme.cornerRadius + 4,
                                      style: .continuous),
                 tint: AETheme.ember.opacity(0.2))
        .padding(.horizontal, AETheme.spacingM)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .sensoryFeedback(.success, trigger: celebration.id) { _, _ in
            controller.preferences.haptics
        }
        .task(id: celebration.id) {
            // Long enough to read, short enough never to be in the way.
            try? await Task.sleep(for: .seconds(4))
            withAnimation(AEMotion.content) { controller.dismissCelebration() }
        }
    }
}
