import Foundation

/// Competition, said in the player's terms (AE-037 "Rival pressure").
///
/// The simulation has always known who shares a city pair with the player
/// and how the demand engine splits it between them; the route screen showed
/// the rivals' fares and nothing about what they were doing to the route.
/// Measured on the seed-2039 campaign (docs/RIVAL_PRESSURE_AUDIT.md §3): a
/// player who entered London–Paris under two incumbents was answered the next
/// morning with a fare cut and an extra rotation, watched both rivals climb
/// to twenty rotations a day over four months, held a third of the market at
/// full load and lost money every month — and not one of those facts was on
/// any screen, because every one of them emits no event at all.
///
/// These models are pure derivations of the snapshot: the same routes, the
/// same allocations, the same attractiveness terms the demand engine used
/// this morning (`DemandSystem.offerQualityTerms`). Nothing here estimates
/// what a rival *might* do.

// MARK: - One route

/// A rival's service on a city pair the player flies.
public struct RivalOffer: Equatable, Sendable {
    public let airline: AirlineID
    public let name: String
    public let livery: Livery
    public let archetype: AIArchetype?
    public let routeID: RouteID
    public let fare: Money
    /// Their fare over the player's: 0.8 means 20% under you.
    public let fareRatioToPlayer: Double
    public let dailyRoundTrips: Int
    public let reputationScore: Double
    /// One end of the pair is their home — this is their fortress.
    public let isBasedOnPair: Bool
    /// Their share of today's demand on the pair, nil before any allocation.
    public let shareToday: Double?

    public init(airline: AirlineID, name: String, livery: Livery, archetype: AIArchetype?,
                routeID: RouteID, fare: Money, fareRatioToPlayer: Double,
                dailyRoundTrips: Int, reputationScore: Double, isBasedOnPair: Bool,
                shareToday: Double?) {
        self.airline = airline
        self.name = name
        self.livery = livery
        self.archetype = archetype
        self.routeID = routeID
        self.fare = fare
        self.fareRatioToPlayer = fareRatioToPlayer
        self.dailyRoundTrips = dailyRoundTrips
        self.reputationScore = reputationScore
        self.isBasedOnPair = isBasedOnPair
        self.shareToday = shareToday
    }
}

/// Where the player stands on one of their own city pairs.
public struct MarketCompetition: Equatable, Sendable {
    public enum Standing: Equatable, Sendable {
        /// Nobody else flies the pair.
        case alone
        /// Rivals fly it, but the demand engine has not allocated a day yet.
        case tooEarly
        /// Ahead of an even split by a clear margin.
        case leading
        /// Within the margin of an even split.
        case even
        /// Behind an even split by a clear margin.
        case trailing
    }

    /// The attractiveness term that separates the player from the strongest
    /// rival by the most — the *why* behind the standing. `playerAhead` is
    /// which side of it the player is on.
    public enum Edge: Equatable, Sendable {
        case fare(playerAhead: Bool)
        case schedule(playerAhead: Bool)
        case reputation(playerAhead: Bool)
        case comfort(playerAhead: Bool)
        case operations(playerAhead: Bool)

        public var playerAhead: Bool {
            switch self {
            case .fare(let ahead), .schedule(let ahead), .reputation(let ahead),
                 .comfort(let ahead), .operations(let ahead):
                ahead
            }
        }
    }

    public let routeID: RouteID
    public let origin: AirportCode
    public let destination: AirportCode
    /// Strongest first: by today's share, then by name.
    public let rivals: [RivalOffer]
    public let standing: Standing
    /// The player's share of today's demand on the pair; nil until the
    /// demand engine has allocated a day with at least one competitor.
    public let playerShareToday: Double?
    /// What an even split would give each carrier flying the pair today.
    public let evenShare: Double?
    /// Passengers the whole market wanted to fly today, across every
    /// carrier and both directions.
    public let marketDemandToday: Int
    public let edge: Edge?
    /// The rival the edge is measured against.
    public let strongestRival: AirlineID?
    /// Rotations the aircraft already on this route could add today — the
    /// scheduler's own capacity arithmetic. Zero means another rotation
    /// needs another aircraft. AE-038 measured a lone narrowbody on
    /// New York–Chicago answering a rival with a third rotation and half
    /// again the route's profit, while the screen said the answer needed
    /// another aircraft (BUG-046).
    public let spareRotationsToday: Int

    public var isContested: Bool { !rivals.isEmpty }

    /// Even-split margin: a share this far above or below 1/(n+1) counts as
    /// leading or trailing rather than noise.
    public static let standingMargin = 0.15

    public init(routeID: RouteID, origin: AirportCode, destination: AirportCode,
                rivals: [RivalOffer], standing: Standing, playerShareToday: Double?,
                evenShare: Double?, marketDemandToday: Int, edge: Edge?,
                strongestRival: AirlineID?, spareRotationsToday: Int = 0) {
        self.routeID = routeID
        self.origin = origin
        self.destination = destination
        self.rivals = rivals
        self.standing = standing
        self.playerShareToday = playerShareToday
        self.evenShare = evenShare
        self.marketDemandToday = marketDemandToday
        self.edge = edge
        self.strongestRival = strongestRival
        self.spareRotationsToday = spareRotationsToday
    }

    /// What the route's assigned aircraft could fly beyond its current
    /// frequency, from the scheduler's own per-aircraft capacity.
    static func spareRotations(of route: Route, state: GameState,
                               catalog: ContentCatalog) -> Int {
        let assigned = route.assignedAircraft.sorted().compactMap { state.aircraft[$0] }
        guard let first = assigned.first,
              let spec = catalog.aircraftType(first.typeCode) else { return 0 }
        let perAircraft = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
            distanceKm: route.distanceKm, spec: spec, ops: catalog.tuning.ops)
        return max(0, perAircraft * assigned.count - route.dailyRoundTrips)
    }
}

// MARK: - The whole network

/// A rival's move on a pair the player flies, or at an airport the player
/// serves — the recent competitive history that matters to this airline.
public struct RivalMove: Equatable, Sendable {
    public enum Relevance: Equatable, Sendable {
        /// The pair is one of the player's own routes.
        case onPlayerMarket
        /// One end is an airport the player serves; no demand is shared.
        case atPlayerAirport
    }

    public let airline: AirlineID
    public let name: String
    public let origin: AirportCode
    public let destination: AirportCode
    public let kind: MarketMove.Kind
    public let at: SimTime
    public let daysAgo: Int
    public let relevance: Relevance
    /// The airline is no longer flying at all — a retreat that was a collapse.
    public let airlineCollapsed: Bool

    public init(airline: AirlineID, name: String, origin: AirportCode,
                destination: AirportCode, kind: MarketMove.Kind, at: SimTime,
                daysAgo: Int, relevance: Relevance, airlineCollapsed: Bool) {
        self.airline = airline
        self.name = name
        self.origin = origin
        self.destination = destination
        self.kind = kind
        self.at = at
        self.daysAgo = daysAgo
        self.relevance = relevance
        self.airlineCollapsed = airlineCollapsed
    }
}

/// A rival, measured by how much of the player's network it touches.
public struct RivalStanding: Equatable, Sendable {
    public let airline: AirlineID
    public let name: String
    public let livery: Livery
    public let archetype: AIArchetype?
    public let status: AirlineStatus
    public let routes: Int
    public let fleet: Int
    public let reputationScore: Double
    /// City pairs both airlines fly.
    public let sharedMarkets: Int
    /// Of those, the ones where the player is trailing today.
    public let marketsWherePlayerTrails: Int
    /// Airports both airlines serve (presence, not shared demand).
    public let sharedAirports: Int
    /// Pairs entered in the last thirty days, anywhere.
    public let marketsEnteredRecently: Int
    /// Pairs left in the last thirty days, anywhere.
    public let marketsLeftRecently: Int

    public init(airline: AirlineID, name: String, livery: Livery, archetype: AIArchetype?,
                status: AirlineStatus, routes: Int, fleet: Int, reputationScore: Double,
                sharedMarkets: Int, marketsWherePlayerTrails: Int, sharedAirports: Int,
                marketsEnteredRecently: Int, marketsLeftRecently: Int) {
        self.airline = airline
        self.name = name
        self.livery = livery
        self.archetype = archetype
        self.status = status
        self.routes = routes
        self.fleet = fleet
        self.reputationScore = reputationScore
        self.sharedMarkets = sharedMarkets
        self.marketsWherePlayerTrails = marketsWherePlayerTrails
        self.sharedAirports = sharedAirports
        self.marketsEnteredRecently = marketsEnteredRecently
        self.marketsLeftRecently = marketsLeftRecently
    }
}

/// The competitive picture of the whole network, and the one fact from it
/// worth a line on Home.
public struct CompetitionSummary: Equatable, Sendable {
    /// The single most decision-relevant competitive fact, in priority
    /// order: something changed on your market; you are losing somewhere;
    /// a rival is growing where you are; you are winning. Nil when there is
    /// nothing to say — a quiet world stays quiet.
    public enum Headline: Equatable, Sendable {
        case rivalEnteredYourMarket(RivalMove)
        case rivalLeftYourMarket(RivalMove)
        case trailing(routes: Int, contested: Int)
        case rivalExpanding(RivalStanding)
        /// Contested routes, none lost, not all won — an ongoing fight.
        case fighting(contested: Int)
        case leading(contested: Int)
    }

    /// Every player route that shares its pair with someone, trailing first.
    public let contested: [MarketCompetition]
    public let contestedRoutes: Int
    public let trailingRoutes: Int
    public let leadingRoutes: Int
    /// The rival that touches the player most: shared markets, then shared
    /// airports, then network size. Nil in a world with no living rival.
    public let biggestRival: RivalStanding?
    /// Every living or fallen rival, biggest first.
    public let rivals: [RivalStanding]
    /// Moves on the player's markets and at the player's airports in the
    /// last thirty days, most recent first.
    public let recentMoves: [RivalMove]
    public let headline: Headline?

    public static let recentWindowDays: Int64 = 30

    public init(contested: [MarketCompetition], contestedRoutes: Int, trailingRoutes: Int,
                leadingRoutes: Int, biggestRival: RivalStanding?, rivals: [RivalStanding],
                recentMoves: [RivalMove], headline: Headline?) {
        self.contested = contested
        self.contestedRoutes = contestedRoutes
        self.trailingRoutes = trailingRoutes
        self.leadingRoutes = leadingRoutes
        self.biggestRival = biggestRival
        self.rivals = rivals
        self.recentMoves = recentMoves
        self.headline = headline
    }
}

// MARK: - Derivation

extension GameState {
    /// Where the player stands on one of their routes. Nil for a route that
    /// does not exist or is not the player's.
    public func marketCompetition(for routeID: RouteID,
                                  catalog: ContentCatalog) -> MarketCompetition? {
        guard let player = playerAirline, let mine = routes[routeID],
              mine.airline == player.id else { return nil }
        return marketCompetition(for: mine, player: player, catalog: catalog)
    }

    private func marketCompetition(for mine: Route, player: Airline,
                                   catalog: ContentCatalog) -> MarketCompetition {
        let tuning = catalog.tuning.demand
        let reference = DemandSystem.referenceFare(distanceKm: mine.distanceKm,
                                                   tuning: tuning)
        let myDemand = mine.demandOutboundToday + mine.demandInboundToday

        // Every other carrier on the pair, with today's allocation.
        var offers: [(route: Route, airline: Airline, demand: Int)] = []
        var marketDemand = myDemand
        for id in orderedRouteIDs {
            guard let route = routes[id], route.airline != player.id,
                  route.sameMarket(origin: mine.origin, destination: mine.destination),
                  let airline = airlines[route.airline] else { continue }
            let demand = route.demandOutboundToday + route.demandInboundToday
            marketDemand += demand
            offers.append((route, airline, demand))
        }

        guard !offers.isEmpty else {
            return MarketCompetition(
                routeID: mine.id, origin: mine.origin, destination: mine.destination,
                rivals: [], standing: .alone, playerShareToday: nil, evenShare: nil,
                marketDemandToday: marketDemand, edge: nil, strongestRival: nil)
        }

        let rivals = offers.map { offer -> RivalOffer in
            RivalOffer(
                airline: offer.airline.id, name: offer.airline.name,
                livery: offer.airline.livery, archetype: offer.airline.aiProfile?.archetype,
                routeID: offer.route.id, fare: offer.route.ticketPrice,
                fareRatioToPlayer: mine.ticketPrice.cents > 0
                    ? offer.route.ticketPrice.asDouble / mine.ticketPrice.asDouble : 1,
                dailyRoundTrips: offer.route.dailyRoundTrips,
                reputationScore: offer.airline.reputation.score,
                isBasedOnPair: offer.airline.homeAirport == mine.origin
                    || offer.airline.homeAirport == mine.destination,
                shareToday: marketDemand > 0
                    ? Double(offer.demand) / Double(marketDemand) : nil)
        }.sorted { lhs, rhs in
            let l = lhs.shareToday ?? 0, r = rhs.shareToday ?? 0
            return l != r ? l > r : lhs.name < rhs.name
        }

        // Standing against an even split of the carriers that actually
        // carried demand today (a rival with no aircraft on the pair is on
        // the list but not in the split). A route the player opened this
        // morning has no allocation yet and has flown nothing: that is not
        // "losing at 0%", it is too early — run 113 photographed the former
        // on the day of entry (docs/RIVAL_PRESSURE_AUDIT.md §8).
        let spare = MarketCompetition.spareRotations(of: mine, state: self, catalog: catalog)
        guard marketDemand > 0, myDemand > 0 || mine.stats.totalFlights > 0 else {
            return MarketCompetition(
                routeID: mine.id, origin: mine.origin, destination: mine.destination,
                rivals: rivals, standing: .tooEarly, playerShareToday: nil,
                evenShare: nil, marketDemandToday: marketDemand, edge: nil,
                strongestRival: rivals.first?.airline, spareRotationsToday: spare)
        }
        let share = Double(myDemand) / Double(marketDemand)
        let carriers = 1 + offers.filter { $0.demand > 0 }.count
        let even = 1.0 / Double(carriers)
        let standing: MarketCompetition.Standing
        if share >= even * (1 + MarketCompetition.standingMargin) {
            standing = .leading
        } else if share <= even * (1 - MarketCompetition.standingMargin) {
            standing = .trailing
        } else {
            standing = .even
        }

        // The edge: log-attractiveness terms, player minus strongest rival,
        // in the demand engine's own form — price utility is exponential in
        // the fare ratio to the reference, the rest multiply.
        var edge: MarketCompetition.Edge?
        if let strongest = rivals.first,
           let theirRoute = routes[strongest.routeID],
           let myTerms = DemandSystem.offerQualityTerms(route: mine, state: self, catalog: catalog),
           let theirTerms = DemandSystem.offerQualityTerms(route: theirRoute, state: self,
                                                           catalog: catalog),
           reference > 0 {
            let sensitivity = (tuning.priceSensitivityBusiness
                               + tuning.priceSensitivityLeisure) / 2
            let fare = sensitivity * ((theirRoute.ticketPrice.asDouble - mine.ticketPrice.asDouble)
                                      / reference)
            let terms: [(MarketCompetition.Edge, Double)] = [
                (.fare(playerAhead: fare > 0), fare),
                (.schedule(playerAhead: myTerms.schedule > theirTerms.schedule),
                 log(myTerms.schedule / theirTerms.schedule)),
                (.reputation(playerAhead: myTerms.reputation > theirTerms.reputation),
                 log(myTerms.reputation / theirTerms.reputation)),
                (.comfort(playerAhead: myTerms.comfort > theirTerms.comfort),
                 log(myTerms.comfort / theirTerms.comfort)),
                (.operations(playerAhead: myTerms.operations > theirTerms.operations),
                 log(myTerms.operations / theirTerms.operations)),
            ]
            // The term that separates the two the most; nothing if every
            // term is within noise of equal, so a screen is never handed a
            // reason that is not one.
            if let dominant = terms.max(by: { abs($0.1) < abs($1.1) }),
               abs(dominant.1) >= 0.05 {
                edge = dominant.0
            }
        }

        return MarketCompetition(
            routeID: mine.id, origin: mine.origin, destination: mine.destination,
            rivals: rivals, standing: standing, playerShareToday: share,
            evenShare: even, marketDemandToday: marketDemand, edge: edge,
            strongestRival: rivals.first?.airline,
            spareRotationsToday: spare)
    }

    /// The competitive picture of the whole network. Nil without a player.
    public func competitionSummary(catalog: ContentCatalog) -> CompetitionSummary? {
        guard let player = playerAirline else { return nil }
        let mine = routes(of: player.id)
        let myMarkets = Set(mine.map(\.market))
        var myAirports = Set<AirportCode>([player.homeAirport])
        for route in mine {
            myAirports.insert(route.origin)
            myAirports.insert(route.destination)
        }

        // Every contested route, trailing first so the worst news leads.
        let all = mine.map { marketCompetition(for: $0, player: player, catalog: catalog) }
        let contested = all.filter(\.isContested).sorted { lhs, rhs in
            let l = lhs.playerShareToday ?? 1, r = rhs.playerShareToday ?? 1
            return l != r ? l < r : lhs.routeID < rhs.routeID
        }
        let trailing = contested.filter { $0.standing == .trailing }.count
        let leading = contested.filter { $0.standing == .leading }.count
        var trailingBy: [AirlineID: Int] = [:]
        for market in contested where market.standing == .trailing {
            for rival in market.rivals { trailingBy[rival.airline, default: 0] += 1 }
        }

        // Recent moves, filtered to what touches the player.
        let now = clock.now
        let window = CompetitionSummary.recentWindowDays * GameCalendar.minutesPerDay
        var recent: [RivalMove] = []
        var enteredBy: [AirlineID: Int] = [:]
        var leftBy: [AirlineID: Int] = [:]
        for move in world.marketMoves where move.airline != player.id
            && now.rawMinutes - move.at.rawMinutes <= window {
            switch move.kind {
            case .entered: enteredBy[move.airline, default: 0] += 1
            case .left: leftBy[move.airline, default: 0] += 1
            }
            let relevance: RivalMove.Relevance?
            if myMarkets.contains(move.market) {
                relevance = .onPlayerMarket
            } else if myAirports.contains(move.origin) || myAirports.contains(move.destination) {
                relevance = .atPlayerAirport
            } else {
                relevance = nil
            }
            guard let relevance, let airline = airlines[move.airline] else { continue }
            recent.append(RivalMove(
                airline: move.airline, name: airline.name, origin: move.origin,
                destination: move.destination, kind: move.kind, at: move.at,
                daysAgo: Int((now.rawMinutes - move.at.rawMinutes) / GameCalendar.minutesPerDay),
                relevance: relevance, airlineCollapsed: airline.status == .collapsed))
        }
        recent.reverse()   // most recent first

        // Every rival, measured against the player's network.
        var standings: [RivalStanding] = []
        for id in orderedAirlineIDs {
            guard let airline = airlines[id], airline.kind == .ai else { continue }
            let theirs = routes(of: id)
            var sharedMarkets = 0
            var theirAirports = Set<AirportCode>([airline.homeAirport])
            for route in theirs {
                if myMarkets.contains(route.market) { sharedMarkets += 1 }
                theirAirports.insert(route.origin)
                theirAirports.insert(route.destination)
            }
            standings.append(RivalStanding(
                airline: id, name: airline.name, livery: airline.livery,
                archetype: airline.aiProfile?.archetype, status: airline.status,
                routes: theirs.count, fleet: fleet(of: id).count,
                reputationScore: airline.reputation.score,
                sharedMarkets: sharedMarkets,
                marketsWherePlayerTrails: trailingBy[id] ?? 0,
                sharedAirports: theirAirports.intersection(myAirports).count,
                marketsEnteredRecently: enteredBy[id] ?? 0,
                marketsLeftRecently: leftBy[id] ?? 0))
        }
        standings.sort { lhs, rhs in
            if (lhs.status == .collapsed) != (rhs.status == .collapsed) {
                return rhs.status == .collapsed
            }
            if lhs.sharedMarkets != rhs.sharedMarkets { return lhs.sharedMarkets > rhs.sharedMarkets }
            if lhs.sharedAirports != rhs.sharedAirports { return lhs.sharedAirports > rhs.sharedAirports }
            if lhs.routes != rhs.routes { return lhs.routes > rhs.routes }
            return lhs.name < rhs.name
        }
        let biggest = standings.first { $0.status == .active }

        // The headline, by priority. The most recent move on one of the
        // player's pairs leads whichever way it went: an entry followed by
        // an exit is "they pulled out", not "they arrived".
        let headline: CompetitionSummary.Headline?
        if let move = recent.first(where: { $0.relevance == .onPlayerMarket }) {
            headline = move.kind == .entered
                ? .rivalEnteredYourMarket(move) : .rivalLeftYourMarket(move)
        } else if trailing > 0 {
            headline = .trailing(routes: trailing, contested: contested.count)
        } else if !contested.isEmpty, leading < contested.count {
            // Your own contested pair outranks a rival's building elsewhere:
            // run 113's Home, a week into the London–Paris fight, led with
            // "SwiftJet added 2 routes this month" instead.
            headline = .fighting(contested: contested.count)
        } else if let biggest, biggest.marketsEnteredRecently >= 2,
                  recent.contains(where: { $0.airline == biggest.airline && $0.kind == .entered }) {
            headline = .rivalExpanding(biggest)
        } else if !contested.isEmpty {
            headline = .leading(contested: contested.count)
        } else {
            headline = nil
        }

        return CompetitionSummary(
            contested: contested, contestedRoutes: contested.count,
            trailingRoutes: trailing, leadingRoutes: leading,
            biggestRival: biggest, rivals: standings, recentMoves: recent,
            headline: headline)
    }
}
