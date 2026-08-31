import Foundation
import Testing
@testable import AirlineEmpireCore

@Suite("Geography")
struct GeoTests {
    @Test func knownDistances() {
        // Real-world anchors, ±3% (haversine on a spherical Earth).
        let stockholm = Coordinate(latitude: 59.65, longitude: 17.92)
        let london = Coordinate(latitude: 51.47, longitude: -0.45)
        let newYork = Coordinate(latitude: 40.64, longitude: -73.78)
        let sydney = Coordinate(latitude: -33.95, longitude: 151.18)

        let stoLon = Geo.distanceKm(from: stockholm, to: london)
        #expect(abs(stoLon - 1430) < 45, "STO-LON was \(stoLon)")

        let lonNyc = Geo.distanceKm(from: london, to: newYork)
        #expect(abs(lonNyc - 5570) < 170, "LON-NYC was \(lonNyc)")

        let lonSyd = Geo.distanceKm(from: london, to: sydney)
        #expect(abs(lonSyd - 17000) < 510, "LON-SYD was \(lonSyd)")
    }

    @Test func symmetryAndIdentity() {
        let a = Coordinate(latitude: 35.55, longitude: 139.78)
        let b = Coordinate(latitude: -33.95, longitude: 151.18)
        #expect(Geo.distanceKm(from: a, to: b) == Geo.distanceKm(from: b, to: a))
        #expect(Geo.distanceKm(from: a, to: a) == 0)
    }

    @Test func antipodalNearHalfCircumference() {
        let a = Coordinate(latitude: 0, longitude: 0)
        let b = Coordinate(latitude: 0, longitude: 180)
        let d = Geo.distanceKm(from: a, to: b)
        #expect(abs(d - 20015) < 10)
    }

    @Test func dateLineCrossing() {
        // Nadi (177.44E) to Auckland (174.79E) is short; but crossing 180°
        // must not wrap the long way.
        let west = Coordinate(latitude: 0, longitude: 179.5)
        let east = Coordinate(latitude: 0, longitude: -179.5)
        #expect(Geo.distanceKm(from: west, to: east) < 150)
    }

    @Test func coordinateValidation() {
        #expect(Coordinate(latitude: 90, longitude: 180).isValid)
        #expect(!Coordinate(latitude: 90.1, longitude: 0).isValid)
        #expect(!Coordinate(latitude: 0, longitude: -180.5).isValid)
    }
}

@Suite("Content catalog")
struct ContentCatalogTests {
    @Test func bundledContentLoadsAndValidates() throws {
        let catalog = try ContentCatalog.loadBundled()
        #expect(catalog.airports.count == 94)
        #expect(catalog.version == "world-1")
        // Every region is represented.
        for region in WorldRegion.allCases {
            #expect(!catalog.airports(in: region).isEmpty, "No airports in \(region)")
        }
        // Spot checks.
        let stockholm = try #require(catalog.airport("ARN"))
        #expect(stockholm.city == "Stockholm")
        #expect(stockholm.region == .europe)
        #expect(stockholm.runwayClass == .large)
    }

    @Test func bundledDistancesAreSane() throws {
        let catalog = try ContentCatalog.loadBundled()
        let d = try #require(catalog.distanceKm("ARN", "LHR"))
        #expect(d > 1300 && d < 1600, "STV-LNW was \(d)")
        let longHaul = try #require(catalog.distanceKm("LHR", "SYD"))
        #expect(longHaul > 16000, "LNW-SYH was \(longHaul)")
        #expect(catalog.distanceKm("ARN", "XXX") == nil)
    }

    @Test func nearestAirportsSortedAscending() throws {
        let catalog = try ContentCatalog.loadBundled()
        let nearest = catalog.nearestAirports(to: "ARN", limit: 5)
        #expect(nearest.count == 5)
        #expect(zip(nearest, nearest.dropFirst()).allSatisfy { $0.1 <= $1.1 })
        // Oslo should be Stockholm's closest neighbor in this dataset.
        #expect(nearest.first?.0.code == AirportCode("OSL"))
    }

    @Test func duplicateCodeRejected() {
        let a = TestAirports.make(code: "AAA")
        #expect(throws: ContentError.self) {
            _ = try ContentCatalog(version: "t", airports: [a, a],
                                   seasonality: [TestAirports.flatProfile],
                                   tuning: Tuning(minRouteDistanceKm: 80))
        }
    }

    @Test func invalidDataRejectedWithSpecificProblems() {
        let bad = TestAirports.make(code: "BAD", latitude: 123.0, slotCapacity: 0,
                                    seasonality: "missingProfile")
        do {
            _ = try ContentCatalog(version: "t", airports: [bad],
                                   seasonality: [TestAirports.flatProfile],
                                   tuning: Tuning(minRouteDistanceKm: 80))
            Issue.record("Expected validation failure")
        } catch let ContentError.invalid(problems) {
            #expect(problems.contains { $0.contains("invalid coordinates") })
            #expect(problems.contains { $0.contains("non-positive capacity") })
            #expect(problems.contains { $0.contains("unknown seasonality") })
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func seasonalityProfilesComplete() throws {
        let catalog = try ContentCatalog.loadBundled()
        for (_, profile) in catalog.seasonality {
            #expect(profile.leisureMonthly.count == 12)
            // Profiles are demand shapes, not free demand: yearly mean stays
            // near neutral so seasonality redistributes rather than inflates.
            let mean = profile.leisureMonthly.reduce(0, +) / 12
            #expect(mean > 0.85 && mean < 1.15,
                    "\(profile.code) mean \(mean) drifts from neutral")
        }
    }
}

@Suite("Route eligibility")
struct RouteEligibilityTests {
    static func catalog() throws -> ContentCatalog {
        try ContentCatalog.loadBundled()
    }

    @Test func validRouteHasNoReasons() throws {
        let reasons = try Self.catalog().routeEligibility(
            from: "ARN", to: "LHR", aircraftRangeKm: 5500, aircraftRunwayRequirement: .large)
        #expect(reasons.isEmpty)
    }

    @Test func sameAirportRejected() throws {
        let reasons = try Self.catalog().routeEligibility(
            from: "ARN", to: "ARN", aircraftRangeKm: 5000, aircraftRunwayRequirement: .small)
        #expect(reasons == [.sameAirport])
    }

    @Test func unknownAirportRejected() throws {
        let reasons = try Self.catalog().routeEligibility(
            from: "ARN", to: "NOPE", aircraftRangeKm: 5000, aircraftRunwayRequirement: .small)
        #expect(reasons == [.unknownAirport("NOPE")])
    }

    @Test func beyondRangeRejected() throws {
        let reasons = try Self.catalog().routeEligibility(
            from: "LHR", to: "SYD", aircraftRangeKm: 5500, aircraftRunwayRequirement: .large)
        #expect(reasons.contains { if case .beyondAircraftRange = $0 { true } else { false } })
    }

    @Test func runwayClassEnforcedAtBothEnds() throws {
        // KRK (Tromsø) is a small runway; a widebody can't serve it.
        let reasons = try Self.catalog().routeEligibility(
            from: "LHR", to: "TOS", aircraftRangeKm: 12000, aircraftRunwayRequirement: .veryLarge)
        #expect(reasons.contains(.runwayTooSmall(airport: "TOS", has: .small, needs: .veryLarge)))
        #expect(!reasons.contains(.runwayTooSmall(airport: "LHR", has: .veryLarge, needs: .veryLarge)))
    }

    @Test func minimumDistanceEnforced() throws {
        // Two airports < 80 km apart: synthesize via direct catalog.
        let near1 = TestAirports.make(code: "NR1", latitude: 50.0, longitude: 10.0)
        let near2 = TestAirports.make(code: "NR2", latitude: 50.3, longitude: 10.0) // ~33 km
        let catalog = try ContentCatalog(version: "t", airports: [near1, near2],
                                         seasonality: [TestAirports.flatProfile],
                                         tuning: Tuning(minRouteDistanceKm: 80))
        let reasons = catalog.routeEligibility(from: "NR1", to: "NR2",
                                               aircraftRangeKm: 2000,
                                               aircraftRunwayRequirement: .small)
        #expect(reasons.contains { if case .belowMinimumDistance = $0 { true } else { false } })
    }

    @Test func runwayOrdering() {
        #expect(RunwayClass.small < .medium)
        #expect(RunwayClass.medium < .large)
        #expect(RunwayClass.large < .veryLarge)
        #expect(!(RunwayClass.veryLarge < .veryLarge))
    }
}

@Suite("Slots")
struct SlotTests {
    let airline1 = AirlineID(raw: 1)
    let airline2 = AirlineID(raw: 2)
    let airport = AirportCode("ARN")

    @Test func allocateWithinCapacity() {
        var world = WorldState()
        #expect(world.allocateSlots(airline: airline1, airport: airport,
                                    count: 10, capacityPerDay: 100) == nil)
        #expect(world.slotsHeld(by: airline1, at: airport) == 10)
        #expect(world.slotsUsed(at: airport) == 10)
    }

    @Test func capacitySharedAcrossAirlines() {
        var world = WorldState()
        #expect(world.allocateSlots(airline: airline1, airport: airport,
                                    count: 60, capacityPerDay: 100) == nil)
        #expect(world.allocateSlots(airline: airline2, airport: airport,
                                    count: 30, capacityPerDay: 100) == nil)
        let error = world.allocateSlots(airline: airline2, airport: airport,
                                        count: 20, capacityPerDay: 100)
        #expect(error == .capacityExceeded(requested: 20, available: 10))
        // Failed allocation changed nothing.
        #expect(world.slotsUsed(at: airport) == 90)
    }

    @Test func releaseReturnsCapacity() {
        var world = WorldState()
        _ = world.allocateSlots(airline: airline1, airport: airport,
                                count: 50, capacityPerDay: 100)
        #expect(world.releaseSlots(airline: airline1, airport: airport, count: 20) == nil)
        #expect(world.slotsHeld(by: airline1, at: airport) == 30)
        #expect(world.allocateSlots(airline: airline2, airport: airport,
                                    count: 70, capacityPerDay: 100) == nil)
    }

    @Test func releasingMoreThanHeldRejected() {
        var world = WorldState()
        _ = world.allocateSlots(airline: airline1, airport: airport,
                                count: 5, capacityPerDay: 100)
        let error = world.releaseSlots(airline: airline1, airport: airport, count: 6)
        #expect(error == .releasingUnheldSlots(requested: 6, held: 5))
        #expect(world.slotsHeld(by: airline1, at: airport) == 5)
        #expect(world.releaseSlots(airline: airline2, airport: airport, count: 1)
                == .releasingUnheldSlots(requested: 1, held: 0))
    }

    @Test func fullReleaseCleansRuntimeEntry() {
        var world = WorldState()
        _ = world.allocateSlots(airline: airline1, airport: airport,
                                count: 5, capacityPerDay: 100)
        _ = world.releaseSlots(airline: airline1, airport: airport, count: 5)
        // Untouched airports must not accrete in the save.
        #expect(world.airportRuntimes.isEmpty)
    }

    @Test func invalidCountsRejected() {
        var world = WorldState()
        #expect(world.allocateSlots(airline: airline1, airport: airport,
                                    count: 0, capacityPerDay: 100) == .invalidCount(0))
        #expect(world.allocateSlots(airline: airline1, airport: airport,
                                    count: -3, capacityPerDay: 100) == .invalidCount(-3))
        #expect(world.releaseSlots(airline: airline1, airport: airport, count: 0)
                == .invalidCount(0))
    }

    @Test func worldStateSurvivesSaveDeterministically() throws {
        // Entity-keyed dictionaries must encode as sorted objects
        // (CodingKeyRepresentable + sortedKeys) — this is the regression
        // test for byte-deterministic saves with populated world slices.
        var state = Fixtures.newState()
        for i in 1...8 {
            _ = state.world.allocateSlots(airline: AirlineID(raw: Int64(i)),
                                          airport: AirportCode("AP\(i % 3)"),
                                          count: i, capacityPerDay: 1000)
        }
        let codec = JSONSaveCodec()
        let a = try codec.encode(state)
        let restored = try codec.decode(a)
        #expect(restored == state)
        let b = try codec.encode(restored)
        #expect(a == b)
    }
}

enum TestAirports {
    static let flatProfile = SeasonalityProfile(
        code: "flat", leisureMonthly: Array(repeating: 1.0, count: 12))

    static func make(code: String, latitude: Double = 50.0, longitude: Double = 8.0,
                     slotCapacity: Int = 100, seasonality: SeasonalityCode = "flat") -> AirportSpec {
        AirportSpec(
            code: AirportCode(code), name: "\(code) Field", city: code, country: "Testland",
            region: .europe, coordinate: Coordinate(latitude: latitude, longitude: longitude),
            utcOffsetMinutes: 0, runwayClass: .large, slotCapacityPerDay: slotCapacity,
            terminalCapacityPerDay: 10_000, movementFee: Money.dollars(1000),
            passengerFee: Money.dollars(15),
            demographics: Demographics(populationThousands: 1000, businessIndex: 0.5,
                                       leisureIndex: 0.5, tourismIndex: 0.5, cargoIndex: 0.5),
            seasonality: seasonality, weatherRisk: .low)
    }
}
