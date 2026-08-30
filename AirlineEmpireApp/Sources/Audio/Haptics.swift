#if canImport(UIKit)
import UIKit
#endif
import AirlineEmpireCore

/// Plays the haptic a cue asks for. The *choice* of haptic is Core's
/// (`AudioCue.haptic`), because it is a semantic decision and therefore
/// testable; this file is only the hands.

/// Plays haptics, with the generators kept alive rather than built per event.
///
/// `UIFeedbackGenerator` needs `prepare()` to be worth anything: a generator
/// created at the moment of use fires late, which feels like lag rather than
/// like feedback.
@MainActor
final class HapticEngine {
    #if canImport(UIKit)
    private let selection = UISelectionFeedbackGenerator()
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notice = UINotificationFeedbackGenerator()
    #endif

    func prepare() {
        #if canImport(UIKit)
        selection.prepare()
        light.prepare()
        medium.prepare()
        heavy.prepare()
        notice.prepare()
        #endif
    }

    func play(_ style: HapticStyle) {
        #if canImport(UIKit)
        switch style {
        case .selection: selection.selectionChanged()
        case .light: light.impactOccurred()
        case .medium: medium.impactOccurred()
        case .heavy: heavy.impactOccurred()
        case .success: notice.notificationOccurred(.success)
        case .warning: notice.notificationOccurred(.warning)
        case .error: notice.notificationOccurred(.error)
        }
        #endif
    }
}
