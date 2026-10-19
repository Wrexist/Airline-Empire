import Foundation
import Testing
@testable import AirlineEmpireCore

/// TD-027: a route knows when it opened, and an older save keeps what it can.
@Suite("Route opening dates")
struct RouteOpeningTests {
    @Test("A route records the moment it opened")
    func aRouteRecordsItsOpening() throws {
        let catalog = try DemandFixtures.anchorCatalog()
        let engine = SimulationEngine(state: Fixtures.newState(),
                                      systems: GamePipeline.standard(), catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(airlineName: "Anchor Air", kind: .player,
                                                homeAirport: "MET",
                                                startingCash: .dollars(300_000_000)))
        let airline = try #require(engine.state.playerAirline?.id)
        engine.advance(ticks: Fixtures.ticksPerDay * 3 + 7)
        let opened = engine.state.clock.now
        #expect(engine.applyNow(OpenRouteCommand(airline: airline, origin: "MET", destination: "COS",
                                                 dailyRoundTrips: 2, ticketPrice: .dollars(129)))
                == .applied)
        let route = try #require(engine.state.routes.values.first)
        #expect(route.openedAt == opened)
        // It is history, not state that moves: a week of flying leaves it be.
        engine.advance(ticks: Fixtures.ticksPerDay * 7)
        #expect(engine.state.routes[route.id]?.openedAt == opened)
    }

    @Test("A save round-trips the opening date")
    func theDateSurvivesASave() throws {
        let (engine, _, routeID) = try DemandFixtures.market(fare: .dollars(129))
        let codec = JSONSaveCodec()
        let restored = try codec.decode(codec.encode(engine.state))
        #expect(restored.routes[routeID]?.openedAt == engine.state.routes[routeID]?.openedAt)
        #expect(restored.routes[routeID]?.openedAt != nil)
    }

    /// A v16 save has no opening dates. The migration takes each from the
    /// market entry recorded with it, and leaves nil where the bounded record
    /// has already let it go.
    @Test("A v16 save takes its openings from the market-move record")
    func v16SavesRecoverWhatTheyCan() throws {
        let (engine, _, routeID) = try DemandFixtures.market(fare: .dollars(129))
        engine.advance(ticks: Fixtures.ticksPerDay)
        let state = engine.state
        let expected = try #require(state.routes[routeID]?.openedAt)

        let recovered = try JSONSaveCodec().decode(try Self.v16Envelope(state, keepMoves: true))
        #expect(recovered.routes[routeID]?.openedAt == expected)

        let forgotten = try JSONSaveCodec().decode(try Self.v16Envelope(state, keepMoves: false))
        #expect(forgotten.routes[routeID] != nil)
        #expect(forgotten.routes[routeID]?.openedAt == nil)
    }

    /// The state as a v16 build wrote it: no `openedAt` on any route, and —
    /// for the second case — a market-move record that has rolled past the
    /// openings.
    private static func v16Envelope(_ state: GameState, keepMoves: Bool) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var tree = try #require(try JSONSerialization.jsonObject(with: encoder.encode(state))
                                as? [String: Any])
        var routes = try #require(tree["routes"] as? [String: Any])
        for key in routes.keys {
            var route = try #require(routes[key] as? [String: Any])
            route["openedAt"] = nil
            routes[key] = route
        }
        tree["routes"] = routes
        if !keepMoves {
            var world = try #require(tree["world"] as? [String: Any])
            world["marketMoves"] = [Any]()
            tree["world"] = world
        }
        let payload = try JSONSerialization.data(withJSONObject: tree)
        let envelope = SaveEnvelope(formatVersion: 16, contentVersion: "0",
                                    savedAtTick: state.clock.tickCount, payload: payload)
        return try encoder.encode(envelope)
    }
}
