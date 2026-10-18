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
        MigrationV11AddMarketMoves(),
        MigrationV12AddRescueDecision(),
        MigrationV13AddProgressionRecord(),
        MigrationV14AddHubBuildings(),
        MigrationV15AddPlayerWindows(),
        MigrationV16AddRouteOpenedAt(),
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

/// v16 → v17: routes gained `openedAt` (TD-027). The opening is recovered
/// where the save still knows it: `OpenRouteCommand` has always recorded a
/// market entry for the same airline and pair at the same instant, so the
/// latest such entry is the current route's opening. The record keeps the
/// last 64 moves, so an older route may have none left; it stays nil, which
/// the route screen reads as "before opening dates were recorded" rather
/// than inventing a date.
public struct MigrationV16AddRouteOpenedAt: SaveMigration {
    public let fromVersion = 16
    public init() {}

    public func migrate(_ payload: inout [String: Any]) throws {
        guard var routes = payload["routes"] as? [String: Any] else { return }
        let world = payload["world"] as? [String: Any]
        let moves = world?["marketMoves"] as? [[String: Any]] ?? []
        for key in routes.keys.sorted() {
            guard var route = routes[key] as? [String: Any], route["openedAt"] == nil,
                  let airline = Self.integer(route["airline"]),
                  let origin = route["origin"] as? String,
                  let destination = route["destination"] as? String else { continue }
            let opening = moves.last { move in
                (move["kind"] as? String) == MarketMove.Kind.entered.rawValue
                    && Self.integer(move["airline"]) == airline
                    && (move["origin"] as? String) == origin
                    && (move["destination"] as? String) == destination
            }
            guard let at = opening?["at"] else { continue }
            route["openedAt"] = at
            routes[key] = route
        }
        payload["routes"] = routes
    }

    /// A JSON number as an integer, whichever type `JSONSerialization`
    /// bridged it to on this platform.
    private static func integer(_ value: Any?) -> Int64? {
        guard let value else { return nil }
        if let number = value as? Int { return Int64(number) }
        if let number = value as? Int64 { return number }
        if let number = value as? NSNumber { return number.int64Value }
        return nil
    }
}

/// v15 → v16: the event log gained the player's feed ring, the ledger each
/// airline's day window, and sale/lease-return events their airline
/// (TD-032). Every new field decodes as absent: the windows report that they
/// cover nothing yet, so a digest falls back to the shared rings until they
/// have recorded a whole day, and old events resolve their owner by lookup
/// as before. The step only moves the version.
public struct MigrationV15AddPlayerWindows: SaveMigration {
    public let fromVersion = 15
    public init() {}
    public func migrate(_ payload: inout [String: Any]) throws {}
}

/// v14 → v15: airlines gained hub buildings (docs/HUB_PROGRESSION_PLAN.md).
/// Every new field decodes as absent — no hangar, no crew base, nothing
/// under construction, statuses assessed from the next day — so the step
/// only moves the version.
public struct MigrationV14AddHubBuildings: SaveMigration {
    public let fromVersion = 14
    public init() {}
    public func migrate(_ payload: inout [String: Any]) throws {}
}

/// v13 → v14: progression gained `record`, the bounded dated log of completed
/// work. An older save starts with an empty log — its retained milestones,
/// achievements and completed programs are untouched, and nothing is
/// manufactured backwards from the event feed, which never held the whole
/// campaign anyway. The log begins from this build.
public struct MigrationV13AddProgressionRecord: SaveMigration {
    public let fromVersion = 13
    public init() {}
    public func migrate(_ payload: inout [String: Any]) throws {
        guard var progression = payload["progression"] as? [String: Any],
              progression["record"] == nil else { return }
        progression["record"] = [Any]()
        payload["progression"] = progression
    }
}

/// v12 → v13 preserves every airline and loan. Existing campaigns have not
/// yet accepted or declined the new one-time rescue offer.
public struct MigrationV12AddRescueDecision: SaveMigration {
    public let fromVersion = 12
    public init() {}
    public func migrate(_ payload: inout [String: Any]) throws {
        guard var airlines = payload["airlines"] as? [String: Any] else { return }
        for key in airlines.keys.sorted() {
            guard var airline = airlines[key] as? [String: Any] else { continue }
            if airline["rescueDecision"] == nil { airline["rescueDecision"] = "unreviewed" }
            airlines[key] = airline
        }
        payload["airlines"] = airlines
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

/// v11 → v12: the world gained `marketMoves`, the bounded record of who
/// entered and left which city pair (AE-037). An older save starts with an
/// empty record: the routes it holds are still there, so the current
/// competitive picture is intact and only the history of how it came to be
/// is missing — which is exactly what a v11 world never had.
public struct MigrationV11AddMarketMoves: SaveMigration {
    public let fromVersion = 11

    public init() {}

    public func migrate(_ payload: inout [String: Any]) throws {
        guard var world = payload["world"] as? [String: Any],
              world["marketMoves"] == nil else { return }
        world["marketMoves"] = [Any]()
        payload["world"] = world
    }
}
