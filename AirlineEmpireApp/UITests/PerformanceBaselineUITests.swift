import XCTest

/// The measurements.
///
/// Alone in its own class **and run in its own uncontended xcodebuild pass**,
/// because these are the only numbers this project treats as evidence: the
/// map's rebuild and replay counters, and cold launch. A figure measured
/// while three other simulators fight for the same cores is not comparable
/// with the figures in `docs/MAP_P0_PERFORMANCE_REPORT.md`, and a benchmark
/// that is not comparable is not a benchmark.
final class PerformanceBaselineUITests: AEUITestCase {

    /// No test-only control on screen while the shipped screen is being
    /// measured: these numbers are compared with figures already recorded
    /// in docs/MAP_P0_PERFORMANCE_REPORT.md.
    override var wantsSunriseWeek: Bool { false }


    /// The map's interaction baseline: drag it, zoom it, and measure it.
    ///
    /// This is MAP TESTS B, C, E and F from the AE-034 brief, driven against
    /// the booted simulator, with the numbers read back from the canvas's own
    /// draw-stats probe (`MapDrawStats`, `-AEUITestProbes` only). It exists
    /// because "the map feels laggy" and "labels jump while panning" are
    /// claims about interaction, and this file's history says exactly what a
    /// screenshot is worth for those: nothing. The probe records what every
    /// real frame cost and how much the label set churned between consecutive
    /// frames; this test drives the gestures and prints the deltas, so the
    /// baseline document quotes measurements rather than impressions.
    ///
    /// Deliberately records rather than judges: no threshold assertions in
    /// the baseline, because a bar invented before the first measurement is a
    /// number pretending to be a standard. The assertions here are only that
    /// the probe exists and that frames were actually drawn while dragging —
    /// without those, the numbers would be fiction.
    func testMapInteractionBaselineMeasurements() throws {
        launch(appearance: .light, arguments: ["-AEUITestProbes"])
        guard foundAirline() else { return }
        openTab("Map")

        let map = app.descendants(matching: .any)["ae-map-canvas"]
        require(map, "the map canvas")

        func stats() -> (frames: Int, totalMs: Double, worstMs: Double,
                         identity: Int, hops: Int, compared: Int)? {
            // Nudge one body rebuild so the published value is current: the
            // stats class is deliberately unobservable, so the value string
            // only refreshes when something else invalidates the view.
            app.buttons["Zoom in"].tap()
            app.buttons["Zoom out"].tap()
            Thread.sleep(forTimeInterval: 0.8)
            let value = map.value as? String ?? ""
            // The render-cache counters ride the same channel and only exist
            // under the probes flag, so this — not the un-probed zoom test —
            // is where they reach the log. Printed at every checkpoint; the
            // per-sequence deltas are the difference between prints. Run 85
            // carried none because the only print sat in a test that never
            // launches with -AEUITestProbes.
            if let cacheRange = value.range(
                of: #"cache rebuilds \d+ replays \d+ placements \d+ reasons \[[^\]]*\]"#,
                options: .regularExpression) {
                print("MAP-CACHE \(value[cacheRange])")
            }
            guard let range = value.range(
                of: #"probe frames (\d+) totalMs ([0-9.]+) worstMs ([0-9.]+) identity (\d+) hops (\d+) compared (\d+)"#,
                options: .regularExpression) else { return nil }
            // "probe frames N totalMs M worstMs W identity I hops H
            // compared C" — thirteen tokens, values at the even indices.
            let parts = value[range].split(separator: " ")
            guard parts.count >= 13,
                  let frames = Int(parts[2]), let total = Double(parts[4]),
                  let worst = Double(parts[6]), let identity = Int(parts[8]),
                  let hops = Int(parts[10]), let compared = Int(parts[12])
            else { return nil }
            return (frames, total, worst, identity, hops, compared)
        }

        // The render-cache counters, read from the value stats() just
        // refreshed. Parsed separately so the timing tuple keeps its shape.
        func cacheCounters() -> (rebuilds: Int, replays: Int,
                                 placements: Int)? {
            let value = map.value as? String ?? ""
            guard let range = value.range(
                of: #"cache rebuilds (\d+) replays (\d+) placements (\d+)"#,
                options: .regularExpression) else { return nil }
            let parts = value[range].split(separator: " ")
            guard parts.count >= 7, let rebuilds = Int(parts[2]),
                  let replays = Int(parts[4]), let placements = Int(parts[6])
            else { return nil }
            return (rebuilds, replays, placements)
        }

        func report(_ label: String,
                    from before: (frames: Int, totalMs: Double, worstMs: Double,
                                  identity: Int, hops: Int, compared: Int),
                    to after: (frames: Int, totalMs: Double, worstMs: Double,
                               identity: Int, hops: Int, compared: Int)) {
            let frames = after.frames - before.frames
            let ms = after.totalMs - before.totalMs
            let compared = max(1, after.compared - before.compared)
            print(String(
                format: "MAP-BASELINE %@: frames %d avg %.2fms worst %.2fms " +
                        "identityChurn/frame %.2f hops/frame %.2f",
                label, frames, frames > 0 ? ms / Double(frames) : 0,
                after.worstMs,
                Double(after.identity - before.identity) / Double(compared),
                Double(after.hops - before.hops) / Double(compared)))
        }

        guard let atOpen = stats() else {
            throw XCTSkip("""
                The canvas published no draw-stats probe under -AEUITestProbes;
                the interaction numbers cannot be measured this run.
                """)
        }
        print("MAP-BASELINE at-open: \(atOpen)")

        // ── MAP TEST E: world → regional, where labels are dense ─────────
        for _ in 0..<2 { app.buttons["Zoom in"].tap() }
        Thread.sleep(forTimeInterval: 1)
        checkpoint("B0-baseline-before-drag")
        guard let beforeDrag = stats() else { return }
        let cacheBefore = cacheCounters()

        // ── MAP TEST B: continuous drag across the region ────────────────
        let strokes: [(CGVector, CGVector)] = [
            (CGVector(dx: 0.75, dy: 0.45), CGVector(dx: 0.25, dy: 0.5)),
            (CGVector(dx: 0.25, dy: 0.5), CGVector(dx: 0.7, dy: 0.55)),
            (CGVector(dx: 0.7, dy: 0.6), CGVector(dx: 0.3, dy: 0.4)),
            (CGVector(dx: 0.3, dy: 0.4), CGVector(dx: 0.75, dy: 0.5)),
        ]
        for (from, to) in strokes {
            map.coordinate(withNormalizedOffset: from)
                .press(forDuration: 0.05,
                       thenDragTo: map.coordinate(withNormalizedOffset: to),
                       withVelocity: .slow, thenHoldForDuration: 0.05)
        }
        checkpoint("B1-baseline-after-slow-drag")
        guard let afterSlow = stats() else { return }
        report("slow-drag", from: beforeDrag, to: afterSlow)

        // ── MAP TEST C: rapid alternating drags ──────────────────────────
        for index in 0..<6 {
            let from = CGVector(dx: index.isMultiple(of: 2) ? 0.8 : 0.2, dy: 0.5)
            let to = CGVector(dx: index.isMultiple(of: 2) ? 0.2 : 0.8, dy: 0.5)
            map.coordinate(withNormalizedOffset: from)
                .press(forDuration: 0.02,
                       thenDragTo: map.coordinate(withNormalizedOffset: to),
                       withVelocity: .fast, thenHoldForDuration: 0)
        }
        checkpoint("B2-baseline-after-fast-drag")
        guard let afterFast = stats() else { return }
        report("fast-drag", from: afterSlow, to: afterFast)

        // ── The AE-034 structural guarantees, as counted facts ───────────
        //
        // Bounds are 2–3x the deltas run 87 measured (the first counted
        // run), so an intentional nudge never trips them but the failure
        // they exist for — a return to per-event rebuilding — cannot pass.
        if let before = cacheBefore, let after = cacheCounters() {
            let rebuilds = after.rebuilds - before.rebuilds
            let replays = after.replays - before.replays
            let placements = after.placements - before.placements
            let frames = afterFast.frames - beforeDrag.frames
            // D1: ten drag strokes must not rebuild per event. Run 87
            // measured 24 rebuilds across both drag sequences, every one a
            // counted deliberate cause (pan headroom, the stats() nudges);
            // the old architecture rebuilt per gesture event — hundreds.
            XCTAssertLessThanOrEqual(rebuilds, 60, """
                \(rebuilds) cache rebuilds across the two drag sequences. \
                The drag path is rebuilding instead of replaying — the \
                AE-034 P0 regressed. Reasons ride the MAP-CACHE log lines.
                """)
            // The fast path must carry the frames: geography and routes
            // replay on every non-rebuild frame, so replays cannot fall
            // below the frame count (run 87: 312 replays for 168 frames).
            XCTAssertGreaterThanOrEqual(replays, frames, """
                \(replays) replays for \(frames) frames — drag frames are \
                not being served by transform replay.
                """)
            // L1-L3: placement runs track settle events (run 87: 14 for
            // ten strokes plus four stats() nudges), never frames.
            XCTAssertLessThanOrEqual(placements, 40, """
                \(placements) label placement runs across the drag \
                sequences — placement is deciding per frame again, not per \
                settle.
                """)
        } else {
            XCTFail("The probe published no cache counters; the structural targets went unchecked.")
        }

        // ── MAP TEST F: zoom cycling between levels ──────────────────────
        for _ in 0..<3 {
            for _ in 0..<3 { app.buttons["Zoom in"].tap() }
            for _ in 0..<3 { app.buttons["Zoom out"].tap() }
        }
        Thread.sleep(forTimeInterval: 1)
        checkpoint("B3-baseline-after-zoom-cycles")
        guard let afterZoom = stats() else { return }
        report("zoom-cycles", from: afterFast, to: afterZoom)

        // The one thing a baseline must assert: the measurement is real.
        XCTAssertGreaterThan(afterFast.frames, beforeDrag.frames,
                             "No frames were drawn during the drag sequence")
    }


    // MARK: Performance (§23)

    /// Cold launch, measured — the first UI-side performance number this
    /// project has ever had.
    ///
    /// `ae-map-bench` measures model computation on Linux; nothing measured
    /// the app. This is deliberately the cheapest honest metric: XCTest
    /// launches the app five times and reports the median in the job log.
    /// It is a baseline, not a budget — no assertion, because a number that
    /// fails a build before anyone has agreed what is acceptable just gets
    /// deleted. Map rendering, zoom latency and scroll hitching remain
    /// unmeasured; those need Instruments and a person (docs/PERFORMANCE.md).
    func testColdLaunchBaseline() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
