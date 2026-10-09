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

/// Merges static copies of models into one mesh per material: a parked
/// turnaround's vehicles, cones and crew, or a hall full of people, become
/// a dozen draws instead of hundreds of entities (docs/HUB_VIEW_3D.md §7).
@available(iOS 18.0, *)
@MainActor
struct HubStaticBatcher {
    private(set) var batches: [HubMaterialKey: HubMeshBatch] = [:]

    mutating func add(_ parts: [(HubMaterialKey, HubMeshBatch)], matrix: float4x4,
                      remap: (HubMaterialKey) -> HubMaterialKey = { $0 }) {
        for (key, batch) in parts {
            batches[remap(key), default: HubMeshBatch()].append(batch, matrix: matrix)
        }
    }

    func entity(materials: HubMaterials, name: String) -> Entity {
        let root = Entity()
        for (key, batch) in batches {
            guard let mesh = batch.resource(name: name) else { continue }
            let model = ModelEntity(mesh: mesh, materials: [materials[key]])
            model.components.set(HubMaterialTag(key: key))
            root.addChild(model)
        }
        return root
    }
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
    /// The focused jet's engine on the camera side, in the jet's own frame.
    private var pulseEngine: SIMD3<Float> = .zero
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
        buildApronTraffic()
        buildLandsideTraffic()
    }

    private static func f(_ v: HubVec) -> SIMD3<Float> { SIMD3(Float(v.x), Float(v.y), Float(v.z)) }

    private func entity(_ parts: [HubPart], remap: @escaping (HubMaterialKey) -> HubMaterialKey = { $0 }) -> Entity {
        models.entity(parts, materials: materials, remap: remap)
    }

    /// A moving vehicle with its contact shadow.
    private func vehicleEntity(_ v: HubModels.Vehicle, remap: (HubMaterialKey) -> HubMaterialKey = { $0 }) -> Entity {
        let e = models.make(HubModels.slot(v), models.vehicle(v), materials: materials, remap: remap)
        let shadow = entity(models.blob())
        let shadowLength: Float = (v == .bus || v == .baggageTrain) ? 13 : 8
        shadow.scale = SIMD3<Float>(shadowLength, 1, 3.6)
        e.addChild(shadow)
        return e
    }

    private func aircraftEntity(_ category: AircraftCategory, livery: Livery) -> Entity {
        let e = models.make(["aircraft_\(category.rawValue)"], models.aircraft(category), materials: materials) { key in
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
        if focus != focusStand || (focus.map { parked[$0]?.occupant.category } ?? nil) != pulseCategory {
            focusStand = focus
            rebuildFocusOverlays()
        }
        rebuildAnchors(snapshot)
    }

    private var pulseCategory: AircraftCategory?

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

    /// Turnaround vehicles, crew and passengers around one stand. The
    /// static ones are merged into one batch per material; walking
    /// passengers stay entities so they can move.
    private func dress(_ stand: HubStand, occupant: HubStandOccupant, level: Int, focused: Bool) -> Entity {
        let group = Entity()
        var batch = HubStaticBatcher()
        let m = HubModels.metrics(occupant.category)
        let fwd = SIMD3<Float>(Float(cos(stand.heading)), 0, Float(-sin(stand.heading)))
        let right = SIMD3<Float>(Float(cos(stand.heading - .pi / 2)), 0, Float(-sin(stand.heading - .pi / 2)))
        let nose = Self.f(stand.nose)
        let yaw = Float(stand.heading)
        func put(_ v: HubModels.Vehicle, _ p: SIMD3<Float>, _ angle: Float) {
            let slots = HubModels.slot(v)
            let at = HubMeshBatch.translation(p) * HubMeshBatch.yaw(angle)
            if models.hasAuthored(slots) {
                let e = models.make(slots, models.vehicle(v), materials: materials)
                e.position = p
                e.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
                group.addChild(e)
            } else {
                batch.add(models.rawVehicle(v), matrix: at)
            }
            let shadowLength: Float = (v == .bus || v == .baggageTrain) ? 13 : 8
            batch.add(models.rawBlob(), matrix: at * HubMeshBatch.scale(SIMD3<Float>(shadowLength, 1, 3.6)))
        }
        let stage = occupant.stage
        let busy = stage != nil && stage != .departed
        if busy {
            // Belt loader at the forward hold, baggage train behind it.
            put(.beltLoader, nose - fwd * (m.length * 0.22) + right * (m.radius + 3.2), yaw + .pi / 2 + 0.25)
            put(.baggageTrain, nose - fwd * (m.length * 0.38) + right * (m.radius + 10), yaw)
        } else if stage == nil {
            // Parked between rotations: tug at the nose, a van by the wing.
            put(.tug, nose + fwd * 5, yaw + .pi)
            put(.serviceVan, nose - fwd * (m.length * 0.5) + right * (m.span * 0.3 + 3), yaw)
        }
        if stage == .servicing || (stage == .boarding && level > 0) {
            put(.fuelTruck, nose - fwd * (m.length * 0.48) + right * (m.span * 0.28 + 2), yaw + .pi)
        }
        if stage == .servicing || stage == .deboarding {
            put(.cateringTruck, nose - fwd * (m.length * 0.78) + right * (m.radius + 4), yaw + .pi / 2)
        }
        if busy && (level > 0 || focused) {
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
        if busy {
            // Cones at the nose, the wingtips and the tail.
            let engineLine: SIMD3<Float> = nose - fwd * (m.length * 0.35)
            let conePositions: [SIMD3<Float>] = [nose + fwd * 2, engineLine + right * (m.span * 0.5 + 1),
                                                 engineLine - right * (m.span * 0.5 + 1), nose - fwd * (m.length + 2)]
            for p in conePositions {
                let at = HubMeshBatch.translation(p + [0, 0.1, 0])
                if models.hasAuthored(["cone"]) {
                    let c = models.make(["cone"], models.cone(), materials: materials)
                    c.position = p + [0, 0.1, 0]
                    group.addChild(c)
                } else {
                    batch.add(models.rawCone(), matrix: at)
                }
            }
            // Ground crew in hi-vis.
            for k in 0..<(focused ? 6 : 3) {
                let p = nose - fwd * (m.length * (0.18 + 0.12 * Float(k))) + right * (m.radius + 2 + Float(k % 2) * 3)
                let face = yaw + (k % 2 == 0 ? .pi / 2 : -.pi / 2)
                let slots = HubModels.personSlots(k, crew: true)
                if models.hasAuthored(slots) {
                    let e = models.make(slots, models.person(k, crew: true), materials: materials) { key in
                        key == .skin(0) ? .skin(k % 4) : key
                    }
                    e.position = p
                    e.scale = [1.8, 1.8, 1.8]
                    group.addChild(e)
                } else {
                    batch.add(models.rawPerson(crew: true),
                              matrix: HubMeshBatch.translation(p) * HubMeshBatch.yaw(face) * HubMeshBatch.scale([1.8, 1.8, 1.8])) { key in
                        key == .skin(0) ? .skin(k % 4) : key
                    }
                }
            }
        }
        // Passengers on the walkway while boarding or deboarding.
        if stage == .boarding || stage == .deboarding {
            let count = focused ? 20 : 8
            for k in 0..<count {
                let person = models.make(HubModels.personSlots(k, crew: false), models.person(k, crew: false),
                                         materials: materials) { key in
                    switch key {
                    case .cloth: .cloth((k * 3 + stand.index) % 8)
                    case .skin: .skin((k + stand.index) % 4)
                    default: key
                    }
                }
                person.scale = [1.8, 1.8, 1.8]
                let offset = Float(k) / Float(count)
                walkers.append((person, stand.queue, offset, stage == .boarding ? 0.03 : -0.03))
                group.addChild(person)
            }
        }
        group.addChild(batch.entity(materials: materials, name: "stand\(stand.index)"))
        return group
    }

    // MARK: Focus overlays

    private func rebuildFocusOverlays() {
        overlays.children.removeAll()
        pulse.removeAll()
        pulseCategory = nil
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
        // Cyan queue glow under the walkway, in every shot.
        var strip = HubMeshBatch()
        let q = stand.queue.points.map(Self.f)
        for (a, b) in zip(q, q.dropFirst()) {
            let mid = (a + b) / 2, d = b - a
            strip.plane(center: [mid.x, 0.3, mid.z], width: simd_length(d) + 2, depth: 3.6, yaw: atan2(-d.z, d.x))
        }
        if let mesh = strip.resource(name: "queue") {
            let e = ModelEntity(mesh: mesh, materials: [materials[.queueGlow]])
            e.components.set(HubMaterialTag(key: .queueGlow))
            overlays.addChild(e)
        }
        // Pulse rings round the engine on the camera's side (reference
        // shot B): the side away from the terminal, as `HubLayout.frame`.
        let right = HubVec(cos(stand.heading - .pi / 2), 0, -sin(stand.heading - .pi / 2))
        let category = parked[index]?.occupant.category ?? stand.maxCategory
        pulseCategory = parked[index]?.occupant.category
        pulseEngine = HubModels.enginePosition(category, right: right.z < -1e-6)
        for _ in 0..<4 {
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
        for (k, spot) in layout.interior.hotspots.prefix(3).enumerated() {
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
        // Jets taxiing between the stands and the taxiway, so the apron
        // is never still.
        for (k, stand) in layout.stands.enumerated() where k % 4 == 1 {
            let pts = stand.departure.points
            guard pts.count > 3 else { continue }
            // From the pushback point out to the taxiway and back.
            let lane = HubPath(Array(pts[1...3]))
            let e = aircraftEntity(k % 8 == 1 ? .narrowbody : .regionalJet, livery: k % 8 == 1 ? .violet : .jade)
            root.addChild(e)
            movers.append(HubMover(entity: e, path: lane, speeds: [7, 9], start: Float(k * 31 % 120), pingPong: true))
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
        // A departure that turns out over the district, so the residential
        // shot has a jet crossing its airside edge (reference shot D).
        if let stop = layout.serviceStops.first {
            let out = HubPath([
                HubVec(west + 60, 0, rwZ), HubVec(east - 420, 0, rwZ), HubVec(east - 120, 70, rwZ),
                HubVec(east + 260, 190, rwZ + 260), HubVec(stop.x + 260, 260, stop.z - 220),
                HubVec(stop.x + 1_600, 760, stop.z + 1_400),
            ])
            let e = aircraftEntity(.narrowbody, livery: .azure)
            root.addChild(e)
            movers.append(HubMover(entity: e, path: out, speeds: [40, 66, 74, 78, 90], start: Float(out.length) * 0.55))
        }
    }

    /// Tugs, baggage trains, vans, fuel bowsers and buses shuttling along
    /// the apron's service roads (reference shot A: ~25 vehicles moving).
    private func buildApronTraffic() {
        let kinds: [HubModels.Vehicle] = [.baggageTrain, .serviceVan, .fuelTruck, .tug, .cateringTruck, .bus]
        let liveries: [Livery] = [.azure, .teal, .slate]
        var k = 0
        for lane in layout.serviceLanes {
            let count = max(2, min(5, Int(lane.length / 60)))
            for i in 0..<count {
                let v = kinds[k % kinds.count]
                let e = vehicleEntity(v) { key in
                    key == .livery(.azure) ? .livery(liveries[k % 3]) : key
                }
                root.addChild(e)
                // Two-way traffic: alternate vehicles keep to either side.
                let side: Double = i % 2 == 0 ? 2.2 : -2.2
                let path = HubPath(lane.points.map { HubVec($0.x, 0, $0.z + side) })
                movers.append(HubMover(entity: e, path: path, speeds: [5.5 + Float(k % 3) * 1.5],
                                       start: Float(i) / Float(count) * Float(lane.length) + Float(k * 13 % 40),
                                       pingPong: true))
                k += 1
            }
        }
    }

    private func buildLandsideTraffic() {
        let kerbZ = layout.terminal.maxZ + 16
        let roads = layout.pieces.filter { $0.kind == .road && max($0.size.x, $0.size.z) > 300 }
        var k = 0
        for road in roads {
            let alongX = road.size.x >= road.size.z
            let half = (alongX ? road.size.x : road.size.z) / 2 - 10
            let atKerb = alongX && abs(road.center.z - kerbZ) < 1
            for lane in [-1.0, 1.0] {
                let off = lane * 3.2
                let a = alongX ? HubVec(road.center.x - half, 0.12, road.center.z + off)
                    : HubVec(road.center.x + off, 0.12, road.center.z - half)
                let b = alongX ? HubVec(road.center.x + half, 0.12, road.center.z + off)
                    : HubVec(road.center.x + off, 0.12, road.center.z + half)
                let path = lane > 0 ? HubPath([a, b]) : HubPath([b, a])
                let count = atKerb ? 3 : Int(half / 220) + 1
                for i in 0..<count {
                    let colour = k
                    // The kerb gets buses and taxis; streets get cars and vans.
                    let kind: HubModels.Vehicle = atKerb ? (i == 0 ? .bus : .car) : (i % 5 == 0 ? .serviceVan : .car)
                    let car = vehicleEntity(kind) { key in
                        key == .cloth(0) ? .cloth(atKerb ? 3 : [0, 1, 5, 6, 7, 3][colour % 6]) : key
                    }
                    root.addChild(car)
                    let mover = HubMover(entity: car, path: path, speeds: [atKerb ? 6 : 14 + Float(k % 4) * 2],
                                         start: Float(i) * Float(path.length) / Float(count) + Float(k * 37 % 90))
                    movers.append(mover)
                    k += 1
                }
            }
        }
        // The service cart towing its tank trailer round the district's
        // streets past the first stop's gate, so it is in the district shot
        // (reference shot D).
        let stop = layout.serviceStops.first ?? layout.focus.district
        let near = layout.serviceRoute.points.filter { $0.distance(to: stop) < 160 }
        let loop = near.count >= 2 ? HubPath(near) : layout.serviceRoute
        for (i, v) in [HubModels.Vehicle.golfCart, .tanker].enumerated() {
            let e = vehicleEntity(v)
            root.addChild(e)
            movers.append(HubMover(entity: e, path: loop, speeds: [4.5], start: Float(loop.length) * 0.35 - Float(i) * 6,
                                   pingPong: true))
        }
    }

    /// The district's service route: a raised glowing ribbon with rounded
    /// joints and a soft halo on the road (reference shot D).
    private func buildRouteLine() {
        var core = HubMeshBatch(), halo = HubMeshBatch()
        let points = layout.serviceRoute.points.map(Self.f)
        for (a, b) in zip(points, points.dropFirst()) {
            let mid = (a + b) / 2, d = b - a
            let length = simd_length(SIMD3(d.x, 0, d.z))
            guard length > 0.01 else { continue }
            let yaw = atan2(-d.z, d.x)
            core.roundedBox(center: [mid.x, 0.16, mid.z], size: [length, 0.22, 0.8], yaw: yaw, bevel: 0.1)
            halo.plane(center: [mid.x, 0.3, mid.z], width: length + 1.5, depth: 4.6, yaw: yaw)
        }
        for p in points {
            core.cylinder(base: [p.x, 0.16, p.z], radius: 0.4, height: 0.22, segments: 12)
        }
        for (mesh, key) in [(core.resource(name: "route"), HubMaterialKey.routeGlow),
                            (halo.resource(name: "routeHalo"), HubMaterialKey.queueGlow)] {
            guard let mesh else { continue }
            let e = ModelEntity(mesh: mesh, materials: [materials[key]])
            e.components.set(HubMaterialTag(key: key))
            routeLine.addChild(e)
        }
    }

    // MARK: Interior crowd

    func populateInterior(load: Double) {
        interiorCrowd.children.removeAll()
        var jitter = SplitMix(seed: 7)
        // ~34 people per bay of the hall at a quiet hour, ~84 when full —
        // the reference's hall holds about 28 in one bay's worth of floor.
        let bays = max(1, layout.interior.bays)
        let count = min(300, bays * (34 + Int(50 * load)))
        let hotspots = layout.interior.hotspots
        guard !hotspots.isEmpty else { return }
        let total = hotspots.reduce(0) { $0 + $1.weight }
        var batch = HubStaticBatcher()
        let authored = models.hasAuthored(HubModels.personSlots(0, crew: false))
        for k in 0..<count {
            var pick = jitter.unit() * total
            var spot = hotspots[0]
            for h in hotspots {
                pick -= h.weight
                if pick <= 0 { spot = h; break }
            }
            let spread = 5 + 8 * spot.weight
            let at = SIMD3<Float>(Float(spot.position.x + (jitter.unit() - 0.5) * spread * 2), 1.7,
                                  Float(spot.position.z + (jitter.unit() - 0.5) * spread))
            let yaw = Float(jitter.unit() * 6.28)
            let remap: (HubMaterialKey) -> HubMaterialKey = { key in
                switch key {
                case .cloth: .cloth(k % 8)
                case .skin: .skin(k % 4)
                default: key
                }
            }
            if authored {
                let p = models.make(HubModels.personSlots(k, crew: false), models.person(k, crew: false),
                                    materials: materials, remap: remap)
                p.position = at
                p.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                p.scale = [2.0, 2.0, 2.0]
                interiorCrowd.addChild(p)
            } else {
                let placed = HubMeshBatch.translation(at) * HubMeshBatch.yaw(yaw) * HubMeshBatch.scale([2, 2, 2])
                batch.add(models.rawPerson(crew: false), matrix: placed, remap: remap)
                // Every third traveller pulls a suitcase.
                if k % 3 == 0 {
                    batch.add(models.rawLuggage(), matrix: placed * HubMeshBatch.translation([0.05, 0, 0.45])) { key in
                        key == .cloth(1) ? .cloth([1, 4, 6, 3][k % 4]) : key
                    }
                }
            }
        }
        if !authored {
            interiorCrowd.addChild(batch.entity(materials: materials, name: "crowd"))
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
        // Pulse rings round the focused jet's engine: stacked, tilted,
        // growing and fading out in turn (reference shot B).
        if let index = focusStand, let current = parked[index] {
            let engine = current.entity.convert(position: pulseEngine, to: nil)
            let tilt = current.entity.orientation * simd_quatf(angle: 0.16, axis: [1, 0, 0])
            for (k, ring) in pulse.enumerated() {
                let phase = (time * 0.42 + Float(k) / Float(pulse.count)).truncatingRemainder(dividingBy: 1)
                let size = 3 + 9 * phase
                ring.position = engine + [0, Float(k) * 0.5 - 0.3, 0]
                ring.orientation = tilt
                ring.scale = [size, 1, size]
                ring.components.set(OpacityComponent(opacity: min(1, (1 - phase) * 1.5)))
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
