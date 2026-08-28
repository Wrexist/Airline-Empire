import SwiftUI
import AirlineEmpireCore

/// Reusable component library (Phase 14). Touch-first: every interactive
/// element ≥ 44pt; color never carries meaning alone.

struct AECard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(AETheme.spacingM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AETheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AETheme.cornerRadius))
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var trend: Trend = .neutral

    enum Trend { case up, down, neutral }

    var body: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingXS) {
            Text(label)
                .font(.caption)
                .foregroundStyle(AETheme.mutedText)
            HStack(spacing: AETheme.spacingXS) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                switch trend {
                case .up:
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(AETheme.positive)
                        .font(.caption)
                case .down:
                    Image(systemName: "arrow.down.right")
                        .foregroundStyle(AETheme.negative)
                        .font(.caption)
                case .neutral:
                    EmptyView()
                }
            }
        }
        .padding(AETheme.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AETheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AETheme.cornerRadius))
    }
}

struct AEBadge: View {
    let text: String
    var color: Color = AETheme.accent
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon).font(.caption2)
            }
            Text(text).font(.caption.weight(.medium))
        }
        .padding(.horizontal, AETheme.spacingS)
        .padding(.vertical, 3)
        .background(color.opacity(0.16))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

/// Money with semantic color + sign (never hue alone: sign carries meaning).
struct MoneyText: View {
    let money: Money

    var body: some View {
        Text(Format.money(money))
            .monospacedDigit()
            .foregroundStyle(money.isNegative ? AETheme.negative
                             : money == .zero ? .primary : AETheme.positive)
    }
}

/// Minimal monthly bar chart (net profit); Phase 17 may upgrade to Swift
/// Charts once macOS validation is running.
struct MonthlyBars: View {
    let points: [FinanceModel.MonthPoint]

    var body: some View {
        GeometryReader { geometry in
            let maxAbs = max(1, points.map { abs($0.netProfit.cents) }.max() ?? 1)
            let barWidth = max(3, geometry.size.width / CGFloat(max(1, points.count)) - 3)
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    let height = CGFloat(abs(point.netProfit.cents))
                        / CGFloat(maxAbs) * geometry.size.height / 2
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if !point.netProfit.isNegative {
                            Rectangle().fill(AETheme.positive)
                                .frame(width: barWidth, height: max(2, height))
                        }
                        Rectangle().fill(AETheme.mutedText.opacity(0.4))
                            .frame(width: barWidth, height: 1)
                        if point.netProfit.isNegative {
                            Rectangle().fill(AETheme.negative)
                                .frame(width: barWidth, height: max(2, height))
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .accessibilityLabel("Monthly net profit chart")
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: AETheme.spacingS) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(AETheme.mutedText)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AETheme.mutedText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(AETheme.spacingL)
    }
}

/// Speed control shown on every primary screen.
struct SpeedControl: View {
    @Environment(GameController.self) private var controller

    var body: some View {
        HStack(spacing: AETheme.spacingS) {
            ForEach([SimSpeed.paused, .x1, .x4, .x16], id: \.self) { speed in
                Button {
                    controller.setSpeed(speed)
                } label: {
                    Text(label(for: speed))
                        .font(.callout.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .tint(controller.speed == speed ? AETheme.accent : .secondary)
            }
            Button {
                controller.advanceToNextMorning()
            } label: {
                Image(systemName: "sunrise")
                    .frame(minWidth: 44, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Advance to next morning")
        }
    }

    private func label(for speed: SimSpeed) -> String {
        switch speed {
        case .paused: "⏸"
        case .x1: "1×"
        case .x4: "4×"
        case .x16: "16×"
        }
    }
}


// MARK: - Liquid Glass

/// Liquid Glass where the OS has it, a material where it does not.
///
/// `glassEffect` arrived in iOS 26 and the deployment target is iOS 17
/// (project.yml), so every call is availability-gated. The fallback is not an
/// apology: `.ultraThinMaterial` with a hairline edge is what Liquid Glass
/// replaced, and on iOS 17–25 it is still the right answer.
///
/// One entry point rather than `if #available` scattered through the screens:
/// when the deployment target rises, this is the only file that changes.
extension View {
    @ViewBuilder
    func aeGlass<S: Shape>(in shape: S,
                           tint: Color? = nil,
                           interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            switch (tint, interactive) {
            case (.some(let color), true):
                self.glassEffect(.regular.tint(color).interactive(), in: shape)
            case (.some(let color), false):
                self.glassEffect(.regular.tint(color), in: shape)
            case (.none, true):
                self.glassEffect(.regular.interactive(), in: shape)
            case (.none, false):
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(AETheme.glassEdge, lineWidth: 0.5))
        }
    }
}

/// The dusk sky the presentation screens sit on.
///
/// Two gradients rather than one: a vertical night, and a wide ember low on
/// the screen where the icon puts its horizon. The ember is deliberately
/// beneath the content and very dilute — it should be felt as depth, not seen
/// as a shape.
struct AEDuskBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [AETheme.duskTop, AETheme.duskBottom],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [AETheme.ember.opacity(0.22), .clear],
                center: UnitPoint(x: 0.5, y: 1.02),
                startRadius: 0,
                endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

/// A small labelled fact: an icon, a value, and nothing else.
///
/// Used on the start cards to replace one line of prose with three readable
/// signals. Every value comes from the content pack — market size, business
/// lean, weather exposure are real numbers in `airports.json`, not flavour.
struct AEChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .imageScale(.small)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

/// A selectable glass card: the shape the onboarding uses for every choice.
///
/// Selection is carried by three things at once — a tinted glass, an accent
/// ring, and a filled checkmark — because colour alone is not a signal
/// (docs/UI_ARCHITECTURE.md, and the reason the old checkmark-only row was
/// hard to read at a glance).
struct AEChoiceCard<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AETheme.cornerRadius + 4, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: AETheme.spacingM) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AETheme.accent : Color.secondary.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .padding(AETheme.spacingM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
            .aeGlass(in: shape,
                     tint: isSelected ? AETheme.accent.opacity(0.30) : nil,
                     interactive: true)
            .overlay(shape.stroke(isSelected ? AETheme.accent.opacity(0.75) : .clear,
                                  lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
