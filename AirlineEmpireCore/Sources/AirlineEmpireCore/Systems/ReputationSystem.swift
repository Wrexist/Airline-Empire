/// Daily reputation evolution (docs/GAME_DESIGN.md §4.10): measures the
/// day's operations, fleet comfort, service tier, and price positioning,
/// then drifts each component toward what the airline actually delivers.
public struct ReputationSystem: SimulationSystem {
    public let id = "reputation"
    public let cadence = Cadence.daily

    public init() {}

    public func update(state: inout GameState, context: SimContext) {
        let tuning = context.catalog.tuning.reputation

        for airlineID in state.orderedAirlineIDs {
            var airline = state.airlines[airlineID]!
            guard airline.status == .active else { continue }

            // Operations: only days with flights teach anything.
            let ops = airline.opsToday
            if ops.flights > 0 {
                let completion = Double(ops.completed) / Double(ops.flights)
                Reputation.drift(&airline.reputation.reliability,
                                 toward: completion, rate: tuning.driftRate)
                if ops.completed > 0 {
                    let onTime = Double(ops.completed - min(ops.delayed, ops.completed))
                        / Double(ops.completed)
                    Reputation.drift(&airline.reputation.punctuality,
                                     toward: onTime, rate: tuning.driftRate)
                }
            }
            airline.opsToday = DailyOps()

            // Service drifts toward the tier the airline pays for
            // (+ ground-experience capability bump for the player).
            let serviceTarget = Self.serviceTarget(
                for: airline.serviceTier, isPlayer: airline.kind == .player,
                hasGroundExperience: state.playerHasCapability(.groundExperience),
                tuning: tuning)
            Reputation.drift(&airline.reputation.service,
                             toward: serviceTarget, rate: tuning.driftRate)

            // Comfort: seat-weighted fleet hardware quality.
            if let target = Self.seatWeightedComfort(of: state.fleet(of: airlineID),
                                                    catalog: context.catalog) {
                Reputation.drift(&airline.reputation.comfort,
                                 toward: target, rate: tuning.driftRate)
            }

            // Value perception: quality delivered relative to price position.
            let routes = state.routes(of: airlineID)
            if !routes.isEmpty {
                var ratioSum = 0.0
                for route in routes {
                    let reference = DemandSystem.referenceFare(
                        distanceKm: route.distanceKm, tuning: context.catalog.tuning.demand)
                    ratioSum += route.ticketPrice.asDouble / reference
                }
                let todayPosition = ratioSum / Double(routes.count)
                // Unclamped: a fare position is a ratio and routinely
                // exceeds 1 (the generic drift clamps to 0...1, which would
                // silently pin premium pricing at neutral — caught by test).
                airline.reputation.farePositionEWMA +=
                    tuning.valueDriftRate * (todayPosition - airline.reputation.farePositionEWMA)
            }
            let quality = (airline.reputation.punctuality + airline.reputation.reliability
                + airline.reputation.service + airline.reputation.comfort) / 4
            // Neutral quality at reference fare reads 0.5; better quality
            // raises value, premium fares demand premium quality to keep it.
            let valueTarget = min(1, max(0, 0.5 + (quality - 0.5)
                - 0.75 * (airline.reputation.farePositionEWMA - 1)))
            Reputation.drift(&airline.reputation.valuePerception,
                             toward: valueTarget, rate: tuning.valueDriftRate)

            state.airlines[airlineID] = airline
        }
    }
}

extension ReputationSystem {
    /// The service component a tier drifts toward, including the player's
    /// ground-experience capability bump. One definition for the daily system,
    /// the aircraft experience profile and the service-policy preview, so a
    /// forecast cannot promise a different target than the engine delivers.
    public static func serviceTarget(for tier: ServiceTier, isPlayer: Bool,
                                     hasGroundExperience: Bool,
                                     tuning: ReputationTuning) -> Double {
        var target = tuning.serviceTarget(tier)
        if isPlayer, hasGroundExperience {
            target = min(1, target + 0.08)
        }
        return target
    }

    /// Seat-weighted cabin comfort — exactly the value the comfort component
    /// drifts toward, and nil when nothing in the fleet can be measured
    /// (no aircraft, or no catalog type for any of them).
    public static func seatWeightedComfort(of fleet: [Aircraft],
                                           catalog: ContentCatalog) -> Double? {
        var seatSum = 0.0
        var weighted = 0.0
        for aircraft in fleet {
            guard let spec = catalog.aircraftType(aircraft.typeCode) else { continue }
            let seats = Double(aircraft.cabin(for: spec).totalSeats)
            seatSum += seats
            weighted += seats * aircraft.passengerComfort(
                for: spec, tuning: catalog.tuning.cabin)
        }
        guard seatSum > 0 else { return nil }
        return weighted / seatSum
    }
}
