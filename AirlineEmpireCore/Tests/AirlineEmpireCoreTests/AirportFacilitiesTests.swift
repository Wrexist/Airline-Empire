import Foundation
import Testing
@testable import AirlineEmpireCore

@Suite("Airport facilities")
struct AirportFacilitiesTests {
    private func context(_ state: GameState, _ catalog: ContentCatalog) -> SimContext {
        .init(previous: state.clock.now, current: state.clock.now, tick: .minutes(0),
              catalog: catalog, events: EventCollector(), progressionCeiling: .empire)
    }
    @Test func installsAtomicallyAndPostsOnlyOnce() throws {
        let (catalog, engine, airline, _) = try RouteFixtures.withAircraft()
        let old = engine.state
        let next = AirportFacilities(lounge: 1, groundServices: 2)
        let command = ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN", facilities: next)
        #expect(engine.applyNow(command) == .applied)
        #expect(engine.state.airlines[airline]?.facilities(at: "ARN") == next)
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
        let (catalog, engine, airline, _) = try RouteFixtures.withAircraft()
        #expect(engine.applyNow(ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN", facilities: .init(lounge: 1))) == .applied)
        var state = engine.state
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
        let facilities = AirportFacilities(lounge: 2, groundServices: 1)
        #expect(engine.applyNow(ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN", facilities: facilities)) == .applied)
        var with = engine.state, without = engine.state
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
        let (catalog, engine, airline, _, id) = try FlightOpsTests.operating()
        let before = engine.state
        #expect(engine.applyNow(ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN", facilities: .init(lounge: 2))) == .applied)
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
