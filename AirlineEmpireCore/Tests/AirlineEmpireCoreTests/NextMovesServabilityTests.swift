import Testing
@testable import AirlineEmpireCore

/// What Home's "Next moves" card has to choose from on the first of
/// February of the seed-2039 campaign, with the fleet that campaign owns.
///
/// Run 116 photographed the campaign opening Stockholm–Tokyo (8,168 km)
/// with a fleet of 5,400–5,700 km narrowbodies. The first suspicion was the
/// ranking — that AE-037's cast fix (BUG-043), by taking the rivals out of
/// the world's largest markets, had pushed intercontinental pairs to the
/// top of the card. This test measured that it had not: the card's four
/// are Paris, Istanbul, Cairo and Delhi, every one flyable, and the frame
/// of Home that morning shows Paris and Istanbul. The Tokyo route came
/// from the guided sheet opening empty (BUG-045). Kept so the ranking the
/// card relies on stays pinned to the fleet's reach.
@Suite("Next moves servability")
struct NextMovesServabilityTests {

    @Test func theTopOfTheRankingFromStockholmIsWithinTheFleetsReach() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let spec = try #require(catalog.scenario("entrepreneur"))
        let session = GameSession(
            state: ScenarioBootstrap.newGame(scenario: "entrepreneur",
                                             worldSeed: FirstEraCampaignTests.campaignSeed,
                                             startYear: spec.startYear),
            systems: GamePipeline.standard(), catalog: catalog)
        #expect(await session.beginScenario(spec, airlineName: "Campaign Air",
                                            home: "ARN") == .applied)
        var state = await session.snapshot
        let player = try #require(state.playerAirline).id
        #expect(await session.submit(LeaseAircraftCommand(
            lessee: player, type: "PA184", termMonths: 60)) == .applied)
        state = await session.snapshot
        let first = try #require(state.onboardingModel(catalog: catalog)?.suggestions.first)
        #expect(await session.submit(OpenRouteCommand(
            airline: player, origin: first.origin, destination: first.destination,
            dailyRoundTrips: 2, ticketPrice: first.referenceFare)) == .applied)

        // To the first of February, as the campaign does.
        let ticksPerDay = Int(GameCalendar.minutesPerDay
            / ScenarioBootstrap.standardTickMinutes)
        while await session.snapshot.currentDate.month == 1 {
            await session.advance(ticks: ticksPerDay)
        }
        state = await session.snapshot

        let four = state.marketOpportunities(catalog: catalog, limit: 4)
        print("NEXT-MOVES 1 Feb top 4: " + four.map {
            "\($0.origin)-\($0.destination) \($0.distanceKm)km \($0.servableNow ? "ok" : "beyond range")"
        }.joined(separator: ", "))

        let longestReach = state.fleet(of: player)
            .compactMap { catalog.aircraftType($0.typeCode)?.rangeKm }.max() ?? 0
        #expect(four.count == 4)
        #expect(four.allSatisfy { $0.servableNow })
        #expect(four.allSatisfy { $0.distanceKm <= longestReach })
        // The two the card shows, as run 116's Home frame has them.
        #expect(four.prefix(2).map(\.destination.raw) == ["CDG", "IST"])
    }
}
