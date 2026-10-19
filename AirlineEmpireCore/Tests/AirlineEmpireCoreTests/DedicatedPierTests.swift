import Foundation
import Testing
@testable import AirlineEmpireCore

/// Hub Phase D, the dedicated pier (docs/HUB_PROGRESSION_PLAN.md §4,
/// building #5): slots held for the player beyond the shared pool, a quicker
/// turnaround the scheduler plans, built over game days once the National
/// era and Hub status are reached.
@Suite("Dedicated pier")
struct DedicatedPierTests {
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

    /// The player in the National era with a hangar, a crew base and a
    /// transfer centre open at home, so ARN is its Hub (Phase E).
    private func hub(_ engine: SimulationEngine, airline: AirlineID) -> SimulationEngine {
        var state = engine.state
        state.progression.era = .national
        state.airlines[airline]?.airportFacilities = ["ARN": AirportFacilities(hangar: 1, crewBase: 1, transferCentre: 1)]
        return SimulationEngine(state: state, systems: engine.systems, catalog: engine.catalog)
    }

    // MARK: Ordering it

    @Test("A pier waits for the National era and Hub status, then costs $30M and 90 days")
    func orderingAPier() throws {
        let (catalog, startup, airline) = try FleetFixtures.catalogAndEngine(systems: [FacilityConstructionSystem()])
        let tuning = catalog.tuning.airportServices
        let first = ConfigureAirportFacilitiesCommand(airline: airline, airport: "ARN",
                                                      facilities: .init(pier: 1))
        #expect(first.validate(state: startup.state, catalog: catalog)?.code == "airport.eraLocked")
        let national = inEra(.national, startup)
        let status = first.validate(state: national.state, catalog: catalog)
        #expect(status?.code == "airport.statusLocked")
        #expect(status?.message.contains("Hub status") == true)
        // Rivals are established carriers, exempt as with the era.
        #expect(national.applyNow(FoundAirlineCommand(airlineName: "Rival", kind: .ai, homeAirport: "CDG",
                                                      startingCash: .dollars(100_000_000))) == .applied)
        let rival = try #require(national.state.airlines.values.first { $0.kind == .ai }).id
        #expect(ConfigureAirportFacilitiesCommand(airline: rival, airport: "CDG", facilities: .init(pier: 1))
            .validate(state: national.state, catalog: catalog) == nil)

        let based = hub(national, airline: airline)
        let cash = based.state.ledger.balance(of: airline)
        let ordered = based.state.clock.now
        #expect(based.applyNow(ConfigureAirportFacilitiesCommand(
            airline: airline, airport: "ARN", facilities: .init(hangar: 1, crewBase: 1, pier: 1, transferCentre: 1))) == .applied)
        let build = try #require(based.state.airlines[airline]?.construction(at: "ARN", of: .pier))
        #expect(build.cost == .dollars(30_000_000))
        #expect(build.cost == tuning.pierInstallation[0])
        #expect(based.state.ledger.balance(of: airline) == cash - build.cost)
        #expect(build.completesAt.dayIndex == ordered.dayIndex + 90)
        #expect(build.completesAt.minuteOfDay == 0)

        // Opens at the start of its ninetieth day.
        based.advance(ticks: Fixtures.ticksPerDay * 90 - 1)
        #expect(based.state.airlines[airline]?.facilities(at: "ARN").pier == 0)
        based.advance(ticks: 1)
        #expect(based.state.airlines[airline]?.facilities(at: "ARN").pier == 1)
        #expect(based.state.eventLog.recent.contains {
            $0.kind == .facilityOpened(airline: airline, airport: "ARN", service: .pier, level: 1)
        })
        #expect(AirportFacilities(pier: 1).monthlyCost(tuning: tuning) == .dollars(250_000))
        #expect(AirportFacilities(pier: 2).monthlyCost(tuning: tuning) == .dollars(350_000))

        // The flagship level on top: $45M and 120 days.
        #expect(based.applyNow(ConfigureAirportFacilitiesCommand(
            airline: airline, airport: "ARN", facilities: .init(hangar: 1, crewBase: 1, pier: 2, transferCentre: 1))) == .applied)
        let flagship = try #require(based.state.airlines[airline]?.construction(at: "ARN", of: .pier))
        #expect(flagship.cost == .dollars(45_000_000))
        #expect(flagship.completesAt.dayIndex - based.state.clock.now.dayIndex == 120)
    }

    @Test("The hub's pier card is locked by era, then by status, then quotes the plan's figures")
    func thePierOfferFollowsItsGates() throws {
        let (catalog, startup, airline) = try FleetFixtures.catalogAndEngine(systems: [FacilityConstructionSystem()])
        let regional = inEra(.regional, startup)
        let locked = try #require(regional.state.hubUpgradeOffers(airport: "ARN", catalog: catalog)
            .first { $0.kind == .pier })
        #expect(locked.lockedUntil == .national)
        #expect(!locked.canUpgrade)
        let waiting = try #require(inEra(.national, startup).state.hubUpgradeOffers(airport: "ARN", catalog: catalog)
            .first { $0.kind == .pier })
        #expect(waiting.lockedUntil == nil)
        #expect(waiting.blocked?.contains("Hub status") == true)

        let offer = try #require(hub(startup, airline: airline).state
            .hubUpgradeOffers(airport: "ARN", catalog: catalog).first { $0.kind == .pier })
        #expect(offer.canUpgrade)
        #expect(offer.buildingName == "Shared pier")
        let next = try #require(offer.next)
        #expect(next.buildingName == "Your own pier")
        #expect(next.buildDays == 90)
        #expect(next.installationCents == Money.dollars(30_000_000).cents)
        #expect(next.monthlyCents == Money.dollars(250_000).cents)
        #expect(next.payoff?.contains("4 movements") == true)
    }

    // MARK: What it does

    @Test("A pier holds slots for its airline beyond the shared pool, and only for it")
    func aPierHoldsSlotsBeyondThePool() throws {
        let (catalog, engine, airline) = try FleetFixtures.catalogAndEngine(systems: [])
        #expect(engine.applyNow(FoundAirlineCommand(airlineName: "Rival", kind: .ai, homeAirport: "CDG",
                                                    startingCash: .dollars(100_000_000))) == .applied)
        let rival = try #require(engine.state.airlines.values.first { $0.kind == .ai }).id
        let tuning = catalog.tuning.airportServices
        let capacity = try #require(catalog.airport("ARN")).slotCapacityPerDay
        var state = engine.state
        // The rival holds the whole shared pool at ARN.
        #expect(state.world.allocateSlots(airline: rival, airport: "ARN", count: capacity,
                                          capacityPerDay: capacity) == nil)
        let open = OpenRouteCommand(airline: airline, origin: "ARN", destination: "LHR",
                                    dailyRoundTrips: 2, ticketPrice: .dollars(129))
        #expect(open.validate(state: state, catalog: catalog)?.code == "route.noSlots")
        #expect(state.slotsAvailable(to: airline, at: "ARN", catalog: catalog) == 0)

        // Its own pier holds four movements a day for the player.
        state.airlines[airline]?.airportFacilities = ["ARN": AirportFacilities(pier: 1)]
        let pier = SimulationEngine(state: state, systems: [], catalog: catalog)
        #expect(pier.state.reservedSlots(for: airline, at: "ARN", tuning: tuning) == 4)
        #expect(pier.state.slotsAvailable(to: airline, at: "ARN", catalog: catalog) == 4)
        #expect(pier.state.slotsAvailable(to: rival, at: "ARN", catalog: catalog) == 0,
                "the rival cannot use the player's gates")
        #expect(pier.applyNow(open) == .applied)
        let route = try #require(pier.state.routes(of: airline).first).id
        #expect(pier.state.world.slotsHeld(by: airline, at: "ARN") == 4)
        #expect(pier.state.sharedSlotsUsed(at: "ARN", tuning: tuning) == capacity)
        #expect(pier.state.slotsAvailable(to: airline, at: "ARN", catalog: catalog) == 0)
        #expect(SetRouteFrequencyCommand(airline: airline, route: route, dailyRoundTrips: 3)
            .validate(state: pier.state, catalog: catalog)?.code == "route.noSlots")

        // The flagship pier holds eight.
        var bigger = pier.state
        bigger.airlines[airline]?.airportFacilities = ["ARN": AirportFacilities(pier: 2)]
        let flagship = SimulationEngine(state: bigger, systems: [], catalog: catalog)
        #expect(flagship.applyNow(SetRouteFrequencyCommand(airline: airline, route: route,
                                                           dailyRoundTrips: 4)) == .applied)
        #expect(flagship.state.world.slotsHeld(by: airline, at: "ARN") == 8)
        #expect(SetRouteFrequencyCommand(airline: airline, route: route, dailyRoundTrips: 5)
            .validate(state: flagship.state, catalog: catalog)?.code == "route.noSlots")
        // Without a pier anywhere, availability is the pool's free capacity.
        #expect(engine.state.slotsAvailable(to: airline, at: "ARN", catalog: catalog)
                == capacity - engine.state.world.slotsUsed(at: "ARN"))
    }

    @Test("A pier turns its airline's aircraft faster, and the scheduler and flight operations use it")
    func aPierShortensTheTurnaround() throws {
        let (catalog, engine, airline, aircraftID, _) = try FlightOpsTests.operating(trips: 6)
        let tuning = catalog.tuning.airportServices
        let spec = try #require(catalog.aircraftType(engine.state.aircraft[aircraftID]!.typeCode))
        var state = engine.state
        state.airlines[airline]?.airportFacilities = ["ARN": AirportFacilities(pier: 2)]
        let plain = state.turnaroundMinutes(spec: spec, airline: airline)
        let atPier = state.turnaroundMinutes(spec: spec, airline: airline, at: "ARN", tuning: tuning)
        #expect(atPier == Int64((Double(plain) * tuning.pierTurnaroundFactor[1]).rounded()))
        #expect(atPier < plain)
        #expect(state.turnaroundMinutes(spec: spec, airline: airline, at: "LHR", tuning: tuning) == plain)

        // The scheduler plans the pier's turn at its end of the route: out of
        // ARN, the plain turn at LHR, back, the pier's turn at ARN.
        var planned = state
        planned.flights = [:]
        FlightSchedulingSystem().update(state: &planned, context: context(planned, catalog))
        let legs = planned.flights.values.filter { $0.aircraft == aircraftID }
            .sorted { $0.scheduledDeparture < $1.scheduledDeparture }
        try #require(legs.count >= 3)
        #expect(legs[0].from == "ARN")
        #expect((legs[1].scheduledDeparture - legs[0].scheduledDeparture).minutes - legs[0].flightMinutes == plain)
        #expect((legs[2].scheduledDeparture - legs[1].scheduledDeparture).minutes - legs[1].flightMinutes == atPier)

        // Somewhere in the catalogue's range the quicker turn fits a rotation more.
        let ops = catalog.tuning.ops
        #expect((300...4_000).contains { distance in
            FlightSchedulingSystem.roundTripsPerAircraftPerDay(
                distanceKm: distance, spec: spec, ops: ops,
                turnaroundMinutes: plain, returnTurnaroundMinutes: atPier)
                > FlightSchedulingSystem.roundTripsPerAircraftPerDay(distanceKm: distance, spec: spec, ops: ops)
        })

        // Flight operations hold a landing at ARN for the pier's turn.
        let running = SimulationEngine(state: state,
                                       systems: GamePipeline.standard().filter { $0.id != "worldEvents" },
                                       catalog: catalog)
        var seen: Set<FlightID> = []
        var turns: [Int64] = []
        for _ in 0..<(Fixtures.ticksPerDay * 2) {
            running.advance(ticks: 1)
            for flight in running.state.flights.values where flight.to == "ARN" && !seen.contains(flight.id) {
                guard case .turnaround(let until) = flight.phase else { continue }
                seen.insert(flight.id)
                turns.append((until - running.state.clock.now).minutes)
            }
        }
        #expect(!turns.isEmpty)
        #expect(turns.allSatisfy { $0 == atPier })
    }

    // MARK: Saves

    @Test("A pier under construction survives a save, and older saves and content decode without one")
    func savesAndContentFromBeforeThePier() throws {
        let facilities = try JSONDecoder().decode(
            AirportFacilities.self, from: Data(#"{"lounge":1,"groundServices":1,"hangar":2,"crewBase":1}"#.utf8))
        #expect(facilities == AirportFacilities(lounge: 1, groundServices: 1, hangar: 2, crewBase: 1))
        #expect(facilities.pier == 0)
        let tuning = try JSONDecoder().decode(
            AirportFacilityTuning.self, from: Data(#"{"loungeInstallation":{"cents":75000000}}"#.utf8))
        #expect(tuning.pierInstallation == AirportFacilityTuning.standard.pierInstallation)
        #expect(tuning.pierReservedSlots == [4, 8])
        #expect(tuning.isValid)
        let bundled = try ContentCatalog.loadBundled().tuning.airportServices
        #expect(bundled.pierInstallation == [.dollars(30_000_000), .dollars(45_000_000)])
        #expect(bundled.pierMonthly == [.dollars(250_000), .dollars(350_000)])
        #expect(bundled.pierBuildDays == [90, 120])

        let systems: [any SimulationSystem] = [FacilityConstructionSystem()]
        let (catalog, startup, airline) = try FleetFixtures.catalogAndEngine(systems: systems)
        let source = hub(startup, airline: airline)
        #expect(source.applyNow(ConfigureAirportFacilitiesCommand(
            airline: airline, airport: "ARN", facilities: .init(hangar: 1, crewBase: 1, pier: 1, transferCentre: 1))) == .applied)
        source.advance(ticks: Fixtures.ticksPerDay * 40)
        let restored = SimulationEngine(state: try JSONSaveCodec().decode(JSONSaveCodec().encode(source.state)),
                                        systems: systems, catalog: catalog)
        #expect(restored.state == source.state)
        source.advance(ticks: Fixtures.ticksPerDay * 50)
        restored.advance(ticks: Fixtures.ticksPerDay * 50)
        #expect(restored.state == source.state)
        #expect(restored.state.airlines[airline]?.facilities(at: "ARN").pier == 1)
    }

    // MARK: Where it stands

    @Test("The pier site is the airport's westmost pier, its bridges with it; a field without piers gets a walkway")
    func thePierSite() {
        for spec in HubLayoutTests.allAirports {
            let layout = HubLayout.make(airport: spec)
            guard let site = layout.site(.pier) else {
                Issue.record("no pier site at \(spec.code)"); continue
            }
            #expect(site.elevation == 0)
            if let west = layout.pieces(.pier).map(\.groundBounds).min(by: { $0.minX < $1.minX }) {
                #expect(site.footprint == west, "\(spec.code)")
                let f = site.footprint
                #expect(layout.stands.contains { stand in
                    stand.hasBridge && stand.bridgeRoot.x >= f.minX - 1 && stand.bridgeRoot.x <= f.maxX + 1
                        && stand.bridgeRoot.z >= f.minZ - 1 && stand.bridgeRoot.z <= f.maxZ + 1
                }, "no bridge on the pier at \(spec.code)")
            } else {
                #expect(site.footprint.maxZ == 0 && site.footprint.minZ >= -6, "\(spec.code)")
                #expect(site.footprint.minX >= layout.terminal.minX
                        && site.footprint.maxX <= layout.terminal.maxX, "\(spec.code)")
            }
        }
    }
}
