import XCTest

/// Money moving: acquiring an aircraft, flying it, and closing a month.
///
/// Grouped because they share the expensive part of their setup — an airline
/// with a fleet and a route actually earning — and because a failure in one
/// almost always explains a failure in the others.
final class EconomyJourneyUITests: AEUITestCase {


    /// AE-042: the advice a new player is given at New York, photographed.
    ///
    /// BUG-055 measured what Home used to say here. Its two suggestions were
    /// Chicago and Toronto, and Toronto — 589 km, 2,926 passengers a day, and
    /// 63% of its revenue going to airport fees — lost $214k a month after
    /// the aircraft it needed. A scripted campaign that followed that advice
    /// went into administration and collapsed on day 430 in 28 of 30 seeds
    /// (docs/AE042_NEXT_MOVES_BASELINE.md). The ranking has since been gated
    /// on whether a market pays for the aircraft that flies it.
    ///
    /// This journey founds the same start in the simulator, photographs what
    /// Home now recommends, follows it with real commands, and comes back at
    /// the day the old advice was fatal. `NextMovesTests` measures the same
    /// world headlessly; this proves the player can see it.
    func testNewYorkAdviceIsWorthFollowing() throws {
        launch(appearance: .light)
        guard foundAirline(seed: "2030", home: (code: "JFK", city: "New York")) else { return }

        // ── AE042-KEY-01 · what Home offers a brand-new airline ────────────
        openTab("Home")
        let card = app.descendants(matching: .any)
            .matching(identifier: "ae-next-moves").firstMatch
        if !card.waitForExistence(timeout: 10) {
            // Before the first aircraft the checklist owns the screen and
            // carries the same suggestions; either surface is the advice.
            capture(Self.logPrefix + "AE042-NO-NEXT-MOVES-CARD")
        }
        checkpoint("AE042-1-home-first-advice")

        // Toronto was the second suggestion and the trap. It must not be
        // among what Home offers now.
        let toronto = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "JFK", "YYZ")).firstMatch
        XCTAssertFalse(toronto.exists, """
            Home still offers New York–Toronto, the market BUG-055 was found \
            on: 589 km, 63% of revenue in airport fees, −$214k a month after \
            the aircraft it needs.
            """)

        // ── AE042-KEY-02 · the aircraft, then the first recommended route ──
        guard openAircraftMarket() else { return }
        guard leaseAnAircraft() else { return }
        checkpoint("AE042-2-after-the-aircraft")

        openTab("Home")
        let suggestion = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "→")).firstMatch
        guard tapWhenReady(suggestion) else {
            capture(Self.logPrefix + "AE042-SUGGESTION-NO-TAP")
            XCTFail("Home's first recommendation did not accept a tap.")
            return
        }
        let commit = app.buttons.matching(identifier: "ae-route-open").firstMatch
        guard require(commit, "the route sheet's commit bar", timeout: 8) else { return }
        checkpoint("AE042-3-route-sheet-for-the-recommendation")
        commit.tap()
        Thread.sleep(forTimeInterval: 1)

        guard openAirlineSection("Routes") else { return }
        let bare = assignAllBareRoutes()
        XCTAssertEqual(bare, 0, "\(bare) route(s) have no aircraft after taking the advice.")
        checkpoint("AE042-4-route-after-assignment")

        // ── AE042-KEY-05 · the first closed month ─────────────────────────
        guard advanceMornings(until: "2030-02-02", cap: 40) else {
            XCTFail("The sunrise control could not reach February.")
            return
        }
        openTab("Home")
        checkpoint("AE042-5-home-after-first-month")
        openTab("Finance")
        checkpoint("AE042-6-finance-first-statement")

        // ── AE042-KEY-07 · the day the old advice was fatal ───────────────
        // The scripted campaign that followed the old recommendations went
        // into administration and collapsed on day 430. This walks past it.
        guard advanceMornings(until: "2031-03-10", cap: 70) else {
            XCTFail("The sunrise control could not reach March 2031.")
            return
        }
        openTab("Home")
        checkpoint("AE042-7-home-past-the-old-collapse-day")
        // Still playing: a collapsed airline is on the game-over screen and
        // has no tabs at all.
        XCTAssertNotNil(waitForTab("Home", timeout: 10), """
            The airline is no longer playable past day 430 — the window in \
            which the pre-AE-042 advice bankrupted this start.
            """)
        openTab("Finance")
        checkpoint("AE042-8-finance-past-the-old-collapse-day")
        openTab("Airline")
        _ = openAirlineSection("Routes")
        checkpoint("AE042-9-network-past-the-old-collapse-day")
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
        // Run 114 ended this journey between the route frame and the
        // flight frame with nothing photographed in between: the map, its
        // framing button and the speed control are the only steps there.
        // One frame of the map as the clock is about to start, so the next
        // silent stop has a picture.
        checkpoint("80b-map-before-the-clock")
        let frameNetwork = app.buttons["Frame my network"]
        if frameNetwork.waitForExistence(timeout: 5), frameNetwork.isHittable {
            frameNetwork.tap()
        }

        let fast = app.buttons["Sixteen times speed"]
        guard require(fast, "the 16x speed control") else { return }
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
}
