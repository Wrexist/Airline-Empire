import Testing
@testable import AirlineEmpireCore

/// The read models that close the audit's three information gaps: the
/// insolvency countdown the player could not see (UI-005), the era gates the
/// game never stated (UI-008), and the month in progress on a route
/// (UI-002).
///
/// The point of every test here is *agreement*: the model must report the same
/// numbers the simulation acts on. A progress bar that disagrees with the
/// system it reports on is worse than no bar, because the player trusts it.
@Suite("Advisory read models")
struct AdvisoryModelTests {

    // MARK: - Fixtures

    private func world(seed: UInt64 = 4242,
                       cash: Money = Money.dollars(200_000_000)) async throws
        -> (GameSession, AirlineID, ContentCatalog) {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: seed),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Advisory Air", kind: .player, homeAirport: "STV",
            startingCash: cash))
        let player = try #require(await session.snapshot.playerAirline).id
        return (session, player, catalog)
    }

    /// A player flying one route, so routes and money actually move.
    private func flyingWorld(seed: UInt64 = 4242) async throws
        -> (GameSession, AirlineID, ContentCatalog) {
        let (session, player, catalog) = try await world(seed: seed)
        _ = await session.submit(BuyUsedAircraftCommand(
            buyer: player, type: "MR180", ageYears: 6))
        var state = await session.snapshot
        let aircraft = try #require(state.fleet(of: player).first).id
        let suggestion = try #require(
            state.onboardingModel(catalog: catalog)?.suggestions.first)
        _ = await session.submit(OpenRouteCommand(
            airline: player, origin: suggestion.origin,
            destination: suggestion.destination, dailyRoundTrips: 2,
            ticketPrice: suggestion.referenceFare))
        state = await session.snapshot
        let route = try #require(state.routes(of: player).first).id
        _ = await session.submit(AssignAircraftToRouteCommand(
            airline: player, route: route, aircraftID: aircraft))
        return (session, player, catalog)
    }

    // MARK: - Solvency (UI-005)

    @Test("A healthy airline reports healthy, with no countdown")
    func healthyAirlineHasNoCountdown() async throws {
        let (session, player, catalog) = try await world()
        let model = try #require(
            await session.snapshot.solvencyModel(for: player, catalog: catalog))
        #expect(model.stage == .healthy)
        #expect(model.daysUntilAdministration == nil)
        #expect(model.daysInsolvent == 0)
        #expect(model.administrationCount == 0)
        #expect(model.nextFailureIsFatal == false)
    }

    /// The countdown the player could not see. Below the overdraft floor the
    /// model must report exactly the days `SolvencySystem` will act on.
    @Test("Below the overdraft floor the model counts down to administration")
    func insolvencyCountsDown() async throws {
        let (session, player, catalog) = try await world()
        let floor = catalog.tuning.finance.overdraftFloorCents
        let grace = catalog.tuning.finance.administrationGraceDays

        // Push the balance under the floor without touching SolvencySystem.
        var state = await session.snapshot
        let balance = state.ledger.balance(of: player)
        let target = Money(cents: floor - 50_000_00)
        state.ledger.post(airline: player, category: .overhead,
                          amount: target - balance, at: state.clock.now,
                          memo: "test drain")
        let drained = GameSession(state: state, systems: GamePipeline.standard(),
                                  catalog: catalog)

        // One day below the floor.
        await drained.advance(ticks: Fixtures.ticksPerDay)
        let after = try #require(
            await drained.snapshot.solvencyModel(for: player, catalog: catalog))
        #expect(after.stage == .danger)
        #expect(after.daysInsolvent >= 1)
        let remaining = try #require(after.daysUntilAdministration)
        #expect(remaining == grace - after.daysInsolvent)
        #expect(remaining < grace)
    }

    /// The model must not promise more time than the simulation gives. The
    /// real contract is that a reported `1` is the last day: the next day
    /// boundary restructures the airline.
    @Test("A countdown of one day is the last day before administration")
    func oneDayLeftMeansAdministrationIsNext() async throws {
        let (session, player, catalog) = try await world()
        var state = await session.snapshot
        let balance = state.ledger.balance(of: player)
        state.ledger.post(
            airline: player, category: .overhead,
            amount: Money(cents: catalog.tuning.finance.overdraftFloorCents
                          - 50_000_00) - balance,
            at: state.clock.now, memo: "test drain")
        let drained = GameSession(state: state, systems: GamePipeline.standard(),
                                  catalog: catalog)

        var sawLastDay = false
        for _ in 0..<(catalog.tuning.finance.administrationGraceDays + 3) {
            await drained.advance(ticks: Fixtures.ticksPerDay)
            let model = try #require(
                await drained.snapshot.solvencyModel(for: player, catalog: catalog))
            if model.daysUntilAdministration == 1 { sawLastDay = true; break }
        }
        #expect(sawLastDay)

        // One more day boundary, and the restructuring has happened.
        await drained.advance(ticks: Fixtures.ticksPerDay)
        let airline = try #require(await drained.snapshot.airlines[player])
        #expect(airline.administrationCount >= 1 || airline.status == .collapsed)
    }

    @Test("A second failure is reported as fatal")
    func secondFailureIsFatal() async throws {
        let (session, player, catalog) = try await world()
        var state = await session.snapshot
        state.airlines[player]?.administrationCount = 1
        let model = try #require(state.solvencyModel(for: player, catalog: catalog))
        #expect(model.nextFailureIsFatal)
        _ = session
    }

    @Test("Runway is only reported against a month that actually lost money")
    func runwayNeedsALosingMonth() async throws {
        let (session, player, catalog) = try await world()
        let model = try #require(
            await session.snapshot.solvencyModel(for: player, catalog: catalog))
        // No month has closed yet, so there is nothing to extrapolate from.
        #expect(model.monthsOfRunway == nil)
    }

    @Test("An unknown airline has no solvency model")
    func unknownAirlineHasNoModel() async throws {
        let (session, _, catalog) = try await world()
        let state = await session.snapshot
        #expect(state.solvencyModel(for: AirlineID(raw: 9999),
                                    catalog: catalog) == nil)
    }

    // MARK: - Era gates (UI-008)

    /// The gate and the screen must be the same arithmetic. If every
    /// requirement is met the system must advance; if one is not, it must not.
    @Test("EraGate.isPassed agrees with its own requirements")
    func gateAgreesWithRequirements() async throws {
        let (session, player, catalog) = try await flyingWorld()
        await session.advance(ticks: Fixtures.ticksPerDay * 40)
        let state = await session.snapshot
        let airline = try #require(state.playerAirline)
        let tuning = catalog.tuning.progression

        for era in Era.allCases {
            let requirements = EraGate.requirements(
                for: era, player: airline, state: state, catalog: catalog,
                tuning: tuning)
            let passed = EraGate.isPassed(era, player: airline, state: state,
                                          catalog: catalog, tuning: tuning)
            #expect(passed == requirements.allSatisfy(\.isMet))
        }
        _ = player
    }

    @Test("The starting era demands nothing; the top of the ladder has no next")
    func ladderEnds() async throws {
        let (session, _, catalog) = try await world()
        let state = await session.snapshot
        let airline = try #require(state.playerAirline)
        #expect(EraGate.requirements(for: .startup, player: airline, state: state,
                                     catalog: catalog,
                                     tuning: catalog.tuning.progression).isEmpty)
        #expect(EraGate.next(after: .empire) == nil)
        #expect(EraGate.next(after: .startup) == .regional)
    }

    /// The reason this model exists: a brand-new airline must be able to read
    /// what the next era is asking for, with real targets.
    @Test("A new airline can read the next era's requirements")
    func nextEraIsLegible() async throws {
        let (session, _, catalog) = try await world()
        let model = try #require(await session.snapshot.progressionModel(catalog: catalog))
        #expect(model.era == .startup)
        #expect(model.nextEra == .regional)
        #expect(!model.nextEraRequirements.isEmpty)
        // Every requirement states a real target, not a placeholder.
        for requirement in model.nextEraRequirements {
            #expect(requirement.target > 0)
            #expect(requirement.fraction >= 0 && requirement.fraction <= 1)
        }
        #expect(model.nextEraProgress >= 0 && model.nextEraProgress <= 1)
        // Nothing has been done yet, so nothing is met.
        #expect(model.nextEraRequirements.allSatisfy { !$0.isMet })
    }

    @Test("Requirement targets come from tuning, not from constants in a view")
    func requirementTargetsComeFromTuning() async throws {
        let (session, _, catalog) = try await world()
        let state = await session.snapshot
        let airline = try #require(state.playerAirline)
        let tuning = catalog.tuning.progression
        let regional = EraGate.requirements(for: .regional, player: airline,
                                            state: state, catalog: catalog,
                                            tuning: tuning)
        let profitable = try #require(regional.first { $0.kind == .profitableRoutes })
        #expect(profitable.target == Double(tuning.regionalProfitableRoutes))

        let national = EraGate.requirements(for: .national, player: airline,
                                            state: state, catalog: catalog,
                                            tuning: tuning)
        let reputation = try #require(national.first { $0.kind == .reputation })
        #expect(reputation.target == tuning.nationalReputationFloor)
    }

    // MARK: - Capabilities and missions (UI-008)

    /// A world already in the era where capability programs open. Reaching it
    /// by play takes a simulated decade; the gate itself is covered above.
    private func nationalEraWorld(seed: UInt64 = 5150) async throws
        -> (GameSession, AirlineID, ContentCatalog) {
        let catalog = try ContentCatalog.loadBundled()
        var state = Fixtures.newState(seed: seed)
        state.progression.era = CapabilityProgram.unlockEra
        let session = GameSession(state: state, systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Programme Air", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(200_000_000)))
        let player = try #require(await session.snapshot.playerAirline).id
        return (session, player, catalog)
    }

    /// Before the National era every program is locked, and the screen must
    /// know that rather than offering a button whose only outcome is a refusal.
    @Test("Capabilities read as era-locked before the era that opens them")
    func capabilitiesAreEraLockedEarly() async throws {
        let (session, _, catalog) = try await world()
        let model = try #require(await session.snapshot.progressionModel(catalog: catalog))
        #expect(model.era < CapabilityProgram.unlockEra)
        for status in model.capabilities {
            guard case .eraLocked(let unlocksAt, _, _) = status.state else {
                Issue.record("expected era-locked, got \(status.state)")
                continue
            }
            #expect(unlocksAt == CapabilityProgram.unlockEra)
            #expect(status.isStartable == false)
        }
    }

    /// The model's "startable" and the command's "accepted" must be the same
    /// question, in every state — that is what makes a disabled button honest.
    @Test("isStartable agrees with the command's own validation")
    func startableAgreesWithTheCommand() async throws {
        let (early, player, catalog) = try await world()
        let earlyState = await early.snapshot
        for status in try #require(earlyState.progressionModel(catalog: catalog)).capabilities {
            let rejection = StartCapabilityProgramCommand(airline: player, code: status.code)
                .validate(state: earlyState, catalog: catalog)
            #expect(status.isStartable == (rejection == nil))
        }

        let (national, nationalPlayer, _) = try await nationalEraWorld()
        _ = await national.submit(StartCapabilityProgramCommand(
            airline: nationalPlayer, code: .efficientTurnarounds))
        let nationalState = await national.snapshot
        for status in try #require(nationalState.progressionModel(catalog: catalog)).capabilities {
            let rejection = StartCapabilityProgramCommand(airline: nationalPlayer,
                                                          code: status.code)
                .validate(state: nationalState, catalog: catalog)
            #expect(status.isStartable == (rejection == nil))
        }
    }

    @Test("A running capability program reports its cost, remaining days and progress")
    func capabilityProgramReportsProgress() async throws {
        let (session, player, catalog) = try await nationalEraWorld()
        _ = await session.submit(StartCapabilityProgramCommand(
            airline: player, code: .efficientTurnarounds))
        await session.advance(ticks: Fixtures.ticksPerDay * 10)
        let model = try #require(await session.snapshot.progressionModel(catalog: catalog))
        let status = try #require(model.capabilities.first {
            $0.code == .efficientTurnarounds
        })
        guard case .inProgress(_, let daysRemaining, let fraction) = status.state else {
            Issue.record("expected an in-progress program, got \(status.state)")
            return
        }
        #expect(fraction > 0 && fraction < 1)
        #expect(daysRemaining > 0)
        #expect(daysRemaining < catalog.tuning.progression.capabilityDurationDays)
        #expect(status.isStartable == false)
    }

    @Test("A completed program reports built, and an untouched one its price")
    func capabilityStatesAreDistinct() async throws {
        let (session, player, catalog) = try await nationalEraWorld(seed: 5151)
        _ = await session.submit(StartCapabilityProgramCommand(
            airline: player, code: .fuelHedging))
        await session.advance(
            ticks: Fixtures.ticksPerDay
                * (catalog.tuning.progression.capabilityDurationDays + 2))
        let model = try #require(await session.snapshot.progressionModel(catalog: catalog))
        let hedging = try #require(model.capabilities.first { $0.code == .fuelHedging })
        #expect(hedging.state == .built)

        let other = try #require(model.capabilities.first { $0.code == .groundExperience })
        guard case .available(let cost, let days) = other.state else {
            Issue.record("expected an available program, got \(other.state)")
            return
        }
        #expect(cost == catalog.tuning.progression.capabilityCost)
        #expect(days == catalog.tuning.progression.capabilityDurationDays)
        #expect(other.isStartable)
    }

    /// Running the maximum concurrent programs must read as "blocked", not as
    /// "available" — otherwise the screen offers a button the command refuses.
    @Test("At the program limit the remaining capabilities read as blocked")
    func programLimitIsVisible() async throws {
        let (session, player, catalog) = try await nationalEraWorld(seed: 5152)
        let limit = catalog.tuning.progression.maxActivePrograms
        let codes = Array(CapabilityCode.allCases.prefix(limit))
        for code in codes {
            _ = await session.submit(StartCapabilityProgramCommand(
                airline: player, code: code))
        }
        let model = try #require(await session.snapshot.progressionModel(catalog: catalog))
        let untouched = model.capabilities.filter { !codes.contains($0.code) }
        #expect(!untouched.isEmpty)
        for status in untouched {
            guard case .blockedBySlots = status.state else {
                Issue.record("expected blocked, got \(status.state) for \(status.code)")
                continue
            }
            #expect(status.isStartable == false)
        }
    }

    /// A mission bar that fills at a different rate from the mission is a lie;
    /// both must come from MissionMath.
    @Test("Mission progress matches the measurement that resolves the mission")
    func missionProgressMatchesResolution() async throws {
        let (session, player, catalog) = try await flyingWorld(seed: 77)
        await session.advance(ticks: Fixtures.ticksPerDay * 200)
        let state = await session.snapshot
        let airline = try #require(state.playerAirline)
        guard let model = state.progressionModel(catalog: catalog),
              let progress = model.missions.first else {
            // No boom fired in this world; the agreement below is what matters
            // and is covered by the direct check on MissionMath.
            return
        }
        let expected = MissionMath.progress(of: progress.mission, player: airline,
                                            state: state, catalog: catalog)
        #expect(progress.current == expected)
        #expect(progress.target == MissionMath.target(of: progress.mission))
        #expect(progress.daysRemaining >= 0)
        _ = player
    }

    // MARK: - Route month to date (UI-002)

    /// The defect this closes: a route opened days ago reported ¤0 forever,
    /// because only the closed month was published.
    @Test("A route flying in its first month reports month-to-date activity")
    func firstMonthIsNotAllZeros() async throws {
        let (session, player, catalog) = try await flyingWorld(seed: 909)
        await session.advance(ticks: Fixtures.ticksPerDay * 6)
        let state = await session.snapshot
        let card = try #require(state.routeCards(for: player, catalog: catalog).first)

        #expect(card.hasClosedMonth == false)
        #expect(card.lastMonthBreakdown == RouteMonthEconomics())
        // Six days of flying has to have moved something.
        #expect(card.thisMonthBreakdown.revenueCents > 0)
        #expect(card.thisMonthPassengers > 0)
        #expect(card.thisMonthProfit == card.thisMonthBreakdown.directOperatingProfit)
    }

    @Test("Month-to-date is the route's own accumulator, not a re-derivation")
    func monthToDateMirrorsTheRoute() async throws {
        let (session, player, catalog) = try await flyingWorld(seed: 910)
        await session.advance(ticks: Fixtures.ticksPerDay * 12)
        let state = await session.snapshot
        for card in state.routeCards(for: player, catalog: catalog) {
            let route = try #require(state.routes[card.id])
            #expect(card.thisMonthBreakdown == route.economicsThisMonth)
            #expect(card.lastMonthBreakdown == route.economicsLastMonth)
        }
    }

    @Test("Once a month closes the route reports a closed month")
    func closedMonthIsReported() async throws {
        let (session, player, catalog) = try await flyingWorld(seed: 911)
        await session.advance(ticks: Fixtures.ticksPerDay * 70)
        let state = await session.snapshot
        let card = try #require(state.routeCards(for: player, catalog: catalog).first)
        #expect(card.hasClosedMonth)
        #expect(card.lastMonthPassengers > 0)
    }
}
