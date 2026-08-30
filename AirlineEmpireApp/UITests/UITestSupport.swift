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
        lease.tap()

        // The dialog must be the LEASE dialog before anything is confirmed.
        //
        // Run 59 on main photographed why: the tap above landed on the
        // Buy-used row and a "Buy used (8y)?" dialog opened; the old code
        // then looked for a Lease button, found none, and blundered on. A
        // confirmation for the wrong action must be cancelled, not confirmed
        // and not ignored. The title is asked for by name — ConfirmableButton
        // titles the dialog "<action>?" — because on this runner's iOS 26 the
        // dialog presents as an anchored popover that `app.sheets` does not
        // reliably match.
        let leaseDialogTitle = app.staticTexts["Lease?"]
        if !leaseDialogTitle.waitForExistence(timeout: 4) {
            capture(Self.logPrefix + "WRONG-OR-NO-DIALOG")
            tapIfPresent(app.buttons["Cancel"])
            Thread.sleep(forTimeInterval: 1)
            lease.tap()
            guard leaseDialogTitle.waitForExistence(timeout: 4) else {
                XCTFail("""
                    Tapping the lease action never produced the "Lease?" \
                    confirmation, twice. Either the tap keeps landing on a \
                    different control or the dialog is not presenting. \
                    Screenshot of the first attempt attached.
                    """)
                return false
            }
        }
        // The dialog's confirm button and the market row are both labelled
        // "Lease"; the row is behind the presented dialog and not hittable,
        // so the hittable match — searched from the most recently added — is
        // the dialog's.
        let confirms = app.buttons.matching(NSPredicate(format: "label == %@", "Lease"))
        var confirmed = false
        for index in stride(from: confirms.count - 1, through: 0, by: -1) {
            let candidate = confirms.element(boundBy: index)
            if candidate.isHittable {
                candidate.tap()
                confirmed = true
                break
            }
        }
        if !confirmed { tapIfPresent(app.buttons["Lease"], settle: 0.3) }

        // The sheet dismisses itself on success. Done is the fallback for the
        // case where it did not — and if it is still there afterwards, the
        // lease did not happen and everything downstream would be nonsense.
        tapIfPresent(app.buttons["Done"])
        let market = app.staticTexts["Aircraft market"]
        if market.waitForNonExistence(timeout: 8) { return true }

        capture(Self.logPrefix + "MARKET-DID-NOT-CLOSE")
        XCTFail("""
            The aircraft market is still on screen after a lease was \
            confirmed. The command was refused without saying so, or the \
            confirmation was never tapped — either way nothing after this \
            point would be testing what it claims to. Screenshot attached.
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

    /// Found an airline and arrive in the shell. Every journey starts here.
    @discardableResult
    func foundAirline() -> Bool {
        // A relaunch inside one test may come back to a shell that is already
        // playing; that is a success, not a missing button.
        if app.tabBars.buttons["Home"].waitForExistence(timeout: 3) { return true }
        let found = app.buttons["Found Skyline Air"]
        guard require(found, "the Found button on the new-game screen") else {
            return false
        }
        found.tap()
        return require(app.tabBars.buttons["Home"], "the tab bar after founding")
    }

    /// Switch to a tab by its title.
    func openTab(_ title: String) {
        let button = app.tabBars.buttons[title]
        require(button, "the \(title) tab")
        button.tap()
    }
}
