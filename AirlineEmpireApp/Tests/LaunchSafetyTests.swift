import XCTest
import AirlineEmpireCore
@testable import AirlineEmpire

final class LaunchSafetyTests: XCTestCase {
    @MainActor
    private func waitForGame(_ controller: GameController) async throws {
        for _ in 0..<250 {
            if controller.snapshot?.playerAirline != nil { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Campaign did not finish loading")
    }

    @MainActor
    func testCampaignsRetainTheirSlotsAcrossSaveQuitAndLoad() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = GameController(savesDirectory: root)
        controller.startNewGame(airlineName: "First", home: "ARN", seed: 1, scenario: "founder")
        try await waitForGame(controller)
        let first = try XCTUnwrap(controller.activeSaveSlot)
        let firstSaved = await controller.saveAndQuit()
        XCTAssertTrue(firstSaved)
        XCTAssertEqual(controller.lastSessionReport?.airlineName, "First")
        XCTAssertEqual(controller.lastSessionReport?.flights, 0)
        controller.startNewGame(airlineName: "Second", home: "OSL", seed: 2, scenario: "founder")
        try await waitForGame(controller)
        let second = try XCTUnwrap(controller.activeSaveSlot)
        XCTAssertNotEqual(first, second)
        let secondSaved = await controller.saveAndQuit()
        XCTAssertTrue(secondSaved)
        XCTAssertEqual(controller.lastSessionReport?.airlineName, "Second")
        XCTAssertEqual(controller.lastSessionReport?.aircraftChange, 0)
        controller.loadGame(slot: first)
        try await waitForGame(controller)
        XCTAssertEqual(controller.activeSaveSlot, first)
        XCTAssertEqual(controller.snapshot?.playerAirline?.name, "First")
        let loadedSaved = await controller.saveAndQuit()
        XCTAssertTrue(loadedSaved)
        XCTAssertEqual(Set(controller.availableSlots().map(\.slot)), Set([first, second]))
        let manager = SaveManager(store: FileSaveStore(rootDirectory: root))
        XCTAssertEqual(try manager.load(slot: second).state.playerAirline?.name, "Second")
    }

    @MainActor
    func testFailedSaveAndQuitRetainsLiveGameAndCanRetry() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("saves")
        try Data("occupied by a file".utf8).write(to: root)
        let controller = GameController(savesDirectory: root)
        controller.startNewGame(airlineName: "Survivor", home: "ARN", seed: 3, scenario: "founder")
        try await waitForGame(controller)
        let slot = controller.activeSaveSlot
        let failed = await controller.saveAndQuit()
        XCTAssertFalse(failed)
        XCTAssertNil(controller.lastSessionReport, "A failed save must not show a saved-session recap")
        XCTAssertTrue(controller.hasGame)
        XCTAssertEqual(controller.activeSaveSlot, slot)
        guard case .failed = controller.lastSaveOutcome else { XCTFail("Missing save error"); return }
        try FileManager.default.removeItem(at: root)
        let retried = await controller.saveAndQuit()
        XCTAssertTrue(retried)
        XCTAssertEqual(controller.lastSessionReport?.airlineName, "Survivor")
        XCTAssertFalse(controller.hasGame)
    }

    @MainActor
    func testUnrelatedUITestFlagsDoNotGrantPro() {
        let entitlements = Entitlements(arguments: ["-AEUITestDarkAppearance"])
        XCTAssertFalse(entitlements.isPro)
        XCTAssertTrue(Entitlements(arguments: ["-AEUITestPro"]).isPro)
    }

    @MainActor
    func testExportImportPreservesCampaignAndRejectsCorruptFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = GameController(savesDirectory: root)
        controller.startNewGame(airlineName: "Portable", home: "ARN", seed: 8, scenario: "founder")
        try await waitForGame(controller)
        let originalSlot = try XCTUnwrap(controller.activeSaveSlot)
        let document = try await controller.exportCampaign()
        let exported = root.appendingPathComponent("export.aesave")
        try document.data.write(to: exported)
        let saved = await controller.saveAndQuit()
        XCTAssertTrue(saved)
        XCTAssertThrowsError(try controller.importCampaign(from: exported, access: .free))
        try controller.importCampaign(from: exported, access: .pro)
        try await waitForGame(controller)
        XCTAssertEqual(controller.snapshot?.playerAirline?.name, "Portable")
        XCTAssertNotEqual(controller.activeSaveSlot, originalSlot)
        let importedSaved = await controller.saveAndQuit()
        XCTAssertTrue(importedSaved)
        try Data("not a campaign".utf8).write(to: exported)
        XCTAssertThrowsError(try controller.importCampaign(from: exported, access: .pro))
        XCTAssertEqual(controller.availableSlots().count, 2)
    }
}
