/// Monthly airline economics (docs/ECONOMY.md): overhead & payroll, loan
/// service. Runs after fleet billing on the month boundary.
public struct EconomySystem: SimulationSystem {
    public let id = "economy"
    public let cadence = Cadence.monthly

    public init() {}

    public func update(state: inout GameState, context: SimContext) {
        let tuning = context.catalog.tuning.finance
        for airlineID in state.orderedAirlineIDs {
            var airline = state.airlines[airlineID]!
            guard airline.status == .active else { continue }

            // Payroll & overhead scale with the operation's size.
            let fleetCount = Int64(state.fleet(of: airlineID).count)
            let routeCount = Int64(state.routes(of: airlineID).count)
            let salaries = tuning.payrollPerAircraftMonthly * fleetCount
                + tuning.payrollPerRouteMonthly * routeCount
            if salaries > .zero {
                state.ledger.post(airline: airlineID, category: .salaries,
                                  amount: -salaries, at: context.current, memo: "Payroll")
            }
            state.ledger.post(airline: airlineID, category: .overhead,
                              amount: -tuning.overheadBaseMonthly, at: context.current,
                              memo: "Company overhead")

            // Loan service: interest + principal from the fixed annuity.
            var remainingLoans: [Loan] = []
            for var loan in airline.loans {
                let interest = Money(rounding: loan.principalRemaining.asDouble * loan.monthlyRate)
                let principalDue = min(loan.principalRemaining,
                                       max(.zero, loan.monthlyPayment - interest))
                state.ledger.post(airline: airlineID, category: .loanInterest,
                                  amount: -interest, at: context.current, memo: "Loan interest")
                state.ledger.post(airline: airlineID, category: .loanPrincipal,
                                  amount: -principalDue, at: context.current,
                                  memo: "Loan principal")
                loan.principalRemaining = loan.principalRemaining - principalDue
                loan.monthsRemaining = max(0, loan.monthsRemaining - 1)
                // A residual from annuity rounding settles with the final
                // scheduled payment.
                if loan.monthsRemaining == 0 && loan.principalRemaining > .zero {
                    state.ledger.post(airline: airlineID, category: .loanPrincipal,
                                      amount: -loan.principalRemaining, at: context.current,
                                      memo: "Loan settlement")
                    loan.principalRemaining = .zero
                }
                if loan.principalRemaining > .zero {
                    remainingLoans.append(loan)
                }
            }
            airline.loans = remainingLoans
            state.airlines[airlineID] = airline
        }
    }
}

/// Daily solvency watch (docs/GAME_DESIGN.md §5): sustained deep overdraft
/// forces administration (fire-sale restructuring with a creditor haircut);
/// a second failure — or one that restructuring cannot fix — collapses the
/// airline for good.
public struct SolvencySystem: SimulationSystem {
    public let id = "solvency"
    public let cadence = Cadence.daily

    public init() {}

    public func update(state: inout GameState, context: SimContext) {
        let tuning = context.catalog.tuning.finance
        for airlineID in state.orderedAirlineIDs {
            var airline = state.airlines[airlineID]!
            guard airline.status == .active else { continue }
            let balance = state.ledger.balance(of: airlineID)
            if balance.cents < tuning.overdraftFloorCents {
                airline.daysInsolvent += 1
            } else {
                airline.daysInsolvent = 0
            }
            guard airline.daysInsolvent >= tuning.administrationGraceDays else {
                state.airlines[airlineID] = airline
                continue
            }

            if airline.administrationCount >= 1 {
                collapse(&airline, state: &state, context: context)
            } else {
                administer(&airline, state: &state, context: context)
                // Restructuring must actually restore solvency; if even the
                // fire sale could not, the airline is finished.
                if state.ledger.balance(of: airlineID).cents < tuning.overdraftFloorCents {
                    collapse(&airline, state: &state, context: context)
                }
            }
            state.airlines[airlineID] = airline
        }
    }

    /// Administration: sell unassigned owned aircraft at fire-sale prices
    /// until solvent; creditors write off part of the debt.
    private func administer(_ airline: inout Airline, state: inout GameState,
                            context: SimContext) {
        let tuning = context.catalog.tuning.finance
        airline.administrationCount += 1
        airline.daysInsolvent = 0

        for aircraft in state.fleet(of: airline.id) {
            guard state.ledger.balance(of: airline.id) < .zero else { break }
            guard case .owned = aircraft.ownership,
                  aircraft.assignedRoute == nil, aircraft.activeFlight == nil
            else { continue }
            let spec = context.catalog.aircraftType(aircraft.typeCode)!
            let value = FleetEconomics.saleValue(
                type: spec, ageYears: aircraft.ageYears, condition: aircraft.condition,
                tuning: context.catalog.tuning.fleet)
            let proceeds = Money(rounding: value.asDouble * tuning.fireSalePriceFactor)
            state.ledger.post(airline: airline.id, category: .aircraftSale,
                              amount: proceeds, at: context.current,
                              memo: "Fire sale, \(spec.model)")
            state.aircraft[aircraft.id] = nil
        }

        airline.reputation.applyScar(
            factor: context.catalog.tuning.reputation.administrationScar)
        airline.loans = airline.loans.map { loan in
            var restructured = loan
            let forgiven = Money(rounding: loan.principalRemaining.asDouble
                * tuning.administrationHaircut)
            restructured.principalRemaining = loan.principalRemaining - forgiven
            if restructured.monthsRemaining > 0 {
                restructured.monthlyPayment = CreditMath.annuityPayment(
                    principal: restructured.principalRemaining,
                    monthlyRate: loan.monthlyRate,
                    months: restructured.monthsRemaining)
            }
            return restructured
        }
        context.emit(.airlineEnteredAdministration(id: airline.id))
    }

    /// Terminal failure: routes close (slots freed, flights cancelled),
    /// leased aircraft return, owned aircraft liquidate, debt dies with the
    /// company.
    private func collapse(_ airline: inout Airline, state: inout GameState,
                          context: SimContext) {
        for route in state.routes(of: airline.id) {
            for flightID in state.orderedFlightIDs {
                guard let flight = state.flights[flightID], flight.route == route.id
                else { continue }
                if var aircraft = state.aircraft[flight.aircraft],
                   aircraft.activeFlight == flightID {
                    aircraft.activeFlight = nil
                    state.aircraft[flight.aircraft] = aircraft
                }
                state.flights[flightID] = nil
            }
            let movements = Route.dailySlotMovements(roundTrips: route.dailyRoundTrips)
            _ = state.world.releaseSlots(airline: airline.id, airport: route.origin,
                                         count: movements)
            _ = state.world.releaseSlots(airline: airline.id, airport: route.destination,
                                         count: movements)
            state.routes[route.id] = nil
            // A collapse empties markets the same way a closure does, and
            // the record must say so: the feed only ever carried the
            // collapse itself, never which city pairs it freed.
            state.world.recordMarketMove(MarketMove(
                at: state.clock.now, airline: airline.id, origin: route.origin,
                destination: route.destination, kind: .left))
            context.emit(.marketLeft(airline: airline.id, origin: route.origin,
                                     destination: route.destination))
        }
        for aircraft in state.fleet(of: airline.id) {
            state.aircraft[aircraft.id] = nil
        }
        airline.loans = []
        airline.status = .collapsed
        airline.daysInsolvent = 0
        context.emit(.airlineCollapsed(id: airline.id))
    }
}

/// Month-boundary statement rollup. Runs BEFORE the month's new billings in
/// the pipeline so a closed statement contains exactly the previous month's
/// postings (deviation from the doc's #11 slot, documented in ECONOMY.md).
public struct StatementRollupSystem: SimulationSystem {
    public let id = "statementRollup"
    public let cadence = Cadence.monthly

    public init() {}

    public func update(state: inout GameState, context: SimContext) {
        let tuning = context.catalog.tuning.finance
        // The month that just ended.
        let closed = GameCalendar.date(at: context.previous, startYear: state.meta.startYear)

        for airlineID in state.orderedAirlineIDs {
            let totals = state.ledger.drainMonthAccumulator(for: airlineID)
            guard !totals.isEmpty else { continue }
            let statement = MonthlyStatement(year: closed.year, month: closed.month,
                                             byCategory: totals)
            state.finance.append(statement, for: airlineID,
                                 keeping: tuning.statementHistoryMonths)
            context.emit(.statementClosed(airline: airlineID, year: closed.year,
                                          month: closed.month,
                                          netProfit: statement.netProfit))
        }

        for routeID in state.orderedRouteIDs {
            var route = state.routes[routeID]!
            route.economicsLastMonth = route.economicsThisMonth
            route.economicsThisMonth = RouteMonthEconomics()
            state.routes[routeID] = route
        }
    }
}
