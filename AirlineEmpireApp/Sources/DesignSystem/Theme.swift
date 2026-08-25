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
