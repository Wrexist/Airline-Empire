/// The *continuous* half of the audio policy (docs/AUDIO_ARCHITECTURE.md §6).
///
/// `AudioDirection.swift` decides which discrete sounds a moment deserves.
/// This file decides what the game should sound like when nothing in
/// particular is happening: how present the world bed is, how much movement is
/// in it, and which music state the airline is living in.
///
/// Both are pure functions of things the simulation already publishes, for the
/// same reason the cue policy is: a soundscape that responds to zoom, speed
/// and scale is a set of rules, and rules that live in a view cannot be
/// checked. Nothing here reads a clock, allocates, or touches AVFoundation.
///
/// The product rule these encode, from the phase brief: **the game must not
/// get louder as the airline grows — it must get richer.** So scale moves
/// *movement* and *density*, and never the master level.

// MARK: - Where the player is looking

/// How close the map is. The app's own zoom ladder maps onto this; Core keeps
/// its own three-value version so the policy is expressible without the
/// renderer's `CGFloat`.
public enum SoundscapeFocus: Int, Equatable, Sendable, Comparable, CaseIterable {
    /// Not on the map at all — a list, a sheet, the finance screen.
    case away = 0
    /// The whole world. Almost silent: there is nothing here to be close to.
    case world
    /// A continent. The bed opens up.
    case regional
    /// A market. The most present the world is allowed to be.
    case local

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - The bed

/// What the continuous layer should be doing right now.
///
/// Levels are 0...1 multipliers on the player's own ambience setting; they
/// are never absolute volume, so a player who wants the bed quiet keeps it
/// quiet at every zoom and every scale.
public struct AmbienceMix: Equatable, Sendable {
    /// Which loop, or nil for silence.
    public let bed: AudioCue?
    /// How present the bed is, 0...1.
    public let level: Double
    /// How much *activity* is in it, 0...1 — the density of movement texture
    /// rather than its loudness. This is the dial that makes a hundred-route
    /// airline feel different from a two-route one.
    public let movement: Double

    public static let silent = AmbienceMix(bed: nil, level: 0, movement: 0)

    public init(bed: AudioCue?, level: Double, movement: Double) {
        self.bed = bed
        self.level = min(1, max(0, level))
        self.movement = min(1, max(0, movement))
    }
}

public enum AmbienceDirector {

    /// The bed for the current moment.
    ///
    /// - Parameters:
    ///   - focus: where the player is looking.
    ///   - airborne: how many of the player's aircraft are in the air. Scale,
    ///     expressed as the one number that actually tracks it.
    ///   - speed: the clock. Paused thins the bed rather than muting it —
    ///     a paused world is still a world.
    ///   - hasSelection: whether the player has singled something out, which
    ///     is the one case where the map is allowed to be more detailed.
    ///   - stage: solvency, because a failing airline should not sound
    ///     comfortable.
    public static func mix(focus: SoundscapeFocus,
                           airborne: Int,
                           speed: SimSpeed,
                           hasSelection: Bool = false,
                           stage: SolvencyModel.Stage = .healthy) -> AmbienceMix {
        guard focus != .away else { return .silent }

        // Presence by distance. At world zoom the map is a diagram and should
        // be nearly silent; the closer the player gets, the more the world is
        // a place. These are the whole "map is not a radar simulator" rule:
        // no layer is ever loud, and the range top-to-bottom is under 3x.
        let base: Double
        switch focus {
        case .away: base = 0
        case .world: base = 0.22
        case .regional: base = 0.45
        case .local: base = 0.62
        }

        // Scale moves *movement*, not level. A big network is busier, not
        // louder. Saturating on purpose: the difference between two flights
        // and twenty must be obvious, and between two hundred and four
        // hundred must not be.
        let density = min(1.0, Double(airborne) / 24.0)
        var movement = density * 0.85

        // Speed changes density, never pitch. Pitching a loop up with the
        // clock is the single most arcade thing an audio system can do.
        switch speed {
        case .paused:
            // A paused world keeps its bed and loses its activity. This is
            // what makes unpausing feel like starting something.
            movement *= 0.15
        case .x1:
            break
        case .x4:
            movement = min(1, movement * 1.15)
        case .x16:
            // Deliberately *below* 4x. At sixteen times, discrete cues are
            // already aggregating; adding a busier bed on top is how a
            // fast-forward becomes exhausting.
            movement = min(1, movement * 1.05)
        }

        // Looking closely at one thing earns a little more detail — the only
        // place the map is permitted to be more present.
        let selectionGain = hasSelection && focus >= .regional ? 1.12 : 1.0

        // A failing airline sounds thinner. Not louder, not alarming: the
        // world recedes, which is a more useful feeling than a siren.
        let strain: Double
        switch stage {
        case .healthy: strain = 1.0
        case .watch: strain = 0.9
        case .danger: strain = 0.75
        }

        return AmbienceMix(bed: focus >= .regional ? .ambienceOperations : .ambienceWorld,
                           level: base * strain * selectionGain,
                           movement: movement)
    }
}

// MARK: - Music

/// What the score should be doing. Deliberately few: a state machine with
/// nine states is one nobody can predict the behaviour of.
public enum MusicState: String, Equatable, Sendable, CaseIterable {
    /// No game in progress.
    case menu
    /// A game, paused. The player is reading, comparing, deciding.
    case planning
    /// A game, running.
    case operating
    /// The airline is in trouble.
    case crisis
    /// Something worth marking just happened. Brief, then back.
    case milestone

    /// Whether moving to `other` should crossfade or cut. Everything
    /// crossfades except the arrival of a milestone, which is the one moment
    /// allowed to assert itself.
    public func crossfadeSeconds(to other: MusicState) -> Double {
        if other == .milestone { return 0.6 }
        if self == .milestone { return 2.5 }
        return other == .crisis || self == .crisis ? 3.0 : 4.0
    }
}

public enum MusicDirector {

    /// How long a milestone state holds before falling back, in seconds.
    public static let milestoneHold: Double = 12

    /// The state the game is in.
    ///
    /// Ordered by precedence rather than by narrative: a milestone during a
    /// crisis is still a milestone (the player just did something), and a
    /// crisis outranks whether the clock is running.
    public static func state(hasGame: Bool,
                             speed: SimSpeed,
                             stage: SolvencyModel.Stage = .healthy,
                             celebrating: Bool = false) -> MusicState {
        guard hasGame else { return .menu }
        if celebrating { return .milestone }
        if stage == .danger { return .crisis }
        return speed == .paused ? .planning : .operating
    }

    /// The asset that voices a state, or nil when the library does not carry
    /// one. Nil is a supported answer, not a failure: the architecture is
    /// designed to be correct with an empty music library
    /// (docs/AUDIO_ASSET_MANIFEST.md §4).
    public static func asset(for state: MusicState) -> String? {
        switch state {
        case .menu: return "music_menu"
        case .planning: return "music_planning"
        case .operating: return "music_operating"
        case .crisis: return "music_crisis"
        // A milestone is marked by its own one-shot cue, not by a track:
        // twelve seconds of different music for a mission completion would be
        // a bigger interruption than the moment deserves. The state exists so
        // the *bed* can duck under the cue and return.
        case .milestone: return nil
        }
    }

    /// How much the bed and the effects should duck while this state holds.
    /// Only the milestone ducks, and only a little.
    public static func duck(for state: MusicState) -> Double {
        state == .milestone ? 0.55 : 1.0
    }
}
