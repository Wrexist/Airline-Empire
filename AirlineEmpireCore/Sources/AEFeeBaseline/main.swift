import Foundation
import AirlineEmpireCore

// Fee economy baseline (AE-040 "The fee economy and the regional archetype").
//
//   swift run -c release ae-fee-baseline [--pairs LHR-CDG,ARN-LHR,…]
//                                        [--types NA70,AV90,MR180,MR300]
//                                        [--rotations max|N] [--seed 2039]
//                                        [--ai regional] [--csv]
//
// For every pair × type it builds a fresh deterministic world with one
// airline flying that one route at the reference fare, lets it fly January
// and February through the real pipeline, and reads February back from the
// route's closed month and the airline's monthly statement: revenue,
// airport fees (split into the movement and passenger parts), fuel, crew,
// onboard service, maintenance checks, the lease, payroll and overhead.
// Beside each booked month it prints what the AI's estimator
// (`CompetitorAISystem.airframeDayValue`, profit basis) would have said
// for the same route, both with the demand engine's own forecast and with
// the passengers the month actually carried, so the estimator's demand
// error and its cost error can be told apart.
//
// `--ai regional` founds the airline as an AI of that archetype instead of
// a player, with the competitor system left out of the pipeline so it
// cannot reshape the network — the same flights under the other owner
// kind, for the parity check. Nothing here changes the simulation.

let arguments = CommandLine.arguments
func option(_ flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1)
    else { return nil }
    return arguments[index + 1]
}
let csv = arguments.contains("--csv")
let seed = UInt64(option("--seed") ?? "2039") ?? 2039
let rotationsOption = option("--rotations") ?? "max"
/// `--months N`: measure N months after the January ramp (default 1, i.e.
/// February) and report the average month; a year shows the maintenance
/// checks the first month never reaches.
let measuredMonths = max(1, Int(option("--months") ?? "1") ?? 1)
let aiArchetype: AIArchetype? = option("--ai").flatMap { AIArchetype(rawValue: $0) }

/// The default battery: short, medium, long and very long pairs at real
/// airports across fee levels, all at large-or-better runways so every
/// type can land.
let defaultPairs = [
    // short (< 500 km)
    "LHR-CDG", "ARN-HEL", "MUC-VIE", "JFK-BOS", "CDG-AMS", "ARN-GOT", "CGK-SIN",
    // medium (700–1,600 km)
    "ORD-YYZ", "JFK-ORD", "ARN-LHR", "MUC-IST", "IST-ATH", "BCN-LHR", "TOS-ARN",
    // long (2,500–6,000 km)
    "LHR-DXB", "LHR-JFK", "SIN-HND", "JFK-LAX",
    // very long (> 9,000 km)
    "LHR-SIN", "SYD-LAX",
]
let pairs: [(AirportCode, AirportCode)] = (option("--pairs")?.split(separator: ",").map(String.init)
    ?? defaultPairs).compactMap { pair in
    let ends = pair.split(separator: "-")
    guard ends.count == 2 else { return nil }
    return (AirportCode(String(ends[0])), AirportCode(String(ends[1])))
}
let types: [AircraftTypeCode] = (option("--types")?.split(separator: ",").map(String.init)
    ?? ["NA70", "AV90", "MR180", "MR300"]).map { AircraftTypeCode($0) }

let catalog = try ContentCatalog.loadBundled()
guard let scenario = catalog.scenario("entrepreneur") else { fatalError("no entrepreneur scenario") }
let ticksPerDay = Int(GameCalendar.minutesPerDay / ScenarioBootstrap.standardTickMinutes)

struct Booked {
    var flights = 0
    var passengers: Int64 = 0
    var seatsFlown: Int64 = 0
    var revenue: Int64 = 0
    var fuel: Int64 = 0
    var fees: Int64 = 0
    var crew: Int64 = 0
    var service: Int64 = 0
    var maintenance: Int64 = 0
    var lease: Int64 = 0
    var salaries: Int64 = 0
    var overhead: Int64 = 0
}

struct RunResult {
    let origin: AirportCode
    let destination: AirportCode
    let distanceKm: Int
    let type: AircraftTypeCode
    let seats: Int
    let rotations: Int
    let fare: Double
    let booked: Booked
    let daysPerMonth: Double
    let fuelPricePerTon: Double
    let movementFeePerFlight: Double
    let passengerFeeAverage: Double
    /// The estimator with the demand engine's forecast of passengers.
    let estimateForecast: (passengers: Double, revenue: Double, costs: Double, profit: Double)
    /// The estimator with the passengers the month actually carried.
    let estimateActual: (revenue: Double, costs: Double, profit: Double)
}

func skipped(_ reason: String) {
    FileHandle.standardError.write(("skipped " + reason + "\n").data(using: .utf8)!)
}

/// Fly one route for January and February; return February.
@MainActor
func fly(_ origin: AirportCode, _ destination: AirportCode, type: AircraftTypeCode) -> RunResult? {
    guard let spec = catalog.aircraftType(type),
          let originSpec = catalog.airport(origin),
          let destinationSpec = catalog.airport(destination),
          let distance = catalog.distanceKm(origin, destination) else {
        skipped("\(origin)-\(destination) \(type): unknown airport or type"); return nil
    }
    let eligibility = catalog.routeEligibility(from: origin, to: destination,
                                               aircraftRangeKm: spec.rangeKm,
                                               aircraftRunwayRequirement: spec.runwayRequirement)
    guard eligibility.isEmpty else {
        skipped("\(origin)-\(destination) \(type): ineligible \(eligibility)"); return nil
    }
    let maxRotations = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
        distanceKm: distance, spec: spec, ops: catalog.tuning.ops)
    guard maxRotations > 0 else {
        skipped("\(origin)-\(destination) \(type): no rotation fits the operating day"); return nil
    }
    let rotations = rotationsOption == "max" ? maxRotations : min(maxRotations, Int(rotationsOption) ?? 2)

    // The standard pipeline; without the competitor system when the
    // airline is an AI, so the archetype's own decisions cannot add a
    // second route or a second airframe to what is being measured.
    var systems = GamePipeline.standard()
    if aiArchetype != nil { systems.removeAll { $0.id == CompetitorAISystem().id } }
    let engine = SimulationEngine(
        state: ScenarioBootstrap.newGame(scenario: "entrepreneur", worldSeed: seed,
                                         startYear: scenario.startYear),
        systems: systems, catalog: catalog)
    let found: CommandResult
    if let aiArchetype {
        found = engine.applyNow(FoundAirlineCommand(
            airlineName: "Baseline Air", kind: .ai, homeAirport: origin,
            startingCash: Money.dollars(200_000_000),
            aiProfile: AIProfile(archetype: aiArchetype)))
    } else {
        found = engine.applyNow(FoundAirlineCommand(
            airlineName: "Baseline Air", kind: .player, homeAirport: origin,
            startingCash: Money.dollars(200_000_000)))
    }
    guard found == .applied, let airline = engine.state.airlines.values.first else {
        skipped("\(origin)-\(destination) \(type): founding \(found)"); return nil
    }
    let lease = engine.applyNow(LeaseAircraftCommand(lessee: airline.id, type: type, termMonths: 60))
    guard lease == .applied, let aircraft = engine.state.fleet(of: airline.id).first else {
        skipped("\(origin)-\(destination) \(type): lease \(lease)"); return nil
    }
    let fare = DemandSystem.referenceFare(distanceKm: distance, tuning: catalog.tuning.demand)
    let open = engine.applyNow(OpenRouteCommand(
        airline: airline.id, origin: origin, destination: destination,
        dailyRoundTrips: rotations, ticketPrice: Money(rounding: fare)))
    guard open == .applied, let route = engine.state.routes(of: airline.id).first else {
        skipped("\(origin)-\(destination) \(type): open \(open)"); return nil
    }
    let assign = engine.applyNow(AssignAircraftToRouteCommand(
        airline: airline.id, route: route.id, aircraftID: aircraft.id))
    guard assign == .applied else {
        skipped("\(origin)-\(destination) \(type): assign \(assign)"); return nil
    }

    // January is the ramp; the months after it are measured, and the
    // figures reported are the average month.
    var flightsAtStart = 0
    var seatsAtStart: Int64 = 0
    var fuelPrices: [Double] = []
    var booked = Booked()
    var monthsClosed = 0
    var lastMonth = engine.state.currentDate.month
    var lastPassengers: Int64 = 0
    var daysMeasured = 0
    while monthsClosed < 1 + measuredMonths {
        engine.advance(ticks: ticksPerDay)
        let now = engine.state.currentDate
        if now.month != lastMonth {
            monthsClosed += 1
            lastMonth = now.month
            guard let r = engine.state.routes[route.id] else { return nil }
            if monthsClosed == 1 {
                flightsAtStart = Int(r.stats.flightsCompleted)
                seatsAtStart = r.stats.seatsFlown
            } else if let statement = engine.state.finance.byAirline[airline.id]?.statements.last {
                // The month just closed: the route's closed figures and the
                // airline's statement for it.
                let month = r.economicsLastMonth
                booked.passengers += month.passengers
                booked.revenue += month.revenueCents
                booked.fuel += month.fuelCents
                booked.fees += month.feesCents
                booked.crew += month.crewCents
                booked.service += -statement.total(.passengerService).cents
                booked.maintenance += -statement.total(.maintenance).cents
                booked.lease += -statement.total(.leasePayment).cents
                booked.salaries += -statement.total(.salaries).cents
                booked.overhead += -statement.total(.overhead).cents
                lastPassengers = month.passengers
            }
        }
        if monthsClosed >= 1 {
            daysMeasured += 1
            fuelPrices.append(engine.state.world.fuelPricePerTon.asDouble)
        }
    }
    // The boundary day that ended the loop belongs to the month after.
    daysMeasured -= 1
    let daysPerMonth = Double(daysMeasured) / Double(measuredMonths)
    let state = engine.state
    guard let flown = state.routes[route.id] else { return nil }
    booked.flights = Int(flown.stats.flightsCompleted) - flightsAtStart
    booked.seatsFlown = flown.stats.seatsFlown - seatsAtStart
    // Averages per month, so a year reads like a month.
    let n = Int64(measuredMonths)
    booked.flights /= measuredMonths
    booked.passengers /= n; booked.seatsFlown /= n; booked.revenue /= n; booked.fuel /= n
    booked.fees /= n; booked.crew /= n; booked.service /= n; booked.maintenance /= n
    booked.lease /= n; booked.salaries /= n; booked.overhead /= n
    let month = booked
    _ = lastPassengers

    // The estimator, on the AI's profit basis, for one airframe day at
    // the rotations flown: with the demand engine's forecast, and with
    // the passengers the month actually carried per day.
    let quality = DemandSystem.offerQualityTerms(route: flown, state: state, catalog: catalog)?.product ?? 1
    let pool = DemandSystem.demandPool(from: origin, to: destination, date: state.currentDate,
                                       economicIndex: state.world.economicIndex, catalog: catalog)
    let forecast = DemandSystem.expectedCapturedPassengers(
        pool: pool, fareRatio: 1.0, quality: quality, tuning: catalog.tuning.demand)
    func estimate(passengersPerDay: Double) -> (revenue: Double, costs: Double, profit: Double) {
        let revenue = CompetitorAISystem.airframeDayValue(
            distanceKm: distance, passengersPerDay: passengersPerDay, spec: spec, fareRatio: 1.0,
            serviceTier: airline.serviceTier, origin: originSpec, destination: destinationSpec,
            state: state, catalog: catalog, rotationsPerDay: rotations, basis: .revenue)
        let profit = CompetitorAISystem.airframeDayValue(
            distanceKm: distance, passengersPerDay: passengersPerDay, spec: spec, fareRatio: 1.0,
            serviceTier: airline.serviceTier, origin: originSpec, destination: destinationSpec,
            state: state, catalog: catalog, rotationsPerDay: rotations, basis: .profit)
        return (revenue, revenue - profit, profit)
    }
    let withForecast = estimate(passengersPerDay: forecast)
    let withActual = estimate(passengersPerDay: Double(month.passengers) / daysPerMonth)
    let averageFuel = fuelPrices.isEmpty ? state.world.fuelPricePerTon.asDouble
        : fuelPrices.reduce(0, +) / Double(fuelPrices.count)
    return RunResult(
        origin: origin, destination: destination, distanceKm: distance, type: type,
        seats: spec.seats, rotations: rotations, fare: fare, booked: booked,
        daysPerMonth: daysPerMonth, fuelPricePerTon: averageFuel,
        movementFeePerFlight: originSpec.movementFee.asDouble + destinationSpec.movementFee.asDouble,
        passengerFeeAverage: (originSpec.passengerFee.asDouble + destinationSpec.passengerFee.asDouble) / 2,
        estimateForecast: (forecast, withForecast.revenue, withForecast.costs, withForecast.profit),
        estimateActual: withActual)
}

func dollars(_ cents: Int64) -> String {
    let value = Double(cents) / 100
    if abs(value) >= 1_000_000 { return String(format: "%.2fM", value / 1_000_000) }
    if abs(value) >= 1_000 { return String(format: "%.0fk", value / 1_000) }
    return String(format: "%.0f", value)
}
func pct(_ numerator: Double, _ denominator: Double) -> String {
    denominator == 0 ? "—" : String(format: "%.0f%%", numerator / denominator * 100)
}

// MARK: - Candidate evaluation (the regional archetype battery)

/// `--candidates all|HOME,HOME`: for each home, found one AI airline of
/// `--profile` (default regional) there with one airframe of each type,
/// and ask the AI's own evaluation (`CompetitorAISystem.candidateMarkets`)
/// what it sees in its horizon on both ranking bases. No simulation runs;
/// this is the decision the archetype makes on its first day.
if let candidateHomes = option("--candidates") {
    let profileName = option("--profile") ?? "regional"
    let profile = AIProfile(archetype: AIArchetype(rawValue: profileName) ?? .regional)
    let homes: [AirportCode] = candidateHomes == "all"
        ? catalog.orderedAirportCodes.filter { (catalog.airport($0)?.runwayClass ?? .small) >= .large }
        : candidateHomes.split(separator: ",").map { AirportCode(String($0)) }
    let day = Int(option("--day") ?? "1") ?? 1
    /// `--detail`: one CSV row per scored candidate with every line of the
    /// estimator's arithmetic, so alternative fee and maintenance rules can
    /// be evaluated on the same candidates without touching the engine.
    let detail = arguments.contains("--detail")
    if csv, detail {
        print("home,type,dest,km,rotations,seats,fare,carried,revenue,movementFees,paxFees,fuel,crew,maintenance,service,profit,homeMovementFee,destMovementFee,homePaxFee,destPaxFee,blockHours")
    } else if csv {
        print("home,region,type,horizon,regionExcluded,ineligible,belowFloor,unprofitable,profitable,bestDest,bestKm,bestProfitDay,bestFeeShare,bestRevenueDay,worstDest,worstProfitDay,bestRevenueRankDest,bestRevenueRankProfitDay")
    }
    for home in homes {
        guard let homeSpec = catalog.airport(home) else { continue }
        var systems = GamePipeline.standard()
        systems.removeAll { $0.id == CompetitorAISystem().id }
        let engine = SimulationEngine(
            state: ScenarioBootstrap.newGame(scenario: "entrepreneur", worldSeed: seed,
                                             startYear: scenario.startYear),
            systems: systems, catalog: catalog)
        guard engine.applyNow(FoundAirlineCommand(
            airlineName: "Battery Air", kind: .ai, homeAirport: home,
            startingCash: Money.dollars(120_000_000), aiProfile: profile)) == .applied,
              let airline = engine.state.airlines.values.first else { continue }
        if day > 1 { engine.advance(ticks: ticksPerDay * (day - 1)) }
        let state = engine.state
        for type in types {
            guard let spec = catalog.aircraftType(type) else { continue }
            CompetitorAISystem.rankingBasis = .profit
            let byProfit = CompetitorAISystem.candidateMarkets(
                from: home, airline: airline, spec: spec, profile: profile, state: state,
                catalog: catalog, tuning: catalog.tuning.ai)
            CompetitorAISystem.rankingBasis = .revenue
            let byRevenue = CompetitorAISystem.candidateMarkets(
                from: home, airline: airline, spec: spec, profile: profile, state: state,
                catalog: catalog, tuning: catalog.tuning.ai)
            var regionExcluded = 0, ineligible = 0, belowFloor = 0, unprofitable = 0, profitable = 0
            var scored: [(AirportCode, Int, Double, Double, Double)] = []   // dest, km, profit, feeShare, revenue
            for (index, candidate) in byProfit.enumerated() {
                switch candidate.verdict {
                case .regionExcluded: regionExcluded += 1
                case .ineligible: ineligible += 1
                case .alreadyServed, .noSlots: break
                case .belowFloor: belowFloor += 1
                case .unprofitable(let value), .scored(let value):
                    if value > 0 { profitable += 1 } else { unprofitable += 1 }
                    let revenue = byRevenue[index].score ?? 0
                    // Fees for one airframe day on this candidate, as the
                    // estimator charges them.
                    guard let destination = catalog.airport(candidate.destination) else { continue }
                    let rotations = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
                        distanceKm: candidate.distanceKm, spec: spec, ops: catalog.tuning.ops)
                    let flights = Double(rotations * 2)
                    let fare = DemandSystem.referenceFare(distanceKm: candidate.distanceKm,
                                                         tuning: catalog.tuning.demand) * profile.priceFactor
                    let carried = fare > 0 ? revenue / fare : 0
                    let fees = flights * (homeSpec.movementFee.asDouble + destination.movementFee.asDouble)
                        + carried / 2 * (homeSpec.passengerFee.asDouble + destination.passengerFee.asDouble)
                    scored.append((candidate.destination, candidate.distanceKm, value,
                                   revenue > 0 ? fees / revenue : 0, revenue))
                    if csv, detail {
                        let ops = catalog.tuning.ops
                        // The scheduler's own timing: cruise minutes, rounded, plus overhead.
                        let blockHours = ((Double(candidate.distanceKm) / Double(spec.cruiseSpeedKmh) * 60).rounded()
                                          + Double(ops.flightOverheadMinutes)) / 60
                        let fuel = flights * spec.fuelBurnKgPerKm * Double(candidate.distanceKm) / 1000
                            * state.world.fuelPricePerTon.asDouble
                        let movement = flights * (homeSpec.movementFee.asDouble + destination.movementFee.asDouble)
                        let paxFees = carried / 2 * (homeSpec.passengerFee.asDouble + destination.passengerFee.asDouble)
                        let crew = flights * blockHours
                            * (Double(spec.crewCockpit) * ops.crewCostPerBlockHourCockpit.asDouble
                               + Double(spec.crewCabin) * ops.crewCostPerBlockHourCabin.asDouble)
                        let maintenance = flights * blockHours * spec.maintenancePerFlightHour.asDouble
                        let service = carried * catalog.tuning.reputation.serviceCostPerPax(airline.serviceTier).asDouble
                        var fields = [home.description, type.description, candidate.destination.description]
                        fields.append("\(candidate.distanceKm)"); fields.append("\(rotations)"); fields.append("\(spec.seats)")
                        fields.append(String(format: "%.2f", fare)); fields.append(String(format: "%.1f", carried))
                        fields.append(String(format: "%.0f", revenue)); fields.append(String(format: "%.0f", movement))
                        fields.append(String(format: "%.0f", paxFees)); fields.append(String(format: "%.0f", fuel))
                        fields.append(String(format: "%.0f", crew)); fields.append(String(format: "%.0f", maintenance))
                        fields.append(String(format: "%.0f", service)); fields.append(String(format: "%.0f", value))
                        fields.append(String(format: "%.0f", homeSpec.movementFee.asDouble)); fields.append(String(format: "%.0f", destination.movementFee.asDouble))
                        fields.append(String(format: "%.0f", homeSpec.passengerFee.asDouble)); fields.append(String(format: "%.0f", destination.passengerFee.asDouble))
                        fields.append(String(format: "%.2f", blockHours))
                        print(fields.joined(separator: ","))
                    }
                }
            }
            let best = scored.max { $0.2 < $1.2 }
            let worst = scored.min { $0.2 < $1.2 }
            let bestByRevenue = scored.max { $0.4 < $1.4 }
            if csv, detail {
                // rows already printed per candidate
            } else if csv {
                var fields: [String] = [home.description, "\(homeSpec.region)", type.description]
                fields.append("\(byProfit.count)")
                fields.append("\(regionExcluded)")
                fields.append("\(ineligible)")
                fields.append("\(belowFloor)")
                fields.append("\(unprofitable)")
                fields.append("\(profitable)")
                fields.append(best?.0.description ?? "")
                fields.append(best.map { "\($0.1)" } ?? "")
                fields.append(best.map { String(format: "%.0f", $0.2) } ?? "")
                fields.append(best.map { String(format: "%.2f", $0.3) } ?? "")
                fields.append(best.map { String(format: "%.0f", $0.4) } ?? "")
                fields.append(worst?.0.description ?? "")
                fields.append(worst.map { String(format: "%.0f", $0.2) } ?? "")
                fields.append(bestByRevenue?.0.description ?? "")
                fields.append(bestByRevenue.map { String(format: "%.0f", $0.2) } ?? "")
                print(fields.joined(separator: ","))
            } else {
                print("\(home) (\(homeSpec.region)) \(type): \(byProfit.count) in horizon · region-excluded \(regionExcluded) · ineligible \(ineligible) · below floor \(belowFloor) · unprofitable \(unprofitable) · profitable \(profitable)")
                for c in scored.sorted(by: { $0.2 > $1.2 }) {
                    print(String(format: "    %@ %d km · profit/day %.0f · revenue/day %.0f · fees %.0f%% of revenue", c.0.description, c.1, c.2, c.4, c.3 * 100))
                }
            }
        }
    }
    exit(0)
}

var results: [RunResult] = []
for (origin, destination) in pairs {
    for type in types {
        if let result = fly(origin, destination, type: type) { results.append(result) }
    }
}

if csv {
    print("pair,km,type,seats,rotations,fare,flights,pax,load,revenue,fees,movementFees,paxFees,fuel,crew,service,maintenance,lease,salaries,overhead,direct,feeOverRevenue,feeOverDirectCosts,margin,estForecastPax,estForecastProfitDay,estActualProfitDay,realProfitDay,fuelPrice")
}
for r in results {
    let b = r.booked
    let movement = Double(b.flights) * r.movementFeePerFlight
    let paxFees = Double(b.fees) / 100 - movement
    let directCosts = b.fuel + b.fees + b.crew
    let direct = b.revenue - directCosts
    let fullCosts = directCosts + b.service + b.maintenance + b.lease + b.salaries + b.overhead
    let operating = b.revenue - fullCosts
    let load = b.seatsFlown > 0 ? Double(b.passengers) / Double(b.seatsFlown) : 0
    let realProfitDay = Double(direct - b.service - b.maintenance) / 100 / r.daysPerMonth
    if csv {
        print([
            "\(r.origin)-\(r.destination)", "\(r.distanceKm)", "\(r.type)", "\(r.seats)", "\(r.rotations)",
            String(format: "%.0f", r.fare), "\(b.flights)", "\(b.passengers)", String(format: "%.3f", load),
            "\(b.revenue / 100)", "\(b.fees / 100)", String(format: "%.0f", movement), String(format: "%.0f", paxFees),
            "\(b.fuel / 100)", "\(b.crew / 100)", "\(b.service / 100)", "\(b.maintenance / 100)",
            "\(b.lease / 100)", "\(b.salaries / 100)", "\(b.overhead / 100)", "\(direct / 100)",
            String(format: "%.3f", b.revenue > 0 ? Double(b.fees) / Double(b.revenue) : 0),
            String(format: "%.3f", directCosts > 0 ? Double(b.fees) / Double(directCosts) : 0),
            String(format: "%.3f", b.revenue > 0 ? Double(operating) / Double(b.revenue) : 0),
            String(format: "%.0f", r.estimateForecast.passengers),
            String(format: "%.0f", r.estimateForecast.profit), String(format: "%.0f", r.estimateActual.profit),
            String(format: "%.0f", realProfitDay), String(format: "%.0f", r.fuelPricePerTon),
        ].joined(separator: ","))
        continue
    }
    print("\(r.origin)-\(r.destination) \(r.distanceKm) km · \(r.type) \(r.seats) seats · \(r.rotations)×/day · fare $\(Int(r.fare))")
    print("  per month (\(measuredMonths) measured, \(String(format: "%.1f", r.daysPerMonth)) days each): \(b.flights) flights, \(b.passengers) pax, load \(pct(Double(b.passengers), Double(b.seatsFlown)))")
    print("  revenue \(dollars(b.revenue)) · fees \(dollars(b.fees)) (movement \(dollars(Int64(movement * 100))) + pax \(dollars(Int64(paxFees * 100)))) · fuel \(dollars(b.fuel)) · crew \(dollars(b.crew))")
    print("  service \(dollars(b.service)) · maintenance \(dollars(b.maintenance)) · lease \(dollars(b.lease)) · payroll \(dollars(b.salaries)) · overhead \(dollars(b.overhead))")
    print("  direct operating profit \(dollars(direct)) · after everything \(dollars(operating)) (margin \(pct(Double(operating), Double(b.revenue))))")
    print("  fees / revenue \(pct(Double(b.fees), Double(b.revenue))) · fees / direct costs \(pct(Double(b.fees), Double(directCosts))) · fuel $\(Int(r.fuelPricePerTon))/t")
    print("  estimator/day: forecast \(Int(r.estimateForecast.passengers)) pax → profit \(Int(r.estimateForecast.profit)); actual pax → profit \(Int(r.estimateActual.profit)); booked (direct − service − maintenance) \(Int(realProfitDay))")
}
