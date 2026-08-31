import Testing
@testable import AirlineEmpireCore

/// The canonical calibration market (docs/GAME_BALANCE.md §4): two mid-size
/// cities ~1100 km apart, one narrowbody at 2x/day, reference-ish fare.
enum DemandFixtures {
    static func anchorCatalog() throws -> ContentCatalog {
        let metroburg = AirportSpec(
            code: "MET", name: "Metroburg Central", city: "Metroburg", country: "Testland",
            region: .europe, coordinate: Coordinate(latitude: 50.0, longitude: 8.0),
            utcOffsetMinutes: 60, runwayClass: .large, slotCapacityPerDay: 400,
            terminalCapacityPerDay: 60_000, movementFee: Money.dollars(1400),
            passengerFee: Money.dollars(16),
            demographics: Demographics(populationThousands: 4000, businessIndex: 0.6,
                                       leisureIndex: 0.6, tourismIndex: 0.5, cargoIndex: 0.5),
            seasonality: "flat", weatherRisk: .low)
        let costport = AirportSpec(
            code: "COS", name: "Costport Bay", city: "Costport", country: "Testland",
            region: .europe, coordinate: Coordinate(latitude: 50.0, longitude: 23.4), // ~1100 km
            utcOffsetMinutes: 60, runwayClass: .large, slotCapacityPerDay: 400,
            terminalCapacityPerDay: 60_000, movementFee: Money.dollars(1400),
            passengerFee: Money.dollars(16),
            demographics: Demographics(populationThousands: 4000, businessIndex: 0.6,
                                       leisureIndex: 0.6, tourismIndex: 0.5, cargoIndex: 0.5),
            seasonality: "flat", weatherRisk: .low)
        let real = try ContentCatalog.loadBundled()
        return try ContentCatalog(
            version: "anchor", airports: [metroburg, costport],
            seasonality: [TestAirports.flatProfile],
            aircraftTypes: real.orderedAircraftTypeCodes.compactMap { real.aircraftTypes[$0] },
            tuning: real.tuning)
    }

    /// Airline with one MR180 flying MET-COS at the given fare/frequency.
    static func market(fare: Money, trips: Int = 2) throws -> (SimulationEngine, AirlineID, RouteID) {
        let catalog = try anchorCatalog()
        let engine = SimulationEngine(state: Fixtures.newState(),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(airlineName: "Anchor Air", kind: .player,
                                                homeAirport: "MET",
                                                startingCash: Money.dollars(300_000_000)))
        let airline = engine.state.airlines.values.first!.id
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180", ageYears: 2))
        let aircraft = engine.state.aircraft.values.first!.id
        let open = engine.applyNow(OpenRouteCommand(
            airline: airline, origin: "MET", destination: "COS",
            dailyRoundTrips: trips, ticketPrice: fare))
        precondition(open == .applied)
        let route = engine.state.routes.values.first!.id
        _ = engine.applyNow(AssignAircraftToRouteCommand(
            airline: airline, route: route, aircraftID: aircraft))
        return (engine, airline, route)
    }

    /// Runs 4 full weeks and returns (avg daily pax per direction-pair sum,
    /// load factor, ticket revenue).
    static func runMonth(fare: Money, trips: Int = 2) throws
        -> (paxPerDay: Double, load: Double, revenue: Money) {
        let (engine, airline, route) = try market(fare: fare, trips: trips)
        engine.advance(ticks: Fixtures.ticksPerDay * 28)
        let stats = engine.state.routes[route]!.stats
        let revenue = engine.state.ledger.recent
            .filter { $0.airline == airline && $0.category == .ticketRevenue }
            .reduce(Money.zero) { $0 + $1.amount }
        return (Double(stats.passengersCarried) / 28.0, stats.loadFactor, revenue)
    }
}

@Suite("Demand engine")
struct DemandEngineTests {
    @Test func anchorMarketHitsCalibration() throws {
        // GAME_BALANCE §4: ~1100 km narrowbody market around reference fare
        // should fill a meaningful share of 720 daily seats (2 round trips).
        let (pax, load, _) = try DemandFixtures.runMonth(fare: Money.dollars(129))
        #expect(pax > 350 && pax < 620, "pax/day was \(pax)")
        #expect(load > 0.55 && load < 0.92, "load was \(load)")
    }

    @Test func priceDemandCurveSlopesDown() throws {
        let cheap = try DemandFixtures.runMonth(fare: Money.dollars(70))
        let reference = try DemandFixtures.runMonth(fare: Money.dollars(129))
        let premium = try DemandFixtures.runMonth(fare: Money.dollars(220))
        let absurd = try DemandFixtures.runMonth(fare: Money.dollars(500))
        #expect(cheap.load >= reference.load)
        #expect(reference.load > premium.load)
        #expect(premium.load > absurd.load)
        #expect(absurd.load < 0.15)
    }

    @Test func revenueHasAnInteriorOptimum() throws {
        // The strategic tradeoff (docs/GAME_BALANCE.md §5): dumping fares
        // caps out capacity at low yield, absurd fares empty the cabin;
        // somewhere near/above reference is best.
        let cheap = try DemandFixtures.runMonth(fare: Money.dollars(60))
        let reference = try DemandFixtures.runMonth(fare: Money.dollars(129))
        let high = try DemandFixtures.runMonth(fare: Money.dollars(160))
        let absurd = try DemandFixtures.runMonth(fare: Money.dollars(500))
        #expect(reference.revenue > cheap.revenue)
        #expect(reference.revenue > absurd.revenue)
        // Mild monopoly premium is allowed; collapse is not.
        #expect(high.revenue > absurd.revenue)
    }

    @Test func frequencyImprovesShareWithDiminishingReturns() throws {
        let one = try DemandFixtures.runMonth(fare: Money.dollars(129), trips: 1)
        let two = try DemandFixtures.runMonth(fare: Money.dollars(129), trips: 2)
        // More frequency, more total passengers...
        #expect(two.paxPerDay > one.paxPerDay)
        // ...but far from double (share gain is sublinear AND capacity was
        // not the binding constraint at 1x for this market).
        #expect(two.paxPerDay < one.paxPerDay * 1.9)
    }

    @Test func competitionSplitsTheMarket() throws {
        let catalog = try DemandFixtures.anchorCatalog()
        let engine = SimulationEngine(state: Fixtures.newState(),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(airlineName: "Anchor Air", kind: .player,
                                                homeAirport: "MET",
                                                startingCash: Money.dollars(300_000_000)))
        _ = engine.applyNow(FoundAirlineCommand(airlineName: "Rival Air", kind: .ai,
                                                homeAirport: "COS",
                                                startingCash: Money.dollars(300_000_000)))
        let player = engine.state.airlines.values.first { $0.kind == .player }!.id
        let rival = engine.state.airlines.values.first { $0.kind == .ai }!.id
        for (airline, home) in [(player, "MET"), (rival, "COS")] {
            _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180", ageYears: 2))
            let aircraft = engine.state.aircraft.values.first {
                $0.owner == airline && $0.assignedRoute == nil }!.id
            _ = engine.applyNow(OpenRouteCommand(
                airline: airline, origin: AirportCode(home),
                destination: AirportCode(home == "MET" ? "COS" : "MET"),
                dailyRoundTrips: 2, ticketPrice: Money.dollars(129)))
            let route = engine.state.routes.values.first { $0.airline == airline }!.id
            _ = engine.applyNow(AssignAircraftToRouteCommand(
                airline: airline, route: route, aircraftID: aircraft))
        }
        engine.advance(ticks: Fixtures.ticksPerDay * 28)

        let playerRoute = engine.state.routes.values.first { $0.airline == player }!
        let rivalRoute = engine.state.routes.values.first { $0.airline == rival }!
        let playerPax = Double(playerRoute.stats.passengersCarried)
        let rivalPax = Double(rivalRoute.stats.passengersCarried)
        // Same product, same price -> roughly even split.
        #expect(abs(playerPax - rivalPax) / max(playerPax, rivalPax) < 0.15)

        // And a solo run carries meaningfully more than a contested one.
        let solo = try DemandFixtures.runMonth(fare: Money.dollars(129))
        #expect(playerPax / 28 < solo.paxPerDay)
    }

    @Test func undercuttingStealsShare() throws {
        let catalog = try DemandFixtures.anchorCatalog()
        let engine = SimulationEngine(state: Fixtures.newState(),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(airlineName: "Full Fare", kind: .player,
                                                homeAirport: "MET",
                                                startingCash: Money.dollars(300_000_000)))
        _ = engine.applyNow(FoundAirlineCommand(airlineName: "Cut Rate", kind: .ai,
                                                homeAirport: "COS",
                                                startingCash: Money.dollars(300_000_000)))
        let expensive = engine.state.airlines.values.first { $0.name == "Full Fare" }!.id
        let cheap = engine.state.airlines.values.first { $0.name == "Cut Rate" }!.id
        for (airline, fare) in [(expensive, 150), (cheap, 95)] {
            _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180", ageYears: 2))
            let aircraft = engine.state.aircraft.values.first {
                $0.owner == airline && $0.assignedRoute == nil }!.id
            let home = engine.state.airlines[airline]!.homeAirport
            let away: AirportCode = home == AirportCode("MET") ? "COS" : "MET"
            _ = engine.applyNow(OpenRouteCommand(
                airline: airline, origin: home, destination: away,
                dailyRoundTrips: 2, ticketPrice: Money.dollars(Int64(fare))))
            let route = engine.state.routes.values.first { $0.airline == airline }!.id
            _ = engine.applyNow(AssignAircraftToRouteCommand(
                airline: airline, route: route, aircraftID: aircraft))
        }
        engine.advance(ticks: Fixtures.ticksPerDay * 28)
        let expensivePax = engine.state.routes.values.first { $0.airline == expensive }!
            .stats.passengersCarried
        let cheapPax = engine.state.routes.values.first { $0.airline == cheap }!
            .stats.passengersCarried
        #expect(Double(cheapPax) > Double(expensivePax) * 1.3,
                "undercutter \(cheapPax) vs premium \(expensivePax)")
    }

    @Test func seasonalityMovesLeisureDemand() throws {
        // Same market, summer-sun destination profile: July >> January.
        let catalog = try ContentCatalog.loadBundled()
        let january = DemandSystem.demandPool(
            from: "ARN", to: "PMI",
            date: GameCalendar.date(at: GameCalendar.time(year: 2030, month: 1, day: 10,
                                                          startYear: 2030), startYear: 2030),
            economicIndex: 1.0, catalog: catalog)
        let july = DemandSystem.demandPool(
            from: "ARN", to: "PMI",
            date: GameCalendar.date(at: GameCalendar.time(year: 2030, month: 7, day: 10,
                                                          startYear: 2030), startYear: 2030),
            economicIndex: 1.0, catalog: catalog)
        #expect(july.leisure > january.leisure * 2)
        // Business demand is season-flat (same weekday chosen: both the
        // 10th... may differ in weekday; compare against weekday factors).
        #expect(july.business > 0 && january.business > 0)
    }

    @Test func economyIndexShiftsDemand() throws {
        let catalog = try ContentCatalog.loadBundled()
        let date = GameCalendar.date(at: .epoch, startYear: 2030)
        let boom = DemandSystem.demandPool(from: "LHR", to: "JFK", date: date,
                                           economicIndex: 1.2, catalog: catalog)
        let bust = DemandSystem.demandPool(from: "LHR", to: "JFK", date: date,
                                           economicIndex: 0.8, catalog: catalog)
        #expect(boom.business > bust.business * 1.5)
        #expect(boom.leisure > bust.leisure)
        // Business swings harder than leisure (docs/GAME_DESIGN.md §4.17).
        #expect(boom.business / bust.business > boom.leisure / bust.leisure)
    }

    @Test func demandIsConserved() throws {
        // Passengers carried never exceed the demand the system granted.
        // Exactly one daily grant occurs per one-day advance; sum them all
        // (grants sampled at an iteration's end are consumed the following
        // iteration, so carried <= granted holds strictly).
        let (engine, _, route) = try DemandFixtures.market(fare: Money.dollars(99))
        var granted = 0
        for _ in 0..<21 {
            engine.advance(ticks: Fixtures.ticksPerDay)
            let r = engine.state.routes[route]!
            granted += r.demandOutboundToday + r.demandInboundToday
        }
        let carried = engine.state.routes[route]!.stats.passengersCarried
        #expect(carried <= Int64(granted))
        #expect(carried > 0)
    }

    @Test func revenueIsPostedPerDepartureAndTraceable() throws {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        engine.advance(ticks: Fixtures.ticksPerDay * 7)
        let revenues = engine.state.ledger.recent.filter {
            $0.airline == airline && $0.category == .ticketRevenue
        }
        #expect(!revenues.isEmpty)
        // Each posting = passengers x fare: divisible by the fare.
        for tx in revenues {
            #expect(tx.amount.cents % Money.dollars(129).cents == 0)
            #expect(tx.amount > .zero)
        }
    }

    @Test func anchorRouteIsProfitableAtReferenceFare() throws {
        // The whole point of Phase 7: a sensible route now MAKES money.
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        engine.advance(ticks: Fixtures.ticksPerDay * 28)
        // Ignore capital transactions; compare operating flows only.
        let operating: Set<TransactionCategory> = [.ticketRevenue, .fuel, .airportFees,
                                                   .crewCosts, .maintenance]
        let net = engine.state.ledger.recent
            .filter { $0.airline == airline && operating.contains($0.category) }
            .reduce(Money.zero) { $0 + $1.amount }
        #expect(net > .zero, "Operating net was \(net.cents) cents")
    }

    @Test func fullPipelineDeterminismWithDemand() throws {
        func run() throws -> UInt64 {
            let (engine, _, _) = try DemandFixtures.market(fare: Money.dollars(119))
            engine.advance(ticks: Fixtures.ticksPerDay * 40)
            return try engine.state.stateHash()
        }
        #expect(try run() == run())
    }
}
