import SwiftUI
import AirlineEmpireCore

struct AEPageIntro: View {
    let title: String
    let subtitle: String
    let icon: String
    var tint: Color = AETheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AEClayIcon(systemName: icon, tint: tint, size: 52)
            Text(title).font(.system(.title2, design: .rounded, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

/// The actual aircraft category silhouette, lit like a small clay model.
struct AEAircraftMedallion: View {
    let category: AircraftCategory
    var tint: Color = AETheme.accent
    var size: CGFloat = 72

    var body: some View {
        AircraftShape(category: category)
            .fill(LinearGradient(colors: [tint.opacity(0.55), tint],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(AircraftShape(category: category).stroke(.white.opacity(0.5), lineWidth: 0.8))
            .rotationEffect(.degrees(32))
            .padding(size * 0.16)
            .frame(width: size, height: size)
            .shadow(color: tint.opacity(0.25), radius: 3, x: 2, y: 4)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

/// Opaque, inexpensive content surfaces beneath the interactive glass layer.
/// Gradients and a fine rim provide depth without sampling a blur for every row.
private struct AEClaySurface<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(LinearGradient(
                    colors: [AETheme.surfaceHighlight, AETheme.cardBackground],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                if let tint { shape.fill(tint.opacity(scheme == .dark ? 0.12 : 0.06)) }
            }
            .overlay {
                shape.stroke(contrast == .increased ? AETheme.mutedText : AETheme.surfaceRim,
                             lineWidth: contrast == .increased ? 1.5 : 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: AETheme.surfaceShadow.opacity(scheme == .dark ? 0.20 : 0.08),
                    radius: 10, x: 0, y: 5)
    }
}

extension View {
    func aeClay<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(AEClaySurface(shape: shape, tint: tint))
    }
}

/// Small sculpted symbols give each panel a recognisable silhouette.
struct AEClayIcon: View {
    let systemName: String
    var tint: Color = AETheme.accent
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.43, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.08), tint.opacity(0.21)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .stroke(AETheme.surfaceRim, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

/// Readable inset metrics; no live blur or repeating animation in a scrolling grid.
struct AEInstrument: View {
    let label: String
    let value: String
    var icon: String
    var tint: Color = AETheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            Text(label).font(AEType.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(tint.opacity(0.065), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

/// Native liquid glass where available, with an opaque accessibility fallback.
struct AEGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(AETheme.cardBackground, in: shape)
                .overlay(shape.stroke(tint ?? AETheme.surfaceRim, lineWidth: 1))
        } else if #available(iOS 26, *) {
            if let tint {
                content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
            } else {
                content.glassEffect(.regular.interactive(interactive), in: shape)
            }
        } else {
            content.background(.regularMaterial, in: shape)
                .overlay(shape.stroke(AETheme.surfaceRim, lineWidth: 1))
        }
    }
}

struct AEActionSurface: ViewModifier {
    let role: AEButtonRole

    @ViewBuilder
    func body(content: Content) -> some View {
        switch role {
        case .primary:
            content
                .background(LinearGradient(colors: [Color(red: 0.15, green: 0.48, blue: 0.79),
                                                    AETheme.actionBlue],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .shadow(color: AETheme.actionBlue.opacity(0.2), radius: 8, y: 4)
        case .secondary:
            content.aeGlass(in: Capsule(), tint: AETheme.accent.opacity(0.10), interactive: true)
        case .destructive:
            content.background(AETheme.negative.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(AETheme.negative.opacity(0.3), lineWidth: 1))
        case .tertiary:
            content
        }
    }
}
