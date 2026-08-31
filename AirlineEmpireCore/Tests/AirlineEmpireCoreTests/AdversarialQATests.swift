import Foundation
import Testing
@testable import AirlineEmpireCore

/// Phase 19: try to break the game (Master Prompt 19), headless scope.
/// Every scenario ends with a full-world sanity sweep — bugs get fixed at
/// the correct layer, never worked around in the tests.
@Suite("Adversarial QA")
struct AdversarialQATests {
    /// Global invariant sweep beyond the engine's own debug checks.
    static func assertWorldSane(_ engine: SimulationEngine,
                                sourceLocation: Testing.SourceLocation = #_sourceLocation) {
        let state = engine.state
        #expect(state.integrityViolations().isEmpty,
                "\(state.integrityViolations())", sourceLocation: sourceLocation)
        for code in engine.catalog.orderedAirportCodes {
            guard let spec = engine.catalog.airports[code] else { continue }
            let used = state.world.slotsUsed(at: code)
            #expect(used >= 0 && used <= spec.slotCapacityPerDay,
                    "Airport \(code) slots \(used)/\(spec.slotCapacityPerDay)",
                    sourceLocation: sourceLocation)
        }
        for route in state.routes.values {
            #expect(route.dailyRoundTrips >= 1 && route.dailyRoundTrips <= 20,
                    sourceLocation: sourceLocation)
            #expect(route.ticketPrice > .zero, sourceLocation: sourceLocation)
            #expect(route.remainingOutboundToday >= 0
                    && route.remainingInboundToday >= 0,
                    sourceLocation: sourceLocation)
        }
        for aircraft in state.aircraft.values {
            #expect(aircraft.condition >= 0 && aircraft.condition <= 1,
                    sourceLocation: sourceLocation)
            #expect(aircraft.totalFlightHours.isFinite && aircraft.totalFlightHours >= 0,
                    sourceLocation: sourceLocation)
        }
        for airline in state.airlines.values {
            let balance = state.ledger.balance(of: airline.id)
            #expect(balance.cents > Int64.min / 4 && balance.cents < Int64.max / 4,
                    sourceLocation: sourceLocation)
        }
    }

    @Test func duplicateAndConflictingCommandBatch() throws {
        // The same route opened twice in one drained batch: first applies,
        // second rejects; slots allocated exactly once.
        let (_, engine, airline, aircraft) = try RouteFixtures.withAircraft()
        for _ in 0..<5 {
            engine.enqueue(OpenRouteCommand(airline: airline, origin: "ARN",
                                            destination: "LHR", dailyRoundTrips: 2,
                                            ticketPrice: Money.dollars(129)))
        }
        for _ in 0..<5 {
            engine.enqueue(AssignAircraftToRouteCommand(
                airline: airline,
                route: RouteID(raw: engine.state.meta.idAllocator.nextByKind["route"] ?? 1),
                aircraftID: aircraft))
        }
        engine.advance(ticks: 1)
        let applied = engine.lastCommandResults.filter { $0 == .applied }.count
        #expect(applied == 2, "expected 1 open + 1 assign, got \(applied)")
        #expect(engine.state.routes.count == 1)
        #expect(engine.state.world.slotsHeld(by: airline, at: "ARN") == 4)
        Self.assertWorldSane(engine)
    }

    @Test func openCloseChurnConservesSlots() throws {
        let (_, engine, airline, aircraft) = try RouteFixtures.withAircraft()
        for cycle in 0..<50 {
            let destination: AirportCode = cycle % 2 == 0 ? "LHR" : "CPH"
            let open = engine.applyNow(OpenRouteCommand(
                airline: airline, origin: "ARN", destination: destination,
                dailyRoundTrips: 1 + cycle % 5, ticketPrice: Money.dollars(99)))
            #expect(open == .applied)
            let route = engine.state.routes.values.first { $0.airline == airline }!.id
            _ = engine.applyNow(AssignAircraftToRouteCommand(
                airline: airline, route: route, aircraftID: aircraft))
            // Let some operations happen on every third cycle.
            if cycle % 3 == 0 {
                engine.advance(ticks: Fixtures.ticksPerDay / 2)
            }
            // Close (wait out airborne rejection when needed).
            var closed = false
            for _ in 0..<(Fixtures.ticksPerDay * 2) {
                if engine.applyNow(CloseRouteCommand(airline: airline, route: route))
                    == .applied {
                    closed = true
                    break
                }
                engine.advance(ticks: 1)
            }
            #expect(closed, "cycle \(cycle) could not close")
        }
        // Everything released: zero slots held anywhere, no flights left.
        for code in engine.catalog.orderedAirportCodes {
            #expect(engine.state.world.slotsHeld(by: airline, at: code) == 0,
                    "leaked slots at \(code)")
        }
        #expect(engine.state.flights.isEmpty)
        #expect(engine.state.aircraft[aircraft] != nil)
        Self.assertWorldSane(engine)
    }

    @Test func buySellStormMidOperations() throws {
        let (_, engine, airline, _) = try RouteFixtures.withAircraft()
        RouteFixtures.openStvLnw(engine, airline, trips: 3)
        let route = engine.state.routes.values.first!.id
        let workhorse = engine.state.aircraft.values.first!.id
        _ = engine.applyNow(AssignAircraftToRouteCommand(
            airline: airline, route: route, aircraftID: workhorse))
        for day in 0..<30 {
            _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "NA70",
                                                       ageYears: 1 + day % 20))
            _ = engine.applyNow(LeaseAircraftCommand(lessee: airline, type: "AV90",
                                                     termMonths: 12))
            engine.advance(ticks: Fixtures.ticksPerDay)
            // Sell/return everything idle, repeatedly.
            for aircraft in engine.state.fleet(of: airline)
            where aircraft.assignedRoute == nil && aircraft.isReadyToFly {
                if aircraft.ownership.isLeased {
                    _ = engine.applyNow(ReturnLeasedAircraftCommand(
                        lessee: airline, aircraftID: aircraft.id))
                } else {
                    _ = engine.applyNow(SellAircraftCommand(
                        seller: airline, aircraftID: aircraft.id))
                }
            }
        }
        // The operation never corrupted; the workhorse still flies.
        #expect(engine.state.aircraft[workhorse] != nil)
        #expect(engine.state.routes[route]!.stats.flightsCompleted > 0)
        Self.assertWorldSane(engine)
    }

    @Test func speedThrashMatchesStraightRun() async throws {
        // Session-level chunk thrash: alternating speeds and manual
        // advances must land byte-identical with a straight advance of the
        // same total ticks.
        let catalog = try ContentCatalog.loadBundled()
        func newSession() -> GameSession {
            let session = GameSession(state: Fixtures.newState(seed: 321),
                                      systems: GamePipeline.standard(), catalog: catalog)
            return session
        }
        let thrashed = newSession()
        _ = await thrashed.submit(FoundAirlineCommand(
            airlineName: "Thrash", kind: .player, homeAirport: "ARN",
            startingCash: Money.dollars(50_000_000)))
        var total = 0
        var step = 1
        while total < Fixtures.ticksPerDay * 10 {
            let n = min(step, Fixtures.ticksPerDay * 10 - total)
            await thrashed.advance(ticks: n)
            total += n
            step = step % 17 + 1
            await thrashed.setSpeed([SimSpeed.paused, .x1, .x4, .x16][step % 4])
        }
        let straight = newSession()
        _ = await straight.submit(FoundAirlineCommand(
            airlineName: "Thrash", kind: .player, homeAirport: "ARN",
            startingCash: Money.dollars(50_000_000)))
        await straight.advance(ticks: Fixtures.ticksPerDay * 10)
        let a = try await thrashed.snapshot.stateHash()
        let b = try await straight.snapshot.stateHash()
        #expect(a == b)
    }

    @Test func giantNetworkSurvivesAndPerforms() throws {
        // A deliberately oversized operation: ~30 aircraft, ~25 routes.
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(seed: 987),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Leviathan", kind: .player, homeAirport: "LHR",
            startingCash: Money.dollars(3_000_000_000)))
        let player = engine.state.playerAirline!.id
        let destinations = catalog.nearestAirports(to: "LHR", limit: 30)
            .map(\.0.code)
        var opened = 0
        for destination in destinations where opened < 25 {
            let open = engine.applyNow(OpenRouteCommand(
                airline: player, origin: "LHR", destination: destination,
                dailyRoundTrips: 2, ticketPrice: Money.dollars(119)))
            guard open == .applied else { continue }
            opened += 1
            _ = engine.applyNow(BuyUsedAircraftCommand(buyer: player, type: "MR180",
                                                       ageYears: 5))
            if let idle = engine.state.fleet(of: player).first(where: {
                $0.assignedRoute == nil && $0.isOperational
            }), let route = engine.state.routes.values.first(where: {
                $0.airline == player && $0.destination == destination
            }) {
                _ = engine.applyNow(AssignAircraftToRouteCommand(
                    airline: player, route: route.id, aircraftID: idle.id))
            }
        }
        #expect(opened >= 20, "only \(opened) routes opened")

        // One game-year over a big network: correct and fast enough.
        let start = ContinuousClock.now
        engine.advance(ticks: Fixtures.ticksPerYear)
        let elapsed = start.duration(to: .now)
        #expect(elapsed < .seconds(120), "1y giant-network sim took \(elapsed)")

        Self.assertWorldSane(engine)
        let totalPax = engine.state.routes(of: player)
            .reduce(Int64(0)) { $0 + $1.stats.passengersCarried }
        #expect(totalPax > 500_000, "carried \(totalPax)")
    }

    @Test func corruptSaveFuzzNeverCrashes() throws {
        let (engine, _, _) = try DemandFixtures.market(fare: Money.dollars(129))
        engine.advance(ticks: Fixtures.ticksPerDay * 15)
        let codec = JSONSaveCodec()
        let pristine = try codec.encode(engine.state)
        var rng = RNGState(worldSeed: 20_260_825)
        var recovered = 0
        for _ in 0..<60 {
            var mutated = pristine
            // 1-4 deterministic byte flips anywhere in the file.
            for _ in 0...(rng.int("fuzz.count", in: 0...3)) {
                let index = rng.int("fuzz.index", in: 0...(mutated.count - 1))
                mutated[index] ^= UInt8(rng.int("fuzz.bit", in: 1...255))
            }
            do {
                let state = try codec.decode(mutated)
                // A flip that survived checksum+decode must yield a state
                // identical to the original (flip hit encoding slack like
                // whitespace) — silent divergence is unacceptable.
                #expect(state == engine.state)
                recovered += 1
            } catch is SaveError {
                // Honest refusal is the expected outcome.
            } catch {
                Issue.record("Unexpected error type: \(error)")
            }
        }
        // Sanity: the fuzz actually corrupted most attempts.
        #expect(recovered < 20)
    }

    @Test func frequencyThrashKeepsSlotLedgerExact() throws {
        let (_, engine, airline, aircraft) = try RouteFixtures.withAircraft()
        let route = RouteFixtures.openStvLnw(engine, airline, trips: 1)
        _ = engine.applyNow(AssignAircraftToRouteCommand(
            airline: airline, route: route, aircraftID: aircraft))
        var expected = 1
        var rng = RNGState(worldSeed: 5150)
        for _ in 0..<200 {
            let target = rng.int("freq", in: 1...20)
            let result = engine.applyNow(SetRouteFrequencyCommand(
                airline: airline, route: route, dailyRoundTrips: target))
            if result == .applied { expected = target }
            if rng.chance("advance", probability: 0.2) {
                engine.advance(ticks: 3)
            }
            #expect(engine.state.world.slotsHeld(by: airline, at: "ARN")
                    == Route.dailySlotMovements(roundTrips: expected))
        }
        Self.assertWorldSane(engine)
    }

    @Test func collapseDuringHeavyOperationsCleansUp() throws {
        // An airline dies WITH a big live operation: everything must
        // release without dangling references.
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(seed: 111),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Doom Ops", kind: .ai, homeAirport: "LHR",
            startingCash: Money.dollars(140_000_000)))
        let airline = engine.state.airlines.values.first!.id
        for destination: AirportCode in ["CDG", "AMS", "FRA"] {
            _ = engine.applyNow(LeaseAircraftCommand(lessee: airline, type: "MR180",
                                                     termMonths: 60))
            _ = engine.applyNow(OpenRouteCommand(
                airline: airline, origin: "LHR", destination: destination,
                dailyRoundTrips: 6, ticketPrice: Money.dollars(15))) // ruinous fare
            if let idle = engine.state.fleet(of: airline).first(where: {
                $0.assignedRoute == nil
            }), let route = engine.state.routes.values.first(where: {
                $0.destination == destination
            }) {
                _ = engine.applyNow(AssignAircraftToRouteCommand(
                    airline: airline, route: route.id, aircraftID: idle.id))
            }
        }
        // Note: airline is .ai but has NO aiProfile -> it never retrenches;
        // dumping fares while leasing guarantees the solvency spiral.
        engine.advance(ticks: Fixtures.ticksPerYear * 3)
        let final = engine.state.airlines[airline]!
        #expect(final.status == .collapsed)
        #expect(engine.state.routes(of: airline).isEmpty)
        #expect(engine.state.fleet(of: airline).isEmpty)
        for code in engine.catalog.orderedAirportCodes {
            #expect(engine.state.world.slotsHeld(by: airline, at: code) == 0)
        }
        engine.advance(ticks: Fixtures.ticksPerDay * 30) // world keeps running
        Self.assertWorldSane(engine)
    }
}
