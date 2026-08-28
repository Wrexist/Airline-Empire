import Testing
@testable import AirlineEmpireCore

/// Screen data contracts (docs/UI_ARCHITECTURE.md §2). Each test asserts
/// that the read models a screen consumes supply everything that screen
/// renders, on a real mid-game world — so a missing or degenerate field is
/// caught here on Linux rather than by Xcode later (B-002).
///
/// These guard the App/Core boundary, not the rendering: they answer "could
/// this screen be drawn correctly from Core alone?".
@Suite("Screen data contracts")
struct ScreenContractTests {
    /// A world with the player operating a small network alongside rivals.
    private func operatingWorld() async throws
        -> (GameSession, GameState, AirlineID, ContentCatalog) {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: 808),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Contract Air", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(200_000_000)))
        var state = await session.snapshot
        let player = try #require(state.playerAirline).id
        await session.populateStandardWorld(competitors: 3)

        // Three routes, three aircraft, all flying.
        for _ in 0..<3 {
            _ = await session.submit(BuyUsedAircraftCommand(
                buyer: player, type: "MR180", ageYears: 6))
        }
        state = await session.snapshot
        let aircraft = state.fleet(of: player).map(\.id)
        let targets = try #require(state.onboardingModel(catalog: catalog,
                                                         suggestionLimit: 3))
            .suggestions
        for (index, suggestion) in targets.enumerated() where index < aircraft.count {
            _ = await session.submit(OpenRouteCommand(
                airline: player, origin: suggestion.origin,
                destination: suggestion.destination, dailyRoundTrips: 2,
                ticketPrice: suggestion.referenceFare))
            let routes = await session.snapshot.routes(of: player)
            if let route = routes.last {
                _ = await session.submit(AssignAircraftToRouteCommand(
                    airline: player, route: route.id, aircraftID: aircraft[index]))
            }
        }
        _ = await session.submit(TakeLoanCommand(airline: player,
                                                 amount: Money.dollars(15_000_000),
                                                 termMonths: 48))
        await session.advance(ticks: Fixtures.ticksPerDay * 70)
        state = await session.snapshot
        return (session, state, player, catalog)
    }

    @Test func dashboardScreenHasEverythingItRenders() async throws {
        let (_, state, _, catalog) = try await operatingWorld()
        let dashboard = try #require(state.dashboardModel())
        #expect(!dashboard.airlineName.isEmpty)
        #expect(dashboard.fleetCount == 3)
        #expect(dashboard.routeCount == 3)
        #expect(dashboard.destinationCount >= 2)
        #expect(dashboard.reputationScore > 0 && dashboard.reputationScore <= 1)
        #expect(dashboard.fuelPricePerTon > .zero)
        #expect(dashboard.economicIndex > 0)
        #expect(dashboard.lastMonthNetProfit != nil)  // a closed month exists
        #expect(dashboard.lastMonthRevenue != nil)
        #expect(!dashboard.gameOver)
        // The onboarding card must be able to retire itself.
        let onboarding = try #require(state.onboardingModel(catalog: catalog))
        #expect(onboarding.isComplete)
    }

    @Test func routeDetailScreenCanExplainItsMoney() async throws {
        let (_, state, player, catalog) = try await operatingWorld()
        let cards = state.routeCards(for: player, catalog: catalog)
        #expect(cards.count == 3)
        for card in cards {
            #expect(card.distanceKm > 0)
            #expect(card.dailyRoundTrips > 0)
            #expect(card.ticketPrice > .zero)
            #expect(card.farePosition > 0)
            #expect(card.assignedAircraftCount >= 1)
            #expect(card.loadFactor >= 0 && card.loadFactor <= 1)
            #expect(card.punctuality >= 0 && card.punctuality <= 1)
            #expect(card.completionRate >= 0 && card.completionRate <= 1)
            // The breakdown the screen prints must reconcile exactly.
            let b = card.lastMonthBreakdown
            #expect(card.lastMonthProfit
                == Money(cents: b.revenueCents - b.fuelCents - b.feesCents - b.crewCents))
            #expect(b.revenueCents > 0)
            #expect(b.fuelCents > 0 && b.crewCents > 0)
        }
        // The assign menu needs identifiable aircraft with locations.
        for aircraft in state.fleetCards(for: player, catalog: catalog) {
            #expect(!aircraft.typeName.isEmpty)
            #expect(catalog.airport(aircraft.location) != nil)
        }
    }

    @Test func fleetScreenHasEveryBadgeItShows() async throws {
        let (_, state, player, catalog) = try await operatingWorld()
        let cards = state.fleetCards(for: player, catalog: catalog)
        #expect(cards.count == 3)
        for card in cards {
            #expect(!card.typeName.isEmpty)
            #expect(card.ageYears > 0)
            #expect(card.condition > 0 && card.condition <= 1)
            #expect(card.reliability > 0 && card.reliability <= 1)
            #expect(card.totalFlightHours > 0)
            switch card.ownershipDescription {
            case .owned(let book): #expect(book > .zero)
            case .leased(let rate, let months):
                #expect(rate > .zero); #expect(months > 0)
            }
        }
    }

    @Test func financeScreenHasStatementsTrendAndLoans() async throws {
        let (_, state, player, _) = try await operatingWorld()
        let finance = try #require(state.financeModel(for: player))
        #expect(finance.totalDebt > .zero)
        #expect(finance.debtRatio > 0 && finance.debtRatio <= 1)
        #expect(finance.loans.count == 1)
        let loan = try #require(finance.loans.first)
        #expect(loan.principalRemaining > .zero)
        #expect(loan.monthlyPayment > .zero)
        #expect(loan.monthsRemaining > 0)
        #expect(loan.annualRateBasisPoints > 0)
        // The bar chart needs an ordered series.
        #expect(finance.monthlySeries.count >= 2)
        let months = finance.monthlySeries.map { $0.year * 12 + $0.month }
        #expect(months == months.sorted())
        // Every statement category the screen labels must be classifiable.
        let statement = try #require(state.finance.byAirline[player]?.latest)
        #expect(!statement.byCategory.isEmpty)
        #expect(statement.netProfit
            == statement.operatingProfit + statement.financingCost)
    }

    /// Map data contract (V3 prompt §16): the renderer must get identity,
    /// geometry, ownership, and live flight state from Core alone.
    @Test func mapScreenHasCompleteRenderData() async throws {
        let (_, state, player, catalog) = try await operatingWorld()
        let map = state.mapModel(catalog: catalog)

        #expect(map.airports.count == catalog.orderedAirportCodes.count)
        for airport in map.airports {
            #expect(!airport.name.isEmpty)
            #expect(!airport.city.isEmpty)
            #expect(airport.position.x >= 0 && airport.position.x <= 1)
            #expect(airport.position.y >= 0 && airport.position.y <= 1)
            #expect(airport.prominence >= 0 && airport.prominence <= 1)
        }
        // The player's own network is marked and drawable.
        #expect(map.airports.contains { $0.servedByPlayer })
        let playerRoutes = map.routes.filter(\.isPlayer)
        #expect(playerRoutes.count == 3)
        for route in map.routes {
            #expect(route.arc.count >= 2)            // a path, not a point
            #expect(route.dailyRoundTrips > 0)
            #expect((route.airline == player) == route.isPlayer)
        }
        // Live aircraft carry position and heading for the airplane glyph.
        for flight in map.flights where flight.airborne {
            #expect(flight.position.x >= 0 && flight.position.x <= 1)
            #expect(flight.position.y >= 0 && flight.position.y <= 1)
            #expect(flight.heading >= 0 && flight.heading < 360)
        }
        // Selection callouts read slots and closure straight from state.
        let home = try #require(state.playerAirline).homeAirport
        #expect(state.world.slotsUsed(at: home) > 0)
        #expect(catalog.airport(home)?.slotCapacityPerDay ?? 0 > 0)
    }

    @Test func worldScreensHaveEventsCompetitorsAndProgression() async throws {
        let (_, state, _, _) = try await operatingWorld()
        // Competitors list: identity, archetype, and standing.
        let rivals = state.orderedAirlineIDs
            .compactMap { state.airlines[$0] }
            .filter { $0.kind == .ai }
        #expect(rivals.count == 3)
        for rival in rivals {
            #expect(!rival.name.isEmpty)
            #expect(rival.aiProfile != nil)
            #expect(rival.reputation.score > 0)
        }
        // Progression screen: era, capability catalogue, mission rendering.
        #expect(CapabilityCode.allCases.count > 0)
        for mission in state.progression.missions {
            #expect(mission.reward > .zero)
            #expect(mission.deadline.rawMinutes > 0)
        }
        // World events, if any are live, render title + window.
        for event in state.world.activeEvents {
            #expect(event.endsAt.rawMinutes > event.beginsAt.rawMinutes)
            #expect(event.severity >= 0)
        }
    }
}
