import Testing
@testable import AirlineEmpireCore

/// HORIZON-06: the curated first start, Stockholm, now meets a rival that
/// comes on its own — the Linux twin of the campaign journey's world,
/// played past the first era (docs/HORIZON_AUDIT.md §5).
///
/// The script is `RivalPressureCampaignTests`' player: the guided first
/// route, the Cairo reaction, February's expansion (two suggested markets
/// — Paris and Istanbul — and the London–Paris fight). Then nothing but
/// sunrises. What the world does to Stockholm–Istanbul is the measurement.
@Suite("Stockholm horizon")
struct StockholmHorizonTests {

    struct Report {
        var entryDay: Int?
        var entrant = ""
        var archetype = ""
        var market = ""
        var entrantFare = Money.zero
        var playerFare = Money.zero
        var headlineNextMorning = ""
        var shareAfterMonth: Double?
        var standingAfterMonth: MarketCompetition.Standing?
        var edgeAfterMonth: MarketCompetition.Edge?
        var profitBefore = Money.zero
        var profitAfter = Money.zero
        var eraDay: Int?
    }

    @Test func aRivalComesToStockholmIstanbul() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let spec = try #require(catalog.scenario("entrepreneur"))
        let session = GameSession(
            state: ScenarioBootstrap.newGame(scenario: "entrepreneur",
                                             worldSeed: FirstEraCampaignTests.campaignSeed,
                                             startYear: spec.startYear),
            systems: GamePipeline.standard(), catalog: catalog)
        #expect(await session.beginScenario(spec, airlineName: "Campaign Air", home: "ARN") == .applied)
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
        var reacted = false, expanded = false
        var knownRivalRoutes: Set<RouteID> = []
        let ticksPerDay = Int(GameCalendar.minutesPerDay / ScenarioBootstrap.standardTickMinutes)
        let fight: (AirportCode, AirportCode) = ("LHR", "CDG")

        for day in 1...260 {
            await session.advance(ticks: ticksPerDay)
            state = await session.snapshot

            if let mission = state.progression.missions.first,
               case .boomRush(let region, _) = mission.kind, !reacted {
                reacted = true
                let home = try #require(catalog.airport("ARN"))
                if let target = catalog.orderedAirportCodes.compactMap({ catalog.airport($0) })
                    .filter({ $0.region == region })
                    .filter({ Geo.distanceKm(from: home.coordinate, to: $0.coordinate) <= 5_500 })
                    .min(by: { Geo.distanceKm(from: home.coordinate, to: $0.coordinate)
                            < Geo.distanceKm(from: home.coordinate, to: $1.coordinate) }) {
                    _ = await session.submit(LeaseAircraftCommand(lessee: player, type: "PA184", termMonths: 60))
                    _ = await session.submit(OpenRouteCommand(
                        airline: player, origin: "ARN", destination: target.code,
                        dailyRoundTrips: 2, ticketPrice: Money(cents: 30000)))
                    try await assignIdle(session, player: player, catalog: catalog)
                }
            }
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
                }
                let distance = try #require(catalog.distanceKm(fight.0, fight.1))
                let reference = DemandSystem.referenceFare(distanceKm: distance, tuning: catalog.tuning.demand)
                _ = await session.submit(LeaseAircraftCommand(lessee: player, type: "PA184", termMonths: 60))
                _ = await session.submit(OpenRouteCommand(
                    airline: player, origin: fight.0, destination: fight.1, dailyRoundTrips: 2,
                    ticketPrice: Money(rounding: reference)))
                try await assignIdle(session, player: player, catalog: catalog)
                state = await session.snapshot
                // The pairs a rival already flies at the moment the player opens
                // them are the player's own doing; only pairs the player held
                // alone count below.
                knownRivalRoutes = Set(state.routes.values.filter { $0.airline != player }.map(\.id))
            }

            // A rival route appearing on a pair the player already flies
            // from Stockholm: the world came to the player.
            let mine = state.routes(of: player)
            let stockholmPairs = Set(mine.filter { $0.origin == "ARN" || $0.destination == "ARN" }.map(\.market))
            for route in state.routes.values where route.airline != player && !knownRivalRoutes.contains(route.id) {
                knownRivalRoutes.insert(route.id)
                guard report.entryDay == nil, stockholmPairs.contains(route.market),
                      let ownRoute = mine.first(where: { $0.market == route.market }) else { continue }
                report.entryDay = day
                report.entrant = state.airlines[route.airline]?.name ?? "?"
                report.archetype = state.airlines[route.airline]?.aiProfile.map { "\($0.archetype)" } ?? "?"
                report.market = "\(ownRoute.origin.raw)-\(ownRoute.destination.raw)"
                report.entrantFare = route.ticketPrice
                report.playerFare = ownRoute.ticketPrice
                report.profitBefore = ownRoute.economicsLastMonth.directOperatingProfit
            }
            if let entry = report.entryDay, day == entry + 1 {
                report.headlineNextMorning = state.competitionSummary(catalog: catalog)?.headline.map { "\($0)" } ?? "nil"
            }
            if let entry = report.entryDay, day == entry + 30,
               let own = mine.first(where: { "\($0.origin.raw)-\($0.destination.raw)" == report.market }),
               let model = state.marketCompetition(for: own.id, catalog: catalog) {
                report.shareAfterMonth = model.playerShareToday
                report.standingAfterMonth = model.standing
                report.edgeAfterMonth = model.edge
                report.profitAfter = own.economicsLastMonth.directOperatingProfit
            }
            if report.eraDay == nil, state.progression.era != .startup { report.eraDay = day }
        }
        print("STOCKHOLM-HORIZON seed \(FirstEraCampaignTests.campaignSeed): entry day \(report.entryDay.map(String.init) ?? "-") \(report.entrant) [\(report.archetype)] on \(report.market) @\(report.entrantFare.compact) vs your \(report.playerFare.compact) · headline \(report.headlineNextMorning.prefix(40)) · month later share \(report.shareAfterMonth.map { String(format: "%.2f", $0) } ?? "-") standing \(String(describing: report.standingAfterMonth)) edge \(String(describing: report.edgeAfterMonth)) profit \(report.profitBefore.compact)→\(report.profitAfter.compact) · era day \(report.eraDay.map(String.init) ?? "-")")

        let entry = try #require(report.entryDay)
        #expect(entry > 60 && entry <= 230, "the world comes to Stockholm in the first year, not the first weeks")
        #expect(report.entrant == "PacificBlue" && report.archetype == "lowCost")
        #expect(report.market == "ARN-IST")
        #expect(report.entrantFare < report.playerFare, "the low-cost carrier arrives under the player's fare")
        #expect(report.headlineNextMorning.hasPrefix("rivalEnteredYourMarket"))
        let share = try #require(report.shareAfterMonth)
        #expect(share > 0.25 && share < 0.55)
        #expect(report.standingAfterMonth != .alone && report.standingAfterMonth != .tooEarly)
        #expect(report.edgeAfterMonth != nil)
        // The campaign's first era still arrives on its day.
        #expect(report.eraDay == 59)
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
