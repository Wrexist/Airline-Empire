// Map model build cost at late-game scale — the number the renderer's frame
// budget actually depends on, since the model is rebuilt once per tick.
import Foundation
import AirlineEmpireCore

let catalog = try ContentCatalog.loadBundled()
let engine = SimulationEngine(
    state: ScenarioBootstrap.newGame(scenario: "bench", worldSeed: 99, startYear: 2030),
    systems: GamePipeline.standard(), catalog: catalog)
let bases = catalog.orderedAirportCodes.compactMap { catalog.airports[$0] }
    .filter { $0.runwayClass >= .large }
    .sorted { $0.demographics.populationThousands > $1.demographics.populationThousands }
    .prefix(8)
for (index, base) in bases.enumerated() {
    let kind: AirlineKind = index == 0 ? .player : .ai
    _ = engine.applyNow(FoundAirlineCommand(
        airlineName: "Bench \(index)", kind: kind, homeAirport: base.code,
        startingCash: Money.dollars(9_000_000_000)))
    guard let airline = engine.state.airlines.values.first(where: { $0.name == "Bench \(index)" })
    else { continue }
    var opened = 0
    for (destination, _) in catalog.nearestAirports(to: base.code, limit: 40) where opened < 25 {
        guard engine.applyNow(OpenRouteCommand(
            airline: airline.id, origin: base.code, destination: destination.code,
            dailyRoundTrips: 3, ticketPrice: Money.dollars(129))) == .applied else { continue }
        opened += 1
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: airline.id, type: "MR180", ageYears: 5))
        if let idle = engine.state.fleet(of: airline.id).first(where: { $0.assignedRoute == nil }),
           let route = engine.state.routes(of: airline.id).last {
            _ = engine.applyNow(AssignAircraftToRouteCommand(
                airline: airline.id, route: route.id, aircraftID: idle.id))
        }
    }
}
engine.advance(ticks: 96 * 20)
let state = engine.state
print("world: \(state.airlines.count) airlines, \(state.routes.count) routes, \(state.aircraft.count) aircraft, \(state.flights.count) live flights")

func measure(_ label: String, _ body: () -> Int) {
    var sink = 0
    let iterations = 200
    let start = DispatchTime.now()
    for _ in 0..<iterations { sink &+= body() }
    let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds)
        / 1e6 / Double(iterations)
    print(String(format: "%@: %.2f ms/call (sink %d)", label, ms, sink))
}

measure("mapModel (with opportunities)") {
    let m = state.mapModel(catalog: catalog)
    return m.airports.count &+ m.routes.count &+ m.flights.count
}
measure("mapModel (no opportunities)") {
    let m = state.mapModel(catalog: catalog, opportunityLimit: 0)
    return m.airports.count &+ m.routes.count &+ m.flights.count
}
measure("marketOpportunities alone") {
    state.marketOpportunities(catalog: catalog, limit: 6).count
}

var sink = 0
let iterations = 200
let start = DispatchTime.now()
for _ in 0..<iterations {
    let model = state.mapModel(catalog: catalog)
    sink &+= model.airports.count &+ model.routes.count &+ model.flights.count
}
let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6
print(String(format: "mapModel build: %.2f ms/call over %d calls (sink %d)",
             elapsed / Double(iterations), iterations, sink))

// Arc segment count is what the renderer strokes each frame.
let model = state.mapModel(catalog: catalog)
let segments = model.routes.reduce(0) { $0 + $1.arc.count }
print("route arc waypoints: \(segments); flights: \(model.flights.count); opportunities: \(model.opportunities.count)")
