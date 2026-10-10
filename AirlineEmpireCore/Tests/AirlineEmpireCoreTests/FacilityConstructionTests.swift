import Foundation
import Testing
@testable import AirlineEmpireCore

/// Buildings that take game days, the hangar and crew base, and hub status
/// (docs/HUB_PROGRESSION_PLAN.md).
@Suite("Facility construction")
struct FacilityConstructionTests {
    private func context(_ state: GameState, _ catalog: ContentCatalog) -> SimContext {
        .init(previous: state.clock.now, current: state.clock.now, tick: .minutes(0),
              catalog: catalog, events: EventCollector(), progressionCeiling: .empire)
    }

    /// The same engine with the player in `era`.
    private func inEra(_ era: Era, _ engine: SimulationEngine) -> SimulationEngine {
        var state = engine.state
        state.progression.era = era
        return SimulationEngine(state: state, systems: engine.systems, catalog: engine.catalog)
    }

    private func ticks(until time: SimTime, from now: SimTime) -> Int {
        Int((time - now).minutes / ScenarioBootstrap.standardTickMinutes)
    }

    @Test func buildingsOpenAtTheStartOfTheirDay() throws {
        let (catalog, engine, airline) = try FleetFixtures.catalogAndEngine(systems: [FacilityConstructionSystem()])
        engine.advance(ticks: 30)  // mid-morning: the build still opens at midnight
        let ordered = engine.state.clock.now
        #expect(engine.applyNow(ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN",
                                                                  facilities: .init(lounge: 1))) == .applied)
        let build = try #require(engine.state.airlines[airline]?.construction(at: "ARN", of: .lounge))
        let days = catalog.tuning.airportServices.loungeBuildDays[0]
        #expect(build.completesAt.dayIndex == ordered.dayIndex + Int64(days))
        #expect(build.completesAt.minuteOfDay == 0)
        #expect(build.cost == catalog.tuning.airportServices.loungeInstallation)

        engine.advance(ticks: ticks(until: build.completesAt, from: ordered) - 1)
        #expect(engine.state.airlines[airline]?.facilities(at: "ARN").lounge == 0)
        #expect(build.daysLeft(at: engine.state.clock.now) == 1)
        engine.advance(ticks: 1)
        let opened = try #require(engine.state.airlines[airline])
        #expect(opened.facilities(at: "ARN").lounge == 1)
        #expect(opened.facilityConstructions == nil)
        #expect(engine.state.eventLog.recent.contains {
            $0.kind == .facilityOpened(airline: airline, airport: "ARN", service: .lounge, level: 1)
        })
        #expect(engine.state.progression.record.contains {
            $0.kind == .facilityOpened("ARN", .lounge, level: 1)
        })
        // The home airport was a base from the first day, without fanfare.
        #expect(opened.hubStatuses?["ARN"] == .base)
        #expect(!engine.state.eventLog.recent.contains { if case .hubStatusRaised = $0.kind { true } else { false } })
    }

    @Test func aConstructionSurvivesASave() throws {
        let systems: [any SimulationSystem] = [FacilityConstructionSystem()]
        let (catalog, source, airline) = try FleetFixtures.catalogAndEngine(systems: systems)
        #expect(source.applyNow(ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN",
                                                                  facilities: .init(lounge: 2))) == .applied)
        source.advance(ticks: Fixtures.ticksPerDay * 10)
        let restored = SimulationEngine(state: try JSONSaveCodec().decode(JSONSaveCodec().encode(source.state)),
                                        systems: systems, catalog: catalog)
        #expect(restored.state == source.state)
        source.advance(ticks: Fixtures.ticksPerDay * 12)
        restored.advance(ticks: Fixtures.ticksPerDay * 12)
        #expect(restored.state == source.state)
        // 7 + 14 days for two levels at once.
        #expect(source.state.airlines[airline]?.facilities(at: "ARN").lounge == 2)
    }

    @Test func oneBuildAtATimeForEachBuilding() throws {
        let (catalog, engine, airline) = try FleetFixtures.catalogAndEngine()
        #expect(engine.applyNow(ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN",
                                                                  facilities: .init(lounge: 1))) == .applied)
        let more = ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN", facilities: .init(lounge: 2))
        #expect(more.validate(state: engine.state, catalog: catalog)?.code == "airport.underConstruction")
        let back = ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN", facilities: .init())
        #expect(back.validate(state: engine.state, catalog: catalog)?.code == "airport.underConstruction")
        // Another building beside it is fine, and the lounge's order stands.
        let cash = engine.state.ledger.balance(of: airline)
        #expect(engine.applyNow(ConfigureAirportFacilitiesCommand(
            airline: airline, airport: "ARN", facilities: .init(lounge: 1, groundServices: 1))) == .applied)
        #expect(engine.state.ledger.balance(of: airline) == cash - catalog.tuning.airportServices.groundInstallation)
        #expect(engine.state.airlines[airline]?.facilityConstructions?.count == 2)
    }

    @Test func regionalBuildingsWaitForTheRegionalEra() throws {
        let (catalog, startup, airline) = try FleetFixtures.catalogAndEngine()
        let hangar = ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN", facilities: .init(hangar: 1))
        let rejection = hangar.validate(state: startup.state, catalog: catalog)
        #expect(rejection?.code == "airport.eraLocked")
        #expect(rejection?.message.contains("Regional") == true)
        let offer = try #require(startup.state.hubUpgradeOffers(airport: "ARN", catalog: catalog).first { $0.kind == .hangar })
        #expect(offer.lockedUntil == .regional)
        #expect(!offer.canUpgrade)
        let regional = inEra(.regional, startup)
        #expect(regional.applyNow(hangar) == .applied)
        // Rivals are established carriers and exempt.
        #expect(startup.applyNow(FoundAirlineCommand(airlineName: "Rival", kind: .ai, homeAirport: "CDG",
                                                     startingCash: .dollars(100_000_000))) == .applied)
        let rival = try #require(startup.state.airlines.values.first { $0.kind == .ai })
        #expect(ConfigureAirportFacilitiesCommand(airline: rival.id, airport: "CDG", facilities: .init(hangar: 1))
            .validate(state: startup.state, catalog: catalog) == nil)
    }

    @Test func aHangarWhereTheAircraftFliesShortensItsCheck() throws {
        let (catalog, engine, airline, aircraftID, _) = try FlightOpsTests.operating()
        let fleet = catalog.tuning.fleet
        let facilities = catalog.tuning.airportServices
        var worn = engine.state
        worn.aircraft[aircraftID]?.condition = fleet.maintenanceConditionThreshold + fleet.dailyConditionDecay / 2
        func check(hangar: Int, at airport: AirportCode) -> (days: Int64, cost: Money) {
            var state = worn
            if hangar > 0 { state.airlines[airline]?.airportFacilities = [airport: .init(hangar: hangar)] }
            let before = state.ledger.balance(of: airline)
            FleetSystem().update(state: &state, context: context(state, catalog))
            guard case .inMaintenance(let until) = state.aircraft[aircraftID]!.status else {
                Issue.record("no check started"); return (0, .zero)
            }
            return ((until - state.clock.now).minutes / GameCalendar.minutesPerDay, before - state.ledger.balance(of: airline))
        }
        let none = check(hangar: 0, at: "ARN")
        #expect(none.days == Int64(fleet.maintenanceCheckDays))
        // Either end of the route counts.
        let line = check(hangar: 1, at: "LHR")
        #expect(line.days == Int64(facilities.hangarCheckDays[0]))
        #expect(line.cost == Money(rounding: none.cost.asDouble * facilities.hangarCheckCostFactor[0]))
        let heavy = check(hangar: 2, at: "ARN")
        #expect(heavy.days == Int64(facilities.hangarCheckDays[1]))
        #expect(heavy.cost == Money(rounding: none.cost.asDouble * facilities.hangarCheckCostFactor[1]))
        // A hangar elsewhere does nothing for it.
        #expect(check(hangar: 2, at: "CDG").days == Int64(fleet.maintenanceCheckDays))
    }

    @Test func anAircraftDueForACheckIsNotScheduledAndOneLeavingTheHangarIs() throws {
        let (catalog, engine, _, aircraftID, routeID) = try FlightOpsTests.operating()
        let fleet = catalog.tuning.fleet
        func scheduled(_ edit: (inout GameState) -> Void) -> Int {
            var state = engine.state
            state.flights = [:]
            edit(&state)
            FlightSchedulingSystem().update(state: &state, context: context(state, catalog))
            return state.flights.values.filter { $0.aircraft == aircraftID }.count
        }
        #expect(scheduled { _ in } > 0)
        // Today's wear will send it for a check: no legs that could only expire.
        #expect(scheduled {
            $0.aircraft[aircraftID]?.condition = fleet.maintenanceConditionThreshold + fleet.dailyConditionDecay / 2
        } == 0)
        // Its check ends this morning: it flies today.
        #expect(scheduled { $0.aircraft[aircraftID]?.status = .inMaintenance(until: $0.clock.now) } > 0)
        #expect(scheduled { $0.aircraft[aircraftID]?.status = .inMaintenance(until: $0.clock.now + .days(1)) } == 0)

        // Run for real: the check starts with nothing on the board to cancel.
        var state = engine.state
        state.aircraft[aircraftID]?.condition = fleet.maintenanceConditionThreshold + fleet.dailyConditionDecay / 2
        let running = SimulationEngine(state: state, systems: GamePipeline.standard().filter { $0.id != "worldEvents" },
                                       catalog: catalog)
        running.advance(ticks: Fixtures.ticksPerDay * 2)
        #expect(running.state.eventLog.recent.contains { if case .maintenanceStarted = $0.kind { true } else { false } })
        #expect(running.state.routes[routeID]!.stats.flightsCancelled == 0)
    }

    @Test func aCrewBaseStretchesTheDayAndCheapensCrews() throws {
        let (catalog, engine, airline, aircraftID, routeID) = try FlightOpsTests.operating(trips: 6)
        let tuning = catalog.tuning.airportServices
        let ops = catalog.tuning.ops
        func firstDeparture(_ state: GameState) -> (minute: Int64, legs: Int) {
            var state = state
            state.flights = [:]
            FlightSchedulingSystem().update(state: &state, context: context(state, catalog))
            let legs = state.flights.values.filter { $0.aircraft == aircraftID }
            return (legs.map(\.scheduledDeparture.minuteOfDay).min() ?? -1, legs.count)
        }
        let plain = firstDeparture(engine.state)
        #expect(plain.minute == ops.operatingDayStartMinute)
        var based = engine.state
        based.airlines[airline]?.airportFacilities = ["LHR": .init(crewBase: 1)]
        let route = try #require(based.routes[routeID])
        #expect(based.hasCrewBase(on: route))
        let stretched = firstDeparture(based)
        #expect(stretched.minute == ops.operatingDayStartMinute - tuning.crewBaseEarlierStartMinutes)
        let spec = try #require(catalog.aircraftType(based.aircraft[aircraftID]!.typeCode))
        let capacity = FlightSchedulingSystem.roundTripsPerAircraftPerDay(
            distanceKm: route.distanceKm, spec: spec, ops: ops,
            operatingMinutes: ops.operatingDayMinutes + tuning.crewBaseExtraMinutes)
        #expect(stretched.legs == 2 * min(6, capacity))
        #expect(stretched.legs >= plain.legs)
        #expect(based.crewCostFactor(on: route, catalog: catalog) == tuning.crewBaseCrewCostFactor)
        #expect(engine.state.crewCostFactor(on: route, catalog: catalog) == 1)
        // Somewhere in the catalogue's range the longer day fits a rotation more.
        #expect((300...4_000).contains { distance in
            FlightSchedulingSystem.roundTripsPerAircraftPerDay(distanceKm: distance, spec: spec, ops: ops,
                operatingMinutes: ops.operatingDayMinutes + tuning.crewBaseExtraMinutes)
                > FlightSchedulingSystem.roundTripsPerAircraftPerDay(distanceKm: distance, spec: spec, ops: ops)
        })
    }

    @Test func efficientTurnaroundsArePlannedNotJustFlown() throws {
        let (catalog, engine, airline, aircraftID, _) = try FlightOpsTests.operating(trips: 6)
        let spec = try #require(catalog.aircraftType(engine.state.aircraft[aircraftID]!.typeCode))
        func legGap(_ state: GameState) -> Int64 {
            var state = state
            state.flights = [:]
            FlightSchedulingSystem().update(state: &state, context: context(state, catalog))
            let legs = state.flights.values.filter { $0.aircraft == aircraftID }
                .sorted { $0.scheduledDeparture < $1.scheduledDeparture }
            return (legs[1].scheduledDeparture - legs[0].scheduledDeparture).minutes - legs[0].flightMinutes
        }
        #expect(legGap(engine.state) == Int64(spec.turnaroundMinutes))
        var programme = engine.state
        programme.progression.completedPrograms.append(CapabilityCode.efficientTurnarounds.rawValue)
        let faster = programme.turnaroundMinutes(spec: spec, airline: airline)
        #expect(faster < Int64(spec.turnaroundMinutes))
        #expect(legGap(programme) == faster)
    }

    @Test func hubStatusIsEarnedRecordedAndKept() throws {
        let (catalog, startup, airline) = try FleetFixtures.catalogAndEngine(systems: [FacilityConstructionSystem()])
        let engine = inEra(.regional, startup)
        engine.advance(ticks: Fixtures.ticksPerDay)
        #expect(engine.state.airlines[airline]?.hubStatuses == ["ARN": .base])
        #expect(engine.state.hubStatusProgress(airport: "ARN").next == .mainBase)

        // A second base: three aircraft flying to LHR and a building there.
        #expect(engine.applyNow(OpenRouteCommand(airline: airline, origin: "ARN", destination: "LHR",
                                                 dailyRoundTrips: 6, ticketPrice: .dollars(129))) == .applied)
        let route = try #require(engine.state.routes(of: airline).first).id
        for _ in 0..<3 {
            #expect(engine.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180", ageYears: 3)) == .applied)
            let aircraft = try #require(engine.state.fleet(of: airline).first { $0.assignedRoute == nil })
            #expect(engine.applyNow(AssignAircraftToRouteCommand(airline: airline, route: route, aircraftID: aircraft.id)) == .applied)
        }
        #expect(engine.state.hubStatusProgress(airport: "LHR").requirements.map(\.isMet) == [true, false])
        #expect(engine.applyNow(ConfigureAirportFacilitiesCommand(airline: airline, airport: "LHR",
                                                                  facilities: .init(groundServices: 1))) == .applied)
        // And ARN becomes the main base with a hangar and a crew base.
        #expect(engine.applyNow(ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN",
                                                                  facilities: .init(hangar: 1, crewBase: 1))) == .applied)
        engine.advance(ticks: Fixtures.ticksPerDay * 31)
        let owner = try #require(engine.state.airlines[airline])
        #expect(owner.hubStatus(at: "LHR") == .base)
        #expect(owner.hubStatus(at: "ARN") == .mainBase)
        let raised = engine.state.eventLog.recent.compactMap { event -> AirportCode? in
            if case .hubStatusRaised(_, let airport, _) = event.kind { return airport } else { return nil }
        }
        #expect(raised.sorted() == ["ARN", "LHR"])
        #expect(engine.state.progression.record.contains { $0.kind == .hubStatus("LHR", .base) })
        let story = engine.state.hubTimeline(airport: "ARN").map(\.kind)
        #expect(story.first == .founded)
        #expect(story.contains(.status))

        // Earned is kept: the aircraft leave, the status stays.
        var state = engine.state
        state.routes[route]?.assignedAircraft = []
        let after = SimulationEngine(state: state, systems: engine.systems, catalog: catalog)
        after.advance(ticks: Fixtures.ticksPerDay)
        #expect(after.state.airlines[airline]?.hubStatus(at: "LHR") == .base)
    }

    @Test func hubOffersFollowTheConstruction() throws {
        let (catalog, startup, airline) = try FleetFixtures.catalogAndEngine(systems: [FacilityConstructionSystem()])
        let engine = inEra(.regional, startup)
        let offer = try #require(engine.state.hubUpgradeOffers(airport: "ARN", catalog: catalog).first { $0.kind == .hangar })
        let next = try #require(offer.next)
        #expect(next.buildDays == catalog.tuning.airportServices.hangarBuildDays[0])
        #expect(offer.canUpgrade)
        #expect(engine.applyNow(ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN",
                                                                  facilities: .init(hangar: 1))) == .applied)
        engine.advance(ticks: Fixtures.ticksPerDay * 10)
        let building = try #require(engine.state.hubUpgradeOffers(airport: "ARN", catalog: catalog).first { $0.kind == .hangar })
        let construction = try #require(building.construction)
        #expect(building.next == nil && building.level == 0)
        #expect(construction.level == 1)
        #expect(construction.daysLeft == 20)
        #expect(construction.stage == HubConstructionStage(progress: construction.progress))
        #expect(construction.progress > 0.3 && construction.progress < 0.36)
        engine.advance(ticks: Fixtures.ticksPerDay * 20)
        let open = try #require(engine.state.hubUpgradeOffers(airport: "ARN", catalog: catalog).first { $0.kind == .hangar })
        #expect(open.level == 1 && open.construction == nil && open.next?.level == 2)
    }

    @Test func aV14SaveOpens() throws {
        let (_, engine, airline) = try FleetFixtures.catalogAndEngine()
        var envelope = try #require(JSONSerialization.jsonObject(with: JSONSaveCodec().encode(engine.state)) as? [String: Any])
        envelope["formatVersion"] = 14
        let restored = try JSONSaveCodec().decode(JSONSerialization.data(withJSONObject: envelope))
        #expect(restored.airlines[airline]?.facilities(at: "ARN") == AirportFacilities())
        #expect(restored.clock == engine.state.clock)
    }

    @Test func savesAndContentFromBeforeTheHangarDecode() throws {
        let facilities = try JSONDecoder().decode(AirportFacilities.self,
                                                  from: Data(#"{"lounge":1,"groundServices":2}"#.utf8))
        #expect(facilities == AirportFacilities(lounge: 1, groundServices: 2))
        let tuning = try JSONDecoder().decode(AirportFacilityTuning.self, from: Data("""
            {"loungeInstallation":{"cents":15000000},"groundInstallation":{"cents":10000000},
             "loungeMonthly":{"cents":1500000},"groundMonthly":{"cents":1000000},
             "loungeComfortPerLevel":0.04,"groundRiskReductionPerLevel":0.1}
            """.utf8))
        #expect(tuning.loungeInstallation == .dollars(150_000))
        #expect(tuning.hangarInstallation == AirportFacilityTuning.standard.hangarInstallation)
        #expect(tuning.isValid)
        let (_, engine, airline) = try FleetFixtures.catalogAndEngine()
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.state.airlines[airline]!)) as? [String: Any])
        json.removeValue(forKey: "facilityConstructions"); json.removeValue(forKey: "hubStatuses")
        let restored = try JSONDecoder().decode(Airline.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.facilityConstructions == nil)
        #expect(restored.hubStatus(at: "ARN") == .base)
        #expect(restored.hubStatus(at: "LHR") == .station)
    }
}
