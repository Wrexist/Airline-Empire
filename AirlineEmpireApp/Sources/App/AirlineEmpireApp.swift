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
                .onChange(of: scenePhase) { _, phase in
                    // Scene-phase autosave (docs/PERSISTENCE_ARCHITECTURE §4).
                    if phase == .background || phase == .inactive {
                        controller.saveOnBackground()
                    }
                    controller.setPumping(phase == .active)
                }
        }
    }
}
