import Foundation
import Testing
@testable import AirlineEmpireCore

/// The campaign record: the bounded, dated log of completed work. It must be
/// recorded by the system as things happen, bounded forever, and lifted into a
/// save that never had one without inventing anything.
@Suite("Campaign record")
struct CampaignRecordTests {
    private func market() throws -> (SimulationEngine, AirlineID, ContentCatalog) {
        let (engine, airline, _) = try DemandFixtures.market(fare: Money.dollars(129))
        let catalog = try DemandFixtures.anchorCatalog()
        return (engine, airline, catalog)
    }

    @Test func notesAreBoundedAndOldestFirst() {
        var progression = ProgressionState()
        let limit = ProgressionState.recordLimit
        for index in 0..<(limit + 5) {
            progression.note(.milestone("m\(index)"),
                             at: SimTime(rawMinutes: Int64(index)))
        }
        #expect(progression.record.count == limit)
        // The oldest five fell off; the rest survived in order.
        guard case .milestone(let first) = progression.record.first?.kind else {
            Issue.record("expected a milestone at the front")
            return
        }
        #expect(first == "m5")
        guard case .milestone(let last) = progression.record.last?.kind else {
            Issue.record("expected a milestone at the end")
            return
        }
        #expect(last == "m\(limit + 4)")
    }

    @Test func eraSinceReadsTheLatestAdvance() {
        var progression = ProgressionState()
        #expect(progression.eraSince == nil)
        progression.note(.milestone("firstFlight"), at: SimTime(rawMinutes: 100))
        progression.note(.eraAdvanced(.regional), at: SimTime(rawMinutes: 500))
        progression.note(.capability(.fuelHedging), at: SimTime(rawMinutes: 900))
        #expect(progression.eraSince == SimTime(rawMinutes: 500))
    }

    @Test func theSystemRecordsAFirstFlight() throws {
        let (engine, airline, catalog) = try market()
        #expect(engine.state.progression.record.isEmpty)
        engine.advance(ticks: Fixtures.ticksPerDay * 2)
        let record = engine.state.progression.record
        #expect(!record.isEmpty)
        #expect(record.contains { moment in
            if case .milestone("firstFlight") = moment.kind { return true }
            return false
        }, "A completed flight must be logged")
        let model = try #require(engine.state.progressionModel(catalog: catalog))
        #expect(model.record == record)
        #expect(model.counters.flightsCompleted > 0)
    }

    @Test func theModelNamesWhatTheNextEraUnlocks() throws {
        let catalog = try DemandFixtures.anchorCatalog()
        let state = Fixtures.newState()
        let model = try #require(state.progressionModel(catalog: catalog))
        #expect(model.era == .startup)
        #expect(model.nextEra == .regional)
        #expect(model.nextEraUnlocks == [.largeNarrowbody])
        #expect(model.record.isEmpty)
        #expect(model.eraSince == nil)
    }

    @Test func aSaveWithoutARecordMigratesToEmpty() throws {
        let state = Fixtures.newState(seed: 707)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var tree = try JSONSerialization.jsonObject(with: encoder.encode(state))
            as! [String: Any]
        var progression = tree["progression"] as! [String: Any]
        progression["record"] = nil
        progression["milestones"] = ["firstFlight"]
        tree["progression"] = progression

        let payload = try JSONSerialization.data(withJSONObject: tree)
        let envelope = SaveEnvelope(formatVersion: 13, contentVersion: "0",
                                    savedAtTick: 0, payload: payload)
        let envelopeEncoder = JSONEncoder()
        envelopeEncoder.outputFormatting = [.sortedKeys]
        let restored = try JSONSaveCodec()
            .decode(try envelopeEncoder.encode(envelope))

        #expect(restored.progression.record.isEmpty)
        #expect(restored.progression.hasMilestone("firstFlight"))
    }

    @Test func theRecordSurvivesSaveLoad() throws {
        let (engine, airline, _) = try market()
        engine.advance(ticks: Fixtures.ticksPerDay * 2)
        let before = engine.state.progression.record
        #expect(!before.isEmpty)

        let data = try JSONSaveCodec().encode(engine.state)
        let restored = try JSONSaveCodec().decode(data)
        #expect(restored.progression.record == before)
        #expect(restored.progression.eraSince == engine.state.progression.eraSince)
        _ = airline
    }
}
