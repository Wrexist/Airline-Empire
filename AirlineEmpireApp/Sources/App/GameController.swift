import Foundation
import Observation
import AirlineEmpireCore

/// The app's single owner of the game session (composition root,
/// docs/UI_ARCHITECTURE.md §2). Holds the latest snapshot for views,
/// forwards commands, and pumps real time into the simulation while the
/// scene is active. No game rules live here.
@MainActor
@Observable
final class GameController {
    private(set) var snapshot: GameState?
    private(set) var catalog: ContentCatalog?
    private(set) var recentEvents: [SimEvent] = []
    private(set) var speed: SimSpeed = .paused
    private(set) var lastRejection: CommandRejection?
    private(set) var loadedFromBackup: Int?
    /// The result of the most recent save, so "Save now" can say what
    /// happened instead of looking identical whether it worked or not
    /// (UIUX_FORENSIC_AUDIT UI-012).
    private(set) var lastSaveOutcome: SaveOutcome?

    /// The reason the last *unannounced* save failed, if one did.
    ///
    /// A backgrounding autosave must not interrupt, but it must not lie
    /// either: this is reported quietly in Settings' Save section, where a
    /// player looks when they want to know the state of their save, rather
    /// than as a modal attached to nothing they did.
    private(set) var quietSaveFailure: String?
    /// Why the last transition into a game failed, if it did. Founding used
    /// to fail through `assertionFailure`, which is a no-op in release — the
    /// button simply did nothing, forever.
    private(set) var startupFailure: String?
    /// Set when the simulation was auto-paused for the player rather than by
    /// them, so the UI can say why time stopped.
    private(set) var autoPauseReason: AutoPauseReason?
    /// The last thing worth celebrating. Milestones, era changes, completed
    /// programs and finished missions used to arrive as one grey line in a
    /// feed; for a game whose stated payload is ownership of a growing
    /// network, nothing ever marked growth (UIUX_FORENSIC_AUDIT UI-014).
    private(set) var celebration: Celebration?

    var preferences: Preferences

    /// Sound and haptics. Owned here rather than by the scene because the
    /// three moments audio cares about — a game beginning, a game ending, and
    /// a tick publishing events — are all moments only this object sees
    /// (docs/AUDIO_ARCHITECTURE.md §3).
    let feedback: Feedback

    init() {
        let preferences = Preferences()
        self.preferences = preferences
        self.feedback = Feedback(preferences: preferences)
    }


    private var session: GameSession?
    private var saveManager: SaveManager?
    private var pumpTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var rejectionTask: Task<Void, Never>?
    /// When the current snapshot arrived in real time.
    ///
    /// The map interpolates flight positions between simulation ticks, and it
    /// measures that from here. Wall-clock rather than simulation time on
    /// purpose: it is a *presentation* clock, it never re-enters the
    /// simulation, and it resets every time Core hands over a new truth.
    private(set) var snapshotReceivedAt = Date()
    /// Solvency stage at the last pump, so entering danger fires the
    /// auto-pause exactly once rather than every quarter second.
    private var lastSolvencyStage: SolvencyModel.Stage = .healthy
    /// Monotonic id so a repeated celebration still re-triggers its animation.
    @ObservationIgnored private var celebrationCounter: Int64 = 0
    /// Events published since the last snapshot refresh, awaiting the audio
    /// director. Bounded: a very long stall must not grow this without limit,
    /// and the director would thin the batch to a handful anyway.
    @ObservationIgnored private var pendingAudioEvents: [SimEvent] = []

    var hasGame: Bool { session != nil }

    /// Derived read models, computed once per simulation tick instead of once
    /// per render (UIUX_FORENSIC_AUDIT UI-016).
    ///
    /// Screens recompute their read models inside `body`, and `body` runs on
    /// every one of the four snapshots a second the pump publishes — so the
    /// map rebuilt eighty airports, a twenty-five-point great-circle arc per
    /// route (the rivals' too) and every airborne flight, four times a second,
    /// for a picture that had barely changed. `docs/UI_ARCHITECTURE.md` §5
    /// requires snapshot→frame work to be O(visible), not O(world).
    ///
    /// The cache key is the tick count, which is exactly when the answers can
    /// change. `@ObservationIgnored` because the cache is not state a view
    /// should observe — the snapshot it derives from already is.
    @ObservationIgnored private var cachedMap: MapModel?
    @ObservationIgnored private var cachedNetwork: NetworkSummary?
    @ObservationIgnored private var cachedFleetSummary: FleetSummary?
    @ObservationIgnored private var cachedRouteCards: [RouteCardModel]?
    @ObservationIgnored private var cachedFleetCards: [FleetCardModel]?

    /// Drops every derived cache. Called on each published snapshot.
    ///
    /// This used to be `invalidateCachesIfNeeded` and skip the work when
    /// `clock.tickCount` had not moved. The tick is the wrong key. While the
    /// game is paused, `GameSession.submit` applies the command with
    /// `engine.applyNow` — which builds its context with
    /// `tick: SimDuration(minutes: 0)` and never touches the clock — and then
    /// publishes. So a paused player who opened a route, bought an aircraft or
    /// changed a fare got a genuinely new `GameState` with an unchanged tick,
    /// the guard returned early, and every screen kept showing the figures
    /// from before their own command (tasks/BUGS.md BUG-031).
    ///
    /// Clearing unconditionally costs one recomputation per published
    /// snapshot, which is what already happened on every tick while running.
    /// The cache's actual job is to stop repeated `body` evaluations between
    /// snapshots from each rebuilding the map, and it still does that.
    private func invalidateCaches() {
        cachedMap = nil
        cachedRouteCards = nil
        cachedFleetCards = nil
        cachedNetwork = nil
        cachedFleetSummary = nil
    }

    /// The network at a glance — Home's pulse, the Routes board's header.
    var networkSummary: NetworkSummary? {
        guard let snapshot, let player = snapshot.playerAirline else { return nil }
        if let cachedNetwork { return cachedNetwork }
        let summary = snapshot.networkSummary(for: player.id)
        cachedNetwork = summary
        return summary
    }

    /// The fleet at a glance — the Fleet board's header.
    var fleetSummary: FleetSummary? {
        guard let snapshot, let player = snapshot.playerAirline else { return nil }
        if let cachedFleetSummary { return cachedFleetSummary }
        let summary = snapshot.fleetSummary(for: player.id)
        cachedFleetSummary = summary
        return summary
    }

    var mapModel: MapModel? {
        guard let snapshot, let catalog else { return nil }
        if let cachedMap { return cachedMap }
        let model = snapshot.mapModel(catalog: catalog)
        cachedMap = model
        return model
    }

    var routeCards: [RouteCardModel] {
        guard let snapshot, let catalog, let player = snapshot.playerAirline
        else { return [] }
        if let cachedRouteCards { return cachedRouteCards }
        let cards = snapshot.routeCards(for: player.id, catalog: catalog)
        cachedRouteCards = cards
        return cards
    }

    var fleetCards: [FleetCardModel] {
        guard let snapshot, let catalog, let player = snapshot.playerAirline
        else { return [] }
        if let cachedFleetCards { return cachedFleetCards }
        let cards = snapshot.fleetCards(for: player.id, catalog: catalog)
        cachedFleetCards = cards
        return cards
    }

    func routeCard(_ id: RouteID) -> RouteCardModel? {
        routeCards.first { $0.id == id }
    }

    func fleetCard(_ id: AircraftID) -> FleetCardModel? {
        fleetCards.first { $0.id == id }
    }

    enum SaveOutcome: Equatable {
        case saved(slot: String)
        case failed(String)
    }

    /// Something the player earned, worth a moment on screen.
    struct Celebration: Hashable, Identifiable {
        let id: Int64
        let title: String
        let detail: String
        let icon: String
    }

    enum AutoPauseReason: Equatable {
        /// The airline dropped below the overdraft floor; the administration
        /// countdown has started (docs/CORE_LOOP.md §2 — fast-forward never
        /// skips a decision the player opted to be paused for).
        case solvencyDanger
    }

    // MARK: Lifecycle

    func startNewGame(airlineName: String, home: AirportCode, seed: UInt64,
                      scenario: ScenarioCode = "entrepreneur",
                      livery: Livery = .default) {
        startupFailure = nil
        let catalog: ContentCatalog
        do {
            catalog = try ContentCatalog.loadBundled()
        } catch {
            // Release builds do not trap on assertionFailure, so this used to
            // be a button that silently did nothing.
            startupFailure = "The game's content could not be loaded. Reinstalling the app usually fixes this."
            return
        }
        guard let spec = catalog.scenario(scenario) else {
            startupFailure = "That scenario is missing from this build."
            return
        }
        let state = ScenarioBootstrap.newGame(scenario: scenario,
                                              worldSeed: seed,
                                              startYear: spec.startYear)
        let session = GameSession(state: state, systems: GamePipeline.standard(),
                                  catalog: catalog)
        self.catalog = catalog
        self.session = session
        self.lastSolvencyStage = .healthy
        Task {
            let result = await session.beginScenario(spec, airlineName: airlineName,
                                                     home: home, livery: livery)
            if case .rejected(let rejection) = result {
                // Founding is the one command whose failure must not leave the
                // player looking at a half-built game.
                self.quitToMenu()
                self.startupFailure = rejection.message
                return
            }
            await self.attachPersistence()
            await self.subscribe()
            await self.refresh()
            // The clock's ignition, and the other half of BUG-040. The
            // scene-phase handler calls setPumping when the phase changes —
            // but at every launch the phase settles on .active while the
            // player is still on the menu, where `session` is nil and the
            // guard returns. Founding is when a session finally exists, so
            // founding must start the pump; without this line the game only
            // ever ran for a player who left the app and came back.
            self.setPumping(true)
        }
    }

    func loadGame(slot: String) {
        startupFailure = nil
        do {
            let catalog = try ContentCatalog.loadBundled()
            let manager = makeSaveManager()
            let result = try manager.load(slot: slot)
            let session = GameSession(state: result.state,
                                      systems: GamePipeline.standard(), catalog: catalog)
            self.catalog = catalog
            self.session = session
            self.saveManager = manager
            self.loadedFromBackup = result.generation > 0 ? result.generation : nil
            self.lastSolvencyStage = .healthy
            Task {
                await session.attachSaveManager(manager)
                await self.subscribe()
                await self.refresh()
                // Same as founding: a loaded game needs its clock started
                // (BUG-040).
                self.setPumping(true)
            }
        } catch {
            // Reported on the menu, which has no rejection alert of its own —
            // this used to be set and never shown to anyone (UI-004).
            self.startupFailure = "That save could not be opened. It may have been written by a newer version of the game."
        }
    }

    func clearStartupFailure() {
        startupFailure = nil
    }

    func availableSlots() -> [(slot: String, meta: SlotMeta?)] {
        let manager = saveManager ?? makeSaveManager()
        return manager.store.slots().map { ($0, manager.store.meta(slot: $0)) }
    }

    /// Removes a save. The menu listed slots with no way to manage them, and
    /// no way to tell the rolling autosave from a deliberate one
    /// (UIUX_FORENSIC_AUDIT UI-035).
    @discardableResult
    func deleteSlot(_ slot: String) -> Bool {
        let manager = saveManager ?? makeSaveManager()
        do {
            try manager.store.deleteSlot(slot)
            return true
        } catch {
            lastSaveOutcome = .failed("That save could not be deleted.")
            return false
        }
    }

    /// A player-facing name for a slot. `auto` is the rolling autosave; a
    /// named slot is something the player asked for.
    static func slotLabel(_ slot: String) -> String {
        slot == "auto" ? "Autosave" : slot.capitalized
    }

    private func makeSaveManager() -> SaveManager {
        let root = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("AirlineEmpire/saves", isDirectory: true)
        return SaveManager(store: FileSaveStore(rootDirectory: root))
    }

    private func attachPersistence() async {
        guard let session else { return }
        let manager = makeSaveManager()
        saveManager = manager
        await session.attachSaveManager(manager)
    }

    /// Backgrounding: save, quietly. A failure here is recorded but never
    /// interrupts — the player is already looking at another app.
    func saveOnBackground() {
        guard session != nil else { return }
        Task { await self.save(slot: "auto", announce: false) }
    }

    /// An explicit save, which must report what happened either way.
    func saveNow(slot: String = "auto") {
        Task { await self.save(slot: slot, announce: true) }
    }

    /// Saves, waits for it, and only then leaves.
    ///
    /// The ordering is the whole point, and it belongs here rather than in a
    /// screen. `saveNow` starts a `Task`; `quitToMenu` releases the session
    /// synchronously; and `save` opens with `guard let session`. A screen that
    /// called the two in sequence therefore queued a save, tore the session
    /// down before the task could start, and the save returned having written
    /// nothing — silently, because the code path that reports a failure was
    /// never reached (tasks/BUGS.md BUG-021).
    func saveAndQuit(slot: String = "auto") async {
        await save(slot: slot, announce: true)
        // Deliberately read before `quitToMenu` clears it: the player asked to
        // save, and if that failed they need to know on the menu rather than
        // discovering it the next time they try to load.
        let outcome = lastSaveOutcome
        quitToMenu()
        lastSaveOutcome = outcome
    }

    private func save(slot: String, announce: Bool) async {
        guard let session else { return }
        do {
            try await session.saveNow(slot: slot)
            quietSaveFailure = nil
            if announce { lastSaveOutcome = .saved(slot: slot) }
        } catch {
            // Swallowing this is how a failing save became indistinguishable
            // from a working one (UI-012). But `lastSaveOutcome` is what
            // `GameShell` raises an alert from, and `saveOnBackground` passes
            // `announce: false` precisely so it never interrupts — setting it
            // here regardless meant a failed autosave greeted the player with
            // a modal on return, attached to nothing they had done
            // (tasks/BUGS.md BUG-026).
            if announce {
                lastSaveOutcome = .failed("Saving failed: \(error.localizedDescription)")
            } else {
                quietSaveFailure = error.localizedDescription
            }
        }
    }

    func clearSaveOutcome() {
        lastSaveOutcome = nil
    }

    /// Leaves the current game and returns to the menu. Without this the
    /// game-over screen is a dead end — no new game, no other save
    /// (tasks/BUGS.md BUG-003).
    func quitToMenu() {
        pumpTask?.cancel()
        pumpTask = nil
        eventTask?.cancel()
        eventTask = nil
        rejectionTask?.cancel()
        rejectionTask = nil
        session = nil
        saveManager = nil
        snapshot = nil
        catalog = nil
        recentEvents = []
        speed = .paused
        lastRejection = nil
        loadedFromBackup = nil
        lastSaveOutcome = nil
        autoPauseReason = nil
        celebration = nil
        // Per-game, like everything else here. Without this the next airline
        // opens Settings to a warning that *this* one's autosave failed
        // (tasks/BUGS.md BUG-028) — the same leak class as BUG-013.
        quietSaveFailure = nil
        lastSolvencyStage = .healthy
        pendingAudioEvents = []
        // The director goes with the game. Without this the next airline
        // inherits the last one's history and never hears its own first route
        // (tasks/BUGS.md BUG-013).
        feedback.endSession()
        cachedMap = nil
        cachedRouteCards = nil
        cachedFleetCards = nil
        cachedNetwork = nil
        cachedFleetSummary = nil
    }

    // MARK: Time control

    func setSpeed(_ newSpeed: SimSpeed) {
        speed = newSpeed
        autoPauseReason = nil
        guard let session else { return }
        Task {
            await session.setSpeed(newSpeed)
            await self.refresh()
        }
    }

    func advanceToNextMorning() {
        guard let session else { return }
        Task {
            await session.advanceToNextMorning()
            await self.refresh()
        }
    }

    func dismissAutoPause() {
        autoPauseReason = nil
    }

    /// Runs while the scene is active: feeds elapsed real time to the
    /// session ~4×/second and refreshes the snapshot.
    func setPumping(_ active: Bool) {
        pumpTask?.cancel()
        pumpTask = nil
        guard active, session != nil else { return }
        pumpTask = Task { [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let session = self.session else { return }
                let now = ContinuousClock.now
                let elapsed = last.duration(to: now)
                last = now
                let seconds = Double(elapsed.components.seconds)
                    + Double(elapsed.components.attoseconds) / 1e18
                _ = await session.pump(elapsedSeconds: seconds)
                await self.refresh()
            }
        }
    }

    // MARK: Commands

    /// Would this command be accepted right now?
    ///
    /// Core validates every command against the state before applying it, and
    /// that validation is public — so a screen can ask the same question
    /// *before* the player commits, disable the control, and say why. This is
    /// what replaces "tap the button, watch nothing happen" (UI-004, UI-006).
    ///
    /// It is a pre-check, not a guarantee: a command queued while the
    /// simulation is running is validated again at the next tick boundary,
    /// against a world that has moved. That second refusal still arrives on
    /// the rejection stream.
    func precheck(_ command: any Command) -> CommandRejection? {
        guard let snapshot, let catalog else { return nil }
        return command.validate(state: snapshot, catalog: catalog)
    }

    /// Submits a command. Returns the rejection if the command could not even
    /// be attempted, so a sheet can stay open and explain itself rather than
    /// dismissing into an alert the player may never see.
    @discardableResult
    func submit(_ command: any Command) -> CommandRejection? {
        guard let session else { return nil }
        if let rejection = precheck(command) {
            reject(rejection)
            return rejection
        }
        Task {
            let result = await session.submit(command)
            // The game can be quit while a command is in flight. Without this
            // the refusal of a command belonging to an abandoned session
            // would still make a noise on the menu — the "sound after
            // switching saves" case in the audio bug hunt.
            guard self.session != nil else { return }
            if case .rejected(let rejection) = result {
                self.reject(rejection)
            }
            await self.refresh()
        }
        return nil
    }

    /// Every refusal, from whichever of the three paths raised it — the
    /// pre-check, the immediate result, or the queued-command stream — makes
    /// the same sound. A command that succeeds makes none here: its own
    /// domain event will voice it a moment later, and playing a confirmation
    /// as well would say the same thing twice
    /// (docs/AUDIO_ARCHITECTURE.md §4).
    private func reject(_ rejection: CommandRejection) {
        lastRejection = rejection
        feedback.play(.uiError)
    }

    func clearRejection() {
        lastRejection = nil
    }

    /// Called by the settings screen after a toggle. Turning sound off should
    /// silence the sound currently playing, not merely the next one.
    func audioSettingsChanged() {
        feedback.settingsChanged()
    }

    func dismissCelebration() {
        celebration = nil
    }

    /// The four things the simulation emits that a player worked for.
    /// Deliberately narrow: celebrating everything celebrates nothing.
    private func noteCelebration(_ event: SimEvent) {
        celebrationCounter += 1
        switch event.kind {
        case .eraAdvanced(let era):
            celebration = Celebration(
                id: celebrationCounter, title: "A new era",
                detail: "Your airline has reached \(Vocab.era(era)).", icon: "flag.fill")
        case .milestoneReached(let code):
            celebration = Celebration(
                id: celebrationCounter, title: Vocab.milestone(code),
                detail: Vocab.milestoneDetail(code), icon: "star.fill")
        case .achievementUnlocked(let code):
            celebration = Celebration(
                id: celebrationCounter, title: Vocab.achievement(code),
                detail: Vocab.achievementDetail(code), icon: "rosette")
        case .capabilityCompleted(let code):
            celebration = Celebration(
                id: celebrationCounter, title: Vocab.capability(code),
                detail: "The program is finished and in effect.",
                icon: Vocab.capabilityIcon(code))
        case .missionCompleted(_, let reward):
            celebration = Celebration(
                id: celebrationCounter, title: "Mission complete",
                detail: "\(Format.money(reward)) paid into your account.",
                icon: "target")
        default:
            celebrationCounter -= 1
        }
    }

    // MARK: Snapshot plumbing

    private func subscribe() async {
        guard let session else { return }
        // Replacing the session replaces the streams; cancelling the old
        // consumers finishes their iteration (tasks/TECH_DEBT.md TD-002).
        eventTask?.cancel()
        rejectionTask?.cancel()
        recentEvents = []
        // Anything the previous game left queued is not this game's news.
        // `loadGame` can replace a session without passing through
        // `quitToMenu`, so the reset belongs here as well as there.
        pendingAudioEvents = []
        // Seeds the audio director from the state as loaded. A save that has
        // already flown carries that fact in its route statistics, so the
        // first-time moments are established as *past* rather than replayed
        // at somebody who has been playing for a season (BUG-013).
        feedback.beginSession(state: await session.snapshot)
        // Player feed only: rivals' private books are not our news (BUG-004).
        let events = await session.events(playerFeedOnly: true)
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.recentEvents.append(event)
                if self.recentEvents.count > 200 {
                    self.recentEvents.removeFirst(self.recentEvents.count - 200)
                }
                self.noteCelebration(event)
                // Queued rather than played. Audio is decided per *batch* so
                // the director can see that eleven flights departed together
                // and say so once; playing from inside this loop would be one
                // sound per event, which is the spam the policy exists to
                // prevent (docs/AUDIO_ARCHITECTURE.md §5).
                self.pendingAudioEvents.append(event)
            }
        }
        // Commands queued while running are validated at the next tick;
        // their rejections arrive here, not from `submit` (BUG-005).
        let rejections = await session.rejections()
        rejectionTask = Task { [weak self] in
            for await rejection in rejections {
                guard let self else { return }
                self.reject(rejection)
            }
        }
    }

    private func refresh() async {
        guard let session else { return }
        let state = await session.snapshot
        if state.clock.tickCount != snapshot?.clock.tickCount {
            snapshotReceivedAt = Date()
        }
        invalidateCaches()
        snapshot = state
        speed = await session.speed
        checkSolvency(state)
        publishAudio(state)
    }

    /// Hands the batch to the director together with the state that produced
    /// it. Drained unconditionally — the director is asked on every refresh
    /// even with no events, because the once-per-campaign moments are read
    /// from the world rather than from the feed.
    private func publishAudio(_ state: GameState) {
        let batch = pendingAudioEvents
        pendingAudioEvents.removeAll(keepingCapacity: true)
        feedback.handle(events: batch, state: state, speed: speed)
        // The continuous layer is derived from the same instant as the
        // discrete one, so the bed and the cues can never describe different
        // moments (docs/AUDIO_ARCHITECTURE.md §6).
        feedback.updateSoundscape(state: state, speed: speed,
                                  stage: lastSolvencyStage)
    }

    /// Money trouble, heard and acted on.
    ///
    /// Two separate consequences of one observation, deliberately not
    /// entangled: crossing a solvency threshold always *sounds*, and it pauses
    /// only if the player asked for that. Tying the warning to the auto-pause
    /// setting would have made a preference about fast-forward silently also
    /// a preference about being told the airline is failing.
    ///
    /// Fast-forward must never skip the one decision that ends the game
    /// (docs/CORE_LOOP.md §2), so crossing into the administration countdown
    /// pauses once, and says so.
    private func checkSolvency(_ state: GameState) {
        guard let catalog,
              let player = state.playerAirline?.id,
              let solvency = state.solvencyModel(for: player, catalog: catalog)
        else { return }
        let previous = lastSolvencyStage
        lastSolvencyStage = solvency.stage

        // Only a transition sounds. The stage is recomputed four times a
        // second and holding at `.danger` for a week must not be a week of
        // warnings (docs/AUDIO_ARCHITECTURE.md §4).
        if solvency.stage > previous {
            switch solvency.stage {
            case .watch: feedback.play(.solvencyWarning)
            case .danger: feedback.play(.solvencyDanger)
            case .healthy: break
            }
        }

        guard preferences.autoPauseOnDanger else { return }
        guard solvency.stage == .danger, previous != .danger else { return }
        guard speed != .paused else { return }
        setSpeed(.paused)
        autoPauseReason = .solvencyDanger
    }
}

/// Player settings, persisted in `UserDefaults`.
///
/// The app previously had none at all — not sound, not haptics, not
/// auto-pause, which `docs/CORE_LOOP.md` §2 specifies as settable. These are
/// deliberately few: each one is a real choice, and defaults are what a first
/// session should want.
@Observable
final class Preferences {
    private enum Key {
        static let autoPause = "ae.autoPauseOnDanger"
        static let confirmDestructive = "ae.confirmDestructive"
    }

    private let defaults: UserDefaults

    /// Audio settings, whose *rules* live in Core (`AudioSettings`) so that
    /// "which switch wins" and "does this survive a relaunch" are questions a
    /// Linux test can answer. This object only stores and forwards.
    private var audioSettings: AudioSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.autoPause: true,
            Key.confirmDestructive: true,
        ])
        storedAutoPause = defaults.bool(forKey: Key.autoPause)
        storedConfirmDestructive = defaults.bool(forKey: Key.confirmDestructive)
        // No `register(defaults:)` for audio: `AudioSettings(store:)` already
        // treats a missing key as its own default, which is that rule said
        // once rather than in two places that can disagree.
        audioSettings = AudioSettings(store: DefaultsStore(defaults: defaults))
    }

    private var storedAutoPause: Bool
    private var storedConfirmDestructive: Bool

    var autoPauseOnDanger: Bool {
        get { storedAutoPause }
        set { storedAutoPause = newValue; defaults.set(newValue, forKey: Key.autoPause) }
    }

    /// Whether selling, returning and closing ask first. On by default:
    /// these are unrecoverable and expensive.
    var confirmDestructive: Bool {
        get { storedConfirmDestructive }
        set { storedConfirmDestructive = newValue; defaults.set(newValue, forKey: Key.confirmDestructive) }
    }

    // MARK: Audio

    /// The resolved settings, for anything that needs to ask about gain.
    var audio: AudioSettings { audioSettings }

    private func mutateAudio(_ change: (inout AudioSettings) -> Void) {
        var next = audioSettings
        change(&next)
        audioSettings = next
        next.write(to: DefaultsStore(defaults: defaults))
    }

    var masterVolume: Double {
        get { audioSettings.masterVolume }
        set { mutateAudio { $0.masterVolume = newValue } }
    }

    var sound: Bool {
        get { audioSettings.sound }
        set { mutateAudio { $0.sound = newValue } }
    }

    var soundVolume: Double {
        get { audioSettings.soundVolume }
        set { mutateAudio { $0.soundVolume = newValue } }
    }

    var music: Bool {
        get { audioSettings.music }
        set { mutateAudio { $0.music = newValue } }
    }

    var musicVolume: Double {
        get { audioSettings.musicVolume }
        set { mutateAudio { $0.musicVolume = newValue } }
    }

    var ambience: Bool {
        get { audioSettings.ambience }
        set { mutateAudio { $0.ambience = newValue } }
    }

    var ambienceVolume: Double {
        get { audioSettings.ambienceVolume }
        set { mutateAudio { $0.ambienceVolume = newValue } }
    }

    var haptics: Bool {
        get { audioSettings.haptics }
        set { mutateAudio { $0.haptics = newValue } }
    }

    var muteAll: Bool {
        get { audioSettings.muteAll }
        set { mutateAudio { $0.muteAll = newValue } }
    }
}

/// `UserDefaults` as Core's storage protocol.
///
/// `object(forKey:)` rather than `bool(forKey:)` on purpose: the typed
/// accessors return `false` and `0` for a missing key, which is exactly how a
/// fresh install ends up silent. Core distinguishes absent from off, and this
/// is what lets it.
private final class DefaultsStore: AudioSettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    func bool(forKey key: String) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }

    func double(forKey key: String) -> Double? {
        defaults.object(forKey: key) as? Double
    }

    func set(_ value: Bool, forKey key: String) { defaults.set(value, forKey: key) }
    func set(_ value: Double, forKey key: String) { defaults.set(value, forKey: key) }
}
