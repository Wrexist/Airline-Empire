import Testing
@testable import AirlineEmpireCore

@Suite("Progression")
struct ProgressionTests {
    @Test func startsInStartupWithLockedCategories() throws {
        let (_, engine, airline) = try FleetFixtures.catalogAndEngine(
            cash: Money.dollars(500_000_000))
        #expect(engine.state.progression.era == .startup)
        // Widebodies are era-locked for the player.
        guard case .rejected(let rejection) = engine.applyNow(
            BuyUsedAircraftCommand(buyer: airline, type: "MR300", ageYears: 8)) else {
            Issue.record("Expected era lock"); return
        }
        #expect(rejection.code == "progression.lockedCategory")
        // Narrowbodies are fine.
        #expect(engine.applyNow(BuyUsedAircraftCommand(
            buyer: airline, type: "MR180", ageYears: 5)) == .applied)
        // AI airlines are exempt (established carriers).
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "BigCarrier", kind: .ai, homeAirport: "LHR",
            startingCash: Money.dollars(500_000_000),
            aiProfile: AIProfile(archetype: .premium)))
        let ai = engine.state.airlines.values.first { $0.kind == .ai }!.id
        #expect(engine.applyNow(BuyUsedAircraftCommand(
            buyer: ai, type: "MR300", ageYears: 8)) == .applied)
    }

    @Test func earlyMilestonesFire() throws {
        let (engine, _, _) = try DemandFixtures.market(fare: Money.dollars(129))
        engine.advance(ticks: Fixtures.ticksPerDay * 40)
        let milestones = engine.state.progression.milestones
        #expect(milestones.contains("firstFlight"))
        #expect(milestones.contains("firstOwnedAircraft"))
        #expect(milestones.contains("firstProfitableMonth"))
        #expect(engine.state.progression.counters.flightsCompleted > 50)
        #expect(engine.state.progression.counters.passengersCarried > 5000)
        let kinds = engine.state.eventLog.recent.map(\.kind)
        _ = kinds // events may have scrolled past; state is authoritative
    }

    @Test func eraAdvancesToRegionalOnCompetence() throws {
        // Three profitable routes + owned aircraft = Regional.
        let (_, engine, airline) = try FleetFixtures.catalogAndEngine(
            cash: Money.dollars(500_000_000))
        for destination in ["OSL", "CPH", "HEL"] {
            _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180",
                                                       ageYears: 3))
            let aircraft = engine.state.aircraft.values.first {
                $0.owner == airline && $0.assignedRoute == nil }!.id
            _ = engine.applyNow(OpenRouteCommand(
                airline: airline, origin: "ARN", destination: AirportCode(destination),
                dailyRoundTrips: 2, ticketPrice: Money.dollars(79)))
            let route = engine.state.routes.values.first {
                $0.destination == AirportCode(destination) }!.id
            _ = engine.applyNow(AssignAircraftToRouteCommand(
                airline: airline, route: route, aircraftID: aircraft))
        }
        engine.advance(ticks: Fixtures.ticksPerDay * 70) // two closed months
        // State is authoritative (the eraAdvanced event may have scrolled
        // out of the bounded ring over 70 busy days).
        #expect(engine.state.progression.era >= .regional,
                "era is \(engine.state.progression.era)")
    }

    /// GAME_AUDIT_2026-10-18 §2.2: a route with no aircraft counted as
    /// network, so eight empty routes bought the National era's destinations
    /// for a slot pair and a month's route payroll each.
    @Test func eraGatesCountOnlyRoutesThatFly() throws {
        let (catalog, engine, airline) = try FleetFixtures.catalogAndEngine(
            cash: Money.dollars(500_000_000), systems: [])
        let nearby = catalog.nearestAirports(to: "ARN", limit: 20)
            .filter { $0.1 >= catalog.tuning.minRouteDistanceKm }
            .prefix(catalog.tuning.progression.nationalDestinations)
        for (airport, _) in nearby {
            #expect(engine.applyNow(OpenRouteCommand(
                airline: airline, origin: "ARN", destination: airport.code,
                dailyRoundTrips: 1, ticketPrice: Money.dollars(119))) == .applied)
        }
        func destinations() throws -> Double {
            let player = try #require(engine.state.playerAirline)
            let national = EraGate.requirements(
                for: .national, player: player, state: engine.state, catalog: catalog,
                tuning: catalog.tuning.progression)
            return try #require(national.first { $0.kind == .destinations }).current
        }
        #expect(try destinations() == 0, "empty routes serve no destination")

        #expect(engine.applyNow(BuyUsedAircraftCommand(
            buyer: airline, type: "MR180", ageYears: 3)) == .applied)
        let aircraft = try #require(engine.state.fleet(of: airline).first).id
        let spec = try #require(catalog.aircraftType("MR180"))
        let route = try #require(engine.state.routes(of: airline).first { route in
            route.distanceKm <= spec.rangeKm
                && [route.origin, route.destination].allSatisfy {
                    (catalog.airport($0)?.runwayClass ?? .small) >= spec.runwayRequirement
                }
        })
        #expect(engine.applyNow(AssignAircraftToRouteCommand(
            airline: airline, route: route.id, aircraftID: aircraft)) == .applied)
        // One route flying: its two ends, and nothing from the empty seven.
        #expect(try destinations() == 2)
    }

    @Test func capabilityProgramGatesAndEffects() throws {
        let (_, engine, airline) = try FleetFixtures.catalogAndEngine(
            cash: Money.dollars(500_000_000))
        // Locked before National.
        guard case .rejected(let r1) = engine.applyNow(
            StartCapabilityProgramCommand(airline: airline, code: .fuelHedging)) else {
            Issue.record("Expected era lock"); return
        }
        #expect(r1.code == "progression.eraLocked")

        // Fast-forward progression state via test surgery to National.
        var state = engine.state
        state.progression.era = .national
        let surgical = SimulationEngine(state: state, systems: GamePipeline.standard(),
                                        catalog: engine.catalog)
        #expect(surgical.applyNow(StartCapabilityProgramCommand(
            airline: airline, code: .fuelHedging)) == .applied)
        // Duplicate start rejected.
        guard case .rejected(let r2) = surgical.applyNow(
            StartCapabilityProgramCommand(airline: airline, code: .fuelHedging)) else {
            Issue.record("Expected duplicate rejection"); return
        }
        #expect(r2.code == "progression.alreadyRunning")
        // Third concurrent program rejected.
        _ = surgical.applyNow(StartCapabilityProgramCommand(
            airline: airline, code: .efficientTurnarounds))
        guard case .rejected(let r3) = surgical.applyNow(
            StartCapabilityProgramCommand(airline: airline, code: .networkOpsCenter)) else {
            Issue.record("Expected concurrency limit"); return
        }
        #expect(r3.code == "progression.tooManyPrograms")

        // Programs complete after their duration.
        surgical.advance(ticks: Fixtures.ticksPerDay * 95)
        #expect(surgical.state.playerHasCapability(.fuelHedging))
        #expect(surgical.state.playerHasCapability(.efficientTurnarounds))
        #expect(surgical.state.progression.activePrograms.isEmpty)
    }

    @Test func fuelHedgingCapsFuelBills() throws {
        // Same world, same shock: hedged pays less for fuel.
        func run(hedged: Bool) throws -> Money {
            let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
            var state = engine.state
            state.progression.era = .national
            if hedged { state.progression.completedPrograms = ["fuelHedging"] }
            // Force an expensive fuel world.
            state.world.fuelPricePerTon = Money(cents: 130_000) // 2x base
            var event = WorldEvent(id: 99, kind: .fuelShock,
                                   beginsAt: state.clock.now,
                                   endsAt: state.clock.now + .days(400), severity: 0.9)
            event.hasStarted = true
            state.world.activeEvents.append(event)
            let surgical = SimulationEngine(state: state,
                                            systems: GamePipeline.standard(),
                                            catalog: engine.catalog)
            surgical.advance(ticks: Fixtures.ticksPerDay * 30)
            _ = airline
            return -surgical.state.ledger.recent
                .filter { $0.category == .fuel }
                .reduce(Money.zero) { $0 + $1.amount }
        }
        let unhedged = try run(hedged: false)
        let hedged = try run(hedged: true)
        #expect(hedged < Money(rounding: unhedged.asDouble * 0.75),
                "hedged \(hedged.cents) vs unhedged \(unhedged.cents)")
    }

    @Test func boomMissionOffersCompletesAndPays() throws {
        // Active boom over the anchor market's region -> mission appears;
        // busy route completes it.
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(99))
        var state = engine.state
        var event = WorldEvent(id: 500, kind: .tourismBoom(region: .europe),
                               beginsAt: state.clock.now,
                               endsAt: state.clock.now + .days(90), severity: 0.35)
        event.hasStarted = true
        state.world.activeEvents.append(event)
        let surgical = SimulationEngine(state: state, systems: GamePipeline.standard(),
                                        catalog: engine.catalog)
        surgical.advance(ticks: Fixtures.ticksPerDay * 3)
        let offered = surgical.state.progression.missions
        #expect(offered.count == 1)
        guard case .boomRush(let region, let target) = offered[0].kind else {
            Issue.record("Wrong mission kind"); return
        }
        #expect(region == .europe)
        #expect(target > 0)

        surgical.advance(ticks: Fixtures.ticksPerDay * 85)
        // Either completed (reward posted) or expired — with a 2x daily
        // service on the boom region at cheap fares, completion is expected.
        let rewards = surgical.state.ledger.recent.filter {
            $0.airline == airline && $0.category == .missionReward
        }
        #expect(!rewards.isEmpty, "Mission should have completed")
        #expect(surgical.state.progression.missions.isEmpty)
        // No duplicate offer for the same event.
        #expect(surgical.state.world.eventCooldowns["mission.500"] != nil)
    }

    /// Two European routes, each with its own MR180, and a European tourism
    /// boom live from the start — the shape a boom rush is offered on.
    private func boomWorld() throws -> (ContentCatalog, SimulationEngine, AirlineID, [RouteID]) {
        let (catalog, setup, airline) = try FleetFixtures.catalogAndEngine(
            cash: Money.dollars(400_000_000), systems: [])
        var routes: [RouteID] = []
        for destination in ["OSL", "CPH"] {
            _ = setup.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180", ageYears: 3))
            let aircraft = try #require(setup.state.fleet(of: airline).last).id
            _ = setup.applyNow(OpenRouteCommand(
                airline: airline, origin: "ARN", destination: AirportCode(destination),
                dailyRoundTrips: 2, ticketPrice: Money.dollars(79)))
            let route = try #require(setup.state.routes(of: airline).last).id
            _ = setup.applyNow(AssignAircraftToRouteCommand(
                airline: airline, route: route, aircraftID: aircraft))
            routes.append(route)
        }
        var state = setup.state
        var event = WorldEvent(id: 600, kind: .tourismBoom(region: .europe),
                               beginsAt: state.clock.now,
                               endsAt: state.clock.now + .days(90), severity: 0.35)
        event.hasStarted = true
        state.world.activeEvents.append(event)
        let engine = SimulationEngine(state: state, systems: GamePipeline.standard(),
                                      catalog: catalog)
        return (catalog, engine, airline, routes)
    }

    /// GAME_AUDIT_2026-10-18 §2.3: boom-rush progress was the region's open
    /// routes' lifetime passengers less the offer's baseline, so closing a
    /// route took its passengers back — to zero, closing the only one — and
    /// could leave the mission unwinnable.
    @Test func boomRushProgressSurvivesClosingARoute() throws {
        let (catalog, engine, airline, routes) = try boomWorld()
        engine.advance(ticks: Fixtures.ticksPerDay * 2)
        let offered = try #require(engine.state.progression.missions.first)
        guard case .boomRush = offered.kind else {
            Issue.record("expected a boom rush, got \(offered.kind)"); return
        }
        engine.advance(ticks: Fixtures.ticksPerDay * 5)
        func progress() throws -> Int64 {
            let mission = try #require(engine.state.progression.missions.first { $0.id == offered.id })
            let player = try #require(engine.state.playerAirline)
            return MissionMath.progress(of: mission, player: player, state: engine.state,
                                        catalog: catalog)
        }
        let before = try progress()
        try #require(before > 0)
        let closing = try #require(engine.state.routes[routes[0]])
        try #require(closing.stats.passengersCarried > 0)

        // Midnight: today's legs are planned, none airborne.
        #expect(engine.applyNow(CloseRouteCommand(airline: airline, route: routes[0])) == .applied)
        #expect(engine.state.routes[routes[0]] == nil)
        // The open routes' counters dropped by the closed route's lifetime;
        // progress did not move.
        #expect(try progress() == before)

        engine.advance(ticks: Fixtures.ticksPerDay * 3)
        #expect(try progress() > before, "the remaining route keeps counting")
    }

    /// GAME_AUDIT_2026-10-18 §6: the boom-rush target assumed 150 seats a
    /// trip at the requested frequency. It is the seats the region's routes
    /// actually offer.
    @Test func boomRushTargetComesFromSeatsOffered() throws {
        let (catalog, engine, airline, _) = try boomWorld()
        let before = engine.state
        engine.advance(ticks: Fixtures.ticksPerDay)
        let mission = try #require(engine.state.progression.missions.first)
        guard case .boomRush(_, let target) = mission.kind else {
            Issue.record("expected a boom rush, got \(mission.kind)"); return
        }
        let seats = before.routes(of: airline).reduce(0) {
            $0 + MissionMath.dailySeatsOffered($1, state: before, catalog: catalog)
        }
        // Two MR180 routes at two round trips: four legs a day of its cabin each.
        let spec = try #require(catalog.aircraftType("MR180"))
        let cabin = try #require(before.fleet(of: airline).first).cabin(for: spec).totalSeats
        #expect(seats == 2 * 2 * 2 * cabin)
        let event = try #require(engine.state.world.activeEvents.first { $0.id == 600 })
        let days = max(1, (event.endsAt - engine.state.clock.now).minutes
            / GameCalendar.minutesPerDay)
        #expect(target == max(500, Int64(Double(seats) * Double(days)
            * catalog.tuning.progression.boomRushTargetFactor)))
    }

    /// GAME_AUDIT_2026-10-18 §6: `weatherProof` was judged on the routes
    /// still open, so closing the ones that cancelled bought it.
    @Test func weatherProofCannotBeBoughtByClosingRoutes() throws {
        let (catalog, setup, airline) = try FleetFixtures.catalogAndEngine(
            cash: Money.dollars(400_000_000), systems: [])
        for destination in ["OSL", "CPH"] {
            _ = setup.applyNow(OpenRouteCommand(
                airline: airline, origin: "ARN", destination: AirportCode(destination),
                dailyRoundTrips: 2, ticketPrice: Money.dollars(79)))
        }
        var state = setup.state
        let routes = state.routes(of: airline).map(\.id)
        // 1,000 flights: 900 on a route that also cancelled 100, and 100
        // clean ones elsewhere — 91% over the airline's life.
        state.progression.counters.flightsCompleted = 1_000
        state.routes[routes[0]]?.stats = RouteStats(flightsCompleted: 900, flightsCancelled: 100)
        state.routes[routes[1]]?.stats = RouteStats(flightsCompleted: 100)
        let engine = SimulationEngine(state: state, systems: [ProgressionSystem()], catalog: catalog)
        engine.advance(ticks: Fixtures.ticksPerDay)
        #expect(!engine.state.progression.achievements.contains("weatherProof"))

        // Close the route that cancelled. Only the clean route is left open.
        #expect(engine.applyNow(CloseRouteCommand(airline: airline, route: routes[0])) == .applied)
        let player = try #require(engine.state.playerAirline)
        #expect(MissionMath.lifetimeCancellations(player: player, state: engine.state) == 100)
        engine.advance(ticks: Fixtures.ticksPerDay)
        #expect(!engine.state.progression.achievements.contains("weatherProof"),
                "closing the route that cancelled must not erase its cancellations")
    }

    @Test func playerCollapseIsGameOver() throws {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Doomed", kind: .player, homeAirport: "ARN",
            startingCash: Money.dollars(3_000_000)))
        let player = engine.state.airlines.values.first!.id
        for _ in 0..<3 {
            _ = engine.applyNow(LeaseAircraftCommand(lessee: player, type: "MR180",
                                                     termMonths: 60))
        }
        engine.advance(ticks: Fixtures.ticksPerYear * 3)
        #expect(engine.state.airlines[player]!.status == .collapsed)
        #expect(engine.state.progression.gameOver)
    }

    @Test func progressionSurvivesSaveDeterministically() throws {
        let catalog = try ContentCatalog.loadBundled()
        func build() throws -> SimulationEngine {
            let engine = SimulationEngine(state: Fixtures.newState(seed: 2027),
                                          systems: GamePipeline.standard(), catalog: catalog)
            _ = engine.applyNow(FoundAirlineCommand(
                airlineName: "ProgSave", kind: .player, homeAirport: "ARN",
                startingCash: Money.dollars(200_000_000)))
            let airline = engine.state.airlines.values.first!.id
            _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180",
                                                       ageYears: 4))
            _ = engine.applyNow(OpenRouteCommand(
                airline: airline, origin: "ARN", destination: "LHR",
                dailyRoundTrips: 3, ticketPrice: Money.dollars(119)))
            let route = engine.state.routes.values.first!.id
            let aircraft = engine.state.aircraft.values.first!.id
            _ = engine.applyNow(AssignAircraftToRouteCommand(
                airline: airline, route: route, aircraftID: aircraft))
            return engine
        }
        let straight = try build()
        straight.advance(ticks: Fixtures.ticksPerDay * 120)
        let split = try build()
        split.advance(ticks: Fixtures.ticksPerDay * 55)
        let data = try JSONSaveCodec().encode(split.state)
        let resumed = SimulationEngine(state: try JSONSaveCodec().decode(data),
                                       systems: GamePipeline.standard(), catalog: catalog)
        resumed.advance(ticks: Fixtures.ticksPerDay * 65)
        #expect(try resumed.state.stateHash() == straight.state.stateHash())
    }
}

@Suite("Scenarios")
struct ScenarioTests {
    @Test func bundledScenariosLoadAndDiffer() throws {
        let catalog = try ContentCatalog.loadBundled()
        #expect(catalog.scenarios.count == 3)
        let founder = try #require(catalog.scenario("founder"))
        let magnate = try #require(catalog.scenario("magnate"))
        #expect(founder.playerStartingCash > magnate.playerStartingCash)
        #expect(founder.competitorCount < magnate.competitorCount)
        #expect(founder.competitorStartingCash < magnate.competitorStartingCash)
    }

    @Test func beginScenarioSetsUpTheWorld() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let spec = try #require(catalog.scenario("magnate"))
        let session = GameSession(
            state: ScenarioBootstrap.newGame(scenario: "magnate", worldSeed: 7,
                                             startYear: spec.startYear),
            systems: GamePipeline.standard(), catalog: catalog)
        let result = await session.beginScenario(spec, airlineName: "Hard Mode",
                                                 home: "ARN")
        #expect(result == .applied)
        let snapshot = await session.snapshot
        let player = try #require(snapshot.playerAirline)
        #expect(snapshot.ledger.balance(of: player.id) == spec.playerStartingCash)
        let competitors = snapshot.airlines.values.filter { $0.kind == .ai }
        #expect(competitors.count == spec.competitorCount)
        // Rich rivals per the scenario (starter aircraft already bought,
        // so balances sit below the initial capital).
        for rival in competitors {
            #expect(snapshot.ledger.recent.contains {
                $0.airline == rival.id && $0.category == .initialCapital
                    && $0.amount == spec.competitorStartingCash
            } || snapshot.ledger.balance(of: rival.id) <= spec.competitorStartingCash)
        }
    }

    @Test func invalidScenarioContentRejected() {
        let bad = ScenarioSpec(code: "bad", name: "Bad", blurb: "", startYear: 2030,
                               playerStartingCash: .zero, competitorCount: 99,
                               competitorStartingCash: Money.dollars(1))
        #expect(throws: ContentError.self) {
            _ = try ContentCatalog(version: "t", airports: [],
                                   seasonality: [], scenarios: [bad],
                                   tuning: .standard)
        }
    }
}
