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

    /// Launch in a named appearance.
    ///
    /// The simulator rather than a trait override inside the process, so what
    /// is captured is what a player changing Appearance in Settings would get,
    /// including the chrome the app does not draw.
    func launch(appearance: XCUIDevice.Appearance) {
        if Self.currentAppearance != appearance {
            XCUIDevice.shared.appearance = appearance
            Self.currentAppearance = appearance
            // Let the switch finish. Launching into a system-wide appearance
            // animation is what produced the two failures above; this is a
            // settle, not a guess at a race.
            Thread.sleep(forTimeInterval: 3)
        }
        app.launch()
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

    // MARK: The journey's shared opening

    /// Found an airline and arrive in the shell. Every journey starts here.
    @discardableResult
    func foundAirline() -> Bool {
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
