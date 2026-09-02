import Testing
@testable import AirlineEmpireCore

/// A rival that comes to the player: the world-initiated contest AE-037
/// never observed (TD-026), found by the AE-038 seed scan and pinned here
/// (docs/RIVALS_THAT_COME_TO_YOU_AUDIT.md).
///
/// From New York on seed 2030 the guided first route is JFK–ORD. SwiftJet,
/// the regional rival based at Chicago, opens the same pair on its own
/// decision — the player did nothing but fly a full aircraft on it — and
/// then pushes frequency week after week. The player's share, the route's
/// money and the one headline on Home all follow from the real engine.
@Suite("Rivals come to you")
struct RivalsComeToYouTests {

    static let seed: UInt64 = 2030
    static let home: AirportCode = "JFK"

    struct Report {
        var firstRoute = ""
        var entryDay: Int?
        var entrant = ""
        var entrantArchetype = ""
        var playerWasFirst = false
        var entrantFare = Money.zero
        var entrantTrips = 0
        var headlineNextMorning = ""
        var feedEventNextMorning = false
        var shareOnEntry: Double?
        var shareAfterMonth: Double?
        var standingAfterMonth: MarketCompetition.Standing?
        var edgeAfterMonth: MarketCompetition.Edge?
        var profitMonthBefore = Money.zero
        var profitMonthAfter = Money.zero
        var rivalTripsAfterMonth = 0
        var responseDay: Int?
        var shareBeforeResponse: Double?
        var shareAfterResponse: Double?
        var tripsAfterResponse = 0
        var retreatDay: Int?
        var monthly: [String] = []
        var spareRotationsAfterMonth = 0
        /// Route profit, last full month, sampled every 30 days from day 120.
        var laterProfits: [Money] = []
        var shareAtDay90: Double?
    }

    enum Response: String { case none, frequency, fare, both }

    func run(days: Int, respond: Response) async throws -> Report {
        let catalog = try ContentCatalog.loadBundled()
        let spec = try #require(catalog.scenario("entrepreneur"))
        let session = GameSession(
            state: ScenarioBootstrap.newGame(scenario: "entrepreneur",
                                             worldSeed: Self.seed, startYear: spec.startYear),
            systems: GamePipeline.standard(), catalog: catalog)
        #expect(await session.beginScenario(spec, airlineName: "Empire State Air",
                                            home: Self.home) == .applied)
        var state = await session.snapshot
        let player = try #require(state.playerAirline).id
        #expect(await session.submit(LeaseAircraftCommand(
            lessee: player, type: "PA184", termMonths: 60)) == .applied)
        state = await session.snapshot
        let first = try #require(state.onboardingModel(catalog: catalog)?.suggestions.first)
        #expect(await session.submit(OpenRouteCommand(
            airline: player, origin: first.origin, destination: first.destination,
            dailyRoundTrips: 2, ticketPrice: first.referenceFare)) == .applied)
        state = await session.snapshot
        let route = try #require(state.routes(of: player).first)
        let aircraft = try #require(state.fleet(of: player).first)
        #expect(await session.submit(AssignAircraftToRouteCommand(
            airline: player, route: route.id, aircraftID: aircraft.id)) == .applied)

        var report = Report()
        report.firstRoute = "\(route.origin.raw)-\(route.destination.raw)"
        let market = route.market
        let ticksPerDay = Int(GameCalendar.minutesPerDay / ScenarioBootstrap.standardTickMinutes)
        var rivalRoutesOnMarket: Set<RouteID> = []

        for day in 1...days {
            await session.advance(ticks: ticksPerDay)
            state = await session.snapshot
            let rivalsHere = state.routes.values.filter { $0.market == market && $0.airline != player }
            let ids = Set(rivalsHere.map(\.id))
            if report.entryDay == nil, let entrant = rivalsHere.first(where: { !rivalRoutesOnMarket.contains($0.id) }) {
                report.entryDay = day
                report.entrant = state.airlines[entrant.airline]?.name ?? "?"
                report.entrantArchetype = state.airlines[entrant.airline]?.aiProfile.map { "\($0.archetype)" } ?? "?"
                report.playerWasFirst = true   // the player's route existed from day 0
                report.entrantFare = entrant.ticketPrice
                report.entrantTrips = entrant.dailyRoundTrips
                report.shareOnEntry = state.marketCompetition(for: route.id, catalog: catalog)?.playerShareToday
                report.profitMonthBefore = route.economicsLastMonth.directOperatingProfit
            }
            if let entry = report.entryDay, day == entry + 1 {
                let summary = state.competitionSummary(catalog: catalog)
                report.headlineNextMorning = summary?.headline.map { "\($0)" } ?? "nil"
                report.feedEventNextMorning = state.eventLog.recent.contains { event in
                    if case .marketEntered(_, let a, let b) = event.kind,
                       Route.market(a, b) == market { return state.isFeedEvent(event, for: player) }
                    return false
                }
            }
            if let entry = report.entryDay, day == entry + 30,
               let model = state.marketCompetition(for: route.id, catalog: catalog),
               let mine = state.routes[route.id] {
                report.shareAfterMonth = model.playerShareToday
                report.standingAfterMonth = model.standing
                report.edgeAfterMonth = model.edge
                report.profitMonthAfter = mine.economicsLastMonth.directOperatingProfit
                report.rivalTripsAfterMonth = model.rivals.map(\.dailyRoundTrips).max() ?? 0
                report.spareRotationsAfterMonth = model.spareRotationsToday
                if respond != .none {
                    report.responseDay = day
                    report.shareBeforeResponse = model.playerShareToday
                    if respond == .frequency || respond == .both {
                        _ = await session.submit(SetRouteFrequencyCommand(
                            airline: player, route: route.id, dailyRoundTrips: mine.dailyRoundTrips + 1))
                    }
                    if respond == .fare || respond == .both {
                        _ = await session.submit(SetRoutePriceCommand(
                            airline: player, route: route.id,
                            ticketPrice: Money(rounding: mine.ticketPrice.asDouble * 0.9)))
                    }
                    state = await session.snapshot
                    report.tripsAfterResponse = state.routes[route.id]?.dailyRoundTrips ?? 0
                }
            }
            if let response = report.responseDay, day == response + 14 {
                report.shareAfterResponse = state.marketCompetition(for: route.id, catalog: catalog)?.playerShareToday
            }
            if day == 90 {
                report.shareAtDay90 = state.marketCompetition(for: route.id, catalog: catalog)?.playerShareToday
            }
            if day % 30 == 0, day >= 120, let mine = state.routes[route.id] {
                report.laterProfits.append(mine.economicsLastMonth.directOperatingProfit)
            }
            if day % 30 == 0, let mine = state.routes[route.id],
               let model = state.marketCompetition(for: route.id, catalog: catalog) {
                report.monthly.append("d\(day) share \(model.playerShareToday.map { String(format: "%.2f", $0) } ?? "-") you \(mine.ticketPrice.compact)/\(mine.dailyRoundTrips)x load \(String(format: "%.0f%%", mine.stats.loadFactor * 100)) last-month \(mine.economicsLastMonth.directOperatingProfit.compact) rivals \(model.rivals.map { "\($0.name) \($0.fare.compact)/\($0.dailyRoundTrips)x" }.joined(separator: ",")) cash \(state.ledger.balance(of: player).compact)")
            }
            if report.entryDay != nil, report.retreatDay == nil,
               !rivalRoutesOnMarket.isEmpty, ids.isStrictSubset(of: rivalRoutesOnMarket) {
                report.retreatDay = day
            }
            rivalRoutesOnMarket = ids
        }
        return report
    }

    @Test(arguments: [Response.none, .frequency, .fare, .both])
    func aRivalEntersTheFirstRouteOnItsOwn(_ response: Response) async throws {
        let report = try await run(days: 365, respond: response)
        print("RIVALS-COME response \(response.rawValue): " + report.monthly.joined(separator: " | "))
        print("RIVALS-COME seed \(Self.seed) \(Self.home): first route \(report.firstRoute) entry day \(report.entryDay.map(String.init) ?? "-") by \(report.entrant) [\(report.entrantArchetype)] @\(report.entrantFare.compact) \(report.entrantTrips)x · share on entry \(report.shareOnEntry.map { String(format: "%.2f", $0) } ?? "-") · headline next morning \(report.headlineNextMorning) feed \(report.feedEventNextMorning) · month later share \(report.shareAfterMonth.map { String(format: "%.2f", $0) } ?? "-") standing \(String(describing: report.standingAfterMonth)) edge \(String(describing: report.edgeAfterMonth)) profit \(report.profitMonthBefore.compact)→\(report.profitMonthAfter.compact) rival trips \(report.rivalTripsAfterMonth) · response day \(report.responseDay.map(String.init) ?? "-") trips \(report.tripsAfterResponse) share \(report.shareBeforeResponse.map { String(format: "%.2f", $0) } ?? "-")→\(report.shareAfterResponse.map { String(format: "%.2f", $0) } ?? "-") · retreat day \(report.retreatDay.map(String.init) ?? "-")")

        // RIVAL-01/02: the player's first route, and a rival that comes to it
        // — on its first decision, now that a contested pair is scored by
        // the demand engine's split (day 17 under the old halving).
        let entry = try #require(report.entryDay)
        #expect(report.playerWasFirst)
        #expect(entry <= 10)
        #expect(report.entrant == "SwiftJet")
        #expect(report.entrantArchetype == "regional")

        // RIVAL-03: the morning after, Home's one headline is this, and the
        // feed carries the entry.
        #expect(report.headlineNextMorning.hasPrefix("rivalEnteredYourMarket"))
        #expect(report.feedEventNextMorning)

        // RIVAL-04/05: a month on, the split is real and the model says why.
        let share = try #require(report.shareAfterMonth)
        #expect(share > 0.4 && share < 0.6)
        #expect(report.standingAfterMonth == .even)
        #expect(report.edgeAfterMonth == .schedule(playerAhead: false))
        #expect(report.rivalTripsAfterMonth >= 3)
        // BUG-046: the one narrowbody on the pair has a rotation to spare.
        #expect(report.spareRotationsAfterMonth >= 1)

        // RIVAL-06: the responses, measured over the year (audit §4).
        let day90 = try #require(report.shareAtDay90)
        #expect(report.laterProfits.count >= 8)
        let averageLater = report.laterProfits.reduce(0.0) { $0 + $1.asDouble }
            / Double(max(1, report.laterProfits.count))
        switch response {
        case .none:
            #expect(day90 < 0.45, "doing nothing: share slides to \(day90)")
            #expect(averageLater < 1_450_000)
        case .frequency:
            #expect(day90 > 0.44)
            #expect(averageLater > 1_600_000, "one more rotation: \(averageLater)")
            #expect(report.tripsAfterResponse == 3)
        case .fare:
            #expect(averageLater < 1_200_000, "a fare cut alone earns less than nothing: \(averageLater)")
        case .both:
            #expect(day90 > 0.48)
        }

        // RIVAL-07: no retreat within the year on this pair — documented,
        // not asserted away.
        #expect(report.retreatDay == nil)
    }
}

/// The arithmetic the competitor AI now scores contested pairs with.
@Suite("Entrant pool")
struct EntrantPoolTests {

    @Test func anEmptyPairIsWorthItsWholePool() throws {
        let catalog = try ContentCatalog.loadBundled()
        let state = Fixtures.newState(seed: 1)
        let pool = SegmentDemand(business: 300, leisure: 700)
        let quality = DemandSystem.representativeStarterQuality(tuning: catalog.tuning.demand)
        let value = DemandSystem.poolAvailableToEntrant(
            pool: pool, fareRatio: 1.0, quality: quality, incumbents: [],
            state: state, catalog: catalog)
        #expect(abs(value - pool.total) < 0.001)
    }

    @Test func oneIncumbentLeavesMoreThanHalfAndLessThanAll() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let spec = try #require(catalog.scenario("entrepreneur"))
        let session = GameSession(
            state: ScenarioBootstrap.newGame(scenario: "entrepreneur", worldSeed: 7,
                                             startYear: spec.startYear),
            systems: GamePipeline.standard(), catalog: catalog)
        #expect(await session.beginScenario(spec, airlineName: "Incumbent Air", home: "ARN") == .applied)
        var state = await session.snapshot
        let player = try #require(state.playerAirline).id
        #expect(await session.submit(LeaseAircraftCommand(lessee: player, type: "PA184", termMonths: 60)) == .applied)
        state = await session.snapshot
        let distance = try #require(catalog.distanceKm("ARN", "LHR"))
        let reference = DemandSystem.referenceFare(distanceKm: distance, tuning: catalog.tuning.demand)
        #expect(await session.submit(OpenRouteCommand(
            airline: player, origin: "ARN", destination: "LHR", dailyRoundTrips: 2,
            ticketPrice: Money(rounding: reference))) == .applied)
        state = await session.snapshot
        let route = try #require(state.routes(of: player).first)
        let aircraft = try #require(state.fleet(of: player).first)
        #expect(await session.submit(AssignAircraftToRouteCommand(
            airline: player, route: route.id, aircraftID: aircraft.id)) == .applied)
        state = await session.snapshot
        let incumbent = try #require(state.routes[route.id])

        let pool = DemandSystem.demandPool(from: "ARN", to: "LHR", date: state.currentDate,
                                           economicIndex: state.world.economicIndex, catalog: catalog)
        let quality = DemandSystem.representativeStarterQuality(tuning: catalog.tuning.demand)
        let contested = DemandSystem.poolAvailableToEntrant(
            pool: pool, fareRatio: 1.0, quality: quality, incumbents: [incumbent],
            state: state, catalog: catalog)
        print("ENTRANT-POOL ARN-LHR pool \(Int(pool.total)) one incumbent at reference: \(Int(contested)) (\(String(format: "%.2f", contested / pool.total)) of it)")
        #expect(contested < pool.total)
        #expect(contested > pool.total / 2, "the old halving undervalued a contested pair")

        // A cheaper entrant expects more; a dearer one less.
        let cheap = DemandSystem.poolAvailableToEntrant(
            pool: pool, fareRatio: 0.85, quality: quality, incumbents: [incumbent],
            state: state, catalog: catalog)
        let dear = DemandSystem.poolAvailableToEntrant(
            pool: pool, fareRatio: 1.25, quality: quality, incumbents: [incumbent],
            state: state, catalog: catalog)
        #expect(cheap > contested && dear < contested)

        // An incumbent that cannot carry anyone attracts nothing.
        var grounded = incumbent
        grounded.assignedAircraft = []
        let unopposed = DemandSystem.poolAvailableToEntrant(
            pool: pool, fareRatio: 1.0, quality: quality, incumbents: [grounded],
            state: state, catalog: catalog)
        #expect(abs(unopposed - pool.total) < 0.001)
    }
}
