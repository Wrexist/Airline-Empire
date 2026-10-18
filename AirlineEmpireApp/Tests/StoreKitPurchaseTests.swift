import XCTest
import StoreKitTest
import AirlineEmpireCore
@testable import AirlineEmpire

final class StoreKitPurchaseTests: XCTestCase {
    override func setUp() {
        super.setUp()
        executionTimeAllowance = 120
    }

    @MainActor
    func testRealStoreKitLifetimePurchaseAndRestore() async throws {
        let store = try SKTestSession(configurationFileNamed: "AirlineEmpire")
        store.resetToDefaultState()
        store.disableDialogs = true
        store.clearTransactions()
        defer { store.clearTransactions(); store.resetToDefaultState() }
        let entitlements = Entitlements(arguments: ["-AEUITestFree"])
        await entitlements.start()
        XCTAssertFalse(entitlements.isPro)
        XCTAssertEqual(entitlements.products.count, ProProduct.allCases.count)
        _ = try XCTUnwrap(entitlements.products[.lifetime], "StoreKit did not load the lifetime product")
        await entitlements.purchase(.lifetime)
        XCTAssertTrue(entitlements.isPro)
        XCTAssertEqual(entitlements.lastOutcome, .purchased(.lifetime))
        // A stale offer must close when verified ownership is refreshed,
        // including ownership obtained while the app was suspended.
        entitlements.presentedGate = .direct
        await entitlements.refreshEntitlement()
        XCTAssertNil(entitlements.presentedGate)
        let restored = Entitlements(arguments: ["-AEUITestFree"])
        await restored.start()
        await restored.restore()
        XCTAssertTrue(restored.isPro)
        XCTAssertEqual(restored.lastOutcome, .restored)
    }

    @MainActor
    func testFailedPurchaseShowsErrorWithoutGrantingPro() async throws {
        let store = try SKTestSession(configurationFileNamed: "AirlineEmpire")
        store.resetToDefaultState()
        store.disableDialogs = true
        store.clearTransactions()
        defer { store.clearTransactions(); store.resetToDefaultState() }
        store.failTransactionsEnabled = true
        let entitlements = Entitlements(arguments: ["-AEUITestFree"])
        await entitlements.start()
        _ = try XCTUnwrap(entitlements.products[.lifetime], "StoreKit did not load the lifetime product")
        await entitlements.purchase(.lifetime)
        XCTAssertFalse(entitlements.isPro)
        guard case .failed = entitlements.lastOutcome else { XCTFail("Missing purchase error"); return }
    }

    @MainActor
    func testPendingApprovalDoesNotGrantProEarly() async throws {
        let store = try SKTestSession(configurationFileNamed: "AirlineEmpire")
        store.resetToDefaultState()
        store.disableDialogs = true
        store.clearTransactions()
        store.askToBuyEnabled = true
        defer { store.clearTransactions(); store.resetToDefaultState() }
        let entitlements = Entitlements(arguments: ["-AEUITestFree"])
        await entitlements.start()
        _ = try XCTUnwrap(entitlements.products[.lifetime], "StoreKit did not load the lifetime product")
        await entitlements.purchase(.lifetime)
        XCTAssertEqual(entitlements.lastOutcome, .pending)
        XCTAssertFalse(entitlements.isPro)
    }

    @MainActor
    func testExpiredSubscriptionReturnsToFree() async throws {
        let store = try SKTestSession(configurationFileNamed: "AirlineEmpire")
        store.resetToDefaultState()
        store.disableDialogs = true
        store.clearTransactions()
        defer { store.clearTransactions(); store.resetToDefaultState() }
        let entitlements = Entitlements(arguments: ["-AEUITestFree"])
        await entitlements.start()
        _ = try XCTUnwrap(entitlements.products[.weekly], "StoreKit did not load the weekly product")
        await entitlements.purchase(.weekly)
        XCTAssertTrue(entitlements.isPro)
        try store.expireSubscription(productIdentifier: ProProduct.weekly.rawValue)
        for _ in 0..<50 {
            await entitlements.refreshEntitlement()
            if !entitlements.isPro { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(entitlements.isPro)
    }

    /// A launch with no network has no products, and renewal state used to
    /// be read only through a loaded product — so a subscriber in billing
    /// grace lost Pro offline. The state must come from the subscription
    /// group itself. Turning auto-renew off is the observable stand-in:
    /// only the group's status can say the subscription will not renew.
    @MainActor
    func testRenewalStateIsReadWithoutLoadedProducts() async throws {
        let store = try SKTestSession(configurationFileNamed: "AirlineEmpire")
        store.resetToDefaultState()
        store.disableDialogs = true
        store.clearTransactions()
        defer { store.clearTransactions(); store.resetToDefaultState() }
        let buyer = Entitlements(arguments: ["-AEUITestFree"])
        await buyer.start()
        _ = try XCTUnwrap(buyer.products[.weekly], "StoreKit did not load the weekly product")
        await buyer.purchase(.weekly)
        XCTAssertTrue(buyer.isPro)
        let purchase = try XCTUnwrap(store.allTransactions().last {
            $0.productIdentifier == ProProduct.weekly.rawValue
        })
        try store.disableAutoRenewForTransaction(identifier: purchase.identifier)

        // A second owner that never loads products, as at an offline launch.
        let offline = Entitlements(arguments: ["-AEUITestFree"])
        for _ in 0..<50 {
            await offline.refreshEntitlement()
            if offline.isPro, !offline.entitlement.willRenew { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(offline.products.isEmpty)
        XCTAssertTrue(offline.isPro)
        XCTAssertFalse(offline.entitlement.willRenew,
                       "Renewal state must be read from the subscription group, not a loaded product")
    }
}
