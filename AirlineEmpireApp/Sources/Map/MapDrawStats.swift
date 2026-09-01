import SwiftUI

/// Frame statistics from the live canvas, for the map runtime baseline
/// (docs/MAP_RUNTIME_BASELINE.md).
///
/// This exists because "the map feels laggy" and "labels jump while panning"
/// are claims about *interaction*, and a screenshot cannot test them. The
/// canvas records what each real draw cost and how much the label set churned
/// between consecutive frames, and publishes the totals through the canvas's
/// accessibility value — the same channel the camera already uses for its
/// zoom — so a UI test can drag the actual map on a booted simulator and read
/// actual numbers back. Collected only under `-AEUITestProbes`; a player's
/// build never pays for its own audit.
///
/// Deliberately not `@Observable`, for `MapHitGeometry`'s reason: it is
/// written from inside the draw, and observing it would let a frame's own
/// output invalidate the view that produced it.
final class MapDrawStats {
    private(set) var frames = 0
    private(set) var totalMs: Double = 0
    private(set) var worstMs: Double = 0

    /// Label churn between consecutive frames, split into the two failure
    /// modes a player reports differently:
    /// - `identityChanges`: a label appeared, vanished, or changed its text
    ///   ("Charles de Gaulle (Paris)" degrading to "CDG" mid-pan).
    /// - `positionHops`: a label moved *differently from the others*. During
    ///   a pan every label translates with the camera, which is motion, not
    ///   churn — so each frame's shared median translation is subtracted and
    ///   only the outliers count as hops (a label flipping from above its
    ///   marker to below it).
    private(set) var identityChanges = 0
    private(set) var positionHops = 0
    private(set) var comparedFrames = 0

    private var previous: [String: CGPoint] = [:]

    func record(drawMs: Double, labels: [MapLabel]) {
        frames += 1
        totalMs += drawMs
        worstMs = max(worstMs, drawMs)

        var current: [String: CGPoint] = [:]
        current.reserveCapacity(labels.count)
        for label in labels { current[label.text] = label.point }
        defer { previous = current }
        guard !previous.isEmpty else { return }
        comparedFrames += 1

        var deltasX: [CGFloat] = []
        var deltasY: [CGFloat] = []
        for (text, point) in current {
            if let before = previous[text] {
                deltasX.append(point.x - before.x)
                deltasY.append(point.y - before.y)
            } else {
                identityChanges += 1
            }
        }
        for text in previous.keys where current[text] == nil {
            identityChanges += 1
        }
        guard !deltasX.isEmpty else { return }
        let medianX = deltasX.sorted()[deltasX.count / 2]
        let medianY = deltasY.sorted()[deltasY.count / 2]
        for (text, point) in current {
            guard let before = previous[text] else { continue }
            let hopX = abs(point.x - before.x - medianX)
            let hopY = abs(point.y - before.y - medianY)
            if hopX > 2 || hopY > 2 { positionHops += 1 }
        }
    }

    /// Raw totals rather than averages, so a test can subtract a before from
    /// an after and get honest numbers for exactly the interaction it drove.
    var summary: String {
        String(format: "probe frames %d totalMs %.1f worstMs %.2f " +
                       "identity %d hops %d compared %d",
               frames, totalMs, worstMs, identityChanges, positionHops,
               comparedFrames)
    }
}
