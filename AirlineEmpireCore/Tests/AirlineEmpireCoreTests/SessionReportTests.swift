import Testing
@testable import AirlineEmpireCore

@Suite("Session report")
struct SessionReportTests {
    @Test func aFlyingSessionReportsItsActualActivityAndRestartsFromZero() throws {
        let (engine, _, _) = try DemandFixtures.market(fare: .dollars(129))
        let start = try #require(SessionCheckpoint(engine.state))
        engine.advance(ticks: Fixtures.ticksPerDay * 3)
        let end = try #require(SessionCheckpoint(engine.state))
        let report = try #require(SessionReport(from: start, to: end))
        #expect(report.days == 3)
        #expect(report.flights > 0)
        #expect(report.passengers > 0)
        #expect(report.routeChange == 0)
        #expect(report.aircraftChange == 0)
        #expect(SessionReport(from: end, to: start) == nil)
        let reopened = try #require(SessionReport(from: end, to: end))
        #expect(reopened.cashChange == .zero)
        #expect(reopened.flights == 0)
        #expect(reopened.passengers == 0)
    }
}
