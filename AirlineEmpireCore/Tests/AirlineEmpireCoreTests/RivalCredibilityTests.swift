import Testing
@testable import AirlineEmpireCore

/// AE-041: the rivals' own openings judged by their own ledgers
/// (docs/AE041_ECONOMIC_CREDIBILITY.md). The scan measured, across 150
/// two-year campaigns on the shipped ranking, that the conservative
/// archetype bought a used airframe on a six-month runway, landed on one
/// month of cash, and a week later retrenched: it closed the full, earning
/// route it had opened three weeks before — judged the worst loss-maker on
/// a closed month of costs with no revenue — and sold the airframe it had
/// just bought (BUG-054, 143 of 150 campaigns). This is the seed-2039
/// Stockholm cast in which that happened to Crown Meridian on days 72–79.
@Suite("Rival credibility")
struct RivalCredibilityTests {

    struct Watch {
        var openedDay: Int
        var flightsCompleted: Int64 = 0
        var loadFactor: Double = 0
        var lastMonthRevenueCents: Int64 = 0
    }

    /// BUG-054: no rival closes a route that is flying full and earning
    /// within its first months, and no rival sells an airframe within a
    /// month of buying it. Both were the retrench rule's doing.
    ///
    /// Fifteen minutes against **9.5 seconds of work** (MEASURED, AE-044, run
    /// alone on the session container; 9.99 s and 10.19 s on two earlier
    /// measurements, so the figure is stable). It was five, and five was the
    /// one PR #15 explicitly judged safe at 31x headroom on a **4x** measured
    /// contention factor.
    ///
    /// That 4x is now measured too low. In CI run 152 this test tripped the
    /// 300-second limit while the suite's own wall clock ran 1,460 s — a
    /// short test starved past its guard by the two twenty-minute balance
    /// tests sharing the runner, which is **>30x** contention on 9.5 s of
    /// work, not 4x. It passed on runs 149, 150 and 151 of the same branch
    /// and on 147 and 148 of main, so the guard is measuring the machine's
    /// load on the day, exactly as it did for the three limits PR #15 raised.
    ///
    /// Fifteen minutes is 95x the measured work and sits above the suite's
    /// own longest wall clock, so a starved run cannot trip it, while a
    /// genuinely hung test is still caught well inside the job's 45-minute
    /// timeout. **No assertion, seed, or piece of test logic changed.** The
    /// root cause is not a limit and cannot be fixed by one: TD-034.
    @Test(.timeLimit(.minutes(15)))
    func aRivalDoesNotBuyAnAirframeAndRetrenchAWeekLater() throws {
        let catalog = try ContentCatalog.loadBundled()
        let spec = try #require(catalog.scenario("entrepreneur"))
        let engine = SimulationEngine(
            state: ScenarioBootstrap.newGame(scenario: "entrepreneur", worldSeed: 2039,
                                             startYear: spec.startYear),
            systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Credibility Air", kind: .player, homeAirport: "ARN",
            startingCash: spec.playerStartingCash))
        WorldSetup.createCompetitors(engine: engine, count: spec.competitorCount,
                                     playerHome: "ARN", startingCash: spec.competitorStartingCash)
        let crown = try #require(engine.state.airlines.values.first { $0.name == "Crown Meridian" })
        #expect(crown.aiProfile?.archetype == .conservative)
        let ticksPerDay = Int(GameCalendar.minutesPerDay / ScenarioBootstrap.standardTickMinutes)

        var routes: [RouteID: Watch] = [:]
        var airframes: [AircraftID: (owner: AirlineID, day: Int)] = [:]
        var earlyClosures: [String] = []
        var quickSales: [String] = []
        var crownOpenings: [String] = []
        for day in 1...150 {
            engine.advance(ticks: ticksPerDay)
            let state = engine.state
            // Rival routes: seen, refreshed, or gone.
            for (id, watch) in routes where state.routes[id] == nil {
                // Gone. A route that had flown a real schedule, full, is not
                // one a solvent airline closes in its first season.
                if watch.flightsCompleted >= 30, watch.loadFactor >= 0.8,
                   state.airlines.values.contains(where: { $0.status == .active && state.routes(of: $0.id).isEmpty == false }) {
                    earlyClosures.append("route \(id) opened day \(watch.openedDay) gone day \(day) after \(watch.flightsCompleted) flights at \(Int(watch.loadFactor * 100))% load")
                }
                routes[id] = nil
            }
            for route in state.routes.values where route.airline != state.playerAirline?.id {
                if routes[route.id] == nil {
                    routes[route.id] = Watch(openedDay: day)
                    if route.airline == crown.id {
                        crownOpenings.append("D\(day) \(route.origin.raw)-\(route.destination.raw)")
                    }
                }
                routes[route.id]?.flightsCompleted = route.stats.flightsCompleted
                routes[route.id]?.loadFactor = route.stats.loadFactor
                routes[route.id]?.lastMonthRevenueCents = route.economicsLastMonth.revenueCents
            }
            // Rival airframes: bought, then sold within a month?
            for (id, bought) in airframes where state.aircraft[id] == nil {
                if state.airlines[bought.owner]?.status == .active, day - bought.day <= 30 {
                    quickSales.append("aircraft \(id) of \(state.airlines[bought.owner]?.name ?? "?") bought day \(bought.day) gone day \(day)")
                }
                airframes[id] = nil
            }
            for aircraft in state.aircraft.values
            where state.airlines[aircraft.owner]?.kind == .ai && airframes[aircraft.id] == nil {
                airframes[aircraft.id] = (aircraft.owner, day)
            }
        }
        print("RIVAL-CREDIBILITY seed 2039: Crown Meridian opened \(crownOpenings) · early closures \(earlyClosures) · quick sales \(quickSales)")
        #expect(earlyClosures.isEmpty, "\(earlyClosures)")
        #expect(quickSales.isEmpty, "\(quickSales)")
        // The measured scenario: the third route, Tokyo–Beijing, opened on
        // day 58 and closed on day 79 before the fix, is still flown.
        let final = engine.state
        let pek = final.routes(of: crown.id).first { $0.sameMarket(origin: "HND", destination: "PEK") }
        #expect(pek != nil, "Crown Meridian no longer flies Tokyo–Beijing: \(crownOpenings)")
        #expect(final.airlines[crown.id]?.status == .active)
    }
}
