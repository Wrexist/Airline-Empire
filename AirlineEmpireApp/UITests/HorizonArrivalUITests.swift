import XCTest

/// The world comes to a start it never came to (AE-039, docs/HORIZON_AUDIT.md).
///
/// AE-038's world-initiated arrival lived in New York, and it turned out to
/// be an artefact: the regional rival's turboprops lost money on every
/// rotation of that pair, and once markets are ranked by what an airframe
/// day sells it never opens it. Munich is the start the measured ranking
/// reaches, in every seed: `MunichHorizonTests` plays this exact script on
/// seed 2030 and measures PacificBlue, the low-cost carrier based at
/// Istanbul, opening Munich–Istanbul on day 61 at $142 against the
/// player's $167; a month later the player holds 39%, trailing on fare,
/// with a rotation to spare; one more rotation keeps the money, a fare cut
/// keeps the share. This journey plays that world in the simulator and
/// photographs what the player sees.
final class HorizonArrivalUITests: AEUITestCase {

    func testARivalComesToMunich() throws {
        launch(appearance: .light)
        guard foundAirline(seed: "2030", home: (code: "MUC", city: "Munich")) else { return }

        // ── January: the guided first route, Munich–London ────────────────
        guard openAircraftMarket() else { return }
        guard leaseAnAircraft() else { return }
        guard openRouteBySearch(city: "London", code: "LHR") else { return }
        guard assignFirstAircraft() else { return }

        // ── February: a used narrowbody, a lease, the two suggested markets ─
        guard advanceMornings(until: "2030-02", cap: 34) else {
            XCTFail("The sunrise control could not reach February.")
            return
        }
        guard openAircraftMarket() else { return }
        let usedDeal = app.buttons.matching(identifier: "ae-deal-buy-used").firstMatch
        guard scrollUntil(usedDeal, "the used-deal card in the market") else { return }
        usedDeal.tap()
        Thread.sleep(forTimeInterval: 0.5)
        let buyUsed = app.buttons.matching(identifier: "ae-market-buy-used").firstMatch
        guard require(buyUsed, "the buy-used commit row", timeout: 5) else { return }
        buyUsed.tap()
        let confirmUsed = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Buy used")).firstMatch
        if confirmUsed.waitForExistence(timeout: 4) { confirmUsed.tap() }
        let fleetRow = app.descendants(matching: .any)
            .matching(identifier: "ae-fleet-row").firstMatch
        guard require(fleetRow, "the fleet after the used purchase", timeout: 10) else { return }
        guard openAircraftMarket() else { return }
        guard leaseAnAircraft() else { return }
        openTab("Home")
        for attempt in 1...2 {
            let suggestion = app.buttons.matching(NSPredicate(
                format: "label CONTAINS %@", "→")).firstMatch
            guard tapWhenReady(suggestion) else {
                checkpoint("HZ-FEB-SUGGESTION-NO-TAP-\(attempt)")
                break
            }
            let commit = app.buttons.matching(identifier: "ae-route-open").firstMatch
            if commit.waitForExistence(timeout: 8), commit.isEnabled {
                commit.tap()
                Thread.sleep(forTimeInterval: 1)
            } else {
                checkpoint("HZ-FEB-ROUTE-SHEET-STUCK-\(attempt)")
                if app.buttons["Done"].exists { app.buttons["Done"].tap() }
                if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
            }
            openTab("Home")
        }
        guard openAirlineSection("Routes") else { return }
        let bare = assignAllBareRoutes()
        XCTAssertEqual(bare, 0, "\(bare) route(s) have no aircraft after February.")
        checkpoint("HZ-network-after-february")

        // ── HORIZON-KEY-01 · before: Munich–Istanbul is the player's alone ─
        guard advanceMornings(until: "2030-03-02", cap: 34) else {
            XCTFail("The sunrise control could not reach March 2.")
            return
        }
        checkpoint("HZ1-home-before-the-world-moves")
        guard openRouteDetail(containing: "IST") else { return }
        let alone = app.staticTexts["Nobody. This market is yours alone — for now."]
        if !alone.waitForExistence(timeout: 6) { capture(Self.logPrefix + "HZ1-ISTANBUL-NOT-ALONE") }
        checkpoint("HZ1-route-before-the-world-moves")
        app.navigationBars.buttons.firstMatch.tap()

        // ── HORIZON-KEY-02/03 · the morning after: Home says who and where ──
        guard advanceMornings(until: "2030-03-04", cap: 4) else {
            XCTFail("The sunrise control could not reach March 4.")
            return
        }
        let entered = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "PacificBlue", "entered your")).firstMatch
        let found = entered.waitForExistence(timeout: 8)
        if !found { capture(Self.logPrefix + "HZ2-NO-ENTRY-HEADLINE") }
        continueAfterFailure = true
        XCTAssertTrue(found, """
            Home does not say that PacificBlue entered the player's market the \
            morning after it did — the world-initiated event on a start the \
            world never came to before this phase.
            """)
        checkpoint("HZ2-home-rival-entered")
        guard openRouteDetail(containing: "IST") else { return }
        checkpoint("HZ3-route-morning-after-entry")
        app.navigationBars.buttons.firstMatch.tap()

        // ── HORIZON-KEY-04 · a month on: the split and what it costs ───────
        guard advanceMornings(until: "2030-04-03", cap: 34) else {
            XCTFail("The sunrise control could not reach April 3.")
            return
        }
        checkpoint("HZ4-home-a-month-on")
        guard openRouteDetail(containing: "IST") else { return }
        let standing = app.descendants(matching: .any)
            .matching(identifier: "ae-route-standing").firstMatch
        XCTAssertTrue(standing.waitForExistence(timeout: 8), """
            A month after a rival came to Munich–Istanbul the route screen has \
            no standing sentence.
            """)
        checkpoint("HZ4-route-a-month-on")
        let response = app.descendants(matching: .any)
            .matching(identifier: "ae-route-response").firstMatch
        if scrollUntil(response, "the response line on Munich–Istanbul") {
            checkpoint("HZ5-response-line")
        }

        // ── HORIZON-KEY-05 · the response: one more rotation ───────────────
        // The twin measured the choice: a tenth off the fare buys share and
        // costs money; another rotation on the aircraft already there earns
        // more. The journey takes the rotation.
        let increment = app.buttons["Increment"].firstMatch
        if scrollUntil(increment, "the frequency stepper") {
            increment.tap()
            Thread.sleep(forTimeInterval: 1)
            // The count lives on the Stepper's own label ("Frequency:
            // 3×/day"), not on a static text: run 121 photographed the
            // route at 3×/day and still failed a staticTexts query for it.
            let three = app.descendants(matching: .any).matching(NSPredicate(
                format: "label CONTAINS %@", "3×/day")).firstMatch
            XCTAssertTrue(three.waitForExistence(timeout: 6), "Tapping the frequency stepper did not take Munich–Istanbul to 3×/day.")
            checkpoint("HZ5-after-response")
        }
        app.navigationBars.buttons.firstMatch.tap()

        // ── HORIZON-KEY-06 · two weeks later: the world after the response ─
        guard advanceMornings(until: "2030-04-17", cap: 18) else {
            XCTFail("The sunrise control could not reach April 17.")
            return
        }
        checkpoint("HZ6-home-after-response")
        guard openRouteDetail(containing: "IST") else { return }
        checkpoint("HZ6-route-after-response")
        app.navigationBars.buttons.firstMatch.tap()
        openTab("World")
        checkpoint("HZ6-world-hub-after-response")
    }

    // MARK: - Helpers

    private func openRouteBySearch(city: String, code: String) -> Bool {
        app.buttons["Routes"].tap()
        let openRoute = app.buttons["Open a route"]
        guard require(openRoute, "the route entry point on an empty board") else { return false }
        openRoute.tap()
        let search = app.searchFields.firstMatch
        guard search.waitForExistence(timeout: 8) else {
            capture(Self.logPrefix + "HZ-NO-ROUTE-SEARCH")
            XCTFail("The route sheet's search field never appeared.")
            return false
        }
        search.tap()
        search.typeText(city)
        Thread.sleep(forTimeInterval: 1)
        let row = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "ae-route-destination", code)).firstMatch
        guard row.waitForExistence(timeout: 8) else {
            capture(Self.logPrefix + "HZ-NO-\(code)-ROW")
            XCTFail("Searching the route sheet for \(city) produced no \(code) row.")
            return false
        }
        row.tap()
        let open = app.buttons.matching(identifier: "ae-route-open").firstMatch
        guard require(open, "the commit bar after picking \(city)", timeout: 8) else { return false }
        open.tap()
        Thread.sleep(forTimeInterval: 1)
        return true
    }

    private func openRouteDetail(containing code: String) -> Bool {
        guard openAirlineSection("Routes") else { return false }
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                  "ae-route-row", code)).firstMatch
        guard row.waitForExistence(timeout: 8) else {
            capture(Self.logPrefix + "HZ-NO-\(code)-ROW-ON-BOARD")
            XCTFail("The Routes board shows no \(code) row.")
            return false
        }
        guard tapWhenReady(row) else {
            capture(Self.logPrefix + "HZ-\(code)-ROW-NO-TAP")
            XCTFail("The \(code) row did not accept a tap.")
            return false
        }
        let header = app.staticTexts["WHO ELSE FLIES THIS"]
        if header.waitForExistence(timeout: 8) { return true }
        return scrollUntil(header, "the competition section on the route screen")
    }
}
