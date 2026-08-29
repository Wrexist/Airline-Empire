import SwiftUI
import Charts
import AirlineEmpireCore

/// Reusable component library (Phase 14). Touch-first: every interactive
/// element ≥ 44pt; color never carries meaning alone.

/// The surface every screen is built from.
///
/// Glass rather than a flat fill (iOS 26 `glassEffect`, `.ultraThinMaterial`
/// below — see `aeGlass`): a simulation is a lot of stacked panels, and glass
/// is what keeps a stack of them reading as depth instead of as a wall of
/// grey rectangles. `tint` is for cards that carry a state — a warning, a
/// selection — and is deliberately weak, because a tinted card should be
/// noticed without being read as an alert.
struct AECard<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AETheme.cornerRadius + 4, style: .continuous)
    }

    var body: some View {
        content
            .padding(AETheme.spacingM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .aeGlass(in: shape, tint: tint)
    }
}

/// The ground the game screens stand on.
///
/// Glass needs something behind it or it renders as flat grey. This is a very
/// quiet vertical gradient in semantic colours, so it is correct in both
/// appearances and never competes with the numbers — the dusk sky belongs to
/// the onboarding, which is presentation; a dashboard is for reading.
struct AEGameBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
            startPoint: .top,
            endPoint: .bottom)
        .ignoresSafeArea()
    }
}

extension View {
    /// The standard game-screen surface: the quiet gradient behind, and the
    /// system's own opaque scroll background out of the way so it shows.
    ///
    /// One modifier rather than three lines repeated on six screens — and the
    /// place to change if the backdrop ever becomes something richer.
    func aeScreenBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AEGameBackdrop())
    }

    /// A list row that reads as a floating glass card rather than a table cell.
    ///
    /// `List` gives keyboard handling, swipe actions and cell recycling that a
    /// hand-rolled `ScrollView` of cards does not; this keeps all of that and
    /// changes only how the row looks. The separator goes because the card
    /// edge already separates, and the inset is tightened because a card needs
    /// less breathing room than a rule does.
    func aeListRow() -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: AETheme.spacingM,
                                      bottom: 5, trailing: AETheme.spacingM))
            .listRowBackground(
                Color.clear
                    .aeGlass(in: RoundedRectangle(cornerRadius: AETheme.cornerRadius + 4,
                                                  style: .continuous))
                    .padding(.vertical, 4)
            )
    }
}

/// A quiet, tracked section heading. Repeated across screens so that "what am
/// I looking at" is answered the same way everywhere.
struct AESectionHeader: View {
    let text: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: AETheme.spacingXS) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2)
            }
            Text(text.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
        }
        .foregroundStyle(AETheme.mutedText)
        .accessibilityAddTraits(.isHeader)
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
                    .contentTransition(.numericText())
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
        .aeGlass(in: RoundedRectangle(cornerRadius: AETheme.cornerRadius + 4,
                                      style: .continuous))
        // The simulation changes these while you watch. Rolling the digits
        // instead of swapping them is the difference between a dashboard that
        // is alive and one that flickers — and at 16× speed it is the only
        // way the numbers stay readable at all.
        .contentTransition(.numericText())
        .animation(AEMotion.content, value: value)
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
            .contentTransition(.numericText())
            .animation(AEMotion.content, value: money.cents)
            .foregroundStyle(money.isNegative ? AETheme.negative
                             : money == .zero ? .primary : AETheme.positive)
    }
}

/// Monthly net profit.
///
/// This was hand-rolled, and it was wrong: every column was a centred `VStack`
/// of `Spacer / bar / rule / bar / Spacer`, so the column's content height
/// varied with the bar and **the zero line sat at a different y for every
/// month**. A chart on the finance screen that misplaces its own baseline is
/// worse than no chart. It also carried no axis, no month labels and no
/// values, so a reader could not tell which bar was which month.
///
/// Swift Charts, which `docs/UI_ARCHITECTURE.md` §2 specified from the start:
/// one baseline by construction, real axes, and accessible values for free.
struct MonthlyBars: View {
    let points: [FinanceModel.MonthPoint]

    private struct Point: Identifiable {
        let id: Int
        let label: String
        let shortLabel: String
        let dollars: Double
        let money: Money
    }

    private var series: [Point] {
        points.enumerated().map { index, point in
            Point(id: index,
                  label: String(format: "%04d-%02d", point.year, point.month),
                  shortLabel: Format.monthAbbreviation(point.month),
                  dollars: Double(point.netProfit.cents) / 100,
                  money: point.netProfit)
        }
    }

    var body: some View {
        Chart(series) { point in
            BarMark(
                x: .value("Month", point.label),
                y: .value("Net profit", point.dollars)
            )
            .foregroundStyle(point.dollars < 0 ? AETheme.negative : AETheme.positive)
            .accessibilityLabel(point.label)
            .accessibilityValue(Format.money(point.money))
        }
        // A zero rule that is actually at zero, once, for the whole chart.
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let dollars = value.as(Double.self) {
                        Text(Format.money(Money(cents: Int64(dollars * 100))))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            // Twenty-four labels do not fit on a phone; every third is enough
            // to read the shape and place a month.
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(String(label.suffix(2)))
                            .font(.caption2)
                    }
                }
            }
        }
        .accessibilityLabel("Monthly net profit chart")
    }
}

/// A loading state that says what it is loading. Five screens used to show a
/// bare, unlabelled `ProgressView` (UIUX_FORENSIC_AUDIT UI-022).
struct LoadingState: View {
    let message: String

    var body: some View {
        VStack(spacing: AETheme.spacingS) {
            ProgressView()
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AETheme.mutedText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

/// An empty state is a screen the player reached on purpose, so it gets the
/// same surface as a full one — never a bare label floating on the background.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: AETheme.spacingS) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(AETheme.accent.opacity(0.85))
                .padding(.bottom, AETheme.spacingXS)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AETheme.mutedText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AETheme.spacingL)
        .padding(.horizontal, AETheme.spacingM)
        .aeGlass(in: RoundedRectangle(cornerRadius: AETheme.cornerRadius + 4,
                                      style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Speed control shown on every primary screen — the most-tapped control in
/// the game, and the one that tells you whether time is moving.
///
/// A single glass capsule with a selection that *slides* between the speeds
/// (`matchedGeometryEffect`) rather than four separate bordered buttons that
/// blink. It is one control, so it should look like one object; and because
/// the eye follows the moving pill, the current speed is readable at a glance
/// without reading any label.
struct SpeedControl: View {
    @Environment(GameController.self) private var controller
    @Namespace private var indicator

    private static let speeds: [SimSpeed] = [.paused, .x1, .x4, .x16]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.speeds, id: \.self) { speed in
                let isSelected = controller.speed == speed
                Button {
                    controller.setSpeed(speed)
                } label: {
                    Text(label(for: speed))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Color.white : AETheme.mutedText)
                        .frame(minWidth: 44, minHeight: 38)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(AETheme.accent)
                                    .matchedGeometryEffect(id: "speed", in: indicator)
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(voiceOverLabel(for: speed))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }

            Divider().frame(height: 18)

            Button {
                controller.advanceToNextMorning()
            } label: {
                Image(systemName: "sunrise")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AETheme.ember)
                    .frame(minWidth: 44, minHeight: 38)
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Advance to next morning")
        }
        .padding(3)
        .aeGlass(in: Capsule(style: .continuous))
        .animation(AEMotion.selection, value: controller.speed)
        .sensoryFeedback(.selection, trigger: controller.speed) { _, _ in
            controller.preferences.haptics
        }
    }

    private func label(for speed: SimSpeed) -> String {
        switch speed {
        case .paused: "❙❙"
        case .x1: "1×"
        case .x4: "4×"
        case .x16: "16×"
        }
    }

    private func voiceOverLabel(for speed: SimSpeed) -> String {
        switch speed {
        case .paused: "Pause"
        case .x1: "Normal speed"
        case .x4: "Four times speed"
        case .x16: "Sixteen times speed"
        }
    }
}

/// The compact time control, for every screen that is not Home or the Map.
///
/// Time control lived on two of six screens, and no other screen showed the
/// date — so from Routes, Fleet, Finance or World a player could not pause,
/// could not change speed, and could not tell whether the world was even
/// running (UIUX_FORENSIC_AUDIT UI-010). The full `SpeedControl` capsule is
/// ~240pt wide and does not belong in a navigation bar beside a title, so
/// secondary screens get this: the date, the current speed, and a menu with
/// every speed and the jump to morning.
struct TimeMenuButton: View {
    @Environment(GameController.self) private var controller

    private static let speeds: [SimSpeed] = [.paused, .x1, .x4, .x16]

    var body: some View {
        Menu {
            Picker("Speed", selection: speedBinding) {
                ForEach(Self.speeds, id: \.self) { speed in
                    Label(Self.name(for: speed), systemImage: Self.icon(for: speed))
                        .tag(speed)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button {
                controller.advanceToNextMorning()
            } label: {
                Label("Advance to next morning", systemImage: "sunrise")
            }
        } label: {
            HStack(spacing: AETheme.spacingXS) {
                Image(systemName: Self.icon(for: controller.speed))
                    .font(.caption)
                    .foregroundStyle(controller.speed == .paused
                                     ? AETheme.caution : AETheme.accent)
                if let date = controller.snapshot?.currentDate {
                    Text(Format.shortDate(date))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(AEMotion.content, value: date.day)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Time controls")
        .accessibilityValue(accessibilityValue)
    }

    private var speedBinding: Binding<SimSpeed> {
        Binding(get: { controller.speed },
                set: { controller.setSpeed($0) })
    }

    private var accessibilityValue: String {
        guard let date = controller.snapshot?.currentDate else {
            return Self.name(for: controller.speed)
        }
        return "\(Format.date(date)), \(Self.name(for: controller.speed))"
    }

    static func name(for speed: SimSpeed) -> String {
        switch speed {
        case .paused: "Paused"
        case .x1: "Normal speed"
        case .x4: "Four times speed"
        case .x16: "Sixteen times speed"
        }
    }

    static func icon(for speed: SimSpeed) -> String {
        switch speed {
        case .paused: "pause.fill"
        case .x1: "play.fill"
        case .x4: "forward.fill"
        case .x16: "forward.end.fill"
        }
    }
}

extension View {
    /// The toolbar every secondary game screen carries: time, always reachable.
    func aeTimeToolbar() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) { TimeMenuButton() }
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
/// ring, and a filled checkmark — because colour alone is not a signal, and
/// because a checkmark-only row is hard to read at a glance.
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
