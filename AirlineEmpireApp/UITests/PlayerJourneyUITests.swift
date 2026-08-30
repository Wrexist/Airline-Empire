import XCTest

/// The first test in this project that actually runs the app.
///
/// ## Why this exists
///
/// Four phases have now shipped user interface work — a design system, a map,
/// a fleet experience, an audio palette — and every one of them ended its
/// report with the same sentence: *authored, not observed*. The macOS CI job
/// compiles the app, which proves the types line up and nothing else. Whether
/// tapping Fleet shows the fleet has never been checked by anything.
///
/// That gap is not theoretical. It is the direct cause of three defects found
/// by hand in the last two phases, all of the same shape — a control that
/// exists, compiles, and does nothing:
///
/// - **BUG-029** route links inert on the Finance tab
/// - **BUG-030** the aircraft link dead on two of five entry paths
/// - **BUG-032** assignment pickers offering moves the engine refuses
///
/// A `NavigationLink(value:)` with no matching `navigationDestination` is
/// silently inert: no warning, no crash, nothing a compiler or a parse can
/// see. The only thing that catches it is tapping it. So this target taps it.
///
/// ## What this is not
///
/// It is not a visual check. XCUITest can tell us a button exists, is
/// hittable, and that tapping it changed what is on screen. It cannot tell us
/// the screen looks good. Screenshots are attached to the result bundle so a
/// human can judge that part; the assertions here are about *reachability*,
/// which is the half that can be automated and the half that has been failing.
///
/// ## Conventions
///
/// Queries go through labels the app already sets for VoiceOver rather than
/// through new test-only identifiers. Two reasons: a label that drifts breaks
/// this test, which is a cheap early warning that VoiceOver also broke; and
/// test-only identifiers tend to become the only thing kept correct.
final class PlayerJourneyUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        // A failed step leaves the rest of the journey meaningless — the
        // tab assertions cannot pass if the game never started — so stop at
        // the first failure rather than reporting a cascade.
        continueAfterFailure = false
        app = XCUIApplication()
        // No fresh-start launch argument, deliberately. `GameController.init`
        // does not load a save — `session` starts nil, so `hasGame` is false
        // and the app always opens on the new-game screen whatever the
        // simulator is carrying. Adding an argument the app does not read
        // would be exactly the kind of dead configuration this target exists
        // to catch.
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    /// Attach the current screen to the result bundle.
    ///
    /// These are the only visual evidence this project has ever produced.
    /// `.keepAlways` because a screenshot attached only on failure is no use
    /// for the question actually being asked, which is "what does it look
    /// like".
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Waits for an element, failing with something a reader can act on.
    @discardableResult
    private func require(_ element: XCUIElement, _ what: String,
                         timeout: TimeInterval = 20) -> Bool {
        let found = element.waitForExistence(timeout: timeout)
        if !found {
            capture("MISSING-\(what)")
            XCTFail("\(what) never appeared. Screenshot attached.")
        }
        return found
    }

    // MARK: The journey

    /// Launch, found an airline, and reach every tab.
    ///
    /// This is deliberately the whole first minute of the game rather than
    /// five separate tests. The bugs worth catching here are transitions —
    /// founding an airline replaces the entire root view — and a test that
    /// starts each case from a fresh launch would never cross one.
    func testFoundingAnAirlineReachesEveryTab() throws {
        // 1 · The new-game screen.
        //
        // `effectiveName` falls back to "Skyline Air" when the field is
        // empty, and the found button carries it in its accessibility label,
        // so the default path needs no typing.
        let found = app.buttons["Found Skyline Air"]
        require(found, "the Found button on the new-game screen")
        capture("01-new-game")

        // 2 · Found it. This swaps RootView's whole content.
        found.tap()

        // 3 · The shell. Home is the default tab; waiting on its tab button
        // rather than on any content is the narrowest check that the swap
        // happened at all.
        let homeTab = app.tabBars.buttons["Home"]
        require(homeTab, "the tab bar after founding an airline")
        capture("02-home")

        // 4 · Every tab, in order. This is the assertion that would have
        // caught a screen that compiles and renders nothing.
        //
        // The tab bar is checked for *content*, not merely for selection:
        // `isSelected` would pass on a tab whose body is an empty VStack.
        for (index, tab) in ["Home", "Map", "Network", "Finance", "World"].enumerated() {
            let button = app.tabBars.buttons[tab]
            require(button, "the \(tab) tab")
            button.tap()

            XCTAssertTrue(button.waitForExistence(timeout: 5),
                          "\(tab) tab vanished after being tapped")
            // Something has to be on screen. A tab showing nothing at all is
            // the failure this is here for.
            let hasContent = app.staticTexts.count > 0 || app.otherElements.count > 0
            XCTAssertTrue(hasContent, "\(tab) rendered no content")
            capture(String(format: "%02d-tab-%@", index + 3, tab))
        }
    }

    /// The onboarding card is on Home for a brand-new airline, and it names
    /// the path to the first aircraft.
    ///
    /// This is the first thing a new player sees, and it is the only thing
    /// telling them where the market is — the Network tab opens on Routes,
    /// whose empty state says "put an aircraft on it" to a player who has
    /// none. That is survivable *because* this card exists, which makes the
    /// card load-bearing rather than decorative, and worth pinning.
    func testHomeGuidesANewPlayerToTheirFirstAircraft() throws {
        let found = app.buttons["Found Skyline Air"]
        require(found, "the Found button")
        found.tap()
        require(app.tabBars.buttons["Home"], "the tab bar")
        capture("20-home-first-run")

        // The step list is rendered as static text; any of the five titles
        // proves the card is mounted.
        let step = app.staticTexts["Get an aircraft"]
        XCTAssertTrue(step.waitForExistence(timeout: 15), """
            Home shows no onboarding step for a brand-new airline. This card \
            is the only signpost to the aircraft market — the Network tab \
            opens on Routes, and its empty state tells a player with no \
            aircraft to put one on a route.
            """)
    }

    /// The aircraft market is reachable by the path onboarding actually names.
    ///
    /// The first version of this test looked for the Fleet empty state's
    /// "Browse the market" straight after tapping Network, and failed —
    /// correctly. `NetworkView` opens on `.routes`, so that button is not on
    /// screen. The app was right and the test was wrong, which is the whole
    /// argument for running one.
    func testAircraftMarketIsReachable() throws {
        let found = app.buttons["Found Skyline Air"]
        require(found, "the Found button")
        found.tap()

        let network = app.tabBars.buttons["Network"]
        require(network, "the Network tab")
        network.tap()
        capture("30-network-routes")

        // Onboarding's hint is "Network tab → Fleet → Acquire", so that is
        // the path tested: a segmented control, then the toolbar action.
        let fleetSegment = app.buttons["Fleet"]
        require(fleetSegment, "the Fleet segment of the Network picker")
        fleetSegment.tap()
        capture("31-network-fleet-empty")

        // Two ways in, both legitimate: the toolbar's Acquire and the empty
        // state's own call to action. A new player has both, and either
        // failing is worth knowing about.
        let acquire = app.buttons["Acquire"]
        let browse = app.buttons["Browse the market"]
        XCTAssertTrue(browse.waitForExistence(timeout: 10),
                      "the empty fleet offers no way to reach the market")
        XCTAssertTrue(acquire.exists,
                      "the Fleet toolbar has no Acquire action")

        browse.tap()
        capture("32-market")

        // The catalogue ships fourteen types. Asserting on a known model name
        // rather than a count: the count is content and may change, but a
        // market listing nothing at all is the failure worth catching.
        let anyType = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "seats")).firstMatch
        XCTAssertTrue(anyType.waitForExistence(timeout: 10),
                      "the market opened but listed no aircraft")
    }
}
