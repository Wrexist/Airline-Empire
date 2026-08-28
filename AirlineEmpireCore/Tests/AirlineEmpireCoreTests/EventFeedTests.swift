import Testing
@testable import AirlineEmpireCore

/// The player's operations feed must show the player's business, world news,
/// and rivals' public fates — never a rival's private books (BUG-004) — and
/// a command rejected while the world is running must still reach the
/// player (BUG-005).
@Suite("Event feed and rejection delivery")
struct EventFeedTests {
    @Test func rivalPrivateBusinessIsNotInThePlayerFeed() throws {
        let (engine, player) = try AIFixtures.world(competitors: 3)
        let rival = try #require(engine.state.airlines.values
            .first { $0.kind == .ai })
        let state = engine.state

        // A rival's closed statement and loan are private.
        let rivalStatement = SimEvent(at: state.clock.now, kind: .statementClosed(
            airline: rival.id, year: 2030, month: 4, netProfit: Money.dollars(1_000)))
        let rivalLoan = SimEvent(at: state.clock.now, kind: .loanTaken(
            airline: rival.id, amount: Money.dollars(5_000_000), rateBasisPoints: 700))
        #expect(!state.isFeedEvent(rivalStatement, for: player))
        #expect(!state.isFeedEvent(rivalLoan, for: player))
        #expect(state.subjectAirline(of: rivalStatement) == rival.id)

        // The player's own equivalents are.
        let ownStatement = SimEvent(at: state.clock.now, kind: .statementClosed(
            airline: player, year: 2030, month: 4, netProfit: Money.dollars(1_000)))
        #expect(state.isFeedEvent(ownStatement, for: player))
    }

    @Test func rivalFailureIsIndustryNewsButRivalOpsAreNot() throws {
        let (engine, player) = try AIFixtures.world(competitors: 3)
        let rival = try #require(engine.state.airlines.values
            .first { $0.kind == .ai })
        let state = engine.state

        for kind: SimEventKind in [.airlineEnteredAdministration(id: rival.id),
                                   .airlineCollapsed(id: rival.id),
                                   .airlineFounded(id: rival.id, name: rival.name)] {
            #expect(state.isFeedEvent(SimEvent(at: state.clock.now, kind: kind),
                                      for: player))
        }
    }

    @Test func flightAndFleetEventsResolveThroughOwnership() throws {
        let (engine, player) = try AIFixtures.world(competitors: 2)
        // Give the player a route and an aircraft, then let both sides fly.
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: player, type: "MR180",
                                                   ageYears: 8))
        let aircraft = try #require(engine.state.fleet(of: player).first).id
        engine.advance(ticks: Fixtures.ticksPerDay * 30)
        let state = engine.state

        let fleetEvent = SimEvent(at: state.clock.now,
                                  kind: .maintenanceCompleted(id: aircraft))
        #expect(state.subjectAirline(of: fleetEvent) == player)
        #expect(state.isFeedEvent(fleetEvent, for: player))

        // A rival's route: its flight events belong to the rival, not us.
        let rivalRoute = try #require(state.orderedRouteIDs
            .compactMap { state.routes[$0] }
            .first { $0.airline != player })
        let rivalFlight = SimEvent(at: state.clock.now, kind: .flightDelayed(
            id: EntityID(raw: 1), route: rivalRoute.id, delayMinutes: 45))
        #expect(state.subjectAirline(of: rivalFlight) == rivalRoute.airline)
        #expect(!state.isFeedEvent(rivalFlight, for: player))
    }

    @Test func worldNewsReachesEveryoneAndKernelChatterReachesNobody() throws {
        let (engine, player) = try AIFixtures.world(competitors: 2)
        let state = engine.state
        let storm = SimEvent(at: state.clock.now, kind: .worldEventStarted(
            id: 1, kind: .storm(region: .europe)))
        #expect(state.subjectAirline(of: storm) == nil)
        #expect(state.isFeedEvent(storm, for: player))

        // Diagnostics are not news.
        let chatter = SimEvent(at: state.clock.now,
                               kind: .commandApplied(name: "OpenRoute"))
        #expect(!state.isFeedEvent(chatter, for: player))
    }

    /// The live path: a filtered subscription must not carry rival noise
    /// while an unfiltered one still sees everything.
    @Test func filteredSubscriptionDropsRivalEvents() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: 9),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Feed Air", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(120_000_000)))
        await session.populateStandardWorld(competitors: 3)
        let player = try #require(await session.snapshot.playerAirline).id

        let filtered = await session.events(playerFeedOnly: true)
        let collector = Task {
            var seen: [SimEvent] = []
            for await event in filtered {
                seen.append(event)
                if seen.count >= 40 { break }
            }
            return seen
        }
        await session.advance(ticks: Fixtures.ticksPerDay * 45)
        let seen = await collector.value
        let snapshot = await session.snapshot
        #expect(!seen.isEmpty)
        for event in seen {
            let subject = snapshot.subjectAirline(of: event)
            let publicNews: Bool
            switch event.kind {
            case .airlineFounded, .airlineEnteredAdministration, .airlineCollapsed:
                publicNews = true
            default:
                publicNews = false
            }
            #expect(subject == nil || subject == player || publicNews)
        }
    }


    /// An entity event whose route or aircraft was deleted before
    /// classification has an *unknown* owner, not a world-wide one. Treating
    /// the two alike leaked a collapsing rival's flights into the player's
    /// feed (BUG-007), because `collapse()` removes the airline's routes and
    /// fleet in the same chunk that produced those events.
    @Test func deletedEntityEventsAreNotTreatedAsWorldNews() throws {
        let (engine, player) = try AIFixtures.world(competitors: 2)
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: player, type: "MR180",
                                                   ageYears: 8))
        engine.advance(ticks: Fixtures.ticksPerDay * 20)
        let state = engine.state

        // A flight event naming a route that no longer exists.
        let ghostRoute = RouteID(raw: 999_999)
        #expect(state.routes[ghostRoute] == nil)
        let ghostFlight = SimEvent(at: state.clock.now, kind: .flightDelayed(
            id: EntityID(raw: 1), route: ghostRoute, delayMinutes: 30))
        #expect(state.subjectAirline(of: ghostFlight) == nil)
        #expect(state.isEntityScoped(ghostFlight))
        #expect(!state.isFeedEvent(ghostFlight, for: player),
                "an unattributable flight must not reach the player's feed")

        // Same for a sold/liquidated aircraft and a closed route.
        let ghostAircraft = SimEvent(at: state.clock.now,
                                     kind: .aircraftSold(id: EntityID(raw: 999_999),
                                                         proceeds: Money.dollars(1)))
        #expect(!state.isFeedEvent(ghostAircraft, for: player))
        let ghostClosure = SimEvent(at: state.clock.now,
                                    kind: .routeClosed(id: ghostRoute))
        #expect(!state.isFeedEvent(ghostClosure, for: player))

        // World news with no entity behind it still reaches everyone.
        let storm = SimEvent(at: state.clock.now, kind: .worldEventStarted(
            id: 7, kind: .storm(region: .europe)))
        #expect(!state.isEntityScoped(storm))
        #expect(state.isFeedEvent(storm, for: player))
    }

    /// A rival collapsing must not spill its final day of operations into the
    /// player's feed — the end-to-end version of the case above.
    @Test func collapsingRivalDoesNotLeakIntoThePlayerFeed() throws {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(seed: 4242),
                                      systems: GamePipeline.standard(),
                                      catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Survivor", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(150_000_000)))
        let player = engine.state.airlines.values.first!.id
        // A rival with barely any cash, flying an expensive lease: it fails.
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Doomed", kind: .ai, homeAirport: "LNW",
            startingCash: Money.dollars(3_000_000)))
        let rival = try #require(engine.state.airlines.values
            .first { $0.name == "Doomed" }).id
        _ = engine.applyNow(LeaseAircraftCommand(lessee: rival, type: "MR300",
                                                 termMonths: 60))
        engine.advance(ticks: Fixtures.ticksPerYear)

        let state = engine.state
        // Whatever survived in the ring, nothing entity-scoped that resolves
        // to the rival — or to nobody — may be in the player's feed.
        for event in state.eventLog.recent where state.isFeedEvent(event, for: player) {
            let subject = state.subjectAirline(of: event)
            if state.isEntityScoped(event) {
                #expect(subject == player,
                        "entity event \(event.kind) leaked with subject \(String(describing: subject))")
            }
        }
    }

    @Test func queuedCommandRejectionReachesTheSubscriber() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: 4),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Broke Air", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(1_000)))
        let player = try #require(await session.snapshot.playerAirline).id

        let rejections = await session.rejections()
        let collector = Task {
            for await rejection in rejections { return rejection }
            return CommandRejection(code: "none", message: "none")
        }

        // Running, not paused: the command is queued, not applied now.
        await session.setSpeed(.x4)
        let immediate = await session.submit(BuyNewAircraftCommand(
            buyer: player, type: "MR180"))
        #expect(immediate == nil)

        await session.advance(ticks: 4)
        let rejection = await collector.value
        #expect(rejection.code != "none")
        #expect(!rejection.message.isEmpty)
    }

    /// Subscription lifecycle (V3 prompt §27): subscribers are independent,
    /// and a session can be re-subscribed after a consumer goes away —
    /// the Core-side half of the TD-002 class of bug.
    @Test func subscriptionsAreIndependentAndResubscribable() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: 12),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Stream Air", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(80_000_000)))

        func collectFive(_ stream: AsyncStream<SimEvent>) -> Task<Int, Never> {
            Task {
                var count = 0
                for await _ in stream {
                    count += 1
                    if count >= 5 { break }
                }
                return count
            }
        }

        // Two concurrent consumers both get served.
        let first = collectFive(await session.events())
        let second = collectFive(await session.events())
        // 30 days of calendar events comfortably exceeds the five each
        // consumer waits for (an airline with no fleet emits little else).
        await session.advance(ticks: Fixtures.ticksPerDay * 30)
        #expect(await first.value == 5)
        #expect(await second.value == 5)

        // Both are finished; a fresh subscription still works, so a new
        // game inside one app run is not deaf.
        let third = collectFive(await session.events())
        // 30 days of calendar events comfortably exceeds the five each
        // consumer waits for (an airline with no fleet emits little else).
        await session.advance(ticks: Fixtures.ticksPerDay * 30)
        #expect(await third.value == 5)
    }

    @Test func appliedQueuedCommandsProduceNoRejection() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: 5),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Solvent Air", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(120_000_000)))
        let player = try #require(await session.snapshot.playerAirline).id
        await session.setSpeed(.x4)
        _ = await session.submit(BuyUsedAircraftCommand(buyer: player,
                                                        type: "MR180", ageYears: 8))
        await session.advance(ticks: 4)
        let fleet = await session.snapshot.fleet(of: player)
        #expect(fleet.count == 1)
    }
}
