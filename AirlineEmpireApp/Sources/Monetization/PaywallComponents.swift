import SwiftUI
import AirlineEmpireCore

// MARK: - The header

/// The paywall's sky: a slow night flight across a great circle.
///
/// A crown on a gradient is the genre default and it says nothing about this
/// game. What this game is, from `docs/GAME_DESIGN.md` §2 pillar 4, is *the
/// network is the hero* — progress as visible geography — so the header draws
/// the one image the whole product is about: routes reaching further than the
/// player can currently fly. The three arcs are drawn to the same great-circle
/// curve the map uses, and the aircraft glyph rides the longest of them.
///
/// Cheap on purpose: three quadratic curves and a symbol, redrawn by a
/// `TimelineView` only while the sheet is on screen. Reduce Motion gets the
/// same picture, finished and still — the art is the arcs, not the movement.
struct PaywallSky: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Arc definitions in unit space: start, end, and how high the curve bows.
    private static let arcs: [(from: CGPoint, to: CGPoint, bow: CGFloat,
                               width: CGFloat, opacity: Double)] = [
        (CGPoint(x: -0.05, y: 0.74), CGPoint(x: 1.05, y: 0.40), 0.30, 2.0, 1.00),
        (CGPoint(x: -0.05, y: 0.90), CGPoint(x: 1.05, y: 0.66), 0.18, 1.2, 0.55),
        (CGPoint(x: 0.10, y: 1.02), CGPoint(x: 1.05, y: 0.86), 0.10, 1.0, 0.30),
    ]

    var body: some View {
        ZStack {
            if reduceMotion {
                sky(progress: 1)
            } else {
                TimelineView(.animation) { context in
                    sky(progress: Self.progress(at: context.date))
                }
            }
            emblem
        }
        .frame(height: 190)
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("Airline Empire Pro")
    }

    /// A 9-second loop: 0…1 draws the arcs, then they hold and fade back.
    /// Derived from the wall clock rather than kept as state so the animation
    /// costs nothing to own and cannot leak a timer.
    private static func progress(at date: Date) -> CGFloat {
        let period: Double = 9
        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period
        // Ease the draw into the first 70% and hold for the rest, so the
        // finished picture — which is the one that sells — is what is on
        // screen most of the time.
        let raw = min(phase / 0.7, 1)
        return CGFloat(raw * raw * (3 - 2 * raw))  // smoothstep
    }

    private func sky(progress: CGFloat) -> some View {
        Canvas { context, size in
            for arc in Self.arcs {
                let path = Self.path(arc, in: size)
                let drawn = path.trimmedPath(from: 0, to: progress)
                context.stroke(
                    drawn,
                    with: .linearGradient(
                        Gradient(colors: [
                            AETheme.ember.opacity(0.15 * arc.opacity),
                            AETheme.ember.opacity(0.95 * arc.opacity),
                        ]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: 0)),
                    style: StrokeStyle(lineWidth: arc.width, lineCap: .round))
            }
            // The aircraft, at the head of the leading arc. Drawn as a filled
            // triangle rather than an SF Symbol because `Canvas.resolve` on a
            // symbol costs a text layout per frame, and this runs at display
            // rate.
            if progress > 0.02, progress < 0.999 {
                let leading = Self.path(Self.arcs[0], in: size)
                if let point = leading.trimmedPath(from: 0, to: progress)
                    .currentPoint {
                    context.fill(Self.marker(at: point), with: .color(.white))
                }
            }
        }
    }

    private static func path(_ arc: (from: CGPoint, to: CGPoint, bow: CGFloat,
                                    width: CGFloat, opacity: Double),
                             in size: CGSize) -> Path {
        let start = CGPoint(x: arc.from.x * size.width, y: arc.from.y * size.height)
        let end = CGPoint(x: arc.to.x * size.width, y: arc.to.y * size.height)
        // The control point that makes a straight line bow like a great
        // circle: the midpoint, lifted. Same construction as the map's route
        // arcs (docs/MAP_ARCHITECTURE.md), one dimension simpler.
        let control = CGPoint(x: (start.x + end.x) / 2,
                              y: (start.y + end.y) / 2 - arc.bow * size.height)
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }

    private static func marker(at point: CGPoint) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: point.x + 5, y: point.y))
        path.addLine(to: CGPoint(x: point.x - 3.5, y: point.y - 3))
        path.addLine(to: CGPoint(x: point.x - 3.5, y: point.y + 3))
        path.closeSubpath()
        return path
    }

    private var emblem: some View {
        VStack(spacing: AETheme.spacingS) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [AETheme.ember.opacity(0.28), .clear],
                        center: .center, startRadius: 2, endRadius: 46))
                    .frame(width: 92, height: 92)
                Circle()
                    .strokeBorder(AETheme.ember.opacity(0.55), lineWidth: 1)
                    .frame(width: 62, height: 62)
                Image(systemName: "crown.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(AETheme.ember)
            }
            Text("AIRLINE EMPIRE PRO")
                .font(AEType.eyebrow)
                .tracking(1.6)
                .foregroundStyle(AETheme.ember)
        }
        .padding(.bottom, AETheme.spacingL)
    }
}

// MARK: - The counter bar

/// The four numbers, in one glass capsule with hairline dividers.
///
/// Its job is to make the size of what is behind the wall a *fact* before the
/// player reads a single benefit. Values come from the catalogue
/// (`PaywallContent.stats`), never typed.
struct PaywallStatBar: View {
    let stats: [PaywallContent.Stat]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Four columns of large type is four columns of hyphens. The
                // Dynamic Type screenshots in run 60 are the record of what
                // that looks like (`AEChipRow` has the same note).
                VStack(spacing: AETheme.spacingS) {
                    ForEach(stats, id: \.label) { stat in
                        HStack {
                            Text(stat.value).font(AEType.metric)
                                .foregroundStyle(AETheme.ember)
                            Text(stat.label).font(AEType.metricLabel)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(stats.enumerated()), id: \.element.label) { index, stat in
                        if index > 0 {
                            Rectangle()
                                .fill(AETheme.glassEdge)
                                .frame(width: 1, height: 30)
                        }
                        VStack(spacing: 2) {
                            Text(stat.value)
                                .font(AEType.metric)
                                .foregroundStyle(AETheme.ember)
                            Text(stat.label)
                                .font(AEType.caption)
                                .tracking(0.8)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.vertical, AETheme.spacingM)
        .padding(.horizontal, AETheme.spacingS)
        .aeGlass(in: AETheme.cardShape)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The benefit grid

/// What Pro unlocks: two columns at reading sizes, one when the type grows.
struct PaywallBenefits: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: Int { typeSize.isAccessibilitySize ? 1 : 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingM) {
            Text("EVERYTHING PRO UNLOCKS")
                .font(AEType.eyebrow)
                .tracking(1.2)
                .foregroundStyle(.secondary)

            let rows = Self.chunk(PaywallContent.benefits, into: columns)
            VStack(alignment: .leading, spacing: AETheme.spacingM) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: AETheme.spacingM) {
                        ForEach(row) { benefit in
                            item(benefit)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        // Keeps a final odd item at column width instead of
                        // letting it stretch across both.
                        if row.count < columns {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(AETheme.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: AETheme.cardShape)
        .overlay(AETheme.cardShape.stroke(AETheme.glassEdge, lineWidth: 0.5))
    }

    private func item(_ benefit: PaywallContent.Benefit) -> some View {
        HStack(alignment: .top, spacing: AETheme.spacingS) {
            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(AETheme.positive)
                .frame(width: 20, height: 20)
                .background(AETheme.positive.opacity(0.18), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(benefit.title)
                    .font(AEType.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(benefit.detail)
                    .font(AEType.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static func chunk(_ benefits: [PaywallContent.Benefit],
                              into size: Int) -> [[PaywallContent.Benefit]] {
        guard size > 1 else { return benefits.map { [$0] } }
        return stride(from: 0, to: benefits.count, by: size).map {
            Array(benefits[$0..<min($0 + size, benefits.count)])
        }
    }
}

// MARK: - A plan

/// One buyable tier.
///
/// Three things carry selection at once — an ember ring, a tinted ground and
/// a filled check — for the same reason `AEChoiceCard` does it: colour alone
/// is not a signal, and this is the control the whole screen exists to
/// operate.
///
/// The price sits on the trailing edge at `AEType.metric` and the intro line
/// sits *under the name*, not over the price. That arrangement is deliberate
/// and it is the compliance-critical part of this view: the amount the player
/// will be billed is the largest number on the card, and the discounted first
/// period never appears larger than it.
struct PaywallPlanCard: View {
    let tier: ProProduct
    let isSelected: Bool
    /// The recurring price, localised by StoreKit. `nil` while loading.
    let price: String?
    /// The introductory price, if this account may still take one.
    let introductoryPrice: String?
    /// "week" / "year" — the unit the price is per.
    let period: String
    /// Percent saved against a year of weekly billing, if it is worth saying.
    let savings: Int?
    /// The small print under the price, e.g. the per-week equivalent.
    let footnote: String?
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var shape: RoundedRectangle { AETheme.cardShape }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: AETheme.spacingM) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AETheme.ember
                                     : Color.secondary.opacity(0.5))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: AETheme.spacingS) {
                        Text(tier.displayName)
                            .font(AEType.sectionTitle)
                            .foregroundStyle(.primary)
                        if let savings {
                            Text("SAVE \(savings)%")
                                .font(AEType.badge)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(AETheme.ember, in: Capsule())
                        }
                    }
                    Text(tier.renewalDescription)
                        .font(AEType.secondary)
                        .foregroundStyle(.secondary)
                    if let introductoryPrice {
                        Text("First \(period): \(introductoryPrice)")
                            .font(AEType.secondary.weight(.semibold))
                            .foregroundStyle(AETheme.positive)
                    }
                    if let footnote {
                        Text(footnote)
                            .font(AEType.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                priceBlock
            }
            .padding(AETheme.spacingM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
            .background(isSelected ? AETheme.ember.opacity(0.10) : Color.white.opacity(0.04),
                        in: shape)
            .overlay(shape.stroke(isSelected ? AETheme.ember.opacity(0.85)
                                  : AETheme.glassEdge,
                                  lineWidth: isSelected ? 1.5 : 0.5))
        }
        .buttonStyle(.aePress)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var priceBlock: some View {
        if let price {
            VStack(alignment: .trailing, spacing: 0) {
                Text(price)
                    .font(AEType.metric)
                    .foregroundStyle(.primary)
                if tier.isSubscription, !typeSize.isAccessibilitySize {
                    Text("/\(period)")
                        .font(AEType.secondary)
                        .foregroundStyle(.secondary)
                }
            }
            .layoutPriority(1)
        } else {
            // A skeleton, not a guessed price. The one thing this view must
            // never do is render a number StoreKit did not supply.
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 62, height: 20)
                .accessibilityLabel("Loading price")
        }
    }
}
