import SwiftUI
import AirlineEmpireCore

@main
struct AirlineEmpireApp: App {
    @State private var controller = GameController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(controller)
                // The controller owns feedback because it is the composition
                // root and because it is the only object that knows when a
                // game begins, ends, or publishes a tick — which is all three
                // of the moments audio cares about.
                .environment(\.feedback, controller.feedback)
                .task {
                    // Decoding the palette is milliseconds, but it is still
                    // not work to do while the player waits for a screen.
                    controller.feedback.prepare()
                }
                .onChange(of: scenePhase) { _, phase in
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
        }
    }
}
