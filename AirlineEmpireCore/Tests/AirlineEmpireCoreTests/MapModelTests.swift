import Testing
@testable import AirlineEmpireCore

@Suite("Map model")
struct MapModelTests {
    @Test func greatCircleEndpointsAndMidpoint() {
        let london = Coordinate(latitude: 51.47, longitude: -0.45)
        let newYork = Coordinate(latitude: 40.64, longitude: -73.78)
        let start = MapMath.greatCirclePoint(from: london, to: newYork, fraction: 0)
        let end = MapMath.greatCirclePoint(from: london, to: newYork, fraction: 1)
        #expect(abs(start.latitude - london.latitude) < 0.01)
        #expect(abs(end.longitude - newYork.longitude) < 0.01)
        // The LON-NYC great circle famously arcs NORTH of both endpoints.
        let mid = MapMath.greatCirclePoint(from: london, to: newYork, fraction: 0.5)
        #expect(mid.latitude > 51.5, "mid latitude \(mid.latitude)")
        // Midpoint splits the distance evenly.
        let d1 = Geo.distanceKm(from: london, to: mid)
        let d2 = Geo.distanceKm(from: mid, to: newYork)
        #expect(abs(d1 - d2) <= 2)
    }

    @Test func headingIsSane() {
        let equatorWest = Coordinate(latitude: 0, longitude: 0)
        let equatorEast = Coordinate(latitude: 0, longitude: 10)
        #expect(abs(MapMath.heading(from: equatorWest, to: equatorEast) - 90) < 0.5)
        let north = Coordinate(latitude: 10, longitude: 0)
        #expect(abs(MapMath.heading(from: equatorWest, to: north) - 0) < 0.5)
    }

    @Test func mapPointNormalization() {
        let topLeft = MapPoint(coordinate: Coordinate(latitude: 90, longitude: -180))
        #expect(topLeft.x == 0 && topLeft.y == 0)
        let center = MapPoint(coordinate: Coordinate(latitude: 0, longitude: 0))
        #expect(abs(center.x - 0.5) < 0.001 && abs(center.y - 0.5) < 0.001)
    }

    @Test func mapModelTracksFlightsAcrossTheSky() throws {
        let (engine, _, route) = try DemandFixtures.market(fare: Money.dollars(129))
        // Reach mid-morning with a flight airborne.
        engine.advance(ticks: Fixtures.ticksPerDay + 30)
        var sawAirborne = false
        for _ in 0..<40 {
            engine.advance(ticks: 1)
            let model = engine.state.mapModel(catalog: engine.catalog)
            if let airborne = model.flights.first(where: { $0.airborne }) {
                sawAirborne = true
                // Position lies between the endpoints (x within arc bounds).
                let r = model.routes.first { $0.id == route }!
                let minX = min(r.from.x, r.to.x) - 0.02
                let maxX = max(r.from.x, r.to.x) + 0.02
                #expect(airborne.position.x >= minX && airborne.position.x <= maxX)
                #expect(airborne.isPlayer)
                break
            }
        }
        #expect(sawAirborne, "No airborne flight observed")
    }

    @Test func mapModelMarksPlayerNetworkAndProminence() throws {
        let (engine, _) = try AIFixtures.world(competitors: 3)
        engine.advance(ticks: Fixtures.ticksPerDay * 40)
        let model = engine.state.mapModel(catalog: engine.catalog)
        #expect(model.airports.count == 94)
        #expect(model.airports.allSatisfy { $0.prominence > 0 && $0.prominence <= 1 })
        // Player serves nothing yet in this fixture beyond... actually the
        // player has no routes here; AI routes must NOT be marked player.
        #expect(model.routes.allSatisfy { !$0.isPlayer })
        #expect(!model.routes.isEmpty)
        // Arcs are drawable polylines.
        #expect(model.routes.allSatisfy { $0.arc.count == 25 })
    }
}
