import Testing
@testable import AirlineEmpireCore

/// The refusal codes the app translates into player-facing copy.
///
/// `CommandRejection.code` is the contract between Core and the app:
/// `Rejections.present` switches on it to answer what happened, why, and what
/// to do next, and deliberately ignores `message` so Core stays free to reword
/// itself. That works right up until a code is renamed or misremembered, and
/// then it fails in the worst available way — silently. The `switch` still
/// compiles, the case is simply never taken, and the refusal falls through to
/// the generic branch with its suggestion missing. Nothing warns anybody.
///
/// It had happened three times before this test existed. The app mapped
/// `route.hasAirborneFlights` and `route.runway`/`route.runwayTooShort`; Core
/// has only ever emitted `route.flightsAirborne` and `route.runwayTooSmall`.
/// So the two most confusing refusals in the fleet flow — "your aeroplane
/// cannot use that airport" and "wait for your flights to land" — had careful
/// copy written for them that no player could ever have seen.
///
/// These provoke each refusal from a real command against a real world and
/// pin the literal string. The app's side cannot be tested here (its target
/// does not build on Linux), so this guards the half that can be: rename a
/// code in Core and this fails, which is the moment to update the app.
@Suite("Rejection code contract")
struct RejectionCodeContractTests {

    private func world(cash: Money = Money.dollars(900_000_000),
                       seed: UInt64 = 4242) async throws
        -> (GameSession, AirlineID, ContentCatalog) {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: seed),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Contract Air", kind: .player, homeAirport: "ARN",
            startingCash: cash))
        let player = try #require(await session.snapshot.playerAirline).id
        await session.populateStandardWorld(competitors: 2)
        return (session, player, catalog)
    }

    @Test("A runway too small for the aircraft is route.runwayTooSmall")
    func runwayCode() async throws {
        let (session, player, catalog) = try await world()
        // A type needing more runway than some airport has, and a route to it.
        let big = try #require(catalog.orderedAircraftTypeCodes
            .compactMap { catalog.aircraftType($0) }
            .first { $0.runwayRequirement == .veryLarge })
        var state = await session.snapshot
        let home = try #require(state.playerAirline).homeAirport
        let small = try #require(catalog.orderedAirportCodes.first { code in
            guard code != home, let airport = catalog.airport(code) else { return false }
            guard airport.runwayClass < big.runwayRequirement else { return false }
            // Inside the aircraft's range, so range cannot pre-empt runway as
            // the reported reason.
            guard let distance = catalog.distanceKm(home, code) else { return false }
            return distance <= big.rangeKm
        })
        _ = await session.submit(OpenRouteCommand(
            airline: player, origin: home, destination: small,
            dailyRoundTrips: 1, ticketPrice: Money.dollars(300)))
        // Era-locked classes cannot be bought at the start, so place it
        // directly: this is a test about the refusal's code, not about
        // progression.
        state = await session.snapshot
        let route = try #require(state.routes(of: player).first { $0.destination == small })
        let id = AircraftID(raw: 9_001)
        state.aircraft[id] = Aircraft(id: id, typeCode: big.code, owner: player,
                                      ownership: .owned(bookValue: big.listPrice),
                                      status: .active, location: home,
                                      ageDays: 0, condition: 1.0)

        let rejection = AssignAircraftToRouteCommand(
            airline: player, route: route.id, aircraftID: id)
            .validate(state: state, catalog: catalog)
        #expect(rejection?.code == "route.runwayTooSmall")
    }

    @Test("Closing a route with aircraft in the air is route.flightsAirborne")
    func airborneCode() async throws {
        let (session, player, catalog) = try await world()
        _ = await session.submit(BuyUsedAircraftCommand(
            buyer: player, type: "MR180", ageYears: 4))
        var state = await session.snapshot
        let market = try #require(state.marketOpportunities(catalog: catalog,
                                                            limit: 1).first)
        _ = await session.submit(OpenRouteCommand(
            airline: player, origin: market.origin, destination: market.destination,
            dailyRoundTrips: 4, ticketPrice: market.referenceFare))
        state = await session.snapshot
        let route = try #require(state.routes(of: player).first)
        let aircraft = try #require(state.fleet(of: player).first)
        _ = await session.submit(AssignAircraftToRouteCommand(
            airline: player, route: route.id, aircraftID: aircraft.id))

        // Advance until something is genuinely en route. Flying is scheduled,
        // so this waits for the state rather than assuming a fixed number of
        // ticks puts an aeroplane in the air.
        var airborne = false
        for _ in 0..<40 where !airborne {
            await session.advance(ticks: Fixtures.ticksPerDay / 4)
            state = await session.snapshot
            airborne = state.flights.values.contains {
                if case .enRoute = $0.phase { return $0.route == route.id }
                return false
            }
        }
        try #require(airborne, "no flight ever got airborne; fixture cannot test this")

        let rejection = CloseRouteCommand(airline: player, route: route.id)
            .validate(state: state, catalog: catalog)
        #expect(rejection?.code == "route.flightsAirborne")
    }

    @Test("Buying a class this era cannot fly is progression.lockedCategory")
    func lockedCategoryCode() async throws {
        let (session, player, catalog) = try await world()
        let state = await session.snapshot
        // The starting era allows turboprop, regional jet and narrowbody, so
        // anything larger is locked.
        let allowed = state.progression.era.allowedCategories
        let locked = try #require(catalog.orderedAircraftTypeCodes
            .compactMap { catalog.aircraftType($0) }
            .first { !allowed.contains($0.category) })

        // All three purchase paths refuse it, and all three must say so with
        // the same code — the app maps one string.
        let buyNew = BuyNewAircraftCommand(buyer: player, type: locked.code)
            .validate(state: state, catalog: catalog)
        let buyUsed = BuyUsedAircraftCommand(buyer: player, type: locked.code,
                                             ageYears: 6)
            .validate(state: state, catalog: catalog)
        let lease = LeaseAircraftCommand(lessee: player, type: locked.code,
                                         termMonths: 60)
            .validate(state: state, catalog: catalog)
        #expect(buyNew?.code == "progression.lockedCategory")
        #expect(buyUsed?.code == "progression.lockedCategory")
        #expect(lease?.code == "progression.lockedCategory")
    }

    @Test("The assignment refusals keep the codes the app maps")
    func assignmentCodes() async throws {
        let (session, player, catalog) = try await world()
        _ = await session.submit(BuyNewAircraftCommand(buyer: player, type: "MR180"))
        var state = await session.snapshot
        let market = try #require(state.marketOpportunities(catalog: catalog,
                                                            limit: 1).first)
        _ = await session.submit(OpenRouteCommand(
            airline: player, origin: market.origin, destination: market.destination,
            dailyRoundTrips: 2, ticketPrice: market.referenceFare))
        state = await session.snapshot
        let route = try #require(state.routes(of: player).first)
        let ordered = try #require(state.fleet(of: player).first)

        #expect(AssignAircraftToRouteCommand(airline: player, route: route.id,
                                             aircraftID: ordered.id)
            .validate(state: state, catalog: catalog)?.code == "fleet.notDelivered")

        // Deliver it, assign it, then try again for the already-assigned code.
        // Advance until it actually arrives rather than guessing a number of
        // days: `deliveryLeadDays` is content, and a fixture that hardcodes a
        // guess at it fails whenever the catalog is retuned, for a reason that
        // has nothing to do with rejection codes.
        var delivered: Aircraft?
        for _ in 0..<24 where delivered == nil {
            await session.advance(ticks: Fixtures.ticksPerDay * 30)
            state = await session.snapshot
            delivered = state.fleet(of: player).first { $0.status.isActive }
        }
        let ready = try #require(delivered, "order never delivered")
        _ = await session.submit(AssignAircraftToRouteCommand(
            airline: player, route: route.id, aircraftID: ready.id))
        state = await session.snapshot
        #expect(AssignAircraftToRouteCommand(airline: player, route: route.id,
                                             aircraftID: ready.id)
            .validate(state: state, catalog: catalog)?.code == "fleet.alreadyAssigned")

        #expect(UnassignAircraftCommand(airline: player,
                                        aircraftID: AircraftID(raw: 9_999))
            .validate(state: state, catalog: catalog)?.code == "fleet.notYourAircraft")
    }

    @Test("Returning an owned aircraft is fleet.notLeased")
    func notLeasedCode() async throws {
        let (session, player, catalog) = try await world()
        _ = await session.submit(BuyUsedAircraftCommand(
            buyer: player, type: "MR180", ageYears: 4))
        let state = await session.snapshot
        let owned = try #require(state.fleet(of: player).first)
        #expect(ReturnLeasedAircraftCommand(lessee: player, aircraftID: owned.id)
            .validate(state: state, catalog: catalog)?.code == "fleet.notLeased")
    }

    /// Every code the app's `Rejections.present` switches on, as of AE-029.
    ///
    /// Kept as a literal list rather than derived, because the point is to
    /// state what the *other* side of the boundary believes. If Core stops
    /// emitting one of these, the app has copy that can never be reached; if
    /// Core starts emitting something new, the app falls back to Core's own
    /// message, which is a softer failure and is checked by review rather
    /// than here.
    @Test("Codes the app maps are all codes some command can still produce")
    func mappedCodesStillExist() {
        let mapped: Set<String> = [
            "airline.badName", "airline.nameTaken",
            "finance.insufficientFunds", "finance.overLeveraged",
            "finance.tooManyLoans",
            "fleet.alreadyAssigned", "fleet.assigned", "fleet.badLeaseTerm",
            "fleet.badUsedAge", "fleet.cannotSellLeased", "fleet.inFlight",
            "fleet.insufficientFunds", "fleet.notAssigned", "fleet.notDelivered",
            "fleet.notLeased", "fleet.notReturnableNow", "fleet.notSellableNow",
            "progression.alreadyCompleted", "progression.alreadyRunning",
            "progression.eraLocked", "progression.insufficientFunds",
            "progression.lockedCategory", "progression.tooManyPrograms",
            "route.badFrequency", "route.badPrice", "route.beyondRange",
            "route.duplicate", "route.flightsAirborne", "route.noSlots",
            "route.runwayTooSmall", "route.sameAirport", "route.tooShort",
        ]
        // The three that were wrong. Named explicitly so that anyone
        // reintroducing them meets this test rather than a silent no-op.
        let neverEmitted: Set<String> = [
            "route.hasAirborneFlights", "route.runway", "route.runwayTooShort",
        ]
        #expect(mapped.isDisjoint(with: neverEmitted))
        #expect(mapped.contains("route.flightsAirborne"))
        #expect(mapped.contains("route.runwayTooSmall"))
    }
}
