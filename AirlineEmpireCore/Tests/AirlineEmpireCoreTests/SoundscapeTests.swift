import Testing
@testable import AirlineEmpireCore

/// The continuous audio policy (docs/AUDIO_ARCHITECTURE.md §6).
///
/// The product rule this suite exists to defend is the phase brief's central
/// one: **the game must not get louder as the airline grows — it must get
/// richer.** That is a property, and properties are testable without a
/// speaker: scale must move movement and never level, speed must move density
/// and never pitch, and no combination of inputs may produce a bed louder
/// than the one the player asked for.
@Suite("Soundscape direction")
struct SoundscapeTests {

    // MARK: - Ambience

    @Test("Away from the map there is no bed at all")
    func awayIsSilent() {
        for airborne in [0, 5, 400] {
            for speed in SimSpeed.allCases {
                let mix = AmbienceDirector.mix(focus: .away, airborne: airborne,
                                               speed: speed)
                #expect(mix == .silent)
                #expect(mix.bed == nil)
            }
        }
    }

    /// The rule the whole design rests on. A hundred aircraft must not be
    /// louder than two — only busier.
    @Test("Growth changes movement, never level")
    func growthChangesMovementNotLevel() {
        let small = AmbienceDirector.mix(focus: .regional, airborne: 2, speed: .x1)
        let large = AmbienceDirector.mix(focus: .regional, airborne: 200, speed: .x1)
        #expect(small.level == large.level)
        #expect(large.movement > small.movement)
    }

    @Test("Movement saturates, so a huge network is not chaos")
    func movementSaturates() {
        let big = AmbienceDirector.mix(focus: .local, airborne: 200, speed: .x1)
        let huge = AmbienceDirector.mix(focus: .local, airborne: 2000, speed: .x1)
        #expect(big.movement == huge.movement)
        #expect(huge.movement <= 1)
    }

    /// Zoom is presence. The world view is a diagram; the local view is a
    /// place.
    @Test("Closer is more present, and world zoom is nearly silent")
    func zoomDrivesPresence() {
        let world = AmbienceDirector.mix(focus: .world, airborne: 10, speed: .x1)
        let regional = AmbienceDirector.mix(focus: .regional, airborne: 10, speed: .x1)
        let local = AmbienceDirector.mix(focus: .local, airborne: 10, speed: .x1)
        #expect(world.level < regional.level)
        #expect(regional.level < local.level)
        #expect(world.level < 0.3)
        // And no layer is ever loud: the whole range is under 3x.
        #expect(local.level / world.level < 3.0)
    }

    @Test("Pausing keeps the world and stops the activity")
    func pauseThinsMovement() {
        let running = AmbienceDirector.mix(focus: .regional, airborne: 20, speed: .x1)
        let paused = AmbienceDirector.mix(focus: .regional, airborne: 20, speed: .paused)
        #expect(paused.bed == running.bed)
        #expect(paused.level == running.level)
        #expect(paused.movement < running.movement * 0.3)
    }

    /// The anti-arcade rule: 16x must not simply be "more of everything".
    @Test("Sixteen times is not busier than four times")
    func fastForwardDoesNotEscalate() {
        let x4 = AmbienceDirector.mix(focus: .regional, airborne: 12, speed: .x4)
        let x16 = AmbienceDirector.mix(focus: .regional, airborne: 12, speed: .x16)
        #expect(x16.movement <= x4.movement)
    }

    @Test("A failing airline sounds thinner, not louder")
    func strainRecedes() {
        let healthy = AmbienceDirector.mix(focus: .regional, airborne: 10,
                                           speed: .x1, stage: .healthy)
        let watch = AmbienceDirector.mix(focus: .regional, airborne: 10,
                                         speed: .x1, stage: .watch)
        let danger = AmbienceDirector.mix(focus: .regional, airborne: 10,
                                          speed: .x1, stage: .danger)
        #expect(watch.level < healthy.level)
        #expect(danger.level < watch.level)
    }

    @Test("Selecting something earns detail, but only up close")
    func selectionAddsDetailOnlyWhenClose() {
        let worldPlain = AmbienceDirector.mix(focus: .world, airborne: 10, speed: .x1)
        let worldPicked = AmbienceDirector.mix(focus: .world, airborne: 10,
                                               speed: .x1, hasSelection: true)
        #expect(worldPlain.level == worldPicked.level)

        let localPlain = AmbienceDirector.mix(focus: .local, airborne: 10, speed: .x1)
        let localPicked = AmbienceDirector.mix(focus: .local, airborne: 10,
                                               speed: .x1, hasSelection: true)
        #expect(localPicked.level > localPlain.level)
    }

    /// The hard ceiling. No combination of zoom, scale, speed and selection
    /// may produce a bed louder than full — the level is a multiplier on the
    /// player's own setting, and exceeding 1 would quietly override it.
    @Test("No input combination can push the bed past full")
    func levelIsAlwaysBounded() {
        for focus in SoundscapeFocus.allCases {
            for airborne in [0, 1, 24, 500] {
                for speed in SimSpeed.allCases {
                    for selected in [true, false] {
                        for stage in [SolvencyModel.Stage.healthy, .watch, .danger] {
                            let mix = AmbienceDirector.mix(
                                focus: focus, airborne: airborne, speed: speed,
                                hasSelection: selected, stage: stage)
                            #expect(mix.level >= 0 && mix.level <= 1)
                            #expect(mix.movement >= 0 && mix.movement <= 1)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Music

    @Test("No game means the menu, whatever else is true")
    func noGameIsMenu() {
        #expect(MusicDirector.state(hasGame: false, speed: .x16,
                                    stage: .danger, celebrating: true) == .menu)
    }

    @Test("The clock decides between planning and operating")
    func clockChoosesPlanningOrOperating() {
        #expect(MusicDirector.state(hasGame: true, speed: .paused) == .planning)
        #expect(MusicDirector.state(hasGame: true, speed: .x1) == .operating)
        #expect(MusicDirector.state(hasGame: true, speed: .x16) == .operating)
    }

    @Test("Crisis outranks the clock; a milestone outranks the crisis")
    func precedenceIsDeliberate() {
        #expect(MusicDirector.state(hasGame: true, speed: .paused,
                                    stage: .danger) == .crisis)
        #expect(MusicDirector.state(hasGame: true, speed: .x1,
                                    stage: .danger) == .crisis)
        // A player who achieves something while failing still achieved it.
        #expect(MusicDirector.state(hasGame: true, speed: .x1, stage: .danger,
                                    celebrating: true) == .milestone)
    }

    @Test("Watch is not yet a crisis")
    func watchIsNotCrisis() {
        #expect(MusicDirector.state(hasGame: true, speed: .x1, stage: .watch)
                == .operating)
    }

    /// Every transition must be able to name a crossfade, and none may cut.
    @Test("Every state transition crossfades")
    func transitionsAlwaysCrossfade() {
        for from in MusicState.allCases {
            for to in MusicState.allCases {
                #expect(from.crossfadeSeconds(to: to) > 0)
                #expect(from.crossfadeSeconds(to: to) <= 5)
            }
        }
    }

    /// The architecture must be correct with an empty library — a state
    /// without a track is silence, not a crash and not a wrong track.
    @Test("A state without a track resolves to nothing, not to another track")
    func missingTrackIsSilenceNotSubstitution() {
        #expect(MusicDirector.asset(for: .milestone) == nil)
        let named = MusicState.allCases.compactMap { MusicDirector.asset(for: $0) }
        #expect(Set(named).count == named.count)
    }

    @Test("Only a milestone ducks what is under it")
    func onlyMilestoneDucks() {
        for state in MusicState.allCases where state != .milestone {
            #expect(MusicDirector.duck(for: state) == 1.0)
        }
        #expect(MusicDirector.duck(for: .milestone) < 1.0)
        #expect(MusicDirector.duck(for: .milestone) > 0)
    }
}

/// Audio settings (docs/AUDIO_ARCHITECTURE.md §7).
///
/// These are the rules a settings *screen* cannot check: which switch wins,
/// whether mute survives a volume change, and whether a fresh install comes
/// up silent because a missing key read as `false`.
@Suite("Audio settings")
struct AudioSettingsTests {

    /// A store that behaves like `UserDefaults` in the way that matters:
    /// absent keys are absent, not zero.
    private final class Memory: AudioSettingsStore {
        var bools: [String: Bool] = [:]
        var doubles: [String: Double] = [:]
        func bool(forKey key: String) -> Bool? { bools[key] }
        func double(forKey key: String) -> Double? { doubles[key] }
        func set(_ value: Bool, forKey key: String) { bools[key] = value }
        func set(_ value: Double, forKey key: String) { doubles[key] = value }
    }

    // MARK: Resolution

    @Test("Mute beats every other setting")
    func muteBeatsEverything() {
        var settings = AudioSettings.standard
        settings.muteAll = true
        for layer in AudioSettings.Layer.allCases {
            #expect(settings.gain(for: layer) == 0)
        }
        #expect(settings.isSilent)
    }

    /// The reason mute is a flag rather than `masterVolume = 0`: unmuting has
    /// to give the player back the mix they built.
    @Test("Unmuting restores the mix rather than a default")
    func unmutingRestoresTheMix() {
        var settings = AudioSettings.standard
        settings.masterVolume = 0.3
        settings.soundVolume = 0.9
        let before = settings.gain(for: .effects)
        settings.muteAll = true
        #expect(settings.gain(for: .effects) == 0)
        settings.muteAll = false
        #expect(settings.gain(for: .effects) == before)
    }

    @Test("A layer turned off is exactly zero, not merely quiet")
    func disabledLayersAreZero() {
        var settings = AudioSettings.standard
        settings.music = false
        #expect(settings.gain(for: .music) == 0)
        // And it does not take the others with it.
        #expect(settings.gain(for: .effects) > 0)
    }

    @Test("Master scales every layer together")
    func masterScalesEverything() {
        var full = AudioSettings.standard
        full.ambience = true
        var half = full
        half.masterVolume = 0.5
        for layer in AudioSettings.Layer.allCases {
            #expect(abs(half.gain(for: layer) - full.gain(for: layer) * 0.5) < 1e-9)
        }
    }

    @Test("A looping cue is ambience; everything else is effects")
    func cuesResolveToTheRightLayer() {
        var settings = AudioSettings.standard
        settings.ambience = true
        settings.ambienceVolume = 0.4
        settings.soundVolume = 0.9
        #expect(settings.gain(for: .ambienceWorld) == settings.gain(for: .ambience))
        #expect(settings.gain(for: .routeOpened) == settings.gain(for: .effects))
    }

    /// Muting the game must not take away a silent-but-tactile mode.
    @Test("Haptics are independent of audio")
    func hapticsAreIndependent() {
        var settings = AudioSettings.standard
        settings.muteAll = true
        settings.sound = false
        #expect(settings.hapticsEnabled)
        settings.haptics = false
        #expect(!settings.hapticsEnabled)
    }

    /// Garbage in a preference file must fail *quiet*. A NaN or an infinity
    /// means a corrupted default or a bad migration, and full volume out of
    /// nowhere is the one outcome a player would actually mind.
    @Test("Out-of-range volumes clamp, and non-finite ones fail to silence")
    func volumesAreClamped() {
        let settings = AudioSettings(
            masterVolume: 4, soundVolume: -2, musicVolume: .nan,
            ambienceVolume: .infinity, sound: true, music: true,
            ambience: true, haptics: true, muteAll: false)
        #expect(settings.masterVolume == 1)
        #expect(settings.soundVolume == 0)
        #expect(settings.musicVolume == 0)
        #expect(settings.ambienceVolume == 0)
        for layer in AudioSettings.Layer.allCases {
            let gain = settings.gain(for: layer)
            #expect(gain >= 0 && gain <= 1)
        }
    }

    // MARK: Persistence

    /// The failure this test exists for: a fresh install where every key is
    /// missing must come up with the defaults, not silent.
    @Test("An empty store yields the defaults, not silence")
    func emptyStoreIsNotSilence() {
        let settings = AudioSettings(store: Memory())
        #expect(settings == AudioSettings.standard)
        #expect(!settings.isSilent)
        #expect(settings.gain(for: .effects) > 0)
    }

    @Test("Every setting survives a write and a reload")
    func settingsRoundTrip() {
        let store = Memory()
        var written = AudioSettings.standard
        written.masterVolume = 0.62
        written.soundVolume = 0.31
        written.musicVolume = 0.17
        written.ambienceVolume = 0.93
        written.sound = false
        written.music = false
        written.ambience = true
        written.haptics = false
        written.muteAll = true
        written.write(to: store)

        #expect(AudioSettings(store: store) == written)
    }

    /// A partially written store — the shape after an update that adds a
    /// setting — must fill the gaps with defaults rather than zeros.
    @Test("A partial store fills its gaps with defaults")
    func partialStoreFillsGaps() {
        let store = Memory()
        store.set(0.25, forKey: AudioSettings.Key.musicVolume)
        let settings = AudioSettings(store: store)
        #expect(settings.musicVolume == 0.25)
        #expect(settings.soundVolume == AudioSettings.standard.soundVolume)
        #expect(settings.sound == AudioSettings.standard.sound)
    }

    @Test("Silence is recognised only when every layer is actually zero")
    func silenceIsExact() {
        var settings = AudioSettings.standard
        settings.ambience = false
        settings.music = false
        #expect(!settings.isSilent)      // effects still on
        settings.sound = false
        #expect(settings.isSilent)
        settings.sound = true
        settings.masterVolume = 0
        #expect(settings.isSilent)       // master at zero silences by value
    }
}
