import Foundation
import AirlineEmpireCore

// Can a new player trust Next Moves? (AE-042, BUG-055)
//
//   swift run -c release ae-advice audit  [--homes ARN,BCN,SIN,JFK] [--seed 2030]
//   swift run -c release ae-advice follow [--homes …] [--seeds 2030-2059] [--days 500]
//   swift run -c release ae-advice sweep  [--seed 2030]
//
// The recommendations printed here are exactly the ones the game makes:
// `GameState.marketOpportunities`, narrowed the way `NextMovesCard` narrows
// them (rank four, keep the servable ones, take two). Nothing in this tool
// changes the simulation; the economics are the flight system's own
// arithmetic ahead of time (`CompetitorAISystem.airframeDayValue`), and in
// `follow` the campaign is played through real commands and read back from
// the ledger.
//
// AE-042: written to measure BUG-055 before deciding whether the ranking,
// the eligibility filter, or something else is at fault.

let arguments = CommandLine.arguments
let mode = arguments.count > 1 ? arguments[1] : "audit"
func option(_ flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1)
    else { return nil }
    return arguments[index + 1]
}
let seedRange: ClosedRange<UInt64> = {
    guard let raw = option("--seeds") ?? option("--seed") else { return 2030...2030 }
    let parts = raw.split(separator: "-").compactMap { UInt64($0) }
    return parts.count == 2 ? parts[0]...parts[1] : (parts.first ?? 2030)...(parts.first ?? 2030)
}()
let days = Int(option("--days") ?? "500") ?? 500
let scenarioName = option("--scenario") ?? "entrepreneur"
let scenarioCode = ScenarioCode(scenarioName)
/// How the trusting player acquires: the cheapest era-legal type that can fly
/// the route (the cash-preserving choice the game itself advises — "leasing
/// keeps cash free early on"), the largest one, or a named type.
let acquireRule = option("--acquire") ?? "cheapest"
let forcedType = option("--type").map { AircraftTypeCode($0) }
let verbose = arguments.contains("--verbose")
/// `--rank keeps`: the counterfactual. The same candidates production
/// already gates (origins, already-served, eligibility, positive pool), in a
/// different order — by what a market keeps after the aircraft it needs,
/// dropping the ones that keep nothing. Measured here before any production
/// change, so the fix can be argued from a campaign rather than a formula.
let rankRule = option("--rank") ?? "passengers"

let catalog = try ContentCatalog.loadBundled()
guard let scenario = catalog.scenario(scenarioCode) else {
    fatalError("no scenario \(scenarioName)")
}
let ticksPerDay = Int(GameCalendar.minutesPerDay / ScenarioBootstrap.standardTickMinutes)
let defaultHomes: [AirportCode] = ["ARN", "BCN", "SIN", "JFK"]
let homes: [AirportCode] = (option("--homes")?.split(separator: ",").map {
    AirportCode(String($0))
}) ?? defaultHomes

// MARK: - What a recommendation is worth

/// One market, one airframe: what the flight system would post for it, a day
/// at a time, and what the aircraft costs to hold.
struct Economics {
    let spec: AircraftTypeSpec
    let rotations: Int
    let poolPerDay: Double
    let carriedPerDay: Double
    let farePerSeat: Double
    let revenuePerDay: Double
    let directPerDay: Double
    let feesPerDay: Double
    let leaseMonthly: Double
    let usedPrice: Double
    let payrollMonthly: Double

    /// Thirty days of the route's own operating result.
    var directMonthly: Double { directPerDay * 30 }
    /// The same, after the aircraft it needs and the crew it carries — the
    /// number that decides whether a first route builds an airline.
    var afterOwnershipMonthly: Double { directMonthly - leaseMonthly - payrollMonthly }
    var feeShare: Double { revenuePerDay > 0 ? feesPerDay / revenuePerDay : 0 }
}

/// The flight system's arithmetic ahead of time, for one candidate airframe.
@MainActor
func economics(origin: AirportCode, destination: AirportCode, distanceKm: Int,
               spec: AircraftTypeSpec, state: GameState) -> Economics? {
    guard let originSpec = catalog.airport(origin),
          let destinationSpec = catalog.airport(destination) else { return nil }
    let ops = catalog.tuning.ops
    let rotations = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
        distanceKm: distanceKm, spec: spec, ops: ops)
    guard rotations > 0 else { return nil }
    let quality = DemandSystem.representativeStarterQuality(tuning: catalog.tuning.demand)
    func captured(_ from: AirportCode, _ to: AirportCode) -> Double {
        DemandSystem.expectedCapturedPassengers(
            pool: DemandSystem.demandPool(from: from, to: to, date: state.currentDate,
                                          economicIndex: state.world.economicIndex,
                                          catalog: catalog),
            fareRatio: 1.0, quality: quality, tuning: catalog.tuning.demand)
    }
    let pool = captured(origin, destination) + captured(destination, origin)
    let flights = Double(rotations * 2)
    let carried = min(pool, flights * Double(spec.seats))
    let fare = DemandSystem.referenceFare(distanceKm: distanceKm,
                                          tuning: catalog.tuning.demand)
    // The shipped estimator, on both bases — one economy, not two.
    let revenue = CompetitorAISystem.airframeDayValue(
        distanceKm: distanceKm, passengersPerDay: pool, spec: spec, fareRatio: 1.0,
        serviceTier: .standard, origin: originSpec, destination: destinationSpec,
        state: state, catalog: catalog, basis: .revenue)
    let direct = CompetitorAISystem.airframeDayValue(
        distanceKm: distanceKm, passengersPerDay: pool, spec: spec, fareRatio: 1.0,
        serviceTier: .standard, origin: originSpec, destination: destinationSpec,
        state: state, catalog: catalog, basis: .profit)
    let fees = flights * (originSpec.movementFee(for: spec, ops: ops).asDouble
                          + destinationSpec.movementFee(for: spec, ops: ops).asDouble)
        + carried / 2 * (originSpec.passengerFee.asDouble + destinationSpec.passengerFee.asDouble)
    let fleetTuning = catalog.tuning.fleet
    let used = FleetEconomics.usedPrice(
        type: spec, ageYears: 8,
        condition: FleetEconomics.usedMarketCondition(ageYears: 8, tuning: fleetTuning),
        tuning: fleetTuning)
    return Economics(
        spec: spec, rotations: rotations, poolPerDay: pool, carriedPerDay: carried,
        farePerSeat: fare, revenuePerDay: revenue, directPerDay: direct,
        feesPerDay: fees, leaseMonthly: spec.leaseMonthly.asDouble,
        usedPrice: used.asDouble,
        payrollMonthly: catalog.tuning.finance.payrollPerAircraftMonthly.asDouble)
}

/// Era-legal types that can actually fly the pair, cheapest list price first.
@MainActor
func flyableTypes(origin: AirportCode, destination: AirportCode,
                  state: GameState) -> [AircraftTypeSpec] {
    let allowed = state.progression.era.allowedCategories
    return catalog.orderedAircraftTypeCodes
        .compactMap { catalog.aircraftTypes[$0] }
        .filter { allowed.contains($0.category) }
        .filter {
            catalog.routeEligibility(from: origin, to: destination,
                                     aircraftRangeKm: $0.rangeKm,
                                     aircraftRunwayRequirement: $0.runwayRequirement).isEmpty
        }
        .sorted { ($0.listPrice.cents, $0.code.raw) < ($1.listPrice.cents, $1.code.raw) }
}

/// The best an era-legal airframe can do on the pair, by monthly result after
/// the aircraft it needs. Nil when nothing in the era can fly it.
@MainActor
func bestEconomics(origin: AirportCode, destination: AirportCode, distanceKm: Int,
                   state: GameState) -> Economics? {
    flyableTypes(origin: origin, destination: destination, state: state)
        .compactMap { economics(origin: origin, destination: destination,
                                distanceKm: distanceKm, spec: $0, state: state) }
        .max { $0.afterOwnershipMonthly < $1.afterOwnershipMonthly }
}

/// What the trusting player would lease for a route.
@MainActor
func acquisitionChoice(origin: AirportCode, destination: AirportCode,
                       state: GameState) -> AircraftTypeSpec? {
    let flyable = flyableTypes(origin: origin, destination: destination, state: state)
    if let forcedType { return flyable.first { $0.code == forcedType } }
    switch acquireRule {
    case "biggest": return flyable.max { $0.seats < $1.seats }
    case "best":
        return flyable.compactMap { spec in
            economics(origin: origin, destination: destination,
                      distanceKm: catalog.distanceKm(origin, destination) ?? 0,
                      spec: spec, state: state).map { ($0, spec) }
        }.max { $0.0.afterOwnershipMonthly < $1.0.afterOwnershipMonthly }?.1
    default: return flyable.first          // cheapest list price
    }
}

/// The verdict on a recommendation, from its own economics. The classes are
/// the phase's, the boundaries are the game's own: a route that cannot pay
/// for the aircraft it needs is the trap BUG-055 describes, and the balance
/// design's operating band (docs/GAME_BALANCE.md §1) is 3–8%.
enum Verdict: String {
    case unflyable = "UNFLYABLE"          // no era-legal airframe can fly it
    case dangerous = "DANGEROUS"          // loses money after its own aircraft
    case marginal = "MARGINAL"            // pays for the aircraft, under a month of lease spare
    case viable = "VIABLE"                // clears its aircraft with room
    case safe = "SAFE"                    // clears it several times over
}

func verdict(_ economics: Economics?) -> Verdict {
    guard let economics else { return .unflyable }
    let after = economics.afterOwnershipMonthly
    if after <= 0 { return .dangerous }
    if after < economics.leaseMonthly { return .marginal }
    if after < economics.leaseMonthly * 3 { return .viable }
    return .safe
}

// MARK: - The world a recommendation is read in

@MainActor
func foundedWorld(seed: UInt64, home: AirportCode) -> SimulationEngine {
    let engine = SimulationEngine(
        state: ScenarioBootstrap.newGame(scenario: scenarioCode, worldSeed: seed,
                                         startYear: scenario.startYear),
        systems: GamePipeline.standard(), catalog: catalog)
    _ = engine.applyNow(FoundAirlineCommand(
        airlineName: "Advice Air", kind: .player, homeAirport: home,
        startingCash: scenario.playerStartingCash))
    WorldSetup.createCompetitors(engine: engine, count: scenario.competitorCount,
                                 playerHome: home,
                                 startingCash: scenario.competitorStartingCash)
    return engine
}

/// What Home actually offers: the checklist's two first-route suggestions
/// before a route exists, and `NextMovesCard`'s two after.
@MainActor
func recommendations(_ state: GameState) -> [MarketOpportunity] {
    switch rankRule {
    case "keeps": return keepsRanked(state)
    case "safe": return safeRanked(state)
    default:
        let ranked = state.marketOpportunities(catalog: catalog, limit: 4)
        let servable = ranked.filter(\.servableNow)
        return Array((servable.isEmpty ? ranked : servable).prefix(2))
    }
}

/// The other counterfactual, and the smaller one: production's own order,
/// with only the markets that cannot pay for the aircraft they need removed.
/// The ranking is untouched; the gate is the whole change.
@MainActor
func safeRanked(_ state: GameState) -> [MarketOpportunity] {
    var kept: [MarketOpportunity] = []
    for market in state.marketOpportunities(catalog: catalog, limit: 400) {
        guard let economics = bestEconomics(origin: market.origin,
                                            destination: market.destination,
                                            distanceKm: market.distanceKm,
                                            state: state),
              economics.afterOwnershipMonthly > 0 else { continue }
        kept.append(market)
        if kept.count == 2 { break }
    }
    return kept
}

/// The counterfactual: production's own candidate set, re-ordered by what
/// each market keeps after the aircraft it needs, with the ones that keep
/// nothing dropped.
@MainActor
func keepsRanked(_ state: GameState) -> [MarketOpportunity] {
    var scored: [(MarketOpportunity, Double)] = []
    for market in state.marketOpportunities(catalog: catalog, limit: 400) {
        guard let economics = bestEconomics(origin: market.origin,
                                            destination: market.destination,
                                            distanceKm: market.distanceKm,
                                            state: state),
              economics.afterOwnershipMonthly > 0 else { continue }
        scored.append((market, economics.afterOwnershipMonthly))
    }
    return scored
        .sorted { lhs, rhs in
            lhs.1 != rhs.1 ? lhs.1 > rhs.1
                : (lhs.0.origin.raw, lhs.0.destination.raw) < (rhs.0.origin.raw, rhs.0.destination.raw)
        }
        .prefix(2).map(\.0)
}

func money(_ value: Double) -> String { Money(rounding: value).compact }

// MARK: - audit

@MainActor
func audit(seed: UInt64, home: AirportCode) {
    let engine = foundedWorld(seed: seed, home: home)
    let state = engine.state
    let player = state.playerAirline!
    let cash = state.ledger.balance(of: player.id)
    print("\n== \(home.raw) \(catalog.airport(home)?.city ?? "?") · seed \(seed) · \(scenarioName) · cash \(cash.compact) · era \(state.progression.era) ==")

    let onboarding = state.onboardingModel(catalog: catalog)?.suggestions ?? []
    print("   Home's first-route suggestions: \(onboarding.map { "\($0.origin.raw)-\($0.destination.raw)" }.joined(separator: ", "))")

    for (index, market) in recommendations(state).enumerated() {
        let best = bestEconomics(origin: market.origin, destination: market.destination,
                                 distanceKm: market.distanceKm, state: state)
        let choice = acquisitionChoice(origin: market.origin,
                                       destination: market.destination, state: state)
        let chosen: Economics? = choice.flatMap { spec in
            economics(origin: market.origin, destination: market.destination,
                      distanceKm: market.distanceKm, spec: spec, state: state)
        }
        print(String(format: "   #%d %@-%@ %@ · %d km · ≈%d pax/day · fare %@ · %d incumbent(s) · servableNow %@",
                     index + 1, market.origin.raw as NSString, market.destination.raw as NSString,
                     market.destinationCity as NSString, market.distanceKm,
                     market.expectedDailyPassengers, market.referenceFare.compact as NSString,
                     market.incumbents, (market.servableNow ? "yes" : "no") as NSString))
        if let chosen {
            print(String(format: "        as the player would fly it (%@, %d seats, lease %@/month): %d rotations, carries %d of %d · revenue %@/day · direct %@/day (fees %.0f%% of revenue) · month %@ direct, %@ after the aircraft → %@",
                         chosen.spec.code.raw as NSString, chosen.spec.seats,
                         money(chosen.leaseMonthly) as NSString, chosen.rotations,
                         Int(chosen.carriedPerDay), Int(chosen.poolPerDay),
                         money(chosen.revenuePerDay) as NSString,
                         money(chosen.directPerDay) as NSString, chosen.feeShare * 100,
                         money(chosen.directMonthly) as NSString,
                         money(chosen.afterOwnershipMonthly) as NSString,
                         verdict(chosen).rawValue as NSString))
        } else {
            print("        no era-legal aircraft can fly it → \(Verdict.unflyable.rawValue)")
        }
        if let best, best.spec.code != chosen?.spec.code {
            print(String(format: "        best era airframe for it (%@): month %@ after the aircraft → %@",
                         best.spec.code.raw as NSString,
                         money(best.afterOwnershipMonthly) as NSString,
                         verdict(best).rawValue as NSString))
        }
    }

    // The counterfactual: every market the player could open from home,
    // ranked by what it would actually keep after its own aircraft.
    var alternatives: [(MarketOpportunity, Economics)] = []
    for candidate in state.marketCandidates(from: home, catalog: catalog) {
        guard let economics = bestEconomics(origin: candidate.origin,
                                            destination: candidate.destination,
                                            distanceKm: candidate.distanceKm,
                                            state: state) else { continue }
        alternatives.append((candidate, economics))
    }
    alternatives.sort { $0.1.afterOwnershipMonthly > $1.1.afterOwnershipMonthly }
    let head = alternatives.prefix(5).map {
        "\($0.0.destination.raw) \(money($0.1.afterOwnershipMonthly))/mo on \($0.1.spec.code.raw)"
    }
    print("   Best by what it keeps after its aircraft: \(head.joined(separator: " · "))")
    let recommended = Set(recommendations(state).map(\.destination))
    for (candidate, economics) in alternatives where recommended.contains(candidate.destination) {
        let rank = (alternatives.firstIndex { $0.0.destination == candidate.destination } ?? -1) + 1
        print("        the recommended \(candidate.destination.raw) is #\(rank) of \(alternatives.count) by that measure (\(money(economics.afterOwnershipMonthly))/mo, \(verdict(economics).rawValue))")
    }
}

// MARK: - follow

struct FollowResult {
    let seed: UInt64
    let home: AirportCode
    var opened: [String] = []
    var verdicts: [String] = []
    var cashByMonth: [String] = []
    var collapseDay: Int?
    var administrationDay: Int?
    var finalCash = Money.zero
    var finalRoutes = 0
    var finalFleet = 0
    var era = ""
    var firstRouteAfterOwnership = 0.0
    var worstMonth = Money.zero
    var lastStatement = Money.zero
}

/// The player who does what Home says: takes the top recommendation, leases
/// the aircraft it needs, opens it at the reference fare, assigns, and comes
/// back next month for the next one while the validators allow it.
@MainActor
func follow(seed: UInt64, home: AirportCode) -> FollowResult {
    let engine = foundedWorld(seed: seed, home: home)
    let player = engine.state.playerAirline!.id
    var result = FollowResult(seed: seed, home: home)

    @discardableResult
    func takeTopRecommendation(day: Int) -> Bool {
        let state = engine.state
        guard let market = recommendations(state).first,
              let spec = acquisitionChoice(origin: market.origin,
                                           destination: market.destination, state: state)
        else { return false }
        let planned: Economics? = economics(
            origin: market.origin, destination: market.destination,
            distanceKm: market.distanceKm, spec: spec, state: state)
        guard engine.applyNow(LeaseAircraftCommand(
            lessee: player, type: spec.code, termMonths: 60)) == .applied else { return false }
        guard let aircraft = engine.state.fleet(of: player)
            .first(where: { $0.assignedRoute == nil && $0.isOperational })
        else { return false }
        let fare = DemandSystem.referenceFare(distanceKm: market.distanceKm,
                                              tuning: catalog.tuning.demand)
        guard engine.applyNow(OpenRouteCommand(
            airline: player, origin: market.origin, destination: market.destination,
            dailyRoundTrips: 2, ticketPrice: Money(rounding: fare))) == .applied
        else { return false }
        guard let route = engine.state.routes(of: player).first(where: {
            $0.sameMarket(origin: market.origin, destination: market.destination)
        }) else { return false }
        _ = engine.applyNow(AssignAircraftToRouteCommand(
            airline: player, route: route.id, aircraftID: aircraft.id))
        result.opened.append("D\(String(format: "%03d", day)) \(market.origin.raw)-\(market.destination.raw) on \(spec.code.raw)")
        result.verdicts.append(verdict(planned).rawValue)
        if result.opened.count == 1, let planned {
            result.firstRouteAfterOwnership = planned.afterOwnershipMonthly
        }
        return true
    }

    takeTopRecommendation(day: 0)
    var lastExpansionMonth = -1
    for day in 1...days {
        engine.advance(ticks: ticksPerDay)
        let state = engine.state
        guard let airline = state.airlines[player] else { break }
        if airline.administrationCount > 0, result.administrationDay == nil {
            result.administrationDay = day
        }
        if airline.status == .collapsed {
            result.collapseDay = day
            result.era = "\(state.progression.era)"
            result.finalCash = state.ledger.balance(of: player)
            return result
        }
        let date = state.currentDate
        if date.day == 1, date.month != lastExpansionMonth {
            lastExpansionMonth = date.month
            result.cashByMonth.append("\(date.year)-\(String(format: "%02d", date.month)) \(state.ledger.balance(of: player).compact)")
            takeTopRecommendation(day: day)
        }
        if let statement = state.finance.byAirline[player]?.latest {
            result.lastStatement = statement.operatingProfit
            if statement.operatingProfit < result.worstMonth { result.worstMonth = statement.operatingProfit }
        }
    }
    let final = engine.state
    result.finalCash = final.ledger.balance(of: player)
    result.finalRoutes = final.routes(of: player).count
    result.finalFleet = final.fleet(of: player).count
    result.era = "\(final.progression.era)"
    return result
}

// MARK: - sweep: every home a player can pick

@MainActor
func sweep(seed: UInt64) {
    let eligible = catalog.orderedAirportCodes
        .compactMap { catalog.airport($0) }
        .filter { $0.runwayClass >= .medium }
    print("== First-recommendation audit from every pickable home · seed \(seed) · \(eligible.count) airports ==")
    var counts: [Verdict: Int] = [:]
    var dangerous: [String] = []
    for airport in eligible {
        let engine = foundedWorld(seed: seed, home: airport.code)
        let state = engine.state
        guard let market = recommendations(state).first else { continue }
        let choice = acquisitionChoice(origin: market.origin,
                                       destination: market.destination, state: state)
        let chosen: Economics? = choice.flatMap { spec in
            economics(origin: market.origin, destination: market.destination,
                      distanceKm: market.distanceKm, spec: spec, state: state)
        }
        let call = verdict(chosen)
        counts[call, default: 0] += 1
        if call == .dangerous || call == .unflyable {
            dangerous.append("\(airport.code.raw) → \(market.destination.raw) \(market.distanceKm) km \(chosen.map { money($0.afterOwnershipMonthly) } ?? "-")/mo on \(choice?.code.raw ?? "-")")
        }
        if verbose {
            print("   \(airport.code.raw) → \(market.destination.raw) \(market.distanceKm) km · \(chosen.map { money($0.afterOwnershipMonthly) } ?? "-")/mo · \(call.rawValue)")
        }
    }
    print("   verdicts: " + [Verdict.safe, .viable, .marginal, .dangerous, .unflyable]
        .map { "\($0.rawValue) \(counts[$0] ?? 0)" }.joined(separator: " · "))
    for line in dangerous { print("   ✗ \(line)") }
}

// MARK: - main

switch mode {
case "audit":
    for seed in seedRange { for home in homes { audit(seed: seed, home: home) } }
case "follow":
    print("== Following Home's advice · \(scenarioName) · \(days) days · acquire \(forcedType?.raw ?? acquireRule) · rank \(rankRule) ==")
    var collapses: [AirportCode: Int] = [:]
    var campaigns: [AirportCode: Int] = [:]

    for home in homes {
        for seed in seedRange {
            let result = follow(seed: seed, home: home)
            campaigns[home, default: 0] += 1
            if result.collapseDay != nil { collapses[home, default: 0] += 1 }
            print(String(format: "seed %llu %@ | routes opened %d %@ | %@ | cash %@ · routes %d · fleet %d · era %@ · worst month %@ · first route %@/mo after its aircraft",
                         seed, home.raw as NSString, result.opened.count,
                         result.verdicts.joined(separator: ",") as NSString,
                         (result.collapseDay.map { "COLLAPSED day \($0)" }
                          ?? result.administrationDay.map { "administration day \($0), alive" }
                          ?? "alive") as NSString,
                         result.finalCash.compact as NSString, result.finalRoutes,
                         result.finalFleet, result.era as NSString,
                         result.worstMonth.compact as NSString,
                         money(result.firstRouteAfterOwnership) as NSString))
            if verbose {
                for line in result.opened { print("     \(line)") }
                for line in result.cashByMonth { print("     cash \(line)") }
            }
        }
    }
    print("\n== Collapse rate following the advice ==")
    for home in homes {
        let total = campaigns[home] ?? 0
        print("   \(home.raw): \(collapses[home] ?? 0) collapsed of \(total)")
    }
case "sweep":
    for seed in seedRange { sweep(seed: seed) }
case "cost":
    // What one call to the ranking costs, at a real start, with the list
    // actually populated — the bench world's player has no opportunities at
    // all, so it times the scan and not the pricing.
    for home in homes {
        let engine = foundedWorld(seed: seedRange.lowerBound, home: home)
        let state = engine.state
        for limit in [2, 4, 6, 8] {
            let runs = 200
            let start = ContinuousClock.now
            var sink = 0
            for _ in 0..<runs { sink += state.marketOpportunities(catalog: catalog, limit: limit).count }
            let elapsed = ContinuousClock.now - start
            let seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
            print(String(format: "   %@ limit %d: %.3f ms/call over %d runs (returned %d)",
                         home.raw as NSString, limit, seconds / Double(runs) * 1000, runs, sink / runs))
        }
    }
default:
    print("modes: audit | follow | sweep")
}
