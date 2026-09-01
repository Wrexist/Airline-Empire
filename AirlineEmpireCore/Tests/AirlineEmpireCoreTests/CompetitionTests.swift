import Foundation
import Testing
@testable import AirlineEmpireCore

/// Competition as the player sees it (AE-037): the market-move record, the
/// two events that let a rival's entry reach the feed, the per-route
/// standing, the network summary and its Home headline — and the two
/// simulation defects the phase's measurement found underneath them.
@Suite("Competition")
struct CompetitionTests {

    /// Player at ARN with the standard cast, through commands only.
    private func world(competitors: Int = 5, seed: UInt64 = 2039)
        throws -> (SimulationEngine, AirlineID) {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(seed: seed),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Player Air", kind: .player, homeAirport: "ARN",
            startingCash: Money.dollars(150_000_000)))
        let player = engine.state.airlines.values.first!.id
        WorldSetup.createCompetitors(engine: engine, count: competitors, playerHome: "ARN")
        return (engine, player)
    }

    private func openAndFly(_ engine: SimulationEngine, player: AirlineID,
                            from: AirportCode, to: AirportCode, fare: Money,
                            type: AircraftTypeCode = "MR180") -> RouteID? {
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: player, type: type, ageYears: 5))
        guard let aircraft = engine.state.fleet(of: player)
            .last(where: { $0.assignedRoute == nil })?.id else { return nil }
        guard engine.applyNow(OpenRouteCommand(
            airline: player, origin: from, destination: to,
            dailyRoundTrips: 2, ticketPrice: fare)) == .applied else { return nil }
        let route = engine.state.routes.values.first {
            $0.airline == player && $0.sameMarket(origin: from, destination: to)
        }!.id
        _ = engine.applyNow(AssignAircraftToRouteCommand(
            airline: player, route: route, aircraftID: aircraft))
        return route
    }

    // MARK: The cast (BUG-043)

    @Test("At least half the cast is based in the player's region")
    func castIsFoundedNearThePlayer() throws {
        let (engine, _) = try world(competitors: 5)
        let catalog = engine.catalog
        let playerRegion = catalog.airport("ARN")!.region
        let rivals = engine.state.airlines.values.filter { $0.kind == .ai }
        #expect(rivals.count == 5)
        let nearby = rivals.filter { catalog.airport($0.homeAirport)?.region == playerRegion }
        #expect(nearby.count >= 3, "only \(nearby.count) of 5 rivals share the player's region")
        // And the rest are still the world's biggest markets.
        let far = rivals.filter { catalog.airport($0.homeAirport)?.region != playerRegion }
        #expect(far.contains { $0.homeAirport == "HND" })
        #expect(Set(rivals.map(\.homeAirport)).count == 5)
        #expect(rivals.allSatisfy { $0.homeAirport != "ARN" })
    }

    // MARK: The AI grows a network, not a single pinned route (BUG-042)

    @Test("A rival whose route is fully crewed opens a second market")
    func rivalOpensASecondMarket() throws {
        let (engine, _) = try world(competitors: 5)
        engine.advance(ticks: Fixtures.ticksPerDay * 120)
        let rivals = engine.state.airlines.values.filter { $0.kind == .ai && $0.status == .active }
        let multiRoute = rivals.filter { engine.state.routes(of: $0.id).count >= 2 }
        #expect(multiRoute.count >= 3,
                "only \(multiRoute.count) rivals fly more than one route after 120 days")
        // And no route carries aircraft it cannot use: the scheduler's own
        // capacity arithmetic bounds the assignment.
        let ops = engine.catalog.tuning.ops
        for route in engine.state.routes.values
        where engine.state.airlines[route.airline]?.kind == .ai {
            let assigned = route.assignedAircraft.compactMap { engine.state.aircraft[$0] }
            guard let first = assigned.first,
                  let spec = engine.catalog.aircraftType(first.typeCode) else { continue }
            let perAircraft = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
                distanceKm: route.distanceKm, spec: spec, ops: ops)
            guard perAircraft > 0 else { continue }
            let needed = (route.dailyRoundTrips + perAircraft - 1) / perAircraft
            #expect(assigned.count <= needed + 1,
                    "\(route.origin.raw)-\(route.destination.raw): \(assigned.count) aircraft on a route that can use \(needed)")
        }
    }

    // MARK: The market-move record

    @Test("Opening and closing a route records who entered and left the pair")
    func marketMovesAreRecorded() throws {
        let (engine, player) = try world(competitors: 0)
        let before = engine.state.world.marketMoves.count
        let route = try #require(openAndFly(engine, player: player, from: "ARN", to: "LHR",
                                            fare: Money.dollars(150)))
        let entered = try #require(engine.state.world.marketMoves.last)
        #expect(engine.state.world.marketMoves.count == before + 1)
        #expect(entered.kind == .entered)
        #expect(entered.airline == player)
        #expect(entered.market == Route.market("ARN", "LHR"))
        _ = engine.applyNow(CloseRouteCommand(airline: player, route: route))
        let left = try #require(engine.state.world.marketMoves.last)
        #expect(left.kind == .left)
        #expect(left.market == Route.market("ARN", "LHR"))
    }

    @Test("The record is bounded")
    func marketMovesAreBounded() {
        var world = WorldState()
        for index in 0..<(WorldState.marketMoveCapacity * 3) {
            world.recordMarketMove(MarketMove(
                at: SimTime(rawMinutes: Int64(index)), airline: AirlineID(raw: 1),
                origin: "ARN", destination: "LHR", kind: .entered))
        }
        #expect(world.marketMoves.count == WorldState.marketMoveCapacity)
        #expect(world.marketMoves.first?.at.rawMinutes
                == Int64(WorldState.marketMoveCapacity * 2))
    }

    @Test("A collapse records every market the airline left")
    func collapseRecordsExits() throws {
        // Drive a rival under with a hostile world: no cash, a leased
        // aircraft and a route it cannot pay for.
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(seed: 7),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Player Air", kind: .player, homeAirport: "ARN",
            startingCash: Money.dollars(150_000_000)))
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Doomed", kind: .ai, homeAirport: "LHR",
            startingCash: Money.dollars(3_000_000),
            aiProfile: AIProfile(archetype: .expansionist)))
        let doomed = engine.state.airlines.values.first { $0.name == "Doomed" }!.id
        _ = engine.applyNow(LeaseAircraftCommand(lessee: doomed, type: "PA184", termMonths: 60))
        engine.advance(ticks: Fixtures.ticksPerDay * 400)
        let airline = try #require(engine.state.airlines[doomed])
        guard airline.status == .collapsed else {
            // The fixture did not fail this seed; the claim is only about
            // what a collapse records, so say so rather than pass silently.
            Issue.record("Doomed did not collapse in 400 days — fixture needs revisiting")
            return
        }
        let exits = engine.state.world.marketMoves.filter {
            $0.airline == doomed && $0.kind == .left
        }
        let entries = engine.state.world.marketMoves.filter {
            $0.airline == doomed && $0.kind == .entered
        }
        #expect(!entries.isEmpty)
        #expect(Set(exits.map(\.market)) == Set(entries.map(\.market)))
        #expect(engine.state.routes(of: doomed).isEmpty)
    }

    // MARK: The events, and who may see them

    @Test("A rival entering your pair reaches your feed; entering elsewhere does not")
    func marketEntryIsNewsOnlyOnYourPair() throws {
        let (engine, player) = try world(competitors: 0)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Rival", kind: .ai, homeAirport: "LHR",
            startingCash: Money.dollars(100_000_000),
            aiProfile: AIProfile(archetype: .lowCost)))
        let rival = engine.state.airlines.values.first { $0.name == "Rival" }!.id
        _ = try #require(openAndFly(engine, player: player, from: "ARN", to: "LHR",
                                    fare: Money.dollars(150)))

        _ = engine.applyNow(OpenRouteCommand(airline: rival, origin: "LHR", destination: "ARN",
                                             dailyRoundTrips: 2, ticketPrice: Money.dollars(99)))
        let onMine = try #require(engine.state.eventLog.recent.last {
            if case .marketEntered(let a, _, _) = $0.kind { return a == rival }
            return false
        })
        #expect(engine.state.isFeedEvent(onMine, for: player))

        _ = engine.applyNow(OpenRouteCommand(airline: rival, origin: "LHR", destination: "CDG",
                                             dailyRoundTrips: 2, ticketPrice: Money.dollars(80)))
        let elsewhere = try #require(engine.state.eventLog.recent.last {
            if case .marketEntered(_, _, let to) = $0.kind { return to == "CDG" }
            return false
        })
        #expect(!engine.state.isFeedEvent(elsewhere, for: player))
        // The old route event on the same pair still does not leak: this is
        // additive to BUG-004's filter, not a hole in it.
        let opened = try #require(engine.state.eventLog.recent.last {
            if case .routeOpened(_, _, let to) = $0.kind { return to == "CDG" }
            return false
        })
        #expect(!engine.state.isFeedEvent(opened, for: player))
    }

    // MARK: The route model

    @Test("An uncontested route stands alone")
    func aloneWhenNobodyElseFlies() throws {
        let (engine, player) = try world(competitors: 0)
        let route = try #require(openAndFly(engine, player: player, from: "ARN", to: "OSL",
                                            fare: Money.dollars(120)))
        engine.advance(ticks: Fixtures.ticksPerDay * 3)
        let model = try #require(engine.state.marketCompetition(for: route,
                                                                catalog: engine.catalog))
        #expect(model.standing == .alone)
        #expect(model.rivals.isEmpty)
        #expect(model.playerShareToday == nil)
        #expect(model.edge == nil)
    }

    @Test("Undercutting a rival on its own pair: rivals, share, standing and the edge agree with the demand engine")
    func invadedMarketIsMeasured() throws {
        let (engine, player) = try world(competitors: 0)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Rival", kind: .ai, homeAirport: "LHR",
            startingCash: Money.dollars(100_000_000),
            aiProfile: AIProfile(archetype: .premium)))
        let rival = engine.state.airlines.values.first { $0.name == "Rival" }!.id
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: rival, type: "MR180", ageYears: 3))
        let theirs = engine.state.fleet(of: rival).first!.id
        let reference = DemandSystem.referenceFare(
            distanceKm: engine.catalog.distanceKm("LHR", "CDG")!,
            tuning: engine.catalog.tuning.demand)
        _ = engine.applyNow(OpenRouteCommand(
            airline: rival, origin: "LHR", destination: "CDG", dailyRoundTrips: 4,
            ticketPrice: Money(rounding: reference * 1.25)))
        let theirRoute = engine.state.routes(of: rival).first!.id
        _ = engine.applyNow(AssignAircraftToRouteCommand(airline: rival, route: theirRoute,
                                                         aircraftID: theirs))
        // Systems are on, but the rival must not answer during the test's
        // window: its decision slot is every seven days and the invasion is
        // measured after one.
        let mine = try #require(openAndFly(engine, player: player, from: "LHR", to: "CDG",
                                           fare: Money(rounding: reference * 0.88)))
        // The morning of entry: nothing flown, nothing allocated — too early,
        // not "losing at 0%" (run 113, KEY-42).
        let onEntry = try #require(engine.state.marketCompetition(for: mine, catalog: engine.catalog))
        #expect(onEntry.standing == .tooEarly)
        #expect(onEntry.rivals.count == 1)
        engine.advance(ticks: Fixtures.ticksPerDay * 2)

        let state = engine.state
        let model = try #require(state.marketCompetition(for: mine, catalog: engine.catalog))
        #expect(model.rivals.count == 1)
        let offer = try #require(model.rivals.first)
        #expect(offer.airline == rival)
        #expect(offer.isBasedOnPair)
        #expect(offer.fareRatioToPlayer > 1.3 && offer.fareRatioToPlayer < 1.5)

        // Share is the demand engine's allocation, restated.
        let my = state.routes[mine]!
        let their = state.routes[theirRoute]!
        let myDemand = my.demandOutboundToday + my.demandInboundToday
        let theirDemand = their.demandOutboundToday + their.demandInboundToday
        #expect(myDemand + theirDemand > 0)
        let share = try #require(model.playerShareToday)
        #expect(abs(share - Double(myDemand) / Double(myDemand + theirDemand)) < 1e-9)
        #expect(model.marketDemandToday == myDemand + theirDemand)
        #expect(model.evenShare == 0.5)
        #expect(model.standing != .alone && model.standing != .tooEarly)
        // The standing names the side of the split the share is on.
        switch model.standing {
        case .leading: #expect(share >= 0.5 * 1.15)
        case .trailing: #expect(share <= 0.5 * 0.85)
        case .even: #expect(share > 0.5 * 0.85 && share < 0.5 * 1.15)
        default: Issue.record("unexpected standing \(model.standing)")
        }
        // The edge is one of the engine's terms, and the fare term says the
        // player is the cheaper offer.
        let edge = try #require(model.edge)
        if case .fare(let ahead) = edge { #expect(ahead) }
        #expect(model.strongestRival == rival)

        // The summary sees the same route.
        let summary = try #require(state.competitionSummary(catalog: engine.catalog))
        #expect(summary.contestedRoutes == 1)
        #expect(summary.contested.first?.routeID == mine)
        #expect(summary.biggestRival?.airline == rival)
        #expect(summary.biggestRival?.sharedMarkets == 1)
    }

    // MARK: The summary and its headline

    @Test("A rival entering your pair is the headline; leaving it is the next; a quiet world says nothing")
    func headlineFollowsTheRecord() throws {
        let (engine, player) = try world(competitors: 0)
        let catalog = engine.catalog
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Rival", kind: .ai, homeAirport: "LHR",
            startingCash: Money.dollars(100_000_000),
            aiProfile: AIProfile(archetype: .lowCost)))
        let rival = engine.state.airlines.values.first { $0.name == "Rival" }!.id
        _ = try #require(openAndFly(engine, player: player, from: "ARN", to: "LHR",
                                    fare: Money.dollars(150)))
        engine.advance(ticks: Fixtures.ticksPerDay)
        var summary = try #require(engine.state.competitionSummary(catalog: catalog))
        #expect(summary.headline == nil)
        #expect(summary.recentMoves.isEmpty)

        _ = engine.applyNow(OpenRouteCommand(airline: rival, origin: "LHR", destination: "ARN",
                                             dailyRoundTrips: 2, ticketPrice: Money.dollars(99)))
        summary = try #require(engine.state.competitionSummary(catalog: catalog))
        guard case .rivalEnteredYourMarket(let move) = summary.headline else {
            Issue.record("expected an entry headline, got \(String(describing: summary.headline))")
            return
        }
        #expect(move.airline == rival)
        #expect(move.relevance == .onPlayerMarket)
        #expect(move.daysAgo == 0)
        #expect(summary.contestedRoutes == 1)

        let theirRoute = engine.state.routes(of: rival).first!.id
        _ = engine.applyNow(CloseRouteCommand(airline: rival, route: theirRoute))
        summary = try #require(engine.state.competitionSummary(catalog: catalog))
        // The most recent move on the pair is the exit, and it outranks the
        // older entry.
        guard case .rivalLeftYourMarket(let exit) = summary.headline else {
            Issue.record("expected an exit headline, got \(String(describing: summary.headline))")
            return
        }
        #expect(exit.kind == .left)
        #expect(summary.contestedRoutes == 0)

        // Thirty-one days on, the moves on the pair have aged out of the
        // window. The rival is alive and still building at London — the
        // player's airport — so what remains is presence, never the pair.
        engine.advance(ticks: Fixtures.ticksPerDay * 31)
        summary = try #require(engine.state.competitionSummary(catalog: catalog))
        #expect(!summary.recentMoves.contains { $0.relevance == .onPlayerMarket })
        switch summary.headline {
        case .rivalEnteredYourMarket, .rivalLeftYourMarket, .trailing, .fighting, .leading:
            Issue.record("a pair-level headline survived the window: \(String(describing: summary.headline))")
        case .rivalExpanding, nil:
            break
        }
    }

    @Test("Trailing on a contested route is the headline when nothing moved")
    func trailingHeadline() throws {
        let (engine, player) = try world(competitors: 0)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Rival", kind: .ai, homeAirport: "LHR",
            startingCash: Money.dollars(100_000_000),
            aiProfile: AIProfile(archetype: .lowCost)))
        let rival = engine.state.airlines.values.first { $0.name == "Rival" }!.id
        for _ in 0..<3 {
            _ = engine.applyNow(BuyUsedAircraftCommand(buyer: rival, type: "MR180", ageYears: 3))
        }
        let reference = DemandSystem.referenceFare(
            distanceKm: engine.catalog.distanceKm("LHR", "CDG")!,
            tuning: engine.catalog.tuning.demand)
        _ = engine.applyNow(OpenRouteCommand(
            airline: rival, origin: "LHR", destination: "CDG", dailyRoundTrips: 8,
            ticketPrice: Money(rounding: reference * 0.8)))
        let theirRoute = engine.state.routes(of: rival).first!.id
        for aircraft in engine.state.fleet(of: rival) {
            _ = engine.applyNow(AssignAircraftToRouteCommand(
                airline: rival, route: theirRoute, aircraftID: aircraft.id))
        }
        // The player: pricier and thinner. Trailing is the only honest read.
        _ = try #require(openAndFly(engine, player: player, from: "LHR", to: "CDG",
                                    fare: Money(rounding: reference * 1.2)))
        engine.advance(ticks: Fixtures.ticksPerDay * 32)   // the entry ages out
        let summary = try #require(engine.state.competitionSummary(catalog: engine.catalog))
        #expect(summary.trailingRoutes == 1)
        #expect(summary.headline == .trailing(routes: 1, contested: 1))
        let model = try #require(summary.contested.first)
        #expect(model.standing == .trailing)
        #expect(model.edge?.playerAhead == false)
    }

    // MARK: Persistence

    @Test("The record survives a save and a v11 save opens with an empty one")
    func marketMovesPersistAndMigrate() throws {
        let (engine, player) = try world(competitors: 2)
        _ = try #require(openAndFly(engine, player: player, from: "ARN", to: "LHR",
                                    fare: Money.dollars(150)))
        engine.advance(ticks: Fixtures.ticksPerDay * 10)
        let state = engine.state
        #expect(!state.world.marketMoves.isEmpty)

        let codec = JSONSaveCodec()
        let restored = try codec.decode(try codec.encode(state))
        #expect(restored.world.marketMoves == state.world.marketMoves)

        // A v11 payload: today's shape without the key.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var tree = try JSONSerialization.jsonObject(with: encoder.encode(state)) as! [String: Any]
        var world = tree["world"] as! [String: Any]
        world["marketMoves"] = nil
        tree["world"] = world
        let payload = try JSONSerialization.data(withJSONObject: tree)
        let envelope = SaveEnvelope(formatVersion: 11, contentVersion: "0",
                                    savedAtTick: 0, payload: payload)
        let data = try encoder.encode(envelope)
        let migrated = try codec.decode(data)
        #expect(migrated.world.marketMoves.isEmpty)
        #expect(migrated.routes.count == state.routes.count)
        #expect(migrated.clock.tickCount == state.clock.tickCount)
        #expect(MigrationChain.standard.minimumSupportedVersion == 9)
    }
}
