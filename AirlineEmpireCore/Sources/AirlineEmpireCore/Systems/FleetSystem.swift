/// Daily fleet lifecycle: aging, condition wear, delivery arrivals, and
/// maintenance-check transitions (docs/AIRCRAFT.md).
///
/// Maintenance is triggered by condition, not cash: a required check posts
/// its cost even into a negative balance — deferred maintenance isn't a
/// player choice, but the bill is (bankruptcy pressure arrives in Phase 8).
public struct FleetSystem: SimulationSystem {
    public let id = "fleet"
    public let cadence = Cadence.daily

    public init() {}

    public func update(state: inout GameState, context: SimContext) {
        let tuning = context.catalog.tuning.fleet
        for aircraftID in state.orderedAircraftIDs {
            var aircraft = state.aircraft[aircraftID]!
            // An airframe on order has not been built: it starts ageing on
            // delivery. Ageing it through the lead time delivered a new
            // MR410 two years old and $62M under its price.
            if !aircraft.status.isOnOrder {
                aircraft.ageDays += 1
            }

            switch aircraft.status {
            case .ordered(let deliveryAt):
                if deliveryAt <= context.current {
                    aircraft.status = .active
                    // New off the line. Clears the age a save from before
                    // this rule gave the airframe while it waited.
                    aircraft.ageDays = 0
                    context.emit(.aircraftDelivered(id: aircraftID))
                }

            case .inMaintenance(let until):
                if until <= context.current {
                    aircraft.status = .active
                    aircraft.condition = 1.0
                    context.emit(.maintenanceCompleted(id: aircraftID))
                }

            case .active:
                let before = aircraft.condition
                aircraft.condition = max(0, aircraft.condition - tuning.dailyConditionDecay)
                var due = aircraft.condition < tuning.maintenanceConditionThreshold
                // Long haul (docs/ROUTES.md): the check waits until the
                // aircraft is home rather than stranding it at the far end
                // with its return leg cancelled; and one home that could not
                // fly another rotation above the threshold goes in now — the
                // scheduler has kept it on the ground today for that reason.
                if let longHaul = state.longHaulRotation(of: aircraft, catalog: context.catalog) {
                    if state.hasLegsAhead(aircraftID) {
                        due = false
                    } else if !due {
                        due = !FlightSchedulingSystem.completesRotation(
                            condition: before, rotation: longHaul.rotation,
                            flightMinutes: longHaul.flightMinutes, fleet: tuning,
                            ops: context.catalog.tuning.ops)
                    }
                }
                if due {
                    let spec = context.catalog.aircraftType(aircraft.typeCode)!
                    var cost = FleetEconomics.maintenanceCheckCost(
                        type: spec, ageYears: aircraft.ageYears, tuning: tuning)
                    var days = tuning.maintenanceCheckDays
                    // The owner's hangar where the aircraft flies shortens
                    // the check, and at the top level makes it cheaper.
                    let hangar = state.hangarLevel(serving: aircraft)
                    if hangar > 0 {
                        let facilities = context.catalog.tuning.airportServices
                        days = min(days, facilities.hangarCheckDays[safe: hangar - 1] ?? days)
                        let factor = facilities.hangarCheckCostFactor[safe: hangar - 1] ?? 1
                        if factor < 1 { cost = Money(rounding: cost.asDouble * factor) }
                    }
                    let until = context.current + .days(Int64(days))
                    state.ledger.post(airline: aircraft.owner, category: .maintenance,
                                      amount: -cost, at: context.current,
                                      memo: "Check, \(spec.model)")
                    aircraft.status = .inMaintenance(until: until)
                    context.emit(.maintenanceStarted(id: aircraftID, until: until, cost: cost))
                }
            }

            state.aircraft[aircraftID] = aircraft
        }
    }
}

/// Monthly fleet money: lease billing and book-value depreciation.
/// Split from `FleetSystem` so billing cadence is explicit and testable.
public struct FleetBillingSystem: SimulationSystem {
    public let id = "fleetBilling"
    public let cadence = Cadence.monthly

    public init() {}

    public func update(state: inout GameState, context: SimContext) {
        let tuning = context.catalog.tuning.fleet
        for aircraftID in state.orderedAircraftIDs {
            var aircraft = state.aircraft[aircraftID]!
            switch aircraft.ownership {
            case .leased(let monthlyRate, let remaining):
                let spec = context.catalog.aircraftType(aircraft.typeCode)!
                state.ledger.post(airline: aircraft.owner, category: .leasePayment,
                                  amount: -monthlyRate, at: context.current,
                                  memo: "Lease, \(spec.model)")
                // Term counts down to 0, then continues month-to-month
                // (returnable without penalty).
                aircraft.ownership = .leased(monthlyRate: monthlyRate,
                                             termMonthsRemaining: max(0, remaining - 1))

            case .owned:
                // Recomputed from the curve each month (idempotent, driftless).
                // An order is carried at age zero — list, what was paid —
                // until delivery: nothing depreciates before it exists.
                let spec = context.catalog.aircraftType(aircraft.typeCode)!
                let ageYears = aircraft.status.isOnOrder ? 0 : aircraft.ageYears
                aircraft.ownership = .owned(bookValue: FleetEconomics.depreciatedValue(
                    type: spec, ageYears: ageYears, tuning: tuning))
            }
            state.aircraft[aircraftID] = aircraft
        }
    }
}

/// Canonical pipeline order for the full game
/// (docs/SIMULATION_ARCHITECTURE.md §4): systems register here as their
/// phases land. Sessions and tools use this; tests may compose subsets.
public enum GamePipeline {
    /// `aiRankingBasis` is for tooling that re-measures the rivals' market
    /// ranking (`ae-rival-scan --profit`); the game always runs the shipped
    /// basis.
    public static func standard(
        aiRankingBasis: CompetitorAISystem.RankingBasis = CompetitorAISystem.shippedRankingBasis
    ) -> [any SimulationSystem] {
        [
            WorldEventSystem(),         // #1a: event lifecycle before world prices
            WorldSystem(),              // #1 in the documented pipeline
            StatementRollupSystem(),    // closes the previous month BEFORE new billings
            DemandSystem(),             // #2
            CompetitorAISystem(rankingBasis: aiRankingBasis), // #3
            FacilityConstructionSystem(), // buildings open before today's plan
            FlightSchedulingSystem(),   // #4
            ConnectingDemandSystem(),   // #2's spill term: hub connections, on today's timetable
            FlightOpsSystem(),          // #5 (+ passenger allocation at boarding, #6)
            FleetSystem(),              // #7 (maintenance/aging/deliveries)
            FleetBillingSystem(),       // #8 (fleet money)
            EconomySystem(),            // #8 (payroll/overhead/loan service)
            ReputationSystem(),         // #9
            SolvencySystem(),           // administration / collapse watch
            ProgressionSystem(),        // #10 (after solvency so game over is seen)
        ]
    }
}
