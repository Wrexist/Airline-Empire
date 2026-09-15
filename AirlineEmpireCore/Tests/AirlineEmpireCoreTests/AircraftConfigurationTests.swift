import Foundation
import Testing
@testable import AirlineEmpireCore

@Suite("Aircraft configuration")
struct AircraftConfigurationTests {
    @Test func cabinUsesSpaceAndClampsAtBothEnds() {
        var cabin = AircraftConfiguration(capacity: 184)
        cabin.setSeats(12, in: .first, capacity: 184)
        cabin.setSeats(24, in: .business, capacity: 184)
        cabin.setSeats(16, in: .premiumEconomy, capacity: 184)
        #expect(cabin.economy == 56)
        #expect(cabin.totalSeats == 108)
        #expect(cabin.isValid(capacity: 184))
        cabin.setSeats(Int.max, in: .first, capacity: 184)
        #expect(cabin.isValid(capacity: 184))
        #expect(cabin.economy == 0)
        cabin.setSeats(-10, in: .business, capacity: 184)
        #expect(cabin.business == 0)
        #expect(cabin.isValid(capacity: 184))
    }

    @Test func rejectsMalformedAndOverCapacityLayoutsWithoutOverflow() {
        var cabin = AircraftConfiguration(capacity: 184)
        cabin.first = Int.max
        #expect(!cabin.isValid(capacity: 184))
        cabin.first = -1
        #expect(!cabin.isValid(capacity: 184))
        cabin.first = 1
        #expect(!cabin.isValid(capacity: 184))
        cabin.first = 0; cabin.wifi = 3
        #expect(!cabin.isValid(capacity: 184))
    }

    @Test func oldAircraftJSONDecodesToOriginalCabin() throws {
        let (catalog, engine, _, id) = try RouteFixtures.withAircraft()
        let aircraft = try #require(engine.state.aircraft[id])
        let spec = try #require(catalog.aircraftType(aircraft.typeCode))
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(aircraft)) as? [String: Any])
        json.removeValue(forKey: "configuration")
        json.removeValue(forKey: "configurationHistory")
        let restored = try JSONDecoder().decode(Aircraft.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.cabin(for: spec) == AircraftConfiguration(capacity: spec.seats))
        #expect(restored.configurationHistory == nil)
    }

    @Test func commandChargesOncePersistsHistoryAndDoesNotRefillDemand() throws {
        let (catalog, engine, airline, id) = try RouteFixtures.withAircraft()
        let routeID = RouteFixtures.openStvLnw(engine, airline)
        #expect(engine.applyNow(AssignAircraftToRouteCommand(airline: airline, route: routeID, aircraftID: id)) == .applied)
        let aircraft = try #require(engine.state.aircraft[id])
        let spec = try #require(catalog.aircraftType(aircraft.typeCode))
        let old = aircraft.cabin(for: spec)
        var cabin = old; cabin.wifi = 2
        cabin.setSeats(8, in: .business, capacity: spec.seats)
        let cash = engine.state.ledger.balance(of: airline)
        let demand = engine.state.routes[routeID]?.remainingOutboundToday
        let command = ConfigureAircraftCommand(airline: airline, aircraftID: id, configuration: cabin)
        #expect(engine.applyNow(command) == .applied)
        #expect(engine.state.ledger.balance(of: airline) == cash - cabin.installationCost(from: old, capacity: spec.seats))
        #expect(engine.state.routes[routeID]?.remainingOutboundToday == demand)
        #expect(engine.state.aircraft[id]?.configurationHistory?.count == 1)
        let after = engine.state
        #expect(engine.applyNow(command) == .applied)
        #expect(engine.state.ledger == after.ledger)
        let restored = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(engine.state))
        #expect(restored.aircraft[id]?.configuration == cabin)
        #expect(restored.aircraft[id]?.configurationHistory == engine.state.aircraft[id]?.configurationHistory)
    }

    @Test func refitRejectedWhileAircraftBusyAndWithoutFunds() throws {
        let (catalog, engine, airline, id) = try RouteFixtures.withAircraft()
        var state = engine.state
        let aircraft = try #require(state.aircraft[id])
        let spec = try #require(catalog.aircraftType(aircraft.typeCode))
        var cabin = aircraft.cabin(for: spec); cabin.seats = 2
        let command = ConfigureAircraftCommand(airline: airline, aircraftID: id, configuration: cabin)
        state.aircraft[id]?.status = .inMaintenance(until: .epoch + .days(1))
        #expect(command.validate(state: state, catalog: catalog)?.code == "aircraft.notReady")
        state.aircraft[id]?.status = .active
        state.ledger.post(airline: airline, category: .maintenance, amount: -state.ledger.balance(of: airline), at: .epoch)
        #expect(command.validate(state: state, catalog: catalog)?.code == "aircraft.refitFunds")
    }

    @Test func forecastUsesLiveDemandWithoutMutatingState() throws {
        let (catalog, engine, airline, id) = try RouteFixtures.withAircraft()
        let routeID = RouteFixtures.openStvLnw(engine, airline)
        #expect(engine.applyNow(AssignAircraftToRouteCommand(airline: airline, route: routeID, aircraftID: id)) == .applied)
        let before = engine.state
        let aircraft = try #require(before.aircraft[id])
        let spec = try #require(catalog.aircraftType(aircraft.typeCode))
        let old = aircraft.cabin(for: spec)
        let base = try #require(AircraftConfigurationPreview.make(aircraftID: id, configuration: old, state: before, catalog: catalog))
        var next = old; next.wifi = 2; next.dining = 2
        let upgraded = try #require(AircraftConfigurationPreview.make(aircraftID: id, configuration: next, state: before, catalog: catalog))
        #expect(upgraded.monthlyCosts > base.monthlyCosts)
        #expect((0...1).contains(upgraded.loadFactor))
        #expect(engine.state == before)
        #expect(engine.applyNow(ConfigureAircraftCommand(airline: airline, aircraftID: id, configuration: next)) == .applied)
        let installed = try #require(AircraftConfigurationPreview.make(aircraftID: id, configuration: next, state: engine.state, catalog: catalog))
        #expect(installed == upgraded)
        let route = try #require(before.routes[routeID])
        let originalQuality = try #require(DemandSystem.offerQualityTerms(route: route, state: before, catalog: catalog))
        let newQuality = try #require(DemandSystem.offerQualityTerms(route: route, state: engine.state, catalog: catalog))
        #expect(newQuality.comfort > originalQuality.comfort)
    }

    @Test func configuredSeatsReachTheFlightAndReputationSystems() throws {
        let (catalog, engine, airline, id) = try RouteFixtures.withAircraft()
        let routeID = RouteFixtures.openStvLnw(engine, airline)
        let aircraft = try #require(engine.state.aircraft[id])
        let spec = try #require(catalog.aircraftType(aircraft.typeCode))
        var cabin = aircraft.cabin(for: spec)
        cabin.setSeats(12, in: .business, capacity: spec.seats)
        cabin.dining = 2
        #expect(engine.applyNow(ConfigureAircraftCommand(airline: airline, aircraftID: id, configuration: cabin)) == .applied)
        #expect(engine.applyNow(AssignAircraftToRouteCommand(airline: airline, route: routeID, aircraftID: id)) == .applied)
        engine.advance(ticks: Fixtures.ticksPerDay * 4)
        let route = try #require(engine.state.routes[routeID])
        #expect(route.stats.flightsCompleted > 0)
        #expect(route.stats.seatsFlown == route.stats.flightsCompleted * Int64(cabin.totalSeats))
        #expect(route.stats.passengersCarried <= route.stats.seatsFlown)
        let expectedRevenue = Money(rounding: Double(route.economicsThisMonth.passengers)
            * route.ticketPrice.asDouble * cabin.yieldMultiplier(tuning: catalog.tuning.cabin))
        // Revenue is rounded once per departure, so allow one cent per flight.
        #expect(abs(route.economicsThisMonth.revenueCents - expectedRevenue.cents)
            <= route.stats.totalFlights + 4)
        #expect(engine.state.ledger.recent.contains { $0.category == .passengerService && $0.amount < .zero })
        #expect(engine.state.airlines[airline]?.reputation.comfort != 0)
    }
    @Test func changingSecondAircraftChangesTheRouteOffer() throws {
        let (catalog, engine, airline, firstID) = try RouteFixtures.withAircraft()
        let routeID = RouteFixtures.openStvLnw(engine, airline)
        #expect(engine.applyNow(AssignAircraftToRouteCommand(airline: airline, route: routeID, aircraftID: firstID)) == .applied)
        #expect(engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180", ageYears: 3)) == .applied)
        let second = try #require(engine.state.aircraft.values.first { $0.id != firstID })
        #expect(engine.applyNow(AssignAircraftToRouteCommand(airline: airline, route: routeID, aircraftID: second.id)) == .applied)
        let route = try #require(engine.state.routes[routeID])
        let old = try #require(DemandSystem.offerQualityTerms(route: route, state: engine.state, catalog: catalog))
        let spec = try #require(catalog.aircraftType(second.typeCode))
        var cabin = second.cabin(for: spec); cabin.seats = 2
        #expect(engine.applyNow(ConfigureAircraftCommand(airline: airline, aircraftID: second.id, configuration: cabin)) == .applied)
        let changed = try #require(DemandSystem.offerQualityTerms(route: route, state: engine.state, catalog: catalog))
        #expect(changed.comfort > old.comfort)
    }

    @Test func contentTuningControlsRefitAndServicePrices() throws {
        let catalog = try ContentCatalog.loadBundled()
        #expect(catalog.tuning.cabin == .standard)
        let tuning = AircraftConfigurationTuning(seatChangeCost: .dollars(10),
            equipmentPerSeatPerLevel: .dollars(5), wifiPerPassengerPerLevel: .dollars(3))
        let old = AircraftConfiguration(capacity: 100)
        var cabin = old
        cabin.wifi = 2
        cabin.setSeats(1, in: .business, capacity: 100)
        #expect(cabin.serviceCostPerPassenger(tuning: tuning) == .dollars(6))
        #expect(cabin.installationCost(from: old, capacity: 100, tuning: tuning) == .dollars(1030))
        #expect(!AircraftConfigurationTuning(firstYield: .infinity).isValid)
        #expect(!AircraftConfigurationTuning(seatChangeCost: Money(cents: -1)).isValid)
    }

}
