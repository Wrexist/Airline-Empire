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
        // Both continuous layers were torn down on the way out; forcing a
        // re-derive is what brings them back on the next snapshot.
        lastMix = nil
        musicState = .menu
        audioHasMusic = false
        lastMusicGain = -1
    }

    /// A new game, or a loaded one. Seeds the director from the state so a
    /// mature airline is never told it has just opened its first route, and
    /// drops everything the previous game left sounding.
    func beginSession(state: GameState) {
        audio.stopAll()
        director = AudioDirector(state: state)
        // Every continuous piece of state resets with the game. Without this
        // a new airline inherits the last one's bed level and music state.
        lastMix = nil
        musicState = .menu
        audioHasMusic = false
        lastMusicGain = -1
        milestoneUntil = -1
        focus = .away
        hasSelection = false
    }

    /// Back to the menu. The director goes with the game.
    func endSession() {
        audio.stopAll()
        director = nil
        lastMix = nil
        musicState = .menu
        audioHasMusic = false
        lastMusicGain = -1
        milestoneUntil = -1
        clearMapFocus()
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
        // One question, answered in Core: mute, then the layer's switch, then
        // master, then the layer's own volume (`AudioSettings.gain(for:)`).
        let gain = preferences.audio.gain(for: cue)
        if gain > 0 { audio.play(cue, gain: Float(gain)) }
        // A milestone opens a short window in which the continuous layers sit
        // back, so the cue that marks the moment is not competing with a bed.
        if cue.isMilestone || cue.priority == .critical {
            milestoneUntil = elapsed + MusicDirector.milestoneHold
        }
        // Haptics are a separate decision from sound, not a companion to it:
        // most cues have no haptic at all, and a few are felt without being
        // heard (docs/AUDIO_ARCHITECTURE.md §8).
        // Haptics ask a different question on purpose: a player who mutes
        // the game may still want to feel it.
        if preferences.audio.hapticsEnabled, let style = cue.haptic {
            haptics.play(style)
        }
    }

    // MARK: - The continuous layer

    /// Where the player is looking, and what they have singled out. Set by
    /// the map; everything else leaves it `.away`, which is silence.
    ///
    /// Held here rather than passed through every call because the bed has to
    /// be re-derived on every snapshot, and a screen that is not the map
    /// should not have to say so four times a second.
    @ObservationIgnored private var focus: SoundscapeFocus = .away
    @ObservationIgnored private var hasSelection = false
    @ObservationIgnored private var lastMix: AmbienceMix?
    @ObservationIgnored private var musicState: MusicState = .menu
    @ObservationIgnored private var milestoneUntil: Double = -1

    /// Called by the map as the camera and selection change.
    ///
    /// Cheap and idempotent: it stores, and the next snapshot applies. Doing
    /// the work here instead would run it on every gesture frame.
    func setMapFocus(_ focus: SoundscapeFocus, hasSelection: Bool) {
        self.focus = focus
        self.hasSelection = hasSelection
    }

    /// The map is no longer on screen.
    func clearMapFocus() {
        focus = .away
        hasSelection = false
    }

    /// Re-derives the bed and the music state from the world.
    ///
    /// Called once per snapshot refresh, from the same place the cues are
    /// drained — so the continuous layer and the discrete one always describe
    /// the same instant.
    func updateSoundscape(state: GameState?, speed: SimSpeed,
                          stage: SolvencyModel.Stage) {
        applyAmbience(state: state, speed: speed, stage: stage)
        applyMusic(hasGame: state != nil, speed: speed, stage: stage)
    }

    private func applyAmbience(state: GameState?, speed: SimSpeed,
                               stage: SolvencyModel.Stage) {
        let ambienceGain = preferences.audio.gain(for: .ambience)
        guard ambienceGain > 0, let state,
              let player = state.playerAirline?.id else {
            if lastMix != nil { audio.stopAmbience(); lastMix = nil }
            return
        }
        let airborne = state.flights.values.reduce(into: 0) { count, flight in
            guard case .enRoute = flight.phase,
                  state.routes[flight.route]?.airline == player else { return }
            count += 1
        }
        let mix = AmbienceDirector.mix(focus: focus, airborne: airborne,
                                       speed: speed, hasSelection: hasSelection,
                                       stage: stage)
        guard mix != lastMix else { return }
        lastMix = mix
        guard let bed = mix.bed else {
            audio.stopAmbience()
            return
        }
        // Movement rides on top of level rather than replacing it: a busy
        // network is more *present* in its activity band without the bed
        // itself getting louder. The 0.3 floor is what stops a paused, empty
        // early game from being literally inaudible.
        let gain = ambienceGain * mix.level * (0.3 + 0.7 * mix.movement)
        audio.startAmbience(bed, gain: Float(gain))
    }

    private func applyMusic(hasGame: Bool, speed: SimSpeed,
                            stage: SolvencyModel.Stage) {
        let musicGain = preferences.audio.gain(for: .music)
        guard musicGain > 0 else {
            if musicState != .menu || audioHasMusic { audio.stopMusic() }
            musicState = .menu
            audioHasMusic = false
            lastMusicGain = -1
            return
        }
        // A milestone holds for a fixed span and then falls back, so a
        // celebration is a moment rather than a mode.
        let now = elapsed
        let celebrating = now < milestoneUntil
        let next = MusicDirector.state(hasGame: hasGame, speed: speed,
                                       stage: stage, celebrating: celebrating)
        let gain = Float(musicGain * MusicDirector.duck(for: next))
        guard next != musicState else {
            // Nothing changed. Re-levelling every snapshot is not free and,
            // more importantly, it is a call into the fade machinery four
            // times a second for no reason — so it happens only when the
            // level actually moved (BUG-018).
            if gain != lastMusicGain {
                lastMusicGain = gain
                audio.setMusic(MusicDirector.asset(for: next), gain: gain, fade: 0)
            }
            return
        }
        let fade = musicState.crossfadeSeconds(to: next)
        musicState = next
        lastMusicGain = gain
        audioHasMusic = true
        audio.setMusic(MusicDirector.asset(for: next), gain: gain, fade: fade)
    }

    @ObservationIgnored private var audioHasMusic = false
    @ObservationIgnored private var lastMusicGain: Float = -1

    /// Called when a setting changes, so a toggle takes effect on the sound
    /// already playing rather than only on the next one.
    func settingsChanged() {
        let settings = preferences.audio
        if settings.gain(for: .effects) == 0 { audio.stopAll() }
        if settings.gain(for: .music) == 0 {
            audio.stopMusic()
            musicState = .menu
            audioHasMusic = false
            lastMusicGain = -1
        }
        if settings.gain(for: .ambience) == 0 { audio.stopAmbience() }
        // Force the next snapshot to re-derive rather than short-circuit on
        // an unchanged mix.
        lastMix = nil
        // Nothing audible means the engine has nothing to do, and a running
        // engine is not free. Muting the game should cost nothing rather than
        // merely produce nothing.
        audio.setActive(!settings.isSilent)
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

extension View {
    /// The open/close pair for a sheet, as one modifier.
    ///
    /// Applied to a sheet's outermost container. Pushing onto a
    /// `NavigationStack` inside the sheet does not disappear that container,
    /// so a drill-down does not fire the closing sound — only the sheet
    /// actually going away does, including a swipe-dismiss, which an explicit
    /// call in the Cancel button would have missed.
    func aeSheetFeedback() -> some View {
        modifier(SheetFeedback())
    }
}

private struct SheetFeedback: ViewModifier {
    @Environment(\.feedback) private var feedback

    func body(content: Content) -> some View {
        content
            .onAppear { feedback.play(.uiSheetOpen) }
            .onDisappear { feedback.play(.uiSheetClose) }
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
