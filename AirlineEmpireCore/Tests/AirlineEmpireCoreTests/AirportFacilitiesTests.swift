import Foundation
import Testing
@testable import AirlineEmpireCore

/// The same engine with every building under construction open. For tests
/// about what a building costs and does rather than how long it takes.
func openingFacilities(_ engine: SimulationEngine) -> SimulationEngine {
    var state = engine.state
    FacilityConstructionSystem.openAll(&state)
    let opened = SimulationEngine(state: state, systems: engine.systems, catalog: engine.catalog)
    opened.progressionCeiling = engine.progressionCeiling
    return opened
}

@Suite("Airport facilities")
struct AirportFacilitiesTests {
    @Test func realMonthBoundariesAndRestoreDoNotDoubleCharge() throws {
        let systems: [any SimulationSystem] = [FacilityConstructionSystem(), EconomySystem()]
        let (catalog, source, airline) = try FleetFixtures.catalogAndEngine(systems: systems)
        let levels = AirportFacilities(lounge: 1, groundServices: 2)
        #expect(source.applyNow(ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN", facilities: levels)) == .applied)
        // Advance to the first real billing boundary after the buildings
        // open, then save on that boundary.
        for _ in 0..<8_000 {
            if source.state.ledger.recent.contains(where: { $0.memo == "ARN airport services" }) { break }
            source.advance(ticks: 1)
        }
        func bills(_ state: GameState) -> Int {
            state.ledger.recent.filter { $0.memo == "ARN airport services" }.count
        }
        #expect(bills(source.state) == 1)
        #expect(source.state.ledger.recent.first(where: { $0.memo == "ARN airport services" })?.amount == -levels.monthlyCost(tuning: catalog.tuning.airportServices))
        #expect(source.state.airlines[airline]?.facilities(at: "ARN") == levels)
        let restored = SimulationEngine(state: try JSONSaveCodec().decode(JSONSaveCodec().encode(source.state)),
            systems: systems, catalog: catalog)
        source.advance(ticks: 1); restored.advance(ticks: 1)
        #expect(bills(restored.state) == 1)
        #expect(restored.state == source.state)
        #expect(restored.applyNow(ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN", facilities: .init())) == .applied)
        restored.advance(ticks: 3_200)
        #expect(bills(restored.state) == 1)
        #expect(restored.state.airlines[airline]?.airportServiceCommitments(tuning: catalog.tuning.airportServices).isEmpty == true)
    }

    @Test func downgradesNeverRefundAndReinstallChargesAgain() throws {
        let (catalog, built, airline) = try FleetFixtures.catalogAndEngine()
        var engine = built
        func apply(_ lounge: Int, _ ground: Int) {
            #expect(engine.applyNow(ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN",
                facilities: .init(lounge: lounge, groundServices: ground))) == .applied)
            engine = openingFacilities(engine)
        }
        apply(2, 2)
        let cash = engine.state.ledger.balance(of: airline)
        apply(1, 0)
        #expect(engine.state.ledger.balance(of: airline) == cash)
        apply(2, 1)
        #expect(engine.state.ledger.balance(of: airline) == cash - catalog.tuning.airportServices.loungeInstallation - catalog.tuning.airportServices.groundInstallation)
        #expect(engine.state.airlines[airline]?.airportFacilityHistory?.count == 3)
    }

    @Test func investmentDoesNotGrantCompetitorServicesOrInstantReputation() throws {
        let (catalog, engine, airline, _, routeID) = try FlightOpsTests.operating()
        #expect(engine.applyNow(FoundAirlineCommand(airlineName: "Rival", kind: .ai, homeAirport: "ARN", startingCash: .dollars(10_000_000))) == .applied)
        let rival = try #require(engine.state.airlines.values.first { $0.kind == .ai })
        let old = engine.state
        #expect(engine.applyNow(ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN", facilities: .init(lounge: 2, groundServices: 2))) == .applied)
        #expect(engine.state.airlines[rival.id] == rival)
        #expect(engine.state.airlines[airline]?.reputation == old.airlines[airline]?.reputation)
        let route = try #require(old.routes[routeID])
        // Give the rival the same offer: its quality must not inherit the player's station.
        let rivalRoute = Route(id: route.id, airline: rival.id, origin: route.origin, destination: route.destination,
            distanceKm: route.distanceKm, dailyRoundTrips: route.dailyRoundTrips, ticketPrice: route.ticketPrice,
            assignedAircraft: route.assignedAircraft)
        #expect(DemandSystem.offerQualityTerms(route: rivalRoute, state: old, catalog: catalog)
            == DemandSystem.offerQualityTerms(route: rivalRoute, state: engine.state, catalog: catalog))
        #expect(engine.state.world == old.world)
    }

    @Test func previewIsDeterministicAndExcludesUnstaffedRoutes() throws {
        let (catalog, engine, airline, aircraft, _) = try FlightOpsTests.operating()
        let before = engine.state
        let proposed = AirportFacilities(lounge: 2, groundServices: 1)
        let first = AirportInvestmentPreview.make(airline: airline, airport: "ARN", proposed: proposed, state: before, catalog: catalog)
        #expect(first == AirportInvestmentPreview.make(airline: airline, airport: "ARN", proposed: proposed, state: before, catalog: catalog))
        #expect(engine.state == before)
        #expect(first?.monthlyDemandChange ?? 0 > 0)
        var idle = before
        idle.aircraft[aircraft]?.status = .active
        idle.routes = idle.routes.mapValues { route in var r = route; r.assignedAircraft = []; return r }
        let empty = try #require(AirportInvestmentPreview.make(airline: airline, airport: "ARN", proposed: proposed, state: idle, catalog: catalog))
        #expect(empty.servedRoutes == 0)
        #expect(empty.monthlyRevenueChange == .zero)
        #expect(empty.monthlyDemandChange == 0)
        #expect(empty.monthlyNetChange == -proposed.monthlyCost(tuning: catalog.tuning.airportServices))
    }

    @Test func cardQuotesShowIncrementalInstallationAndFullMonthlyCost() {
        let quote = AirportServiceReadModel(service: .lounge, installed: .init(lounge: 1),
            proposed: .init(lounge: 2, groundServices: 2), tuning: .standard)
        #expect(quote.installation == .dollars(750_000))
        #expect(quote.monthly == .dollars(30_000))
        #expect(quote.buildDays == 14)
        #expect(quote.current == 1 && quote.proposed == 2)
        let hangar = AirportServiceReadModel(service: .hangar, installed: .init(),
            proposed: .init(hangar: 2), tuning: .standard)
        #expect(hangar.installation == .dollars(5_000_000))
        #expect(hangar.monthly == .dollars(70_000))
        #expect(hangar.buildDays == 90)
        let downgrade = AirportServiceReadModel(service: .ground, installed: .init(groundServices: 2),
            proposed: .init(), tuning: .standard)
        #expect(downgrade.installation == .zero && downgrade.monthly == .zero)
        for level in [-1, 3, Int.max] {
            #expect(!AirportFacilities(lounge: level).isValid)
            #expect(!AirportFacilities(groundServices: level).isValid)
            #expect(!AirportFacilities(hangar: level).isValid)
        }
        #expect(!AirportFacilities(crewBase: 2).isValid)
        #expect(AirportFacilities(lounge: 2, groundServices: 2, hangar: 2, crewBase: 1).isValid)
    }

    @Test func economyScaleBaseline() throws {
        // Fixed airport/fare/airframe, varying network breadth. No tuning mutations.
        for count in [1, 4, 8] {
            let (catalog, engine, airline) = try FleetFixtures.catalogAndEngine(cash: .dollars(2_000_000_000))
            let destinations: [AirportCode] = ["LHR", "CDG", "AMS", "FRA", "MUC", "FCO", "MAD", "IST"]
            for destination in destinations.prefix(count) {
                #expect(engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180", ageYears: 3)) == .applied)
                let aircraft = try #require(engine.state.fleet(of: airline).first { $0.assignedRoute == nil })
                #expect(engine.applyNow(OpenRouteCommand(airline: airline, origin: "ARN", destination: destination,
                    dailyRoundTrips: 3, ticketPrice: .dollars(180))) == .applied)
                let route = try #require(engine.state.routes(of: airline).first { $0.destination == destination })
                #expect(engine.applyNow(AssignAircraftToRouteCommand(airline: airline, route: route.id, aircraftID: aircraft.id)) == .applied)
            }
            for level in 0...2 {
                let services = AirportFacilities(lounge: level, groundServices: level)
                let quote = try #require(AirportInvestmentPreview.make(airline: airline, airport: "ARN", proposed: services, state: engine.state, catalog: catalog))
                #expect(quote.servedRoutes == count)
                print("AIRPORT_BASELINE routes=\(count) tier=\(level) install=\(quote.installationCost.cents) monthly=\(quote.monthlyServiceCost.cents) demandBefore=\(quote.monthlyDemandBefore) demandAfter=\(quote.monthlyDemandAfter) revenueDelta=\(quote.monthlyRevenueChange.cents) operatingProfitDelta=\(quote.monthlyOperatingProfitChange.cents) netDelta=\(quote.monthlyNetChange.cents) technicalMultiplier=\(services.technicalDisruptionMultiplier(tuning: catalog.tuning.airportServices))")
                if level == 0 { #expect(quote.monthlyNetChange == .zero) }
                // Buying more reliability is never a fabricated direct cash return.
                let ground = try #require(AirportInvestmentPreview.make(airline: airline, airport: "ARN", proposed: .init(groundServices: level), state: engine.state, catalog: catalog))
                #expect(ground.monthlyRevenueChange == .zero)
                #expect(ground.monthlyNetChange == -ground.monthlyServiceCost)
            }
        }
    }
    private func context(_ state: GameState, _ catalog: ContentCatalog) -> SimContext {
        .init(previous: state.clock.now, current: state.clock.now, tick: .minutes(0),
              catalog: catalog, events: EventCollector(), progressionCeiling: .empire)
    }
    @Test func ordersAtomicallyAndPostsOnlyOnce() throws {
        let (catalog, engine, airline, _) = try RouteFixtures.withAircraft()
        let old = engine.state
        let next = AirportFacilities(lounge: 1, groundServices: 2)
        let command = ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN", facilities: next)
        #expect(engine.applyNow(command) == .applied)
        // Ordered, paid, and building: nothing stands yet.
        #expect(engine.state.airlines[airline]?.facilities(at: "ARN") == AirportFacilities())
        #expect(engine.state.airlines[airline]?.plannedFacilities(at: "ARN") == next)
        #expect(engine.state.airlines[airline]?.facilityConstructions?.count == 2)
        #expect(engine.state.ledger.balance(of: airline) == old.ledger.balance(of: airline) - next.installationCost(from: .init(), tuning: catalog.tuning.airportServices))
        let count = engine.state.ledger.totalTransactionCount
        #expect(engine.applyNow(command) == .applied)
        #expect(engine.state.ledger.totalTransactionCount == count)
        #expect(engine.state.airlines[airline]?.airportFacilityHistory?.count == 1)
        #expect(engine.state.world == old.world)
        let restored = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(engine.state))
        #expect(restored.airlines[airline] == engine.state.airlines[airline])
    }
    @Test func invalidAndUnservedInvestmentsCannotChangeState() throws {
        let (catalog, engine, airline, _) = try RouteFixtures.withAircraft()
        let old = engine.state
        let invalid = ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN", facilities: .init(lounge: 3))
        #expect(invalid.validate(state: old, catalog: catalog)?.code == "airport.invalidFacilities")
        let unserved = ConfigureAirportFacilitiesCommand(airline: airline, airport: "CDG", facilities: .init(lounge: 1))
        #expect(unserved.validate(state: old, catalog: catalog)?.code == "airport.noPresence")
        guard case .rejected = engine.applyNow(invalid) else { Issue.record("Expected rejection"); return }
        #expect(engine.state.airlines == old.airlines)
        #expect(engine.state.ledger == old.ledger)
    }
    @Test func cannotSpendUnavailableFundsButCanCloseServicesInDebt() throws {
        let (catalog, ordered, airline, _) = try RouteFixtures.withAircraft()
        #expect(ordered.applyNow(ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN", facilities: .init(lounge: 1))) == .applied)
        var state = openingFacilities(ordered).state
        state.ledger.post(airline: airline, category: .overhead, amount: -state.ledger.balance(of: airline) - .dollars(1), at: state.clock.now)
        let upgrade = ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN", facilities: .init(lounge: 2))
        #expect(upgrade.validate(state: state, catalog: catalog)?.code == "airport.insufficientFunds")
        let close = ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN", facilities: .init())
        #expect(close.validate(state: state, catalog: catalog) == nil)
        let balance = state.ledger.balance(of: airline)
        close.apply(state: &state, context: context(state, catalog))
        #expect(state.ledger.balance(of: airline) == balance)
        #expect(state.airlines[airline]?.airportFacilities?.isEmpty == true)
    }
    @Test func monthlyServicesAreBilledAndClosureStopsFutureCharges() throws {
        let (catalog, engine, airline, _) = try RouteFixtures.withAircraft()
        let facilities = AirportFacilities(lounge: 2, groundServices: 1, hangar: 1, crewBase: 1)
        var state = engine.state
        state.progression.era = .regional
        let regional = SimulationEngine(state: state, systems: engine.systems, catalog: catalog)
        #expect(regional.applyNow(ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN", facilities: facilities)) == .applied)
        var with = openingFacilities(regional).state, without = with
        without.airlines[airline]?.airportFacilities = nil
        EconomySystem().update(state: &with, context: context(with, catalog))
        EconomySystem().update(state: &without, context: context(without, catalog))
        #expect(without.ledger.balance(of: airline) - with.ledger.balance(of: airline) == facilities.monthlyCost(tuning: catalog.tuning.airportServices))
        #expect(with.ledger.recent.contains { $0.memo == "ARN airport services" && $0.amount == -facilities.monthlyCost(tuning: catalog.tuning.airportServices) })
    }
    @Test func legacyAirlinesAndContentDecodeWithNoFacilities() throws {
        let (catalog, engine, airline, _) = try RouteFixtures.withAircraft()
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.state.airlines[airline]!)) as? [String: Any])
        json.removeValue(forKey: "airportFacilities"); json.removeValue(forKey: "airportFacilityHistory")
        let restored = try JSONDecoder().decode(Airline.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.facilities(at: "ARN") == AirportFacilities())
        var tuning = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(catalog.tuning)) as? [String: Any])
        tuning.removeValue(forKey: "airportFacilities")
        #expect(try JSONDecoder().decode(Tuning.self, from: JSONSerialization.data(withJSONObject: tuning)).airportServices == .standard)
    }
    @Test func loungeChangesAuthoritativeDemandWithoutRefillingSoldSeats() throws {
        let (catalog, ordered, airline, _, id) = try FlightOpsTests.operating()
        let before = ordered.state
        #expect(ordered.applyNow(ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN", facilities: .init(lounge: 2))) == .applied)
        // Nothing changes until it opens.
        #expect(DemandSystem.offerQualityTerms(route: before.routes[id]!, state: ordered.state, catalog: catalog)
            == DemandSystem.offerQualityTerms(route: before.routes[id]!, state: before, catalog: catalog))
        let engine = openingFacilities(ordered)
        #expect(engine.state.routes[id] == before.routes[id])
        let route = try #require(before.routes[id])
        let old = try #require(DemandSystem.offerQualityTerms(route: route, state: before, catalog: catalog))
        let updated = try #require(DemandSystem.offerQualityTerms(route: route, state: engine.state, catalog: catalog))
        #expect(updated.comfort > old.comfort)
        var a = before, b = engine.state
        DemandSystem().update(state: &a, context: context(a, catalog))
        DemandSystem().update(state: &b, context: context(b, catalog))
        #expect(b.routes[id]!.demandOutboundToday > a.routes[id]!.demandOutboundToday)
        #expect(b.routes[id]!.demandInboundToday > a.routes[id]!.demandInboundToday)
    }
    @Test func previewIsPureAndIncludesFacilityOverheadExactlyOnce() throws {
        let (catalog, engine, airline, _, _) = try FlightOpsTests.operating()
        let before = engine.state
        let next = AirportFacilities(groundServices: 2)
        let preview = try #require(AirportInvestmentPreview.make(airline: airline, airport: "ARN", proposed: next, state: before, catalog: catalog))
        #expect(preview.monthlyRevenueChange == .zero)
        #expect(preview.monthlyNetChange == -next.monthlyCost(tuning: catalog.tuning.airportServices))
        #expect(preview.servedRoutes == 1)
        #expect(engine.state == before)
        let unchanged = try #require(AirportInvestmentPreview.make(airline: airline, airport: "ARN", proposed: .init(), state: before, catalog: catalog))
        #expect(unchanged.monthlyNetChange == .zero)
    }

    @Test func groundServicesPreventAnActualTechnicalDisruptionAtDepartureOnly() throws {
        let (catalog, engine, airline, aircraftID, routeID) = try FlightOpsTests.operating()
        var baseline = engine.state
        let aircraft = try #require(baseline.aircraft[aircraftID])
        let spec = try #require(catalog.aircraftType(aircraft.typeCode))
        let probability = 1 - aircraft.currentReliability(type: spec, tuning: catalog.tuning.fleet)
        let facilities = AirportFacilities(groundServices: 2)
        let reduced = probability * facilities.technicalDisruptionMultiplier(tuning: catalog.tuning.airportServices)
        let seed = try #require((UInt64(0)..<100_000).first { value in
            var rng = RNGState(worldSeed: value)
            let draw = rng.unitDouble("flightOps.dispatch")
            return draw >= reduced && draw < probability
        })
        baseline.rng = RNGState(worldSeed: seed)
        let id = FlightID(raw: 99_999)
        var flight = Flight(id: id, route: routeID, aircraft: aircraftID, kind: .revenue,
            from: "ARN", to: "LHR", distanceKm: 1400, flightMinutes: 120, scheduledDeparture: baseline.clock.now)
        flight.phase = .boarding
        baseline.flights = [id: flight]
        baseline.aircraft[aircraftID]?.activeFlight = id
        var origin = baseline, destination = baseline
        origin.airlines[airline]?.airportFacilities = ["ARN": facilities]
        destination.airlines[airline]?.airportFacilities = ["LHR": facilities]
        FlightOpsSystem().update(state: &baseline, context: context(baseline, catalog))
        FlightOpsSystem().update(state: &origin, context: context(origin, catalog))
        FlightOpsSystem().update(state: &destination, context: context(destination, catalog))
        #expect(origin.flights[id]?.phase == .enRoute(actualDeparture: origin.clock.now))
        #expect(baseline.flights[id]?.phase != .enRoute(actualDeparture: baseline.clock.now))
        #expect(destination.flights[id] == baseline.flights[id])
    }
}
