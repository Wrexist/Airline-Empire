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

/// What the layers menu can switch on and off over the world.
enum HubOverlay: String, CaseIterable, Identifiable {
    case routes, standTags, upgrades, traffic, labels

    var id: String { rawValue }

    var title: String {
        switch self {
        case .routes: "Route fan"
        case .standTags: "Stand tags"
        case .upgrades: "Upgrade sites"
        case .traffic: "Traffic"
        case .labels: "Place labels"
        }
    }

    var systemImage: String {
        switch self {
        case .routes: "point.3.connected.trianglepath.dotted"
        case .standTags: "tag.fill"
        case .upgrades: "building.2.crop.circle"
        case .traffic: "car.2.fill"
        case .labels: "mappin.and.ellipse"
        }
    }

    var detail: String {
        switch self {
        case .routes: "Your routes on their bearings, coloured by load"
        case .standTags: "Flight and stage over your jets"
        case .upgrades: "Your lounge and ground-crew depot, and what is next"
        case .traffic: "Circuit, apron and street traffic"
        case .labels: "Terminal hotspots and district stops"
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

/// A critically damped spring towards a goal that may move ("Critically
/// Damped Ease-In/Ease-Out Smoothing", Game Programming Gems 4): it starts
/// from rest, never overshoots, and keeps its velocity when the goal is
/// retargeted mid-move, so a second tap bends the flight instead of jerking.
struct HubSpring {
    var value: Float
    var velocity: Float = 0

    init(_ value: Float) { self.value = value }

    /// Settles within a few percent after about three `smoothTime`s.
    mutating func step(to goal: Float, smoothTime: Float, dt: Float) {
        let omega = 2 / max(0.001, smoothTime)
        let x = omega * dt
        let decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let change = value - goal
        let temp = (velocity + omega * change) * dt
        velocity = (velocity - omega * temp) * decay
        value = goal + (change + temp) * decay
    }

    mutating func snap(to goal: Float) {
        value = goal
        velocity = 0
    }
}

/// The camera's springs. Distance runs in log space so a zoom from the
/// whole airfield to one gate moves at a constant *apparent* speed.
struct HubRigSpring {
    var x, z, logDistance, pitch, yaw: HubSpring

    init(_ rig: HubCameraRig) {
        x = HubSpring(rig.target.x)
        z = HubSpring(rig.target.z)
        logDistance = HubSpring(log(max(1, rig.distance)))
        pitch = HubSpring(rig.pitch)
        yaw = HubSpring(rig.yaw)
    }

    var rig: HubCameraRig {
        HubCameraRig(target: [x.value, 0, z.value], distance: exp(logDistance.value), pitch: pitch.value, yaw: yaw.value)
    }

    /// Moving in, the target leads so the subject is centred before the
    /// camera closes on it; moving out, the zoom leads.
    mutating func step(to goal: HubCameraRig, smoothTime: Float, dt: Float) {
        let target = log(max(1, goal.distance))
        let zoomingIn = target < logDistance.value - 0.05
        let zoomingOut = target > logDistance.value + 0.05
        let move = smoothTime * (zoomingIn ? 0.8 : zoomingOut ? 1.15 : 1)
        let zoom = smoothTime * (zoomingIn ? 1.1 : zoomingOut ? 0.8 : 1)
        x.step(to: goal.target.x, smoothTime: move, dt: dt)
        z.step(to: goal.target.z, smoothTime: move, dt: dt)
        logDistance.step(to: target, smoothTime: zoom, dt: dt)
        pitch.step(to: goal.pitch, smoothTime: smoothTime, dt: dt)
        yaw.step(to: goal.yaw, smoothTime: smoothTime, dt: dt)
    }

    var isMoving: Bool {
        max(abs(x.velocity), abs(z.velocity)) > 0.5 || abs(logDistance.velocity) > 0.01
            || abs(yaw.velocity) > 0.005 || abs(pitch.velocity) > 0.005
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
    private var spring: HubRigSpring
    /// How quickly the camera follows `goal`: long for a shot change, short
    /// while a finger is on the glass.
    private var smoothTime: Float = 0.5
    /// Inertia after a pan or twist is released, world metres and radians
    /// per second.
    private var panVelocity: SIMD3<Float> = .zero
    private var yawVelocity: Float = 0
    /// The idle turntable eases in rather than starting at full rate.
    private var driftRate: Float = 0
    private var nightValue: Double = 0
    private var lastInteraction = Date()
    private var projectionClock: Float = 0
    private let idleDrift: Bool

    var onProjected: (([HubProjectedAnchor]) -> Void)?
    var onTapAircraft: ((Int) -> Void)?
    var onTapFacility: ((HubFacilityKind) -> Void)?
    /// The facility site the camera has flown to, if any.
    private(set) var siteFocus: HubFacilityKind?
    private(set) var shot: HubShot = .overview

    init(layout: HubLayout, idleDrift: Bool = true) {
        self.layout = layout
        self.idleDrift = idleDrift
        arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        rig = HubSceneController.rig(for: .overview, layout: layout, focus: nil, size: CGSize(width: 1_376, height: 1_032))
        goal = rig
        spring = HubRigSpring(rig)
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
        siteFocus = nil
        focusIndex = focus
        framedAspect = aspect
        framedForRealBounds = arView.bounds.height > 0
        let stand = focus.flatMap { $0 < layout.stands.count ? layout.stands[$0] : nil }
        let size = arView.bounds.height > 0 ? arView.bounds.size : CGSize(width: 1_376, height: 1_032)
        goal = Self.rig(for: shot, layout: layout, focus: stand, size: size)
        // Turn the short way round to the new shot.
        goal.yaw = rig.yaw + (goal.yaw - rig.yaw).remainder(dividingBy: 2 * .pi)
        panVelocity = .zero
        yawVelocity = 0
        driftRate = 0
        // A longer flight gets a little longer, up to about two seconds.
        let travel = simd_distance(rig.position, goal.position)
        let turn = abs(goal.yaw - rig.yaw) * 400
        smoothTime = min(0.68, 0.42 + (travel + turn) / 9_000)
        if !animated {
            rig = goal
            spring = HubRigSpring(goal)
            applyRig()
        }
        let cutaway = shot == .terminal
        layers[.terminalRoof]?.isEnabled = !cutaway
        layers[.terminalShell]?.isEnabled = !cutaway
        layers[.interior]?.isEnabled = cutaway
        dynamics.yard.roofRoot.isEnabled = !cutaway
        dynamics.showsInterior = cutaway
        dynamics.showsRoute = shot == .district || nightValue > 0.5
        applyOverlays()
        lastInteraction = Date()
    }

    /// Flies to a facility site, close enough to watch it built.
    func showFacility(_ kind: HubFacilityKind) {
        if shot != .overview { show(.overview, focus: focusIndex) }
        siteFocus = kind
        let size = arView.bounds.height > 0 ? arView.bounds.size : CGSize(width: 1_376, height: 1_032)
        let w = Double(max(size.width, 1)), h = Double(max(size.height, 1))
        // The upgrade card takes the right of the screen: frame the site in
        // what is left of it, so the construction is never under the card.
        var safe = HubFraming.safeArea(width: w, height: h)
        let card: Double
        switch HubChromeMode(size: size) {
        case .regular: card = 340 + 64 + 28
        case .landscape: card = 300 + 60 + 24
        case .portrait: card = 0
        }
        if card > 0 { safe.maxX = min(safe.maxX, 1 - 2 * card / w) }
        goal = HubCameraRig(layout.frame(.facility(kind), aspect: w / h, safe: safe))
        goal.yaw = rig.yaw + (goal.yaw - rig.yaw).remainder(dividingBy: 2 * .pi)
        panVelocity = .zero
        yawVelocity = 0
        driftRate = 0
        smoothTime = 0.6
        applyOverlays()
        lastInteraction = Date()
    }

    func leaveFacility() {
        guard siteFocus != nil else { return }
        siteFocus = nil
        applyOverlays()
    }

    // MARK: Overlays

    private(set) var overlays: Set<HubOverlay> = Set(HubOverlay.allCases)

    func setOverlays(_ value: Set<HubOverlay>) {
        overlays = value
        applyOverlays()
    }

    func highlightRoute(_ id: RouteID?) {
        dynamics.highlightedRoute = id
    }

    private func applyOverlays() {
        // The fan radiates from the terminal roof: it belongs to the
        // airfield overview, and would cut across every close shot.
        dynamics.showsRouteFan = overlays.contains(.routes) && shot == .overview && siteFocus == nil
        dynamics.showsTraffic = overlays.contains(.traffic)
    }

    // MARK: Day and night

    /// Where the dusk crossfade is heading (0 day, 1 night) and where it
    /// is; the world repaints in steps as it goes (`advanceDusk`).
    private var duskGoal: Float = 0
    private var dusk: Float = 0
    private var appliedDusk: Float?
    private var appliedSky: Bool?

    func setNight(_ value: Double, animated: Bool = true) {
        nightValue = value
        duskGoal = value > 0.5 ? 1 : 0
        dynamics.showsRoute = shot == .district || value > 0.5
        if !animated || appliedDusk == nil {
            dusk = duskGoal
            applyDusk()
        }
    }

    /// About a second and a half from day to night, eased at both ends,
    /// repainted in twelve steps: a material swap per frame would cost
    /// more than the fade is worth.
    private func advanceDusk(_ dt: Float) {
        guard dusk != duskGoal else { return }
        let step = dt / 1.5
        dusk = duskGoal > dusk ? min(duskGoal, dusk + step) : max(duskGoal, dusk - step)
        let quantised = (dusk * 12).rounded() / 12
        if quantised != appliedDusk || dusk == duskGoal { applyDusk() }
    }

    private func applyDusk() {
        let q = dusk == duskGoal ? dusk : (dusk * 12).rounded() / 12
        guard q != appliedDusk else { return }
        appliedDusk = q
        let eased = q * q * (3 - 2 * q)
        let palette = HubPalette.mix(.day, .night, eased)
        post.setNight(eased)
        materials.setPalette(palette)
        // The sky probe is regenerated once, at the midpoint; colours and
        // intensities follow every step.
        let skyNight = eased > 0.5
        if skyNight != appliedSky {
            appliedSky = skyNight
            applyLighting(skyNight ? .night : .day)
        }
        arView.environment.lighting.intensityExponent = palette.iblExponent
        arView.environment.background = .color(palette.background)
        sun.light.color = palette.keyColor
        sun.light.intensity = palette.keyIntensity
        repaint(anchor)
        layers[.lamps]?.isEnabled = true
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
        advanceDusk(dt)
        // Released gestures coast to a stop.
        if simd_length(panVelocity) > 0.5 {
            goal.target += panVelocity * dt
            panVelocity *= exp(-4.2 * dt)
            clampTarget()
        } else {
            panVelocity = .zero
        }
        if abs(yawVelocity) > 0.01 {
            goal.yaw += yawVelocity * dt
            yawVelocity *= exp(-3.6 * dt)
        } else {
            yawVelocity = 0
        }
        // The idle turntable: after five quiet seconds it eases up to a
        // slow orbit over about four seconds.
        let idle = idleDrift && Date().timeIntervalSince(lastInteraction) > 5
        driftRate += ((idle ? 0.012 : 0) - driftRate) * min(1, dt * 0.6)
        if idle { goal.yaw += dt * driftRate }
        spring.step(to: goal, smoothTime: smoothTime, dt: dt)
        rig = spring.rig
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
        // Labels stay in the part of the screen the dashboard leaves free
        // and never stack: the focused stand first, then stands, then routes.
        let safe = HubFraming.safeArea(width: Double(size.width), height: Double(size.height))
        let free = CGRect(x: (safe.minX + 1) / 2 * size.width, y: (1 - safe.maxY) / 2 * size.height,
                          width: (safe.maxX - safe.minX) / 2 * size.width,
                          height: (safe.maxY - safe.minY) / 2 * size.height).insetBy(dx: -10, dy: -24)
        var placed: [CGRect] = []
        let ordered = dynamics.anchors.sorted { rank($0) < rank($1) }
        let visible: [HubProjectedAnchor] = ordered.compactMap { anchor in
            switch anchor.kind {
            case .pin: guard shot == .terminal, overlays.contains(.labels) else { return nil }
            case .pill: guard shot == .district, overlays.contains(.labels) else { return nil }
            case .callout: guard shot == .gate else { return nil }
            case .tag: guard shot == .overview, overlays.contains(.standTags) else { return nil }
            case .route: guard shot == .overview, overlays.contains(.routes), siteFocus == nil else { return nil }
            case .facility(let tag):
                guard shot == .overview, overlays.contains(.upgrades) || siteFocus == tag.kind else { return nil }
            }
            guard let p = arView.project(anchor.position),
                  p.x > -40, p.y > -40, p.x < size.width + 40, p.y < size.height + 40 else { return nil }
            // Behind the camera.
            let toPoint = anchor.position - rig.position
            let forward = rig.target - rig.position
            guard simd_dot(toPoint, forward) > 0 else { return nil }
            switch anchor.kind {
            case .tag, .route, .facility:
                let box = CGRect(x: p.x - 70, y: p.y - 26, width: 140, height: 26)
                guard free.contains(CGPoint(x: p.x, y: p.y)),
                      !placed.contains(where: { $0.intersects(box) }) else { return nil }
                placed.append(box)
            default: break
            }
            return HubProjectedAnchor(anchor: anchor, point: p)
        }
        onProjected(visible)
    }

    private func rank(_ anchor: HubAnchor) -> Int {
        switch anchor.kind {
        case .tag(let tag): tag.standIndex == dynamics.focusStand ? 0 : 1
        case .route(let tag): tag.highlighted ? 0 : 2
        case .facility(let tag): tag.kind == siteFocus ? 0 : 1
        default: 0
        }
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

    /// A finger on the glass: the camera follows it closely, and lets go
    /// of anything it was coasting on.
    private func touch() {
        lastInteraction = Date()
        smoothTime = 0.11
        driftRate = 0
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        touch()
        if g.state == .began { panVelocity = .zero }
        let t = g.translation(in: arView)
        g.setTranslation(.zero, in: arView)
        let scale = goal.distance / Float(max(arView.bounds.height, 1)) * 0.42
        let right = SIMD3<Float>(cos(goal.yaw), 0, -sin(goal.yaw))
        let back = SIMD3<Float>(sin(goal.yaw), 0, cos(goal.yaw))
        goal.target -= right * Float(t.x) * scale
        goal.target -= back * Float(t.y) * scale
        clampTarget()
        if g.state == .ended {
            // Fling: carry the release velocity, capped so a flick can't
            // throw the camera off the airfield.
            let v = g.velocity(in: arView)
            var fling = -(right * Float(v.x) + back * Float(v.y)) * scale
            let cap = goal.distance * 1.6
            if simd_length(fling) > cap { fling = simd_normalize(fling) * cap }
            panVelocity = fling
        }
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        touch()
        if g.state == .began { pinchStart = goal.distance }
        goal.distance = min(4_200, max(60, pinchStart / Float(max(g.scale, 0.05))))
    }

    @objc private func onRotate(_ g: UIRotationGestureRecognizer) {
        touch()
        if g.state == .began {
            rotateStart = goal.yaw
            yawVelocity = 0
        }
        goal.yaw = rotateStart - Float(g.rotation)
        if g.state == .ended {
            yawVelocity = max(-1.5, min(1.5, -Float(g.velocity)))
        }
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
            if e.name.hasPrefix("facility-"), let kind = HubFacilityKind(rawValue: String(e.name.dropFirst("facility-".count))) {
                onTapFacility?(kind)
                return
            }
            hit = e.parent
        }
    }

    func zoom(by factor: Float) {
        lastInteraction = Date()
        smoothTime = 0.32
        goal.distance = min(4_200, max(60, goal.distance * factor))
    }

    func rotate(by radians: Float) {
        lastInteraction = Date()
        smoothTime = 0.4
        driftRate = 0
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
