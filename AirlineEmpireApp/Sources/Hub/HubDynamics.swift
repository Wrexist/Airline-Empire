import RealityKit
import UIKit
import simd
import AirlineEmpireCore

/// Something that moves along a path forever: ambient air traffic, apron
/// vehicles, cars, the service cart.
///
/// Motion is what makes the diorama feel alive or cheap, so it is modelled
/// rather than interpolated: paths have their corners rounded; speed eases
/// towards each leg's target within an acceleration limit (a jet floats
/// down the approach, brakes on the runway, crawls along the taxiway);
/// heading steers towards a point a little ahead instead of snapping at
/// corners; jets pitch with the climb and bank into turns; back-and-forth
/// movers brake, pause and turn at the ends; one-way movers fade in and out
/// at the ends of their path instead of popping.
@available(iOS 18.0, *)
@MainActor
final class HubMover {
    enum Style { case ground, air }

    let entity: Entity
    let path: HubPath
    let style: Style
    let pingPong: Bool
    let height: Float
    private let speeds: [Float]
    /// Where each original leg ends, measured along the rounded path.
    private let legEnds: [Float]
    private let length: Float
    private let closed: Bool
    private let accel: Float
    private var distance: Float
    private var direction: Float = 1
    private var speed: Float
    private var heading: Float?
    private var bank: Float = 0
    private var pitch: Float = 0
    private var dwell: Float = 0
    private var faded = false

    init(entity: Entity, path original: HubPath, speeds: [Float], start: Float = 0, pingPong: Bool = false,
         height: Float = 0, style: Style = .ground, corner: Double? = nil) {
        let path = original.rounded(radius: corner ?? (style == .air ? 70 : 9))
        self.entity = entity
        self.path = path
        self.style = style
        self.pingPong = pingPong
        self.height = height
        let resolved = speeds.isEmpty ? [Float(6)] : speeds
        self.speeds = resolved
        let total = Float(path.length)
        length = total
        closed = path.points.count > 2 && path.points.first == path.points.last
        accel = style == .air ? 3.5 : 2.4
        // Leg boundaries of the original path, scaled onto the rounded one
        // (rounding shortens corners only slightly).
        var marks: [Float] = []
        var run: Float = 0
        let originalLength = Float(max(original.length, 0.001))
        for (a, b) in zip(original.points, original.points.dropFirst()) {
            let d = b - a
            run += Float((d.x * d.x + d.y * d.y + d.z * d.z).squareRoot())
            marks.append(run / originalLength * total)
        }
        legEnds = marks
        distance = total > 0 ? start.truncatingRemainder(dividingBy: total) : 0
        if distance < 0 { distance += total }
        speed = resolved[0]
    }

    private func targetSpeed() -> Float {
        let leg = legEnds.firstIndex { $0 >= distance } ?? (legEnds.count - 1)
        return speeds[min(max(0, leg), speeds.count - 1)]
    }

    private static func wrap(_ a: Float) -> Float {
        var x = a.truncatingRemainder(dividingBy: 2 * .pi)
        if x > .pi { x -= 2 * .pi }
        if x < -.pi { x += 2 * .pi }
        return x
    }

    func step(_ dt: Float) {
        guard length > 0 else { return }
        if dwell > 0 {
            dwell -= dt
            if dwell <= 0 { direction = -direction }
            pose(dt)
            return
        }
        var target = targetSpeed()
        if pingPong {
            // Brake to a stop at the end of the line.
            let remaining = direction > 0 ? length - distance : distance
            target = min(target, (2 * accel * max(0, remaining)).squareRoot() + 0.25)
        }
        speed += max(-accel * dt, min(accel * dt, target - speed))
        distance += speed * dt * direction
        if pingPong {
            if distance >= length { distance = length; speed = 0; dwell = 1.8 }
            if distance <= 0 { distance = 0; speed = 0; dwell = 1.8 }
        } else if distance >= length {
            distance -= length
        } else if distance < 0 {
            distance += length
        }
        pose(dt)
    }

    private func at(_ d: Float) -> HubVec {
        var x = d
        if closed {
            x = x.truncatingRemainder(dividingBy: length)
            if x < 0 { x += length }
        } else {
            x = max(0, min(length, x))
        }
        return path.sample(at: Double(x)).position
    }

    private func pose(_ dt: Float) {
        let here = at(distance)
        let lookahead: Float = style == .air ? 30 + speed * 0.8 : 3 + speed * 0.45
        let ahead = at(distance + lookahead * (dwell > 0 ? -direction : direction))
        let dx = Float(ahead.x - here.x), dz = Float(ahead.z - here.z)
        let flat = (dx * dx + dz * dz).squareRoot()
        let wanted = flat > 0.05 ? atan2(-dz, dx) : (heading ?? 0)
        let previous = heading ?? wanted
        let turnRate: Float = style == .air ? 1.4 : 4.5
        let yaw = previous + Self.wrap(wanted - previous) * min(1, dt * turnRate)
        heading = yaw
        if style == .air {
            // Bank into the turn, pitch with the climb or descent.
            let yawRate = dt > 0 ? Self.wrap(yaw - previous) / dt : 0
            let wantBank = max(-0.5, min(0.5, -yawRate * 1.6))
            bank += (wantBank - bank) * min(1, dt * 2)
            let climb = flat > 0.5 ? Float(ahead.y - here.y) / flat : 0
            let wantPitch = here.y > 0.5 || climb > 0.01 ? max(-0.1, min(0.24, atan(climb))) : 0
            pitch += (wantPitch - pitch) * min(1, dt * 2.5)
        }
        entity.position = [Float(here.x), Float(here.y) + height, Float(here.z)]
        entity.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            * simd_quatf(angle: pitch, axis: [0, 0, 1])
            * simd_quatf(angle: bank, axis: [1, 0, 0])
        // One-way paths fade in and out at their ends rather than pop.
        if !closed && !pingPong {
            let edge = min(distance, length - distance)
            let fade: Float = style == .air ? 120 : 25
            let opacity = max(0, min(1, edge / fade))
            if opacity < 0.999 {
                entity.components.set(OpacityComponent(opacity: opacity * opacity * (3 - 2 * opacity)))
                faded = true
            } else if faded {
                entity.components.remove(OpacityComponent.self)
                faded = false
            }
        }
    }
}

/// How a world label is tinted.
enum HubTone: Equatable {
    case good, accent, warn, neutral
}

/// A player's stand, labelled over its jet in the overview.
struct HubStandTag: Equatable {
    let standIndex: Int
    let gate: Int
    let code: String
    let stage: String
    let systemImage: String
    let tone: HubTone
}

/// A route of the fan, labelled part-way along its arc.
struct HubRouteTag: Equatable {
    let routeID: RouteID
    let code: String
    let detail: String
    /// Load-factor band, as `HubMaterialKey.routeArc`.
    let band: Int
    let highlighted: Bool
}

/// Anchors the SwiftUI overlay pins to the 3D world.
struct HubAnchor: Identifiable, Equatable {
    enum Kind: Equatable {
        case callout
        case pin(String)
        case pill(String, systemImage: String)
        case tag(HubStandTag)
        case route(HubRouteTag)
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
    /// Everything that circulates on its own: the circuit, apron and
    /// street traffic. One switch for the layers menu.
    private var traffic = Entity()
    /// The player's routes out of the hub (`updateRouteFan`).
    private var routeFan = Entity()
    private var routeArcs: [(link: HubRouteLink, points: [SIMD3<Float>])] = []
    private var routePulses: [(entity: Entity, arc: Int, offset: Float, speed: Float, outbound: Bool)] = []
    private var routeSignature = ""
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

    var showsRouteFan = false {
        didSet { routeFan.isEnabled = showsRouteFan }
    }

    var showsTraffic = true {
        didSet { traffic.isEnabled = showsTraffic }
    }

    /// The route drawn bright and thick, chosen in the insights panel or
    /// from search.
    var highlightedRoute: RouteID? {
        didSet {
            guard highlightedRoute != oldValue else { return }
            routeSignature = ""
            if let last = lastLinks { updateRouteFan(last) }
        }
    }
    private var lastLinks: [HubRouteLink]?

    init(layout: HubLayout, models: HubModels, materials: HubMaterials) {
        self.layout = layout
        self.models = models
        self.materials = materials
        root.name = "dynamics"
        for e in [crowd, interiorCrowd, overlays, routeLine, traffic, routeFan] { root.addChild(e) }
        interiorCrowd.isEnabled = false
        routeLine.isEnabled = false
        routeFan.isEnabled = false
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
            parkTargets[index] = nil
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
        updateRouteFan(snapshot.insights.routes)
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
        // The snapshot moves a pushback in steps; the jet glides to each
        // new spot instead (`update`). A new arrival is placed outright.
        if parkTargets[stand.index] == nil { e.position = center }
        parkTargets[stand.index] = center
        e.orientation = simd_quatf(angle: Float(stand.heading), axis: [0, 1, 0])
    }

    private var parkTargets: [Int: SIMD3<Float>] = [:]

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
        // The player's stands, tagged over their jets.
        for occupant in snapshot.occupants where occupant.operatorKind == .player {
            guard let current = parked[occupant.standIndex] else { continue }
            let m = HubModels.metrics(occupant.category)
            let stage = occupant.stage
            let delayed = (occupant.flight?.delayMinutes ?? 0) > 0
            let tone: HubTone = delayed ? .warn : stage == .boarding || stage == .pushback ? .accent : .good
            let tag = HubStandTag(standIndex: occupant.standIndex, gate: occupant.gate,
                                  code: occupant.flight?.code ?? occupant.registration,
                                  stage: delayed ? "+\(occupant.flight?.delayMinutes ?? 0)m" : stage?.title ?? "Parked",
                                  systemImage: Self.symbol(stage), tone: tone)
            let above = parkTargets[occupant.standIndex] ?? current.entity.position
            list.append(HubAnchor(id: "tag\(occupant.standIndex)", position: above + [0, m.axisY + m.radius * 2 + 12, 0],
                                  kind: .tag(tag)))
        }
        // The busiest routes, and the highlighted one, labelled part-way out.
        let ranked = routeArcs.enumerated().sorted {
            $0.element.link.dailyRoundTrips != $1.element.link.dailyRoundTrips
                ? $0.element.link.dailyRoundTrips > $1.element.link.dailyRoundTrips : $0.offset < $1.offset
        }
        for (rank, item) in ranked.enumerated() {
            let link = item.element.link
            let highlighted = link.routeID == highlightedRoute
            guard rank < 8 || highlighted else { continue }
            let load = link.loadFactor.map { "\(Int(($0 * 100).rounded()))%" } ?? "new"
            let tag = HubRouteTag(routeID: link.routeID, code: link.other.raw,
                                  detail: "\(load) · \(link.dailyRoundTrips)/day", band: Self.band(link.loadFactor),
                                  highlighted: highlighted)
            let points = item.element.points
            list.append(HubAnchor(id: "route\(link.routeID.raw)", position: points[points.count * 3 / 10] + [0, 8, 0],
                                  kind: .route(tag)))
        }
        anchors = list
    }

    private static func symbol(_ stage: HubTurnaroundStage?) -> String {
        switch stage {
        case .deboarding: "figure.walk.departure"
        case .servicing: "fuelpump.fill"
        case .boarding: "figure.walk.arrival"
        case .pushback: "arrow.uturn.backward"
        case .departed: "airplane.departure"
        case nil: "parkingsign"
        }
    }

    /// Load-factor band: 0 no flights yet, 1 full (≥ 75 %), 2 fair, 3 thin
    /// (below 55 %, where the alerts start).
    static func band(_ loadFactor: Double?) -> Int {
        guard let lf = loadFactor else { return 0 }
        return lf >= 0.75 ? 1 : lf >= 0.55 ? 2 : 3
    }

    // MARK: Route fan

    /// The player's routes as arcs leaving the terminal on their real
    /// bearings (north up the screen), coloured by how full they fly, with
    /// a light for each daily round trip running out and back along them.
    private func updateRouteFan(_ links: [HubRouteLink]) {
        lastLinks = links
        let signature = links.map { "\($0.routeID.raw):\(Self.band($0.loadFactor)):\($0.dailyRoundTrips)" }
            .joined(separator: ",") + "|\(highlightedRoute?.raw ?? -1)"
        guard signature != routeSignature else { return }
        routeSignature = signature
        routeFan.children.removeAll()
        routePulses.removeAll()
        routeArcs.removeAll()
        guard !links.isEmpty else { return }
        let t = layout.terminal
        let start = SIMD3<Float>(Float(t.center.x), 26, Float(t.center.z))
        let reach = Float(min(1_800, max(900, max(layout.bounds.width, layout.bounds.depth) * 0.45)))
        var batches: [HubMaterialKey: HubMeshBatch] = [:]
        for link in links {
            let bearing = Float(link.bearing * .pi / 180)
            let dir = SIMD3<Float>(sin(bearing), 0, -cos(bearing))
            // Longer routes reach a little further out and climb higher.
            let length = reach * (0.75 + 0.25 * min(1, Float(link.distanceKm) / 6_000))
            // High and light: the arcs climb away like departures and end
            // in the air, so they never lie across the landside.
            let end = start + dir * length + [0, length * 0.1, 0]
            let control = start + dir * (length * 0.45) + [0, length * 0.55, 0]
            var points: [SIMD3<Float>] = []
            for i in 0...32 {
                let u = Float(i) / 32
                let a = (1 - u) * (1 - u), b = 2 * (1 - u) * u, c = u * u
                points.append(start * a + control * b + end * c)
            }
            let highlighted = link.routeID == highlightedRoute
            let key: HubMaterialKey = highlighted ? .routePulse : .routeArc(Self.band(link.loadFactor))
            var batch = batches.removeValue(forKey: key) ?? HubMeshBatch()
            Self.tube(&batch, points, thickness: highlighted ? 3.2 : 1.5)
            batches[key] = batch
            let arc = routeArcs.count
            routeArcs.append((link, points))
            let count = max(1, min(4, link.dailyRoundTrips))
            for k in 0..<count {
                guard let mesh = pulseMesh else { break }
                let e = ModelEntity(mesh: mesh, materials: [materials[.routePulse]])
                e.components.set(HubMaterialTag(key: .routePulse))
                e.scale = SIMD3<Float>(repeating: highlighted ? 3.4 : 2.3)
                routeFan.addChild(e)
                routePulses.append((e, arc, Float(k) / Float(count) + Float(arc) * 0.137,
                                    1 / (7 + length / 300), k % 2 == 0))
            }
        }
        for (key, batch) in batches {
            guard let mesh = batch.resource(name: "routeFan") else { continue }
            let e = ModelEntity(mesh: mesh, materials: [materials[key]])
            e.components.set(HubMaterialTag(key: key))
            routeFan.addChild(e)
        }
    }

    private lazy var pulseMesh: MeshResource? = {
        var b = HubMeshBatch()
        b.sphere(center: .zero, radius: 1, segments: 12, rings: 8)
        return b.resource(name: "routePulse")
    }()

    /// A square tube through `points`, one box per segment, each turned
    /// to its segment.
    private static func tube(_ batch: inout HubMeshBatch, _ points: [SIMD3<Float>], thickness t: Float) {
        for (a, b) in zip(points, points.dropFirst()) {
            let d = b - a
            let length = simd_length(d)
            guard length > 0.01 else { continue }
            let turn = simd_quatf(from: [1, 0, 0], to: d / length)
            batch.transform = HubMeshBatch.translation((a + b) / 2) * simd_float4x4(turn)
            batch.box(center: [0, -t / 2, 0], size: [length + t * 0.5, t, t], bottom: true)
        }
        batch.transform = matrix_identity_float4x4
    }

    private static func sample(_ points: [SIMD3<Float>], _ u: Float) -> SIMD3<Float> {
        let x = max(0, min(1, u)) * Float(points.count - 1)
        let i = min(points.count - 2, Int(x))
        let f = x - Float(i)
        return points[i] + (points[i + 1] - points[i]) * f
    }

    // MARK: Ambient traffic

    private func buildAmbientTraffic() {
        guard let runway = layout.runways.first,
              let taxi = layout.pieces.first(where: { $0.kind == .taxiway && $0.variant == 0 }) else { return }
        let rwZ = runway.thresholdA.z, taxiZ = taxi.center.z
        let west = runway.thresholdA.x, east = runway.thresholdB.x
        // The airfield circuit: approach from the west, touch down, roll
        // out, turn off onto the taxiway, taxi back west, line up and take
        // off east. Three jets spaced round it; they fade in and out far
        // out in the sky where the loop restarts.
        let circuit = HubPath([
            HubVec(west - 1_600, 460, rwZ), HubVec(west - 500, 150, rwZ), HubVec(west + 140, 0, rwZ),
            HubVec(east - 160, 0, rwZ), HubVec(east - 60, 0, (rwZ + taxiZ) / 2), HubVec(east - 60, 0, taxiZ),
            HubVec(west + 60, 0, taxiZ), HubVec(west + 60, 0, (rwZ + taxiZ) / 2), HubVec(west + 90, 0, rwZ),
            HubVec(east - 260, 0, rwZ), HubVec(east + 500, 160, rwZ), HubVec(east + 2_600, 900, rwZ),
        ])
        // Approach, flare, roll-out braking, turn off, taxi, line up,
        // take-off roll, rotate, climb.
        let speeds: [Float] = [78, 64, 30, 9, 9, 10, 9, 7, 58, 82, 92]
        let categories: [AircraftCategory] = [.narrowbody, .widebody, .regionalJet]
        let liveries: [Livery] = [.slate, .crimson, .teal]
        let lap = Float(circuit.length)
        for k in 0..<3 {
            let e = aircraftEntity(categories[k], livery: liveries[k])
            traffic.addChild(e)
            movers.append(HubMover(entity: e, path: circuit, speeds: speeds, start: Float(k) * lap / 3,
                                   style: .air, corner: 45))
        }
        // Second runway gets departures only.
        if layout.runways.count > 1 {
            let r2 = layout.runways[1]
            let dep = HubPath([HubVec(r2.thresholdA.x + 60, 0, r2.thresholdA.z), HubVec(r2.thresholdB.x - 200, 0, r2.thresholdA.z),
                               HubVec(r2.thresholdB.x + 600, 260, r2.thresholdA.z),
                               HubVec(r2.thresholdB.x + 2_600, 900, r2.thresholdA.z)])
            let e = aircraftEntity(.largeWidebody, livery: .gold)
            traffic.addChild(e)
            movers.append(HubMover(entity: e, path: dep, speeds: [55, 80, 92], start: 400, style: .air))
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
            traffic.addChild(e)
            movers.append(HubMover(entity: e, path: out, speeds: [45, 70, 78, 82, 92], start: Float(out.length) * 0.55,
                                   style: .air, corner: 120))
        }
    }

    /// Tugs, baggage trains, vans, bowsers and buses circulating on the
    /// apron's service roads — two-way loops with U-turns at the ends, so
    /// nothing ever reverses or pops (reference shot A: ~25 vehicles).
    private func buildApronTraffic() {
        let kinds: [HubModels.Vehicle] = [.baggageTrain, .serviceVan, .fuelTruck, .tug, .cateringTruck, .bus]
        let liveries: [Livery] = [.azure, .teal, .slate]
        var k = 0
        for lane in layout.serviceLanes {
            let loop = lane.roundTrip(lane: 2.4)
            let count = max(2, min(6, Int(lane.length / 45)))
            for i in 0..<count {
                let v = kinds[k % kinds.count]
                let e = vehicleEntity(v) { key in
                    key == .livery(.azure) ? .livery(liveries[k % 3]) : key
                }
                traffic.addChild(e)
                let cruise: Float = v == .baggageTrain || v == .tug ? 5 : 7
                movers.append(HubMover(entity: e, path: loop, speeds: [cruise + Float(k % 3) * 0.6],
                                       start: Float(i) / Float(count) * Float(loop.length) + Float(k * 13 % 40)))
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
            let half = (alongX ? road.size.x : road.size.z) / 2 - 12
            let atKerb = alongX && abs(road.center.z - kerbZ) < 1
            let a = alongX ? HubVec(road.center.x - half, 0.12, road.center.z) : HubVec(road.center.x, 0.12, road.center.z - half)
            let b = alongX ? HubVec(road.center.x + half, 0.12, road.center.z) : HubVec(road.center.x, 0.12, road.center.z + half)
            // Both directions as one loop, keeping right.
            let loop = HubPath([a, b]).roundTrip(lane: 3.2)
            let count = atKerb ? 5 : 2 * (Int(half / 220) + 1)
            for i in 0..<count {
                let colour = k
                // The kerb gets buses and taxis; streets get cars and vans.
                let kind: HubModels.Vehicle = atKerb ? (i % 3 == 0 ? .bus : .car) : (i % 5 == 0 ? .serviceVan : .car)
                let car = vehicleEntity(kind) { key in
                    key == .cloth(0) ? .cloth(atKerb ? 3 : [0, 1, 5, 6, 7, 3][colour % 6]) : key
                }
                traffic.addChild(car)
                let cruise: Float = atKerb ? 6 : 13 + Float(k % 4) * 1.5
                movers.append(HubMover(entity: car, path: loop, speeds: [cruise],
                                       start: Float(i) * Float(loop.length) / Float(count) + Float(k * 37 % 90)))
                k += 1
            }
        }
        // The service cart towing its tank trailer round the district's
        // streets past the first stop's gate (reference shot D): one loop,
        // the trailer a few metres behind on the same path.
        let stop = layout.serviceStops.first ?? layout.focus.district
        let near = layout.serviceRoute.points.filter { $0.distance(to: stop) < 160 }.map { HubVec($0.x, 0, $0.z) }
        let street = near.count >= 2 ? HubPath(near) : layout.serviceRoute
        let loop = street.rounded(radius: 6).roundTrip(lane: 1.6)
        for (i, v) in [HubModels.Vehicle.golfCart, .tanker].enumerated() {
            let e = vehicleEntity(v)
            traffic.addChild(e)
            movers.append(HubMover(entity: e, path: loop, speeds: [4.5],
                                   start: Float(loop.length) * 0.2 - Float(i) * 6.5, corner: 4))
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
        // Parked jets glide to where the snapshot puts them (pushback).
        for (index, target) in parkTargets {
            guard let e = parked[index]?.entity else { continue }
            let gap = target - e.position
            if simd_length_squared(gap) > 0.0001 {
                e.position += gap * min(1, dt * 1.8)
            }
        }
        // Walkers along queues: a gentle step bob, turned the way they
        // walk, fading in at the back of the queue and out at the door.
        for (k, walker) in walkers.enumerated() where walker.entity.scene != nil {
            var t = (walker.offset + time * walker.speed).truncatingRemainder(dividingBy: 1)
            if t < 0 { t += 1 }
            let s = walker.path.sample(fraction: Double(t))
            let bob = abs(sin(time * 7.5 + Float(k) * 1.7)) * 0.09
            walker.entity.position = [Float(s.position.x), Float(s.position.y) + bob, Float(s.position.z)]
            walker.entity.orientation = simd_quatf(angle: Float(s.yaw) + (walker.speed < 0 ? .pi : 0), axis: [0, 1, 0])
            let edge = min(t, 1 - t)
            let opacity = min(1, edge / 0.07)
            walker.entity.components.set(OpacityComponent(opacity: opacity * opacity * (3 - 2 * opacity)))
        }
        walkers.removeAll { $0.entity.parent?.parent == nil }
        // Route lights run out along their arcs and back, easing in and
        // out of the terminal and fading at both ends.
        if showsRouteFan {
            for pulse in routePulses {
                let points = routeArcs[pulse.arc].points
                var u = (pulse.offset + time * pulse.speed).truncatingRemainder(dividingBy: 1)
                if u < 0 { u += 1 }
                let eased = u * u * (3 - 2 * u) * 0.35 + u * 0.65
                pulse.entity.position = Self.sample(points, pulse.outbound ? eased : 1 - eased)
                let edge = min(u, 1 - u)
                pulse.entity.components.set(OpacityComponent(opacity: min(1, edge / 0.08)))
            }
        }
        // Pulse rings round the focused jet's engine: stacked, tilted,
        // growing with an ease-out and fading as they go (reference shot B).
        if let index = focusStand, let current = parked[index] {
            let engine = current.entity.convert(position: pulseEngine, to: nil)
            let tilt = current.entity.orientation * simd_quatf(angle: 0.16, axis: [1, 0, 0])
            for (k, ring) in pulse.enumerated() {
                let phase = (time * 0.4 + Float(k) / Float(pulse.count)).truncatingRemainder(dividingBy: 1)
                let eased = 1 - (1 - phase) * (1 - phase) * (1 - phase)
                let size = 3 + 9 * eased
                ring.position = engine + [0, Float(k) * 0.5 - 0.3, 0]
                ring.orientation = tilt
                ring.scale = [size, 1, size]
                let fadeIn = min(1, phase / 0.12)
                ring.components.set(OpacityComponent(opacity: fadeIn * (1 - phase) * (1 - phase) * 1.4))
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
