import Testing
@testable import AirlineEmpireCore

/// HORIZON-06: a start the world never came to now meets a rival that comes
/// on its own — Munich, the Linux twin of `HorizonArrivalUITests`
/// (docs/HORIZON_AUDIT.md §5).
///
/// The script is what the journey does in the simulator and nothing more:
/// found in Munich on seed 2030, lease a narrowbody, open the guided first
/// route, then in February buy a used narrowbody, lease another, and open
/// the two markets Home's Next Moves card names — one of them Istanbul.
/// PacificBlue, the low-cost carrier based at Istanbul, does the rest.
@Suite("Munich horizon")
struct MunichHorizonTests {

    static let seed: UInt64 = 2030
    static let home: AirportCode = "MUC"

    struct Report {
        var firstRoute = ""
        var februaryMarkets: [String] = []
        var entryDay: Int?
        var entrant = ""
        var archetype = ""
        var market = ""
        var entrantFare = Money.zero
        var playerFare = Money.zero
        var headlineNextMorning = ""
        var headlinePair = ""
        var feedEventNextMorning = false
        var shareAfterMonth: Double?
        var standingAfterMonth: MarketCompetition.Standing?
        var edgeAfterMonth: MarketCompetition.Edge?
        var spareRotationsAfterMonth = 0
        var profitBefore = Money.zero
        var profitAfter = Money.zero
        var eraDay: Int?
        var responseDay: Int?
        var shareAtDay90: Double?
        var laterProfits: [Money] = []
    }

    enum Response: String { case none, frequency, fare }

    func run(days: Int, respond: Response) async throws -> Report {
        let catalog = try ContentCatalog.loadBundled()
        let spec = try #require(catalog.scenario("entrepreneur"))
        let session = GameSession(
            state: ScenarioBootstrap.newGame(scenario: "entrepreneur", worldSeed: Self.seed,
                                             startYear: spec.startYear),
            systems: GamePipeline.standard(), catalog: catalog)
        #expect(await session.beginScenario(spec, airlineName: "Bavaria Air", home: Self.home) == .applied)
        var state = await session.snapshot
        let player = try #require(state.playerAirline).id
        #expect(await session.submit(LeaseAircraftCommand(lessee: player, type: "PA184", termMonths: 60)) == .applied)
        state = await session.snapshot
        let first = try #require(state.onboardingModel(catalog: catalog)?.suggestions.first)
        #expect(await session.submit(OpenRouteCommand(
            airline: player, origin: first.origin, destination: first.destination,
            dailyRoundTrips: 2, ticketPrice: first.referenceFare)) == .applied)
        try await assignIdle(session, player: player, catalog: catalog)

        var report = Report()
        report.firstRoute = "\(first.origin.raw)-\(first.destination.raw)"
        var expanded = false
        var knownRivalRoutes: Set<RouteID> = []
        let ticksPerDay = Int(GameCalendar.minutesPerDay / ScenarioBootstrap.standardTickMinutes)

        for day in 1...days {
            await session.advance(ticks: ticksPerDay)
            state = await session.snapshot
            if !expanded, state.currentDate.month == 2 {
                expanded = true
                _ = await session.submit(BuyUsedAircraftCommand(buyer: player, type: "MR180", ageYears: 8))
                _ = await session.submit(LeaseAircraftCommand(lessee: player, type: "PA184", termMonths: 60))
                state = await session.snapshot
                for market in state.marketOpportunities(catalog: catalog, limit: 4)
                    .filter(\.servableNow).prefix(2) {
                    _ = await session.submit(OpenRouteCommand(
                        airline: player, origin: market.origin, destination: market.destination,
                        dailyRoundTrips: 2, ticketPrice: market.referenceFare))
                    report.februaryMarkets.append("\(market.origin.raw)-\(market.destination.raw)")
                }
                try await assignIdle(session, player: player, catalog: catalog)
                state = await session.snapshot
                knownRivalRoutes = Set(state.routes.values.filter { $0.airline != player }.map(\.id))
            }
            let mine = state.routes(of: player)
            let myPairs = Set(mine.map(\.market))
            for route in state.routes.values where route.airline != player && !knownRivalRoutes.contains(route.id) {
                knownRivalRoutes.insert(route.id)
                guard report.entryDay == nil, myPairs.contains(route.market),
                      let ownRoute = mine.first(where: { $0.market == route.market }) else { continue }
                report.entryDay = day
                report.entrant = state.airlines[route.airline]?.name ?? "?"
                report.archetype = state.airlines[route.airline]?.aiProfile.map { "\($0.archetype)" } ?? "?"
                report.market = "\(ownRoute.origin.raw)-\(ownRoute.destination.raw)"
                report.entrantFare = route.ticketPrice
                report.playerFare = ownRoute.ticketPrice
                report.profitBefore = ownRoute.economicsLastMonth.directOperatingProfit
            }
            guard let own = mine.first(where: { "\($0.origin.raw)-\($0.destination.raw)" == report.market }) else {
                if report.eraDay == nil, state.progression.era != .startup { report.eraDay = day }
                continue
            }
            if let entry = report.entryDay, day == entry + 1 {
                let summary = state.competitionSummary(catalog: catalog)
                report.headlineNextMorning = summary?.headline.map { "\($0)" } ?? "nil"
                if case .rivalEnteredYourMarket(let move)? = summary?.headline {
                    report.headlinePair = "\(move.origin.raw)-\(move.destination.raw)"
                }
                report.feedEventNextMorning = state.eventLog.recent.contains { event in
                    if case .marketEntered(_, let a, let b) = event.kind, Route.market(a, b) == own.market {
                        return state.isFeedEvent(event, for: player)
                    }
                    return false
                }
            }
            if let entry = report.entryDay, day == entry + 30,
               let model = state.marketCompetition(for: own.id, catalog: catalog) {
                report.shareAfterMonth = model.playerShareToday
                report.standingAfterMonth = model.standing
                report.edgeAfterMonth = model.edge
                report.spareRotationsAfterMonth = model.spareRotationsToday
                report.profitAfter = own.economicsLastMonth.directOperatingProfit
                if respond != .none {
                    report.responseDay = day
                    switch respond {
                    case .frequency:
                        _ = await session.submit(SetRouteFrequencyCommand(
                            airline: player, route: own.id, dailyRoundTrips: own.dailyRoundTrips + 1))
                    case .fare:
                        _ = await session.submit(SetRoutePriceCommand(
                            airline: player, route: own.id,
                            ticketPrice: Money(rounding: own.ticketPrice.asDouble * 0.9)))
                    case .none: break
                    }
                }
            }
            if let entry = report.entryDay, day == entry + 90 {
                report.shareAtDay90 = state.marketCompetition(for: own.id, catalog: catalog)?.playerShareToday
            }
            if let entry = report.entryDay, day > entry + 60, (day - entry) % 30 == 0 {
                report.laterProfits.append(own.economicsLastMonth.directOperatingProfit)
            }
            if report.eraDay == nil, state.progression.era != .startup { report.eraDay = day }
        }
        return report
    }

    @Test(arguments: [Response.none, .frequency, .fare])
    func aRivalComesToMunichIstanbul(_ response: Response) async throws {
        let report = try await run(days: 300, respond: response)
        let later = report.laterProfits.map(\.compact).joined(separator: " ")
        print("MUNICH-HORIZON seed \(Self.seed) response \(response.rawValue): first \(report.firstRoute) february \(report.februaryMarkets) · entry day \(report.entryDay.map(String.init) ?? "-") \(report.entrant) [\(report.archetype)] on \(report.market) @\(report.entrantFare.compact) vs your \(report.playerFare.compact) · headline \(report.headlineNextMorning.prefix(24)) pair \(report.headlinePair) feed \(report.feedEventNextMorning) · month later share \(report.shareAfterMonth.map { String(format: "%.2f", $0) } ?? "-") standing \(String(describing: report.standingAfterMonth)) edge \(String(describing: report.edgeAfterMonth)) spare \(report.spareRotationsAfterMonth) profit \(report.profitBefore.compact)→\(report.profitAfter.compact) · day 90 share \(report.shareAtDay90.map { String(format: "%.2f", $0) } ?? "-") later months \(later) · era day \(report.eraDay.map(String.init) ?? "-")")

        // The world comes to Munich in the first season, on a pair the
        // player opened from the Next Moves card.
        let entry = try #require(report.entryDay)
        #expect(entry > 31 && entry <= 120)
        #expect(report.entrant == "PacificBlue" && report.archetype == "lowCost")
        #expect(report.market == "MUC-IST")
        #expect(report.februaryMarkets.contains("MUC-IST"))
        #expect(report.entrantFare < report.playerFare, "the low-cost carrier arrives under the player's fare")
        // Home says so the next morning, the player's way round, and the
        // feed carries it.
        #expect(report.headlineNextMorning.hasPrefix("rivalEnteredYourMarket"))
        #expect(report.headlinePair == "MUC-IST")
        #expect(report.feedEventNextMorning)
        // A month on the split is real and the model says why.
        let share = try #require(report.shareAfterMonth)
        #expect(share > 0.25 && share < 0.55)
        #expect(report.standingAfterMonth != .alone && report.standingAfterMonth != .tooEarly)
        #expect(report.edgeAfterMonth != nil)
        // The first era still arrives on the campaign's timetable.
        #expect(report.eraDay != nil)
    }

    private func assignIdle(_ session: GameSession, player: AirlineID, catalog: ContentCatalog) async throws {
        var state = await session.snapshot
        let bare = state.routes(of: player).filter { route in
            !state.fleet(of: player).contains { $0.assignedRoute == route.id }
        }
        var idle = state.fleet(of: player).filter { $0.assignedRoute == nil }
        for route in bare {
            guard let index = idle.firstIndex(where: {
                (catalog.aircraftType($0.typeCode)?.rangeKm ?? 0) >= route.distanceKm
            }) else { continue }
            let aircraft = idle.remove(at: index)
            _ = await session.submit(AssignAircraftToRouteCommand(airline: player, route: route.id, aircraftID: aircraft.id))
            state = await session.snapshot
        }
    }
}
