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
            aircraft.ageDays += 1

            switch aircraft.status {
            case .ordered(let deliveryAt):
                if deliveryAt <= context.current {
                    aircraft.status = .active
                    context.emit(.aircraftDelivered(id: aircraftID))
                }

            case .inMaintenance(let until):
                if until <= context.current {
                    aircraft.status = .active
                    aircraft.condition = 1.0
                    context.emit(.maintenanceCompleted(id: aircraftID))
                }

            case .active:
                aircraft.condition = max(0, aircraft.condition - tuning.dailyConditionDecay)
                if aircraft.condition < tuning.maintenanceConditionThreshold {
                    let spec = context.catalog.aircraftType(aircraft.typeCode)!
                    let cost = FleetEconomics.maintenanceCheckCost(
                        type: spec, ageYears: aircraft.ageYears, tuning: tuning)
                    let until = context.current + .days(Int64(tuning.maintenanceCheckDays))
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
                let spec = context.catalog.aircraftType(aircraft.typeCode)!
                aircraft.ownership = .owned(bookValue: FleetEconomics.depreciatedValue(
                    type: spec, ageYears: aircraft.ageYears, tuning: tuning))
            }
            state.aircraft[aircraftID] = aircraft
        }
    }
}

/// Canonical pipeline order for the full game
/// (docs/SIMULATION_ARCHITECTURE.md §4): systems register here as their
/// phases land. Sessions and tools use this; tests may compose subsets.
public enum GamePipeline {
    public static func standard() -> [any SimulationSystem] {
        [
            DemandSystem(),             // #2 in the documented pipeline
            FlightSchedulingSystem(),   // #4
            FlightOpsSystem(),          // #5 (+ passenger allocation at boarding, #6)
            FleetSystem(),              // #7 (maintenance/aging/deliveries)
            FleetBillingSystem(),       // #8 (fleet money)
        ]
    }
}
