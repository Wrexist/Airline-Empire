import Testing
@testable import AirlineEmpireCore

/// Which aircraft may fly which route (MASTER PROMPT 5 §23, §24).
///
/// The model exists because two screens were deciding this for themselves and
/// both were wrong, so the test that carries the weight is
/// `blockersAgreeWithTheValidator`: it drives every aircraft against every
/// route in a real world and asserts the model and
/// `AssignAircraftToRouteCommand.validate` reach the same verdict on each. If
/// someone changes the validator and not the model, that test fails rather
/// than the player discovering it at the tap.
///
/// The rest are about restraint, on the same reasoning as `RouteVerdictTests`:
/// a note that fires on every candidate ranks nothing.
@Suite("Assignment eligibility")
struct AssignmentEligibilityTests {

    /// A funded airline in the standard world, with a mixed fleet and several
    /// routes of different lengths — the shape that actually exercises range
    /// and runway, which a single-route fixture never would.
    private func world(seed: UInt64 = 8080) async throws
        -> (GameSession, AirlineID, ContentCatalog) {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: seed),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Eligibility Air", kind: .player, homeAirport: "ARN",
            startingCash: Money.dollars(900_000_000)))
        let player = try #require(await session.snapshot.playerAirline).id
        await session.populateStandardWorld(competitors: 2)
        return (session, player, catalog)
    }

    /// Buys one of several types so range and runway differ across the fleet,
    /// then opens the longest routes the market offers so some pairings are
    /// genuinely out of reach.
    private func mixedWorld(seed: UInt64 = 8080) async throws
        -> (GameSession, AirlineID, ContentCatalog) {
        let (session, player, catalog) = try await world(seed: seed)
        // Deliberately spans the categories: a turboprop cannot reach what a
        // widebody can, and a widebody cannot use every runway.
        let types = catalog.orderedAircraftTypeCodes.prefix(8)
        for code in types {
            _ = await session.submit(BuyUsedAircraftCommand(
                buyer: player, type: code, ageYears: 4))
        }
        let state = await session.snapshot
        for market in state.marketOpportunities(catalog: catalog, limit: 6) {
            _ = await session.submit(OpenRouteCommand(
                airline: player, origin: market.origin,
                destination: market.destination, dailyRoundTrips: 2,
                ticketPrice: market.referenceFare))
        }
        await session.advance(ticks: Fixtures.ticksPerDay * 3)
        return (session, player, catalog)
    }

    // MARK: The one that matters

    @Test("Every blocker agrees with the command validator, on every pairing")
    func blockersAgreeWithTheValidator() async throws {
        let (session, player, catalog) = try await mixedWorld()
        let state = await session.snapshot
        let fleet = state.fleet(of: player)
        let routes = state.routes(of: player)
        try #require(!fleet.isEmpty)
        try #require(!routes.isEmpty)

        var checked = 0
        var refusedByBoth = 0
        for aircraft in fleet {
            for route in routes {
                let candidate = state.candidate(aircraft: aircraft, route: route,
                                                catalog: catalog)
                let rejection = AssignAircraftToRouteCommand(
                    airline: player, route: route.id, aircraftID: aircraft.id)
                    .validate(state: state, catalog: catalog)
                checked += 1
                if rejection != nil { refusedByBoth += 1 }
                #expect(candidate.isEligible == (rejection == nil),
                        """
                        model and validator disagree for \(aircraft.typeCode.raw) \
                        on \(route.origin.raw)–\(route.destination.raw) \
                        (\(route.distanceKm) km): model blocker \
                        \(String(describing: candidate.blocker)), validator \
                        \(String(describing: rejection?.code))
                        """)
            }
        }
        // Guard the guard: a fixture where nothing is ever refused would let
        // a model that returns "eligible" unconditionally pass the loop above.
        #expect(checked > 20, "fixture too small to be evidence")
        #expect(refusedByBoth > 0,
                "no pairing was refused — this fixture cannot detect an over-permissive model")
    }

    // MARK: Blockers

    @Test("A route beyond an aircraft's range is blocked, and says by how much")
    func beyondRangeIsBlocked() async throws {
        let (session, player, catalog) = try await world()
        let turboprop = try #require(catalog.orderedAircraftTypeCodes
            .compactMap { catalog.aircraftType($0) }
            .first { $0.category == .turboprop })
        var state = await session.snapshot
        let home = try #require(state.playerAirline).homeAirport

        // The pair comes from the catalog, not from `marketOpportunities`.
        // Opportunities narrow to what the fleet can already fly the moment
        // the player owns anything, so once the turboprop is bought they will
        // never propose a route past its range — which is the right product
        // behaviour and makes them useless for testing the range rule.
        //
        // Every airport takes a turboprop (`small` is the lowest runway
        // class), so a route past its range fails for range and nothing else.
        let far = try #require(catalog.orderedAirportCodes
            .first { code in
                guard code != home,
                      let distance = catalog.distanceKm(home, code) else { return false }
                return distance > turboprop.rangeKm
            })
        _ = await session.submit(OpenRouteCommand(
            airline: player, origin: home, destination: far,
            dailyRoundTrips: 1,
            ticketPrice: Money.dollars(400)))
        _ = await session.submit(BuyUsedAircraftCommand(
            buyer: player, type: turboprop.code, ageYears: 2))
        state = await session.snapshot
        let aircraft = try #require(state.fleet(of: player).first)
        let route = try #require(state.routes(of: player)
            .first { $0.destination == far })

        let candidate = state.candidate(aircraft: aircraft, route: route,
                                        catalog: catalog)
        #expect(!candidate.isEligible)
        #expect(candidate.blocker == .beyondRange(rangeKm: turboprop.rangeKm,
                                                  distanceKm: route.distanceKm))
        // A blocked pairing makes no fit claim: how well it would have suited
        // the route is not a question worth answering about a flight that
        // cannot legally happen.
        #expect(candidate.note == nil)
    }

    @Test("An aircraft already on a route is blocked, and names the route")
    func alreadyAssignedIsBlocked() async throws {
        let (session, player, catalog) = try await mixedWorld()
        var state = await session.snapshot
        let route = try #require(state.routes(of: player).first)
        let candidates = state.assignmentCandidates(forRoute: route.id,
                                                    catalog: catalog)
        let usable = try #require(candidates.first { $0.isEligible })
        _ = await session.submit(AssignAircraftToRouteCommand(
            airline: player, route: route.id, aircraftID: usable.aircraftID))
        state = await session.snapshot

        let after = state.assignmentCandidates(forRoute: route.id, catalog: catalog)
        let now = try #require(after.first { $0.aircraftID == usable.aircraftID })
        #expect(now.blocker == .alreadyAssigned(route.id))
    }

    @Test("An undelivered aircraft is blocked, and carries its delivery date")
    func orderedAircraftIsBlocked() async throws {
        let (session, player, catalog) = try await world()
        _ = await session.submit(BuyNewAircraftCommand(buyer: player, type: "MR180"))
        var state = await session.snapshot
        let market = try #require(state.marketOpportunities(catalog: catalog,
                                                            limit: 1).first)
        _ = await session.submit(OpenRouteCommand(
            airline: player, origin: market.origin, destination: market.destination,
            dailyRoundTrips: 2, ticketPrice: market.referenceFare))
        state = await session.snapshot
        let aircraft = try #require(state.fleet(of: player).first)
        let route = try #require(state.routes(of: player).first)

        let candidate = state.candidate(aircraft: aircraft, route: route,
                                        catalog: catalog)
        guard case .notDelivered(let at)? = candidate.blocker else {
            Issue.record("expected notDelivered, got \(String(describing: candidate.blocker))")
            return
        }
        // The date is the point: "not delivered" without a when is not
        // something a player can plan around.
        #expect(at > state.clock.now)
    }

    // MARK: The maintenance case — where the old UI was too strict

    @Test("An aircraft in maintenance is offered, with a caveat, because Core allows it")
    func maintenanceIsANoteNotABlocker() async throws {
        let (session, player, catalog) = try await mixedWorld()
        var state = await session.snapshot
        let route = try #require(state.routes(of: player).first)
        let aircraft = try #require(state.fleet(of: player)
            .first { $0.assignedRoute == nil })

        // Ground it directly. Waiting for condition to decay far enough for a
        // real check would take simulated years and make this a test about
        // the decay curve rather than about the rule.
        var grounded = aircraft
        grounded.status = .inMaintenance(until: state.clock.now + .days(3))
        state.aircraft[aircraft.id] = grounded

        let candidate = state.candidate(aircraft: grounded, route: route,
                                        catalog: catalog)
        // The validator is the authority, and it permits this.
        let rejection = AssignAircraftToRouteCommand(
            airline: player, route: route.id, aircraftID: grounded.id)
            .validate(state: state, catalog: catalog)
        #expect(rejection == nil, "precondition: Core permits assigning from a check")
        #expect(candidate.isEligible,
                "the old UI hid these; Core allows them, so the model must offer them")
        guard case .inMaintenance? = candidate.note else {
            Issue.record("expected a maintenance note, got \(String(describing: candidate.note))")
            return
        }
    }

    // MARK: Notes, and their restraint

    @Test("A route using nearly all of an aircraft's range is flagged as tight")
    func tightRangeIsFlagged() async throws {
        let (session, player, catalog) = try await world()
        var state = await session.snapshot
        let opportunities = state.marketOpportunities(catalog: catalog, limit: 200)

        // Search for the pairing rather than naming one. Whether any given
        // type has a route sitting in its top 10% of range is a property of
        // the world's geography, not of the rule under test: MR180's band
        // (4860–5400 km) happens to be empty in this scenario, and a test
        // hardcoded to it would fail for a reason that says nothing about
        // the code. Both ends must also take the aircraft, so that a runway
        // blocker cannot pre-empt the note being asserted.
        let found = try #require(catalog.orderedAircraftTypeCodes
            .compactMap { catalog.aircraftType($0) }
            .lazy
            .compactMap { spec -> (AircraftTypeSpec, MarketOpportunity)? in
                let lower = Int(AssignmentThresholds.tightRangeFraction
                                * Double(spec.rangeKm))
                let match = opportunities.first { opportunity in
                    guard opportunity.distanceKm > lower,
                          opportunity.distanceKm <= spec.rangeKm else { return false }
                    return [opportunity.origin, opportunity.destination].allSatisfy {
                        (catalog.airport($0)?.runwayClass ?? .small)
                            >= spec.runwayRequirement
                    }
                }
                return match.map { (spec, $0) }
            }
            .first, "no type in the catalog has a route in its tight-range band")
        let (spec, stretch) = found

        _ = await session.submit(BuyUsedAircraftCommand(
            buyer: player, type: spec.code, ageYears: 2))
        _ = await session.submit(OpenRouteCommand(
            airline: player, origin: stretch.origin,
            destination: stretch.destination, dailyRoundTrips: 1,
            ticketPrice: stretch.referenceFare))
        state = await session.snapshot
        let aircraft = try #require(state.fleet(of: player).first)
        let route = try #require(state.routes(of: player)
            .first { $0.destination == stretch.destination })

        let candidate = state.candidate(aircraft: aircraft, route: route,
                                        catalog: catalog)
        #expect(candidate.isEligible, "inside range is legal, merely tight")
        #expect(candidate.note == .tightRange(marginKm: spec.rangeKm - route.distanceKm))
    }

    @Test("A route the demand engine has not priced yet makes no capacity claim")
    func unpricedRouteSaysNothingAboutCapacity() async throws {
        let (session, player, catalog) = try await world()
        _ = await session.submit(BuyUsedAircraftCommand(
            buyer: player, type: "MR180", ageYears: 2))
        var state = await session.snapshot
        let market = try #require(state.marketOpportunities(catalog: catalog,
                                                            limit: 1).first)
        _ = await session.submit(OpenRouteCommand(
            airline: player, origin: market.origin, destination: market.destination,
            dailyRoundTrips: 2, ticketPrice: market.referenceFare))
        // Deliberately no advance: demand is still zero on a brand-new route.
        state = await session.snapshot
        let aircraft = try #require(state.fleet(of: player).first)
        var route = try #require(state.routes(of: player).first)
        route.demandOutboundToday = 0
        route.demandInboundToday = 0
        state.routes[route.id] = route

        let candidate = state.candidate(aircraft: aircraft, route: route,
                                        catalog: catalog)
        #expect(candidate.isEligible)
        // Zero demand is "not measured yet", not "nobody wants to fly". A
        // model that read it the second way would call every new route
        // massively over-served on its first day.
        #expect(candidate.note == nil,
                "a route with no measured demand must not be described as over-served")
    }

    @Test("Capacity notes describe the demand actually recorded")
    func capacityNotesFollowRecordedDemand() async throws {
        let (session, player, catalog) = try await world()
        let spec = try #require(catalog.aircraftType("MR180"))
        _ = await session.submit(BuyUsedAircraftCommand(
            buyer: player, type: spec.code, ageYears: 2))
        var state = await session.snapshot
        let market = try #require(state.marketOpportunities(catalog: catalog,
                                                            limit: 1).first)
        _ = await session.submit(OpenRouteCommand(
            airline: player, origin: market.origin, destination: market.destination,
            dailyRoundTrips: 1, ticketPrice: market.referenceFare))
        state = await session.snapshot
        let aircraft = try #require(state.fleet(of: player).first)
        var route = try #require(state.routes(of: player).first)
        let seatsPerDay = spec.seats * route.dailyRoundTrips * 2

        // Demand far beyond the seats on offer.
        route.demandOutboundToday = seatsPerDay
        route.demandInboundToday = seatsPerDay
        state.routes[route.id] = route
        #expect(state.candidate(aircraft: aircraft, route: route, catalog: catalog)
            .note == .seatsShortOfDemand(seatsPerDay: seatsPerDay,
                                         demandPerDay: seatsPerDay * 2))

        // Demand far below.
        route.demandOutboundToday = max(1, seatsPerDay / 8)
        route.demandInboundToday = 0
        state.routes[route.id] = route
        guard case .seatsAboveDemand? = state
            .candidate(aircraft: aircraft, route: route, catalog: catalog).note else {
            Issue.record("expected seatsAboveDemand")
            return
        }

        // Demand that matches the seats.
        route.demandOutboundToday = seatsPerDay / 2
        route.demandInboundToday = seatsPerDay / 2
        state.routes[route.id] = route
        #expect(state.candidate(aircraft: aircraft, route: route, catalog: catalog)
            .note == .strongMatch)
    }

    // MARK: Both directions return the same answer

    @Test("Asking from the aircraft and from the route give the same verdict")
    func bothDirectionsAgree() async throws {
        let (session, player, catalog) = try await mixedWorld()
        let state = await session.snapshot
        let routes = state.routes(of: player)
        try #require(routes.count > 1)

        for aircraft in state.fleet(of: player) {
            let fromAircraft = state.assignmentCandidates(forAircraft: aircraft.id,
                                                          catalog: catalog)
            for candidate in fromAircraft {
                let fromRoute = state.assignmentCandidates(forRoute: candidate.routeID,
                                                           catalog: catalog)
                let mirror = try #require(fromRoute.first { $0.aircraftID == aircraft.id })
                // The two pickers disagreeing is the original bug in a
                // different costume, so this is pinned rather than assumed.
                #expect(mirror == candidate)
            }
        }
    }

    @Test("Every route is offered, including the ones that cannot be flown")
    func ineligibleRoutesAreStillReturned() async throws {
        let (session, player, catalog) = try await mixedWorld()
        let state = await session.snapshot
        let routeCount = state.routes(of: player).count
        let aircraft = try #require(state.fleet(of: player).first)

        let candidates = state.assignmentCandidates(forAircraft: aircraft.id,
                                                    catalog: catalog)
        // The old picker silently dropped what it could not offer, which is
        // how "why isn't my new route in this list?" became unanswerable.
        #expect(candidates.count == routeCount)
    }
}
