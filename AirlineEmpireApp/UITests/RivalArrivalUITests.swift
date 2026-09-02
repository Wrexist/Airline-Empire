import XCTest

/// The rival that comes to the player (AE-038, TD-026).
///
/// AE-037 photographed every competitive state the game had, and every one
/// of them was the player's doing. The seed scan behind
/// docs/RIVALS_THAT_COME_TO_YOU_AUDIT.md found the one the world starts:
/// from New York, the guided first route is JFK–ORD, and SwiftJet — the
/// regional rival based at Chicago — opens the same pair on day 3 of every
/// seed, its first decision, and then adds a rotation a week until it
/// flies twenty. `RivalsComeToYouTests` is the Linux twin on seed 2030 and
/// measured the arc: the player's share slides from all of it to 42% by
/// day 90 if they do nothing; one more rotation on the aircraft they
/// already have is worth half again the route's profit; a fare cut alone
/// is worth less than doing nothing.
///
/// This journey plays that world in the simulator and photographs what the
/// player sees at each step. Its own class so it runs beside the campaign,
/// not after it.
final class RivalArrivalUITests: AEUITestCase {

    func testARivalComesToYourFirstRoute() throws {
        launch(appearance: .light)
        guard foundAirline(seed: "2030", home: (code: "JFK", city: "New York")) else { return }

        // ── The first route, from the guided path ─────────────────────────
        guard openAircraftMarket() else { return }
        guard leaseAnAircraft() else { return }
        guard openRouteBySearch(city: "Chicago", code: "ORD") else { return }
        guard assignFirstAircraft() else { return }

        // ── RIVAL-KEY-01 · before: the pair is the player's alone ─────────
        guard advanceMornings(until: "2030-01-03", cap: 6) else {
            XCTFail("The sunrise control could not reach January 3.")
            return
        }
        checkpoint("R1-home-before-the-rival")
        guard openRouteDetail(containing: "ORD") else { return }
        let alone = app.staticTexts["Nobody. This market is yours alone — for now."]
        XCTAssertTrue(alone.waitForExistence(timeout: 6), """
            On January 3 the route screen should still say nobody else flies \
            JFK–ORD; the Core twin has SwiftJet arriving on day 3 (the 4th).
            """)
        checkpoint("R1-route-before-the-rival")
        app.navigationBars.buttons.firstMatch.tap()

        // ── RIVAL-KEY-02/03 · the morning after: Home says who and where ──
        guard advanceMornings(until: "2030-01-05", cap: 4) else {
            XCTFail("The sunrise control could not reach January 5.")
            return
        }
        let entered = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "SwiftJet", "entered your")).firstMatch
        let found = entered.waitForExistence(timeout: 8)
        if !found { capture(Self.logPrefix + "R2-NO-ENTRY-HEADLINE") }
        continueAfterFailure = true
        XCTAssertTrue(found, """
            Home does not say that SwiftJet entered the player's market the \
            morning after it did — the one world-initiated competitive fact \
            this journey exists to show.
            """)
        checkpoint("R2-home-rival-entered")
        guard openRouteDetail(containing: "ORD") else { return }
        checkpoint("R3-route-morning-after-entry")
        app.navigationBars.buttons.firstMatch.tap()

        // ── RIVAL-KEY-04/05 · a month on: the split and what it costs ─────
        guard advanceMornings(until: "2030-02-03", cap: 32) else {
            XCTFail("The sunrise control could not reach February 3.")
            return
        }
        checkpoint("R4-home-a-month-on")
        guard openRouteDetail(containing: "ORD") else { return }
        let standing = app.descendants(matching: .any)
            .matching(identifier: "ae-route-standing").firstMatch
        XCTAssertTrue(standing.waitForExistence(timeout: 8), """
            A month into a contested pair the route screen has no standing \
            sentence.
            """)
        checkpoint("R4-route-a-month-on")
        // The money and the market, further down the same screen.
        let response = app.descendants(matching: .any)
            .matching(identifier: "ae-route-response").firstMatch
        if scrollUntil(response, "the response line on the contested route") {
            checkpoint("R5-route-consequence-and-response")
        }

        // ── RIVAL-KEY-06 · the response: one more rotation ────────────────
        let increment = app.buttons["Increment"].firstMatch
        if scrollUntil(increment, "the frequency stepper") {
            checkpoint("R6-frequency-control")
            increment.tap()
            Thread.sleep(forTimeInterval: 1)
            let three = app.staticTexts.matching(NSPredicate(
                format: "label CONTAINS %@", "3×/day")).firstMatch
            XCTAssertTrue(three.waitForExistence(timeout: 6), """
                Tapping the frequency stepper did not take JFK–ORD to 3×/day.
                """)
            checkpoint("R6-after-response")
        }
        app.navigationBars.buttons.firstMatch.tap()

        // ── RIVAL-KEY-07 · two weeks later: the world after the response ──
        guard advanceMornings(until: "2030-02-17", cap: 18) else {
            XCTFail("The sunrise control could not reach February 17.")
            return
        }
        checkpoint("R7-home-after-response")
        guard openRouteDetail(containing: "ORD") else { return }
        checkpoint("R7-route-after-response")
        app.navigationBars.buttons.firstMatch.tap()
        openTab("World")
        checkpoint("R7-world-hub-after-response")
        // RIVAL-KEY-08, a retreat: not reached in this world within a year
        // (the Core twin measures SwiftJet still on the pair at day 365), so
        // it is not photographed here — docs/RIVALS_THAT_COME_TO_YOU_AUDIT.md.
    }

    // MARK: - Helpers

    /// Open a route from an empty board by searching the sheet for a city
    /// and picking its row — the campaign's Cairo step, generalised.
    private func openRouteBySearch(city: String, code: String) -> Bool {
        app.buttons["Routes"].tap()
        let openRoute = app.buttons["Open a route"]
        guard require(openRoute, "the route entry point on an empty board") else { return false }
        openRoute.tap()
        let search = app.searchFields.firstMatch
        guard search.waitForExistence(timeout: 8) else {
            capture(Self.logPrefix + "R-NO-ROUTE-SEARCH")
            XCTFail("The route sheet's search field never appeared.")
            return false
        }
        search.tap()
        search.typeText(city)
        Thread.sleep(forTimeInterval: 1)
        let row = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "ae-route-destination", code)).firstMatch
        guard row.waitForExistence(timeout: 8) else {
            capture(Self.logPrefix + "R-NO-\(code)-ROW")
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

    /// The route screen for the board row whose label carries `code`, with
    /// its competition section on screen.
    private func openRouteDetail(containing code: String) -> Bool {
        guard openAirlineSection("Routes") else { return false }
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                  "ae-route-row", code)).firstMatch
        guard row.waitForExistence(timeout: 8) else {
            capture(Self.logPrefix + "R-NO-\(code)-ROW-ON-BOARD")
            XCTFail("The Routes board shows no \(code) row.")
            return false
        }
        guard tapWhenReady(row) else {
            capture(Self.logPrefix + "R-\(code)-ROW-NO-TAP")
            XCTFail("The \(code) row did not accept a tap.")
            return false
        }
        let header = app.staticTexts["WHO ELSE FLIES THIS"]
        if header.waitForExistence(timeout: 8) { return true }
        return scrollUntil(header, "the competition section on the route screen")
    }
}
