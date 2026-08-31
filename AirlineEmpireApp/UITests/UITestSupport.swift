import XCTest

/// Shared helpers for the UI target.
///
/// Two jobs: capturing evidence, and asserting the thing BUG-035 proved no
/// existing check could see — **where** an element is, not merely whether it
/// exists.
class AEUITestCase: XCTestCase {

    var app: XCUIApplication!

    /// Screenshots whose names start with this go into the CI job log as
    /// base64, downscaled; everything else lives only in the result bundle.
    ///
    /// The bound is the point. The log carries roughly 200 lines per screen,
    /// so an unbounded set silently pushes the earliest images out of reach of
    /// any practical `tail` (TD-020) — and the ones pushed out are the early
    /// journey steps, which are the ones worth seeing. Marking a checkpoint is
    /// therefore a deliberate act with a visible cost.
    static let logPrefix = "KEY-"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    /// The appearance the simulator is currently in, across tests in a run.
    ///
    /// Static on purpose. `XCUIDevice.appearance` drives the *simulator*, and
    /// switching it is a system-wide animation, not a per-process flag —
    /// setting it before every launch made two of six tests fail on the first
    /// run with "Timed out while launching application via Xcode" and "Failed
    /// to get background assertion for target app with pid 0". Neither was an
    /// app defect; both were the harness fighting the simulator.
    ///
    /// Tracking the current value turns six switches into at most two.
    private static var currentAppearance: XCUIDevice.Appearance?

    /// Put the simulator into an appearance, if it is not already there.
    private func applyAppearance(_ appearance: XCUIDevice.Appearance,
                                 settle: TimeInterval) {
        guard Self.currentAppearance != appearance else { return }
        XCUIDevice.shared.appearance = appearance
        Self.currentAppearance = appearance
        // Let the switch finish. Launching into a system-wide appearance
        // animation is what produced the two failures above; this is a
        // settle, not a guess at a race.
        Thread.sleep(forTimeInterval: settle)
    }

    /// Launch in a named appearance, optionally with extra launch arguments
    /// (a Dynamic Type override, the test probes).
    func launch(appearance: XCUIDevice.Appearance,
                arguments: [String] = []) {
        applyAppearance(appearance, settle: 3)
        app.launchArguments.append(contentsOf: arguments)
        app.launch()
    }

    /// How the appearance under test was actually achieved. Screenshots are
    /// named with it, so an image can never imply more than it proved.
    enum AppearanceRoute: String {
        /// The simulator itself was switched. What a player would see.
        case system = "dark"
        /// The simulator refused, so the app was asked to pin the scheme.
        /// Proves the app renders correctly in dark; does not prove the app
        /// follows the system setting.
        case forced = "darkforced"
    }

    private(set) var appearanceRoute: AppearanceRoute = .system

    /// Reach the game shell in a named appearance, having proved the
    /// appearance actually took — and retrying the launch if it did not.
    ///
    /// **This replaces a guard that did not work.** The first version asked
    /// the question on the new-game screen, which `NewGameView` pins to dark
    /// with `.preferredColorScheme(.dark)` because it is a presentation
    /// surface. So the answer there is "dark" whatever the simulator is
    /// doing: the dark test passed for the wrong reason and captured five
    /// light screens named "dark", and the light test failed with the
    /// self-refuting message "Asked for light appearance; the app reports
    /// light."
    ///
    /// Appearance only varies once the game is running, so that is where it
    /// has to be asked. The retry is here because the switch is a system-wide
    /// animation with no completion to wait on: a fixed sleep either wastes
    /// time or loses the race, and re-launching until the app agrees loses
    /// neither.
    ///
    /// If the simulator will not switch at all — which is what the CI runner
    /// does — it falls back to asking the app to pin the scheme, and records
    /// that in `appearanceRoute` so no screenshot can overstate what it shows.
    @discardableResult
    func reachGameplay(in appearance: XCUIDevice.Appearance) -> Bool {
        let wanted = appearance == .dark ? "dark" : "light"
        appearanceRoute = .system
        for attempt in 1...3 {
            applyAppearance(appearance, settle: attempt == 1 ? 3 : 6)
            app.launch()
            guard foundAirline() else { return false }
            if rendersAppearance(appearance) { return true }
            guard attempt < 3 else { break }
            // Force the next pass to re-apply and wait longer.
            app.terminate()
            Self.currentAppearance = nil
        }

        // The simulator would not switch. Three launches at up to six seconds
        // of settle is past the point where waiting longer is the answer.
        //
        // Rather than lose dark coverage entirely, ask the app to pin the
        // scheme itself, and record in every screenshot name that this is how
        // it was obtained. The two are not the same claim: this proves the
        // app *renders* correctly in dark, and says nothing about whether it
        // follows the system setting. Naming the route is what keeps the
        // weaker claim from being read as the stronger one — which is the
        // whole failure this guard exists to prevent.
        guard appearance == .dark else {
            capture(Self.logPrefix + "APPEARANCE-MISMATCH")
            XCTFail("""
                Asked for light appearance and the shell reports \
                \(reportedAppearance() ?? "nothing") after three launches.
                """)
            return false
        }
        app.terminate()
        app.launchArguments.append("-AEUITestDarkAppearance")
        app.launch()
        guard foundAirline() else { return false }
        if rendersAppearance(.dark) {
            appearanceRoute = .forced
            return true
        }

        capture(Self.logPrefix + "APPEARANCE-MISMATCH")
        let reported = reportedAppearance() ?? "no appearance at all"
        XCTFail("""
            Asked for \(wanted) appearance; the simulator would not switch \
            after three launches, and the app's own override did not take \
            either — the shell still reports \(reported). Screenshots from \
            this test would be mislabelled, so it fails rather than producing \
            false evidence.
            """)
        return false
    }

    /// What the running app says it is rendering in, or nil if it says
    /// nothing. Non-failing: the caller decides what to do about it.
    private func reportedAppearance() -> String? {
        if app.descendants(matching: .any)["ae-appearance-dark"].exists { return "dark" }
        if app.descendants(matching: .any)["ae-appearance-light"].exists { return "light" }
        return nil
    }

    private func rendersAppearance(_ appearance: XCUIDevice.Appearance) -> Bool {
        let wanted = appearance == .dark ? "ae-appearance-dark" : "ae-appearance-light"
        return app.descendants(matching: .any)[wanted].waitForExistence(timeout: 10)
    }

    // MARK: Evidence

    /// Attach the current screen. Prefix with `logPrefix` to also print it
    /// into the CI log.
    func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// A journey checkpoint: attached to the bundle *and* printed to the log.
    func checkpoint(_ name: String) {
        capture(Self.logPrefix + name)
    }

    @discardableResult
    func require(_ element: XCUIElement, _ what: String,
                 timeout: TimeInterval = 25) -> Bool {
        let found = element.waitForExistence(timeout: timeout)
        if !found {
            capture(Self.logPrefix + "MISSING-\(what)")
            XCTFail("\(what) never appeared. Screenshot attached.")
        }
        return found
    }

    /// Wait for an element, scrolling if it is not on screen yet.
    ///
    /// SwiftUI only realises the rows a scroll view has actually laid out, so
    /// a control below the fold is not "not yet visible" to XCUITest — it does
    /// not exist. The aircraft market is the case that proved it: its header
    /// is a cash line, a sort picker, an era switch and two steppers, which is
    /// most of a phone screen before the first aircraft card begins. A query
    /// for the Lease button found nothing and the test reported the app had no
    /// Lease action, which was not true.
    @discardableResult
    func scrollUntil(_ element: XCUIElement, _ what: String,
                     swipes: Int = 8) -> Bool {
        for _ in 0..<swipes {
            if element.exists { break }
            app.swipeUp()
        }
        guard element.exists else {
            capture(Self.logPrefix + "MISSING-\(what)")
            XCTFail("\(what) never appeared, after scrolling \(swipes) times.")
            return false
        }
        // Let the scroll's inertia finish before anyone taps. A tap resolves
        // the element's frame at tap time, and a list still settling moved
        // the Lease row far enough that the tap landed on the Buy-used row
        // directly above it — the "Buy used (8y)?" dialog in main run 59's
        // MARKET-DID-NOT-CLOSE screenshot is that exact miss, photographed.
        Thread.sleep(forTimeInterval: 0.8)
        return true
    }

    // MARK: Layout assertions (TD-019)

    /// The window, as the coordinate space every assertion below is relative
    /// to. Fractions rather than points: a rule written in points is a rule
    /// that only holds on the device it was written on.
    /// Wait until an element has stopped moving, then report whether it did.
    ///
    /// A coordinate tap resolves the element's frame and then fires at that
    /// point, so a row still carrying scroll momentum is tapped where it
    /// *was*. In this project that shows up as one specific failure: the tap
    /// aimed at "Lease" opens the **"Buy used (8y)?"** dialog, the row
    /// immediately above it — photographed in runs 59, 61 and 78, and every
    /// time with a healthy market underneath. Two consecutive frame reads
    /// that agree is enough; the poll is cheap and the alternative is a fixed
    /// sleep long enough for the worst case, which is slower and still a
    /// guess.
    @discardableResult
    func waitUntilStill(_ element: XCUIElement,
                        timeout: TimeInterval = 4) -> Bool {
        guard element.exists else { return false }
        var last = element.frame
        var agreements = 0
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.15)
            guard element.exists else { return false }
            let now = element.frame
            if abs(now.midY - last.midY) < 0.5, abs(now.midX - last.midX) < 0.5 {
                agreements += 1
                if agreements >= 2 { return true }
            } else {
                agreements = 0
            }
            last = now
        }
        return false
    }

    var window: CGRect { app.windows.firstMatch.frame }

    /// Fails when an element sits lower down the screen than it should.
    ///
    /// **This is the BUG-035 assertion.** That defect put the Network tab's
    /// section picker — the control the whole tab is navigated by — about 40%
    /// of the way down the screen with nothing above it, because a compact
    /// empty state centred in a parent it did not fill and `safeAreaInset`
    /// then anchored to the content's top edge.
    ///
    /// Everything that existed at the time passed: it compiled, it parsed, 412
    /// Core tests were green, and the UI smoke test found the picker and
    /// tapped it successfully. All of those ask whether an element *exists*.
    /// None asks where.
    ///
    /// Deliberately a generous fraction rather than a pixel: the aim is to
    /// catch a control that has floated into dead space, not to freeze a
    /// layout. A test that fails on every intentional nudge gets disabled.
    func assertNear(_ element: XCUIElement, top fraction: CGFloat,
                    _ what: String,
                    file: StaticString = #filePath, line: UInt = #line) {
        guard element.exists else {
            XCTFail("\(what) does not exist, so its position cannot be checked",
                    file: file, line: line)
            return
        }
        let limit = window.minY + window.height * fraction
        let actual = element.frame.minY
        if actual > limit {
            capture(Self.logPrefix + "LAYOUT-\(what)")
            let percent = Int(((actual - window.minY) / window.height) * 100)
            XCTFail("""
                \(what) starts \(percent)% down the screen; it should be within \
                the top \(Int(fraction * 100))%. This is the BUG-035 shape: a \
                control floating in dead space. Screenshot attached.
                """, file: file, line: line)
        }
    }

    /// Fails when `lower` is not below `upper`. Reading order as a rule,
    /// which survives any device size.
    func assertBelow(_ lower: XCUIElement, _ upper: XCUIElement,
                     _ what: String,
                     file: StaticString = #filePath, line: UInt = #line) {
        guard lower.exists, upper.exists else {
            XCTFail("\(what): both elements must exist to compare them",
                    file: file, line: line)
            return
        }
        XCTAssertGreaterThan(lower.frame.minY, upper.frame.minY,
                             "\(what) is not below what it should follow",
                             file: file, line: line)
    }

    /// Fails when two related elements have drifted far apart — the other
    /// half of BUG-035, where the empty-state card sat a long way under the
    /// picker that introduced it.
    func assertClose(_ a: XCUIElement, _ b: XCUIElement,
                     within fraction: CGFloat, _ what: String,
                     file: StaticString = #filePath, line: UInt = #line) {
        guard a.exists, b.exists else {
            XCTFail("\(what): both elements must exist", file: file, line: line)
            return
        }
        let gap = abs(b.frame.minY - a.frame.maxY)
        let limit = window.height * fraction
        if gap > limit {
            capture(Self.logPrefix + "GAP-\(what)")
            XCTFail("""
                \(what): \(Int(gap)) pt of empty space between two related \
                elements, more than the \(Int(fraction * 100))% of the screen \
                allowed. Screenshot attached.
                """, file: file, line: line)
        }
    }

    /// Fails when an element is hidden behind the tab bar — visible to a
    /// query, invisible to a player.
    func assertNotUnderTabBar(_ element: XCUIElement, _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let tabBar = app.tabBars.firstMatch
        guard element.exists, tabBar.exists else { return }
        if element.frame.midY > tabBar.frame.minY {
            capture(Self.logPrefix + "OBSCURED-\(what)")
            XCTFail("\(what) sits under the tab bar and cannot be tapped",
                    file: file, line: line)
        }
    }

    /// Tap something only if it is still there and still tappable.
    ///
    /// `if element.exists { element.tap() }` is a race, and it lost: the
    /// market sheet dismisses itself on a successful lease, so `Done` existed
    /// when it was asked and was gone a frame later — "Failed to tap Done: No
    /// matches found". The settle lets a dismissal finish before the question
    /// is asked, and `isHittable` re-queries rather than trusting the earlier
    /// answer.
    @discardableResult
    func tapIfPresent(_ element: XCUIElement,
                      settle: TimeInterval = 0.6) -> Bool {
        Thread.sleep(forTimeInterval: settle)
        guard element.exists, element.isHittable else { return false }
        element.tap()
        return true
    }

    /// Lease the first aircraft the market will sell this airline, and prove
    /// the sheet closed behind it.
    ///
    /// One implementation for both journeys that need an aircraft. It was two,
    /// and they drifted: one failed on a `Done` that had already dismissed
    /// itself, the other sailed past a sheet that had *not* dismissed and then
    /// reported that the routes board was missing — from behind the market,
    /// which was still covering it.
    ///
    /// The confirmation is a `confirmationDialog`, which is an action sheet on
    /// a phone, so it is queried through `app.sheets` rather than by label
    /// against the whole app — the market row is also called "Lease".
    @discardableResult
    func leaseAnAircraft() -> Bool {
        // Hide what the era cannot buy, so the first lease action on screen
        // belongs to an aircraft this airline is allowed to take.
        let eraFilter = app.switches["Hide what this era cannot buy"]
        if eraFilter.waitForExistence(timeout: 5),
           eraFilter.value as? String == "0" {
            eraFilter.tap()
        }

        let lease = app.buttons.matching(identifier: "ae-market-lease").firstMatch
        guard scrollUntil(lease, "a Lease action in the market") else { return false }

        // The dialog must be the LEASE dialog before anything is confirmed,
        // and a wrong dialog must be dismissed and the tap retried.
        //
        // Both halves are earned. Run 59 photographed a tap aimed at the
        // lease row opening a "Buy used (8y)?" dialog — a synthetic-tap miss
        // that run 61 reproduced twice even after a scroll settle, while the
        // very same helper succeeded later in the same run, so retrying is
        // sound. And on this runner's iOS 26 the dialog is an anchored
        // popover with NO Cancel button, so the only way out of a wrong one
        // is a tap outside it. The dialog is also why confirmations stay ON
        // in tests: a mis-tap with confirmations off would silently buy the
        // wrong aircraft and pass.
        let market = app.staticTexts["Aircraft market"]
        let leaseDialogTitle = app.staticTexts["Lease?"]
        let fleetRow = app.descendants(matching: .any)
            .matching(identifier: "ae-fleet-row").firstMatch
        for attempt in 1...4 {
            // Bring the row into the middle band before touching it. Every
            // mis-hit this runner has produced — the Buy-used dialog of runs
            // 59 and 61, the untappable row of run 63 — happened with the
            // row hugging the sheet's bottom edge. Small drags rather than
            // swipeUp: a full swipe is what overshot in the first place.
            var hops = 0
            while lease.exists, lease.frame.midY > window.height * 0.66,
                  hops < 4 {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                    .press(forDuration: 0.05,
                           thenDragTo: app.coordinate(
                               withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)))
                hops += 1
                Thread.sleep(forTimeInterval: 0.6)
            }
            guard lease.exists else { break }
            // Let the list stop before reading the row's position. The drag
            // above leaves momentum, and a coordinate tap fires at the frame
            // as it was when resolved — which is how run 78's first attempt
            // hit "Buy used (8y)", the row directly above this one.
            waitUntilStill(lease)
            guard lease.exists else { break }
            // A coordinate tap at the element's own centre: fires at the
            // frame wherever hit-testing disagrees, and the dialog check
            // below decides whether it landed right.
            lease.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

            if leaseDialogTitle.waitForExistence(timeout: 3) {
                // The dialog's confirm button and the market row are both
                // labelled "Lease"; the row is behind the dialog and not
                // hittable, so the hittable match — searched from the most
                // recently added — is the dialog's.
                let confirms = app.buttons.matching(
                    NSPredicate(format: "label == %@", "Lease"))
                for index in stride(from: confirms.count - 1, through: 0, by: -1) {
                    let candidate = confirms.element(boundBy: index)
                    if candidate.isHittable { candidate.tap(); break }
                }
                // The sheet dismisses itself on success — there is no Done
                // fallback any more. Blind-tapping Done has never rescued a
                // stuck sheet; in runs 62 and 63 it closed a healthy market
                // over a lease that had not happened, three times each.
                if market.waitForNonExistence(timeout: 8),
                   fleetRow.waitForExistence(timeout: 6) {
                    return true
                }
            }

            // Wrong dialog, no dialog, or a confirm that did not land.
            // Photograph the state, dismiss any popover by tapping the
            // sheet title's own coordinates (the scrim when one is up,
            // inert otherwise), and reopen the market if something closed it.
            capture(Self.logPrefix + "LEASE-ATTEMPT-\(attempt)")
            if market.exists {
                market.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                Thread.sleep(forTimeInterval: 1)
            }
            if !market.exists {
                let browse = app.buttons["Browse the market"]
                guard browse.waitForExistence(timeout: 5) else { break }
                browse.tap()
                _ = market.waitForExistence(timeout: 5)
                guard scrollUntil(lease, "the Lease action, reopened market")
                else { return false }
            }
        }

        capture(Self.logPrefix + "MARKET-DID-NOT-CLOSE")
        XCTFail("""
            No lease completed after four attempts. The attempt screenshots \
            show what each tap actually produced. Nothing after this point \
            would be testing what it claims to.
            """)
        return false
    }

    /// Open a route from the empty routes board, taking the guided first
    /// suggestion. One implementation for every journey that needs a route,
    /// for the same reason `leaseAnAircraft` is: two copies drifted once
    /// already.
    @discardableResult
    func openARoute() -> Bool {
        app.buttons["Routes"].tap()
        let openRoute = app.buttons["Open a route"]
        guard require(openRoute, "the route entry point on an empty board")
        else { return false }
        openRoute.tap()

        // The first *destination*, by its stable identifier. The previous
        // version tapped `app.cells.firstMatch`, which on this sheet is the
        // From picker: screenshots 05 and 06 of run 59 are pixel-identical,
        // because the tap selected nothing and the test then reached for a
        // button labelled "Open" that has never existed — the real label is
        // "Open this route". Neither miss failed anything until the final
        // assertion, which is what §17 calls manufactured sequence: action
        // and assertion with no causality between them.
        let destination = app.buttons
            .matching(identifier: "ae-route-destination").firstMatch
        guard require(destination, "a destination row in the route sheet")
        else { return false }
        destination.tap()

        // CAUSALITY: the commit bar only exists once a destination is
        // actually selected, so its appearance is proof the tap took.
        checkpoint("06-route-sheet-destination-picked")
        let open = app.buttons.matching(identifier: "ae-route-open").firstMatch
        guard require(open, "the commit bar after picking a destination",
                      timeout: 8) else { return false }
        if !open.isEnabled {
            capture(Self.logPrefix + "ROUTE-OPEN-BLOCKED")
            XCTFail("""
                "Open this route" is disabled for the top-ranked suggestion. \
                The sheet prints Core's reason above the button — the \
                screenshot carries it. The guided first-route path does not \
                connect, which is a product finding, not a test failure.
                """)
            return false
        }
        open.tap()

        // AGREEMENT: opening a route must put one on the board.
        let emptyRoutes = app.staticTexts["No routes yet"]
        if !emptyRoutes.waitForExistence(timeout: 8) { return true }
        capture(Self.logPrefix + "ROUTE-DID-NOT-OPEN")
        XCTFail("""
            The routes board still reports "No routes yet" after Open was \
            tapped. The sheet may have dismissed without the command being \
            accepted. Screenshot attached.
            """)
        return false
    }

    // MARK: The journey's shared opening

    /// The control that opens a top-level section, wherever this width class
    /// put it.
    ///
    /// Compact width renders the shell's `TabView` as a tab bar; regular
    /// width renders it as a **sidebar**, and `app.tabBars` matches nothing
    /// at all — which is how the first iPad run in this project's history
    /// (run 60) failed both its tests with "the tab bar after founding never
    /// appeared" over a screenshot showing a perfectly healthy shell. The
    /// fallback is scoped as a plain button lookup because the sidebar rows
    /// expose themselves as buttons named by their tab title.
    /// The control that opens `title`'s section in the current snapshot, or
    /// nil if none of its shapes exist yet.
    ///
    /// Run 62 taught the second lesson here: the iPad's sidebar rows are not
    /// `buttons` either — a frame showing a perfectly healthy sidebar failed
    /// "the Home tab never appeared" because only bar-buttons and plain
    /// buttons were tried. Sidebar rows surface as cells (with the title as
    /// a static text), so the ladder now walks tab bar → button → cell →
    /// bare static text, and callers poll rather than binding to whichever
    /// rung happened to be empty at first evaluation.
    func tabButton(_ title: String) -> XCUIElement? {
        let candidates = [
            app.tabBars.buttons[title],
            app.buttons[title].firstMatch,
            app.cells.containing(.staticText, identifier: title).firstMatch,
            app.staticTexts[title].firstMatch,
        ]
        for candidate in candidates where candidate.exists { return candidate }
        return nil
    }

    /// Poll for the section control across all its shapes.
    func waitForTab(_ title: String, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let found = tabButton(title) { return found }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return nil
    }

    /// Found an airline and arrive in the shell. Every journey starts here.
    @discardableResult
    func foundAirline() -> Bool {
        // A relaunch inside one test may come back to a shell that is already
        // playing; that is a success, not a missing button.
        if waitForTab("Home", timeout: 3) != nil { return true }
        let found = app.buttons["Found Skyline Air"]
        guard require(found, "the Found button on the new-game screen") else {
            return false
        }
        found.tap()
        if waitForTab("Home", timeout: 25) != nil { return true }
        capture(Self.logPrefix + "MISSING-the shell after founding")
        XCTFail("No Home control (tab bar, button, sidebar cell or text) appeared after founding. Screenshot attached.")
        return false
    }

    /// Switch to a tab by its title.
    func openTab(_ title: String) {
        guard let button = waitForTab(title, timeout: 15) else {
            capture(Self.logPrefix + "MISSING-the \(title) tab")
            XCTFail("The \(title) tab never appeared in any shape. Screenshot attached.")
            return
        }
        button.tap()
    }
}
