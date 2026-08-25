/// Deterministic future-work queue (the kernel's "basic scheduling").
/// Entries are pure data (Codable) so scheduling survives saves; ties on due
/// time resolve by insertion sequence, so behavior is order-stable.
///
/// The kernel fires due entries at the start of each tick and emits their
/// events; later phases add `ScheduledKind` cases (deliveries, event
/// resolutions) that their systems react to.
public struct ScheduleQueue: Equatable, Codable, Sendable {
    public struct Entry: Equatable, Codable, Sendable {
        public let due: SimTime
        public let sequence: Int64
        public let kind: ScheduledKind
    }

    /// Kept sorted by (due, sequence).
    public private(set) var entries: [Entry]
    private var nextSequence: Int64

    public init() {
        entries = []
        nextSequence = 1
    }

    public mutating func schedule(_ kind: ScheduledKind, at due: SimTime) {
        let entry = Entry(due: due, sequence: nextSequence, kind: kind)
        nextSequence += 1
        // Binary insertion keeps pops O(1) amortized off the front batch and
        // insertion O(n) worst case — fine for the bounded queues we expect;
        // revisit with evidence (docs/TECHNICAL_STANDARDS.md §6).
        var low = 0
        var high = entries.count
        while low < high {
            let mid = (low + high) / 2
            if (entries[mid].due, entries[mid].sequence) < (due, entry.sequence) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        entries.insert(entry, at: low)
    }

    /// Removes and returns every entry due at or before `time`, in order.
    public mutating func popDue(at time: SimTime) -> [Entry] {
        var count = 0
        while count < entries.count && entries[count].due <= time {
            count += 1
        }
        guard count > 0 else { return [] }
        let due = Array(entries[..<count])
        entries.removeFirst(count)
        return due
    }

    public var isWellOrdered: Bool {
        guard !entries.isEmpty else { return true }
        for i in 1..<entries.count {
            let a = entries[i - 1]
            let b = entries[i]
            if (a.due, a.sequence) >= (b.due, b.sequence) { return false }
        }
        return true
    }
}

/// Grows per phase; cases never repurposed.
public enum ScheduledKind: Equatable, Codable, Sendable {
    /// Generic labeled wake; fires a `.wakeFired` event.
    case wake(label: String)
}
