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

    /// Lifted over whatever is under the eye (`HubCameraClearance`), so a
    /// pinch or a pan never puts the camera inside a building.
    func cleared(by clearance: HubCameraClearance) -> HubCameraRig {
        let frame = HubFrame(target: HubVec(Double(target.x), 0, Double(target.z)), distance: Double(distance),
                             pitch: Double(pitch), yaw: Double(yaw))
        let clear = clearance.clear(frame)
        return clear == frame ? self : HubCameraRig(clear)
    }

    /// Within a centimetre and a hundredth of a degree: the springs creep
    /// towards their goal for ever, and the labels need not follow motion
    /// well under a point.
    func isClose(to other: HubCameraRig) -> Bool {
        simd_distance_squared(target, other.target) < 0.000_1 && abs(distance - other.distance) < 0.01
            && abs(pitch - other.pitch) < 0.000_2 && abs(yaw - other.yaw) < 0.000_2
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
    /// Hot or in Low Power Mode (`HubDevice.shouldRest`), read once a second.
    private var resting = false
    private var restCheck: Float = 0
    private var nightValue: Double = 0
    private var lastInteraction = Date()
    private let idleDrift: Bool
    /// Roofs the camera rises over.
    private let clearance: HubCameraClearance
    /// Labels on screen last frame: they keep their place against newcomers
    /// and get a little slack at the edge of the free area, so they do not
    /// flicker as the camera moves.
    private var shownAnchors: Set<String> = []

    var onProjected: (([HubProjectedAnchor]) -> Void)?
    var onTapAircraft: ((Int) -> Void)?
    var onTapFacility: ((HubFacilityKind) -> Void)?
    /// The facility site the camera has flown to, if any.
    private(set) var siteFocus: HubFacilityKind?
    private(set) var shot: HubShot = .overview

    init(layout: HubLayout, idleDrift: Bool = true) {
        self.layout = layout
        self.idleDrift = idleDrift
        clearance = HubCameraClearance(layout: layout)
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
        // Bloom is a full-screen pass a 3 GB device (A12, A13) cannot spare
        // at 60 frames; it starts there a quality step down, without it.
        if HubDevice.isLowMemory {
            quality = 1
        } else if !ProcessInfo.processInfo.arguments.contains("-AEHubNoBloom") {
            post.install(on: arView)
            bloomInstalled = true
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
        // Flat things cast no shadow worth a second draw in the shadow pass.
        for layer in [HubLayer.ground, .markings, .shadows, .lamps] {
            layers[layer]?.setCastsShadows(false)
        }
        dynamics = HubDynamics(layout: layout, models: models, materials: materials)
        // Build the additive glow program in the background; the pulse rings
        // switch to it once it exists.
        Task { [materials] in await materials.prepareAdditive() }
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
    /// subject fills the part of a `size` view the dashboard leaves free —
    /// with the inspector's column, or without it while it is closed.
    static func rig(for shot: HubShot, layout: HubLayout, focus: HubStand?, size: CGSize,
                    inspector: Bool = true) -> HubCameraRig {
        let w = Double(max(size.width, 1)), h = Double(max(size.height, 1))
        let safe = HubFraming.safeArea(width: w, height: h, inspector: inspector)
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
    private var framedSize: CGSize = .zero
    private var framedForRealBounds = false
    private var focusIndex: Int?

    /// Whether the view has changed shape enough to frame the shot again.
    /// Aspect alone misses a fold: iPhone Duo's outer and inner displays on
    /// their sides are 1.455 and 1.422 — nearly the same ratio at almost
    /// twice the size, and with different chrome over them.
    private var needsReframe: Bool {
        if abs(aspect - framedAspect) > 0.05 { return true }
        let size = arView.bounds.size
        guard framedSize.width > 0, framedSize.height > 0 else { return false }
        return abs(size.width / framedSize.width - 1) > 0.08
            || abs(size.height / framedSize.height - 1) > 0.08
    }

    func show(_ shot: HubShot, focus: Int?, animated: Bool = true) {
        self.shot = shot
        siteFocus = nil
        focusIndex = focus
        framedAspect = aspect
        framedSize = arView.bounds.size
        framedForRealBounds = arView.bounds.height > 0
        cameraIsFramed = true
        projectionsDirty = true
        let stand = focus.flatMap { $0 < layout.stands.count ? layout.stands[$0] : nil }
        let size = arView.bounds.height > 0 ? arView.bounds.size : CGSize(width: 1_376, height: 1_032)
        goal = Self.rig(for: shot, layout: layout, focus: stand, size: size, inspector: inspectorShown)
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
        frameFacility(kind)
        panVelocity = .zero
        yawVelocity = 0
        driftRate = 0
        smoothTime = 0.6
        applyOverlays()
        projectionsDirty = true
        lastInteraction = Date()
    }

    /// The upgrade card's height along the bottom of a narrow window, as
    /// laid out (the dashboard measures it); 0 while it is beside the site.
    private var facilityCard: CGFloat = 0

    func setFacilityCard(height: CGFloat) {
        guard abs(height - facilityCard) > 12 else { return }
        facilityCard = height
        projectionsDirty = true
        // The card grew or shrank under the site being watched: frame it
        // again in the room that is left.
        if let site = siteFocus { frameFacility(site) }
    }

    /// The camera for a facility site, in the part of the screen the
    /// upgrade card leaves, so the construction is never under the card:
    /// the card takes the right of a wide screen and the bottom of a
    /// narrow one.
    private func frameFacility(_ kind: HubFacilityKind) {
        let size = arView.bounds.height > 0 ? arView.bounds.size : CGSize(width: 1_376, height: 1_032)
        let w = Double(max(size.width, 1)), h = Double(max(size.height, 1))
        goal = HubCameraRig(layout.frame(.facility(kind), aspect: w / h, safe: facilitySafeArea(size)))
        goal.yaw = rig.yaw + (goal.yaw - rig.yaw).remainder(dividingBy: 2 * .pi)
    }

    /// The part of a `size` view the upgrade card leaves free.
    private func facilitySafeArea(_ size: CGSize) -> HubSafeArea {
        let w = Double(max(size.width, 1)), h = Double(max(size.height, 1))
        // A side panel, not the inspector, has the right column now.
        let safe = HubFraming.safeArea(width: w, height: h, inspector: false)
        switch HubChromeMode(size: size) {
        case .regular: return safe.clearing(right: 340 + 64 + 28, of: w)
        case .landscape: return safe.clearing(right: 300 + 60 + 24, of: w)
        case .portrait:
            // Until the card has been measured, about the compact card.
            let card = Double(facilityCard > 0 ? facilityCard : 300)
            return safe.clearing(bottom: card + 12 + 8 + Double(arView.safeAreaInsets.bottom), of: h)
        }
    }

    func leaveFacility() {
        guard siteFocus != nil else { return }
        siteFocus = nil
        applyOverlays()
        projectionsDirty = true
    }

    // MARK: Inspector

    /// Whether the inspector (or a side panel in its place) has the right
    /// column of a wide window. Framing and labels leave the column free
    /// only while it does.
    private var inspectorShown = true
    /// The camera still sits where the last shot put it: no pan, pinch or
    /// twist since. Only then does the inspector opening or closing frame
    /// the shot again — a camera the player placed stays where they put it.
    private var cameraIsFramed = true

    func setInspector(shown: Bool) {
        guard shown != inspectorShown else { return }
        let size = arView.bounds.size
        let w = Double(size.width), h = Double(size.height)
        let changesFraming = w > 0 && h > 0
            && HubFraming.safeArea(width: w, height: h, inspector: shown)
            != HubFraming.safeArea(width: w, height: h, inspector: inspectorShown)
        inspectorShown = shown
        projectionsDirty = true
        guard changesFraming, cameraIsFramed, siteFocus == nil else { return }
        let keepDrift = lastInteraction
        show(shot, focus: focusIndex)
        lastInteraction = keepDrift
    }

    /// The next level of a building as a blueprint on its site; nil hides it.
    func showBlueprint(_ target: (kind: HubFacilityKind, level: Int)?) {
        dynamics?.yard.showBlueprint(target)
    }

    /// Plays a building's opening again: one that opened while away.
    func replayFacility(_ kind: HubFacilityKind) {
        dynamics?.yard.replay(kind)
    }

    // MARK: Overlays

    private(set) var overlays: Set<HubOverlay> = Set(HubOverlay.allCases)

    func setOverlays(_ value: Set<HubOverlay>) {
        overlays = value
        applyOverlays()
        projectionsDirty = true
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
        dynamics.repainted()
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

    private func tick(_ rawDT: Float) {
        let dt = min(rawDT, 0.1)
        dynamics.cameraPosition = rig.position
        dynamics.update(dt)
        // Reframe when the view changes shape (rotation, split view, a fold)
        // unless the player has just moved the camera. A construction site
        // being watched stays the subject: `show` clears it, so fly back.
        if needsReframe
            && (!framedForRealBounds || Date().timeIntervalSince(lastInteraction) > 1.5) {
            let keepDrift = lastInteraction
            let site = siteFocus
            show(shot, focus: focusIndex, animated: !framedForRealBounds ? false : true)
            if let site { showFacility(site) }
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
        // slow orbit over about four seconds, and after a minute eases out
        // again — a hub left open must not re-lay its labels sixty times a
        // second forever. Never on a hot device or in Low Power Mode.
        restCheck -= dt
        if restCheck <= 0 {
            restCheck = 1
            resting = HubDevice.shouldRest
        }
        let quiet = Date().timeIntervalSince(lastInteraction)
        let idle = idleDrift && !resting && quiet > 5 && quiet < 65
        driftRate += ((idle ? 0.012 : 0) - driftRate) * min(1, dt * 0.6)
        if idle || driftRate > 0.000_1 { goal.yaw += dt * driftRate } else { driftRate = 0 }
        spring.step(to: goal, smoothTime: smoothTime, dt: dt)
        rig = spring.rig.cleared(by: clearance)
        applyRig()
        // People a few pixels tall need not be re-posed every frame.
        dynamics.crowdDetail = rig.distance > 1_100 ? 3 : rig.distance > 600 ? 2 : 1
        // Every frame, after the camera has moved: the labels are projected
        // with the camera this frame renders with, so they stay pinned.
        publishProjections()
        adaptQuality(Float(rawDT))
        if gestureHost == nil { hostCameraGestures() }
    }

    // MARK: Quality

    private var bloomInstalled = false
    /// 0 full; 1 no bloom, a little less resolution; 2 no shadows, less again.
    private var quality = 0
    private var frameTime: Float = 1.0 / 60
    private var slowFor: Float = 0
    private var warmUp: Float = 2.5
    private var thermalCheck = 0
    private var appliedScale: CGFloat = 0

    /// Steps quality down when frames run long for a few seconds, or the
    /// device runs hot; never back up within a visit, so it cannot oscillate.
    private func adaptQuality(_ dt: Float) {
        // The Simulator renders in software at its own pace, and the review
        // captures should show the full look: devices only.
        #if !targetEnvironment(simulator)
        updateRenderScale()
        if warmUp > 0 {
            warmUp -= dt
            return
        }
        frameTime += (min(dt, 0.2) - frameTime) * 0.05
        slowFor = frameTime > 1.0 / 42 ? slowFor + dt : max(0, slowFor - dt * 0.5)
        var wanted = quality
        if slowFor > 2.5 && quality < 2 {
            wanted = quality + 1
            slowFor = 0
        }
        thermalCheck += 1
        if thermalCheck >= 60 {
            thermalCheck = 0
            switch ProcessInfo.processInfo.thermalState {
            case .serious: wanted = max(wanted, 1)
            case .critical: wanted = 2
            default: break
            }
        }
        guard wanted > quality else { return }
        quality = wanted
        if quality >= 1, bloomInstalled {
            arView.renderCallbacks.postProcess = nil
            bloomInstalled = false
        }
        if quality >= 2 {
            sun.shadow = nil
        }
        appliedScale = 0
        #endif
    }

    /// Renders at most about 3.6 million pixels: an iPad Pro at its full 2×
    /// is 5.7 million, most of them spent on soft clay that looks the same a
    /// little under. The dashboard is SwiftUI and stays sharp.
    private func updateRenderScale() {
        let size = arView.bounds.size
        guard size.width > 1, size.height > 1 else { return }
        let native = arView.window?.windowScene?.screen.nativeScale ?? arView.traitCollection.displayScale
        let fit = (3_600_000 / (size.width * size.height)).squareRoot()
        let step: [CGFloat] = [1, 0.85, 0.72]
        let scale = max(1, min(native, 2.5, fit) * step[min(quality, 2)])
        guard abs(scale - appliedScale) > 0.01 else { return }
        appliedScale = scale
        arView.contentScaleFactor = scale
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
        guard quality < 2 else { return }
        let wanted = rig.distance * 2.4 + 120
        guard shadowRange == 0 || abs(wanted - shadowRange) / shadowRange > 0.2 else { return }
        shadowRange = wanted
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: wanted, depthBias: 3)
    }

    // MARK: Labels

    /// Something other than the camera changed what the labels show (a
    /// shot, the layers, a site, the inspector): project them again even
    /// if the camera has not moved.
    private var projectionsDirty = true
    private var projectedRig: HubCameraRig?
    private var projectedRevision = -1
    private var projectedSize: CGSize = .zero
    /// The labels in placing order, kept between frames: sorted again only
    /// when the labels or the set already showing change.
    private var orderedAnchors: [HubAnchor] = []
    private var orderedRevision = -1
    /// Reused every projection instead of allocated.
    private var placedBoxes: [CGRect] = []
    private var shownScratch: Set<String> = []
    /// Where the tappable labels are on screen this frame, so a pan, pinch
    /// or twist that starts on one still moves the camera (`acceptsCameraTouch`).
    private var labelBoxes: [CGRect] = []

    private func publishProjections() {
        guard let onProjected else { return }
        let size = arView.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        // Nothing moved — the camera has settled, the labels are as they
        // were — and nothing moves by itself: last frame's layout stands.
        let moving = dynamics.hasMovingAnchors
        let dirty = projectionsDirty
        if !dirty, !moving, size == projectedSize, dynamics.anchorsRevision == projectedRevision,
           let last = projectedRig, last.isClose(to: rig) {
            return
        }
        projectionsDirty = false
        projectedSize = size
        projectedRevision = dynamics.anchorsRevision
        projectedRig = rig
        // Labels stay wholly inside the part of the screen the dashboard
        // leaves free and never stack: the focused stand first, then
        // stands, then routes, then the live figures. A label already
        // showing keeps its place, with a few points of slack at the edge
        // so it does not flicker there as the camera moves.
        let mode = HubChromeMode(size: size)
        // With an upgrade card open, what the card leaves.
        let safe = siteFocus != nil ? facilitySafeArea(size)
            : HubFraming.safeArea(width: Double(size.width), height: Double(size.height), inspector: inspectorShown)
        var free = CGRect(x: (safe.minX + 1) / 2 * size.width, y: (1 - safe.maxY) / 2 * size.height,
                          width: (safe.maxX - safe.minX) / 2 * size.width,
                          height: (safe.maxY - safe.minY) / 2 * size.height)
        if siteFocus == nil && mode == .landscape && inspectorShown {
            // A phone's inspector slides over the right of the scene.
            let edge = size.width - arView.safeAreaInsets.right - 312
            free.size.width = max(0, min(free.maxX, edge) - free.minX)
        }
        let roomy = free.insetBy(dx: -8, dy: -8)
        let all = dynamics.anchors
        // The order depends on the focus, the site and what showed last
        // frame, all of which mark the projection dirty.
        if dirty || moving || dynamics.anchorsRevision != orderedRevision {
            orderedRevision = dynamics.anchorsRevision
            orderedAnchors = all.enumerated().sorted { a, b in
                let ra = rank(a.element), rb = rank(b.element)
                if ra != rb { return ra < rb }
                let sa = shownAnchors.contains(a.element.id), sb = shownAnchors.contains(b.element.id)
                if sa != sb { return sa }
                return a.offset < b.offset
            }.map(\.element)
        }
        placedBoxes.removeAll(keepingCapacity: true)
        labelBoxes.removeAll(keepingCapacity: true)
        var visible: [HubProjectedAnchor] = []
        visible.reserveCapacity(orderedAnchors.count)
        let forward = rig.target - rig.position
        for anchor in orderedAnchors {
            switch anchor.kind {
            case .pin: guard shot == .terminal, overlays.contains(.labels) else { continue }
            case .pill: guard shot == .district, overlays.contains(.labels) else { continue }
            case .callout: guard shot == .gate else { continue }
            case .tag: guard shot == .overview, overlays.contains(.standTags) else { continue }
            case .route: guard shot == .overview, overlays.contains(.routes), siteFocus == nil else { continue }
            case .facility(let tag):
                guard shot == .overview, overlays.contains(.upgrades) || siteFocus == tag.kind else { continue }
            case .stat: guard shot == .overview, overlays.contains(.labels), siteFocus == nil else { continue }
            case .popup: guard shot == .overview || shot == .gate else { continue }
            }
            // Behind the camera.
            guard simd_dot(anchor.position - rig.position, forward) > 0,
                  let p = arView.project(anchor.position),
                  p.x > -40, p.y > -40, p.x < size.width + 40, p.y < size.height + 40 else { continue }
            if case .callout = anchor.kind {
                // Never hidden: the overlay holds it inside the free band
                // over its jet (`HubAnchorOverlay.calloutCenter`). It claims
                // its box first, so nothing is laid over it.
                let box = Self.calloutBox(p, compact: mode == .landscape, in: free)
                placedBoxes.append(box)
                labelBoxes.append(box)
            } else if let box = Self.labelBox(anchor.kind, at: p) {
                let region = shownAnchors.contains(anchor.id) ? roomy : free
                // The site being watched is the subject, framed to fill the
                // free area: its tag floats over the building, often just
                // past the area's top, and is kept as long as its anchor
                // is inside.
                var watched = false
                if case .facility(let tag) = anchor.kind { watched = tag.kind == siteFocus }
                let fits = watched ? region.insetBy(dx: -10, dy: -24).contains(p) : region.contains(box)
                guard fits, !placedBoxes.contains(where: { $0.intersects(box) }) else { continue }
                placedBoxes.append(box)
                switch anchor.kind {
                case .tag, .facility, .stat, .route: labelBoxes.append(box)
                default: break
                }
            }
            visible.append(HubProjectedAnchor(anchor: anchor, point: p))
        }
        shownScratch.removeAll(keepingCapacity: true)
        for item in visible { shownScratch.insert(item.id) }
        if shownScratch != shownAnchors {
            let previous = shownAnchors
            shownAnchors = shownScratch
            shownScratch = previous
            // Those showing now go first: place once more next frame.
            projectionsDirty = true
        }
        onProjected(visible)
    }

    /// Where a label is drawn, in view points: above its anchor on its
    /// stem, or centred on it. Nil for the pop-ups, which float free.
    private static func labelBox(_ kind: HubAnchor.Kind, at p: CGPoint) -> CGRect? {
        switch kind {
        case .tag: return CGRect(x: p.x - 85, y: p.y - 42, width: 170, height: 32)
        case .facility: return CGRect(x: p.x - 85, y: p.y - 52, width: 170, height: 40)
        case .stat: return CGRect(x: p.x - 90, y: p.y - 56, width: 180, height: 42)
        case .route: return CGRect(x: p.x - 70, y: p.y - 13, width: 140, height: 26)
        case .pin(let label):
            // The name's capsule over the teardrop, drawn 24 pt up.
            let width = max(40, CGFloat(label.count) * 6.6 + 18)
            return CGRect(x: p.x - width / 2, y: p.y - 56, width: width, height: 64)
        case .pill(let label, _):
            let width = CGFloat(label.count) * 7 + 42
            return CGRect(x: p.x - width / 2, y: p.y - 14, width: width, height: 28)
        case .callout, .popup: return nil
        }
    }

    /// The callout's box: over its jet, held inside `free`, the size of
    /// `HubCallout` (one line and a bar on a phone on its side).
    private static func calloutBox(_ p: CGPoint, compact: Bool, in free: CGRect) -> CGRect {
        let half = compact ? CGSize(width: 110, height: 30) : CGSize(width: 118, height: 80)
        let left = free.minX + half.width, right = max(left, free.maxX - half.width)
        let top = free.minY + half.height, bottom = max(top, free.maxY - half.height)
        let x = min(max(p.x, left), right)
        let y = min(max(p.y - 60 - half.height, top), bottom)
        return CGRect(x: x - half.width, y: y - half.height, width: half.width * 2, height: half.height * 2)
    }

    private func rank(_ anchor: HubAnchor) -> Int {
        switch anchor.kind {
        case .tag(let tag): tag.standIndex == dynamics.focusStand ? 0 : 1
        case .route(let tag): tag.highlighted ? 0 : 2
        case .facility(let tag): tag.kind == siteFocus ? 0 : 1
        case .stat: 3
        default: 0
        }
    }

    // MARK: Gestures

    private var pinchStart: Float = 0
    private var rotateStart: Float = 0
    /// Pan, pinch and twist. They start on the 3D view and move up to the
    /// view that hosts the whole dashboard once it is on screen
    /// (`hostCameraGestures`), so they also hear a finger that lands on a
    /// world label: the labels sit over the scene in SwiftUI, and used to
    /// swallow any pan or pinch begun on one. A tap on a label stays the
    /// label's own (its button, its accessibility identifier); a tap on the
    /// scene stays the 3D view's.
    private var cameraGestures: [UIGestureRecognizer] = []
    private weak var gestureHost: UIView?
    /// Off while a panel is open: a drag inside it is the panel's.
    var labelsPassCameraGestures = true

    private func installGestures() {
        let relay = HubGestureRelay(scene: self)
        let pan = HubCameraPan(target: relay, action: #selector(HubGestureRelay.pan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.relay = relay
        let pinch = HubCameraPinch(target: relay, action: #selector(HubGestureRelay.pinch(_:)))
        pinch.relay = relay
        let rotate = HubCameraRotation(target: relay, action: #selector(HubGestureRelay.rotate(_:)))
        rotate.relay = relay
        cameraGestures = [pan, pinch, rotate]
        for g in cameraGestures {
            g.delegate = relay
            arView.addGestureRecognizer(g)
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        tap.delegate = self
        arView.addGestureRecognizer(tap)
    }

    /// Moves the camera gestures to the view controller's view that holds
    /// the 3D view and every label over it — the hub's own presentation —
    /// once the scene is in a window. Until then, or if there is none,
    /// they stay on the 3D view, as before.
    private func hostCameraGestures() {
        guard gestureHost == nil, arView.window != nil else { return }
        var responder: UIResponder? = arView.next
        while let next = responder, !(next is UIViewController) { responder = next.next }
        guard let host = (responder as? UIViewController)?.view, host !== arView else { return }
        for g in cameraGestures { host.addGestureRecognizer(g) }
        gestureHost = host
    }

    /// Back onto the 3D view while paused: nothing is left on a view that
    /// outlives this scene (a hub switch keeps the presentation).
    private func lowerCameraGestures() {
        guard gestureHost != nil else { return }
        for g in cameraGestures { arView.addGestureRecognizer(g) }
        gestureHost = nil
    }

    /// Whether a camera gesture may take this touch: any on the 3D view,
    /// and one on a tappable label while no panel is open.
    fileprivate func acceptsCameraTouch(_ touch: UITouch) -> Bool {
        if let view = touch.view, view.isDescendant(of: arView) { return true }
        guard labelsPassCameraGestures, !labelBoxes.isEmpty else { return false }
        let p = touch.location(in: arView)
        return labelBoxes.contains { $0.contains(p) }
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
        cameraIsFramed = false
    }

    fileprivate func onPan(_ g: UIPanGestureRecognizer) {
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

    fileprivate func onPinch(_ g: UIPinchGestureRecognizer) {
        touch()
        if g.state == .began { pinchStart = goal.distance }
        goal.distance = min(4_200, max(60, pinchStart / Float(max(g.scale, 0.05))))
    }

    fileprivate func onRotate(_ g: UIRotationGestureRecognizer) {
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
        cameraIsFramed = false
        goal.distance = min(4_200, max(60, goal.distance * factor))
    }

    func rotate(by radians: Float) {
        lastInteraction = Date()
        smoothTime = 0.4
        driftRate = 0
        cameraIsFramed = false
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
            lowerCameraGestures()
        } else if updates == nil {
            updates = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                MainActor.assumeIsolated { self?.tick(Float(event.deltaTime)) }
            }
        }
    }
}

/// Target and delegate of the camera gestures. Each gesture holds its
/// relay and the relay only a weak reference to the scene, so a gesture
/// left on the hosting view can never message a scene that has gone — it
/// just stops taking touches.
@available(iOS 18.0, *)
@MainActor
private final class HubGestureRelay: NSObject, UIGestureRecognizerDelegate {
    weak var scene: HubSceneController?

    init(scene: HubSceneController) {
        self.scene = scene
    }

    @objc func pan(_ g: UIPanGestureRecognizer) { scene?.onPan(g) }
    @objc func pinch(_ g: UIPinchGestureRecognizer) { scene?.onPinch(g) }
    @objc func rotate(_ g: UIRotationGestureRecognizer) { scene?.onRotate(g) }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        scene?.acceptsCameraTouch(touch) ?? false
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// The camera gestures, each keeping its relay alive (UIKit holds neither
/// a target nor a delegate strongly).
private final class HubCameraPan: UIPanGestureRecognizer {
    var relay: AnyObject?
}

private final class HubCameraPinch: UIPinchGestureRecognizer {
    var relay: AnyObject?
}

private final class HubCameraRotation: UIRotationGestureRecognizer {
    var relay: AnyObject?
}

@available(iOS 18.0, *)
extension Entity {
    /// Sets whether this entity and everything under it casts shadows from
    /// the sun. Small and flat things are not worth a draw in the shadow pass.
    @MainActor
    func setCastsShadows(_ casts: Bool) {
        components.set(DynamicLightShadowComponent(castsShadow: casts))
        for child in children { child.setCastsShadows(casts) }
    }
}
