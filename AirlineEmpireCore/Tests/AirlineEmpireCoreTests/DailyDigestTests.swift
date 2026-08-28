import Testing
@testable import AirlineEmpireCore

/// The evening digest (docs/CORE_LOOP.md §3) must be exact, honest about
/// its own limits, and derived — never a second copy of the ledger.
@Suite("Daily digest")
struct DailyDigestTests {
    private func flyingWorld(seed: UInt64 = 606)
        throws -> (SimulationEngine, AirlineID) {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(seed: seed),
                                      systems: GamePipeline.standard(),
                                      catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Digest Air", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(120_000_000)))
        let player = engine.state.airlines.values.first!.id
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: player, type: "MR180",
                                                   ageYears: 6))
        let aircraft = engine.state.fleet(of: player)[0].id
        let suggestion = engine.state.onboardingModel(catalog: catalog)!
            .suggestions[0]
        _ = engine.applyNow(OpenRouteCommand(
            airline: player, origin: suggestion.origin,
            destination: suggestion.destination, dailyRoundTrips: 3,
            ticketPrice: suggestion.referenceFare))
        let route = engine.state.routes(of: player)[0].id
        _ = engine.applyNow(AssignAircraftToRouteCommand(
            airline: player, route: route, aircraftID: aircraft))
        return (engine, player)
    }

    @Test func digestReconcilesWithTheDaysTransactionsExactly() throws {
        let (engine, player) = try flyingWorld()
        engine.advance(ticks: Fixtures.ticksPerDay * 12)
        let state = engine.state
        // Summarize a completed day, the way an evening digest does.
        let day = state.clock.now.dayIndex - 1
        let digest = try #require(state.dailyDigest(for: player, day: day))

        #expect(digest.dayIndex == day)
        #expect(digest.isComplete)
        #expect(digest.hasContent)

        // Recompute independently from the ledger and demand agreement.
        let dayStart = SimTime(rawMinutes: day * GameCalendar.minutesPerDay)
        let dayEnd = SimTime(rawMinutes: (day + 1) * GameCalendar.minutesPerDay)
        let today = state.ledger.recent.filter {
            $0.airline == player && $0.at >= dayStart && $0.at < dayEnd
        }
        #expect(!today.isEmpty)
        let expectedNet = today.reduce(Int64(0)) { $0 + $1.amount.cents }
        #expect(digest.netCashChange.cents == expectedNet)
        #expect(digest.revenue.cents
            == today.filter { $0.amount.cents >= 0 }.reduce(0) { $0 + $1.amount.cents })
        #expect(digest.expenses.cents
            == today.filter { $0.amount.cents < 0 }.reduce(0) { $0 + $1.amount.cents })
        // Revenue + expenses is the whole story, by construction.
        #expect(digest.revenue + digest.expenses == digest.netCashChange)

        // Categories sum back to the net, so the "why" explains the "what".
        let categorySum = digest.byCategory.values.reduce(Money.zero, +)
        #expect(categorySum == digest.netCashChange)
        // A flying day earns tickets and burns fuel.
        #expect(digest.byCategory[.ticketRevenue]?.cents ?? 0 > 0)
        #expect(digest.byCategory[.fuel]?.cents ?? 0 < 0)
        #expect(digest.flightsCompleted > 0)
    }

    @Test func digestIsPureAndDeterministic() throws {
        let (engine, player) = try flyingWorld()
        engine.advance(ticks: Fixtures.ticksPerDay * 8)
        let before = try engine.state.stateHash()
        let first = engine.state.dailyDigest(for: player)
        let second = engine.state.dailyDigest(for: player)
        let after = try engine.state.stateHash()
        #expect(first == second)
        #expect(before == after)
    }

    @Test func digestCarriesTheDaysNewsButNotItsNoise() throws {
        let (engine, player) = try flyingWorld()
        engine.advance(ticks: Fixtures.ticksPerDay * 40)
        let state = engine.state
        // Scan recent days for one that carried news.
        var withNews: DailyDigestModel?
        for offset in 1...20 {
            let candidate = state.dailyDigest(for: player,
                                              day: state.clock.now.dayIndex - Int64(offset))
            if let candidate, !candidate.notableEvents.isEmpty {
                withNews = candidate
                break
            }
        }
        let digest = try #require(withNews, "40 days produced no notable event")
        for event in digest.notableEvents {
            // Never per-flight chatter, never another airline's business.
            switch event.kind {
            case .flightDeparted, .flightArrived, .flightDelayed, .dayStarted,
                 .commandApplied, .wakeFired:
                Issue.record("noise leaked into the digest: \(event.kind)")
            default: break
            }
            #expect(state.isFeedEvent(event, for: player))
            #expect(event.at.dayIndex == digest.dayIndex)
        }
    }

    @Test func digestOnlyCoversTheRequestedDay() throws {
        let (engine, player) = try flyingWorld()
        engine.advance(ticks: Fixtures.ticksPerDay * 10)
        let state = engine.state
        let a = try #require(state.dailyDigest(for: player,
                                               day: state.clock.now.dayIndex - 1))
        let b = try #require(state.dailyDigest(for: player,
                                               day: state.clock.now.dayIndex - 2))
        #expect(a.dayIndex != b.dayIndex)
        #expect(a.date.day != b.date.day)
        // Two different operating days do not share one set of postings.
        #expect(a.netCashChange != .zero || b.netCashChange != .zero)
    }

    /// A day before the airline existed has nothing to report, and an
    /// unknown airline has no digest at all.
    @Test func emptyAndAbsentCasesAreHandled() throws {
        let (engine, player) = try flyingWorld()
        engine.advance(ticks: Fixtures.ticksPerDay * 3)
        let state = engine.state
        let unknown = state.dailyDigest(for: AirlineID(raw: 99_999))
        #expect(unknown == nil)

        // A far-future day has no transactions yet.
        let future = try #require(state.dailyDigest(for: player,
                                                    day: state.clock.now.dayIndex + 30))
        #expect(future.netCashChange == .zero)
        #expect(future.flightsCompleted == 0)
        #expect(!future.hasContent)
    }

    /// Honesty under pressure: when the transaction ring cannot hold a
    /// whole day, the digest must say so instead of under-reporting.
    @Test func truncationIsReportedNotHidden() throws {
        let catalog = try ContentCatalog.loadBundled()
        // A deliberately tiny ring stands in for a very large network.
        var state = Fixtures.newState(seed: 12)
        state.ledger = Ledger(recentCapacity: 8)
        let engine = SimulationEngine(state: state,
                                      systems: GamePipeline.standard(),
                                      catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Tiny Ring", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(120_000_000)))
        let player = engine.state.airlines.values.first!.id
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: player, type: "MR180",
                                                   ageYears: 6))
        let aircraft = engine.state.fleet(of: player)[0].id
        let suggestion = engine.state.onboardingModel(catalog: catalog)!
            .suggestions[0]
        _ = engine.applyNow(OpenRouteCommand(
            airline: player, origin: suggestion.origin,
            destination: suggestion.destination, dailyRoundTrips: 4,
            ticketPrice: suggestion.referenceFare))
        let route = engine.state.routes(of: player)[0].id
        _ = engine.applyNow(AssignAircraftToRouteCommand(
            airline: player, route: route, aircraftID: aircraft))
        engine.advance(ticks: Fixtures.ticksPerDay * 5)

        let digest = try #require(engine.state.dailyDigest(
            for: player, day: engine.state.clock.now.dayIndex - 1))
        #expect(!digest.isComplete, "a full ring must flag the day as partial")
    }
    // MARK: - BUG-008: the first day has no yesterday

    /// The crash TestFlight found in 1.0.0 (1), reproduced at the Core level.
    ///
    /// On the first day `clock.now.dayIndex` is 0, so a caller asking for
    /// "yesterday" asks for day −1. That reached `GameCalendar.date(at:)`,
    /// whose `day >= 0` precondition killed the process — on the first screen
    /// after founding an airline, which is every new player's first action.
    @Test("A day before the game began has no digest, and does not crash")
    func digestBeforeEpochIsNil() throws {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(seed: 808),
                                      systems: GamePipeline.standard(),
                                      catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Day Zero Air", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(50_000_000)))
        let player = engine.state.airlines.values.first!.id

        #expect(engine.state.clock.now.dayIndex == 0)
        #expect(engine.state.dailyDigest(for: player, day: -1) == nil)
        #expect(engine.state.dailyDigest(for: player, day: -365) == nil)
        // Today still works: the guard rejects days before the epoch, not the
        // first day itself.
        #expect(engine.state.dailyDigest(for: player, day: 0) != nil)
    }

    /// The shape the dashboard actually uses. `previousDayIndex` is the fix
    /// at the call site: it makes "there is no yesterday" representable
    /// instead of arithmetic that silently produces −1.
    @Test("previousDayIndex is nil on day 0 and one less thereafter")
    func previousDayIndexIsSafe() {
        #expect(SimTime(rawMinutes: 0).previousDayIndex == nil)
        #expect(SimTime(rawMinutes: 60).previousDayIndex == nil)
        #expect(SimTime(rawMinutes: GameCalendar.minutesPerDay - 1).previousDayIndex == nil)
        #expect(SimTime(rawMinutes: GameCalendar.minutesPerDay).previousDayIndex == 0)
        #expect(SimTime(rawMinutes: 10 * GameCalendar.minutesPerDay + 5).previousDayIndex == 9)
    }

}
