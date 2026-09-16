import Testing
@testable import AirlineEmpireCore

/// The fleet health board. It must rank what costs money first, keep
/// "cannot fly today" separate from "should be looked at", and quote the same
/// maintenance number the fleet system will post.
@Suite("Fleet board")
struct FleetBoardTests {
    /// An airline with one MET–COS route and `assigned + idle` MR-180s, the
    /// first `assigned` of them on the route.
    private func fleetFixture(idle: Int, assigned: Int) throws
        -> (SimulationEngine, AirlineID, ContentCatalog) {
        let catalog = try DemandFixtures.anchorCatalog()
        let engine = SimulationEngine(state: Fixtures.newState(),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(airlineName: "Board Air", kind: .player,
                                                homeAirport: "MET",
                                                startingCash: Money.dollars(300_000_000)))
        let airline = engine.state.airlines.values.first!.id
        for _ in 0..<(idle + assigned) {
            _ = engine.applyNow(LeaseAircraftCommand(lessee: airline, type: "MR180",
                                                     termMonths: 60))
        }
        _ = engine.applyNow(OpenRouteCommand(airline: airline, origin: "MET",
                                             destination: "COS", dailyRoundTrips: 2,
                                             ticketPrice: Money.dollars(129)))
        let route = engine.state.routes.values.first!.id
        for id in engine.state.fleet(of: airline).map(\.id).sorted().prefix(assigned) {
            _ = engine.applyNow(AssignAircraftToRouteCommand(
                airline: airline, route: route, aircraftID: id))
        }
        return (engine, airline, catalog)
    }

    @Test func idleRanksFirstAndIsADecision() throws {
        let (engine, airline, catalog) = try fleetFixture(idle: 1, assigned: 1)
        let board = engine.state.fleetBoard(for: airline, catalog: catalog)
        #expect(board.rows.count == 2)
        #expect(board.rows.first?.isIdle == true)
        #expect(board.idleCount == 1)
        #expect(board.needsDecision.count == 1)
        #expect(board.needsDecision.first?.issues == [.idle])
        #expect(board.unavailable.isEmpty)
        #expect(board.flying.count == 1)
    }

    @Test func inCheckAndOnOrderAreUnavailableNotDecisions() throws {
        let (engine, airline, catalog) = try fleetFixture(idle: 2, assigned: 0)
        var state = engine.state
        let ids = state.fleet(of: airline).map(\.id).sorted()
        let checkUntil = state.clock.now + .days(3)
        let delivery = state.clock.now + .days(20)
        state.aircraft[ids[0]]?.status = .inMaintenance(until: checkUntil)
        state.aircraft[ids[1]]?.status = .ordered(deliveryAt: delivery)

        let board = state.fleetBoard(for: airline, catalog: catalog)
        let check = try #require(board.rows.first { $0.aircraftID == ids[0] })
        let order = try #require(board.rows.first { $0.aircraftID == ids[1] })
        #expect(check.availability == .inCheck(until: checkUntil))
        #expect(order.availability == .onOrder(deliveryAt: delivery))
        #expect(check.issues.isEmpty)
        #expect(order.issues.isEmpty)
        #expect(check.checkDueInDays == nil)
        #expect(order.checkDueInDays == nil)
        #expect(board.inCheckCount == 1)
        #expect(board.onOrderCount == 1)
        #expect(board.needsDecision.isEmpty)
        #expect(board.unavailable.count == 2)
    }

    @Test func lowConditionAndWornReliabilityAreInspectionConcerns() throws {
        let (engine, airline, catalog) = try fleetFixture(idle: 2, assigned: 0)
        var state = engine.state
        let ids = state.fleet(of: airline).map(\.id).sorted()
        state.aircraft[ids[0]]?.condition = 0.72
        // Reliability is derived from condition and age, so wear is aged in.
        state.aircraft[ids[1]]?.ageDays = Int(GameCalendar.daysPerYear) * 20

        let board = state.fleetBoard(for: airline, catalog: catalog)
        let low = try #require(board.rows.first { $0.aircraftID == ids[0] })
        let worn = try #require(board.rows.first { $0.aircraftID == ids[1] })
        #expect(low.issues.contains(.lowCondition))
        #expect(worn.issues.contains(.wornReliability))
        #expect(!worn.issues.contains(.lowCondition))
        #expect(board.lowConditionCount == 1)
        #expect(board.wornReliabilityCount == 1)
        #expect(board.needsDecision.count == 2)
    }

    @Test func leaseEndingFlagsOnlyNearTerm() throws {
        let (engine, airline, catalog) = try fleetFixture(idle: 2, assigned: 0)
        var state = engine.state
        let ids = state.fleet(of: airline).map(\.id).sorted()
        state.aircraft[ids[0]]?.ownership = .leased(
            monthlyRate: Money.dollars(100_000), termMonthsRemaining: 2)
        state.aircraft[ids[1]]?.ownership = .leased(
            monthlyRate: Money.dollars(100_000), termMonthsRemaining: 10)

        let board = state.fleetBoard(for: airline, catalog: catalog)
        let ending = try #require(board.rows.first { $0.aircraftID == ids[0] })
        let open = try #require(board.rows.first { $0.aircraftID == ids[1] })
        #expect(ending.issues.contains(.leaseEnding))
        #expect(ending.leaseMonthsRemaining == 2)
        #expect(!open.issues.contains(.leaseEnding))
        #expect(board.leaseEndingCount == 1)
    }

    @Test func freshAircraftIsHealthy() throws {
        let (engine, airline, catalog) = try fleetFixture(idle: 0, assigned: 1)
        let board = engine.state.fleetBoard(for: airline, catalog: catalog)
        #expect(board.needsDecision.isEmpty)
        #expect(board.unavailable.isEmpty)
        #expect(board.flying.count == 1)
        #expect(board.dueSoon.isEmpty)
    }

    @Test func checkQuoteMatchesTheFleetSystemAndFlyingShortensIt() throws {
        let (engine, airline, catalog) = try fleetFixture(idle: 1, assigned: 1)
        let board = engine.state.fleetBoard(for: airline, catalog: catalog)
        let idle = try #require(board.rows.first { $0.isIdle })
        let flying = try #require(board.rows.first { !$0.isIdle })
        let spec = try #require(catalog.aircraftType(idle.card.typeCode))
        let quote = FleetEconomics.maintenanceCheckCost(
            type: spec, ageYears: idle.card.ageYears, tuning: catalog.tuning.fleet)
        #expect(idle.checkCost == quote)
        #expect(flying.checkCost == quote)

        let restDays = try #require(idle.checkDueInDays)
        let flyingDays = try #require(flying.checkDueInDays)
        #expect(flyingDays < restDays)
        // At rest the estimate is the daily decay alone: (1 − 0.75) / 0.0006.
        let expectedRest = try #require(FleetEconomics.daysUntilCheck(
            condition: 1.0, conditionPerDay: catalog.tuning.fleet.dailyConditionDecay,
            threshold: catalog.tuning.fleet.maintenanceConditionThreshold))
        #expect(restDays == expectedRest)
    }

    @Test func dueSoonCountsAndCostsOnlyInsideTheWindow() throws {
        let (engine, airline, catalog) = try fleetFixture(idle: 1, assigned: 1)
        var state = engine.state
        let ids = state.fleet(of: airline).map(\.id).sorted()
        // ids[0] is the assigned aircraft; a check comes in a few days.
        state.aircraft[ids[0]]?.condition = 0.76
        let board = state.fleetBoard(for: airline, catalog: catalog)
        let due = try #require(board.dueSoon.first)
        #expect(board.dueSoon.count == 1)
        #expect(board.dueSoonCost == due.checkCost)
        #expect((due.checkDueInDays ?? .max) <= FleetAttentionThresholds.checkSoonDays)
    }

    @Test func boardIsDeterministicAndDoesNotMutate() throws {
        let (engine, airline, catalog) = try fleetFixture(idle: 2, assigned: 1)
        let before = try engine.state.stateHash()
        let first = engine.state.fleetBoard(for: airline, catalog: catalog)
        let second = engine.state.fleetBoard(for: airline, catalog: catalog)
        #expect(first == second)
        #expect(try engine.state.stateHash() == before)
    }
}
