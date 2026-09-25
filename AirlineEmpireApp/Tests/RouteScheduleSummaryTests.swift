import XCTest
import AirlineEmpireCore
@testable import AirlineEmpire

final class RouteScheduleSummaryTests: XCTestCase {
    private let now = SimTime(rawMinutes: 100)

    private func flight(departure: Int64, phase: FlightPhase = .scheduled) -> Flight {
        var flight = Flight(id: FlightID(raw: departure), route: RouteID(raw: 1),
                            aircraft: AircraftID(raw: 1), kind: .revenue,
                            from: "ARN", to: "BER", distanceKm: 810,
                            flightMinutes: 90, scheduledDeparture: SimTime(rawMinutes: departure))
        flight.phase = phase
        return flight
    }

    func testUsesEarliestPlannedDepartureAndGameTimeWhilePaused() {
        let text = RouteScheduleSummary.text(flights: [flight(departure: 190), flight(departure: 130)],
                                            now: now, paused: true, hasOperationalAircraft: true)
        XCTAssertTrue(text.contains("30 min of game time"))
        XCTAssertTrue(text.contains("paused"))
    }

    func testUsesDelayAdjustedDepartureAndDoesNotPromiseOverdueTakeoff() {
        var delayed = flight(departure: 90)
        delayed.departureTime = SimTime(rawMinutes: 145)
        XCTAssertTrue(RouteScheduleSummary.text(flights: [delayed], now: now,
            paused: false, hasOperationalAircraft: true).contains("45 min of game time"))
        XCTAssertTrue(RouteScheduleSummary.text(flights: [flight(departure: 90)], now: now,
            paused: false, hasOperationalAircraft: true).contains("Departure pending"))
    }

    func testAirborneAndReadinessStatesDoNotAskForAnotherDeparture() {
        let airborne = flight(departure: 90, phase: .enRoute(actualDeparture: SimTime(rawMinutes: 90)))
        XCTAssertTrue(RouteScheduleSummary.text(flights: [airborne], now: now,
            paused: false, hasOperationalAircraft: true).contains("in flight"))
        XCTAssertTrue(RouteScheduleSummary.text(flights: [airborne], now: now,
            paused: true, hasOperationalAircraft: true).contains("paused in the air"))
        XCTAssertTrue(RouteScheduleSummary.text(flights: [], now: now,
            paused: false, hasOperationalAircraft: false).contains("delivery or maintenance"))
    }

    func testReadyAircraftWithoutScheduleExplainsMidnightAndPausedTime() {
        XCTAssertTrue(RouteScheduleSummary.text(flights: [], now: now,
            paused: false, hasOperationalAircraft: true).contains("midnight"))
        XCTAssertTrue(RouteScheduleSummary.text(flights: [], now: now,
            paused: true, hasOperationalAircraft: true).contains("Resume time"))
    }
}
