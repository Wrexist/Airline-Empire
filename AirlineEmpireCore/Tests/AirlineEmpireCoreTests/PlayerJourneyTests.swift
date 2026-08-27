import Testing
@testable import AirlineEmpireCore

/// Player journeys driven through the real command surface and verified
/// through the read models the UI actually consumes — the Linux equivalent
/// of a simulator walkthrough (no SwiftUI runtime available, B-002).
///
/// These exist because static review missed BUG-002: every command was
/// implemented and tested, yet the player could not complete the core loop.
/// A journey test fails when a *sequence* is broken, not just a unit.
@Suite("Player journeys")
struct PlayerJourneyTests {

    /// NEW GAME → AIRLINE → AIRCRAFT → ROUTE → ASSIGN → FLY → REVENUE.
    /// Every transition is checked through the read model the matching
    /// screen renders, so a broken data contract fails here.
    @Test func firstSessionReachesProfitableOperations() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let spec = try #require(catalog.scenario("entrepreneur"))
        let session = GameSession(
            state: ScenarioBootstrap.newGame(scenario: "entrepreneur",
                                             worldSeed: 2026,
                                             startYear: spec.startYear),
            systems: GamePipeline.standard(), catalog: catalog)

        // 1. New game: the airline exists and the world has rivals.
        #expect(await session.beginScenario(spec, airlineName: "Journey Air",
                                            home: "STV") == .applied)
        var state = await session.snapshot
        let player = try #require(state.playerAirline).id
        var dashboard = try #require(state.dashboardModel())
        #expect(dashboard.airlineName == "Journey Air")
        #expect(dashboard.cash == spec.playerStartingCash)
        #expect(dashboard.fleetCount == 0)
        #expect(dashboard.routeCount == 0)
        #expect(state.airlines.values.filter { $0.kind == .ai }.count
            == spec.competitorCount)

        // Onboarding tells the player what to do first.
        var onboarding = try #require(state.onboardingModel(catalog: catalog))
        #expect(onboarding.nextStep == .acquireAircraft)

        // 2. Buy an aircraft (paused: applies immediately).
        #expect(await session.submit(BuyUsedAircraftCommand(
            buyer: player, type: "MR180", ageYears: 8)) == .applied)
        state = await session.snapshot
        let fleetCards = state.fleetCards(for: player, catalog: catalog)
        #expect(fleetCards.count == 1)
        let aircraft = try #require(fleetCards.first)
        #expect(aircraft.status == .active)
        #expect(aircraft.assignedRoute == nil)
        #expect(aircraft.location == "STV")   // starts at home, ready to work
        #expect(state.ledger.balance(of: player) < spec.playerStartingCash)

        // 3. Open a route the onboarding model itself suggested.
        onboarding = try #require(state.onboardingModel(catalog: catalog))
        #expect(onboarding.nextStep == .openRoute)
        let suggestion = try #require(onboarding.suggestions.first)
        #expect(await session.submit(OpenRouteCommand(
            airline: player, origin: suggestion.origin,
            destination: suggestion.destination, dailyRoundTrips: 2,
            ticketPrice: suggestion.referenceFare)) == .applied)
        state = await session.snapshot
        var routeCards = state.routeCards(for: player, catalog: catalog)
        #expect(routeCards.count == 1)
        let route = try #require(routeCards.first)
        #expect(route.assignedAircraftCount == 0)   // nothing flies yet

        // 4. Assign the aircraft — the step BUG-002 made unreachable in UI.
        #expect(await session.submit(AssignAircraftToRouteCommand(
            airline: player, route: route.id, aircraftID: aircraft.id))
            == .applied)
        state = await session.snapshot
        routeCards = state.routeCards(for: player, catalog: catalog)
        #expect(routeCards[0].assignedAircraftCount == 1)
        #expect(state.fleetCards(for: player, catalog: catalog)[0]
            .assignedRoute == route.id)

        // 5. Run the world: flights must actually operate.
        await session.advance(ticks: Fixtures.ticksPerDay * 45)
        state = await session.snapshot
        let flown = try #require(state.routes[route.id]).stats
        #expect(flown.flightsCompleted > 0)
        #expect(flown.passengersCarried > 0)
        #expect(flown.loadFactor > 0)

        // 6. Revenue and a readable P&L reach the finance screens.
        routeCards = state.routeCards(for: player, catalog: catalog)
        #expect(routeCards[0].lastMonthBreakdown.revenueCents > 0)
        #expect(routeCards[0].lastMonthProfit
            == routeCards[0].lastMonthBreakdown.directOperatingProfit)
        let finance = try #require(state.financeModel(for: player))
        #expect(!finance.monthlySeries.isEmpty)
        #expect(finance.monthlySeries.allSatisfy { $0.revenue >= .zero })

        dashboard = try #require(state.dashboardModel())
        #expect(dashboard.fleetCount == 1)
        #expect(dashboard.routeCount == 1)
        #expect(dashboard.destinationCount == 2)
        #expect(dashboard.lastMonthRevenue != nil)

        // 7. The onboarding arc is complete and gets out of the way.
        onboarding = try #require(state.onboardingModel(catalog: catalog))
        #expect(onboarding.isComplete)
    }

    /// The player must be able to undo every commitment: unassign, close a
    /// route, and sell the aircraft — ending solvent with no orphan state.
    @Test func playerCanUnwindEveryCommitment() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: 77),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Unwind Air", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(120_000_000)))
        var state = await session.snapshot
        let player = try #require(state.playerAirline).id

        _ = await session.submit(BuyUsedAircraftCommand(buyer: player,
                                                        type: "MR180", ageYears: 8))
        state = await session.snapshot
        let aircraft = try #require(state.fleet(of: player).first).id
        let suggestion = try #require(state.onboardingModel(catalog: catalog)?
            .suggestions.first)
        _ = await session.submit(OpenRouteCommand(
            airline: player, origin: suggestion.origin,
            destination: suggestion.destination, dailyRoundTrips: 2,
            ticketPrice: suggestion.referenceFare))
        state = await session.snapshot
        let route = try #require(state.routes(of: player).first).id
        _ = await session.submit(AssignAircraftToRouteCommand(
            airline: player, route: route, aircraftID: aircraft))
        await session.advance(ticks: Fixtures.ticksPerDay * 10)

        // Unassign → the route keeps existing but nothing is committed.
        #expect(await session.submit(UnassignAircraftCommand(
            airline: player, aircraftID: aircraft)) == .applied)
        state = await session.snapshot
        #expect(state.routeCards(for: player, catalog: catalog)[0]
            .assignedAircraftCount == 0)
        #expect(state.fleetCards(for: player, catalog: catalog)[0]
            .assignedRoute == nil)

        // Close the route → slots come back, no dangling flights.
        let slotsBefore = state.world.slotsUsed(at: "STV")
        #expect(await session.submit(CloseRouteCommand(airline: player,
                                                       route: route)) == .applied)
        state = await session.snapshot
        #expect(state.routes(of: player).isEmpty)
        #expect(state.world.slotsUsed(at: "STV") < slotsBefore)
        #expect(!state.flights.values.contains { $0.route == route })

        // Sell the aircraft → cash back, empty fleet, world still sane.
        let cashBefore = state.ledger.balance(of: player)
        #expect(await session.submit(SellAircraftCommand(
            seller: player, aircraftID: aircraft)) == .applied)
        state = await session.snapshot
        #expect(state.fleet(of: player).isEmpty)
        #expect(state.ledger.balance(of: player) > cashBefore)
        #expect(state.integrityViolations().isEmpty)

        // Back to the start of the arc, honestly reported.
        let onboarding = try #require(state.onboardingModel(catalog: catalog))
        #expect(onboarding.nextStep == .acquireAircraft)
    }

    /// Save mid-journey, reload, and keep playing — the contract a player
    /// relies on every session (flagship invariant, docs/PERSISTENCE §8).
    @Test func journeySurvivesSaveAndReload() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: 31),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Persist Air", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(120_000_000)))
        var state = await session.snapshot
        let player = try #require(state.playerAirline).id
        _ = await session.submit(BuyUsedAircraftCommand(buyer: player,
                                                        type: "MR180", ageYears: 8))
        state = await session.snapshot
        let aircraft = try #require(state.fleet(of: player).first).id
        let suggestion = try #require(state.onboardingModel(catalog: catalog)?
            .suggestions.first)
        _ = await session.submit(OpenRouteCommand(
            airline: player, origin: suggestion.origin,
            destination: suggestion.destination, dailyRoundTrips: 3,
            ticketPrice: suggestion.referenceFare))
        state = await session.snapshot
        let route = try #require(state.routes(of: player).first).id
        _ = await session.submit(AssignAircraftToRouteCommand(
            airline: player, route: route, aircraftID: aircraft))
        await session.advance(ticks: Fixtures.ticksPerDay * 20)

        // Save mid-run, then continue in both the live and restored games.
        let codec = JSONSaveCodec()
        let saved = try codec.encode(await session.snapshot)
        let restored = try codec.decode(saved)
        let continued = GameSession(state: restored,
                                    systems: GamePipeline.standard(),
                                    catalog: catalog)
        await session.advance(ticks: Fixtures.ticksPerDay * 15)
        await continued.advance(ticks: Fixtures.ticksPerDay * 15)

        let live = await session.snapshot
        let reloaded = await continued.snapshot
        #expect(try live.stateHash() == reloaded.stateHash())

        // And the player-facing numbers agree, not just the bytes.
        let liveDash = try #require(live.dashboardModel())
        let reloadedDash = try #require(reloaded.dashboardModel())
        #expect(liveDash == reloadedDash)
        #expect(live.routeCards(for: player, catalog: catalog)
            == reloaded.routeCards(for: player, catalog: catalog))
    }

    /// Failure has to be survivable: an airline in trouble can raise cash
    /// through the same commands, and the read models explain the hole.
    @Test func playerCanFightBackFromLosses() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: 55),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Rescue Air", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(40_000_000)))
        var state = await session.snapshot
        let player = try #require(state.playerAirline).id

        // Overreach: lease capacity and price far below the market.
        _ = await session.submit(LeaseAircraftCommand(lessee: player,
                                                      type: "MR180",
                                                      termMonths: 60))
        state = await session.snapshot
        let aircraft = try #require(state.fleet(of: player).first).id
        let suggestion = try #require(state.onboardingModel(catalog: catalog)?
            .suggestions.first)
        _ = await session.submit(OpenRouteCommand(
            airline: player, origin: suggestion.origin,
            destination: suggestion.destination, dailyRoundTrips: 4,
            ticketPrice: Money(rounding: suggestion.referenceFare.asDouble * 0.35)))
        state = await session.snapshot
        let route = try #require(state.routes(of: player).first).id
        _ = await session.submit(AssignAircraftToRouteCommand(
            airline: player, route: route, aircraftID: aircraft))
        await session.advance(ticks: Fixtures.ticksPerDay * 90)

        // The finance read model must explain the damage, not hide it.
        state = await session.snapshot
        let finance = try #require(state.financeModel(for: player))
        #expect(!finance.monthlySeries.isEmpty)

        // Recovery levers all work through the normal command surface.
        #expect(await session.submit(SetRoutePriceCommand(
            airline: player, route: route,
            ticketPrice: suggestion.referenceFare)) == .applied)
        #expect(await session.submit(TakeLoanCommand(
            airline: player, amount: Money.dollars(10_000_000),
            termMonths: 48)) == .applied)
        state = await session.snapshot
        #expect(try #require(state.financeModel(for: player)).loans.count == 1)
        #expect(state.routeCards(for: player, catalog: catalog)[0].ticketPrice
            == suggestion.referenceFare)

        await session.advance(ticks: Fixtures.ticksPerDay * 60)
        state = await session.snapshot
        #expect(state.integrityViolations().isEmpty)
    }
}
