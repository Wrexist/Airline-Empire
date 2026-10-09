import Foundation

// Everything the Hub View can show about the hub beyond the turnarounds
// (docs/HUB_VIEW_3D.md §6): the player's routes through it — drawn as the
// route fan in the world and listed in the insights panel — who holds the
// slots, today's movements by hour, the airline's money and reputation, the
// facilities bought here, and the alerts the bell collects. A pure read of
// `GameState`, rebuilt with each `HubSnapshot`.

/// One of the player's routes through the hub.
public struct HubRouteLink: Equatable, Codable, Sendable, Identifiable {
    public let routeID: RouteID
    public var id: RouteID { routeID }
    /// The far end.
    public let other: AirportCode
    public let city: String
    /// Initial great-circle bearing from the hub, degrees clockwise from
    /// north: which way the route leaves the airport in the route fan.
    public let bearing: Double
    public let distanceKm: Int
    public let dailyRoundTrips: Int
    public let aircraftAssigned: Int
    /// Lifetime; nil before the first flight.
    public let loadFactor: Double?
    public let onTimeRate: Double?
    /// Passengers booked today, both directions, and the demand they came from.
    public let passengersToday: Int
    public let demandToday: Int
    public let fareCents: Int64
    public let revenueThisMonthCents: Int64
    public let profitThisMonthCents: Int64
    /// The last closed month, the comparable figure.
    public let profitLastMonthCents: Int64
}

/// A carrier's share of the hub's daily slots.
public struct HubCarrierShare: Equatable, Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let livery: Livery?
    public let slots: Int
    public let isPlayer: Bool
}

/// Something at the hub that wants the player's attention.
public struct HubAlert: Equatable, Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case delay, lowLoad, slots, terminal, maintenance
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let detail: String
    /// The stand to focus when the alert is tapped, if it is about one.
    public let standIndex: Int?
}

/// An airport in the player's network: the hub switcher's list.
public struct HubNetworkAirport: Equatable, Codable, Sendable, Identifiable {
    public let code: AirportCode
    public var id: AirportCode { code }
    public let city: String
    /// The player's routes touching it.
    public let routes: Int
    public let isHome: Bool
}

public struct HubInsights: Equatable, Codable, Sendable {
    public let routes: [HubRouteLink]
    /// Player first, then the largest rivals, then everyone else together.
    public let carriers: [HubCarrierShare]
    public let slotCapacity: Int
    public let slotsUsed: Int
    /// The player's departures and arrivals per local hour, 24 entries.
    public let movementsByHour: [Int]
    public let cashCents: Int64
    /// Reputation, all 0…1.
    public let reputation: Double
    public let punctuality: Double
    public let reliability: Double
    public let service: Double
    public let comfort: Double
    /// Facilities bought at this hub, levels 0…2.
    public let lounge: Int
    public let groundServices: Int
    /// The player's aircraft on the ground here, and in the whole fleet.
    public let fleetAtHub: Int
    public let fleetTotal: Int
    public let routesTotal: Int
    /// The hub's routes, this month so far.
    public let monthRevenueCents: Int64
    public let monthProfitCents: Int64
    public let alerts: [HubAlert]
    /// Home first, then by routes: the airports the hub switcher offers.
    public var network: [HubNetworkAirport] = []

    public static let empty = HubInsights(
        routes: [], carriers: [], slotCapacity: 0, slotsUsed: 0, movementsByHour: Array(repeating: 0, count: 24),
        cashCents: 0, reputation: 0, punctuality: 0, reliability: 0, service: 0, comfort: 0, lounge: 0,
        groundServices: 0, fleetAtHub: 0, fleetTotal: 0, routesTotal: 0, monthRevenueCents: 0,
        monthProfitCents: 0, alerts: [])
}

extension Geo {
    /// Initial great-circle bearing from `a` to `b`, degrees clockwise from
    /// north, 0..<360. Display only: it never feeds the simulation.
    public static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}

extension GameState {
    /// The hub's insights for the player (empty without a player airline).
    public func hubInsights(airport code: AirportCode, catalog: ContentCatalog,
                            occupants: [HubStandOccupant], kpis: HubKPIs,
                            departures: [HubBoardRow]) -> HubInsights {
        guard let spec = catalog.airport(code), let player = playerAirline else { return .empty }
        let pid = player.id
        let mine = orderedRouteIDs.compactMap { routes[$0] }.filter { $0.airline == pid }
        let hubRoutes = mine.filter { $0.servesAirport(code) }

        let links: [HubRouteLink] = hubRoutes.map { r in
            let other = r.origin == code ? r.destination : r.origin
            let far = catalog.airport(other)
            let s = r.stats
            return HubRouteLink(
                routeID: r.id, other: other, city: far?.city ?? other.raw,
                bearing: far.map { Geo.bearing(from: spec.coordinate, to: $0.coordinate) } ?? 0,
                distanceKm: r.distanceKm, dailyRoundTrips: r.dailyRoundTrips,
                aircraftAssigned: r.assignedAircraft.count,
                loadFactor: s.seatsFlown == 0 ? nil : s.loadFactor,
                onTimeRate: s.flightsCompleted == 0 ? nil : 1 - Double(s.flightsDelayed) / Double(s.flightsCompleted),
                passengersToday: max(0, r.demandOutboundToday - r.remainingOutboundToday)
                    + max(0, r.demandInboundToday - r.remainingInboundToday),
                demandToday: r.demandOutboundToday + r.demandInboundToday,
                fareCents: r.ticketPrice.cents,
                revenueThisMonthCents: r.economicsThisMonth.revenueCents,
                profitThisMonthCents: r.economicsThisMonth.directOperatingProfit.cents,
                profitLastMonthCents: r.economicsLastMonth.directOperatingProfit.cents)
        }
        .sorted { $0.dailyRoundTrips != $1.dailyRoundTrips ? $0.dailyRoundTrips > $1.dailyRoundTrips
                                                           : $0.routeID.raw < $1.routeID.raw }

        // Slots: the player, the three largest rivals, everyone else.
        let used = world.slotsUsed(at: code)
        let holders = orderedAirlineIDs.compactMap { airlines[$0] }
            .map { ($0, world.slotsHeld(by: $0.id, at: code)) }
            .filter { $0.1 > 0 }
        var carriers: [HubCarrierShare] = []
        let playerSlots = world.slotsHeld(by: pid, at: code)
        carriers.append(HubCarrierShare(id: "player", name: player.name, livery: player.livery,
                                        slots: playerSlots, isPlayer: true))
        let rivals = holders.filter { $0.0.id != pid }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id.raw < $1.0.id.raw }
            .prefix(3)
        for (airline, slots) in rivals {
            carriers.append(HubCarrierShare(id: "airline-\(airline.id.raw)", name: airline.name,
                                            livery: airline.livery, slots: slots, isPlayer: false))
        }
        let rest = used - carriers.reduce(0) { $0 + $1.slots }
        if rest > 0 {
            carriers.append(HubCarrierShare(id: "others", name: "Other carriers", livery: nil,
                                            slots: rest, isPlayer: false))
        }

        // Today's movements by local hour: the player's departures from and
        // arrivals at the hub among the flights the scheduler holds.
        var hours = Array(repeating: 0, count: 24)
        func hour(_ t: SimTime) -> Int {
            HubFormat.localMinute(t, utcOffsetMinutes: spec.utcOffsetMinutes) / 60
        }
        for f in orderedFlightIDs.compactMap({ flights[$0] }) where aircraft[f.aircraft]?.owner == pid {
            if f.from == code { hours[hour(f.departureTime) % 24] += 1 }
            if f.to == code { hours[hour(f.departureTime + .minutes(f.flightMinutes)) % 24] += 1 }
        }

        let fleet = orderedAircraftIDs.compactMap { aircraft[$0] }.filter { $0.owner == pid && !$0.status.isOnOrder }
        let facilities = player.airportFacilities?[code] ?? AirportFacilities()

        // Alerts, most urgent first.
        var alerts: [HubAlert] = []
        let standOf: [String: Int] = Dictionary(occupants.compactMap { o in o.flight.map { ($0.code, o.standIndex) } },
                                                uniquingKeysWith: { a, _ in a })
        for row in departures where row.status == .delayed {
            alerts.append(HubAlert(id: "delay-\(row.code)", kind: .delay,
                                   title: "\(row.code) to \(row.city) delayed",
                                   detail: "+\(row.delayMinutes) min" + (row.gate.map { " · Gate \($0)" } ?? ""),
                                   standIndex: standOf[row.code]))
        }
        for plane in fleet where plane.location == code && plane.status.isInMaintenance {
            let reg = HubFormat.registration(airline: HubFormat.airlineCode(player.name), aircraft: plane.id)
            alerts.append(HubAlert(id: "maintenance-\(plane.id.raw)", kind: .maintenance,
                                   title: "\(reg) in maintenance",
                                   detail: "Out of the rotation until the check is done",
                                   standIndex: occupants.first { $0.aircraftID == plane.id }?.standIndex))
        }
        if kpis.slotUse >= 0.9 {
            alerts.append(HubAlert(id: "slots", kind: .slots, title: "Slots nearly full",
                                   detail: String(format: "%.0f%% of daily movements allocated", kpis.slotUse * 100),
                                   standIndex: nil))
        }
        if kpis.terminalLoad >= 0.85 {
            alerts.append(HubAlert(id: "terminal", kind: .terminal, title: "Terminal near capacity",
                                   detail: String(format: "%.0f%% of daily throughput", kpis.terminalLoad * 100),
                                   standIndex: nil))
        }
        for link in links {
            guard let lf = link.loadFactor, lf < 0.55,
                  let r = routes[link.routeID], r.stats.flightsCompleted >= 3 else { continue }
            alerts.append(HubAlert(id: "load-\(link.routeID.raw)", kind: .lowLoad,
                                   title: "\(link.city) flying \(Int((lf * 100).rounded()))% full",
                                   detail: "\(link.dailyRoundTrips) round trips a day", standIndex: nil))
        }

        // The network: every airport the player flies to or from.
        var routeCount: [AirportCode: Int] = [:]
        for r in mine {
            routeCount[r.origin, default: 0] += 1
            routeCount[r.destination, default: 0] += 1
        }
        routeCount[player.homeAirport, default: 0] += 0
        let network = routeCount.map { code, n in
            HubNetworkAirport(code: code, city: catalog.airport(code)?.city ?? code.raw, routes: n,
                              isHome: code == player.homeAirport)
        }
        .sorted { a, b in
            if a.isHome != b.isHome { return a.isHome }
            if a.routes != b.routes { return a.routes > b.routes }
            return a.code < b.code
        }

        var insights = HubInsights(
            routes: links, carriers: carriers, slotCapacity: spec.slotCapacityPerDay, slotsUsed: used,
            movementsByHour: hours, cashCents: ledger.balance(of: pid).cents,
            reputation: player.reputation.score, punctuality: player.reputation.punctuality,
            reliability: player.reputation.reliability, service: player.reputation.service,
            comfort: player.reputation.comfort, lounge: facilities.lounge,
            groundServices: facilities.groundServices,
            fleetAtHub: fleet.filter { $0.location == code }.count, fleetTotal: fleet.count,
            routesTotal: mine.count,
            monthRevenueCents: hubRoutes.reduce(0) { $0 + $1.economicsThisMonth.revenueCents },
            monthProfitCents: hubRoutes.reduce(0) { $0 + $1.economicsThisMonth.directOperatingProfit.cents },
            alerts: alerts)
        insights.network = Array(network.prefix(16))
        return insights
    }
}
