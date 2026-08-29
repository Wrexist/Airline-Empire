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

        engine.attach(effectsMixer)
        engine.attach(ambienceMixer)
        engine.connect(effectsMixer, to: engine.mainMixerNode, format: nil)
        engine.connect(ambienceMixer, to: engine.mainMixerNode, format: nil)

        for _ in 0..<Self.voiceCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: effectsMixer, format: nil)
            voices.append(node)
        }

        for cue in AudioCue.allCases {
            if let buffer = loadBuffer(cue) {
                buffers[cue] = buffer
            } else {
                unavailable.insert(cue)
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
        // `.ambient` + `.mixWithOthers`: never interrupt the player's music,
        // always obey the silent switch.
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func loadBuffer(_ cue: AudioCue) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: cue.assetName,
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
        applyCategoryTrim(to: buffer, cue: cue)
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
        guard isRunning, !cue.isLoop, let buffer = buffers[cue] else { return }
        effectsMixer.outputVolume = min(1, max(0, gain))
        let node = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
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
            engine.pause()
        }
    }

    func stopAll() {
        stopAmbience()
        guard isRunning else { return }
        for voice in voices {
            voice.stop()
            voice.play()
        }
    }
}
