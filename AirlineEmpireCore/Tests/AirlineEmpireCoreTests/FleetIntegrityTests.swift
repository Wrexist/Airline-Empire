import Testing
@testable import AirlineEmpireCore

/// Adversarial fleet audit (MASTER PROMPT 5 §46).
///
/// §46 lists a dozen ways the fleet can go wrong — an aircraft on two routes,
/// a stale assignment after load, a sold aircraft still shown. Most of them
/// are one underlying fault: **assignment is stored twice.** `Aircraft` holds
/// `assignedRoute` and `Route` holds `assignedAircraft`, and every command
/// that touches either has to update both.
///
/// `GameState`'s integrity checks catch a *dangling* reference — an aircraft
/// pointing at a route that no longer exists. They do not catch the two sides
/// both existing and disagreeing, which is the failure that would show the
/// player a different answer on the Fleet board than on the Route board with
/// nothing obviously broken anywhere.
///
/// So these drive real churn — assign, unassign, close, sell, return, and a
/// save/load in the middle — and assert the invariant in both directions after
/// each step, rather than testing any one command in isolation.
@Suite("Fleet integrity under churn")
struct FleetIntegrityTests {

    /// Every aircraft's route agrees with that route's aircraft list, and
    /// vice versa. Returns a description of the first disagreement.
    private func assignmentDisagreement(in state: GameState) -> String? {
        for id in state.orderedAircraftIDs {
            guard let aircraft = state.aircraft[id] else { continue }
            guard let routeID = aircraft.assignedRoute else { continue }
            guard let route = state.routes[routeID] else {
                return "aircraft \(id.raw) points at route \(routeID.raw), which does not exist"
            }
            guard route.assignedAircraft.contains(id) else {
                return "aircraft \(id.raw) claims route \(routeID.raw), which does not list it"
            }
            guard route.airline == aircraft.owner else {
                return "aircraft \(id.raw) is on a route belonging to another airline"
            }
        }
        for id in state.orderedRouteIDs {
            guard let route = state.routes[id] else { continue }
            // The same aircraft twice on one route would double its capacity
            // for free — §46's "assigned to multiple routes", from the other
            // side.
            if Set(route.assignedAircraft).count != route.assignedAircraft.count {
                return "route \(id.raw) lists an aircraft more than once"
            }
            for aircraftID in route.assignedAircraft {
                guard let aircraft = state.aircraft[aircraftID] else {
                    return "route \(id.raw) lists aircraft \(aircraftID.raw), which does not exist"
                }
                guard aircraft.assignedRoute == id else {
                    return """
                        route \(id.raw) lists aircraft \(aircraftID.raw), which \
                        points at \(aircraft.assignedRoute.map { "\($0.raw)" } ?? "nothing")
                        """
                }
            }
        }
        return nil
    }

    private func world(seed: UInt64 = 7373) async throws
        -> (GameSession, AirlineID, ContentCatalog) {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: seed),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Churn Air", kind: .player, homeAirport: "ARN",
            startingCash: Money.dollars(2_000_000_000)))
        let player = try #require(await session.snapshot.playerAirline).id
        await session.populateStandardWorld(competitors: 2)
        return (session, player, catalog)
    }

    @Test("Assignment agrees in both directions through heavy churn")
    func assignmentSurvivesChurn() async throws {
        let (session, player, catalog) = try await world()

        // A fleet worth churning: owned and leased, several classes.
        for index in 0..<10 {
            let code: AircraftTypeCode = index % 2 == 0 ? "MR180" : "AV90"
            if index % 3 == 0 {
                _ = await session.submit(LeaseAircraftCommand(
                    lessee: player, type: code, termMonths: 36))
            } else {
                _ = await session.submit(BuyUsedAircraftCommand(
                    buyer: player, type: code, ageYears: 5))
            }
        }
        var state = await session.snapshot
        for market in state.marketOpportunities(catalog: catalog, limit: 5) {
            _ = await session.submit(OpenRouteCommand(
                airline: player, origin: market.origin,
                destination: market.destination, dailyRoundTrips: 2,
                ticketPrice: market.referenceFare))
        }
        state = await session.snapshot
        #expect(assignmentDisagreement(in: state) == nil)

        var steps = 0
        for round in 0..<6 {
            state = await session.snapshot

            // Assign everything that can be assigned, using the eligibility
            // model — which is also a live check that it never proposes a
            // pairing the command refuses.
            for route in state.routes(of: player) {
                for candidate in state.assignmentCandidates(forRoute: route.id,
                                                            catalog: catalog)
                where candidate.isEligible {
                    let result = await session.submit(AssignAircraftToRouteCommand(
                        airline: player, route: route.id,
                        aircraftID: candidate.aircraftID))
                    // A live cross-check of the eligibility model against the
                    // real pipeline, not just against `validate` in isolation.
                    if case .rejected(let rejection) = result {
                        Issue.record("""
                            eligibility proposed a pairing the command refused: \
                            \(rejection.code) — \(rejection.message)
                            """)
                        return
                    }
                    state = await session.snapshot
                    steps += 1
                    if let problem = assignmentDisagreement(in: state) {
                        Issue.record("after assign: \(problem)")
                        return
                    }
                }
            }

            await session.advance(ticks: Fixtures.ticksPerDay * 5)
            state = await session.snapshot
            if let problem = assignmentDisagreement(in: state) {
                Issue.record("after advancing: \(problem)")
                return
            }

            // Unassign a couple.
            for aircraft in state.fleet(of: player)
                .filter({ $0.assignedRoute != nil }).prefix(2) {
                _ = await session.submit(UnassignAircraftCommand(
                    airline: player, aircraftID: aircraft.id))
                state = await session.snapshot
                steps += 1
                if let problem = assignmentDisagreement(in: state) {
                    Issue.record("after unassign: \(problem)")
                    return
                }
            }

            // Close a route on alternate rounds — the path that has to clear
            // `assignedRoute` on everything it was carrying.
            if round % 2 == 1, let route = state.routes(of: player).last {
                _ = await session.submit(CloseRouteCommand(airline: player,
                                                           route: route.id))
                state = await session.snapshot
                steps += 1
                if let problem = assignmentDisagreement(in: state) {
                    Issue.record("after closing a route: \(problem)")
                    return
                }
            }
        }
        #expect(steps > 20, "churn too light to be evidence")
    }

    @Test("Selling and returning leave no trace on any route")
    func disposalClearsAssignment() async throws {
        let (session, player, catalog) = try await world()
        _ = await session.submit(BuyUsedAircraftCommand(
            buyer: player, type: "MR180", ageYears: 5))
        _ = await session.submit(LeaseAircraftCommand(
            lessee: player, type: "MR180", termMonths: 36))
        var state = await session.snapshot
        let market = try #require(state.marketOpportunities(catalog: catalog,
                                                            limit: 1).first)
        _ = await session.submit(OpenRouteCommand(
            airline: player, origin: market.origin, destination: market.destination,
            dailyRoundTrips: 2, ticketPrice: market.referenceFare))
        state = await session.snapshot
        let route = try #require(state.routes(of: player).first)
        let owned = try #require(state.fleet(of: player).first {
            if case .owned = $0.ownership { return true } else { return false }
        })
        let leased = try #require(state.fleet(of: player).first {
            if case .leased = $0.ownership { return true } else { return false }
        })

        // Both refuse while assigned — that is the guard that keeps the
        // invariant from being broken by disposal in the first place.
        _ = await session.submit(AssignAircraftToRouteCommand(
            airline: player, route: route.id, aircraftID: owned.id))
        state = await session.snapshot
        #expect(SellAircraftCommand(seller: player, aircraftID: owned.id)
            .validate(state: state, catalog: catalog) != nil,
                "selling an assigned aircraft must be refused, or the route keeps a ghost")

        _ = await session.submit(UnassignAircraftCommand(airline: player,
                                                         aircraftID: owned.id))
        _ = await session.submit(SellAircraftCommand(seller: player,
                                                     aircraftID: owned.id))
        _ = await session.submit(ReturnLeasedAircraftCommand(lessee: player,
                                                             aircraftID: leased.id))
        state = await session.snapshot

        // §46: "sold aircraft still displayed", "returned leased aircraft
        // still displayed". The read model is what a screen renders, so that
        // is what is checked — not just the entity dictionary.
        let cards = state.fleetCards(for: player, catalog: catalog)
        #expect(!cards.contains { $0.id == owned.id })
        #expect(!cards.contains { $0.id == leased.id })
        #expect(assignmentDisagreement(in: state) == nil)
        for routeID in state.orderedRouteIDs {
            #expect(state.routes[routeID]?.assignedAircraft.contains(owned.id) != true)
            #expect(state.routes[routeID]?.assignedAircraft.contains(leased.id) != true)
        }
    }

    @Test("A save round trip preserves assignment in both directions")
    func assignmentSurvivesSaveAndLoad() async throws {
        let (session, player, catalog) = try await world()
        for _ in 0..<4 {
            _ = await session.submit(BuyUsedAircraftCommand(
                buyer: player, type: "MR180", ageYears: 5))
        }
        var state = await session.snapshot
        for market in state.marketOpportunities(catalog: catalog, limit: 3) {
            _ = await session.submit(OpenRouteCommand(
                airline: player, origin: market.origin,
                destination: market.destination, dailyRoundTrips: 2,
                ticketPrice: market.referenceFare))
        }
        state = await session.snapshot
        for route in state.routes(of: player) {
            if let candidate = state.assignmentCandidates(forRoute: route.id,
                                                          catalog: catalog)
                .first(where: { $0.isEligible }) {
                _ = await session.submit(AssignAircraftToRouteCommand(
                    airline: player, route: route.id,
                    aircraftID: candidate.aircraftID))
                state = await session.snapshot
            }
        }
        await session.advance(ticks: Fixtures.ticksPerDay * 20)
        state = await session.snapshot
        try #require(assignmentDisagreement(in: state) == nil)
        try #require(state.fleet(of: player).contains { $0.assignedRoute != nil },
                     "fixture must have something assigned to be evidence")

        let codec = JSONSaveCodec()
        let restored = try codec.decode(try codec.encode(state))
        // §46's "stale assignment after load". Both directions, because a
        // codec that dropped one side would still round-trip the other.
        #expect(assignmentDisagreement(in: restored) == nil)
        for id in state.orderedAircraftIDs {
            #expect(restored.aircraft[id]?.assignedRoute
                    == state.aircraft[id]?.assignedRoute)
        }
        for id in state.orderedRouteIDs {
            #expect(restored.routes[id]?.assignedAircraft
                    == state.routes[id]?.assignedAircraft)
        }
    }

    @Test("Fleet state does not leak from one game into the next")
    func fleetDoesNotLeakBetweenGames() async throws {
        let (first, player, catalog) = try await world(seed: 1111)
        for _ in 0..<3 {
            _ = await first.submit(BuyUsedAircraftCommand(
                buyer: player, type: "MR180", ageYears: 5))
        }
        let firstState = await first.snapshot
        try #require(!firstState.fleet(of: player).isEmpty)

        // A second session built the way starting a new game builds one.
        let second = GameSession(state: Fixtures.newState(seed: 2222),
                                 systems: GamePipeline.standard(),
                                 catalog: catalog)
        let fresh = await second.snapshot
        // §46: "fleet state leaking between games". `GameState` is a value
        // type, so this should be structurally impossible — which is exactly
        // the kind of assumption worth one cheap test, since anything static
        // or cached creeping in later would break it silently.
        #expect(fresh.aircraft.isEmpty)
        #expect(fresh.routes.isEmpty)
        #expect(fresh.playerAirline == nil)
    }
}
