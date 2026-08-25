/// Systemic world-event lifecycle (docs/EVENTS.md): expiry → activation →
/// rate-limited triggering, all seeded and deterministic. Effects apply in
/// the systems that own each domain (demand, flight ops, fuel walk) via
/// `WorldState` queries — this system only manages the event population.
public struct WorldEventSystem: SimulationSystem {
    public let id = "worldEvents"
    public let cadence = Cadence.daily

    public init() {}

    public func update(state: inout GameState, context: SimContext) {
        let tuning = context.catalog.tuning.events
        let now = context.current

        // 1. Expire.
        var remaining: [WorldEvent] = []
        for event in state.world.activeEvents {
            if event.endsAt <= now {
                context.emit(.worldEventEnded(id: event.id, kind: event.kind))
            } else {
                remaining.append(event)
            }
        }
        // 2. Announce starts (forecast lead makes this a separate moment).
        for index in remaining.indices where !remaining[index].hasStarted
            && remaining[index].beginsAt <= now {
            remaining[index].hasStarted = true
            context.emit(.worldEventStarted(id: remaining[index].id,
                                            kind: remaining[index].kind))
        }
        state.world.activeEvents = remaining

        // 3. Trigger new events, deterministic order, rate-limited.
        triggerFuelShock(&state, context: context, tuning: tuning)
        triggerStorms(&state, context: context, tuning: tuning)
        triggerTourismBoom(&state, context: context, tuning: tuning)
        triggerStrikes(&state, context: context, tuning: tuning)
    }

    // MARK: Triggers

    private func triggerFuelShock(_ state: inout GameState, context: SimContext,
                                  tuning: EventTuning) {
        guard !state.world.activeEvents.contains(where: {
            if case .fuelShock = $0.kind { true } else { false }
        }) else { return }
        guard majorCooldownElapsed(state, tuning: tuning) else { return }
        guard state.rng.chance("events.fuelShock", probability: tuning.fuelShockDailyChance)
        else { return }
        let severity = tuning.fuelShockSeverityMin
            + state.rng.unitDouble("events.fuelShock.severity")
            * (tuning.fuelShockSeverityMax - tuning.fuelShockSeverityMin)
        let days = Int64(state.rng.int("events.fuelShock.duration",
                                       in: tuning.fuelShockDurationDaysMin...tuning.fuelShockDurationDaysMax))
        add(kind: .fuelShock, beginsAt: context.current,
            endsAt: context.current + .days(days), severity: severity,
            state: &state, context: context, isMajor: true)
    }

    private func triggerStorms(_ state: inout GameState, context: SimContext,
                               tuning: EventTuning) {
        for region in WorldRegion.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard regionalEventCount(state) < tuning.maxActiveRegionalEvents else { return }
            guard state.world.activeStorm(in: region, at: context.current) == nil,
                  !state.world.activeEvents.contains(where: {
                      if case .storm(let r) = $0.kind { r == region } else { false }
                  }) else { continue }
            let risk = regionRiskFactor(region, catalog: context.catalog)
            guard state.rng.chance("events.storm.\(region.rawValue)",
                                   probability: tuning.stormBaseDailyChance * risk)
            else { continue }
            let severity = tuning.stormSeverityMin
                + state.rng.unitDouble("events.storm.severity.\(region.rawValue)")
                * (tuning.stormSeverityMax - tuning.stormSeverityMin)
            let days = Int64(state.rng.int("events.storm.duration.\(region.rawValue)",
                                           in: tuning.stormDurationDaysMin...tuning.stormDurationDaysMax))
            // Forecast lead: the storm is announced today, begins tomorrow.
            let begins = context.current + .days(tuning.stormForecastLeadDays)
            add(kind: .storm(region: region), beginsAt: begins,
                endsAt: begins + .days(days), severity: severity,
                state: &state, context: context, isMajor: false)
            context.emit(.worldEventForecast(kind: .storm(region: region),
                                             beginsAt: begins))

            // A violent storm closes the region's most exposed big airport.
            if severity >= tuning.closureSeverityThreshold,
               let exposed = mostExposedAirport(in: region, catalog: context.catalog) {
                add(kind: .airportClosure(airport: exposed), beginsAt: begins,
                    endsAt: begins + .days(min(days, 2)), severity: severity,
                    state: &state, context: context, isMajor: false)
                context.emit(.worldEventForecast(
                    kind: .airportClosure(airport: exposed), beginsAt: begins))
            }
        }
    }

    private func triggerTourismBoom(_ state: inout GameState, context: SimContext,
                                    tuning: EventTuning) {
        guard regionalEventCount(state) < tuning.maxActiveRegionalEvents,
              !state.world.activeEvents.contains(where: {
                  if case .tourismBoom = $0.kind { true } else { false }
              }),
              state.rng.chance("events.boom", probability: tuning.tourismBoomDailyChance)
        else { return }
        let regions = WorldRegion.allCases.sorted { $0.rawValue < $1.rawValue }
        let region = regions[state.rng.int("events.boom.region", in: 0...(regions.count - 1))]
        let days = Int64(state.rng.int("events.boom.duration",
                                       in: tuning.tourismBoomDurationDaysMin...tuning.tourismBoomDurationDaysMax))
        add(kind: .tourismBoom(region: region), beginsAt: context.current,
            endsAt: context.current + .days(days), severity: tuning.tourismBoomBoost,
            state: &state, context: context, isMajor: false)
    }

    private func triggerStrikes(_ state: inout GameState, context: SimContext,
                                tuning: EventTuning) {
        for airlineID in state.orderedAirlineIDs {
            guard let airline = state.airlines[airlineID], airline.status == .active,
                  airline.reputation.service < tuning.strikeServiceThreshold,
                  !state.world.strikeActive(for: airlineID, at: context.current)
            else { continue }
            let cooldownKey = "strike.\(airlineID.raw)"
            if let last = state.world.eventCooldowns[cooldownKey],
               context.current.dayIndex - last < Int64(tuning.strikeCooldownDays) {
                continue
            }
            guard state.rng.chance("events.strike.\(airlineID.raw)",
                                   probability: tuning.strikeDailyChance) else { continue }
            let days = Int64(state.rng.int("events.strike.duration.\(airlineID.raw)",
                                           in: tuning.strikeDurationDaysMin...tuning.strikeDurationDaysMax))
            state.world.eventCooldowns[cooldownKey] = context.current.dayIndex
            add(kind: .strike(airline: airlineID), beginsAt: context.current,
                endsAt: context.current + .days(days), severity: 1,
                state: &state, context: context, isMajor: false)
        }
    }

    // MARK: Helpers

    private func add(kind: WorldEventKind, beginsAt: SimTime, endsAt: SimTime,
                     severity: Double, state: inout GameState, context: SimContext,
                     isMajor: Bool) {
        let id = state.world.nextEventID
        state.world.nextEventID += 1
        var event = WorldEvent(id: id, kind: kind, beginsAt: beginsAt,
                               endsAt: endsAt, severity: severity)
        if beginsAt <= context.current {
            event.hasStarted = true
            context.emit(.worldEventStarted(id: id, kind: kind))
        }
        state.world.activeEvents.append(event)
        if isMajor {
            state.world.eventCooldowns["major"] = context.current.dayIndex
        }
    }

    private func majorCooldownElapsed(_ state: GameState, tuning: EventTuning) -> Bool {
        guard let last = state.world.eventCooldowns["major"] else { return true }
        return state.clock.now.dayIndex - last >= Int64(tuning.majorEventCooldownDays)
    }

    private func regionalEventCount(_ state: GameState) -> Int {
        state.world.activeEvents.filter {
            switch $0.kind {
            case .storm, .tourismBoom, .airportClosure: true
            case .fuelShock, .strike: false
            }
        }.count
    }

    private func regionRiskFactor(_ region: WorldRegion, catalog: ContentCatalog) -> Double {
        var factor = 0.5
        for airport in catalog.airports(in: region) {
            let value: Double = switch airport.weatherRisk {
            case .low: 0.5
            case .moderate: 1.0
            case .high: 1.5
            case .severe: 2.2
            }
            factor = max(factor, value)
        }
        return factor
    }

    private func mostExposedAirport(in region: WorldRegion,
                                    catalog: ContentCatalog) -> AirportCode? {
        catalog.airports(in: region)
            .sorted {
                (riskRank($0.weatherRisk), $0.demographics.populationThousands, $0.code.raw)
                    > (riskRank($1.weatherRisk), $1.demographics.populationThousands, $1.code.raw)
            }
            .first?.code
    }

    private func riskRank(_ risk: WeatherRisk) -> Int {
        switch risk {
        case .low: 0
        case .moderate: 1
        case .high: 2
        case .severe: 3
        }
    }
}

public struct EventTuning: Equatable, Codable, Sendable {
    public let fuelShockDailyChance: Double
    public let fuelShockSeverityMin: Double
    public let fuelShockSeverityMax: Double
    public let fuelShockDurationDaysMin: Int
    public let fuelShockDurationDaysMax: Int
    public let stormBaseDailyChance: Double
    public let stormSeverityMin: Double
    public let stormSeverityMax: Double
    public let stormDurationDaysMin: Int
    public let stormDurationDaysMax: Int
    public let stormForecastLeadDays: Int64
    /// Extra dispatch-disruption probability at severity 1.
    public let stormDisruptionBoost: Double
    public let closureSeverityThreshold: Double
    public let tourismBoomDailyChance: Double
    public let tourismBoomBoost: Double
    public let tourismBoomDurationDaysMin: Int
    public let tourismBoomDurationDaysMax: Int
    public let strikeServiceThreshold: Double
    public let strikeDailyChance: Double
    public let strikeDurationDaysMin: Int
    public let strikeDurationDaysMax: Int
    public let strikeCooldownDays: Int
    public let maxActiveRegionalEvents: Int
    public let majorEventCooldownDays: Int

    public init(fuelShockDailyChance: Double, fuelShockSeverityMin: Double,
                fuelShockSeverityMax: Double, fuelShockDurationDaysMin: Int,
                fuelShockDurationDaysMax: Int, stormBaseDailyChance: Double,
                stormSeverityMin: Double, stormSeverityMax: Double,
                stormDurationDaysMin: Int, stormDurationDaysMax: Int,
                stormForecastLeadDays: Int64, stormDisruptionBoost: Double,
                closureSeverityThreshold: Double, tourismBoomDailyChance: Double,
                tourismBoomBoost: Double, tourismBoomDurationDaysMin: Int,
                tourismBoomDurationDaysMax: Int, strikeServiceThreshold: Double,
                strikeDailyChance: Double, strikeDurationDaysMin: Int,
                strikeDurationDaysMax: Int, strikeCooldownDays: Int,
                maxActiveRegionalEvents: Int, majorEventCooldownDays: Int) {
        self.fuelShockDailyChance = fuelShockDailyChance
        self.fuelShockSeverityMin = fuelShockSeverityMin
        self.fuelShockSeverityMax = fuelShockSeverityMax
        self.fuelShockDurationDaysMin = fuelShockDurationDaysMin
        self.fuelShockDurationDaysMax = fuelShockDurationDaysMax
        self.stormBaseDailyChance = stormBaseDailyChance
        self.stormSeverityMin = stormSeverityMin
        self.stormSeverityMax = stormSeverityMax
        self.stormDurationDaysMin = stormDurationDaysMin
        self.stormDurationDaysMax = stormDurationDaysMax
        self.stormForecastLeadDays = stormForecastLeadDays
        self.stormDisruptionBoost = stormDisruptionBoost
        self.closureSeverityThreshold = closureSeverityThreshold
        self.tourismBoomDailyChance = tourismBoomDailyChance
        self.tourismBoomBoost = tourismBoomBoost
        self.tourismBoomDurationDaysMin = tourismBoomDurationDaysMin
        self.tourismBoomDurationDaysMax = tourismBoomDurationDaysMax
        self.strikeServiceThreshold = strikeServiceThreshold
        self.strikeDailyChance = strikeDailyChance
        self.strikeDurationDaysMin = strikeDurationDaysMin
        self.strikeDurationDaysMax = strikeDurationDaysMax
        self.strikeCooldownDays = strikeCooldownDays
        self.maxActiveRegionalEvents = maxActiveRegionalEvents
        self.majorEventCooldownDays = majorEventCooldownDays
    }

    public static let standard = EventTuning(
        fuelShockDailyChance: 0.0025, fuelShockSeverityMin: 0.3,
        fuelShockSeverityMax: 0.9, fuelShockDurationDaysMin: 30,
        fuelShockDurationDaysMax: 90, stormBaseDailyChance: 0.004,
        stormSeverityMin: 0.3, stormSeverityMax: 1.0,
        stormDurationDaysMin: 1, stormDurationDaysMax: 3,
        stormForecastLeadDays: 1, stormDisruptionBoost: 0.3,
        closureSeverityThreshold: 0.85, tourismBoomDailyChance: 0.002,
        tourismBoomBoost: 0.35, tourismBoomDurationDaysMin: 60,
        tourismBoomDurationDaysMax: 120, strikeServiceThreshold: 0.35,
        strikeDailyChance: 0.02, strikeDurationDaysMin: 2,
        strikeDurationDaysMax: 4, strikeCooldownDays: 180,
        maxActiveRegionalEvents: 2, majorEventCooldownDays: 45)
}
