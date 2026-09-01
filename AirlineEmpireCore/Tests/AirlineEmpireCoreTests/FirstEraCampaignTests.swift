import Testing
@testable import AirlineEmpireCore

/// The campaign from founding to the first era gate, driven through the real
/// command surface — the Linux twin of the AE-035 UI journey, and the proof
/// that the scripted path is *deterministic* before a simulator ever runs it
/// (docs/FIRST_ERA_RUNTIME_AUDIT.md §2).
///
/// The Regional gate asks for three routes whose last closed month made a
/// direct operating profit, plus one airframe owned outright (EraGate). The
/// script is a plausible player: month one on the guided first route, then
/// the February expansion — buy a used narrowbody with the war chest, lease
/// a second, open the two markets the Next Moves ranking suggests — and let
/// February close. The era must arrive with March.
@Suite("First era campaign")
struct FirstEraCampaignTests {

    struct Report {
        var eraDay: Int?
        var statements: [Money] = []
        var boomDays: [Int] = []
        var missionsOffered = 0
        var missionCompletedDay: Int?
        var finalCash = Money.zero
        var routesProfitableLastMonth = 0
    }

    /// The seed the UI journey founds with. Chosen by a local 50-seed scan:
    /// a tourism boom starts on day 8 (Africa), so the campaign gets a real
    /// mission to react to, and the era still arrives with March.
    static let campaignSeed: UInt64 = 2039

    func runCampaign(seed: UInt64, days: Int = 70) async throws -> Report {
        let catalog = try ContentCatalog.loadBundled()
        let spec = try #require(catalog.scenario("entrepreneur"))
        let session = GameSession(
            state: ScenarioBootstrap.newGame(scenario: "entrepreneur",
                                             worldSeed: seed,
                                             startYear: spec.startYear),
            systems: GamePipeline.standard(), catalog: catalog)
        #expect(await session.beginScenario(spec, airlineName: "Campaign Air",
                                            home: "ARN") == .applied)
        var state = await session.snapshot
        let player = try #require(state.playerAirline).id

        // Month one: the guided path, exactly as the UI journey drives it.
        #expect(await session.submit(LeaseAircraftCommand(
            lessee: player, type: "PA184", termMonths: 60)) == .applied)
        state = await session.snapshot
        let onboarding = try #require(state.onboardingModel(catalog: catalog))
        let first = try #require(onboarding.suggestions.first)
        #expect(await session.submit(OpenRouteCommand(
            airline: player, origin: first.origin,
            destination: first.destination, dailyRoundTrips: 2,
            ticketPrice: first.referenceFare)) == .applied)
        state = await session.snapshot
        try await assignIdleAircraft(session, player: player, catalog: catalog)

        var report = Report()
        var expanded = false
        var reacted = false
        var seenBooms = Set<Int64>()
        let ticksPerDay = Int(GameCalendar.minutesPerDay
            / ScenarioBootstrap.standardTickMinutes)

        for day in 1...days {
            await session.advance(ticks: ticksPerDay)
            state = await session.snapshot

            for event in state.world.activeEvents where event.hasStarted {
                if case .tourismBoom = event.kind,
                   !seenBooms.contains(event.id) {
                    seenBooms.insert(event.id)
                    report.boomDays.append(day)
                }
            }
            report.missionsOffered = max(report.missionsOffered,
                                         state.progression.missions.count)

            // React to a mission the way its design intends: a boom in a
            // region the airline does not serve is an invitation to expand
            // into it. One route toward the boom, on a fresh lease.
            if let mission = state.progression.missions.first,
               case .boomRush(let region, _) = mission.kind,
               !reacted {
                reacted = true
                // The nearest airport in the boom's region that the era's
                // longest-legged narrowbody can actually reach — the first
                // scripted pick (alphabetical) chose Addis Ababa, 5,850 km
                // from ARN and beyond every startup airframe, and the route
                // sat unflown for two months.
                let home = try #require(catalog.airport("ARN"))
                let target = catalog.orderedAirportCodes
                    .compactMap { catalog.airport($0) }
                    .filter { $0.region == region }
                    .filter {
                        Geo.distanceKm(from: home.coordinate,
                                       to: $0.coordinate) <= 5_500
                    }
                    .min {
                        Geo.distanceKm(from: home.coordinate, to: $0.coordinate)
                            < Geo.distanceKm(from: home.coordinate, to: $1.coordinate)
                    }
                if let target {
                    #expect(await session.submit(LeaseAircraftCommand(
                        lessee: player, type: "PA184",
                        termMonths: 60)) == .applied)
                    #expect(await session.submit(OpenRouteCommand(
                        airline: player, origin: "ARN",
                        destination: target.code, dailyRoundTrips: 2,
                        ticketPrice: Money(cents: 30000))) == .applied)
                    state = await session.snapshot
                    try await assignIdleAircraft(session, player: player,
                                                 catalog: catalog)
                }
            }
            if report.missionCompletedDay == nil, reacted,
               state.progression.missions.isEmpty {
                report.missionCompletedDay = day
            }

            // The February expansion, the morning after the first close.
            if !expanded, state.currentDate.month == 2 {
                expanded = true
                #expect(await session.submit(BuyUsedAircraftCommand(
                    buyer: player, type: "MR180", ageYears: 8)) == .applied)
                #expect(await session.submit(LeaseAircraftCommand(
                    lessee: player, type: "PA184", termMonths: 60)) == .applied)
                state = await session.snapshot
                let markets = state.marketOpportunities(catalog: catalog, limit: 4)
                    .filter(\.servableNow).prefix(2)
                #expect(markets.count == 2)
                for market in markets {
                    #expect(await session.submit(OpenRouteCommand(
                        airline: player, origin: market.origin,
                        destination: market.destination, dailyRoundTrips: 2,
                        ticketPrice: market.referenceFare)) == .applied)
                }
                state = await session.snapshot
                try await assignIdleAircraft(session, player: player,
                                             catalog: catalog)
            }

            if report.eraDay == nil, state.progression.era != .startup {
                report.eraDay = day
            }
        }

        state = await session.snapshot
        report.statements = (state.finance.byAirline[player]?.statements ?? [])
            .map(\.netProfit)
        report.finalCash = state.ledger.balance(of: player)
        report.routesProfitableLastMonth = state.routes(of: player).filter {
            $0.economicsLastMonth.directOperatingProfit > .zero
        }.count
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
            // Pair by capability, not by list order: a blind zip once handed
            // the shorter-legged used airframe a route past its range.
            guard let index = idle.firstIndex(where: { aircraft in
                (catalog.aircraftType(aircraft.typeCode)?.rangeKm ?? 0)
                    >= route.distanceKm
            }) else { continue }
            let aircraft = idle.remove(at: index)
            #expect(await session.submit(AssignAircraftToRouteCommand(
                airline: player, route: route.id,
                aircraftID: aircraft.id)) == .applied)
            state = await session.snapshot
        }
    }

    /// The deterministic claim the UI journey stands on: with this seed the
    /// era arrives with March, on real economics.
    @Test func campaignReachesTheRegionalEraDeterministically() async throws {
        let report = try await runCampaign(seed: Self.campaignSeed)
        print("CAMPAIGN seed \(Self.campaignSeed): eraDay \(report.eraDay.map(String.init) ?? "never") " +
              "statements \(report.statements.map(\.compact)) booms@days \(report.boomDays) " +
              "missions \(report.missionsOffered) missionDone \(report.missionCompletedDay.map(String.init) ?? "-") " +
              "profitableRoutes \(report.routesProfitableLastMonth) " +
              "cash \(report.finalCash.compact)")
        let eraDay = try #require(report.eraDay,
                                  "the campaign never left the Startup era")
        // Feb closes on day 59; the gate check runs with the month boundary.
        #expect(eraDay <= 62)
        #expect(report.statements.count >= 2)
        // The gate's own terms, restated from the state we ended in.
        #expect(report.routesProfitableLastMonth >= 3)
        // The mission beat: the day-8 boom's mission, completed by reacting
        // with a route into the boom region (ARN-CAI, day 11 measured).
        #expect(report.missionsOffered >= 1)
        #expect(report.missionCompletedDay != nil)
        if let done = report.missionCompletedDay { #expect(done <= 20) }
    }
}
