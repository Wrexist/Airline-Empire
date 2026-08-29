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

    var preferences = Preferences()

    private var session: GameSession?
    private var saveManager: SaveManager?
    private var pumpTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var rejectionTask: Task<Void, Never>?
    /// Solvency stage at the last pump, so entering danger fires the
    /// auto-pause exactly once rather than every quarter second.
    private var lastSolvencyStage: SolvencyModel.Stage = .healthy
    /// Monotonic id so a repeated celebration still re-triggers its animation.
    @ObservationIgnored private var celebrationCounter: Int64 = 0

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
    @ObservationIgnored private var cachedTick: Int64 = -1
    @ObservationIgnored private var cachedMap: MapModel?
    @ObservationIgnored private var cachedRouteCards: [RouteCardModel]?
    @ObservationIgnored private var cachedFleetCards: [FleetCardModel]?

    private func invalidateCachesIfNeeded(_ state: GameState) {
        guard state.clock.tickCount != cachedTick else { return }
        cachedTick = state.clock.tickCount
        cachedMap = nil
        cachedRouteCards = nil
        cachedFleetCards = nil
    }

    var mapModel: MapModel? {
        guard let snapshot, let catalog else { return nil }
        if let cachedMap, snapshot.clock.tickCount == cachedTick { return cachedMap }
        let model = snapshot.mapModel(catalog: catalog)
        cachedTick = snapshot.clock.tickCount
        cachedMap = model
        return model
    }

    var routeCards: [RouteCardModel] {
        guard let snapshot, let catalog, let player = snapshot.playerAirline
        else { return [] }
        if let cachedRouteCards, snapshot.clock.tickCount == cachedTick {
            return cachedRouteCards
        }
        let cards = snapshot.routeCards(for: player.id, catalog: catalog)
        cachedTick = snapshot.clock.tickCount
        cachedRouteCards = cards
        return cards
    }

    var fleetCards: [FleetCardModel] {
        guard let snapshot, let catalog, let player = snapshot.playerAirline
        else { return [] }
        if let cachedFleetCards, snapshot.clock.tickCount == cachedTick {
            return cachedFleetCards
        }
        let cards = snapshot.fleetCards(for: player.id, catalog: catalog)
        cachedTick = snapshot.clock.tickCount
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
    struct Celebration: Equatable, Identifiable {
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
                      scenario: ScenarioCode = "entrepreneur") {
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
                                                     home: home)
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
        guard let session else { return }
        Task { await self.save(slot: "auto", announce: false) }
    }

    /// An explicit save, which must report what happened either way.
    func saveNow(slot: String = "auto") {
        Task { await self.save(slot: slot, announce: true) }
    }

    private func save(slot: String, announce: Bool) async {
        guard let session else { return }
        do {
            try await session.saveNow(slot: slot)
            if announce { lastSaveOutcome = .saved(slot: slot) }
        } catch {
            // Swallowing this is how a failing save became indistinguishable
            // from a working one (UI-012).
            lastSaveOutcome = .failed("Saving failed: \(error.localizedDescription)")
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
        lastSolvencyStage = .healthy
        cachedTick = -1
        cachedMap = nil
        cachedRouteCards = nil
        cachedFleetCards = nil
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
            lastRejection = rejection
            return rejection
        }
        Task {
            let result = await session.submit(command)
            if case .rejected(let rejection) = result {
                self.lastRejection = rejection
            }
            await self.refresh()
        }
        return nil
    }

    func clearRejection() {
        lastRejection = nil
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
                detail: "Milestone reached.", icon: "star.fill")
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
            }
        }
        // Commands queued while running are validated at the next tick;
        // their rejections arrive here, not from `submit` (BUG-005).
        let rejections = await session.rejections()
        rejectionTask = Task { [weak self] in
            for await rejection in rejections {
                guard let self else { return }
                self.lastRejection = rejection
            }
        }
    }

    private func refresh() async {
        guard let session else { return }
        let state = await session.snapshot
        invalidateCachesIfNeeded(state)
        snapshot = state
        speed = await session.speed
        checkAutoPause(state)
    }

    /// Fast-forward must never skip the one decision that ends the game
    /// (docs/CORE_LOOP.md §2). Crossing into the administration countdown
    /// pauses once, and says so.
    private func checkAutoPause(_ state: GameState) {
        guard preferences.autoPauseOnDanger,
              let catalog,
              let player = state.playerAirline?.id,
              let solvency = state.solvencyModel(for: player, catalog: catalog)
        else { return }
        defer { lastSolvencyStage = solvency.stage }
        guard solvency.stage == .danger, lastSolvencyStage != .danger else { return }
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
        static let haptics = "ae.haptics"
        static let confirmDestructive = "ae.confirmDestructive"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `bool(forKey:)` is false for a missing key, and every setting here
        // defaults to on — so absence is registered as the default rather
        // than read as "off".
        defaults.register(defaults: [
            Key.autoPause: true,
            Key.haptics: true,
            Key.confirmDestructive: true,
        ])
        storedAutoPause = defaults.bool(forKey: Key.autoPause)
        storedHaptics = defaults.bool(forKey: Key.haptics)
        storedConfirmDestructive = defaults.bool(forKey: Key.confirmDestructive)
    }

    private var storedAutoPause: Bool
    private var storedHaptics: Bool
    private var storedConfirmDestructive: Bool

    var autoPauseOnDanger: Bool {
        get { storedAutoPause }
        set { storedAutoPause = newValue; defaults.set(newValue, forKey: Key.autoPause) }
    }

    var haptics: Bool {
        get { storedHaptics }
        set { storedHaptics = newValue; defaults.set(newValue, forKey: Key.haptics) }
    }

    /// Whether selling, returning and closing ask first. On by default:
    /// these are unrecoverable and expensive.
    var confirmDestructive: Bool {
        get { storedConfirmDestructive }
        set { storedConfirmDestructive = newValue; defaults.set(newValue, forKey: Key.confirmDestructive) }
    }
}
