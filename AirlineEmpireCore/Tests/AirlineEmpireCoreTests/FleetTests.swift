import Testing
@testable import AirlineEmpireCore

/// Fleet fixtures: a real catalog + a founded airline, the base of most
/// fleet scenarios.
enum FleetFixtures {
    static func catalogAndEngine(
        cash: Money = Money.dollars(300_000_000),
        systems: [any SimulationSystem] = GamePipeline.standard()
    ) throws -> (ContentCatalog, SimulationEngine, AirlineID) {
        let catalog = try ContentCatalog.loadBundled()
        let engine = SimulationEngine(state: Fixtures.newState(), systems: systems,
                                      catalog: catalog)
        let result = engine.applyNow(FoundAirlineCommand(
            airlineName: "Nordwind", kind: .player, homeAirport: "ARN", startingCash: cash))
        #expect(result == .applied)
        let airlineID = engine.state.airlines.values.first { $0.name == "Nordwind" }!.id
        return (catalog, engine, airlineID)
    }
}

@Suite("Airline founding")
struct FoundAirlineTests {
    @Test func foundingCreatesAirlineAndCapital() throws {
        let (_, engine, id) = try FleetFixtures.catalogAndEngine(cash: Money.dollars(5_000_000))
        let airline = try #require(engine.state.airlines[id])
        #expect(airline.kind == .player)
        #expect(airline.homeAirport == AirportCode("ARN"))
        #expect(engine.state.ledger.balance(of: id) == Money.dollars(5_000_000))
        #expect(engine.state.ledger.recent.last?.category == .initialCapital)
        #expect(engine.state.eventLog.recent.map(\.kind)
            .contains(.airlineFounded(id: id, name: "Nordwind")))
    }

    @Test func validationRejections() throws {
        let (_, engine, _) = try FleetFixtures.catalogAndEngine()
        func rejectionCode(_ command: FoundAirlineCommand) -> String? {
            if case .rejected(let r) = engine.applyNow(command) { r.code } else { nil }
        }
        #expect(rejectionCode(.init(airlineName: "  ", kind: .ai, homeAirport: "ARN",
                                    startingCash: .zero)) == "airline.badName")
        #expect(rejectionCode(.init(airlineName: "Nordwind", kind: .ai, homeAirport: "ARN",
                                    startingCash: .zero)) == "airline.nameTaken")
        #expect(rejectionCode(.init(airlineName: "Other", kind: .ai, homeAirport: "XXX",
                                    startingCash: .zero)) == "airline.unknownHome")
        #expect(rejectionCode(.init(airlineName: "Other", kind: .ai, homeAirport: "ARN",
                                    startingCash: Money(cents: -1))) == "airline.negativeCapital")
        #expect(rejectionCode(.init(airlineName: "Second", kind: .player, homeAirport: "LHR",
                                    startingCash: .zero)) == "airline.playerExists")
        // AI airlines are unlimited.
        #expect(engine.applyNow(FoundAirlineCommand(
            airlineName: "PacificBlue", kind: .ai, homeAirport: "LHR",
            startingCash: Money.dollars(1_000_000))) == .applied)
    }
}

@Suite("Aircraft acquisition")
struct AcquisitionTests {
    @Test func newOrderDeliversAfterLeadTime() throws {
        let (catalog, engine, airline) = try FleetFixtures.catalogAndEngine()
        let spec = try #require(catalog.aircraftType("NA70"))
        #expect(engine.applyNow(BuyNewAircraftCommand(buyer: airline, type: "NA70")) == .applied)

        let aircraft = try #require(engine.state.aircraft.values.first)
        #expect(aircraft.status == .ordered(deliveryAt: SimTime(rawMinutes: 0) + .days(120)))
        #expect(!aircraft.isOperational)
        #expect(engine.state.ledger.balance(of: airline)
                == Money.dollars(300_000_000) - spec.listPrice)

        // Not delivered the day before...
        engine.advance(ticks: Fixtures.ticksPerDay * 119)
        #expect(!engine.state.aircraft[aircraft.id]!.isOperational)
        // ...delivered on the due day.
        engine.advance(ticks: Fixtures.ticksPerDay * 2)
        #expect(engine.state.aircraft[aircraft.id]!.isOperational)
        #expect(engine.state.eventLog.recent.map(\.kind)
            .contains(.aircraftDelivered(id: aircraft.id)))
    }

    @Test func insufficientFundsRejected() throws {
        let (_, engine, airline) = try FleetFixtures.catalogAndEngine(cash: Money.dollars(1000))
        let result = engine.applyNow(BuyNewAircraftCommand(buyer: airline, type: "NA70"))
        guard case .rejected(let rejection) = result else {
            Issue.record("Expected rejection"); return
        }
        #expect(rejection.code == "fleet.insufficientFunds")
        #expect(engine.state.aircraft.isEmpty)
        #expect(engine.state.ledger.balance(of: airline) == Money.dollars(1000))
    }

    @Test func usedPurchaseIsImmediateAndCheaper() throws {
        let (catalog, engine, airline) = try FleetFixtures.catalogAndEngine()
        let spec = try #require(catalog.aircraftType("MR180"))
        #expect(engine.applyNow(BuyUsedAircraftCommand(
            buyer: airline, type: "MR180", ageYears: 10)) == .applied)
        let aircraft = try #require(engine.state.aircraft.values.first)
        #expect(aircraft.isOperational)
        #expect(aircraft.ageDays == 3650)
        #expect(aircraft.condition < 1.0)
        let paid = Money.dollars(300_000_000) - engine.state.ledger.balance(of: airline)
        #expect(paid < spec.listPrice)
        #expect(paid > Money(rounding: spec.listPrice.asDouble * 0.2))
    }

    @Test func usedAgeBoundsEnforced() throws {
        let (_, engine, airline) = try FleetFixtures.catalogAndEngine()
        for age in [0, 23, -5] {
            guard case .rejected(let rejection) = engine.applyNow(
                BuyUsedAircraftCommand(buyer: airline, type: "MR180", ageYears: age)) else {
                Issue.record("Age \(age) should be rejected"); continue
            }
            #expect(rejection.code == "fleet.badUsedAge")
        }
    }

    @Test func leaseChargesSigningAndMonthly() throws {
        let (catalog, engine, airline) = try FleetFixtures.catalogAndEngine()
        let spec = try #require(catalog.aircraftType("AV90"))
        #expect(engine.applyNow(LeaseAircraftCommand(
            lessee: airline, type: "AV90", termMonths: 24)) == .applied)
        let afterSigning = engine.state.ledger.balance(of: airline)
        #expect(afterSigning == Money.dollars(300_000_000) - spec.leaseMonthly)

        // Cross Feb 1 (31 days): exactly one monthly lease billing, plus
        // the month's payroll (1 aircraft) and company overhead (Phase 8).
        engine.advance(ticks: Fixtures.ticksPerDay * 32)
        let afterMonth = engine.state.ledger.balance(of: airline)
        let finance = engine.catalog.tuning.finance
        #expect(afterMonth == afterSigning - spec.leaseMonthly
                - finance.payrollPerAircraftMonthly - finance.overheadBaseMonthly)
        let aircraft = try #require(engine.state.aircraft.values.first)
        guard case .leased(_, let remaining) = aircraft.ownership else {
            Issue.record("Expected lease"); return
        }
        #expect(remaining == 23)
    }

    @Test func badLeaseTermRejected() throws {
        let (_, engine, airline) = try FleetFixtures.catalogAndEngine()
        for term in [0, 5, 145] {
            guard case .rejected(let rejection) = engine.applyNow(
                LeaseAircraftCommand(lessee: airline, type: "AV90", termMonths: term)) else {
                Issue.record("Term \(term) should be rejected"); continue
            }
            #expect(rejection.code == "fleet.badLeaseTerm")
        }
    }
}

@Suite("Aircraft disposal")
struct DisposalTests {
    @Test func sellingRecoversLessThanPurchase() throws {
        let (_, engine, airline) = try FleetFixtures.catalogAndEngine()
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "NA70", ageYears: 5))
        let bought = Money.dollars(300_000_000) - engine.state.ledger.balance(of: airline)
        let aircraft = engine.state.aircraft.values.first!
        #expect(engine.applyNow(SellAircraftCommand(
            seller: airline, aircraftID: aircraft.id)) == .applied)
        #expect(engine.state.aircraft.isEmpty)
        let net = engine.state.ledger.balance(of: airline) - Money.dollars(300_000_000)
        // Sale friction: flipping must lose money (docs/GAME_BALANCE.md §7).
        #expect(net.isNegative)
        let loss = -net
        #expect(loss > Money(rounding: bought.asDouble * 0.05))
    }

    @Test func sellingRejectedForLeasedOrderedOrForeign() throws {
        let (_, engine, airline) = try FleetFixtures.catalogAndEngine()
        _ = engine.applyNow(FoundAirlineCommand(airlineName: "Rival", kind: .ai,
                                                homeAirport: "LHR",
                                                startingCash: Money.dollars(500_000_000)))
        let rival = engine.state.airlines.values.first { $0.name == "Rival" }!.id

        _ = engine.applyNow(LeaseAircraftCommand(lessee: airline, type: "AV90", termMonths: 12))
        let leased = engine.state.aircraft.values.first!
        guard case .rejected(let r1) = engine.applyNow(
            SellAircraftCommand(seller: airline, aircraftID: leased.id)) else {
            Issue.record("Leased sale should reject"); return
        }
        #expect(r1.code == "fleet.cannotSellLeased")

        _ = engine.applyNow(BuyNewAircraftCommand(buyer: airline, type: "NA70"))
        let ordered = engine.state.aircraft.values.first { !$0.ownership.isLeased }!
        guard case .rejected(let r2) = engine.applyNow(
            SellAircraftCommand(seller: airline, aircraftID: ordered.id)) else {
            Issue.record("Ordered sale should reject"); return
        }
        #expect(r2.code == "fleet.notSellableNow")

        guard case .rejected(let r3) = engine.applyNow(
            SellAircraftCommand(seller: rival, aircraftID: leased.id)) else {
            Issue.record("Foreign sale should reject"); return
        }
        #expect(r3.code == "fleet.notYourAircraft")
    }

    @Test func earlyLeaseReturnCostsPenalty() throws {
        let (catalog, engine, airline) = try FleetFixtures.catalogAndEngine()
        let spec = catalog.aircraftType("AV90")!
        _ = engine.applyNow(LeaseAircraftCommand(lessee: airline, type: "AV90", termMonths: 24))
        let aircraft = engine.state.aircraft.values.first!
        let before = engine.state.ledger.balance(of: airline)
        #expect(engine.applyNow(ReturnLeasedAircraftCommand(
            lessee: airline, aircraftID: aircraft.id)) == .applied)
        #expect(engine.state.aircraft.isEmpty)
        #expect(engine.state.ledger.balance(of: airline) == before - spec.leaseMonthly * 2)
    }

    @Test func expiredLeaseReturnsFree() throws {
        let (_, engine, airline) = try FleetFixtures.catalogAndEngine()
        _ = engine.applyNow(LeaseAircraftCommand(lessee: airline, type: "AV90", termMonths: 6))
        let aircraft = engine.state.aircraft.values.first!
        // Run out the 6-month term (183 days crosses Jul 1 = 6 monthly bills).
        engine.advance(ticks: Fixtures.ticksPerDay * 185)
        guard case .leased(_, let remaining) = engine.state.aircraft[aircraft.id]!.ownership else {
            Issue.record("Expected lease"); return
        }
        #expect(remaining == 0)
        let before = engine.state.ledger.balance(of: airline)
        #expect(engine.applyNow(ReturnLeasedAircraftCommand(
            lessee: airline, aircraftID: aircraft.id)) == .applied)
        #expect(engine.state.ledger.balance(of: airline) == before)
    }
}

@Suite("Fleet lifecycle over time")
struct FleetLifecycleTests {
    @Test func conditionDecaysAndMaintenanceRestores() throws {
        let (_, engine, airline) = try FleetFixtures.catalogAndEngine()
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "NA70", ageYears: 8))
        let id = engine.state.aircraft.values.first!.id
        let startCondition = engine.state.aircraft[id]!.condition

        // 8y used condition 0.84 decays 0.0006/day -> hits 0.75 in ~150 days.
        engine.advance(ticks: Fixtures.ticksPerDay * 140)
        let decayed = engine.state.aircraft[id]!.condition
        #expect(decayed < startCondition)
        #expect(engine.state.aircraft[id]!.isOperational)

        engine.advance(ticks: Fixtures.ticksPerDay * 30)
        // By now the check has triggered and completed: condition restored.
        let after = engine.state.aircraft[id]!
        #expect(after.condition > 0.9)
        let kinds = engine.state.eventLog.recent.map(\.kind)
        #expect(kinds.contains { if case .maintenanceStarted = $0 { true } else { false } })
        #expect(kinds.contains(.maintenanceCompleted(id: id)))
        // The check was paid for.
        #expect(engine.state.ledger.recent.contains { $0.category == .maintenance })
    }

    @Test func groundedAircraftIsNotOperational() throws {
        let (_, engine, airline) = try FleetFixtures.catalogAndEngine()
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "NA70", ageYears: 12))
        let id = engine.state.aircraft.values.first!.id
        // 12y condition 0.76: first check triggers within days.
        engine.advance(ticks: Fixtures.ticksPerDay * 30)
        var sawGrounded = false
        for _ in 0..<10 {
            engine.advance(ticks: Fixtures.ticksPerDay)
            if case .inMaintenance = engine.state.aircraft[id]!.status {
                sawGrounded = true
                #expect(!engine.state.aircraft[id]!.isOperational)
                break
            }
        }
        // Either we caught it grounded or it already completed a check.
        let completed = engine.state.eventLog.recent.map(\.kind)
            .contains { if case .maintenanceCompleted = $0 { true } else { false } }
        #expect(sawGrounded || completed)
    }

    @Test func bookValueDepreciatesTowardFloor() throws {
        let (catalog, engine, airline) = try FleetFixtures.catalogAndEngine(
            cash: Money.dollars(500_000_000))
        let spec = catalog.aircraftType("MR180")!
        _ = engine.applyNow(BuyNewAircraftCommand(buyer: airline, type: "MR180"))
        let id = engine.state.aircraft.values.first!.id

        engine.advance(ticks: Fixtures.ticksPerYear * 2)
        guard case .owned(let bookAfter2y) = engine.state.aircraft[id]!.ownership else {
            Issue.record("Expected owned"); return
        }
        #expect(bookAfter2y < spec.listPrice)
        let expected2y = spec.listPrice.asDouble * 0.92 * 0.92
        #expect(abs(bookAfter2y.asDouble - expected2y) / expected2y < 0.02)

        // Floor: after very long service, value stops at 25% of list.
        engine.advance(ticks: Fixtures.ticksPerYear * 20)
        guard case .owned(let bookOld) = engine.state.aircraft[id]!.ownership else {
            Issue.record("Expected owned"); return
        }
        #expect(bookOld == Money(rounding: spec.listPrice.asDouble * 0.25))
    }

    @Test func reliabilityDegradesWithAgeAndWear() throws {
        let catalog = try ContentCatalog.loadBundled()
        let spec = catalog.aircraftType("MR180")!
        let tuning = catalog.tuning.fleet
        let fresh = Aircraft(id: AircraftID(raw: 1), typeCode: "MR180",
                             owner: AirlineID(raw: 1),
                             ownership: .owned(bookValue: spec.listPrice),
                             status: .active, location: "ARN", ageDays: 0, condition: 1.0)
        var old = fresh
        old.ageDays = 20 * 365
        old.condition = 0.6
        let freshR = fresh.currentReliability(type: spec, tuning: tuning)
        let oldR = old.currentReliability(type: spec, tuning: tuning)
        #expect(freshR == spec.reliabilityBaseline)
        #expect(oldR < freshR)
        #expect(oldR >= tuning.reliabilityFloor)
    }

    @Test func fleetSurvivesSaveLoadMidLifecycle() throws {
        let (catalog, engine, airline) = try FleetFixtures.catalogAndEngine()
        _ = engine.applyNow(BuyNewAircraftCommand(buyer: airline, type: "MR180"))
        _ = engine.applyNow(LeaseAircraftCommand(lessee: airline, type: "AV90", termMonths: 36))
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "NA70", ageYears: 15))
        engine.advance(ticks: Fixtures.ticksPerDay * 45) // mid-order, mid-lease

        let saved = try JSONSaveCodec().encode(engine.state)
        let resumed = SimulationEngine(state: try JSONSaveCodec().decode(saved),
                                       systems: GamePipeline.standard(), catalog: catalog)
        resumed.advance(ticks: Fixtures.ticksPerDay * 120)
        engine.advance(ticks: Fixtures.ticksPerDay * 120)
        #expect(try resumed.state.stateHash() == engine.state.stateHash())
        // The ordered MR180 (365-day lead) is still pending in both.
        #expect(engine.state.aircraft.values.contains {
            if case .ordered = $0.status { true } else { false }
        })
    }

    @Test func ledgerBalancesMatchTransactionTrail() throws {
        let (_, engine, airline) = try FleetFixtures.catalogAndEngine()
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "NA70", ageYears: 3))
        _ = engine.applyNow(LeaseAircraftCommand(lessee: airline, type: "AV90", termMonths: 12))
        engine.advance(ticks: Fixtures.ticksPerDay * 70)
        // Every cent of the balance is explained by the recent trail (the
        // trail hasn't overflowed its ring in this scenario).
        let ledger = engine.state.ledger
        let sum = ledger.recent.filter { $0.airline == airline }
            .reduce(Money.zero) { $0 + $1.amount }
        #expect(sum == ledger.balance(of: airline))
    }
}
