/// A route: the atomic strategic object (docs/GAME_DESIGN.md §4.5).
/// Round-trip service between two airports with a frequency, a fare, and
/// assigned aircraft.
public struct Route: Equatable, Codable, Sendable {
    public let id: RouteID
    public let airline: AirlineID
    public let origin: AirportCode
    public let destination: AirportCode
    /// Fixed at opening from world geometry (whole km, deterministic).
    public let distanceKm: Int
    /// Target round trips per day across all assigned aircraft. The
    /// scheduler materializes at most what assigned aircraft can actually
    /// fly; the shortfall shows in `stats`.
    public var dailyRoundTrips: Int
    /// One-way economy fare per passenger.
    public var ticketPrice: Money
    /// Sorted aircraft IDs serving this route.
    public var assignedAircraft: [AircraftID]
    public var planHistory: [RoutePlanChange]?
    public var stats: RouteStats
    /// Today's bookable demand per direction (set daily by DemandSystem;
    /// consumed at boarding). Outbound = origin -> destination.
    public var demandOutboundToday: Int
    public var demandInboundToday: Int
    public var remainingOutboundToday: Int
    public var remainingInboundToday: Int
    /// The travellers connecting at a hub inside today's demand above (set by
    /// `ConnectingDemandSystem`, sold at boarding with everyone else). Nil on
    /// every route that carries none, so a network without a transfer centre
    /// saves exactly as it did before connections existed.
    public var connectionsToday: ConnectingLoad?
    /// Direct operating P&L attribution (docs/ECONOMY.md): current month
    /// accumulates live; previous month is the closed, comparable figure.
    public var economicsThisMonth: RouteMonthEconomics
    public var economicsLastMonth: RouteMonthEconomics
    /// When the route opened: the moment its `OpenRouteCommand` applied
    /// (TD-027). The start of the route's story — "since you arrived" is a
    /// sentence the game can only say if it knows when that was. Nil for a
    /// route from a save written before format 17 whose opening the
    /// market-move record no longer held (`MigrationV16AddRouteOpenedAt`).
    public var openedAt: SimTime?

    public init(id: RouteID, airline: AirlineID, origin: AirportCode,
                destination: AirportCode, distanceKm: Int, dailyRoundTrips: Int,
                ticketPrice: Money, assignedAircraft: [AircraftID] = [],
                stats: RouteStats = RouteStats(), openedAt: SimTime? = nil) {
        self.id = id
        self.airline = airline
        self.origin = origin
        self.destination = destination
        self.distanceKm = distanceKm
        self.dailyRoundTrips = dailyRoundTrips
        self.ticketPrice = ticketPrice
        self.assignedAircraft = assignedAircraft
        self.stats = stats
        self.demandOutboundToday = 0
        self.demandInboundToday = 0
        self.remainingOutboundToday = 0
        self.remainingInboundToday = 0
        self.economicsThisMonth = RouteMonthEconomics()
        self.economicsLastMonth = RouteMonthEconomics()
        self.openedAt = openedAt
    }

    /// Daily airport movements this route consumes at EACH endpoint
    /// (one departure + one arrival per round trip).
    public static func dailySlotMovements(roundTrips: Int) -> Int {
        roundTrips * 2
    }

    public func servesAirport(_ code: AirportCode) -> Bool {
        origin == code || destination == code
    }

    /// Whether the route can carry anyone: at least one aircraft assigned.
    /// A route without one holds slots and draws payroll, and nothing else —
    /// it is not part of the network a gate, a rival or a traveller sees
    /// (`GameState.operatingRoutes(of:)`).
    public var isOperating: Bool { !assignedAircraft.isEmpty }

    /// True if the two routes cover the same city pair in either direction.
    public func sameMarket(origin o: AirportCode, destination d: AirportCode) -> Bool {
        (origin == o && destination == d) || (origin == d && destination == o)
    }
}

/// Operational counters; punctuality inputs for Phase 9. Lifetime counters
/// (bounded by being counters, not logs).
public struct RouteStats: Equatable, Codable, Sendable {
    public var flightsCompleted: Int64
    public var flightsCancelled: Int64
    public var flightsDelayed: Int64
    public var totalDelayMinutes: Int64
    public var passengersCarried: Int64
    public var seatsFlown: Int64

    public init(flightsCompleted: Int64 = 0, flightsCancelled: Int64 = 0,
                flightsDelayed: Int64 = 0, totalDelayMinutes: Int64 = 0,
                passengersCarried: Int64 = 0, seatsFlown: Int64 = 0) {
        self.flightsCompleted = flightsCompleted
        self.flightsCancelled = flightsCancelled
        self.flightsDelayed = flightsDelayed
        self.totalDelayMinutes = totalDelayMinutes
        self.passengersCarried = passengersCarried
        self.seatsFlown = seatsFlown
    }

    /// Lifetime load factor; 0 with no flying yet.
    public var loadFactor: Double {
        seatsFlown == 0 ? 0 : Double(passengersCarried) / Double(seatsFlown)
    }

    public var totalFlights: Int64 { flightsCompleted + flightsCancelled }

    /// Share of flights that operated (not cancelled); 1.0 with no history.
    public var completionRate: Double {
        totalFlights == 0 ? 1.0 : Double(flightsCompleted) / Double(totalFlights)
    }

    /// Share of completed flights that left on time; 1.0 with no history.
    public var punctuality: Double {
        flightsCompleted == 0 ? 1.0
            : Double(flightsCompleted - min(flightsDelayed, flightsCompleted))
                / Double(flightsCompleted)
    }
}


/// One month of a route's direct operating figures, in cents.
/// "Direct" = revenue minus fuel, airport fees, and crew — costs that
/// attach to specific flights. Fleet ownership and company overhead are
/// airline-level (statements), by design.
public struct RouteMonthEconomics: Equatable, Codable, Sendable {
    public var revenueCents: Int64
    public var fuelCents: Int64
    public var feesCents: Int64
    public var crewCents: Int64
    public var passengers: Int64
    /// Of `passengers` and `revenueCents`: the travellers connecting at a hub
    /// and this leg's share of their through fares. Nil until the route has
    /// carried one, which keeps older saves and point-to-point networks as
    /// they were.
    public var connectingPassengers: Int64?
    public var connectingRevenueCents: Int64?

    public init(revenueCents: Int64 = 0, fuelCents: Int64 = 0, feesCents: Int64 = 0,
                crewCents: Int64 = 0, passengers: Int64 = 0,
                connectingPassengers: Int64? = nil, connectingRevenueCents: Int64? = nil) {
        self.revenueCents = revenueCents
        self.fuelCents = fuelCents
        self.feesCents = feesCents
        self.crewCents = crewCents
        self.passengers = passengers
        self.connectingPassengers = connectingPassengers
        self.connectingRevenueCents = connectingRevenueCents
    }

    /// Direct operating profit (costs are stored positive).
    public var directOperatingProfit: Money {
        Money(cents: revenueCents - fuelCents - feesCents - crewCents)
    }
}

/// The connecting travellers inside a route's bookable demand for the day,
/// by direction (docs/HUB_PROGRESSION_PLAN.md §4 #6). They are part of
/// `demandOutboundToday` / `demandInboundToday`, not extra to them; this only
/// says how many of those seats are connections and what each one pays.
public struct ConnectingLoad: Equatable, Codable, Sendable {
    public struct Direction: Equatable, Codable, Sendable {
        /// Connecting travellers in the day's demand this way.
        public var booked: Int
        /// Of those, still to board.
        public var remaining: Int
        /// This leg's share of their through fares, per traveller, before
        /// the cabin's yield.
        public var fare: Money

        public init(booked: Int = 0, remaining: Int = 0, fare: Money = .zero) {
            self.booked = booked
            self.remaining = remaining
            self.fare = fare
        }
    }

    public var outbound: Direction
    public var inbound: Direction

    public init(outbound: Direction = Direction(), inbound: Direction = Direction()) {
        self.outbound = outbound
        self.inbound = inbound
    }

    public var booked: Int { outbound.booked + inbound.booked }

    public func direction(outbound isOutbound: Bool) -> Direction { isOutbound ? outbound : inbound }

    public mutating func set(_ direction: Direction, outbound isOutbound: Bool) {
        if isOutbound { outbound = direction } else { inbound = direction }
    }
}
