/// Snapshot read models (docs/UI_ARCHITECTURE.md §1): the derived numbers
/// the UI presents, computed in Core so every screen shows exactly what the
/// simulation used — and so they are testable without a device.
/// Views format; they never calculate.

public struct DashboardModel: Equatable, Sendable {
    public let airlineName: String
    public let era: Era
    public let cash: Money
    public let netWorth: Money
    public let fleetCount: Int
    public let routeCount: Int
    public let destinationCount: Int
    public let reputationScore: Double
    public let lastMonthNetProfit: Money?
    public let lastMonthRevenue: Money?
    public let fuelPricePerTon: Money
    public let economicIndex: Double
    public let activeEventCount: Int
    /// The player's own aeroplanes in the air right now.
    ///
    /// This was `flights.count` — every flight in the world dictionary, which
    /// is every airline's, in every phase including scheduled and boarding.
    /// It reported 34 for a player with nothing airborne (tasks/BUGS.md
    /// BUG-027).
    public let liveFlightCount: Int
    public let gameOver: Bool
}

public struct RouteCardModel: Equatable, Sendable {
    public let id: RouteID
    public let origin: AirportCode
    public let destination: AirportCode
    public let distanceKm: Int
    public let dailyRoundTrips: Int
    public let ticketPrice: Money
    /// Fare as a multiple of the market reference fare (1.0 = reference).
    public let farePosition: Double
    public let assignedAircraftCount: Int
    public let loadFactor: Double
    public let punctuality: Double
    public let completionRate: Double
    /// Closed previous month; the comparable figure.
    public let lastMonthProfit: Money
    public let lastMonthPassengers: Int64
    /// Cost breakdown for "why did this route make/lose money".
    public let lastMonthBreakdown: RouteMonthEconomics
    /// The month in progress, so a route that opened three days ago has a
    /// story instead of a column of zeros (UIUX_FORENSIC_AUDIT UI-002).
    /// Partial by definition — it is what has happened so far this month.
    public let thisMonthBreakdown: RouteMonthEconomics
    public let thisMonthProfit: Money
    public let thisMonthPassengers: Int64
    /// True before the route's first month has ever closed: `lastMonth*` is
    /// then structurally zero rather than a real result, and a screen must
    /// say so instead of reporting a loss of nothing.
    public let hasClosedMonth: Bool
}

public struct FleetCardModel: Equatable, Sendable {
    public let id: AircraftID
    public let typeCode: AircraftTypeCode
    public let typeName: String
    public let category: AircraftCategory
    public let status: AircraftStatus
    public let ownershipDescription: OwnershipSummary
    public let location: AirportCode
    public let assignedRoute: RouteID?
    public let ageYears: Double
    public let condition: Double
    public let reliability: Double
    public let totalFlightHours: Double

    public enum OwnershipSummary: Equatable, Sendable {
        case owned(bookValue: Money)
        case leased(monthlyRate: Money, monthsRemaining: Int)
    }
}

public struct FinanceModel: Equatable, Sendable {
    public let cash: Money
    public let netWorth: Money
    public let totalDebt: Money
    public let debtRatio: Double
    /// Oldest-first, bounded to statement history.
    public let monthlySeries: [MonthPoint]
    public let loans: [Loan]
    public let lifetimeNetProfit: Money

    public struct MonthPoint: Equatable, Sendable {
        public let year: Int
        public let month: Int
        public let revenue: Money
        public let expenses: Money   // negative
        public let netProfit: Money
    }
}

extension GameState {
    /// The player dashboard; nil before an airline exists.
    public func dashboardModel() -> DashboardModel? {
        guard let player = playerAirline else { return nil }
        let routes = routes(of: player.id)
        var destinationSet = Set<AirportCode>()
        for route in routes {
            destinationSet.insert(route.origin)
            destinationSet.insert(route.destination)
        }
        let latest = finance.byAirline[player.id]?.latest
        return DashboardModel(
            airlineName: player.name,
            era: progression.era,
            cash: ledger.balance(of: player.id),
            netWorth: CreditMath.assets(of: player.id, state: self)
                - CreditMath.totalDebt(of: player),
            fleetCount: fleet(of: player.id).count,
            routeCount: routes.count,
            destinationCount: destinationSet.count,
            reputationScore: player.reputation.score,
            lastMonthNetProfit: latest?.netProfit,
            lastMonthRevenue: latest?.operatingRevenue,
            fuelPricePerTon: world.fuelPricePerTon,
            economicIndex: world.economicIndex,
            activeEventCount: world.activeEvents.filter {
                $0.isActive(at: clock.now)
            }.count,
            liveFlightCount: airborneFlightCount(for: player.id),
            gameOver: progression.gameOver)
    }

    /// Route cards for an airline, deterministic order.
    public func routeCards(for airline: AirlineID,
                           catalog: ContentCatalog) -> [RouteCardModel] {
        routes(of: airline).map { route in
            let reference = DemandSystem.referenceFare(
                distanceKm: route.distanceKm, tuning: catalog.tuning.demand)
            return RouteCardModel(
                id: route.id, origin: route.origin, destination: route.destination,
                distanceKm: route.distanceKm, dailyRoundTrips: route.dailyRoundTrips,
                ticketPrice: route.ticketPrice,
                farePosition: reference > 0 ? route.ticketPrice.asDouble / reference : 1,
                assignedAircraftCount: route.assignedAircraft.count,
                loadFactor: route.stats.loadFactor,
                punctuality: route.stats.punctuality,
                completionRate: route.stats.completionRate,
                lastMonthProfit: route.economicsLastMonth.directOperatingProfit,
                lastMonthPassengers: route.economicsLastMonth.passengers,
                lastMonthBreakdown: route.economicsLastMonth,
                thisMonthBreakdown: route.economicsThisMonth,
                thisMonthProfit: route.economicsThisMonth.directOperatingProfit,
                thisMonthPassengers: route.economicsThisMonth.passengers,
                // A month that closed leaves a trace even when it lost money:
                // some flight flew, or some cost posted. All-zero means the
                // route has not yet lived through a close.
                hasClosedMonth: route.economicsLastMonth != RouteMonthEconomics())
        }
    }

    /// Fleet cards for an airline, deterministic order.
    public func fleetCards(for airline: AirlineID,
                           catalog: ContentCatalog) -> [FleetCardModel] {
        fleet(of: airline).compactMap { aircraft in
            guard let spec = catalog.aircraftType(aircraft.typeCode) else { return nil }
            let ownership: FleetCardModel.OwnershipSummary
            switch aircraft.ownership {
            case .owned(let book):
                ownership = .owned(bookValue: book)
            case .leased(let rate, let remaining):
                ownership = .leased(monthlyRate: rate, monthsRemaining: remaining)
            }
            return FleetCardModel(
                id: aircraft.id, typeCode: aircraft.typeCode,
                typeName: "\(spec.manufacturer) \(spec.model)",
                category: spec.category, status: aircraft.status,
                ownershipDescription: ownership, location: aircraft.location,
                assignedRoute: aircraft.assignedRoute, ageYears: aircraft.ageYears,
                condition: aircraft.condition,
                reliability: aircraft.currentReliability(type: spec,
                                                         tuning: catalog.tuning.fleet),
                totalFlightHours: aircraft.totalFlightHours)
        }
    }

    public func financeModel(for airline: AirlineID) -> FinanceModel? {
        guard let a = airlines[airline] else { return nil }
        let history = finance.byAirline[airline]
        let series = (history?.statements ?? []).map { statement in
            FinanceModel.MonthPoint(year: statement.year, month: statement.month,
                                    revenue: statement.operatingRevenue,
                                    expenses: statement.operatingExpenses,
                                    netProfit: statement.netProfit)
        }
        return FinanceModel(
            cash: ledger.balance(of: airline),
            netWorth: CreditMath.assets(of: airline, state: self)
                - CreditMath.totalDebt(of: a),
            totalDebt: CreditMath.totalDebt(of: a),
            debtRatio: CreditMath.debtRatio(of: a, state: self),
            monthlySeries: series,
            loans: a.loans,
            lifetimeNetProfit: history?.lifetimeNetProfit ?? .zero)
    }
}

// MARK: - Summaries

/// What the whole route network is doing, in one value.
///
/// Every screen that wanted this was deriving it from `routeCards` in a view
/// body — which is O(routes) per render on a pump that publishes four
/// snapshots a second, and which meant Home, the Routes board and the map
/// could each answer "how is the network doing" slightly differently. It is
/// computed once, here, from the same routes the simulation ran.
public struct NetworkSummary: Equatable, Sendable {
    public let routeCount: Int
    /// Routes whose month to date is in profit.
    public let profitableRoutes: Int
    /// Routes losing money right now. Not the inverse of profitable: a route
    /// that has flown nothing yet is neither.
    public let losingRoutes: Int
    /// Open routes with no aircraft on them — capacity the player has paid
    /// slots for and is not using.
    public let idleRoutes: Int
    /// Seats sold over seats flown, across the network, over the routes'
    /// lifetimes — the same basis `RouteCardModel.loadFactor` reports, so the
    /// board and its rows cannot disagree. Nil before anything has flown,
    /// because zero would read as "empty aeroplanes" rather than "no
    /// aeroplanes".
    public let averageLoadFactor: Double?
    public let liveFlights: Int
    public let monthToDateProfit: Money
    public let destinations: Int

    public init(routeCount: Int, profitableRoutes: Int, losingRoutes: Int,
                idleRoutes: Int, averageLoadFactor: Double?, liveFlights: Int,
                monthToDateProfit: Money, destinations: Int) {
        self.routeCount = routeCount
        self.profitableRoutes = profitableRoutes
        self.losingRoutes = losingRoutes
        self.idleRoutes = idleRoutes
        self.averageLoadFactor = averageLoadFactor
        self.liveFlights = liveFlights
        self.monthToDateProfit = monthToDateProfit
        self.destinations = destinations
    }
}

/// What the fleet is doing, in one value.
public struct FleetSummary: Equatable, Sendable {
    public let total: Int
    /// Flying a route today.
    public let assigned: Int
    /// Active, airworthy and doing nothing — the number that costs money.
    public let idle: Int
    public let inMaintenance: Int
    public let onOrder: Int
    /// Assigned over airworthy. Nil with no airworthy aircraft, so a fleet of
    /// nothing does not report 0% utilisation as though it were a failure.
    public let utilization: Double?
    public let averageAgeYears: Double?
    public let averageCondition: Double?
    /// Book value of owned aircraft. Leased aircraft are not an asset.
    public let ownedValue: Money
    public let leasedCount: Int
    /// Monthly lease bill, which is the fleet cost a player can actually act on.
    public let monthlyLeaseCost: Money

    public init(total: Int, assigned: Int, idle: Int, inMaintenance: Int,
                onOrder: Int, utilization: Double?, averageAgeYears: Double?,
                averageCondition: Double?, ownedValue: Money, leasedCount: Int,
                monthlyLeaseCost: Money) {
        self.total = total
        self.assigned = assigned
        self.idle = idle
        self.inMaintenance = inMaintenance
        self.onOrder = onOrder
        self.utilization = utilization
        self.averageAgeYears = averageAgeYears
        self.averageCondition = averageCondition
        self.ownedValue = ownedValue
        self.leasedCount = leasedCount
        self.monthlyLeaseCost = monthlyLeaseCost
    }
}

extension GameState {
    /// Aeroplanes of `airline` currently in the air.
    ///
    /// Airborne means airborne: a flight that is boarding, turning round or
    /// merely scheduled is not traffic the player can watch move. Shared by
    /// `dashboardModel` and `networkSummary` so the two cannot disagree.
    public func airborneFlightCount(for airline: AirlineID) -> Int {
        // A flight carries no airline of its own; it belongs to whoever owns
        // its route.
        let ownRoutes = Set(routes(of: airline).map(\.id))
        var live = 0
        for id in orderedFlightIDs {
            guard let flight = flights[id], ownRoutes.contains(flight.route) else { continue }
            if case .enRoute = flight.phase { live += 1 }
        }
        return live
    }

    /// The network at a glance. Deterministic; derived from the same routes
    /// and flights the simulation stepped.
    public func networkSummary(for airline: AirlineID) -> NetworkSummary {
        let routes = self.routes(of: airline)
        var profitable = 0, losing = 0, idle = 0
        var monthToDate = Money.zero
        var destinations = Set<AirportCode>()

        // Load factor is weighted by seats flown rather than averaged over
        // routes: one daily widebody and one weekly turboprop are not two
        // equal opinions about how full the airline is.
        var seatsSold: Int64 = 0
        var seatsFlown: Int64 = 0

        for route in routes {
            let profit = route.economicsThisMonth.directOperatingProfit
            monthToDate = monthToDate + profit
            if profit.isNegative {
                losing += 1
            } else if profit.cents > 0 {
                profitable += 1
            }
            if route.assignedAircraft.isEmpty { idle += 1 }
            destinations.insert(route.origin)
            destinations.insert(route.destination)

            if route.stats.seatsFlown > 0 {
                seatsFlown += route.stats.seatsFlown
                seatsSold += route.stats.passengersCarried
            }
        }

        let live = airborneFlightCount(for: airline)

        return NetworkSummary(
            routeCount: routes.count, profitableRoutes: profitable,
            losingRoutes: losing, idleRoutes: idle,
            averageLoadFactor: seatsFlown > 0
                ? Double(seatsSold) / Double(seatsFlown) : nil,
            liveFlights: live, monthToDateProfit: monthToDate,
            destinations: destinations.count)
    }

    /// The fleet at a glance.
    public func fleetSummary(for airline: AirlineID) -> FleetSummary {
        let aircraft = fleet(of: airline)
        var assigned = 0, idle = 0, maintenance = 0, onOrder = 0, leased = 0
        var ageTotal = 0.0, conditionTotal = 0.0, airworthy = 0
        var owned = Money.zero
        var leaseBill = Money.zero

        for unit in aircraft {
            switch unit.status {
            case .ordered: onOrder += 1
            case .inMaintenance: maintenance += 1
            case .active:
                airworthy += 1
                if unit.assignedRoute == nil { idle += 1 } else { assigned += 1 }
            }
            // Age and condition describe every aircraft the airline owns,
            // including one waiting for its check — that is exactly when its
            // condition matters most.
            if !unit.status.isOnOrder {
                ageTotal += unit.ageYears
                conditionTotal += unit.condition
            }
            switch unit.ownership {
            case .owned(let book): owned = owned + book
            case .leased(let rate, _):
                leased += 1
                leaseBill = leaseBill + rate
            }
        }

        let delivered = aircraft.count - onOrder
        return FleetSummary(
            total: aircraft.count, assigned: assigned, idle: idle,
            inMaintenance: maintenance, onOrder: onOrder,
            utilization: airworthy > 0
                ? Double(assigned) / Double(airworthy) : nil,
            averageAgeYears: delivered > 0 ? ageTotal / Double(delivered) : nil,
            averageCondition: delivered > 0 ? conditionTotal / Double(delivered) : nil,
            ownedValue: owned, leasedCount: leased, monthlyLeaseCost: leaseBill)
    }
}
