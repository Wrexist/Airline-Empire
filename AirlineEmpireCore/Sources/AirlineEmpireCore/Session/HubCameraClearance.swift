import Foundation

// Keeps the hub camera out of the buildings (docs/HUB_HANDOFF.md §0g).
//
// The orbit rig can be pinched down to 60 m and swung anywhere; at a gate
// shot's 21° pitch that puts the eye 20 m up, inside the terminal, a pier or
// the tower. Rather than clamping the zoom, the camera rises over whatever is
// below it: every roofed piece is a box with a top, and the lowest height the
// eye may fly at blends smoothly from each roof (plus a margin) to the open
// ground over a falloff distance, so the lift is continuous as the camera
// slides past a building's edge and never pops.

/// A box the camera keeps out of: a footprint and the height of its top.
public struct HubCameraObstacle: Equatable, Sendable {
    public let bounds: HubRect
    public let top: Double

    public init(bounds: HubRect, top: Double) {
        self.bounds = bounds
        self.top = top
    }
}

public struct HubCameraClearance: Equatable, Sendable {
    public let obstacles: [HubCameraObstacle]
    /// Height above a roof the eye keeps.
    public let margin: Double
    /// How far outside a footprint the lift fades to nothing, at least; a
    /// tall building's lift reaches further out (0.8 × its height), so the
    /// climb past the tower is as gentle as past a low roof.
    public let falloff: Double
    /// The eye never goes lower than this, anywhere.
    public let floor: Double

    public init(obstacles: [HubCameraObstacle], margin: Double = 8, falloff: Double = 45, floor: Double = 6) {
        self.obstacles = obstacles
        self.margin = margin
        self.falloff = falloff
        self.floor = floor
    }

    /// Every piece with a roof, the facility sites (with room for a crane)
    /// and the parked jets' envelopes (tail height).
    public init(layout: HubLayout) {
        let roofed: Set<HubPieceKind> = [.terminalHall, .pier, .jetBridge, .controlTower, .hangar, .cargoShed,
                                         .fuelTank, .officeBlock, .apartmentBlock, .house, .loungeBlock]
        var list = layout.pieces.filter { roofed.contains($0.kind) }.map {
            HubCameraObstacle(bounds: $0.groundBounds, top: $0.center.y + $0.size.y)
        }
        // The terminal as a whole, roof vaults included.
        list.append(HubCameraObstacle(bounds: layout.terminal, top: HubLayout.terminalRoofTop + 6))
        for site in layout.facilitySites {
            list.append(HubCameraObstacle(bounds: site.footprint, top: site.elevation + 34))
        }
        for stand in layout.stands {
            let tail = HubAircraftEnvelope.length(stand.maxCategory) >= 55 ? 19.0 : 13.0
            list.append(HubCameraObstacle(bounds: stand.parkedEnvelope, top: tail))
        }
        self.init(obstacles: list)
    }

    /// The lowest height the eye may fly at over (x, z).
    public func minimumHeight(x: Double, z: Double) -> Double {
        var height = floor
        for o in obstacles {
            let wanted = o.top + margin
            guard wanted > height else { continue }
            let b = o.bounds
            let dx = max(b.minX - x, 0, x - b.maxX)
            let dz = max(b.minZ - z, 0, z - b.maxZ)
            let outside = (dx * dx + dz * dz).squareRoot()
            let reach = max(falloff, wanted * 0.8)
            guard outside < reach else { continue }
            let u = 1 - outside / reach
            height = max(height, floor + (wanted - floor) * u * u * (3 - 2 * u))
        }
        return height
    }

    /// `frame` with its pitch raised (and, if it has to, its distance
    /// lengthened) until the eye clears everything below it. A frame that
    /// is already clear comes back unchanged.
    public func clear(_ frame: HubFrame, maxPitch: Double = 1.25) -> HubFrame {
        var f = frame
        for _ in 0..<8 {
            let eye = f.position
            let need = minimumHeight(x: eye.x, z: eye.z)
            guard eye.y < need - 0.01 else { break }
            if need >= f.distance * sin(maxPitch) {
                f.pitch = maxPitch
                f.distance = need / sin(maxPitch)
            } else {
                f.pitch = max(f.pitch, asin(need / f.distance))
            }
        }
        return f
    }
}
