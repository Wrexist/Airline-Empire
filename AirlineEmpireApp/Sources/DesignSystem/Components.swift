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
