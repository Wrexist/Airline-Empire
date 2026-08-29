import SwiftUI
import AirlineEmpireCore

/// Design tokens (docs/UI_ARCHITECTURE.md §2): the single source of visual
/// truth. Screens compose these; no ad-hoc styling in feature views.
enum AETheme {
    // Spacing grid (pt).
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 16
    static let spacingL: CGFloat = 24

    static let cornerRadius: CGFloat = 14

    // Semantic colors (asset-catalog free v1; Phase 17 refines).
    static let accent = Color.blue
    static let positive = Color.green
    static let negative = Color.red
    static let caution = Color.orange
    static let mutedText = Color.secondary
    static let cardBackground = Color(.secondarySystemBackground)
    static let mapBackground = Color(red: 0.07, green: 0.10, blue: 0.16)
    static let mapLand = Color(red: 0.13, green: 0.17, blue: 0.24)
    static let playerRoute = Color.cyan
    static let rivalRoute = Color.gray.opacity(0.55)

    // MARK: - Dusk palette
    //
    // The onboarding and other "presentation" surfaces sit on a dusk sky
    // rather than the system background: it is the app icon's own palette
    // (docs/ASO.md §6), and it is what makes the first screen read as a
    // product rather than a settings pane. Gameplay screens keep the system
    // background — a dashboard is for reading numbers, not for atmosphere.
    static let duskTop = Color(red: 0.04, green: 0.07, blue: 0.14)
    static let duskBottom = Color(red: 0.10, green: 0.13, blue: 0.22)
    /// The warm horizon in the icon, used as a low, wide glow.
    static let ember = Color(red: 0.95, green: 0.66, blue: 0.23)
    /// Hairline for glass edges where the OS does not draw its own.
    static let glassEdge = Color.white.opacity(0.12)
}

/// Motion tokens (docs/UI_ARCHITECTURE.md §2). Screens name a feeling, not a
/// duration — so the whole app can be retimed in one place, and so nobody
/// invents a 0.37-second spring at 2am.
///
/// Three curves, because three is what a simulation needs:
///
/// - `selection` — a tap changed something. Fast enough to feel like the
///   finger did it (~0.2s), never bouncy: this fires dozens of times a session.
/// - `content` — data arrived or a card appeared. Slightly softer, so a
///   dashboard refreshing at 16× speed reads as movement rather than flicker.
/// - `screen` — a whole view swapped. The only one slow enough to notice, and
///   the only one that should be.
///
/// All three respect Reduce Motion through SwiftUI's own handling of
/// `withAnimation`; nothing here animates position over long distances, which
/// is the thing that actually makes people ill.
enum AEMotion {
    static let selection: Animation = .snappy(duration: 0.22)
    static let content: Animation = .smooth(duration: 0.32)
    static let screen: Animation = .smooth(duration: 0.42)
}

/// Centralized formatting (docs/UI_ARCHITECTURE.md §2): views never invent
/// number formats.
enum Format {
    static func money(_ money: Money) -> String {
        let dollars = Double(money.cents) / 100
        let magnitude = abs(dollars)
        let sign = dollars < 0 ? "−" : ""
        switch magnitude {
        case 1_000_000_000...:
            return "\(sign)¤\(String(format: "%.2f", magnitude / 1_000_000_000))B"
        case 1_000_000...:
            return "\(sign)¤\(String(format: "%.1f", magnitude / 1_000_000))M"
        case 10_000...:
            return "\(sign)¤\(String(format: "%.0f", magnitude / 1_000))k"
        default:
            return "\(sign)¤\(String(format: "%.0f", magnitude))"
        }
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    static func date(_ date: GameDate) -> String {
        String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
    }

    static func clock(_ date: GameDate) -> String {
        String(format: "%02d:%02d", date.hour, date.minute)
    }
}
