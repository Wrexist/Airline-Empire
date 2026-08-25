import Foundation
import Testing
@testable import AirlineEmpireCore

@Suite("Schedule queue")
struct ScheduleQueueTests {
    @Test func popsInDueOrder() {
        var queue = ScheduleQueue()
        queue.schedule(.wake(label: "late"), at: SimTime(rawMinutes: 300))
        queue.schedule(.wake(label: "early"), at: SimTime(rawMinutes: 100))
        queue.schedule(.wake(label: "middle"), at: SimTime(rawMinutes: 200))

        let due = queue.popDue(at: SimTime(rawMinutes: 250))
        #expect(due.map(\.kind) == [.wake(label: "early"), .wake(label: "middle")])
        #expect(queue.entries.count == 1)
    }

    @Test func tiesResolveByInsertionOrder() {
        var queue = ScheduleQueue()
        for label in ["a", "b", "c"] {
            queue.schedule(.wake(label: label), at: SimTime(rawMinutes: 100))
        }
        let due = queue.popDue(at: SimTime(rawMinutes: 100))
        #expect(due.map(\.kind) == [.wake(label: "a"), .wake(label: "b"), .wake(label: "c")])
    }

    @Test func nothingDueReturnsEmpty() {
        var queue = ScheduleQueue()
        queue.schedule(.wake(label: "x"), at: SimTime(rawMinutes: 500))
        #expect(queue.popDue(at: SimTime(rawMinutes: 499)).isEmpty)
        #expect(queue.entries.count == 1)
    }

    @Test func entryDueExactlyNowFires() {
        var queue = ScheduleQueue()
        queue.schedule(.wake(label: "now"), at: SimTime(rawMinutes: 45))
        #expect(queue.popDue(at: SimTime(rawMinutes: 45)).count == 1)
    }

    @Test func codableRoundTripPreservesOrderAndSequence() throws {
        var queue = ScheduleQueue()
        queue.schedule(.wake(label: "b"), at: SimTime(rawMinutes: 100))
        queue.schedule(.wake(label: "a"), at: SimTime(rawMinutes: 100))
        _ = queue.popDue(at: SimTime(rawMinutes: 0))

        let data = try JSONEncoder().encode(queue)
        var restored = try JSONDecoder().decode(ScheduleQueue.self, from: data)
        #expect(restored == queue)

        // Sequence numbering continues after restore — new entries with the
        // same due time still order after old ones.
        restored.schedule(.wake(label: "c"), at: SimTime(rawMinutes: 100))
        let due = restored.popDue(at: SimTime(rawMinutes: 100))
        #expect(due.map(\.kind) == [.wake(label: "b"), .wake(label: "a"), .wake(label: "c")])
    }

    @Test func manyEntriesStayWellOrdered() {
        var queue = ScheduleQueue()
        var rng = RNGState(worldSeed: 9)
        for i in 0..<500 {
            queue.schedule(.wake(label: "\(i)"),
                           at: SimTime(rawMinutes: Int64(rng.int("t", in: 0...10_000))))
        }
        #expect(queue.isWellOrdered)
        var last = SimTime(rawMinutes: -1)
        var popped = 0
        for time in stride(from: Int64(0), through: 10_000, by: 500) {
            for entry in queue.popDue(at: SimTime(rawMinutes: time)) {
                #expect(entry.due >= last || entry.due == last)
                last = max(last, entry.due)
                popped += 1
            }
        }
        #expect(popped == 500)
    }
}

@Suite("Command serialization")
struct CommandCodingTests {
    @Test func envelopeRoundTripsThroughRegistry() throws {
        var registry = CommandRegistry()
        registry.register(ScheduleWakeCommand.self)

        let original = ScheduleWakeCommand(label: "delivery", at: SimTime(rawMinutes: 720))
        let data = try JSONEncoder().encode(CommandEnvelope(original))

        let decoder = JSONDecoder()
        decoder.userInfo[CommandRegistry.userInfoKey] = registry
        let envelope = try decoder.decode(CommandEnvelope.self, from: data)
        #expect(envelope.name == "scheduleWake")
        #expect(envelope.command as? ScheduleWakeCommand == original)
    }

    @Test func unknownCommandNameFailsCleanly() throws {
        let registry = CommandRegistry() // nothing registered
        let data = try JSONEncoder().encode(
            CommandEnvelope(ScheduleWakeCommand(label: "x", at: SimTime(rawMinutes: 10))))
        let decoder = JSONDecoder()
        decoder.userInfo[CommandRegistry.userInfoKey] = registry
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(CommandEnvelope.self, from: data)
        }
    }
}
