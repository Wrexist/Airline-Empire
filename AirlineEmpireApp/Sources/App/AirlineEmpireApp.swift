import SwiftUI
import AirlineEmpireCore

@main
struct AirlineEmpireApp: App {
    @State private var controller = GameController()
    /// The other half of the composition root. Owned here for the same reason
    /// `controller` is: it must outlive every screen, and exactly one of it
    /// must exist — two `Entitlements` would mean two transaction listeners
    /// racing to finish the same purchase.
    @State private var entitlements = Entitlements()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(controller)
                .environment(entitlements)
                // The controller owns feedback because it is the composition
                // root and because it is the only object that knows when a
                // game begins, ends, or publishes a tick — which is all three
                // of the moments audio cares about.
                .environment(\.feedback, controller.feedback)
                .task {
                    // UI tests only: open a save the engine wrote, so the
                    // late game can be photographed (AE-037 COMP-07).
                    controller.loadFixtureIfRequested()
                    // Starts the transaction listener and loads prices. Runs
                    // after the fixture load, not before: a first launch has
                    // to reach a playable screen whether or not the App Store
                    // answers, and this awaits the network.
                    await entitlements.start()
                }
                // Keeps the clock's ceiling in step with what the player owns.
                // `initial: true` for the same reason the scene phase below
                // uses it: the first value is the one that matters most, and
                // `onChange` does not deliver it.
                .onChange(of: entitlements.access, initial: true) { _, access in
                    controller.eraCeiling = access.eraCeiling
                }
                // `initial: true` is load-bearing, and it is BUG-040's fix.
                // `onChange` does not fire for the value that is already
                // there: when the scene attaches already `.active`, the
                // change never comes, `setPumping` is never called, and the
                // game launches frozen — the speed control responds, the
                // world does not. Run 64 photographed it: an aircraft
                // assigned to a route, 16× selected, and the clock still at
                // day one, 00:00, two real minutes later. Whether a launch
                // hits it depends on whether `.active` lands before or after
                // this modifier attaches, which is a race no player should
                // be on the wrong side of.
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Scene-phase autosave (docs/PERSISTENCE_ARCHITECTURE §4).
                    if phase == .background || phase == .inactive {
                        controller.saveOnBackground()
                    }
                    // Only a real background hands the audio route back
                    // (docs/AUDIO_ARCHITECTURE §9). `.inactive` is every
                    // notification banner, control centre pull and app
                    // switcher glance, and tearing the ambience down for each
                    // of those made the game audibly stutter at the moments
                    // the player had not left it.
                    if phase == .background {
                        controller.feedback.applicationDidEnterBackground()
                    } else if phase == .active {
                        controller.feedback.applicationWillEnterForeground()
                    }
                    controller.setPumping(phase == .active)
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    controller.feedback.prepare()
                    // Ownership may have changed on another device while
                    // suspended. Refresh before deciding whether to offer Pro.
                    await entitlements.refreshEntitlement()
                    guard !Task.isCancelled else { return }
                    if controller.snapshot?.progression.hasMilestone("firstFlight") == true {
                        entitlements.nudgeIfDue()
                    }
                }
        }
    }
}
