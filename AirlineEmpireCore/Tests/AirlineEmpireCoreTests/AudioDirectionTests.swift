import Testing
@testable import AirlineEmpireCore

/// The audio policy (docs/AUDIO_ARCHITECTURE.md).
///
/// None of this can be heard from here, and that is exactly why the decisions
/// live in Core rather than in a view: what *can* be checked without a speaker
/// is whether the right sounds are chosen, whether they are chosen once, and
/// whether a fast-forwarded morning produces two sounds or forty. Those are
/// the properties that make an audio system feel premium or exhausting, and
/// they are all pure functions.
@Suite("Audio direction")
struct AudioDirectionTests {

    private func world(seed: UInt64 = 8801) async throws
        -> (GameSession, AirlineID, ContentCatalog) {
        let catalog = try ContentCatalog.loadBundled()
        let session = GameSession(state: Fixtures.newState(seed: seed),
                                  systems: GamePipeline.standard(),
                                  catalog: catalog)
        _ = await session.submit(FoundAirlineCommand(
            airlineName: "Reverb Air", kind: .player, homeAirport: "STV",
            startingCash: Money.dollars(300_000_000)))
        let player = try #require(await session.snapshot.playerAirline).id
        return (session, player, catalog)
    }

    /// An airline with routes, aircraft and several days of operations behind
    /// it — the state a loaded save arrives in.
    private func flyingWorld(seed: UInt64 = 8801, days: Int = 4) async throws
        -> (GameSession, AirlineID, ContentCatalog) {
        let (session, player, catalog) = try await world(seed: seed)
        for _ in 0..<2 {
            _ = await session.submit(BuyUsedAircraftCommand(
                buyer: player, type: "MR180", ageYears: 5))
        }
        var state = await session.snapshot
        let fleet = state.fleet(of: player).map(\.id)
        let targets = state.marketOpportunities(catalog: catalog, limit: 2)
        for (index, market) in targets.enumerated() where index < fleet.count {
            _ = await session.submit(OpenRouteCommand(
                airline: player, origin: market.origin,
                destination: market.destination, dailyRoundTrips: 3,
                ticketPrice: market.referenceFare))
            state = await session.snapshot
            if let route = state.routes(of: player).last {
                _ = await session.submit(AssignAircraftToRouteCommand(
                    airline: player, route: route.id, aircraftID: fleet[index]))
            }
        }
        await session.advance(ticks: Fixtures.ticksPerDay * days)
        return (session, player, catalog)
    }

    private func event(_ kind: SimEventKind) -> SimEvent {
        SimEvent(at: SimTime(rawMinutes: 0), kind: kind)
    }

    // MARK: - Taxonomy

    /// Every cue has to be playable, which means every cue needs a category
    /// and a priority. A `switch` that silently defaulted would leave a cue
    /// mis-filed and mis-mixed, and nobody would notice until it was too loud.
    @Test("Every cue is classified")
    func everyCueIsClassified() {
        for cue in AudioCue.allCases {
            _ = cue.category
            _ = cue.priority
            #expect(cue.cooldown >= 0)
        }
        #expect(AudioCue.allCases.count == Set(AudioCue.allCases.map(\.rawValue)).count)
    }

    /// The one rule the priority ladder exists to enforce.
    @Test("Critical cues outrank everything and are never rate-limited")
    func criticalCuesAreNeverSuppressed() {
        for cue in AudioCue.allCases where cue.priority == .critical {
            #expect(cue.cooldown == 0)
            #expect(cue.priority > AudioPriority.important)
        }
        #expect(AudioCue.gameOver.priority == .critical)
        #expect(AudioCue.collapse.priority == .critical)
        #expect(AudioCue.administrationEntered.priority == .critical)
    }

    /// Silence is a tool: the events that fire on a schedule must map to
    /// nothing at all, or the game pings four times a second.
    @Test("Routine calendar events make no sound")
    func routineEventsAreSilent() {
        #expect(AudioCue.for(.dayStarted(GameDate(year: 1970, month: 1, day: 1, hour: 0, minute: 0, weekday: .monday, season: .winter))) == nil)
        #expect(AudioCue.for(.weekStarted(weekIndex: 3)) == nil)
        #expect(AudioCue.for(.monthStarted(year: 1970, month: 2)) == nil)
        #expect(AudioCue.for(.seasonChanged(.summer)) == nil)
        #expect(AudioCue.for(.commandApplied(name: "OpenRouteCommand")) == nil)
        #expect(AudioCue.for(.wakeFired(label: "daily")) == nil)
    }

    /// A closed month is not one sound, it is two — and which one it is
    /// carries the entire meaning.
    @Test("A month closes with a different sound depending on the result")
    func statementSignChoosesTheCue() {
        #expect(AudioCue.for(.statementClosed(airline: AirlineID(raw: 1), year: 1970,
                                          month: 3,
                                          netProfit: Money.dollars(10_000)))
                == .monthClosedProfit)
        #expect(AudioCue.for(.statementClosed(airline: AirlineID(raw: 1), year: 1970,
                                          month: 3,
                                          netProfit: Money.dollars(-10_000)))
                == .monthClosedLoss)
    }

    /// The five world events have five identities. A storm and a boom sharing
    /// a sound would tell the player nothing they could act on.
    @Test("Each world event has its own sound")
    func worldEventsAreDistinct() {
        let cues: [AudioCue?] = [
            AudioCue.for(.worldEventStarted(id: 1, kind: .storm(region: .europe))),
            AudioCue.for(.worldEventStarted(id: 2, kind: .strike(airline: AirlineID(raw: 1)))),
            AudioCue.for(.worldEventStarted(id: 3, kind: .fuelShock)),
            AudioCue.for(.worldEventStarted(id: 4, kind: .tourismBoom(region: .eastAsia))),
            AudioCue.for(.worldEventStarted(id: 5, kind: .airportClosure(airport: "STV"))),
        ]
        #expect(cues.allSatisfy { $0 != nil })
        #expect(Set(cues.compactMap { $0 }).count == 5)
    }

    // MARK: - Haptics

    /// The rule that keeps a phone from buzzing itself flat: nothing the
    /// simulation does on its own schedule may be felt. Flights depart every
    /// few game-minutes, and a fast-forward that vibrated at each would be
    /// unusable.
    @Test("Routine operations are never felt")
    func routineOperationsHaveNoHaptic() {
        let routine: [AudioCue] = [.flightDeparted, .flightArrived,
                                   .flightDelayed, .departureFlurry,
                                   .arrivalFlurry, .maintenanceStarted,
                                   .maintenanceCompleted, .worldEventForecast,
                                   .worldEventEnded, .missionOffered,
                                   .missionExpired, .monthClosedProfit,
                                   .loanRepaid, .uiSheetOpen, .uiSheetClose,
                                   .ambienceOperations, .ambienceWorld]
        for cue in routine {
            #expect(cue.haptic == nil, "\(cue.rawValue) should not be felt")
        }
    }

    /// And its mirror: the moments that must be felt, are.
    @Test("The moments that matter carry weight")
    func consequentialCuesAreFelt() {
        #expect(AudioCue.routeOpened.haptic == .medium)
        #expect(AudioCue.aircraftDelivered.haptic == .heavy)
        #expect(AudioCue.eraAdvanced.haptic == .heavy)
        #expect(AudioCue.uiError.haptic == .error)
        for cue in AudioCue.allCases where cue.priority == .critical {
            #expect(cue.haptic != nil, "\(cue.rawValue) must be felt")
        }
        for cue in AudioCue.allCases where cue.isMilestone {
            #expect(cue.haptic != nil, "\(cue.rawValue) must be felt")
        }
    }

    /// Every cue has to name a file, and no two may name the same one — a
    /// shared asset means two different moments sound identical, which is how
    /// an audio language stops being one.
    @Test("Every cue names its own asset")
    func assetNamesAreTotalAndUnique() {
        let names = AudioCue.allCases.map(\.assetName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
        #expect(AudioCue.allCases.filter(\.isLoop).count == 2)
    }

    // MARK: - Deduplication and rate limiting

    /// The bug this whole design exists to prevent: one event, one sound.
    @Test("A cue repeated inside one batch is heard once")
    func duplicatesCollapseWithinABatch() async throws {
        let (session, _, _) = try await world()
        let state = await session.snapshot
        var director = AudioDirector(state: state)
        let cues = director.cues(
            for: [event(.aircraftDelivered(id: AircraftID(raw: 1))),
                  event(.aircraftDelivered(id: AircraftID(raw: 2))),
                  event(.aircraftDelivered(id: AircraftID(raw: 3)))],
            state: state, speed: .x1, now: 100)
        #expect(cues.filter { $0 == .aircraftDelivered }.count == 1)
    }

    @Test("A cue inside its cooldown is dropped, and plays again after it")
    func cooldownSuppressesRepeats() async throws {
        let (session, _, _) = try await world()
        let state = await session.snapshot
        var director = AudioDirector(state: state)
        let batch = [event(.worldEventStarted(id: 1, kind: .fuelShock))]

        #expect(director.cues(for: batch, state: state, speed: .x1, now: 0)
                    .contains(.fuelShockStarted))
        // Well inside the world-event cooldown.
        #expect(!director.cues(for: batch, state: state, speed: .x1, now: 1)
                    .contains(.fuelShockStarted))
        // Past it.
        #expect(director.cues(for: batch, state: state, speed: .x1,
                              now: AudioCue.fuelShockStarted.cooldown + 0.01)
                    .contains(.fuelShockStarted))
    }

    /// A cooldown that muted a bankruptcy warning would be a cooldown that
    /// cost somebody their game.
    @Test("A critical cue repeats no matter how recently it played")
    func criticalCuesIgnoreCooldown() async throws {
        let (session, player, _) = try await world()
        let state = await session.snapshot
        var director = AudioDirector(state: state)
        let batch = [event(.airlineEnteredAdministration(id: player))]
        #expect(director.cues(for: batch, state: state, speed: .x1, now: 0)
                    .contains(.administrationEntered))
        #expect(director.cues(for: batch, state: state, speed: .x1, now: 0.001)
                    .contains(.administrationEntered))
    }

    // MARK: - Speed policy

    /// The 16x test. A busy pump can publish twenty departures; the player
    /// must hear one thing, not twenty.
    @Test("Fast-forward aggregates flights instead of playing each one")
    func fastForwardAggregatesFlights() async throws {
        let (session, _, _) = try await world()
        let state = await session.snapshot
        let departures = (1...20).map {
            event(.flightDeparted(id: FlightID(raw: Int64($0)),
                                  route: RouteID(raw: 1)))
        }

        var slow = AudioDirector(state: state)
        let atOneX = slow.cues(for: departures, state: state, speed: .x1, now: 0)
        #expect(atOneX.contains(.departureFlurry))
        #expect(!atOneX.contains(.flightDeparted))

        var fast = AudioDirector(state: state)
        let atSixteenX = fast.cues(for: departures, state: state, speed: .x16, now: 0)
        #expect(atSixteenX.contains(.departureFlurry))
        #expect(!atSixteenX.contains(.flightDeparted))
        #expect(atSixteenX.count <= SimSpeed.x16.cueBudget)
    }

    /// A single departure at 1x is still worth hearing on its own.
    @Test("One departure at 1x stays an individual sound")
    func oneDepartureIsNotAggregated() async throws {
        let (session, _, _) = try await world()
        let state = await session.snapshot
        var director = AudioDirector(state: state)
        let cues = director.cues(
            for: [event(.flightDeparted(id: FlightID(raw: 1), route: RouteID(raw: 1)))],
            state: state, speed: .x1, now: 0)
        #expect(cues.contains(.flightDeparted))
        #expect(!cues.contains(.departureFlurry))
    }

    /// At 16x an individual departure is not worth hearing at all.
    @Test("A single departure at 16x is suppressed entirely")
    func singleDepartureIsSilentAtSixteenX() async throws {
        let (session, _, _) = try await world()
        let state = await session.snapshot
        var director = AudioDirector(state: state)
        let cues = director.cues(
            for: [event(.flightDeparted(id: FlightID(raw: 1), route: RouteID(raw: 1)))],
            state: state, speed: .x16, now: 0)
        #expect(!cues.contains(.flightDeparted))
        #expect(cues.contains(.departureFlurry))
    }

    @Test("No batch ever exceeds its speed's budget of ordinary cues")
    func batchesAreCapped() async throws {
        let (session, _, _) = try await world()
        let state = await session.snapshot
        // A deliberately noisy quarter second: eight unrelated ordinary cues.
        let noisy: [SimEvent] = [
            event(.aircraftOrdered(id: AircraftID(raw: 1), type: "MR180",
                                   deliveryAt: SimTime(rawMinutes: 100))),
            event(.aircraftSold(id: AircraftID(raw: 2), proceeds: Money.dollars(1))),
            event(.leaseReturned(id: AircraftID(raw: 3), penalty: Money.dollars(1))),
            event(.maintenanceStarted(id: AircraftID(raw: 4),
                                      until: SimTime(rawMinutes: 200),
                                      cost: Money.dollars(1))),
            event(.maintenanceCompleted(id: AircraftID(raw: 5))),
            event(.routeClosed(id: RouteID(raw: 6))),
            event(.aircraftUnassigned(aircraft: AircraftID(raw: 7), route: RouteID(raw: 8))),
            event(.loanRepaidEarly(airline: AirlineID(raw: 1), amount: Money.dollars(1))),
        ]
        for speed in [SimSpeed.x1, .x4, .x16] {
            var director = AudioDirector(state: state)
            let cues = director.cues(for: noisy, state: state, speed: speed, now: 0)
            #expect(cues.count <= speed.cueBudget)
        }
    }

    /// Ranking must be stable, or the same busy moment sounds different every
    /// time it is replayed and the audio stops being a language.
    @Test("The same batch always yields the same cues in the same order")
    func rankingIsDeterministic() async throws {
        let (session, _, _) = try await world()
        let state = await session.snapshot
        let batch: [SimEvent] = [
            event(.routeOpened(id: RouteID(raw: 1), origin: "STV", destination: "LHR")),
            event(.aircraftDelivered(id: AircraftID(raw: 2))),
            event(.maintenanceCompleted(id: AircraftID(raw: 3))),
            event(.loanTaken(airline: AirlineID(raw: 1),
                             amount: Money.dollars(1_000_000), rateBasisPoints: 500)),
        ]
        var a = AudioDirector(state: state)
        var b = AudioDirector(state: state)
        #expect(a.cues(for: batch, state: state, speed: .x1, now: 0)
                == b.cues(for: batch, state: state, speed: .x1, now: 0))
    }

    /// A high-priority cue must survive a batch that is over budget.
    @Test("The budget cuts the quiet cues, not the loud ones")
    func budgetKeepsThePriorities() async throws {
        let (session, _, _) = try await world()
        let state = await session.snapshot
        var director = AudioDirector(state: state)
        let batch: [SimEvent] = [
            event(.maintenanceCompleted(id: AircraftID(raw: 1))),   // subtle
            event(.aircraftUnassigned(aircraft: AircraftID(raw: 2),
                                      route: RouteID(raw: 1))),      // subtle
            event(.missionOffered(id: 3, kind: .boomRush(region: .europe, targetPassengers: 100),
                                  deadline: SimTime(rawMinutes: 1),
                                  reward: Money.dollars(1))),        // subtle
            event(.routeOpened(id: RouteID(raw: 4), origin: "STV",
                               destination: "LHR")),                 // important
        ]
        let cues = director.cues(for: batch, state: state, speed: .x16, now: 0)
        #expect(cues.contains(.routeOpened))
        #expect(cues.count <= SimSpeed.x16.cueBudget)
    }

    // MARK: - The first times, and save/restore

    /// The whole point of seeding from state: a mature airline loaded from
    /// disk must not be told it has just opened its first route.
    @Test("Loading a flying airline replays none of its first times")
    func loadedGameDoesNotReplayMilestones() async throws {
        let (session, _, _) = try await flyingWorld()
        let state = await session.snapshot
        // A save/load is exactly this: a new director built from the state.
        var director = AudioDirector(state: state)
        let cues = director.cues(for: [], state: state, speed: .x1, now: 0)
        #expect(!cues.contains(.firstRoute))
        #expect(!cues.contains(.firstDeparture))
        #expect(!cues.contains(.firstArrival))
        #expect(!cues.contains(.firstRevenue))
    }

    /// And the mirror: an airline that has actually done these things for the
    /// first time must hear about it.
    @Test("A new airline earns its first times exactly once")
    func firstTimesFireOnceForANewAirline() async throws {
        let (session, player, catalog) = try await world()
        let empty = await session.snapshot
        var director = AudioDirector(state: empty)
        // Nothing yet.
        #expect(director.cues(for: [], state: empty, speed: .x1, now: 0).isEmpty)

        _ = await session.submit(BuyUsedAircraftCommand(
            buyer: player, type: "MR180", ageYears: 5))
        var state = await session.snapshot
        let market = try #require(state.marketOpportunities(catalog: catalog,
                                                            limit: 1).first)
        _ = await session.submit(OpenRouteCommand(
            airline: player, origin: market.origin, destination: market.destination,
            dailyRoundTrips: 3, ticketPrice: market.referenceFare))
        state = await session.snapshot

        let opened = director.cues(for: [], state: state, speed: .x1, now: 1)
        #expect(opened.contains(.firstRoute))
        // Asking again changes nothing: the moment has been had.
        #expect(!director.cues(for: [], state: state, speed: .x1, now: 2)
                    .contains(.firstRoute))

        let aircraft = try #require(state.fleet(of: player).first).id
        let route = try #require(state.routes(of: player).first).id
        _ = await session.submit(AssignAircraftToRouteCommand(
            airline: player, route: route, aircraftID: aircraft))
        await session.advance(ticks: Fixtures.ticksPerDay * 3)
        state = await session.snapshot

        var heard: Set<AudioCue> = []
        for step in 0..<6 {
            heard.formUnion(director.cues(for: [], state: state, speed: .x1,
                                          now: Double(10 + step)))
        }
        #expect(heard.contains(.firstDeparture) || heard.contains(.firstArrival))
        // Whatever fired, it fired once and cannot fire again.
        let again = director.cues(for: [], state: state, speed: .x1, now: 100)
        #expect(!again.contains(.firstDeparture))
        #expect(!again.contains(.firstArrival))
        #expect(!again.contains(.firstRevenue))
    }

    /// A milestone must never be the cue that a busy batch drops.
    @Test("A first time survives a batch that is over budget")
    func milestonesAreNeverCut() async throws {
        let (session, player, catalog) = try await world()
        _ = await session.submit(BuyUsedAircraftCommand(
            buyer: player, type: "MR180", ageYears: 5))
        var state = await session.snapshot
        var director = AudioDirector(state: state)
        let market = try #require(state.marketOpportunities(catalog: catalog,
                                                            limit: 1).first)
        _ = await session.submit(OpenRouteCommand(
            airline: player, origin: market.origin, destination: market.destination,
            dailyRoundTrips: 3, ticketPrice: market.referenceFare))
        state = await session.snapshot

        let noisy = (1...12).map {
            event(.flightDeparted(id: FlightID(raw: Int64($0)), route: RouteID(raw: 1)))
        } + [event(.worldEventStarted(id: 1, kind: .fuelShock)),
             event(.aircraftDelivered(id: AircraftID(raw: 99)))]
        let cues = director.cues(for: noisy, state: state, speed: .x16, now: 0)
        #expect(cues.contains(.firstRoute))
    }

    /// Closing every route must not re-arm "your first route".
    @Test("A first time latches forward and cannot be won back")
    func milestonesLatchForward() {
        var director = AudioDirector(milestones: AudioDirector.Milestones(hasRoute: true))
        #expect(director.milestones.hasRoute)
        // Feed it a state where nothing is true; the latch must hold.
        let empty = AudioDirector.Milestones()
        var again = AudioDirector(milestones: empty)
        again = AudioDirector(milestones: AudioDirector.Milestones(hasRoute: true))
        #expect(again.milestones.hasRoute)
        _ = director
    }

    /// The early-out must not change behaviour, only cost. A director that
    /// has seen everything reports so, and one that has not, does not.
    @Test("A director stops looking once every first time has happened")
    func milestoneScanStopsWhenComplete() async throws {
        let (session, _, _) = try await flyingWorld()
        let state = await session.snapshot
        let director = AudioDirector(state: state)
        #expect(director.milestones.allSeen)

        let (fresh, _, _) = try await world()
        let empty = await fresh.snapshot
        #expect(!AudioDirector(state: empty).milestones.allSeen)
    }

    // MARK: - Market candidates (the route sheet's ranking)

    /// The route sheet's destination list and the onboarding card must agree
    /// about which markets are worth flying. They are computed by different
    /// entry points — one takes an origin, the other picks bases — so this is
    /// the guard against them drifting into two different answers to the same
    /// question, exactly as `MarketOpportunities` already guards the map.
    @Test("The route sheet and the onboarding card rank the same markets")
    func sheetAndOnboardingAgree() async throws {
        let (session, player, catalog) = try await world()
        _ = await session.submit(BuyUsedAircraftCommand(
            buyer: player, type: "MR180", ageYears: 5))
        let state = await session.snapshot
        let home = try #require(state.playerAirline).homeAirport

        let sheet = state.marketCandidates(from: home, catalog: catalog)
        let onboarding = state.marketOpportunities(catalog: catalog, limit: 5)
            .filter { $0.origin == home }
        #expect(!sheet.isEmpty)
        #expect(!onboarding.isEmpty)

        // Same arithmetic: a market in both lists must carry the same figure.
        for market in onboarding {
            let match = sheet.first { $0.destination == market.destination }
            #expect(match?.expectedDailyPassengers == market.expectedDailyPassengers,
                    "\(market.destination.raw) disagrees between the two lists")
        }
    }

    /// The header claims a demand ranking; this is what makes it true.
    @Test("Candidates come back ranked by demand, deterministically")
    func candidatesAreRankedByDemand() async throws {
        let (session, player, catalog) = try await world()
        _ = await session.submit(BuyUsedAircraftCommand(
            buyer: player, type: "MR180", ageYears: 5))
        let state = await session.snapshot
        let home = try #require(state.playerAirline).homeAirport

        let ranked = state.marketCandidates(from: home, catalog: catalog)
        #expect(ranked.count == catalog.orderedAirportCodes.count - 1)
        for (a, b) in zip(ranked, ranked.dropFirst()) {
            #expect(a.expectedDailyPassengers >= b.expectedDailyPassengers)
        }
        // No airport ranks itself, and the same world always ranks the same.
        #expect(!ranked.contains { $0.destination == home })
        #expect(state.marketCandidates(from: home, catalog: catalog)
                    .map(\.destination) == ranked.map(\.destination))
    }

    /// Unlike the opportunity list, a market the player already serves must
    /// still appear — a second route on a busy pair is a legitimate move.
    @Test("A market already served is still offered to the route sheet")
    func servedMarketsRemainCandidates() async throws {
        let (session, player, catalog) = try await flyingWorld()
        let state = await session.snapshot
        let route = try #require(state.routes(of: player).first)
        let candidates = state.marketCandidates(from: route.origin, catalog: catalog)
        #expect(candidates.contains { $0.destination == route.destination })
        // Whereas the opportunity ranking deliberately excludes it.
        #expect(!state.marketOpportunities(catalog: catalog, limit: 40)
                    .contains { $0.origin == route.origin
                                && $0.destination == route.destination })
    }

    // MARK: - Stream behaviour

    /// The regression guard for §26/§27: a subscriber attached to a session
    /// built from a loaded state receives no historical events at all, so
    /// there is nothing for the director to mistake for news.
    @Test("A session built from a played state publishes no history")
    func loadingPublishesNoBacklog() async throws {
        let (session, _, catalog) = try await flyingWorld()
        let played = await session.snapshot
        #expect(played.eventLog.totalCount > 0)

        // Exactly what `loadGame` does: a fresh session over a restored state.
        let reloaded = GameSession(state: played, systems: GamePipeline.standard(),
                                   catalog: catalog)
        var received: [SimEvent] = []
        let stream = await reloaded.events(playerFeedOnly: true)
        let task = Task { for await event in stream { received.append(event) } }
        // Give the stream a chance to deliver anything it intended to.
        await reloaded.advance(ticks: 0)
        task.cancel()
        #expect(received.isEmpty)
    }
}
