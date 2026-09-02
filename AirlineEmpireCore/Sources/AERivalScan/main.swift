import Foundation
import AirlineEmpireCore

// Headless rival campaign scan (AE-038 "Rivals that come to you").
//
//   swift run -c release ae-rival-scan [days] [firstSeed-lastSeed] [HOME,HOME,…]
//
// Runs the entrepreneur campaign the probe and the Core twin play — guided
// first route, the boom-region reaction, February's expansion, then one
// aircraft and one market a month while the cash is there — for every
// seed and home asked for, and classifies every rival move that touches
// the player's network by who started the contest:
//
//   WORLD-INITIATED   a rival opens a pair the player already flies
//   PLAYER-INITIATED  the player opens a pair a rival already flies
//
// plus rival exits from the player's pairs, rival openings at the
// player's airports, price and frequency moves against the player, and
// collapses. Nothing here changes the simulation; every line is MEASURED
// from the real engine.

let arguments = CommandLine.arguments
let days = Int(arguments.count > 1 ? arguments[1] : "730") ?? 730
let seedRange: ClosedRange<UInt64> = {
    guard arguments.count > 2 else { return 2039...2039 }
    let parts = arguments[2].split(separator: "-").compactMap { UInt64($0) }
    return parts.count == 2 ? parts[0]...parts[1] : (parts.first ?? 2039)...(parts.first ?? 2039)
}()
let homes: [AirportCode] = (arguments.count > 3 ? arguments[3] : "ARN")
    .split(separator: ",").map { AirportCode(String($0)) }
/// `--horizon`: instead of the move table, explain on the last day why each
/// rival can or cannot reach each of the player's pairs (AE-039,
/// docs/HORIZON_AUDIT.md).
let horizonMode = arguments.contains("--horizon")
/// `--limit N`: run with a candidate horizon of N airports instead of the
/// shipped `candidateMarketLimit`, for the AE-039 horizon sweep. The
/// shipped tuning file is not touched; the catalog is rebuilt in memory.
let horizonLimit: Int? = arguments.firstIndex(of: "--limit").flatMap {
    arguments.indices.contains($0 + 1) ? Int(arguments[$0 + 1]) : nil
}
let shipped = try ContentCatalog.loadBundled()
let catalog: ContentCatalog = try {
    guard let horizonLimit else { return shipped }
    let ai = shipped.tuning.ai
    let tuning = Tuning(
        minRouteDistanceKm: shipped.tuning.minRouteDistanceKm, fleet: shipped.tuning.fleet,
        ops: shipped.tuning.ops, demand: shipped.tuning.demand, finance: shipped.tuning.finance,
        world: shipped.tuning.world, reputation: shipped.tuning.reputation,
        ai: AITuning(decisionIntervalDays: ai.decisionIntervalDays,
                     retrenchRunwayMonths: ai.retrenchRunwayMonths,
                     expandLoadFactor: ai.expandLoadFactor, shrinkLoadFactor: ai.shrinkLoadFactor,
                     undercutResponseThreshold: ai.undercutResponseThreshold,
                     candidateMarketLimit: horizonLimit,
                     minViableDailyDemand: ai.minViableDailyDemand,
                     initialRoundTrips: ai.initialRoundTrips,
                     maxFleetPerAirline: ai.maxFleetPerAirline),
        events: shipped.tuning.events, progression: shipped.tuning.progression)
    return try ContentCatalog(
        version: shipped.version, airports: Array(shipped.airports.values),
        seasonality: Array(shipped.seasonality.values),
        aircraftTypes: Array(shipped.aircraftTypes.values),
        scenarios: Array(shipped.scenarios.values), tuning: tuning)
}()
guard let spec = catalog.scenario("entrepreneur") else { fatalError("no entrepreneur scenario") }
let ticksPerDay = Int(GameCalendar.minutesPerDay / ScenarioBootstrap.standardTickMinutes)

struct RivalMoveRecord {
    enum Kind: String { case worldEntry = "WORLD-INITIATED ENTRY", playerEntry = "PLAYER-INITIATED ENTRY",
                        exit = "RIVAL EXIT", collapse = "COLLAPSE", airportEntry = "AT YOUR AIRPORT",
                        priceCut = "PRICE CUT", frequencyUp = "FREQUENCY UP" }
    let day: Int
    let rival: String
    let archetype: String
    let kind: Kind
    let market: String
    let detail: String
}

struct CampaignResult {
    let seed: UInt64
    let home: AirportCode
    var moves: [RivalMoveRecord] = []
    var playerRoutes = 0
    var playerMonthlyProfitOnWorldEntries: [String] = []
    var era = ""
    var rivalsAlive = 0
    var reachable: [String] = []
    var horizon: [String] = []
}

/// Why a rival at `base` can or cannot come to the player's pair `base`–`far`:
/// the AI's own candidate evaluation, asked over the whole world, against
/// the best it can see inside its horizon.
@MainActor
func explainReach(state: GameState, catalog: ContentCatalog, rival: Airline,
                  base: AirportCode, far: AirportCode, player: AirlineID) -> String {
    let tuning = catalog.tuning.ai
    guard let profile = rival.aiProfile else { return "no profile" }
    // The rival's longest-legged type, the one that decides reach.
    let specs = state.fleet(of: rival.id).compactMap { catalog.aircraftType($0.typeCode) }
    guard let spec = specs.max(by: { $0.rangeKm < $1.rangeKm }) else { return "no aircraft" }
    let everything = CompetitorAISystem.candidateMarkets(
        from: base, airline: rival, spec: spec, profile: profile, state: state,
        catalog: catalog, tuning: tuning, limit: catalog.orderedAirportCodes.count)
    let inside = CompetitorAISystem.candidateMarkets(
        from: base, airline: rival, spec: spec, profile: profile, state: state,
        catalog: catalog, tuning: tuning)
    guard let target = everything.first(where: { $0.destination == far }) else { return "not in catalog" }
    let winner = inside.compactMap { c in c.score.map { (c, $0) } }.max { $0.1 < $1.1 }
    let winnerText = winner.map { "\($0.0.destination.raw) \(Int($0.1))" } ?? "none"
    let inHorizon = target.nearestRank <= tuning.candidateMarketLimit
    let verdict: String
    switch target.verdict {
    case .scored(let score):
        if !inHorizon {
            verdict = "CASE A · outside the horizon (rank \(target.nearestRank) of \(tuning.candidateMarketLimit)); would score \(Int(score)) vs winner \(winnerText)" + (winner.map { score > $0.1 ? " → WOULD WIN" : " → would lose" } ?? " → WOULD WIN")
        } else if let winner, score < winner.1 {
            verdict = "CASE B · inside (rank \(target.nearestRank)) but scores \(Int(score)) vs winner \(winnerText)"
        } else {
            verdict = "IN REACH · inside (rank \(target.nearestRank)), scores \(Int(score)) — the winner"
        }
    case .ineligible:
        verdict = "CASE C/D · ineligible for \(spec.code) (range \(spec.rangeKm) km, \(target.distanceKm) km)" + (inHorizon ? "" : " and outside the horizon (rank \(target.nearestRank))")
    case .belowFloor(let score):
        verdict = "CASE D · below the viability floor (\(Int(score)) < \(Int(tuning.minViableDailyDemand)))" + (inHorizon ? "" : " and outside the horizon (rank \(target.nearestRank))")
    case .noSlots:
        verdict = "CASE D · no slots" + (inHorizon ? "" : " and outside the horizon (rank \(target.nearestRank))")
    case .regionExcluded:
        verdict = "CASE D · outside the archetype's home region" + (inHorizon ? "" : " and outside the horizon (rank \(target.nearestRank))")
    case .alreadyServed:
        verdict = "already flies it"
    }
    return "\(rival.name) [\(profile.archetype)] at \(base.raw) → \(far.raw) \(target.distanceKm) km: \(verdict)"
}

@MainActor
func runCampaign(seed: UInt64, home: AirportCode) -> CampaignResult {
    let engine = SimulationEngine(
        state: ScenarioBootstrap.newGame(scenario: "entrepreneur", worldSeed: seed,
                                         startYear: spec.startYear),
        systems: GamePipeline.standard(), catalog: catalog)
    _ = engine.applyNow(FoundAirlineCommand(
        airlineName: "Campaign Air", kind: .player, homeAirport: home,
        startingCash: spec.playerStartingCash))
    WorldSetup.createCompetitors(engine: engine, count: spec.competitorCount,
                                 playerHome: home, startingCash: spec.competitorStartingCash)
    let player = engine.state.playerAirline!.id
    var result = CampaignResult(seed: seed, home: home)

    func name(_ id: AirlineID) -> String { engine.state.airlines[id]?.name ?? "?" }
    func archetype(_ id: AirlineID) -> String {
        engine.state.airlines[id]?.aiProfile.map { "\($0.archetype)" } ?? "?"
    }
    func assignIdle() {
        var state = engine.state
        let bare = state.routes(of: player).filter { route in
            !state.fleet(of: player).contains { $0.assignedRoute == route.id }
        }
        var idle = state.fleet(of: player).filter { $0.assignedRoute == nil && $0.isOperational }
        for route in bare {
            guard let index = idle.firstIndex(where: {
                (catalog.aircraftType($0.typeCode)?.rangeKm ?? 0) >= route.distanceKm
            }) else { continue }
            let aircraft = idle.remove(at: index)
            _ = engine.applyNow(AssignAircraftToRouteCommand(airline: player, route: route.id,
                                                             aircraftID: aircraft.id))
            state = engine.state
        }
    }
    func open(_ market: MarketOpportunity) {
        _ = engine.applyNow(OpenRouteCommand(
            airline: player, origin: market.origin, destination: market.destination,
            dailyRoundTrips: 2, ticketPrice: market.referenceFare))
    }
    func rivalRoutes(_ state: GameState) -> [RouteID: (AirlineID, Route.Market, Money, Int)] {
        var out: [RouteID: (AirlineID, Route.Market, Money, Int)] = [:]
        for id in state.orderedRouteIDs {
            guard let route = state.routes[id], route.airline != player else { continue }
            out[id] = (route.airline, route.market, route.ticketPrice, route.dailyRoundTrips)
        }
        return out
    }
    func playerShare(_ state: GameState, _ market: Route.Market) -> Double? {
        var mine = 0, total = 0
        for id in state.orderedRouteIDs {
            guard let route = state.routes[id], route.market == market else { continue }
            let demand = route.demandOutboundToday + route.demandInboundToday
            total += demand
            if route.airline == player { mine += demand }
        }
        return total > 0 ? Double(mine) / Double(total) : nil
    }
    func label(_ market: Route.Market) -> String {
        let codes = [market.a.raw, market.b.raw].sorted()
        return "\(codes[0])-\(codes[1])"
    }

    // Which of the player's airports any rival can even consider: the
    // candidate set is the sixteen nearest airports to where the airframe
    // sits, so a pair is only enterable from a base that has its far end
    // in that set.
    for id in engine.state.orderedAirlineIDs {
        guard let airline = engine.state.airlines[id], airline.kind == .ai else { continue }
        let near = catalog.nearestAirports(to: airline.homeAirport, limit: catalog.tuning.ai.candidateMarketLimit)
            .map(\.0.code)
        if near.contains(home) {
            result.reachable.append("\(airline.name)@\(airline.homeAirport.raw)")
        }
    }

    _ = engine.applyNow(LeaseAircraftCommand(lessee: player, type: "PA184", termMonths: 60))
    if let first = engine.state.onboardingModel(catalog: catalog)?.suggestions.first {
        _ = engine.applyNow(OpenRouteCommand(
            airline: player, origin: first.origin, destination: first.destination,
            dailyRoundTrips: 2, ticketPrice: first.referenceFare))
    }
    assignIdle()

    var previous = rivalRoutes(engine.state)
    var previousStatus: [AirlineID: AirlineStatus] = [:]
    var reacted = false, expandedFebruary = false, lastExpansionMonth = -1
    // Pairs the player flies, with the day the player opened them and
    // whether a rival was already there.
    var playerPairs: [Route.Market: (day: Int, contestedAtOpen: Bool)] = [:]
    var pendingImpact: [(market: Route.Market, day: Int, rival: String)] = []

    /// The player's pairs are recorded the moment they exist, before the
    /// world gets its day: a rival that opens the same pair during the
    /// first day after the player is a rival that came to the player.
    func recordPlayerPairs(_ state: GameState, day: Int) {
        for route in state.routes(of: player) where playerPairs[route.market] == nil {
            let rivalsHere = state.routes.values.filter { $0.market == route.market && $0.airline != player }
            playerPairs[route.market] = (day, !rivalsHere.isEmpty)
            if !rivalsHere.isEmpty {
                let rivals = rivalsHere.map { name($0.airline) }.sorted()
                result.moves.append(RivalMoveRecord(
                    day: day, rival: rivals.joined(separator: "+"), archetype: "-",
                    kind: .playerEntry, market: label(route.market),
                    detail: "you entered under \(rivals.count) incumbent\(rivals.count == 1 ? "" : "s")"))
            }
        }
    }
    recordPlayerPairs(engine.state, day: 0)

    for day in 1...days {
        recordPlayerPairs(engine.state, day: day - 1)
        engine.advance(ticks: ticksPerDay)
        var state = engine.state

        if let mission = state.progression.missions.first,
           case .boomRush(let region, _) = mission.kind, !reacted {
            reacted = true
            let homeSpec = catalog.airport(home)!
            let target = catalog.orderedAirportCodes.compactMap { catalog.airport($0) }
                .filter { $0.region == region && $0.code != home }
                .filter { Geo.distanceKm(from: homeSpec.coordinate, to: $0.coordinate) <= 5_500 }
                .min { Geo.distanceKm(from: homeSpec.coordinate, to: $0.coordinate)
                        < Geo.distanceKm(from: homeSpec.coordinate, to: $1.coordinate) }
            if let target {
                _ = engine.applyNow(LeaseAircraftCommand(lessee: player, type: "PA184", termMonths: 60))
                _ = engine.applyNow(OpenRouteCommand(airline: player, origin: home, destination: target.code,
                                                     dailyRoundTrips: 2, ticketPrice: Money(cents: 30000)))
                assignIdle()
            }
        }
        if !expandedFebruary, state.currentDate.month == 2 {
            expandedFebruary = true
            _ = engine.applyNow(BuyUsedAircraftCommand(buyer: player, type: "MR180", ageYears: 8))
            _ = engine.applyNow(LeaseAircraftCommand(lessee: player, type: "PA184", termMonths: 60))
            for market in engine.state.marketOpportunities(catalog: catalog, limit: 4)
                .filter(\.servableNow).prefix(2) { open(market) }
            assignIdle()
            lastExpansionMonth = 2
        }
        state = engine.state
        let date = state.currentDate
        if expandedFebruary, date.day == 1,
           (date.year * 12 + date.month) > (2030 * 12 + lastExpansionMonth),
           state.fleet(of: player).count < 40 {
            lastExpansionMonth = date.month
            if state.ledger.balance(of: player) > Money.dollars(60_000_000) {
                let type: AircraftTypeCode = state.progression.era >= .regional ? "MR180" : "PA184"
                if engine.applyNow(BuyUsedAircraftCommand(buyer: player, type: type, ageYears: 8)) != .applied {
                    _ = engine.applyNow(LeaseAircraftCommand(lessee: player, type: "PA184", termMonths: 60))
                }
                if let market = engine.state.marketOpportunities(catalog: catalog, limit: 6)
                    .first(where: \.servableNow) { open(market) }
                assignIdle()
            }
        }
        if date.month == 12, date.day == 1 { lastExpansionMonth = 12 }
        if date.month == 1, date.day == 2 { lastExpansionMonth = 1 }

        state = engine.state
        let now = rivalRoutes(state)
        // Pairs the player opened during this day's script, before the
        // world's turn tomorrow.
        recordPlayerPairs(state, day: day)
        let myPairs = Set(playerPairs.keys.filter { m in state.routes(of: player).contains { $0.market == m } })
        var myAirports: Set<AirportCode> = [home]
        for route in state.routes(of: player) { myAirports.insert(route.origin); myAirports.insert(route.destination) }

        for (id, shot) in now.sorted(by: { $0.key < $1.key }) where previous[id] == nil {
            if myPairs.contains(shot.1) {
                let share = playerShare(state, shot.1).map { String(format: "your share today %.0f%%", $0 * 100) } ?? "no split yet"
                result.moves.append(RivalMoveRecord(
                    day: day, rival: name(shot.0), archetype: archetype(shot.0), kind: .worldEntry,
                    market: label(shot.1),
                    detail: "@\(shot.2.compact) \(shot.3)x · \(share) · you opened it day \(playerPairs[shot.1]?.day ?? 0)"))
                pendingImpact.append((shot.1, day, name(shot.0)))
            } else if myAirports.contains(shot.1.a) || myAirports.contains(shot.1.b) {
                result.moves.append(RivalMoveRecord(
                    day: day, rival: name(shot.0), archetype: archetype(shot.0), kind: .airportEntry,
                    market: label(shot.1), detail: "@\(shot.2.compact) \(shot.3)x"))
            }
        }
        for (id, shot) in previous.sorted(by: { $0.key < $1.key }) where now[id] == nil {
            guard myPairs.contains(shot.1) else { continue }
            let collapsed = state.airlines[shot.0]?.status == .collapsed
            result.moves.append(RivalMoveRecord(
                day: day, rival: name(shot.0), archetype: archetype(shot.0),
                kind: collapsed ? .collapse : .exit, market: label(shot.1),
                detail: collapsed ? "collapsed" : "closed the route; \(now.values.filter { $0.1 == shot.1 }.count) rival(s) remain"))
        }
        for (id, shot) in now.sorted(by: { $0.key < $1.key }) {
            guard let before = previous[id], myPairs.contains(shot.1) else { continue }
            if shot.2 < before.2 {
                result.moves.append(RivalMoveRecord(
                    day: day, rival: name(shot.0), archetype: archetype(shot.0), kind: .priceCut,
                    market: label(shot.1), detail: "\(before.2.compact)→\(shot.2.compact)"))
            }
            if shot.3 > before.3 {
                result.moves.append(RivalMoveRecord(
                    day: day, rival: name(shot.0), archetype: archetype(shot.0), kind: .frequencyUp,
                    market: label(shot.1), detail: "\(before.3)x→\(shot.3)x"))
            }
        }
        for id in state.orderedAirlineIDs {
            guard let airline = state.airlines[id], airline.kind == .ai else { continue }
            if let was = previousStatus[id], was != airline.status, airline.status == .collapsed {
                result.moves.append(RivalMoveRecord(day: day, rival: airline.name, archetype: archetype(id),
                                                    kind: .collapse, market: "-", detail: "airline collapsed"))
            }
            previousStatus[id] = airline.status
        }
        // A month after a world-initiated entry: what it did to the route.
        for pending in pendingImpact where pending.day + 30 == day {
            if let route = state.routes(of: player).first(where: { $0.market == pending.market }) {
                let share = playerShare(state, pending.market).map { String(format: "%.0f%%", $0 * 100) } ?? "-"
                result.playerMonthlyProfitOnWorldEntries.append(
                    "\(label(pending.market)) 30d after \(pending.rival): share \(share) load \(String(format: "%.0f%%", route.stats.loadFactor * 100)) last-month \(route.economicsLastMonth.directOperatingProfit.compact) this-month \(route.economicsThisMonth.directOperatingProfit.compact)")
            }
        }
        previous = now
        if horizonMode, day == days {
            let bases: [(Airline, AirportCode)] = state.orderedAirlineIDs.compactMap { id -> [(Airline, AirportCode)] in
                guard let airline = state.airlines[id], airline.kind == .ai, airline.status == .active else { return [] }
                // Where an expansion can start from: the home (new deliveries
                // arrive there) and wherever an *idle* airframe sits. An
                // assigned airframe's location alternates between its
                // route's ends and is not an expansion origin.
                var locations = Set(state.fleet(of: id)
                    .filter { $0.assignedRoute == nil && $0.isOperational }
                    .map(\.location))
                locations.insert(airline.homeAirport)
                return locations.sorted { $0.raw < $1.raw }.map { (airline, $0) }
            }.flatMap { $0 }
            for (airline, base) in bases {
                let ranks = catalog.nearestAirports(to: base, limit: catalog.orderedAirportCodes.count)
                let homeRank = ranks.firstIndex { $0.0.code == home }.map { $0 + 1 } ?? -1
                let range = state.fleet(of: airline.id).compactMap { catalog.aircraftType($0.typeCode)?.rangeKm }.max() ?? 0
                result.horizon.append("BASE \(airline.name) [\(airline.aiProfile.map { "\($0.archetype)" } ?? "?")] at \(base.raw) · fleet \(state.fleet(of: airline.id).count) · longest range \(range) km · player's home \(home.raw) is rank \(homeRank) from here (\(catalog.distanceKm(base, home) ?? 0) km)")
            }
            for route in state.routes(of: player).sorted(by: { $0.id < $1.id }) {
                var lines: [String] = []
                for (airline, base) in bases where base == route.origin || base == route.destination {
                    let far = base == route.origin ? route.destination : route.origin
                    lines.append("   " + explainReach(state: state, catalog: catalog, rival: airline,
                                                     base: base, far: far, player: player))
                }
                let contested = state.routes.values.contains { $0.market == route.market && $0.airline != player }
                result.horizon.append("PAIR \(route.origin.raw)-\(route.destination.raw) \(route.distanceKm) km load \(String(format: "%.0f%%", route.stats.loadFactor * 100))\(contested ? " CONTESTED" : "") · rivals sitting at an end: \(lines.count)")
                result.horizon.append(contentsOf: lines)
            }
        }
    }
    let final = engine.state
    result.playerRoutes = final.routes(of: player).count
    result.era = "\(final.progression.era)"
    result.rivalsAlive = final.airlines.values.filter { $0.kind == .ai && $0.status == .active }.count
    return result
}

print("== Rival scan · \(days) days · seeds \(seedRange.lowerBound)-\(seedRange.upperBound) · homes \(homes.map(\.raw).joined(separator: ",")) · horizon \(catalog.tuning.ai.candidateMarketLimit) ==")
var totals: [RivalMoveRecord.Kind: Int] = [:]
var campaigns = 0
for seed in seedRange {
    for home in homes {
        let start = Date()
        let result = runCampaign(seed: seed, home: home)
        campaigns += 1
        let counts = Dictionary(grouping: result.moves, by: \.kind).mapValues(\.count)
        for (kind, count) in counts { totals[kind, default: 0] += count }
        let secs = Int(Date().timeIntervalSince(start))
        print(String(format: "seed %llu %@ | %ds | player routes %d era %@ rivals alive %d | world entries %d · player entries %d · rival exits %d · at your airports %d · price cuts %d · freq ups %d · collapses %d | home in a rival's candidate set: %@",
                     seed, home.raw as NSString, secs, result.playerRoutes, result.era as NSString, result.rivalsAlive,
                     counts[.worldEntry] ?? 0, counts[.playerEntry] ?? 0, counts[.exit] ?? 0,
                     counts[.airportEntry] ?? 0, counts[.priceCut] ?? 0, counts[.frequencyUp] ?? 0,
                     counts[.collapse] ?? 0,
                     (result.reachable.isEmpty ? "none" : result.reachable.joined(separator: " ")) as NSString))
        for move in result.moves where move.kind == .worldEntry || move.kind == .playerEntry || move.kind == .exit
            || (move.kind == .collapse && move.market != "-") {
            print("   D\(String(format: "%03d", move.day)) \(move.kind.rawValue) \(move.market) \(move.rival) [\(move.archetype)] \(move.detail)")
        }
        for line in result.playerMonthlyProfitOnWorldEntries { print("   → \(line)") }
        for line in result.horizon { print(line) }
    }
}
print("\n== Totals over \(campaigns) campaigns ==")
for (kind, count) in totals.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
    print("   \(kind.rawValue): \(count)")
}
