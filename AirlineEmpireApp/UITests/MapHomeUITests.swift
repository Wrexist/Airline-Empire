import XCTest

/// AE-048 — the map is the home screen.
///
/// The phase's claim is an *experience* claim: the game opens on the world,
/// the world says what the airline is doing, and the next thing to do is on
/// the world rather than on a screen beside it. None of that is provable by a
/// screenshot alone, so this journey drives the real controls the claim rests
/// on and photographs what they produce:
///
/// | Frame | What it shows |
/// | --- | --- |
/// | A | the world, on arrival, with no dashboard in front of it |
/// | B | the airline's state and its one next move, at the foot of the map |
/// | C | the first interaction — the next move opens the aircraft market |
/// | D | the move became the first route, offered over the arcs it names |
/// | E | the move became the assignment, on the route's own screen |
/// | F | an aircraft selected on the map, and the camera riding with it |
/// | G | an airport selected, with its contextual actions |
/// | H | back to the world, selection released |
/// | I | the management areas, still one tap away |
/// | J | the map later, with the network running |
///
/// What it cannot prove is that any of it *looks* right. That is what the
/// frames are for, and they are read by a person.
final class MapHomeUITests: AEUITestCase {

    /// The whole claim, in one run.
    func testTheMapIsTheHomeScreen() throws {
        launch(appearance: .light, arguments: ["-AEUITestSunriseWeek"])
        guard foundAirline() else { return }

        // ── FRAME A · the game opens on the world ──────────────────────────
        let map = app.descendants(matching: .any)["ae-map-canvas"]
        XCTAssertTrue(map.waitForExistence(timeout: 25), """
            Founding an airline did not land on the world map. AE-048's whole \
            claim is that the map is what the game opens on; a shell that \
            arrives anywhere else has not shipped the phase.
            """)
        assertTabBarIsTheFourTabShell()
        checkpoint("AE048-A-map-home-on-arrival")

        // ── FRAME B · the airline, and its one next move ───────────────────
        let handle = app.buttons["ae-home-briefing"]
        guard require(handle, "the briefing handle at the foot of the map") else { return }
        let move = app.descendants(matching: .any)
            .matching(identifier: "ae-home-next-action").firstMatch
        XCTAssertTrue(move.waitForExistence(timeout: 10), """
            The map home offers no next move to a brand-new airline. The row \
            reads the onboarding model, whose first step is always present \
            for an airline with no aircraft, so an empty row means it is not \
            reading it.
            """)
        XCTAssertTrue(move.label.contains("Get an aircraft"), """
            The map home's first move reads "\(move.label)" for an airline \
            with nothing. Expected the onboarding model's first step.
            """)
        // The state strip is the handle, and it must actually say something.
        XCTAssertFalse((handle.value as? String ?? "").isEmpty, """
            The briefing handle carries no airline state. It is the only \
            place on the map that says what the airline has.
            """)
        checkpoint("AE048-B-state-and-next-move")

        // The briefing: everything the Home tab used to be, one tap away.
        guard openBriefing() else { return }
        checkpoint("AE048-B2-briefing-over-the-world")
        XCTAssertTrue(app.staticTexts["Get an aircraft"].waitForExistence(timeout: 10),
                      "The briefing does not carry the onboarding checklist.")
        closeBriefing()
        XCTAssertTrue(map.waitForExistence(timeout: 10),
                      "Closing the briefing did not return to the map.")

        // ── FRAME C · the first interaction happens on the map ─────────────
        guard tapWhenReady(move) else {
            capture(Self.logPrefix + "AE048-MOVE-NO-TAP")
            XCTFail("The map home's next move did not accept a tap.")
            return
        }
        XCTAssertTrue(app.staticTexts["Aircraft market"].waitForExistence(timeout: 12), """
            Pressing "Get an aircraft" on the map did not open the aircraft \
            market. A next move that names an action and does not perform it \
            is the dead-control class this phase forbids.
            """)
        checkpoint("AE048-C-market-opened-from-the-map")
        guard leaseAnAircraft(proof: .mapHomeBriefing) else { return }

        // ── FRAME D · the move becomes the first route ─────────────────────
        XCTAssertTrue(map.waitForExistence(timeout: 15), """
            Leasing from the map's own market did not return to the map.
            """)
        let suggestion = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "→")).firstMatch
        guard tapWhenReady(suggestion, timeout: 15) else {
            capture(Self.logPrefix + "AE048-NO-ROUTE-SUGGESTION")
            XCTFail("""
                With an aircraft and no routes, the map home offers no first \
                market to open. The suggestions come from the onboarding \
                model, which has two at this point.
                """)
            return
        }
        let commit = app.buttons.matching(identifier: "ae-route-open").firstMatch
        guard require(commit, "the route sheet's commit bar", timeout: 10) else { return }
        checkpoint("AE048-D-route-sheet-from-the-map")
        commit.tap()

        // ── FRAME E · the move becomes the assignment ──────────────────────
        XCTAssertTrue(move.waitForExistence(timeout: 15), """
            The map home shows no next move after the first route was opened.
            """)
        XCTAssertTrue(move.label.contains("Put the aircraft on the route"), """
            With a route open and an aircraft idle, the map home's move reads \
            "\(move.label)". Expected the onboarding model's assignment step.
            """)
        guard tapWhenReady(move) else {
            capture(Self.logPrefix + "AE048-ASSIGN-MOVE-NO-TAP")
            XCTFail("The assignment move did not accept a tap.")
            return
        }
        let assign = app.buttons["Assign an aircraft"]
        guard require(assign, "the assignment control on the route the map opened",
                      timeout: 12) else { return }
        checkpoint("AE048-E-route-detail-from-the-map")
        assign.tap()
        let candidate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", " at ")).firstMatch
        if candidate.waitForExistence(timeout: 6) { candidate.tap() }
        XCTAssertTrue(app.buttons["Unassign"].waitForExistence(timeout: 12), """
            The aircraft was not assigned. The map's move reached the right \
            screen but the command did not take.
            """)

        // ── FRAME F · the world moves, and can be ridden ───────────────────
        //
        // Pop the route detail first. It was pushed inside the map's own
        // navigation stack, and tapping the Home tab that is already selected
        // does not pop it — the map would still be behind a detail screen.
        let back = app.navigationBars.buttons.firstMatch
        if back.exists, back.isHittable { back.tap() }
        Thread.sleep(forTimeInterval: 0.6)
        openTab("Home")
        // Assignments materialise into flights at the next daily boundary.
        // At 1x, five real minutes reach only 20:00 on the founding day.
        guard advanceMornings(until: "2030-01-02", cap: 1) else { return }

        // Speed selection is idempotent. A recorded 26.2 synthetic Pause
        // tap hit its reported frame but left 1x selected. Permit one
        // state-checked retry, retain its screenshot, and still fail if the
        // requested speed is not selected. Purchases and day advances do
        // not use this retry because repeating them changes the game twice.
        func selectSpeed(_ label: String) -> Bool {
            for attempt in 1...2 {
                let control = app.buttons.matching(identifier: label).firstMatch
                guard require(control, "the \(label) control", timeout: 8),
                      control.isHittable, waitUntilStill(control) else {
                    checkpoint("AE048-SPEED-\(label)-NOT-READY")
                    XCTFail("The \(label) control was not stable and hittable.")
                    return false
                }
                if control.isSelected { return true }
                control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    let current = self.app.buttons.matching(identifier: label).firstMatch
                    return current.exists && current.isSelected
                }, object: nil)
                if XCTWaiter.wait(for: [selected], timeout: 8) == .completed { return true }
                checkpoint("AE048-SPEED-\(label)-ATTEMPT-\(attempt)")
            }
            XCTFail("\(label) did not become selected after two idempotent attempts.")
            return false
        }
        // Observe real departures at normal speed so a short flight remains
        // airborne long enough for accessibility discovery and Pause.
        guard selectSpeed("Normal speed") else { return }

        func value() -> String { map.value as? String ?? "" }
        func airborne() -> Int {
            let text = value()
            guard let range = text.range(of: #"([0-9]+) aircraft in the air"#,
                                         options: .regularExpression)
            else { return 0 }
            return Int(text[range].prefix(while: \.isNumber)) ?? 0
        }
        let menuDeadline = Date().addingTimeInterval(300)
        while !app.buttons["ae-follow-flight-menu"].exists && Date() < menuDeadline {
            Thread.sleep(forTimeInterval: 1)
        }
        // Pause before taking a screenshot or querying the canvas. On a
        // loaded runner those operations took five game hours at 16x, so
        // the flight landed between its discovery and the Pause tap.
        guard selectSpeed("Pause") else { return }
        Thread.sleep(forTimeInterval: 1)
        checkpoint("AE048-F0-map-with-the-network-running")

        if airborne() > 0 {
            // Use the same accessible flight menu available to every player.
            let menu = app.buttons.matching(identifier: "ae-follow-flight-menu").firstMatch
            guard require(menu, "the live flight menu", timeout: 8) else { return }
            menu.tap()
            let flight = app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier != %@",
                "ae-follow-flight-", "ae-follow-flight-menu")).firstMatch
            guard require(flight, "a player flight in the menu", timeout: 8) else { return }
            flight.tap()
            Thread.sleep(forTimeInterval: 1)
            XCTAssertTrue(value().contains("following"), """
                The follow control was pressed from the map home and the \
                map does not report a followed flight. Canvas value: \
                \(value())
                """)
            checkpoint("AE048-F-following-from-the-home-map")
            map.swipeLeft()
            Thread.sleep(forTimeInterval: 1)
            XCTAssertFalse(value().contains("following"), """
                A drag did not release the follow camera on the home map.
                """)
        } else {
            checkpoint("AE048-F-NOTHING-AIRBORNE")
            XCTFail("The assigned route did not produce a flight to follow.")
            return
        }

        // ── FRAME G · something in the world, selected on the home map ─────
        //
        // The clock is already stopped by the follow leg above; stop it here
        // too for the path where that leg was skipped. This leg is about the
        // *panel*, not about hitting a particular kind of object — an airport
        // or the route between them both count. The claim is that the world
        // answers a tap and the briefing gets out of the way while it does.
        let paused = app.buttons["Pause"]
        if paused.exists, paused.isHittable { paused.tap() }
        let frameNetwork = app.buttons["Frame my network"]
        if frameNetwork.exists { frameNetwork.tap() }
        Thread.sleep(forTimeInterval: 1)
        let zoomIn2 = app.buttons["Zoom in"]
        if zoomIn2.exists { for _ in 0..<2 { zoomIn2.tap() } }
        Thread.sleep(forTimeInterval: 0.5)

        func selected() -> Bool { value().contains("Selected") }
        let ring: [(CGFloat, CGFloat)] = [
            (0.5, 0.5), (0.5, 0.46), (0.54, 0.5), (0.46, 0.5),
            (0.5, 0.54), (0.54, 0.46), (0.46, 0.54),
        ]
        var picked = false
        for offset in ring {
            map.coordinate(withNormalizedOffset:
                CGVector(dx: offset.0, dy: offset.1)).tap()
            Thread.sleep(forTimeInterval: 0.6)
            if selected() { picked = true; break }
        }
        if picked {
            let panel = app.descendants(matching: .any)["ae-map-selection"]
            XCTAssertTrue(panel.waitForExistence(timeout: 6), """
                The home map reported a selection and opened no panel.
                """)
            // The briefing must get out of the way while something is
            // inspected: one bottom region, one occupant.
            XCTAssertFalse(app.buttons["ae-home-briefing"].exists, """
                The briefing strip is still at the foot of the map with a \
                selection card open. Both are competing for the same region, \
                which is exactly what this phase had to avoid.
                """)
            checkpoint("AE048-G-selection-on-the-home-map")

            // ── FRAME H · back to the world ────────────────────────────────
            let close = app.buttons["Clear selection"]
            if close.exists, close.isHittable {
                close.tap()
            } else {
                map.coordinate(withNormalizedOffset:
                    CGVector(dx: 0.06, dy: 0.3)).tap()
            }
            Thread.sleep(forTimeInterval: 1)
            XCTAssertTrue(app.buttons["ae-home-briefing"]
                .waitForExistence(timeout: 8), """
                Releasing the selection did not bring the briefing strip \
                back, so the map home has no state and no next move on it.
                """)
            checkpoint("AE048-H-back-to-the-world")
        } else {
            checkpoint("AE048-G-NO-SELECTION")
        }

        // ── FRAME I · nothing was hidden ───────────────────────────────────
        for tab in ["Airline", "Finance", "World"] {
            openTab(tab)
            XCTAssertTrue(app.staticTexts.count > 0,
                          "\(tab) rendered nothing after the home moved to the map.")
        }
        checkpoint("AE048-I-management-still-reachable")
        openTab("Home")
        XCTAssertTrue(map.waitForExistence(timeout: 10),
                      "The Home tab no longer returns to the world.")
        checkpoint("AE048-J-later-map-home")
    }

    /// Four tabs, and neither of the two shapes this phase could regress into.
    ///
    /// Asked of the tab bar itself rather than through `tabButton`, whose
    /// ladder falls through to any button or static text with the same name —
    /// which would make "is there a Map tab" answerable by a label somewhere
    /// on the map. Regular width has a sidebar and no tab bar at all, so the
    /// check states what it saw rather than failing an iPad run.
    private func assertTabBarIsTheFourTabShell() {
        let bar = app.tabBars.firstMatch
        guard bar.exists else { return }
        XCTAssertFalse(bar.buttons["Map"].exists, """
            A separate Map tab still exists alongside Home. Home *is* the map \
            now, and two tabs showing one world is the duplication this phase \
            was for.
            """)
        XCTAssertFalse(bar.buttons["More"].exists, """
            The shell has spilled into the system More list. Four tabs cannot \
            overflow, so a More list means a fifth was added back (BUG-009).
            """)
        XCTAssertEqual(bar.buttons.count, 4, """
            The shell shows \(bar.buttons.count) tabs; AE-048 left four — \
            Home, Airline, Finance, World.
            """)
    }


    /// The shell, after the tab that was removed.
    ///
    /// Four tabs, every one of them opening a real screen, and neither a Map
    /// tab nor a system *More* list. This is the cheap standing guard against
    /// the two ways this phase could regress: putting the duplicate world
    /// back, or adding a fifth tab and re-creating BUG-009.
    func testTheShellHasFourTabsAndNoDeadDestinations() throws {
        launch(appearance: .light)
        guard foundAirline() else { return }

        for tab in ["Home", "Airline", "Finance", "World"] {
            guard let button = waitForTab(tab, timeout: 12) else {
                capture(Self.logPrefix + "MISSING-\(tab)")
                XCTFail("The \(tab) tab does not exist in any shape.")
                continue
            }
            XCTAssertTrue(button.isHittable, "The \(tab) tab is not tappable.")
            openTab(tab)
            XCTAssertTrue(app.staticTexts.count > 0 || app.otherElements.count > 0,
                          "The \(tab) tab opened an empty screen.")
        }
        openTab("Home")
        assertTabBarIsTheFourTabShell()

        // And the briefing behind Home, which is where the removed tab's
        // content went. A destination that cannot be reached is a dead one.
        XCTAssertTrue(openBriefing(), "The briefing could not be opened from Home.")
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 8), """
            Settings is not on the briefing. It was on the Home toolbar \
            before AE-048 and the briefing is where that toolbar went; \
            without it, saving and quitting the game are unreachable.
            """)
        closeBriefing()
    }
}
