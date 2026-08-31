import Testing
@testable import AirlineEmpireCore

/// Why a route earns or loses (MASTER PROMPT 4 §13).
///
/// The verdict's whole value is that a player can trust it, so the tests that
/// matter are the ones about *restraint*: that it stays silent when the data
/// cannot support a claim, that it does not call an unflown route empty, and
/// that when several things are wrong it names the one that actually dominates
/// rather than whichever the code happened to check first.
@Suite("Route verdicts")
struct RouteVerdictTests {

    /// A card built directly, so each case is exactly the shape it describes.
    /// Going through a live simulation would make these tests about the
    /// balance tuning rather than about the attribution rules.
    private func card(loadFactor: Double = 0.8,
                      farePosition: Double = 1.0,
                      completionRate: Double = 1.0,
                      assigned: Int = 1,
                      revenue: Int64 = 1_000_000,
                      fuel: Int64 = 300_000,
                      fees: Int64 = 200_000,
                      crew: Int64 = 100_000,
                      passengers: Int64 = 5_000) -> RouteCardModel {
        let economics = RouteMonthEconomics(
            revenueCents: revenue, fuelCents: fuel, feesCents: fees,
            crewCents: crew, passengers: passengers)
        return RouteCardModel(
            id: RouteID(raw: 1), origin: "ARN", destination: "KRP",
            distanceKm: 900, dailyRoundTrips: 2, ticketPrice: Money.dollars(200),
            farePosition: farePosition, assignedAircraftCount: assigned,
            loadFactor: loadFactor, punctuality: 0.9,
            completionRate: completionRate,
            lastMonthProfit: .zero, lastMonthPassengers: 0,
            lastMonthBreakdown: RouteMonthEconomics(),
            thisMonthBreakdown: economics,
            thisMonthProfit: economics.directOperatingProfit,
            thisMonthPassengers: passengers,
            hasClosedMonth: false, hasFlown: true)
    }

    @Test("A route with no aircraft is idle, not empty")
    func unassignedRouteIsIdle() {
        let verdict = card(assigned: 0).verdict
        #expect(verdict.standing == .idle)
        // The distinction that matters: "your aeroplanes are flying half
        // empty" would be true of a route flying nothing, and useless.
        #expect(verdict.primary == nil)
    }

    @Test("A route that has not flown yet is too early to judge")
    func unflownRouteIsTooEarly() {
        let verdict = card(revenue: 0, fuel: 0, fees: 0, crew: 0,
                           passengers: 0).verdict
        #expect(verdict.standing == .tooEarly)
        #expect(verdict.primary == nil)
    }

    @Test("A full, well-priced route is earning, and says why")
    func fullRouteIsEarning() {
        let verdict = card(loadFactor: 0.86, farePosition: 1.15).verdict
        #expect(verdict.standing == .earning)
        #expect(verdict.primary == .strongDemand(loadFactor: 0.86))
        #expect(verdict.secondary == .fareAboveMarket(position: 1.15))
    }

    @Test("An empty route blames the load factor")
    func emptyRouteBlamesLoad() {
        // Costs unremarkable; the only thing wrong is that nobody is on board.
        let verdict = card(loadFactor: 0.25, revenue: 300_000, fuel: 200_000,
                           fees: 80_000, crew: 100_000).verdict
        #expect(verdict.standing == .losing)
        #expect(verdict.primary == .loadFactor(0.25))
    }

    @Test("When fees dominate a loss, fees are named — not load factor")
    func feesOutrankAMarginalLoad() {
        // Load factor 0.52 is barely under the 0.55 bar; fees are at 60% of
        // revenue, which is far past theirs. The verdict must name the term
        // that is actually dominant.
        let verdict = card(loadFactor: 0.52, revenue: 1_000_000,
                           fuel: 200_000, fees: 600_000, crew: 300_000).verdict
        #expect(verdict.standing == .losing)
        #expect(verdict.primary == .fees(shareOfRevenue: 0.6))
        #expect(verdict.secondary == .loadFactor(0.52))
    }

    @Test("A loss with nothing out of the ordinary names nothing")
    func unremarkableLossStaysSilent() {
        // Losing, but every ratio is within its normal band: full-ish
        // aeroplanes, market fare, flights completing, ordinary costs. There
        // is no honest single cause, so the verdict must not invent one.
        let verdict = card(loadFactor: 0.70, farePosition: 1.0,
                           completionRate: 1.0, revenue: 1_000_000,
                           fuel: 400_000, fees: 250_000, crew: 400_000).verdict
        #expect(verdict.standing == .losing)
        #expect(verdict.primary == nil,
                "a verdict that always names a cause is not evidence")
    }

    @Test("Cancellations are named when flights are not completing")
    func cancellationsAreNamed() {
        let verdict = card(loadFactor: 0.80, completionRate: 0.55,
                           revenue: 400_000, fuel: 200_000, fees: 150_000,
                           crew: 200_000).verdict
        #expect(verdict.standing == .losing)
        #expect(verdict.primary == .cancellations(completionRate: 0.55))
    }

    @Test("An underpriced route is told its fare is below the market")
    func underpricedRouteBlamesFare() {
        let verdict = card(loadFactor: 0.95, farePosition: 0.55,
                           revenue: 500_000, fuel: 250_000, fees: 150_000,
                           crew: 200_000).verdict
        #expect(verdict.standing == .losing)
        #expect(verdict.primary == .fareBelowMarket(position: 0.55))
    }

    @Test("Standing always agrees with the arithmetic it describes")
    func standingMatchesProfit() {
        // The verdict must never say "earning" about a negative number,
        // whatever the drivers look like.
        for load in stride(from: 0.1, through: 1.0, by: 0.1) {
            for fee in stride(from: 0.0, through: 800_000.0, by: 200_000.0) {
                let c = card(loadFactor: load, fees: Int64(fee))
                switch c.verdict.standing {
                case .earning: #expect(c.thisMonthProfit.cents > 0)
                case .losing: #expect(c.thisMonthProfit.cents <= 0)
                case .idle, .tooEarly: break
                }
            }
        }
    }
}
