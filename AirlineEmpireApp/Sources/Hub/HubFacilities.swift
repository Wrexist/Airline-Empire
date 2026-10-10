import RealityKit
import UIKit
import simd
import AirlineEmpireCore

/// The player's facility buildings (docs/HUB_HANDOFF.md §0c,
/// docs/HUB_PROGRESSION_PLAN.md §6): one entity per site, built for its
/// current level, with the construction site on it while a level is going
/// up — hoarding, groundworks, a crane and frame, cladding — and a reveal
/// when it opens: scaffold and crane, the new building rising, a pulse on
/// the ground. Every level looks different, so an upgrade is something you
/// can see from the overview; a plot of a later era waits behind a barrier.
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
    private var built: [HubFacilityKind: (state: SiteState, entity: Entity)] = [:]
    private var jobs: [Job] = []
    /// Cranes and diggers on the construction sites, animated each frame.
    private var cranes: [HubFacilityKind: [Entity]] = [:]
    private var diggers: [HubFacilityKind: [Entity]] = [:]
    /// The translucent next level shown while its card is open.
    private var ghost: (kind: HubFacilityKind, level: Int, entity: Entity)?
    private var time: Float = 0

    /// What a site shows: the building, and the works on it.
    struct SiteState: Equatable {
        var level: Int
        var livery: Livery
        /// The level going up and how far it has got.
        var building: Int?
        var stage: HubConstructionStage?
        var locked: Bool
        var inCheck: AircraftCategory?
    }

    /// One reveal in progress.
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

    /// How long a reveal takes, seconds.
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
        case .hangar: level == 0 ? 4 : level == 1 ? 22 : 28
        case .crewBase: level == 0 ? 4 : 27
        }
    }

    /// Height for a site's tag: above the crane while it builds.
    static func tagHeight(_ offer: HubUpgradeOffer) -> Float {
        let standing = height(offer.kind, level: offer.level)
        guard let build = offer.construction else { return standing }
        return max(standing, height(offer.kind, level: build.level) + (offer.kind == .lounge ? 6 : 12))
    }

    // MARK: Levels

    /// Builds or rebuilds each site for `offers`. A level that went up plays
    /// the reveal; the first call, a new construction stage and a level that
    /// went down swap in place.
    func apply(offers: [HubUpgradeOffer], livery: Livery) {
        for site in layout.facilitySites {
            let offer = offers.first { $0.kind == site.kind }
            let state = SiteState(level: offer?.level ?? 0, livery: livery,
                                  building: offer?.construction?.level, stage: offer?.construction?.stage,
                                  locked: offer?.isLocked ?? false, inCheck: offer?.inCheck.first)
            let current = built[site.kind]
            guard current?.state != state else { continue }
            let entity = building(site, state: state)
            parent(site.kind).addChild(entity)
            if let current, state.level > current.state.level {
                startJob(site, level: state.level, old: current.entity, new: entity)
            } else {
                current?.entity.removeFromParent()
            }
            built[site.kind] = (state, entity)
            if let ghost, ghost.kind == site.kind, state.level >= ghost.level || state.building != nil {
                showBlueprint(nil)
            }
        }
    }

    /// The reveal is playing on `kind`'s site.
    func isRevealing(_ kind: HubFacilityKind) -> Bool { jobs.contains { $0.kind == kind } }

    /// Plays the reveal again for what stands on `kind`'s site: a building
    /// that opened while the player was away.
    func replay(_ kind: HubFacilityKind) {
        guard let site = layout.site(kind), let current = built[kind], current.state.level > 0 else { return }
        let entity = building(site, state: current.state)
        parent(kind).addChild(entity)
        startJob(site, level: current.state.level, old: current.entity, new: entity)
        built[kind] = (current.state, entity)
    }

    /// Shows `level` of `kind` as a translucent blueprint on its site, or
    /// hides it (nil).
    func showBlueprint(_ target: (kind: HubFacilityKind, level: Int)?) {
        if let ghost, let target, ghost.kind == target.kind, ghost.level == target.level { return }
        ghost?.entity.removeFromParent()
        ghost = nil
        guard let target, let site = layout.site(target.kind), let current = built[target.kind] else { return }
        var state = current.state
        state.level = target.level
        state.building = nil; state.stage = nil; state.locked = false
        let entity = building(site, state: state, interactive: false)
        entity.name = "blueprint-\(target.kind.rawValue)"
        entity.components.set(OpacityComponent(opacity: 0.4))
        parent(target.kind).addChild(entity)
        ghost = (target.kind, target.level, entity)
    }

    // MARK: Reveal

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
        let (sw, sd) = Self.scaffoldSize(site.kind, w: w, d: d)
        let scaffold = entity(Self.scaffold(sw: sw, sd: sd, h: h), name: "scaffold")
        scaffold.position = base
        scaffold.scale = [1, 0.01, 1]

        let (crane, jib) = self.crane(height: h + 14, reach: max(sw, sd) * 0.9)
        crane.position = base + [sw / 2 + 3, 0, -sd / 2 - 3]
        crane.scale = [1, 0.01, 1]

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

    private static func scaffoldSize(_ kind: HubFacilityKind, w: Float, d: Float) -> (Float, Float) {
        switch kind {
        case .lounge: (w * 0.8, d * 0.75)
        case .groundServices: (w * 0.7, d * 0.62)
        case .hangar: (w * 0.9, d * 0.86)
        case .crewBase: (w * 0.8, d * 0.5)
        }
    }

    /// Yellow poles and grey rails round a building `h` tall.
    private static func scaffold(sw: Float, sd: Float, h: Float, from: Float = 0) -> [HubMaterialKey: HubMeshBatch] {
        var parts: [HubMaterialKey: HubMeshBatch] = [:]
        let poles: Float = max(5, max(sw, sd) / 14)
        with(&parts, .hiVis) { b in
            var x = -sw / 2
            while x <= sw / 2 + 0.01 {
                for z in [-sd / 2, sd / 2] { b.box(center: [x, from, z], size: [0.3, h + 1.5, 0.3]) }
                x += poles
            }
            var z = -sd / 2
            while z <= sd / 2 + 0.01 {
                for x in [-sw / 2, sw / 2] { b.box(center: [x, from, z], size: [0.3, h + 1.5, 0.3]) }
                z += poles
            }
        }
        with(&parts, .darkMetal) { b in
            var y: Float = from + 2.2
            while y < from + h + 1.4 {
                b.box(center: [0, y, -sd / 2], size: [sw, 0.18, 0.18])
                b.box(center: [0, y, sd / 2], size: [sw, 0.18, 0.18])
                b.box(center: [-sw / 2, y, 0], size: [0.18, 0.18, sd])
                b.box(center: [sw / 2, y, 0], size: [0.18, 0.18, sd])
                y += 2.4
            }
        }
        return parts
    }

    /// A tower crane: a yellow lattice mast and a slewing jib with its
    /// counterweight and hook.
    private func crane(height craneHeight: Float, reach: Float) -> (Entity, Entity) {
        var mast: [HubMaterialKey: HubMeshBatch] = [:]
        Self.with(&mast, .hiVis) { $0.box(center: .zero, size: [1.3, craneHeight, 1.3]) }
        Self.with(&mast, .darkMetal) { $0.box(center: [0, 0, 0], size: [3.2, 0.8, 3.2]) }
        let crane = entity(mast, name: "crane")
        var arm: [HubMaterialKey: HubMeshBatch] = [:]
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
        return (crane, jib)
    }

    private func finish(_ job: Job) {
        job.old?.removeFromParent()
        for e in [job.scaffold, job.crane, job.ring] { e.removeFromParent() }
        job.new.scale = .one
        job.new.components.remove(OpacityComponent.self)
    }

    /// Advances the reveals and the works; true when a reveal finished this
    /// frame.
    @discardableResult
    func update(_ dt: Float) -> Bool {
        time += dt
        // The works never stop: jibs slew, diggers dig, the blueprint breathes.
        for (kind, list) in cranes {
            for (k, jib) in list.enumerated() {
                let phase = Float(kind.rawValue.count) + Float(k) * 1.7
                jib.orientation = simd_quatf(angle: sin(time * 0.22 + phase) * 1.3, axis: [0, 1, 0])
            }
        }
        for list in diggers.values {
            for (k, arm) in list.enumerated() {
                arm.orientation = simd_quatf(angle: -0.35 + sin(time * 0.9 + Float(k)) * 0.3, axis: [0, 0, 1])
            }
        }
        if let ghost {
            ghost.entity.components.set(OpacityComponent(opacity: 0.32 + 0.12 * sin(time * 2.4)))
        }
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

    private func building(_ site: HubFacilitySite, state: SiteState, interactive: Bool = true) -> Entity {
        let w = Float(site.footprint.width), d = Float(site.footprint.depth)
        let level = state.level, livery = state.livery
        let e: Entity
        // The apron (or the airport) is on the side towards the centre line.
        let apronSide: Float = site.center.x > 0 ? -1 : 1
        switch site.kind {
        case .lounge: e = entity(Self.lounge(w: w, d: d, level: level, livery: livery), name: "lounge")
        case .groundServices: e = depot(w: w, d: d, level: level, livery: livery, apronSide: apronSide)
        case .hangar: e = hangar(w: w, d: d, level: level, livery: livery, inCheck: state.inCheck)
        case .crewBase: e = crewBase(w: w, d: d, level: level, livery: livery, apronSide: apronSide)
        }
        let holder = Entity()
        holder.name = "facility-\(site.kind.rawValue)"
        holder.position = Self.f(site.center)
        holder.addChild(e)
        if level == 0 && site.kind != .lounge && site.kind != .groundServices {
            holder.addChild(entity(Self.plotBoard(w: w, d: d, livery: livery, locked: state.locked), name: "board"))
        }
        if let target = state.building, let stage = state.stage {
            holder.addChild(works(site, target: target, stage: stage, livery: livery, standing: level))
        } else if interactive {
            cranes[site.kind] = nil
            diggers[site.kind] = nil
        }
        guard interactive else { return holder }
        // Tappable over the whole lot.
        let h = max(Self.height(site.kind, level: level), state.building.map { Self.height(site.kind, level: $0) } ?? 0)
        holder.components.set(CollisionComponent(shapes: [
            .generateBox(size: [w, max(4, h), d]).offsetBy(translation: [0, max(4, h) / 2, 0]),
        ]))
        return holder
    }

    // MARK: Works

    /// The construction site on a lot at a stage: hoarding in the airline's
    /// colours from the first day, then diggers and spoil, then a crane over
    /// a rising frame, then cladding under scaffold.
    private func works(_ site: HubFacilitySite, target: Int, stage: HubConstructionStage, livery: Livery,
                       standing: Int) -> Entity {
        let kind = site.kind
        let w = Float(site.footprint.width), d = Float(site.footprint.depth)
        let h = Self.height(kind, level: target)
        let roof = kind == .lounge
        // An upgrade builds beside or over what stands; a new building on
        // the whole lot.
        let (sw, sd) = Self.scaffoldSize(kind, w: w, d: d)
        var p: [HubMaterialKey: HubMeshBatch] = [:]
        // Hoarding: panels in the livery with a white cap, a gap for the gate.
        let hw = roof ? w * 0.92 : w - 3, hd = roof ? d * 0.88 : d - 3
        let fence: Float = roof ? 1.6 : 2.6
        Self.with(&p, .livery(livery)) { b in
            b.box(center: [-hw / 2, 0, 0], size: [0.3, fence, hd])
            b.box(center: [hw / 2, 0, 0], size: [0.3, fence, hd])
            b.box(center: [0, 0, hd / 2], size: [hw, fence, 0.3])
            let gate = min(14, hw * 0.25)
            b.box(center: [-(hw + gate) / 4, 0, -hd / 2], size: [(hw - gate) / 2, fence, 0.3])
            b.box(center: [(hw + gate) / 4, 0, -hd / 2], size: [(hw - gate) / 2, fence, 0.3])
        }
        Self.with(&p, .white) { b in
            b.box(center: [-hw / 2, fence, 0], size: [0.4, 0.3, hd])
            b.box(center: [hw / 2, fence, 0], size: [0.4, 0.3, hd])
            b.box(center: [0, fence, hd / 2], size: [hw, 0.3, 0.4])
        }
        if standing == 0 && !roof {
            // The lot itself, scraped to earth.
            Self.with(&p, .houseWood) { $0.box(center: .zero, size: [hw - 1, 0.1, hd - 1]) }
        }
        if stage >= .groundworks && !roof {
            // Spoil heaps and a site cabin.
            Self.with(&p, .houseWood) { b in
                b.sphere(center: [-hw * 0.3, 0, hd * 0.3], radius: 4, scale: [1.4, 0.45, 1], segments: 10, rings: 5)
                b.sphere(center: [hw * 0.32, 0, hd * 0.28], radius: 3, scale: [1.2, 0.5, 1.1], segments: 10, rings: 5)
            }
            Self.with(&p, .white) { $0.roundedBox(center: [hw / 2 - 6, 0, -hd / 2 + 4], size: [8, 2.8, 3], bevel: 0.2) }
            Self.with(&p, .windowDark) { $0.box(center: [hw / 2 - 6, 1.1, -hd / 2 + 2.45], size: [5, 0.9, 0.1]) }
        }
        if stage >= .frame {
            // The frame: columns on a grid up to the height reached, and a
            // slab every floor.
            let reach: Float = stage == .frame ? 0.6 : 1.0
            let top = h * reach
            Self.with(&p, .darkMetal) { b in
                let nx = max(2, Int(sw / 9)), nz = max(2, Int(sd / 9))
                for i in 0...nx {
                    for j in 0...nz {
                        let x = -sw / 2 + sw * Float(i) / Float(nx), z = -sd / 2 + sd * Float(j) / Float(nz)
                        b.box(center: [x, 0, z], size: [0.45, top, 0.45])
                    }
                }
            }
            Self.with(&p, .concrete) { b in
                var y: Float = 3.6
                while y < top - 0.5 {
                    b.box(center: [0, y, 0], size: [sw, 0.35, sd])
                    y += 3.6
                }
            }
        }
        if stage == .cladding {
            // Walls going on from the bottom, under scaffold.
            Self.with(&p, kind == .lounge ? .glass : .building) { b in
                b.box(center: [0, 0, -sd / 2], size: [sw, h * 0.7, 0.3])
                b.box(center: [-sw / 2, 0, 0], size: [0.3, h * 0.7, sd])
                b.box(center: [sw / 2, 0, 0], size: [0.3, h * 0.55, sd])
                b.box(center: [0, 0, sd / 2], size: [sw, h * 0.45, 0.3])
            }
            for (key, batch) in Self.scaffold(sw: sw + 1.5, sd: sd + 1.5, h: h) {
                var merged = p.removeValue(forKey: key) ?? HubMeshBatch()
                merged.append(batch, matrix: matrix_identity_float4x4)
                p[key] = merged
            }
        }
        let site = entity(p, name: "works")
        var batcher = HubStaticBatcher()
        var craneList: [Entity] = []
        var diggerList: [Entity] = []
        if stage >= .groundworks && !roof {
            // An excavator at the dig and a tipper by the gate.
            let (digger, arm) = excavator(livery: livery)
            digger.position = [-hw * 0.12, 0, hd * 0.12]
            digger.orientation = simd_quatf(angle: 0.6, axis: [0, 1, 0])
            site.addChild(digger)
            diggerList.append(arm)
            batcher.add(models.rawVehicle(.tanker), matrix: HubMeshBatch.translation([hw * 0.18, 0, -hd / 2 + 7])
                        * HubMeshBatch.yaw(.pi / 2))
        }
        if stage >= .frame {
            let (crane, jib) = self.crane(height: h + (roof ? 8 : 14), reach: max(sw, sd) * 0.85)
            crane.position = [sw / 2 + 2.5, 0, sd / 2 + 2.5]
            site.addChild(crane)
            craneList.append(jib)
        }
        if stage < .frame && !roof {
            // Survey pegs and a parked van before the steel arrives.
            batcher.add(models.rawVehicle(.serviceVan), matrix: HubMeshBatch.translation([-hw * 0.3, 0, -hd / 2 + 6]))
        }
        site.addChild(batcher.entity(materials: materials, name: "worksVehicles"))
        cranes[kind] = craneList.isEmpty ? nil : craneList
        diggers[kind] = diggerList.isEmpty ? nil : diggerList
        return site
    }

    /// A yellow excavator; the returned arm pitches as it digs.
    private func excavator(livery: Livery) -> (Entity, Entity) {
        var body: [HubMaterialKey: HubMeshBatch] = [:]
        Self.with(&body, .darkMetal) { $0.box(center: .zero, size: [5.2, 1.0, 3.4]) }
        Self.with(&body, .hiVis) { b in
            b.roundedBox(center: [0, 1.0, 0], size: [3.4, 1.6, 3.0], bevel: 0.2)
            b.roundedBox(center: [-0.6, 2.6, 0.7], size: [1.6, 1.6, 1.4], bevel: 0.15)
        }
        Self.with(&body, .windowDark) { $0.box(center: [-0.6, 2.9, 0.7], size: [1.7, 0.9, 1.2]) }
        let e = entity(body, name: "excavator")
        var boom: [HubMaterialKey: HubMeshBatch] = [:]
        Self.with(&boom, .hiVis) { b in
            b.box(center: [2.4, -0.25, 0], size: [4.8, 0.5, 0.6])
            b.box(center: [4.6, -2.2, 0], size: [0.5, 2.4, 0.5])
        }
        Self.with(&boom, .darkMetal) { $0.box(center: [4.6, -2.8, 0], size: [1.1, 0.8, 1.0]) }
        let arm = entity(boom, name: "boom")
        arm.position = [0.9, 2.2, -0.6]
        e.addChild(arm)
        return (e, arm)
    }

    /// The board on an empty plot: the airline's colour when it can be
    /// built, grey behind a barrier when its era has not come.
    private static func plotBoard(w: Float, d: Float, livery: Livery, locked: Bool) -> [HubMaterialKey: HubMeshBatch] {
        var p: [HubMaterialKey: HubMeshBatch] = [:]
        let at = SIMD3<Float>(0, 0, -d / 2 + 4)
        with(&p, .darkMetal) { b in
            b.box(center: at + [-3.6, 0, 0], size: [0.3, 5.4, 0.3])
            b.box(center: at + [3.6, 0, 0], size: [0.3, 5.4, 0.3])
        }
        with(&p, locked ? .buildingShade : .livery(livery)) { $0.roundedBox(center: at + [0, 2.6, 0], size: [8.4, 2.8, 0.35], bevel: 0.12) }
        with(&p, .white) { $0.box(center: at + [0, 3.3, -0.2], size: [6, 0.5, 0.05]) }
        if locked {
            // A barrier across the front of the plot.
            with(&p, .hiVis) { b in
                var x = -w / 2 + 3
                while x < w / 2 - 2 {
                    b.box(center: [x, 0.9, -d / 2 + 1.5], size: [2.2, 0.35, 0.25])
                    x += 4.4
                }
            }
            with(&p, .white) { b in
                var x = -w / 2 + 5.2
                while x < w / 2 - 2 {
                    b.box(center: [x, 0.9, -d / 2 + 1.5], size: [2.2, 0.35, 0.25])
                    x += 4.4
                }
            }
            with(&p, .cone) { b in
                for x in stride(from: -w / 2 + 2, through: w / 2 - 2, by: 8) {
                    b.cylinder(base: [x, 0, -d / 2 + 1.5], radius: 0.4, topRadius: 0.05, height: 0.9, segments: 8)
                }
            }
        }
        return p
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

    /// The maintenance hangar, doors to the taxiway (−z) and a glazed gable
    /// towards the terminal, so the jet in for a check shows from the
    /// overview. Level 0 is a fenced pad; 1 a line-maintenance hall in your
    /// colours; 2 a bigger heavy-maintenance hall with a workshop annex,
    /// skylights and docking stands.
    private func hangar(w: Float, d: Float, level: Int, livery: Livery, inCheck: AircraftCategory?) -> Entity {
        var p: [HubMaterialKey: HubMeshBatch] = [:]
        guard level > 0 else {
            Self.with(&p, .concrete) { $0.box(center: .zero, size: [w - 4, 0.1, d - 4]) }
            Self.with(&p, .marking) { b in
                var x = -w / 2 + 4
                while x < w / 2 - 4 {
                    for z in [-d / 2 + 2, d / 2 - 2] { b.box(center: [x, 0.1, z], size: [2.6, 0.04, 0.45]) }
                    x += 5
                }
            }
            return entity(p, name: "hangarPlot")
        }
        let heavy = level >= 2
        let annex: Float = heavy ? 14 : 0
        let hw = min(w - 10, heavy ? 96 : 76) - annex, hd = min(d - 12, heavy ? 72 : 58)
        let wall: Float = heavy ? 22 : 17
        let cx = -annex / 2, back = hd / 2 - 4
        let front = back - hd
        // Floor, and the apron pad out to the lot's edge with a lead-in line.
        Self.with(&p, .concreteLight) { $0.box(center: [cx, 0, back - hd / 2], size: [hw, 0.12, hd]) }
        Self.with(&p, .concrete) { $0.box(center: [cx, 0, (front - d / 2) / 2], size: [hw + 8, 0.1, front + d / 2]) }
        Self.with(&p, .marking) { $0.box(center: [cx, 0.13, (front - d / 2) / 2], size: [0.5, 0.04, front + d / 2 - 1]) }
        // Side walls, the glazed gable at the back, the header over the doors.
        Self.with(&p, .building) { b in
            b.box(center: [cx - hw / 2, 0, back - hd / 2], size: [0.8, wall, hd])
            b.box(center: [cx + hw / 2, 0, back - hd / 2], size: [0.8, wall, hd])
            b.box(center: [cx, 0, back], size: [hw, 4, 0.8])
        }
        Self.with(&p, .glass) { $0.box(center: [cx, 4, back], size: [hw - 1, wall - 4, 0.5]) }
        Self.with(&p, .white) { b in
            var x = cx - hw / 2 + 6
            while x < cx + hw / 2 - 1 {
                b.box(center: [x, 4, back + 0.1], size: [0.4, wall - 4, 0.7])
                x += 6
            }
            // Door posts and the folded door leaves at either end.
            for side: Float in [-1, 1] {
                b.box(center: [cx + side * (hw / 2 - 1.5), 0, front], size: [3, wall, 1.2])
            }
        }
        Self.with(&p, .darkMetal) { b in
            for side: Float in [-1, 1] {
                for k in 0..<3 {
                    b.box(center: [cx + side * (hw / 2 - 4.5 - Float(k) * 1.1), 0, front + 0.6 + Float(k) * 0.9],
                          size: [0.8, wall - 2.5, 0.5])
                }
            }
        }
        Self.with(&p, .livery(livery)) { $0.box(center: [cx, wall - 4, front], size: [hw, 4, 1.4], top: false) }
        Self.with(&p, .liveryAccent(livery)) { b in
            b.box(center: [cx - hw / 2 - 0.45, wall - 3, back - hd / 2], size: [0.2, 1.4, hd * 0.9])
            b.box(center: [cx + hw / 2 + 0.45, wall - 3, back - hd / 2], size: [0.2, 1.4, hd * 0.9])
        }
        // A shallow vault: three stepped slabs, rounded.
        Self.with(&p, .roof) { b in
            b.roundedBox(center: [cx, wall, back - hd / 2], size: [hw + 1.6, 1.2, hd + 1.6], bevel: 0.4)
            b.roundedBox(center: [cx, wall + 1.2, back - hd / 2], size: [hw * 0.72, 1.6, hd + 1.2], bevel: 0.6)
            b.roundedBox(center: [cx, wall + 2.8, back - hd / 2], size: [hw * 0.4, 1.4, hd + 0.8], bevel: 0.6)
        }
        if heavy {
            Self.with(&p, .skylight) { b in
                for k in [-1, 1] as [Float] {
                    b.box(center: [cx + k * hw * 0.25, wall + 1.25, back - hd / 2], size: [3, 0.4, hd * 0.8])
                }
            }
            // Workshop annex on the far side, two floors of offices.
            let ax = cx + hw / 2 + annex / 2
            Self.with(&p, .buildingShade) { $0.roundedBox(center: [ax, 0, back - hd * 0.45], size: [annex, 9, hd * 0.8], bevel: 0.4) }
            Self.with(&p, .windowDark) { b in
                for y: Float in [2, 5.6] { b.box(center: [ax + annex / 2 + 0.05, y, back - hd * 0.45], size: [0.1, 1.5, hd * 0.7]) }
            }
            Self.with(&p, .roof) { $0.roundedBox(center: [ax, 9, back - hd * 0.45], size: [annex + 0.8, 0.5, hd * 0.8 + 0.8], bevel: 0.2) }
        }
        // Docking stands either side of the bay, taller in the heavy hall.
        Self.with(&p, .hiVis) { b in
            for side: Float in [-1, 1] {
                let x = cx + side * hw * 0.3
                b.box(center: [x, 0, back - hd * 0.45], size: [hw * 0.12, heavy ? 5.5 : 3.6, 3])
                b.box(center: [x, heavy ? 5.5 : 3.6, back - hd * 0.45], size: [hw * 0.14, 0.3, 3.4])
            }
            if heavy { b.box(center: [cx, 0, back - 6], size: [6, 9, 4]) }
        }
        let hall = entity(p, name: "hangar")
        if let inCheck {
            // The aircraft in for its check, towed in nose first.
            let m = HubModels.metrics(inCheck)
            let fit = min(1, (hd - 8) / m.length, (hw - 6) / m.span)
            let jet = models.make(["aircraft_\(inCheck.rawValue)"], models.aircraft(inCheck), materials: materials) { key in
                switch key {
                case .livery: .livery(livery)
                case .liveryAccent: .liveryAccent(livery)
                default: key
                }
            }
            jet.scale = [fit, fit, fit]
            jet.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])
            jet.position = [cx, 0.12, back - hd / 2 + 2]
            jet.name = "hangarJet"
            hall.addChild(jet)
        }
        return hall
    }

    /// The crew base: a hotel for the crews, its lobby and bus bay facing
    /// the street to the terminal, a crew bus in the airline's colours
    /// waiting. Level 0 is a marked lawn.
    private func crewBase(w: Float, d: Float, level: Int, livery: Livery, apronSide: Float) -> Entity {
        var p: [HubMaterialKey: HubMeshBatch] = [:]
        Self.with(&p, .grass) { $0.box(center: .zero, size: [w, 0.2, d]) }
        guard level > 0 else {
            Self.with(&p, .marking) { b in
                var x = -w / 2 + 3
                while x < w / 2 - 3 {
                    for z in [-d / 2 + 2, d / 2 - 2] { b.box(center: [x, 0.2, z], size: [2, 0.04, 0.4]) }
                    x += 4
                }
            }
            return entity(p, name: "crewPlot")
        }
        // A slab long along the street, seven storeys.
        let bw: Float = 16, bd: Float = min(d - 14, 38), floors = 7
        let storey: Float = 3.3
        let bh = Float(floors) * storey + 1.5
        let bx = -apronSide * (w / 2 - bw / 2 - 4)
        let face = bx + apronSide * (bw / 2)
        Self.with(&p, .building) { $0.roundedBox(center: [bx, 0.2, 0], size: [bw, bh, bd], bevel: 0.5) }
        Self.with(&p, .windowDark) { b in
            for f in 1..<floors {
                let y = 0.2 + Float(f) * storey + 0.9
                b.box(center: [bx - bw / 2 - 0.05, y, 0], size: [0.1, 1.3, bd - 2])
                b.box(center: [bx + bw / 2 + 0.05, y, 0], size: [0.1, 1.3, bd - 2])
                b.box(center: [bx, y, -bd / 2 - 0.05], size: [bw - 2, 1.3, 0.1])
                b.box(center: [bx, y, bd / 2 + 0.05], size: [bw - 2, 1.3, 0.1])
            }
        }
        Self.with(&p, .glass) { $0.box(center: [face + apronSide * 0.3, 0.2, 0], size: [0.6, storey - 0.4, bd * 0.55]) }
        Self.with(&p, .roof) { $0.roundedBox(center: [bx, 0.2 + bh, 0], size: [bw + 1, 0.6, bd + 1], bevel: 0.25) }
        Self.with(&p, .livery(livery)) { $0.box(center: [bx, bh - 1.4, 0], size: [bw + 0.3, 1.4, bd + 0.3], top: false) }
        Self.with(&p, .liveryAccent(livery)) { $0.roundedBox(center: [bx, bh + 0.8, 0], size: [1.2, 2.2, bd * 0.45], bevel: 0.3) }
        // The lobby canopy, and the bus bay along the street side.
        Self.with(&p, .white) { b in
            b.box(center: [face + apronSide * 3, 3.2, 0], size: [6, 0.4, bd * 0.4])
            for dz: Float in [-bd * 0.17, bd * 0.17] { b.box(center: [face + apronSide * 5.6, 0.2, dz], size: [0.35, 3.2, 0.35]) }
        }
        let bayX = apronSide * (w / 2 - 5.5)
        Self.with(&p, .asphalt) { $0.box(center: [bayX, 0.2, 0], size: [9, 0.06, d - 4]) }
        Self.with(&p, .marking) { $0.box(center: [bayX, 0.27, 0], size: [0.3, 0.03, d - 8]) }
        // Trees at the ends of the lawn, and two flags by the door.
        Self.with(&p, .trunk) { b in
            for z: Float in [-d / 2 + 4, d / 2 - 4] { b.box(center: [bx, 0.2, z], size: [0.6, 2.4, 0.6]) }
        }
        Self.with(&p, .tree(2)) { b in
            for z: Float in [-d / 2 + 4, d / 2 - 4] { b.sphere(center: [bx, 4, z], radius: 2.8, segments: 8, rings: 5) }
        }
        let flags = face + apronSide * 8.5
        Self.with(&p, .darkMetal) { b in
            for z: Float in [-bd * 0.3, -bd * 0.3 + 4] { b.box(center: [flags, 0.2, z], size: [0.2, 9, 0.2]) }
        }
        Self.with(&p, .livery(livery)) { b in
            for z: Float in [-bd * 0.3, -bd * 0.3 + 4] { b.box(center: [flags, 7.6, z + 1.1], size: [0.08, 1.3, 2.2]) }
        }
        let e = entity(p, name: "crewBase")
        var fleet = HubStaticBatcher()
        let own: (HubMaterialKey) -> HubMaterialKey = { key in
            switch key {
            case .livery: .livery(livery)
            case .liveryAccent: .liveryAccent(livery)
            default: key
            }
        }
        // Models run along +x; the bus waits along the street.
        fleet.add(models.rawVehicle(.bus), matrix: HubMeshBatch.translation([bayX, 0.26, 4]) * HubMeshBatch.yaw(.pi / 2),
                  remap: own)
        e.addChild(fleet.entity(materials: materials, name: "crewBus"))
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
