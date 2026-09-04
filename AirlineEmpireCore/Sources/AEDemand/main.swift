import Foundation
import AirlineEmpireCore

// AE-044 — the controlled demand battery (TD-033).
//
//   swift run -c release ae-demand capacity    [--pairs …] [--types …] [--rotations max|N]
//   swift run -c release ae-demand frequency   [--pairs …] [--types …]
//   swift run -c release ae-demand competition [--pairs …] [--types …] [--incumbents 0,1,2,3]
//   swift run -c release ae-demand airframe    [--routes HAM:LHR:KT95:PA184,…]
//   swift run -c release ae-demand estimator   [--pairs …] [--types …]   (no simulation)
//
// Every mode holds origin, destination, fare (the market reference), day,
// seed and world constant, varies exactly one thing, flies the result
// through the real pipeline, and reads February back from the route's own
// closed month. Beside each flown month it prints what the estimator would
// have said — the shipped one and, once it exists, the corrected one — so
// the demand error and the cost error can be told apart.
//
// Nothing here changes the simulation. `--incumbents N` founds N extra AI
// airlines on the same pair with the competitor system removed from the
// pipeline, so they hold the route they are given and nothing else moves.

let arguments = CommandLine.arguments
let mode = arguments.count > 1 ? arguments[1] : "capacity"
func option(_ flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1)
    else { return nil }
    return arguments[index + 1]
}
let seed = UInt64(option("--seed") ?? "2030") ?? 2030
let measuredMonths = max(1, Int(option("--months") ?? "1") ?? 1)
let csv = arguments.contains("--csv")

let catalog = try ContentCatalog.loadBundled()
guard let scenario = catalog.scenario("entrepreneur") else { fatalError("no entrepreneur scenario") }
let ticksPerDay = Int(GameCalendar.minutesPerDay / ScenarioBootstrap.standardTickMinutes)

let defaultPairs = ["HAM-LHR", "DUB-CDG", "GOT-LHR", "PMI-LHR", "KEF-LHR", "JFK-ORD"]
let pairs: [(AirportCode, AirportCode)] = (option("--pairs")?
    .split(separator: ",").map(String.init) ?? defaultPairs).compactMap { pair in
    let ends = pair.split(separator: "-")
    guard ends.count == 2 else { return nil }
    return (AirportCode(String(ends[0])), AirportCode(String(ends[1])))
}
/// `--estimate-rotations max|N`: what the ESTIMATE assumes the airframe
/// flies, independently of the frequency the route is actually opened at.
/// Production assumes the maximum; the route is opened at two.
let estimateRotationsOption: Int? = (option("--estimate-rotations")
    .flatMap { $0 == "max" ? nil : Int($0) })
let types: [AircraftTypeCode] = (option("--types")?.split(separator: ",").map(String.init)
    ?? ["KT72", "AV90", "KT95", "NA160", "PA184", "MR220"]).map { AircraftTypeCode($0) }

// MARK: - One flown month

/// The fuel price the last flown month averaged, so the line-by-line mode
/// charges the estimator the same price the ledger paid.
nonisolated(unsafe) var fuelPriceObserved: Double?

struct Flown {
    var flights = 0
    var cancelled = 0
    var passengers: Int64 = 0
    var seatsFlown: Int64 = 0
    var revenue: Int64 = 0
    var fuel: Int64 = 0
    var fees: Int64 = 0
    var crew: Int64 = 0
    var service: Int64 = 0
    var maintenance: Int64 = 0
    /// Demand the engine allocated to the route on the last measured day,
    /// both directions — the number before the seat cap bites.
    var allocatedLastDay = 0
    var days = 0.0
}

struct Measurement {
    let origin: AirportCode
    let destination: AirportCode
    let distanceKm: Int
    let type: AircraftTypeCode
    let seats: Int
    let roundTrips: Int
    let maxRotations: Int
    let incumbents: Int
    let fare: Double
    let flown: Flown
    /// The rotation count the ESTIMATE was priced at, which production
    /// takes as the airframe's maximum and need not equal `roundTrips`.
    let estimateRotations: Int
    /// Estimator, as shipped: one market figure, no airframe in it.
    let shippedPassengers: Double
    let shippedCarried: Double
    let shippedRevenue: Double
    let shippedProfit: Double
    /// Estimator, corrected (the new derivation; equals the shipped one
    /// until the fix lands).
    let correctedPassengers: Double
    let correctedCarried: Double
    let correctedRevenue: Double
    let correctedProfit: Double
    /// The ledger, per day.
    var actualPassengers: Double { Double(flown.passengers) / flown.days }
    var actualRevenue: Double { Double(flown.revenue) / 100 / flown.days }
    /// Direct − service − maintenance: exactly what `.profit` estimates.
    var actualProfit: Double {
        Double(flown.revenue - flown.fuel - flown.fees - flown.crew
               - flown.service - flown.maintenance) / 100 / flown.days
    }
    var actualLoad: Double {
        flown.seatsFlown > 0 ? Double(flown.passengers) / Double(flown.seatsFlown) : 0
    }
    var seatsPerDay: Double { Double(flown.seatsFlown) / flown.days }
    /// The product ranks airframes on a month of the route's own result
    /// less the airframe's lease and the payroll it carries
    /// (`GameState.airframeResult`), not on the day value alone.
    let leaseMonthly: Double
    let payrollMonthly: Double
    func afterOwnership(_ perDay: Double) -> Double {
        perDay * 30 - leaseMonthly - payrollMonthly
    }
    var shippedAfterOwnership: Double { afterOwnership(shippedProfit) }
    var correctedAfterOwnership: Double { afterOwnership(correctedProfit) }
    var actualAfterOwnership: Double { afterOwnership(actualProfit) }
}

/// Fly one pair with one airframe at one frequency against `incumbents`
/// identical AI carriers, and read the measured months back.
@MainActor
func fly(_ origin: AirportCode, _ destination: AirportCode, type: AircraftTypeCode,
         roundTrips: Int?, incumbents: Int) -> Measurement? {
    guard let spec = catalog.aircraftType(type),
          let originSpec = catalog.airport(origin),
          let destinationSpec = catalog.airport(destination),
          let distance = catalog.distanceKm(origin, destination),
          catalog.routeEligibility(from: origin, to: destination,
                                   aircraftRangeKm: spec.rangeKm,
                                   aircraftRunwayRequirement: spec.runwayRequirement).isEmpty
    else { return nil }
    let maxRotations = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
        distanceKm: distance, spec: spec, ops: catalog.tuning.ops)
    guard maxRotations > 0 else { return nil }
    let trips = min(maxRotations, roundTrips ?? maxRotations)
    guard trips > 0 else { return nil }

    // The standard pipeline without the competitor system: the incumbents
    // hold what they are given and open nothing else, so the only thing
    // that varies between runs is what this call varies.
    var systems = GamePipeline.standard()
    systems.removeAll { $0.id == CompetitorAISystem().id }
    let engine = SimulationEngine(
        state: ScenarioBootstrap.newGame(scenario: "entrepreneur", worldSeed: seed,
                                         startYear: scenario.startYear),
        systems: systems, catalog: catalog)
    let fare = DemandSystem.referenceFare(distanceKm: distance, tuning: catalog.tuning.demand)

    // The incumbents first, so the subject enters a market that already has
    // them — exactly the order the world produces.
    // A mid-size regional jet at the reference fare, twice a day: the
    // "equal incumbent" of §4 unless --incumbent-type says otherwise.
    let incumbentType = AircraftTypeCode(option("--incumbent-type") ?? "KT95")
    for index in 0..<incumbents {
        guard engine.applyNow(FoundAirlineCommand(
            airlineName: "Incumbent \(index + 1)", kind: .ai, homeAirport: origin,
            startingCash: Money.dollars(400_000_000),
            aiProfile: AIProfile(archetype: .regional))) == .applied,
              let airline = engine.state.airlines.values.first(where: {
                  $0.name == "Incumbent \(index + 1)" }) else { continue }
        guard engine.applyNow(LeaseAircraftCommand(
            lessee: airline.id, type: incumbentType, termMonths: 60)) == .applied,
              let aircraft = engine.state.fleet(of: airline.id).first else { continue }
        guard engine.applyNow(OpenRouteCommand(
            airline: airline.id, origin: origin, destination: destination,
            dailyRoundTrips: 2, ticketPrice: Money(rounding: fare))) == .applied,
              let route = engine.state.routes(of: airline.id).first else { continue }
        _ = engine.applyNow(AssignAircraftToRouteCommand(
            airline: airline.id, route: route.id, aircraftID: aircraft.id))
    }

    guard engine.applyNow(FoundAirlineCommand(
        airlineName: "Subject Air", kind: .player, homeAirport: origin,
        startingCash: Money.dollars(400_000_000))) == .applied,
          let subject = engine.state.airlines.values.first(where: { $0.kind == .player })
    else { return nil }
    guard engine.applyNow(LeaseAircraftCommand(
        lessee: subject.id, type: type, termMonths: 60)) == .applied,
          let aircraft = engine.state.fleet(of: subject.id).first else { return nil }
    guard engine.applyNow(OpenRouteCommand(
        airline: subject.id, origin: origin, destination: destination,
        dailyRoundTrips: trips, ticketPrice: Money(rounding: fare))) == .applied,
          let route = engine.state.routes(of: subject.id).first else { return nil }
    guard engine.applyNow(AssignAircraftToRouteCommand(
        airline: subject.id, route: route.id, aircraftID: aircraft.id)) == .applied
    else { return nil }

    // The estimate is taken on day 0, before anything flies — the moment
    // the player or the AI would actually make this decision.
    let day0 = engine.state
    let rivalRoutes = day0.routes.values.filter {
        $0.airline != subject.id && $0.sameMarket(origin: origin, destination: destination)
    }.sorted { $0.id.raw < $1.id.raw }

    // --- the shipped estimator (player path: both directions, constant quality)
    let starter = DemandSystem.representativeStarterQuality(tuning: catalog.tuning.demand)
    func captured(_ from: AirportCode, _ to: AirportCode) -> Double {
        DemandSystem.expectedCapturedPassengers(
            pool: DemandSystem.demandPool(from: from, to: to, date: day0.currentDate,
                                          economicIndex: day0.world.economicIndex,
                                          catalog: catalog),
            fareRatio: 1.0, quality: starter, tuning: catalog.tuning.demand)
    }
    let shippedPassengers = captured(origin, destination) + captured(destination, origin)
    // The estimate is priced at `estimateRotations` — production's own
    // assumption is the airframe's maximum, whatever the route is then
    // opened at, and `--estimate-rotations` lets that be varied on its own.
    let priced = estimateRotationsOption.map { min(maxRotations, $0) } ?? maxRotations
    let shippedCarried = min(shippedPassengers, Double(priced * 2 * spec.seats))
    let shippedRevenue = CompetitorAISystem.airframeDayValue(
        distanceKm: distance, passengersPerDay: shippedPassengers, spec: spec, fareRatio: 1.0,
        serviceTier: subject.serviceTier, origin: originSpec, destination: destinationSpec,
        state: day0, catalog: catalog, rotationsPerDay: priced, basis: .revenue)
    let shippedProfit = CompetitorAISystem.airframeDayValue(
        distanceKm: distance, passengersPerDay: shippedPassengers, spec: spec, fareRatio: 1.0,
        serviceTier: subject.serviceTier, origin: originSpec, destination: destinationSpec,
        state: day0, catalog: catalog, rotationsPerDay: priced, basis: .profit)

    // --- the corrected estimator, when the engine has one
    let corrected = correctedEstimate(
        origin: originSpec, destination: destinationSpec, distanceKm: distance,
        spec: spec, roundTrips: priced, incumbents: rivalRoutes, state: day0,
        serviceTier: subject.serviceTier)

    // --- fly it
    var flown = Flown()
    var flightsAtStart = 0, cancelledAtStart = 0
    var seatsAtStart: Int64 = 0
    var monthsClosed = 0
    var lastMonth = engine.state.currentDate.month
    var daysMeasured = 0
    var fuelPrices: [Double] = []
    while monthsClosed < 1 + measuredMonths {
        engine.advance(ticks: ticksPerDay)
        let now = engine.state.currentDate
        if now.month != lastMonth {
            monthsClosed += 1
            lastMonth = now.month
            guard let r = engine.state.routes[route.id] else { return nil }
            if monthsClosed == 1 {
                flightsAtStart = Int(r.stats.flightsCompleted)
                cancelledAtStart = Int(r.stats.flightsCancelled)
                seatsAtStart = r.stats.seatsFlown
            } else if let statement = engine.state.finance.byAirline[subject.id]?.statements.last {
                let month = r.economicsLastMonth
                flown.passengers += month.passengers
                flown.revenue += month.revenueCents
                flown.fuel += month.fuelCents
                flown.fees += month.feesCents
                flown.crew += month.crewCents
                flown.service += -statement.total(.passengerService).cents
                flown.maintenance += -statement.total(.maintenance).cents
            }
        }
        if monthsClosed >= 1 {
            daysMeasured += 1
            fuelPrices.append(engine.state.world.fuelPricePerTon.asDouble)
        }
    }
    fuelPriceObserved = fuelPrices.isEmpty ? nil
        : fuelPrices.reduce(0, +) / Double(fuelPrices.count)
    daysMeasured -= 1
    let state = engine.state
    guard let r = state.routes[route.id] else { return nil }
    flown.flights = Int(r.stats.flightsCompleted) - flightsAtStart
    flown.cancelled = Int(r.stats.flightsCancelled) - cancelledAtStart
    flown.seatsFlown = r.stats.seatsFlown - seatsAtStart
    flown.allocatedLastDay = r.demandOutboundToday + r.demandInboundToday
    flown.days = Double(daysMeasured)
    return Measurement(
        origin: origin, destination: destination, distanceKm: distance, type: type,
        seats: spec.seats, roundTrips: trips, maxRotations: maxRotations,
        incumbents: incumbents, fare: fare, flown: flown,
        estimateRotations: priced,
        shippedPassengers: shippedPassengers, shippedCarried: shippedCarried,
        shippedRevenue: shippedRevenue, shippedProfit: shippedProfit,
        correctedPassengers: corrected.passengers, correctedCarried: corrected.carried,
        correctedRevenue: corrected.revenue, correctedProfit: corrected.profit,
        leaseMonthly: spec.leaseMonthly.asDouble,
        payrollMonthly: catalog.tuning.finance.payrollPerAircraftMonthly.asDouble
            + catalog.tuning.finance.payrollPerRouteMonthly.asDouble)
}

// MARK: - Reporting

func f(_ value: Double, _ places: Int = 0) -> String {
    String(format: "%.\(places)f", value)
}
func err(_ estimate: Double, _ actual: Double) -> String {
    actual == 0 ? "—" : String(format: "%+.0f%%", (estimate / actual - 1) * 100)
}

let header = "pair,km,type,seats,roundTrips,maxRot,incumbents,fare,"
    + "pricedRotations,estPaxShipped,estPaxCorrected,actualPax,"
    + "estCarriedShipped,estCarriedCorrected,actualPax2,seatsPerDay,load,"
    + "estRevShipped,estRevCorrected,actualRev,"
    + "estProfitShipped,estProfitCorrected,actualProfit,"
    + "flights,cancelled,allocatedLastDay,"
    + "leaseMonthly,payrollMonthly,"
    + "shippedAfterOwnership,correctedAfterOwnership,actualAfterOwnership"

func row(_ m: Measurement) -> String {
    [
        "\(m.origin)-\(m.destination)", "\(m.distanceKm)", "\(m.type)", "\(m.seats)",
        "\(m.roundTrips)", "\(m.maxRotations)", "\(m.incumbents)", f(m.fare),
        "\(m.estimateRotations)",
        f(m.shippedPassengers, 1), f(m.correctedPassengers, 1), f(m.actualPassengers, 1),
        f(m.shippedCarried, 1), f(m.correctedCarried, 1), f(m.actualPassengers, 1),
        f(m.seatsPerDay, 1), f(m.actualLoad, 3),
        f(m.shippedRevenue), f(m.correctedRevenue), f(m.actualRevenue),
        f(m.shippedProfit), f(m.correctedProfit), f(m.actualProfit),
        "\(m.flown.flights)", "\(m.flown.cancelled)", "\(m.flown.allocatedLastDay)",
        f(m.leaseMonthly), f(m.payrollMonthly),
        f(m.shippedAfterOwnership), f(m.correctedAfterOwnership), f(m.actualAfterOwnership),
    ].joined(separator: ",")
}

func pad(_ text: String, _ width: Int, right: Bool = false) -> String {
    let padding = String(repeating: " ", count: max(0, width - text.count))
    return right ? padding + text : text + padding
}

func report(_ measurements: [Measurement], title: String) {
    if csv {
        for m in measurements { print(row(m)) }
        return
    }
    print("\n== \(title) ==")
    print(pad("pair", 10) + pad("type", 7) + pad("seats", 6, right: true)
          + pad("trip", 5, right: true) + pad("inc", 4, right: true)
          + pad("estPax", 9, right: true) + pad("newPax", 9, right: true)
          + pad("realPax", 9, right: true) + pad("err", 8, right: true)
          + pad("newErr", 8, right: true) + pad("estProfit", 11, right: true)
          + pad("newProfit", 11, right: true) + pad("realProfit", 11, right: true)
          + pad("load", 7, right: true))
    for m in measurements {
        print(pad("\(m.origin)-\(m.destination)", 10) + pad("\(m.type)", 7)
              + pad("\(m.seats)", 6, right: true) + pad("\(m.roundTrips)", 5, right: true)
              + pad("\(m.incumbents)", 4, right: true)
              + pad(f(m.shippedPassengers), 9, right: true)
              + pad(f(m.correctedPassengers), 9, right: true)
              + pad(f(m.actualPassengers), 9, right: true)
              + pad(err(m.shippedPassengers, m.actualPassengers), 8, right: true)
              + pad(err(m.correctedPassengers, m.actualPassengers), 8, right: true)
              + pad(f(m.shippedProfit), 11, right: true)
              + pad(f(m.correctedProfit), 11, right: true)
              + pad(f(m.actualProfit), 11, right: true)
              + pad(f(m.actualLoad * 100) + "%", 7, right: true))
    }
}

// MARK: - Modes

if csv { print(header) }

switch mode {
case "capacity":
    // Phase 2. One market, every airframe size, each at its own maximum
    // rotations (what the estimator prices) — and, with --rotations N,
    // every airframe at the SAME frequency, which isolates seats alone.
    let fixed = option("--rotations").flatMap { $0 == "max" ? nil : Int($0) }
    var out: [Measurement] = []
    for (origin, destination) in pairs {
        for type in types {
            if let m = fly(origin, destination, type: type, roundTrips: fixed, incumbents: 0) {
                out.append(m)
            }
        }
    }
    report(out, title: "Phase 2 — offered capacity (rotations \(option("--rotations") ?? "max"))")

case "frequency":
    // Phase 3. One airframe, every valid frequency from 1 to its maximum.
    var out: [Measurement] = []
    for (origin, destination) in pairs {
        for type in types {
            guard let spec = catalog.aircraftType(type),
                  let distance = catalog.distanceKm(origin, destination) else { continue }
            let maxRotations = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
                distanceKm: distance, spec: spec, ops: catalog.tuning.ops)
            for trips in 1...max(1, maxRotations) {
                if let m = fly(origin, destination, type: type, roundTrips: trips,
                               incumbents: 0) { out.append(m) }
            }
        }
    }
    report(out, title: "Phase 3 — frequency")

case "competition":
    // Phase 4. One airframe at its maximum rotations, 0…N incumbents.
    let counts = (option("--incumbents") ?? "0,1,2,3").split(separator: ",").compactMap { Int($0) }
    var out: [Measurement] = []
    for (origin, destination) in pairs {
        for type in types {
            for count in counts {
                if let m = fly(origin, destination, type: type, roundTrips: nil,
                               incumbents: count) { out.append(m) }
            }
        }
    }
    report(out, title: "Phase 4 — competition")

case "airframe":
    // Phase 5 / 10. The AE-043 comparison: for each pair, every airframe
    // named, flown and estimated, so the ORDERING can be compared.
    var out: [Measurement] = []
    for (origin, destination) in pairs {
        for type in types {
            if let m = fly(origin, destination, type: type, roundTrips: nil, incumbents: 0) {
                out.append(m)
            }
        }
    }
    report(out, title: "Phase 5 — airframe-day value against the ledger")
    if !csv {
        print("\n   ranking agreement (best airframe by each measure):")
        for (origin, destination) in pairs {
            let group = out.filter { $0.origin == origin && $0.destination == destination }
            guard !group.isEmpty else { continue }
            let shipped = group.max { $0.shippedAfterOwnership < $1.shippedAfterOwnership }!
            let corrected = group.max { $0.correctedAfterOwnership < $1.correctedAfterOwnership }!
            let ledger = group.max { $0.actualAfterOwnership < $1.actualAfterOwnership }!
            print("   \(origin)-\(destination): shipped \(shipped.type) · corrected \(corrected.type) · ledger \(ledger.type)"
                  + "  [\(shipped.type == ledger.type ? "agree" : "DISAGREE")/\(corrected.type == ledger.type ? "agree" : "DISAGREE")]")
        }
    }

case "estimator":
    // No simulation: what the two estimators say, side by side. Cheap
    // enough to sweep the whole catalogue.
    print("pair,km,type,seats,rotations,estPaxShipped,estPaxCorrected,estProfitShipped,estProfitCorrected")
    for (origin, destination) in pairs {
        guard let originSpec = catalog.airport(origin),
              let destinationSpec = catalog.airport(destination),
              let distance = catalog.distanceKm(origin, destination) else { continue }
        var systems = GamePipeline.standard()
        systems.removeAll { $0.id == CompetitorAISystem().id }
        let engine = SimulationEngine(
            state: ScenarioBootstrap.newGame(scenario: "entrepreneur", worldSeed: seed,
                                             startYear: scenario.startYear),
            systems: systems, catalog: catalog)
        _ = engine.applyNow(FoundAirlineCommand(
            airlineName: "Subject Air", kind: .player, homeAirport: origin,
            startingCash: Money.dollars(400_000_000)))
        let state = engine.state
        let starter = DemandSystem.representativeStarterQuality(tuning: catalog.tuning.demand)
        func captured(_ from: AirportCode, _ to: AirportCode) -> Double {
            DemandSystem.expectedCapturedPassengers(
                pool: DemandSystem.demandPool(from: from, to: to, date: state.currentDate,
                                              economicIndex: state.world.economicIndex,
                                              catalog: catalog),
                fareRatio: 1.0, quality: starter, tuning: catalog.tuning.demand)
        }
        let shippedPassengers = captured(origin, destination) + captured(destination, origin)
        for type in types {
            guard let spec = catalog.aircraftType(type),
                  catalog.routeEligibility(from: origin, to: destination,
                                           aircraftRangeKm: spec.rangeKm,
                                           aircraftRunwayRequirement: spec.runwayRequirement).isEmpty
            else { continue }
            let rotations = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
                distanceKm: distance, spec: spec, ops: catalog.tuning.ops)
            guard rotations > 0 else { continue }
            let shippedProfit = CompetitorAISystem.airframeDayValue(
                distanceKm: distance, passengersPerDay: shippedPassengers, spec: spec,
                fareRatio: 1.0, serviceTier: .standard, origin: originSpec,
                destination: destinationSpec, state: state, catalog: catalog, basis: .profit)
            let corrected = correctedEstimate(
                origin: originSpec, destination: destinationSpec, distanceKm: distance,
                spec: spec, roundTrips: rotations, incumbents: [], state: state,
                serviceTier: .standard)
            print([
                "\(origin)-\(destination)", "\(distance)", "\(type)", "\(spec.seats)",
                "\(rotations)", f(shippedPassengers, 1), f(corrected.passengers, 1),
                f(shippedProfit), f(corrected.profit),
            ].joined(separator: ","))
        }
    }

case "lines":
    // Phase 5. Every line of the estimator's `.profit` arithmetic beside
    // the ledger's own, so the FIRST divergence can be located rather than
    // inferred from the bottom line.
    for (origin, destination) in pairs {
        for type in types {
            guard let m = fly(origin, destination, type: type,
                              roundTrips: estimateRotationsOption, incumbents: 0),
                  let spec = catalog.aircraftType(type),
                  let originSpec = catalog.airport(origin),
                  let destinationSpec = catalog.airport(destination) else { continue }
            let ops = catalog.tuning.ops
            let flights = Double(m.estimateRotations * 2)
            // The scheduler's own timing: cruise minutes, rounded, plus overhead.
            let blockHours = ((Double(m.distanceKm) / Double(spec.cruiseSpeedKmh) * 60).rounded()
                              + Double(ops.flightOverheadMinutes)) / 60
            func lines(_ carried: Double) -> [(String, Double)] {
                let fuelPrice = fuelPriceObserved ?? 0
                return [
                    ("passengers", carried),
                    ("revenue", carried * m.fare),
                    ("movement fees", flights * (originSpec.movementFee(for: spec, ops: ops).asDouble
                                                 + destinationSpec.movementFee(for: spec, ops: ops).asDouble)),
                    ("passenger fees", carried / 2 * (originSpec.passengerFee.asDouble
                                                      + destinationSpec.passengerFee.asDouble)),
                    ("fuel", flights * spec.fuelBurnKgPerKm * Double(m.distanceKm) / 1000 * fuelPrice),
                    ("crew", flights * blockHours
                        * (Double(spec.crewCockpit) * ops.crewCostPerBlockHourCockpit.asDouble
                           + Double(spec.crewCabin) * ops.crewCostPerBlockHourCabin.asDouble)),
                    ("maintenance", FleetEconomics.expectedMaintenancePerDay(
                        type: spec, ageYears: 0, blockHoursPerDay: flights * blockHours,
                        fleet: catalog.tuning.fleet, ops: ops)),
                    ("service", carried * catalog.tuning.reputation
                        .serviceCostPerPax(.standard).asDouble),
                ]
            }
            let shipped = lines(m.shippedCarried)
            let correctedLines = lines(min(m.correctedPassengers,
                                           flights * Double(spec.seats)))
            let d = m.flown.days
            let movementLedger = Double(m.flown.flights) / d
                * (originSpec.movementFee(for: spec, ops: ops).asDouble
                   + destinationSpec.movementFee(for: spec, ops: ops).asDouble)
            let ledger: [(String, Double)] = [
                ("passengers", m.actualPassengers),
                ("revenue", Double(m.flown.revenue) / 100 / d),
                ("movement fees", movementLedger),
                ("passenger fees", Double(m.flown.fees) / 100 / d - movementLedger),
                ("fuel", Double(m.flown.fuel) / 100 / d),
                ("crew", Double(m.flown.crew) / 100 / d),
                ("maintenance", Double(m.flown.maintenance) / 100 / d),
                ("service", Double(m.flown.service) / 100 / d),
            ]
            print("\n== \(origin)-\(destination) \(m.distanceKm) km · \(type) \(spec.seats) seats · "
                  + "priced \(m.estimateRotations) rot · flown \(m.roundTrips) rot · fare $\(Int(m.fare)) ==")
            print(pad("line", 17) + pad("shipped", 12, right: true)
                  + pad("corrected", 12, right: true) + pad("ledger", 12, right: true))
            for index in shipped.indices {
                print(pad(shipped[index].0, 17) + pad(f(shipped[index].1), 12, right: true)
                      + pad(f(correctedLines[index].1), 12, right: true)
                      + pad(f(ledger[index].1), 12, right: true))
            }
            print(pad("profit", 17) + pad(f(m.shippedProfit), 12, right: true)
                  + pad(f(m.correctedProfit), 12, right: true)
                  + pad(f(m.actualProfit), 12, right: true))
        }
    }

case "verify":
    // Is the corrected estimate the SAME allocation the engine performs?
    // Open a route, advance a day at a time, and compare the demand the
    // engine allocated that morning with the estimate computed for that
    // same date at the route's own quality. Any gap is arithmetic, not
    // modelling.
    let days = Int(option("--days") ?? "14") ?? 14
    print("pair,type,rot,incumbents,day,weekday,engineAllocated,estimate,ratio")
    for (origin, destination) in pairs {
        for type in types {
            for incumbentCount in (option("--incumbents") ?? "0,1")
                .split(separator: ",").compactMap({ Int($0) }) {
                guard let spec = catalog.aircraftType(type),
                      let originSpec = catalog.airport(origin),
                      let destinationSpec = catalog.airport(destination),
                      let distance = catalog.distanceKm(origin, destination),
                      catalog.routeEligibility(
                        from: origin, to: destination, aircraftRangeKm: spec.rangeKm,
                        aircraftRunwayRequirement: spec.runwayRequirement).isEmpty
                else { continue }
                let rotations = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
                    distanceKm: distance, spec: spec, ops: catalog.tuning.ops)
                guard rotations > 0 else { continue }
                var systems = GamePipeline.standard()
                systems.removeAll { $0.id == CompetitorAISystem().id }
                let engine = SimulationEngine(
                    state: ScenarioBootstrap.newGame(scenario: "entrepreneur", worldSeed: seed,
                                                     startYear: scenario.startYear),
                    systems: systems, catalog: catalog)
                let fare = DemandSystem.referenceFare(distanceKm: distance,
                                                      tuning: catalog.tuning.demand)
                let incumbentType = AircraftTypeCode(option("--incumbent-type") ?? "KT95")
                for index in 0..<incumbentCount {
                    guard engine.applyNow(FoundAirlineCommand(
                        airlineName: "Incumbent \(index + 1)", kind: .ai, homeAirport: origin,
                        startingCash: Money.dollars(400_000_000),
                        aiProfile: AIProfile(archetype: .regional))) == .applied,
                          let airline = engine.state.airlines.values.first(where: {
                              $0.name == "Incumbent \(index + 1)" }) else { continue }
                    guard engine.applyNow(LeaseAircraftCommand(
                        lessee: airline.id, type: incumbentType, termMonths: 60)) == .applied,
                          let aircraft = engine.state.fleet(of: airline.id).first else { continue }
                    guard engine.applyNow(OpenRouteCommand(
                        airline: airline.id, origin: origin, destination: destination,
                        dailyRoundTrips: 2, ticketPrice: Money(rounding: fare))) == .applied,
                          let route = engine.state.routes(of: airline.id).first else { continue }
                    _ = engine.applyNow(AssignAircraftToRouteCommand(
                        airline: airline.id, route: route.id, aircraftID: aircraft.id))
                }
                guard engine.applyNow(FoundAirlineCommand(
                    airlineName: "Subject Air", kind: .player, homeAirport: origin,
                    startingCash: Money.dollars(400_000_000))) == .applied,
                      let subject = engine.state.airlines.values.first(where: { $0.kind == .player })
                else { continue }
                guard engine.applyNow(LeaseAircraftCommand(
                    lessee: subject.id, type: type, termMonths: 60)) == .applied,
                      let aircraft = engine.state.fleet(of: subject.id).first else { continue }
                guard engine.applyNow(OpenRouteCommand(
                    airline: subject.id, origin: origin, destination: destination,
                    dailyRoundTrips: rotations, ticketPrice: Money(rounding: fare))) == .applied,
                      let route = engine.state.routes(of: subject.id).first else { continue }
                _ = engine.applyNow(AssignAircraftToRouteCommand(
                    airline: subject.id, route: route.id, aircraftID: aircraft.id))
                // The engine allocates a day's demand from the stats as they
                // stood when the day began; read them before advancing, or
                // the comparison is against a different offer.
                for day in 1...days {
                    let before = engine.state.routes[route.id]?.stats ?? RouteStats()
                    engine.advance(ticks: ticksPerDay)
                    let state = engine.state
                    guard let flown = state.routes[route.id] else { break }
                    let allocated = Double(flown.demandOutboundToday + flown.demandInboundToday)
                    let rivals = state.routes.values.filter {
                        $0.airline != subject.id
                            && $0.sameMarket(origin: origin, destination: destination)
                    }.sorted { $0.id.raw < $1.id.raw }
                    // The estimate at the route's OWN operations record and
                    // reputation, for the date the engine just allocated for —
                    // the raw 0…1 score `offerQualityTerms` takes, not the
                    // multiplier it returns.
                    let operationsScore = before.completionRate * 0.5
                        + before.punctuality * 0.5
                    let reputation = state.airlines[flown.airline]?.reputation
                        .demandMultiplier(tuning: catalog.tuning.reputation) ?? 1.0
                    let estimate = correctedEstimate(
                        origin: originSpec, destination: destinationSpec, distanceKm: distance,
                        spec: spec, roundTrips: rotations, incumbents: rivals, state: state,
                        serviceTier: subject.serviceTier,
                        operationsOverride: operationsScore,
                        reputationMultiplier: reputation)
                    print([
                        "\(origin)-\(destination)", "\(type)", "\(rotations)", "\(incumbentCount)",
                        "\(day)", "\(state.currentDate.weekday)", f(allocated, 1),
                        f(estimate.passengers, 1),
                        f(allocated > 0 ? estimate.passengers / allocated : 0, 4),
                    ].joined(separator: ","))
                }
            }
        }
    }

default:
    print("modes: capacity | frequency | competition | airframe | estimator | verify")
}
