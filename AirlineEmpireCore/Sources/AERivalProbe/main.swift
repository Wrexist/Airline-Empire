import Foundation
import AirlineEmpireCore

// Competitor activity probe (AE-037 "Rival pressure").
//
//   swift run -c release ae-rival-probe [seed] [days]
//
// Replays the seed-2039 campaign the Core twin proves
// (FirstEraCampaignTests), then keeps the airline growing on a plain monthly
// policy so the world reaches late-game density, and diffs every rival's
// state day by day. Nothing here changes the simulation: the probe only
// reads state after each day and reports what the competitors did, what it
// cost the player, and whether the player had any way of knowing.
//
// Every line is MEASURED from the real engine; the visibility column is
// READ from the event feed rules (`GameState.isFeedEvent`) applied to the
// events the day actually emitted.

let arguments = CommandLine.arguments
let seed = UInt64(arguments.count > 1 ? arguments[1] : "2039") ?? 2039
let days = Int(arguments.count > 2 ? arguments[2] : "730") ?? 730
let home: AirportCode = AirportCode(arguments.count > 3 ? arguments[3] : "ARN")
/// Optional fourth argument: a rival market to invade in February, as
/// "LHR-CDG:0.88" (pair and fare as a multiple of the reference fare).
let fight: (origin: AirportCode, destination: AirportCode, fareRatio: Double)? = {
    guard arguments.count > 4 else { return nil }
    let parts = arguments[4].split(separator: ":")
    let pair = parts[0].split(separator: "-")
    guard pair.count == 2 else { return nil }
    let ratio = parts.count > 1 ? Double(parts[1]) ?? 1.0 : 1.0
    return (AirportCode(String(pair[0])), AirportCode(String(pair[1])), ratio)
}()

/// `--profit`: the AE-039 alternative rival ranking (measured, not shipped).
if arguments.contains("--profit") { CompetitorAISystem.rankingBasis = .profit }
let catalog = try ContentCatalog.loadBundled()
guard let spec = catalog.scenario("entrepreneur") else {
    fatalError("no entrepreneur scenario")
}
let engine = SimulationEngine(
    state: ScenarioBootstrap.newGame(scenario: "entrepreneur", worldSeed: seed,
                                     startYear: spec.startYear),
    systems: GamePipeline.standard(), catalog: catalog)
_ = engine.applyNow(FoundAirlineCommand(
    airlineName: "Campaign Air", kind: .player, homeAirport: home,
    startingCash: spec.playerStartingCash))
WorldSetup.createCompetitors(engine: engine, count: spec.competitorCount,
                             playerHome: home,
                             startingCash: spec.competitorStartingCash)
let player = engine.state.playerAirline!.id
let ticksPerDay = Int(GameCalendar.minutesPerDay / ScenarioBootstrap.standardTickMinutes)

// MARK: - The scripted player

@MainActor func assignIdle() {
    var state = engine.state
    let bare = state.routes(of: player).filter { route in
        !state.fleet(of: player).contains { $0.assignedRoute == route.id }
    }
    var idle = state.fleet(of: player).filter {
        $0.assignedRoute == nil && $0.isOperational
    }
    for route in bare {
        guard let index = idle.firstIndex(where: { aircraft in
            (catalog.aircraftType(aircraft.typeCode)?.rangeKm ?? 0) >= route.distanceKm
        }) else { continue }
        let aircraft = idle.remove(at: index)
        _ = engine.applyNow(AssignAircraftToRouteCommand(
            airline: player, route: route.id, aircraftID: aircraft.id))
        state = engine.state
    }
}

@MainActor func open(_ market: MarketOpportunity) -> Bool {
    engine.applyNow(OpenRouteCommand(
        airline: player, origin: market.origin, destination: market.destination,
        dailyRoundTrips: 2, ticketPrice: market.referenceFare)) == .applied
}

// Month one: the guided path.
_ = engine.applyNow(LeaseAircraftCommand(lessee: player, type: "PA184", termMonths: 60))
if let first = engine.state.onboardingModel(catalog: catalog)?.suggestions.first {
    _ = engine.applyNow(OpenRouteCommand(
        airline: player, origin: first.origin, destination: first.destination,
        dailyRoundTrips: 2, ticketPrice: first.referenceFare))
}
assignIdle()

// MARK: - Rival state snapshots

struct RouteShot: Equatable {
    let airline: AirlineID
    let origin: AirportCode
    let destination: AirportCode
    var price: Money
    var trips: Int
    var aircraft: Int
}

struct AirlineShot: Equatable {
    var fleet: Int
    var status: AirlineStatus
    var administrations: Int
    var reputation: Double
    var cash: Money
}

@MainActor func routeShots(_ state: GameState) -> [RouteID: RouteShot] {
    var out: [RouteID: RouteShot] = [:]
    for id in state.orderedRouteIDs {
        guard let route = state.routes[id], route.airline != player else { continue }
        out[id] = RouteShot(airline: route.airline, origin: route.origin,
                            destination: route.destination, price: route.ticketPrice,
                            trips: route.dailyRoundTrips,
                            aircraft: route.assignedAircraft.count)
    }
    return out
}

@MainActor func airlineShots(_ state: GameState) -> [AirlineID: AirlineShot] {
    var out: [AirlineID: AirlineShot] = [:]
    for id in state.orderedAirlineIDs {
        guard let airline = state.airlines[id], airline.kind == .ai else { continue }
        out[id] = AirlineShot(fleet: state.fleet(of: id).count, status: airline.status,
                              administrations: airline.administrationCount,
                              reputation: airline.reputation.score,
                              cash: state.ledger.balance(of: id))
    }
    return out
}

@MainActor func name(_ id: AirlineID) -> String { engine.state.airlines[id]?.name ?? "?" }

/// Player markets and airports, for "does this touch me".
@MainActor func playerMarkets(_ state: GameState) -> Set<Route.Market> {
    Set(state.routes(of: player).map(\.market))
}
@MainActor func playerAirports(_ state: GameState) -> Set<AirportCode> {
    var codes: Set<AirportCode> = [state.airlines[player]!.homeAirport]
    for route in state.routes(of: player) {
        codes.insert(route.origin); codes.insert(route.destination)
    }
    return codes
}

/// Today's demand split on a market: the player's share of what the demand
/// engine allocated across every route on the pair.
@MainActor func playerShare(_ state: GameState, market: Route.Market) -> (share: Double, rivals: Int)? {
    var mine = 0, total = 0, rivals = Set<AirlineID>()
    for id in state.orderedRouteIDs {
        guard let route = state.routes[id], route.market == market else { continue }
        let demand = route.demandOutboundToday + route.demandInboundToday
        total += demand
        if route.airline == player { mine += demand } else { rivals.insert(route.airline) }
    }
    guard total > 0 else { return nil }
    return (Double(mine) / Double(total), rivals.count)
}

/// Whether an event about this fact reached the player's feed today.
enum Visibility: String {
    case feed = "FEED"           // event exists and passes the player feed filter
    case filtered = "FILTERED"   // event exists in the log but the feed drops it
    case none = "NO EVENT"       // the simulation emits nothing for this
}

@MainActor func visibility(of state: GameState, dayStart: SimTime,
                matches: (SimEventKind) -> Bool) -> Visibility {
    var found: Visibility = .none
    for event in state.eventLog.recent where event.at >= dayStart {
        guard matches(event.kind) else { continue }
        if state.isFeedEvent(event, for: player) { return .feed }
        found = .filtered
    }
    return found
}

// MARK: - The run

var previousRoutes = routeShots(engine.state)
var previousAirlines = airlineShots(engine.state)
var counts: [String: Int] = [:]
var touchingCounts: [String: Int] = [:]
var visibilityCounts: [String: Int] = [:]
var reacted = false
var expandedFebruary = false
var lastExpansionMonth = -1
var contestedFirstDay: Int?
var timeline: [String] = []

@MainActor func log(_ day: Int, _ rival: String, _ action: String, _ impact: String,
         _ visible: Visibility, touches: Bool) {
    let date = engine.state.currentDate
    let line = String(format: "D%03d %04d-%02d-%02d | %-16@ | %-52@ | %-46@ | %@",
                      day, date.year, date.month, date.day,
                      rival as NSString, action as NSString, impact as NSString,
                      visible.rawValue as NSString)
    timeline.append(line)
    print(line)
    counts[action.components(separatedBy: " ").prefix(2).joined(separator: " "), default: 0] += 1
    if touches { touchingCounts[action.components(separatedBy: " ").prefix(2).joined(separator: " "), default: 0] += 1 }
    visibilityCounts[visible.rawValue, default: 0] += 1
}

print("== Rival pressure probe · seed \(seed) · \(days) days · entrepreneur · home \(home.raw) ==")
print("DAY  DATE       | RIVAL            | ACTION                                               | PLAYER IMPACT                                  | CURRENT VISIBILITY")

for day in 1...days {
    let dayStart = engine.state.clock.now
    engine.advance(ticks: ticksPerDay)
    var state = engine.state

    // -- The scripted player keeps playing (before diffing, so that the
    //    player's own routes count as "touched" from the day they exist).
    if let mission = state.progression.missions.first,
       case .boomRush(let region, _) = mission.kind, !reacted {
        reacted = true
        let homeSpec = catalog.airport(home)!
        let target = catalog.orderedAirportCodes
            .compactMap { catalog.airport($0) }
            .filter { $0.region == region && $0.code != home }
            .filter { Geo.distanceKm(from: homeSpec.coordinate, to: $0.coordinate) <= 5_500 }
            .min { Geo.distanceKm(from: homeSpec.coordinate, to: $0.coordinate)
                    < Geo.distanceKm(from: homeSpec.coordinate, to: $1.coordinate) }
        if let target {
            _ = engine.applyNow(LeaseAircraftCommand(lessee: player, type: "PA184", termMonths: 60))
            _ = engine.applyNow(OpenRouteCommand(
                airline: player, origin: home, destination: target.code,
                dailyRoundTrips: 2, ticketPrice: Money(cents: 30000)))
            assignIdle()
        }
    }
    if !expandedFebruary, state.currentDate.month == 2 {
        expandedFebruary = true
        _ = engine.applyNow(BuyUsedAircraftCommand(buyer: player, type: "MR180", ageYears: 8))
        _ = engine.applyNow(LeaseAircraftCommand(lessee: player, type: "PA184", termMonths: 60))
        for market in engine.state.marketOpportunities(catalog: catalog, limit: 4)
            .filter(\.servableNow).prefix(2) {
            _ = open(market)
        }
        if let fight, let distance = catalog.distanceKm(fight.origin, fight.destination) {
            // The fight: a third aircraft onto a rival's own pair, priced to
            // provoke a response (>12% under the cheapest incumbent triggers
            // the archetype's price policy).
            let reference = DemandSystem.referenceFare(distanceKm: distance,
                                                       tuning: catalog.tuning.demand)
            _ = engine.applyNow(LeaseAircraftCommand(lessee: player, type: "PA184", termMonths: 60))
            let result = engine.applyNow(OpenRouteCommand(
                airline: player, origin: fight.origin, destination: fight.destination,
                dailyRoundTrips: 2, ticketPrice: Money(rounding: reference * fight.fareRatio)))
            print("FIGHT day \(day): opened \(fight.origin.raw)-\(fight.destination.raw) at \(Money(rounding: reference * fight.fareRatio).compact) (ref \(Money(rounding: reference).compact)) → \(result)")
        }
        assignIdle()
        lastExpansionMonth = 2
    }
    // From March on: a plain growth policy on the first of each month. One
    // aircraft and one market per month while the cash is there, so the
    // world reaches late-game density without any cheat.
    state = engine.state
    let date = state.currentDate
    if expandedFebruary, date.day == 1,
       (date.year * 12 + date.month) > (2030 * 12 + lastExpansionMonth),
       state.fleet(of: player).count < 40 {
        lastExpansionMonth = date.month
        if date.month == 1 { lastExpansionMonth = 1 }
        let cash = state.ledger.balance(of: player)
        if cash > Money.dollars(60_000_000) {
            let era = state.progression.era
            let type: AircraftTypeCode = era >= .regional ? "MR180" : "PA184"
            if engine.applyNow(BuyUsedAircraftCommand(buyer: player, type: type, ageYears: 8)) != .applied {
                _ = engine.applyNow(LeaseAircraftCommand(lessee: player, type: "PA184", termMonths: 60))
            }
            if let market = engine.state.marketOpportunities(catalog: catalog, limit: 6)
                .first(where: \.servableNow) {
                _ = open(market)
            }
            assignIdle()
        }
    }
    // Year rollover bookkeeping for the monthly gate above.
    if date.month == 12, date.day == 1 { lastExpansionMonth = 12 }
    if date.month == 1, date.day == 2 { lastExpansionMonth = 1 }

    state = engine.state
    if let fight, day % 7 == 0,
       let mine = state.routes(of: player).first(where: { $0.market == Route.market(fight.origin, fight.destination) }),
       let split = playerShare(state, market: mine.market) {
        let rivalFares = state.routes.values
            .filter { $0.market == mine.market && $0.airline != player }
            .map { "\(name($0.airline)) \($0.ticketPrice.compact)/\($0.dailyRoundTrips)x" }
            .sorted().joined(separator: ", ")
        print(String(format: "FIGHT D%03d %@-%@ share %.0f%% (%d rivals) load %.0f%% month-to-date %@ · you %@/%dx vs %@",
                     day, mine.origin.raw as NSString, mine.destination.raw as NSString,
                     split.share * 100, split.rivals, mine.stats.loadFactor * 100,
                     mine.economicsThisMonth.directOperatingProfit.compact as NSString,
                     mine.ticketPrice.compact as NSString, mine.dailyRoundTrips, rivalFares as NSString))
    }
    let myMarkets = playerMarkets(state)
    let myAirports = playerAirports(state)
    let routesNow = routeShots(state)
    let airlinesNow = airlineShots(state)

    // -- Route openings and closures.
    for (id, shot) in routesNow.sorted(by: { $0.key < $1.key }) where previousRoutes[id] == nil {
        let market = Route.market(shot.origin, shot.destination)
        let onMine = myMarkets.contains(market)
        let atMine = myAirports.contains(shot.origin) || myAirports.contains(shot.destination)
        let where_ = onMine ? "ON YOUR MARKET" : atMine ? "at your airport" : "elsewhere"
        var impact = "none"
        if onMine {
            if contestedFirstDay == nil { contestedFirstDay = day }
            if let split = playerShare(state, market: market) {
                impact = String(format: "your share today %.0f%% (%d rivals)", split.share * 100, split.rivals)
            } else { impact = "contested; no demand allocated yet" }
        }
        let vis = visibility(of: state, dayStart: dayStart) {
            if case .routeOpened(let rid, _, _) = $0 { return rid == id }
            return false
        }
        log(day, name(shot.airline),
            "OPENED \(shot.origin.raw)-\(shot.destination.raw) \(where_) @\(shot.price.compact) \(shot.trips)x",
            impact, vis, touches: onMine || atMine)
    }
    for (id, shot) in previousRoutes.sorted(by: { $0.key < $1.key }) where routesNow[id] == nil {
        let market = Route.market(shot.origin, shot.destination)
        let onMine = myMarkets.contains(market)
        let where_ = onMine ? "ON YOUR MARKET" : "elsewhere"
        var impact = "none"
        if onMine, let split = playerShare(state, market: market) {
            impact = String(format: "your share today %.0f%% (%d rivals left)", split.share * 100, split.rivals)
        } else if onMine { impact = "market yours again" }
        let collapsed = airlinesNow[shot.airline]?.status == .collapsed
            && previousAirlines[shot.airline]?.status != .collapsed
        let vis = visibility(of: state, dayStart: dayStart) {
            if case .routeClosed(let rid) = $0 { return rid == id }
            return false
        }
        log(day, name(shot.airline),
            "CLOSED \(shot.origin.raw)-\(shot.destination.raw) \(where_)\(collapsed ? " (collapse)" : "")",
            impact, vis, touches: onMine)
    }
    // -- Price and frequency moves on routes that still exist.
    for (id, shot) in routesNow.sorted(by: { $0.key < $1.key }) {
        guard let before = previousRoutes[id] else { continue }
        let market = Route.market(shot.origin, shot.destination)
        let onMine = myMarkets.contains(market)
        if shot.price != before.price {
            var impact = onMine ? "" : "none"
            if onMine, let mine = state.routes(of: player).first(where: { $0.market == market }) {
                let ratio = shot.price.asDouble / mine.ticketPrice.asDouble
                impact = String(format: "now %.0f%% of your fare", ratio * 100)
                if let split = playerShare(state, market: market) {
                    impact += String(format: "; your share %.0f%%", split.share * 100)
                }
            }
            let direction = shot.price < before.price ? "CUT" : "RAISED"
            log(day, name(shot.airline),
                "PRICE \(direction) \(shot.origin.raw)-\(shot.destination.raw) \(before.price.compact)→\(shot.price.compact)\(onMine ? " ON YOUR MARKET" : "")",
                impact, .none, touches: onMine)
        }
        if shot.trips != before.trips {
            let direction = shot.trips > before.trips ? "UP" : "DOWN"
            var impact = onMine ? "capacity against you \(before.trips)x→\(shot.trips)x" : "none"
            if onMine, let split = playerShare(state, market: market) {
                impact += String(format: "; your share %.0f%%", split.share * 100)
            }
            log(day, name(shot.airline),
                "FREQUENCY \(direction) \(shot.origin.raw)-\(shot.destination.raw) \(before.trips)x→\(shot.trips)x\(onMine ? " ON YOUR MARKET" : "")",
                impact, .none, touches: onMine)
        }
    }
    // -- Fleet, failure, reputation.
    for (id, shot) in airlinesNow.sorted(by: { $0.key < $1.key }) {
        guard let before = previousAirlines[id] else { continue }
        if shot.fleet != before.fleet {
            let direction = shot.fleet > before.fleet ? "GREW" : "SHRANK"
            let vis = visibility(of: state, dayStart: dayStart) {
                switch $0 {
                case .aircraftDelivered, .aircraftSold, .leaseReturned, .aircraftOrdered: return true
                default: return false
                }
            }
            log(day, name(id), "FLEET \(direction) \(before.fleet)→\(shot.fleet)",
                "none directly", vis, touches: false)
        }
        if shot.administrations != before.administrations {
            let vis = visibility(of: state, dayStart: dayStart) {
                if case .airlineEnteredAdministration(let a) = $0 { return a == id }
                return false
            }
            log(day, name(id), "ADMINISTRATION (fire sale, retrench)", "their routes/slots may free up", vis, touches: false)
        }
        if shot.status != before.status {
            let vis = visibility(of: state, dayStart: dayStart) {
                if case .airlineCollapsed(let a) = $0 { return a == id }
                return false
            }
            log(day, name(id), "COLLAPSED", "their markets are open again", vis, touches: false)
        }
        if abs(shot.reputation - before.reputation) >= 0.05 {
            log(day, name(id), String(format: "REPUTATION %.2f→%.2f", before.reputation, shot.reputation),
                "changes their pull on shared markets", .none, touches: false)
        }
    }

    // -- Monthly: the player's standing on every contested market.
    if date.day == 1 {
        let mine = state.routes(of: player)
        var lines: [String] = []
        for route in mine {
            guard let split = playerShare(state, market: route.market), split.rivals > 0 else { continue }
            let rivalFares = state.routes.values
                .filter { $0.market == route.market && $0.airline != player }
                .map { "\(name($0.airline)) \($0.ticketPrice.compact)/\($0.dailyRoundTrips)x" }
                .sorted().joined(separator: ", ")
            lines.append(String(format: "   %@-%@ share %.0f%% load %.0f%% last-month %@ fare %@/%dx vs %@",
                                route.origin.raw as NSString, route.destination.raw as NSString,
                                split.share * 100, route.stats.loadFactor * 100,
                                route.economicsLastMonth.directOperatingProfit.compact as NSString,
                                route.ticketPrice.compact as NSString, route.dailyRoundTrips,
                                rivalFares as NSString))
        }
        let rivalsAlive = airlinesNow.values.filter { $0.status == .active }.count
        let rivalRoutes = routesNow.count
        print(String(format: "MONTH %04d-%02d | player routes %d fleet %d cash %@ era %@ | rivals alive %d routes %d | contested %d",
                     date.year, date.month, mine.count, state.fleet(of: player).count,
                     state.ledger.balance(of: player).compact as NSString,
                     "\(state.progression.era)" as NSString,
                     rivalsAlive, rivalRoutes, lines.count))
        for line in lines { print(line) }
    }

    previousRoutes = routesNow
    previousAirlines = airlinesNow
}

// MARK: - Save (for the UI tests' late-game fixture)

if let flag = arguments.firstIndex(of: "--save"), arguments.indices.contains(flag + 1) {
    let url = URL(fileURLWithPath: arguments[flag + 1])
    try JSONSaveCodec().encode(engine.state).write(to: url)
    print("saved \(url.path) (\(engine.state.currentDate))")
}

// MARK: - Summary

let final = engine.state
print("\n== Summary ==")
print("first contested player market: day \(contestedFirstDay.map(String.init) ?? "never")")
for (action, count) in counts.sorted(by: { $0.key < $1.key }) {
    print(String(format: "%-22@ %5d  touching the player: %d", action as NSString, count, touchingCounts[action] ?? 0))
}
print("visibility of rival actions through the player's feed:")
for (kind, count) in visibilityCounts.sorted(by: { $0.key < $1.key }) {
    print("   \(kind): \(count)")
}
print("final: player routes \(final.routes(of: player).count), fleet \(final.fleet(of: player).count), era \(final.progression.era), cash \(final.ledger.balance(of: player).compact)")
print("   player routes: " + final.routes(of: player).map { "\($0.origin.raw)-\($0.destination.raw)" }.joined(separator: " "))
for id in final.orderedAirlineIDs {
    guard let airline = final.airlines[id], airline.kind == .ai else { continue }
    print("   \(airline.name) [\(airline.aiProfile!.archetype)] \(airline.status) routes \(final.routes(of: id).count) fleet \(final.fleet(of: id).count) rep \(String(format: "%.2f", airline.reputation.score)) cash \(final.ledger.balance(of: id).compact)")
    // How much of that fleet the route can actually use: the scheduler's own
    // arithmetic (trips = min(target, capacity per aircraft × aircraft)).
    let ops = catalog.tuning.ops
    for route in final.routes(of: id) {
        guard let first = route.assignedAircraft.sorted().compactMap({ final.aircraft[$0] }).first,
              let type = catalog.aircraftType(first.typeCode) else { continue }
        let flight = Int64((Double(route.distanceKm) / Double(type.cruiseSpeedKmh) * 60).rounded())
            + ops.flightOverheadMinutes
        let block = 2 * (flight + Int64(type.turnaroundMinutes))
        let perAircraft = max(0, Int(ops.operatingDayMinutes / block))
        let needed = perAircraft > 0 ? (route.dailyRoundTrips + perAircraft - 1) / perAircraft : 0
        print("      \(route.origin.raw)-\(route.destination.raw) \(route.dailyRoundTrips)x/day target, \(route.assignedAircraft.count) aircraft assigned, \(needed) needed (\(perAircraft) trips/aircraft/day) · last month \(route.economicsLastMonth.passengers) pax \(route.economicsLastMonth.directOperatingProfit.compact) · load \(String(format: "%.0f%%", route.stats.loadFactor * 100))")
    }
}
