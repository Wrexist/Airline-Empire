import RealityKit
import UIKit
import simd
import AirlineEmpireCore

/// Something that moves along a path forever: ambient air traffic, cars,
/// the service cart. Speeds are per segment so a jet can float down the
/// approach, brake on the runway and crawl along the taxiway.
@available(iOS 18.0, *)
@MainActor
final class HubMover {
    let entity: Entity
    let path: HubPath
    let speeds: [Float]
    var distance: Float
    let pingPong: Bool
    var direction: Float = 1
    let height: Float

    init(entity: Entity, path: HubPath, speeds: [Float], start: Float = 0, pingPong: Bool = false, height: Float = 0) {
        self.entity = entity
        self.path = path
        self.speeds = speeds
        self.distance = start
        self.pingPong = pingPong
        self.height = height
    }

    private lazy var cumulative: [Float] = {
        var out: [Float] = [0]
        for (a, b) in zip(path.points, path.points.dropFirst()) {
            let d = b - a
            out.append(out.last! + Float((d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()))
        }
        return out
    }()

    var length: Float { cumulative.last ?? 0 }

    func step(_ dt: Float) {
        guard length > 0 else { return }
        let segment = max(0, min(speeds.count - 1, (cumulative.firstIndex { $0 > distance } ?? cumulative.count) - 1))
        distance += speeds[segment] * dt * direction
        if pingPong {
            if distance > length { distance = length; direction = -1 }
            if distance < 0 { distance = 0; direction = 1 }
        } else if distance > length {
            distance -= length
        }
        let s = path.sample(at: Double(distance))
        let yaw = Float(s.yaw) + (direction < 0 ? .pi : 0)
        // Bank into turns and pitch on climbs would be nice; a level attitude
        // reads cleaner at the dashboard's distance.
        entity.position = [Float(s.position.x), Float(s.position.y) + height, Float(s.position.z)]
        entity.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        if s.position.y > 1 {
            // Nose-up on the climb, nose-down on the approach.
            let climbing = distance > length * 0.5
            entity.orientation *= simd_quatf(angle: climbing ? 0.14 : -0.04, axis: [0, 0, 1])
        }
    }
}

/// Anchors the SwiftUI overlay pins to the 3D world.
struct HubAnchor: Identifiable, Equatable {
    enum Kind: Equatable {
        case callout
        case pin(String)
        case pill(String, systemImage: String)
    }

    let id: String
    let position: SIMD3<Float>
    let kind: Kind
}

/// Everything in the scene that follows the simulation or moves.
@available(iOS 18.0, *)
@MainActor
final class HubDynamics {
    let root = Entity()
    let layout: HubLayout
    private let models: HubModels
    private let materials: HubMaterials

    private var parked: [Int: (entity: Entity, occupant: HubStandOccupant)] = [:]
    private var standDressing: [Int: Entity] = [:]
    private var movers: [HubMover] = []
    private var crowd = Entity()
    private var interiorCrowd = Entity()
    private var overlays = Entity()
    private var pulse: [Entity] = []
    private var routeLine = Entity()
    private var time: Float = 0
    private(set) var focusStand: Int?
    private(set) var anchors: [HubAnchor] = []
    private var walkers: [(entity: Entity, path: HubPath, offset: Float, speed: Float)] = []

    var showsInterior = false {
        didSet { interiorCrowd.isEnabled = showsInterior }
    }

    var showsRoute = false {
        didSet { routeLine.isEnabled = showsRoute }
    }

    init(layout: HubLayout, models: HubModels, materials: HubMaterials) {
        self.layout = layout
        self.models = models
        self.materials = materials
        root.name = "dynamics"
        for e in [crowd, interiorCrowd, overlays, routeLine] { root.addChild(e) }
        interiorCrowd.isEnabled = false
        routeLine.isEnabled = false
        buildRouteLine()
        buildAmbientTraffic()
        buildLandsideTraffic()
    }

    private static func f(_ v: HubVec) -> SIMD3<Float> { SIMD3(Float(v.x), Float(v.y), Float(v.z)) }

    private func entity(_ parts: [HubPart], remap: @escaping (HubMaterialKey) -> HubMaterialKey = { $0 }) -> Entity {
        models.entity(parts, materials: materials, remap: remap)
    }

    private func aircraftEntity(_ category: AircraftCategory, livery: Livery) -> Entity {
        let e = entity(models.aircraft(category)) { key in
            switch key {
            case .livery: .livery(livery)
            case .liveryAccent: .liveryAccent(livery)
            default: key
            }
        }
        let m = HubModels.metrics(category)
        let shadow = entity(models.blob())
        shadow.scale = [m.length * 1.15, 1, m.span * 1.05]
        shadow.position.y = -0.05
        e.addChild(shadow)
        return e
    }

    // MARK: Snapshot

    func apply(_ snapshot: HubSnapshot, focus: Int?, groundServices: Int) {
        let wanted = Dictionary(uniqueKeysWithValues: snapshot.occupants.map { ($0.standIndex, $0) })
        for (index, current) in parked where wanted[index] == nil
            || wanted[index]!.category != current.occupant.category
            || wanted[index]!.livery != current.occupant.livery {
            current.entity.removeFromParent()
            standDressing[index]?.removeFromParent()
            standDressing[index] = nil
            parked[index] = nil
        }
        for (index, occupant) in wanted {
            let stand = layout.stands[index]
            let e: Entity
            if let existing = parked[index] {
                e = existing.entity
            } else {
                e = aircraftEntity(occupant.category, livery: occupant.livery)
                e.name = "aircraft-\(index)"
                // Tappable.
                let m = HubModels.metrics(occupant.category)
                e.components.set(CollisionComponent(shapes: [.generateBox(size: [m.length, m.radius * 3, m.span * 0.5])
                        .offsetBy(translation: [0, m.axisY, 0])]))
                root.addChild(e)
            }
            parked[index] = (e, occupant)
            place(e, at: stand, occupant: occupant)
            let previous = standDressing[index]?.name
            let signature = "\(occupant.stage?.rawValue ?? -1)-\(groundServices)-\(index == focus)"
            if previous != signature {
                standDressing[index]?.removeFromParent()
                let dressing = dress(stand, occupant: occupant, level: groundServices, focused: index == focus)
                dressing.name = signature
                root.addChild(dressing)
                standDressing[index] = dressing
            }
        }
        if focus != focusStand {
            focusStand = focus
            rebuildFocusOverlays()
        }
        rebuildAnchors(snapshot)
    }

    private func place(_ e: Entity, at stand: HubStand, occupant: HubStandOccupant) {
        let m = HubModels.metrics(occupant.category)
        let fwd = SIMD3<Float>(Float(cos(stand.heading)), 0, Float(-sin(stand.heading)))
        var center = Self.f(stand.nose) - fwd * (m.length / 2 + 2)
        if occupant.stage == .pushback {
            center -= fwd * Float(occupant.stageProgress) * 24
        }
        e.position = center
        e.orientation = simd_quatf(angle: Float(stand.heading), axis: [0, 1, 0])
    }

    /// Turnaround vehicles, crew and passengers around one stand.
    private func dress(_ stand: HubStand, occupant: HubStandOccupant, level: Int, focused: Bool) -> Entity {
        let group = Entity()
        let m = HubModels.metrics(occupant.category)
        let fwd = SIMD3<Float>(Float(cos(stand.heading)), 0, Float(-sin(stand.heading)))
        let right = SIMD3<Float>(Float(cos(stand.heading - .pi / 2)), 0, Float(-sin(stand.heading - .pi / 2)))
        let nose = Self.f(stand.nose)
        let yaw = Float(stand.heading)
        func put(_ v: HubModels.Vehicle, _ p: SIMD3<Float>, _ angle: Float) {
            let e = entity(models.vehicle(v))
            e.position = p
            e.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
            let shadow = entity(models.blob())
            shadow.scale = [9, 1, 4]
            e.addChild(shadow)
            group.addChild(e)
        }
        let stage = occupant.stage
        let busy = stage != nil && stage != .departed
        if busy {
            // Belt loader at the forward hold, baggage train behind it.
            put(.beltLoader, nose - fwd * (m.length * 0.22) + right * (m.radius + 3.2), yaw + .pi / 2 + 0.25)
            put(.baggageTrain, nose - fwd * (m.length * 0.38) + right * (m.radius + 10), yaw)
        }
        if stage == .servicing || (stage == .boarding && level > 0) {
            put(.fuelTruck, nose - fwd * (m.length * 0.48) + right * (m.span * 0.28 + 2), yaw + .pi)
        }
        if stage == .servicing || stage == .deboarding {
            put(.cateringTruck, nose - fwd * (m.length * 0.78) + right * (m.radius + 4), yaw + .pi / 2)
        }
        if level > 0 && busy {
            put(.serviceVan, nose - fwd * (m.length * 0.6) - right * (m.span * 0.45 + 4), yaw)
        }
        if level > 1 && busy {
            put(.tanker, nose - fwd * (m.length + 10) + right * 6, yaw + .pi / 2)
        }
        if stage == .pushback || stage == .boarding {
            put(.tug, nose + fwd * 6 - fwd * Float(stage == .pushback ? occupant.stageProgress * 24 : 0), yaw + .pi)
        }
        if !stand.hasBridge && busy {
            put(.bus, nose - fwd * (m.length * 0.3) - right * (m.radius + 12), yaw)
        }
        // Cones at the nose and engines.
        if busy {
            let engineLine: SIMD3<Float> = nose - fwd * (m.length * 0.35)
            let engineOffset: SIMD3<Float> = right * (m.span * 0.34)
            let noseCone: SIMD3<Float> = nose + fwd * 2
            let tailCone: SIMD3<Float> = nose - fwd * (m.length + 2)
            let conePositions: [SIMD3<Float>] = [noseCone, engineLine + engineOffset, engineLine - engineOffset, tailCone]
            for p in conePositions {
                let c = entity(models.cone())
                c.position = p + [0, 0.1, 0]
                group.addChild(c)
            }
            // Ground crew.
            for k in 0..<(focused ? 5 : 2) {
                let p = entity(models.person(k, crew: true)) { key in key == .skin(0) ? .skin(k) : key }
                p.position = nose - fwd * (m.length * (0.18 + 0.12 * Float(k))) + right * (m.radius + 2 + Float(k % 2) * 3)
                p.scale = [1.8, 1.8, 1.8]
                group.addChild(p)
            }
        }
        // Passengers on the walkway while boarding or deboarding.
        if stage == .boarding || stage == .deboarding {
            let count = focused ? 16 : 7
            for k in 0..<count {
                let person = entity(models.person(k, crew: false)) { key in
                    switch key {
                    case .cloth: .cloth(k * 3 + stand.index)
                    case .skin: .skin(k + stand.index)
                    default: key
                    }
                }
                person.scale = [1.8, 1.8, 1.8]
                let offset = Float(k) / Float(count)
                walkers.append((person, stand.queue, offset, stage == .boarding ? 0.03 : -0.03))
                group.addChild(person)
            }
        }
        return group
    }

    // MARK: Focus overlays

    private func rebuildFocusOverlays() {
        overlays.children.removeAll()
        pulse.removeAll()
        guard let index = focusStand, index < layout.stands.count else { return }
        let stand = layout.stands[index]
        // Pink safety outline.
        let outline = stand.safetyOutline.map(Self.f)
        var lines = HubMeshBatch()
        for (a, b) in zip(outline, outline.dropFirst()) {
            let mid = (a + b) / 2, d = b - a
            lines.box(center: [mid.x, 0.12, mid.z], size: [simd_length(d) + 0.5, 0.05, 0.6], yaw: atan2(-d.z, d.x))
        }
        if let mesh = lines.resource(name: "outline") {
            let e = ModelEntity(mesh: mesh, materials: [materials[.safety]])
            e.components.set(HubMaterialTag(key: .safety))
            overlays.addChild(e)
        }
        // Cyan queue glow under the walkway.
        var strip = HubMeshBatch()
        let q = stand.queue.points.map(Self.f)
        for (a, b) in zip(q, q.dropFirst()) {
            let mid = (a + b) / 2, d = b - a
            strip.plane(center: [mid.x, 0.3, mid.z], width: simd_length(d) + 2, depth: 3.2, yaw: atan2(-d.z, d.x))
        }
        if let mesh = strip.resource(name: "queue") {
            let e = ModelEntity(mesh: mesh, materials: [materials[.queueGlow]])
            e.components.set(HubMaterialTag(key: .queueGlow))
            overlays.addChild(e)
        }
        // Two pulse rings at the wing root.
        for _ in 0..<2 {
            let ring = entity(models.ring())
            ring.components.set(OpacityComponent(opacity: 0))
            overlays.addChild(ring)
            pulse.append(ring)
        }
    }

    // MARK: Anchors

    private func rebuildAnchors(_ snapshot: HubSnapshot) {
        var list: [HubAnchor] = []
        if let index = focusStand, let current = parked[index] {
            let m = HubModels.metrics(current.occupant.category)
            list.append(HubAnchor(id: "callout", position: current.entity.position + [0, m.axisY + m.radius + 9, 0], kind: .callout))
        }
        // Terminal hotspots (visible in the cutaway).
        let labels = ["Security", "Check-in", "Retail"]
        for (k, spot) in layout.interior.hotspots.enumerated() {
            list.append(HubAnchor(id: "hot\(k)", position: Self.f(spot.position) + [0, 7, 0],
                                  kind: .pin(labels[k % labels.count])))
        }
        // District service stops.
        let stops = [("Maintenance", "wrench.and.screwdriver.fill"), ("Crew pickup", "person.2.fill"),
                     ("Waste pickup", "trash.fill")]
        for (k, stop) in layout.serviceStops.enumerated() {
            list.append(HubAnchor(id: "stop\(k)", position: Self.f(stop) + [0, 12, 0],
                                  kind: .pill(stops[k % stops.count].0, systemImage: stops[k % stops.count].1)))
        }
        anchors = list
    }

    // MARK: Ambient traffic

    private func buildAmbientTraffic() {
        guard let runway = layout.runways.first,
              let taxi = layout.pieces.first(where: { $0.kind == .taxiway && $0.variant == 0 }) else { return }
        let rwZ = runway.thresholdA.z, taxiZ = taxi.center.z
        let west = runway.thresholdA.x, east = runway.thresholdB.x
        let loop = HubPath([
            HubVec(west - 1_400, 420, rwZ), HubVec(west + 140, 0, rwZ), HubVec(east - 140, 0, rwZ),
            HubVec(east - 60, 0, taxiZ), HubVec(west + 60, 0, taxiZ), HubVec(west + 60, 0, rwZ),
            HubVec(east - 200, 0, rwZ), HubVec(east + 600, 260, rwZ), HubVec(east + 2_400, 900, rwZ),
        ])
        let speeds: [Float] = [75, 42, 12, 18, 8, 55, 75, 90]
        let categories: [AircraftCategory] = [.narrowbody, .widebody, .regionalJet]
        let liveries: [Livery] = [.slate, .crimson, .teal]
        for k in 0..<2 {
            let e = aircraftEntity(categories[k % 3], livery: liveries[k % 3])
            root.addChild(e)
            let mover = HubMover(entity: e, path: loop, speeds: speeds, start: Float(k) * 2_600)
            movers.append(mover)
        }
        // Second runway gets departures only.
        if layout.runways.count > 1 {
            let r2 = layout.runways[1]
            let dep = HubPath([HubVec(r2.thresholdA.x + 60, 0, r2.thresholdA.z), HubVec(r2.thresholdB.x - 200, 0, r2.thresholdA.z),
                               HubVec(r2.thresholdB.x + 600, 260, r2.thresholdA.z),
                               HubVec(r2.thresholdB.x + 2_600, 900, r2.thresholdA.z)])
            let e = aircraftEntity(.largeWidebody, livery: .gold)
            root.addChild(e)
            movers.append(HubMover(entity: e, path: dep, speeds: [50, 75, 90], start: 400))
        }
    }

    private func buildLandsideTraffic() {
        let roads = layout.pieces.filter { $0.kind == .road && max($0.size.x, $0.size.z) > 400 }
        var k = 0
        for road in roads {
            let alongX = road.size.x >= road.size.z
            let half = (alongX ? road.size.x : road.size.z) / 2 - 10
            for lane in [-1.0, 1.0] {
                let off = lane * 3.2
                let a = alongX ? HubVec(road.center.x - half, 0.12, road.center.z + off)
                    : HubVec(road.center.x + off, 0.12, road.center.z - half)
                let b = alongX ? HubVec(road.center.x + half, 0.12, road.center.z + off)
                    : HubVec(road.center.x + off, 0.12, road.center.z + half)
                let path = lane > 0 ? HubPath([a, b]) : HubPath([b, a])
                let count = Int(half / 220) + 1
                for i in 0..<count {
                    let colour = k
                    let car = entity(models.vehicle(i % 5 == 0 ? .serviceVan : .car)) { key in
                        key == .cloth(0) ? .cloth([0, 1, 5, 6, 7, 3][colour % 6]) : key
                    }
                    root.addChild(car)
                    let mover = HubMover(entity: car, path: path, speeds: [14 + Float(k % 4) * 2],
                                         start: Float(i) * Float(path.length) / Float(count) + Float(k * 37 % 90))
                    movers.append(mover)
                    k += 1
                }
            }
        }
        // The service cart and tanker on the district route (shot D).
        for (i, v) in [HubModels.Vehicle.golfCart, .tanker].enumerated() {
            let e = entity(models.vehicle(v))
            root.addChild(e)
            movers.append(HubMover(entity: e, path: layout.serviceRoute, speeds: [7], start: Float(i) * 140,
                                   pingPong: true))
        }
    }

    private func buildRouteLine() {
        var line = HubMeshBatch()
        let points = layout.serviceRoute.points.map(Self.f)
        for (a, b) in zip(points, points.dropFirst()) {
            let mid = (a + b) / 2, d = b - a
            line.box(center: [mid.x, 0.34, mid.z], size: [simd_length(d) + 1.2, 0.06, 1.2], yaw: atan2(-d.z, d.x))
        }
        if let mesh = line.resource(name: "route") {
            let e = ModelEntity(mesh: mesh, materials: [materials[.routeGlow]])
            e.components.set(HubMaterialTag(key: .routeGlow))
            routeLine.addChild(e)
        }
    }

    // MARK: Interior crowd

    func populateInterior(load: Double) {
        interiorCrowd.children.removeAll()
        var jitter = SplitMix(seed: 7)
        let count = 46 + Int(110 * load)
        let hotspots = layout.interior.hotspots
        let total = hotspots.reduce(0) { $0 + $1.weight }
        for k in 0..<count {
            var pick = jitter.unit() * total
            var spot = hotspots[0]
            for h in hotspots {
                pick -= h.weight
                if pick <= 0 { spot = h; break }
            }
            let p = entity(models.person(k, crew: false)) { key in
                switch key {
                case .cloth: .cloth(k)
                case .skin: .skin(k)
                default: key
                }
            }
            let spread = 6 + 10 * spot.weight
            p.position = [Float(spot.position.x + (jitter.unit() - 0.5) * spread * 2), 1.7,
                          Float(spot.position.z + (jitter.unit() - 0.5) * spread)]
            p.orientation = simd_quatf(angle: Float(jitter.unit() * 6.28), axis: [0, 1, 0])
            p.scale = [2.0, 2.0, 2.0]
            interiorCrowd.addChild(p)
        }
    }

    // MARK: Frame

    func update(_ dt: Float) {
        time += dt
        for mover in movers { mover.step(dt) }
        // Walkers along queues.
        for (entity, path, offset, speed) in walkers where entity.scene != nil {
            var t = (offset + time * speed).truncatingRemainder(dividingBy: 1)
            if t < 0 { t += 1 }
            let s = path.sample(fraction: Double(t))
            entity.position = [Float(s.position.x), Float(s.position.y), Float(s.position.z)]
            entity.orientation = simd_quatf(angle: Float(s.yaw) + (speed < 0 ? .pi : 0), axis: [0, 1, 0])
        }
        walkers.removeAll { $0.entity.parent?.parent == nil }
        // Pulse rings around the focused aircraft.
        if let index = focusStand, let current = parked[index] {
            let m = HubModels.metrics(current.occupant.category)
            let fwd = current.entity.transform.matrix.columns.0
            let base = current.entity.position - SIMD3(fwd.x, 0, fwd.z) * (m.length * 0.08)
            for (k, ring) in pulse.enumerated() {
                let phase = (time * 0.5 + Float(k) * 0.5).truncatingRemainder(dividingBy: 1)
                let size = m.span * (0.25 + 0.55 * phase)
                ring.position = base + [0, 0.05, 0]
                ring.scale = [size, 1, size]
                ring.components.set(OpacityComponent(opacity: (1 - phase) * 0.9))
            }
        }
    }
}

/// Deterministic jitter for the app layer (crowds).
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
