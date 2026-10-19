import Foundation
import Testing
@testable import AirlineEmpireCore

/// A hub with three spokes in clean geometry: Westby and Eastham 572 km
/// either side of Hubton on one parallel (a straight line through the hub),
/// Northport 667 km north. Equal cities, flat seasons, no world events.
enum HubFixtures {
    static func airport(_ code: String, _ city: String, latitude: Double, longitude: Double,
                        population: Int = 4_000) -> AirportSpec {
        AirportSpec(
            code: AirportCode(code), name: "\(city) International", city: city, country: "Testland",
            region: .europe, coordinate: Coordinate(latitude: latitude, longitude: longitude),
            utcOffsetMinutes: 60, runwayClass: .large, slotCapacityPerDay: 400,
            terminalCapacityPerDay: 60_000, movementFee: Money.dollars(1_400),
            passengerFee: Money.dollars(16),
            demographics: Demographics(populationThousands: population, businessIndex: 0.6,
                                       leisureIndex: 0.6, tourismIndex: 0.5, cargoIndex: 0.5),
            seasonality: "flat", weatherRisk: .low)
    }

    static let airports = [
        airport("HUB", "Hubton", latitude: 50, longitude: 10),
        airport("WST", "Westby", latitude: 50, longitude: 2),
        airport("EST", "Eastham", latitude: 50, longitude: 18),
        airport("NTH", "Northport", latitude: 56, longitude: 10),
    ]

    static func catalog(airports: [AirportSpec] = airports,
                        facilities: AirportFacilityTuning? = nil) throws -> ContentCatalog {
        let real = try ContentCatalog.loadBundled()
        let t = real.tuning
        let tuning = Tuning(minRouteDistanceKm: t.minRouteDistanceKm, fleet: t.fleet, ops: t.ops,
                            demand: t.demand, finance: t.finance, world: t.world,
                            reputation: t.reputation, ai: t.ai, events: t.events,
                            progression: t.progression, aircraftConfiguration: t.cabin,
                            airportFacilities: facilities ?? t.airportServices)
        return try ContentCatalog(
            version: "hub", airports: airports, seasonality: [TestAirports.flatProfile],
            aircraftTypes: real.orderedAircraftTypeCodes.compactMap { real.aircraftTypes[$0] },
            tuning: tuning)
    }

    static let pipeline: [any SimulationSystem] = GamePipeline.standard().filter { $0.id != "worldEvents" }

    /// A player at Hubton in the National era flying one narrowbody to each
    /// spoke, `trips` round trips a day at `fare`, with its transfer centre
    /// open when `hub` is set.
    static func network(spokes: [String] = ["WST", "EST"], trips: Int = 3, fare: Int64 = 99,
                        hub: Bool = true, catalog: ContentCatalog? = nil,
                        cash: Money = .dollars(400_000_000),
                        systems: [any SimulationSystem] = pipeline) throws
        -> (SimulationEngine, AirlineID, [RouteID]) {
        let catalog = try catalog ?? Self.catalog()
        let founder = SimulationEngine(state: Fixtures.newState(), systems: systems, catalog: catalog)
        #expect(founder.applyNow(FoundAirlineCommand(airlineName: "Hub Air", kind: .player, homeAirport: "HUB",
                                                     startingCash: cash)) == .applied)
        let airline = try #require(founder.state.airlines.values.first { $0.kind == .player }).id
        var routes: [RouteID] = []
        for spoke in spokes {
            #expect(founder.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180", ageYears: 2)) == .applied)
            let aircraft = try #require(founder.state.fleet(of: airline).first { $0.assignedRoute == nil }).id
            #expect(founder.applyNow(OpenRouteCommand(airline: airline, origin: "HUB", destination: AirportCode(spoke),
                                                      dailyRoundTrips: trips, ticketPrice: .dollars(fare))) == .applied)
            let route = try #require(founder.state.routes(of: airline).first { $0.servesAirport(AirportCode(spoke)) }).id
            #expect(founder.applyNow(AssignAircraftToRouteCommand(airline: airline, route: route,
                                                                  aircraftID: aircraft)) == .applied)
            routes.append(route)
        }
        var state = founder.state
        state.progression.era = .national
        if hub { state.airlines[airline]?.airportFacilities = ["HUB": AirportFacilities(transferCentre: 1)] }
        return (SimulationEngine(state: state, systems: systems, catalog: catalog), airline, routes)
    }

    /// The A→C pool the demand engine computes at this moment.
    static func pool(_ a: AirportCode, _ c: AirportCode, _ state: GameState, _ catalog: ContentCatalog) -> Double {
        let boost = catalog.airport(c).map { state.world.tourismBoost(for: $0.region, at: state.clock.now) } ?? 0
        return DemandSystem.demandPool(from: a, to: c, date: state.currentDate,
                                       economicIndex: state.world.economicIndex,
                                       tourismBoost: boost, catalog: catalog).total
    }
}

@Suite("Transfer centre and connecting passengers")
struct TransferCentreTests {
    private func inEra(_ era: Era, _ engine: SimulationEngine) -> SimulationEngine {
        var state = engine.state
        state.progression.era = era
        return SimulationEngine(state: state, systems: engine.systems, catalog: engine.catalog)
    }

    // MARK: Designation

    @Test func buildingTheTransferCentreMakesAMainBaseAHub() throws {
        let catalog = try HubFixtures.catalog()
        let systems: [any SimulationSystem] = [FacilityConstructionSystem(), EconomySystem()]
        let (founded, airline, routes) = try HubFixtures.network(spokes: [], hub: false, catalog: catalog,
                                                                 systems: systems)
        #expect(routes.isEmpty)
        // Regional first: the transfer centre waits for the National era.
        let regional = inEra(.regional, founded)
        regional.advance(ticks: Fixtures.ticksPerDay)
        let order = ConfigureAirportFacilitiesCommand(airline: airline, airport: "HUB",
                                                      facilities: .init(hangar: 1, crewBase: 1, transferCentre: 1))
        let refusal = order.validate(state: regional.state, catalog: catalog)
        #expect(refusal?.code == "airport.eraLocked")
        #expect(refusal?.message.contains("National") == true)
        let locked = try #require(regional.state.hubUpgradeOffers(airport: "HUB", catalog: catalog)
            .first { $0.kind == .transferCentre })
        #expect(locked.lockedUntil == .national && !locked.canUpgrade)
        // Free play's era ceiling refuses it at the command boundary too.
        #expect(ExpansionAccess.rejection(for: order, state: regional.state, catalog: catalog,
                                          ceiling: .regional)?.code == "access.proRequired")
        #expect(ExpansionAccess.rejection(for: ConfigureAirportFacilitiesCommand(
            airline: airline, airport: "HUB", facilities: .init(hangar: 1)), state: regional.state,
            catalog: catalog, ceiling: .regional) == nil)

        // The main base: a hangar and a crew base.
        #expect(regional.applyNow(ConfigureAirportFacilitiesCommand(airline: airline, airport: "HUB",
                                                                    facilities: .init(hangar: 1, crewBase: 1))) == .applied)
        regional.advance(ticks: Fixtures.ticksPerDay * 31)
        #expect(regional.state.airlines[airline]?.hubStatus(at: "HUB") == .mainBase)
        let towards = regional.state.hubStatusProgress(airport: "HUB")
        #expect(towards.next == .hub)
        #expect(towards.requirements.map(\.title) == ["Main base status", "Transfer centre open"])
        #expect(towards.requirements.map(\.isMet) == [true, false])
        let start = try #require(SessionCheckpoint(regional.state))

        // Designation: $25M, 60 days, then a hub.
        let national = inEra(.national, regional)
        let cash = national.state.ledger.balance(of: airline)
        #expect(national.applyNow(order) == .applied)
        let tuning = catalog.tuning.airportServices
        #expect(national.state.ledger.balance(of: airline) == cash - tuning.transferCentreInstallation)
        #expect(tuning.transferCentreInstallation == .dollars(25_000_000))
        #expect(tuning.transferCentreMonthly == .dollars(200_000))
        let build = try #require(national.state.airlines[airline]?.construction(at: "HUB", of: .transferCentre))
        #expect(build.completesAt.dayIndex - national.state.clock.now.dayIndex == Int64(tuning.transferCentreBuildDays))
        let works = try #require(national.state.hubUpgradeOffers(airport: "HUB", catalog: catalog)
            .first { $0.kind == .transferCentre }?.construction)
        #expect(works.buildingName == "Transfer centre")
        national.advance(ticks: Fixtures.ticksPerDay * (tuning.transferCentreBuildDays + 1))

        let owner = try #require(national.state.airlines[airline])
        #expect(owner.facilities(at: "HUB").transferCentre == 1)
        #expect(owner.designatedHubs == ["HUB"])
        #expect(owner.hubStatus(at: "HUB") == .hub)
        #expect(national.state.eventLog.recent.contains {
            $0.kind == .facilityOpened(airline: airline, airport: "HUB", service: .transferCentre, level: 1)
        })
        #expect(national.state.eventLog.recent.contains {
            $0.kind == .hubStatusRaised(airline: airline, airport: "HUB", status: .hub)
        })
        #expect(national.state.progression.record.contains { $0.kind == .hubStatus("HUB", .hub) })
        #expect(national.state.hubTimeline(airport: "HUB").contains { $0.title == "Became a hub" })
        let progress = national.state.hubStatusProgress(airport: "HUB")
        #expect(progress.status == .hub && progress.next == nil)
        // Its upkeep is billed with the station's.
        #expect(owner.facilities(at: "HUB").monthlyCost(tuning: tuning)
                == tuning.hangarMonthly[0] + tuning.crewBaseMonthly + tuning.transferCentreMonthly)
        // The session report's line.
        let end = try #require(SessionCheckpoint(national.state))
        let report = try #require(SessionReport(from: start, to: end))
        #expect(report.statusRises == [HubStatusRise(airport: "HUB", status: .hub)])
    }

    // MARK: The spill term

    @Test func noTransferCentreNoConnections() throws {
        let (engine, airline, routes) = try HubFixtures.network(hub: false)
        engine.advance(ticks: Fixtures.ticksPerDay * 3)
        #expect(routes.allSatisfy { engine.state.routes[$0]?.connectionsToday == nil })
        #expect(engine.state.airlines[airline]?.connectingFlowsToday == nil)
        #expect(engine.state.airlines[airline]?.hubTransfers == nil)
        #expect(DemandSystem.connectingSpill(airline: airline, state: engine.state, catalog: engine.catalog).isEmpty)
        // Nothing of it reaches the save either.
        let payload = String(decoding: try JSONEncoder().encode(engine.state), as: UTF8.self)
        for key in ["connectionsToday", "connectingFlowsToday", "hubTransfers", "transferCentre",
                    "connectingPassengers", "connectingFare"] {
            #expect(!payload.contains("\"\(key)\""), "\(key) in a point-to-point save")
        }
    }

    @Test func aHubConnectsItsSpokes() throws {
        let (engine, airline, routes) = try HubFixtures.network()
        engine.advance(ticks: Fixtures.ticksPerDay * 2)
        let flows = try #require(engine.state.airlines[airline]?.connectingFlowsToday)
        // Both directions of the one pair the hub links.
        #expect(Set(flows.map { "\($0.origin.raw)>\($0.destination.raw)" }) == ["WST>EST", "EST>WST"])
        for flow in flows {
            #expect(flow.hub == "HUB")
            #expect(flow.passengers > 0)
            #expect(flow.connections > 0)
            // The through fare: both legs less the discount.
            let tuning = engine.catalog.tuning.airportServices
            #expect(flow.fare == Money(rounding: Money.dollars(198).asDouble * (1 - tuning.transferThroughFareDiscount)))
            #expect(flow.averageWaitMinutes >= Int(tuning.transferMinimumConnectMinutes))
        }
        // Each leg carries the flows that use it, inside its demand.
        for routeID in routes {
            let route = try #require(engine.state.routes[routeID])
            let load = try #require(route.connectionsToday)
            for outbound in [true, false] {
                let from = outbound ? route.origin : route.destination
                let to = outbound ? route.destination : route.origin
                let using = flows.filter { ($0.origin == from && $0.hub == to) || ($0.hub == from && $0.destination == to) }
                #expect(load.direction(outbound: outbound).booked == using.reduce(0) { $0 + $1.passengers })
                #expect((outbound ? route.demandOutboundToday : route.demandInboundToday)
                        >= load.direction(outbound: outbound).booked)
                #expect(load.direction(outbound: outbound).fare > .zero)
            }
        }
        // The hub's tally counts every traveller once.
        let tally = try #require(engine.state.airlines[airline]?.hubTransfers?["HUB"])
        #expect(tally.thisMonth >= Int64(flows.reduce(0) { $0 + $1.passengers }))
    }

    @Test func connectionsNeedBothLegsAndTheWindow() {
        // Minimum connect time and the longest layover, both inclusive.
        #expect(DemandSystem.timing(arrivals: [0], departures: [20], minimum: 30, maximum: 300).connections == 0)
        let exact = DemandSystem.timing(arrivals: [0], departures: [30], minimum: 30, maximum: 300)
        #expect(exact.connections == 1 && exact.averageWait == 30)
        #expect(DemandSystem.timing(arrivals: [0], departures: [301], minimum: 30, maximum: 300).connections == 0)
        #expect(DemandSystem.timing(arrivals: [0], departures: [300], minimum: 30, maximum: 300).connections == 1)
        // The shortest onward wait counts; two arrivals onto one departure
        // are one itinerary's worth of frequency.
        let shared = DemandSystem.timing(arrivals: [0, 100], departures: [150], minimum: 30, maximum: 300)
        #expect(shared.connections == 1)
        #expect(shared.averageWait == 100)
        let banked = DemandSystem.timing(arrivals: [0, 200, 400], departures: [40, 240, 440, 900],
                                         minimum: 30, maximum: 300)
        #expect(banked.connections == 3 && banked.averageWait == 40)
        // Nothing arrives, or nothing leaves: no connection.
        #expect(DemandSystem.timing(arrivals: [], departures: [40], minimum: 30, maximum: 300).connections == 0)
        #expect(DemandSystem.timing(arrivals: [0], departures: [], minimum: 30, maximum: 300).connections == 0)
    }

    @Test func aLegThatDoesNotFlyConnectsNobody() throws {
        let (engine, airline, routes) = try HubFixtures.network()
        // Eastham's aircraft leaves the route: that leg has no flights.
        var state = engine.state
        let grounded = try #require(state.routes[routes[1]]?.assignedAircraft.first)
        state.routes[routes[1]]?.assignedAircraft = []
        state.aircraft[grounded]?.assignedRoute = nil
        let alone = SimulationEngine(state: state, systems: engine.systems, catalog: engine.catalog)
        alone.advance(ticks: Fixtures.ticksPerDay * 2)
        #expect(alone.state.airlines[airline]?.connectingFlowsToday == nil)
        #expect(alone.state.routes[routes[0]]?.connectionsToday == nil)
    }

    @Test func aWindowNoFlightFitsConnectsNobody() throws {
        // The same network with a minimum connect time longer than any wait
        // the timetable offers.
        let strict = AirportFacilityTuning(transferMinimumConnectMinutes: 200, transferMaximumLayoverMinutes: 220)
        #expect(strict.isValid)
        let (engine, airline, _) = try HubFixtures.network(catalog: HubFixtures.catalog(facilities: strict))
        engine.advance(ticks: Fixtures.ticksPerDay * 2)
        #expect(engine.state.airlines[airline]?.connectingFlowsToday == nil)
    }

    @Test func nobodyConnectsTheLongWayRound() throws {
        // Westby–Northport via Hubton is within the detour limit; with the
        // limit at 1.05 only the straight line through the hub connects.
        let tight = AirportFacilityTuning(transferMaximumDetour: 1.05)
        let (engine, airline, _) = try HubFixtures.network(spokes: ["WST", "EST", "NTH"],
                                                           catalog: HubFixtures.catalog(facilities: tight))
        engine.advance(ticks: Fixtures.ticksPerDay * 2)
        let pairs = Set((engine.state.airlines[airline]?.connectingFlowsToday ?? []).map { "\($0.origin.raw)>\($0.destination.raw)" })
        #expect(pairs == ["WST>EST", "EST>WST"])
        let (loose, looseAirline, _) = try HubFixtures.network(spokes: ["WST", "EST", "NTH"])
        loose.advance(ticks: Fixtures.ticksPerDay * 2)
        let all = Set((loose.state.airlines[looseAirline]?.connectingFlowsToday ?? []).map { $0.origin.raw + ">" + $0.destination.raw })
        #expect(all.isSuperset(of: ["WST>EST", "EST>WST"]))
        #expect(all.contains { $0.contains("NTH") })
    }

    @Test func ownNonstopsAreNotConnected() throws {
        // The player flies Westby–Eastham itself: those travellers take it.
        let (engine, airline, _) = try HubFixtures.network()
        var state = engine.state
        let direct = SimulationEngine(state: state, systems: engine.systems, catalog: engine.catalog)
        #expect(direct.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180", ageYears: 2)) == .applied)
        #expect(direct.applyNow(OpenRouteCommand(airline: airline, origin: "WST", destination: "EST",
                                                 dailyRoundTrips: 2, ticketPrice: .dollars(129))) == .applied)
        state = direct.state
        let route = try #require(state.routes(of: airline).first { $0.sameMarket(origin: "WST", destination: "EST") }).id
        let aircraft = try #require(state.fleet(of: airline).first { $0.assignedRoute == nil }).id
        #expect(direct.applyNow(AssignAircraftToRouteCommand(airline: airline, route: route, aircraftID: aircraft)) == .applied)
        direct.advance(ticks: Fixtures.ticksPerDay * 2)
        #expect(direct.state.airlines[airline]?.connectingFlowsToday == nil)
    }

    // MARK: Conservation

    /// The pools are never exceeded: on every directional city pair, the
    /// nonstops' allocation plus the connections through any hub stays
    /// within the demand engine's pool — with a rival flying a nonstop on
    /// the connected pair, so the residual is real. And the boarding step
    /// never carries more than was granted.
    @Test func demandIsConservedWithConnections() throws {
        let (engine, player, routes) = try HubFixtures.network(spokes: ["WST", "EST", "NTH"])
        #expect(engine.applyNow(FoundAirlineCommand(airlineName: "Rival Air", kind: .ai, homeAirport: "WST",
                                                    startingCash: .dollars(300_000_000))) == .applied)
        let rival = try #require(engine.state.airlines.values.first { $0.kind == .ai }).id
        #expect(engine.applyNow(BuyUsedAircraftCommand(buyer: rival, type: "MR180", ageYears: 2)) == .applied)
        #expect(engine.applyNow(OpenRouteCommand(airline: rival, origin: "WST", destination: "EST",
                                                 dailyRoundTrips: 2, ticketPrice: .dollars(129))) == .applied)
        let rivalRoute = try #require(engine.state.routes(of: rival).first).id
        let rivalAircraft = try #require(engine.state.fleet(of: rival).first).id
        #expect(engine.applyNow(AssignAircraftToRouteCommand(airline: rival, route: rivalRoute,
                                                             aircraftID: rivalAircraft)) == .applied)
        let codes = HubFixtures.airports.map(\.code)
        var granted = 0
        var connected = 0
        for _ in 0..<21 {
            engine.advance(ticks: Fixtures.ticksPerDay)
            let state = engine.state
            let flows = state.airlines[player]?.connectingFlowsToday ?? []
            connected += flows.reduce(0) { $0 + $1.passengers }
            for a in codes {
                for c in codes where c != a {
                    let local = state.routes.values.filter { $0.sameMarket(origin: a, destination: c) }
                        .reduce(0) { $0 + $1.localDemand(outbound: $1.origin == a) }
                    let connecting = flows.filter { $0.origin == a && $0.destination == c }
                        .reduce(0) { $0 + $1.passengers }
                    let pool = HubFixtures.pool(a, c, state, engine.catalog)
                    #expect(Double(local + connecting) <= pool + 1e-6,
                            "\(a.raw)>\(c.raw): \(local) local + \(connecting) connecting > pool \(pool)")
                }
            }
            // The rival's route may close under its own AI: what it had
            // granted was counted while it flew.
            for id in routes + [rivalRoute] {
                guard let r = state.routes[id] else { continue }
                granted += r.demandOutboundToday + r.demandInboundToday
            }
        }
        #expect(connected > 0, "the hub connected nobody")
        let carried = (routes + [rivalRoute]).reduce(Int64(0)) { $0 + (engine.state.routes[$1]?.stats.passengersCarried ?? 0) }
        #expect(carried <= Int64(granted))
        #expect(carried > 0)
    }

    /// Connections only fill seats the locals leave: on no leg does the
    /// day's demand pass its seats because of them.
    @Test func connectionsFillOnlyEmptySeats() throws {
        let (engine, _, routes) = try HubFixtures.network(spokes: ["WST", "EST", "NTH"], trips: 2, fare: 70)
        var booked = 0
        for _ in 0..<7 {
            engine.advance(ticks: Fixtures.ticksPerDay)
            let state = engine.state
            for id in routes {
                let route = try #require(state.routes[id])
                guard let load = route.connectionsToday else { continue }
                // The seats today's flights put on sale each way.
                for outbound in [true, false] where load.direction(outbound: outbound).booked > 0 {
                    let seats = state.flights.values.filter {
                        $0.route == id && $0.kind == .revenue && ($0.from == route.origin) == outbound
                            && $0.scheduledDeparture.dayIndex == state.clock.now.dayIndex
                    }.reduce(0) { total, flight in
                        guard let aircraft = state.aircraft[flight.aircraft],
                              let spec = engine.catalog.aircraftType(aircraft.typeCode) else { return total }
                        return total + aircraft.cabin(for: spec).totalSeats
                    }
                    let demand = outbound ? route.demandOutboundToday : route.demandInboundToday
                    #expect(demand <= seats, "\(id.raw) \(outbound): \(demand) booked on \(seats) seats")
                    booked += load.direction(outbound: outbound).booked
                }
            }
        }
        #expect(booked > 0)
    }

    // MARK: Money

    @Test func connectingTravellersPayTheirShareAndShowSeparately() throws {
        let (engine, airline, routes) = try HubFixtures.network()
        engine.advance(ticks: Fixtures.ticksPerDay * 6)
        let month = routes.compactMap { engine.state.routes[$0]?.economicsThisMonth }
        let connecting = month.reduce(Int64(0)) { $0 + ($1.connectingPassengers ?? 0) }
        let connectingRevenue = month.reduce(Int64(0)) { $0 + ($1.connectingRevenueCents ?? 0) }
        #expect(connecting > 0)
        #expect(connectingRevenue > 0)
        #expect(connectingRevenue < month.reduce(Int64(0)) { $0 + $1.revenueCents })
        #expect(month.allSatisfy { ($0.connectingPassengers ?? 0) <= $0.passengers })
        #expect(engine.state.ledger.recent.contains {
            $0.airline == airline && $0.category == .ticketRevenue && $0.memo?.contains("connecting") == true
        })
        // The read models say so.
        let cards = engine.state.routeCards(for: airline, catalog: engine.catalog)
        #expect(cards.allSatisfy { $0.connectingVia == ["HUB"] })
        #expect(cards.contains { ($0.thisMonthBreakdown.connectingPassengers ?? 0) > 0 })
        let network = engine.state.networkSummary(for: airline)
        #expect(network.monthToDateConnectingPassengers == connecting)
        #expect(network.monthToDateConnectingRevenue == Money(cents: connectingRevenue))
        let finance = try #require(engine.state.financeBreakdown(for: airline, catalog: engine.catalog).connecting)
        #expect(finance.hubs == ["HUB"])
        #expect(finance.travellersThisMonth > 0 && finance.revenueThisMonth == Money(cents: connectingRevenue))
        // A month closes: the tally rolls over with the routes.
        engine.advance(ticks: Fixtures.ticksPerDay * 31)
        let tally = try #require(engine.state.airlines[airline]?.hubTransfers?["HUB"])
        #expect(tally.lastMonth > 0)
        #expect(tally.lifetime >= tally.lastMonth + tally.thisMonth)
    }

    @Test func theHubShowsItsTransferFlows() throws {
        let (engine, airline, _) = try HubFixtures.network(spokes: ["WST", "EST", "NTH"])
        engine.advance(ticks: Fixtures.ticksPerDay * 2)
        func read(_ code: AirportCode) throws -> HubSnapshot {
            let spec = try #require(engine.catalog.airport(code))
            return try #require(engine.state.hubSnapshot(airport: code, catalog: engine.catalog,
                                                         layout: HubLayout.make(airport: spec)))
        }
        let snapshot = try read("HUB")
        let transfers = try #require(snapshot.insights.transfers)
        #expect(transfers.passengersToday == (engine.state.airlines[airline]?.connectingFlowsToday ?? [])
            .reduce(0) { $0 + $1.passengers })
        #expect(transfers.passengersToday > 0)
        #expect(!transfers.flows.isEmpty && transfers.flows.count <= 8)
        #expect(zip(transfers.flows, transfers.flows.dropFirst()).allSatisfy { $0.passengers >= $1.passengers })
        #expect(snapshot.insights.routes.contains { $0.connectingToday > 0 })
        #expect(snapshot.status.status == .base) // a hub building alone: no main base yet
        // A spoke's own snapshot has no transfer section.
        #expect(try read("WST").insights.transfers == nil)
    }

    @Test func theCardQuotesConnectionsBeforeItIsBuilt() throws {
        let (engine, airline, _) = try HubFixtures.network(hub: false)
        engine.advance(ticks: Fixtures.ticksPerDay * 2)
        let offer = try #require(engine.state.hubUpgradeOffers(airport: "HUB", catalog: engine.catalog)
            .first { $0.kind == .transferCentre })
        let payoff = try #require(offer.next?.payoff)
        #expect(payoff.hasPrefix("About "), "\(payoff)")
        #expect(payoff.contains("connecting"))
        let flows = engine.state.connectingFlowsIfHub(at: "HUB", airline: airline, catalog: engine.catalog)
        #expect(!flows.isEmpty)
        // A spoke with one route has nothing to connect.
        let spokeOffer = try #require(engine.state.hubUpgradeOffers(airport: "WST", catalog: engine.catalog)
            .first { $0.kind == .transferCentre })
        #expect(spokeOffer.next?.payoff?.contains("at least two") == true)
        // And the estimate changed nothing.
        #expect(engine.state.airlines[airline]?.connectingFlowsToday == nil)
    }

    // MARK: Determinism and saves

    /// Short-haul campaigns without a transfer centre run exactly as before:
    /// the pipeline with the connecting system and the one without it leave
    /// bit-identical worlds.
    @Test func pointToPointBaselinesDoNotMove() throws {
        func run(_ systems: [any SimulationSystem]) throws -> UInt64 {
            let (engine, _, _) = try DemandFixtures.market(fare: Money.dollars(119))
            let replay = SimulationEngine(state: engine.state, systems: systems, catalog: engine.catalog)
            replay.advance(ticks: Fixtures.ticksPerDay * 40)
            return try replay.state.stateHash()
        }
        let with = try run(GamePipeline.standard())
        let without = try run(GamePipeline.standard().filter { $0.id != "connectingDemand" })
        #expect(with == without)
        #expect(GamePipeline.standard().map(\.id).contains("connectingDemand"))
    }

    @Test func connectionsAreDeterministic() throws {
        func run() throws -> UInt64 {
            let (engine, _, _) = try HubFixtures.network(spokes: ["WST", "EST", "NTH"])
            engine.advance(ticks: Fixtures.ticksPerDay * 12 + 37)
            return try engine.state.stateHash()
        }
        #expect(try run() == run())
    }

    @Test func aHubSurvivesASaveMidDay() throws {
        let (source, airline, _) = try HubFixtures.network(spokes: ["WST", "EST", "NTH"])
        // Mid-morning: some flights have boarded their connecting travellers.
        source.advance(ticks: Fixtures.ticksPerDay * 3 + 40)
        #expect(source.state.flights.values.contains { ($0.connectingPassengers ?? 0) > 0 })
        let restored = SimulationEngine(state: try JSONSaveCodec().decode(JSONSaveCodec().encode(source.state)),
                                        systems: source.systems, catalog: source.catalog)
        #expect(restored.state == source.state)
        source.advance(ticks: Fixtures.ticksPerDay * 2)
        restored.advance(ticks: Fixtures.ticksPerDay * 2)
        #expect(restored.state == source.state)
        #expect(restored.state.airlines[airline]?.hubStatus(at: "HUB") != nil)
    }

    @Test func aV16SaveOpensWithoutConnections() throws {
        let (engine, airline, routes) = try HubFixtures.network(hub: false)
        engine.advance(ticks: Fixtures.ticksPerDay * 2)
        var envelope = try #require(JSONSerialization.jsonObject(with: JSONSaveCodec().encode(engine.state)) as? [String: Any])
        envelope["formatVersion"] = 16
        let restored = try JSONSaveCodec().decode(JSONSerialization.data(withJSONObject: envelope))
        #expect(restored == engine.state)
        #expect(restored.airlines[airline]?.facilities(at: "HUB").transferCentre == 0)
        #expect(routes.allSatisfy { restored.routes[$0]?.connectionsToday == nil })
        // Facilities written before the transfer centre decode with none.
        let old = try JSONDecoder().decode(AirportFacilities.self,
                                           from: Data(#"{"lounge":1,"groundServices":0,"hangar":1,"crewBase":1}"#.utf8))
        #expect(old == AirportFacilities(lounge: 1, hangar: 1, crewBase: 1))
        // Content from before it loads with the plan's figures.
        let tuning = try JSONDecoder().decode(AirportFacilityTuning.self, from: Data("""
            {"loungeInstallation":{"cents":75000000},"groundInstallation":{"cents":50000000},
             "loungeMonthly":{"cents":1500000},"groundMonthly":{"cents":1000000},
             "loungeComfortPerLevel":0.04,"groundRiskReductionPerLevel":0.1}
            """.utf8))
        #expect(tuning.transferCentreInstallation == .dollars(25_000_000))
        #expect(tuning.transferCentreBuildDays == 60)
        #expect(tuning.isValid)
    }

    // MARK: Cost and balance

    /// The day's cost is bounded by the caps, not the network: thirty
    /// spokes round one hub, timed, and no more pairs connected than the
    /// per-hub cap.
    @Test func theSpillCostIsBoundedOnALargeNetwork() throws {
        var airports = [HubFixtures.airport("HUB", "Hubton", latitude: 50, longitude: 10)]
        for k in 0..<30 {
            let angle = Double(k) / 30 * 2 * .pi
            airports.append(HubFixtures.airport(String(format: "S%02d", k), "Spoke \(k)",
                                                latitude: 50 + 5 * cos(angle), longitude: 10 + 7.5 * sin(angle),
                                                population: 1_500 + 150 * k))
        }
        let catalog = try HubFixtures.catalog(airports: airports)
        let (engine, airline, routes) = try HubFixtures.network(spokes: airports.dropFirst().map(\.code.raw),
                                                                trips: 2, catalog: catalog,
                                                                cash: .dollars(5_000_000_000))
        #expect(routes.count == 30)
        engine.advance(ticks: Fixtures.ticksPerDay * 2)
        let flows = try #require(engine.state.airlines[airline]?.connectingFlowsToday)
        #expect(!flows.isEmpty)
        #expect(flows.count <= catalog.tuning.airportServices.transferMarketsPerHub)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<5 {
                _ = DemandSystem.connectingSpill(airline: airline, state: engine.state, catalog: catalog)
            }
        }
        print("TRANSFER-COST connectingSpill, 30 spokes, \(flows.count) flows: \(elapsed / 5) a day")
        #expect(elapsed / 5 < .seconds(1), "the spill took \(elapsed / 5) a day")
    }

    /// What a transfer centre is worth in the hub fixture, against the same
    /// network without one: printed for the balance record, and held to
    /// "it earns something and cannot print money".
    @Test func balanceOfAThreeSpokeHub() throws {
        func run(hub: Bool) throws -> (revenue: Int64, profit: Int64, connecting: Int64, load: Double) {
            let (engine, _, routes) = try HubFixtures.network(spokes: ["WST", "EST", "NTH"], hub: hub)
            // Thirty days from the 1st: one whole month on the routes' books.
            engine.advance(ticks: Fixtures.ticksPerDay * 30)
            var revenue: Int64 = 0, profit: Int64 = 0, connecting: Int64 = 0
            var carried: Int64 = 0, seats: Int64 = 0
            for id in routes {
                let r = try #require(engine.state.routes[id])
                let m = r.economicsThisMonth
                revenue += m.revenueCents
                profit += m.directOperatingProfit.cents
                connecting += m.connectingPassengers ?? 0
                carried += r.stats.passengersCarried
                seats += r.stats.seatsFlown
            }
            return (revenue, profit, connecting, seats > 0 ? Double(carried) / Double(seats) : 0)
        }
        let plain = try run(hub: false), hub = try run(hub: true)
        // Direct operating profit counts the passenger fees connections pay;
        // onboard service (a few dollars a traveller) is airline-level.
        let monthly = Double(hub.profit - plain.profit) / 100
        let upkeep = AirportFacilityTuning.standard.transferCentreMonthly.asDouble
        let payback = monthly > upkeep
            ? AirportFacilityTuning.standard.transferCentreInstallation.asDouble / (monthly - upkeep) : .infinity
        print("TRANSFER-BALANCE 3 spokes x 3/day at $99: connecting legs \(hub.connecting) a month, "
              + "load \(plain.load) -> \(hub.load), revenue +$\((hub.revenue - plain.revenue) / 100), "
              + "direct profit +$\(Int(monthly)) a month, payback \(payback) months after upkeep")
        #expect(hub.connecting > 0)
        #expect(hub.revenue > plain.revenue)
        #expect(hub.load > plain.load)
        #expect(hub.load <= 1)
        // No money-printer: a small hub pays back within the plan's bar
        // (§8: 18–36 months), not in a year.
        #expect(payback > 15, "a three-spoke hub pays back in \(payback) months")
    }

    /// The same measurement on the real map: Stockholm with eight European
    /// spokes at the reference fare, three round trips a day, no rivals —
    /// an upper bound, since rivals' nonstops shrink the residual.
    @Test func balanceOfAStockholmHub() throws {
        let catalog = try ContentCatalog.loadBundled()
        let spokes: [AirportCode] = ["LHR", "CDG", "FRA", "AMS", "HEL", "CPH", "OSL", "WAW"]
        func run(hub: Bool) throws -> (revenue: Int64, profit: Int64, connecting: Int64, flows: Int, load: Double) {
            let founder = SimulationEngine(state: Fixtures.newState(), systems: HubFixtures.pipeline, catalog: catalog)
            #expect(founder.applyNow(FoundAirlineCommand(airlineName: "Nordic Hub", kind: .player, homeAirport: "ARN",
                                                         startingCash: .dollars(1_500_000_000))) == .applied)
            let airline = try #require(founder.state.playerAirline).id
            var routes: [RouteID] = []
            for spoke in spokes {
                let distance = try #require(catalog.distanceKm("ARN", spoke))
                let fare = Money(rounding: DemandSystem.referenceFare(distanceKm: distance, tuning: catalog.tuning.demand))
                #expect(founder.applyNow(BuyUsedAircraftCommand(buyer: airline, type: "MR180", ageYears: 2)) == .applied)
                let aircraft = try #require(founder.state.fleet(of: airline).first { $0.assignedRoute == nil }).id
                #expect(founder.applyNow(OpenRouteCommand(airline: airline, origin: "ARN", destination: spoke,
                                                          dailyRoundTrips: 3, ticketPrice: fare)) == .applied)
                let route = try #require(founder.state.routes(of: airline).first { $0.servesAirport(spoke) }).id
                #expect(founder.applyNow(AssignAircraftToRouteCommand(airline: airline, route: route,
                                                                      aircraftID: aircraft)) == .applied)
                routes.append(route)
            }
            var state = founder.state
            state.progression.era = .national
            if hub { state.airlines[airline]?.airportFacilities = ["ARN": AirportFacilities(transferCentre: 1)] }
            let engine = SimulationEngine(state: state, systems: HubFixtures.pipeline, catalog: catalog)
            engine.advance(ticks: Fixtures.ticksPerDay * 30)
            var revenue: Int64 = 0, profit: Int64 = 0, connecting: Int64 = 0, carried: Int64 = 0, seats: Int64 = 0
            for id in routes {
                guard let r = engine.state.routes[id] else { continue }
                revenue += r.economicsThisMonth.revenueCents
                profit += r.economicsThisMonth.directOperatingProfit.cents
                connecting += r.economicsThisMonth.connectingPassengers ?? 0
                carried += r.stats.passengersCarried
                seats += r.stats.seatsFlown
            }
            let flows = engine.state.airlines[airline]?.connectingFlowsToday?.count ?? 0
            return (revenue, profit, connecting, flows, seats > 0 ? Double(carried) / Double(seats) : 0)
        }
        let plain = try run(hub: false), hub = try run(hub: true)
        let monthly = Double(hub.profit - plain.profit) / 100
        let upkeep = AirportFacilityTuning.standard.transferCentreMonthly.asDouble
        let payback = monthly > upkeep
            ? AirportFacilityTuning.standard.transferCentreInstallation.asDouble / (monthly - upkeep) : .infinity
        print("TRANSFER-BALANCE ARN, 8 spokes x 3/day at reference fares: \(hub.flows) city pairs, "
              + "connecting legs \(hub.connecting) a month, load \(plain.load) -> \(hub.load), "
              + "revenue +$\((hub.revenue - plain.revenue) / 100), direct profit +$\(Int(monthly)) a month, "
              + "payback \(payback) months after upkeep")
        #expect(hub.connecting > 0)
        #expect(hub.revenue > plain.revenue)
        #expect(hub.load <= 1)
        // The uncontested upper bound still takes over a year to pay back.
        #expect(payback > 12, "an uncontested eight-spoke hub pays back in \(payback) months")
    }

    // MARK: The hub view

    @Test func transferWalkRunsAlongTheMezzanine() throws {
        let catalog = try ContentCatalog.loadBundled()
        for code in catalog.orderedAirportCodes.prefix(40) {
            let spec = try #require(catalog.airport(code))
            for facilities in [AirportFacilities(), AirportFacilities(lounge: 2, transferCentre: 1)] {
                let layout = HubLayout.make(airport: spec, facilities: facilities)
                let walk = try #require(layout.transferWalk, "no walk at \(code.raw)")
                let deck = try #require(layout.interior.pieces.first { $0.kind == .mezzanine })
                for point in walk.points {
                    #expect(point.y == deck.center.y + deck.size.y)
                    #expect(layout.interior.bounds.contains(point), "\(code.raw)")
                }
                if let lounge = layout.interior.pieces.first(where: { $0.kind == .loungeBlock }) {
                    #expect(walk.points.allSatisfy { $0.x < lounge.center.x - lounge.size.x / 2 }, "\(code.raw)")
                }
            }
        }
    }
}
