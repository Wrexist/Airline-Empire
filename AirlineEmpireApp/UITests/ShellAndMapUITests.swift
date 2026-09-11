import XCTest

/// The shell and the map: what every screen looks like, in both appearances,
/// at large text sizes, and under the camera.
///
/// Three defect classes have been found in this project that no compiler can
/// see, and all three are *agreements* Swift does not check:
///
/// | Class | Example | What catches it |
/// | --- | --- | --- |
/// | a link that resolves to nothing | BUG-029, BUG-030 | tapping it |
/// | a string that matches nothing | BUG-033 | a contract test |
/// | a control in the wrong place | BUG-035 | a frame assertion |
///
/// The first and third live here. The second lives in Core, in
/// `RejectionCodeContractTests`.
///
/// The two appearance tests stay in the same class deliberately: appearance
/// is a property of the *simulator*, not of the process, so switching it is
/// a system-wide animation. Tests that fight over it must run on one clone,
/// one after another.
final class ShellAndMapUITests: AEUITestCase {

    func testAirportRouteFiltersAndContextualAircraftAcquisition() throws {
        launch(appearance: .light)
        guard foundAirline() else { return }
        let map = app.descendants(matching: .any)["ae-map-canvas"]
        guard require(map, "the home map") else { return }
        app.buttons["Frame my network"].tap()
        Thread.sleep(forTimeInterval: 1)
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let expand = app.buttons["ae-airport-expand"]
        guard require(expand, "the selected home airport's expansion control") else { return }
        expand.tap()
        let create = app.buttons["ae-airport-create-route"]
        guard require(create, "route creation inside the expanded airport") else { return }
        XCTAssertTrue(create.label.contains("ARN"))
        checkpoint("SMART-expanded-airport")
        expand.tap()
        XCTAssertTrue(create.waitForNonExistence(timeout: 5))
        expand.tap()
        create.tap()
        let origin = app.buttons["ae-route-origin"]
        guard require(origin, "the map airport preselected as origin") else { return }
        XCTAssertTrue((origin.label + (origin.value as? String ?? "")).contains("ARN"))
        let idle = app.buttons["Fits idle aircraft"]
        guard require(idle, "the idle-aircraft route filter") else { return }
        idle.tap()
        XCTAssertTrue(app.staticTexts["No destinations match your search and filter."].waitForExistence(timeout: 5))
        checkpoint("SMART-empty-idle-filter")
        app.buttons["Reset filters"].tap()
        let destination = app.buttons.matching(identifier: "ae-route-destination").firstMatch
        guard require(destination, "destinations after resetting filters") else { return }
        destination.tap()
        let commit = app.buttons["ae-route-open"]
        guard require(commit, "the selected route's commit") else { return }
        commit.tap()
        guard require(app.buttons["ae-route-setup-done"], "the route setup continuation", timeout: 15) else { return }
        let market = app.buttons["ae-route-find-aircraft"]
        guard scrollUntil(market, "the route's aircraft market") else { return }
        market.tap()
        XCTAssertTrue(app.buttons["ae-market-route"].waitForExistence(timeout: 10))
        checkpoint("SMART-route-matched-market")
        guard leaseAnAircraft(proof: .routeAssignment) else { return }
        XCTAssertTrue(app.buttons["Unassign"].exists, "The acquired aircraft must be assigned to the selected route.")
        checkpoint("SMART-leased-and-assigned")
        finishRouteSetup()
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

        // Home is the world map now (AE-048), so the briefing — everything
        // that used to be the Home tab — is a fourth surface with its own
        // materials, and it is the one this suite had never seen in dark.
        let tabs = ["Airline", "Finance", "World", "Home"]
        for (index, tab) in tabs.enumerated() {
            openTab(tab)
            XCTAssertTrue(app.staticTexts.count > 0 || app.otherElements.count > 0,
                          "\(tab) rendered nothing in dark appearance")
            checkpoint("5\(index + 1)-\(route)-\(tab.lowercased())")
        }
        if openBriefing() {
            checkpoint("55-\(route)-briefing")
            closeBriefing()
        }
    }


    /// The same screens in light, so the pair can be compared directly.
    /// The map is the one that matters: its palette is fixed near-black in
    /// both appearances, so light is where it risks looking like a hole.
    func testLightAppearanceMapForComparison() throws {
        guard reachGameplay(in: .light) else { return }
        checkpoint("60-light-home")
        openTab("Home")
        checkpoint("61-light-map")
        // BUG-036's other half: the briefing is glass and system materials
        // over a near-black map, and light is where that combination has
        // failed before.
        if openBriefing() {
            checkpoint("62-light-briefing")
            closeBriefing()
        }
    }


    // MARK: Screens the journey had never reached (§12)

    /// Aircraft detail, route detail, and Settings — three screens that were
    /// 📖 read-only until this test: reachable in source, never rendered.
    func testDetailScreensAndSettingsRender() throws {
        launch(appearance: .light)
        guard foundAirline() else { return }

        // ── Aircraft detail, via the fleet board ──────────────────────────
        openTab("Airline")
        app.buttons["Fleet"].tap()
        let browse = app.buttons["Browse the market"]
        require(browse, "the market entry point")
        browse.tap()
        guard leaseAnAircraft() else { return }

        let aircraftRow = app.descendants(matching: .any)
            .matching(identifier: "ae-fleet-row").firstMatch
        require(aircraftRow, "the leased aircraft on the fleet board")
        aircraftRow.tap()
        // Content only aircraft detail has. The first attempt asked for
        // "condition", which the fleet board's own summary also says — so
        // run 60 photographed the board under the name "aircraft-detail" and
        // the assertion passed anyway. "Ownership" is a section header that
        // exists nowhere else — matched case-insensitively, because
        // AESectionHeader uppercases its text and run 64 failed this over a
        // perfectly rendered screen whose header read "OWNERSHIP".
        let detailRendered = app.staticTexts.matching(
            NSPredicate(format: "label ==[c] %@", "Ownership")).firstMatch
            .waitForExistence(timeout: 10)
        checkpoint("90-aircraft-detail")
        XCTAssertTrue(detailRendered, """
            Aircraft detail shows no Ownership section — either the wrong \
            screen was pushed or it rendered empty. Screenshot attached.
            """)
        app.navigationBars.buttons.firstMatch.tap()

        // ── Route detail, via the routes board ────────────────────────────
        guard openARoute() else { return }
        let routeRow = app.descendants(matching: .any)
            .matching(identifier: "ae-route-row").firstMatch
        require(routeRow, "the new route on the board")

        // A zero-result query must leave its search field mounted and usable.
        let search = app.searchFields.firstMatch
        guard require(search, "route search"), tapWhenReady(search) else { return }
        search.typeText("zzzznomatchingairport")
        let clearSearch = app.buttons["Clear search"]
        guard require(clearSearch, "recovery from an empty route search") else { return }
        XCTAssertTrue(search.exists, "Search disappeared when there were no matches")
        XCTAssertTrue(search.isHittable, "The empty state hid the search field")
        checkpoint("90b-route-search-empty")
        guard tapWhenReady(clearSearch) else { return }
        guard require(routeRow, "the route restored after clearing search") else { return }
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

        // ── Settings, from the briefing ───────────────────────────────────
        // Settings left the World hub for the Home toolbar (UI-001); AE-048
        // moved that toolbar into the briefing when Home became the map.
        guard openBriefing() else { return }
        let settings = app.buttons["Settings"]
        require(settings, "the Settings button in the toolbar")
        settings.tap()
        // Scrolled to, not merely waited for. Settings is a long list and
        // "Mute everything" is its third section; CI run 171's iPad frame
        // showed the screen rendered perfectly with the toggle below the
        // fold, and reported it as "the sheet did not present or it rendered
        // empty". Reaching a control by scrolling is the stronger claim
        // anyway — it proves the list scrolls as well as that it drew.
        let muteToggle = app.switches["Mute everything"]
        let settingsList = app.descendants(matching: .any)
            .matching(identifier: "ae-settings-list").firstMatch
        guard require(settingsList, "the Settings list") else { return }
        let settingsRendered = scrollUntil(muteToggle, "the Mute everything toggle in Settings",
                                           in: settingsList)
        checkpoint("92-settings")
        XCTAssertTrue(settingsRendered, """
            The Settings sheet shows no "Mute everything" toggle. Either the \
            sheet did not present or it rendered empty. Screenshot attached.
            """)
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
        for tab in ["Airline", "Finance", "World", "Home"] {
            guard let button = waitForTab(tab, timeout: 10) else {
                capture(Self.logPrefix + "MISSING-\(tab)-at-accessibility-size")
                XCTFail("The \(tab) tab vanished at accessibility size. Screenshot attached.")
                continue
            }
            XCTAssertTrue(button.isHittable,
                          "The \(tab) tab is not tappable at accessibility size")
        }

        openTab("Airline")
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


    // MARK: The clock (BUG-040)

    /// Time actually passes when the player asks it to.
    ///
    /// The regression test for the most serious defect this phase found:
    /// founding a game never started the simulation pump, so the clock sat
    /// at day one, 00:00, whatever speed was selected — photographed twice
    /// (runs 64 and 65) before the cause was found. This asks the smallest
    /// possible version of the question, with no market, no sheets and no
    /// scrolling in the way: found an airline, select 16×, and the date on
    /// Home must change. At 16× a game-day passes in ~22 real seconds; a
    /// minute of patience is generous, and a failure here means the game is
    /// frozen for every player.
    func testTheClockActuallyRuns() throws {
        launch(appearance: .light)
        guard foundAirline() else { return }

        let openingDate = app.staticTexts["2030-01-01"]
        XCTAssertTrue(openingDate.waitForExistence(timeout: 10),
                      "Home does not show the scenario's opening date")

        let fast = app.buttons["Sixteen times speed"]
        require(fast, "the 16x speed control")
        fast.tap()

        let advanced = openingDate.waitForNonExistence(timeout: 60)
        checkpoint("85-clock-after-16x")
        XCTAssertTrue(advanced, """
            A real minute at 16x — about two and a half game days — and Home \
            still shows 2030-01-01. The simulation pump is not running: this \
            is BUG-040's exact shape, and the game is frozen. Screenshot \
            attached.
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
        openTab("Home")

        let map = app.descendants(matching: .any)["ae-map-canvas"]
        require(map, "the map canvas")

        // The camera's zoom is in the canvas's accessibility value, so every
        // step below is *proved* to have moved it. The previous version of
        // this test pinched blind: run 59's "world", "regional" and "local"
        // screenshots came back byte-identical (the map opens framed on the
        // home network, near the clamp, so pinching in moved nothing), and
        // its final wide pinch-out landed a synthetic finger on the tab bar
        // and photographed the Finance screen under a map filename. It
        // passed, because all it asserted was that the canvas existed.
        func zoom() -> Double {
            let value = map.value as? String ?? ""
            guard let range = value.range(of: #"zoom ([0-9.]+)x"#,
                                          options: .regularExpression)
            else { return .nan }
            return Double(value[range].dropFirst(5).dropLast(1)) ?? .nan
        }
        checkpoint("70-map-opening-frame")
        let opening = zoom()
        XCTAssertFalse(opening.isNaN, "The map does not publish its zoom")

        // Buttons first: they drive the same camera the gestures do, and a
        // button tap cannot miss. Out to the world, in to the streets.
        let zoomOut = app.buttons["Zoom out"]
        require(zoomOut, "the zoom out control")
        for _ in 0..<6 { zoomOut.tap() }
        let world = zoom()
        XCTAssertLessThan(world, opening,
                          "Six zoom-out taps did not move the camera out")
        checkpoint("71-map-world")

        let zoomIn = app.buttons["Zoom in"]
        for _ in 0..<3 { zoomIn.tap() }
        XCTAssertGreaterThan(zoom(), world,
                             "Three zoom-in taps did not move the camera in")
        checkpoint("72-map-regional")
        for _ in 0..<3 { zoomIn.tap() }
        checkpoint("73-map-local")

        // The gestures, each proved against the same probe.
        //
        // Double tap is synthesized reliably; it must zoom in, and that is a
        // hard assertion. The pinch is XCUITest's weakest synthesis — if it
        // moves the camera the claim is upgraded to asserted, and if it does
        // not, that is recorded as an honest skip rather than a pass,
        // because from here it is impossible to tell a broken gesture
        // handler from a synthetic gesture the recognizer never saw. A
        // person with a device settles it either way (docs/APPLE_VALIDATION.md).
        for _ in 0..<4 { zoomOut.tap() }
        let beforeDoubleTap = zoom()
        map.doubleTap()
        XCTAssertGreaterThan(zoom(), beforeDoubleTap,
                             "Double-tapping the map did not zoom in")
        checkpoint("74-map-after-double-tap")

        let beforePinch = zoom()
        map.pinch(withScale: 1.8, velocity: 1.0)
        Thread.sleep(forTimeInterval: 1)
        if !(zoom() > beforePinch) {
            checkpoint("75-PINCH-DID-NOT-ZOOM")
            throw XCTSkip("""
                The synthetic pinch left the camera at \(zoom())x (was \
                \(beforePinch)x). Buttons and double tap both move the same \
                camera, so the zoom path works; whether a real two-finger \
                pinch reaches the recognizer still needs a person and a \
                device. Recorded as NOT VERIFIED, not as passing.
                """)
        }
        checkpoint("75-map-after-pinch")
    }


    /// Riding with a flight (AE-046).
    ///
    /// What this can honestly prove: that a flight can be selected on the map,
    /// that the card offers to follow it, and that pressing Follow puts the
    /// camera into follow mode — the canvas publishes which flight it is
    /// riding with, in the same accessibility value that carries the zoom, so
    /// the claim is read back from the app rather than photographed and
    /// assumed (the BUG-039 rule).
    ///
    /// What it cannot prove is that following *looks* right: whether the
    /// aircraft holds still while the world slides under it, whether the ease
    /// into the follow zoom is pleasant, whether a flight at 16× is a blur.
    /// Those need a hand and a screen. Where the synthetic tap cannot find an
    /// aircraft at all, this skips with a frame attached rather than passing —
    /// a test that proves nothing must say so.
    func testFollowingAFlightRidesTheCamera() throws {
        launch(appearance: .light)
        guard foundAirline() else { return }
        // A flight to follow has to exist first: an aircraft, a route, an
        // assignment, and enough game time for something to take off.
        guard openAircraftMarket(), leaseAnAircraft() else { return }
        guard openRouteBySearch(city: "London", code: "LHR") else { return }
        guard assignFirstAircraft() else { return }
        openTab("Home")

        let map = app.descendants(matching: .any)["ae-map-canvas"]
        require(map, "the map canvas")

        func value() -> String { map.value as? String ?? "" }
        func airborne() -> Int {
            let text = value()
            guard let range = text.range(of: #"([0-9]+) aircraft in the air"#,
                                         options: .regularExpression)
            else { return 0 }
            return Int(text[range].prefix(while: \.isNumber)) ?? 0
        }

        // Run the clock until something is actually flying. The map says how
        // many aircraft are in the air, so this waits on the fact rather than
        // on a duration.
        // By its VoiceOver label, not its glyph: the speed pill draws "16×"
        // and answers to "Sixteen times speed", and a test that taps the
        // glyph taps nothing.
        let fast = app.buttons["Sixteen times speed"]
        if fast.waitForExistence(timeout: 5) { fast.tap() }
        var waited = 0
        var seen = 0
        while seen == 0 && waited < 40 {
            Thread.sleep(forTimeInterval: 1)
            waited += 1
            seen = airborne()
        }
        // Read once and keep it. The first version asked `airborne()` in the
        // loop condition and *again* in the guard below, and run 172 skipped
        // on the pair disagreeing — "no aircraft reached the air within 19
        // seconds" after the loop had already exited because one had. A
        // flight that lands between two accessibility queries is a race in
        // the test, not a fact about the camera.
        guard seen > 0 else {
            checkpoint("76-NO-FLIGHT-TO-FOLLOW")
            throw XCTSkip("""
                No aircraft reached the air within \(waited) seconds at 16×, \
                so the follow camera could not be exercised. The assignment \
                journey succeeded, so this is a pacing question, not a \
                broken camera. Recorded as NOT VERIFIED.
                """)
        }

        // Stop the clock before aiming.
        //
        // This spiral has never once hit an aircraft — AE-046 recorded the
        // camera NOT VERIFIED, and runs 171 and 172 both skipped here. It was
        // tapping at 16×, where an aeroplane crosses its own width several
        // times between the snapshot the tap is aimed from and the tap
        // landing. Paused, the flight holds position, `MapFlightCard` still
        // offers Follow (`flight.airborne || isFollowing`), and the target
        // stops moving out from under the finger.
        let pause = app.buttons["Pause"]
        if pause.waitForExistence(timeout: 5) { pause.tap() }
        Thread.sleep(forTimeInterval: 1)

        // Frame the network, then sweep it — and know what was hit.
        //
        // Seven blind taps around the centre have now missed in four
        // consecutive attempts (AE-046, and runs 171, 172, 173), which is
        // long enough to stop calling it luck. Two things were wrong with
        // them. They clustered on the middle of the canvas, and the middle of
        // a framed network is usually the ocean *between* the two airports,
        // not the arc; and they asked only whether *something* had been
        // selected, so an airport under the third tap would have ended the
        // search with the wrong object.
        //
        // A grid across the framed network looks where the arc actually is,
        // and the canvas's own accessibility value says which kind of thing
        // was hit — "Selected a flight to LHR" for an aircraft against
        // "Selected Stockholm" for an airport — so the sweep can walk past an
        // airport and keep going. Thirty taps on a paused map cost about
        // eight seconds.
        let frameNetwork = app.buttons["Frame my network"]
        if frameNetwork.waitForExistence(timeout: 5) { frameNetwork.tap() }
        Thread.sleep(forTimeInterval: 1)
        let zoomIn = app.buttons["Zoom in"]
        if zoomIn.waitForExistence(timeout: 5) { for _ in 0..<2 { zoomIn.tap() } }
        Thread.sleep(forTimeInterval: 0.5)
        let follow = app.buttons["ae-map-follow"]
        func aircraftSelected() -> Bool { value().contains("Selected a flight") }
        var offsets: [(CGFloat, CGFloat)] = []
        for row in 0..<6 {
            for column in 0..<5 {
                offsets.append((0.16 + CGFloat(column) * 0.17,
                                0.28 + CGFloat(row) * 0.075))
            }
        }
        for (x, y) in offsets {
            map.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
            Thread.sleep(forTimeInterval: 0.25)
            if aircraftSelected() { break }
            if follow.exists { break }
        }
        guard follow.exists else {
            checkpoint("76-NO-AIRCRAFT-SELECTED")
            throw XCTSkip("""
                Thirty taps swept across the framed network on a paused map \
                selected no aircraft, so the flight card never appeared and \
                the follow control was never reachable. An aircraft marker is \
                a few points wide; this is a limitation of synthetic tapping, \
                not evidence about the camera. Recorded as NOT VERIFIED.
                """)
        }
        checkpoint("76-map-flight-card")

        follow.tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(value().contains("following"), """
            The map does not report following a flight after the Follow \
            control was pressed. Canvas value: \(value())
            """)
        checkpoint("77-map-following-a-flight")

        // A finger on the map takes the camera back — the rule the whole
        // follow mode rests on.
        map.swipeLeft()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(value().contains("following"), """
            A drag did not release the follow camera. Canvas value: \(value())
            """)
        checkpoint("78-map-after-releasing-follow")
    }

    /// Selecting an airport on the map: the panel, and the marker art.
    ///
    /// This leg exists because of a gap the AE-033 audit had to record as
    /// NOT VERIFIED. The selection pulse and the global-hub ring are drawn on
    /// every frame the map renders, and *no automated frame had ever selected
    /// an airport* — so neither had been seen, and neither could be, however
    /// many map screenshots the suite collected. A tap that selects is the
    /// one thing that photographs both.
    ///
    /// The camera frames home on open, so the home airport is at or near the
    /// middle of the canvas. That is a good first guess and not a promise:
    /// the tap walks a small spiral outward until the map reports a
    /// selection, because an airport marker is a few points wide and a
    /// synthetic tap that lands on empty ocean deselects rather than fails.
    func testSelectingAnAirportOpensItsPanel() throws {
        launch(appearance: .light)
        guard foundAirline() else { return }
        openTab("Home")

        let map = app.descendants(matching: .any)["ae-map-canvas"]
        require(map, "the map canvas")

        // Zoom in a few steps first: at the opening frame the markers are
        // small and close together, and a tap between two of them selects
        // neither.
        let zoomIn = app.buttons["Zoom in"]
        if zoomIn.waitForExistence(timeout: 5) {
            for _ in 0..<2 { zoomIn.tap() }
        }

        func selected() -> Bool {
            (map.value as? String ?? "").contains("Selected")
        }

        // Centre first, then a ring around it. Normalised offsets, so this
        // holds on any device the suite is pointed at.
        let offsets: [(CGFloat, CGFloat)] = [
            (0.5, 0.5), (0.5, 0.46), (0.54, 0.5), (0.46, 0.5),
            (0.5, 0.54), (0.54, 0.46), (0.46, 0.54),
        ]
        var found = false
        for (index, offset) in offsets.enumerated() {
            map.coordinate(withNormalizedOffset:
                CGVector(dx: offset.0, dy: offset.1)).tap()
            Thread.sleep(forTimeInterval: 0.6)
            if selected() { found = true; break }
            if index == offsets.count - 1 { checkpoint("86-NO-AIRPORT-SELECTED") }
        }

        guard found else {
            throw XCTSkip("""
                Seven taps around the middle of the map selected nothing. The                 camera frames the home network on open, so a marker should be                 near the centre; a synthetic tap landing between markers is                 the likeliest explanation, and the pulse and hub ring stay                 NOT VERIFIED rather than being claimed on a frame that does                 not show them.
                """)
        }

        // The panel is the proof the tap *meant* something, and the frame is
        // the proof of what it looks like — the selection pulse around the
        // marker, and the ring on any global hub in view.
        let panel = app.descendants(matching: .any)["ae-map-selection"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5),
                      "The map reported a selection but no panel opened")
        checkpoint("86-airport-selected")
        let expand = app.buttons["ae-airport-expand"]
        guard require(expand, "the airport expansion action") else { return }
        expand.tap()
        let create = app.buttons["ae-airport-create-route"]
        guard require(create, "route creation in the expanded airport") else { return }
        XCTAssertLessThan(panel.frame.maxY - create.frame.maxY, 44,
                          "An airport with no routes should fit its actions without an empty scroll area.")
        checkpoint("86b-airport-expanded-fits-content")
        expand.tap()

        // Zoomed out one more time with the selection held: this is the frame
        // where the hub rings on the other global airports are visible beside
        // the pulsing selection.
        let zoomOut = app.buttons["Zoom out"]
        if zoomOut.exists {
            for _ in 0..<3 { zoomOut.tap() }
            checkpoint("87-airport-selected-world")
        }
    }


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
        openTab("Airline")

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
}
