import Testing
@testable import AirlineEmpireCore

@Suite("Smart route and fleet planning")
struct FleetPlanningTests {
    @Test func idleFilterRequiresAvailableUnassignedAircraftAndRouteFit() throws {
        let (catalog, engine, airline, id) = try RouteFixtures.withAircraft()
        var state = engine.state
        #expect(state.idleAircraft(from: "ARN", to: "LHR", catalog: catalog).map(\.id) == [id])
        #expect(state.idleAircraft(from: "ARN", to: "SYD", catalog: catalog).isEmpty)
        state.aircraft[id]?.status = .inMaintenance(until: state.clock.now)
        #expect(state.idleAircraft(from: "ARN", to: "LHR", catalog: catalog).isEmpty)
        state.aircraft[id]?.status = .ordered(deliveryAt: state.clock.now)
        #expect(state.idleAircraft(from: "ARN", to: "LHR", catalog: catalog).isEmpty)
        state.aircraft[id]?.status = .active
        state.aircraft[id]?.activeFlight = FlightID(raw: 999)
        #expect(state.idleAircraft(from: "ARN", to: "LHR", catalog: catalog).isEmpty)
        let route = RouteFixtures.openStvLnw(engine, airline)
        _ = engine.applyNow(AssignAircraftToRouteCommand(airline: airline, route: route, aircraftID: id))
        #expect(engine.state.idleAircraft(from: "ARN", to: "LHR", catalog: catalog).isEmpty)
    }

    @Test func fleetNeedsDistinguishesMissingAircraftFrequencyAndSeats() throws {
        let (catalog, engine, airline, id) = try RouteFixtures.withAircraft()
        let route = RouteFixtures.openStvLnw(engine, airline, trips: 1)
        #expect(engine.state.fleetNeeds(catalog: catalog).first?.reason == .unassigned)
        _ = engine.applyNow(AssignAircraftToRouteCommand(airline: airline, route: route, aircraftID: id))
        var state = engine.state
        state.routes[route]?.demandOutboundToday = 1
        state.routes[route]?.demandInboundToday = 1
        #expect(state.fleetNeeds(catalog: catalog).isEmpty)
        state.routes[route]?.dailyRoundTrips = 20
        #expect(state.fleetNeeds(catalog: catalog).first?.reason == .frequency)
        state.routes[route]?.dailyRoundTrips = 1
        state.routes[route]?.demandOutboundToday = 1_000
        #expect(state.fleetNeeds(catalog: catalog).first?.reason == .seats)
        state.aircraft[id]?.status = .inMaintenance(until: state.clock.now)
        #expect(state.fleetNeeds(catalog: catalog).first?.reason == .frequency)
    }

    @Test func marketFitHonorsEraRangeAndRunwaysAndEstimatesNewRouteDemand() throws {
        let (catalog, engine, airline, _) = try RouteFixtures.withAircraft()
        let id = RouteFixtures.openStvLnw(engine, airline)
        var route = try #require(engine.state.routes[id])
        route.demandOutboundToday = 0
        route.demandInboundToday = 0
        let fits = engine.state.aircraftFits(route: route, catalog: catalog, era: .startup)
        #expect(!fits.isEmpty)
        for spec in fits {
            #expect(Era.startup.allowedCategories.contains(spec.category))
            #expect(catalog.routeEligibility(from: route.origin, to: route.destination,
                aircraftRangeKm: spec.rangeKm, aircraftRunwayRequirement: spec.runwayRequirement).isEmpty)
        }
        let demand = try #require(engine.state.marketCandidates(from: route.origin, catalog: catalog)
            .first(where: { $0.destination == route.destination })).expectedDailyPassengers
        func mismatch(_ spec: AircraftTypeSpec) -> Int {
            let trips = min(route.dailyRoundTrips, FlightSchedulingSystem.roundTripsPerAircraftPerDay(
                distanceKm: route.distanceKm, spec: spec, ops: catalog.tuning.ops))
            return abs(demand - trips * spec.seats * 2)
        }
        #expect(fits.map(mismatch) == fits.map(mismatch).sorted())
    }
}
