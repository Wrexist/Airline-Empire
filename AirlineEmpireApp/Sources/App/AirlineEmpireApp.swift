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
                        // Hand the audio route back rather than holding it
                        // open behind another app (docs/AUDIO_ARCHITECTURE §9).
                        controller.feedback.applicationDidEnterBackground()
                    } else {
                        controller.feedback.applicationWillEnterForeground()
                    }
                    controller.setPumping(phase == .active)
                }
        }
    }
}
