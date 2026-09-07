import XCTest
import StoreKitTest
import AirlineEmpireCore
@testable import AirlineEmpire

final class StoreKitPurchaseTests: XCTestCase {
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
        await entitlements.purchase(.lifetime)
        XCTAssertTrue(entitlements.isPro)
        XCTAssertEqual(entitlements.lastOutcome, .purchased(.lifetime))
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
}
