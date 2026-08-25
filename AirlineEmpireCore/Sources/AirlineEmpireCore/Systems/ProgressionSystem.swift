/// Daily player progression (docs/PROGRESSION.md): capability completion,
/// era gates, milestones, achievements, mission lifecycle, game over.
/// Pipeline slot #10 — after operations and economics have written the day.
public struct ProgressionSystem: SimulationSystem {
    public let id = "progression"
    public let cadence = Cadence.daily

    public init() {}

    public func update(state: inout GameState, context: SimContext) {
        guard let player = state.playerAirline else { return }
        let tuning = context.catalog.tuning.progression

        // Game over is terminal.
        if player.status == .collapsed {
            if !state.progression.gameOver {
                state.progression.gameOver = true
                context.emit(.gameOver)
            }
            return
        }

        completePrograms(&state, context: context)
        advanceEra(player: player, state: &state, context: context, tuning: tuning)
        checkMilestones(player: player, state: &state, context: context)
        checkAchievements(player: player, state: &state, context: context, tuning: tuning)
        runMissions(player: player, state: &state, context: context, tuning: tuning)
    }

    // MARK: Capabilities

    private func completePrograms(_ state: inout GameState, context: SimContext) {
        var stillActive: [CapabilityProgram] = []
        for program in state.progression.activePrograms {
            if program.completesAt <= context.current {
                state.progression.completedPrograms.append(program.code.rawValue)
                context.emit(.capabilityCompleted(code: program.code))
            } else {
                stillActive.append(program)
            }
        }
        state.progression.activePrograms = stillActive
    }

    // MARK: Eras

    private func advanceEra(player: Airline, state: inout GameState,
                            context: SimContext, tuning: ProgressionTuning) {
        let next: Era? = switch state.progression.era {
        case .startup: .regional
        case .regional: .national
        case .national: .international
        case .international: .empire
        case .empire: nil
        }
        guard let next, gatePassed(next, player: player, state: state,
                                   catalog: context.catalog, tuning: tuning)
        else { return }
        state.progression.era = next
        context.emit(.eraAdvanced(era: next))
    }

    private func gatePassed(_ era: Era, player: Airline, state: GameState,
                            catalog: ContentCatalog,
                            tuning: ProgressionTuning) -> Bool {
        let routes = state.routes(of: player.id)
        let fleet = state.fleet(of: player.id)
        switch era {
        case .startup:
            return true
        case .regional:
            // Demonstrated route competence + first owned airframe.
            let profitable = routes.filter {
                $0.economicsLastMonth.directOperatingProfit > .zero
            }.count
            let ownsOne = fleet.contains { if case .owned = $0.ownership { true } else { false } }
            return profitable >= tuning.regionalProfitableRoutes && ownsOne
        case .national:
            let trailing = trailingNetProfit(player.id, state: state, months: 12)
            return trailing > .zero
                && destinations(routes).count >= tuning.nationalDestinations
                && player.reputation.score >= tuning.nationalReputationFloor
        case .international:
            // Serving two world regions IS going international.
            let regions = Set(routes.flatMap { route -> [WorldRegion] in
                [route.origin, route.destination].compactMap {
                    catalog.airport($0)?.region
                }
            })
            let trailing = trailingNetProfit(player.id, state: state, months: 12)
            return trailing > .zero && fleet.count >= tuning.internationalFleet
                && regions.count >= 2
        case .empire:
            return destinations(routes).count >= tuning.empireDestinations
                && fleet.count >= tuning.empireFleet
        }
    }

    private func destinations(_ routes: [Route]) -> Set<AirportCode> {
        var set = Set<AirportCode>()
        for route in routes {
            set.insert(route.origin)
            set.insert(route.destination)
        }
        return set
    }

    private func trailingNetProfit(_ airline: AirlineID, state: GameState,
                                   months: Int) -> Money {
        guard let finance = state.finance.byAirline[airline] else { return .zero }
        return finance.statements.suffix(months)
            .reduce(Money.zero) { $0 + $1.netProfit }
    }

    // MARK: Milestones

    private func checkMilestones(player: Airline, state: inout GameState,
                                 context: SimContext) {
        let routes = state.routes(of: player.id)
        let fleet = state.fleet(of: player.id)
        let counters = state.progression.counters

        reach("firstFlight", when: counters.flightsCompleted >= 1,
              state: &state, context: context)
        reach("firstOwnedAircraft",
              when: fleet.contains { if case .owned = $0.ownership { true } else { false } },
              state: &state, context: context)
        if let latest = state.finance.byAirline[player.id]?.latest {
            reach("firstProfitableMonth", when: latest.netProfit > .zero,
                  state: &state, context: context)
            reach("firstMillionMonth",
                  when: latest.netProfit >= Money.dollars(1_000_000),
                  state: &state, context: context)
        }
        reach("passengers100k", when: counters.passengersCarried >= 100_000,
              state: &state, context: context)
        reach("passengers1m", when: counters.passengersCarried >= 1_000_000,
              state: &state, context: context)
        reach("destinations10", when: destinations(routes).count >= 10,
              state: &state, context: context)
        reach("fleet10", when: fleet.count >= 10, state: &state, context: context)
        let intercontinental = routes.contains { route in
            guard let origin = context.catalog.airport(route.origin),
                  let destination = context.catalog.airport(route.destination)
            else { return false }
            return origin.region != destination.region
        }
        reach("firstIntercontinental", when: intercontinental,
              state: &state, context: context)
    }

    private func reach(_ code: String, when condition: Bool,
                       state: inout GameState, context: SimContext) {
        guard condition, !state.progression.hasMilestone(code) else { return }
        state.progression.milestones.append(code)
        context.emit(.milestoneReached(code: code))
    }

    // MARK: Achievements

    private func checkAchievements(player: Airline, state: inout GameState,
                                   context: SimContext, tuning: ProgressionTuning) {
        // Value Legend: sustained top value perception.
        if player.reputation.valuePerception >= tuning.valueLegendThreshold {
            state.progression.valueStreakDays += 1
        } else {
            state.progression.valueStreakDays = 0
        }
        unlock("valueLegend",
               when: state.progression.valueStreakDays >= tuning.valueLegendDays,
               state: &state, context: context)

        // Purist: reach international with a single manufacturer fleet.
        let fleet = state.fleet(of: player.id)
        if state.progression.era >= .international, fleet.count >= 5 {
            let manufacturers = Set(fleet.compactMap {
                context.catalog.aircraftType($0.typeCode)?.manufacturer
            })
            unlock("purist", when: manufacturers.count == 1,
                   state: &state, context: context)
        }

        // Debt-free: reached national without ever borrowing.
        unlock("debtFree",
               when: state.progression.era >= .national
                   && state.progression.counters.loansTaken == 0,
               state: &state, context: context)

        // Weather-proof: big completed volume at near-perfect completion.
        let counters = state.progression.counters
        if counters.flightsCompleted >= tuning.weatherProofFlights {
            let routes = state.routes(of: player.id)
            let totals = routes.reduce((completed: Int64(0), total: Int64(0))) {
                ($0.completed + $1.stats.flightsCompleted, $0.total + $1.stats.totalFlights)
            }
            if totals.total > 0 {
                unlock("weatherProof",
                       when: Double(totals.completed) / Double(totals.total)
                           >= tuning.weatherProofCompletionRate,
                       state: &state, context: context)
            }
        }
    }

    private func unlock(_ code: String, when condition: Bool,
                        state: inout GameState, context: SimContext) {
        guard condition, !state.progression.achievements.contains(code) else { return }
        state.progression.achievements.append(code)
        context.emit(.achievementUnlocked(code: code))
    }

    // MARK: Missions

    private func runMissions(player: Airline, state: inout GameState,
                             context: SimContext, tuning: ProgressionTuning) {
        // Resolve running missions.
        var open: [Mission] = []
        for mission in state.progression.missions {
            let progress = missionProgress(mission, player: player, state: state,
                                           catalog: context.catalog)
            switch mission.kind {
            case .boomRush(_, let target):
                if progress >= target {
                    state.ledger.post(airline: player.id, category: .missionReward,
                                      amount: mission.reward, at: context.current,
                                      memo: "Mission reward")
                    context.emit(.missionCompleted(id: mission.id, reward: mission.reward))
                } else if mission.deadline <= context.current {
                    context.emit(.missionExpired(id: mission.id))
                } else {
                    open.append(mission)
                }
            }
        }
        state.progression.missions = open

        // Offer new missions from active tourism booms (one per event).
        for event in state.world.activeEvents where event.hasStarted {
            guard case .tourismBoom(let region) = event.kind,
                  !state.progression.missions.contains(where: {
                      $0.sourceEventID == event.id
                  }),
                  !completedOrExpired(event.id, state: state)
            else { continue }
            let baseline = regionPassengers(region, player: player, state: state,
                                            catalog: context.catalog)
            // Target scales with what the player could plausibly add.
            let routesInRegion = state.routes(of: player.id).filter { route in
                touchesRegion(route, region, catalog: context.catalog)
            }
            let dailySeats = routesInRegion.reduce(0) { partial, route in
                partial + route.dailyRoundTrips * 2 * 150
            }
            let days = max(1, (event.endsAt - context.current).minutes
                / GameCalendar.minutesPerDay)
            let target = max(500, Int64(Double(dailySeats) * Double(days)
                * tuning.boomRushTargetFactor))
            let reward = tuning.boomRushRewardPerPax * target
            let mission = Mission(id: state.progression.nextMissionID,
                                  sourceEventID: event.id,
                                  kind: .boomRush(region: region,
                                                  targetPassengers: target),
                                  deadline: event.endsAt, reward: reward,
                                  baseline: baseline)
            state.progression.nextMissionID += 1
            state.progression.missions.append(mission)
            // One offer per source event, ever.
            state.world.eventCooldowns["mission.\(event.id)"] = context.current.dayIndex
            context.emit(.missionOffered(id: mission.id, kind: mission.kind,
                                         deadline: mission.deadline,
                                         reward: reward))
        }
    }

    /// Missions are one-shot per source event; a mission absent from the
    /// active list with a lower id than the counter was completed/expired.
    private func completedOrExpired(_ eventID: Int64, state: GameState) -> Bool {
        // Cheap dedup: remember offered events in cooldowns ledger.
        state.world.eventCooldowns["mission.\(eventID)"] != nil
    }

    private func missionProgress(_ mission: Mission, player: Airline,
                                 state: GameState, catalog: ContentCatalog) -> Int64 {
        switch mission.kind {
        case .boomRush(let region, _):
            // Pax carried on region-touching routes since the baseline.
            let current = regionPassengers(region, player: player, state: state,
                                           catalog: catalog)
            return max(0, current - mission.baseline)
        }
    }

    private func regionPassengers(_ region: WorldRegion, player: Airline,
                                  state: GameState, catalog: ContentCatalog) -> Int64 {
        state.routes(of: player.id)
            .filter { touchesRegion($0, region, catalog: catalog) }
            .reduce(Int64(0)) { $0 + $1.stats.passengersCarried }
    }

    private func touchesRegion(_ route: Route, _ region: WorldRegion,
                               catalog: ContentCatalog) -> Bool {
        [route.origin, route.destination].contains { code in
            catalog.airport(code)?.region == region
        }
    }
}
