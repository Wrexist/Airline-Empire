import Testing
@testable import AirlineEmpireCore

/// The competitive arc of the seed-2039 campaign, driven through the real
/// command surface — the Linux twin of the AE-037 UI journey and the proof
/// that every COMP state it photographs exists in the simulation first
/// (docs/RIVAL_PRESSURE_AUDIT.md §6).
///
/// The script is `FirstEraCampaignTests`' player with one more decision: on
/// the first of February, having reached London on the guided first route,
/// it opens London–Paris under the two rivals already flying it, priced to
/// provoke them. What the world does next is the measurement.
@Suite("Rival pressure campaign")
struct RivalPressureCampaignTests {

    struct Report {
        var firstRivalAtMyAirportDay: Int?
        var invasionDay: Int?
        var rivalsOnInvasionDay = 0
        var firstRivalResponseDay: Int?
        var firstRivalResponse = ""
        var shareAfterAWeek: Double?
        var standingAfterAWeek: MarketCompetition.Standing?
        var edgeAfterAWeek: MarketCompetition.Edge?
        var marchRouteProfit = Money.zero
        var rivalMaxTrips = 0
        var retreatDay: Int?
        var retreatHeadline = false
        var eraDay: Int?
        var contestedAtDay60 = 0
        var biggestRivalAtDay60 = ""
    }

    static let seed = FirstEraCampaignTests.campaignSeed
    /// London–Berlin: the pair Aurora Atlantic, the premium rival based at
    /// London, opens on day 18 of this seed. Until AE-039 the fight was
    /// London–Paris under two incumbents; with markets ranked by what an
    /// airframe day sells, no rival flies that fee-dominated 350 km pair,
    /// and the fight is one incumbent that holds its fare floor
    /// (docs/HORIZON_AUDIT.md §5).
    static let fight: (origin: AirportCode, destination: AirportCode) = ("LHR", "BER")

    func runCampaign(days: Int) async throws -> Report {
        let catalog = try ContentCatalog.loadBundled()
        let spec = try #require(catalog.scenario("entrepreneur"))
        let session = GameSession(
            state: ScenarioBootstrap.newGame(scenario: "entrepreneur",
                                             worldSeed: Self.seed,
                                             startYear: spec.startYear),
            systems: GamePipeline.standard(), catalog: catalog)
        #expect(await session.beginScenario(spec, airlineName: "Campaign Air",
                                            home: "ARN") == .applied)
        var state = await session.snapshot
        let player = try #require(state.playerAirline).id

        #expect(await session.submit(LeaseAircraftCommand(
            lessee: player, type: "PA184", termMonths: 60)) == .applied)
        state = await session.snapshot
        let first = try #require(state.onboardingModel(catalog: catalog)?.suggestions.first)
        #expect(await session.submit(OpenRouteCommand(
            airline: player, origin: first.origin, destination: first.destination,
            dailyRoundTrips: 2, ticketPrice: first.referenceFare)) == .applied)
        try await assignIdleAircraft(session, player: player, catalog: catalog)

        var report = Report()
        var reacted = false
        var expanded = false
        var fightRoute: RouteID?
        var rivalOffersAtEntry: [AirlineID: (fare: Money, trips: Int)] = [:]
        let ticksPerDay = Int(GameCalendar.minutesPerDay
            / ScenarioBootstrap.standardTickMinutes)

        for day in 1...days {
            await session.advance(ticks: ticksPerDay)
            state = await session.snapshot

            // The same mission reaction as the first-era twin.
            if let mission = state.progression.missions.first,
               case .boomRush(let region, _) = mission.kind, !reacted {
                reacted = true
                let home = try #require(catalog.airport("ARN"))
                let target = catalog.orderedAirportCodes
                    .compactMap { catalog.airport($0) }
                    .filter { $0.region == region }
                    .filter { Geo.distanceKm(from: home.coordinate, to: $0.coordinate) <= 5_500 }
                    .min { Geo.distanceKm(from: home.coordinate, to: $0.coordinate)
                            < Geo.distanceKm(from: home.coordinate, to: $1.coordinate) }
                if let target {
                    _ = await session.submit(LeaseAircraftCommand(
                        lessee: player, type: "PA184", termMonths: 60))
                    _ = await session.submit(OpenRouteCommand(
                        airline: player, origin: "ARN", destination: target.code,
                        dailyRoundTrips: 2, ticketPrice: Money(cents: 30000)))
                    try await assignIdleAircraft(session, player: player, catalog: catalog)
                }
            }

            // February: the first-era expansion, plus the fight.
            if !expanded, state.currentDate.month == 2 {
                expanded = true
                _ = await session.submit(BuyUsedAircraftCommand(
                    buyer: player, type: "MR180", ageYears: 8))
                _ = await session.submit(LeaseAircraftCommand(
                    lessee: player, type: "PA184", termMonths: 60))
                state = await session.snapshot
                for market in state.marketOpportunities(catalog: catalog, limit: 4)
                    .filter(\.servableNow).prefix(2) {
                    _ = await session.submit(OpenRouteCommand(
                        airline: player, origin: market.origin,
                        destination: market.destination, dailyRoundTrips: 2,
                        ticketPrice: market.referenceFare))
                }
                let distance = try #require(catalog.distanceKm(Self.fight.origin,
                                                               Self.fight.destination))
                let reference = DemandSystem.referenceFare(distanceKm: distance,
                                                           tuning: catalog.tuning.demand)
                _ = await session.submit(LeaseAircraftCommand(
                    lessee: player, type: "PA184", termMonths: 60))
                #expect(await session.submit(OpenRouteCommand(
                    airline: player, origin: Self.fight.origin,
                    destination: Self.fight.destination, dailyRoundTrips: 2,
                    ticketPrice: Money(rounding: reference * 0.88))) == .applied)
                try await assignIdleAircraft(session, player: player, catalog: catalog)
                state = await session.snapshot
                fightRoute = state.routes(of: player).first {
                    $0.sameMarket(origin: Self.fight.origin, destination: Self.fight.destination)
                }?.id
                report.invasionDay = day
                if let fightRoute,
                   let model = state.marketCompetition(for: fightRoute, catalog: catalog) {
                    report.rivalsOnInvasionDay = model.rivals.count
                    for rival in model.rivals {
                        rivalOffersAtEntry[rival.airline] = (rival.fare, rival.dailyRoundTrips)
                    }
                }
            }

            let summary = state.competitionSummary(catalog: catalog)
            if report.firstRivalAtMyAirportDay == nil,
               summary?.recentMoves.contains(where: {
                   $0.kind == .entered && $0.relevance == .atPlayerAirport
               }) == true {
                report.firstRivalAtMyAirportDay = day
            }

            if let fightRoute, let invasion = report.invasionDay,
               let model = state.marketCompetition(for: fightRoute, catalog: catalog) {
                // The first rival to change its offer after the entry.
                if report.firstRivalResponseDay == nil {
                    for rival in model.rivals {
                        guard let before = rivalOffersAtEntry[rival.airline] else { continue }
                        if rival.fare != before.fare || rival.dailyRoundTrips != before.trips {
                            report.firstRivalResponseDay = day
                            report.firstRivalResponse = "\(rival.name) \(before.fare.compact)/\(before.trips)x → \(rival.fare.compact)/\(rival.dailyRoundTrips)x"
                            break
                        }
                    }
                }
                if day == invasion + 7 {
                    report.shareAfterAWeek = model.playerShareToday
                    report.standingAfterAWeek = model.standing
                    report.edgeAfterAWeek = model.edge
                }
                report.rivalMaxTrips = max(report.rivalMaxTrips,
                                           model.rivals.map(\.dailyRoundTrips).max() ?? 0)
                if report.retreatDay == nil,
                   model.rivals.count < report.rivalsOnInvasionDay, day > invasion {
                    report.retreatDay = day
                    if case .rivalLeftYourMarket = summary?.headline {
                        report.retreatHeadline = true
                    }
                }
                if state.currentDate.month == 4, state.currentDate.day == 1,
                   let route = state.routes[fightRoute] {
                    report.marchRouteProfit = route.economicsLastMonth.directOperatingProfit
                }
            }

            if day == 60, let summary {
                report.contestedAtDay60 = summary.contestedRoutes
                report.biggestRivalAtDay60 = summary.biggestRival?.name ?? ""
            }
            if report.eraDay == nil, state.progression.era != .startup {
                report.eraDay = day
            }
        }
        return report
    }

    private func assignIdleAircraft(_ session: GameSession, player: AirlineID,
                                    catalog: ContentCatalog) async throws {
        var state = await session.snapshot
        let bare = state.routes(of: player).filter { route in
            !state.fleet(of: player).contains { $0.assignedRoute == route.id }
        }
        var idle = state.fleet(of: player).filter { $0.assignedRoute == nil }
        for route in bare {
            guard let index = idle.firstIndex(where: { aircraft in
                (catalog.aircraftType(aircraft.typeCode)?.rangeKm ?? 0) >= route.distanceKm
            }) else { continue }
            let aircraft = idle.remove(at: index)
            #expect(await session.submit(AssignAircraftToRouteCommand(
                airline: player, route: route.id,
                aircraftID: aircraft.id)) == .applied)
            state = await session.snapshot
        }
    }

    /// COMP-01 … COMP-05, in the order the UI journey meets them.
    @Test func theWorldPushesBackDeterministically() async throws {
        let report = try await runCampaign(days: 260)
        print("RIVAL-PRESSURE seed \(Self.seed): rivalAtMyAirport day \(report.firstRivalAtMyAirportDay.map(String.init) ?? "-") " +
              "invasion day \(report.invasionDay.map(String.init) ?? "-") rivals \(report.rivalsOnInvasionDay) " +
              "response day \(report.firstRivalResponseDay.map(String.init) ?? "-") (\(report.firstRivalResponse)) " +
              "week-later share \(report.shareAfterAWeek.map { String(format: "%.2f", $0) } ?? "-") standing \(String(describing: report.standingAfterAWeek)) edge \(String(describing: report.edgeAfterAWeek)) " +
              "march route profit \(report.marchRouteProfit.compact) rival max trips \(report.rivalMaxTrips) " +
              "retreat day \(report.retreatDay.map(String.init) ?? "-") headline \(report.retreatHeadline) " +
              "era day \(report.eraDay.map(String.init) ?? "-") contested@60 \(report.contestedAtDay60) biggest@60 \(report.biggestRivalAtDay60)")

        // COMP-02: a rival builds at an airport the player serves within the
        // first month (London is the guided first route's far end, and a
        // rival is based there).
        let atMyAirport = try #require(report.firstRivalAtMyAirportDay)
        #expect(atMyAirport <= 31)

        // COMP-01: the fight opens under an incumbent, on the first of February.
        let invasion = try #require(report.invasionDay)
        #expect(invasion <= 32)
        #expect(report.rivalsOnInvasionDay >= 1)

        // COMP-04: a rival changes its offer within its next decision cycle.
        let response = try #require(report.firstRivalResponseDay)
        #expect(response - invasion <= 7, "\(report.firstRivalResponse)")

        // COMP-03: the player holds a real share, the model can say where
        // they stand and why, and the rivals answer with capacity — the
        // measured arc is both incumbents climbing to the frequency cap.
        let share = try #require(report.shareAfterAWeek)
        #expect(share > 0.15 && share < 0.6)
        #expect(report.standingAfterAWeek != .alone && report.standingAfterAWeek != .tooEarly)
        #expect(report.edgeAfterAWeek != nil)
        #expect(report.rivalMaxTrips >= 10)

        // COMP-05: a retreat from the pair is not part of this seed's arc
        // any more (the London–Paris incumbent that left on day 248 never
        // opens under the AE-039 ranking); the retreat state stays pinned
        // by `RivalPressureFixtureTests` from its save.
        if let retreat = report.retreatDay {
            #expect(retreat <= 260)
            #expect(report.retreatHeadline)
        }

        // COMP-06: the summary carries live numbers by the end of month two.
        #expect(report.contestedAtDay60 >= 1)
        #expect(!report.biggestRivalAtDay60.isEmpty)

        // The first era still arrives: the fight does not break the campaign.
        let era = try #require(report.eraDay)
        #expect(era <= 62)
    }
}
