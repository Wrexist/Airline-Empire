import Testing
@testable import AirlineEmpireCore

/// The network and fleet summaries (docs/DESIGN_SYSTEM.md §5).
///
/// These exist because Home, the Routes board and the Fleet board each wanted
/// the same handful of aggregates and each derived them in a view body. The
/// risk that creates is not performance, it is disagreement: two screens
/// answering "how full are the aeroplanes" with different numbers. So the
/// tests that matter here are the ones holding a summary against the per-row
/// model it summarises.
@Suite("Summary read models")
struct SummaryModelTests {

    private func world(seed: UInt64 = 5150) async throws
        -> (GameSession, AirlineID, ContentCatalog) {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: seed),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Summary Air", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(400_000_000)))
        let player = try #require(await session.snapshot.playerAirline).id
        await session.populateStandardWorld(competitors: 2)
        return (session, player, catalog)
    }

    /// A player flying several routes, far enough in that flights have flown.
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
        await session.advance(ticks: Fixtures.ticksPerDay * 45)
        return (session, player, catalog)
    }

    @Test("An airline with nothing reports nothing, and says so with nil rather than zero")
    func emptyAirlineIsHonest() async throws {
        let (session, player, _) = try await world()
        let state = await session.snapshot
        let network = state.networkSummary(for: player)
        let fleet = state.fleetSummary(for: player)

        #expect(network.routeCount == 0)
        #expect(network.liveFlights == 0)
        #expect(network.monthToDateProfit == .zero)
        #expect(network.monthToDateRevenue == .zero)
        #expect(network.monthToDateCosts == .zero)
        // The distinction the optionals exist to make: no aeroplanes is not
        // the same claim as empty aeroplanes.
        #expect(network.averageLoadFactor == nil)
        #expect(fleet.total == 0)
        #expect(fleet.utilization == nil)
        #expect(fleet.averageAgeYears == nil)
        #expect(fleet.averageCondition == nil)
    }

    @Test("The network summary agrees with the route cards it summarises")
    func networkAgreesWithRouteCards() async throws {
        let (session, player, catalog) = try await flyingWorld()
        let state = await session.snapshot
        let cards = state.routeCards(for: player, catalog: catalog)
        let summary = state.networkSummary(for: player)

        #expect(summary.routeCount == cards.count)
        #expect(summary.routeCount > 0, "the world must have opened routes")
        #expect(summary.profitableRoutes == cards.filter { $0.thisMonthProfit.cents > 0 }.count)
        #expect(summary.losingRoutes == cards.filter { $0.thisMonthProfit.isNegative }.count)
        #expect(summary.idleRoutes == cards.filter { $0.assignedAircraftCount == 0 }.count)
        // Profit is the sum of the parts, to the cent.
        #expect(summary.monthToDateProfit
                == cards.reduce(Money.zero) { $0 + $1.thisMonthProfit })
        // Profitable and losing are not complements: a route that has not
        // flown is neither, so they may sum to less than the total.
        #expect(summary.profitableRoutes + summary.losingRoutes <= summary.routeCount)

        // Revenue and costs are the two halves of the profit, and costs are a
        // positive magnitude rather than a negative to re-sign at the view.
        let revenue = cards.reduce(Money.zero) {
            $0 + Money(cents: $1.thisMonthBreakdown.revenueCents)
        }
        let costs = cards.reduce(Money.zero) {
            $0 + Money(cents: $1.thisMonthBreakdown.fuelCents
                       + $1.thisMonthBreakdown.feesCents
                       + $1.thisMonthBreakdown.crewCents)
        }
        #expect(summary.monthToDateRevenue == revenue)
        #expect(summary.monthToDateCosts == costs)
        #expect(!summary.monthToDateCosts.isNegative)
        #expect(summary.monthToDateRevenue - summary.monthToDateCosts
                == summary.monthToDateProfit)
    }

    @Test("Network load factor is weighted by seats, not averaged over routes")
    func loadFactorIsSeatWeighted() async throws {
        let (session, player, _) = try await flyingWorld()
        let state = await session.snapshot
        let summary = state.networkSummary(for: player)
        let loadFactor = try #require(summary.averageLoadFactor,
                                      "the world must have flown something")
        #expect(loadFactor > 0 && loadFactor <= 1)

        // The same arithmetic, spelled out: seats sold over seats flown.
        var sold: Int64 = 0, flown: Int64 = 0
        for route in state.routes(of: player) where route.stats.seatsFlown > 0 {
            sold += route.stats.passengersCarried
            flown += route.stats.seatsFlown
        }
        #expect(abs(loadFactor - Double(sold) / Double(flown)) < 1e-12)
    }

    @Test("The fleet summary agrees with the fleet cards, and its buckets partition the fleet")
    func fleetAgreesWithFleetCards() async throws {
        let (session, player, catalog) = try await flyingWorld()
        let state = await session.snapshot
        let cards = state.fleetCards(for: player, catalog: catalog)
        let summary = state.fleetSummary(for: player)

        #expect(summary.total == cards.count)
        #expect(summary.total > 0, "the world must have bought aircraft")
        // Every aircraft lands in exactly one status bucket.
        #expect(summary.assigned + summary.idle + summary.inMaintenance
                + summary.onOrder == summary.total)
        #expect(summary.inMaintenance == cards.filter { $0.status.isInMaintenance }.count)
        #expect(summary.onOrder == cards.filter { $0.status.isOnOrder }.count)
        #expect(summary.assigned == cards.filter {
            $0.status.isActive && $0.assignedRoute != nil
        }.count)
        #expect(summary.idle == cards.filter {
            $0.status.isActive && $0.assignedRoute == nil
        }.count)
        #expect(summary.leasedCount == cards.filter {
            if case .leased = $0.ownershipDescription { return true }
            return false
        }.count)
    }

    @Test("Utilisation counts only airworthy aircraft, so an undelivered order is not idleness")
    func utilizationExcludesUndelivered() async throws {
        let (session, player, catalog) = try await flyingWorld()
        // A new order is months away and cannot fly; it must not drag
        // utilisation down as though the player were wasting it.
        _ = await session.submit(BuyNewAircraftCommand(buyer: player, type: "MR180"))
        let state = await session.snapshot
        let summary = state.fleetSummary(for: player)
        #expect(summary.onOrder >= 1)

        let airworthy = summary.assigned + summary.idle
        let utilization = try #require(summary.utilization)
        #expect(abs(utilization - Double(summary.assigned) / Double(airworthy)) < 1e-12)
        #expect(utilization <= 1)

        // Age and condition likewise describe delivered aircraft only.
        let delivered = state.fleetCards(for: player, catalog: catalog)
            .filter { !$0.status.isOnOrder }
        let age = try #require(summary.averageAgeYears)
        let expected = delivered.reduce(0.0) { $0 + $1.ageYears } / Double(delivered.count)
        #expect(abs(age - expected) < 1e-9)
    }

    /// TD-012. Two Core functions describe the same population of routes and
    /// nothing connected them.
    ///
    /// `MapModel.health(of:)` returns `.grounded` for `assignedAircraft.isEmpty`;
    /// `NetworkSummary.idleRoutes` counts exactly that. The map's overlay hint
    /// ("N of your routes have no aircraft and are still paying fees") and the
    /// Routes board header ("no aircraft: N") are therefore two independent
    /// answers to one question, free to drift the moment either definition is
    /// edited — and a player reading both would have no way to tell which was
    /// wrong. This is the cheap half of the fix: not a refactor of working
    /// view code, just a test that fails the day they disagree.
    @Test("Grounded routes on the map are the same routes the summary calls idle")
    func groundedAgreesWithIdle() async throws {
        let (session, player, catalog) = try await flyingWorld()
        var state = await session.snapshot

        // With everything assigned the count is zero, which would let a broken
        // implementation pass. Ground one route first so the assertion has
        // something to be wrong about.
        let route = try #require(state.routes(of: player).first)
        _ = await session.submit(UnassignAircraftCommand(
            airline: player,
            aircraftID: try #require(route.assignedAircraft.first)))
        state = await session.snapshot

        let summary = state.networkSummary(for: player)
        let grounded = state.mapModel(catalog: catalog).routes
            .filter { $0.isPlayer && $0.health == .grounded }
            .count
        #expect(summary.idleRoutes >= 1, "the world must have a grounded route")
        #expect(summary.idleRoutes == grounded)
    }

    /// BUG-031, pinned at its source.
    ///
    /// The bug itself was in the app: `GameController` keyed its derived
    /// caches on `clock.tickCount`, so a paused player's own command changed
    /// nothing on screen. There is no app test target that runs here, so this
    /// asserts the Core behaviour that made the app's assumption wrong —
    /// **a command applied while paused changes the state without advancing
    /// the tick.** Anything that caches on the tick alone is broken by this,
    /// and this test is where that is written down.
    @Test("A command applied while paused changes the state without advancing the tick")
    func pausedCommandChangesStateAtTheSameTick() async throws {
        let (session, player, catalog) = try await flyingWorld()
        await session.setSpeed(.paused)

        let before = await session.snapshot
        let beforeSummary = before.networkSummary(for: player)
        let beforeFleet = before.fleetSummary(for: player)

        _ = await session.submit(BuyUsedAircraftCommand(
            buyer: player, type: "MR180", ageYears: 4))
        let after = await session.snapshot

        // The trap: same tick, different world.
        #expect(after.clock.tickCount == before.clock.tickCount)
        #expect(after.fleetSummary(for: player).total == beforeFleet.total + 1)

        // And again for a route, so the network summary is covered too.
        let market = try #require(after.marketCandidates(from: before.playerAirline!.homeAirport,
                                                         catalog: catalog)
            .first { candidate in
                !after.routes(of: player).contains {
                    $0.sameMarket(origin: candidate.origin,
                                  destination: candidate.destination)
                }
            })
        _ = await session.submit(OpenRouteCommand(
            airline: player, origin: market.origin, destination: market.destination,
            dailyRoundTrips: 2, ticketPrice: market.referenceFare))
        let withRoute = await session.snapshot

        #expect(withRoute.clock.tickCount == before.clock.tickCount)
        #expect(withRoute.networkSummary(for: player).routeCount
                == beforeSummary.routeCount + 1)
    }

    @Test("Live flights are the player's own, counted while airborne")
    func liveFlightsAreThePlayersAndAirborne() async throws {
        let (session, player, _) = try await flyingWorld()
        let state = await session.snapshot
        let summary = state.networkSummary(for: player)

        // The same count the dashboard publishes, so Home cannot show two
        // different numbers for "in the air right now".
        let dashboard = try #require(state.dashboardModel())
        #expect(summary.liveFlights == dashboard.liveFlightCount)

        // Spelled out, and scoped to this airline: a rival's aeroplane is not
        // the player's traffic.
        let ownRoutes = Set(state.routes(of: player).map(\.id))
        var expected = 0
        for id in state.orderedFlightIDs {
            guard let flight = state.flights[id],
                  ownRoutes.contains(flight.route) else { continue }
            if case .enRoute = flight.phase { expected += 1 }
        }
        #expect(summary.liveFlights == expected)
    }
}
