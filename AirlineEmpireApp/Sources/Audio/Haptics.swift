#if canImport(UIKit)
import UIKit
#endif
import AirlineEmpireCore

/// The haptic vocabulary (docs/AUDIO_ARCHITECTURE.md §8).
///
/// Haptics say *how much* something mattered; sound says *what* it was. The
/// two are chosen per cue rather than paired automatically, because pairing
/// them everywhere is what makes a phone feel like a toy: a tab change that
/// buzzes as hard as a bankruptcy has told the player nothing.
///
/// The rule that keeps this honest: **nothing the simulation does on its own
/// schedule may vibrate the phone.** Flights depart every few minutes of game
/// time and would otherwise turn a fast-forward into a massage. Only things
/// the player caused, or things they must not miss, are felt.
enum HapticStyle: Equatable, Sendable {
    case selection
    case light
    case medium
    case heavy
    case success
    case warning
    case error
}

extension AudioCue {
    /// What this cue should feel like, or nil for the great majority that
    /// should feel like nothing at all.
    var haptic: HapticStyle? {
        switch self {
        // Interface: the player's own finger, so the lightest possible
        // acknowledgement and nothing more.
        case .uiSelect, .uiNavigate, .uiToggle:
            return .selection
        case .uiSheetOpen, .uiSheetClose:
            return nil          // The sheet's own movement is the feedback.
        case .uiConfirm:
            return .light
        case .uiCancel:
            return nil
        case .uiError:
            return .error

        // Commitments. A route and an aircraft are the two things a player
        // spends real money and real time on; they get weight.
        case .routeOpened:
            return .medium
        case .aircraftDelivered:
            return .heavy
        case .aircraftOrdered, .aircraftAssigned:
            return .medium
        case .aircraftSold, .leaseReturned, .routeClosed, .aircraftUnassigned:
            return .light

        // The first times. The whole point of the opening hour.
        case .firstRoute, .firstDeparture:
            return .medium
        case .firstArrival, .firstRevenue:
            return .success

        // Progression.
        case .missionCompleted, .milestoneReached, .achievementUnlocked,
             .capabilityCompleted:
            return .success
        case .eraAdvanced:
            return .heavy

        // Trouble the player must not scroll past.
        case .flightCancelled, .disruptionFlurry, .monthClosedLoss,
             .stormStarted, .strikeStarted, .fuelShockStarted, .airportClosed:
            return .warning
        case .administrationEntered, .collapse, .gameOver:
            return .error

        // Everything else — every routine flight, every forecast, every
        // month that merely went fine — is silent to the hand on purpose.
        default:
            return nil
        }
    }
}

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
