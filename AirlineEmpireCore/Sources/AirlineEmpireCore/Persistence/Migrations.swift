import Foundation

/// One save-format migration step, operating on the decoded generic JSON
/// tree (docs/PERSISTENCE_ARCHITECTURE.md §5). Pure, registered in a chain,
/// unit-tested against a fixture of its source version.
public protocol SaveMigration: Sendable {
    /// The format version this step upgrades FROM (to fromVersion + 1).
    var fromVersion: Int { get }
    func migrate(_ payload: inout [String: Any]) throws
}

public struct MigrationChain: Sendable {
    private let steps: [Int: any SaveMigration]
    /// Oldest version the chain can lift to current.
    public let minimumSupportedVersion: Int

    public init(_ migrations: [any SaveMigration]) {
        var table: [Int: any SaveMigration] = [:]
        for migration in migrations {
            precondition(table[migration.fromVersion] == nil,
                         "Duplicate migration from v\(migration.fromVersion)")
            table[migration.fromVersion] = migration
        }
        self.steps = table
        // Contiguity: min supported = lowest version from which every step
        // to current exists.
        var minimum = SaveFormat.currentVersion
        while let _ = table[minimum - 1] { minimum -= 1 }
        self.minimumSupportedVersion = minimum
    }

    /// The shipping chain. Versions below `minimumSupportedVersion` are
    /// pre-release formats and refuse honestly (no public release carried
    /// them; committed fixtures start at the first supported version).
    public static let standard = MigrationChain([
        MigrationV9AddProgression(),
        MigrationV10AddLivery(),
    ])

    public func migrate(payload: [String: Any], from version: Int) throws -> [String: Any] {
        guard version >= minimumSupportedVersion else {
            throw SaveError.unsupportedVersion(version)
        }
        var current = payload
        var v = version
        while v < SaveFormat.currentVersion {
            guard let step = steps[v] else {
                throw SaveError.unsupportedVersion(version)
            }
            try step.migrate(&current)
            v += 1
        }
        return current
    }
}

/// v9 → v10: Phase 12 added the `progression` slice; older saves get the
/// fresh-start default (a v9 world had no progression to lose).
public struct MigrationV9AddProgression: SaveMigration {
    public let fromVersion = 9

    public init() {}

    public func migrate(_ payload: inout [String: Any]) throws {
        guard payload["progression"] == nil else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ProgressionState())
        payload["progression"] = try JSONSerialization.jsonObject(with: data)
    }
}

/// v10 → v11: airlines gained a `livery`. v10 is the first format that
/// reached a real device (TestFlight 1.0.0), so this one genuinely runs on
/// somebody's save rather than being a formality.
///
/// The player keeps the default colour — it is the accent their whole game so
/// far has been painted in, and changing it under them would be a strange
/// thing for a bug-fix build to do. Rivals are coloured deterministically by
/// their position in the airline table, so the same save reopens the same
/// world rather than reshuffling every carrier's colour on each load.
public struct MigrationV10AddLivery: SaveMigration {
    public let fromVersion = 10

    public init() {}

    public func migrate(_ payload: inout [String: Any]) throws {
        guard var airlines = payload["airlines"] as? [String: Any] else { return }
        // Sorted so the assignment is a function of the save, not of
        // dictionary iteration order, which is not stable across runs.
        var competitorIndex = 0
        for key in airlines.keys.sorted() {
            guard var airline = airlines[key] as? [String: Any],
                  airline["livery"] == nil else { continue }
            let isPlayer = (airline["kind"] as? String) == "player"
            if isPlayer {
                airline["livery"] = Livery.default.rawValue
            } else {
                airline["livery"] = Livery.forCompetitor(index: competitorIndex).rawValue
                competitorIndex += 1
            }
            airlines[key] = airline
        }
        payload["airlines"] = airlines
    }
}
