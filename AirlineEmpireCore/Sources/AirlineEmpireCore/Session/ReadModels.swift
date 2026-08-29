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
            liveFlightCount: flights.count,
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
