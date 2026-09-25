import Foundation
import Testing
@testable import AirlineEmpireCore

@Suite("Route planning")
struct RoutePlanningTests {
    @Test func planAppliesTogetherAndPreservesSoldDemand() throws {
        let (_, engine, airline, _) = try RouteFixtures.withAircraft()
        let id = RouteFixtures.openStvLnw(engine, airline)
        let before = try #require(engine.state.routes[id])
        let plan = RoutePlan(fare: .dollars(160), frequency: 3)
        let command = ApplyRoutePlanCommand(airline: airline, route: id, plan: plan)
        #expect(engine.applyNow(command) == .applied)
        let after = try #require(engine.state.routes[id])
        #expect(RoutePlan(route: after) == plan)
        #expect(after.remainingOutboundToday == before.remainingOutboundToday)
        #expect(engine.state.world.slotsHeld(by: airline, at: "ARN") == 6)
        #expect(after.planHistory?.first?.previous == RoutePlan(route: before))
        #expect(engine.applyNow(command) == .applied)
        #expect(engine.state.routes[id]?.planHistory?.count == 1)
        let restored = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(engine.state))
        #expect(restored.routes[id] == after)
    }

    @Test func invalidFrequencyDoesNotPartiallyChangeFare() throws {
        let (_, engine, airline, _) = try RouteFixtures.withAircraft()
        let id = RouteFixtures.openStvLnw(engine, airline)
        let before = engine.state
        guard case .rejected = engine.applyNow(ApplyRoutePlanCommand(airline: airline, route: id,
            plan: RoutePlan(fare: .dollars(999), frequency: 21))) else { Issue.record("Expected rejection"); return }
        #expect(engine.state.routes[id] == before.routes[id])
        #expect(engine.state.world == before.world)
    }

    @Test func soldOutSlotsRejectWholePlan() throws {
        let (catalog, engine, airline, _) = try RouteFixtures.withAircraft()
        let id = RouteFixtures.openStvLnw(engine, airline)
        var state = engine.state
        let capacity = try #require(catalog.airport("ARN")).slotCapacityPerDay
        _ = state.world.allocateSlots(airline: airline, airport: "ARN",
            count: capacity - state.world.slotsUsed(at: "ARN"), capacityPerDay: capacity)
        let command = ApplyRoutePlanCommand(airline: airline, route: id, plan: .init(fare: .dollars(160), frequency: 3))
        #expect(command.validate(state: state, catalog: catalog)?.code == "route.noSlots")
        #expect(RoutePlanPreview.make(routeID: id, plan: command.plan, state: state, catalog: catalog) == nil)
    }

    @Test func oldRouteSavesDecodeWithoutHistory() throws {
        let (_, engine, airline, _) = try RouteFixtures.withAircraft()
        let id = RouteFixtures.openStvLnw(engine, airline)
        let route = try #require(engine.state.routes[id])
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(route)) as? [String: Any])
        json.removeValue(forKey: "planHistory")
        let restored = try JSONDecoder().decode(Route.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.planHistory == nil)
        #expect(RoutePlan(route: restored) == RoutePlan(route: route))
    }

    @Test func previewIsPureAndAgreesWithAircraftQuote() throws {
        let (catalog, engine, airline, aircraftID) = try RouteFixtures.withAircraft()
        let id = RouteFixtures.openStvLnw(engine, airline)
        #expect(engine.applyNow(AssignAircraftToRouteCommand(airline: airline, route: id, aircraftID: aircraftID)) == .applied)
        let state = engine.state
        let route = try #require(state.routes[id])
        let aircraft = try #require(state.aircraft[aircraftID])
        let spec = try #require(catalog.aircraftType(aircraft.typeCode))
        let quote = try #require(RoutePlanPreview.make(routeID: id, plan: .init(route: route), state: state, catalog: catalog))
        let plane = try #require(AircraftConfigurationPreview.make(aircraftID: aircraftID, configuration: aircraft.cabin(for: spec), state: state, catalog: catalog))
        #expect(quote.revenue == plane.monthlyRevenue)
        #expect(quote.costs == plane.monthlyCosts)
        #expect(abs(quote.loadFactor - plane.loadFactor) < 0.000001)
        let changed = try #require(RoutePlanPreview.make(routeID: id, plan: .init(fare: .dollars(200), frequency: 3), state: state, catalog: catalog))
        #expect(changed != quote)
        #expect(engine.state == state)
    }

    @Test func aircraftComparisonUsesInstalledCabinWithoutAssignment() throws {
        let (catalog, engine, airline, aircraftID) = try RouteFixtures.withAircraft()
        let id = RouteFixtures.openStvLnw(engine, airline)
        let aircraft = try #require(engine.state.aircraft[aircraftID])
        let spec = try #require(catalog.aircraftType(aircraft.typeCode))
        var cabin = aircraft.cabin(for: spec)
        cabin.setSeats(8, in: .business, capacity: spec.seats)
        #expect(engine.applyNow(ConfigureAircraftCommand(airline: airline, aircraftID: aircraftID, configuration: cabin)) == .applied)
        let before = engine.state
        let route = try #require(before.routes[id])
        let quote = try #require(RoutePlanPreview.make(routeID: id, plan: .init(route: route), comparisonAircraft: aircraftID, state: before, catalog: catalog))
        #expect(quote.seatsPerDay == quote.rotations * 2 * cabin.totalSeats)
        #expect(engine.state == before)
        #expect(engine.state.aircraft[aircraftID]?.assignedRoute == nil)
    }
}
