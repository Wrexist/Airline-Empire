import Foundation

// Camera framing for the 3D hub's shots (docs/HUB_VIEW_3D.md §3).
//
// The camera is an orbit rig: a target on the ground, a distance, a pitch
// and a yaw, seen through a 24° vertical field of view. Rather than fixed
// distances per shot, each shot names a *subject* — the points that must be
// on screen — and the solver moves the target and distance until the
// subject fills the part of the screen the dashboard leaves free. So a
// regional field and an 18-stand hub both open framed, and the subject sits
// between the KPI cards and the timeline instead of under them.

/// An orbit camera. The camera sits at
/// `target + (sin yaw · cos pitch, sin pitch, cos yaw · cos pitch) · distance`
/// looking at `target`.
public struct HubFrame: Equatable, Sendable {
    public var target: HubVec
    public var distance: Double
    public var pitch: Double
    public var yaw: Double

    public init(target: HubVec, distance: Double, pitch: Double, yaw: Double) {
        self.target = target
        self.distance = distance
        self.pitch = pitch
        self.yaw = yaw
    }

    public var position: HubVec {
        let flat = cos(pitch) * distance
        return target + HubVec(sin(yaw) * flat, sin(pitch) * distance, cos(yaw) * flat)
    }
}

/// The part of the screen the dashboard leaves free, in normalised device
/// coordinates (x right, y up, both −1…1).
public struct HubSafeArea: Equatable, Sendable {
    public var minX: Double
    public var maxX: Double
    public var minY: Double
    public var maxY: Double

    public init(minX: Double, maxX: Double, minY: Double, maxY: Double) {
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
    }

    /// iPad and wide windows: KPI cards across the top, the inspector down
    /// the right, timeline and board along the bottom.
    public static let wide = HubSafeArea(minX: -0.94, maxX: 0.52, minY: -0.64, maxY: 0.56)
    /// iPhone portrait: KPI cards and shot picker on top, timeline below.
    /// Slightly wider than the screen: a tall frame crops a wide airport's
    /// ends rather than shrinking the jets to specks.
    public static let tall = HubSafeArea(minX: -1.0, maxX: 1.0, minY: -0.62, maxY: 0.44)
    /// iPhone in landscape: a slim bar across the top with the KPI chips
    /// under it, the camera controls down the right, a slim timeline
    /// along the bottom. The inspector slides over when asked for.
    public static let landscape = HubSafeArea(minX: -0.9, maxX: 0.78, minY: -0.5, maxY: 0.5)
}

/// The shots a hub camera can be asked for.
public enum HubCameraShot: Equatable, Sendable {
    case overview
    case gate(stand: Int)
    case terminal
    case district
    /// One of the player's facility sites, close enough to watch it built.
    case facility(HubFacilityKind)
}

public enum HubFraming {
    /// Vertical field of view, degrees. Narrow, so the perspective reads as
    /// isometric while keeping a little convergence.
    public static let fieldOfView = 24.0

    /// Where `point` lands on screen, in normalised device coordinates, or
    /// nil when it is behind the camera.
    public static func project(_ point: HubVec, frame: HubFrame, aspect: Double) -> (x: Double, y: Double)? {
        let eye = frame.position
        var fwd = frame.target - eye
        let len = (fwd.x * fwd.x + fwd.y * fwd.y + fwd.z * fwd.z).squareRoot()
        guard len > 0 else { return nil }
        fwd = fwd * (1 / len)
        var right = HubVec(-fwd.z, 0, fwd.x)
        let rl = right.groundLength
        guard rl > 0 else { return nil }
        right = right * (1 / rl)
        let up = HubVec(right.y * fwd.z - right.z * fwd.y, right.z * fwd.x - right.x * fwd.z,
                        right.x * fwd.y - right.y * fwd.x)
        let d = point - eye
        let z = d.x * fwd.x + d.y * fwd.y + d.z * fwd.z
        guard z > 0.5 else { return nil }
        let t = tan(fieldOfView * .pi / 360)
        return ((d.x * right.x + d.y * right.y + d.z * right.z) / (z * t * aspect),
                (d.x * up.x + d.y * up.y + d.z * up.z) / (z * t))
    }

    /// Solves target and distance so every subject point lands inside
    /// `safe`, as large as it will go, centred in it. Pitch and yaw are the
    /// shot's own.
    public static func solve(subject: [HubVec], pitch: Double, yaw: Double, aspect: Double,
                             safe: HubSafeArea, minDistance: Double = 40, maxDistance: Double = 6_000) -> HubFrame {
        guard !subject.isEmpty else {
            return HubFrame(target: .zero, distance: max(minDistance, 400), pitch: pitch, yaw: yaw)
        }
        let n = Double(subject.count)
        var target = HubVec(subject.reduce(0) { $0 + $1.x } / n, 0, subject.reduce(0) { $0 + $1.z } / n)
        let width = safe.maxX - safe.minX, height = safe.maxY - safe.minY
        let midX = (safe.minX + safe.maxX) / 2, midY = (safe.minY + safe.maxY) / 2
        let t = tan(fieldOfView * .pi / 360)
        let right = HubVec(cos(yaw), 0, -sin(yaw))
        let away = HubVec(-sin(yaw), 0, -cos(yaw))
        var distance = maxDistance
        func box(_ d: Double) -> (minX: Double, maxX: Double, minY: Double, maxY: Double)? {
            let frame = HubFrame(target: target, distance: d, pitch: pitch, yaw: yaw)
            var b = (minX: Double.infinity, maxX: -Double.infinity, minY: Double.infinity, maxY: -Double.infinity)
            for p in subject {
                guard let s = project(p, frame: frame, aspect: aspect) else { return nil }
                b = (min(b.minX, s.x), max(b.maxX, s.x), min(b.minY, s.y), max(b.maxY, s.y))
            }
            return b
        }
        // Size by bisection, then slide the target so the subject's box is
        // centred in the safe area; a few rounds converge.
        for _ in 0..<6 {
            var lo = minDistance, hi = maxDistance
            for _ in 0..<36 {
                let mid = (lo + hi) / 2
                if let b = box(mid), b.maxX - b.minX <= width, b.maxY - b.minY <= height {
                    hi = mid
                } else {
                    lo = mid
                }
            }
            distance = hi
            guard let b = box(distance) else { break }
            let ox = (b.minX + b.maxX) / 2 - midX, oy = (b.minY + b.maxY) / 2 - midY
            let wx = ox * distance * t * aspect
            let wy = oy * distance * t / max(0.2, sin(pitch))
            target = target + right * wx + away * wy
        }
        return HubFrame(target: target, distance: distance, pitch: pitch, yaw: yaw)
    }

    /// The safe area for a view of this shape: the dashboard puts the
    /// inspector beside the scene once the view is wide enough.
    public static func safeArea(width: Double, height: Double) -> HubSafeArea {
        if width > height && height < 520 { return .landscape }
        return width >= 760 && width >= height * 0.7 ? .wide : .tall
    }
}

extension HubLayout {
    /// The camera for `shot` on a view of `aspect` (width ÷ height).
    public func frame(_ shot: HubCameraShot, aspect: Double, safe: HubSafeArea) -> HubFrame {
        let deg = Double.pi / 180
        let tall = safe.maxX - safe.minX > 1.8 && aspect < 1
        switch shot {
        case .overview:
            // Terminal at the centre, both piers radiating, the kerb road
            // across the bottom (reference shot A). A tall frame trades the
            // terminal's ends for jets that still read as jets, and turns to
            // put the piers along the long axis.
            let piers = pieces(.pier).map(\.groundBounds)
            let envelopes = stands.map(\.parkedEnvelope)
            var core = (piers + envelopes).reduce(terminal) { $0.union($1) }
            if tall {
                let reach = max(piers.map { max(abs($0.minX), abs($0.maxX)) }.max() ?? 0, terminal.width * 0.2)
                core = HubRect(minX: max(core.minX, -reach), minZ: core.minZ, maxX: min(core.maxX, reach), maxZ: core.maxZ)
            }
            var subject = HubLayout.corners(HubRect(minX: max(core.minX, terminal.minX), minZ: terminal.minZ,
                                                    maxX: min(core.maxX, terminal.maxX), maxZ: terminal.maxZ),
                                            height: 19)
            for pier in piers where pier.maxX > core.minX && pier.minX < core.maxX {
                subject += HubLayout.corners(pier, height: 12)
            }
            for e in envelopes where e.maxX > core.minX && e.minX < core.maxX {
                subject += HubLayout.corners(e, height: 0)
            }
            subject += [HubVec(core.minX, 0, terminal.maxZ + 30), HubVec(core.maxX, 0, terminal.maxZ + 30)]
            return HubFraming.solve(subject: subject, pitch: 32 * deg, yaw: (tall ? 50 : 35) * deg,
                                    aspect: aspect, safe: safe, minDistance: 200)
        case .gate(let index):
            guard index >= 0, index < stands.count else { return frame(.overview, aspect: aspect, safe: safe) }
            let stand = stands[index]
            let length = HubAircraftEnvelope.length(stand.maxCategory)
            let span = HubAircraftEnvelope.span(stand.maxCategory)
            let fwd = HubVec(cos(stand.heading), 0, -sin(stand.heading))
            let right = HubVec(cos(stand.heading - .pi / 2), 0, -sin(stand.heading - .pi / 2))
            let center = stand.nose - fwd * (length / 2 + 2)
            // Behind the tail and to one side, so the concourse and the gate
            // sign stand beyond the jet (reference shot B): the side away
            // from the terminal, the door side on a tie.
            let side = right.z < -1e-6 ? right : right * -1
            let offset = side * 0.66 - fwd * 0.75
            // The jet itself — nose, tail and fin, swept wingtips — and the
            // bridge, not the empty corners of its bounding box.
            let tips = center - fwd * (length * 0.18)
            let subject: [HubVec] = [
                center + fwd * (length / 2) + HubVec(0, 3, 0),
                center - fwd * (length / 2),
                center - fwd * (length * 0.45) + HubVec(0, 11, 0),
                tips + right * (span / 2) + HubVec(0, 2.5, 0),
                tips - right * (span / 2) + HubVec(0, 2.5, 0),
                stand.bridgeRoot + HubVec(0, 7, 0),
            ]
            return HubFraming.solve(subject: subject, pitch: 21 * deg, yaw: atan2(offset.x, offset.z),
                                    aspect: aspect, safe: safe, minDistance: 60)
        case .terminal:
            // One bay of the hall as a doll's house: floor, back wall and the
            // far side wall, looking into the corner (reference shot C).
            let first = interior.hotspots.first?.position.x ?? interior.bounds.minX
            let bay = (0..<max(1, interior.bays)).map { interior.bay($0) }
                .first { $0.minX <= first && first <= $0.maxX } ?? interior.bay(0)
            var subject = HubLayout.corners(bay, height: 0).map { HubVec($0.x, 1.7, $0.z) }
            subject += [HubVec(bay.minX, 13, bay.minZ), HubVec(bay.maxX, 13, bay.minZ)]
            return HubFraming.solve(subject: subject, pitch: 38 * deg, yaw: 35 * deg,
                                    aspect: aspect, safe: safe, minDistance: 60)
        case .district:
            // The first stop's villa with the mid-rise block behind it
            // (reference shot D).
            let stop = serviceStops.first ?? focus.district
            var subject = [-28.0, 28.0].flatMap { dx in [-28.0, 28.0].map { dz in stop + HubVec(dx, 0, dz) } }
            if let block = pieces(.apartmentBlock).min(by: { $0.center.distance(to: stop) < $1.center.distance(to: stop) }) {
                let r = block.groundBounds
                subject += [HubVec(r.minX, block.size.y, r.minZ), HubVec(r.maxX, block.size.y, r.minZ)]
            }
            return HubFraming.solve(subject: subject, pitch: 28 * deg, yaw: 35 * deg,
                                    aspect: aspect, safe: safe, minDistance: 60)
        case .facility(let kind):
            // The site with room round it and the height of the finished
            // building, so the construction plays out in frame.
            guard let site = site(kind) else { return frame(.overview, aspect: aspect, safe: safe) }
            let r = site.footprint
            let margin = kind == .lounge ? 36.0 : 24.0
            let around = HubRect(minX: r.minX - margin, minZ: r.minZ - margin, maxX: r.maxX + margin, maxZ: r.maxZ + margin)
            var subject = HubLayout.corners(around, height: 0).map { HubVec($0.x, site.elevation, $0.z) }
            subject += HubLayout.corners(r, height: 0).map { HubVec($0.x, site.elevation + 16, $0.z) }
            return HubFraming.solve(subject: subject, pitch: 30 * deg, yaw: 35 * deg,
                                    aspect: aspect, safe: safe, minDistance: 70)
        }
    }

    static func corners(_ r: HubRect, height: Double) -> [HubVec] {
        let ground = [HubVec(r.minX, 0, r.minZ), HubVec(r.maxX, 0, r.minZ),
                      HubVec(r.maxX, 0, r.maxZ), HubVec(r.minX, 0, r.maxZ)]
        guard height > 0 else { return ground }
        return ground + ground.map { HubVec($0.x, height, $0.z) }
    }
}
