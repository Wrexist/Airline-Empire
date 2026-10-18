import Foundation
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
            airlineName: "Feed Air", kind: .player, homeAirport: "ARN",
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
            airlineName: "Survivor", kind: .player, homeAirport: "ARN",
            startingCash: Money.dollars(150_000_000)))
        let player = engine.state.airlines.values.first!.id
        // A rival with barely any cash, flying an expensive lease: it fails.
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Doomed", kind: .ai, homeAirport: "LHR",
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

    /// BUG-005 was a refusal that never reached the player because a running
    /// game queued the command and `submit` returned nil. Commands now apply
    /// at once, so the refusal comes straight back from `submit`.
    @Test func runningCommandRejectionIsReturnedAtOnce() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: 4),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Broke Air", kind: .player, homeAirport: "ARN",
            startingCash: Money.dollars(1_000)))
        let player = try #require(await session.snapshot.playerAirline).id

        await session.setSpeed(.x4)
        let result = await session.submit(BuyNewAircraftCommand(
            buyer: player, type: "MR180"))
        guard case .rejected(let rejection) = result else {
            Issue.record("An unaffordable purchase was not refused: \(result)")
            return
        }
        #expect(!rejection.code.isEmpty)
        #expect(!rejection.message.isEmpty)
        #expect(await session.snapshot.fleet(of: player).isEmpty)
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
            airlineName: "Stream Air", kind: .player, homeAirport: "ARN",
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
            airlineName: "Solvent Air", kind: .player, homeAirport: "ARN",
            startingCash: Money.dollars(120_000_000)))
        let player = try #require(await session.snapshot.playerAirline).id
        await session.setSpeed(.x4)
        _ = await session.submit(BuyUsedAircraftCommand(buyer: player,
                                                        type: "MR180", ageYears: 8))
        await session.advance(ticks: 4)
        let fleet = await session.snapshot.fleet(of: player)
        #expect(fleet.count == 1)
    }

    // MARK: - Own disposals and TD-032

    /// The player's own sale and lease return reach their feed. Both
    /// commands delete the aircraft before the event is classified, so the
    /// owner lookup found nothing and the player's own business was filed as
    /// nobody's — absent from the feed it was most about.
    @Test func ownSaleAndLeaseReturnReachThePlayersFeed() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: 21),
                                  systems: GamePipeline.standard(), catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Seller Air", kind: .player, homeAirport: "ARN",
            startingCash: Money.dollars(150_000_000)))
        let player = try #require(await session.snapshot.playerAirline).id
        #expect(await session.submit(BuyUsedAircraftCommand(
            buyer: player, type: "MR180", ageYears: 8)) == .applied)
        #expect(await session.submit(LeaseAircraftCommand(
            lessee: player, type: "MR180", termMonths: 36)) == .applied)
        let fleet = await session.snapshot.fleet(of: player)
        let owned = try #require(fleet.first { !$0.ownership.isLeased }).id
        let leased = try #require(fleet.first { $0.ownership.isLeased }).id

        let feed = await session.events(playerFeedOnly: true)
        let collector = Task {
            var seen: [SimEvent] = []
            for await event in feed {
                seen.append(event)
                // The sentinel below: a purchase is always the player's.
                if case .aircraftDelivered = event.kind { break }
            }
            return seen
        }
        await session.setSpeed(.x1)
        #expect(await session.submit(SellAircraftCommand(
            seller: player, aircraftID: owned)) == .applied)
        #expect(await session.submit(ReturnLeasedAircraftCommand(
            lessee: player, aircraftID: leased)) == .applied)
        _ = await session.submit(BuyUsedAircraftCommand(buyer: player, type: "MR180", ageYears: 8))
        let seen = await collector.value

        #expect(seen.contains { event in
            if case .aircraftSold(let id, _, let airline) = event.kind {
                return id == owned && airline == player
            }
            return false
        }, "the player's own sale is missing from their feed")
        #expect(seen.contains { event in
            if case .leaseReturned(let id, _, let airline) = event.kind {
                return id == leased && airline == player
            }
            return false
        }, "the player's own lease return is missing from their feed")
        // And the kept feed, which the digest reads, has both too.
        let kept = await session.snapshot.eventLog.playerFeed
        #expect(kept.contains { if case .aircraftSold = $0.kind { true } else { false } })
        #expect(kept.contains { if case .leaseReturned = $0.kind { true } else { false } })
    }

    /// Sale and lease-return events in a save written before they carried an
    /// airline must still decode — they sit in every older save's event log.
    @Test func disposalEventsFromBeforeTheAirlineFieldStillDecode() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let cases: [(key: String, current: SimEventKind, legacy: SimEventKind)] = [
            ("aircraftSold",
             .aircraftSold(id: AircraftID(raw: 4), proceeds: Money.dollars(10), airline: AirlineID(raw: 1)),
             .aircraftSold(id: AircraftID(raw: 4), proceeds: Money.dollars(10))),
            ("leaseReturned",
             .leaseReturned(id: AircraftID(raw: 5), penalty: Money.dollars(20), airline: AirlineID(raw: 1)),
             .leaseReturned(id: AircraftID(raw: 5), penalty: Money.dollars(20))),
        ]
        for entry in cases {
            let event = SimEvent(at: SimTime(rawMinutes: 90), kind: entry.current)
            var tree = try #require(JSONSerialization.jsonObject(
                with: encoder.encode(event)) as? [String: Any])
            var kind = try #require(tree["kind"] as? [String: Any])
            var payload = try #require(kind[entry.key] as? [String: Any])
            #expect(payload["airline"] != nil)
            payload["airline"] = nil
            kind[entry.key] = payload
            tree["kind"] = kind
            let decoded = try JSONDecoder().decode(
                SimEvent.self, from: JSONSerialization.data(withJSONObject: tree))
            #expect(decoded.kind == entry.legacy)
            // The current shape round-trips with its airline.
            #expect(try JSONDecoder().decode(SimEvent.self, from: encoder.encode(event)) == event)
        }
    }

    /// TD-032: the shared rings are one window for the whole world, so a
    /// busy world's rival traffic pushed the player's own news and money out
    /// of them within the day. The player's feed ring and the airline's own
    /// ledger day window keep both, and the digest reads them whole.
    @Test func playerNewsAndMoneySurviveHeavyRivalTraffic() throws {
        let (_, engine, player, _, routeID) = try FlightOpsTests.operating()
        #expect(engine.applyNow(FoundAirlineCommand(
            airlineName: "Flood Air", kind: .ai, homeAirport: "LHR",
            startingCash: Money.dollars(200_000_000))) == .applied)
        let rival = try #require(engine.state.airlines.values.first { $0.name == "Flood Air" }).id
        let own = try #require(engine.state.routes[routeID])
        // The rival enters the player's market: news the player must see.
        #expect(engine.applyNow(OpenRouteCommand(
            airline: rival, origin: own.destination, destination: own.origin,
            dailyRoundTrips: 2, ticketPrice: Money.dollars(99))) == .applied)
        let entry = try #require(engine.state.eventLog.recent.last { event in
            if case .marketEntered(let airline, _, _) = event.kind { return airline == rival }
            return false
        })
        let rivalRoute = try #require(engine.state.routes(of: rival).first).id

        // A day of somebody else's flying and spending, far more than either
        // shared ring holds.
        var state = engine.state
        let now = state.clock.now
        state.recordEvents((0..<5_000).map { index in
            SimEvent(at: now, kind: .flightArrived(id: FlightID(raw: Int64(500_000 + index)),
                                                   route: rivalRoute, delayMinutes: 0))
        })
        for _ in 0..<5_000 {
            state.ledger.post(airline: rival, category: .fuel, amount: Money.dollars(-1), at: now)
        }
        #expect(!state.eventLog.recent.contains(entry), "the flood should evict the shared ring")
        #expect(!state.ledger.recent.contains { $0.airline == player })

        #expect(state.eventLog.playerFeed.contains(entry))
        #expect(!state.eventLog.playerFeed.contains { event in
            if case .flightArrived(_, let route, _) = event.kind { return route == rivalRoute }
            return false
        }, "rival flights must not enter the player's feed")
        let digest = try #require(state.dailyDigest(for: player))
        #expect(digest.isComplete)
        #expect(digest.notableEvents.contains(entry))
        // Every posting the player has made is today's: the day's net is
        // the whole balance, to the cent.
        #expect(digest.netCashChange == state.ledger.balance(of: player))
    }

    /// The live stream half of TD-032: a long advance used to publish once
    /// per game day, handing subscribers only the last 512 events of a day
    /// that held tens of thousands. The player's news in the morning never
    /// arrived. Events now stream tick by tick.
    @Test func playerStreamKeepsEventsFromABusyDay() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: 33),
                                  systems: [TrafficSystem(perTick: 200), MarkerSystem()],
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Busy Day Air", kind: .player, homeAirport: "ARN",
            startingCash: Money.dollars(150_000_000)))
        let player = try #require(await session.snapshot.playerAirline).id
        let feed = await session.events(playerFeedOnly: true)
        let collector = Task {
            var codes: [String] = []
            for await event in feed {
                if case .milestoneReached(let code) = event.kind { codes.append(code) }
                if case .aircraftDelivered = event.kind { break }
            }
            return codes
        }
        await session.advanceToNextMorning() // a day and a quarter in one call
        // Sentinel: the player's own purchase ends the collection.
        _ = await session.submit(BuyUsedAircraftCommand(buyer: player, type: "MR180", ageYears: 8))
        #expect(await collector.value == ["test.morning", "test.evening"])
    }
}

/// A busy world's traffic, none of it the player's: `perTick` diagnostic
/// events every tick.
private struct TrafficSystem: SimulationSystem {
    let id = "test.traffic"
    let cadence = Cadence.everyTick
    let perTick: Int

    func update(state: inout GameState, context: SimContext) {
        for index in 0..<perTick { context.emit(.wakeFired(label: "traffic \(index)")) }
    }
}

/// The player's news at 02:00 and 22:00 on the first day — each followed by
/// hours of traffic before the day ends.
private struct MarkerSystem: SimulationSystem {
    let id = "test.marker"
    let cadence = Cadence.everyTick

    func update(state: inout GameState, context: SimContext) {
        guard context.current.dayIndex == 0 else { return }
        switch context.current.minuteOfDay {
        case 2 * 60: context.emit(.milestoneReached(code: "test.morning"))
        case 22 * 60: context.emit(.milestoneReached(code: "test.evening"))
        default: break
        }
    }
}
