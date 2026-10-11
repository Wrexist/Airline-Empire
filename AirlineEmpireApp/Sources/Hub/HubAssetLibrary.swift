import RealityKit
import Foundation
import simd

/// Authored models that replace procedural pieces (docs/HUB_MODEL_LIST.md).
///
/// A file named `Hub_<slot>.usdz` in `Resources/HubModels/` replaces the
/// procedural model for that slot everywhere; a missing file simply leaves
/// the procedural one in place, so models can arrive one at a time.
///
/// Prims named `ae_<slot>` are repainted with the hub palette, which is how
/// an authored jet still wears the player's livery and an authored villa
/// still lights up at night.
@available(iOS 18.0, *)
@MainActor
final class HubAssetLibrary {
    private let bundle: Bundle
    private var prototypes: [String: Entity] = [:]
    private var missing: Set<String> = []

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func url(_ slot: String) -> URL? {
        bundle.url(forResource: "Hub_\(slot)", withExtension: "usdz", subdirectory: "HubModels")
            ?? bundle.url(forResource: "Hub_\(slot)", withExtension: "usdz")
    }

    func has(_ slot: String) -> Bool {
        prototype(slot) != nil
    }

    private func prototype(_ slot: String) -> Entity? {
        if let hit = prototypes[slot] { return hit }
        if missing.contains(slot) { return nil }
        guard let url = url(slot), let loaded = try? Entity.load(contentsOf: url) else {
            missing.insert(slot)
            return nil
        }
        prototypes[slot] = loaded
        return loaded
    }

    /// A fresh copy of the slot's model, repainted, or nil when no file ships.
    func instance(_ slot: String, materials: HubMaterials,
                  remap: (HubMaterialKey) -> HubMaterialKey = { $0 }) -> Entity? {
        guard let proto = prototype(slot) else { return nil }
        let copy = proto.clone(recursive: true)
        repaint(copy, inherited: nil, materials: materials, remap: remap)
        return copy
    }

    private var rawCache: [String: [(HubMaterialKey, HubMeshBatch)]] = [:]
    private var rawUnavailable: Set<String> = []
    private var rawFallbackCache: [String: [(HubMaterialKey, HubMeshBatch)]] = [:]

    /// The slot's geometry as CPU batches per palette key, in the model's own
    /// frame, so many static copies merge into one draw per material (crowds,
    /// crew, parked vehicles) instead of one entity each. Nil when no file
    /// ships, or when a part keeps its own authored material (the fuel
    /// truck's polished tank), which a palette batch cannot carry — unless
    /// `unkeyed` names the palette key such parts take instead.
    func raw(_ slot: String, unkeyed: HubMaterialKey? = nil) -> [(HubMaterialKey, HubMeshBatch)]? {
        if let unkeyed {
            if let hit = rawCache[slot] ?? rawFallbackCache[slot] { return hit }
            guard let made = rawBatches(slot, unkeyed: unkeyed) else { return nil }
            rawFallbackCache[slot] = made
            return made
        }
        if let hit = rawCache[slot] { return hit }
        if rawUnavailable.contains(slot) { return nil }
        guard let made = rawBatches(slot, unkeyed: nil) else {
            rawUnavailable.insert(slot)
            return nil
        }
        rawCache[slot] = made
        return made
    }

    private func rawBatches(_ slot: String, unkeyed: HubMaterialKey?) -> [(HubMaterialKey, HubMeshBatch)]? {
        guard let proto = prototype(slot) else { return nil }
        var complete = true
        var batches: [HubMaterialKey: HubMeshBatch] = [:]
        var order: [HubMaterialKey] = []
        func walk(_ entity: Entity, inherited: HubMaterialKey?) {
            let own = Self.key(forPrim: entity.name) ?? inherited
            if own == nil, unkeyed == nil, entity.components[ModelComponent.self] != nil { complete = false }
            let key = own ?? (entity.components[ModelComponent.self] != nil ? unkeyed : nil)
            if let key, let model = entity.components[ModelComponent.self] {
                let placed = entity.transformMatrix(relativeTo: proto)
                if batches[key] == nil { order.append(key) }
                var batch = batches[key] ?? HubMeshBatch()
                for instance in model.mesh.contents.instances {
                    guard let source = model.mesh.contents.models[instance.model] else { continue }
                    batch.transform = placed * instance.transform
                    for part in source.parts {
                        guard let tris = part.triangleIndices?.elements else { continue }
                        batch.triangles(positions: part.positions.elements, normals: part.normals?.elements,
                                        indices: tris)
                    }
                }
                batch.transform = matrix_identity_float4x4
                batches[key] = batch
            }
            for child in entity.children {
                walk(child, inherited: own)
            }
        }
        walk(proto, inherited: nil)
        let made = order.compactMap { key in batches[key].map { (key, $0) } }.filter { !$0.1.isEmpty }
        return complete && !made.isEmpty ? made : nil
    }

    /// First available slot from a list of alternatives (variants).
    func instance(anyOf slots: [String], materials: HubMaterials,
                  remap: (HubMaterialKey) -> HubMaterialKey = { $0 }) -> Entity? {
        for slot in slots {
            if let e = instance(slot, materials: materials, remap: remap) { return e }
        }
        return nil
    }

    private func repaint(_ entity: Entity, inherited: HubMaterialKey?, materials: HubMaterials,
                         remap: (HubMaterialKey) -> HubMaterialKey) {
        let key = Self.key(forPrim: entity.name) ?? inherited
        if let key, var model = entity.components[ModelComponent.self] {
            let mapped = remap(key)
            model.materials = model.materials.map { _ in materials[mapped] }
            entity.components.set(model)
            entity.components.set(HubMaterialTag(key: mapped))
        }
        for child in entity.children {
            repaint(child, inherited: key, materials: materials, remap: remap)
        }
    }

    /// `ae_livery`, `ae_livery_2`, `ae_windowDark` … → palette key.
    nonisolated static func key(forPrim name: String) -> HubMaterialKey? {
        guard name.hasPrefix("ae_") else { return nil }
        var slot = String(name.dropFirst(3))
        if let underscore = slot.firstIndex(of: "_") { slot = String(slot[..<underscore]) }
        switch slot {
        case "white": return .white
        case "livery": return .livery(.azure)
        case "liveryAccent": return .liveryAccent(.azure)
        case "windowDark", "window": return .windowDark
        case "glass": return .glass
        case "building": return .building
        case "buildingShade": return .buildingShade
        case "roof": return .roof
        case "houseRoof": return .houseRoof
        case "houseWood", "wood": return .houseWood
        case "darkMetal", "metal": return .darkMetal
        case "tyre", "tire": return .tyre
        case "hiVis": return .hiVis
        case "cone": return .cone
        case "cloth": return .cloth(0)
        case "skin": return .skin(0)
        case "screen": return .screen
        case "lamp": return .lamp
        case "water": return .water
        case "tree": return .tree(0)
        case "trunk": return .trunk
        case "grass": return .grass
        case "grassBright": return .grassBright
        case "concrete": return .concrete
        case "marking": return .marking
        default: return nil
        }
    }

    /// Scales `entity` uniformly so its footprint fits `size` (x, z) and
    /// sits on the ground, centred on its own pivot.
    static func fit(_ entity: Entity, footprint size: SIMD2<Float>, height: Float? = nil) {
        let bounds = entity.visualBounds(relativeTo: entity)
        let ext = bounds.extents
        guard ext.x > 0.01, ext.z > 0.01 else { return }
        var s = min(size.x / ext.x, size.y / ext.z)
        if let height, ext.y > 0.01 { s = height / ext.y }
        entity.scale = [s, s, s]
    }
}
