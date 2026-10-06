import RealityKit
import UIKit
import simd
import AirlineEmpireCore

/// Groups the static scene is split into, so modes can show and hide them
/// (the terminal cutaway hides the shell and shows the interior).
enum HubLayer: String, CaseIterable {
    case ground, markings, airside, terminalShell, terminalRoof, landside, nature, interior, shadows, lamps
}

/// Turns a `HubLayout` into static RealityKit geometry
/// (docs/HUB_VIEW_3D.md §5). Repeated pieces are batched per layer and
/// material; only the gate signs (text) are separate entities.
@available(iOS 18.0, *)
@MainActor
struct HubSceneBuilder {
    let layout: HubLayout
    let materials: HubMaterials

    private var batches: [HubLayer: [HubMaterialKey: HubMeshBatch]] = [:]
    private var extras: [(HubLayer, Entity)] = []

    init(layout: HubLayout, materials: HubMaterials) {
        self.layout = layout
        self.materials = materials
    }

    private mutating func with(_ layer: HubLayer, _ key: HubMaterialKey, _ body: (inout HubMeshBatch) -> Void) {
        var batch = batches[layer]?[key] ?? HubMeshBatch()
        body(&batch)
        batches[layer, default: [:]][key] = batch
    }

    /// Builds every layer. Returns one entity per layer, named by the layer.
    mutating func build() -> [HubLayer: Entity] {
        ground()
        for piece in layout.pieces { place(piece) }
        for piece in layout.interior.pieces { placeInterior(piece) }
        runwayMarkings()
        standMarkings()

        var roots: [HubLayer: Entity] = [:]
        for layer in HubLayer.allCases {
            let root = Entity()
            root.name = layer.rawValue
            roots[layer] = root
        }
        for (layer, byMaterial) in batches {
            for (key, batch) in byMaterial {
                guard let mesh = batch.resource(name: "\(layer.rawValue)") else { continue }
                let model = ModelEntity(mesh: mesh, materials: [materials[key]])
                model.components.set(HubMaterialTag(key: key))
                roots[layer]?.addChild(model)
            }
        }
        for (layer, entity) in extras { roots[layer]?.addChild(entity) }
        roots[.interior]?.isEnabled = false
        return roots
    }

    // MARK: Ground

    private mutating func ground() {
        let b = layout.bounds
        let cx = Float(b.center.x), cz = Float(b.center.z)
        with(.ground, .grass) { $0.plane(center: [cx, 0, cz], width: 9_000, depth: 9_000) }
    }

    private static func f(_ v: HubVec) -> SIMD3<Float> { SIMD3(Float(v.x), Float(v.y), Float(v.z)) }

    private mutating func flat(_ layer: HubLayer, _ key: HubMaterialKey, _ p: HubPiece, top: Float, inset: Float = 0) {
        let c = Self.f(p.center)
        let w = Float(p.size.x) - inset * 2, d = Float(p.size.z) - inset * 2
        with(layer, key) { $0.box(center: [c.x, 0, c.z], size: [w, top, d], yaw: Float(p.yaw)) }
    }

    private mutating func blob(_ c: SIMD3<Float>, w: Float, d: Float, y: Float = 0.33, yaw: Float = 0) {
        with(.shadows, .blob) { $0.plane(center: [c.x, y, c.z], width: w, depth: d, yaw: yaw) }
    }

    // MARK: Pieces

    private mutating func place(_ p: HubPiece) {
        let c = Self.f(p.center)
        let w = Float(p.size.x), h = Float(p.size.y), d = Float(p.size.z)
        let yaw = Float(p.yaw)
        switch p.kind {
        case .apron: flat(.ground, p.variant == 0 ? .concrete : .concreteLight, p, top: 0.1)
        case .taxiway: flat(.ground, .asphaltDark, p, top: 0.12)
        case .runway: flat(.ground, .asphalt, p, top: 0.14)
        case .road:
            flat(.ground, .asphalt, p, top: 0.12)
            laneDashes(p)
            streetLamps(p)
        case .sidewalk: flat(.ground, .concreteLight, p, top: 0.22)
        case .parking:
            flat(.ground, .asphaltDark, p, top: 0.13)
            parkingLines(p)
        case .lawn:
            flat(.ground, .grassBright, p, top: max(0.18, h))
        case .plaza: flat(.ground, .concreteLight, p, top: 0.15)
        case .crosswalk: crosswalk(p)
        case .standMarking: break // drawn from the stands themselves
        case .terminalHall: terminal(p)
        case .pier: pier(p)
        case .jetBridge: jetBridge(p)
        case .gateSign: gateSign(p)
        case .controlTower: tower(p)
        case .hangar: hangar(p)
        case .cargoShed:
            with(.airside, .buildingShade) { $0.box(center: c, size: [w, h, d]) }
            with(.airside, .roof) { $0.box(center: c + [0, h, 0], size: [w + 1.5, 0.8, d + 1.5]) }
            for i in 0..<4 {
                let x = c.x - w / 2 + w * (Float(i) + 0.5) / 4
                with(.airside, .darkMetal) { $0.box(center: [x, 0, c.z - d / 2 - 0.1], size: [w / 6, h * 0.6, 0.3]) }
            }
            blob(c, w: w * 1.35, d: d * 1.5)
        case .fuelTank:
            with(.airside, .white) {
                $0.cylinder(base: c, radius: w / 2, height: h, segments: 24)
                $0.sphere(center: c + [0, h, 0], radius: w / 2, scale: [1, 0.18, 1], segments: 20, rings: 6)
            }
            with(.airside, .darkMetal) { $0.box(center: c + [w / 2, 0, 0], size: [0.6, h, 0.6]) }
            blob(c, w: w * 1.6, d: w * 1.6)
        case .blastFence:
            with(.airside, .darkMetal) { $0.box(center: c, size: [w, h, d]) }
        case .officeBlock: office(p)
        case .house: house(p)
        case .gardenWall: gardenWall(p)
        case .pool:
            with(.landside, .white) { $0.box(center: c, size: [w + 1.2, 0.4, d + 1.2]) }
            with(.landside, .water) { $0.box(center: c, size: [w, 0.44, d]) }
        case .tree: tree(p)
        case .lampPost:
            with(.landside, .darkMetal) {
                $0.cylinder(base: c, radius: 0.16, height: h, segments: 6, caps: false)
                $0.box(center: c + [0, h - 0.2, 0.9], size: [0.2, 0.2, 2])
            }
            with(.lamps, .lamp) { $0.box(center: c + [0, h - 0.45, 1.7], size: [0.7, 0.3, 1.0]) }
            with(.lamps, .lampPool) { $0.plane(center: c + [0, 0.3, 1.7], width: 14, depth: 14) }
        case .parkedCar:
            let color = HubMaterialKey.cloth([0, 1, 5, 6, 7, 5][p.variant % 6])
            with(.landside, color) {
                $0.box(center: c + [0, 0.2, 0], size: [w, 0.7, d], yaw: yaw)
                $0.box(center: c + [0, 0.9, 0.3], size: [w * 0.85, 0.6, d * 0.5], yaw: yaw)
            }
            with(.landside, .windowDark) { $0.box(center: c + [0, 0.95, 0.3], size: [w * 0.88, 0.4, d * 0.52], yaw: yaw, top: false) }
        // Interior kinds never appear in `pieces`.
        default: break
        }
    }

    private mutating func laneDashes(_ p: HubPiece) {
        let c = Self.f(p.center)
        let alongX = p.size.x >= p.size.z
        let length = Float(alongX ? p.size.x : p.size.z)
        let width = Float(alongX ? p.size.z : p.size.x)
        guard width > 15 else { return }
        var t = -length / 2 + 6
        with(.markings, .marking) { batch in
            while t < length / 2 - 6 {
                if alongX {
                    batch.box(center: [c.x + t, 0.12, c.z], size: [4, 0.012, 0.35], top: true)
                } else {
                    batch.box(center: [c.x, 0.12, c.z + t], size: [0.35, 0.012, 4], top: true)
                }
                t += 10
            }
        }
    }

    private mutating func streetLamps(_ p: HubPiece) {
        let c = Self.f(p.center)
        let alongX = p.size.x >= p.size.z
        let length = Float(alongX ? p.size.x : p.size.z)
        let width = Float(alongX ? p.size.z : p.size.x)
        guard length > 60 else { return }
        var t = -length / 2 + 20
        var k = 0
        while t < length / 2 - 10 {
            let side: Float = k % 2 == 0 ? 1 : -1
            let off = side * (width / 2 + 1.5)
            let base: SIMD3<Float> = alongX ? [c.x + t, 0, c.z + off] : [c.x + off, 0, c.z + t]
            let arm: SIMD3<Float> = alongX ? [0, 0, -side * 1.6] : [-side * 1.6, 0, 0]
            with(.landside, .darkMetal) { $0.cylinder(base: base, radius: 0.14, height: 7.5, segments: 5, caps: false) }
            with(.lamps, .lamp) { $0.box(center: base + arm + [0, 7.3, 0], size: [0.9, 0.3, 0.9]) }
            with(.lamps, .lampPool) { $0.plane(center: base + arm * 2 + [0, 0.36, 0], width: 12, depth: 12) }
            t += 42
            k += 1
        }
    }

    private mutating func parkingLines(_ p: HubPiece) {
        let r = p.groundBounds
        with(.markings, .marking) { batch in
            var x = Float(r.minX) + 4.7
            while x < Float(r.maxX) - 3 {
                for z in [Float(r.minZ) + 12, Float(r.minZ) + 30, Float(r.maxZ) - 30, Float(r.maxZ) - 12] {
                    batch.box(center: [x, 0.13, z], size: [0.15, 0.01, 5], top: true)
                }
                x += 3.4
            }
        }
    }

    private mutating func crosswalk(_ p: HubPiece) {
        let c = Self.f(p.center)
        let alongX = p.variant == 0
        with(.markings, .marking) { batch in
            for i in 0..<7 {
                let o = -7.2 + Float(i) * 2.4
                if alongX {
                    batch.box(center: [c.x + o, 0.12, c.z], size: [1.2, 0.014, 5.4], top: true)
                } else {
                    batch.box(center: [c.x, 0.12, c.z + o], size: [5.4, 0.014, 1.2], top: true)
                }
            }
        }
    }

    // MARK: Airside buildings

    private mutating func terminal(_ p: HubPiece) {
        let c = Self.f(p.center)
        let w = Float(p.size.x), d = Float(p.size.z), h = Float(p.size.y)
        let glassTop = h - 4
        // Plinth and floors.
        with(.airside, .buildingShade) { $0.box(center: c, size: [w, 1.6, d]) }
        // Side walls (solid, white) stay up in the cutaway: the doll's-house
        // frame of reference shot C.
        with(.airside, .building) {
            $0.box(center: [c.x - w / 2 + 2, 1.6, c.z], size: [4, glassTop - 1.6, d])
            $0.box(center: [c.x + w / 2 - 2, 1.6, c.z], size: [4, glassTop - 1.6, d])
        }
        with(.terminalShell, .building) {
            // Floor band between levels on the landside face.
            $0.box(center: [c.x, 9.5, c.z + d / 2 - 0.4], size: [w, 1.0, 1.0])
        }
        with(.airside, .building) {
            $0.box(center: [c.x, 9.5, c.z - d / 2 + 0.4], size: [w, 1.0, 1.0])
        }
        // Curtain walls.
        with(.airside, .glass) { $0.box(center: [c.x, 1.6, c.z - d / 2 + 0.5], size: [w - 8, glassTop - 1.6, 0.4]) }
        with(.terminalShell, .glass) { $0.box(center: [c.x, 1.6, c.z + d / 2 - 0.5], size: [w - 8, glassTop - 1.6, 0.4]) }
        // Mullions every 8 m.
        var x = c.x - w / 2 + 8
        while x < c.x + w / 2 - 4 {
            let mx = x
            with(.airside, .white) { $0.box(center: [mx, 1.6, c.z - d / 2 + 0.2], size: [0.6, glassTop - 1.6, 0.6]) }
            with(.terminalShell, .white) { $0.box(center: [mx, 1.6, c.z + d / 2 - 0.2], size: [0.6, glassTop - 1.6, 0.6]) }
            x += 8
        }
        // Roof: overhanging slab, glass skylight ridge, plant.
        with(.terminalRoof, .roof) {
            $0.box(center: [c.x, glassTop, c.z], size: [w + 3, 1.6, d + 5], bottom: true)
            $0.box(center: [c.x, glassTop + 1.8, c.z], size: [w * 0.86, 0.6, d * 0.7])
        }
        with(.terminalRoof, .glass) { $0.box(center: [c.x, glassTop + 2.4, c.z], size: [w * 0.8, 2.6, 9]) }
        with(.terminalRoof, .buildingShade) {
            for i in 0..<4 {
                $0.box(center: [c.x - w * 0.3 + Float(i) * w * 0.2, glassTop + 2.4, c.z + d * 0.25], size: [7, 2.2, 5])
            }
        }
        // Landside canopy on columns over the kerb.
        with(.airside, .roof) { $0.box(center: [c.x, 9, c.z + d / 2 + 6], size: [w * 0.6, 0.7, 12]) }
        with(.airside, .white) {
            var cx = c.x - w * 0.28
            while cx <= c.x + w * 0.28 {
                $0.cylinder(base: [cx, 0, c.z + d / 2 + 11], radius: 0.4, height: 9, segments: 8, caps: false)
                cx += 18
            }
        }
        // City name on the landside roof edge.
        if let label = p.label {
            let text = ModelEntity(mesh: .generateText(label, extrusionDepth: 0.3,
                                                       font: .systemFont(ofSize: 4, weight: .bold)),
                                   materials: [materials[.houseRoof]])
            text.components.set(HubMaterialTag(key: .houseRoof))
            let bounds = text.visualBounds(relativeTo: nil)
            text.position = [c.x - bounds.extents.x / 2, glassTop + 0.1, c.z + d / 2 + 2.55]
            extras.append((.terminalRoof, text))
        }
        blob(c, w: w * 1.2, d: d * 1.6, y: 0.24)
    }

    private mutating func pier(_ p: HubPiece) {
        let c = Self.f(p.center)
        let w = Float(p.size.x), d = Float(p.size.z)
        with(.airside, .building) { $0.box(center: c, size: [w, 4, d]) }
        with(.airside, .glass) { $0.box(center: c + [0, 4, 0], size: [w - 0.6, 5.2, d - 0.6]) }
        with(.airside, .white) {
            var z = c.z - d / 2 + 6
            while z < c.z + d / 2 - 2 {
                $0.box(center: [c.x - w / 2 + 0.2, 4, z], size: [0.5, 5.2, 0.5])
                $0.box(center: [c.x + w / 2 - 0.2, 4, z], size: [0.5, 5.2, 0.5])
                z += 7
            }
        }
        with(.airside, .roof) {
            $0.box(center: c + [0, 9.2, 0], size: [w + 2.4, 1.2, d + 2.4], bottom: true)
            $0.box(center: c + [0, 10.4, 0], size: [w * 0.5, 0.8, d * 0.9])
        }
        blob(c, w: w * 2.2, d: d * 1.1, y: 0.12)
    }

    private mutating func jetBridge(_ p: HubPiece) {
        let c = Self.f(p.center)
        let len = Float(p.size.x), yaw = Float(p.yaw)
        let frame = HubMeshBatch.translation(c) * HubMeshBatch.yaw(yaw)
        with(.airside, .glass) { b in
            b.transform = frame
            b.box(center: [0, 4.6, 0], size: [len - 2, 2.6, 3.0])
            b.transform = matrix_identity_float4x4
        }
        with(.airside, .white) { b in
            b.transform = frame
            b.box(center: [0, 4.2, 0], size: [len - 2, 0.45, 3.4])
            b.box(center: [0, 7.2, 0], size: [len - 2, 0.4, 3.4])
            // Rotunda at the root, cab at the tip.
            b.cylinder(base: [-len / 2, 3.9, 0], radius: 2.3, height: 3.8, segments: 14)
            b.box(center: [len / 2 - 1.2, 3.9, 0], size: [3.4, 3.8, 4.0])
            b.transform = matrix_identity_float4x4
        }
        with(.airside, .darkMetal) { b in
            b.transform = frame
            // Drive column and bogie near the tip; root column.
            b.box(center: [len * 0.3, 0, 0], size: [0.6, 4.2, 2.4])
            b.box(center: [len * 0.3, 0.3, 0], size: [1.4, 0.7, 3.6])
            b.cylinder(base: [-len / 2, 0, 0], radius: 0.8, height: 3.9, segments: 8, caps: false)
            b.box(center: [len / 2 - 0.2, 4.2, 0], size: [0.5, 3.2, 3.0])
            b.transform = matrix_identity_float4x4
        }
        blob(c, w: len * 1.1, d: 6, y: 0.12, yaw: yaw)
    }

    private mutating func gateSign(_ p: HubPiece) {
        let c = Self.f(p.center)
        let sign = Entity()
        let panel = ModelEntity(mesh: .generateBox(width: 6.4, height: 2.6, depth: 0.35, cornerRadius: 0.25),
                                materials: [materials[.darkMetal]])
        panel.components.set(HubMaterialTag(key: .darkMetal))
        sign.addChild(panel)
        if let label = p.label {
            let text = ModelEntity(mesh: .generateText(label, extrusionDepth: 0.05,
                                                       font: .systemFont(ofSize: 1.1, weight: .semibold)),
                                   materials: [materials[.lamp]])
            text.components.set(HubMaterialTag(key: .lamp))
            let bounds = text.visualBounds(relativeTo: nil)
            text.position = [-bounds.extents.x / 2, -bounds.extents.y / 2 - 0.1, 0.2]
            sign.addChild(text)
        }
        sign.position = c
        // Face the default camera (south-west).
        sign.orientation = simd_quatf(angle: 0.61, axis: [0, 1, 0])
        extras.append((.airside, sign))
    }

    private mutating func tower(_ p: HubPiece) {
        let c = Self.f(p.center)
        let h = Float(p.size.y)
        with(.airside, .building) {
            $0.cylinder(base: c, radius: 4.2, topRadius: 3.0, height: h - 10, segments: 18)
            $0.cylinder(base: c + [0, h - 10, 0], radius: 5.0, topRadius: 7.0, height: 2.5, segments: 18)
        }
        with(.airside, .glass) { $0.cylinder(base: c + [0, h - 7.5, 0], radius: 7.0, topRadius: 7.6, height: 4.5, segments: 18) }
        with(.airside, .roof) { $0.cylinder(base: c + [0, h - 3, 0], radius: 8.0, topRadius: 6.0, height: 1.2, segments: 18) }
        with(.airside, .darkMetal) { $0.cylinder(base: c + [0, h - 1.8, 0], radius: 0.18, height: 8, segments: 6) }
        blob(c, w: 22, d: 22)
    }

    private mutating func hangar(_ p: HubPiece) {
        let c = Self.f(p.center)
        let w = Float(p.size.x), d = Float(p.size.z)
        let wall: Float = 15
        with(.airside, .building) {
            $0.box(center: c, size: [w, wall, d])
        }
        with(.airside, .roof) { $0.vault(center: c + [0, wall, 0], width: w + 1, depth: d + 1, rise: 11) }
        // Big doors on the apron (north) face, window band above.
        with(.airside, .darkMetal) {
            for i in 0..<4 {
                let x = c.x - w * 0.38 + Float(i) * w * 0.253
                $0.box(center: [x, 0.1, c.z - d / 2 - 0.15], size: [w * 0.23, wall * 0.78, 0.4])
            }
        }
        with(.airside, .glass) { $0.box(center: [c.x, wall * 0.84, c.z - d / 2 - 0.1], size: [w * 0.9, 1.6, 0.3]) }
        with(.airside, .windowDark) {
            for i in 0..<6 {
                $0.box(center: [c.x - w / 2 - 0.1, 3, c.z - d / 2 + 8 + Float(i) * (d - 16) / 5], size: [0.3, 2, 4])
            }
        }
        blob(c, w: w * 1.3, d: d * 1.3)
    }

    // MARK: Landside buildings

    private mutating func office(_ p: HubPiece) {
        let c = Self.f(p.center)
        let w = Float(p.size.x), h = Float(p.size.y), d = Float(p.size.z)
        let floors = max(1, min(8, p.variant))
        with(.landside, .office(floors: floors)) { $0.box(center: c + [0, 0.6, 0], size: [w, h, d], top: false) }
        with(.landside, .roof) {
            $0.box(center: c + [0, h + 0.6, 0], size: [w + 0.8, 0.9, d + 0.8])
            $0.box(center: c + [w * 0.15, h + 1.5, -d * 0.1], size: [w * 0.3, 2.2, d * 0.3])
        }
        with(.landside, .buildingShade) { $0.box(center: c, size: [w + 1, 0.6, d + 1]) }
        blob(c, w: w + 14, d: d + 14)
    }

    private mutating func house(_ p: HubPiece) {
        let c = Self.f(p.center)
        let w = Float(p.size.x), d = Float(p.size.z)
        let storey: Float = 3.6
        let v = p.variant
        // Ground floor: a white box glazed on the garden (south) and east
        // faces; upper floor set back, under a pitched navy roof with a flat
        // canopy wing — the reference's modern villa.
        let upper = c + [-w * 0.12, storey, -d * 0.08]
        let upperW = w * 0.62, upperD = d * 0.78
        with(.landside, .building) {
            $0.box(center: c + [0, 0, -d * 0.25], size: [w, storey, d * 0.5])
            $0.box(center: c + [-w * 0.35, 0, d * 0.25], size: [w * 0.3, storey, d * 0.5])
            $0.box(center: upper, size: [upperW, storey, upperD])
            // Balcony slab.
            $0.box(center: upper + [0, -0.3, upperD / 2 + 1.2], size: [upperW * 0.9, 0.35, 2.4])
        }
        with(.landside, .glass) {
            $0.box(center: c + [w * 0.15, 0.1, d * 0.25], size: [w * 0.7 - 0.4, storey - 0.4, d * 0.5 - 0.4])
            $0.box(center: upper + [upperW * 0.1, 0.5, upperD / 2], size: [upperW * 0.55, storey * 0.7, 0.2])
        }
        with(.landside, .white) {
            // Window frames: mullions on the glass box.
            for k in 0..<4 {
                let x = c.x - w * 0.2 + Float(k) * w * 0.233
                $0.box(center: [x, c.y, c.z + d / 2 - 0.1], size: [0.25, storey, 0.3])
            }
            $0.box(center: c + [w * 0.15, storey - 0.35, d * 0.25], size: [w * 0.7, 0.35, d * 0.5])
            // Balcony rail.
            $0.box(center: upper + [0, 0.05, upperD / 2 + 2.3], size: [upperW * 0.9, 1.0, 0.12])
        }
        with(.landside, .houseWood) {
            // Vertical slats beside the entrance.
            for k in 0..<7 {
                $0.box(center: c + [-w * 0.48 + Float(k) * 0.45, 0, d / 2 + 0.05], size: [0.2, storey * 0.92, 0.2])
            }
            $0.box(center: upper + [-upperW / 2 - 0.05, 0, 0], size: [0.2, storey * 0.9, upperD * 0.6])
            if v == 1 { $0.box(center: upper + [upperW * 0.3, 0, upperD / 2 + 0.05], size: [upperW * 0.3, storey * 0.9, 0.25]) }
        }
        with(.landside, .houseRoof) {
            $0.gable(center: upper + [0, storey, 0], width: upperW + 1.6, depth: upperD + 1.6,
                     height: 3.2, yaw: v == 2 ? .pi / 2 : 0)
            $0.box(center: c + [w * 0.15, storey, d * 0.2], size: [w * 0.75, 0.45, d * 0.62])
        }
        with(.landside, .windowDark) {
            $0.box(center: upper + [-upperW * 0.3, 0.6, upperD / 2 + 0.02], size: [upperW * 0.25, storey * 0.55, 0.2])
            $0.box(center: c + [-w / 2 - 0.02, 0.7, -d * 0.2], size: [0.2, storey * 0.55, d * 0.3])
        }
        // A car on the drive.
        let car = c + [w * 0.25, 0.3, d / 2 + 6]
        with(.landside, .cloth(v * 3)) {
            $0.box(center: car, size: [1.9, 0.75, 4.4])
            $0.box(center: car + [0, 0.75, -0.3], size: [1.7, 0.6, 2.4])
        }
        with(.landside, .windowDark) { $0.box(center: car + [0, 0.8, -0.3], size: [1.74, 0.42, 2.44], top: false) }
        blob(c, w: w * 1.5, d: d * 1.5, y: 0.34)
    }

    private mutating func gardenWall(_ p: HubPiece) {
        let c = Self.f(p.center)
        let w = Float(p.size.x), h = Float(p.size.y), d = Float(p.size.z)
        let t: Float = 0.45
        with(.landside, .white) {
            $0.box(center: c + [0, 0, -d / 2], size: [w, h, t])
            $0.box(center: c + [-w / 2, 0, 0], size: [t, h, d])
            $0.box(center: c + [w / 2, 0, 0], size: [t, h, d])
            // Front wall with a gate gap.
            $0.box(center: c + [-w * 0.3, 0, d / 2], size: [w * 0.4, h, t])
            $0.box(center: c + [w * 0.3, 0, d / 2], size: [w * 0.4, h, t])
        }
        with(.landside, .concreteLight) { $0.box(center: c + [0, 0, d / 2 - 6], size: [6, 0.32, 12]) }
    }

    private mutating func tree(_ p: HubPiece) {
        let c = Self.f(p.center)
        let s = Float(p.size.x) / 8 * 1.45, h = Float(p.size.y) * 1.4
        with(.nature, .trunk) { $0.cylinder(base: c + [0, 0.15, 0], radius: 0.32 * s, topRadius: 0.22 * s, height: h * 0.45, segments: 6, caps: false) }
        with(.nature, .tree(p.variant)) {
            $0.sphere(center: c + [0, h * 0.62, 0], radius: 3.4 * s, scale: [1, 1.08, 1], segments: 12, rings: 8)
            $0.sphere(center: c + [1.4 * s, h * 0.52, 1.1 * s], radius: 2.4 * s, segments: 10, rings: 6)
            $0.sphere(center: c + [-1.3 * s, h * 0.5, -0.8 * s], radius: 2.2 * s, segments: 10, rings: 6)
        }
        blob(c + [1.5 * s, 0, 1.5 * s], w: 9 * s, d: 9 * s)
    }

    // MARK: Markings

    private mutating func runwayMarkings() {
        for runway in layout.runways {
            let a = Self.f(runway.thresholdA), b = Self.f(runway.thresholdB)
            let length = simd_distance(a, b)
            let dir = simd_normalize(b - a)
            let yaw = atan2(-dir.z, dir.x)
            let width = Float(runway.width)
            with(.markings, .marking) { batch in
                batch.transform = HubMeshBatch.translation(a) * HubMeshBatch.yaw(yaw)
                // Centreline.
                var t: Float = 120
                while t < length - 120 {
                    batch.box(center: [t, 0.14, 0], size: [30, 0.012, 0.9])
                    t += 50
                }
                // Edges.
                batch.box(center: [length / 2, 0.14, width / 2 - 1], size: [length - 8, 0.012, 0.9])
                batch.box(center: [length / 2, 0.14, -width / 2 + 1], size: [length - 8, 0.012, 0.9])
                // Thresholds (piano keys) and aiming points at both ends.
                for end: Float in [0, 1] {
                    let base = end == 0 ? Float(12) : length - 42
                    for k in 0..<12 where k != 5 && k != 6 {
                        let z = -width / 2 + 3 + Float(k) * (width - 6) / 11
                        batch.box(center: [base + 15, 0.14, z], size: [30, 0.012, 1.8])
                    }
                    let aim = end == 0 ? Float(300) : length - 300
                    for side: Float in [-1, 1] {
                        batch.box(center: [aim, 0.14, side * width * 0.22], size: [45, 0.012, 6])
                    }
                }
                batch.transform = matrix_identity_float4x4
            }
        }
        // Taxiway centrelines.
        for p in layout.pieces where p.kind == .taxiway {
            let c = Self.f(p.center)
            let alongX = p.size.x >= p.size.z
            with(.markings, .taxiLine) {
                $0.box(center: [c.x, 0.12, c.z], size: alongX ? [Float(p.size.x) - 4, 0.012, 0.45]
                       : [0.45, 0.012, Float(p.size.z) - 4])
            }
        }
    }

    private mutating func standMarkings() {
        for stand in layout.stands {
            let nose = Self.f(stand.nose)
            let fwd = SIMD3<Float>(Float(cos(stand.heading)), 0, Float(-sin(stand.heading)))
            let yaw = Float(stand.heading)
            let len = Float(HubAircraftEnvelope.length(stand.maxCategory))
            with(.markings, .taxiLine) { b in
                // Lead-in line from the taxilane to the stop bar.
                let mid = nose - fwd * (len / 2 + 14)
                b.box(center: [mid.x, 0.1, mid.z], size: [len + 28, 0.012, 0.4], yaw: yaw)
            }
            with(.markings, .marking) { b in
                // Stop bar and a tail-clearance line.
                b.box(center: [nose.x, 0.1, nose.z], size: [0.5, 0.012, 6], yaw: yaw)
                let tail = nose - fwd * (len + 6)
                b.box(center: [tail.x, 0.1, tail.z], size: [0.4, 0.012, Float(HubAircraftEnvelope.span(stand.maxCategory))], yaw: yaw)
            }
        }
    }

    // MARK: Interior (cutaway)

    private mutating func placeInterior(_ p: HubPiece) {
        let c = Self.f(p.center)
        let w = Float(p.size.x), h = Float(p.size.y), d = Float(p.size.z)
        let yaw = Float(p.yaw)
        switch p.kind {
        case .floorSlab:
            with(.interior, .concreteLight) { $0.box(center: c + [0, 1.6, 0], size: [w, 0.1, d]) }
        case .mezzanine:
            with(.interior, .building) { $0.box(center: c, size: [w, 0.6, d], bottom: true) }
            with(.interior, .glass) { $0.box(center: c + [0, 0.6, d / 2 - 0.1], size: [w, 1.1, 0.15]) }
            with(.interior, .white) {
                var x = c.x - w / 2 + 6
                while x < c.x + w / 2 {
                    $0.box(center: [x, 1.7, c.z + d / 2 - 1], size: [0.6, c.y - 1.7, 0.6])
                    x += 12
                }
            }
        case .checkInDesk:
            // Counter, bag belt, and the tall branded backboard behind it.
            with(.interior, .white) { $0.box(center: c + [0, 1.7, 0], size: [w, h, d]) }
            with(.interior, .darkMetal) { $0.box(center: c + [-w * 0.7, 1.7, 0], size: [w * 0.5, 0.5, d]) }
            with(.interior, .houseRoof) { $0.box(center: c + [-w * 1.1, 1.7, 0], size: [0.5, 3.6, d + 1]) }
            with(.interior, .screen) {
                var z = c.z - d / 2 + 2
                while z < c.z + d / 2 {
                    $0.box(center: [c.x, 1.7 + h + 0.05, z], size: [0.1, 0.6, 0.9])
                    $0.box(center: [c.x - w * 1.1 + 0.3, 4.2, z], size: [0.05, 0.7, 1.6])
                    z += 3
                }
            }
        case .kiosk:
            with(.interior, .white) { $0.box(center: c + [0, 1.7, 0], size: [w, h, d]) }
            with(.interior, .screen) { $0.box(center: c + [0, 1.7 + h * 0.55, d / 2], size: [w * 0.8, h * 0.35, 0.05]) }
        case .securityLane:
            with(.interior, .white) {
                $0.box(center: c + [-2, 1.7, -d / 2 + 0.2], size: [0.3, h, 0.3])
                $0.box(center: c + [-2, 1.7, d / 2 - 0.2], size: [0.3, h, 0.3])
                $0.box(center: c + [-2, 1.7 + h, 0], size: [0.4, 0.3, d])
            }
            with(.interior, .darkMetal) { $0.box(center: c + [2, 1.7, 0], size: [w * 0.6, 0.9, 0.9]) }
            with(.interior, .pulse) { $0.box(center: c + [-2, 1.72, 0], size: [0.6, 0.02, d - 0.8]) }
        case .queueBarrier:
            with(.interior, .darkMetal) {
                let rows = max(2, Int(d / 2.4))
                for r in 0...rows {
                    let z = c.z - d / 2 + Float(r) * d / Float(rows)
                    $0.box(center: [c.x, 1.7 + 0.9, z], size: [w, 0.08, 0.06])
                    for k in 0...3 {
                        $0.cylinder(base: [c.x - w / 2 + Float(k) * w / 3, 1.7, z], radius: 0.06, height: 1, segments: 4, caps: false)
                    }
                }
            }
        case .shopShelf:
            with(.interior, .houseWood) { $0.box(center: c + [0, 1.7, 0], size: [w, h, d], yaw: yaw) }
            with(.interior, .cloth(p.variant + 2)) {
                for k in 0..<3 {
                    $0.box(center: c + [0, 1.9 + Float(k) * 0.7, d / 2 - 0.1], size: [w * 0.9, 0.35, 0.3], yaw: yaw)
                }
            }
            if let label = p.label {
                let text = ModelEntity(mesh: .generateText(label, extrusionDepth: 0.05,
                                                           font: .systemFont(ofSize: 1.2, weight: .bold)),
                                       materials: [materials[.houseRoof]])
                text.components.set(HubMaterialTag(key: .houseRoof))
                text.position = c + [-w / 2, 1.7 + h + 0.6, d / 2]
                extras.append((.interior, text))
            }
        case .seatRow:
            with(.interior, .darkMetal) { $0.box(center: c + [0, 1.7, 0], size: [w, 0.5, d]) }
            with(.interior, .cloth(0)) { $0.box(center: c + [0, 2.2, -d / 2 + 0.2], size: [w, 0.6, 0.25]) }
        case .flightBoard:
            with(.interior, .darkMetal) { $0.box(center: c + [0, 1.7, 0], size: [w + 0.4, h + 0.4, d]) }
            with(.interior, .screen) { $0.box(center: c + [0, 1.9, d / 2], size: [w, h, 0.05]) }
        case .escalator:
            with(.interior, .darkMetal) { b in
                b.transform = HubMeshBatch.translation(c + [0, 1.7, 0]) * HubMeshBatch.yaw(.pi / 2) * HubMeshBatch.pitch(-0.42)
                b.box(center: [0, -1, 0], size: [d, 0.4, w])
                b.transform = matrix_identity_float4x4
            }
            with(.interior, .glass) { b in
                b.transform = HubMeshBatch.translation(c + [0, 1.7, 0]) * HubMeshBatch.yaw(.pi / 2) * HubMeshBatch.pitch(-0.42)
                b.box(center: [0, -0.6, -w / 2], size: [d, 1.0, 0.1])
                b.box(center: [0, -0.6, w / 2], size: [d, 1.0, 0.1])
                b.transform = matrix_identity_float4x4
            }
        case .loungeBlock:
            with(.interior, .houseWood) { $0.box(center: c, size: [w, 0.3, d]) }
            with(.interior, .glass) { $0.box(center: c + [0, 0.3, d / 2], size: [w, h, 0.2]) }
            with(.interior, .cloth(4)) {
                for k in 0..<4 { $0.box(center: c + [-w / 2 + 4 + Float(k) * (w - 8) / 3, 0.3, 0], size: [3, 0.8, 2]) }
            }
        default: break
        }
    }
}
