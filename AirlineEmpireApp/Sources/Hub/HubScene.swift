import RealityKit
import UIKit
import Combine
import Observation
import simd
import AirlineEmpireCore

/// The dashboard's camera shots (docs/HUB_VIEW_3D.md §1, §3).
enum HubShot: String, CaseIterable, Identifiable {
    case overview, gate, terminal, district

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Airport"
        case .gate: "Gate"
        case .terminal: "Terminal"
        case .district: "District"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "airplane.departure"
        case .gate: "door.left.hand.open"
        case .terminal: "building.2"
        case .district: "house"
        }
    }
}

/// Orbit camera: a target on the ground, a distance, a pitch and a yaw.
struct HubCameraRig: Equatable {
    var target: SIMD3<Float>
    var distance: Float
    var pitch: Float
    var yaw: Float

    var position: SIMD3<Float> {
        let flat = cos(pitch) * distance
        return target + [sin(yaw) * flat, sin(pitch) * distance, cos(yaw) * flat]
    }

    func lerp(to b: HubCameraRig, _ t: Float) -> HubCameraRig {
        HubCameraRig(target: target + (b.target - target) * t,
                     distance: distance + (b.distance - distance) * t,
                     pitch: pitch + (b.pitch - pitch) * t,
                     yaw: yaw + (b.yaw - yaw) * t)
    }
}

/// Positions of the world-anchored overlay, in view points.
struct HubProjectedAnchor: Identifiable, Equatable {
    let anchor: HubAnchor
    let point: CGPoint
    var id: String { anchor.id }
}

/// Owns the RealityKit view and everything in it. SwiftUI talks to it
/// through `HubScreenModel`; it never reads `GameState` itself.
@MainActor
final class HubSceneController: NSObject, UIGestureRecognizerDelegate {
    let arView: ARView
    let layout: HubLayout
    private let materials = HubMaterials(palette: .day)
    private let models = HubModels()
    private let anchor = AnchorEntity(world: .zero)
    private let camera = PerspectiveCamera()
    private let sun = DirectionalLight()
    private var layers: [HubLayer: Entity] = [:]
    private(set) var dynamics: HubDynamics!
    private var updates: Cancellable?
    private var rig: HubCameraRig
    private var goal: HubCameraRig
    private var nightValue: Double = 0
    private var lastInteraction = Date()
    private var projectionClock: Float = 0
    private let idleDrift: Bool

    var onProjected: (([HubProjectedAnchor]) -> Void)?
    var onTapAircraft: ((Int) -> Void)?
    private(set) var shot: HubShot = .overview

    init(layout: HubLayout, idleDrift: Bool = true) {
        self.layout = layout
        self.idleDrift = idleDrift
        arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        rig = HubSceneController.rig(for: .overview, layout: layout, focus: nil)
        goal = rig
        super.init()
        HubMaterialTag.registerComponent()
        configureView()
        buildScene()
        installGestures()
        updates = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated { self?.tick(Float(event.deltaTime)) }
        }
    }

    // MARK: Setup

    private func configureView() {
        arView.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableCameraGrain,
                                .disablePersonOcclusion, .disableGroundingShadows]
        arView.environment.background = .color(HubPalette.day.background)
        applyLighting(.day)
        arView.isAccessibilityElement = true
        arView.accessibilityIdentifier = "ae-hub-scene"
        arView.accessibilityLabel = "3D view of your hub airport"
    }

    private func applyLighting(_ palette: HubPalette) {
        if let sky = HubMaterials.skyImage(palette),
           let env = try? EnvironmentResource.generate(fromEquirectangular: sky) {
            arView.environment.lighting.resource = env
        }
        arView.environment.lighting.intensityExponent = palette.iblExponent
        arView.environment.background = .color(palette.background)
        sun.light.color = palette.keyColor
        sun.light.intensity = palette.keyIntensity
    }

    private func buildScene() {
        arView.scene.addAnchor(anchor)
        var builder = HubSceneBuilder(layout: layout, materials: materials)
        layers = builder.build()
        for (_, e) in layers { anchor.addChild(e) }
        dynamics = HubDynamics(layout: layout, models: models, materials: materials)
        anchor.addChild(dynamics.root)

        // Key light: elevation 52°, azimuth 140°, soft shadows.
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 2_400, depthBias: 4)
        let center = SIMD3<Float>(Float(layout.bounds.center.x), 0, Float(layout.bounds.center.z))
        let elevation: Float = 52 * .pi / 180, azimuth: Float = 140 * .pi / 180
        let dir = SIMD3<Float>(cos(elevation) * sin(azimuth), sin(elevation), cos(elevation) * cos(azimuth))
        sun.look(at: center, from: center + dir * 1_500, relativeTo: nil)
        anchor.addChild(sun)

        camera.camera.fieldOfViewInDegrees = 24
        camera.camera.near = 2
        camera.camera.far = 12_000
        anchor.addChild(camera)
        applyRig()
    }

    // MARK: Shots

    static func rig(for shot: HubShot, layout: HubLayout, focus: HubStand?) -> HubCameraRig {
        let f: (HubVec) -> SIMD3<Float> = { SIMD3(Float($0.x), 0, Float($0.z)) }
        let yaw: Float = 35 * .pi / 180
        switch shot {
        case .overview:
            let apron = layout.pieces.first { $0.kind == .apron }?.groundBounds ?? layout.terminal
            let span = Float(max(apron.width, apron.depth * 1.6))
            return HubCameraRig(target: f(apron.center) + [0, 0, 40], distance: max(900, span * 2.6),
                                pitch: 38 * .pi / 180, yaw: yaw)
        case .gate:
            guard let stand = focus else { return rig(for: .overview, layout: layout, focus: nil) }
            let fwd = SIMD3<Float>(Float(cos(stand.heading)), 0, Float(-sin(stand.heading)))
            let length = Float(HubAircraftEnvelope.length(stand.maxCategory))
            return HubCameraRig(target: f(stand.nose) - fwd * (length * 0.45), distance: length * 5.6,
                                pitch: 30 * .pi / 180, yaw: yaw)
        case .terminal:
            return HubCameraRig(target: f(layout.interior.bounds.center) + [0, 0, -4],
                                distance: Float(layout.terminal.width) * 1.25 + 120, pitch: 42 * .pi / 180, yaw: yaw)
        case .district:
            return HubCameraRig(target: f(layout.focus.district), distance: 620, pitch: 40 * .pi / 180, yaw: yaw)
        }
    }

    func show(_ shot: HubShot, focus: Int?, animated: Bool = true) {
        self.shot = shot
        let stand = focus.flatMap { $0 < layout.stands.count ? layout.stands[$0] : nil }
        goal = Self.rig(for: shot, layout: layout, focus: stand)
        if !animated { rig = goal; applyRig() }
        let cutaway = shot == .terminal
        layers[.terminalRoof]?.isEnabled = !cutaway
        layers[.terminalShell]?.isEnabled = !cutaway
        layers[.interior]?.isEnabled = cutaway
        dynamics.showsInterior = cutaway
        dynamics.showsRoute = shot == .district || nightValue > 0.5
        lastInteraction = Date()
    }

    // MARK: Day and night

    private var appliedNight: Bool?

    func setNight(_ value: Double) {
        let night = value > 0.5
        nightValue = value
        guard night != appliedNight else { return }
        appliedNight = night
        let palette: HubPalette = night ? .night : .day
        materials.setPalette(palette)
        applyLighting(palette)
        repaint(anchor)
        layers[.lamps]?.isEnabled = true
        dynamics.showsRoute = shot == .district || night
    }

    private func repaint(_ entity: Entity) {
        if let tag = entity.components[HubMaterialTag.self], var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map { _ in materials[tag.key] }
            entity.components.set(model)
        }
        for child in entity.children { repaint(child) }
    }

    // MARK: Simulation

    func apply(_ snapshot: HubSnapshot, focus: Int?, groundServices: Int, terminalLoad: Double) {
        dynamics.apply(snapshot, focus: focus, groundServices: groundServices)
        let bounds = layout.interior.bounds
        let hotspots = layout.interior.hotspots.map { spot in
            (x: CGFloat((spot.position.x - bounds.minX) / bounds.width),
             y: CGFloat((spot.position.z - bounds.minZ) / bounds.depth),
             weight: CGFloat(spot.weight))
        }
        if materials.heatmap == nil || abs(lastLoad - terminalLoad) > 0.05 {
            lastLoad = terminalLoad
            materials.makeHeatmap(hotspots: hotspots, load: CGFloat(terminalLoad))
            installHeatmap()
            dynamics.populateInterior(load: terminalLoad)
        }
    }

    private var lastLoad: Double = -1
    private var heatEntity: ModelEntity?

    private func installHeatmap() {
        heatEntity?.removeFromParent()
        let b = layout.interior.bounds
        var plane = HubMeshBatch()
        plane.plane(center: [Float(b.center.x), 1.78, Float(b.center.z)], width: Float(b.width), depth: Float(b.depth))
        guard let mesh = plane.resource(name: "heat") else { return }
        let e = ModelEntity(mesh: mesh, materials: [materials[.heat]])
        layers[.interior]?.addChild(e)
        heatEntity = e
    }

    // MARK: Frame

    private func tick(_ dt: Float) {
        let dt = min(dt, 0.1)
        dynamics.update(dt)
        if idleDrift && Date().timeIntervalSince(lastInteraction) > 5 {
            goal.yaw += dt * 0.012
        }
        rig = rig.lerp(to: goal, min(1, dt * 3.2))
        applyRig()
        projectionClock += dt
        if projectionClock > 1.0 / 30 {
            projectionClock = 0
            publishProjections()
        }
    }

    private func applyRig() {
        camera.look(at: rig.target, from: rig.position, relativeTo: nil)
    }

    private func publishProjections() {
        guard let onProjected else { return }
        let size = arView.bounds.size
        let visible: [HubProjectedAnchor] = dynamics.anchors.compactMap { anchor in
            switch anchor.kind {
            case .pin: guard shot == .terminal else { return nil }
            case .pill: guard shot == .district else { return nil }
            case .callout: guard shot == .gate || shot == .overview else { return nil }
            }
            guard let p = arView.project(anchor.position),
                  p.x > -40, p.y > -40, p.x < size.width + 40, p.y < size.height + 40 else { return nil }
            // Behind the camera.
            let toPoint = anchor.position - rig.position
            let forward = rig.target - rig.position
            guard simd_dot(toPoint, forward) > 0 else { return nil }
            return HubProjectedAnchor(anchor: anchor, point: p)
        }
        onProjected(visible)
    }

    // MARK: Gestures

    private var pinchStart: Float = 0
    private var rotateStart: Float = 0

    private func installGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(onRotate(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        for g in [pan, pinch, rotate, tap] as [UIGestureRecognizer] {
            g.delegate = self
            arView.addGestureRecognizer(g)
        }
    }

    nonisolated func gestureRecognizer(_ g: UIGestureRecognizer,
                                       shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        lastInteraction = Date()
        let t = g.translation(in: arView)
        g.setTranslation(.zero, in: arView)
        let scale = goal.distance / Float(max(arView.bounds.height, 1)) * 0.42
        let right = SIMD3<Float>(cos(goal.yaw), 0, -sin(goal.yaw))
        let back = SIMD3<Float>(sin(goal.yaw), 0, cos(goal.yaw))
        goal.target -= right * Float(t.x) * scale
        goal.target -= back * Float(t.y) * scale
        clampTarget()
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        lastInteraction = Date()
        if g.state == .began { pinchStart = goal.distance }
        goal.distance = min(4_200, max(90, pinchStart / Float(max(g.scale, 0.05))))
    }

    @objc private func onRotate(_ g: UIRotationGestureRecognizer) {
        lastInteraction = Date()
        if g.state == .began { rotateStart = goal.yaw }
        goal.yaw = rotateStart - Float(g.rotation)
    }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        lastInteraction = Date()
        let point = g.location(in: arView)
        var hit = arView.entity(at: point)
        while let e = hit {
            if e.name.hasPrefix("aircraft-"), let index = Int(e.name.dropFirst("aircraft-".count)) {
                onTapAircraft?(index)
                return
            }
            hit = e.parent
        }
    }

    func zoom(by factor: Float) {
        lastInteraction = Date()
        goal.distance = min(4_200, max(90, goal.distance * factor))
    }

    func rotate(by radians: Float) {
        lastInteraction = Date()
        goal.yaw += radians
    }

    func recenter(focus: Int?) {
        show(shot, focus: focus)
    }

    private func clampTarget() {
        let b = layout.bounds
        goal.target.x = min(Float(b.maxX), max(Float(b.minX), goal.target.x))
        goal.target.z = min(Float(b.maxZ), max(Float(b.minZ), goal.target.z))
    }

    /// For the UI tests: a camera description they can assert on.
    var probe: String {
        String(format: "shot %@ yaw %.2f dist %.0f night %.2f anchors %d",
               shot.rawValue, rig.yaw, rig.distance, nightValue, dynamics.anchors.count)
    }

    func pause(_ paused: Bool) {
        if paused {
            updates?.cancel()
            updates = nil
        } else if updates == nil {
            updates = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                MainActor.assumeIsolated { self?.tick(Float(event.deltaTime)) }
            }
        }
    }
}
