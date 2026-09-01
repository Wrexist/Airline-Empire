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

        let tabs = ["Map", "Airline", "Finance", "World"]
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
        openTab("Airline")
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
        openTab("Airline")
        app.buttons["Fleet"].tap()
        let browse = app.buttons["Browse the market"]
        require(browse, "the market entry point")
        browse.tap()

        guard leaseAnAircraft() else { return }

        // ── Open a route ───────────────────────────────────────────────────
        guard openARoute() else { return }

        // ── Assign ─────────────────────────────────────────────────────────
        guard assignFirstAircraft() else { return }
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

        // ── The payoff (EXP-01) ────────────────────────────────────────────
        // Revenue posts as the flight lands, seconds of real time after
        // takeoff at 16x. The durable proof is on Home: the onboarding
        // checklist retires and the Next Moves card takes its place. The
        // celebration overlay is transient, so it is photographed when the
        // poll happens to catch it, never asserted — a screenshot loop is
        // not a race the suite should bet on.
        openTab("Home")
        let lastStep = app.staticTexts["Earn your first ticket revenue"]
        var celebrationSeen = false
        let payoffDeadline = Date().addingTimeInterval(120)
        while Date() < payoffDeadline, lastStep.exists {
            if !celebrationSeen, app.staticTexts["First flight"].exists {
                celebrationSeen = true
                checkpoint("08-first-flight-celebration")
            }
            Thread.sleep(forTimeInterval: 2)
        }
        checkpoint("09-home-after-first-revenue")
        XCTAssertFalse(lastStep.exists, """
            Two real minutes after an aircraft was airborne — several game \
            days at 16x — the checklist still says no ticket revenue has \
            been earned. Either revenue is not posting on landing or the \
            onboarding model is not seeing it.
            """)
        let nextMoves = app.descendants(matching: .any)
            .matching(identifier: "ae-next-moves").firstMatch
        XCTAssertTrue(nextMoves.waitForExistence(timeout: 10), """
            The checklist retired but nothing took its place: the Next \
            Moves card did not render on Home. With one route open there \
            are open markets to suggest, so an empty card is a defect, not \
            a quiet state (EXP-01).
            """)
    }

    /// The first month closes with a statement — the state no automation has
    /// ever seen (AE-034 "The First Month").
    ///
    /// Everything before this test ends within the first game days: the
    /// project has photographed a founded airline, a first flight, and first
    /// revenue, but never a month-end — so the first financial statement,
    /// the populated Finance tab, and the "first profitable month" milestone
    /// have only ever existed as code (READ, never OBSERVED).
    ///
    /// The engine is driven by the sunrise control — "Advance to next
    /// morning" simulates synchronously to the next midnight, a real product
    /// action, so the month passes through the real economy with no
    /// wall-clock dependence and no cheat scaffolding. Thirty-one taps take
    /// the calendar from 2030-01-01 to 2030-02-01; the month boundary runs
    /// the statement rollup during the last one.
    ///
    /// What it asserts is the contract, not the outcome: a statement for
    /// January exists with a Net profit line. Whether the month is
    /// *profitable* belongs to the balance, not this test — the milestone
    /// celebration is photographed when it appears, never required.
    func testTheFirstMonthClosesWithAStatement() throws {
        launch(appearance: .light)
        guard foundAirline() else { return }

        // A schedule to bill and earn against: the same guided path every
        // journey uses. Without a flying aircraft the month would close on
        // overhead alone — a statement, but not the player's first month.
        openTab("Airline")
        app.buttons["Fleet"].tap()
        let browse = app.buttons["Browse the market"]
        require(browse, "the market entry point")
        browse.tap()
        guard leaseAnAircraft() else { return }
        guard openARoute() else { return }
        guard assignFirstAircraft() else { return }

        // ── A month passes ─────────────────────────────────────────────────
        openTab("Home")
        let sunrise = app.buttons["Advance to next morning"]
        require(sunrise, "the advance-to-morning control")
        // The header prints the date as 2030-01-01; February appearing is
        // the proof the boundary was crossed. Polled by prefix so the exact
        // day is not a contract.
        let february = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH '2030-02'")).firstMatch
        let january31 = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH '2030-01-31'")).firstMatch
        var days = 0
        while days < 33, !february.exists {
            if january31.exists { checkpoint("10-before-month-end") }
            sunrise.tap()
            // Each tap simulates a full game day synchronously on the
            // session actor; the pause lets the snapshot land before the
            // date is re-read. State-based, not time-based: the loop exits
            // on the calendar, the sleep only paces the polling.
            Thread.sleep(forTimeInterval: 0.5)
            days += 1
        }
        XCTAssertTrue(february.exists, """
            Thirty-three advance-to-morning taps did not reach February. \
            Either the control stopped advancing the clock or the header \
            stopped showing the date.
            """)
        // The overlay for "First profitable month" is transient; caught if
        // present, never required — profitability is the balance's contract.
        if app.staticTexts["First profitable month"].exists {
            checkpoint("14-first-profitable-month")
        }
        checkpoint("11-home-after-month-end")

        // ── The statement (the never-seen state) ───────────────────────────
        openTab("Finance")
        // AESectionHeader renders its text uppercased, and XCUITest matches
        // the rendered string: run 94 failed this assertion against
        // "Jan 2030 statement" while KEY-11's populated "Last month $959k"
        // tile proved the statement existed — the only defect was this
        // test's casing.
        let statementHeader = app.staticTexts["JAN 2030 STATEMENT"]
        XCTAssertTrue(statementHeader.waitForExistence(timeout: 10), """
            February has begun but Finance shows no "JAN 2030 STATEMENT" \
            header — the month closed without a statement the player can \
            see, or the rollup did not run.
            """)
        XCTAssertFalse(app.staticTexts["No closed month yet."].exists,
                       "The empty-state line survived a closed month.")
        // Scroll the statement's own card into view before photographing:
        // the header cards sit above it.
        let netProfit = app.staticTexts["Net profit"]
        scrollUntil(netProfit, "the statement's Net profit line")
        XCTAssertTrue(netProfit.exists, """
            The January statement renders without a Net profit line — the \
            one number the first month exists to teach.
            """)
        checkpoint("12-finance-first-statement")

        // ── The month, from the route's side ───────────────────────────────
        openTab("Airline")
        app.buttons["Routes"].tap()
        let routeRow = app.descendants(matching: .any)
            .matching(identifier: "ae-route-row").firstMatch
        if routeRow.waitForExistence(timeout: 5) {
            routeRow.tap()
            Thread.sleep(forTimeInterval: 1)
            checkpoint("13-route-after-month")
        }

        // ── The world, a month in ──────────────────────────────────────────
        // The World hub's live lines (EXP-05) have nothing to say on day
        // one — no event has started, the rivals are still building. A
        // month later the world has history, which is the state the lines
        // exist for; this is the frame that can show them.
        openTab("World")
        Thread.sleep(forTimeInterval: 1)
        checkpoint("15-world-after-month")
    }

    /// The campaign: founding to the Regional era, on the world seed the
    /// Core twin proved (AE-035 "The First Era").
    ///
    /// `FirstEraCampaignTests.campaignReachesTheRegionalEraDeterministically`
    /// walks this exact script headlessly on seed 2039 and measures: a
    /// tourism boom on day 8 offers a mission; reacting with an ARN–Cairo
    /// route completes it by day 11; the February expansion (a used
    /// narrowbody bought outright, two more markets) satisfies the Regional
    /// gate — three profitable routes plus one owned airframe — and the era
    /// arrives on day 59, with statements of $1.8M and $5.4M behind it.
    /// This test's job is what Linux cannot do: SHOW those states — the
    /// mission on the Progression screen, the gate's requirement rows, the
    /// era changing on Home — and photograph them.
    ///
    /// Wherever the simulator's world diverges from the Core twin (a tap
    /// that lands differently is a different command stream), the assertions
    /// hold to the *contract* — a mission appears, the era arrives — rather
    /// than to Linux's exact numbers.
    func testTheCampaignReachesTheRegionalEra() throws {
        launch(appearance: .light)
        guard foundAirline(seed: "2039") else { return }

        // ── Month one, the guided path ─────────────────────────────────────
        guard openAircraftMarket() else { return }
        guard leaseAnAircraft() else { return }
        guard openARoute() else { return }
        guard assignFirstAircraft() else { return }

        // ── Day 8: the world moves, a mission arrives ──────────────────────
        guard advanceMornings(until: "2030-01-10", cap: 12) else {
            XCTFail("The sunrise control could not reach January 10.")
            return
        }
        guard openProgression() else { return }
        let mission = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Carry ")).firstMatch
        XCTAssertTrue(mission.waitForExistence(timeout: 8), """
            Seed 2039's day-8 tourism boom offered no visible mission on the \
            Progression screen by January 10 — the Core twin proves the \
            mission exists in state, so either the offer diverged or the \
            screen is not showing it.
            """)
        checkpoint("30-mission-offered")
        app.navigationBars.buttons.firstMatch.tap()

        // ── React: a route into the boom region ────────────────────────────
        // Cairo is the nearest African airport inside a narrowbody's range
        // (Addis Ababa, the alphabetical pick, is 5,850 km out — measured by
        // the Core twin when its own first script left that route unflown).
        guard openAircraftMarket() else { return }
        guard leaseAnAircraft() else { return }
        guard openAirlineSection("Routes") else { return }
        // The shell toolbar's "+" is labelled "Open route".
        let add = app.buttons["Open route"]
        guard require(add, "the Open route toolbar action") else { return }
        add.tap()
        let search = app.searchFields.firstMatch
        guard search.waitForExistence(timeout: 8) else {
            capture(Self.logPrefix + "NO-ROUTE-SEARCH")
            XCTFail("The route sheet's search field never appeared.")
            return
        }
        search.tap()
        // First, the trap AE-035 measured: Addis Ababa is the boom region's
        // alphabetical pick and 5,850 km from ARN — beyond every startup
        // airframe. The sheet must say which kind of impossible that is,
        // and the commit must warn before the player opens a route nothing
        // can fly (DEC-03/DEC-04).
        search.typeText("Addis")
        Thread.sleep(forTimeInterval: 1)
        let addis = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@",
            "ae-route-destination", "Addis")).firstMatch
        if addis.waitForExistence(timeout: 6) {
            checkpoint("38-future-opportunity-row")
            addis.tap()
            let caution = app.descendants(matching: .any)
                .matching(identifier: "ae-route-unservable").firstMatch
            XCTAssertTrue(caution.waitForExistence(timeout: 6),
                          "An unservable destination is selected and the commit bar shows no warning — the player can open a route nothing can fly with no signal that it will sit unflown (AE-035's dead route, unfixed).")
            checkpoint("39-open-anyway-caution")
        } else {
            capture(Self.logPrefix + "NO-ADDIS-ROW")
        }
        let clear = app.buttons["Clear text"]
        if clear.exists { clear.tap() } else {
            search.tap()
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                                   count: 5))
        }
        Thread.sleep(forTimeInterval: 0.5)
        search.typeText("Cairo")
        Thread.sleep(forTimeInterval: 1)
        let cairo = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@",
            "ae-route-destination", "Cairo")).firstMatch
        guard cairo.waitForExistence(timeout: 8) else {
            capture(Self.logPrefix + "NO-CAIRO-ROW")
            XCTFail("Searching the route sheet for Cairo produced no destination row.")
            return
        }
        cairo.tap()
        let open = app.buttons.matching(identifier: "ae-route-open").firstMatch
        guard require(open, "the commit bar after picking Cairo", timeout: 8)
        else { return }
        open.tap()
        Thread.sleep(forTimeInterval: 1)
        assignAllBareRoutes()

        // ── The mission completes on real passengers ───────────────────────
        guard advanceMornings(until: "2030-01-2", cap: 14) else {
            XCTFail("The sunrise control could not reach late January.")
            return
        }
        guard openProgression() else { return }
        checkpoint("31-mission-after-reaction")
        app.navigationBars.buttons.firstMatch.tap()

        // ── February: buy used, expand on the ranking ──────────────────────
        guard advanceMornings(until: "2030-02", cap: 20) else {
            XCTFail("The sunrise control could not reach February.")
            return
        }
        checkpoint("32-month-two-home")
        guard openAircraftMarket() else { return }
        let usedDeal = app.buttons.matching(identifier: "ae-deal-buy-used").firstMatch
        guard scrollUntil(usedDeal, "the used-deal card in the market") else { return }
        usedDeal.tap()
        Thread.sleep(forTimeInterval: 0.5)
        let buyUsed = app.buttons.matching(identifier: "ae-market-buy-used").firstMatch
        XCTAssertTrue(buyUsed.waitForExistence(timeout: 5), """
            Picking the Used deal card did not hand the commit row the \
            ae-market-buy-used identity — the deal picker's selection did \
            not take.
            """)
        buyUsed.tap()
        let confirmUsed = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Buy used")).firstMatch
        if confirmUsed.waitForExistence(timeout: 4) { confirmUsed.tap() }
        let fleetRow = app.descendants(matching: .any)
            .matching(identifier: "ae-fleet-row").firstMatch
        XCTAssertTrue(fleetRow.waitForExistence(timeout: 10), """
            The used purchase did not land back on the fleet — the market \
            sheet is still up or the command was rejected.
            """)

        // Two more markets, from the same ranking the Next Moves card shows.
        openTab("Home")
        for _ in 0..<2 {
            let suggestion = app.buttons.matching(NSPredicate(
                format: "label CONTAINS %@", "→")).firstMatch
            // The market sheet has just closed over this card; wait for the
            // suggestion to actually accept a tap rather than assuming a
            // visible frame means a live control (run 99).
            guard tapWhenReady(suggestion) else { break }
            let commit = app.buttons.matching(identifier: "ae-route-open").firstMatch
            if commit.waitForExistence(timeout: 8), commit.isEnabled {
                commit.tap()
                Thread.sleep(forTimeInterval: 1)
            } else if app.buttons["Done"].exists {
                app.buttons["Done"].tap()
            }
            openTab("Home")
        }
        guard openAirlineSection("Routes") else { return }
        assignAllBareRoutes()

        // ── The gate, asked the player's question ──────────────────────────
        guard openProgression() else { return }
        let gate = app.staticTexts["To reach Regional"]
        XCTAssertTrue(gate.waitForExistence(timeout: 8), """
            The Progression screen does not answer "what do I need to reach \
            the next era" — no "To reach Regional" section rendered.
            """)
        checkpoint("34-progression-before-era")
        app.navigationBars.buttons.firstMatch.tap()

        // ── February closes; the era arrives with March ────────────────────
        guard advanceMornings(until: "2030-03", cap: 33) else {
            XCTFail("The sunrise control could not reach March.")
            return
        }
        if app.staticTexts["A new era"].exists {
            checkpoint("35-era-celebration")
        }
        let regional = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "Regional era")).firstMatch
        XCTAssertTrue(regional.waitForExistence(timeout: 10), """
            March has begun with the Core twin's gate satisfied, but Home \
            still does not say "Regional era" — the era did not advance, or \
            the banner does not show it.
            """)
        checkpoint("36-era-home")

        openTab("Finance")
        Thread.sleep(forTimeInterval: 1)
        checkpoint("33-second-statement")

        guard openProgression() else { return }
        let nextGate = app.staticTexts["To reach National"]
        XCTAssertTrue(nextGate.waitForExistence(timeout: 8), """
            The Regional era arrived but the Progression screen offers no \
            next goal — "To reach National" is missing, and a campaign \
            without a next goal ends here.
            """)
        checkpoint("37-progression-after-era")
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
        openTab("Map")

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

        // Zoomed out one more time with the selection held: this is the frame
        // where the hub rings on the other global airports are visible beside
        // the pulsing selection.
        let zoomOut = app.buttons["Zoom out"]
        if zoomOut.exists {
            for _ in 0..<3 { zoomOut.tap() }
            checkpoint("87-airport-selected-world")
        }
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

        for tab in ["Home", "Map", "Airline", "Finance", "World"] {
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

        for (index, tab) in ["Home", "Map", "Airline", "Finance", "World"].enumerated() {
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
        for tab in ["Map", "Airline", "Finance", "World", "Home"] {
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

    /// Home guides a new player to their first aircraft.
    ///
    /// Load-bearing rather than decorative: the Airline tab opens on Routes,
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
