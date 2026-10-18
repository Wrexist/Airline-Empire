import RealityKit
import Metal
import simd
import AirlineEmpireCore

/// People who walk: passengers queueing to the door, ground crew pacing
/// round the jet, travellers crossing the hall.
///
/// A crowd is one mesh per material, like the static batches, but its
/// vertices are rewritten every frame from each figure's template
/// (`LowLevelMesh`, iOS 18), so a hundred walkers stay a handful of draws.
/// Legs and arms swing by shearing the template's limbs about the hip and
/// the shoulder — no skeleton is needed at this scale — and the body bobs
/// with each step.
@available(iOS 18.0, *)
@MainActor
final class HubCrowd {
    enum Motion {
        /// Along `path` and round again, shrinking away at either end (into
        /// the aircraft door, out at the terminal). A negative speed walks
        /// it backwards. Metres per second, world scale.
        case loop(HubPath, offset: Float, speed: Float)
        /// To the end of `path` and back, pausing at each end.
        case pace(HubPath, offset: Float, speed: Float, pause: Float)
        /// Between random spots round `points`, pausing at each.
        case wander([SIMD3<Float>], spread: Float, speed: Float, seed: UInt64)
    }

    struct Walker {
        /// Index into the crowd's figures.
        let figure: Int
        let scale: Float
        let cloth: Int
        let skin: Int
        let motion: Motion
    }

    /// A figure's geometry per material, prepared for walking: the stance
    /// straightened, and a weight per vertex for how far it swings with the
    /// legs and with the arms.
    private struct Template {
        let key: HubMaterialKey
        let positions: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
        let indices: [UInt32]
        let leg: [Float]
        let arm: [Float]
    }

    private struct Segment {
        let walker: Int
        let part: Int
        /// First vertex of this walker's copy in the batch's mesh.
        let first: Int
    }

    private struct Batch {
        let mesh: LowLevelMesh
        let segments: [Segment]
    }

    private struct State {
        var position: SIMD3<Float> = .zero
        var yaw: Float = 0
        var phase: Float = 0
        /// 0 standing … 1 in full stride.
        var stride: Float = 0
        /// 0 gone … 1 full size: loop walkers shrink at the path's ends.
        var size: Float = 1
        var distance: Float = 0
        var direction: Float = 1
        var pause: Float = 0
        var target: SIMD3<Float> = .zero
        var rng = SplitMix(seed: 1)
    }

    let entity = Entity()
    private let figures: [[Template]]
    private let walkers: [Walker]
    /// Each walker's path length, measured once rather than every frame.
    private let lengths: [Float]
    private var states: [State]
    private var batches: [Batch] = []
    private var frame = 0
    /// Time since the last pose, carried over the frames that skip one.
    private var pending: Float = 0

    /// `figures` are raw figures (`HubModels.rawPerson`), facing +x.
    init(figures raw: [[(HubMaterialKey, HubMeshBatch)]], walkers: [Walker], materials: HubMaterials, name: String) {
        figures = raw.map(Self.prepare)
        self.walkers = walkers
        lengths = walkers.map { walker in
            switch walker.motion {
            case .loop(let path, _, _), .pace(let path, _, _, _): Float(path.length)
            case .wander: 0
            }
        }
        states = walkers.enumerated().map { index, walker in Self.start(walker, index: index) }
        build(materials: materials, name: name)
        write()
    }

    /// Where `walker` stands at the start, as a matrix for a static batch:
    /// the people a small device keeps still rather than animating.
    static func startPose(_ walker: Walker, index: Int) -> float4x4 {
        let s = start(walker, index: index)
        var yaw = s.yaw
        if case .loop(_, _, let v) = walker.motion, v < 0 { yaw += .pi }
        return HubMeshBatch.translation(s.position) * HubMeshBatch.yaw(yaw)
            * HubMeshBatch.scale(SIMD3<Float>(repeating: walker.scale))
    }

    var isEmpty: Bool { walkers.isEmpty }

    // MARK: Templates

    private static func prepare(_ parts: [(HubMaterialKey, HubMeshBatch)]) -> [Template] {
        let all = parts.flatMap { $0.1.positions }
        let height = max(0.5, all.map(\.y).max() ?? 1.75)
        let u = height / 1.75
        // The body's midline from the head, which nothing hangs beside.
        let head = all.filter { $0.y > 1.5 * u }
        let x0 = head.isEmpty ? 0 : head.reduce(0) { $0 + $1.x } / Float(head.count)
        let z0 = head.isEmpty ? 0 : head.reduce(0) { $0 + $1.z } / Float(head.count)
        let hip = 0.93 * u, shoulder = 1.4 * u
        // Each foot's offset from the midline, so a figure modelled mid-stride
        // walks from a straight stance.
        func foot(_ side: Float) -> Float {
            let feet = all.filter { $0.y < 0.25 * u && side * ($0.z - z0) > 0.03 && abs($0.z - z0) < 0.2 }
            return feet.isEmpty ? 0 : feet.reduce(0) { $0 + $1.x } / Float(feet.count) - x0
        }
        let feet: [Float] = [foot(-1), foot(1)]
        // A hand that holds luggage (something low and wide of the legs) keeps still.
        func holds(_ side: Float) -> Bool {
            all.contains { $0.y < 0.7 * u && side * ($0.z - z0) > 0.22 }
        }
        let still: [Bool] = [holds(-1), holds(1)]
        return parts.map { key, batch in
            var positions = batch.positions
            var leg = [Float](repeating: 0, count: positions.count)
            var arm = [Float](repeating: 0, count: positions.count)
            for i in positions.indices {
                let p = positions[i]
                let dz = p.z - z0, side: Float = dz < 0 ? -1 : 1, s = side < 0 ? 0 : 1
                if p.y < hip && abs(dz) < 0.2 * u {
                    let reach = min(1, max(0, (hip - p.y) / (hip - 0.1 * u)))
                    let across = min(1, max(0, (abs(dz) - 0.02 * u) / (0.04 * u)))
                    positions[i].x -= feet[s] * reach * across
                    leg[i] = side * across * (hip - p.y) / hip
                }
                if p.y > 0.78 * u && p.y < shoulder + 0.02 && abs(dz) > 0.18 * u && abs(dz) < 0.45 * u && !still[s] {
                    arm[i] = side * min(1, (shoulder - p.y) / (0.6 * u))
                }
            }
            return Template(key: key, positions: positions, normals: batch.normals, indices: batch.indices,
                            leg: leg, arm: arm)
        }
    }

    private static func remap(_ key: HubMaterialKey, _ walker: Walker) -> HubMaterialKey {
        switch key {
        case .cloth: .cloth(walker.cloth)
        case .skin: .skin(walker.skin)
        default: key
        }
    }

    // MARK: Meshes

    private struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
    }

    private func build(materials: HubMaterials, name: String) {
        var groups: [HubMaterialKey: [(walker: Int, part: Int)]] = [:]
        var order: [HubMaterialKey] = []
        for (w, walker) in walkers.enumerated() where walker.figure < figures.count {
            for (p, part) in figures[walker.figure].enumerated() {
                let key = Self.remap(part.key, walker)
                if groups[key] == nil { order.append(key) }
                groups[key, default: []].append((w, p))
            }
        }
        let bounds = reach()
        for key in order {
            guard let members = groups[key] else { continue }
            var vertexCount = 0, indexCount = 0
            var segments: [Segment] = []
            for m in members {
                let t = figures[walkers[m.walker].figure][m.part]
                segments.append(Segment(walker: m.walker, part: m.part, first: vertexCount))
                vertexCount += t.positions.count
                indexCount += t.indices.count
            }
            guard vertexCount > 0, indexCount > 0 else { continue }
            var d = LowLevelMesh.Descriptor()
            d.vertexCapacity = vertexCount
            d.indexCapacity = indexCount
            d.indexType = .uint32
            d.vertexAttributes = [
                LowLevelMesh.Attribute(semantic: .position, format: .float3,
                                       offset: MemoryLayout<Vertex>.offset(of: \.position) ?? 0),
                LowLevelMesh.Attribute(semantic: .normal, format: .float3,
                                       offset: MemoryLayout<Vertex>.offset(of: \.normal) ?? 16),
            ]
            d.vertexLayouts = [LowLevelMesh.Layout(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride)]
            guard let mesh = try? LowLevelMesh(descriptor: d) else { continue }
            mesh.withUnsafeMutableIndices { raw in
                let out = raw.bindMemory(to: UInt32.self)
                var at = 0
                for s in segments {
                    let t = figures[walkers[s.walker].figure][s.part]
                    let base = UInt32(s.first)
                    for i in t.indices {
                        out[at] = i + base
                        at += 1
                    }
                }
            }
            mesh.parts.replaceAll([LowLevelMesh.Part(indexCount: indexCount, topology: .triangle, bounds: bounds)])
            guard let resource = try? MeshResource(from: mesh) else { continue }
            let model = ModelEntity(mesh: resource, materials: [materials[key]])
            model.name = name
            model.components.set(HubMaterialTag(key: key))
            entity.addChild(model)
            batches.append(Batch(mesh: mesh, segments: segments))
        }
    }

    /// Everywhere the crowd can walk, for culling.
    private func reach() -> BoundingBox {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        var tallest: Float = 4
        for walker in walkers {
            tallest = max(tallest, walker.scale * 2.2)
            let points: [SIMD3<Float>]
            var pad: Float = 2
            switch walker.motion {
            case .loop(let path, _, _), .pace(let path, _, _, _):
                points = path.points.map { SIMD3(Float($0.x), Float($0.y), Float($0.z)) }
            case .wander(let spots, let spread, _, _):
                points = spots
                pad += spread
            }
            for p in points {
                lo = simd_min(lo, p - SIMD3(pad, 0, pad))
                hi = simd_max(hi, p + SIMD3(pad, 0, pad))
            }
        }
        guard lo.x <= hi.x else { return BoundingBox(min: .zero, max: .one) }
        return BoundingBox(min: lo - [0, 1, 0], max: hi + [0, tallest + 1, 0])
    }

    // MARK: Motion

    private static func start(_ walker: Walker, index: Int) -> State {
        var s = State()
        switch walker.motion {
        case .loop(let path, let offset, _):
            s.distance = offset * Float(path.length)
            let here = path.sample(at: Double(s.distance))
            s.position = Self.f(here.position)
            s.yaw = Float(here.yaw)
            s.stride = 1
        case .pace(let path, let offset, _, _):
            s.distance = offset * Float(path.length)
            s.direction = index % 2 == 0 ? 1 : -1
            let here = path.sample(at: Double(s.distance))
            s.position = Self.f(here.position)
            s.yaw = Float(here.yaw)
        case .wander(let spots, let spread, _, let seed):
            s.rng = SplitMix(seed: seed &+ UInt64(index) &* 977)
            s.position = Self.pick(spots, spread: spread, &s.rng)
            s.target = Self.pick(spots, spread: spread, &s.rng)
            s.yaw = Float(s.rng.unit() * 6.28)
            s.pause = Float(s.rng.unit() * 4)
        }
        s.phase = Float(index) * 1.37
        return s
    }

    private static func f(_ v: HubVec) -> SIMD3<Float> { SIMD3(Float(v.x), Float(v.y), Float(v.z)) }

    private static func pick(_ spots: [SIMD3<Float>], spread: Float, _ rng: inout SplitMix) -> SIMD3<Float> {
        guard !spots.isEmpty else { return .zero }
        let spot = spots[min(spots.count - 1, Int(rng.unit() * Double(spots.count)))]
        return spot + SIMD3(Float(rng.unit() - 0.5) * spread * 2, 0, Float(rng.unit() - 0.5) * spread)
    }

    private static func wrap(_ a: Float) -> Float {
        var x = a.truncatingRemainder(dividingBy: 2 * .pi)
        if x > .pi { x -= 2 * .pi }
        if x < -.pi { x += 2 * .pi }
        return x
    }

    private static func turn(_ yaw: inout Float, to wanted: Float, rate: Float, dt: Float) {
        yaw += max(-rate * dt, min(rate * dt, wrap(wanted - yaw)))
    }

    /// Moves everyone on and rewrites the meshes, at most thirty times a
    /// second — a walk reads the same at half the frame rate, and the
    /// rewrite is CPU work per vertex — and less often when `detail` is
    /// above 2 (the camera is far enough out that people are a few pixels
    /// tall). A hidden crowd (the terminal cutaway, off the scene) stands
    /// still and costs nothing, and picks up where it was when it shows.
    func update(_ dt: Float, detail: Int = 1) {
        guard !walkers.isEmpty else { return }
        guard entity.scene != nil, entity.isEnabledInHierarchy else {
            pending = 0
            return
        }
        pending += dt
        frame += 1
        guard frame % max(2, detail) == 0 else { return }
        let elapsed = min(pending, 0.25)
        pending = 0
        for i in states.indices { step(i, elapsed) }
        write()
    }

    private func step(_ i: Int, _ dt: Float) {
        let walker = walkers[i]
        var s = states[i]
        var speed: Float = 0
        switch walker.motion {
        case .loop(let path, _, let v):
            let length = lengths[i]
            guard length > 0.1 else { break }
            s.distance += v * dt
            if s.distance >= length { s.distance -= length }
            if s.distance < 0 { s.distance += length }
            let here = path.sample(at: Double(s.distance))
            s.position = Self.f(here.position)
            Self.turn(&s.yaw, to: Float(here.yaw) + (v < 0 ? .pi : 0), rate: 5, dt: dt)
            let edge = min(s.distance, length - s.distance) / 3
            let grow = min(1, max(0, edge))
            s.size = grow * grow * (3 - 2 * grow)
            speed = abs(v)
        case .pace(let path, _, let v, let pause):
            let length = lengths[i]
            guard length > 0.1 else { break }
            if s.pause > 0 {
                s.pause -= dt
                if s.pause <= 0 { s.direction = -s.direction }
            } else {
                s.distance += s.direction * v * dt
                if s.distance >= length || s.distance <= 0 {
                    s.distance = min(length, max(0, s.distance))
                    s.pause = pause * (0.6 + 0.8 * Float(s.rng.unit()))
                }
                speed = v
            }
            let here = path.sample(at: Double(s.distance))
            s.position = Self.f(here.position)
            // While paused, turn round ready to walk back.
            let heading = s.pause > 0 ? -s.direction : s.direction
            Self.turn(&s.yaw, to: Float(here.yaw) + (heading < 0 ? .pi : 0), rate: 3.5, dt: dt)
        case .wander(let spots, let spread, let v, _):
            if s.pause > 0 {
                s.pause -= dt
                break
            }
            let to = s.target - s.position
            let gap = simd_length(SIMD2(to.x, to.z))
            if gap < 0.8 {
                s.pause = 1.5 + Float(s.rng.unit()) * 5
                s.target = Self.pick(spots, spread: spread, &s.rng)
                break
            }
            let wanted = atan2(-to.z, to.x)
            Self.turn(&s.yaw, to: wanted, rate: 3, dt: dt)
            // Slow down to turn, rather than walking sideways.
            let facing = max(0.15, cos(Self.wrap(wanted - s.yaw)))
            speed = v * facing
            s.position += SIMD3(cos(s.yaw), 0, -sin(s.yaw)) * speed * dt
        }
        let walking: Float = speed > 0.05 ? 1 : 0
        s.stride += (walking - s.stride) * min(1, dt * 6)
        // One stride (two steps) per ~1.4 m of a person's own height.
        s.phase += dt * speed / (1.4 * max(0.1, walker.scale)) * 2 * .pi
        if s.phase > 1_000 { s.phase -= 2 * .pi * 159 }
        states[i] = s
    }

    private func write() {
        for batch in batches {
            batch.mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
                let out = raw.bindMemory(to: Vertex.self)
                for segment in batch.segments {
                    let walker = walkers[segment.walker]
                    let s = states[segment.walker]
                    let t = figures[walker.figure][segment.part]
                    let k = walker.scale * s.size
                    let cy = cos(s.yaw), sy = sin(s.yaw)
                    let c = cy * k, sn = sy * k
                    let swing = sin(s.phase) * s.stride
                    let legSwing = 0.24 * swing, armSwing = -0.16 * swing
                    let bob = (1 - abs(cos(s.phase))) * 0.05 * walker.scale * s.stride
                    let base = s.position + SIMD3(0, bob, 0)
                    t.positions.withUnsafeBufferPointer { ps in
                        t.normals.withUnsafeBufferPointer { ns in
                            t.leg.withUnsafeBufferPointer { legs in
                                t.arm.withUnsafeBufferPointer { arms in
                                    let hasNormals = ns.count == ps.count
                                    for i in 0..<ps.count {
                                        let p = ps[i]
                                        let x = p.x + legs[i] * legSwing + arms[i] * armSwing
                                        let n = hasNormals ? ns[i] : SIMD3<Float>(0, 1, 0)
                                        out[segment.first + i] = Vertex(
                                            position: SIMD3(base.x + c * x + sn * p.z, base.y + k * p.y,
                                                            base.z - sn * x + c * p.z),
                                            normal: SIMD3(cy * n.x + sy * n.z, n.y, -sy * n.x + cy * n.z))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
