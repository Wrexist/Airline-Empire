import SwiftUI

/// Canvas coordinates, including its bleed beneath the tab bar. Chrome is
/// measured in the same space; camera gestures still use the entire canvas.
struct MapViewport: Equatable {
    let size: CGSize
    let usable: CGRect

    init(size: CGSize, top: CGFloat, bottom: CGFloat) {
        self.size = size
        // Leave room for airport rings and labels. When large text consumes
        // most of the screen, retain a small usable strip without negative sizes.
        let margin = min(28, size.width * 0.07)
        let upper = min(max(0, top) + 20, max(0, size.height - 100))
        let lower = max(upper + 80, size.height - max(0, bottom) - 20)
        usable = CGRect(x: margin, y: upper,
                        width: max(1, size.width - 2 * margin),
                        height: max(1, min(size.height, lower) - upper))
    }

    /// Solve the 2:1 projector for the centre that puts a world point at the
    /// centre of the clear map region, rather than under a selection panel.
    func center(placing point: CGPoint, zoom: CGFloat) -> CGPoint {
        let worldWidth = max(1, size.width * zoom)
        return CGPoint(x: point.x - (usable.midX - size.width / 2) / worldWidth,
                       y: point.y - (usable.midY - size.height / 2) / (worldWidth / 2))
    }

    func fit(points: [CGPoint]) -> (zoom: CGFloat, center: CGPoint) {
        let finite = points.filter { $0.x.isFinite && $0.y.isFinite }
        guard let first = finite.first else {
            let zoom: CGFloat = MapCamera.minZoom
            return (zoom, center(placing: CGPoint(x: 0.5, y: 0.5), zoom: zoom))
        }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in finite {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        // A lone home airport should open with its region, not a tiny dot at
        // maximum zoom. For larger networks, each axis uses its actual pixels.
        let width = max(0.10, maxX - minX)
        let height = max(0.10, maxY - minY)
        let zoom = min(MapCamera.maxZoom, max(MapCamera.minZoom,
            min(usable.width / max(1, size.width) / width,
                usable.height * 2 / max(1, size.width) / height)))
        return (zoom, center(placing: CGPoint(x: (minX + maxX) / 2,
                                             y: (minY + maxY) / 2), zoom: zoom))
    }
}
