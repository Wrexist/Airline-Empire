import Testing
@testable import AirlineEmpireCore

/// The aircraft market's route comparison. It must be a comparison and
/// nothing else: every candidate on the same route, at the same fare and the
/// same frequency, ranked on the money the economy actually charges — and it
/// must not touch the world it reads.
@Suite("Aircraft market comparison")
struct AircraftMarketTests {
    /// A player at ARN with one used MR180 and a 2×/day LHR route.
    private func route() throws -> (ContentCatalog, SimulationEngine, RouteID) {
        let (catalog, engine, airline, _) = try RouteFixtures.withAircraft()
        let route = RouteFixtures.openStvLnw(engine, airline)
        return (catalog, engine, route)
    }

    @Test func candidatesAreEligibleAndHoldTheRoutesOwnTerms() throws {
        let (catalog, engine, route) = try route()
        let published = try #require(engine.state.aircraftMarketComparison(
            routeID: route, catalog: catalog, era: .startup))
        let mine = try #require(engine.state.routes[route])
        #expect(!published.candidates.isEmpty)
        #expect(published.distanceKm == mine.distanceKm)
        #expect(published.fare == mine.ticketPrice)
        #expect(published.dailyRoundTrips == mine.dailyRoundTrips)
        for candidate in published.candidates {
            #expect(Era.startup.allowedCategories.contains(candidate.spec.category))
            #expect(catalog.routeEligibility(
                from: mine.origin, to: mine.destination,
                aircraftRangeKm: candidate.spec.rangeKm,
                aircraftRunwayRequirement: candidate.spec.runwayRequirement).isEmpty)
            // Every candidate is priced at the route's own frequency, never
            // at a frequency of its own choosing.
            #expect(candidate.frequencySeatsPerDay
                == published.dailyRoundTrips * candidate.spec.seats * 2)
        }
        // The frequency is the route's, so a type that cannot fly it alone
        // reports the fleet the schedule needs.
        for candidate in published.candidates {
            let expected = (published.dailyRoundTrips + candidate.rotationsPerAircraft - 1)
                / candidate.rotationsPerAircraft
            #expect(candidate.aircraftNeeded == expected)
            #expect(candidate.coversFrequencyAlone == (expected <= 1))
        }
    }

    @Test func theShortlistIsTheRankedPrefixOfEveryCandidate() throws {
        let (catalog, engine, route) = try route()
        let published = try #require(engine.state.aircraftMarketComparison(
            routeID: route, catalog: catalog, era: .startup, shortlistLimit: 3))
        #expect(published.candidates.count >= published.shortlist.count)
        #expect(published.shortlist.map(\.spec.code)
            == published.candidates.prefix(3).map(\.spec.code))
        for (index, candidate) in published.candidates.enumerated() where index > 0 {
            let previous = published.candidates[index - 1]
            #expect(previous.monthlyAfterAirframe >= candidate.monthlyAfterAirframe,
                    "The list is ranked on the money")
        }
    }

    @Test func aSmallerShortlistNeverChangesTheOrder() throws {
        let (catalog, engine, route) = try route()
        let wide = try #require(engine.state.aircraftMarketComparison(
            routeID: route, catalog: catalog, era: .startup, shortlistLimit: 10))
        let narrow = try #require(engine.state.aircraftMarketComparison(
            routeID: route, catalog: catalog, era: .startup, shortlistLimit: 2))
        #expect(narrow.candidates == wide.candidates)
        #expect(narrow.shortlist.map(\.spec.code) == Array(wide.candidates.prefix(2)).map(\.spec.code))
    }

    @Test func aRouteThatIsNotThisAirlinesHasNoComparison() throws {
        let (catalog, engine, _) = try route()
        #expect(engine.state.aircraftMarketComparison(
            routeID: RouteID(raw: 99_999), catalog: catalog, era: .startup) == nil)
    }

    @Test func comparingIsPureAndDeterministic() throws {
        let (catalog, engine, route) = try route()
        let before = engine.state
        let first = try #require(engine.state.aircraftMarketComparison(
            routeID: route, catalog: catalog, era: .startup))
        let second = try #require(engine.state.aircraftMarketComparison(
            routeID: route, catalog: catalog, era: .startup))
        #expect(first == second)
        #expect(engine.state.clock == before.clock)
        #expect(engine.state.routes.count == before.routes.count)
        #expect(engine.state.aircraft.count == before.aircraft.count)
        #expect(engine.state.ledger == before.ledger)
        #expect(engine.state.eventLog.recent.map(\.kind) == before.eventLog.recent.map(\.kind))
    }

    /// The fare is anchored where the demand engine anchors it, so the
    /// screen and the simulation price against the same number.
    @Test func theFareIsPricedAgainstTheDemandEnginesAnchor() throws {
        let (catalog, engine, route) = try route()
        let published = try #require(engine.state.aircraftMarketComparison(
            routeID: route, catalog: catalog, era: .startup))
        let mine = try #require(engine.state.routes[route])
        let anchor = DemandSystem.referenceFare(distanceKm: mine.distanceKm,
                                                tuning: catalog.tuning.demand)
        #expect(published.referenceFare == Money(rounding: anchor))
        #expect(published.fare == mine.ticketPrice)
    }

    /// An era ceiling changes what the market can sell, and the comparison
    /// must respect it rather than price what the player cannot buy.
    @Test func theEraCeilingFiltersTheCandidates() throws {
        let (catalog, engine, route) = try route()
        let startup = try #require(engine.state.aircraftMarketComparison(
            routeID: route, catalog: catalog, era: .startup))
        let later = try #require(engine.state.aircraftMarketComparison(
            routeID: route, catalog: catalog, era: .empire))
        #expect(!later.candidates.isEmpty)
        #expect(later.candidates.count >= startup.candidates.count)
        for candidate in later.candidates {
            #expect(Era.empire.allowedCategories.contains(candidate.spec.category))
        }
    }

    /// The market's own pool is the market's, not a candidate's: the route
    /// and fare are held, so every candidate is priced on the same demand.
    @Test func theMarketDemandIsThePairsNotTheCandidates() throws {
        let (catalog, engine, route) = try route()
        let published = try #require(engine.state.aircraftMarketComparison(
            routeID: route, catalog: catalog, era: .startup))
        #expect(published.marketDemandToday > 0)
        #expect(Set(published.candidates.map(\.demandToday)) == [published.demandToday])
    }
}
