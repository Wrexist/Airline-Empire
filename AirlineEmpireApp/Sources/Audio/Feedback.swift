import Foundation
import Observation
import SwiftUI
import AirlineEmpireCore

/// The one thing views and the controller talk to about feedback
/// (docs/AUDIO_ARCHITECTURE.md §3).
///
/// Everything the game can be heard or felt to do goes through here, as a
/// semantic cue: `feedback.play(.routeOpened)`. No view knows a filename, a
/// volume, or whether a cue is also a haptic — which is what makes it
/// possible to re-voice the whole game by editing two files.
///
/// It owns three things and decides nothing about *whether* a simulation
/// moment deserves a sound: that lives in Core's `AudioDirector`, where it can
/// be tested. This class is the hands.
@MainActor
@Observable
final class Feedback {

    private let preferences: Preferences
    @ObservationIgnored private let audio = AudioEngine()
    @ObservationIgnored private let haptics = HapticEngine()

    /// Core's policy, one per game. Nil between games — which is precisely
    /// what stops the previous airline's history leaking into the next one
    /// (tasks/BUGS.md BUG-013).
    @ObservationIgnored private var director: AudioDirector?
    /// Monotonic seconds since the app started, handed to the director so its
    /// cooldowns are real-time and its tests can supply their own clock.
    @ObservationIgnored private let started = ContinuousClock.now

    /// Cues whose asset could not be loaded. Empty in a healthy build; the
    /// settings screen shows it when it is not, because a missing sound is
    /// otherwise indistinguishable from a working one.
    var missingAssets: [AudioCue] { audio.unavailable.sorted { $0.rawValue < $1.rawValue } }

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    // MARK: - Lifecycle

    func prepare() {
        audio.prepare()
        haptics.prepare()
    }

    func applicationDidEnterBackground() {
        audio.suspend()
    }

    func applicationWillEnterForeground() {
        audio.resume()
        refreshAmbience()
    }

    /// A new game, or a loaded one. Seeds the director from the state so a
    /// mature airline is never told it has just opened its first route, and
    /// drops everything the previous game left sounding.
    func beginSession(state: GameState) {
        audio.stopAll()
        director = AudioDirector(state: state)
        refreshAmbience()
    }

    /// Back to the menu. The director goes with the game.
    func endSession() {
        audio.stopAll()
        director = nil
    }

    // MARK: - Playing

    /// Plays a cue the *player* caused — a tap, a confirmation, a refusal.
    ///
    /// These bypass the director entirely. The director exists to thin out
    /// what the simulation emits on its own schedule; a sound the player's
    /// own finger asked for must never be rate-limited, because a swallowed
    /// tap reads as a dropped input.
    func play(_ cue: AudioCue) {
        emit(cue)
    }

    /// Hands the simulation's events to Core's policy and plays whatever
    /// comes back. Called once per snapshot refresh, never per event.
    ///
    /// It is called on every refresh even when `events` is empty, because the
    /// first-time moments are read from *state* rather than from events —
    /// "your first flight has landed" is true the moment the statistics say
    /// so, whether or not the arrival happened to be in this batch.
    func handle(events: [SimEvent], state: GameState, speed: SimSpeed) {
        guard director != nil else { return }
        let cues = director?.cues(for: events, state: state, speed: speed,
                                  now: elapsed) ?? []
        for cue in cues { emit(cue) }
    }

    private var elapsed: Double {
        let duration = started.duration(to: ContinuousClock.now)
        return Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
    }

    private func emit(_ cue: AudioCue) {
        if preferences.sound {
            audio.play(cue, gain: Float(preferences.soundVolume))
        }
        // Haptics are a separate decision from sound, not a companion to it:
        // most cues have no haptic at all, and a few are felt without being
        // heard (docs/AUDIO_ARCHITECTURE.md §8).
        if preferences.haptics, let style = cue.haptic {
            haptics.play(style)
        }
    }

    // MARK: - Ambience

    /// Starts, stops or re-levels the bed to match the current settings.
    /// Idempotent, so calling it from `onAppear` cannot stack loops.
    func refreshAmbience(_ cue: AudioCue = .ambienceWorld) {
        guard preferences.ambience, director != nil else {
            audio.stopAmbience()
            return
        }
        audio.startAmbience(cue, gain: Float(preferences.ambienceVolume) * 0.35)
    }

    /// Called when a setting changes, so a toggle takes effect on the sound
    /// already playing rather than only on the next one.
    func settingsChanged() {
        if !preferences.sound { audio.stopAll() }
        refreshAmbience()
    }
}

// MARK: - Environment

private struct FeedbackKey: EnvironmentKey {
    // A feedback object that was never prepared plays nothing, which is the
    // right behaviour for a preview and for any view rendered outside the app.
    @MainActor static let defaultValue = Feedback(preferences: Preferences(
        defaults: UserDefaults(suiteName: "ae.preview") ?? .standard))
}

extension EnvironmentValues {
    var feedback: Feedback {
        get { self[FeedbackKey.self] }
        set { self[FeedbackKey.self] = newValue }
    }
}

extension View {
    /// Plays a cue when `value` changes — the declarative form, for the many
    /// places where the interesting moment is a state change rather than a
    /// button action. `Hashable` rather than `Equatable`, to match
    /// `aeAnimation` and for the same reason: it erases cleanly.
    func aeFeedback(_ cue: AudioCue, on value: some Hashable) -> some View {
        modifier(FeedbackOnChange(cue: cue, value: AnyHashable(value)))
    }
}

private struct FeedbackOnChange: ViewModifier {
    @Environment(\.feedback) private var feedback
    let cue: AudioCue
    let value: AnyHashable

    func body(content: Content) -> some View {
        content.onChange(of: value) { _, _ in feedback.play(cue) }
    }
}
