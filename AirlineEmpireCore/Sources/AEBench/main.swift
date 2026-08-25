import Foundation
import AirlineEmpireCore

// Headless performance benchmark (Phase 20). Run in release:
//   swift run -c release ae-bench
// Builds worlds at several scales and measures simulation throughput and
// save codec cost. Results recorded in docs/PERFORMANCE.md.

func buildWorld(airlines airlineCount: Int, routesPerAirline: Int,
                seed: UInt64) throws -> SimulationEngine {
    let catalog = try ContentCatalog.loadBundled()
    let engine = SimulationEngine(
        state: ScenarioBootstrap.newGame(scenario: "bench", worldSeed: seed,
                                         startYear: 2030),
        systems: GamePipeline.standard(), catalog: catalog)
    let bases = catalog.orderedAirportCodes
        .compactMap { catalog.airports[$0] }
        .filter { $0.runwayClass >= .large }
        .sorted { $0.demographics.populationThousands > $1.demographics.populationThousands }
        .prefix(airlineCount)

    for (index, base) in bases.enumerated() {
        let kind: AirlineKind = index == 0 ? .player : .ai
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Bench \(index)", kind: kind, homeAirport: base.code,
            startingCash: Money.dollars(5_000_000_000)))
        guard let airline = engine.state.airlines.values.first(where: {
            $0.name == "Bench \(index)"
        }) else { continue }
        let destinations = catalog.nearestAirports(to: base.code, limit: 40)
        var opened = 0
        for (destination, _) in destinations where opened < routesPerAirline {
            let open = engine.applyNow(OpenRouteCommand(
                airline: airline.id, origin: base.code, destination: destination.code,
                dailyRoundTrips: 2, ticketPrice: Money.dollars(119)))
            guard open == .applied else { continue }
            opened += 1
            _ = engine.applyNow(BuyUsedAircraftCommand(
                buyer: airline.id, type: "MR180", ageYears: 5))
            if let idle = engine.state.fleet(of: airline.id).first(where: {
                $0.assignedRoute == nil && $0.isOperational
            }), let route = engine.state.routes.values.first(where: {
                $0.airline == airline.id && $0.destination == destination.code
            }) {
                _ = engine.applyNow(AssignAircraftToRouteCommand(
                    airline: airline.id, route: route.id, aircraftID: idle.id))
            }
        }
    }
    return engine
}

func measure(_ label: String, _ block: () throws -> Void) rethrows {
    let start = ContinuousClock.now
    try block()
    let elapsed = start.duration(to: .now)
    let seconds = Double(elapsed.components.seconds)
        + Double(elapsed.components.attoseconds) / 1e18
    print(String(format: "%-46s %8.2f s", (label as NSString).utf8String!, seconds))
}

let ticksPerDay = Int(GameCalendar.minutesPerDay / ScenarioBootstrap.standardTickMinutes)
let ticksPerYear = ticksPerDay * Int(GameCalendar.daysPerYear)

print("== Airline Empire headless benchmark ==")
for (airlines, routes) in [(2, 5), (4, 15), (8, 25)] {
    let engine = try buildWorld(airlines: airlines, routesPerAirline: routes, seed: 99)
    // Warm up world state (schedules materialize, stats accrue).
    engine.advance(ticks: ticksPerDay * 7)
    let label = "\(airlines) airlines × \(routes) routes: 1 game-year"
    measure(label) {
        engine.advance(ticks: ticksPerYear)
    }
    print("   flights live: \(engine.state.flights.count), aircraft: \(engine.state.aircraft.count), routes: \(engine.state.routes.count)")

    let codec = JSONSaveCodec()
    var data = Data()
    try measure("   save encode") { data = try codec.encode(engine.state) }
    print("   save size: \(data.count / 1024) KiB")
    try measure("   save decode") { _ = try codec.decode(data) }
}
print("== done ==")
