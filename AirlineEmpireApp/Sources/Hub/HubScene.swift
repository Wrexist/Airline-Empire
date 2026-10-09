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

    init(target: SIMD3<Float>, distance: Float, pitch: Float, yaw: Float) {
        self.target = target
        self.distance = distance
        self.pitch = pitch
        self.yaw = yaw
    }

    /// The Core solver's frame (`HubFraming`), in RealityKit's types.
    init(_ frame: HubFrame) {
        self.init(target: [Float(frame.target.x), 0, Float(frame.target.z)], distance: Float(frame.distance),
                  pitch: Float(frame.pitch), yaw: Float(frame.yaw))
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
@available(iOS 18.0, *)
@MainActor
final class HubSceneController: NSObject, UIGestureRecognizerDelegate {
    let arView: ARView
    let layout: HubLayout
    private let materials = HubMaterials(palette: .day)
    private let models = HubModels()
    private let anchor = AnchorEntity(world: .zero)
    private let camera = PerspectiveCamera()
    private let sun = DirectionalLight()
    private let post = HubPostProcess()
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
        rig = HubSceneController.rig(for: .overview, layout: layout, focus: nil, size: CGSize(width: 1_376, height: 1_032))
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
        if !ProcessInfo.processInfo.arguments.contains("-AEHubNoBloom") {
            post.install(on: arView)
        }
        arView.isAccessibilityElement = true
        arView.accessibilityIdentifier = "ae-hub-scene"
        arView.accessibilityLabel = "3D view of your hub airport"
    }

    private func applyLighting(_ palette: HubPalette) {
        if let sky = HubMaterials.skyImage(palette) {
            Task { @MainActor [weak self] in
                guard let env = try? await EnvironmentResource(equirectangular: sky) else { return }
                self?.arView.environment.lighting.resource = env
            }
        }
        arView.environment.lighting.intensityExponent = palette.iblExponent
        arView.environment.background = .color(palette.background)
        sun.light.color = palette.keyColor
        sun.light.intensity = palette.keyIntensity
    }

    private func buildScene() {
        arView.scene.addAnchor(anchor)
        var builder = HubSceneBuilder(layout: layout, materials: materials, library: models.library)
        layers = builder.build()
        for (_, e) in layers { anchor.addChild(e) }
        dynamics = HubDynamics(layout: layout, models: models, materials: materials)
        anchor.addChild(dynamics.root)

        // Key light: elevation 52°, azimuth 140°, soft shadows. The shadow
        // range follows the camera (`fitShadows`), so the close shots get
        // crisp shadows instead of sharing one map with the whole airfield.
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 2_400, depthBias: 4)
        let center = SIMD3<Float>(Float(layout.bounds.center.x), 0, Float(layout.bounds.center.z))
        let elevation: Float = 52 * .pi / 180, azimuth: Float = 140 * .pi / 180
        let dir = SIMD3<Float>(cos(elevation) * sin(azimuth), sin(elevation), cos(elevation) * cos(azimuth))
        sun.look(at: center, from: center + dir * 1_500, relativeTo: nil)
        anchor.addChild(sun)

        camera.camera.fieldOfViewInDegrees = Float(HubFraming.fieldOfView)
        camera.camera.near = 2
        camera.camera.far = 12_000
        anchor.addChild(camera)
        applyRig()
    }

    // MARK: Shots

    /// Default framing per shot, solved in Core (`HubLayout.frame`) so the
    /// subject fills the part of a `size` view the dashboard leaves free.
    static func rig(for shot: HubShot, layout: HubLayout, focus: HubStand?, size: CGSize) -> HubCameraRig {
        let w = Double(max(size.width, 1)), h = Double(max(size.height, 1))
        let safe = HubFraming.safeArea(width: w, height: h)
        let cameraShot: HubCameraShot
        switch shot {
        case .overview: cameraShot = .overview
        case .gate: cameraShot = focus.map { HubCameraShot.gate(stand: $0.index) } ?? .overview
        case .terminal: cameraShot = .terminal
        case .district: cameraShot = .district
        }
        return HubCameraRig(layout.frame(cameraShot, aspect: w / h, safe: safe))
    }

    private var aspect: Float {
        let size = arView.bounds.size
        return size.height > 0 ? Float(size.width / size.height) : 1.33
    }

    private var framedAspect: Float = 0
    private var framedForRealBounds = false
    private var focusIndex: Int?

    func show(_ shot: HubShot, focus: Int?, animated: Bool = true) {
        self.shot = shot
        focusIndex = focus
        framedAspect = aspect
        framedForRealBounds = arView.bounds.height > 0
        let stand = focus.flatMap { $0 < layout.stands.count ? layout.stands[$0] : nil }
        let size = arView.bounds.height > 0 ? arView.bounds.size : CGSize(width: 1_376, height: 1_032)
        goal = Self.rig(for: shot, layout: layout, focus: stand, size: size)
        // Turn the short way round to the new shot.
        goal.yaw = rig.yaw + (goal.yaw - rig.yaw).remainder(dividingBy: 2 * .pi)
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
        post.setNight(night ? 1 : 0)
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
            materials.makeHeatmap(hotspots: hotspots, load: CGFloat(terminalLoad), floorWidth: CGFloat(bounds.width),
                                  floorDepth: CGFloat(bounds.depth))
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
        // Reframe when the view changes shape (rotation, split view) unless
        // the player has just moved the camera.
        if abs(aspect - framedAspect) > 0.05
            && (!framedForRealBounds || Date().timeIntervalSince(lastInteraction) > 1.5) {
            let keepDrift = lastInteraction
            show(shot, focus: focusIndex, animated: !framedForRealBounds ? false : true)
            lastInteraction = keepDrift
        }
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
        // Depth range scaled to the shot: a fixed 2 m near plane against a
        // 12 km far plane z-fights the stacked ground layers (apron, lines,
        // markings) at overview distance.
        camera.camera.near = max(1, rig.distance * 0.04)
        camera.camera.far = rig.distance * 8 + 3_000
        fitShadows()
    }

    private var shadowRange: Float = 0

    /// Re-fits the sun's shadow map to what the camera can see, when the
    /// distance has moved enough to matter.
    private func fitShadows() {
        let wanted = rig.distance * 2.4 + 120
        guard shadowRange == 0 || abs(wanted - shadowRange) / shadowRange > 0.2 else { return }
        shadowRange = wanted
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: wanted, depthBias: 3)
    }

    private func publishProjections() {
        guard let onProjected else { return }
        let size = arView.bounds.size
        let visible: [HubProjectedAnchor] = dynamics.anchors.compactMap { anchor in
            switch anchor.kind {
            case .pin: guard shot == .terminal else { return nil }
            case .pill: guard shot == .district else { return nil }
            case .callout: guard shot == .gate else { return nil }
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
