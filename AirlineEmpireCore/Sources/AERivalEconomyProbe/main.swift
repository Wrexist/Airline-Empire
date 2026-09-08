// Monthly ledgers for the five-archetype balance world.
// Reproduce: swift run -c release ae-rival-economy 11
import Foundation
import AirlineEmpireCore

let seed = UInt64(CommandLine.arguments.dropFirst().first ?? "11") ?? 11
let catalog = try ContentCatalog.loadBundled()
let state = ScenarioBootstrap.newGame(scenario: "test", worldSeed: seed, startYear: 2030)
let engine = SimulationEngine(state: state, systems: GamePipeline.standard(), catalog: catalog)
let homes: [AirportCode] = ["LHR", "JFK", "SIN", "DXB", "GRU"]
for (index, archetype) in AIArchetype.allCases.enumerated() {
    let profile = AIProfile(archetype: archetype)
    engine.applyNow(FoundAirlineCommand(airlineName: "Bench \(archetype.rawValue)", kind: .ai,
        homeAirport: homes[index], startingCash: .dollars(120_000_000), aiProfile: profile))
    let id = engine.state.airlines.values.first { $0.name == "Bench \(archetype.rawValue)" }!.id
    if profile.prefersLeasing {
        engine.applyNow(LeaseAircraftCommand(lessee: id, type: "MR180", termMonths: 60))
    } else {
        engine.applyNow(BuyUsedAircraftCommand(buyer: id, type: "MR180", ageYears: profile.usedAgeYears))
    }
}
for day in 1...1461 {
    engine.advance(ticks: 96)
    if day % 30 != 0 && day != 1461 { continue }
    for id in engine.state.orderedAirlineIDs {
        let airline = engine.state.airlines[id]!
        let fleet = engine.state.fleet(of: id)
        let routes = engine.state.routes(of: id)
        let statement = engine.state.finance.byAirline[id]?.latest
        var row: [String: Any] = ["seed": seed, "day": day,
            "archetype": airline.aiProfile!.archetype.rawValue,
            "status": String(describing: airline.status), "fleet": fleet.count, "routes": routes.count,
            "idle": fleet.filter { $0.assignedRoute == nil }.count,
            "cash": engine.state.ledger.balance(of: id).asDouble,
            "netWorth": (CreditMath.assets(of: id, state: engine.state) - CreditMath.totalDebt(of: airline)).asDouble,
            "routeProfit": routes.reduce(0.0) { $0 + $1.economicsLastMonth.directOperatingProfit.asDouble }]
        if let statement {
            row["revenue"] = statement.operatingRevenue.asDouble
            row["profit"] = statement.netProfit.asDouble
            for (key,value) in statement.byCategory { row[key.rawValue] = Double(value) / 100 }
        }
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
