import Testing
@testable import AirlineEmpireCore

/// Phase 18 strategy battery (docs/GAME_BALANCE.md §6): headless multi-year
/// worlds measuring strategy outcomes. Assertions encode the red-flag list —
/// dominant strategies, money printers, impossible starts, dead mechanics,
/// runaway concentration. Deterministic: fixed seeds, no wall clock.
@Suite("Balance battery")
struct BalanceTests {
    struct Outcome {
        let archetype: AIArchetype
        let survived: Bool
        let netWorthCents: Int64
        let passengers: Int64
        let operatingMargin: Double?
    }

    /// A world of archetype-driven airlines only (the shared AI drives every
    /// strategy through player-identical commands), run for `years`.
    static func archetypeWorld(seed: UInt64, years: Int) throws -> [Outcome] {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(seed: seed),
                                      systems: GamePipeline.standard(), catalog: catalog)
        let homes: [AirportCode] = ["LNW", "NYH", "SGM", "DXG", "SPG"]
        for (index, archetype) in AIArchetype.allCases.enumerated() {
            let profile = AIProfile(archetype: archetype)
            _ = engine.applyNow(FoundAirlineCommand(
                airlineName: "Bench \(archetype.rawValue)", kind: .ai,
                homeAirport: homes[index], startingCash: Money.dollars(120_000_000),
                aiProfile: profile))
            let airline = engine.state.airlines.values.first {
                $0.name == "Bench \(archetype.rawValue)" }!.id
            if profile.prefersLeasing {
                _ = engine.applyNow(LeaseAircraftCommand(
                    lessee: airline, type: "MR180", termMonths: 60))
            } else {
                _ = engine.applyNow(BuyUsedAircraftCommand(
                    buyer: airline, type: "MR180", ageYears: profile.usedAgeYears))
            }
        }
        engine.advance(ticks: Fixtures.ticksPerYear * years)

        return engine.state.orderedAirlineIDs.compactMap { airlineID in
            guard let airline = engine.state.airlines[airlineID],
                  let profile = airline.aiProfile else { return nil }
            let netWorth = CreditMath.assets(of: airlineID, state: engine.state)
                - CreditMath.totalDebt(of: airline)
            let passengers = engine.state.routes(of: airlineID)
                .reduce(Int64(0)) { $0 + $1.stats.passengersCarried }
            let statements = engine.state.finance.byAirline[airlineID]?.statements ?? []
            let margin: Double?
            let revenue = statements.reduce(Int64(0)) { $0 + $1.operatingRevenue.cents }
            if revenue > 0 {
                let profit = statements.reduce(Int64(0)) { $0 + $1.operatingProfit.cents }
                margin = Double(profit) / Double(revenue)
            } else {
                margin = nil
            }
            return Outcome(archetype: profile.archetype,
                           survived: airline.status == .active,
                           netWorthCents: netWorth.cents,
                           passengers: passengers,
                           operatingMargin: margin)
        }
    }

    @Test(.timeLimit(.minutes(10)))
    func archetypeParityAndSanity() throws {
        var byArchetype: [AIArchetype: [Int64]] = [:]
        var survivors = 0
        var total = 0
        for seed: UInt64 in [11, 22, 33] {
            let outcomes = try Self.archetypeWorld(seed: seed, years: 4)
            for outcome in outcomes {
                byArchetype[outcome.archetype, default: []].append(outcome.netWorthCents)
                total += 1
                if outcome.survived { survivors += 1 }
                // Money-printer red flag: nobody mints absurd wealth from
                // 120M in four years.
                #expect(outcome.netWorthCents < 3_000_000_000_00,
                        "\(outcome.archetype) net worth \(outcome.netWorthCents)")
                // Uncontested mega-market routes earn scarcity rents
                // (fleet capacity << demand pool). Finding recorded in
                // docs/BALANCING.md: the compression mechanism is ENTRY,
                // verified by contestedMarketsCompressMargins below. The
                // bench bound is the money-printer line, not the target.
                if let margin = outcome.operatingMargin, outcome.passengers > 100_000 {
                    #expect(margin < 0.60,
                            "\(outcome.archetype) margin \(margin)")
                }
            }
        }
        // Impossible-start red flag: the world must be survivable.
        #expect(Double(survivors) / Double(total) >= 0.6,
                "Only \(survivors)/\(total) archetype runs survived")
        // Dominant-strategy red flag: median outcomes within a loose band.
        let medians = byArchetype.mapValues { values -> Int64 in
            values.sorted()[values.count / 2]
        }
        let positives = medians.values.filter { $0 > 0 }
        if let best = positives.max(), let worst = positives.min(), worst > 0 {
            #expect(Double(best) / Double(worst) < 6.0,
                    "Archetype spread too wide: \(medians)")
        }
    }

    @Test(.timeLimit(.minutes(10)))
    func contestedMarketsCompressMargins() throws {
        // Two carriers on the anchor market: competition + the outside
        // option must pull operating margins toward the 3-8% design band
        // (docs/GAME_BALANCE.md §1) — nothing like the uncontested rents.
        let catalog = try DemandFixtures.anchorCatalog()
        let engine = SimulationEngine(state: Fixtures.newState(seed: 77),
                                      systems: GamePipeline.standard(), catalog: catalog)
        for (name, home) in [("Alpha", "MET"), ("Beta", "COS")] {
            _ = engine.applyNow(FoundAirlineCommand(
                airlineName: name, kind: name == "Alpha" ? .player : .ai,
                homeAirport: AirportCode(home),
                startingCash: Money.dollars(300_000_000)))
            let airline = engine.state.airlines.values.first { $0.name == name }!.id
            _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180",
                                                       ageYears: 3))
            let aircraft = engine.state.aircraft.values.first {
                $0.owner == airline && $0.assignedRoute == nil }!.id
            let away: AirportCode = home == "MET" ? "COS" : "MET"
            _ = engine.applyNow(OpenRouteCommand(
                airline: airline, origin: AirportCode(home), destination: away,
                dailyRoundTrips: 3, ticketPrice: Money.dollars(129)))
            let route = engine.state.routes.values.first { $0.airline == airline }!.id
            _ = engine.applyNow(AssignAircraftToRouteCommand(
                airline: airline, route: route, aircraftID: aircraft))
        }
        engine.advance(ticks: Fixtures.ticksPerYear)
        for airlineID in engine.state.orderedAirlineIDs {
            let statements = engine.state.finance.byAirline[airlineID]?.statements ?? []
            let revenue = statements.reduce(Int64(0)) { $0 + $1.operatingRevenue.cents }
            guard revenue > 0 else { continue }
            let profit = statements.reduce(Int64(0)) { $0 + $1.operatingProfit.cents }
            let margin = Double(profit) / Double(revenue)
            #expect(margin < 0.25, "contested margin \(margin)")
        }
    }

    @Test(.timeLimit(.minutes(10)))
    func passivityIsNotViableButNotInstantDeath() throws {
        // Idle cash with no operation: survives on the bank balance but
        // never progresses (a stagnation check, not a death sentence).
        let catalog = try ContentCatalog.loadBundled()
        let idle = SimulationEngine(state: Fixtures.newState(seed: 44),
                                    systems: GamePipeline.standard(), catalog: catalog)
        _ = idle.applyNow(FoundAirlineCommand(
            airlineName: "Idle", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(60_000_000)))
        idle.advance(ticks: Fixtures.ticksPerYear * 3)
        let idlePlayer = idle.state.playerAirline!
        #expect(idlePlayer.status == .active)
        #expect(idle.state.progression.era == .startup) // zero progress
        #expect(idle.state.ledger.balance(of: idlePlayer.id)
                < Money.dollars(60_000_000)) // overhead bleeds

        // Idle FLEET (leases, no routes) is a death sentence.
        let bleeding = SimulationEngine(state: Fixtures.newState(seed: 44),
                                        systems: GamePipeline.standard(), catalog: catalog)
        _ = bleeding.applyNow(FoundAirlineCommand(
            airlineName: "Bleeder", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(20_000_000)))
        let bleeder = bleeding.state.playerAirline!.id
        for _ in 0..<4 {
            _ = bleeding.applyNow(LeaseAircraftCommand(lessee: bleeder, type: "MR180",
                                                       termMonths: 60))
        }
        bleeding.advance(ticks: Fixtures.ticksPerYear * 3)
        #expect(bleeding.state.airlines[bleeder]!.status == .collapsed)
    }

    @Test(.timeLimit(.minutes(10)))
    func leverageAmplifiesButDoesNotDominate() throws {
        // Same operating script with and without max borrowing: debt should
        // fund growth, and interest drag must keep it from being free money.
        func run(borrow: Bool, seed: UInt64) throws -> Int64 {
            let catalog = try ContentCatalog.loadBundled()
            let engine = SimulationEngine(state: Fixtures.newState(seed: seed),
                                          systems: GamePipeline.standard(),
                                          catalog: catalog)
            _ = engine.applyNow(FoundAirlineCommand(
                airlineName: "Lever", kind: .player, homeAirport: "LNW",
                startingCash: Money.dollars(120_000_000)))
            let player = engine.state.playerAirline!.id
            let destinations: [AirportCode] = ["PRV", "AMD", "FRB", "MDL", "RMC",
                                               "DBK", "CPN", "ZRA", "VND", "BCM"]
            var nextDestination = 0
            for _ in 0..<24 { // two years, monthly decisions
                if borrow {
                    // Borrow whatever the validators allow, in 20M slices.
                    _ = engine.applyNow(TakeLoanCommand(
                        airline: player, amount: Money.dollars(20_000_000),
                        termMonths: 60))
                }
                _ = engine.applyNow(BuyUsedAircraftCommand(
                    buyer: player, type: "MR180", ageYears: 8))
                if let idle = engine.state.fleet(of: player).first(where: {
                    $0.isOperational && $0.assignedRoute == nil
                }), nextDestination < destinations.count {
                    let destination = destinations[nextDestination]
                    nextDestination += 1
                    _ = engine.applyNow(OpenRouteCommand(
                        airline: player, origin: "LNW", destination: destination,
                        dailyRoundTrips: 2, ticketPrice: Money.dollars(119)))
                    if let route = engine.state.routes.values.first(where: {
                        $0.airline == player && $0.destination == destination
                    }) {
                        _ = engine.applyNow(AssignAircraftToRouteCommand(
                            airline: player, route: route.id, aircraftID: idle.id))
                    }
                }
                engine.advance(ticks: Fixtures.ticksPerDay * 30)
            }
            engine.advance(ticks: Fixtures.ticksPerYear)
            let player2 = engine.state.airlines[player]!
            return (CreditMath.assets(of: player, state: engine.state)
                - CreditMath.totalDebt(of: player2)).cents
        }
        let leveraged = try run(borrow: true, seed: 55)
        let unleveraged = try run(borrow: false, seed: 55)
        // Leverage may win or lose, but a debt snowball must not mint
        // multiples of the honest baseline (GAME_BALANCE §7).
        if unleveraged > 0 {
            #expect(Double(leveraged) < Double(unleveraged) * 2.5,
                    "leverage \(leveraged) vs base \(unleveraged)")
        }
        // And borrowing must remain usable (not always ruinous): the
        // leveraged run should not end collapsed-to-zero.
        #expect(leveraged > 20_000_000_00)
    }

    @Test(.timeLimit(.minutes(10)))
    func fleetFlippingBleedsMoney() throws {
        // The flipper archetype: buy used, sell immediately, repeat.
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(seed: 66),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Flipper", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(200_000_000)))
        let player = engine.state.playerAirline!.id
        for _ in 0..<20 {
            _ = engine.applyNow(BuyUsedAircraftCommand(buyer: player, type: "MR180",
                                                       ageYears: 6))
            if let aircraft = engine.state.fleet(of: player).first {
                _ = engine.applyNow(SellAircraftCommand(seller: player,
                                                        aircraftID: aircraft.id))
            }
            engine.advance(ticks: Fixtures.ticksPerDay)
        }
        let balance = engine.state.ledger.balance(of: player)
        #expect(balance < Money.dollars(200_000_000))
        // Each flip costs real money (spread + friction): 20 flips should
        // burn well over 5% of the bankroll.
        #expect(balance < Money.dollars(190_000_000),
                "Flipping only cost \(200_000_000 - balance.cents / 100)")
    }

    @Test(.timeLimit(.minutes(15)))
    func tenYearWorldRemainsStableAndContested() throws {
        let (engine, _) = try AIFixtures.world(competitors: 5, seed: 4242)
        for _ in 0..<10 {
            engine.advance(ticks: Fixtures.ticksPerYear)
            #expect(engine.state.integrityViolations().isEmpty)
            // Fuel and economy stay inside their design clamps.
            let fuel = engine.state.world.fuelPricePerTon.asDouble
            let base = engine.catalog.tuning.ops.baseFuelPricePerTon.asDouble
            #expect(fuel >= base * 0.6 - 1 && fuel <= base * 2.2 + 1)
            #expect(engine.state.world.economicIndex > 0.7
                    && engine.state.world.economicIndex < 1.3)
            // Entity populations stay bounded.
            #expect(engine.state.flights.count < 3000)
            #expect(engine.state.aircraft.count < 300)
        }
        // Concentration red flag: lifetime pax not monopolized by one line.
        var paxByAirline: [AirlineID: Int64] = [:]
        for route in engine.state.routes.values {
            paxByAirline[route.airline, default: 0] += route.stats.passengersCarried
        }
        let totalPax = paxByAirline.values.reduce(0, +)
        if totalPax > 0 {
            let herfindahl = paxByAirline.values.reduce(0.0) { partial, pax in
                let share = Double(pax) / Double(totalPax)
                return partial + share * share
            }
            #expect(herfindahl < 0.7, "HHI \(herfindahl): near-monopoly world")
        }
        // The world stayed alive: someone is still flying after a decade.
        #expect(engine.state.flights.count + Int(totalPax) > 0)
        let activeAirlines = engine.state.airlines.values.filter {
            $0.status == .active && !engine.state.routes(of: $0.id).isEmpty
        }
        #expect(activeAirlines.count >= 2, "Only \(activeAirlines.count) active operators after 10y")
    }
}
