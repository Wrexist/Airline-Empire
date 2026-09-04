import Testing
@testable import AirlineEmpireCore

/// AE-042: can a new player trust Next Moves?
///
/// BUG-055 measured that the answer was no. `marketOpportunities` ranked
/// markets by the passengers a starter service would capture and by nothing
/// else, and because the reference fare rises with distance while the two
/// movement fees do not, the densest short pairs sorted to the top of the
/// list and to the bottom of the economics. At 21 of the 93 homes a player
/// can pick, Home's first suggestion either lost money after the airframe it
/// needed or could not be flown at all; New York's second suggestion, Toronto,
/// lost $214k a month, and AE-041's scripted campaign following that advice
/// collapsed in 28 of 30 seeds (docs/AE042_NEXT_MOVES_BASELINE.md).
///
/// The fix gates the ranking on whether a market pays for the aircraft it
/// needs, using the flight system's own arithmetic. These tests pin the
/// gate, the advice at the starts the game curates, and a campaign that
/// follows the advice through real commands.
@Suite("Next moves")
struct NextMovesTests {

    static func founded(seed: UInt64 = 2030, home: AirportCode,
                        scenario code: ScenarioCode = "entrepreneur") throws
        -> (SimulationEngine, ContentCatalog, ScenarioSpec) {
        let catalog = try ContentCatalog.loadBundled()
        let spec = try #require(catalog.scenario(code))
        let engine = SimulationEngine(
            state: ScenarioBootstrap.newGame(scenario: code, worldSeed: seed,
                                             startYear: spec.startYear),
            systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Advice Air", kind: .player, homeAirport: home,
            startingCash: spec.playerStartingCash))
        WorldSetup.createCompetitors(engine: engine, count: spec.competitorCount,
                                     playerHome: home,
                                     startingCash: spec.competitorStartingCash)
        return (engine, catalog, spec)
    }

    /// Exactly what Home shows: `marketOpportunities` narrowed the way
    /// `NextMovesCard` narrows it.
    static func homeRecommends(_ state: GameState,
                               catalog: ContentCatalog) -> [MarketOpportunity] {
        let ranked = state.marketOpportunities(catalog: catalog, limit: 4)
        let servable = ranked.filter(\.servableNow)
        return Array((servable.isEmpty ? ranked : servable).prefix(2))
    }

    // MARK: The gate

    /// NEXTMOVES-01: every market Home offers pays for the aircraft it needs,
    /// at every start the game curates and at the one BUG-055 was found on —
    /// unless no market from that home does, which is a real state the gate
    /// reports rather than hides.
    @Test(arguments: [AirportCode("ARN"), "BCN", "SIN", "MUC", "JFK", "LHR", "MAN"])
    func everyRecommendedMarketPaysForTheAircraftItNeeds(_ home: AirportCode) throws {
        let (engine, catalog, _) = try Self.founded(home: home)
        let state = engine.state
        let recommended = Self.homeRecommends(state, catalog: catalog)
        #expect(!recommended.isEmpty, "Home offers nothing at all from \(home.raw)")

        // If anything from this home pays, everything offered must pay: the
        // gate puts qualifying markets first, so a trap can only appear
        // beside one when there were not enough to fill the list.
        let anyPays = state.marketOpportunities(catalog: catalog, limit: 40)
            .contains { $0.paysForItsAirframe }
        let summary = recommended.map {
            "\($0.origin.raw)-\($0.destination.raw) \($0.distanceKm)km \($0.monthlyAfterAirframe.compact)/mo on \($0.bestAirframe?.raw ?? "-")"
        }.joined(separator: " · ")
        print("NEXTMOVES \(home.raw): \(summary)")
        if anyPays {
            for market in recommended {
                #expect(market.paysForItsAirframe,
                        "\(home.raw) still offers \(market.origin.raw)-\(market.destination.raw), which keeps \(market.monthlyAfterAirframe.compact) a month after its aircraft")
            }
        }
    }

    /// NEXTMOVES-02: the specific traps BUG-055 was measured on are gone from
    /// the advice. Each of these lost money after its aircraft on every
    /// era-legal airframe, and each was recommended before the fix.
    @Test(arguments: [(AirportCode("LHR"), AirportCode("CDG")),   // 347 km, fees 85% of revenue
                      ("MAN", "LHR"),                             // 243 km, fees 96%
                      ("JFK", "YYZ"),                             // 589 km, −$214k a month
                      ("SIN", "KUL"),                             // 297 km, −$598k a month
                      ("BOS", "JFK")])                            // 300 km, −$1.4M a month
    func aMarketThatCannotPayForItsAircraftIsNotRecommended(
        _ pair: (AirportCode, AirportCode)) throws {
        let (home, trap) = pair
        let (engine, catalog, _) = try Self.founded(home: home)
        let state = engine.state
        let recommended = Self.homeRecommends(state, catalog: catalog)
        #expect(!recommended.contains { $0.destination == trap },
                "\(home.raw) still recommends \(trap.raw): \(recommended.map { "\($0.destination.raw) \($0.monthlyAfterAirframe.compact)" })")

        // And the market is still there to find, priced honestly — the gate
        // orders the advice, it does not hide a city from the route sheet.
        let listed = try #require(state.marketCandidates(from: home, catalog: catalog)
            .first { $0.destination == trap })
        #expect(!listed.paysForItsAirframe,
                "\(home.raw)-\(trap.raw) is supposed to be the trap and now reads as paying \(listed.monthlyAfterAirframe.compact)")
    }

    /// NEXTMOVES-03: the advice at the three curated starts and at Munich is
    /// exactly what it was before the gate. Those are the worlds the AE-039
    /// and AE-041 twins and the UI journeys are pinned on; the fix was chosen
    /// over a full re-ranking precisely so they would not move.
    @Test func theCuratedStartsAdviceIsUnchanged() throws {
        let expected: [AirportCode: [AirportCode]] = [
            "ARN": ["LHR", "CDG"],
            "BCN": ["LHR", "CDG"],
            "SIN": ["CGK", "BKK"],   // Kuala Lumpur, the one trap, replaced
            "MUC": ["LHR", "CDG"],
        ]
        for (home, markets) in expected.sorted(by: { $0.key.raw < $1.key.raw }) {
            let (engine, catalog, _) = try Self.founded(home: home)
            let recommended = Self.homeRecommends(engine.state, catalog: catalog)
            #expect(recommended.map(\.destination) == markets,
                    "\(home.raw) now recommends \(recommended.map(\.destination.raw))")
        }
    }

    /// NEXTMOVES-04: a recommendation carries the airframe it was judged on,
    /// so the screen can name it. Nine of the ninety-three homes recommend a
    /// market that pays on a small airframe and loses on the large one the
    /// aircraft market lists first (BUG-056); the airframe is the only part
    /// of that the recommendation can answer.
    @Test func aRecommendationNamesTheAirframeItWasJudgedOn() throws {
        let (engine, catalog, _) = try Self.founded(home: "KEF")
        let recommended = Self.homeRecommends(engine.state, catalog: catalog)
        for market in recommended where market.paysForItsAirframe {
            let code = try #require(market.bestAirframe,
                                    "\(market.destination.raw) pays but names no airframe")
            let spec = try #require(catalog.aircraftType(code))
            #expect(catalog.routeEligibility(
                from: market.origin, to: market.destination,
                aircraftRangeKm: spec.rangeKm,
                aircraftRunwayRequirement: spec.runwayRequirement).isEmpty,
                    "\(market.destination.raw) names \(code.raw), which cannot fly it")
            #expect(market.monthlyAfterAirframe > .zero)
        }
    }

    /// NEXTMOVES-05: a home where nothing pays still gets advice, and the
    /// advice is honest about it. From Nadi in the startup era no market
    /// covers its own airframe — the best loses $897k a month — and the two
    /// largest are beyond every era airframe's range. The player must not be
    /// stranded without a first route to open, and must not be told the
    /// least bad option is strong.
    @Test func aHomeWhereNothingPaysStillGetsAdviceAndSaysSo() throws {
        let (engine, catalog, _) = try Self.founded(home: "NAN")
        let state = engine.state
        let recommended = Self.homeRecommends(state, catalog: catalog)
        #expect(!recommended.isEmpty, "Nadi is offered nothing at all")
        #expect(!recommended.contains { $0.paysForItsAirframe },
                "Nadi now has a market that pays; the fixture has moved")
        // The checklist can still teach the first route.
        let onboarding = try #require(state.onboardingModel(catalog: catalog))
        #expect(!onboarding.suggestions.isEmpty)
    }

    // MARK: The campaign

    /// NEXTMOVES-06: the BUG-055 regression. A player who follows Home's
    /// advice from New York — the checklist's first route, then the two
    /// markets Next Moves names, on the aircraft the market's own default
    /// sort offers first — is still flying after the window in which the old
    /// advice bankrupted them.
    ///
    /// MEASURED before the fix (`ae-rival-scan 730 2030-2059 JFK --player`):
    /// administration and collapse on day 430 in 28 of 30 seeds, ending at
    /// −$2.0M to −$2.9M. The same script on the same seed after the fix:
    /// alive. This test plays that script through real commands.
    ///
    /// The limit is ten minutes against **65 seconds of work** (MEASURED,
    /// AE-043, run alone on the session container). It was five, and CI run
    /// 136 tripped it on code byte-identical to run 135, where it passed —
    /// after every assertion in the body had already succeeded and the result
    /// line had printed. Swift Testing measures a time limit as wall clock
    /// while the whole 457-test suite runs in parallel, so five minutes was
    /// measuring how contended the runner was, not how long this campaign
    /// takes. Ten leaves a runaway nowhere to hide and stops the suite
    /// reporting the machine's load as a product failure. No assertion here
    /// changed.
    @Test(.timeLimit(.minutes(10)))
    func followingTheAdviceFromNewYorkDoesNotBankruptThePlayer() async throws {
        let (engine, catalog, scenario) = try Self.founded(home: "JFK")
        let player = engine.state.playerAirline!.id
        let ticksPerDay = Int(GameCalendar.minutesPerDay / ScenarioBootstrap.standardTickMinutes)

        /// The largest airframe the era allows that can fly the pair — what
        /// the aircraft market's default sort (seats, descending) puts first.
        func marketDefaultAirframe(for market: MarketOpportunity) -> AircraftTypeSpec? {
            let allowed = engine.state.progression.era.allowedCategories
            return catalog.orderedAircraftTypeCodes
                .compactMap { catalog.aircraftTypes[$0] }
                .filter { allowed.contains($0.category) }
                .filter {
                    catalog.routeEligibility(
                        from: market.origin, to: market.destination,
                        aircraftRangeKm: $0.rangeKm,
                        aircraftRunwayRequirement: $0.runwayRequirement).isEmpty
                }
                .max { ($0.seats, $0.code.raw) < ($1.seats, $1.code.raw) }
        }

        @discardableResult
        func take(_ market: MarketOpportunity) -> Bool {
            guard let spec = marketDefaultAirframe(for: market),
                  engine.applyNow(LeaseAircraftCommand(
                    lessee: player, type: spec.code, termMonths: 60)) == .applied,
                  let aircraft = engine.state.fleet(of: player)
                    .first(where: { $0.assignedRoute == nil && $0.isOperational })
            else { return false }
            let fare = DemandSystem.referenceFare(distanceKm: market.distanceKm,
                                                  tuning: catalog.tuning.demand)
            guard engine.applyNow(OpenRouteCommand(
                airline: player, origin: market.origin, destination: market.destination,
                dailyRoundTrips: 2, ticketPrice: Money(rounding: fare))) == .applied,
                  let route = engine.state.routes(of: player).first(where: {
                      $0.sameMarket(origin: market.origin, destination: market.destination)
                  })
            else { return false }
            return engine.applyNow(AssignAircraftToRouteCommand(
                airline: player, route: route.id, aircraftID: aircraft.id)) == .applied
        }

        // Day 0: the checklist's own first suggestion.
        let first = try #require(engine.state.onboardingModel(catalog: catalog)?.suggestions.first)
        let firstMarket = try #require(engine.state.marketOpportunities(catalog: catalog, limit: 4)
            .first { $0.destination == first.destination })
        #expect(firstMarket.paysForItsAirframe,
                "New York's guided first route no longer pays for its aircraft")
        #expect(take(firstMarket), "could not open the guided first route")

        var followed: [String] = []
        var opened = 1
        var lastMonth = -1
        var lowestCash = engine.state.ledger.balance(of: player)
        for day in 1...500 {
            engine.advance(ticks: ticksPerDay)
            let state = engine.state
            let airline = try #require(state.airlines[player])
            #expect(airline.status != .collapsed,
                    "the player collapsed on day \(day) following Home's advice — BUG-055")
            lowestCash = min(lowestCash, state.ledger.balance(of: player))
            let date = state.currentDate
            guard date.day == 1, date.month != lastMonth, opened < 6 else { continue }
            lastMonth = date.month
            // What Home says this morning, taken as a player would take it.
            for market in Self.homeRecommends(state, catalog: catalog) {
                #expect(market.paysForItsAirframe,
                        "day \(day): Home recommends \(market.origin.raw)-\(market.destination.raw), which keeps \(market.monthlyAfterAirframe.compact) a month after its aircraft")
                if take(market) {
                    opened += 1
                    followed.append("D\(day) \(market.origin.raw)-\(market.destination.raw)")
                }
            }
        }

        let final = engine.state
        let airline = try #require(final.airlines[player])
        let cash = final.ledger.balance(of: player)
        print("NEXTMOVES-NY followed \(followed) · status \(airline.status) · cash \(cash.compact) · lowest \(lowestCash.compact) · routes \(final.routes(of: player).count) · administrations \(airline.administrationCount)")

        #expect(airline.status == .active)
        #expect(airline.administrationCount == 0,
                "the player went into administration following the advice")
        // Not merely solvent: better off than they started, which the old
        // advice never managed from New York.
        #expect(cash > scenario.playerStartingCash,
                "cash \(cash.compact) against \(scenario.playerStartingCash.compact) started with")
        #expect(final.routes(of: player).count >= 5)
    }
}
