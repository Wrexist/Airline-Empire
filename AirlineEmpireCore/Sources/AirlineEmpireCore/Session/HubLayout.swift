import Foundation

// The 3D hub's ground plan (docs/HUB_VIEW_3D.md §5–6).
//
// A deterministic function of the airport's static spec: the same airport
// always produces the same plan, on every device and in every test. The app
// turns each piece into geometry; nothing here knows about RealityKit, so
// the whole plan is testable on Linux.
//
// Frame: metres, x east, z south (towards the default camera), y up. The
// terminal's airside face sits on z = 0; airside is negative z, landside
// positive z. Yaw is radians about +y, 0 = local +x along world +x.

/// A point or extent in hub space.
public struct HubVec: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = HubVec(0, 0, 0)

    public static func + (a: HubVec, b: HubVec) -> HubVec { HubVec(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: HubVec, b: HubVec) -> HubVec { HubVec(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: HubVec, s: Double) -> HubVec { HubVec(a.x * s, a.y * s, a.z * s) }

    public var groundLength: Double { (x * x + z * z).squareRoot() }

    /// Yaw that points local +x along this vector on the ground plane.
    public var groundYaw: Double { atan2(-z, x) }

    public func distance(to other: HubVec) -> Double { (self - other).groundLength }
}

/// Every kind of thing the hub is built from. The raw value names the
/// procedural builder in the app and the optional authored replacement
/// (`HubAssetSlot` in the app).
public enum HubPieceKind: String, CaseIterable, Codable, Sendable {
    // Ground
    case apron, runway, taxiway, road, sidewalk, crosswalk, parking, lawn, plaza
    // Airside
    case terminalHall, pier, jetBridge, gateSign, controlTower, hangar, cargoShed, fuelTank
    case standMarking, blastFence
    // Landside
    case officeBlock, house, gardenWall, pool, tree, lampPost, parkedCar
    // Terminal interior (cutaway only)
    case floorSlab, mezzanine, checkInDesk, kiosk, securityLane, queueBarrier
    case shopShelf, seatRow, flightBoard, escalator, loungeBlock
    case shopFront, gondola, cafeCounter, metalDetector, luggageTrolley, electricCart, wayfindingSign
}

/// One placed piece: an oriented box footprint with a height, plus a variant
/// number the builder may use for colour or style. `center.y` is the base.
public struct HubPiece: Equatable, Codable, Sendable {
    public let kind: HubPieceKind
    public let center: HubVec
    /// Extent along local x (width), y (height) and local z (depth).
    public let size: HubVec
    public let yaw: Double
    public let variant: Int
    /// Text a builder may paint on the piece (gate numbers, shop names).
    public let label: String?

    public init(_ kind: HubPieceKind, center: HubVec, size: HubVec, yaw: Double = 0,
                variant: Int = 0, label: String? = nil) {
        self.kind = kind
        self.center = center
        self.size = size
        self.yaw = yaw
        self.variant = variant
        self.label = label
    }

    /// Axis-aligned ground bounds of the (possibly rotated) footprint.
    public var groundBounds: HubRect {
        let c = cos(yaw), s = sin(yaw)
        let hx = abs(c) * size.x / 2 + abs(s) * size.z / 2
        let hz = abs(s) * size.x / 2 + abs(c) * size.z / 2
        return HubRect(minX: center.x - hx, minZ: center.z - hz, maxX: center.x + hx, maxZ: center.z + hz)
    }
}

public struct HubRect: Equatable, Codable, Sendable {
    public var minX: Double
    public var minZ: Double
    public var maxX: Double
    public var maxZ: Double

    public init(minX: Double, minZ: Double, maxX: Double, maxZ: Double) {
        self.minX = minX
        self.minZ = minZ
        self.maxX = maxX
        self.maxZ = maxZ
    }

    public var width: Double { maxX - minX }
    public var depth: Double { maxZ - minZ }
    public var center: HubVec { HubVec((minX + maxX) / 2, 0, (minZ + maxZ) / 2) }

    public func contains(_ p: HubVec) -> Bool {
        p.x >= minX && p.x <= maxX && p.z >= minZ && p.z <= maxZ
    }

    /// Strict overlap (shared edges do not count).
    public func overlaps(_ o: HubRect, margin: Double = 0) -> Bool {
        minX + margin < o.maxX && o.minX + margin < maxX &&
            minZ + margin < o.maxZ && o.minZ + margin < maxZ
    }

    public func union(_ o: HubRect) -> HubRect {
        HubRect(minX: min(minX, o.minX), minZ: min(minZ, o.minZ),
                maxX: max(maxX, o.maxX), maxZ: max(maxZ, o.maxZ))
    }
}

/// A polyline on the ground, parameterised by distance.
public struct HubPath: Equatable, Codable, Sendable {
    public let points: [HubVec]

    public init(_ points: [HubVec]) {
        self.points = points
    }

    public var length: Double {
        zip(points, points.dropFirst()).reduce(0) { total, pair in
            let d = pair.1 - pair.0
            return total + (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
        }
    }

    /// Position and heading yaw at `distance` metres along the path, clamped
    /// to its ends.
    public func sample(at distance: Double) -> (position: HubVec, yaw: Double) {
        guard points.count > 1 else { return (points.first ?? .zero, 0) }
        var remaining = max(0, distance)
        for (a, b) in zip(points, points.dropFirst()) {
            let segment = (b - a)
            let len = (segment.groundLength * segment.groundLength + segment.y * segment.y).squareRoot()
            if remaining <= len || b == points.last! {
                let t = len == 0 ? 0 : min(1, remaining / len)
                return (a + segment * t, segment.groundLength == 0 ? 0 : segment.groundYaw)
            }
            remaining -= len
        }
        let a = points[points.count - 2], b = points[points.count - 1]
        return (b, (b - a).groundYaw)
    }

    public func sample(fraction: Double) -> (position: HubVec, yaw: Double) {
        sample(at: length * min(1, max(0, fraction)))
    }
}

/// A runway: centreline from `thresholdA` to `thresholdB`.
public struct HubRunway: Equatable, Codable, Sendable {
    public let thresholdA: HubVec
    public let thresholdB: HubVec
    public let width: Double

    public var length: Double { thresholdA.distance(to: thresholdB) }
}

/// An aircraft stand: where a jet parks, how it gets in and out.
public struct HubStand: Equatable, Codable, Sendable {
    public let index: Int
    /// Gate number shown on the sign board ("14").
    public let gate: Int
    /// Nose-wheel stop position.
    public let nose: HubVec
    /// Yaw the aircraft faces when parked (towards the building).
    public let heading: Double
    /// Largest category the stand accepts.
    public let maxCategory: AircraftCategory
    /// Jet bridge (true) or remote stand with stairs and bus (false).
    public let hasBridge: Bool
    /// Where the bridge leaves the pier wall.
    public let bridgeRoot: HubVec
    /// Departure: pushback, taxi, line-up, take-off roll, climb-out.
    public let departure: HubPath
    /// Arrival: approach, touchdown, roll-out, taxi in to the nose stop.
    public let arrival: HubPath
    /// Where boarding passengers queue (walkway alongside the pier).
    public let queue: HubPath
    /// Corners of the painted safety envelope, closed.
    public let safetyOutline: [HubVec]
    /// Where ground vehicles park during a turnaround.
    public let servicePoints: [HubVec]
}

/// The doll's-house interior revealed by the terminal cutaway.
public struct HubTerminalInterior: Equatable, Codable, Sendable {
    public let bounds: HubRect
    public let pieces: [HubPiece]
    /// Where queues pool (the heatmap's seeds), with relative weight 0…1.
    public let hotspots: [(position: HubVec, weight: Double)]

    public static func == (a: Self, b: Self) -> Bool {
        a.bounds == b.bounds && a.pieces == b.pieces &&
            a.hotspots.map(\.position) == b.hotspots.map(\.position) &&
            a.hotspots.map(\.weight) == b.hotspots.map(\.weight)
    }

    enum CodingKeys: String, CodingKey { case bounds, pieces, hotspotPositions, hotspotWeights }

    public init(bounds: HubRect, pieces: [HubPiece], hotspots: [(position: HubVec, weight: Double)]) {
        self.bounds = bounds
        self.pieces = pieces
        self.hotspots = hotspots
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bounds = try c.decode(HubRect.self, forKey: .bounds)
        pieces = try c.decode([HubPiece].self, forKey: .pieces)
        let p = try c.decode([HubVec].self, forKey: .hotspotPositions)
        let w = try c.decode([Double].self, forKey: .hotspotWeights)
        hotspots = Array(zip(p, w)).map { (position: $0.0, weight: $0.1) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bounds, forKey: .bounds)
        try c.encode(pieces, forKey: .pieces)
        try c.encode(hotspots.map(\.position), forKey: .hotspotPositions)
        try c.encode(hotspots.map(\.weight), forKey: .hotspotWeights)
    }
}

/// Named camera targets for the dashboard's shots.
public struct HubFocusPoints: Equatable, Codable, Sendable {
    public let overview: HubVec
    public let terminal: HubVec
    public let district: HubVec
    public let hangars: HubVec
}

public struct HubLayout: Equatable, Codable, Sendable {
    public let airport: AirportCode
    public let runwayClass: RunwayClass
    /// Everything the hub is built from, airside and landside.
    public let pieces: [HubPiece]
    public let runways: [HubRunway]
    public let stands: [HubStand]
    public let terminal: HubRect
    public let interior: HubTerminalInterior
    /// The landside service route drawn as a glowing line (shot D).
    public let serviceRoute: HubPath
    /// Landmarks along the service route that carry pins.
    public let serviceStops: [HubVec]
    public let focus: HubFocusPoints
    /// Union of every footprint.
    public let bounds: HubRect

    public func pieces(_ kind: HubPieceKind) -> [HubPiece] { pieces.filter { $0.kind == kind } }
}

// MARK: - Generation

/// Footprint, in metres, the stand planner reserves per category.
public enum HubAircraftEnvelope {
    public static func length(_ category: AircraftCategory) -> Double {
        switch category {
        case .turboprop: 27
        case .regionalJet: 33
        case .narrowbody: 38
        case .largeNarrowbody: 45
        case .widebody: 60
        case .largeWidebody: 70
        }
    }

    public static func span(_ category: AircraftCategory) -> Double {
        switch category {
        case .turboprop: 27
        case .regionalJet: 28
        case .narrowbody: 35
        case .largeNarrowbody: 36
        case .widebody: 60
        case .largeWidebody: 65
        }
    }

    public static func engines(_ category: AircraftCategory) -> Int {
        category == .largeWidebody ? 4 : 2
    }
}

extension HubLayout {
    /// Stands an airport of this size gets: 4 for a field of a few dozen
    /// movements, 18 for the largest hubs.
    public static func standCount(slotCapacityPerDay slots: Int) -> Int {
        min(18, max(4, Int((4 + Double(slots) / 90).rounded())))
    }

    public static func make(airport spec: AirportSpec,
                            facilities: AirportFacilities = AirportFacilities()) -> HubLayout {
        var planner = HubPlanner(spec: spec, facilities: facilities)
        return planner.build().withTaxiRoutes()
    }
}

/// splitmix64, seeded from the airport code: deterministic jitter for trees,
/// cars and building heights without touching the game's RNG streams.
struct HubJitter {
    private var state: UInt64

    init(_ label: String) {
        state = StableHash.fnv1a("hub.layout." + label)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }

    mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
}

struct HubPlanner {
    let spec: AirportSpec
    let facilities: AirportFacilities
    var jitter: HubJitter
    var pieces: [HubPiece] = []

    init(spec: AirportSpec, facilities: AirportFacilities) {
        self.spec = spec
        self.facilities = facilities
        self.jitter = HubJitter(spec.code.raw)
    }

    // Size parameters ---------------------------------------------------

    var standCount: Int { HubLayout.standCount(slotCapacityPerDay: spec.slotCapacityPerDay) }

    var largestCategory: AircraftCategory {
        switch spec.runwayClass {
        case .small: .turboprop
        case .medium: .regionalJet
        case .large: .largeNarrowbody
        case .veryLarge: .largeWidebody
        }
    }

    var pierCount: Int {
        switch spec.runwayClass {
        case .small: 0
        case .medium: 1
        case .large: 2
        case .veryLarge: standCount > 14 ? 3 : 2
        }
    }

    var runwayCount: Int {
        switch spec.runwayClass {
        case .small, .medium: 1
        case .large: spec.slotCapacityPerDay >= 600 ? 2 : 1
        case .veryLarge: 2
        }
    }

    /// Diorama-compressed runway length (about half the real one).
    var runwayLength: Double {
        switch spec.runwayClass {
        case .small: 800
        case .medium: 1_100
        case .large: 1_400
        case .veryLarge: 1_700
        }
    }

    var runwayWidth: Double { spec.runwayClass >= .large ? 45 : 32 }

    var terminalLength: Double {
        let byCapacity = 120 + Double(spec.terminalCapacityPerDay) / 1_000 * 1.0
        // Never shorter than the piers it feeds.
        let piers = Double(max(0, pierCount - 1)) * pierSpacing + pierWidth + 40
        return min(520, max(130, byCapacity, piers))
    }

    var pierSpacing: Double { 2 * standDepth + pierWidth + 56 }

    let terminalDepth: Double = 58
    let pierWidth: Double = 26

    var standPitch: Double { HubAircraftEnvelope.span(largestCategory) + 14 }
    var standDepth: Double { HubAircraftEnvelope.length(largestCategory) + 16 }

    // Build ---------------------------------------------------------------

    mutating func build() -> HubLayout {
        let L = terminalLength
        // Terminal: airside face on z = 0.
        let terminal = HubRect(minX: -L / 2, minZ: 0, maxX: L / 2, maxZ: terminalDepth)
        add(.terminalHall, terminal, height: 19, label: spec.city)

        let stands = planStands(terminal: terminal)
        let apronNorth = (stands.map(\.nose.z).min() ?? -60) - standDepth - 70
        let apronHalf = max(L / 2 + 30,
                            (stands.map { abs($0.nose.x) }.max() ?? 0) + standDepth + 45)
        let apron = HubRect(minX: -apronHalf, minZ: apronNorth, maxX: apronHalf, maxZ: 0)
        add(.apron, apron, height: 0.06)

        // Taxiway and runways north of the apron.
        let taxiZ = apronNorth - 45
        let runwayHalf = max(runwayLength / 2, apronHalf + 260)
        add(.taxiway, HubRect(minX: -runwayHalf, minZ: taxiZ - 12, maxX: runwayHalf, maxZ: taxiZ + 12), height: 0.07)
        var runways: [HubRunway] = []
        for i in 0..<runwayCount {
            let z = taxiZ - 130 - Double(i) * 230
            runways.append(HubRunway(thresholdA: HubVec(-runwayHalf, 0, z),
                                     thresholdB: HubVec(runwayHalf, 0, z), width: runwayWidth))
            add(.runway, HubRect(minX: -runwayHalf, minZ: z - runwayWidth / 2,
                                 maxX: runwayHalf, maxZ: z + runwayWidth / 2), height: 0.08, variant: i)
            // Connectors between taxiway and each runway at both ends and the middle.
            for x in [-runwayHalf + 60, 0, runwayHalf - 60] {
                let from = taxiZ, to = z
                add(.taxiway, HubRect(minX: x - 11, minZ: min(from, to), maxX: x + 11, maxZ: max(from, to)),
                    height: 0.07, variant: 1)
            }
        }

        // Stand markings, signs, bridges.
        for stand in stands {
            let away = HubVec(cos(stand.heading + .pi), 0, -sin(stand.heading + .pi))
            let markingCenter = stand.nose + away * (standDepth / 2)
            pieces.append(HubPiece(.standMarking, center: markingCenter,
                                   size: HubVec(standDepth, 0.02, standPitch - 6),
                                   yaw: stand.heading + .pi, label: "\(stand.gate)"))
            if stand.hasBridge {
                let left = HubVec(cos(stand.heading + .pi / 2), 0, -sin(stand.heading + .pi / 2))
                let tip = stand.nose + away * 7 + left * 3
                let span = tip - stand.bridgeRoot
                pieces.append(HubPiece(.jetBridge, center: stand.bridgeRoot + span * 0.5,
                                       size: HubVec(span.groundLength, 5, 3.6), yaw: span.groundYaw,
                                       variant: stand.index, label: "\(stand.gate)"))
                pieces.append(HubPiece(.gateSign, center: stand.bridgeRoot + HubVec(0, 9, 0),
                                       size: HubVec(6, 3, 0.4), yaw: stand.heading + .pi / 2,
                                       label: "Gate \(stand.gate)"))
            }
        }

        // Hangars east of the apron, cargo west, tower beside the terminal.
        let hangarW: Double = spec.runwayClass >= .large ? 95 : 70
        for i in 0..<(spec.runwayClass >= .large ? 2 : 1) {
            let x = apronHalf + 70 + Double(i) * (hangarW + 18)
            let z = apronNorth + 70
            add(.hangar, HubRect(minX: x - hangarW / 2, minZ: z - 40, maxX: x + hangarW / 2, maxZ: z + 40),
                height: 30, variant: i)
            add(.apron, HubRect(minX: x - hangarW / 2 - 6, minZ: z - 80, maxX: x + hangarW / 2 + 6, maxZ: z - 40),
                height: 0.06, variant: 1)
        }
        if spec.runwayClass >= .medium {
            for i in 0..<2 {
                let x = -apronHalf - 70
                let z = apronNorth + 60 + Double(i) * 70
                add(.cargoShed, HubRect(minX: x - 45, minZ: z - 25, maxX: x + 45, maxZ: z + 25), height: 14, variant: i)
            }
        }
        let tower = HubVec(-L / 2 - 45, 0, 34)
        pieces.append(HubPiece(.controlTower, center: tower, size: HubVec(16, spec.runwayClass >= .large ? 72 : 46, 16)))
        add(.blastFence, HubRect(minX: -runwayHalf + 10, minZ: taxiZ + 18, maxX: -runwayHalf + 70, maxZ: taxiZ + 20),
            height: 4)

        // Landside: kerb road, parking, avenue, streets, blocks, district.
        let kerbZ = terminalDepth + 16
        add(.road, HubRect(minX: -L / 2 - 30, minZ: kerbZ - 10, maxX: L / 2 + 30, maxZ: kerbZ + 10), height: 0.07)
        add(.sidewalk, HubRect(minX: -L / 2, minZ: terminalDepth, maxX: L / 2, maxZ: kerbZ - 10), height: 0.18)
        let parkingZ0 = kerbZ + 22, parkingZ1 = kerbZ + 120
        for side in [-1.0, 1.0] {
            let r = HubRect(minX: side < 0 ? -L / 2 : 12, minZ: parkingZ0,
                            maxX: side < 0 ? -12 : L / 2, maxZ: parkingZ1)
            add(.parking, r, height: 0.07)
            // Rows of cars with a little jitter.
            var x = r.minX + 6
            while x < r.maxX - 6 {
                for row in [r.minZ + 12, r.minZ + 30, r.maxZ - 30, r.maxZ - 12] where jitter.unit() < 0.62 {
                    pieces.append(HubPiece(.parkedCar, center: HubVec(x, 0, row), size: HubVec(2, 1.5, 4.6),
                                           variant: jitter.int(6)))
                }
                x += 3.4
            }
            // Island trees.
            pieces.append(HubPiece(.lawn, center: HubVec(r.center.x, 0, (r.minZ + r.maxZ) / 2),
                                   size: HubVec(r.width - 20, 0.25, 6)))
            var tx = r.minX + 18
            while tx < r.maxX - 10 {
                tree(at: HubVec(tx, 0, (r.minZ + r.maxZ) / 2), scale: jitter.range(0.85, 1.15))
                tx += 26
            }
        }
        let avenueZ = parkingZ1 + 40
        let landsideHalf = runwayHalf + 200
        road(HubRect(minX: -landsideHalf, minZ: avenueZ - 13, maxX: landsideHalf, maxZ: avenueZ + 13))
        // Connector from the kerb loop to the avenue at both ends of the terminal.
        let streetXs = [-L / 2 - 60, L / 2 + 60, -L / 2 - 330, L / 2 + 330]
        for x in streetXs {
            let fromZ = abs(x) < L / 2 + 100 ? kerbZ - 10 : avenueZ
            road(HubRect(minX: x - 11, minZ: fromZ, maxX: x + 11, maxZ: avenueZ + 640))
            crosswalk(at: HubVec(x, 0, avenueZ - 20), alongX: true)
            crosswalk(at: HubVec(x, 0, avenueZ + 20), alongX: true)
            crosswalk(at: HubVec(x - 19, 0, avenueZ), alongX: false)
            crosswalk(at: HubVec(x + 19, 0, avenueZ), alongX: false)
        }
        road(HubRect(minX: -landsideHalf, minZ: avenueZ + 300, maxX: landsideHalf, maxZ: avenueZ + 322))
        // Avenue trees and lamps.
        var ax = -landsideHalf + 20
        while ax < landsideHalf {
            if !streetXs.contains(where: { abs($0 - ax) < 30 }) {
                for side in [-1.0, 1.0] {
                    tree(at: HubVec(ax + jitter.range(-3, 3), 0, avenueZ + side * 20), scale: jitter.range(0.8, 1.1))
                }
            }
            if Int((ax + landsideHalf) / 34) % 2 == 0 {
                pieces.append(HubPiece(.lampPost, center: HubVec(ax, 0, avenueZ - 15), size: HubVec(0.5, 9, 0.5)))
            }
            ax += 34
        }
        // West blocks: offices between the outer streets, beyond the avenue.
        for (x0, x1) in [(-landsideHalf, -L / 2 - 341), (-L / 2 - 319, -L / 2 - 71)] where x1 - x0 > 60 {
            officeRow(x0: x0 + 14, x1: x1 - 14, z0: avenueZ + 26, z1: avenueZ + 288)
        }
        // The district east of the airport (shot D): houses in walled gardens.
        let district = HubRect(minX: L / 2 + 71, minZ: avenueZ + 26, maxX: L / 2 + 319, maxZ: avenueZ + 288)
        let serviceStops = houses(in: district)
        officeRow(x0: L / 2 + 341 + 14, x1: landsideHalf - 14, z0: avenueZ + 26, z1: avenueZ + 288)
        // A band of offices south of the second street too, to fill the frame.
        officeRow(x0: -landsideHalf + 14, x1: landsideHalf - 14, z0: avenueZ + 336, z1: avenueZ + 600,
                  skipping: streetXs)
        // Lawns and tree clumps around the airfield edge.
        for _ in 0..<(18 + standCount) {
            let x = jitter.range(-runwayHalf, runwayHalf)
            let z = jitter.range(runways.last!.thresholdA.z - 160, runways.last!.thresholdA.z - 60)
            tree(at: HubVec(x, 0, z), scale: jitter.range(0.9, 1.4))
        }
        for side in [-1.0, 1.0] {
            let x = side * (L / 2 + 105)
            pieces.append(HubPiece(.lawn, center: HubVec(x, 0, 40), size: HubVec(60, 0.25, 70)))
            for _ in 0..<5 {
                tree(at: HubVec(x + jitter.range(-24, 24), 0, 40 + jitter.range(-28, 28)), scale: jitter.range(0.9, 1.3))
            }
        }
        // Fuel farm on the landside east edge.
        for i in 0..<3 {
            pieces.append(HubPiece(.fuelTank, center: HubVec(apronHalf + 80 + Double(i) * 34, 0, kerbZ + 40),
                                   size: HubVec(26, 14, 26), variant: i))
        }

        // The service route: from the fuel farm gate along the avenue into the district.
        let gate = HubVec(apronHalf + 80, 0, avenueZ)
        let east = L / 2 + 60
        let route = HubPath([
            HubVec(-L / 2 - 60, 0.4, kerbZ),
            HubVec(-L / 2 - 60, 0.4, avenueZ),
            HubVec(east, 0.4, avenueZ),
            HubVec(east, 0.4, district.minZ + 100),
            serviceStops.first.map { HubVec($0.x, 0.4, district.minZ + 100) } ?? gate,
        ] + serviceStops.map { HubVec($0.x, 0.4, $0.z) })

        let interior = planInterior(terminal: terminal)
        let bounds = pieces.map(\.groundBounds).reduce(terminal) { $0.union($1) }
        return HubLayout(
            airport: spec.code, runwayClass: spec.runwayClass, pieces: pieces, runways: runways,
            stands: stands, terminal: terminal, interior: interior, serviceRoute: route,
            serviceStops: serviceStops,
            focus: HubFocusPoints(overview: HubVec(0, 0, apronNorth / 2),
                                  terminal: HubVec(0, 0, terminalDepth / 2),
                                  district: district.center,
                                  hangars: HubVec(apronHalf + 70, 0, apronNorth + 70)),
            bounds: bounds)
    }

    // Stands ---------------------------------------------------------------

    mutating func planStands(terminal: HubRect) -> [HubStand] {
        let n = standCount
        var result: [HubStand] = []
        var gate = 1
        // Runway geometry is not planned yet; departures are completed by
        // `routeStands` once the apron edge is known.
        let piers = pierCount
        var perPierSide: Int {
            piers == 0 ? 0 : Int((Double(n) / Double(piers * 2)).rounded(.up))
        }
        let pierLength = Double(max(1, perPierSide)) * standPitch + 30
        var placed = 0
        for p in 0..<piers {
            let px = (Double(p) - Double(piers - 1) / 2) * pierSpacing
            let pier = HubRect(minX: px - pierWidth / 2, minZ: -pierLength, maxX: px + pierWidth / 2, maxZ: 0)
            add(.pier, pier, height: 12, variant: p)
            for side in [-1.0, 1.0] {
                for j in 0..<perPierSide where placed < n {
                    let z = -24 - Double(j) * standPitch - standPitch / 2 + 10
                    let nose = HubVec(px + side * (pierWidth / 2 + 7), 0, z)
                    // Nose points back at the pier: towards -side on x.
                    let heading = side > 0 ? Double.pi : 0
                    let root = HubVec(px + side * pierWidth / 2, 0, z - 4)
                    result.append(stand(index: placed, gate: gate, nose: nose, heading: heading,
                                        bridge: true, root: root))
                    placed += 1
                    gate += 1
                }
            }
        }
        // Whatever the piers could not take: nose-in stands along the
        // terminal's airside face (with bridges), then remote stands.
        var faceX = -terminal.width / 2 + standPitch / 2 + 10
        while placed < n && faceX < terminal.width / 2 - standPitch / 2 {
            if piers > 0 && result.contains(where: { abs($0.nose.x - faceX) < standDepth + pierWidth }) {
                faceX += standPitch
                continue
            }
            let nose = HubVec(faceX, 0, -7)
            result.append(stand(index: placed, gate: gate, nose: nose, heading: -.pi / 2,
                                bridge: spec.runwayClass >= .medium, root: HubVec(faceX - 4, 0, 0)))
            placed += 1
            gate += 1
            faceX += standPitch
        }
        var remote = 0
        while placed < n {
            let x = -terminal.width / 2 - 60 - Double(remote) * standPitch
            let nose = HubVec(x, 0, -30)
            result.append(stand(index: placed, gate: gate, nose: nose, heading: -.pi / 2,
                                bridge: false, root: nose))
            placed += 1
            gate += 1
            remote += 1
        }
        return result
    }

    func stand(index: Int, gate: Int, nose: HubVec, heading: Double, bridge: Bool, root: HubVec) -> HubStand {
        // Unit vectors: forward = the way the parked jet faces.
        let fwd = HubVec(cos(heading), 0, -sin(heading))
        let right = HubVec(cos(heading - .pi / 2), 0, -sin(heading - .pi / 2))
        let tail = nose - fwd * standDepth
        let halfW = (standPitch - 8) / 2
        let outline = [nose + fwd * 4 + right * halfW, nose + fwd * 4 - right * halfW,
                       tail - right * halfW, tail + right * halfW, nose + fwd * 4 + right * halfW]
        let len = HubAircraftEnvelope.length(largestCategory)
        let services = [
            nose - fwd * (len * 0.30) + right * 9,   // fuel truck by the wing root
            nose - fwd * 6 - right * 7,              // belt loader at the forward hold
            nose + fwd * 2 - right * 2,              // tug at the nose
            nose - fwd * (len * 0.75) - right * 7,   // catering at the rear door
            nose - fwd * (len * 0.55) - right * 10,  // baggage carts
        ]
        let queueStart = bridge ? root + HubVec(0, 0.3, 0) : nose - right * 14
        let queue = HubPath([queueStart, queueStart + HubVec(0, 0, 18), queueStart + HubVec(-fwd.x * 2, 0, 34)])
        // Departure and arrival are finished once the taxi network exists;
        // the stand alone knows the first and last legs.
        let push = tail - fwd * 30
        return HubStand(index: index, gate: gate, nose: nose, heading: heading, maxCategory: largestCategory,
                        hasBridge: bridge, bridgeRoot: root,
                        departure: HubPath([nose - fwd * (len / 2), push]),
                        arrival: HubPath([push, nose - fwd * (len / 2)]),
                        queue: queue, safetyOutline: outline, servicePoints: services)
    }

    // Landside helpers -----------------------------------------------------

    mutating func add(_ kind: HubPieceKind, _ r: HubRect, height: Double, variant: Int = 0, label: String? = nil) {
        pieces.append(HubPiece(kind, center: HubVec(r.center.x, 0, r.center.z),
                               size: HubVec(r.width, height, r.depth), variant: variant, label: label))
    }

    mutating func road(_ r: HubRect) {
        add(.road, r, height: 0.07)
    }

    mutating func crosswalk(at p: HubVec, alongX: Bool) {
        pieces.append(HubPiece(.crosswalk, center: p, size: HubVec(alongX ? 18 : 6, 0.02, alongX ? 6 : 18),
                               yaw: 0, variant: alongX ? 0 : 1))
    }

    mutating func tree(at p: HubVec, scale: Double) {
        pieces.append(HubPiece(.tree, center: p, size: HubVec(8 * scale, 11 * scale, 8 * scale),
                               variant: jitter.int(3)))
    }

    mutating func officeRow(x0: Double, x1: Double, z0: Double, z1: Double, skipping: [Double] = []) {
        var x = x0
        while x < x1 - 30 {
            let w = jitter.range(42, 70)
            let d = min(z1 - z0 - 20, jitter.range(40, 70))
            let cx = x + w / 2
            if skipping.contains(where: { abs($0 - cx) < w / 2 + 16 }) {
                x += 40
                continue
            }
            let z = z0 + 10 + d / 2 + jitter.range(0, max(0, z1 - z0 - 20 - d))
            let floors = 2 + jitter.int(6)
            pieces.append(HubPiece(.officeBlock, center: HubVec(cx, 0, z), size: HubVec(w, Double(floors) * 4.2, d),
                                   variant: floors))
            pieces.append(HubPiece(.lawn, center: HubVec(cx, 0, z), size: HubVec(w + 14, 0.2, d + 14)))
            if jitter.unit() < 0.7 { tree(at: HubVec(cx + w / 2 + 4, 0, z + d / 2 + 3), scale: 1) }
            x += w + jitter.range(16, 30)
        }
    }

    /// Lays out walled houses on a grid with streets between the lots, and
    /// returns the service-route stops.
    mutating func houses(in r: HubRect) -> [HubVec] {
        var stops: [HubVec] = []
        let lot: Double = 56
        let street: Double = 14
        let pitch = lot + street
        let cols = max(1, Int((r.width - street) / pitch))
        let rows = max(1, Int((r.depth - street) / pitch))
        let x0 = r.minX + (r.width - Double(cols) * pitch + street) / 2
        let z0 = r.minZ + (r.depth - Double(rows) * pitch + street) / 2
        // Streets between the lots.
        for c in 1..<max(2, cols) where c < cols {
            let x = x0 + Double(c) * pitch - street / 2
            road(HubRect(minX: x - street / 2 + 1, minZ: z0, maxX: x + street / 2 - 1, maxZ: z0 + Double(rows) * pitch - street))
        }
        for row in 1..<max(2, rows) where row < rows {
            let z = z0 + Double(row) * pitch - street / 2
            road(HubRect(minX: x0, minZ: z - street / 2 + 1, maxX: x0 + Double(cols) * pitch - street, maxZ: z + street / 2 - 1))
        }
        for row in 0..<rows {
            for col in 0..<cols {
                let center = HubVec(x0 + Double(col) * pitch + lot / 2, 0, z0 + Double(row) * pitch + lot / 2)
                pieces.append(HubPiece(.lawn, center: center, size: HubVec(lot, 0.3, lot)))
                pieces.append(HubPiece(.gardenWall, center: center, size: HubVec(lot - 2, 1.6, lot - 2)))
                let houseSize = HubVec(jitter.range(24, 30), 2 * 3.6, jitter.range(17, 21))
                pieces.append(HubPiece(.house, center: center + HubVec(-3, 0, -5), size: houseSize,
                                       variant: (row + col) % 3, label: nil))
                if (row + col) % 2 == 0 {
                    pieces.append(HubPiece(.pool, center: center + HubVec(13, 0, 16), size: HubVec(11, 0.3, 7)))
                }
                tree(at: center + HubVec(lot / 2 - 8, 0, lot / 2 - 8), scale: 1.1)
                tree(at: center + HubVec(-lot / 2 + 7, 0, lot / 2 - 7), scale: 0.9)
                tree(at: center + HubVec(-lot / 2 + 7, 0, -lot / 2 + 8), scale: 1)
                if stops.count < 3 && (row + col) % 2 == 0 { stops.append(center) }
            }
        }
        return stops
    }

    // Interior ---------------------------------------------------------------

    /// The cutaway hall (reference shot C), as repeating 70 m bays so a long
    /// terminal is as busy as the reference's short one. Each bay, back
    /// (airside, low z) to front (street, high z): a pharmacy under the
    /// mezzanine, the stair up to it, a row of e-gates under the departure
    /// board, a convenience store and café on the right, self-service kiosks
    /// with a queue maze at the front left, security arches, trolleys and
    /// carts. Bigger terminals get more bays, so more of everything.
    mutating func planInterior(terminal t: HubRect) -> HubTerminalInterior {
        var inside: [HubPiece] = []
        let floor = HubRect(minX: t.minX + 2, minZ: t.minZ + 2, maxX: t.maxX - 2, maxZ: t.maxZ - 2)
        inside.append(HubPiece(.floorSlab, center: HubVec(floor.center.x, 0, floor.center.z),
                               size: HubVec(floor.width, 0.4, floor.depth)))
        let mezzDepth = min(14, floor.depth * 0.26)
        inside.append(HubPiece(.mezzanine, center: HubVec(floor.center.x, 6, floor.minZ + mezzDepth / 2),
                               size: HubVec(floor.width, 0.6, mezzDepth)))
        let bayWidth: Double = 70
        let bays = max(1, Int(floor.width / bayWidth))
        let bayW = floor.width / Double(bays)
        // Kiosks scale with throughput: two rows per bay, 3–5 per row.
        let perRow = max(3, min(5, spec.terminalCapacityPerDay / (40_000 * bays) + 3))
        let back = floor.minZ, front = floor.maxZ
        let depth = floor.depth
        func z(_ fraction: Double) -> Double { back + depth * fraction }
        var hotspots: [(position: HubVec, weight: Double)] = []
        let shopNames = ["Nord Care", "Café", "Market"]
        for b in 0..<bays {
            let x0 = floor.minX + Double(b) * bayW
            func x(_ fraction: Double) -> Double { x0 + bayW * fraction }
            // Pharmacy under the mezzanine, back left.
            for i in 0..<3 {
                inside.append(HubPiece(.shopShelf, center: HubVec(x(0.06 + Double(i) * 0.075), 0, back + 1.2),
                                       size: HubVec(4.8, 2.4, 1.2), variant: i))
            }
            inside.append(HubPiece(.shopFront, center: HubVec(x(0.16), 0, back + mezzDepth - 0.5),
                                   size: HubVec(bayW * 0.25, 4.6, 0.6), label: shopNames[0]))
            inside.append(HubPiece(.cafeCounter, center: HubVec(x(0.2), 0, back + mezzDepth - 4),
                                   size: HubVec(5, 1.1, 1.2), variant: 1))
            // Stair up to the mezzanine.
            inside.append(HubPiece(.escalator, center: HubVec(x(0.43), 3, back + mezzDepth + 7),
                                   size: HubVec(4, 6, 14)))
            // E-gates in a row under the departure board.
            let gates = 6
            for g in 0..<gates {
                inside.append(HubPiece(.securityLane, center: HubVec(x(0.52) + Double(g) * 2.4, 0, z(0.36)),
                                       size: HubVec(1, 1.3, 2.6), variant: g))
            }
            inside.append(HubPiece(.flightBoard, center: HubVec(x(0.62), 8.4, back + 0.6),
                                   size: HubVec(12, 3.4, 0.4)))
            inside.append(HubPiece(.wayfindingSign, center: HubVec(x(0.43), 5.2, back + mezzDepth + 1.5),
                                   size: HubVec(4.5, 0.9, 0.2)))
            inside.append(HubPiece(.wayfindingSign, center: HubVec(x(0.6), 5.2, z(0.3)),
                                   size: HubVec(4.5, 0.9, 0.2), variant: 1))
            // Convenience store on the right: shelves on the back and side
            // walls, two island gondolas, café counter at the front.
            for i in 0..<3 {
                inside.append(HubPiece(.shopShelf, center: HubVec(x(0.8 + Double(i) * 0.065), 0, back + mezzDepth + 1.2),
                                       size: HubVec(4.2, 2.6, 1.2), variant: i + 3,
                                       label: i == 0 ? shopNames[2] : nil))
            }
            for i in 0..<3 {
                inside.append(HubPiece(.shopShelf, center: HubVec(x(0.975), 0, z(0.45 + Double(i) * 0.1)),
                                       size: HubVec(4.2, 2.6, 1.2), yaw: .pi / 2, variant: i + 6))
            }
            for i in 0..<2 {
                inside.append(HubPiece(.gondola, center: HubVec(x(0.82 + Double(i) * 0.07), 0, z(0.5)),
                                       size: HubVec(1.4, 1.4, 3.6), variant: i))
            }
            inside.append(HubPiece(.cafeCounter, center: HubVec(x(0.85), 0, z(0.72)),
                                   size: HubVec(7, 1.1, 1.3), label: shopNames[1]))
            // Kiosks at the front left, with their queue maze in front.
            for row in 0..<2 {
                for k in 0..<perRow {
                    inside.append(HubPiece(.kiosk, center: HubVec(x(0.1) + Double(k) * 4.2, 0, z(0.55 + Double(row) * 0.12)),
                                           size: HubVec(0.7, 1.7, 0.6), variant: k))
                }
            }
            inside.append(HubPiece(.queueBarrier, center: HubVec(x(0.2), 0, z(0.86)),
                                   size: HubVec(Double(perRow) * 4, 1, depth * 0.14)))
            // Security arches, trolleys and carts.
            for a in 0..<2 {
                inside.append(HubPiece(.metalDetector, center: HubVec(x(0.66) + Double(a) * 4, 0, z(0.6)),
                                       size: HubVec(1.4, 2.4, 1), variant: a))
            }
            for i in 0..<2 {
                inside.append(HubPiece(.luggageTrolley, center: HubVec(x(0.56) + Double(i) * 3, 0, z(0.66)),
                                       size: HubVec(1.6, 1.2, 1), variant: i))
                inside.append(HubPiece(.electricCart, center: HubVec(x(0.45) + Double(i) * 4, 0, front - 5),
                                       size: HubVec(2.8, 1.4, 1.5), variant: i))
            }
            for i in 0..<2 {
                inside.append(HubPiece(.seatRow, center: HubVec(x(0.66), 0, z(0.82 + Double(i) * 0.08)),
                                       size: HubVec(6, 0.9, 1.2)))
            }
            hotspots += [
                (HubVec(x(0.58), 0, z(0.42)), 1.0),
                (HubVec(x(0.2), 0, z(0.68)), 0.75),
                (HubVec(x(0.86), 0, z(0.55)), 0.4),
            ]
        }
        if facilities.lounge > 0 {
            inside.append(HubPiece(.loungeBlock, center: HubVec(floor.maxX - 24, 6.3, floor.minZ + mezzDepth / 2),
                                   size: HubVec(30 + Double(facilities.lounge) * 10, 3, mezzDepth - 2),
                                   variant: facilities.lounge))
        }
        return HubTerminalInterior(bounds: floor, pieces: inside, hotspots: hotspots)
    }
}

extension HubLayout {
    /// Completes each stand's departure and arrival with the taxi network:
    /// pushback → taxiway → runway line-up → take-off roll → climb-out, and
    /// the reverse for arrivals. Done after planning because the network's
    /// position depends on how far the piers reach.
    public func withTaxiRoutes() -> HubLayout {
        guard let runway = runways.first,
              let taxi = pieces.first(where: { $0.kind == .taxiway && $0.variant == 0 }) else { return self }
        let taxiZ = taxi.center.z
        let rwZ = runway.thresholdA.z
        let west = runway.thresholdA.x, east = runway.thresholdB.x
        let routed = stands.map { s -> HubStand in
            let push = s.departure.points.last!
            let apronExit = HubVec(push.x, 0, taxiZ + 30)
            let onTaxi = HubVec(push.x, 0, taxiZ)
            let hold = HubVec(west + 60, 0, taxiZ)
            let lineUp = HubVec(west + 60, 0, rwZ)
            let rotate = HubVec(west + (east - west) * 0.62, 0, rwZ)
            let liftoff = HubVec(east - 80, 60, rwZ)
            let climb = HubVec(east + 900, 420, rwZ)
            let dep = HubPath(s.departure.points + [apronExit, onTaxi, hold, lineUp, rotate, liftoff, climb])
            let approach = HubVec(west - 1_100, 380, rwZ)
            let touch = HubVec(west + 120, 0, rwZ)
            let vacate = HubVec(east - 60, 0, rwZ)
            let arr = HubPath([approach, touch, vacate, HubVec(east - 60, 0, taxiZ),
                               HubVec(push.x, 0, taxiZ), HubVec(push.x, 0, taxiZ + 30)] + s.arrival.points)
            return HubStand(index: s.index, gate: s.gate, nose: s.nose, heading: s.heading,
                            maxCategory: s.maxCategory, hasBridge: s.hasBridge, bridgeRoot: s.bridgeRoot,
                            departure: dep, arrival: arr, queue: s.queue,
                            safetyOutline: s.safetyOutline, servicePoints: s.servicePoints)
        }
        return HubLayout(airport: airport, runwayClass: runwayClass, pieces: pieces, runways: runways,
                         stands: routed, terminal: terminal, interior: interior, serviceRoute: serviceRoute,
                         serviceStops: serviceStops, focus: focus, bounds: bounds)
    }
}
