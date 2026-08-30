import XCTest

/// The first minute of the game, driven against a booted simulator.
///
/// Three defect classes have now been found in this project that no compiler
/// can see, and all three are *agreements* Swift does not check:
///
/// | Class | Example | What catches it |
/// | --- | --- | --- |
/// | a link that resolves to nothing | BUG-029, BUG-030 | tapping it |
/// | a string that matches nothing | BUG-033 | a contract test |
/// | a control in the wrong place | BUG-035 | a frame assertion |
///
/// This file covers the first and third. The second lives in Core, in
/// `RejectionCodeContractTests`.
final class PlayerJourneyUITests: AEUITestCase {

    // MARK: Layout regression (TD-019)

    /// The assertion that would have failed before BUG-035 was fixed.
    ///
    /// Measured from the screenshots either side of the fix: the section
    /// picker's top edge sat at roughly **39%** of the window before, and
    /// **15%** after. The bar is set at 30% — comfortably clear of the fixed
    /// layout, comfortably under the broken one, and loose enough that an
    /// intentional change to spacing does not fail it.
    func testSectionPickerSitsUnderTheNavigationBarNotInDeadSpace() throws {
        launch(appearance: .light)
        guard foundAirline() else { return }
        openTab("Network")

        let routesSegment = app.buttons["Routes"]
        require(routesSegment, "the Routes segment")
        assertNear(routesSegment, top: 0.30, "the section picker (Routes)")
        checkpoint("40-layout-routes-empty")

        let fleetSegment = app.buttons["Fleet"]
        require(fleetSegment, "the Fleet segment")
        fleetSegment.tap()
        assertNear(fleetSegment, top: 0.30, "the section picker (Fleet)")

        // The other half of BUG-035: the empty-state card had drifted a long
        // way below the picker that introduces it.
        let emptyTitle = app.staticTexts["No aircraft"]
        require(emptyTitle, "the empty fleet state")
        assertBelow(emptyTitle, fleetSegment, "the empty state")
        assertClose(fleetSegment, emptyTitle, within: 0.20,
                    "the picker and the empty state it introduces")
        assertNotUnderTabBar(emptyTitle, "the empty fleet state")
        checkpoint("41-layout-fleet-empty")
    }

    // MARK: Appearance
    //
    // `Theme.swift` states the intended behaviour outright: presentation
    // surfaces sit on the dusk palette (the new-game screen forces
    // `.preferredColorScheme(.dark)`), while "gameplay screens keep the system
    // background — a dashboard is for reading numbers, not for atmosphere."
    // `DESIGN_SYSTEM.md` §10 agrees, listing contrast in *both appearances* as
    // unverified.
    //
    // So the app is adaptive by design, and the light screens seen in AE-031
    // were correct behaviour, not a theme failing to apply. What has never
    // been looked at is the dark half — which is the half the map's fixed
    // near-black palette was designed against.

    func testDarkAppearanceRendersEveryTab() throws {
        // Reaching gameplay is the check: appearance only varies once the
        // game is running, because the new-game screen is pinned to dark.
        guard reachGameplay(in: .dark) else { return }
        // Named by how the appearance was actually obtained, so a screenshot
        // can never imply more than it proved.
        let route = appearanceRoute.rawValue
        checkpoint("50-\(route)-home")

        let tabs = ["Map", "Network", "Finance", "World"]
        for (index, tab) in tabs.enumerated() {
            openTab(tab)
            XCTAssertTrue(app.staticTexts.count > 0 || app.otherElements.count > 0,
                          "\(tab) rendered nothing in dark appearance")
            checkpoint("5\(index + 1)-\(route)-\(tab.lowercased())")
        }
    }

    /// The same screens in light, so the pair can be compared directly.
    /// The map is the one that matters: its palette is fixed near-black in
    /// both appearances, so light is where it risks looking like a hole.
    func testLightAppearanceMapForComparison() throws {
        guard reachGameplay(in: .light) else { return }
        checkpoint("60-light-home")
        openTab("Map")
        checkpoint("61-light-map")
    }

    // MARK: The real journey (§6)

    /// Lease an aircraft, then open a route — checking the game agreed each
    /// time.
    ///
    /// The checks that matter are the **agreements**: a lease must appear in
    /// the fleet, a route must appear on the board. Each is a place where the
    /// interface could report success while the simulation did nothing, which
    /// is the failure this target exists to catch.
    func testAcquireAircraftThenOpenARoute() throws {
        launch(appearance: .light)
        guard foundAirline() else { return }
        checkpoint("01-home")

        // ── Acquire ────────────────────────────────────────────────────────
        openTab("Network")
        app.buttons["Fleet"].tap()
        let browse = app.buttons["Browse the market"]
        require(browse, "the market entry point on an empty fleet")
        browse.tap()
        checkpoint("02-market")

        guard leaseAnAircraft() else { return }
        checkpoint("03-after-lease")

        // AGREEMENT: leasing must put an aircraft in the fleet. The sheet
        // dismisses on success, so a non-empty Fleet is the observable result.
        let emptyFleet = app.staticTexts["No aircraft"]
        XCTAssertFalse(emptyFleet.waitForExistence(timeout: 8),
                       """
                       The fleet still reports "No aircraft" after a lease was \
                       confirmed. Either the command was rejected without \
                       saying so, or the screen did not refresh — both are the \
                       silent failures this target exists to find.
                       """)
        checkpoint("04-fleet-with-aircraft")

        // ── Open a route ───────────────────────────────────────────────────
        guard openARoute() else { return }
        checkpoint("07-routes-with-route")
    }

    /// An aircraft actually in the air, on an actual route, photographed.
    ///
    /// The longest journey in this file, and the only one that reaches the
    /// state the game is *for*. Every earlier test stops at a static board:
    /// a fleet with one aircraft in it, a route with no aircraft on it, a
    /// paused clock. None of them has ever seen the simulation run.
    ///
    /// Five steps, each of which can fail on its own terms:
    /// lease → open a route → assign the aircraft → start the clock → wait.
    ///
    /// The wait is the interesting part. `MapScreen` publishes "N aircraft in
    /// the air" as the canvas's accessibility value, straight from the model,
    /// so the test can poll for the simulation's own count rather than
    /// guessing at a duration and hoping. That also makes this the one place
    /// that checks the agreement the whole map rests on: the simulation says
    /// an aircraft is flying, and the map says the same.
    func testAnAircraftFliesItsRouteOnTheMap() throws {
        launch(appearance: .light)
        guard foundAirline() else { return }

        // ── Lease ──────────────────────────────────────────────────────────
        openTab("Network")
        app.buttons["Fleet"].tap()
        let browse = app.buttons["Browse the market"]
        require(browse, "the market entry point")
        browse.tap()

        guard leaseAnAircraft() else { return }

        // ── Open a route ───────────────────────────────────────────────────
        guard openARoute() else { return }

        // ── Assign ─────────────────────────────────────────────────────────
        // Into the route's own screen, where the assignment lives.
        let routeRow = app.cells.firstMatch
        require(routeRow, "the new route on the board")
        routeRow.tap()

        let assign = app.buttons["Assign an aircraft"]
        guard assign.waitForExistence(timeout: 10) else {
            // Not a silent skip. If no aircraft can fly this route the
            // assignment card says why, and that reason is the finding.
            capture(Self.logPrefix + "NO-ASSIGNABLE-AIRCRAFT")
            XCTFail("""
                No aircraft could be assigned to the route just opened. The \
                leased aircraft cannot fly it — most likely range — which \
                means the guided path a new player is offered (lease the \
                first aircraft, open the first suggested route) does not \
                connect. Screenshot attached.
                """)
            return
        }
        assign.tap()
        // The menu lists one row per eligible aircraft; the first is the one
        // just leased, since it is the only one owned.
        let candidate = app.buttons.element(boundBy: 0)
        if candidate.waitForExistence(timeout: 5) { candidate.tap() }
        checkpoint("80-route-with-aircraft")

        // ── Run the clock ──────────────────────────────────────────────────
        openTab("Map")
        let frameNetwork = app.buttons["Frame my network"]
        if frameNetwork.waitForExistence(timeout: 5) { frameNetwork.tap() }

        let fast = app.buttons["Sixteen times speed"]
        require(fast, "the 16x speed control")
        fast.tap()

        // At 16x the world runs 64 game-minutes a real second, so a game day
        // costs about 22 seconds. Two minutes is roughly five game days —
        // long enough that a schedule with no departure in it is a finding
        // rather than impatience.
        let map = app.descendants(matching: .any)["ae-map-canvas"]
        var airborne = false
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if let value = map.value as? String,
               value.contains("aircraft in the air"),
               !value.contains("0 aircraft in the air") {
                airborne = true
                break
            }
            Thread.sleep(forTimeInterval: 2)
        }

        // The photograph, taken whether or not anything took off: a map with
        // nothing flying on it after five game days is the more interesting
        // image of the two.
        checkpoint("81-flight-in-progress")
        app.buttons["Zoom in"].tap()
        app.buttons["Zoom in"].tap()
        checkpoint("82-flight-close-up")

        XCTAssertTrue(airborne, """
            No aircraft reached the air in roughly five game days, on a route \
            with an aircraft assigned to it. Either nothing was scheduled or \
            the map is not reporting what the simulation is doing — and the \
            map's own accessibility value is what this polled, so the two \
            disagreeing is itself the defect.
            """)
    }

    /// The map at two zoom levels, and a pinch that does not fall over.
    ///
    /// Two things this can honestly check, and one it cannot. It can prove the
    /// pinch gesture is accepted and the map survives it — a `Canvas` that
    /// throws away its projection under a gesture would fail here. And it
    /// captures the world and regional levels, which is the only way anyone
    /// finds out whether the country labels crowd the airport codes.
    ///
    /// What it cannot check is whether any of it *looks* right. There is no
    /// assertion in XCUITest for "the coastline reads as geography" or "the
    /// flag rendered in colour". Those need a person and a screenshot, which
    /// is why both are captured rather than merely visited.
    func testZoomingTheMapRevealsCountryLabels() throws {
        launch(appearance: .light)
        guard foundAirline() else { return }
        openTab("Map")

        let map = app.descendants(matching: .any)["ae-map-canvas"]
        require(map, "the map canvas")
        checkpoint("70-map-world-zoom")

        // Two pinches rather than one large one: the camera clamps at 16x, and
        // a single huge scale would jump straight past the regional level that
        // is the interesting one for labels.
        map.pinch(withScale: 2.4, velocity: 1.2)
        checkpoint("71-map-regional-zoom")
        map.pinch(withScale: 2.4, velocity: 1.2)
        checkpoint("72-map-local-zoom")

        // The map must still be there and still be interactive; a gesture that
        // wedged the canvas would show up as the element going away.
        XCTAssertTrue(map.exists,
                      "The map canvas did not survive being pinched")

        map.pinch(withScale: 0.3, velocity: -1.5)
        checkpoint("73-map-zoomed-back-out")
    }

    /// No screen shows the old generic currency sign.
    ///
    /// `¤` (U+00A4) was chosen deliberately — the world is fictional, so
    /// naming a real currency was judged a lie. The intent was sound and the
    /// execution was not: most system faces draw it as a hollow box with
    /// legs, so every cash figure in the game read as a font-fallback error.
    ///
    /// Nothing could have caught that except looking. It compiled, it was
    /// centralised, it was documented, and it survived four phases of UI work
    /// — until AE-032 put a screenshot in front of a person, who spotted it in
    /// seconds. This is the cheap guard that stops it coming back: money is
    /// on almost every screen, so one sweep is enough.
    func testNoScreenShowsTheOldCurrencyGlyph() throws {
        launch(appearance: .light)
        guard foundAirline() else { return }

        for tab in ["Home", "Map", "Network", "Finance", "World"] {
            openTab(tab)
            let offending = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "\u{00A4}"))
            if offending.count > 0 {
                capture(Self.logPrefix + "CURRENCY-\(tab)")
                XCTFail("""
                    \(tab) shows \(offending.count) label(s) containing ¤, the \
                    generic currency sign, which renders as a hollow box and \
                    reads as a broken glyph. Money should use $.
                    """)
                return
            }
        }
    }

    /// Every tab reachable, and each renders something.
    ///
    /// Checkpoints on every tab, because this is also the test the iPad job
    /// runs: the same five screens at regular width are the whole of what
    /// that job exists to photograph.
    func testFoundingAnAirlineReachesEveryTab() throws {
        launch(appearance: .light)
        guard foundAirline() else { return }

        for (index, tab) in ["Home", "Map", "Network", "Finance", "World"].enumerated() {
            openTab(tab)
            XCTAssertTrue(app.staticTexts.count > 0 || app.otherElements.count > 0,
                          "\(tab) rendered no content")
            checkpoint("2\(index)-shell-\(tab.lowercased())")
        }
    }

    // MARK: Screens the journey had never reached (§12)

    /// Aircraft detail, route detail, and Settings — three screens that were
    /// 📖 read-only until this test: reachable in source, never rendered.
    func testDetailScreensAndSettingsRender() throws {
        launch(appearance: .light)
        guard foundAirline() else { return }

        // ── Aircraft detail, via the fleet board ──────────────────────────
        openTab("Network")
        app.buttons["Fleet"].tap()
        let browse = app.buttons["Browse the market"]
        require(browse, "the market entry point")
        browse.tap()
        guard leaseAnAircraft() else { return }

        let aircraftRow = app.cells.firstMatch
        require(aircraftRow, "the leased aircraft on the fleet board")
        aircraftRow.tap()
        // The screen must carry content that only aircraft detail has:
        // condition is its vocabulary, and a blank push would fail this.
        let detailRendered = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "condition"))
            .firstMatch.waitForExistence(timeout: 10)
        checkpoint("90-aircraft-detail")
        XCTAssertTrue(detailRendered, """
            Aircraft detail shows nothing describing the aircraft's \
            condition — either the wrong screen was pushed or it rendered \
            empty. Screenshot attached.
            """)
        app.navigationBars.buttons.firstMatch.tap()

        // ── Route detail, via the routes board ────────────────────────────
        guard openARoute() else { return }
        let routeRow = app.cells.firstMatch
        require(routeRow, "the new route on the board")
        routeRow.tap()
        let routeRendered = app.buttons["Assign an aircraft"]
            .waitForExistence(timeout: 10)
        checkpoint("91-route-detail")
        XCTAssertTrue(routeRendered, """
            Route detail did not offer to assign an aircraft, on a route \
            with an idle, in-range aircraft in the fleet. Either the wrong \
            screen was pushed or the assignment card is missing. Screenshot \
            attached.
            """)

        // ── Settings, from Home ───────────────────────────────────────────
        openTab("Home")
        let settings = app.buttons["Settings"]
        require(settings, "the Settings button in the toolbar")
        settings.tap()
        let muteToggle = app.switches["Mute everything"]
        let settingsRendered = muteToggle.waitForExistence(timeout: 10)
        checkpoint("92-settings")
        XCTAssertTrue(settingsRendered, """
            The Settings sheet shows no "Mute everything" toggle. Either the \
            sheet did not present or it rendered empty. Screenshot attached.
            """)
    }

    // MARK: Audio (§18)

    /// The audio pipeline starts, and every shipped cue decoded.
    ///
    /// This is the strongest audio claim CI can make, and it is deliberately
    /// bounded: `AVAudioSession` activates, the `AVAudioEngine` graph starts,
    /// and all ~52 one-shot buffers loaded. Nothing here proves a sound was
    /// *heard* — the engine could be running into a muted mixer — but every
    /// failure mode short of that (a file that stopped decoding, a format
    /// mismatch, a session that will not activate, an engine that throws on
    /// start) turns from silent to red. The probe only exists under
    /// `-AEUITestProbes`, so shipping accessibility is untouched.
    func testAudioEngineStartsAndEveryCueDecodes() throws {
        launch(appearance: .light, arguments: ["-AEUITestProbes"])
        guard foundAirline() else { return }

        let probe = app.descendants(matching: .any)["ae-audio-status"]
        guard probe.waitForExistence(timeout: 10) else {
            XCTFail("The audio status probe never appeared under -AEUITestProbes.")
            return
        }
        // prepare() runs off the first frame; give it a beat and re-read.
        var status = probe.value as? String ?? ""
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline,
              !(status.contains("running") && status.contains("0 assets missing")) {
            Thread.sleep(forTimeInterval: 1)
            status = probe.value as? String ?? ""
        }
        XCTAssertTrue(status.contains("engine running"), """
            The AVAudioEngine is not running after launch: the probe reports \
            "\(status)". Every sound in the game is currently playing into \
            nothing.
            """)
        XCTAssertTrue(status.contains("0 assets missing"), """
            Some audio assets failed to decode on-device: the probe reports \
            "\(status)". scripts/audio/check-assets.py validates the files \
            exist and share a format, so a failure here is a decode problem \
            the static check cannot see.
            """)
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

    // MARK: Dynamic Type (§19)

    /// The shell at an accessibility text size.
    ///
    /// `AccessibilityL` is the first of the five accessibility sizes — large
    /// enough that any layout which cannot flex has already broken, small
    /// enough that a pass is not trivial. The assertions are the failure
    /// classes §19 names: navigation must survive, and the market's primary
    /// action must still be reachable. Whether it *looks* right is what the
    /// checkpoints are for.
    func testAccessibilityTextSizeKeepsTheShellUsable() throws {
        launch(appearance: .light, arguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityL",
        ])
        guard foundAirline() else { return }
        checkpoint("95-dynamictype-home")

        // Navigation failure is the worst outcome: every tab must survive.
        for tab in ["Map", "Network", "Finance", "World", "Home"] {
            let button = app.tabBars.buttons[tab]
            require(button, "the \(tab) tab at accessibility size")
            XCTAssertTrue(button.isHittable,
                          "The \(tab) tab is not tappable at accessibility size")
        }

        openTab("Network")
        checkpoint("96-dynamictype-routes-empty")

        // The market's primary action must still be reachable by scrolling.
        app.buttons["Fleet"].tap()
        let browse = app.buttons["Browse the market"]
        require(browse, "the market entry point at accessibility size")
        browse.tap()
        let lease = app.buttons.matching(identifier: "ae-market-lease").firstMatch
        scrollUntil(lease, "a Lease action in the market at accessibility size")
        checkpoint("97-dynamictype-market")
    }

    /// Home guides a new player to their first aircraft.
    ///
    /// Load-bearing rather than decorative: the Network tab opens on Routes,
    /// whose empty state tells a player with no aircraft to "put an aircraft
    /// on it". This card is the only thing naming where the market is.
    func testHomeGuidesANewPlayerToTheirFirstAircraft() throws {
        launch(appearance: .light)
        guard foundAirline() else { return }
        XCTAssertTrue(app.staticTexts["Get an aircraft"].waitForExistence(timeout: 15),
                      """
                      Home shows no onboarding step for a new airline. This \
                      card is the only signpost to the market.
                      """)
    }
}
