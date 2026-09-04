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
//
// AE-041 (docs/AE041_STRATEGY_BASELINE.md) added the rival's side of every
// move: each world-initiated entry followed through the rival's own ledger
// (`⇒ RIVAL LEDGER`), every rival opening anywhere classified by its later
// months (`rival openings N: SOUND … BAD OPENING …`), routes opened and
// closed, idle airframes, airframes gone within thirty days, the scripted
// player's fate, and three narrations: `--player`, `--follow NAME`,
// `--openings`.

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
/// `--rivals`: print every rival's end state after each campaign (AE-040).
let rivalsMode = arguments.contains("--rivals")
/// `--player`: narrate the scripted player's own campaign — every route it
/// opens or loses, and the day its status changes — with cash and fleet
/// (AE-041: the New York script ended every campaign with no routes).
let playerMode = arguments.contains("--player")
/// `--openings`: list every rival opening in order — the day, the rival,
/// the pair and the AI's own profit estimate at the rotations it opened
/// with — to read the order a hub works through its markets.
let openingsMode = arguments.contains("--openings")
/// `--follow NAME`: narrate one rival's campaign the way `--player` narrates
/// the player's — every route opened or lost, with the airline's cash and
/// each surviving route's last closed month on the day of a loss.
let followName: String? = arguments.firstIndex(of: "--follow").flatMap {
    arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
}
/// `--limit N`: run with a candidate horizon of N airports instead of the
/// shipped `candidateMarketLimit`, for the AE-039 horizon sweep. The
/// shipped tuning file is not touched; the catalog is rebuilt in memory.
let horizonLimit: Int? = arguments.firstIndex(of: "--limit").flatMap {
    arguments.indices.contains($0 + 1) ? Int(arguments[$0 + 1]) : nil
}
/// `--profit`: the AE-039 alternative — rank by what an airframe day keeps
/// after costs rather than what it sells (measured, not shipped).
if arguments.contains("--profit") { CompetitorAISystem.rankingBasis = .profit }
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
    /// `--rivals`: every rival's end state (AE-040).
    var rivalStates: [String] = []
    /// AE-041: what each world-initiated entry cost or earned the rival —
    /// the AI's estimate on the day it opened, and the route's own ledger
    /// a month, a quarter and half a year on, and at the end.
    var entryEconomics: [String] = []
    /// AE-041: every rival route opened and closed over the campaign
    /// (any pair, not only the player's), and the rival airframes idle
    /// on the last day.
    var rivalRoutesOpened = 0
    var rivalRoutesClosed = 0
    var idleRivalAircraft = 0
    /// AE-041: rival airframes acquired and gone again within thirty days
    /// while the airline lived — bought and sold, or leased and returned,
    /// the retrench churn of BUG-054.
    var quickDisposals = 0
    /// AE-041: the scripted player's own fate — status at the end, cash,
    /// and the day it went into administration or collapsed, if it did.
    var playerFate = ""
    /// `--player`: the player's route openings, closures and status changes.
    var playerStory: [String] = []
    /// AE-041: every rival opening classified by its own later ledger, and
    /// the ones that were not plainly sound, one line each.
    var openingSummary = ""
    var openingVerdicts: [String] = []
}

/// AE-041: every rival opening anywhere, followed through its own ledger —
/// was the market worth opening by the rival's own later months?
struct OpeningFollowUp {
    let day: Int
    let rival: String
    let archetype: String
    let market: String
    let routeID: RouteID
    let estimatedProfitPerDay: Double?
    var directAt90: Int64?
    var directAt180: Int64?
    var lastSeenDirect: Int64 = 0
    var lastSeenMonthsFlown = 0
    var closedDay: Int?
    /// The route as last seen before it vanished — what it had flown, how
    /// full it was, what it was earning, who was on it.
    var lastSeen: String = ""
    var earnedAtSomePoint = false

    enum Verdict: String {
        case sound = "SOUND"
        case losingButFlown = "LOSS-MAKING, STILL FLOWN"
        case closedLosing = "BAD OPENING"
        case closedAfterEarning = "CLOSED AFTER EARNING"
        case closedEarning = "CLOSED WHILE EARNING"
        case closedEarly = "CLOSED BEFORE A FULL MONTH"
        case tooYoung = "TOO YOUNG TO JUDGE"
    }
    func verdict(at lastDay: Int) -> Verdict {
        if closedDay != nil {
            if lastSeenMonthsFlown == 0 { return .closedEarly }
            if lastSeenDirect >= 0 { return .closedEarning }
            return earnedAtSomePoint ? .closedAfterEarning : .closedLosing
        }
        if let directAt180 { return directAt180 > 0 ? .sound : .losingButFlown }
        if let directAt90 { return directAt90 > 0 ? .sound : .losingButFlown }
        if lastDay - day >= 60 { return lastSeenDirect > 0 ? .sound : .losingButFlown }
        return .tooYoung
    }
}

/// AE-041: one world-initiated entry followed through the rival's ledger.
struct EntryFollowUp {
    let day: Int
    let rival: String
    let market: String
    let routeID: RouteID
    var opening: String
    var checkpoints: [String] = []
    var end: String?
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
    case .unprofitable(let loss):
        verdict = "CASE D · one airframe would lose \(Int(-loss)) a day on it"  + (inHorizon ? "" : " and outside the horizon (rank \(target.nearestRank))")
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
    var followUps: [EntryFollowUp] = []
    var openings: [OpeningFollowUp] = []
    var playerRouteSet: Set<String> = []
    var playerStatus: AirlineStatus = .active
    var followedRouteSet: Set<String> = []
    var rivalAirframes: [AircraftID: (owner: AirlineID, day: Int)] = [:]
    func narrateFollowed(_ state: GameState, day: Int) {
        guard let followName, let airline = state.airlines.values.first(where: { $0.name == followName }) else { return }
        let routesNow = Set(state.routes(of: airline.id).map { "\($0.origin.raw)-\($0.destination.raw)" })
        let cash = state.ledger.balance(of: airline.id).compact
        let statement = state.finance.byAirline[airline.id]?.latest
        let costs = statement.map { (-$0.operatingExpenses.asDouble - $0.financingCost.asDouble) } ?? 0
        let runway = costs > 0 ? String(format: "%.2f", state.ledger.balance(of: airline.id).asDouble / costs) : "n/a"
        let opened = routesNow.subtracting(followedRouteSet).sorted()
        let lost = followedRouteSet.subtracting(routesNow).sorted()
        for pair in opened {
            result.playerStory.append("FOLLOW \(followName) D\(String(format: "%03d", day)) opened \(pair) · cash \(cash) · fleet \(state.fleet(of: airline.id).count) · runway \(runway) months")
        }
        for pair in lost {
            let survivors = state.routes(of: airline.id).map { "\($0.origin.raw)-\($0.destination.raw) last month \($0.economicsLastMonth.directOperatingProfit.compact) (rev \(Money(cents: $0.economicsLastMonth.revenueCents).compact)) flights \($0.stats.flightsCompleted)" }
            result.playerStory.append("FOLLOW \(followName) D\(String(format: "%03d", day)) LOST \(pair) · cash \(cash) · fleet \(state.fleet(of: airline.id).count) (idle \(state.fleet(of: airline.id).filter { $0.assignedRoute == nil }.count)) · runway \(runway) months · statement costs \(Money(rounding: costs).compact) · survivors: \(survivors.joined(separator: "; "))")
        }
        if !lost.isEmpty || !opened.isEmpty {
            // The day before a loss, every route's closed month, so the
            // retrench choice can be read.
        }
        followedRouteSet = routesNow
        let decisionDay = (state.clock.now.dayIndex + airline.id.raw) % Int64(catalog.tuning.ai.decisionIntervalDays) == 0
        result.playerStory.append("FOLLOW-DAY \(followName) D\(String(format: "%03d", day)) cash \(cash) · statement opex \(statement?.operatingExpenses.compact ?? "-") financing \(statement?.financingCost.compact ?? "-") revenue \(statement?.operatingRevenue.compact ?? "-") · runway \(runway) · fleet \(state.fleet(of: airline.id).count) idle \(state.fleet(of: airline.id).filter { $0.assignedRoute == nil }.count) · routes \(routesNow.count)\(decisionDay ? " · DECISION DAY" : "")")
    }
    var followedYesterday: [String] = []

    func narratePlayer(_ state: GameState, day: Int) {
        guard playerMode, let me = state.airlines[player] else { return }
        let routesNow = Set(state.routes(of: player).map { "\($0.origin.raw)-\($0.destination.raw) \($0.dailyRoundTrips)x @\($0.ticketPrice.compact) \($0.assignedAircraft.count)ac" })
        let cash = state.ledger.balance(of: player).compact
        for opened in routesNow.subtracting(playerRouteSet).sorted() {
            result.playerStory.append("PLAYER D\(String(format: "%03d", day)) opened \(opened) · cash \(cash) · fleet \(state.fleet(of: player).count)")
        }
        for gone in playerRouteSet.subtracting(routesNow).sorted() {
            result.playerStory.append("PLAYER D\(String(format: "%03d", day)) lost \(gone) · cash \(cash) · fleet \(state.fleet(of: player).count)")
        }
        playerRouteSet = routesNow
        if me.status != playerStatus {
            playerStatus = me.status
            let month = state.finance.byAirline[player]?.latest
            result.playerStory.append("PLAYER D\(String(format: "%03d", day)) status \(me.status) · cash \(cash) · fleet \(state.fleet(of: player).count) · administrations \(me.administrationCount) · last statement revenue \(month?.operatingRevenue.compact ?? "-") operating profit \(month?.operatingProfit.compact ?? "-") financing \(month?.financingCost.compact ?? "-")")
        }
    }
    func pct(_ value: Double) -> String { String(format: "%.0f%%", value * 100) }
    /// The AI's own estimate for the pair the rival just opened, recomputed
    /// on the day of the opening with the rival's airframe and fare, against
    /// the incumbents that were there before it (its own new route excluded):
    /// what an airframe day sells and keeps by `airframeDayValue` on both
    /// bases, at the scheduler's rotations and at the two it opened with.
    /// The profit-basis airframe-day estimate for a route the rival just
    /// opened, per day at the rotations it opened with — nil when no
    /// airframe is assigned yet.
    func estimatedProfitPerDay(route: Route, state: GameState) -> Double? {
        guard let rival = state.airlines[route.airline], let profile = rival.aiProfile,
              let aircraftID = route.assignedAircraft.first, let aircraft = state.aircraft[aircraftID],
              let spec = catalog.aircraftType(aircraft.typeCode),
              let origin = catalog.airport(route.origin), let destination = catalog.airport(route.destination)
        else { return nil }
        let pool = DemandSystem.demandPool(from: route.origin, to: route.destination, date: state.currentDate,
                                           economicIndex: state.world.economicIndex, catalog: catalog)
        let quality = DemandSystem.representativeStarterQuality(tuning: catalog.tuning.demand)
            * rival.reputation.demandMultiplier(tuning: catalog.tuning.reputation)
        let incumbents = state.routes.values.filter {
            $0.sameMarket(origin: route.origin, destination: route.destination) && $0.id != route.id
        }
        let passengers = DemandSystem.poolAvailableToEntrant(
            pool: pool, fareRatio: profile.priceFactor, quality: quality,
            incumbents: incumbents, state: state, catalog: catalog)
        return CompetitorAISystem.airframeDayValue(
            distanceKm: route.distanceKm, passengersPerDay: passengers, spec: spec,
            fareRatio: profile.priceFactor, serviceTier: rival.serviceTier,
            origin: origin, destination: destination, state: state, catalog: catalog,
            rotationsPerDay: route.dailyRoundTrips, basis: .profit)
    }
    func estimate(route: Route, state: GameState) -> String {
        guard let rival = state.airlines[route.airline], let profile = rival.aiProfile,
              let aircraftID = route.assignedAircraft.first, let aircraft = state.aircraft[aircraftID],
              let spec = catalog.aircraftType(aircraft.typeCode),
              let origin = catalog.airport(route.origin), let destination = catalog.airport(route.destination)
        else { return "no airframe assigned" }
        let pool = DemandSystem.demandPool(from: route.origin, to: route.destination, date: state.currentDate,
                                           economicIndex: state.world.economicIndex, catalog: catalog)
        let quality = DemandSystem.representativeStarterQuality(tuning: catalog.tuning.demand)
            * rival.reputation.demandMultiplier(tuning: catalog.tuning.reputation)
        let incumbents = state.routes.values.filter {
            $0.sameMarket(origin: route.origin, destination: route.destination) && $0.id != route.id
        }
        let passengers = DemandSystem.poolAvailableToEntrant(
            pool: pool, fareRatio: profile.priceFactor, quality: quality,
            incumbents: incumbents, state: state, catalog: catalog)
        func value(_ basis: CompetitorAISystem.RankingBasis, rotations: Int?) -> Double {
            CompetitorAISystem.airframeDayValue(
                distanceKm: route.distanceKm, passengersPerDay: passengers, spec: spec,
                fareRatio: profile.priceFactor, serviceTier: rival.serviceTier,
                origin: origin, destination: destination, state: state, catalog: catalog,
                rotationsPerDay: rotations, basis: basis)
        }
        let rotations = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
            distanceKm: route.distanceKm, spec: spec, ops: catalog.tuning.ops)
        return String(format: "%@ (%d seats, %d km) · entrant pool %d pax/day of %d · airframe day at %dx: revenue %d profit %d · at %dx opened: profit %d/day (%@/month)",
                      spec.code.raw as NSString, spec.seats, route.distanceKm, Int(passengers), Int(pool.total),
                      rotations, Int(value(.revenue, rotations: nil)), Int(value(.profit, rotations: nil)),
                      route.dailyRoundTrips, Int(value(.profit, rotations: route.dailyRoundTrips)),
                      Money(rounding: value(.profit, rotations: route.dailyRoundTrips) * 30).compact as NSString)
    }
    func ledger(_ route: Route) -> String {
        let month = route.economicsLastMonth
        return "direct \(month.directOperatingProfit.compact) on revenue \(Money(cents: month.revenueCents).compact) fees \(Money(cents: month.feesCents).compact) · load \(pct(route.stats.loadFactor)) · \(route.dailyRoundTrips)x @\(route.ticketPrice.compact) · \(route.assignedAircraft.count) aircraft"
    }

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
        narratePlayer(state, day: day)
        if let followName, let airline = state.airlines.values.first(where: { $0.name == followName }) {
            let today = state.routes(of: airline.id).map { "\($0.origin.raw)-\($0.destination.raw) last month \($0.economicsLastMonth.directOperatingProfit.compact) (rev \(Money(cents: $0.economicsLastMonth.revenueCents).compact)) this month \($0.economicsThisMonth.directOperatingProfit.compact) flights \($0.stats.flightsCompleted) · \($0.assignedAircraft.count)ac" }
            let routesNow = Set(state.routes(of: airline.id).map { "\($0.origin.raw)-\($0.destination.raw)" })
            if !followedRouteSet.subtracting(routesNow).isEmpty {
                result.playerStory.append("FOLLOW \(followName) D\(String(format: "%03d", day - 1)) (the day before): \(followedYesterday.joined(separator: "; "))")
            }
            narrateFollowed(state, day: day)
            followedYesterday = today
        }
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
                if let route = state.routes[id] {
                    followUps.append(EntryFollowUp(day: day, rival: name(shot.0), market: label(shot.1),
                                                   routeID: id, opening: estimate(route: route, state: state)))
                }
            } else if myAirports.contains(shot.1.a) || myAirports.contains(shot.1.b) {
                result.moves.append(RivalMoveRecord(
                    day: day, rival: name(shot.0), archetype: archetype(shot.0), kind: .airportEntry,
                    market: label(shot.1), detail: "@\(shot.2.compact) \(shot.3)x"))
            }
        }
        for (id, acquired) in rivalAirframes where state.aircraft[id] == nil {
            if state.airlines[acquired.owner]?.status == .active, day - acquired.day <= 30 {
                result.quickDisposals += 1
            }
            rivalAirframes[id] = nil
        }
        for aircraft in state.aircraft.values
        where state.airlines[aircraft.owner]?.kind == .ai && rivalAirframes[aircraft.id] == nil {
            rivalAirframes[aircraft.id] = (aircraft.owner, day)
        }
        result.rivalRoutesOpened += now.keys.filter { previous[$0] == nil }.count
        result.rivalRoutesClosed += previous.keys.filter { now[$0] == nil }.count
        for id in now.keys.sorted() where previous[id] == nil {
            guard let route = state.routes[id] else { continue }
            openings.append(OpeningFollowUp(
                day: day, rival: name(route.airline), archetype: archetype(route.airline),
                market: label(route.market), routeID: id,
                estimatedProfitPerDay: estimatedProfitPerDay(route: route, state: state)))
        }
        for index in openings.indices where openings[index].closedDay == nil {
            let opening = openings[index]
            if let route = state.routes[opening.routeID] {
                // A closed month is only meaningful once the route has flown
                // one: the first statement after opening is a partial month.
                if route.economicsLastMonth.revenueCents > 0 {
                    openings[index].lastSeenDirect = route.economicsLastMonth.directOperatingProfit.cents
                    openings[index].lastSeenMonthsFlown = 1
                    if route.economicsLastMonth.directOperatingProfit.cents > 0 { openings[index].earnedAtSomePoint = true }
                }
                let airline = state.airlines[route.airline]
                openings[index].lastSeen = "flights \(route.stats.flightsCompleted)/\(route.stats.flightsCancelled) cancelled · seats flown \(route.stats.seatsFlown) · load \(pct(route.stats.loadFactor)) · \(route.dailyRoundTrips)x · \(route.assignedAircraft.count) aircraft · this month direct \(route.economicsThisMonth.directOperatingProfit.compact) on \(Money(cents: route.economicsThisMonth.revenueCents).compact) · airline cash \(state.ledger.balance(of: route.airline).compact) fleet \(state.fleet(of: route.airline).count) status \(airline.map { "\($0.status)" } ?? "?")"
                if day == opening.day + 90 { openings[index].directAt90 = route.economicsLastMonth.directOperatingProfit.cents }
                if day == opening.day + 180 { openings[index].directAt180 = route.economicsLastMonth.directOperatingProfit.cents }
            } else {
                openings[index].closedDay = day
            }
        }
        for index in followUps.indices where followUps[index].end == nil {
            let followed = followUps[index]
            if let route = state.routes[followed.routeID] {
                for offset in [30, 90, 180] where day == followed.day + offset {
                    followUps[index].checkpoints.append("+\(offset)d: \(ledger(route))")
                }
            } else {
                let collapsed = state.airlines.values.first { $0.name == followed.rival }?.status == .collapsed
                followUps[index].end = "\(collapsed ? "COLLAPSED" : "CLOSED") on day \(day) (\(day - followed.day) days after opening)"
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
            // From each rival home: the whole world ranked by the AI's score,
            // and where the player's pairs from that home sit in it — how
            // many better markets stand between the rival and the player.
            for id in state.orderedAirlineIDs {
                guard let airline = state.airlines[id], airline.kind == .ai, airline.status == .active,
                      let profile = airline.aiProfile else { continue }
                let specs = state.fleet(of: id).compactMap { catalog.aircraftType($0.typeCode) }
                guard let spec = specs.max(by: { $0.rangeKm < $1.rangeKm }) else { continue }
                let everything = CompetitorAISystem.candidateMarkets(
                    from: airline.homeAirport, airline: airline, spec: spec, profile: profile,
                    state: state, catalog: catalog, tuning: catalog.tuning.ai,
                    limit: catalog.orderedAirportCodes.count)
                let ranked = everything.compactMap { c in c.score.map { (c, $0) } }.sorted { $0.1 > $1.1 }
                let myFarEnds = Set(state.routes(of: player).compactMap { r -> AirportCode? in
                    r.origin == airline.homeAirport ? r.destination : r.destination == airline.homeAirport ? r.origin : nil
                })
                let top = ranked.prefix(12).map { "\($0.0.destination.raw)\(myFarEnds.contains($0.0.destination) ? "*" : "")\($0.0.nearestRank <= catalog.tuning.ai.candidateMarketLimit ? "" : "°") \(Int($0.1))" }.joined(separator: " ")
                var positions: [String] = []
                for far in myFarEnds.sorted(by: { $0.raw < $1.raw }) {
                    if let index = ranked.firstIndex(where: { $0.0.destination == far }) {
                        positions.append("\(far.raw) is #\(index + 1) of \(ranked.count) scored (\(Int(ranked[index].1)))")
                    } else if let c = everything.first(where: { $0.destination == far }) {
                        positions.append("\(far.raw) unscored: \(c.verdict)")
                    }
                }
                result.horizon.append("RANKING from \(airline.homeAirport.raw) (\(airline.name), \(spec.code) \(spec.rangeKm) km): \(top) · your pairs: \(positions.isEmpty ? "none from here" : positions.joined(separator: "; ")) · scored candidates in the world \(ranked.count), inside the horizon \(ranked.filter { $0.0.nearestRank <= catalog.tuning.ai.candidateMarketLimit }.count)")
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
    for followed in followUps {
        let end = followed.end ?? final.routes[followed.routeID].map { "alive on day \(days): \(ledger($0))" } ?? "gone"
        result.entryEconomics.append("D\(String(format: "%03d", followed.day)) \(followed.market) \(followed.rival) · opened with \(followed.opening)\(followed.checkpoints.map { " · " + $0 }.joined()) · \(end)")
    }
    var verdicts: [OpeningFollowUp.Verdict: Int] = [:]
    for opening in openings {
        let verdict = opening.verdict(at: days)
        verdicts[verdict, default: 0] += 1
        if verdict != .sound && verdict != .tooYoung {
            result.openingVerdicts.append(
                "\(verdict.rawValue) \(opening.market) \(opening.rival) [\(opening.archetype)] opened D\(String(format: "%03d", opening.day)) est \(opening.estimatedProfitPerDay.map { "\(Int($0))/day" } ?? "n/a")"
                + (opening.closedDay.map { " · closed D\(String(format: "%03d", $0)) after \($0 - opening.day) days · last seen: \(opening.lastSeen)" } ?? "")
                + " · last closed month direct \(Money(cents: opening.lastSeenDirect).compact)"
                + (opening.directAt90.map { " · +90d \(Money(cents: $0).compact)" } ?? "")
                + (opening.directAt180.map { " · +180d \(Money(cents: $0).compact)" } ?? ""))
        }
    }
    if openingsMode {
        for opening in openings {
            result.openingVerdicts.append("OPENED D\(String(format: "%03d", opening.day)) \(opening.market) \(opening.rival) [\(opening.archetype)] est \(opening.estimatedProfitPerDay.map { "\(Int($0))/day" } ?? "n/a") → \(opening.verdict(at: days).rawValue)")
        }
    }
    result.openingSummary = "rival openings \(openings.count): " + [OpeningFollowUp.Verdict.sound, .losingButFlown, .closedLosing, .closedAfterEarning, .closedEarning, .closedEarly, .tooYoung]
        .map { "\($0.rawValue) \(verdicts[$0] ?? 0)" }.joined(separator: " · ")
    result.idleRivalAircraft = final.aircraft.values.filter { aircraft in
        aircraft.assignedRoute == nil && aircraft.isOperational
            && final.airlines[aircraft.owner]?.kind == .ai
    }.count
    if rivalsMode {
        // Each rival at the end: what it flies, what it owns, whether its
        // routes pay, and how much of its route revenue the airports took
        // (AE-040, docs/REGIONAL_ARCHETYPE_AUDIT.md).
        for airline in final.airlines.values.sorted(by: { $0.id < $1.id }) where airline.kind == .ai {
            let routes = final.routes(of: airline.id)
            let revenue = routes.reduce(Int64(0)) { $0 + $1.economicsLastMonth.revenueCents }
            let fees = routes.reduce(Int64(0)) { $0 + $1.economicsLastMonth.feesCents }
            let direct = routes.reduce(Int64(0)) { $0 + $1.economicsLastMonth.directOperatingProfit.cents }
            let losing = routes.filter { $0.economicsLastMonth.directOperatingProfit.cents < 0 }.count
            let fleet = final.fleet(of: airline.id)
            let types = Dictionary(grouping: fleet, by: \.typeCode).map { "\($0.value.count)×\($0.key.raw)" }.sorted().joined(separator: " ")
            let netWorth = CreditMath.assets(of: airline.id, state: final) - CreditMath.totalDebt(of: airline)
            let statement = final.finance.byAirline[airline.id]?.latest
            let margin = statement.map { s -> String in
                s.operatingRevenue.cents > 0
                    ? String(format: "%.0f%%", Double(s.operatingProfit.cents) / Double(s.operatingRevenue.cents) * 100) : "—"
            } ?? "—"
            result.rivalStates.append(String(
                format: "RIVAL %@ [%@] %@ · routes %d (losing %d) · fleet %d (%@) · last month revenue %@ fees %@ (%@) direct %@ · airline margin %@ · net worth %@ · cash %@",
                airline.name as NSString, airline.aiProfile?.archetype.rawValue ?? "?" as NSString,
                "\(airline.status)" as NSString, routes.count, losing, fleet.count, types as NSString,
                Money(cents: revenue).compact as NSString, Money(cents: fees).compact as NSString,
                (revenue > 0 ? String(format: "%.0f%%", Double(fees) / Double(revenue) * 100) : "—") as NSString,
                Money(cents: direct).compact as NSString, margin as NSString, netWorth.compact as NSString,
                final.ledger.balance(of: airline.id).compact as NSString))
        }
    }
    result.playerRoutes = final.routes(of: player).count
    if let me = final.airlines[player] {
        result.playerFate = "\(me.status) · cash \(final.ledger.balance(of: player).compact) · fleet \(final.fleet(of: player).count) · administrations \(me.administrationCount)"
    }
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
        for line in result.entryEconomics { print("   ⇒ RIVAL LEDGER \(line)") }
        for line in result.playerStory { print("   \(line)") }
        print("   \(result.openingSummary)")
        for line in result.openingVerdicts { print("   ✗ \(line)") }
        print("   rival routes opened \(result.rivalRoutesOpened) closed \(result.rivalRoutesClosed) · idle rival aircraft at the end \(result.idleRivalAircraft) · airframes gone within 30 days of arriving \(result.quickDisposals) · player \(result.playerFate)")
        for line in result.horizon { print(line) }
        for line in result.rivalStates { print("   " + line) }
    }
}
print("\n== Totals over \(campaigns) campaigns ==")
for (kind, count) in totals.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
    print("   \(kind.rawValue): \(count)")
}
