import RealityKit
import UIKit
import Foundation
import simd

/// The hub's models for the whole app run, not one visit: the authored
/// prototypes, read from the bundle off the main thread before a hub is
/// built, and the CPU geometry and procedural meshes made from them. A
/// second visit, or a switch to another hub, builds from memory instead of
/// re-reading some 46 files. A memory warning empties it; a hub open at the
/// time keeps what it already holds, and the next one reads again.
@available(iOS 18.0, *)
@MainActor
final class HubModelCache {
    static let shared = HubModelCache()

    private var prototypes: [String: Entity] = [:]
    /// Slots read and found wanting (no file, or one that would not load).
    private var missing: Set<String> = []
    /// Every shipped file has been read since launch or the last warning:
    /// a slot not in `prototypes` now does not ship.
    private var loaded = false
    private var loading: Task<Void, Never>?
    /// Bumped by a memory warning, so a read that was under way then does
    /// not mark the emptied cache complete.
    private var generation = 0

    /// Authored geometry per palette key (`HubAssetLibrary.raw`), by slot.
    var authoredRaw: [String: [(HubMaterialKey, HubMeshBatch)]] = [:]
    var authoredRawUnavailable: Set<String> = []
    var authoredRawFallback: [String: [(HubMaterialKey, HubMeshBatch)]] = [:]
    /// Procedural geometry and meshes (`HubModels`), by shape.
    var proceduralRaw: [String: [(HubMaterialKey, HubMeshBatch)]] = [:]
    var parts: [String: [HubPart]] = [:]

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: .main) { _ in
            Task { @MainActor in HubModelCache.shared.empty() }
        }
    }

    /// Reads every shipped `Hub_*.usdz` that is not already in memory,
    /// asynchronously (`Entity(contentsOf:)`), so the main thread stays
    /// free for the spinner. Callers arriving while a read is under way
    /// wait for that one.
    func preload(bundle: Bundle = .main) async {
        if loaded { return }
        if let loading {
            await loading.value
            return
        }
        let started = generation
        let task = Task { @MainActor in
            for (slot, url) in Self.shippedFiles(in: bundle) where self.prototypes[slot] == nil {
                if let entity = try? await Entity(contentsOf: url) {
                    self.prototypes[slot] = entity
                } else {
                    self.missing.insert(slot)
                }
            }
            if self.generation == started { self.loaded = true }
            self.loading = nil
        }
        loading = task
        await task.value
    }

    /// The slot's prototype. Read from memory once `preload` has run;
    /// before that (or after a memory warning) the file is read here, on
    /// the spot, as it always was.
    func prototype(_ slot: String, url: () -> URL?) -> Entity? {
        if let hit = prototypes[slot] { return hit }
        if loaded || missing.contains(slot) { return nil }
        guard let url = url(), let entity = try? Entity.load(contentsOf: url) else {
            missing.insert(slot)
            return nil
        }
        prototypes[slot] = entity
        return entity
    }

    private func empty() {
        generation += 1
        loaded = false
        prototypes.removeAll()
        missing.removeAll()
        authoredRaw.removeAll()
        authoredRawUnavailable.removeAll()
        authoredRawFallback.removeAll()
        proceduralRaw.removeAll()
        parts.removeAll()
    }

    /// `Hub_<slot>.usdz` in `HubModels/` (a folder reference), or loose in
    /// the bundle, by slot.
    private static func shippedFiles(in bundle: Bundle) -> [(String, URL)] {
        let urls = (bundle.urls(forResourcesWithExtension: "usdz", subdirectory: "HubModels") ?? [])
            + (bundle.urls(forResourcesWithExtension: "usdz", subdirectory: nil) ?? [])
        var seen: Set<String> = []
        var files: [(String, URL)] = []
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("Hub_") else { continue }
            let slot = String(name.dropFirst(4))
            if seen.insert(slot).inserted { files.append((slot, url)) }
        }
        return files
    }
}

/// Authored models that replace procedural pieces (docs/HUB_MODEL_LIST.md).
///
/// A file named `Hub_<slot>.usdz` in `Resources/HubModels/` replaces the
/// procedural model for that slot everywhere; a missing file simply leaves
/// the procedural one in place, so models can arrive one at a time.
///
/// Prims named `ae_<slot>` are repainted with the hub palette, which is how
/// an authored jet still wears the player's livery and an authored villa
/// still lights up at night.
///
/// One per visit, and cheap: the files and the geometry made from them
/// live in `HubModelCache` for the whole run.
@available(iOS 18.0, *)
@MainActor
final class HubAssetLibrary {
    private let bundle: Bundle
    /// What this visit has used, held so a memory warning mid-visit cannot
    /// pull a model out from under the scene.
    private var prototypes: [String: Entity] = [:]
    private let cache = HubModelCache.shared

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
        guard let loaded = cache.prototype(slot, url: { url(slot) }) else { return nil }
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

    /// The slot's geometry as CPU batches per palette key, in the model's own
    /// frame, so many static copies merge into one draw per material (crowds,
    /// crew, parked vehicles) instead of one entity each. Nil when no file
    /// ships, or when a part keeps its own authored material (the fuel
    /// truck's polished tank), which a palette batch cannot carry — unless
    /// `unkeyed` names the palette key such parts take instead.
    func raw(_ slot: String, unkeyed: HubMaterialKey? = nil) -> [(HubMaterialKey, HubMeshBatch)]? {
        if let unkeyed {
            if let hit = cache.authoredRaw[slot] ?? cache.authoredRawFallback[slot] { return hit }
            guard let made = rawBatches(slot, unkeyed: unkeyed) else { return nil }
            cache.authoredRawFallback[slot] = made
            return made
        }
        if let hit = cache.authoredRaw[slot] { return hit }
        if cache.authoredRawUnavailable.contains(slot) { return nil }
        guard let made = rawBatches(slot, unkeyed: nil) else {
            cache.authoredRawUnavailable.insert(slot)
            return nil
        }
        cache.authoredRaw[slot] = made
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
