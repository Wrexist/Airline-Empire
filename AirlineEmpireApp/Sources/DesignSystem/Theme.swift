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
    // The map's own palette (docs/MAP_ARCHITECTURE.md §2). Near-black ocean,
    // land a few points above it, coast a few points above that — the whole
    // geography sits inside a narrow value range so it can never compete with
    // the network drawn over it.
    static let mapBackground = Color(red: 0.043, green: 0.063, blue: 0.106)
    /// Deep water, for the vertical gradient that gives the plane depth.
    static let mapDeep = Color(red: 0.024, green: 0.039, blue: 0.075)
    static let mapLand = Color(red: 0.098, green: 0.129, blue: 0.184)
    /// The coastline itself, a shade up from the land so the silhouette reads.
    static let mapCoast = Color(red: 0.169, green: 0.220, blue: 0.298)
    /// Meridians and parallels: present, never read as data.
    static let mapGraticule = Color(red: 0.35, green: 0.45, blue: 0.60).opacity(0.10)
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

/// A press state for the app's own tappable surfaces.
///
/// SwiftUI's `.plain` button style on iOS gives no press feedback whatsoever:
/// the label simply sits there while the finger is down, and the first
/// evidence that a tap registered is whatever happens after it. Twenty-two
/// call sites across this app used it — every card, row and pill the player
/// touches — which is most of why the interface felt weightless to press
/// (MASTER PROMPT 3 §24).
///
/// This keeps `.plain`'s complete absence of chrome, which is why it was
/// chosen, and adds the one thing it was missing: the surface acknowledges the
/// finger. The scale is small on purpose — a game about running an airline
/// should not bounce.
///
/// Reduce Motion drops the scale and keeps the dim, because a fade is not
/// motion and removing the acknowledgement entirely would make the setting
/// cost the player their feedback.
struct AEPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration)
    }

    /// `isEnabled` is read here rather than on the style itself.
    ///
    /// A `ButtonStyle` is not a `View`; its environment is captured when the
    /// style is created and does not track later changes, so a button that
    /// became disabled kept full opacity. A nested `View` re-reads it.
    private struct Surface: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.972)
                .opacity(opacity)
                .animation(reduceMotion ? .easeOut(duration: 0.12) : AEMotion.selection,
                           value: configuration.isPressed)
        }

        private var opacity: Double {
            if !isEnabled { return 0.45 }
            return configuration.isPressed ? 0.78 : 1
        }
    }
}

extension ButtonStyle where Self == AEPressStyle {
    /// The app's tappable-surface style. Use instead of `.plain` anywhere the
    /// player is meant to feel that they hit something.
    static var aePress: AEPressStyle { AEPressStyle() }
}

// MARK: - Typography

/// The type scale, by role (docs/DESIGN_SYSTEM.md §2).
///
/// The app had 291 `.font(...)` call sites and no type tokens at all. Every
/// one named a *system size* — `.caption`, `.subheadline` — which says how big
/// the text is and nothing about what it is for. So `.caption` was
/// simultaneously the metric label, the supporting sentence, the badge and the
/// timestamp, and there was no way to restyle "every metric label" or even to
/// find them. That is the actual cause of the weak hierarchy this phase was
/// asked to fix: not that the sizes were wrong, but that nothing recorded
/// which of them meant what.
///
/// These are roles. Pick by what the text *is*; the size follows.
///
/// The ladder, loosely: `screenTitle` > `sectionTitle` > `metric` > `body` >
/// `secondary` > `caption`. Weight carries hierarchy far more cheaply than
/// size on a phone, so the sizes stay close together and the weights do the
/// work — which is also what keeps Dynamic Type from tearing layouts apart.
enum AEType {
    /// The one number a screen exists to show. Rare, by design.
    static let hero = Font.system(.largeTitle, design: .rounded, weight: .semibold)
        .monospacedDigit()

    /// A screen's own title, where the navigation bar is not carrying it.
    static let screenTitle = Font.title3.weight(.semibold)

    /// The heading over a group of related rows, where the heading is a
    /// sentence rather than a label.
    static let sectionTitle = Font.subheadline.weight(.semibold)

    /// The small uppercase, letter-spaced heading `AESectionHeader` draws.
    ///
    /// Kept at caption size deliberately: uppercase with tracking already
    /// reads as a heading, so size would be a second signal doing the same
    /// job, and at subheadline it starts competing with the content beneath
    /// it. This is the size iOS itself uses for grouped-list headers.
    static let eyebrow = Font.caption.weight(.semibold)

    /// A figure the player reads as a number: cash, load factor, a count.
    /// Monospaced digits, so a value that ticks does not jitter its neighbours.
    static let metric = Font.title3.weight(.semibold).monospacedDigit()

    /// A figure in a dense row or tile, where `metric` would dominate.
    static let metricCompact = Font.subheadline.weight(.semibold).monospacedDigit()

    /// The label naming a metric. Deliberately quiet: the number is the point.
    static let metricLabel = Font.caption

    /// Ordinary prose and list rows.
    static let body = Font.subheadline

    /// The same weight of content, one step back — a row's supporting detail.
    static let secondary = Font.caption

    /// Timestamps, footnotes, units. The smallest thing the app should ask
    /// anyone to read.
    static let caption = Font.caption2

    /// Text inside a badge or pill.
    static let badge = Font.caption2.weight(.semibold)

    /// An airport or aircraft code, where the fixed width is the meaning.
    static let code = Font.subheadline.weight(.semibold).monospaced()
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
///
/// Everything numeric goes through `FormatStyle`, which reads the reader's
/// locale. That is not a localization nicety — `String(format: "%.1f")` prints
/// `3.5` to a player in Paris who writes `3,5`, and it did so on every screen
/// in this app. Two things stay deliberately fixed:
///
/// - **`$`**, as a money mark rather than as a currency.
///
///   This was `¤` (U+00A4, the generic currency sign), on the reasoning that
///   the world is fictional and naming a real currency would be a lie. Sound
///   intent, failed execution: `¤` is drawn as a hollow box with legs in most
///   system faces, so on a screen it reads as a font-fallback error rather
///   than as money — "is this build broken?", not "this is a neutral unit".
///   That was invisible until AE-032 put actual screenshots in front of a
///   human, who pointed at it immediately.
///
///   `$` is read in a management game as "money", not as US dollars — the
///   genre has used it that way for thirty years. It renders in every font at
///   every size, which the symbol it replaces does not. The fiction is carried
///   by the world, not by the glyph.
/// - **The ISO game date.** `2031-03-14` is unambiguous everywhere, which a
///   date in a game about global schedules should be.
enum Format {
    static func money(_ money: Money) -> String {
        let dollars = Double(money.cents) / 100
        let magnitude = abs(dollars)
        let sign = dollars < 0 ? "−" : ""
        switch magnitude {
        case 1_000_000_000...:
            return "\(sign)$\(decimal(magnitude / 1_000_000_000, places: 2))B"
        case 1_000_000...:
            return "\(sign)$\(decimal(magnitude / 1_000_000, places: 1))M"
        case 10_000...:
            return "\(sign)$\(decimal(magnitude / 1_000, places: 0))k"
        default:
            // Grouped, so $9999 does not read as a serial number
            // (UIUX_FORENSIC_AUDIT UI-031).
            return "\(sign)$\(grouped(Int64(magnitude.rounded())))"
        }
    }

    /// A fraction as a whole-number percentage, in the reader's locale.
    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    /// A decimal with a fixed number of places, in the reader's locale.
    static func decimal(_ value: Double, places: Int) -> String {
        value.formatted(.number.precision(.fractionLength(places))
            .grouping(.automatic))
    }

    /// Thousands separators for the reader's locale.
    static func grouped(_ value: Int64) -> String {
        value.formatted(.number)
    }

    /// Deliberately ISO, and deliberately not localized — see the note above.
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
        count == 1 ? "1 day" : "\(grouped(Int64(count))) days"
    }

    /// Whole numbers with thousands separators — `Format.money` compresses
    /// above $10k, but a passenger count should read exactly.
    static func count(_ value: Int64) -> String { grouped(value) }
}
