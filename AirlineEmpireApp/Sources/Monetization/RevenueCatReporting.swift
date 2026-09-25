import Foundation
import OSLog
import RevenueCat
import StoreKit

/// RevenueCat observes purchases; StoreKit remains responsible for verified
/// access and finishing transactions. Reporting never delays an unlock.
@MainActor
enum RevenueCatReporting {
    // Public, app-scoped SDK key. Secret Apple/API credentials stay in RevenueCat.
    static let publicAPIKey = "appl_busLzewoIIaqfsHttpPkGgnJYVB"
    static let entitlementIdentifier = "airline_empire_pro"
    private static let migrationKey = "revenueCat.purchaseMigration.v1"
    private static let logger = Logger(subsystem: "com.airlineempire.game", category: "Purchases")
    private static var enabled = false
    private static var syncInFlight = false

    static func configure() {
        // Local StoreKit fixtures are not App Store receipts. Keep simulator
        // tests out of the live project; validate RevenueCat with TestFlight.
        #if !targetEnvironment(simulator)
        guard !enabled else { return }
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-AEUITest") }),
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        #endif
        Purchases.logLevel = .warn
        Purchases.configure(with: Configuration.Builder(withAPIKey: publicAPIKey)
            .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
            .build())
        enabled = true
        #endif
    }

    static func record(_ result: StoreKit.VerificationResult<StoreKit.Transaction>) {
        guard enabled, case .verified = result else { return }
        Task {
            do {
                _ = try await Purchases.shared.recordPurchase(.success(result))
            } catch {
                // StoreKit ownership is unaffected. The SDK's transaction
                // observer and the next sync can recover failed reporting.
                logger.warning("Purchase reporting deferred; will retry on a future sync.")
                UserDefaults.standard.removeObject(forKey: migrationKey)
            }
        }
    }

    /// Migrate existing owners once, retry after failure, and sync on an
    /// explicit restore. Anonymous RevenueCat IDs require no player account.
    static func sync(force: Bool = false) {
        guard enabled, !syncInFlight,
              force || !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        syncInFlight = true
        Task {
            defer { syncInFlight = false }
            do {
                _ = try await Purchases.shared.syncPurchases()
                UserDefaults.standard.set(true, forKey: migrationKey)
            } catch {
                logger.warning("Purchase synchronization deferred; will retry on a future launch.")
            }
        }
    }
}
