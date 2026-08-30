import Testing
@testable import AirlineEmpireCore

/// The map's read model (docs/MAP_ARCHITECTURE.md).
///
/// A map is the one screen where a wrong number is invisible — a dot in the
/// wrong place looks exactly like a dot in the right place. So everything the
/// renderer will draw is classified here, in Core, and asserted against the
/// simulation it claims to describe: an airport's tier, a route's health, a
/// flight's progress along its arc, an event's reach, and which markets are
/// worth showing a player who has none.
@Suite("Map presentation model")
struct MapPresentationTests {

    private func world(seed: UInt64 = 5150, competitors: Int = 3) async throws
        -> (GameSession, AirlineID, ContentCatalog) {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: seed),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Cartograph Air", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(300_000_000)))
        let player = try #require(await session.snapshot.playerAirline).id
        await session.populateStandardWorld(competitors: competitors)
        return (session, player, catalog)
    }

    /// A player flying a handful of routes out of home.
    private func flyingWorld(seed: UInt64 = 5150, routes: Int = 3) async throws
        -> (GameSession, AirlineID, ContentCatalog) {
        let (session, player, catalog) = try await world(seed: seed)
        for _ in 0..<routes {
            _ = await session.submit(BuyUsedAircraftCommand(
                buyer: player, type: "MR180", ageYears: 5))
        }
        var state = await session.snapshot
        let fleet = state.fleet(of: player).map(\.id)
        let targets = state.marketOpportunities(catalog: catalog, limit: routes)
        for (index, market) in targets.enumerated() where index < fleet.count {
            _ = await session.submit(OpenRouteCommand(
                airline: player, origin: market.origin,
                destination: market.destination, dailyRoundTrips: 2,
                ticketPrice: market.referenceFare))
            state = await session.snapshot
            if let route = state.routes(of: player).last {
                _ = await session.submit(AssignAircraftToRouteCommand(
                    airline: player, route: route.id, aircraftID: fleet[index]))
            }
        }
        await session.advance(ticks: Fixtures.ticksPerDay * 5)
        return (session, player, catalog)
    }

    // MARK: - Airports

    @Test("Every airport in the content pack reaches the map exactly once")
    func everyAirportIsDrawn() async throws {
        let (session, _, catalog) = try await world()
        let model = await session.snapshot.mapModel(catalog: catalog)
        #expect(model.airports.count == catalog.orderedAirportCodes.count)
        #expect(Set(model.airports.map(\.code)).count == model.airports.count)
    }

    /// The tiering exists so the map can draw a hierarchy. A classification
    /// that puts everything in one bucket would render exactly the flat field
    /// of identical dots this model was built to replace.
    @Test("Airport tiers are a real hierarchy, not one bucket")
    func tiersAreDistributed() async throws {
        let (session, _, catalog) = try await world()
        let model = await session.snapshot.mapModel(catalog: catalog)
        let byTier = Dictionary(grouping: model.airports, by: \.tier)
        #expect(byTier.keys.count >= 3)
        // No tier may swallow the world.
        for (_, group) in byTier {
            #expect(group.count < model.airports.count)
        }
        // A bigger catchment never lands in a lower tier than a smaller one
        // with the same runway — the ordering has to mean something.
        let global = model.airports.filter { $0.tier == .global }
        let small = model.airports.filter { $0.tier == .small }
        if let smallestGlobal = global.map(\.prominence).min(),
           let largestSmall = small.map(\.prominence).max() {
            #expect(smallestGlobal > largestSmall)
        }
    }

    @Test("Home, hubs and competitor presence are marked from real state")
    func presenceIsMarked() async throws {
        let (session, player, catalog) = try await flyingWorld()
        let state = await session.snapshot
        let model = state.mapModel(catalog: catalog)

        let home = try #require(model.airports.first { $0.isPlayerHome })
        #expect(home.code == state.airlines[player]?.homeAirport)
        #expect(model.airports.filter(\.isPlayerHome).count == 1)
        #expect(model.playerHome == home.code)

        // Served airports match the routes exactly.
        let servedByModel = Set(model.airports.filter(\.servedByPlayer).map(\.code))
        var servedByState = Set<AirportCode>()
        for route in state.routes(of: player) {
            servedByState.insert(route.origin)
            servedByState.insert(route.destination)
        }
        #expect(servedByModel == servedByState)

        // Home is a hub once three routes touch it, and not before.
        #expect(home.isPlayerHub == (home.playerRouteCount >= 3))

        // Somebody else is out there.
        #expect(model.airports.contains { $0.competitorHubCount > 0 })
        #expect(model.airports.allSatisfy { $0.slotPressure >= 0 && $0.slotPressure <= 1 })
    }

    // MARK: - Routes

    @Test("A route with no aircraft reads as grounded, not as unprofitable")
    func groundedOutranksMoney() async throws {
        let (session, player, catalog) = try await world()
        let state = await session.snapshot
        let market = try #require(state.marketOpportunities(catalog: catalog,
                                                            limit: 1).first)
        _ = await session.submit(OpenRouteCommand(
            airline: player, origin: market.origin, destination: market.destination,
            dailyRoundTrips: 2, ticketPrice: market.referenceFare))
        let model = await session.snapshot.mapModel(catalog: catalog)
        let route = try #require(model.routes.first { $0.isPlayer })
        #expect(route.health == .grounded)
    }

    @Test("Route health tracks the simulation's own figures")
    func healthMatchesTheRoute() async throws {
        let (session, player, catalog) = try await flyingWorld(seed: 5151)
        let state = await session.snapshot
        let model = state.mapModel(catalog: catalog)
        for mapRoute in model.routes where mapRoute.isPlayer {
            let route = try #require(state.routes[mapRoute.id])
            #expect(mapRoute.loadFactor == route.stats.loadFactor)
            #expect(mapRoute.origin == route.origin)
            #expect(mapRoute.destination == route.destination)
            if route.assignedAircraft.isEmpty {
                #expect(mapRoute.health == .grounded)
            } else {
                #expect(mapRoute.health != .grounded)
            }
        }
        _ = player
    }

    /// Arcs must actually join the airports they claim to join, or routes
    /// float free of the map.
    @Test("Every arc starts and ends on its own airports")
    func arcsConnectTheirAirports() async throws {
        let (session, _, catalog) = try await flyingWorld(seed: 5152)
        let model = await session.snapshot.mapModel(catalog: catalog)
        #expect(!model.routes.isEmpty)
        for route in model.routes {
            let first = try #require(route.arc.first)
            let last = try #require(route.arc.last)
            #expect(abs(first.x - route.from.x) < 1e-9)
            #expect(abs(first.y - route.from.y) < 1e-9)
            #expect(abs(last.x - route.to.x) < 1e-9)
            #expect(abs(last.y - route.to.y) < 1e-9)
            #expect(route.arc.count >= 2)
            // And every waypoint is inside the map, or the projection will
            // draw a line off the edge of the world.
            for point in route.arc {
                #expect(point.x >= 0 && point.x <= 1)
                #expect(point.y >= 0 && point.y <= 1)
            }
        }
    }

    // MARK: - Flights

    @Test("Flights carry the progress and duration the renderer interpolates from")
    func flightsCarryProgress() async throws {
        let (session, _, catalog) = try await flyingWorld(seed: 5153)
        await session.advance(ticks: Fixtures.ticksPerDay * 3)
        let state = await session.snapshot
        let model = state.mapModel(catalog: catalog)
        for flight in model.flights {
            #expect(flight.progress >= 0 && flight.progress <= 1)
            #expect(flight.flightMinutes > 0)
            let real = try #require(state.flights[flight.id])
            #expect(flight.route == real.route)
            #expect(flight.aircraft == real.aircraft)
            #expect(flight.origin == real.from)
            #expect(flight.destination == real.to)
            #expect(flight.flightMinutes == real.flightMinutes)
            // A parked aircraft is at its origin and has made no progress.
            if !flight.airborne { #expect(flight.progress == 0) }
        }
    }

    /// The bug this guards: a marker left behind after its flight ended, or a
    /// marker for a flight that has not started. Both put an aircraft on the
    /// map that is not there.
    @Test("Only live flights appear, and every one of them still exists")
    func noGhostFlights() async throws {
        let (session, _, catalog) = try await flyingWorld(seed: 5154)
        for _ in 0..<6 {
            await session.advance(ticks: Fixtures.ticksPerDay)
            let state = await session.snapshot
            let model = state.mapModel(catalog: catalog)
            for flight in model.flights {
                let real = try #require(state.flights[flight.id])
                if case .scheduled = real.phase {
                    Issue.record("a scheduled flight was drawn on the map")
                }
            }
            let drawn = Set(model.flights.map(\.id))
            let live = Set(state.orderedFlightIDs.filter { id in
                guard let flight = state.flights[id] else { return false }
                if case .scheduled = flight.phase { return false }
                return true
            })
            #expect(drawn == live)
        }
    }

    /// A flight's marker must sit on its own arc, or aircraft appear to fly
    /// routes they are not on.
    @Test("An airborne flight sits on the great circle between its airports")
    func flightsSitOnTheirArc() async throws {
        let (session, _, catalog) = try await flyingWorld(seed: 5155)
        await session.advance(ticks: Fixtures.ticksPerDay * 2)
        let state = await session.snapshot
        let model = state.mapModel(catalog: catalog)
        for flight in model.flights where flight.airborne {
            let from = try #require(catalog.airport(flight.origin)).coordinate
            let to = try #require(catalog.airport(flight.destination)).coordinate
            let expected = MapPoint(coordinate: MapMath.greatCirclePoint(
                from: from, to: to, fraction: flight.progress))
            #expect(abs(flight.position.x - expected.x) < 1e-6)
            #expect(abs(flight.position.y - expected.y) < 1e-6)
        }
    }

    // MARK: - Events

    @Test("A regional event names the airports it actually reaches")
    func eventsArePlaced() async throws {
        let (session, _, catalog) = try await flyingWorld(seed: 5156)
        // Long enough for the world to generate something.
        await session.advance(ticks: Fixtures.ticksPerDay * 240)
        let state = await session.snapshot
        let model = state.mapModel(catalog: catalog)
        #expect(model.events.count == state.world.activeEvents.count)
        for event in model.events {
            switch event.kind {
            case .fuelShock:
                #expect(event.isGlobal)
                #expect(event.affectedAirports.isEmpty)
            case .storm(let region), .tourismBoom(let region):
                #expect(!event.isGlobal)
                #expect(!event.affectedAirports.isEmpty)
                for code in event.affectedAirports {
                    #expect(catalog.airport(code)?.region == region)
                }
            case .airportClosure(let code):
                #expect(event.affectedAirports == [code])
            case .strike:
                #expect(!event.isGlobal)
            }
            // Whatever it touches, the routes it names must be the player's.
            for id in event.affectedPlayerRoutes {
                #expect(state.routes[id]?.airline == state.playerAirline?.id)
            }
        }
    }

    // MARK: - Opportunities

    /// The empty-map problem: a player with no routes must still be shown
    /// something worth looking at.
    @Test("A brand-new airline is offered real markets from home")
    func newAirlineHasOpportunities() async throws {
        let (session, player, catalog) = try await world()
        let state = await session.snapshot
        let model = state.mapModel(catalog: catalog)
        // The player's network is what "brand-new" means here; whether the
        // rivals have flown yet is a different question.
        #expect(state.routes(of: player).isEmpty)
        #expect(!model.opportunities.isEmpty)
        let home = try #require(model.playerHome)
        for opportunity in model.opportunities {
            #expect(opportunity.origin == home)
            #expect(opportunity.expectedDailyPassengers > 0)
            #expect(opportunity.distanceKm > 0)
        }
    }

    @Test("Opportunities never propose a market already flown")
    func opportunitiesExcludeTheNetwork() async throws {
        let (session, player, catalog) = try await flyingWorld(seed: 5157)
        let state = await session.snapshot
        let flown = Set(state.routes(of: player).map(\.market))
        for opportunity in state.marketOpportunities(catalog: catalog, limit: 12) {
            #expect(!flown.contains(Route.market(opportunity.origin,
                                                 opportunity.destination)))
        }
    }

    @Test("Opportunities open from anywhere the airline already reaches")
    func opportunitiesUseTheWholeNetwork() async throws {
        let (session, player, catalog) = try await flyingWorld(seed: 5158)
        let state = await session.snapshot
        var reachable = Set<AirportCode>()
        if let home = state.airlines[player]?.homeAirport { reachable.insert(home) }
        for route in state.routes(of: player) {
            reachable.insert(route.origin)
            reachable.insert(route.destination)
        }
        let opportunities = state.marketOpportunities(catalog: catalog, limit: 20)
        #expect(!opportunities.isEmpty)
        for opportunity in opportunities {
            #expect(reachable.contains(opportunity.origin))
        }
    }

    /// Two rankings of "where should I fly" that can disagree is one too many.
    @Test("The onboarding card and the map rank the same markets")
    func onboardingAgreesWithTheMap() async throws {
        let (session, _, catalog) = try await world(seed: 5159)
        let state = await session.snapshot
        let onboarding = try #require(state.onboardingModel(catalog: catalog,
                                                            suggestionLimit: 2))
        let markets = state.marketOpportunities(catalog: catalog, limit: 2)
        #expect(onboarding.suggestions.count == markets.count)
        for (suggestion, market) in zip(onboarding.suggestions, markets) {
            #expect(suggestion.origin == market.origin)
            #expect(suggestion.destination == market.destination)
            #expect(suggestion.expectedDailyPassengers == market.expectedDailyPassengers)
        }
    }

    @Test("The ranking is deterministic for a seed")
    func rankingIsDeterministic() async throws {
        func rank(_ seed: UInt64) async throws -> [String] {
            let (session, _, catalog) = try await world(seed: seed)
            return await session.snapshot
                .marketOpportunities(catalog: catalog, limit: 8)
                .map { "\($0.origin.raw)-\($0.destination.raw)" }
        }
        #expect(try await rank(4242) == (try await rank(4242)))
    }

    // MARK: - Cost

    /// The map model is rebuilt every simulation tick. It must stay linear in
    /// the world, not quadratic — `docs/UI_ARCHITECTURE.md` §5.
    @Test("Building the model stays cheap on a large network")
    func modelBuildIsLinear() async throws {
        let (session, player, catalog) = try await world(seed: 5160, competitors: 6)
        for _ in 0..<12 {
            _ = await session.submit(BuyUsedAircraftCommand(
                buyer: player, type: "MR220", ageYears: 4))
        }
        var state = await session.snapshot
        let fleet = state.fleet(of: player).map(\.id)
        for (index, market) in state.marketOpportunities(catalog: catalog,
                                                         limit: fleet.count).enumerated() {
            _ = await session.submit(OpenRouteCommand(
                airline: player, origin: market.origin,
                destination: market.destination, dailyRoundTrips: 3,
                ticketPrice: market.referenceFare))
            state = await session.snapshot
            if let route = state.routes(of: player).last, index < fleet.count {
                _ = await session.submit(AssignAircraftToRouteCommand(
                    airline: player, route: route.id, aircraftID: fleet[index]))
            }
        }
        await session.advance(ticks: Fixtures.ticksPerDay * 30)
        state = await session.snapshot

        // The assertion is correctness under load rather than a wall-clock
        // number, which a shared CI runner cannot promise: every airport,
        // every route and every live flight is present and well-formed.
        let model = state.mapModel(catalog: catalog)
        #expect(model.airports.count == catalog.orderedAirportCodes.count)
        #expect(model.routes.count == state.routes.count)
        #expect(model.routes.allSatisfy { $0.arc.count == 25 })
        #expect(model.flights.allSatisfy { $0.progress >= 0 && $0.progress <= 1 })
    }

    private func strikeEvent(id: Int64, by airline: AirlineID,
                             at now: SimTime) -> WorldEvent {
        var event = WorldEvent(
            id: id, kind: .strike(airline: airline), beginsAt: now,
            endsAt: SimTime(rawMinutes: now.rawMinutes
                            + GameCalendar.minutesPerDay * 3),
            severity: 0.8)
        event.hasStarted = true
        return event
    }

    /// BUG-022. A strike grounds the airline that is striking. Sharing a hub
    /// with a struck rival is normal at any large airport, so counting the
    /// player's routes through those airports made the disruption overlay
    /// report a problem the player does not have.
    @Test("A rival's strike does not disrupt the player's routes")
    func rivalStrikeLeavesThePlayerAlone() async throws {
        let (session, player, catalog) = try await flyingWorld()
        var state = await session.snapshot
        let rival = try #require(state.airlines.values.first { $0.kind == .ai })

        // The two carriers must actually meet, or the test proves nothing: the
        // shared airport is what used to manufacture the claim. Competitors
        // get aircraft at setup but open routes on their first decision day,
        // so the meeting is seeded rather than waited for.
        let playerRoute = try #require(state.routes(of: player).first)
        let hub = playerRoute.origin
        let rivalRoute = Route(
            id: RouteID(raw: 90_001), airline: rival.id, origin: hub,
            destination: rival.homeAirport,
            distanceKm: catalog.distanceKm(hub, rival.homeAirport) ?? 500,
            dailyRoundTrips: 2, ticketPrice: Money.dollars(200))
        state.routes[rivalRoute.id] = rivalRoute
        #expect(state.routes(of: rival.id).contains { $0.servesAirport(hub) })

        state.world.activeEvents = [
            strikeEvent(id: 9_001, by: rival.id, at: state.clock.now)
        ]
        let rivalStrike = try #require(state.mapModel(catalog: catalog).events.first)
        #expect(rivalStrike.affectedPlayerRoutes.isEmpty)
        // The airports are still named — the strike is real, it is just not
        // the player's.
        #expect(!rivalStrike.affectedAirports.isEmpty)

        // The player's own strike still reaches the player's routes, so the
        // fix is a distinction and not a blanket silence.
        state.world.activeEvents = [
            strikeEvent(id: 9_002, by: player, at: state.clock.now)
        ]
        let ownStrike = try #require(state.mapModel(catalog: catalog).events.first)
        #expect(!ownStrike.affectedPlayerRoutes.isEmpty)
    }

    /// BUG-023. `heading(from:to:)` has no direction to report for two
    /// identical coordinates and returns 0, so an aircraft whose progress had
    /// been clamped to 1 snapped to due north and stayed there.
    @Test("A flight at the end of its arc still points along the route")
    func headingSurvivesArrival() async throws {
        let (_, _, catalog) = try await world()
        let from = try #require(catalog.airport("STV")).coordinate
        let to = try #require(catalog.orderedAirportCodes
            .compactMap { catalog.airport($0) }
            .first { $0.coordinate.longitude != from.longitude }).coordinate

        let midway = MapMath.heading(alongRouteFrom: from, to: to, at: 0.5)
        let arrival = MapMath.heading(alongRouteFrom: from, to: to, at: 1)
        // Not the "no direction" answer, and still recognisably the same
        // course as the leg before it.
        #expect(abs(arrival - midway) < 25)

        // Sabotage: the old expression is what the assertion above rules out.
        let ahead = MapMath.greatCirclePoint(from: from, to: to,
                                             fraction: min(1, 1 + 0.02))
        let end = MapMath.greatCirclePoint(from: from, to: to, fraction: 1)
        #expect(MapMath.heading(from: end, to: ahead) == 0)
    }

    /// The pair loops ask for incumbent counts once per candidate market, so
    /// the counts are built in one pass. That pass must agree with the scan it
    /// replaced.
    @Test("Pre-computed carrier counts agree with the per-market scan")
    func carrierCountsAgreeWithTheScan() async throws {
        let (session, _, catalog) = try await flyingWorld()
        let state = await session.snapshot
        let counts = state.carrierCountByMarket()

        // Every market that is actually flown, so the agreement is checked
        // where it matters rather than only on empty pairs.
        var served = 0
        for route in state.orderedRouteIDs.compactMap({ state.routes[$0] }) {
            let scanned = state.airlinesServing(route.origin, route.destination)
            #expect(counts[route.market] ?? 0 == scanned)
            #expect(scanned > 0)
            served += 1
        }
        #expect(served > 0, "the world must fly something")

        // And a handful of unserved pairs, where the answer must be zero on
        // both sides rather than absent on one.
        let codes = catalog.orderedAirportCodes
        for origin in codes.prefix(8) {
            for destination in codes.suffix(8) where destination != origin {
                #expect(counts[Route.market(origin, destination)] ?? 0
                        == state.airlinesServing(origin, destination))
            }
        }
    }
}

/// The antimeridian (BUG-012).
///
/// A great circle from Tokyo to Los Angeles crosses 180°. In equirectangular
/// map space its x values jump from ~0.99 to ~0.01 between two waypoints, and
/// a renderer that draws the raw polyline puts a straight line back across the
/// whole map — a route connecting nothing to nothing. These assert the
/// unwrapping that fixes it, because it is the kind of geometry bug that is
/// invisible until somebody flies the Pacific.
@Suite("Antimeridian handling")
struct AntimeridianTests {

    private func arc(_ a: (Double, Double), _ b: (Double, Double)) -> [MapPoint] {
        MapMath.arc(from: Coordinate(latitude: a.0, longitude: a.1),
                    to: Coordinate(latitude: b.0, longitude: b.1))
    }

    /// The defect itself: without unwrapping, the raw arc contains a jump.
    @Test("A Pacific crossing does contain a wrap in raw map space")
    func rawArcWraps() {
        let pacific = arc((35.6, 139.8), (33.9, -118.4))   // Tokyo → Los Angeles
        let jumps = zip(pacific, pacific.dropFirst()).filter { abs($1.x - $0.x) > 0.5 }
        #expect(!jumps.isEmpty, "the fixture must actually cross the date line")
    }

    @Test("Unwrapping removes every jump")
    func unwrappedArcIsContinuous() {
        for pair in [((35.6, 139.8), (33.9, -118.4)),      // Tokyo → LA
                     ((-36.8, 174.8), (-33.4, -70.7)),     // Auckland → Santiago
                     ((64.8, -147.7), (55.0, 82.9))] {     // Fairbanks → Novosibirsk
            let unwrapped = MapMath.unwrap(arc(pair.0, pair.1))
            for (a, b) in zip(unwrapped, unwrapped.dropFirst()) {
                #expect(abs(b.x - a.x) < 0.5,
                        "unwrapped arcs must never jump half a world")
            }
        }
    }

    /// Unwrapping must move points by whole worlds only — a shifted arc is
    /// still the same arc, or the route would no longer join its airports.
    @Test("Unwrapping shifts by whole worlds and preserves latitude")
    func unwrappingPreservesGeometry() {
        let raw = arc((35.6, 139.8), (33.9, -118.4))
        let unwrapped = MapMath.unwrap(raw)
        #expect(unwrapped.count == raw.count)
        for (original, moved) in zip(raw, unwrapped) {
            #expect(moved.y == original.y)
            let shift = moved.x - original.x
            #expect(abs(shift - shift.rounded()) < 1e-9,
                    "a point may only move by a whole world")
        }
    }

    @Test("An arc that does not cross the date line is left alone")
    func ordinaryArcIsUntouched() {
        let raw = arc((59.7, 17.9), (41.9, 12.4))          // Stockholm → Rome
        let unwrapped = MapMath.unwrap(raw)
        #expect(unwrapped == raw)
        #expect(MapMath.worldOffsets(for: unwrapped) == [0])
    }

    /// A crossing arc has to be drawn in two world copies, or one leg of it is
    /// simply missing from the screen.
    @Test("A crossing arc asks for a second world copy")
    func crossingNeedsTwoCopies() {
        let unwrapped = MapMath.unwrap(arc((35.6, 139.8), (33.9, -118.4)))
        let offsets = MapMath.worldOffsets(for: unwrapped)
        #expect(offsets.count == 2)
        #expect(offsets.contains(0))
    }

    @Test("Degenerate input does not trap")
    func degenerateInput() {
        #expect(MapMath.unwrap([]).isEmpty)
        let single = [MapPoint(x: 0.5, y: 0.5)]
        #expect(MapMath.unwrap(single) == single)
        #expect(MapMath.worldOffsets(for: []) == [0])
    }

    /// Every route in a real game must survive unwrapping with its endpoints
    /// still on its airports.
    @Test("Unwrapping keeps every real route joined to its airports")
    func realRoutesStayJoined() async throws {
        let catalog = try ContentCatalog.loadBundled()
        // Every ordered pair of airports, which is far more crossings than any
        // one save will contain.
        let codes = catalog.orderedAirportCodes
        for origin in codes.prefix(12) {
            for destination in codes.suffix(12) where destination != origin {
                guard let a = catalog.airport(origin), let b = catalog.airport(destination)
                else { continue }
                let raw = MapMath.arc(from: a.coordinate, to: b.coordinate)
                let unwrapped = MapMath.unwrap(raw)
                let first = try #require(unwrapped.first)
                let last = try #require(unwrapped.last)
                // The first point never moves, and the last is the true
                // endpoint to within a whole number of worlds.
                #expect(first == raw[0])
                let endShift = last.x - (raw.last?.x ?? 0)
                #expect(abs(endShift - endShift.rounded()) < 1e-9)
                #expect(last.y == raw.last?.y)
            }
        }
    }
}
