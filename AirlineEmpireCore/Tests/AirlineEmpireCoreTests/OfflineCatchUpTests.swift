import Foundation
import Testing
@testable import AirlineEmpireCore

/// Capped offline catch-up (AE-050, docs/LAUNCH_AUDIT.md §6: "cap, clock
/// changes, expiry, no absence punishment, deterministic processing").
@Suite("Offline catch-up")
struct OfflineCatchUpTests {
    static let tuning = OfflineCatchUpTuning.standard
    static let hour: Double = 3_600
    static let day: Double = 86_400

    /// One airline flying MET–COS, without the world-event system — so no
    /// tourism boom can offer a mission mid-test and stop a catch-up that is
    /// meant to run to its credit.
    static func world(adjust: (inout GameState, AirlineID) -> Void = { _, _ in })
        throws -> (session: GameSession, state: GameState, airline: AirlineID, catalog: ContentCatalog) {
        let (engine, airline, _) = try DemandFixtures.market(fare: .dollars(129))
        var state = engine.state
        adjust(&state, airline)
        let session = GameSession(state: state, systems: systems, catalog: engine.catalog)
        return (session, state, airline, engine.catalog)
    }

    static var systems: [any SimulationSystem] {
        GamePipeline.standard().filter { $0.id != "worldEvents" }
    }

    // MARK: - The rate and the cap

    @Test("A night away is one game day")
    func aNightIsOneDay() {
        #expect(OfflineCatchUp.creditedGameMinutes(awaySeconds: 8 * Self.hour, tuning: Self.tuning)
                == GameCalendar.minutesPerDay)
        #expect(OfflineCatchUp.plannedTicks(awaySeconds: 8 * Self.hour,
                                            tickMinutes: ScenarioBootstrap.standardTickMinutes,
                                            tuning: Self.tuning) == Fixtures.ticksPerDay)
        #expect(!OfflineCatchUp.isCapped(awaySeconds: 8 * Self.hour, tuning: Self.tuning))
    }

    @Test("No absence earns more than a game week")
    func theCapHolds() {
        let week = 7 * GameCalendar.minutesPerDay
        for away in [3 * Self.day, 30 * Self.day, 365 * Self.day] {
            #expect(OfflineCatchUp.creditedGameMinutes(awaySeconds: away, tuning: Self.tuning) == week)
            #expect(OfflineCatchUp.isCapped(awaySeconds: away, tuning: Self.tuning))
        }
    }

    @Test("A wound-back, broken or absurd clock earns nothing")
    func untrustworthyClocksEarnNothing() {
        let untrusted: [Double] = [-Self.hour, -1, 0, .nan, .infinity, -.infinity,
                                   401 * Self.day, 50 * 365 * Self.day]
        for away in untrusted {
            #expect(OfflineCatchUp.creditedGameMinutes(awaySeconds: away, tuning: Self.tuning) == 0)
            #expect(!OfflineCatchUp.isCapped(awaySeconds: away, tuning: Self.tuning))
        }
        // An app switch is not time away.
        #expect(OfflineCatchUp.creditedGameMinutes(awaySeconds: 5 * 60, tuning: Self.tuning) == 0)
        #expect(OfflineCatchUp.creditedGameMinutes(awaySeconds: 10 * 60, tuning: Self.tuning) == 30)
    }

    @Test("The shipped tuning is the bundled tuning, and valid")
    func bundledTuning() throws {
        let catalog = try ContentCatalog.loadBundled()
        #expect(catalog.tuning.offline == .standard)
        #expect(OfflineCatchUpTuning.standard.isValid)
        #expect(!OfflineCatchUpTuning(gameMinutesPerRealMinute: -1, capGameDays: 7,
                                      minimumAwayRealMinutes: 10,
                                      maximumTrustedAwayDays: 400).isValid)
    }

    // MARK: - Running it

    @Test("Without an airline, or without credit, nothing runs")
    func nothingToRun() async throws {
        let empty = GameSession(state: Fixtures.newState(), systems: [])
        #expect(await empty.catchUp(awaySeconds: 8 * Self.hour) == nil)

        let (session, state, _, _) = try Self.world()
        #expect(await session.catchUp(awaySeconds: -Self.day) == nil)
        #expect(await session.catchUp(awaySeconds: 60) == nil)
        #expect(try await session.snapshot.stateHash() == state.stateHash())
    }

    @Test("A day away flies the airline and accounts for every dollar")
    func aReturnIsAnAccount() async throws {
        let (session, state, _, _) = try Self.world()
        // A day away is three game days: the first has no schedule yet.
        let report = try #require(await session.catchUp(awaySeconds: Self.day))
        let after = await session.snapshot
        #expect(report.stopReason == nil)
        #expect(report.ticksRun == 3 * Fixtures.ticksPerDay)
        #expect(report.gameMinutesAdvanced == 3 * GameCalendar.minutesPerDay)
        #expect(after.clock.now == state.clock.now + .days(3))
        #expect(report.flightsCompleted > 0)
        #expect(report.passengersCarried > 0)
        #expect(report.revenue > .zero)
        #expect(report.expenses < .zero)
        // The account adds up to the balance's movement exactly.
        #expect(report.revenue + report.expenses == report.cashChange)
        let total = report.byCategory.values.reduce(Money.zero, +)
        #expect(total == report.cashChange)
        #expect(report.isWorthShowing)
    }

    @Test("However long the absence, the world moves a week")
    func theSessionHonoursTheCap() async throws {
        let (session, state, _, _) = try Self.world()
        let report = try #require(await session.catchUp(awaySeconds: 30 * Self.day))
        #expect(report.wasCapped)
        #expect(report.stopReason == nil)
        #expect(report.ticksRun == 7 * Fixtures.ticksPerDay)
        #expect(await session.snapshot.clock.now == state.clock.now + .days(7))
    }

    @Test("A catch-up nothing stopped is exactly the same ticks of play")
    func catchUpEqualsPlay() async throws {
        let (catchingUp, state, _, catalog) = try Self.world()
        let playing = GameSession(state: state, systems: Self.systems, catalog: catalog)
        let report = try #require(await catchingUp.catchUp(awaySeconds: Self.day))
        await playing.advance(ticks: report.ticksRun)
        #expect(try await catchingUp.snapshot.stateHash() == playing.snapshot.stateHash())
    }

    @Test("The same world and the same absence give the same result")
    func catchUpIsDeterministic() async throws {
        let (first, state, _, catalog) = try Self.world()
        let second = GameSession(state: state, systems: Self.systems, catalog: catalog)
        let a = await first.catchUp(awaySeconds: 2 * Self.day)
        let b = await second.catchUp(awaySeconds: 2 * Self.day)
        #expect(a == b)
        #expect(try await first.snapshot.stateHash() == second.snapshot.stateHash())
    }

    // MARK: - Nothing punishes absence

    /// The month's bills land at midnight and take the airline under the
    /// overdraft floor. Played, that midnight starts the administration
    /// countdown; away, the catch-up puts the tick back and the world waits
    /// at 23:45 for the player to answer it.
    @Test("The administration countdown never starts while the player is away")
    func theCountdownWaits() async throws {
        let floor = try ContentCatalog.loadBundled().tuning.finance.overdraftFloorCents
        let (engine, airline, _) = try DemandFixtures.market(fare: .dollars(129))
        // 23:45 on 31 January: the next tick is the month boundary.
        let control = SimulationEngine(state: engine.state, systems: Self.systems,
                                       catalog: engine.catalog)
        control.advance(ticks: 30 * Fixtures.ticksPerDay + Fixtures.ticksPerDay - 1)
        var state = control.state
        let target = Money(cents: floor) + .dollars(1_000)
        state.ledger.post(airline: airline, category: .initialCapital,
                          amount: target - state.ledger.balance(of: airline), at: state.clock.now)

        // Played straight through, that midnight counts a day of insolvency.
        let played = SimulationEngine(state: state, systems: Self.systems, catalog: engine.catalog)
        played.advance(ticks: 1)
        #expect(played.state.airlines[airline]?.daysInsolvent == 1)

        let session = GameSession(state: state, systems: Self.systems, catalog: engine.catalog)
        let report = try #require(await session.catchUp(awaySeconds: Self.day))
        let after = await session.snapshot
        #expect(report.stopReason == .solvency)
        #expect(report.ticksRun == 0)
        #expect(after.airlines[airline]?.daysInsolvent == 0)
        #expect(after.airlines[airline]?.administrationCount == 0)
        #expect(after.airlines[airline]?.status == .active)
        // The undone tick left no trace at all.
        #expect(try after.stateHash() == state.stateHash())
        #expect(report.isWorthShowing)
    }

    @Test("An airline one day from administration is not run while away")
    func aCountdownInProgressWaits() async throws {
        let floor = try ContentCatalog.loadBundled().tuning.finance.overdraftFloorCents
        let (session, state, airline, _) = try Self.world { state, airline in
            let below = Money(cents: floor) - .dollars(500_000)
            state.ledger.post(airline: airline, category: .initialCapital,
                              amount: below - state.ledger.balance(of: airline),
                              at: state.clock.now)
            state.airlines[airline]?.daysInsolvent = 6
        }
        let report = try #require(await session.catchUp(awaySeconds: 3 * Self.day))
        let after = await session.snapshot
        #expect(report.stopReason == .solvency)
        #expect(report.ticksRun == 0)
        #expect(after.airlines[airline]?.administrationCount == 0)
        #expect(after.airlines[airline]?.daysInsolvent == 6)
        #expect(try after.stateHash() == state.stateHash())
    }

    @Test("A held contract never expires while the player is away")
    func aDeadlineWaits() async throws {
        let (session, state, _, _) = try Self.world { state, _ in
            let deadline = SimTime(rawMinutes: (state.clock.now.dayIndex + 1)
                                   * GameCalendar.minutesPerDay)
            state.progression.missions.append(Mission(
                id: state.progression.nextMissionID, sourceEventID: -1,
                kind: .flightContract(targetFlights: 10_000), deadline: deadline,
                reward: .dollars(1_000_000), baseline: 0))
            state.progression.nextMissionID += 1
        }
        let mission = try #require(state.progression.missions.first)
        let report = try #require(await session.catchUp(awaySeconds: Self.day))
        let after = await session.snapshot
        #expect(report.stopReason == .deadline)
        #expect(report.ticksRun > 0)
        #expect(after.clock.now < mission.deadline)
        #expect(after.progression.missions.contains { $0.id == mission.id })
    }

    // MARK: - The anchor

    @Test("A save records when it was written; an older meta file does not")
    func slotMetaCarriesTheWallClock() throws {
        let root = SaveStoreTests.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let (state, catalog) = try SaveStoreTests.populatedState()
        let manager = SaveStoreTests.manager(root, catalog)
        let written = Date(timeIntervalSince1970: 1_800_000_000)
        try manager.save(state, slot: "away", at: written)
        #expect(manager.store.meta(slot: "away")?.savedAt == written)

        let legacy = Data(#"{"airlineName":"Anchor Air","era":"startup","gameDateDescription":"2030-01-21","netWorthCents":1,"savedAtTick":1}"#.utf8)
        let decoded = try JSONDecoder().decode(SlotMeta.self, from: legacy)
        #expect(decoded.savedAt == nil)
    }
}
