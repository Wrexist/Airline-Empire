import Testing
@testable import AirlineEmpireCore

// The New York twin that lived here (AE-038: SwiftJet entering JFK–ORD on
// its first decision) was an artefact of ranking markets by passengers:
// the regional rival's turboprops lost $277k a month on that pair at 100%
// load, and once the AI ranks by what an airframe day sells the entry no
// longer happens (docs/HORIZON_AUDIT.md §4). The world-initiated twin is
// now `MunichHorizonTests`.

/// The arithmetic the competitor AI now scores contested pairs with.
@Suite("Entrant pool")
struct EntrantPoolTests {

    @Test func anEmptyPairIsWorthItsWholePool() throws {
        let catalog = try ContentCatalog.loadBundled()
        let state = Fixtures.newState(seed: 1)
        let pool = SegmentDemand(business: 300, leisure: 700)
        let quality = DemandSystem.representativeStarterQuality(tuning: catalog.tuning.demand)
        let value = DemandSystem.poolAvailableToEntrant(
            pool: pool, fareRatio: 1.0, quality: quality, incumbents: [],
            state: state, catalog: catalog)
        #expect(abs(value - pool.total) < 0.001)
    }

    @Test func oneIncumbentLeavesMoreThanHalfAndLessThanAll() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let spec = try #require(catalog.scenario("entrepreneur"))
        let session = GameSession(
            state: ScenarioBootstrap.newGame(scenario: "entrepreneur", worldSeed: 7,
                                             startYear: spec.startYear),
            systems: GamePipeline.standard(), catalog: catalog)
        #expect(await session.beginScenario(spec, airlineName: "Incumbent Air", home: "ARN") == .applied)
        var state = await session.snapshot
        let player = try #require(state.playerAirline).id
        #expect(await session.submit(LeaseAircraftCommand(lessee: player, type: "PA184", termMonths: 60)) == .applied)
        state = await session.snapshot
        let distance = try #require(catalog.distanceKm("ARN", "LHR"))
        let reference = DemandSystem.referenceFare(distanceKm: distance, tuning: catalog.tuning.demand)
        #expect(await session.submit(OpenRouteCommand(
            airline: player, origin: "ARN", destination: "LHR", dailyRoundTrips: 2,
            ticketPrice: Money(rounding: reference))) == .applied)
        state = await session.snapshot
        let route = try #require(state.routes(of: player).first)
        let aircraft = try #require(state.fleet(of: player).first)
        #expect(await session.submit(AssignAircraftToRouteCommand(
            airline: player, route: route.id, aircraftID: aircraft.id)) == .applied)
        state = await session.snapshot
        let incumbent = try #require(state.routes[route.id])

        let pool = DemandSystem.demandPool(from: "ARN", to: "LHR", date: state.currentDate,
                                           economicIndex: state.world.economicIndex, catalog: catalog)
        let quality = DemandSystem.representativeStarterQuality(tuning: catalog.tuning.demand)
        let contested = DemandSystem.poolAvailableToEntrant(
            pool: pool, fareRatio: 1.0, quality: quality, incumbents: [incumbent],
            state: state, catalog: catalog)
        print("ENTRANT-POOL ARN-LHR pool \(Int(pool.total)) one incumbent at reference: \(Int(contested)) (\(String(format: "%.2f", contested / pool.total)) of it)")
        #expect(contested < pool.total)
        #expect(contested > pool.total / 2, "the old halving undervalued a contested pair")

        // A cheaper entrant expects more; a dearer one less.
        let cheap = DemandSystem.poolAvailableToEntrant(
            pool: pool, fareRatio: 0.85, quality: quality, incumbents: [incumbent],
            state: state, catalog: catalog)
        let dear = DemandSystem.poolAvailableToEntrant(
            pool: pool, fareRatio: 1.25, quality: quality, incumbents: [incumbent],
            state: state, catalog: catalog)
        #expect(cheap > contested && dear < contested)

        // An incumbent that cannot carry anyone attracts nothing.
        var grounded = incumbent
        grounded.assignedAircraft = []
        let unopposed = DemandSystem.poolAvailableToEntrant(
            pool: pool, fareRatio: 1.0, quality: quality, incumbents: [grounded],
            state: state, catalog: catalog)
        #expect(abs(unopposed - pool.total) < 0.001)
    }
}
