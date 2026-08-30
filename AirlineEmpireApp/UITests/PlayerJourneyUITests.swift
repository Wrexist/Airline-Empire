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
        checkpoint("50-dark-home")

        let tabs = ["Map", "Network", "Finance", "World"]
        for (index, tab) in tabs.enumerated() {
            openTab(tab)
            XCTAssertTrue(app.staticTexts.count > 0 || app.otherElements.count > 0,
                          "\(tab) rendered nothing in dark appearance")
            checkpoint("5\(index + 1)-dark-\(tab.lowercased())")
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

        // Hide what the era cannot buy, so the first lease action on screen
        // belongs to an aircraft this airline is actually allowed to take.
        // Without this the market opens on two locked flagships and the first
        // buyable row is well below the fold.
        let eraFilter = app.switches["Hide what this era cannot buy"]
        if eraFilter.waitForExistence(timeout: 5), eraFilter.value as? String == "0" {
            eraFilter.tap()
        }

        // Lease rather than buy: a lease delivers immediately, where a new
        // purchase stays `ordered` until its lead days pass. Leasing is also
        // what the empty state itself recommends to a new player.
        //
        // By identifier, not by label. The first version of this matched
        // `label BEGINSWITH "Lease"` and hit the *"Lease term: 60 months"*
        // stepper instead, which silently decremented the term to 48 and
        // leased nothing — a test that drove the wrong control and then
        // reported the app had failed.
        let leaseButton = app.buttons
            .matching(identifier: "ae-market-lease").firstMatch
        require(leaseButton, "a Lease action in the market")
        leaseButton.tap()

        // Confirmed, because the sums involved should never move on one tap.
        let confirm = app.buttons["Lease"]
        if confirm.waitForExistence(timeout: 5) { confirm.tap() }
        checkpoint("03-after-lease")

        // Back to the fleet: the sheet dismisses on success, but only Done
        // gets us out of a sheet that stayed up.
        let done = app.buttons["Done"]
        if done.exists { done.tap() }

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
        app.buttons["Routes"].tap()
        let openRoute = app.buttons["Open a route"]
        require(openRoute, "the route entry point on an empty routes board")
        openRoute.tap()
        checkpoint("05-open-route-sheet")

        // The sheet ranks destinations by demand; the first row is the guided
        // path a new player is offered.
        let firstMarket = app.cells.firstMatch
        if firstMarket.waitForExistence(timeout: 8) { firstMarket.tap() }
        let openAction = app.buttons["Open"]
        if openAction.waitForExistence(timeout: 5), openAction.isEnabled {
            openAction.tap()
        }
        checkpoint("06-after-open-route")

        // AGREEMENT: opening a route must put one on the board.
        let emptyRoutes = app.staticTexts["No routes yet"]
        XCTAssertFalse(emptyRoutes.waitForExistence(timeout: 8),
                       """
                       The routes board still reports "No routes yet" after \
                       Open was tapped. The sheet may have dismissed without \
                       the command being accepted.
                       """)
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

        let eraFilter = app.switches["Hide what this era cannot buy"]
        if eraFilter.waitForExistence(timeout: 5), eraFilter.value as? String == "0" {
            eraFilter.tap()
        }
        let lease = app.buttons.matching(identifier: "ae-market-lease").firstMatch
        require(lease, "a Lease action")
        lease.tap()
        let confirmLease = app.buttons["Lease"]
        if confirmLease.waitForExistence(timeout: 5) { confirmLease.tap() }
        let done = app.buttons["Done"]
        if done.waitForExistence(timeout: 3) { done.tap() }

        // ── Open a route ───────────────────────────────────────────────────
        app.buttons["Routes"].tap()
        let openRoute = app.buttons["Open a route"]
        require(openRoute, "the route entry point")
        openRoute.tap()
        let firstMarket = app.cells.firstMatch
        if firstMarket.waitForExistence(timeout: 8) { firstMarket.tap() }
        let openAction = app.buttons["Open"]
        if openAction.waitForExistence(timeout: 5), openAction.isEnabled {
            openAction.tap()
        }

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
    func testFoundingAnAirlineReachesEveryTab() throws {
        launch(appearance: .light)
        guard foundAirline() else { return }

        for tab in ["Home", "Map", "Network", "Finance", "World"] {
            openTab(tab)
            XCTAssertTrue(app.staticTexts.count > 0 || app.otherElements.count > 0,
                          "\(tab) rendered no content")
        }
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
