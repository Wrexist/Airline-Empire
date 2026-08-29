import Foundation
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

    /// The card radius, as the number cards actually use.
    ///
    /// Nine call sites wrote `AETheme.cornerRadius + 4`, which meant the token
    /// said 14 and the app drew 18 — a token that is not the source of truth
    /// is worse than no token (UIUX_FORENSIC_AUDIT UI-028).
    static let cornerRadius: CGFloat = 18
    /// The tighter radius, for capsule-adjacent controls and small chips.
    static let cornerRadiusSmall: CGFloat = 12

    /// The standard card shape, so nobody writes the radius out again.
    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    // Semantic colors (asset-catalog free v1; Phase 17 refines).
    //
    // The accent used to be the system blue — the accent of a utility, on a
    // game whose own identity is a dusk sky and an ember horizon
    // (UIUX_FORENSIC_AUDIT §9). This is that palette's blue: deep enough to
    // sit under white text, bright enough to read on the dusk backdrop, and
    // distinct from the cyan the map already spends on the player's routes.
    static let accent = Color(red: 0.24, green: 0.51, blue: 0.92)
    static let positive = Color.green
    static let negative = Color.red
    static let caution = Color.orange
    static let mutedText = Color.secondary

    // Badge hues. Five call sites reached past the tokens for `.purple`,
    // `.indigo` and `.teal`, which is exactly the drift a token set exists to
    // prevent (UIUX_FORENSIC_AUDIT UI-029).
    /// Fares and pricing.
    static let fare = Color(red: 0.55, green: 0.36, blue: 0.86)
    /// Assets the airline owns outright.
    static let owned = Color(red: 0.31, green: 0.35, blue: 0.76)
    /// Assets the airline rents.
    static let leased = Color(red: 0.17, green: 0.56, blue: 0.60)
    static let cardBackground = Color(.secondarySystemBackground)
    static let mapBackground = Color(red: 0.07, green: 0.10, blue: 0.16)
    static let mapLand = Color(red: 0.13, green: 0.17, blue: 0.24)
    /// The coastline itself, a shade up from the land so the silhouette reads.
    static let mapCoast = Color(red: 0.22, green: 0.28, blue: 0.37)
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

/// Reduce Motion, honoured on purpose rather than by luck.
///
/// The audit found the app relying entirely on SwiftUI's own defaults, which
/// soften some animations and leave others alone. A simulation whose screens
/// slide, roll digits and crossfade should ask the system directly and mean it.
struct AEMotionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: AnyHashable

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// Animate with one of the motion tokens, unless the player has asked the
    /// system for less movement.
    func aeAnimation(_ animation: Animation, value: some Hashable) -> some View {
        modifier(AEMotionModifier(animation: animation, value: AnyHashable(value)))
    }
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
            // Grouped, so ¤9999 does not read as a serial number
            // (UIUX_FORENSIC_AUDIT UI-031).
            return "\(sign)¤\(grouped(Int64(magnitude.rounded())))"
        }
    }

    /// Thousands separators for the reader's locale.
    static func grouped(_ value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
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

    /// "14 Mar" — the form that fits in a navigation bar beside a control.
    static func shortDate(_ date: GameDate) -> String {
        "\(date.day) \(monthAbbreviation(date.month))"
    }

    static func monthAbbreviation(_ month: Int) -> String {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard (1...12).contains(month) else { return "—" }
        return names[month - 1]
    }

    /// A count of days as a phrase, because "1 days" is how a game loses a
    /// player's trust in everything else it says.
    static func days(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }

    /// Whole numbers with thousands separators — `Format.money` compresses
    /// above ¤10k, but a passenger count should read exactly.
    static func count(_ value: Int64) -> String { grouped(value) }
}
