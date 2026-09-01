import XCTest

/// The long campaign: founding an airline, and driving the real engine far
/// enough that progression has something to say.
///
/// Its own class, and the reason the suite is split into several. XCUITest
/// distributes work **by test class**, so nineteen tests in one class ran
/// one after another for twenty-six minutes however many simulators the
/// runner could have cloned. The campaign is the long pole — it simulates a
/// quarter of game time one sunrise at a time — so it sits alone with the
/// three shortest tests packed in beside it.
final class CampaignUITests: AEUITestCase {


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
        // The Core twin completes it on day 11. Watch Home every morning
        // rather than arriving ten days later: the feed keeps fourteen
        // *events*, so the completion is gone from it well before then, and
        // run 102's late-January frame could only show the mission missing.
        if advanceMorningsUntilHomeSays("Mission complete", cap: 16) {
            checkpoint("30b-mission-complete-on-home")
        } else {
            capture(Self.logPrefix + "NO-MISSION-COMPLETE-ON-HOME")
        }
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

        // The twin's February also *leases* alongside the purchase: four
        // routes need four aircraft, and a route with nothing to fly it
        // earns nothing and so never counts toward the gate's "routes that
        // made money last month". Run 100 reached March with three.
        guard openAircraftMarket() else { return }
        guard leaseAnAircraft() else { return }

        // Two more markets, from the same ranking the Next Moves card shows.
        openTab("Home")
        for attempt in 1...2 {
            let suggestion = app.buttons.matching(NSPredicate(
                format: "label CONTAINS %@", "→")).firstMatch
            // The market sheet has just closed over this card; wait for the
            // suggestion to actually accept a tap rather than assuming a
            // visible frame means a live control (run 99).
            guard tapWhenReady(suggestion) else {
                checkpoint("FEB-SUGGESTION-NO-TAP-\(attempt)")
                break
            }
            let commit = app.buttons.matching(identifier: "ae-route-open").firstMatch
            if commit.waitForExistence(timeout: 8), commit.isEnabled {
                commit.tap()
                Thread.sleep(forTimeInterval: 1)
            } else {
                // Run 102 grew the network by one route across two taps and
                // said nothing about the second. Whatever the sheet is doing
                // here — a disabled commit, a rejection, a screen that never
                // arrived — it gets photographed before we walk away.
                checkpoint("FEB-ROUTE-SHEET-STUCK-\(attempt)")
                if app.buttons["Done"].exists { app.buttons["Done"].tap() }
            }
            openTab("Home")
        }

        // ── The fight: London–Paris under two incumbents (AE-037) ──────────
        // The Core twin (RivalPressureCampaignTests) measures this exact
        // move on this seed: two rivals already fly LHR–CDG; entering under
        // their fares is answered the next morning with a fare cut and an
        // extra rotation, both incumbents then climb to twenty a day, and
        // the player holds a third of the market at full load while losing
        // money. COMP-01 … COMP-04 are these states, photographed.
        guard openAircraftMarket() else { return }
        guard leaseAnAircraft() else { return }
        guard openAirlineSection("Routes") else { return }
        let addFight = app.buttons["Open route"]
        guard require(addFight, "the Open route toolbar action (fight)") else { return }
        addFight.tap()
        // From: London. The picker is a menu whose label leads with "From".
        let fromPicker = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "From")).firstMatch
        guard fromPicker.waitForExistence(timeout: 8) else {
            capture(Self.logPrefix + "NO-FROM-PICKER")
            XCTFail("The route sheet's From picker never appeared.")
            return
        }
        fromPicker.tap()
        let london = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "LHR")).firstMatch
        guard london.waitForExistence(timeout: 6) else {
            capture(Self.logPrefix + "NO-LHR-ORIGIN")
            XCTFail("London is not offered as an origin although ARN–LHR is flown — the From picker lists airports the airline serves.")
            return
        }
        london.tap()
        let fightSearch = app.searchFields.firstMatch
        guard fightSearch.waitForExistence(timeout: 8) else {
            capture(Self.logPrefix + "NO-FIGHT-SEARCH")
            XCTFail("The route sheet's search field never appeared for the fight.")
            return
        }
        fightSearch.tap()
        fightSearch.typeText("Paris")
        Thread.sleep(forTimeInterval: 1)
        let paris = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@",
            "ae-route-destination", "Paris")).firstMatch
        guard paris.waitForExistence(timeout: 8) else {
            capture(Self.logPrefix + "NO-PARIS-ROW")
            XCTFail("Searching for Paris from London produced no destination row.")
            return
        }
        // COMP-01: the row says who is already there before anything is
        // committed ("2 airlines already fly it").
        XCTAssertTrue(paris.label.contains("already fly") || paris.label.contains("already flies"), """
            The London–Paris row does not say that airlines already fly it: \
            "\(paris.label)". The Core twin has two incumbents on this pair \
            on this seed by day 4.
            """)
        checkpoint("40-contested-market-row")
        paris.tap()
        // At the market fare, not under it. Run 112 tried the fare slider
        // here and the drag landed on the pinned commit bar under the
        // keyboard: the route opened at the reference fare before the
        // journey had looked, and the "missing commit bar" frame was the
        // Routes board with LHR–CDG already on it. The Core twin measures
        // the undercut variant (0.88×, answered with a fare cut the next
        // morning); at parity the incumbents answer with capacity, which
        // is what the frames a week on show.
        let openFight = app.buttons.matching(identifier: "ae-route-open").firstMatch
        if openFight.waitForExistence(timeout: 8) {
            checkpoint("41-fight-commit")
            openFight.tap()
            Thread.sleep(forTimeInterval: 1)
        } else if app.buttons["Done"].exists || app.buttons["Cancel"].exists {
            capture(Self.logPrefix + "NO-FIGHT-COMMIT-BAR")
            XCTFail("Picking Paris from London produced no commit bar.")
            return
        }
        assignAllBareRoutes()

        // The day of entry: the rivals' offers before they answer.
        guard openContestedRouteDetail() else { return }
        checkpoint("42-contested-route-on-entry")
        app.navigationBars.buttons.firstMatch.tap()

        // A week on: the answer (COMP-04), the split (COMP-03), and the
        // sentence that says where the player stands and why.
        guard advanceMornings(until: "2030-02-09", cap: 12) else {
            XCTFail("The sunrise control could not reach February 9.")
            return
        }
        checkpoint("43-home-rival-pressure")
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "ae-rival-pressure").firstMatch
            .waitForExistence(timeout: 6), """
            Home carries no rival-pressure card a week into a contested \
            market — the one competitive fact the screen exists to show.
            """)
        guard openContestedRouteDetail() else { return }
        let standing = app.descendants(matching: .any)
            .matching(identifier: "ae-route-standing").firstMatch
        XCTAssertTrue(standing.waitForExistence(timeout: 8), """
            The route screen for a contested pair does not say where the \
            player stands — no standing sentence rendered.
            """)
        checkpoint("44-contested-route-after-a-week")
        app.navigationBars.buttons.firstMatch.tap()

        // COMP-06: the World hub and the Competitors screen, live.
        openTab("World")
        checkpoint("45-world-hub-with-competition")
        guard openCompetitors() else { return }
        checkpoint("46-competitors-screen")
        app.navigationBars.buttons.firstMatch.tap()

        // CAUSALITY: the gate counts routes that made money, so the campaign
        // has to actually be flying four of them. A silent three is what run
        // 102 carried into March.
        guard openAirlineSection("Routes") else { return }
        let routeRows = app.descendants(matching: .any)
            .matching(identifier: "ae-route-row")
        _ = routeRows.firstMatch.waitForExistence(timeout: 8)
        let openedRoutes = routeRows.count
        checkpoint("32b-network-after-february")
        let bare = assignAllBareRoutes()
        XCTAssertEqual(bare, 0, """
            February ends with \(bare) of \(openedRoutes) routes having no \
            aircraft to fly them. A route nothing flies earns nothing, so it \
            can never count toward "routes that made money last month".
            """)
        XCTAssertGreaterThanOrEqual(openedRoutes, 4, """
            February ended with \(openedRoutes) routes; the Core twin on the \
            same seed opens four. The two Next Moves suggestions did not both \
            become routes — the FEB- frames say which step dropped.
            """)

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
        // Photograph March *before* the verdict: run 100's assertion failed
        // with no frame of the state it was judging, so the next question —
        // did the era not advance, or does Home not say so? — had nothing to
        // read. The gate's own rows answer it either way.
        checkpoint("36-era-home")
        guard openProgression() else { return }
        checkpoint("37-progression-after-era")
        app.navigationBars.buttons.firstMatch.tap()
        openTab("Home")

        let regional = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "Regional era")).firstMatch
        XCTAssertTrue(regional.waitForExistence(timeout: 10), """
            March has begun with the Core twin's gate satisfied, but Home \
            still does not say "Regional era" — the era did not advance, or \
            the banner does not show it.
            """)

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
    }


    /// The route detail for the contested London–Paris pair, from wherever
    /// the tab was left.
    private func openContestedRouteDetail() -> Bool {
        guard openAirlineSection("Routes") else { return false }
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                  "ae-route-row", "LHR")).firstMatch
        guard row.waitForExistence(timeout: 8) else {
            capture(Self.logPrefix + "NO-LHR-CDG-ROW")
            XCTFail("The Routes board shows no LHR row after the fight was opened.")
            return false
        }
        guard tapWhenReady(row) else {
            capture(Self.logPrefix + "LHR-CDG-ROW-NO-TAP")
            XCTFail("The LHR–CDG row did not accept a tap.")
            return false
        }
        let header = app.staticTexts["WHO ELSE FLIES THIS"]
        if header.waitForExistence(timeout: 8) { return true }
        // The section may be below the fold on a small phone.
        return scrollUntil(header, "the competition section on the route screen")
    }

    /// The Competitors screen from the World hub. Its card's label is the
    /// whole card (title, badge, subtitle, live line), matched by prefix as
    /// `openProgression()` does.
    private func openCompetitors() -> Bool {
        openTab("World")
        let card = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Competitors")).firstMatch
        if card.waitForExistence(timeout: 8) {
            card.tap()
        } else if app.staticTexts["Competitors"].waitForExistence(timeout: 4) {
            app.staticTexts["Competitors"].tap()
        } else {
            capture(Self.logPrefix + "NO-COMPETITORS-CARD")
            XCTFail("The World hub shows no Competitors card in any shape.")
            return false
        }
        let rival = app.descendants(matching: .any)
            .matching(identifier: "ae-rival-card").firstMatch
        guard rival.waitForExistence(timeout: 8) else {
            capture(Self.logPrefix + "NO-RIVAL-CARDS")
            XCTFail("The Competitors screen rendered no rival card.")
            return false
        }
        return true
    }

    /// A world the engine built, opened through the game's own codec.
    ///
    /// `ae-rival-probe` writes these after driving the seed-2039 campaign —
    /// the same script the Core twin proves — for a chosen number of days;
    /// the app loads them under `-AEUITestLoadSave`. A late-game world is
    /// ~1,800 sunrise taps away and a rival's retreat lands on day 248, so
    /// both are photographed from saves rather than not at all.
    private func launchFromFixture(_ name: String) -> Bool {
        guard let url = Bundle(for: CampaignUITests.self)
            .url(forResource: name, withExtension: "json") else {
            XCTFail("The fixture \(name).json is not in the UI test bundle.")
            return false
        }
        launch(appearance: .light, arguments: ["-AEUITestLoadSave", url.path])
        guard waitForTab("Home", timeout: 25) != nil else {
            capture(Self.logPrefix + "FIXTURE-NOT-LOADED-\(name)")
            XCTFail("The app did not reach the shell from \(name).json.")
            return false
        }
        return true
    }

    /// COMP-05: the morning after a rival pulls out of the player's market.
    ///
    /// On seed 2039 the regional incumbent closes London–Paris on day 248,
    /// two hundred days after the player entered it. The fixture is that
    /// campaign saved on day 249; Home must say so.
    func testARivalsRetreatIsOnHomeTheMorningAfter() throws {
        guard launchFromFixture("rival-pressure-retreat") else { return }
        let card = app.descendants(matching: .any)
            .matching(identifier: "ae-rival-pressure").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), """
            Home shows no rival-pressure card the morning after a rival left \
            the player's market.
            """)
        let line = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@", "pulled out")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 6), """
            The card does not name the retreat — expected a line saying a \
            rival pulled out of a market.
            """)
        checkpoint("47-rival-retreat-on-home")
        guard openContestedRouteDetail() else { return }
        checkpoint("48-market-after-retreat")
    }

    /// COMP-07: five simulated years in, with the competitor density the
    /// simulation actually produces — every screen the competition lives on.
    func testLateGameCompetitionFromASavedWorld() throws {
        guard launchFromFixture("rival-pressure-late-game") else { return }
        checkpoint("50-late-game-home")
        openTab("World")
        checkpoint("51-late-game-world-hub")
        guard openCompetitors() else { return }
        checkpoint("52-late-game-competitors")
        let cards = app.descendants(matching: .any).matching(identifier: "ae-rival-card")
        XCTAssertGreaterThanOrEqual(cards.count, 3, """
            The late-game Competitors screen shows \(cards.count) rival cards; \
            the saved world has five rivals.
            """)
        app.navigationBars.buttons.firstMatch.tap()
        openTab("Map")
        Thread.sleep(forTimeInterval: 2)
        let layer = app.buttons["Map layer"]
        if layer.waitForExistence(timeout: 6) {
            layer.tap()
            let rivals = app.buttons.matching(NSPredicate(
                format: "label BEGINSWITH %@", "Rivals")).firstMatch
            if rivals.waitForExistence(timeout: 4) { rivals.tap() }
            Thread.sleep(forTimeInterval: 1)
        }
        checkpoint("53-late-game-map-rivals")
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
