import Foundation

// The live half of the 3D hub (docs/HUB_VIEW_3D.md §6): who is parked where,
// what each turnaround is doing, the departures board and the dashboard's
// KPIs. A pure read model over `GameState`, rebuilt per tick like `MapModel`.

/// The five steps of the dashboard's turnaround timeline.
public enum HubTurnaroundStage: Int, CaseIterable, Codable, Sendable, Comparable {
    case deboarding, servicing, boarding, pushback, departed

    public var title: String {
        switch self {
        case .deboarding: "Deboarding"
        case .servicing: "Servicing"
        case .boarding: "Boarding"
        case .pushback: "Pushback"
        case .departed: "Departed"
        }
    }

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Whose aircraft is on a stand.
public enum HubOperator: Equatable, Codable, Sendable {
    case player
    case rival(AirlineID)
    /// Background traffic standing in for the slots other carriers hold.
    case traffic
}

public enum HubBoardStatus: String, Codable, Sendable {
    case scheduled, boarding, delayed, departed, enRoute, landed

    public var title: String {
        switch self {
        case .scheduled: "On time"
        case .boarding: "Boarding"
        case .delayed: "Delayed"
        case .departed: "Departed"
        case .enRoute: "En route"
        case .landed: "Landed"
        }
    }
}

public struct HubFlightCard: Equatable, Codable, Sendable {
    public let flightID: FlightID
    public let code: String
    public let from: AirportCode
    public let to: AirportCode
    public let destinationCity: String
    /// Local time at the hub, "HH:mm".
    public let time: String
    public let passengers: Int
    public let seats: Int
    public let delayMinutes: Int
    public let status: HubBoardStatus

    public var loadFactor: Double { seats == 0 ? 0 : Double(passengers) / Double(seats) }
}

public struct HubStandOccupant: Equatable, Codable, Sendable {
    public let standIndex: Int
    public let gate: Int
    public let aircraftID: AircraftID?
    public let operatorKind: HubOperator
    public let livery: Livery
    public let category: AircraftCategory
    public let typeName: String
    public let registration: String
    public let flight: HubFlightCard?
    /// Nil when the aircraft is parked with nothing scheduled.
    public let stage: HubTurnaroundStage?
    /// Progress through `stage`, 0…1.
    public let stageProgress: Double
}

public struct HubBoardRow: Equatable, Codable, Sendable {
    public let code: String
    public let city: String
    public let airport: AirportCode
    public let time: String
    public let gate: Int?
    public let status: HubBoardStatus
    public let isDeparture: Bool
    public let delayMinutes: Int
}

public struct HubKPIs: Equatable, Codable, Sendable {
    /// Share of the player's completed flights through this hub that left
    /// on time. Nil before the first one.
    public let onTimeRate: Double?
    public let averageDelayMinutes: Int
    public let activeFlights: Int
    public let aircraftOnGround: Int
    public let passengersToday: Int
    public let slotUse: Double
    /// Estimated terminal throughput against capacity, 0…1 (drives the heatmap).
    public let terminalLoad: Double
    public let averageTurnaroundMinutes: Int
    public let loadFactor: Double?
}

public struct HubSnapshot: Equatable, Codable, Sendable {
    public let airport: AirportCode
    public let airportName: String
    public let city: String
    public let airlineName: String
    public let airlineCode: String
    public let livery: Livery
    /// Minutes since local midnight at the hub.
    public let localMinuteOfDay: Int
    public let localTime: String
    /// 0 in daylight, 1 at night, ramps through dusk and dawn.
    public let nightFactor: Double
    public let occupants: [HubStandOccupant]
    public let departures: [HubBoardRow]
    public let arrivals: [HubBoardRow]
    public let kpis: HubKPIs
    /// Aircraft movements per hour the scene animates (all carriers).
    public let movementsPerHour: Double
    /// The stand the dashboard opens on: the player's busiest turnaround.
    public let focusStand: Int?

    public var delays: [HubBoardRow] { (departures + arrivals).filter { $0.status == .delayed } }

    public func occupant(atStand index: Int) -> HubStandOccupant? {
        occupants.first { $0.standIndex == index }
    }
}

// MARK: - Building

public enum HubFormat {
    public static func clock(_ minuteOfDay: Int) -> String {
        let m = ((minuteOfDay % 1_440) + 1_440) % 1_440
        let h = m / 60, mm = m % 60
        return (h < 10 ? "0" : "") + "\(h):" + (mm < 10 ? "0" : "") + "\(mm)"
    }

    public static func localMinute(_ time: SimTime, utcOffsetMinutes: Int) -> Int {
        Int(((time.rawMinutes + Int64(utcOffsetMinutes)) % GameCalendar.minutesPerDay + GameCalendar.minutesPerDay)
            % GameCalendar.minutesPerDay)
    }

    /// Two-letter designator from the airline's name: initials of the first
    /// two words, else its first two letters.
    public static func airlineCode(_ name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter }).filter { !$0.isEmpty }
        let letters: [Character]
        if words.count >= 2 {
            letters = [words[0].first!, words[1].first!]
        } else {
            letters = Array((words.first ?? "AE").prefix(2))
        }
        let code = String(letters).uppercased()
        return code.count == 2 ? code : "AE"
    }

    /// Stable flight number per route and direction: odd outbound from the
    /// route's origin, even on the way back.
    public static func flightCode(airline: String, route: RouteID, outbound: Bool) -> String {
        let base = 100 + Int((route.raw &* 37) % 440) * 2
        return "\(airline) \(base + (outbound ? 1 : 0))"
    }

    public static func registration(airline: String, aircraft: AircraftID) -> String {
        let hash = StableHash.combine(UInt64(bitPattern: aircraft.raw), "hub.registration")
        let scalars = (0..<3).map { i in Character(UnicodeScalar(UInt8(65 + Int((hash >> (UInt64(i) * 8)) % 26)))) }
        return "\(airline.prefix(1))-\(airline.suffix(1))\(String(scalars))"
    }

    /// 0 by day, 1 by night, linear ramps 05:00–07:00 and 18:30–20:30.
    public static func nightFactor(localMinute m: Int) -> Double {
        let t = Double(m)
        switch t {
        case ..<300: return 1
        case ..<420: return 1 - (t - 300) / 120
        case ..<1_110: return 0
        case ..<1_230: return (t - 1_110) / 120
        default: return 1
        }
    }
}

extension GameState {
    public func hubSnapshot(airport code: AirportCode, catalog: ContentCatalog,
                            layout: HubLayout) -> HubSnapshot? {
        guard let spec = catalog.airport(code) else { return nil }
        let player = playerAirline
        let airlineName = player?.name ?? "Airline Empire"
        let designator = HubFormat.airlineCode(airlineName)
        let now = clock.now
        let localMinute = HubFormat.localMinute(now, utcOffsetMinutes: spec.utcOffsetMinutes)
        func local(_ t: SimTime) -> String {
            HubFormat.clock(HubFormat.localMinute(t, utcOffsetMinutes: spec.utcOffsetMinutes))
        }

        // Flights touching the hub, per aircraft.
        let hubFlights = orderedFlightIDs.compactMap { flights[$0] }.filter { $0.from == code || $0.to == code }
        func card(_ f: Flight, seats: Int) -> HubFlightCard {
            let outbound = routes[f.route].map { $0.origin == f.from } ?? true
            let owner = aircraft[f.aircraft].map(\.owner)
            let ownerName = owner.flatMap { airlines[$0]?.name } ?? airlineName
            let number = HubFormat.flightCode(airline: HubFormat.airlineCode(ownerName), route: f.route, outbound: outbound)
            let city = catalog.airport(f.from == code ? f.to : f.from)?.city ?? f.to.raw
            return HubFlightCard(flightID: f.id, code: number, from: f.from, to: f.to, destinationCity: city,
                                 time: local(f.departureTime), passengers: f.passengers, seats: seats,
                                 delayMinutes: Int(f.delayMinutes), status: status(f))
        }
        func status(_ f: Flight) -> HubBoardStatus {
            switch f.phase {
            case .scheduled: f.delayMinutes > 0 ? .delayed : .scheduled
            case .boarding: f.delayMinutes > 0 ? .delayed : .boarding
            case .enRoute: f.from == code ? .departed : .enRoute
            case .turnaround: .landed
            }
        }

        // Stage of an aircraft that is on the ground here.
        func stage(for plane: Aircraft, type: AircraftTypeSpec?) -> (HubTurnaroundStage?, Double, Flight?) {
            let mine = hubFlights.filter { $0.aircraft == plane.id }
            let turnaroundMinutes = Double(max(20, type?.turnaroundMinutes ?? 45))
            if let arrived = mine.first(where: { if case .turnaround = $0.phase { return $0.to == code } else { return false } }),
               case .turnaround(let until) = arrived.phase {
                let left = Double((until - now).minutes)
                let progress = min(1, max(0, 1 - left / turnaroundMinutes))
                let next = mine.first { $0.from == code && $0.id != arrived.id }
                return progress < 0.35
                    ? (.deboarding, progress / 0.35, next ?? arrived)
                    : (.servicing, (progress - 0.35) / 0.65, next ?? arrived)
            }
            if let next = mine.filter({ $0.from == code })
                .min(by: { $0.departureTime < $1.departureTime }) {
                let toGo = Double((next.departureTime - now).minutes)
                switch next.phase {
                case .boarding:
                    return toGo <= 5 ? (.pushback, 1 - max(0, toGo) / 5, next)
                        : (.boarding, min(1, max(0, 1 - (toGo - 5) / 30)), next)
                case .scheduled:
                    return toGo <= turnaroundMinutes
                        ? (.servicing, min(1, max(0, 1 - toGo / turnaroundMinutes)), next)
                        : (nil, 0, next)
                case .enRoute, .turnaround:
                    return (nil, 0, next)
                }
            }
            return (nil, 0, nil)
        }

        // Aircraft physically on the ground at the hub.
        let grounded = orderedAircraftIDs.compactMap { aircraft[$0] }.filter { plane in
            guard plane.location == code, !plane.status.isOnOrder else { return false }
            if let fid = plane.activeFlight, let f = flights[fid], case .enRoute = f.phase { return false }
            return true
        }
        let playerID = player?.id
        let mine = grounded.filter { $0.owner == playerID }
        let rivals = grounded.filter { $0.owner != playerID }

        var occupants: [HubStandOccupant] = []
        var free = layout.stands
        func take(for category: AircraftCategory) -> HubStand? {
            guard let i = free.firstIndex(where: { categoryRank($0.maxCategory) >= categoryRank(category) })
                ?? free.indices.first else { return nil }
            return free.remove(at: i)
        }
        for plane in mine + rivals {
            let type = catalog.aircraftType(plane.typeCode)
            let category = type?.category ?? .narrowbody
            guard let stand = take(for: category) else { break }
            let owner = airlines[plane.owner]
            let ownerCode = HubFormat.airlineCode(owner?.name ?? airlineName)
            let (st, progress, flight) = stage(for: plane, type: type)
            occupants.append(HubStandOccupant(
                standIndex: stand.index, gate: stand.gate, aircraftID: plane.id,
                operatorKind: plane.owner == playerID ? .player : .rival(plane.owner),
                livery: owner?.livery ?? .slate, category: category,
                typeName: type.map { "\($0.manufacturer) \($0.model)" } ?? plane.typeCode.raw,
                registration: HubFormat.registration(airline: ownerCode, aircraft: plane.id),
                flight: flight.map { card($0, seats: plane.configuration?.totalSeats ?? type?.seats ?? 0) },
                stage: st, stageProgress: progress))
        }

        // Background traffic for the slots other carriers hold, so a busy
        // airport looks busy and a quiet one does not.
        let slotUse = spec.slotCapacityPerDay == 0 ? 0
            : Double(world.slotsUsed(at: code)) / Double(spec.slotCapacityPerDay)
        let busy = min(0.85, max(0.35, 0.3 + slotUse * 0.9))
        let target = Int((Double(layout.stands.count) * busy).rounded())
        var jitter = HubJitter(code.raw + ".traffic")
        let trafficTypes = catalog.orderedAircraftTypeCodes.compactMap { catalog.aircraftType($0) }
        while occupants.count < target, !free.isEmpty {
            let stand = free.removeFirst()
            let fitting = trafficTypes.filter { categoryRank($0.category) <= categoryRank(stand.maxCategory) }
            let type = fitting.isEmpty ? nil : fitting[jitter.int(fitting.count)]
            let stages: [HubTurnaroundStage?] = [.deboarding, .servicing, .servicing, .boarding, nil]
            occupants.append(HubStandOccupant(
                standIndex: stand.index, gate: stand.gate, aircraftID: nil, operatorKind: .traffic,
                livery: Livery.allCases[jitter.int(Livery.allCases.count)],
                category: type?.category ?? .narrowbody,
                typeName: type.map { "\($0.manufacturer) \($0.model)" } ?? "Airliner",
                registration: "", flight: nil, stage: stages[jitter.int(stages.count)],
                stageProgress: jitter.unit()))
        }
        occupants.sort { $0.standIndex < $1.standIndex }

        // Board.
        let gateFor: [AircraftID: Int] = Dictionary(uniqueKeysWithValues: occupants.compactMap { o in
            o.aircraftID.map { ($0, o.gate) }
        })
        let playerFlights = hubFlights.filter { aircraft[$0.aircraft]?.owner == playerID }
        func row(_ f: Flight, departure: Bool) -> HubBoardRow {
            let c = card(f, seats: 0)
            return HubBoardRow(code: c.code, city: catalog.airport(departure ? f.to : f.from)?.city ?? "",
                               airport: departure ? f.to : f.from,
                               time: departure ? c.time : local(f.departureTime + .minutes(f.flightMinutes)),
                               gate: gateFor[f.aircraft], status: c.status, isDeparture: departure,
                               delayMinutes: c.delayMinutes)
        }
        let departures = playerFlights.filter { $0.from == code }
            .sorted { $0.departureTime < $1.departureTime }.prefix(8).map { row($0, departure: true) }
        let arrivals = playerFlights.filter { $0.to == code }
            .sorted { $0.departureTime < $1.departureTime }.prefix(8).map { row($0, departure: false) }

        // KPIs.
        let hubRoutes = orderedRouteIDs.compactMap { routes[$0] }
            .filter { $0.airline == playerID && $0.servesAirport(code) }
        let completed = hubRoutes.reduce(Int64(0)) { $0 + $1.stats.flightsCompleted }
        let delayed = hubRoutes.reduce(Int64(0)) { $0 + $1.stats.flightsDelayed }
        let delayMinutes = hubRoutes.reduce(Int64(0)) { $0 + $1.stats.totalDelayMinutes }
        let seatsFlown = hubRoutes.reduce(Int64(0)) { $0 + $1.stats.seatsFlown }
        let carried = hubRoutes.reduce(Int64(0)) { $0 + $1.stats.passengersCarried }
        let paxToday = hubRoutes.reduce(0) {
            $0 + max(0, $1.demandOutboundToday - $1.remainingOutboundToday)
                + max(0, $1.demandInboundToday - $1.remainingInboundToday)
        }
        let turnarounds = mine.compactMap { catalog.aircraftType($0.typeCode)?.turnaroundMinutes }
        // Terminal throughput estimate: every slot is a movement carrying
        // about 60 passengers through the building.
        let terminalLoad = spec.terminalCapacityPerDay == 0 ? 0
            : min(1, Double(world.slotsUsed(at: code)) * 60 / Double(spec.terminalCapacityPerDay))
        let kpis = HubKPIs(
            onTimeRate: completed == 0 ? nil : 1 - Double(delayed) / Double(completed),
            averageDelayMinutes: delayed == 0 ? 0 : Int(delayMinutes / delayed),
            activeFlights: playerFlights.count,
            aircraftOnGround: mine.count,
            passengersToday: paxToday,
            slotUse: slotUse,
            terminalLoad: terminalLoad,
            averageTurnaroundMinutes: turnarounds.isEmpty ? 0 : turnarounds.reduce(0, +) / turnarounds.count,
            loadFactor: seatsFlown == 0 ? nil : Double(carried) / Double(seatsFlown))

        let movementsPerHour = max(2, Double(max(world.slotsUsed(at: code), spec.slotCapacityPerDay / 4)) / 18)
        let focus = occupants.filter { $0.operatorKind == .player }
            .max { ($0.stage.map(stagePriority) ?? -1) < ($1.stage.map(stagePriority) ?? -1) }
            ?? occupants.first

        return HubSnapshot(
            airport: code, airportName: spec.name, city: spec.city, airlineName: airlineName,
            airlineCode: designator, livery: player?.livery ?? .default,
            localMinuteOfDay: localMinute, localTime: HubFormat.clock(localMinute),
            nightFactor: HubFormat.nightFactor(localMinute: localMinute),
            occupants: occupants, departures: Array(departures), arrivals: Array(arrivals),
            kpis: kpis, movementsPerHour: movementsPerHour, focusStand: focus?.standIndex)
    }
}

private func stagePriority(_ s: HubTurnaroundStage) -> Int {
    switch s {
    case .boarding: 4
    case .pushback: 3
    case .servicing: 2
    case .deboarding: 1
    case .departed: 0
    }
}

func categoryRank(_ c: AircraftCategory) -> Int {
    switch c {
    case .turboprop: 0
    case .regionalJet: 1
    case .narrowbody: 2
    case .largeNarrowbody: 3
    case .widebody: 4
    case .largeWidebody: 5
    }
}
