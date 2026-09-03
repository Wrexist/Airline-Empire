import Foundation
import Testing
@testable import AirlineEmpireCore

/// Save format v10 → v11 (`Airline.livery`).
///
/// This is the first migration in the project's history that runs on somebody
/// else's data: v10 is the format TestFlight build 1.0.0 wrote to a real
/// phone. A migration that quietly drops an airline, reshuffles the world's
/// colours on every load, or refuses a valid save costs a player their game,
/// so the tests here are about *that* rather than about the field.
@Suite("Livery and the v10 → v11 migration")
struct LiveryMigrationTests {

    /// A v10 payload: today's state with the livery keys stripped back out,
    /// which is exactly the shape a v10 build wrote.
    private func v10Payload(competitors: Int = 3) async throws -> (Data, GameState) {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: 1011),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Legacy Air", kind: .player, homeAirport: "ARN",
            startingCash: Money.dollars(100_000_000)))
        await session.populateStandardWorld(competitors: competitors)
        await session.advance(ticks: Fixtures.ticksPerDay * 3)
        let state = await session.snapshot

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var tree = try JSONSerialization.jsonObject(with: encoder.encode(state))
            as! [String: Any]
        var airlines = tree["airlines"] as! [String: Any]
        for key in airlines.keys {
            var airline = airlines[key] as! [String: Any]
            airline["livery"] = nil
            airlines[key] = airline
        }
        tree["airlines"] = airlines
        return (try JSONSerialization.data(withJSONObject: tree), state)
    }

    /// Wraps a raw payload in an envelope claiming a given format version, so
    /// the codec takes the migration path a real old save would.
    private func envelope(_ payload: Data, version: Int) throws -> Data {
        let envelope = SaveEnvelope(formatVersion: version, contentVersion: "0",
                                    savedAtTick: 0, payload: payload)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(envelope)
    }

    @Test("The version bumped, and the chain still reaches back to v9")
    func chainIsContiguous() {
        #expect(SaveFormat.currentVersion == 12)
        #expect(MigrationChain.standard.minimumSupportedVersion == 9)
    }

    /// The one that matters: a save written by the build already on a phone
    /// must open.
    @Test("A v10 save loads, with every airline intact")
    func v10SaveLoads() async throws {
        let (payload, original) = try await v10Payload()
        let data = try envelope(payload, version: 10)
        let restored = try JSONSaveCodec().decode(data)

        #expect(restored.airlines.count == original.airlines.count)
        for (id, airline) in original.airlines {
            let migrated = try #require(restored.airlines[id])
            #expect(migrated.name == airline.name)
            #expect(migrated.kind == airline.kind)
            #expect(migrated.homeAirport == airline.homeAirport)
        }
        // Nothing else about the world moved.
        #expect(restored.clock.tickCount == original.clock.tickCount)
        #expect(restored.routes.count == original.routes.count)
        #expect(restored.aircraft.count == original.aircraft.count)
        for (id, airline) in original.airlines {
            #expect(restored.ledger.balance(of: id) == original.ledger.balance(of: id))
        }
    }

    /// The player's colour is the accent their whole game has been painted
    /// in; a bug-fix build must not repaint it.
    @Test("The migrated player keeps the default livery")
    func playerKeepsTheDefault() async throws {
        let (payload, _) = try await v10Payload()
        let restored = try JSONSaveCodec().decode(try envelope(payload, version: 10))
        let player = try #require(restored.playerAirline)
        #expect(player.livery == .default)
    }

    /// Rivals must be told apart on a dark map, and must be the *same* colours
    /// every time the save is opened.
    @Test("Migrated rivals get distinct, stable liveries")
    func rivalsAreDistinctAndStable() async throws {
        let (payload, _) = try await v10Payload(competitors: 5)
        let first = try JSONSaveCodec().decode(try envelope(payload, version: 10))
        let second = try JSONSaveCodec().decode(try envelope(payload, version: 10))

        let rivals = first.orderedAirlineIDs.compactMap { id -> Airline? in
            guard let airline = first.airlines[id], airline.kind == .ai else { return nil }
            return airline
        }
        #expect(rivals.count >= 3)
        #expect(Set(rivals.map(\.livery)).count == rivals.count)
        #expect(!rivals.contains { $0.livery == .default })

        // Same bytes in, same colours out — twice.
        for id in first.orderedAirlineIDs {
            #expect(first.airlines[id]?.livery == second.airlines[id]?.livery)
        }
    }

    /// Running the step twice must not repaint anything: migrations are
    /// applied to a tree that may already carry the key.
    @Test("The step is idempotent")
    func migrationIsIdempotent() async throws {
        let (payload, _) = try await v10Payload()
        var tree = try JSONSerialization.jsonObject(with: payload) as! [String: Any]
        let step = MigrationV10AddLivery()
        try step.migrate(&tree)
        let once = tree
        try step.migrate(&tree)

        let a = once["airlines"] as! [String: Any]
        let b = tree["airlines"] as! [String: Any]
        for key in a.keys {
            let lhs = (a[key] as! [String: Any])["livery"] as? String
            let rhs = (b[key] as! [String: Any])["livery"] as? String
            #expect(lhs == rhs)
        }
    }

    /// A payload with no airlines at all (a kernel-only save) must pass
    /// through rather than trap.
    @Test("A save with no airlines migrates cleanly")
    func emptyWorldMigrates() throws {
        var tree: [String: Any] = ["airlines": [String: Any]()]
        try MigrationV10AddLivery().migrate(&tree)
        #expect((tree["airlines"] as! [String: Any]).isEmpty)

        var without: [String: Any] = [:]
        try MigrationV10AddLivery().migrate(&without)
        #expect(without["airlines"] == nil)
    }

    // MARK: - The field itself

    @Test("A founded airline carries the livery it was founded with")
    func foundingCarriesTheLivery() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: 77),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Crimson Air", kind: .player, homeAirport: "ARN",
            startingCash: Money.dollars(50_000_000), livery: .crimson))
        let player = try #require(await session.snapshot.playerAirline)
        #expect(player.livery == .crimson)
    }

    @Test("A new world paints its rivals apart from the player")
    func newWorldRivalsAreDistinct() async throws {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: 78),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        let spec = try #require(catalog.scenario("entrepreneur"))
        _ = await session.beginScenario(spec, airlineName: "Jade Air",
                                        home: "ARN", livery: .jade)
        let state = await session.snapshot
        let player = try #require(state.playerAirline)
        #expect(player.livery == .jade)

        let rivals = state.airlines.values.filter { $0.kind == .ai }
        #expect(!rivals.isEmpty)
        #expect(Set(rivals.map(\.livery)).count == rivals.count)
    }

    /// The livery is identity, not mechanics — a world painted differently
    /// must simulate identically, or it is a balance change in disguise.
    @Test("Livery does not touch the simulation")
    func liveryIsCosmetic() async throws {
        func run(_ livery: Livery) async throws -> UInt64 {
            let catalog = try ContentCatalog.loadBundled()
            let session = GameSession(state: Fixtures.newState(seed: 4242),
                                      systems: GamePipeline.standard(),
                                      catalog: catalog)
            let spec = try #require(catalog.scenario("entrepreneur"))
            _ = await session.beginScenario(spec, airlineName: "Same Air",
                                            home: "ARN", livery: livery)
            await session.advance(ticks: Fixtures.ticksPerDay * 120)
            var state = await session.snapshot
            // Neutralise the one field that is meant to differ.
            for id in state.orderedAirlineIDs {
                state.airlines[id]?.livery = .default
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return StableHash.fnv1a(try encoder.encode(state))
        }
        #expect(try await run(.azure) == (try await run(.gold)))
    }
}
