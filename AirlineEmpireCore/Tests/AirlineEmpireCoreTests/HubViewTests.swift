import Foundation
import Testing
@testable import AirlineEmpireCore

@Suite("Hub view layout")
struct HubLayoutTests {
    static let catalog = try! ContentCatalog.loadBundled()

    static var allAirports: [AirportSpec] {
        catalog.airports.values.sorted { $0.code < $1.code }
    }

    @Test func layoutIsDeterministic() {
        for spec in Self.allAirports.prefix(12) {
            #expect(HubLayout.make(airport: spec) == HubLayout.make(airport: spec), "\(spec.code)")
        }
    }

    @Test func standCountScalesWithSlotsWithinBounds() {
        #expect(HubLayout.standCount(slotCapacityPerDay: 0) == 4)
        #expect(HubLayout.standCount(slotCapacityPerDay: 150) == 6)
        #expect(HubLayout.standCount(slotCapacityPerDay: 1_500) == 18)
        for spec in Self.allAirports {
            let layout = HubLayout.make(airport: spec)
            #expect(layout.stands.count == HubLayout.standCount(slotCapacityPerDay: spec.slotCapacityPerDay),
                    "\(spec.code)")
            #expect(Set(layout.stands.map(\.gate)).count == layout.stands.count, "gates unique at \(spec.code)")
        }
    }

    @Test func runwaysMatchTheAirportClass() {
        for spec in Self.allAirports {
            let layout = HubLayout.make(airport: spec)
            switch spec.runwayClass {
            case .small, .medium: #expect(layout.runways.count == 1, "\(spec.code)")
            case .veryLarge: #expect(layout.runways.count == 2, "\(spec.code)")
            case .large: #expect((1...2).contains(layout.runways.count), "\(spec.code)")
            }
            // Runways are airside of everything with a roof.
            let roofed = layout.pieces.filter { [.terminalHall, .pier, .hangar, .cargoShed].contains($0.kind) }
            for runway in layout.runways {
                for piece in roofed {
                    #expect(piece.groundBounds.minZ > runway.thresholdA.z + runway.width / 2,
                            "\(piece.kind) crosses a runway at \(spec.code)")
                }
            }
        }
    }

    /// No two parked aircraft overlap, and none sits on a building.
    @Test func parkedAircraftEnvelopesAreClear() {
        for spec in Self.allAirports {
            let layout = HubLayout.make(airport: spec)
            let envelopes = layout.stands.map { stand -> HubRect in
                let len = HubAircraftEnvelope.length(stand.maxCategory)
                let span = HubAircraftEnvelope.span(stand.maxCategory)
                let fwd = HubVec(cos(stand.heading), 0, -sin(stand.heading))
                let center = stand.nose - fwd * (len / 2)
                let piece = HubPiece(.apron, center: center, size: HubVec(len, 1, span), yaw: stand.heading)
                return piece.groundBounds
            }
            for i in envelopes.indices {
                for j in envelopes.indices where j > i {
                    #expect(!envelopes[i].overlaps(envelopes[j], margin: 0.5),
                            "stands \(i) and \(j) overlap at \(spec.code)")
                }
                for building in layout.pieces where [.terminalHall, .pier, .hangar, .cargoShed, .controlTower].contains(building.kind) {
                    #expect(!envelopes[i].overlaps(building.groundBounds, margin: 1),
                            "stand \(i) hits \(building.kind) at \(spec.code)")
                }
            }
        }
    }

    @Test func everyStandSitsOnTheApron() {
        for spec in Self.allAirports {
            let layout = HubLayout.make(airport: spec)
            let apron = layout.pieces.first { $0.kind == .apron && $0.variant == 0 }!.groundBounds
            for stand in layout.stands {
                #expect(apron.contains(stand.nose), "stand \(stand.gate) off the apron at \(spec.code)")
            }
        }
    }

    @Test func departuresEndAirborneAndArrivalsEndAtTheStand() {
        let spec = Self.catalog.airport("LHR")!
        let layout = HubLayout.make(airport: spec)
        for stand in layout.stands {
            let last = stand.departure.points.last!
            #expect(last.y > 100, "departure from gate \(stand.gate) never climbs")
            let end = stand.arrival.points.last!
            #expect(end.y == 0)
            #expect(stand.arrival.points.first!.y > 100, "arrival starts on approach")
            #expect(stand.departure.length > 1_000)
            // The taxi route passes through the runway's line-up point.
            let runwayZ = layout.runways[0].thresholdA.z
            #expect(stand.departure.points.contains { abs($0.z - runwayZ) < 0.01 && $0.y == 0 })
        }
    }

    @Test func pathSamplingIsContinuous() {
        let path = HubPath([HubVec(0, 0, 0), HubVec(100, 0, 0), HubVec(100, 0, -50)])
        #expect(path.length == 150)
        #expect(path.sample(at: 50).position == HubVec(50, 0, 0))
        #expect(abs(path.sample(at: 50).yaw) < 1e-9)
        let corner = path.sample(at: 125)
        #expect(corner.position == HubVec(100, 0, -25))
        // Heading north (−z) is +90°.
        #expect(abs(corner.yaw - .pi / 2) < 1e-9)
        #expect(path.sample(at: 1_000).position == HubVec(100, 0, -50))
        #expect(path.sample(fraction: 0).position == HubVec(0, 0, 0))
    }

    @Test func districtAndServiceRouteExist() {
        let layout = HubLayout.make(airport: Self.catalog.airport("ARN")!)
        #expect(layout.pieces(.house).count >= 9)
        #expect(layout.serviceStops.count == 3)
        #expect(layout.serviceRoute.points.count >= 5)
        #expect(layout.pieces(.tree).count > 60)
        #expect(!layout.interior.pieces.filter { $0.kind == .securityLane }.isEmpty)
        #expect(layout.interior.hotspots.count == layout.interior.bays * HubTerminalInterior.hotspotsPerBay)
        #expect(layout.interior.pieces.filter { $0.kind == .bayPartition }.count == layout.interior.bays - 1)
        // The reference's hall: kiosks, e-gates, shops, security arches, a
        // stair and a departure board.
        for kind in [HubPieceKind.kiosk, .securityLane, .shopShelf, .shopFront, .gondola, .cafeCounter,
                     .metalDetector, .luggageTrolley, .electricCart, .escalator, .flightBoard, .wayfindingSign] {
            #expect(layout.interior.pieces.contains { $0.kind == kind }, "no \(kind) in the hall")
        }
    }

    @Test func biggerTerminalsGetMoreKiosksAndSecurity() {
        let small = HubLayout.make(airport: Self.catalog.airport("GOT")!)
        let big = HubLayout.make(airport: Self.catalog.airport("ATL")!)
        func count(_ l: HubLayout, _ k: HubPieceKind) -> Int { l.interior.pieces.filter { $0.kind == k }.count }
        #expect(count(big, .securityLane) > count(small, .securityLane))
        #expect(count(big, .kiosk) > count(small, .kiosk))
        #expect(big.terminal.width > small.terminal.width)
    }

    /// Interior furniture stays inside the hall's floor.
    @Test func interiorStaysInsideTheHall() {
        for spec in Self.allAirports.prefix(30) {
            let interior = HubLayout.make(airport: spec).interior
            let hall = interior.bounds
            for piece in interior.pieces {
                let r = piece.groundBounds
                #expect(r.minX >= hall.minX - 0.5 && r.maxX <= hall.maxX + 0.5 &&
                        r.minZ >= hall.minZ - 0.5 && r.maxZ <= hall.maxZ + 0.5,
                        "\(piece.kind) outside the hall at \(spec.code)")
            }
        }
    }

    @Test func loungeAppearsOnlyWhenBought() {
        let spec = Self.catalog.airport("ARN")!
        let none = HubLayout.make(airport: spec)
        let some = HubLayout.make(airport: spec, facilities: AirportFacilities(lounge: 2, groundServices: 0))
        #expect(none.interior.pieces.allSatisfy { $0.kind != .loungeBlock })
        #expect(some.interior.pieces.contains { $0.kind == .loungeBlock && $0.variant == 2 })
    }

    /// Every pier face carries jets: the planner spreads stands evenly, so
    /// no pier is a bare wall in the overview.
    @Test func standsAreSpreadOverEveryPierFace() {
        for spec in Self.allAirports {
            let layout = HubLayout.make(airport: spec)
            let piers = layout.pieces(.pier)
            guard !piers.isEmpty else { continue }
            var perFace: [String: Int] = [:]
            for stand in layout.stands {
                guard let pier = piers.min(by: { abs($0.center.x - stand.nose.x) < abs($1.center.x - stand.nose.x) }) else { continue }
                let key = "\(pier.center.x)/\(stand.nose.x < pier.center.x ? "w" : "e")"
                perFace[key, default: 0] += 1
            }
            let counts = Array(perFace.values)
            #expect((counts.max() ?? 0) - (counts.min() ?? 0) <= 1, "unbalanced piers at \(spec.code): \(perFace)")
            if layout.stands.count >= piers.count * 2 {
                #expect(perFace.count == piers.count * 2, "a bare pier face at \(spec.code)")
            }
        }
    }

    /// The apron hugs its stands: one taxilane beyond the furthest stand or
    /// pier tip, not a field of empty concrete (reference shot A).
    @Test func apronIsTightAroundTheStands() {
        for spec in Self.allAirports {
            let layout = HubLayout.make(airport: spec)
            let apron = layout.pieces.first { $0.kind == .apron && $0.variant == 0 }!.groundBounds
            let reach = (layout.stands.map(\.parkedEnvelope) + layout.pieces(.pier).map(\.groundBounds))
                .reduce(layout.terminal) { $0.union($1) }
            let lane = HubAircraftEnvelope.span(layout.stands[0].maxCategory) + 12
            #expect(abs((reach.minZ - apron.minZ) - lane) < 1, "apron margin at \(spec.code)")
            for stand in layout.stands {
                let e = stand.parkedEnvelope
                #expect(e.minX >= apron.minX && e.maxX <= apron.maxX && e.minZ >= apron.minZ,
                        "stand \(stand.gate) hangs off the apron at \(spec.code)")
                let push = stand.departure.points[1]
                #expect(apron.contains(push), "gate \(stand.gate) pushes back off the apron at \(spec.code)")
            }
        }
    }

    /// Apron service roads stay on the apron and clear of buildings and
    /// parked aircraft, so the vehicles on them never drive through a jet.
    @Test func serviceLanesAreClear() {
        for spec in Self.allAirports {
            let layout = HubLayout.make(airport: spec)
            #expect(layout.serviceLanes.count >= 2, "\(spec.code)")
            let apron = layout.pieces.first { $0.kind == .apron && $0.variant == 0 }!.groundBounds
            let solid = layout.pieces.filter { [.pier, .terminalHall].contains($0.kind) }.map(\.groundBounds)
                + layout.stands.map(\.parkedEnvelope)
            for lane in layout.serviceLanes {
                #expect(lane.length > 20)
                var d = 0.0
                while d <= lane.length {
                    let p = lane.sample(at: d).position
                    #expect(apron.contains(p), "lane leaves the apron at \(spec.code)")
                    #expect(!solid.contains { $0.contains(p) }, "lane hits something at \(spec.code) \(p)")
                    d += 4
                }
            }
        }
    }

    /// The district's service route runs on the road the whole way (the
    /// reference draws it on the street), and the mid-rise apartments stand
    /// on the airport side of the villas.
    @Test func serviceRouteFollowsTheStreets() {
        for spec in Self.allAirports.prefix(40) {
            let layout = HubLayout.make(airport: spec)
            let paved = layout.pieces.filter { [.road, .roundabout, .crosswalk].contains($0.kind) }.map(\.groundBounds)
            let route = layout.serviceRoute
            var d = 0.0
            while d <= route.length {
                let p = route.sample(at: d).position
                #expect(paved.contains { HubRect(minX: $0.minX - 1, minZ: $0.minZ - 1, maxX: $0.maxX + 1, maxZ: $0.maxZ + 1).contains(p) },
                        "route leaves the road at \(spec.code) \(p)")
                d += 3
            }
            let flats = layout.pieces(.apartmentBlock)
            #expect(flats.count == 4, "\(spec.code)")
            let houses = layout.pieces(.house)
            #expect(flats.allSatisfy { f in houses.allSatisfy { f.groundBounds.maxZ < $0.groundBounds.minZ } },
                    "apartments not behind the villas at \(spec.code)")
            #expect(layout.pieces(.roundabout).count == 2)
        }
    }

    /// Every shot frames its subject inside the part of the screen the
    /// dashboard leaves free, on iPad and iPhone, and the overview's jets
    /// stay big enough to read.
    @Test func shotsFrameTheirSubjectInTheSafeArea() {
        let shapes: [(aspect: Double, safe: HubSafeArea)] = [(1.333, .wide), (0.46, .tall), (2.17, .landscape)]
        for spec in Self.allAirports.prefix(30) {
            let layout = HubLayout.make(airport: spec)
            for (aspect, safe) in shapes {
                func inside(_ p: HubVec, _ frame: HubFrame, _ what: String, slack: Double = 0.03) {
                    guard let s = HubFraming.project(p, frame: frame, aspect: aspect) else {
                        Issue.record("\(what) behind the camera at \(spec.code)"); return
                    }
                    #expect(s.x >= safe.minX - slack && s.x <= safe.maxX + slack &&
                            s.y >= safe.minY - slack && s.y <= safe.maxY + slack,
                            "\(what) off screen (\(s.x), \(s.y)) at \(spec.code) aspect \(aspect)")
                }
                let overview = layout.frame(.overview, aspect: aspect, safe: safe)
                inside(layout.terminal.center, overview, "terminal")
                #expect(overview.distance > 150 && overview.distance < 4_000, "\(spec.code) \(overview.distance)")
                if aspect > 1, let stand = layout.stands.first {
                    let e = stand.parkedEnvelope
                    let a = HubFraming.project(HubVec(e.minX, 0, e.center.z), frame: overview, aspect: aspect)
                    let b = HubFraming.project(HubVec(e.maxX, 0, e.center.z), frame: overview, aspect: aspect)
                    if let a, let b {
                        #expect(abs(a.x - b.x) / 2 > 0.03, "jets are specks at \(spec.code)")
                    }
                }
                let gate = layout.frame(.gate(stand: 0), aspect: aspect, safe: safe)
                inside(layout.stands[0].nose, gate, "gate nose")
                inside(layout.stands[0].parkedEnvelope.center, gate, "gate jet")
                let terminal = layout.frame(.terminal, aspect: aspect, safe: safe)
                inside(layout.interior.hotspots[0].position, terminal, "security hotspot")
                let district = layout.frame(.district, aspect: aspect, safe: safe)
                inside(layout.serviceStops[0], district, "first stop")
                for kind in HubFacilityKind.allCases {
                    guard let site = layout.site(kind) else { continue }
                    let frame = layout.frame(.facility(kind), aspect: aspect, safe: safe)
                    inside(site.center, frame, "\(kind) site")
                    #expect(frame.distance < overview.distance, "\(kind) shot no closer than the overview at \(spec.code)")
                }
            }
        }
    }

    @Test func facilitySitesStandClearOfEverything() throws {
        for spec in Self.allAirports {
            let layout = HubLayout.make(airport: spec)
            #expect(Set(layout.facilitySites.map(\.kind)) == Set(HubFacilityKind.allCases), "\(spec.code)")
            // The lounge sits on the terminal roof, inside its footprint.
            let lounge = try #require(layout.site(.lounge))
            #expect(lounge.elevation == HubLayout.terminalRoofTop)
            #expect(layout.terminal.contains(HubVec(lounge.footprint.minX, 0, lounge.footprint.minZ))
                    && layout.terminal.contains(HubVec(lounge.footprint.maxX, 0, lounge.footprint.maxZ)), "\(spec.code)")
            // The depot's, hangar's and crew base's lots are on the ground
            // and clear of every piece, the stands' parked jets, the service
            // lanes and each other.
            let lots = try [HubFacilityKind.groundServices, .hangar, .crewBase].map { try #require(layout.site($0)) }
            for (index, lot) in lots.enumerated() {
                #expect(lot.elevation == 0)
                for piece in layout.pieces where piece.groundBounds.overlaps(lot.footprint, margin: 2) {
                    Issue.record("\(piece.kind) on the \(lot.kind) lot at \(spec.code)")
                }
                for stand in layout.stands where stand.parkedEnvelope.overlaps(lot.footprint) {
                    Issue.record("stand \(stand.gate) on the \(lot.kind) lot at \(spec.code)")
                }
                for lane in layout.serviceLanes where lane.points.contains(where: { lot.footprint.contains($0) }) {
                    Issue.record("service lane through the \(lot.kind) lot at \(spec.code)")
                }
                for other in lots[(index + 1)...] where other.footprint.overlaps(lot.footprint, margin: 6) {
                    Issue.record("\(lot.kind) and \(other.kind) lots overlap at \(spec.code)")
                }
            }
        }
    }

    @Test func safeAreaFollowsTheShapeOfTheView() {
        #expect(HubFraming.safeArea(width: 1_376, height: 1_032) == .wide)
        #expect(HubFraming.safeArea(width: 1_032, height: 1_376) == .wide)
        #expect(HubFraming.safeArea(width: 430, height: 932) == .tall)
        // An iPhone on its side: the short height wins over the width.
        #expect(HubFraming.safeArea(width: 932, height: 430) == .landscape)
        #expect(HubFraming.safeArea(width: 852, height: 393) == .landscape)
    }

    @Test func roundedPathsTurnThroughArcsNearTheirCorners() {
        let path = HubPath([HubVec(0, 0, 0), HubVec(100, 0, 0), HubVec(100, 0, 80)])
        let round = path.rounded(radius: 12)
        #expect(round.points.first == path.points.first)
        #expect(round.points.last == path.points.last)
        #expect(round.points.count > path.points.count)
        // Nothing strays further than the radius from the corner it rounds.
        for p in round.points where p.distance(to: HubVec(100, 0, 0)) < 20 {
            #expect(p.distance(to: HubVec(100, 0, 0)) <= 12 + 1e-9)
        }
        // The heading changes gradually: no single step turns by more than 20°.
        var last: Double?
        var d = 0.0
        while d <= round.length {
            let yaw = round.sample(at: d).yaw
            if let last {
                var turn = abs(yaw - last).truncatingRemainder(dividingBy: 2 * .pi)
                if turn > .pi { turn = 2 * .pi - turn }
                #expect(turn < 20 * .pi / 180, "sharp turn at \(d)")
            }
            last = yaw
            d += 1
        }
    }

    @Test func roundTripIsAClosedTwoWayLoop() {
        let path = HubPath([HubVec(0, 0, 0), HubVec(100, 0, 0)])
        let loop = path.roundTrip(lane: 2)
        #expect(loop.points.first == loop.points.last)
        // Out keeping right (south when heading east), back on the other side.
        #expect(abs(loop.points[0].z - 2) < 1e-9)
        #expect(loop.points.contains { abs($0.z + 2) < 1e-9 && $0.x > 50 })
        // Two straight legs and two half-circle U-turns of radius 2.
        #expect(abs(loop.length - (200 + 2 * .pi * 2)) < 1.5)
    }

    @Test func bearingsPointTheWayTheRouteLeaves() {
        let here = Coordinate(latitude: 0, longitude: 0)
        #expect(abs(Geo.bearing(from: here, to: Coordinate(latitude: 10, longitude: 0)) - 0) < 1e-6)
        #expect(abs(Geo.bearing(from: here, to: Coordinate(latitude: 0, longitude: 10)) - 90) < 1e-6)
        #expect(abs(Geo.bearing(from: here, to: Coordinate(latitude: -10, longitude: 0)) - 180) < 1e-6)
        #expect(abs(Geo.bearing(from: here, to: Coordinate(latitude: 0, longitude: -10)) - 270) < 1e-6)
    }

    @Test func layoutRoundTripsThroughCodable() throws {
        let layout = HubLayout.make(airport: Self.catalog.airport("FRA")!)
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(HubLayout.self, from: data) == layout)
    }
}

@Suite("Hub view snapshot")
struct HubSnapshotTests {
    @Test func formattingHelpers() {
        #expect(HubFormat.clock(0) == "00:00")
        #expect(HubFormat.clock(9 * 60 + 41) == "09:41")
        #expect(HubFormat.clock(-1) == "23:59")
        #expect(HubFormat.airlineCode("Anchor Air") == "AA")
        #expect(HubFormat.airlineCode("Nordwind") == "NO")
        #expect(HubFormat.airlineCode("") == "AE")
        #expect(HubFormat.flightCode(airline: "AA", route: RouteID(raw: 3), outbound: true)
            != HubFormat.flightCode(airline: "AA", route: RouteID(raw: 3), outbound: false))
        #expect(HubFormat.nightFactor(localMinute: 12 * 60) == 0)
        #expect(HubFormat.nightFactor(localMinute: 23 * 60) == 1)
        #expect(HubFormat.nightFactor(localMinute: 2 * 60) == 1)
        let dusk = HubFormat.nightFactor(localMinute: 19 * 60 + 30)
        #expect(dusk > 0 && dusk < 1)
    }

    @Test func playerAircraftParksAndWalksThroughTheTurnaround() throws {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        let layout = HubLayout.make(airport: engine.catalog.airport("MET")!)
        var stages = Set<HubTurnaroundStage>()
        var sawBoardRow = false
        var sawPlayerParked = false
        for _ in 0..<(Fixtures.ticksPerDay * 2) {
            engine.advance(ticks: 1)
            let snapshot = try #require(engine.state.hubSnapshot(airport: "MET", catalog: engine.catalog,
                                                                 layout: layout))
            #expect(snapshot.airlineName == engine.state.airlines[airline]!.name)
            if let mine = snapshot.occupants.first(where: { $0.operatorKind == .player }) {
                sawPlayerParked = true
                #expect(mine.aircraftID != nil)
                #expect(!mine.registration.isEmpty)
                #expect(mine.stageProgress >= 0 && mine.stageProgress <= 1)
                if let stage = mine.stage { stages.insert(stage) }
                #expect(snapshot.focusStand == mine.standIndex)
            }
            if !snapshot.departures.isEmpty { sawBoardRow = true }
            // Stands are never double-booked.
            #expect(Set(snapshot.occupants.map(\.standIndex)).count == snapshot.occupants.count)
        }
        #expect(sawPlayerParked)
        #expect(sawBoardRow)
        #expect(stages.contains(.boarding), "stages seen: \(stages)")
        #expect(stages.contains(.servicing) || stages.contains(.deboarding), "stages seen: \(stages)")
    }

    @Test func kpisReadTheRouteLedger() throws {
        let (engine, _, route) = try DemandFixtures.market(fare: Money.dollars(129))
        engine.advance(ticks: Fixtures.ticksPerDay * 5)
        let layout = HubLayout.make(airport: engine.catalog.airport("MET")!)
        let snapshot = try #require(engine.state.hubSnapshot(airport: "MET", catalog: engine.catalog, layout: layout))
        let stats = engine.state.routes[route]!.stats
        #expect(stats.flightsCompleted > 0)
        let expected = 1 - Double(stats.flightsDelayed) / Double(stats.flightsCompleted)
        #expect(abs((snapshot.kpis.onTimeRate ?? -1) - expected) < 1e-9)
        #expect(snapshot.kpis.loadFactor != nil)
        #expect(snapshot.kpis.averageTurnaroundMinutes > 0)
        #expect(snapshot.kpis.slotUse > 0)
    }

    @Test func insightsReadTheRoutesSlotsAndMoney() throws {
        let (engine, airline, route) = try DemandFixtures.market(fare: Money.dollars(129))
        engine.advance(ticks: Fixtures.ticksPerDay * 3)
        let layout = HubLayout.make(airport: engine.catalog.airport("MET")!)
        let snapshot = try #require(engine.state.hubSnapshot(airport: "MET", catalog: engine.catalog, layout: layout))
        let insights = snapshot.insights
        let link = try #require(insights.routes.first { $0.routeID == route })
        #expect(link.bearing >= 0 && link.bearing < 360)
        #expect(link.dailyRoundTrips == engine.state.routes[route]!.dailyRoundTrips)
        #expect(link.loadFactor != nil)
        #expect(insights.carriers.first?.isPlayer == true)
        #expect(insights.carriers.first?.slots == engine.state.world.slotsHeld(by: airline, at: "MET"))
        #expect(insights.carriers.reduce(0) { $0 + $1.slots } == insights.slotsUsed)
        #expect(insights.movementsByHour.count == 24)
        #expect(insights.cashCents == engine.state.ledger.balance(of: airline).cents)
        #expect(insights.routesTotal >= insights.routes.count)
        #expect((0...1).contains(insights.reputation))
        // A player occupant carries its route for the inspector.
        if let mine = snapshot.occupants.first(where: { $0.operatorKind == .player }) {
            #expect(mine.routeID != nil)
        }
    }

    @Test func networkListsHomeFirstThenTheBusiestAirports() throws {
        let (engine, airline, route) = try DemandFixtures.market(fare: Money.dollars(129))
        let layout = HubLayout.make(airport: engine.catalog.airport("MET")!)
        let snapshot = try #require(engine.state.hubSnapshot(airport: "MET", catalog: engine.catalog, layout: layout))
        let network = snapshot.insights.network
        let home = try #require(engine.state.airlines[airline]?.homeAirport)
        #expect(network.first?.code == home)
        #expect(network.first?.isHome == true)
        let r = try #require(engine.state.routes[route])
        for end in [r.origin, r.destination] {
            #expect(network.contains { $0.code == end && $0.routes >= 1 })
        }
        #expect(Set(network.map(\.code)).count == network.count)
    }

    @Test func searchFindsGatesFlightsRoutesAndPlaces() throws {
        let (engine, _, route) = try DemandFixtures.market(fare: Money.dollars(129))
        engine.advance(ticks: Fixtures.ticksPerDay)
        let layout = HubLayout.make(airport: engine.catalog.airport("MET")!)
        let snapshot = try #require(engine.state.hubSnapshot(airport: "MET", catalog: engine.catalog, layout: layout))
        #expect(snapshot.search("   ", layout: layout).isEmpty)
        // A gate number comes back as that gate, first.
        let gate = layout.stands[0].gate
        let byNumber = snapshot.search("\(gate)", layout: layout)
        #expect(byNumber.first?.target == .stand(0))
        #expect(byNumber.first?.kind == .gate)
        // Places, case-insensitively.
        #expect(snapshot.search("SECURITY", layout: layout).first?.target == .shot(.terminal))
        #expect(snapshot.search("maint", layout: layout).first?.target == .shot(.district))
        // The route by its far end's code.
        let link = try #require(snapshot.insights.routes.first { $0.routeID == route })
        #expect(snapshot.search(link.other.raw, layout: layout).contains { $0.target == .route(route) })
        // Every result once, and never more than asked for.
        let many = snapshot.search("a", layout: layout, limit: 5)
        #expect(many.count <= 5)
        #expect(Set(many.map(\.id)).count == many.count)
    }

    @Test func upgradeOffersQuoteTheNextLevelAndTheCommandAgrees() throws {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        let layout = HubLayout.make(airport: engine.catalog.airport("MET")!)
        let snapshot = try #require(engine.state.hubSnapshot(airport: "MET", catalog: engine.catalog, layout: layout))
        #expect(snapshot.upgrades.map(\.kind) == HubFacilityKind.allCases)
        let tuning = engine.catalog.tuning.airportServices
        let lounge = try #require(snapshot.upgrades.first { $0.kind == .lounge })
        let installed = engine.state.airlines[airline]!.facilities(at: "MET")
        #expect(lounge.level == installed.lounge)
        let next = try #require(lounge.next)
        #expect(next.level == lounge.level + 1)
        let proposed = AirportService.lounge.setting(next.level, in: installed)
        #expect(next.installationCents == proposed.installationCost(from: installed, tuning: tuning).cents)
        // The card's verdict is the command's.
        let command = ConfigureAirportFacilitiesCommand(airline: airline, airport: "MET", facilities: proposed)
        #expect((lounge.blocked == nil) == (command.validate(state: engine.state, catalog: engine.catalog) == nil))

        // Bought, the offer moves up a level; at the top there is no next.
        var state = engine.state
        let top = AirportFacilities(lounge: 2, groundServices: 2, hangar: 2, crewBase: 1)
        var owner = state.airlines[airline]!
        owner.airportFacilities = ["MET": top]
        state.airlines[airline] = owner
        let maxed = state.hubUpgradeOffers(airport: "MET", catalog: engine.catalog)
        #expect(maxed.allSatisfy { $0.level == $0.maxLevel && $0.next == nil && !$0.canUpgrade })
        #expect(maxed.allSatisfy { $0.monthlyCents > 0 })
    }

    @Test func upgradeOffersExplainWhyTheyAreBlocked() throws {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        // No cash: every next level is refused, with the command's reason.
        var state = engine.state
        let balance = state.ledger.balance(of: airline)
        state.ledger.post(airline: airline, category: .overhead, amount: .zero - balance - Money.dollars(1),
                          at: state.clock.now, memo: "test")
        let offers = state.hubUpgradeOffers(airport: "MET", catalog: engine.catalog)
        #expect(!offers.isEmpty)
        for offer in offers where offer.next != nil {
            #expect(!offer.canUpgrade)
            // A building of a later era says so before it talks money.
            let reason = offer.isLocked ? "era" : "cash"
            #expect(offer.blocked?.contains(reason) == true, "\(offer.kind): \(offer.blocked ?? "nil")")
        }
    }

    @Test func holdingAStageRewritesOnlyThatStand() throws {
        let catalog = try ContentCatalog.loadBundled()
        var state = Fixtures.newState()
        let spec = catalog.airport("LHR")!
        let layout = HubLayout.make(airport: spec)
        _ = state.world.allocateSlots(airline: AirlineID(raw: 99), airport: "LHR",
                                      count: 200, capacityPerDay: spec.slotCapacityPerDay)
        let snapshot = try #require(state.hubSnapshot(airport: "LHR", catalog: catalog, layout: layout))
        let first = try #require(snapshot.occupants.first)
        let held = snapshot.holding(.boarding, progress: 0.4, atStand: first.standIndex)
        #expect(held.occupant(atStand: first.standIndex)?.stage == .boarding)
        #expect(held.occupant(atStand: first.standIndex)?.stageProgress == 0.4)
        #expect(Array(held.occupants.dropFirst()) == Array(snapshot.occupants.dropFirst()))
        #expect(held.kpis == snapshot.kpis)
        #expect(held.focusStand == snapshot.focusStand)
    }

    @Test func busierAirportsFillMoreStands() throws {
        let catalog = try ContentCatalog.loadBundled()
        let state = Fixtures.newState()
        let spec = catalog.airport("LHR")!
        let layout = HubLayout.make(airport: spec)
        let quiet = try #require(state.hubSnapshot(airport: "LHR", catalog: catalog, layout: layout))
        var busy = state
        _ = busy.world.allocateSlots(airline: AirlineID(raw: 99), airport: "LHR",
                                     count: spec.slotCapacityPerDay - 10, capacityPerDay: spec.slotCapacityPerDay)
        let full = try #require(busy.hubSnapshot(airport: "LHR", catalog: catalog, layout: layout))
        #expect(full.occupants.count > quiet.occupants.count)
        #expect(full.occupants.allSatisfy { $0.operatorKind == .traffic })
        #expect(full.movementsPerHour > quiet.movementsPerHour)
    }
}
