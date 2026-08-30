/// What the player asked for, and what that resolves to per layer
/// (docs/AUDIO_ARCHITECTURE.md §7).
///
/// The *values* are persisted by the app in `UserDefaults`; the *rules* live
/// here. That split exists because the rules are where the bugs are — which
/// switch wins, whether mute survives a volume change, whether turning music
/// off can accidentally silence effects — and none of that is testable inside
/// a SwiftUI settings screen.
///
/// It never touches the save file. Audio settings are application
/// preferences, not simulation state, so nothing here can affect determinism
/// and no save-format change is needed to carry them.
public struct AudioSettings: Equatable, Sendable {

    // MARK: Stored choices

    /// One number over every layer, so a player can set a balance once and
    /// then turn the whole thing down without losing it.
    public var masterVolume: Double
    public var soundVolume: Double
    public var musicVolume: Double
    public var ambienceVolume: Double

    public var sound: Bool
    public var music: Bool
    public var ambience: Bool
    public var haptics: Bool

    /// Silences everything **without disturbing any choice underneath it**, so
    /// unmuting restores the mix the player built rather than a default one.
    /// This is why it is a separate flag rather than `masterVolume = 0`.
    public var muteAll: Bool

    /// The defaults a first session should want. Effects on, music on but
    /// quiet, ambience off — the bed is the setting most likely to be
    /// unwanted on a commute and the one nobody thinks to look for.
    public static let standard = AudioSettings(
        masterVolume: 1.0, soundVolume: 0.8, musicVolume: 0.45,
        ambienceVolume: 0.5,
        sound: true, music: true, ambience: false, haptics: true,
        muteAll: false)

    public init(masterVolume: Double, soundVolume: Double, musicVolume: Double,
                ambienceVolume: Double, sound: Bool, music: Bool,
                ambience: Bool, haptics: Bool, muteAll: Bool) {
        self.masterVolume = Self.clamp(masterVolume)
        self.soundVolume = Self.clamp(soundVolume)
        self.musicVolume = Self.clamp(musicVolume)
        self.ambienceVolume = Self.clamp(ambienceVolume)
        self.sound = sound
        self.music = music
        self.ambience = ambience
        self.haptics = haptics
        self.muteAll = muteAll
    }

    /// Clamps to 0...1, and sends anything non-finite to **zero** rather than
    /// to one. A NaN or an infinity here means a corrupted preference or a
    /// bad migration, and the safe failure for audio is silence: full volume
    /// from garbage input is the one outcome a player would actually mind.
    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }

    // MARK: Resolution

    /// The three continuous layers, named so the resolution rules can be
    /// stated once rather than per call site.
    public enum Layer: String, Equatable, Sendable, CaseIterable {
        case effects
        case music
        case ambience
    }

    /// The gain a layer should actually play at, 0...1.
    ///
    /// The order is the whole contract: **mute beats everything**, then the
    /// layer's own switch, then master, then the layer's own volume. A layer
    /// turned off is exactly zero rather than merely quiet, so nothing can
    /// leak through at a low master.
    public func gain(for layer: Layer) -> Double {
        guard !muteAll else { return 0 }
        switch layer {
        case .effects: return sound ? masterVolume * soundVolume : 0
        case .music: return music ? masterVolume * musicVolume : 0
        case .ambience: return ambience ? masterVolume * ambienceVolume : 0
        }
    }

    /// Which layer a cue belongs to.
    public func gain(for cue: AudioCue) -> Double {
        gain(for: cue.isLoop ? .ambience : .effects)
    }

    /// Whether haptics should fire. A separate question from sound on
    /// purpose: some players want a silent game they can still feel, and
    /// muting audio must not take that away.
    public var hapticsEnabled: Bool { haptics }

    /// True when nothing at all would be audible, so the engine can be idled
    /// rather than left running with nothing to do.
    public var isSilent: Bool {
        Layer.allCases.allSatisfy { gain(for: $0) == 0 }
    }
}

// MARK: - Persistence

/// The smallest thing a settings store has to be.
///
/// Declared here so `AudioSettings` can be loaded and saved by a test with a
/// dictionary, and by the app with `UserDefaults`, through the same code —
/// which is what makes "does this setting survive a relaunch" a question a
/// Linux test can answer.
public protocol AudioSettingsStore: AnyObject {
    func bool(forKey key: String) -> Bool?
    func double(forKey key: String) -> Double?
    func set(_ value: Bool, forKey key: String)
    func set(_ value: Double, forKey key: String)
}

extension AudioSettings {
    public enum Key {
        public static let master = "ae.masterVolume"
        public static let soundOn = "ae.sound"
        public static let soundVolume = "ae.soundVolume"
        public static let musicOn = "ae.music"
        public static let musicVolume = "ae.musicVolume"
        public static let ambienceOn = "ae.ambience"
        public static let ambienceVolume = "ae.ambienceVolume"
        public static let haptics = "ae.haptics"
        public static let muteAll = "ae.muteAll"
    }

    /// Reads settings from a store, falling back to the standard value for
    /// anything absent. A missing key is a *default*, never `false` or `0` —
    /// which is the classic way a fresh install ends up silent.
    public init(store: AudioSettingsStore) {
        let d = AudioSettings.standard
        self.init(
            masterVolume: store.double(forKey: Key.master) ?? d.masterVolume,
            soundVolume: store.double(forKey: Key.soundVolume) ?? d.soundVolume,
            musicVolume: store.double(forKey: Key.musicVolume) ?? d.musicVolume,
            ambienceVolume: store.double(forKey: Key.ambienceVolume) ?? d.ambienceVolume,
            sound: store.bool(forKey: Key.soundOn) ?? d.sound,
            music: store.bool(forKey: Key.musicOn) ?? d.music,
            ambience: store.bool(forKey: Key.ambienceOn) ?? d.ambience,
            haptics: store.bool(forKey: Key.haptics) ?? d.haptics,
            muteAll: store.bool(forKey: Key.muteAll) ?? d.muteAll)
    }

    public func write(to store: AudioSettingsStore) {
        store.set(masterVolume, forKey: Key.master)
        store.set(soundVolume, forKey: Key.soundVolume)
        store.set(musicVolume, forKey: Key.musicVolume)
        store.set(ambienceVolume, forKey: Key.ambienceVolume)
        store.set(sound, forKey: Key.soundOn)
        store.set(music, forKey: Key.musicOn)
        store.set(ambience, forKey: Key.ambienceOn)
        store.set(haptics, forKey: Key.haptics)
        store.set(muteAll, forKey: Key.muteAll)
    }
}
