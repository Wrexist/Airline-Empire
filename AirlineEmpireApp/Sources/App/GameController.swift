import Foundation
import Observation
import UIKit
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
    #if DEBUG
    /// Test acknowledgement: distinguishes an OS-intercepted tap from a
    /// request already delivered to the asynchronous simulation.
    private(set) var manualAdvanceRequests = 0
    #endif
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

    init(savesDirectory: URL? = nil) {
        #if DEBUG
        // Isolate UI journeys without deleting saves or granting paid access.
        // Keep the same directory when a journey deliberately relaunches.
        if savesDirectory == nil,
           let value = ProcessInfo.processInfo.environment["AE_UI_TEST_SAVE_ID"],
           let id = UUID(uuidString: value) {
            self.savesDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("AE-UI-\(id.uuidString)", isDirectory: true)
        } else {
            self.savesDirectory = savesDirectory
        }
        #else
        self.savesDirectory = savesDirectory
        #endif
        let preferences = Preferences()
        self.preferences = preferences
        self.feedback = Feedback(preferences: preferences)
    }


    private var session: GameSession?
    private(set) var activeSaveSlot: String?
    private let savesDirectory: URL?
    private var backgroundSaveTask: UIBackgroundTaskIdentifier = .invalid
    private(set) var isSavingAndQuitting = false
    private var sessionCheckpoint: SessionCheckpoint?
    private(set) var lastSessionReport: SessionReport?
    private(set) var lastSessionNextMove: String?
    private var saveManager: SaveManager?
    private var pumpTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var rejectionTask: Task<Void, Never>?
    /// When the current *tick* arrived in real time.
    ///
    /// Wall-clock rather than simulation time on purpose: it is a
    /// *presentation* clock, it never re-enters the simulation, and it resets
    /// every time Core hands over a new tick. The map's caches key on it —
    /// route styling and label placement re-decide per tick, not per publish
    /// (docs/MAP_INTERACTION_ARCHITECTURE.md §3), so it deliberately does
    /// *not* move on a publish that carried no new tick.
    private(set) var snapshotReceivedAt = Date()
    /// The continuous presentation clock, in two halves: when the last
    /// snapshot was published, and how far past its tick the simulation had
    /// already been handed at that moment.
    ///
    /// Separate from `snapshotReceivedAt` because they answer different
    /// questions and moved at different rates the moment anything depended on
    /// both: the caches want "which tick is this" (3.75 s apart at 1×), and
    /// flight prediction wants "what time is it now" (every publish, 4 Hz).
    /// Predicting from the tick alone is what made aircraft jump backwards —
    /// the prediction ran on real time while its base stepped in whole ticks,
    /// so every tick landed a correction (tasks/BUGS.md BUG-058).
    private(set) var publishedAt = Date()
    /// Game minutes the pump has consumed past `snapshot.clock.now` — Core's
    /// fractional tick accumulator, as of `publishedAt`.
    private(set) var publishedTickFraction: Double = 0
    /// How far ahead of a published snapshot the map may predict.
    ///
    /// The pump publishes every 250 ms, so this is never reached while the
    /// app is running. It exists for when it stops being reached — a stall, a
    /// return from the background — where extrapolating minutes of real time
    /// from a stale snapshot would fling every aircraft down its route and
    /// then yank it back on the next publish. Holding still is the honest
    /// answer when the last truth is that old.
    private static let maxPredictionSeconds: TimeInterval = 1.5
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
    @ObservationIgnored private var cachedCompetition: CompetitionSummary?
    @ObservationIgnored private var cachedDashboard: DashboardModel?
    @ObservationIgnored private var cachedProgression: ProgressionModel?
    /// Doubly optional on purpose: the inner `nil` is a real answer — a quiet
    /// airline with nothing to do — and a single optional could not tell it
    /// apart from "not computed yet", so the most expensive derivation of the
    /// six would re-run on every gesture frame precisely when it has nothing
    /// to say.
    @ObservationIgnored private var cachedNextMove: HomeNextMove??

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
        cachedCompetition = nil
        cachedDashboard = nil
        cachedProgression = nil
        cachedNextMove = nil
    }

    /// The competitive picture — Home's one rival fact, the World hub's live
    /// line, the Competitors screen. Computed once per snapshot like the
    /// rest: it walks every route and the market-move record.
    var competitionSummary: CompetitionSummary? {
        guard let snapshot, let catalog else { return nil }
        if let cachedCompetition { return cachedCompetition }
        let summary = snapshot.competitionSummary(catalog: catalog)
        cachedCompetition = summary
        return summary
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

    /// The airline at a glance — the map's top bar and briefing strip, the
    /// briefing's own header and stat grid.
    ///
    /// Cached because the map home reads it on every body pass, and the map's
    /// body is driven by a finger: it walks the routes, the fleet and the
    /// asset valuation, which is not per-gesture-frame work.
    var dashboard: DashboardModel? {
        guard let snapshot else { return nil }
        if let cachedDashboard { return cachedDashboard }
        let model = snapshot.dashboardModel()
        cachedDashboard = model
        return model
    }

    /// The one thing worth doing next, on the map home (AE-048).
    ///
    /// A derivation over `OnboardingModel`, the fleet and `marketOpportunities`
    /// — no stored progress, nothing persisted, and therefore nothing that can
    /// survive a new game or go stale against the state it describes.
    var progressionModel: ProgressionModel? {
        guard let snapshot, let catalog else { return nil }
        if let cachedProgression { return cachedProgression }
        let model = snapshot.progressionModel(catalog: catalog)
        cachedProgression = model
        return model
    }

    var homeNextMove: HomeNextMove? {
        guard let snapshot, let model = mapModel else { return nil }
        if let cachedNextMove { return cachedNextMove }
        let move = HomeNextMove.resolve(snapshot: snapshot, model: model,
                                        catalog: catalog,
                                        fleetSummary: fleetSummary)
        cachedNextMove = .some(move)
        return move
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
        /// The airline earned an era the player's purchases do not cover
        /// (docs/MONETIZATION.md §4). Time stops here until Pro; every
        /// command still works, so nothing the player built is taken away.
        case eraCeiling
    }

    // MARK: Entitlement ceiling

    /// Runtime expansion policy. Saved progress is preserved, and simulation
    /// time continues independently of the current purchase entitlement.
    var eraCeiling: Era = .regional {
        didSet {
            guard oldValue != eraCeiling else { return }
            if let session {
                let ceiling = eraCeiling
                Task { await session.setProgressionCeiling(ceiling) }
            }
            if let snapshot { checkEraCeiling(snapshot) }
        }
    }

    /// Expansion is capped; the current airline remains playable.
    private(set) var isBeyondEraCeiling = false

    // MARK: Lifecycle

    func startNewGame(airlineName: String, home: AirportCode, seed: UInt64,
                      scenario: ScenarioCode = "entrepreneur",
                      livery: Livery = .default) {
        guard session == nil else { return }
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
        self.activeSaveSlot = UUID().uuidString.lowercased()
        self.lastSolvencyStage = .healthy
        Task {
            await session.setProgressionCeiling(self.eraCeiling)
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
            if let slot = self.activeSaveSlot {
                _ = await self.save(session: session, slot: slot, announce: false)
            }
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
        guard session == nil else { return }
        startupFailure = nil
        do {
            let catalog = try ContentCatalog.loadBundled()
            let manager = makeSaveManager()
            let result = try manager.load(slot: slot)
            let session = GameSession(state: result.state,
                                      systems: GamePipeline.standard(), catalog: catalog)
            self.catalog = catalog
            self.session = session
            self.activeSaveSlot = slot
            self.saveManager = manager
            self.loadedFromBackup = result.generation > 0 ? result.generation : nil
            self.lastSolvencyStage = .healthy
            Task {
                await session.setProgressionCeiling(self.eraCeiling)
                await session.attachSaveManager(manager, autosaveSlot: slot,
                                                autosaveEveryGameDays: 1)
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

    /// Opens a save file written by the real engine, from a path handed over
    /// on the command line — `-AEUITestLoadSave <path>`.
    ///
    /// For the UI tests only, and a narrow affordance on purpose: the file
    /// goes through the same codec, migrations and session setup as a slot
    /// load, so what the screens then show is a world the simulation built
    /// (`ae-rival-probe` writes it after five simulated years), not a state
    /// assembled for the camera. A late-game world is ~1,800 sunrise taps
    /// away from a fresh one; a save is how a player reaches it too.
    func loadFixtureIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-AEUITestLoadSave"),
              arguments.indices.contains(flag + 1), session == nil else { return }
        loadGame(fileURL: URL(fileURLWithPath: arguments[flag + 1]))
    }

    private func loadGame(fileURL: URL) {
        startupFailure = nil
        do {
            let catalog = try ContentCatalog.loadBundled()
            let manager = makeSaveManager()
            let state = try manager.codec.decode(try Data(contentsOf: fileURL))
            let session = GameSession(state: state, systems: GamePipeline.standard(),
                                      catalog: catalog)
            self.catalog = catalog
            self.session = session
            let slot = UUID().uuidString.lowercased()
            self.activeSaveSlot = slot
            self.saveManager = manager
            self.loadedFromBackup = nil
            self.lastSolvencyStage = .healthy
            Task {
                await session.setProgressionCeiling(self.eraCeiling)
                await session.attachSaveManager(manager, autosaveSlot: slot,
                                                autosaveEveryGameDays: 1)
                await self.subscribe()
                await self.refresh()
                self.setPumping(true)
            }
        } catch {
            self.startupFailure = "The save at \(fileURL.lastPathComponent) could not be opened: \(error)"
        }
    }

    func clearStartupFailure() {
        startupFailure = nil
    }

    func availableSlots() -> [(slot: String, meta: SlotMeta?)] {
        let manager = saveManager ?? makeSaveManager()
        return manager.store.slots().map { ($0, manager.store.meta(slot: $0)) }
    }

    func exportCampaign() async throws -> CampaignDocument {
        guard let session else { throw CocoaError(.fileNoSuchFile) }
        let state = await session.snapshot
        let data = try await Task.detached { try JSONSaveCodec().encode(state) }.value
        return CampaignDocument(data: data)
    }

    /// Imports only validated data and always into a fresh slot. An invalid
    /// file or a failed write cannot replace a campaign the player already has.
    func importCampaign(from url: URL, access: ContentAccess) throws {
        guard session == nil, access.allowsNewSave(existingSaves: availableSlots().count) else {
            throw SaveError.corruptPayload("Keep your current campaign, or use Pro to keep more than one.")
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let limit = 32 * 1024 * 1024
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else {
            throw SaveError.corruptPayload("This file is too large to be an Airline Empire campaign.")
        }
        let manager = makeSaveManager()
        let state = try manager.codec.decode(data)
        guard state.playerAirline != nil else {
            throw SaveError.corruptPayload("This save does not contain a founded airline.")
        }
        let slot = UUID().uuidString.lowercased()
        try manager.save(state, slot: slot)
        loadGame(slot: slot)
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
        if slot == "auto" { return "Autosave" }
        return UUID(uuidString: slot) == nil ? slot.capitalized : "Campaign"
    }

    private func makeSaveManager() -> SaveManager {
        let root = savesDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("AirlineEmpire/saves", isDirectory: true)
        return SaveManager(store: FileSaveStore(rootDirectory: root))
    }

    private func attachPersistence() async {
        guard let session, let activeSaveSlot else { return }
        let manager = makeSaveManager()
        saveManager = manager
        await session.attachSaveManager(manager, autosaveSlot: activeSaveSlot,
                                        autosaveEveryGameDays: 1)
    }

    /// Backgrounding: save, quietly. A failure here is recorded but never
    /// interrupts — the player is already looking at another app.
    func saveOnBackground() {
        guard let session, let slot = activeSaveSlot,
              backgroundSaveTask == .invalid else { return }
        backgroundSaveTask = UIApplication.shared.beginBackgroundTask(withName: "Save campaign") {
            MainActor.assumeIsolated { self.endBackgroundSave() }
        }
        Task {
            _ = await self.save(session: session, slot: slot, announce: false)
            self.endBackgroundSave()
        }
    }

    private func endBackgroundSave() {
        guard backgroundSaveTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundSaveTask)
        backgroundSaveTask = .invalid
    }

    /// An explicit save, which must report what happened either way.
    func saveNow() {
        guard let session, let slot = activeSaveSlot else { return }
        Task { _ = await self.save(session: session, slot: slot, announce: true) }
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
    @discardableResult
    func saveAndQuit() async -> Bool {
        guard !isSavingAndQuitting, let session, let slot = activeSaveSlot else { return false }
        isSavingAndQuitting = true
        let wasPumping = pumpTask != nil
        setPumping(false)
        defer { isSavingAndQuitting = false }
        guard await save(session: session, slot: slot, announce: true, announceSuccess: false) else {
            if self.session === session { setPumping(wasPumping) }
            return false
        }
        guard self.session === session else { return false }
        let closingState = await session.snapshot
        guard self.session === session else { return false }
        let report = sessionCheckpoint.flatMap { start in
            SessionCheckpoint(closingState).flatMap { SessionReport(from: start, to: $0) }
        }
        let nextMove = homeNextMove?.title
        quitToMenu()
        lastSessionReport = report
        lastSessionNextMove = nextMove
        lastSaveOutcome = nil // The saved-session card is the confirmation.
        return true
    }

    private func save(session: GameSession, slot: String, announce: Bool,
                      announceSuccess: Bool = true) async -> Bool {
        do {
            try await session.saveNow(slot: slot)
            guard self.session === session else { return true }
            quietSaveFailure = nil
            if announce && announceSuccess { lastSaveOutcome = .saved(slot: slot) }
            return true
        } catch {
            guard self.session === session else { return false }
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
            return false
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
        activeSaveSlot = nil
        sessionCheckpoint = nil
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
        // Every derived cache, by the one function that knows them all. This
        // was an inline copy of that list and had already drifted once: a
        // cache added for a screen is a cache the *next* airline inherits
        // unless somebody remembers two places (BUG-013's shape).
        invalidateCaches()
    }

    /// Game minutes to add to the published snapshot's clock to get the world
    /// as it stands at `date` — the map's client-side prediction, in the one
    /// unit the simulation measures time in.
    ///
    /// Monotonic by construction: `publishedTickFraction` is the part of a
    /// tick already paid for in real time, so the base it is added to never
    /// steps forwards without the fraction stepping back by the same amount.
    /// Paused returns the frozen fraction rather than zero — the aircraft
    /// stay where the pause found them instead of stepping back to the last
    /// tick (BUG-058).
    func predictedGameMinutes(at date: Date) -> Double {
        let realSeconds = min(max(0, date.timeIntervalSince(publishedAt)),
                              Self.maxPredictionSeconds)
        return publishedTickFraction + realSeconds * speed.gameMinutesPerRealSecond
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
        #if DEBUG
        manualAdvanceRequests += 1
        #endif
        Task {
            await session.advanceToNextMorning()
            await self.refresh()
        }
    }

    /// Several mornings, one refresh: what `count` taps of the sunrise do
    /// to the world, without the screen catching up between them. The UI
    /// journeys' week control uses it (`-AEUITestSunriseWeek`).
    func advanceMornings(_ count: Int) {
        guard let session, count > 0 else { return }
        #if DEBUG
        manualAdvanceRequests += 1
        #endif
        Task {
            for _ in 0..<count {
                await session.advanceToNextMorning()
            }
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
        return ExpansionAccess.rejection(for: command, state: snapshot,
                                         catalog: catalog, ceiling: eraCeiling)
            ?? command.validate(state: snapshot, catalog: catalog)
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
            guard self.session === session else { return }
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
        let fraction = await session.pendingGameMinutes
        let sessionSpeed = await session.speed
        guard self.session === session else { return }
        if sessionCheckpoint == nil {
            sessionCheckpoint = SessionCheckpoint(state)
        }
        if state.clock.tickCount != snapshot?.clock.tickCount {
            snapshotReceivedAt = Date()
        }
        // Every publish, tick or no tick: this pair *is* the current game
        // time, and `state.clock.now + fraction` is continuous across a tick
        // boundary precisely because the fraction drops by a tick as the
        // clock gains one.
        publishedAt = Date()
        publishedTickFraction = fraction
        invalidateCaches()
        snapshot = state
        speed = sessionSpeed
        checkEraCeiling(state)
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

    /// Present an expansion offer without pausing the player's operations.
    private func checkEraCeiling(_ state: GameState) {
        isBeyondEraCeiling = eraCeiling < .empire && state.progression.era >= eraCeiling
        if autoPauseReason == .eraCeiling { autoPauseReason = nil }
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
