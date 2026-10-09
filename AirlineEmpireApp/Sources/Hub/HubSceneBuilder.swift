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

    let library: HubAssetLibrary?

    init(layout: HubLayout, materials: HubMaterials, library: HubAssetLibrary? = nil) {
        self.layout = layout
        self.materials = materials
        self.library = library
    }

    // MARK: Authored models (docs/HUB_MODEL_LIST.md)

    /// How an authored model stands in for a piece: which files, which way
    /// its +X front should face, and how it is fitted to the footprint.
    private enum Fit { case footprint, height, none, stretchX }

    private func authored(_ p: HubPiece) -> (slots: [String], yaw: Float, fit: Fit, layer: HubLayer)? {
        // A building's authored front is +X; these turn it to face where the
        // layout needs it (north = apron, south = street).
        let faceNorth: Float = .pi / 2, faceSouth: Float = -.pi / 2
        switch p.kind {
        case .tree:
            let base = ["tree_round", "tree_tall", "tree_small"][p.variant % 3]
            return ([base, "tree_round"], 0, .height, .nature)
        case .house:
            let variants = ["house_villa", "house_villa_b", "house_villa_c"]
            let first = variants[p.variant % 3]
            return ([first] + variants.filter { $0 != first }, faceSouth, .footprint, .landside)
        case .gardenWall: return (["house_garden"], faceSouth, .footprint, .landside)
        case .pool: return (["pool"], 0, .footprint, .landside)
        case .hangar: return (["hangar"], faceNorth, .footprint, .airside)
        case .controlTower: return (["controlTower"], faceSouth, .height, .airside)
        case .cargoShed: return (["cargoShed"], faceNorth, .footprint, .airside)
        case .fuelTank: return (["fuelTank"], 0, .footprint, .airside)
        case .officeBlock:
            return (p.variant >= 4 ? ["midrise_apartment", "office_low"] : ["office_low", "midrise_apartment"],
                    faceSouth, .footprint, .landside)
        case .jetBridge: return (["jetBridge"], 0, .stretchX, .airside)
        case .gateSign: return (["gateSign"], 0.61, .none, .airside)
        case .terminalHall: return (["terminal_hall"], faceSouth, .footprint, .airside)
        case .parkedCar: return (["vehicle_car_sedan", "vehicle_car_suv"], 0, .none, .landside)
        case .kiosk: return (["kiosk_selfService"], faceSouth, .none, .interior)
        case .checkInDesk: return (["checkInDesk"], faceSouth, .none, .interior)
        case .securityLane: return (["eGate"], 0, .none, .interior)
        case .shopShelf: return (["shop_shelving"], faceSouth, .none, .interior)
        case .seatRow: return (["seatRow"], 0, .none, .interior)
        default: return nil
        }
    }

    /// Places the authored model for `p` if one ships. Returns false to fall
    /// back to the procedural builder.
    private mutating func placeAuthored(_ p: HubPiece, floor: Float = 0) -> Bool {
        guard let library, let spec = authored(p) else { return false }
        let colour = p.kind == .parkedCar ? HubMaterialKey.cloth([0, 1, 5, 6, 7, 5][p.variant % 6]) : nil
        guard let e = library.instance(anyOf: spec.slots, materials: materials, remap: { key in
            if let colour, case .cloth = key { return colour }
            return key
        }) else { return false }
        let c = Self.f(p.center)
        switch spec.fit {
        case .footprint:
            // Rotated a quarter turn the footprint's axes swap.
            let quarter = abs(sin(spec.yaw)) > 0.5
            HubAssetLibrary.fit(e, footprint: quarter ? [Float(p.size.z), Float(p.size.x)]
                                                      : [Float(p.size.x), Float(p.size.z)])
        case .height:
            HubAssetLibrary.fit(e, footprint: [1, 1], height: Float(p.size.y) * 1.4)
        case .stretchX:
            let ext = e.visualBounds(relativeTo: e).extents
            if ext.x > 0.1 { e.scale = [Float(p.size.x) / ext.x, 1, 1] }
        case .none:
            break
        }
        e.position = [c.x, c.y + floor, c.z]
        e.orientation = simd_quatf(angle: Float(p.yaw) + spec.yaw, axis: [0, 1, 0])
        if p.kind == .terminalHall {
            // Prims named `cutaway…` are the roof and street wall the
            // terminal shot lifts off.
            for child in Array(e.children) where child.name.lowercased().hasPrefix("cutaway") {
                let world = child.transformMatrix(relativeTo: nil)
                child.removeFromParent()
                child.setTransformMatrix(world, relativeTo: nil)
                extras.append((.terminalShell, child))
            }
        }
        if p.kind == .gateSign, let label = p.label {
            let number = label.replacingOccurrences(of: "Gate ", with: "")
            let text = ModelEntity(mesh: .generateText(number, extrusionDepth: 0.05,
                                                       font: .systemFont(ofSize: 0.9, weight: .bold)),
                                   materials: [materials[.lamp]])
            text.components.set(HubMaterialTag(key: .lamp))
            text.position = [0.4, 0.1, 0.25]
            e.addChild(text)
        }
        extras.append((spec.layer, e))
        if [.tree, .house, .hangar, .officeBlock, .terminalHall, .controlTower].contains(p.kind) {
            blob(c, w: Float(p.size.x) * 1.4, d: Float(p.size.z) * 1.4)
        }
        return true
    }

    /// Whether an authored terminal interior ships (then the procedural
    /// shell furniture — floor, mezzanine, stairs, boards — steps aside).
    private var hasAuthoredInterior: Bool { library?.has("terminal_hall_interior") ?? false }

    private mutating func with(_ layer: HubLayer, _ key: HubMaterialKey, _ body: (inout HubMeshBatch) -> Void) {
        // Take the batch out while it grows: with the dictionary still
        // holding it, every append would copy the whole mesh (copy on
        // write), and the scene build would go quadratic.
        var batch = batches[layer]?.removeValue(forKey: key) ?? HubMeshBatch()
        body(&batch)
        batches[layer, default: [:]][key] = batch
    }

    /// Builds every layer. Returns one entity per layer, named by the layer.
    mutating func build() -> [HubLayer: Entity] {
        ground()
        for piece in layout.pieces { place(piece) }
        for piece in layout.interior.pieces { placeInterior(piece) }
        placeAuthoredInterior()
        runwayMarkings()
        standMarkings()
        airfieldLights()
        apronMasts()
        windsocks()
        perimeterFence()
        standNumbers()

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

    /// Tiles the authored glass concourse module along a pier.
    private mutating func placeConcourse(_ p: HubPiece) -> Bool {
        guard let library, library.has("concourse_glass") else { return false }
        let c = Self.f(p.center)
        let length = Float(p.size.z), width = Float(p.size.x)
        let count = max(1, Int((length / 30).rounded()))
        let module = length / Float(count)
        for i in 0..<count {
            let isTip = i == 0
            guard let e = library.instance(anyOf: isTip ? ["concourse_glass_end", "concourse_glass"] : ["concourse_glass"],
                                           materials: materials) else { continue }
            let ext = e.visualBounds(relativeTo: e).extents
            let sz = ext.z > 0.1 ? width / ext.z : 1
            e.scale = [ext.x > 0.1 ? module / ext.x : 1, sz, sz]
            // +X along the pier towards the apron (north).
            e.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
            let z = c.z - length / 2 + module * (Float(i) + 0.5)
            e.position = [c.x, 0, z]
            extras.append((.airside, e))
        }
        blob(c, w: width * 2.2, d: length * 1.1, y: 0.12)
        return true
    }

    private mutating func placeAuthoredInterior() {
        guard let library, let e = library.instance("terminal_hall_interior", materials: materials) else { return }
        let b = layout.interior.bounds
        let ext = e.visualBounds(relativeTo: e).extents
        // Authored front (+X) faces the street (south).
        if ext.x > 0.1, ext.z > 0.1 {
            let s = min(Float(b.width) / ext.z, Float(b.depth) / ext.x)
            e.scale = [s, s, s]
        }
        e.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])
        e.position = [Float(b.center.x), 0, Float(b.center.z)]
        extras.append((.interior, e))
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
        if placeAuthored(p) { return }
        if p.kind == .pier, placeConcourse(p) { return }
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
        case .roundabout: roundabout(p)
        case .apartmentBlock: apartments(p)
        case .crosswalk: crosswalk(p)
        case .standMarking: break // drawn from the stands themselves
        case .terminalHall: terminal(p)
        case .pier: pier(p)
        case .jetBridge: jetBridge(p)
        case .gateSign: gateSign(p)
        case .controlTower: tower(p)
        case .hangar: hangar(p)
        case .cargoShed:
            with(.airside, .buildingShade) { $0.roundedBox(center: c, size: [w, h, d], bevel: 0.5) }
            with(.airside, .roof) { $0.roundedBox(center: c + [0, h, 0], size: [w + 1.5, 0.8, d + 1.5], bevel: 0.3) }
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
        with(.airside, .buildingShade) { $0.roundedBox(center: c, size: [w, 1.6, d], bevel: 0.3) }
        // Side walls (solid, white) stay up in the cutaway: the doll's-house
        // frame of reference shot C.
        with(.airside, .building) {
            $0.roundedBox(center: [c.x - w / 2 + 2, 1.6, c.z], size: [4, glassTop - 1.6, d], bevel: 0.5)
            $0.roundedBox(center: [c.x + w / 2 - 2, 1.6, c.z], size: [4, glassTop - 1.6, d], bevel: 0.5)
        }
        with(.terminalShell, .building) {
            // Floor band between levels on the landside face.
            $0.box(center: [c.x, 9.5, c.z + d / 2 - 0.4], size: [w, 1.0, 1.0])
        }
        with(.airside, .building) {
            $0.box(center: [c.x, 9.5, c.z - d / 2 + 0.4], size: [w, 1.0, 1.0])
            // The roof's edge on the back and the ends: it stays when the
            // roof lifts off, framing the cutaway like the reference's.
            // Kept just inside the roof slab, so it never shows through it.
            $0.roundedBox(center: [c.x, glassTop, c.z - d / 2 + 0.8], size: [w + 2, 1.4, 1.6], bevel: 0.4)
            $0.roundedBox(center: [c.x - w / 2 + 0.8, glassTop, c.z], size: [1.6, 1.4, d + 3], bevel: 0.4)
            $0.roundedBox(center: [c.x + w / 2 - 0.8, glassTop, c.z], size: [1.6, 1.4, d + 3], bevel: 0.4)
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
        // Roof: a white slab carrying three glazed barrel vaults along the
        // hall, white ribs across them, and plant boxes (reference shot A).
        with(.terminalRoof, .roof) {
            $0.roundedBox(center: [c.x, glassTop, c.z], size: [w + 3, 1.6, d + 5], bevel: 0.6, bottom: true)
        }
        // The vaults stop short of the lounge site on the roof's east end
        // (`HubLayout.facilitySites`), where the player's lounge is built.
        let west = c.x - w * 0.43
        let east = layout.site(.lounge).map { Float($0.footprint.minX) - 4 } ?? c.x + w * 0.43
        let vaultLength = max(w * 0.4, east - west)
        let vaultX = west + vaultLength / 2
        let lanes: [Float] = [-d * 0.28, 0, d * 0.28]
        for dz in lanes {
            let frame = HubMeshBatch.translation([vaultX, glassTop + 1.6, c.z + dz]) * HubMeshBatch.yaw(.pi / 2)
            with(.terminalRoof, .skylight) { b in
                b.transform = frame
                b.vault(center: .zero, width: d * 0.2, depth: vaultLength, rise: 3.2, segments: 12, caps: false)
                b.transform = matrix_identity_float4x4
            }
            with(.terminalRoof, .white) { b in
                b.transform = frame
                var t = -vaultLength / 2
                while t <= vaultLength / 2 {
                    b.vault(center: [0, 0, t], width: d * 0.2 + 0.5, depth: 0.45, rise: 3.45, segments: 12, caps: false)
                    t += 9
                }
                b.transform = matrix_identity_float4x4
            }
        }
        with(.terminalRoof, .buildingShade) {
            for i in 0..<4 {
                $0.roundedBox(center: [c.x - w * 0.3 + Float(i) * w * 0.2, glassTop + 1.6, c.z + d * 0.42],
                              size: [7, 2.2, 3], bevel: 0.3)
            }
        }
        // Landside canopy on columns over the kerb; it lifts with the roof
        // so the cutaway sees the whole hall.
        with(.terminalShell, .roof) { $0.roundedBox(center: [c.x, 9, c.z + d / 2 + 6], size: [w * 0.6, 0.7, 12], bevel: 0.25) }
        with(.terminalShell, .white) {
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
        // Light from the glazed faces pooling on the kerb and the apron at
        // night.
        with(.lamps, .lampPool) {
            $0.plane(center: [c.x, 0.3, c.z + d / 2 + 9], width: w * 0.95, depth: 16)
            $0.plane(center: [c.x, 0.3, c.z - d / 2 - 7], width: w * 0.95, depth: 12)
        }
        blob(c, w: w * 1.2, d: d * 1.6, y: 0.24)
    }

    private mutating func pier(_ p: HubPiece) {
        let c = Self.f(p.center)
        let w = Float(p.size.x), d = Float(p.size.z)
        with(.airside, .building) { $0.roundedBox(center: c, size: [w, 4, d], bevel: 0.4) }
        with(.airside, .glass) { $0.box(center: c + [0, 4, 0], size: [w - 0.6, 5.2, d - 0.6]) }
        with(.airside, .white) {
            var z = c.z - d / 2 + 6
            while z < c.z + d / 2 - 2 {
                $0.box(center: [c.x - w / 2 + 0.2, 4, z], size: [0.5, 5.2, 0.5])
                $0.box(center: [c.x + w / 2 - 0.2, 4, z], size: [0.5, 5.2, 0.5])
                z += 7
            }
            // Eave beams the vault springs from.
            $0.roundedBox(center: [c.x - w / 2 - 0.2, 9.2, c.z], size: [1.4, 0.9, d + 1.4], bevel: 0.25)
            $0.roundedBox(center: [c.x + w / 2 + 0.2, 9.2, c.z], size: [1.4, 0.9, d + 1.4], bevel: 0.25)
        }
        // The glazed barrel vault along the pier, white ribs every 7 m
        // (reference shot A: the piers are glass, not boxes).
        with(.airside, .skylight) {
            $0.vault(center: c + [0, 10.1, 0], width: w + 0.6, depth: d + 1.2, rise: 5.2, segments: 16, caps: false)
        }
        with(.airside, .white) {
            var z = c.z - d / 2 - 0.4
            while z <= c.z + d / 2 + 0.5 {
                $0.vault(center: [c.x, 10.1, z], width: w + 1.0, depth: 0.5, rise: 5.45, segments: 16, caps: false)
                z += 7
            }
            // Gable ends of the vault, filled.
            $0.vault(center: [c.x, 10.1, c.z - d / 2 - 0.6], width: w + 0.6, depth: 0.3, rise: 5.2, segments: 16)
        }
        blob(c, w: w * 2.2, d: d * 1.1, y: 0.12)
    }

    private mutating func jetBridge(_ p: HubPiece) {
        let c = Self.f(p.center)
        let len = Float(p.size.x), yaw = Float(p.yaw)
        let frame = HubMeshBatch.translation(c) * HubMeshBatch.yaw(yaw)
        let tubeY: Float = 4.4, r: Float = 1.55
        // A glazed tube with white rib rings every 3 m and a white floor —
        // the reference's glass bridge, not a box (shot B).
        with(.airside, .glass) { b in
            b.transform = frame
            b.lathe([(-len / 2 + 1.6, r, tubeY), (len / 2 - 1.6, r, tubeY)], segments: 16, squash: 0.95)
            b.transform = matrix_identity_float4x4
        }
        with(.airside, .white) { b in
            b.transform = frame
            var t = -len / 2 + 2
            while t < len / 2 - 2 {
                b.lathe([(t, r + 0.12, tubeY), (t + 0.35, r + 0.12, tubeY)], segments: 16, squash: 0.95)
                t += 3
            }
            b.roundedBox(center: [0, tubeY - r - 0.1, 0], size: [len - 2.4, 0.5, 3.0], bevel: 0.15)
            // Rotunda at the root, cab at the tip.
            b.cylinder(base: [-len / 2, 2.6, 0], radius: 2.3, height: 3.9, segments: 16)
            b.roundedBox(center: [len / 2 - 1.2, 2.7, 0], size: [3.4, 3.5, 4.0], bevel: 0.3)
            b.transform = matrix_identity_float4x4
        }
        with(.airside, .darkMetal) { b in
            b.transform = frame
            // Drive column and bogie near the tip; root column; cab canopy.
            b.box(center: [len * 0.3, 0, 0], size: [0.6, tubeY - r, 2.4])
            b.roundedBox(center: [len * 0.3, 0.3, 0], size: [1.4, 0.7, 3.6], bevel: 0.15)
            b.cylinder(base: [-len / 2, 0, 0], radius: 0.8, height: 2.6, segments: 8, caps: false)
            b.box(center: [len / 2 - 0.2, 2.8, 0], size: [0.5, 3.2, 3.0])
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
            $0.roundedBox(center: c, size: [w, wall, d], bevel: 0.6)
        }
        with(.airside, .roof) { $0.vault(center: c + [0, wall, 0], width: w + 1, depth: d + 1, rise: 11, segments: 18) }
        // Ribs over the vault, as on the reference's barrel-roofed pair.
        with(.airside, .white) {
            var z = c.z - d / 2
            while z <= c.z + d / 2 {
                $0.vault(center: [c.x, wall, z], width: w + 1.6, depth: 0.6, rise: 11.35, segments: 18, caps: false)
                z += d / 6
            }
        }
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

    /// Window bands on every face of a block, one row per floor, split
    /// into panes so the night lights some and not others: the lit ones use
    /// the window material that glows warm after dusk, the rest stay dark
    /// (reference night: grids of lit windows on every building).
    private mutating func windowBands(_ c: SIMD3<Float>, w: Float, d: Float, base: Float, floors: Int, storey: Float,
                                      seed: Int) {
        let faces: [(normal: SIMD3<Float>, along: SIMD3<Float>, length: Float, offset: Float)] = [
            (SIMD3<Float>(0, 0, 1), SIMD3<Float>(1, 0, 0), w, d / 2),
            (SIMD3<Float>(0, 0, -1), SIMD3<Float>(1, 0, 0), w, d / 2),
            (SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1), d, w / 2),
            (SIMD3<Float>(-1, 0, 0), SIMD3<Float>(0, 0, 1), d, w / 2),
        ]
        for f in 0..<floors {
            let y = base + Float(f) * storey + storey * 0.3
            for (k, face) in faces.enumerated() {
                let panes = max(2, Int(face.length / 9))
                let pitch = (face.length - 2) / Float(panes)
                for i in 0..<panes {
                    let lit = (seed &+ f &* 7 &+ k &* 13 &+ i &* 5) % 5 != 0
                    let along = -face.length / 2 + 1 + (Float(i) + 0.5) * pitch
                    let at = c + face.normal * (face.offset + 0.06) + face.along * along + SIMD3<Float>(0, y, 0)
                    let size: SIMD3<Float> = face.normal.x != 0 ? [0.12, storey * 0.45, pitch - 1.4]
                                                                : [pitch - 1.4, storey * 0.45, 0.12]
                    with(.landside, lit ? .windowDark : .windowUnlit) { $0.box(center: at, size: size) }
                }
            }
        }
    }

    private mutating func office(_ p: HubPiece) {
        let c = Self.f(p.center)
        let w = Float(p.size.x), h = Float(p.size.y), d = Float(p.size.z)
        let floors = max(1, min(8, p.variant))
        with(.landside, .building) { $0.box(center: c + [0, 0.6, 0], size: [w, h, d], top: false) }
        windowBands(c, w: w, d: d, base: 0.6, floors: floors, storey: h / Float(floors), seed: Int(abs(c.x * 3 + c.z)))
        with(.landside, .roof) {
            $0.roundedBox(center: c + [0, h + 0.6, 0], size: [w + 0.8, 0.9, d + 0.8], bevel: 0.3)
            $0.roundedBox(center: c + [w * 0.15, h + 1.5, -d * 0.1], size: [w * 0.3, 2.2, d * 0.3], bevel: 0.3)
        }
        with(.landside, .buildingShade) { $0.box(center: c, size: [w + 1, 0.6, d + 1]) }
        blob(c, w: w + 14, d: d + 14)
    }

    /// Mid-rise apartments behind the villas (reference shot D): window
    /// bands, a white balcony slab per floor on the street face, a roof
    /// with plant.
    private mutating func apartments(_ p: HubPiece) {
        let c = Self.f(p.center)
        let w = Float(p.size.x), h = Float(p.size.y), d = Float(p.size.z)
        let floors = max(1, min(8, p.variant))
        let storey = h / Float(floors)
        with(.landside, .building) { $0.box(center: c + [0, 0.6, 0], size: [w, h, d], top: false) }
        windowBands(c, w: w, d: d, base: 0.6, floors: floors, storey: storey, seed: Int(abs(c.x * 5 + c.z)))
        with(.landside, .white) {
            for f in 1..<floors {
                let y = 0.6 + Float(f) * storey - 0.2
                $0.roundedBox(center: c + [0, y, d / 2 + 0.9], size: [w * 0.92, 0.3, 1.8], bevel: 0.1)
                $0.box(center: c + [0, y + 0.3, d / 2 + 1.75], size: [w * 0.92, 0.9, 0.1])
            }
        }
        with(.landside, .houseWood) {
            // Wood-clad end bays.
            $0.box(center: c + [-w / 2 - 0.05, 0.6, 0], size: [0.2, h, d * 0.5])
        }
        with(.landside, .roof) {
            $0.roundedBox(center: c + [0, h + 0.6, 0], size: [w + 1, 0.8, d + 1], bevel: 0.3)
            $0.roundedBox(center: c + [-w * 0.2, h + 1.4, 0], size: [w * 0.25, 2.4, d * 0.4], bevel: 0.3)
        }
        with(.landside, .buildingShade) { $0.box(center: c, size: [w + 1, 0.6, d + 1]) }
        with(.lamps, .lampPool) { $0.plane(center: c + [0, 0.32, d / 2 + 6], width: w + 8, depth: 12) }
        blob(c, w: w + 16, d: d + 16)
    }

    /// The reference's modern villa: two storeys, flat roofs with a navy
    /// fascia, big dark-framed glazing, wood cladding, a terrace by the
    /// pool. Three variants mirror and shuffle the volumes.
    private mutating func house(_ p: HubPiece) {
        let c = Self.f(p.center)
        let w = Float(p.size.x), d = Float(p.size.z)
        let storey: Float = 3.6
        let v = p.variant
        let m: Float = v == 1 ? -1 : 1 // mirror
        // Ground floor: a solid white volume at the back, a glazed living
        // wing to the front.
        let back = c + [0, 0, -d * 0.22]
        let wing = c + [m * w * 0.18, 0, d * 0.24]
        let wingW = w * 0.62, wingD = d * 0.48
        // Upper floor cantilevers over the wing.
        let upper = c + [-m * w * 0.08, storey, v == 2 ? d * 0.02 : -d * 0.08]
        let upperW = w * 0.7, upperD = d * 0.6
        with(.landside, .building) {
            $0.roundedBox(center: back, size: [w, storey, d * 0.56], bevel: 0.18)
            $0.roundedBox(center: upper, size: [upperW, storey, upperD], bevel: 0.18)
        }
        with(.landside, .glass) {
            $0.box(center: wing, size: [wingW - 0.3, storey - 0.3, wingD - 0.3])
            // The upper floor's long window band on the garden face.
            $0.box(center: upper + [m * upperW * 0.08, 0.7, upperD / 2 + 0.02], size: [upperW * 0.7, storey * 0.55, 0.12])
        }
        with(.landside, .darkMetal) {
            // Window frames: posts around the glazed wing and the band.
            for k in 0...4 {
                let x = wing.x - wingW / 2 + Float(k) * wingW / 4
                $0.box(center: [x, 0, wing.z + wingD / 2 - 0.1], size: [0.16, storey - 0.3, 0.16])
            }
            for side: Float in [-1, 1] {
                $0.box(center: [wing.x + side * (wingW / 2 - 0.1), 0, wing.z], size: [0.16, storey - 0.3, wingD])
            }
            $0.box(center: upper + [m * upperW * 0.08, 0.6, upperD / 2 + 0.05], size: [upperW * 0.72, 0.12, 0.16])
            $0.box(center: upper + [m * upperW * 0.08, 0.7 + storey * 0.55, upperD / 2 + 0.05], size: [upperW * 0.72, 0.12, 0.16])
        }
        with(.landside, .houseWood) {
            // Wood cladding on one end of the upper floor and beside the door.
            $0.box(center: upper + [-m * (upperW / 2 + 0.06), 0, 0], size: [0.18, storey, upperD * 0.96])
            for k in 0..<8 {
                $0.box(center: back + [-m * (w * 0.45 - Float(k) * 0.42), 0, d * 0.28 + 0.06], size: [0.2, storey * 0.92, 0.2])
            }
            // Terrace deck in front of the wing, towards the pool.
            $0.box(center: wing + [0, 0, wingD / 2 + 2.2], size: [wingW * 0.9, 0.25, 4.4])
        }
        // Flat roofs: a white slab over a navy fascia, overhanging.
        with(.landside, .houseRoof) {
            $0.box(center: wing + [0, storey - 0.05, 0], size: [wingW + 1.2, 0.35, wingD + 1.4])
            $0.box(center: upper + [0, storey - 0.05, 0], size: [upperW + 1.2, 0.35, upperD + 1.2])
        }
        with(.landside, .roof) {
            $0.roundedBox(center: wing + [0, storey + 0.3, 0], size: [wingW + 1.1, 0.2, wingD + 1.3], bevel: 0.08)
            $0.roundedBox(center: upper + [0, storey + 0.3, 0], size: [upperW + 1.1, 0.2, upperD + 1.1], bevel: 0.08)
        }
        with(.landside, .windowDark) {
            $0.box(center: back + [m * w * 0.3, 0.8, -d * 0.28 - 0.02], size: [w * 0.25, storey * 0.5, 0.15])
            $0.box(center: upper + [0, 0.8, -upperD / 2 - 0.02], size: [upperW * 0.4, storey * 0.5, 0.15])
        }
        // Window light spilling onto the terrace and lawn at night.
        with(.lamps, .lampPool) {
            $0.plane(center: wing + [0, 0.42, wingD / 2 + 3], width: wingW + 6, depth: 9)
        }
        // A car on the drive.
        let car = c + [w * 0.25, 0.3, d / 2 + 6]
        with(.landside, .cloth(v * 3)) {
            $0.roundedBox(center: car, size: [1.9, 0.75, 4.4], bevel: 0.2)
            $0.roundedBox(center: car + [0, 0.75, -0.3], size: [1.7, 0.6, 2.4], bevel: 0.2)
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
        // Clipped hedges inside the side walls.
        with(.landside, .tree(1)) {
            $0.roundedBox(center: c + [-w / 2 + 1.4, 0, 2], size: [1.6, 1.5, d * 0.7], bevel: 0.5)
            $0.roundedBox(center: c + [w / 2 - 1.4, 0, -4], size: [1.6, 1.5, d * 0.5], bevel: 0.5)
        }
    }

    /// A roundabout at the avenue's terminal junctions: an asphalt ring,
    /// a white kerb, a planted island with a tree.
    private mutating func roundabout(_ p: HubPiece) {
        let c = Self.f(p.center)
        let r = Float(p.size.x) / 2
        // Above the crossing roads' lane dashes (0.13), so none show through.
        with(.ground, .asphalt) { $0.cylinder(base: c, radius: r, height: 0.16, segments: 40) }
        with(.markings, .marking) {
            // Dashed lane line round the ring.
            for k in 0..<18 {
                let a = Float(k) / 18 * 2 * .pi
                let mid = (r + 11) / 2
                $0.box(center: c + [cos(a) * mid, 0.16, -sin(a) * mid], size: [0.35, 0.012, 2.6], yaw: a)
            }
        }
        with(.landside, .white) { $0.cylinder(base: c, radius: 11, height: 0.42, segments: 32) }
        with(.landside, .grassBright) { $0.cylinder(base: c, radius: 10.3, height: 0.5, segments: 32) }
        tree(HubPiece(.tree, center: p.center, size: HubVec(9, 12, 9), variant: 1))
        with(.landside, .tree(2)) {
            for k in 0..<6 {
                let a = Float(k) / 6 * 2 * .pi
                $0.sphere(center: c + [cos(a) * 6.5, 0.9, -sin(a) * 6.5], radius: 1.3, segments: 8, rings: 5)
            }
        }
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

    // MARK: Airfield furniture

    /// Edge, threshold and approach lights on every runway, blue edge
    /// lights on the taxiways. Matte fittings by day; after dusk they glow
    /// and the bloom pass turns them into the reference's strings of light.
    /// A little over scale, as everything in the diorama is.
    private mutating func airfieldLights() {
        for runway in layout.runways {
            let a = Self.f(runway.thresholdA), b = Self.f(runway.thresholdB)
            let length = simd_distance(a, b)
            guard length > 1 else { continue }
            let dir = simd_normalize(b - a)
            let yaw = atan2(-dir.z, dir.x)
            let half = Float(runway.width) / 2
            let frame = HubMeshBatch.translation(a) * HubMeshBatch.yaw(yaw)
            with(.lamps, .runwayLight) { batch in
                batch.transform = frame
                var t: Float = 20
                while t < length - 20 {
                    for side: Float in [-1, 1] {
                        batch.box(center: [t, 0, side * (half + 2.5)], size: [1.4, 0.7, 1.4])
                    }
                    t += 60
                }
                // Approach lights: a centreline of bars out from each end,
                // with a crossbar 150 m out.
                for end: Float in [0, 1] {
                    let out: Float = end == 0 ? -1 : 1
                    let base: Float = end == 0 ? 0 : length
                    var d: Float = 30
                    while d <= 300 {
                        batch.box(center: [base + out * d, 0, 0], size: [1.2, 0.9, d == 150 ? 30 : 6])
                        d += 30
                    }
                }
                batch.transform = matrix_identity_float4x4
            }
            with(.lamps, .thresholdLight) { batch in
                batch.transform = frame
                for x: Float in [-3, length + 3] {
                    var z = -half
                    while z <= half + 0.01 {
                        batch.box(center: [x, 0, z], size: [1.2, 0.7, 1.2])
                        z += 4.5
                    }
                }
                batch.transform = matrix_identity_float4x4
            }
        }
        for p in layout.pieces where p.kind == .taxiway {
            let c = Self.f(p.center)
            let alongX = p.size.x >= p.size.z
            let length = Float(alongX ? p.size.x : p.size.z), width = Float(alongX ? p.size.z : p.size.x)
            with(.lamps, .taxiEdgeLight) { batch in
                var t = -length / 2 + 15
                while t < length / 2 - 15 {
                    for side: Float in [-1, 1] {
                        let off = side * (width / 2 + 1.5)
                        let at: SIMD3<Float> = alongX ? [c.x + t, 0, c.z + off] : [c.x + off, 0, c.z + t]
                        batch.box(center: at, size: [1.0, 0.6, 1.0])
                    }
                    t += 45
                }
            }
        }
    }

    /// Floodlight masts along the apron's open edge: tall poles with a lamp
    /// head, and a wide pool of light on the concrete at night.
    private mutating func apronMasts() {
        let terminalZ = Float(layout.terminal.minZ)
        for p in layout.pieces where p.kind == .apron && p.variant == 0 {
            let r = p.groundBounds
            // The edge away from the terminal faces the taxiway.
            let farZ = Float(abs(r.minZ - Double(terminalZ)) > abs(r.maxZ - Double(terminalZ)) ? r.minZ : r.maxZ)
            let inward: Float = farZ < Float(r.center.z) ? 1 : -1
            let count = max(2, Int(r.width / 170) + 1)
            for i in 0..<count {
                let x = Float(r.minX) + 20 + (Float(r.width) - 40) * Float(i) / Float(max(1, count - 1))
                let base = SIMD3<Float>(x, 0, farZ + inward * 6)
                with(.airside, .darkMetal) {
                    $0.cylinder(base: base, radius: 0.55, topRadius: 0.35, height: 32, segments: 8)
                    $0.box(center: base + [0, 31.4, 0], size: [5.4, 0.4, 0.6])
                }
                with(.lamps, .lamp) { $0.box(center: base + [0, 31.8, inward * 0.5], size: [5.0, 1.0, 1.0]) }
                with(.lamps, .lampPool) {
                    $0.plane(center: base + [0, 0.26, inward * 26], width: 64, depth: 56)
                }
                blob(base, w: 3, d: 3)
            }
        }
    }

    /// A striped windsock beside each runway's first threshold.
    private mutating func windsocks() {
        for runway in layout.runways {
            let a = Self.f(runway.thresholdA), b = Self.f(runway.thresholdB)
            guard simd_distance(a, b) > 1 else { continue }
            let dir = simd_normalize(b - a)
            let side = SIMD3<Float>(-dir.z, 0, dir.x)
            let base = a + dir * 260 + side * (Float(runway.width) / 2 + 55)
            with(.airside, .darkMetal) { $0.cylinder(base: base, radius: 0.2, height: 9, segments: 6) }
            // The sock streams downwind: four bands narrowing away from the
            // mast, alternating orange and white.
            let wind = simd_normalize(dir * 0.7 + side * 0.7)
            let yaw = atan2(-wind.z, wind.x)
            for k in 0..<4 {
                let along = 0.9 + Float(k) * 1.3
                let size = 1.25 - Float(k) * 0.18
                let key: HubMaterialKey = k % 2 == 0 ? .cone : .white
                with(.airside, key) {
                    $0.box(center: base + wind * along + [0, 8.2 - Float(k) * 0.12 - size / 2, 0],
                           size: [1.3, size, size], yaw: yaw)
                }
            }
            with(.markings, .marking) { $0.cylinder(base: base + [0, 0.1, 0], radius: 7, height: 0.05, segments: 20) }
        }
    }

    /// The airside fence: posts and two rails round the far three sides of
    /// the airfield, the terminal and its kerb closing the fourth.
    private mutating func perimeterFence() {
        let airside = layout.pieces.filter { [.runway, .taxiway, .apron].contains($0.kind) }.map(\.groundBounds)
        guard var r = airside.first else { return }
        for b in airside.dropFirst() { r = r.union(b) }
        let minX = Float(r.minX) - 60, maxX = Float(r.maxX) + 60, minZ = Float(r.minZ) - 60
        let maxZ = Float(layout.terminal.minZ) - 5
        guard maxZ > minZ + 20 else { return }
        let runs: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([minX, 0, maxZ], [minX, 0, minZ]), ([minX, 0, minZ], [maxX, 0, minZ]), ([maxX, 0, minZ], [maxX, 0, maxZ]),
        ]
        with(.airside, .darkMetal) { batch in
            for (a, b) in runs {
                let length = simd_distance(a, b)
                let d = simd_normalize(b - a)
                let yaw = atan2(-d.z, d.x)
                let mid = (a + b) / 2
                for y: Float in [1.2, 2.6] {
                    batch.box(center: mid + [0, y, 0], size: [length, 0.14, 0.14], yaw: yaw)
                }
                var t: Float = 0
                while t <= length {
                    batch.box(center: a + d * t, size: [0.22, 3, 0.22])
                    t += 14
                }
            }
        }
    }

    /// Stand numbers painted at the head of each lead-in line, reading from
    /// the taxilane towards the gate.
    private mutating func standNumbers() {
        for stand in layout.stands {
            let fwd = SIMD3<Float>(Float(cos(stand.heading)), 0, Float(-sin(stand.heading)))
            let len = Float(HubAircraftEnvelope.length(stand.maxCategory))
            // Beside the lead-in line, not on it.
            let right = SIMD3<Float>(fwd.z * -1, 0, fwd.x)
            let at = Self.f(stand.nose) - fwd * (len + 18) + right * 7
            let mesh = MeshResource.generateText("\(stand.gate)", extrusionDepth: 0.02,
                                                 font: .systemFont(ofSize: 6, weight: .heavy))
            let text = ModelEntity(mesh: mesh, materials: [materials[.marking]])
            text.components.set(HubMaterialTag(key: .marking))
            let b = mesh.bounds
            text.position = [-b.center.x, -b.center.y, 0]
            let holder = Entity()
            holder.addChild(text)
            // Lay the text flat (its up becomes −z), then turn it so its up
            // points along the lead-in towards the nose.
            holder.orientation = simd_quatf(angle: Float(stand.heading) - .pi / 2, axis: [0, 1, 0])
                * simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            holder.position = [at.x, 0.13, at.z]
            extras.append((.markings, holder))
        }
    }

    // MARK: Interior (cutaway)

    private mutating func placeInterior(_ p: HubPiece) {
        if placeAuthored(p, floor: 1.7) { return }
        if hasAuthoredInterior, [.floorSlab, .mezzanine, .escalator, .flightBoard].contains(p.kind) { return }
        let c = Self.f(p.center)
        let w = Float(p.size.x), h = Float(p.size.y), d = Float(p.size.z)
        let yaw = Float(p.yaw)
        let fl: Float = 1.7 // floor level inside the hall
        let base = SIMD3<Float>(c.x, fl, c.z)
        switch p.kind {
        case .floorSlab:
            with(.interior, .concreteLight) { $0.box(center: c + [0, 1.6, 0], size: [w, 0.1, d]) }
            // Walkway strips, slightly darker, as in the reference's floor.
            with(.interior, .concrete) {
                $0.box(center: c + [0, 1.7, d * 0.18], size: [w - 4, 0.02, 3])
                $0.box(center: c + [0, 1.7, -d * 0.12], size: [w - 4, 0.02, 3])
            }
        case .mezzanine:
            with(.interior, .building) {
                $0.box(center: c, size: [w, 0.6, d], bottom: true)
                // Back wall up to the roof, where the departure board hangs.
                $0.box(center: c + [0, -c.y + fl, -d / 2 - 0.2], size: [w, 14, 0.4])
            }
            with(.interior, .glass) { $0.box(center: c + [0, 0.6, d / 2 - 0.1], size: [w, 1.1, 0.12]) }
            with(.interior, .darkMetal) { $0.box(center: c + [0, 1.7, d / 2 - 0.1], size: [w, 0.08, 0.16]) }
            with(.interior, .white) {
                var x = c.x - w / 2 + 6
                while x < c.x + w / 2 {
                    $0.box(center: [x, fl, c.z + d / 2 - 1], size: [0.7, c.y - fl, 0.7])
                    x += 12
                }
            }
        case .escalator:
            // A straight stair with glass sides, rising from the hall floor
            // (front, +z) to the mezzanine (back, -z).
            let rise: Float = 4.9, run = d // hall floor (1.7) to mezzanine deck (6.6)
            let steps = 18
            with(.interior, .white) { b in
                for i in 0..<steps {
                    let t = Float(i) / Float(steps)
                    b.box(center: [c.x, fl + rise * t - 0.05, c.z + run / 2 - run * t - run / Float(steps) / 2],
                          size: [w, rise / Float(steps) + 0.05, run / Float(steps)])
                }
            }
            with(.interior, .glass) { b in
                for side: Float in [-1, 1] {
                    b.transform = HubMeshBatch.translation([c.x + side * (w / 2 + 0.05), fl, c.z])
                        * HubMeshBatch.roll(atan2(rise, run))
                    b.box(center: [0, 0.4, 0], size: [0.1, 1.1, sqrt(rise * rise + run * run)])
                    b.transform = matrix_identity_float4x4
                }
            }
        case .checkInDesk:
            with(.interior, .white) { $0.box(center: base, size: [w, h, d], yaw: yaw) }
            with(.interior, .darkMetal) { $0.box(center: base + [0, h, 0], size: [w + 0.2, 0.08, d + 0.2], yaw: yaw) }
        case .kiosk:
            // White rounded pedestal with a tilted blue screen.
            with(.interior, .white) {
                $0.box(center: base, size: [0.55, 1.1, 0.45])
                $0.box(center: base + [0, 1.1, -0.05], size: [0.7, 0.55, 0.3])
            }
            with(.interior, .kioskScreen) { b in
                b.transform = HubMeshBatch.translation(base + [0, 1.38, 0.12]) * HubMeshBatch.roll(-0.45)
                b.box(center: [0, -0.22, 0], size: [0.6, 0.44, 0.04])
                b.transform = matrix_identity_float4x4
            }
        case .securityLane:
            // An e-gate: white pedestal with glass flaps.
            with(.interior, .white) { $0.box(center: base, size: [0.35, h, d]) }
            with(.interior, .glass) {
                $0.box(center: base + [0.5, 0.5, 0], size: [0.7, 0.8, 0.06])
            }
            with(.interior, .screen) { $0.box(center: base + [0, h, d / 2 - 0.3], size: [0.3, 0.25, 0.05]) }
        case .metalDetector:
            with(.interior, .white) {
                $0.box(center: base + [-w / 2, 0, 0], size: [0.25, h, d])
                $0.box(center: base + [w / 2, 0, 0], size: [0.25, h, d])
                $0.box(center: base + [0, h, 0], size: [w + 0.25, 0.3, d])
            }
        case .queueBarrier:
            with(.interior, .darkMetal) {
                let rows = max(2, Int(d / 2.4))
                for r in 0...rows {
                    let z = c.z - d / 2 + Float(r) * d / Float(rows)
                    // Alternate gaps at the ends make the maze.
                    let shift: Float = r % 2 == 0 ? 0.8 : -0.8
                    $0.box(center: [c.x + shift, fl + 0.9, z], size: [w - 1.6, 0.06, 0.05])
                    for k in 0...3 {
                        $0.cylinder(base: [c.x + shift - (w - 1.6) / 2 + Float(k) * (w - 1.6) / 3, fl, z],
                                    radius: 0.05, height: 0.95, segments: 5, caps: false)
                    }
                }
            }
        case .shopShelf:
            with(.interior, .houseWood) {
                $0.box(center: base, size: [w, h, d], yaw: yaw)
            }
            // Rows of stock on the front face: small boxes in mixed colours
            // and heights, so the shelves read stocked (reference shot C).
            let colours = [2, 3, 4, 6, 0, 1, 5]
            let face = SIMD3<Float>(sin(yaw), 0, cos(yaw)) * (d / 2 + 0.02)
            let along = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
            let perRow = max(3, Int(w * 0.9 / 0.5))
            let rowH = (h - 0.5) / 4
            for k in 0..<4 {
                for i in 0..<perRow {
                    let n = i * 7 + k * 3 + p.variant
                    let key = HubMaterialKey.cloth(colours[n % colours.count])
                    let x = -w * 0.45 + (Float(i) + 0.5) * (w * 0.9 / Float(perRow))
                    let tall = rowH * (0.45 + 0.25 * Float(n % 3))
                    with(.interior, key) {
                        $0.box(center: base + face + along * x + [0, 0.3 + Float(k) * rowH, 0],
                               size: [w * 0.9 / Float(perRow) * 0.8, tall, 0.2], yaw: yaw)
                    }
                }
            }
            if let label = p.label { sign(label, at: base + [0, h + 0.5, d / 2 + 0.1], width: w) }
        case .shopFront:
            // Dark fascia band with the shop's name, over an open front.
            with(.interior, .darkMetal) {
                $0.box(center: base + [0, h - 1.1, 0], size: [w, 1.1, d])
                $0.box(center: base + [-w / 2, 0, 0], size: [0.4, h, d])
                $0.box(center: base + [w / 2, 0, 0], size: [0.4, h, d])
            }
            if let label = p.label { sign(label, at: base + [0, h - 0.95, d / 2 + 0.05], width: w * 0.5) }
        case .gondola:
            with(.interior, .white) { $0.box(center: base, size: [w, h, d]) }
            for k in 0..<3 {
                with(.interior, .cloth([3, 5, 2, 6][(k + p.variant) % 4])) {
                    $0.box(center: base + [0, 0.25 + Float(k) * 0.4, 0], size: [w + 0.15, 0.25, d * 0.92])
                }
            }
        case .cafeCounter:
            with(.interior, .houseWood) { $0.box(center: base, size: [w, h, d]) }
            with(.interior, .white) { $0.box(center: base + [0, h, 0], size: [w + 0.2, 0.08, d + 0.2]) }
            with(.interior, .glass) { $0.box(center: base + [-w * 0.25, h + 0.08, 0], size: [w * 0.4, 0.45, d * 0.8]) }
            with(.interior, .darkMetal) { $0.box(center: base + [w * 0.3, h + 0.08, -d * 0.2], size: [0.7, 0.6, 0.5]) }
            if let label = p.label { sign(label, at: base + [0, h + 2.4, -d / 2], width: w * 0.5) }
        case .luggageTrolley:
            with(.interior, .white) {
                $0.box(center: base + [0, 0.25, 0], size: [w, 0.1, d])
                $0.box(center: base + [-w / 2, 0.25, 0], size: [0.08, 1.0, d])
            }
            with(.interior, .cloth(6)) {
                $0.box(center: base + [0.1, 0.35, 0], size: [w * 0.7, 0.45, d * 0.8])
                $0.box(center: base + [0.1, 0.8, 0], size: [w * 0.55, 0.35, d * 0.7])
            }
            with(.interior, .tyre) { $0.box(center: base, size: [w * 0.9, 0.25, d * 0.9]) }
        case .electricCart:
            with(.interior, .white) {
                $0.box(center: base + [0, 0.3, 0], size: [w, 0.5, d])
                $0.box(center: base + [w * 0.35, 0.8, 0], size: [0.4, 0.6, d * 0.9])
            }
            with(.interior, .darkMetal) {
                $0.box(center: base + [-w * 0.15, 0.8, 0], size: [w * 0.35, 0.15, d * 0.85])
                $0.box(center: base + [-w * 0.32, 0.95, 0], size: [0.12, 0.45, d * 0.85])
            }
            with(.interior, .tyre) { $0.box(center: base, size: [w * 0.85, 0.3, d * 0.95]) }
        case .wayfindingSign:
            with(.interior, .darkMetal) {
                $0.box(center: c + [0, fl, 0], size: [w, h, d])
                $0.box(center: c + [0, fl + h, 0], size: [0.06, 8 - c.y, 0.06])
            }
            with(.interior, .hiVis) { $0.box(center: c + [-w * 0.3, fl + h * 0.2, d / 2 + 0.01], size: [w * 0.3, h * 0.6, 0.02]) }
        case .seatRow:
            with(.interior, .darkMetal) { $0.box(center: base, size: [w, 0.45, d]) }
            with(.interior, .cloth(0)) {
                $0.box(center: base + [0, 0.45, 0.1], size: [w, 0.12, d * 0.7])
                $0.box(center: base + [0, 0.45, -d / 2 + 0.15], size: [w, 0.6, 0.15])
            }
        case .flightBoard:
            // Two big screens side by side on a dark frame (reference shot C).
            with(.interior, .darkMetal) { $0.box(center: c + [0, fl, 0], size: [w + 0.6, h + 0.6, d]) }
            with(.interior, .screen) {
                $0.box(center: c + [-w / 4 - 0.1, fl + 0.3, d / 2], size: [w / 2 - 0.3, h, 0.05])
                $0.box(center: c + [w / 4 + 0.1, fl + 0.3, d / 2], size: [w / 2 - 0.3, h, 0.05])
            }
            with(.interior, .grassBright) {
                for r in 0..<5 {
                    let y = fl + 0.6 + Float(r) * h / 5.5
                    $0.box(center: c + [-w / 4 - 0.1, y, d / 2 + 0.03], size: [w / 2 - 0.9, 0.12, 0.02])
                }
            }
            with(.interior, .marking) {
                for r in 0..<5 {
                    let y = fl + 0.6 + Float(r) * h / 5.5
                    $0.box(center: c + [w / 4 + 0.1, y, d / 2 + 0.03], size: [w / 2 - 0.9, 0.12, 0.02])
                }
            }
        case .bayPartition:
            // Glazed partition between bays: glass panes in a white frame,
            // so the next bay shows through (doll's-house rooms, shot C).
            with(.interior, .glass) { $0.box(center: base, size: [w * 0.4, h, d]) }
            with(.interior, .white) {
                $0.box(center: base + [0, h - 0.4, 0], size: [w, 0.4, d])
                $0.box(center: base, size: [w, 0.5, d])
                var z = c.z - d / 2
                while z <= c.z + d / 2 + 0.01 {
                    $0.box(center: [c.x, fl, z], size: [w, h, 0.3])
                    z += 6
                }
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

    /// A text label for shop fronts and counters.
    private mutating func sign(_ text: String, at position: SIMD3<Float>, width: Float) {
        let mesh = MeshResource.generateText(text, extrusionDepth: 0.04,
                                             font: .systemFont(ofSize: 0.7, weight: .bold))
        let label = ModelEntity(mesh: mesh, materials: [materials[.white]])
        label.components.set(HubMaterialTag(key: .white))
        let bounds = label.visualBounds(relativeTo: nil)
        label.position = position + [-bounds.extents.x / 2, -bounds.extents.y / 2, 0]
        extras.append((.interior, label))
    }
}
