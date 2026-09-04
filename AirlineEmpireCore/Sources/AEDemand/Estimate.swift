import Foundation
import AirlineEmpireCore

/// The corrected estimate under test.
///
/// Phases 2–5 measured a *hypothesis* here, built from the demand engine's
/// public primitives, before anything in Core changed. Phase 9 moved the
/// validated version into `DemandSystem.serviceDemand` /
/// `CompetitorAISystem.airframeDayEstimate`, so this is now a one-line
/// delegation: the tool and the product cannot answer differently, and every
/// number in docs/AE044_AIRFRAME_VALUE_AUDIT.md can be re-measured against
/// the shipped code.
struct CorrectedEstimate {
    var passengers: Double
    var carried: Double
    var revenue: Double
    var profit: Double
}

@MainActor
func correctedEstimate(origin: AirportSpec, destination: AirportSpec, distanceKm: Int,
                       spec: AircraftTypeSpec, roundTrips: Int, incumbents: [Route],
                       state: GameState, serviceTier: ServiceTier,
                       fareRatio: Double = 1.0,
                       operationsOverride: Double? = nil,
                       reputationMultiplier: Double = 1.0) -> CorrectedEstimate {
    let catalog = try! ContentCatalog.loadBundled()
    let demand = DemandSystem.serviceDemand(
        origin: origin.code, destination: destination.code, spec: spec,
        roundTripsPerDay: roundTrips, fareRatio: fareRatio,
        operationsScore: operationsOverride ?? DemandSystem.unprovenOperationsScore,
        reputationMultiplier: reputationMultiplier, incumbents: incumbents,
        state: state, catalog: catalog)
    func value(_ basis: CompetitorAISystem.RankingBasis) -> Double {
        CompetitorAISystem.airframeDayEstimate(
            origin: origin, destination: destination, distanceKm: distanceKm,
            spec: spec, fareRatio: fareRatio, serviceTier: serviceTier,
            reputationMultiplier: reputationMultiplier, incumbents: incumbents,
            rotationsPerDay: roundTrips, state: state, catalog: catalog,
            basis: basis).value
    }
    return CorrectedEstimate(passengers: demand.capturedPerDay,
                             carried: demand.carriedPerDay,
                             revenue: value(.revenue), profit: value(.profit))
}
