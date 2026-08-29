import AVFoundation
import AirlineEmpireCore

/// The thing that actually makes noise (docs/AUDIO_ARCHITECTURE.md §4).
///
/// One `AVAudioEngine`, three mixers, a fixed pool of player nodes, and every
/// buffer decoded once at launch. Nothing here decides *whether* to play —
/// that is `AudioDirector`'s job in Core, and this class is deliberately dumb
/// so the interesting decisions stay testable.
///
/// ## Why a node pool rather than `AVAudioPlayer`
///
/// `AVAudioPlayer` allocates a decoder per instance, cannot overlap itself,
/// and adds latency that is audible on a tap. A route opening while two
/// flights land is three overlapping sounds, so the engine keeps a small
/// round-robin of `AVAudioPlayerNode`s fed from preloaded PCM. Playing a cue
/// after launch allocates nothing (§28).
///
/// ## Why the session category is `.ambient`
///
/// A strategy game is played next to a podcast. `.ambient` means the game
/// never interrupts what the player is already listening to, and it obeys the
/// ring/silent switch — which is the behaviour anyone would expect from a
/// game and the opposite of what `.playback` would do.
@MainActor
final class AudioEngine {

    /// Volume trims per category, applied on top of the player's settings.
    /// This is where the mix is balanced: assets are mastered to their own
    /// peaks, and these keep a family from crowding the others.
    private static let categoryTrim: [AudioCategory: Float] = [
        .ui: 0.55,
        .operations: 0.7,
        .routes: 0.9,
        .finance: 0.85,
        .world: 0.9,
        .progression: 1.0,
        .critical: 1.0,
    ]

    private let engine = AVAudioEngine()
    /// One-shots. Separate from ambience so effects volume and ambience
    /// volume are genuinely independent faders rather than one shared number.
    private let effectsMixer = AVAudioMixerNode()
    private let ambienceMixer = AVAudioMixerNode()

    /// Round-robin pool. Eight is comfortably more than the director will ever
    /// hand over at once (the largest batch budget is four) while leaving room
    /// for tails still ringing from the previous batch.
    private static let voiceCount = 8
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0

    private var ambienceNode: AVAudioPlayerNode?
    private var ambienceCue: AudioCue?

    /// Music, on its own mixer so its volume is a third independent fader.
    private let musicMixer = AVAudioMixerNode()
    /// Two decks. A crossfade needs the outgoing track to keep sounding while
    /// the incoming one comes up, which one node cannot do — and cutting
    /// between music states is the thing that would make a strategy game feel
    /// like a menu system.
    private var musicDecks: [AVAudioPlayerNode] = []
    private var activeDeck = 0
    private var musicTrack: String?
    private var musicBuffers: [String: AVAudioPCMBuffer] = [:]
    private var musicFade: Task<Void, Never>?
    /// The player's music setting, held so a crossfade knows what "full"
    /// means without asking back through the facade every step.
    private var musicTarget: Float = 0
    private(set) var missingMusic: Set<String> = []

    private var buffers: [AudioCue: AVAudioPCMBuffer] = [:]
    private(set) var isRunning = false
    /// Cues whose file was missing or unreadable. Surfaced rather than
    /// swallowed: silence is indistinguishable from working, so the one place
    /// this can be noticed is a list somebody can look at.
    private(set) var unavailable: Set<AudioCue> = []

    // MARK: - Lifecycle

    /// Builds the graph and decodes every one-shot. Called once, off the
    /// first frame — decoding fifty short files is milliseconds, but it is
    /// still not work to do while the player is waiting for a screen.
    func prepare() {
        guard !isRunning else { return }
        configureSession()

        // Buffers first, deliberately. A player node's output connection has
        // a format, and `scheduleBuffer` with a buffer that does not match it
        // raises an Objective-C exception — which Swift cannot catch, so it is
        // a crash rather than a failure. Connecting with `format: nil` lets
        // the engine guess, and it guesses the hardware's format, which is
        // stereo. Every asset here is mono. So the voices are wired with the
        // real format of a real decoded buffer, and there is no guessing.
        //
        // `scripts/audio/check-assets.py` enforces that all 52 share one
        // format, which is what makes "any buffer's format" a safe choice.
        for cue in AudioCue.allCases {
            if let buffer = loadBuffer(cue) {
                buffers[cue] = buffer
            } else {
                unavailable.insert(cue)
            }
        }
        guard let voiceFormat = buffers.first(where: { !$0.key.isLoop })?
            .value.format else {
            // No effect assets loaded at all. The graph would have nothing to
            // carry, and building it would only invite the format mismatch
            // above.
            isRunning = false
            return
        }

        engine.attach(effectsMixer)
        engine.attach(ambienceMixer)
        engine.attach(musicMixer)
        engine.connect(effectsMixer, to: engine.mainMixerNode, format: nil)
        engine.connect(ambienceMixer, to: engine.mainMixerNode, format: nil)
        engine.connect(musicMixer, to: engine.mainMixerNode, format: nil)
        musicMixer.outputVolume = 0

        for _ in 0..<Self.voiceCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: effectsMixer, format: voiceFormat)
            voices.append(node)
        }

        // Music beds are addressed by name rather than by cue, and they run
        // at half the rate (see docs/AUDIO_ASSET_MANIFEST.md §3), so each deck
        // is wired to the format of the bed it will actually carry.
        for state in MusicState.allCases {
            guard let name = MusicDirector.asset(for: state),
                  musicBuffers[name] == nil else { continue }
            if let buffer = loadBuffer(named: name) {
                musicBuffers[name] = buffer
            } else {
                missingMusic.insert(name)
            }
        }
        if let musicFormat = musicBuffers.values.first?.format {
            for _ in 0..<2 {
                let deck = AVAudioPlayerNode()
                engine.attach(deck)
                engine.connect(deck, to: musicMixer, format: musicFormat)
                musicDecks.append(deck)
            }
        }

        do {
            try engine.start()
            for voice in voices { voice.play() }
            isRunning = true
        } catch {
            // A game that cannot start its audio engine is still a game. The
            // failure is recorded and every later call becomes a no-op.
            isRunning = false
        }
    }

    /// Releases the hardware. Called when the app leaves the foreground so a
    /// backgrounded game is not holding an audio route open (§28).
    func suspend() {
        guard isRunning else { return }
        stopAmbience()
        stopMusic()
        engine.pause()
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
    }

    func resume() {
        guard isRunning else { return }
        configureSession()
        try? engine.start()
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        // `.ambient`: never interrupt the player's music, always obey the
        // silent switch. It mixes by default — that is what the category
        // *means* — so the option is not needed.
        //
        // It was `[.mixWithOthers]` here, which is worse than redundant.
        // That option is only valid with `.playback`, `.playAndRecord` and
        // `.multiRoute`; passing it with `.ambient` makes `setCategory` throw,
        // the `try?` swallowed the throw, and the session was left on its
        // default `.soloAmbient` — which does **not** mix. The one behaviour
        // this line exists to guarantee was the behaviour it prevented
        // (tasks/BUGS.md BUG-019).
        try? session.setCategory(.ambient, mode: .default)
        try? session.setActive(true)
    }

    private func loadBuffer(_ cue: AudioCue) -> AVAudioPCMBuffer? {
        guard let buffer = loadBuffer(named: cue.assetName) else { return nil }
        applyCategoryTrim(to: buffer, cue: cue)
        return buffer
    }

    private func loadBuffer(named name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name,
                                        withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length))
        else { return nil }
        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }
        return buffer
    }

    /// Scales the category trim into the samples, once, at load.
    ///
    /// The obvious alternative — setting `node.volume` per play — is wrong,
    /// and subtly so. A player node's volume applies to whatever it is
    /// *currently sounding*, not to the buffer being scheduled: a UI tap
    /// landing on the node that is still two seconds into an era swell would
    /// duck the swell to the tap's level. With eight voices that needs only
    /// eight sounds inside one tail, which a 16x flurry reaches easily.
    ///
    /// Baking it here means node volume is a constant 1, the mixer carries
    /// the player's master setting (uniform across every sound at any
    /// instant, so re-levelling a sounding node is harmless), and a play
    /// costs one `scheduleBuffer` and nothing else.
    private func applyCategoryTrim(to buffer: AVAudioPCMBuffer, cue: AudioCue) {
        let trim = Self.categoryTrim[cue.category] ?? 1
        guard trim != 1, let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            for frame in 0..<frames {
                samples[frame] *= trim
            }
        }
    }

    // MARK: - One-shots

    /// Plays a cue immediately. `gain` is the player's master effects volume;
    /// the per-category balance is already in the buffer (see
    /// `applyCategoryTrim`).
    ///
    /// Scheduling on a node that is already sounding simply layers the new
    /// buffer — `AVAudioPlayerNode` mixes its own scheduled buffers — so a
    /// busy moment overlaps rather than cutting itself off. The round robin
    /// spreads the load so no single node accumulates a long queue.
    func play(_ cue: AudioCue, gain: Float) {
        guard isRunning, !cue.isLoop, let buffer = buffers[cue],
              let node = voices.first,
              buffer.format == node.outputFormat(forBus: 0) else { return }
        effectsMixer.outputVolume = min(1, max(0, gain))
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    // MARK: - Ambience

    /// Starts (or swaps to) a looping bed. Asking for the bed that is already
    /// playing is a no-op, which is what stops two copies stacking every time
    /// a view reappears (tasks/BUGS.md BUG-014).
    func startAmbience(_ cue: AudioCue, gain: Float) {
        guard isRunning, cue.isLoop, let buffer = buffers[cue] else { return }
        guard ambienceCue != cue else {
            ambienceMixer.outputVolume = min(1, max(0, gain))
            return
        }
        stopAmbience()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: ambienceMixer, format: buffer.format)
        node.scheduleBuffer(buffer, at: nil, options: [.loops],
                            completionHandler: nil)
        ambienceMixer.outputVolume = min(1, max(0, gain))
        node.play()
        ambienceNode = node
        ambienceCue = cue
    }

    func setAmbienceGain(_ gain: Float) {
        ambienceMixer.outputVolume = min(1, max(0, gain))
    }

    func stopAmbience() {
        guard let node = ambienceNode else { return }
        node.stop()
        engine.detach(node)
        ambienceNode = nil
        ambienceCue = nil
    }

    /// Silences everything currently sounding without tearing the graph down
    /// — used when a game ends or the player mutes mid-sound, so a two-second
    /// era swell does not outlive the screen that earned it.
    // MARK: - Music

    /// Crossfades to `track`, or fades out entirely when it is nil.
    ///
    /// Idempotent: asking for the track already playing only re-levels. That
    /// is what makes it safe to call from an observation that fires on every
    /// snapshot, which is exactly how a music system ends up with four copies
    /// of the same bed running at once.
    func setMusic(_ track: String?, gain: Float, fade: Double) {
        guard isRunning, !musicDecks.isEmpty else { return }
        musicTarget = min(1, max(0, gain))

        guard track != musicTrack else {
            // Same bed: re-level, and **do not touch a fade in flight**.
            //
            // This branch is reached four times a second, because the caller
            // re-derives the music state on every snapshot. Cancelling here —
            // which the first version did — killed every crossfade about
            // 250 ms in and left the two decks stranded mid-ramp, so the game
            // was permanently stuck on the previous track at almost full
            // volume (tasks/BUGS.md BUG-018). A running fade already reads
            // `musicTarget` for itself.
            if musicFade == nil { musicMixer.outputVolume = musicTarget }
            return
        }
        musicTrack = track

        musicFade?.cancel()
        let outgoing = musicDecks[activeDeck]
        guard let track, let buffer = musicBuffers[track] else {
            // Fading to silence.
            musicFade = Task { [weak self] in
                await self?.ramp(to: 0, over: fade)
                guard !Task.isCancelled else { return }
                outgoing.stop()
                self?.musicFade = nil
            }
            return
        }

        activeDeck = (activeDeck + 1) % musicDecks.count
        let incoming = musicDecks[activeDeck]
        incoming.stop()
        incoming.scheduleBuffer(buffer, at: nil, options: [.loops],
                                completionHandler: nil)
        incoming.volume = 0
        incoming.play()

        musicFade = Task { [weak self] in
            await self?.crossfade(from: outgoing, to: incoming, over: fade)
            self?.musicFade = nil
        }
    }

    /// Equal-power crossfade over `seconds`, stepped at 20 Hz.
    ///
    /// Equal-power rather than linear because two linear ramps sum to a dip in
    /// the middle, and a dip in the middle of every music transition is
    /// audible as a stumble.
    private func crossfade(from outgoing: AVAudioPlayerNode,
                           to incoming: AVAudioPlayerNode,
                           over seconds: Double) async {
        let steps = max(1, Int(seconds * 20))
        for step in 0...steps {
            if Task.isCancelled { return }
            // Read the target every step rather than once: the player can
            // move a slider mid-transition, and a fade that captured the old
            // value would spend four seconds ignoring them.
            musicMixer.outputVolume = musicTarget
            let t = Double(step) / Double(steps)
            incoming.volume = Float(sin(t * .pi / 2))
            outgoing.volume = Float(cos(t * .pi / 2))
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard !Task.isCancelled else { return }
        outgoing.stop()
        outgoing.volume = 0
        incoming.volume = 1
    }

    private func ramp(to level: Float, over seconds: Double) async {
        let steps = max(1, Int(seconds * 20))
        let from = musicMixer.outputVolume
        for step in 0...steps {
            if Task.isCancelled { return }
            let t = Float(step) / Float(steps)
            musicMixer.outputVolume = from + (level - from) * t
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    func stopMusic() {
        musicFade?.cancel()
        musicFade = nil
        for deck in musicDecks {
            deck.stop()
            deck.volume = 0
        }
        musicMixer.outputVolume = 0
        musicTrack = nil
    }

    /// Idles the graph when the player has turned everything off.
    ///
    /// A running `AVAudioEngine` with nothing to play still holds a render
    /// thread and an audio route. Muting the game should cost nothing, not
    /// merely produce nothing (MASTER PROMPT 3 §29).
    func setActive(_ active: Bool) {
        guard isRunning else { return }
        if active {
            if !engine.isRunning {
                configureSession()
                try? engine.start()
                for voice in voices { voice.play() }
            }
        } else if engine.isRunning {
            stopAmbience()
            stopMusic()
            engine.pause()
        }
    }

    func stopAll() {
        stopAmbience()
        stopMusic()
        guard isRunning else { return }
        for voice in voices {
            voice.stop()
            voice.play()
        }
    }
}
