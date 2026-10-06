import RealityKit
import UIKit
import simd
import AirlineEmpireCore

/// One part of a model: a mesh painted with one material.
struct HubPart {
    let mesh: MeshResource
    let material: HubMaterialKey
}

/// Procedural models (docs/HUB_VIEW_3D.md §5). Each is a set of parts,
/// cached per shape so every jet of a category shares its meshes and only
/// the livery material differs. Local frame: forward +x, up +y, right +z,
/// origin at the centre of the footprint on the ground.
@available(iOS 18.0, *)
@MainActor
final class HubModels {
    private var cache: [String: [HubPart]] = [:]

    private func parts(_ key: String, _ build: () -> [(HubMaterialKey, HubMeshBatch)]) -> [HubPart] {
        if let hit = cache[key] { return hit }
        let made = build().compactMap { material, batch in
            batch.resource(name: key).map { HubPart(mesh: $0, material: material) }
        }
        cache[key] = made
        return made
    }

    /// Builds an entity from parts, remapping material keys (for liveries).
    func entity(_ parts: [HubPart], materials: HubMaterials,
                remap: (HubMaterialKey) -> HubMaterialKey = { $0 }) -> Entity {
        let root = Entity()
        for part in parts {
            let key = remap(part.material)
            let model = ModelEntity(mesh: part.mesh, materials: [materials[key]])
            model.components.set(HubMaterialTag(key: key))
            root.addChild(model)
        }
        return root
    }

    // MARK: Aircraft

    struct AircraftMetrics {
        let length: Float
        let span: Float
        let radius: Float
        let gear: Float
        var bellyY: Float { gear }
        var axisY: Float { gear + radius }
        /// Distance from the nose to the forward left door.
        var doorFromNose: Float { length * 0.13 }
    }

    static func metrics(_ category: AircraftCategory) -> AircraftMetrics {
        let length = Float(HubAircraftEnvelope.length(category))
        let span = Float(HubAircraftEnvelope.span(category))
        let radius: Float
        switch category {
        case .turboprop: radius = 1.35
        case .regionalJet: radius = 1.5
        case .narrowbody, .largeNarrowbody: radius = 2.0
        case .widebody: radius = 2.9
        case .largeWidebody: radius = 3.2
        }
        return AircraftMetrics(length: length, span: span, radius: radius,
                               gear: category == .turboprop ? 1.1 : radius * 0.75)
    }

    func aircraft(_ category: AircraftCategory) -> [HubPart] {
        parts("aircraft.\(category.rawValue)") { Self.buildAircraft(category) }
    }

    private static func buildAircraft(_ category: AircraftCategory) -> [(HubMaterialKey, HubMeshBatch)] {
        let m = metrics(category)
        let L = m.length, r = m.radius, cy = m.axisY
        let tailX = -L / 2, noseX = L / 2
        var body = HubMeshBatch(), livery = HubMeshBatch(), accent = HubMeshBatch()
        var dark = HubMeshBatch(), metal = HubMeshBatch()

        // Fuselage: lathe from tail to nose. The tail cone sweeps up.
        let profile: [(x: Float, r: Float, y: Float)] = [
            (tailX, r * 0.12, cy + r * 0.55),
            (tailX + L * 0.06, r * 0.45, cy + r * 0.38),
            (tailX + L * 0.14, r * 0.78, cy + r * 0.18),
            (tailX + L * 0.24, r, cy),
            (noseX - L * 0.14, r, cy),
            (noseX - L * 0.08, r * 0.92, cy - r * 0.02),
            (noseX - L * 0.04, r * 0.74, cy - r * 0.06),
            (noseX - L * 0.015, r * 0.45, cy - r * 0.1),
            (noseX, r * 0.05, cy - r * 0.14),
        ]
        body.lathe(profile, segments: 22, squash: 1.05)

        // Window line and cheat line: thin bands just proud of the skin.
        dark.box(center: [-L * 0.02, cy + r * 0.22, 0], size: [L * 0.62, 0.32, 2 * r + 0.06], top: false)
        accent.box(center: [-L * 0.02, cy - r * 0.22, 0], size: [L * 0.66, 0.18, 2 * r + 0.08], top: false)
        // Cockpit glazing.
        dark.transform = HubMeshBatch.translation([noseX - L * 0.055, cy + r * 0.38, 0])
        dark.box(center: .zero, size: [L * 0.03, r * 0.22, r * 1.15], yaw: 0)
        dark.transform = matrix_identity_float4x4
        // Doors (forward left, rear left): darker outlines.
        dark.box(center: [noseX - m.doorFromNose, cy - r * 0.35, -r * 0.98], size: [0.9, r * 0.95, 0.12])

        // Wings: swept, slightly dihedral, low-set (high-set on turboprops).
        let high = category == .turboprop
        let wingY = high ? cy + r * 0.85 : cy - r * 0.45
        let rootLE = high ? L * 0.06 : L * 0.08
        let rootChord = L * (high ? 0.11 : 0.2)
        let semi = m.span / 2
        let sweep: Float = high ? 0.06 : 0.55
        let tipChord = rootChord * 0.3
        for side: Float in [-1, 1] {
            let dihedral: Float = high ? 0 : 0.06
            body.transform = HubMeshBatch.translation([0, wingY, 0])
                * float4x4(simd_quatf(angle: -side * dihedral, axis: [1, 0, 0]))
            let rootZ = side * r * 0.6, tipZ = side * semi
            let tipLE = rootLE - semi * sweep
            let poly: [SIMD2<Float>] = [
                [rootLE, rootZ], [rootLE - rootChord, rootZ],
                [tipLE - tipChord, tipZ], [tipLE, tipZ],
            ]
            body.slab(poly, thickness: high ? 0.45 : 0.55)
            body.transform = matrix_identity_float4x4
            // Winglet in livery.
            if !high {
                let wl = HubMeshBatch.translation([tipLE - tipChord * 0.6, wingY + semi * dihedral + 0.2, tipZ])
                livery.transform = wl
                livery.box(center: .zero, size: [tipChord * 0.9, 2.0 + r * 0.3, 0.25])
                livery.transform = matrix_identity_float4x4
            }
            // Engines.
            let engines = HubAircraftEnvelope.engines(category)
            let stations: [Float] = engines == 4 ? [0.36, 0.66] : [high ? 0.3 : 0.34]
            for s in stations {
                let ez = side * semi * s
                let eLE = rootLE - (semi * s) * sweep + (high ? L * 0.05 : L * 0.06)
                let er: Float = high ? r * 0.42 : r * (category.isWidebody ? 0.48 : 0.5)
                let elen: Float = high ? L * 0.13 : L * (category.isWidebody ? 0.11 : 0.12)
                let ey = high ? wingY - er * 0.2 : wingY - er - 0.25
                livery.transform = HubMeshBatch.translation([eLE - elen, ey, ez])
                livery.lathe([(0, er * 0.55, 0), (elen * 0.25, er * 0.92, 0), (elen * 0.8, er, 0), (elen, er * 0.92, 0)],
                             segments: 16)
                livery.transform = matrix_identity_float4x4
                dark.transform = HubMeshBatch.translation([eLE, ey, ez])
                dark.box(center: [-0.02, -er * 0.8, 0], size: [0.06, er * 1.6, er * 1.6])
                dark.transform = matrix_identity_float4x4
                accent.transform = HubMeshBatch.translation([eLE - 0.01, ey, ez])
                accent.lathe([(-0.4, er * 0.96, 0), (0.05, er * 0.96, 0)], segments: 16)
                accent.transform = matrix_identity_float4x4
                // Pylon.
                body.box(center: [eLE - elen * 0.55, ey + er * 0.6, ez], size: [elen * 0.6, high ? er * 0.2 : 0.9, 0.35])
                if high {
                    // Propeller disc.
                    dark.transform = HubMeshBatch.translation([eLE + 0.15, ey, ez]) * HubMeshBatch.pitch(-.pi / 2)
                    dark.cylinder(base: .zero, radius: r * 1.25, height: 0.06, segments: 20)
                    dark.transform = matrix_identity_float4x4
                }
            }
        }

        // Horizontal stabiliser.
        let hsY = high ? cy + r * 2.4 : cy + r * 0.45
        let hsRoot = tailX + L * 0.12, hsChord = L * 0.09, hsSemi = m.span * 0.19
        for side: Float in [-1, 1] {
            let poly: [SIMD2<Float>] = [
                [hsRoot, side * r * 0.3], [hsRoot - hsChord, side * r * 0.3],
                [hsRoot - hsChord * 0.8 - hsSemi * 0.5, side * hsSemi], [hsRoot - hsSemi * 0.5, side * hsSemi],
            ]
            livery.transform = HubMeshBatch.translation([0, hsY, 0])
            livery.slab(poly, thickness: 0.3)
            livery.transform = matrix_identity_float4x4
        }

        // Vertical fin: a swept quad in the xy plane, extruded in z.
        let finBase = cy + r * 0.6
        let finRoot = tailX + L * 0.24, finRootChord = L * 0.2
        let finH = r * (category.isWidebody ? 3.6 : 3.2) * (high ? 1.1 : 1)
        let finTipLE = finRoot - finH * 0.8, finTipChord = finRootChord * 0.45
        livery.transform = HubMeshBatch.roll(.pi / 2)
        // After rolling +90° about x, slab's xz polygon lies in the xy plane
        // with z → -y; build the polygon in (x, -height) accordingly.
        livery.slab([
            [finRoot, -finBase], [finTipLE, -(finBase + finH)],
            [finTipLE - finTipChord, -(finBase + finH)], [finRoot - finRootChord, -finBase],
        ], thickness: 0.45)
        livery.transform = matrix_identity_float4x4
        // Fin flash in the accent colour.
        accent.transform = HubMeshBatch.roll(.pi / 2)
        accent.slab([
            [finRoot - finH * 0.45, -(finBase + finH * 0.55)], [finTipLE - 0.2, -(finBase + finH * 0.92)],
            [finTipLE - finTipChord * 0.6, -(finBase + finH * 0.92)], [finRoot - finH * 0.45 - finRootChord * 0.5, -(finBase + finH * 0.55)],
        ], thickness: 0.5)
        accent.transform = matrix_identity_float4x4

        // Landing gear.
        for (x, z) in [(noseX - L * 0.12, Float(0)), (-L * 0.04, r * 0.7), (-L * 0.04, -r * 0.7)] {
            metal.cylinder(base: [x, 0.35, z], radius: 0.12, height: m.gear - 0.2, segments: 6, caps: false)
            metal.transform = HubMeshBatch.translation([x, 0.38, z]) * HubMeshBatch.roll(.pi / 2)
            metal.cylinder(base: [0, -0.35, 0], radius: 0.38, height: 0.7, segments: 10)
            metal.transform = matrix_identity_float4x4
        }

        return [(.white, body), (.livery(.azure), livery), (.liveryAccent(.azure), accent),
                (.windowDark, dark), (.tyre, metal)]
    }

    // MARK: Ground vehicles

    enum Vehicle: String, CaseIterable {
        case fuelTruck, tug, beltLoader, cateringTruck, baggageTrain, bus, car, golfCart, tanker, serviceVan
    }

    func vehicle(_ v: Vehicle) -> [HubPart] {
        parts("vehicle.\(v.rawValue)") { Self.buildVehicle(v) }
    }

    private static func wheels(_ batch: inout HubMeshBatch, xs: [Float], halfTrack: Float, radius: Float = 0.5) {
        for x in xs {
            for z in [-halfTrack, halfTrack] {
                batch.transform = HubMeshBatch.translation([x, radius, z]) * HubMeshBatch.roll(.pi / 2)
                batch.cylinder(base: [0, -0.2, 0], radius: radius, height: 0.4, segments: 10)
                batch.transform = matrix_identity_float4x4
            }
        }
    }

    private static func buildVehicle(_ v: Vehicle) -> [(HubMaterialKey, HubMeshBatch)] {
        var white = HubMeshBatch(), dark = HubMeshBatch(), tyre = HubMeshBatch()
        var hi = HubMeshBatch(), glass = HubMeshBatch(), accent = HubMeshBatch()
        switch v {
        case .fuelTruck, .tanker:
            white.box(center: [3.2, 0.9, 0], size: [2.2, 2.3, 2.4])                 // cab
            glass.box(center: [4.31, 2.0, 0], size: [0.05, 0.9, 2.1])
            dark.box(center: [-0.6, 0.7, 0], size: [7.6, 0.4, 2.2])                   // chassis
            white.transform = HubMeshBatch.translation([-4.2, 2.35, 0])
            white.lathe([(0, 1.0, 0), (0.25, 1.25, 0), (5.6, 1.25, 0), (5.85, 1.0, 0)], segments: 16, squash: 0.9)
            white.transform = matrix_identity_float4x4
            accent.box(center: [-1.4, 2.0, 0], size: [2.4, 0.5, 2.56], top: false)  // tank band
            wheels(&tyre, xs: [3.1, -1.6, -3.0], halfTrack: 1.05)
            return [(.white, white), (.windowDark, glass), (.darkMetal, dark), (.tyre, tyre),
                    (v == .tanker ? .liveryAccent(.ember) : .hiVis, accent)]
        case .tug:
            white.box(center: [0, 0.5, 0], size: [4.2, 1.0, 2.4])
            hi.box(center: [-0.9, 1.5, 0], size: [1.4, 1.0, 1.8])
            glass.box(center: [-0.9, 2.05, 0], size: [1.2, 0.08, 1.6])
            wheels(&tyre, xs: [1.4, -1.4], halfTrack: 1.0, radius: 0.45)
            return [(.white, white), (.hiVis, hi), (.windowDark, glass), (.tyre, tyre)]
        case .beltLoader:
            white.box(center: [0, 0.5, 0], size: [5.0, 0.8, 1.9])
            white.box(center: [-1.6, 1.3, 0], size: [1.2, 1.0, 1.5])
            dark.transform = HubMeshBatch.translation([0.4, 1.6, 0]) * HubMeshBatch.pitch(0.42)
            dark.box(center: .zero, size: [7.4, 0.25, 1.1])
            dark.transform = matrix_identity_float4x4
            wheels(&tyre, xs: [1.6, -1.6], halfTrack: 0.9, radius: 0.4)
            return [(.white, white), (.darkMetal, dark), (.tyre, tyre)]
        case .cateringTruck:
            white.box(center: [2.9, 0.8, 0], size: [1.8, 2.0, 2.3])
            glass.box(center: [3.81, 1.9, 0], size: [0.05, 0.8, 2.0])
            dark.box(center: [-0.6, 0.7, 0], size: [6.8, 0.4, 2.2])
            white.box(center: [-0.9, 2.4, 0], size: [4.8, 2.6, 2.4])
            hi.box(center: [-0.9, 1.6, 0], size: [3.8, 0.8, 2.0])
            wheels(&tyre, xs: [2.8, -2.4], halfTrack: 1.0)
            return [(.white, white), (.windowDark, glass), (.darkMetal, dark), (.hiVis, hi), (.tyre, tyre)]
        case .baggageTrain:
            white.box(center: [4.4, 0.4, 0], size: [2.2, 1.0, 1.5])
            hi.box(center: [4.0, 1.4, 0], size: [0.9, 0.9, 1.3])
            for i in 0..<3 {
                let x = 1.6 - Float(i) * 3.0
                dark.box(center: [x, 0.45, 0], size: [2.6, 0.2, 1.5])
                accent.box(center: [x, 0.65, 0], size: [2.2, 1.0, 1.3])
            }
            wheels(&tyre, xs: [4.8, 4.0, 2.4, 0.8, -0.6, -2.2, -3.6, -5.2], halfTrack: 0.7, radius: 0.3)
            return [(.white, white), (.hiVis, hi), (.darkMetal, dark), (.cloth(6), accent), (.tyre, tyre)]
        case .bus:
            white.box(center: [0, 0.5, 0], size: [12, 2.6, 2.6])
            glass.box(center: [0, 1.6, 0], size: [11.2, 1.1, 2.66], top: false)
            accent.box(center: [0, 0.75, 0], size: [12.04, 0.25, 2.64], top: false)
            wheels(&tyre, xs: [4.2, -4.2], halfTrack: 1.15)
            return [(.white, white), (.windowDark, glass), (.livery(.azure), accent), (.tyre, tyre)]
        case .car:
            white.box(center: [0, 0.45, 0], size: [4.4, 0.75, 1.8])
            white.box(center: [-0.3, 1.2, 0], size: [2.4, 0.65, 1.6])
            glass.box(center: [-0.3, 1.25, 0], size: [2.45, 0.45, 1.64], top: false)
            wheels(&tyre, xs: [1.4, -1.4], halfTrack: 0.8, radius: 0.35)
            return [(.cloth(0), white), (.windowDark, glass), (.tyre, tyre)]
        case .golfCart:
            white.box(center: [0, 0.4, 0], size: [2.6, 0.6, 1.3])
            white.box(center: [-0.2, 2.0, 0], size: [2.2, 0.12, 1.4])
            dark.box(center: [0.9, 1.0, 0.6], size: [0.08, 1.1, 0.08])
            dark.box(center: [0.9, 1.0, -0.6], size: [0.08, 1.1, 0.08])
            dark.box(center: [-1.1, 1.0, 0.6], size: [0.08, 1.1, 0.08])
            dark.box(center: [-1.1, 1.0, -0.6], size: [0.08, 1.1, 0.08])
            accent.box(center: [-0.4, 1.0, 0], size: [0.8, 0.6, 1.1])
            wheels(&tyre, xs: [0.8, -0.8], halfTrack: 0.6, radius: 0.3)
            return [(.white, white), (.darkMetal, dark), (.cloth(5), accent), (.tyre, tyre)]
        case .serviceVan:
            white.box(center: [0, 0.5, 0], size: [5.4, 2.2, 2.1])
            glass.box(center: [2.71, 1.8, 0], size: [0.05, 0.8, 1.9])
            accent.box(center: [0, 1.2, 0], size: [5.44, 0.3, 2.14], top: false)
            wheels(&tyre, xs: [1.8, -1.8], halfTrack: 0.9, radius: 0.4)
            return [(.white, white), (.windowDark, glass), (.livery(.azure), accent), (.tyre, tyre)]
        }
    }

    // MARK: People

    func person(_ variant: Int, crew: Bool) -> [HubPart] {
        parts("person.\(crew)") {
            var body = HubMeshBatch(), head = HubMeshBatch(), legs = HubMeshBatch()
            legs.cylinder(base: [0, 0, 0], radius: 0.2, topRadius: 0.24, height: 0.85, segments: 8)
            body.cylinder(base: [0, 0.85, 0], radius: 0.27, topRadius: 0.24, height: 0.7, segments: 8)
            body.sphere(center: [0, 1.55, 0], radius: 0.24, scale: [1, 0.5, 1], segments: 8, rings: 4)
            head.sphere(center: [0, 1.82, 0], radius: 0.2, segments: 8, rings: 6)
            return [(crew ? .hiVis : .cloth(0), body), (.skin(0), head), (.darkMetal, legs)]
        }
    }

    // MARK: Pieces used at a single position (for the gate shot)

    func cone() -> [HubPart] {
        parts("cone") {
            var c = HubMeshBatch(), w = HubMeshBatch()
            c.cylinder(base: [0, 0.05, 0], radius: 0.3, topRadius: 0.04, height: 0.85, segments: 10)
            c.box(center: [0, 0, 0], size: [0.6, 0.05, 0.6])
            w.cylinder(base: [0, 0.4, 0], radius: 0.19, topRadius: 0.15, height: 0.16, segments: 10, caps: false)
            return [(.cone, c), (.white, w)]
        }
    }

    /// A flat blob shadow, 1 × 1 m, scaled per use.
    func blob() -> [HubPart] {
        parts("blob") {
            var b = HubMeshBatch()
            b.plane(center: [0, 0.16, 0], width: 1, depth: 1)
            return [(.blob, b)]
        }
    }

    func ring() -> [HubPart] {
        parts("ring") {
            var b = HubMeshBatch()
            b.plane(center: [0, 0.3, 0], width: 1, depth: 1)
            return [(.pulse, b)]
        }
    }
}

extension AircraftCategory {
    var isWidebody: Bool { self == .widebody || self == .largeWidebody }
}

/// Remembers which palette material a model part uses, so the scene can be
/// repainted for day and night in place.
struct HubMaterialTag: Component {
    var key: HubMaterialKey
}
