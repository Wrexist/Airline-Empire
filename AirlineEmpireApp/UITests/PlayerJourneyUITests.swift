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
        launch(appearance: .dark)
        // Before anything is captured: prove the appearance actually took.
        guard requireAppearance(.dark) else { return }
        guard foundAirline() else { return }
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
        launch(appearance: .light)
        guard requireAppearance(.light) else { return }
        guard foundAirline() else { return }
        openTab("Map")
        checkpoint("60-light-map")
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

        // Lease rather than buy: a lease delivers immediately, where a new
        // purchase stays `ordered` until its lead days pass. Leasing is also
        // what the empty state itself recommends to a new player.
        let leaseButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Lease")).firstMatch
        require(leaseButton, "a Lease action in the market")
        leaseButton.tap()

        // Confirmed, because the sums involved should never move on one tap.
        let confirm = app.buttons["Lease"]
        if confirm.waitForExistence(timeout: 5) { confirm.tap() }
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
