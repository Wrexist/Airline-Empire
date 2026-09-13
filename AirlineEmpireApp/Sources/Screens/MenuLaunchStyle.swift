import SwiftUI

/// The menu's floating action: native interactive glass, with a material
/// fallback for older systems and an opaque alternative for accessibility.
struct MenuLaunchStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, prominent: prominent)
    }

    private struct Surface: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.isEnabled) private var isEnabled

        private var solid: Bool { reduceTransparency || contrast == .increased }
        private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        var body: some View {
            surface
                .contentShape(shape)
                .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.975)
                .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1) : 0.45)
                .shadow(color: .black.opacity(configuration.isPressed ? 0.08 : 0.18),
                        radius: configuration.isPressed ? 4 : 12, y: 6)
                .animation(reduceMotion ? .easeOut(duration: 0.12)
                           : .spring(response: 0.3, dampingFraction: 0.72),
                           value: configuration.isPressed)
        }

        private var label: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(solid && prominent ? AETheme.duskTop : .white)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, minHeight: 58)
        }

        @ViewBuilder private var surface: some View {
            if solid {
                label.background(prominent ? AETheme.ember : AETheme.mapLand, in: shape)
            } else if #available(iOS 26.0, *) {
                label
                    .glassEffect(.clear.tint(prominent ? AETheme.ember.opacity(0.18) : nil)
                        .interactive(), in: shape)
                    .overlay {
                        shape.stroke(LinearGradient(
                            colors: [.white.opacity(0.38), .white.opacity(0.06),
                                     AETheme.ember.opacity(prominent ? 0.28 : 0.1)],
                            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                            .allowsHitTesting(false)
                    }
            } else {
                label
                    .background(prominent ? AETheme.ember.opacity(0.18) : .clear, in: shape)
                    .background(.ultraThinMaterial, in: shape)
                    .overlay {
                        shape.stroke(LinearGradient(
                            colors: [.white.opacity(0.5), .white.opacity(0.08),
                                     AETheme.ember.opacity(prominent ? 0.4 : 0.12)],
                            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    }
            }
        }
    }
}
