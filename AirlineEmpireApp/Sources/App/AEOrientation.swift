import UIKit

/// The interface orientations the app allows right now. Everything is
/// free to rotate except the 3D Hub View on iPhone, which is a wide
/// dashboard over a wide diorama and opens in landscape: on a phone held
/// upright the airport shrinks to a strip between the KPI cards and the
/// timeline. iPad keeps every orientation (multitasking requires it, and
/// the hub's wide layout fits either way).
@MainActor
enum AEOrientation {
    /// Read by `AEAppDelegate`. The project lists portrait and both
    /// landscapes for iPhone; this narrows that list, never widens it.
    private(set) static var mask: UIInterfaceOrientationMask = .all
    private static var restore: UIInterfaceOrientation?

    static var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    /// The size of the app's window, which is not the screen's: an iPad in
    /// Split View, or iPhone Duo folding between its 5.4" outer and 7.6"
    /// inner display, hands the app a window of its own shape. Layout
    /// decisions read this (or a GeometryReader), never `UIScreen.main`.
    static var windowSize: CGSize {
        guard let scene = activeScene else { return .zero }
        return (scene.keyWindow ?? scene.windows.first)?.bounds.size ?? .zero
    }

    /// Turns the phone to landscape and holds it there. iPhone Duo's inner
    /// display does not honour supported orientations, so there the request
    /// is ignored and the hub lays out for the near-square window it has
    /// (`HubChromeMode`); folded to the outer display, the lock applies.
    static func lockLandscape() {
        guard isPhone, let scene = activeScene else { return }
        if mask != .landscape { restore = scene.effectiveGeometry.interfaceOrientation }
        mask = .landscape
        update(scene, to: .landscape)
    }

    /// Lets go, and turns back to the orientation the player came from.
    static func unlock() {
        guard isPhone, mask != .all, let scene = activeScene else { return }
        mask = .all
        let back: UIInterfaceOrientationMask
        switch restore {
        case .portrait, .portraitUpsideDown: back = .portrait
        case .landscapeLeft: back = .landscapeLeft
        case .landscapeRight: back = .landscapeRight
        default: back = .portrait
        }
        restore = nil
        update(scene, to: back)
    }

    private static func update(_ scene: UIWindowScene, to orientations: UIInterfaceOrientationMask) {
        for window in scene.windows {
            var vc = window.rootViewController
            while let current = vc {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                vc = current.presentedViewController
            }
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in
            // Refused (a rotation lock on iPad, say): the layout adapts to
            // whatever shape it gets.
        }
    }

    private static var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

/// Only here to answer the orientation question per window.
final class AEAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { AEOrientation.mask }
    }
}
