/// Quotes the change across this airline's routes touching one station.
/// No live commands, demand inventory, ledger entries or random draws change.
public struct AirportInvestmentPreview: Equatable, Sendable {
    public let monthlyRevenueChange: Money
    public let monthlyOperatingProfitChange: Money
    public let monthlyFacilityCostChange: Money
    public let servedRoutes: Int
    public var monthlyNetChange: Money { monthlyOperatingProfitChange - monthlyFacilityCostChange }

    public static func make(airline: AirlineID, airport: AirportCode, proposed: AirportFacilities,
                            state: GameState, catalog: ContentCatalog) -> Self? {
        guard proposed.isValid, let owner = state.airlines[airline], catalog.airport(airport) != nil else { return nil }
        let routes = state.routes(of: airline).filter { $0.origin == airport || $0.destination == airport }
        func totals(_ facilities: AirportFacilities) -> (revenue: Money, profit: Money) {
            var copy = state
            var stations = owner.airportFacilities ?? [:]
            stations[airport] = facilities
            copy.airlines[airline]?.airportFacilities = stations
            let context = SimContext(previous: state.clock.now, current: state.clock.now,
                tick: .minutes(0), catalog: catalog, events: EventCollector(), progressionCeiling: .empire)
            DemandSystem().update(state: &copy, context: context)
            var revenue = Money.zero, profit = Money.zero
            for route in routes {
                for id in route.assignedAircraft.sorted() {
                    if let quote = AircraftConfigurationPreview.makeAllocated(aircraftID: id, state: copy, catalog: catalog) {
                        revenue = revenue + quote.monthlyRevenue
                        profit = profit + quote.monthlyProfit
                    }
                }
            }
            return (revenue, profit)
        }
        let old = owner.facilities(at: airport)
        let before = totals(old), after = totals(proposed)
        return Self(monthlyRevenueChange: after.revenue - before.revenue,
            monthlyOperatingProfitChange: after.profit - before.profit,
            monthlyFacilityCostChange: proposed.monthlyCost(tuning: catalog.tuning.airportServices)
                - old.monthlyCost(tuning: catalog.tuning.airportServices), servedRoutes: routes.count)
    }
}
