import RealityKit
import UIKit
import simd
import AirlineEmpireCore

/// The player's facility buildings (docs/HUB_HANDOFF.md §0c): one entity
/// per site, built for its current level, and a construction sequence —
/// scaffold, crane, the new building rising, a pulse on the ground — when a
/// level goes up. Every level looks different, so an upgrade is something
/// you can see from the overview.
@available(iOS 18.0, *)
@MainActor
final class HubFacilityYard {
    let root = Entity()
    /// What stands on the terminal roof: hidden with the roof in the
    /// terminal cutaway.
    let roofRoot = Entity()
    private let layout: HubLayout
    private let models: HubModels
    private let materials: HubMaterials
    private var built: [HubFacilityKind: (level: Int, livery: Livery, entity: Entity)] = [:]
    private var jobs: [Job] = []

    /// One construction in progress.
    private struct Job {
        let kind: HubFacilityKind
        let old: Entity?
        let new: Entity
        let scaffold: Entity
        let crane: Entity
        let jib: Entity
        let ring: Entity
        let ringSize: Float
        var t: Float = 0
    }

    /// How long a construction takes, seconds.
    static let buildTime: Float = 4.4

    init(layout: HubLayout, models: HubModels, materials: HubMaterials) {
        self.layout = layout
        self.models = models
        self.materials = materials
        root.name = "facilities"
        root.addChild(roofRoot)
    }

    private func parent(_ kind: HubFacilityKind) -> Entity { kind == .lounge ? roofRoot : root }

    /// The tallest the building on `kind`'s site gets, for tags and taps.
    static func height(_ kind: HubFacilityKind, level: Int) -> Float {
        switch kind {
        case .lounge: level == 0 ? 2 : level == 1 ? 6.2 : 10.4
        case .groundServices: level == 0 ? 4 : level == 1 ? 10 : 12.5
        }
    }

    // MARK: Levels

    /// Builds or rebuilds each site for `levels`. A level that went up plays
    /// the construction; the first call and a level that went down swap in
    /// place.
    func apply(levels: [HubFacilityKind: Int], livery: Livery) {
        for site in layout.facilitySites {
            let level = levels[site.kind] ?? 0
            let current = built[site.kind]
            guard current?.level != level || current?.livery != livery else { continue }
            let entity = building(site, level: level, livery: livery)
            parent(site.kind).addChild(entity)
            if let current, level > current.level {
                startJob(site, level: level, old: current.entity, new: entity)
            } else {
                current?.entity.removeFromParent()
            }
            built[site.kind] = (level, livery, entity)
        }
    }

    func isBuilding(_ kind: HubFacilityKind) -> Bool { jobs.contains { $0.kind == kind } }

    // MARK: Construction

    private func startJob(_ site: HubFacilitySite, level: Int, old: Entity, new: Entity) {
        jobs.removeAll { job in
            guard job.kind == site.kind else { return false }
            finish(job)
            return true
        }
        let r = site.footprint
        let w = Float(r.width), d = Float(r.depth)
        let h = Self.height(site.kind, level: level)
        let base = Self.f(site.center)
        // Scaffold: yellow poles and grey rails round the new building.
        var parts: [HubMaterialKey: HubMeshBatch] = [:]
        let sw = w * (site.kind == .lounge ? 0.8 : 0.7), sd = d * (site.kind == .lounge ? 0.75 : 0.62)
        let poles: Float = 5
        Self.with(&parts, .hiVis) { b in
            var x = -sw / 2
            while x <= sw / 2 + 0.01 {
                for z in [-sd / 2, sd / 2] { b.box(center: [x, 0, z], size: [0.3, h + 1.5, 0.3]) }
                x += poles
            }
            var z = -sd / 2
            while z <= sd / 2 + 0.01 {
                for x in [-sw / 2, sw / 2] { b.box(center: [x, 0, z], size: [0.3, h + 1.5, 0.3]) }
                z += poles
            }
        }
        Self.with(&parts, .darkMetal) { b in
            var y: Float = 2.2
            while y < h + 1.4 {
                b.box(center: [0, y, -sd / 2], size: [sw, 0.18, 0.18])
                b.box(center: [0, y, sd / 2], size: [sw, 0.18, 0.18])
                b.box(center: [-sw / 2, y, 0], size: [0.18, 0.18, sd])
                b.box(center: [sw / 2, y, 0], size: [0.18, 0.18, sd])
                y += 2.4
            }
        }
        let scaffold = entity(parts, name: "scaffold")
        scaffold.position = base
        scaffold.scale = [1, 0.01, 1]

        // Crane: a yellow lattice mast at one corner and a slewing jib.
        let craneHeight = h + 14
        var mast: [HubMaterialKey: HubMeshBatch] = [:]
        Self.with(&mast, .hiVis) { $0.box(center: .zero, size: [1.3, craneHeight, 1.3]) }
        Self.with(&mast, .darkMetal) { $0.box(center: [0, 0, 0], size: [3.2, 0.8, 3.2]) }
        let crane = entity(mast, name: "crane")
        crane.position = base + [sw / 2 + 3, 0, -sd / 2 - 3]
        crane.scale = [1, 0.01, 1]
        var arm: [HubMaterialKey: HubMeshBatch] = [:]
        let reach = max(sw, sd) * 0.9
        Self.with(&arm, .hiVis) {
            $0.box(center: [-reach / 2 + 2, 0, 0], size: [reach + 4, 1.0, 1.0])
            $0.box(center: [0, 1.0, 0], size: [1.6, 2.4, 1.6])
        }
        Self.with(&arm, .darkMetal) {
            $0.box(center: [6, -1.2, 0], size: [3.4, 2.4, 2.2])
            $0.box(center: [-reach * 0.7, -6, 0], size: [0.12, 6, 0.12])
            $0.box(center: [-reach * 0.7, -7.2, 0], size: [1.0, 1.2, 1.0])
        }
        let jib = entity(arm, name: "jib")
        jib.position = [0, craneHeight, 0]
        crane.addChild(jib)

        // The finishing pulse on the ground.
        let ring = models.entity(models.ring(), materials: materials)
        ring.position = base + [0, 0.25, 0]
        ring.components.set(OpacityComponent(opacity: 0))
        let ringSize = max(w, d) * 1.1

        new.scale = [1, 0.02, 1]
        new.components.set(OpacityComponent(opacity: 0))
        for e in [scaffold, crane, ring] { parent(site.kind).addChild(e) }
        jobs.append(Job(kind: site.kind, old: old, new: new, scaffold: scaffold, crane: crane, jib: jib,
                        ring: ring, ringSize: ringSize))
    }

    private func finish(_ job: Job) {
        job.old?.removeFromParent()
        for e in [job.scaffold, job.crane, job.ring] { e.removeFromParent() }
        job.new.scale = .one
        job.new.components.remove(OpacityComponent.self)
    }

    /// Advances the constructions; true when one finished this frame.
    @discardableResult
    func update(_ dt: Float) -> Bool {
        guard !jobs.isEmpty else { return false }
        for i in jobs.indices {
            jobs[i].t += dt
            let job = jobs[i], t = job.t
            // 0–0.8 s: scaffold and crane go up; the old building fades.
            let up = Self.easeOut(Self.phase(t, 0, 0.8))
            let down = Self.easeIn(Self.phase(t, 3.1, 3.9))
            let rig = max(0.01, up * (1 - down))
            job.scaffold.scale = [1, rig, 1]
            job.crane.scale = [1, rig, 1]
            job.scaffold.components.set(OpacityComponent(opacity: 1 - down))
            job.crane.components.set(OpacityComponent(opacity: 1 - down))
            job.old?.components.set(OpacityComponent(opacity: 1 - Self.phase(t, 0.2, 0.9)))
            // The jib slews back and forth as the building goes up.
            job.jib.orientation = simd_quatf(angle: sin(t * 0.9) * 1.1 + 0.6, axis: [0, 1, 0])
            // 0.7–3.1 s: the building rises with a little overshoot.
            let rise = Self.easeOutBack(Self.phase(t, 0.7, 3.1))
            job.new.scale = [1, max(0.02, rise), 1]
            job.new.components.set(OpacityComponent(opacity: min(1, Self.phase(t, 0.7, 1.2))))
            // 3.3–4.4 s: a pulse spreads from the site.
            let p = Self.phase(t, 3.3, Self.buildTime)
            let s = job.ringSize * (0.5 + Self.easeOut(p))
            job.ring.scale = [s, 1, s]
            job.ring.components.set(OpacityComponent(opacity: p > 0 && p < 1 ? (1 - p) * (1 - p) * 1.2 : 0))
        }
        let done = jobs.filter { $0.t >= Self.buildTime }
        for job in done { finish(job) }
        jobs.removeAll { $0.t >= Self.buildTime }
        return !done.isEmpty
    }

    private static func phase(_ t: Float, _ a: Float, _ b: Float) -> Float { max(0, min(1, (t - a) / (b - a))) }
    private static func easeOut(_ x: Float) -> Float { 1 - (1 - x) * (1 - x) * (1 - x) }
    private static func easeIn(_ x: Float) -> Float { x * x * x }
    private static func easeOutBack(_ x: Float) -> Float {
        let c1: Float = 1.2, c3 = c1 + 1
        let y = x - 1
        return 1 + c3 * y * y * y + c1 * y * y
    }

    // MARK: Buildings

    private func building(_ site: HubFacilitySite, level: Int, livery: Livery) -> Entity {
        let w = Float(site.footprint.width), d = Float(site.footprint.depth)
        let e: Entity
        switch site.kind {
        case .lounge: e = entity(Self.lounge(w: w, d: d, level: level, livery: livery), name: "lounge")
        case .groundServices:
            // The apron is on the side towards the airport's centre line.
            let apronSide: Float = site.center.x > 0 ? -1 : 1
            e = depot(w: w, d: d, level: level, livery: livery, apronSide: apronSide)
        }
        let holder = Entity()
        holder.name = "facility-\(site.kind.rawValue)"
        holder.position = Self.f(site.center)
        holder.addChild(e)
        // Tappable over the whole lot.
        let h = Self.height(site.kind, level: level)
        holder.components.set(CollisionComponent(shapes: [
            .generateBox(size: [w, max(4, h), d]).offsetBy(translation: [0, max(4, h) / 2, 0]),
        ]))
        return holder
    }

    /// The lounge pavilion on the terminal roof. Level 0 is a marked-out
    /// site among planters; 1 a glass pavilion with an airline fascia and
    /// seating; 2 a two-tier flagship with a terrace, parasols and lights.
    private static func lounge(w: Float, d: Float, level: Int, livery: Livery) -> [HubMaterialKey: HubMeshBatch] {
        var p: [HubMaterialKey: HubMeshBatch] = [:]
        // Planters at the corners, always.
        with(&p, .buildingShade) { b in
            for sx: Float in [-1, 1] {
                for sz: Float in [-1, 1] {
                    b.roundedBox(center: [sx * (w / 2 - 2), 0, sz * (d / 2 - 2)], size: [3, 1.1, 3], bevel: 0.25)
                }
            }
        }
        with(&p, .tree(1)) { b in
            for sx: Float in [-1, 1] {
                for sz: Float in [-1, 1] {
                    b.sphere(center: [sx * (w / 2 - 2), 1.9, sz * (d / 2 - 2)], radius: 1.4, segments: 8, rings: 5)
                }
            }
        }
        guard level > 0 else {
            // A dashed outline: the site, waiting.
            with(&p, .marking) { b in
                var x = -w / 2 + 5
                while x < w / 2 - 5 {
                    for z in [-d / 2 + 4, d / 2 - 4] { b.box(center: [x, 0.02, z], size: [2.4, 0.05, 0.5]) }
                    x += 4
                }
                var z = -d / 2 + 6
                while z < d / 2 - 6 {
                    for x in [-w / 2 + 4, w / 2 - 4] { b.box(center: [x, 0.02, z], size: [0.5, 0.05, 2.4]) }
                    z += 4
                }
            }
            return p
        }
        let gw = w * (level == 1 ? 0.6 : 0.74), gd = d * (level == 1 ? 0.58 : 0.66)
        let gh: Float = 4.6
        // Deck, glass walls with white mullions, roof slab with the fascia.
        with(&p, .white) { b in
            b.roundedBox(center: .zero, size: [w * 0.9, 0.4, d * 0.86], bevel: 0.15)
            var x = -gw / 2
            while x <= gw / 2 + 0.01 {
                for z in [-gd / 2, gd / 2] { b.box(center: [x, 0.4, z], size: [0.35, gh, 0.35]) }
                x += 3.2
            }
        }
        with(&p, .glass) { $0.box(center: [0, 0.4, 0], size: [gw, gh, gd]) }
        with(&p, .roof) { $0.roundedBox(center: [0, 0.4 + gh, 0], size: [gw + 1.4, 0.55, gd + 1.4], bevel: 0.2) }
        with(&p, .livery(livery)) { $0.box(center: [0, 0.4 + gh - 0.65, 0], size: [gw + 1.5, 0.7, gd + 1.5], top: false) }
        // Seating inside, in the airline's accent and neutral cloth.
        with(&p, .cloth(5)) { b in
            var x = -gw / 2 + 2.5
            while x < gw / 2 - 2 {
                b.roundedBox(center: [x, 0.4, -gd * 0.18], size: [1.6, 0.8, 1.1], bevel: 0.15)
                b.roundedBox(center: [x, 0.4, gd * 0.18], size: [1.6, 0.8, 1.1], bevel: 0.15)
                x += 3.2
            }
        }
        with(&p, .liveryAccent(livery)) { $0.roundedBox(center: [0, 0.4, 0], size: [gw * 0.3, 1.0, 1.4], bevel: 0.2) }
        // Railing round the deck.
        with(&p, .white) { b in
            b.box(center: [0, 1.4, -d * 0.43], size: [w * 0.9, 0.12, 0.12])
            b.box(center: [0, 1.4, d * 0.43], size: [w * 0.9, 0.12, 0.12])
            b.box(center: [-w * 0.45, 1.4, 0], size: [0.12, 0.12, d * 0.86])
            b.box(center: [w * 0.45, 1.4, 0], size: [0.12, 0.12, d * 0.86])
        }
        guard level > 1 else { return p }
        // Flagship: an upper tier, a timber terrace with parasols, and a
        // string of lights round the deck that glows after dusk.
        let uw = gw * 0.5, ud = gd * 0.62
        let ux = -gw * 0.22
        let top = 0.4 + gh + 0.55
        with(&p, .glass) { $0.box(center: [ux, top, 0], size: [uw, 3.6, ud]) }
        with(&p, .roof) { $0.roundedBox(center: [ux, top + 3.6, 0], size: [uw + 1.2, 0.5, ud + 1.2], bevel: 0.2) }
        with(&p, .livery(livery)) { $0.box(center: [ux, top + 3.6 - 0.55, 0], size: [uw + 1.3, 0.6, ud + 1.3], top: false) }
        with(&p, .houseWood) { $0.box(center: [gw * 0.22, top, 0], size: [gw * 0.42, 0.25, gd * 0.7]) }
        for (k, z) in [-gd * 0.2, gd * 0.2].enumerated() {
            let x = gw * 0.22
            with(&p, .darkMetal) { $0.box(center: [x, top, z], size: [0.12, 2.4, 0.12]) }
            with(&p, .cloth(k == 0 ? 3 : 1)) { $0.cylinder(base: [x, top + 2.2, z], radius: 1.8, topRadius: 0.05, height: 0.8, segments: 10) }
        }
        with(&p, .lamp) { b in
            var x = -w * 0.43
            while x <= w * 0.43 {
                for z in [-d * 0.43, d * 0.43] { b.sphere(center: [x, 1.7, z], radius: 0.22, segments: 6, rings: 4) }
                x += 2.4
            }
        }
        return p
    }

    /// The ground-services depot. Level 0 is the shared handler's corner:
    /// a cabin and two grey vehicles. Level 1 is your own shed in your
    /// colours with a liveried fleet in painted bays; level 2 a bigger shed
    /// with solar panels, chargers and an electric fleet.
    private func depot(w: Float, d: Float, level: Int, livery: Livery, apronSide: Float) -> Entity {
        var p: [HubMaterialKey: HubMeshBatch] = [:]
        // The lot: a concrete pad with a painted edge and a low fence.
        Self.with(&p, .concreteLight) { $0.box(center: .zero, size: [w, 0.12, d]) }
        Self.with(&p, .marking) { b in
            b.box(center: [0, 0.12, -d / 2 + 1], size: [w - 2, 0.03, 0.4])
            b.box(center: [0, 0.12, d / 2 - 1], size: [w - 2, 0.03, 0.4])
            b.box(center: [w / 2 - 1, 0.12, 0], size: [0.4, 0.03, d - 2])
            b.box(center: [-w / 2 + 1, 0.12, 0], size: [0.4, 0.03, d - 2])
        }
        Self.with(&p, .darkMetal) { b in
            // Fence on the three sides away from the apron.
            let back = -apronSide * w / 2
            b.box(center: [back, 1.2, 0], size: [0.14, 0.14, d])
            b.box(center: [0, 1.2, -d / 2], size: [w, 0.14, 0.14])
            b.box(center: [0, 1.2, d / 2], size: [w, 0.14, 0.14])
            var t = -d / 2
            while t <= d / 2 { b.box(center: [back, 0, t], size: [0.2, 1.8, 0.2]); t += 6 }
            var s = -w / 2
            while s <= w / 2 {
                b.box(center: [s, 0, -d / 2], size: [0.2, 1.8, 0.2])
                b.box(center: [s, 0, d / 2], size: [0.2, 1.8, 0.2])
                s += 6
            }
        }
        var fleet = HubStaticBatcher()
        let shedX = -apronSide * w * 0.24
        let bayX = apronSide * w * 0.2
        let faceApron: Float = apronSide > 0 ? 0 : .pi
        if level == 0 {
            Self.with(&p, .buildingShade) { $0.roundedBox(center: [shedX, 0.12, -d * 0.25], size: [12, 3.2, 6], bevel: 0.3) }
            Self.with(&p, .windowDark) { $0.box(center: [shedX + apronSide * 6.05, 1.2, -d * 0.25], size: [0.1, 1.2, 3.5]) }
            let grey: (HubMaterialKey) -> HubMaterialKey = { key in
                switch key {
                case .livery, .liveryAccent: .livery(.slate)
                default: key
                }
            }
            for (k, v) in [HubModels.Vehicle.tug, .serviceVan].enumerated() {
                let at = SIMD3<Float>(bayX, 0.12, -d * 0.15 + Float(k) * 12)
                fleet.add(models.rawVehicle(v), matrix: HubMeshBatch.translation(at) * HubMeshBatch.yaw(faceApron), remap: grey)
            }
        } else {
            let sw: Float = level == 1 ? 40 : 54, sd: Float = level == 1 ? 26 : 32, sh: Float = level == 1 ? 9 : 11
            let center = SIMD3<Float>(shedX, 0.12, 0)
            Self.with(&p, .building) { $0.roundedBox(center: center, size: [sd, sh, sw], bevel: 0.5) }
            Self.with(&p, .roof) { $0.roundedBox(center: center + [0, sh, 0], size: [sd + 1.2, 0.7, sw + 1.2], bevel: 0.3) }
            Self.with(&p, .livery(livery)) { $0.box(center: center + [0, sh - 1.4, 0], size: [sd + 0.3, 1.2, sw + 0.3], top: false) }
            // Roll-up doors on the apron face.
            Self.with(&p, .darkMetal) { b in
                for i in 0..<(level == 1 ? 3 : 4) {
                    let z = -sw / 2 + sw * (Float(i) + 0.5) / Float(level == 1 ? 3 : 4)
                    b.box(center: [shedX + apronSide * (sd / 2 + 0.05), 0.12, z], size: [0.2, sh * 0.62, sw * 0.18])
                }
            }
            // Painted bays and the fleet in the airline's colours.
            let bays = level == 1 ? 6 : 10
            Self.with(&p, .marking) { b in
                for i in 0...(bays / 2) {
                    let z = -d * 0.4 + Float(i) * (d * 0.8) / Float(bays / 2)
                    b.box(center: [bayX, 0.13, z], size: [w * 0.34, 0.03, 0.3])
                }
            }
            let kinds: [HubModels.Vehicle] = level == 1
                ? [.tug, .beltLoader, .serviceVan, .baggageTrain, .cateringTruck, .fuelTruck]
                : [.tug, .tug, .beltLoader, .serviceVan, .baggageTrain, .cateringTruck, .fuelTruck, .tug, .beltLoader, .serviceVan]
            let own: (HubMaterialKey) -> HubMaterialKey = { key in
                switch key {
                case .livery: .livery(livery)
                case .liveryAccent: .liveryAccent(livery)
                default: key
                }
            }
            for (k, v) in kinds.enumerated() {
                let row = Float(k / 2), col: Float = k % 2 == 0 ? -1 : 1
                let z = -d * 0.4 + (row + 0.5) * (d * 0.8) / Float(bays / 2)
                let at = SIMD3<Float>(bayX + col * w * 0.08, 0.12, z)
                fleet.add(models.rawVehicle(v), matrix: HubMeshBatch.translation(at) * HubMeshBatch.yaw(faceApron), remap: own)
            }
            if level >= 2 {
                // Solar panels on the roof, chargers beside the bays, and a
                // wash bay canopy.
                Self.with(&p, .windowDark) { b in
                    var z = -sw / 2 + 3
                    while z < sw / 2 - 2 {
                        b.box(center: center + [0, sh + 0.75, z], size: [sd - 3, 0.25, 4])
                        z += 5
                    }
                }
                Self.with(&p, .kioskScreen) { b in
                    for i in 0..<(bays / 2) {
                        let z = -d * 0.4 + (Float(i) + 0.5) * (d * 0.8) / Float(bays / 2)
                        b.box(center: [bayX - apronSide * w * 0.16, 0.12, z], size: [0.5, 1.6, 0.5])
                    }
                }
                let wash = SIMD3<Float>(bayX, 0.12, d * 0.36)
                Self.with(&p, .white) { b in
                    for dx: Float in [-5, 5] { for dz: Float in [-3, 3] { b.box(center: wash + [dx, 0, dz], size: [0.4, 5, 0.4]) } }
                }
                Self.with(&p, .roof) { $0.roundedBox(center: wash + [0, 5, 0], size: [12, 0.5, 8], bevel: 0.2) }
            }
        }
        let e = entity(p, name: "depot")
        let vehicles = fleet.entity(materials: materials, name: "depotFleet")
        e.addChild(vehicles)
        return e
    }

    // MARK: Helpers

    private static func with(_ parts: inout [HubMaterialKey: HubMeshBatch], _ key: HubMaterialKey,
                             _ body: (inout HubMeshBatch) -> Void) {
        var batch = parts.removeValue(forKey: key) ?? HubMeshBatch()
        body(&batch)
        parts[key] = batch
    }

    private func entity(_ parts: [HubMaterialKey: HubMeshBatch], name: String) -> Entity {
        let root = Entity()
        root.name = name
        for (key, batch) in parts {
            guard let mesh = batch.resource(name: name) else { continue }
            let model = ModelEntity(mesh: mesh, materials: [materials[key]])
            model.components.set(HubMaterialTag(key: key))
            root.addChild(model)
        }
        return root
    }

    private static func f(_ v: HubVec) -> SIMD3<Float> { SIMD3(Float(v.x), Float(v.y), Float(v.z)) }
}
