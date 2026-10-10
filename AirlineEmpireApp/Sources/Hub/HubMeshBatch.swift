import RealityKit
import simd

/// Accumulates many small solids into one mesh (docs/HUB_VIEW_3D.md §7).
///
/// RealityKit draws one call per model entity, so 400 trees as 400 entities
/// is 400 draws; as one batch it is one. Everything static and repeated —
/// lane dashes, trees, cars, walls, markings — goes through here. Shapes are
/// generated rather than loaded because `generateCylinder`/`generateCone`
/// need iOS 18 and the app's floor is 17.
struct HubMeshBatch {
    private(set) var positions: [SIMD3<Float>] = []
    private(set) var normals: [SIMD3<Float>] = []
    private(set) var uvs: [SIMD2<Float>] = []
    private(set) var indices: [UInt32] = []

    var isEmpty: Bool { indices.isEmpty }
    var triangleCount: Int { indices.count / 3 }

    /// The transform applied to everything added after it is set.
    var transform = matrix_identity_float4x4

    @MainActor
    func resource(name: String = "batch") -> MeshResource? {
        guard !isEmpty else { return nil }
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffers.Positions(positions)
        d.normals = MeshBuffers.Normals(normals)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        d.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [d])
    }

    // MARK: Primitive emitters

    private mutating func vertex(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ uv: SIMD2<Float>) -> UInt32 {
        let wp = transform * SIMD4<Float>(p, 1)
        let wn = transform * SIMD4<Float>(n, 0)
        positions.append(SIMD3(wp.x, wp.y, wp.z))
        normals.append(simd_normalize(SIMD3(wn.x, wn.y, wn.z)))
        uvs.append(uv)
        return UInt32(positions.count - 1)
    }

    /// A flat quad, counter-clockwise seen from the side `n` points to.
    mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                       normal n: SIMD3<Float>, uv: (SIMD2<Float>, SIMD2<Float>) = (.zero, .one)) {
        let i0 = vertex(a, n, SIMD2(uv.0.x, uv.0.y))
        let i1 = vertex(b, n, SIMD2(uv.1.x, uv.0.y))
        let i2 = vertex(c, n, SIMD2(uv.1.x, uv.1.y))
        let i3 = vertex(d, n, SIMD2(uv.0.x, uv.1.y))
        indices += [i0, i1, i2, i0, i2, i3]
    }

    /// An axis-aligned box in the current transform, base at `center.y`.
    mutating func box(center c: SIMD3<Float>, size s: SIMD3<Float>, yaw: Float = 0, top: Bool = true,
                      bottom: Bool = false) {
        let saved = transform
        transform = transform * Self.translation(c) * Self.yaw(yaw)
        let x = s.x / 2, z = s.z / 2, h = s.y
        let p000 = SIMD3<Float>(-x, 0, -z), p100 = SIMD3<Float>(x, 0, -z)
        let p101 = SIMD3<Float>(x, 0, z), p001 = SIMD3<Float>(-x, 0, z)
        let p010 = SIMD3<Float>(-x, h, -z), p110 = SIMD3<Float>(x, h, -z)
        let p111 = SIMD3<Float>(x, h, z), p011 = SIMD3<Float>(-x, h, z)
        if top { quad(p011, p111, p110, p010, normal: [0, 1, 0]) }
        if bottom { quad(p000, p100, p101, p001, normal: [0, -1, 0]) }
        quad(p001, p101, p111, p011, normal: [0, 0, 1])
        quad(p100, p000, p010, p110, normal: [0, 0, -1])
        quad(p101, p100, p110, p111, normal: [1, 0, 0])
        quad(p000, p001, p011, p010, normal: [-1, 0, 0])
        transform = saved
    }

    /// A flat rectangle lying on y = `center.y`, with UVs repeated `uvScale`
    /// times (for tiled markings).
    mutating func plane(center c: SIMD3<Float>, width: Float, depth: Float, yaw: Float = 0,
                        uvScale: SIMD2<Float> = .one) {
        let saved = transform
        transform = transform * Self.translation(c) * Self.yaw(yaw)
        let x = width / 2, z = depth / 2
        quad([-x, 0, z], [x, 0, z], [x, 0, -z], [-x, 0, -z], normal: [0, 1, 0],
             uv: (SIMD2(0, uvScale.y), SIMD2(uvScale.x, 0)))
        transform = saved
    }

    /// A cylinder (or truncated cone) along +y from the base centre.
    mutating func cylinder(base c: SIMD3<Float>, radius r0: Float, topRadius r1: Float? = nil,
                           height h: Float, segments n: Int = 16, caps: Bool = true) {
        let r1 = r1 ?? r0
        let slope = (r0 - r1) / max(h, 0.0001)
        var ring0: [UInt32] = [], ring1: [UInt32] = []
        for i in 0...n {
            let a = Float(i) / Float(n) * 2 * .pi
            let dir = SIMD3<Float>(cos(a), 0, -sin(a))
            let normal = simd_normalize(SIMD3(dir.x, slope, dir.z))
            ring0.append(vertex(c + dir * r0, normal, SIMD2(Float(i) / Float(n), 1)))
            ring1.append(vertex(c + dir * r1 + [0, h, 0], normal, SIMD2(Float(i) / Float(n), 0)))
        }
        for i in 0..<n {
            indices += [ring0[i], ring0[i + 1], ring1[i + 1], ring0[i], ring1[i + 1], ring1[i]]
        }
        if caps {
            disc(center: c + [0, h, 0], radius: r1, up: true, segments: n)
            if r0 > 0 { disc(center: c, radius: r0, up: false, segments: n) }
        }
    }

    mutating func disc(center c: SIMD3<Float>, radius r: Float, up: Bool, segments n: Int = 16) {
        let normal: SIMD3<Float> = up ? [0, 1, 0] : [0, -1, 0]
        let mid = vertex(c, normal, [0.5, 0.5])
        var rim: [UInt32] = []
        for i in 0...n {
            let a = Float(i) / Float(n) * 2 * .pi
            rim.append(vertex(c + SIMD3(cos(a), 0, -sin(a)) * r, normal, SIMD2(0.5 + cos(a) / 2, 0.5 - sin(a) / 2)))
        }
        for i in 0..<n {
            indices += up ? [mid, rim[i], rim[i + 1]] : [mid, rim[i + 1], rim[i]]
        }
    }

    /// A UV sphere, optionally squashed.
    mutating func sphere(center c: SIMD3<Float>, radius r: Float, scale: SIMD3<Float> = .one,
                         segments n: Int = 12, rings m: Int = 8) {
        var grid: [[UInt32]] = []
        for j in 0...m {
            let v = Float(j) / Float(m)
            let phi = v * .pi
            var row: [UInt32] = []
            for i in 0...n {
                let u = Float(i) / Float(n)
                let theta = u * 2 * .pi
                let unit = SIMD3<Float>(sin(phi) * cos(theta), cos(phi), -sin(phi) * sin(theta))
                row.append(vertex(c + unit * r * scale, simd_normalize(unit / scale), SIMD2(u, v)))
            }
            grid.append(row)
        }
        for j in 0..<m {
            for i in 0..<n {
                let a = grid[j][i], b = grid[j][i + 1], cc = grid[j + 1][i + 1], d = grid[j + 1][i]
                indices += [a, d, cc, a, cc, b]
            }
        }
    }

    /// A surface of revolution about the local x axis. Each profile station
    /// is (x, radius, centre height); `squash` scales the cross-section's
    /// height against its width (fuselages are a little taller than wide).
    mutating func lathe(_ profile: [(x: Float, r: Float, y: Float)], segments n: Int = 20,
                        squash: Float = 1) {
        var rings: [[UInt32]] = []
        for (k, station) in profile.enumerated() {
            // Slope of the radius along x for the normal.
            let prev = profile[max(0, k - 1)], next = profile[min(profile.count - 1, k + 1)]
            let dx = max(0.0001, next.x - prev.x)
            let dr = next.r - prev.r
            var ring: [UInt32] = []
            for i in 0...n {
                let a = Float(i) / Float(n) * 2 * .pi
                let cy = cos(a), cz = sin(a)
                let p = SIMD3<Float>(station.x, station.y + cy * station.r * squash, cz * station.r)
                let normal = simd_normalize(SIMD3<Float>(-dr / dx, cy / squash, cz))
                ring.append(vertex(p, normal, SIMD2(Float(i) / Float(n), Float(k) / Float(max(1, profile.count - 1)))))
            }
            rings.append(ring)
        }
        for k in 0..<(rings.count - 1) {
            for i in 0..<n {
                let a = rings[k][i], b = rings[k][i + 1], c = rings[k + 1][i + 1], d = rings[k + 1][i]
                indices += [a, b, c, a, c, d]
            }
        }
    }

    /// A flat polygon (convex, counter-clockwise in the xz plane) extruded
    /// along y by `thickness`, centred on y = 0.
    mutating func slab(_ input: [SIMD2<Float>], thickness t: Float) {
        // Accept either winding: make it counter-clockwise in (x, z).
        var area: Float = 0
        for i in input.indices {
            let a = input[i], b = input[(i + 1) % input.count]
            area += a.x * b.y - b.x * a.y
        }
        let polygon = area < 0 ? Array(input.reversed()) : input
        let h = t / 2
        let top = polygon.map { SIMD3<Float>($0.x, h, $0.y) }
        let bottom = polygon.map { SIMD3<Float>($0.x, -h, $0.y) }
        // Caps (fan).
        let topIdx = top.map { vertex($0, [0, 1, 0], [0, 0]) }
        let botIdx = bottom.map { vertex($0, [0, -1, 0], [0, 0]) }
        for i in 1..<(polygon.count - 1) {
            indices += [topIdx[0], topIdx[i + 1], topIdx[i]]
            indices += [botIdx[0], botIdx[i], botIdx[i + 1]]
        }
        // Sides.
        for i in 0..<polygon.count {
            let j = (i + 1) % polygon.count
            let e = polygon[j] - polygon[i]
            let n = simd_normalize(SIMD3<Float>(e.y, 0, -e.x))
            quad(bottom[i], bottom[j], top[j], top[i], normal: n)
        }
    }

    /// A triangular prism along z (a pitched roof): ridge height `h` over a
    /// `w`-wide base, `d` long.
    mutating func gable(center c: SIMD3<Float>, width w: Float, depth d: Float, height h: Float, yaw: Float = 0) {
        let saved = transform
        transform = transform * Self.translation(c) * Self.yaw(yaw)
        let x = w / 2, z = d / 2
        let l0 = SIMD3<Float>(-x, 0, -z), r0 = SIMD3<Float>(x, 0, -z), t0 = SIMD3<Float>(0, h, -z)
        let l1 = SIMD3<Float>(-x, 0, z), r1 = SIMD3<Float>(x, 0, z), t1 = SIMD3<Float>(0, h, z)
        let nl = simd_normalize(SIMD3<Float>(-h, x, 0)), nr = simd_normalize(SIMD3<Float>(h, x, 0))
        quad(l1, t1, t0, l0, normal: nl)
        quad(r0, t0, t1, r1, normal: nr)
        // Gable ends.
        let a = vertex(l1, [0, 0, 1], [0, 1]), b = vertex(r1, [0, 0, 1], [1, 1]), cc = vertex(t1, [0, 0, 1], [0.5, 0])
        indices += [a, b, cc]
        let e = vertex(r0, [0, 0, -1], [0, 1]), f = vertex(l0, [0, 0, -1], [1, 1]), g = vertex(t0, [0, 0, -1], [0.5, 0])
        indices += [e, f, g]
        transform = saved
    }

    /// A half cylinder along z (a barrel-vault roof) on y = `center.y`.
    mutating func vault(center c: SIMD3<Float>, width w: Float, depth d: Float, rise: Float, segments n: Int = 14) {
        let r = w / 2
        var front: [UInt32] = [], back: [UInt32] = []
        var ringF: [SIMD3<Float>] = [], ringB: [SIMD3<Float>] = []
        for i in 0...n {
            let a = Float(i) / Float(n) * .pi
            let p = SIMD3<Float>(cos(a) * r, sin(a) * rise, 0)
            let normal = simd_normalize(SIMD3<Float>(cos(a) / r, sin(a) / rise, 0))
            ringF.append(c + p + [0, 0, d / 2])
            ringB.append(c + p - [0, 0, d / 2])
            front.append(vertex(ringF.last!, normal, SIMD2(Float(i) / Float(n), 0)))
            back.append(vertex(ringB.last!, normal, SIMD2(Float(i) / Float(n), 1)))
        }
        for i in 0..<n {
            indices += [front[i], back[i], back[i + 1], front[i], back[i + 1], front[i + 1]]
        }
        // End caps (fans).
        let cf = vertex(c + [0, 0, d / 2], [0, 0, 1], [0.5, 0.5])
        let cb = vertex(c - [0, 0, d / 2], [0, 0, -1], [0.5, 0.5])
        let rf = ringF.map { vertex($0, [0, 0, 1], [0, 0]) }
        let rb = ringB.map { vertex($0, [0, 0, -1], [0, 0]) }
        for i in 0..<n {
            indices += [cf, rf[i], rf[i + 1]]
            indices += [cb, rb[i + 1], rb[i]]
        }
    }

    // MARK: Transforms

    static func translation(_ t: SIMD3<Float>) -> float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(t.x, t.y, t.z, 1)
        return m
    }

    static func yaw(_ a: Float) -> float4x4 {
        float4x4(simd_quatf(angle: a, axis: [0, 1, 0]))
    }

    static func roll(_ a: Float) -> float4x4 {
        float4x4(simd_quatf(angle: a, axis: [1, 0, 0]))
    }

    static func pitch(_ a: Float) -> float4x4 {
        float4x4(simd_quatf(angle: a, axis: [0, 0, 1]))
    }

    static func scale(_ s: SIMD3<Float>) -> float4x4 {
        var m = matrix_identity_float4x4
        m.columns.0.x = s.x
        m.columns.1.y = s.y
        m.columns.2.z = s.z
        return m
    }
}
