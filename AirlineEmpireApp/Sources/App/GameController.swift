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

    private var session: GameSession?
    private var saveManager: SaveManager?
    private var pumpTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?

    var hasGame: Bool { session != nil }

    // MARK: Lifecycle

    func startNewGame(airlineName: String, home: AirportCode, seed: UInt64,
                      scenario: ScenarioCode = "entrepreneur") {
        do {
            let catalog = try ContentCatalog.loadBundled()
            guard let spec = catalog.scenario(scenario) else {
                assertionFailure("Unknown scenario \(scenario)")
                return
            }
            let state = ScenarioBootstrap.newGame(scenario: scenario,
                                                  worldSeed: seed,
                                                  startYear: spec.startYear)
            let session = GameSession(state: state, systems: GamePipeline.standard(),
                                      catalog: catalog)
            self.catalog = catalog
            self.session = session
            Task {
                await session.beginScenario(spec, airlineName: airlineName, home: home)
                await self.attachPersistence()
                await self.subscribe()
                await self.refresh()
            }
        } catch {
            assertionFailure("Content failed to load: \(error)")
        }
    }

    func loadGame(slot: String) {
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
            Task {
                await session.attachSaveManager(manager)
                await self.subscribe()
                await self.refresh()
            }
        } catch {
            self.lastRejection = CommandRejection(
                code: "load.failed", message: "Could not load this save")
        }
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

    func saveOnBackground() {
        guard let session else { return }
        Task { try? await session.saveNow(slot: "auto") }
    }

    // MARK: Time control

    func setSpeed(_ newSpeed: SimSpeed) {
        speed = newSpeed
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

    func submit(_ command: any Command) {
        guard let session else { return }
        Task {
            let result = await session.submit(command)
            if case .rejected(let rejection) = result {
                self.lastRejection = rejection
            }
            await self.refresh()
        }
    }

    func clearRejection() {
        lastRejection = nil
    }

    // MARK: Snapshot plumbing

    private func subscribe() async {
        guard let session else { return }
        // Replacing the session replaces the stream; cancelling the old
        // consumer finishes its iteration (tasks/TECH_DEBT.md TD-002).
        eventTask?.cancel()
        recentEvents = []
        let events = await session.events()
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.recentEvents.append(event)
                if self.recentEvents.count > 200 {
                    self.recentEvents.removeFirst(self.recentEvents.count - 200)
                }
            }
        }
    }

    private func refresh() async {
        guard let session else { return }
        snapshot = await session.snapshot
        speed = await session.speed
    }
}
