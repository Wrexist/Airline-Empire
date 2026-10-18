import Foundation

/// What this device can afford for the hub (docs/GAME_AUDIT_2026-10-18.md
/// §4): the memory class, read once, and whether the device is asking to
/// rest. Both are cheap, so the scene may ask about once a second.
enum HubDevice {
    /// Under 4 GB: the A12 and A13 iPhones (XS, XR, 11, SE 2) have 3 GB and
    /// report about 3.0 billion bytes; every 4 GB device reports about 3.9
    /// billion, so the line sits between. Such a device skips the bloom,
    /// starts a quality step down and animates fewer people.
    /// `-AEHubLowMemory` forces it, to see the small-device hub anywhere.
    static let isLowMemory: Bool = ProcessInfo.processInfo.physicalMemory < 3_500_000_000
        || ProcessInfo.processInfo.arguments.contains("-AEHubLowMemory")

    /// Hot, or saving power: nothing moves that does not have to (the idle
    /// turntable stays still).
    static var shouldRest: Bool {
        let info = ProcessInfo.processInfo
        switch info.thermalState {
        case .serious, .critical: return true
        default: return info.isLowPowerModeEnabled
        }
    }
}
