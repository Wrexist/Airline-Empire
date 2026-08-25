import Foundation

/// Immutable, validated game content (docs/ARCHITECTURE.md §6). Loaded once
/// at startup; passed by reference; never part of `GameState` — saves refer
/// to content by stable codes.
public final class ContentCatalog: Sendable {
    public let version: String
    public let airports: [AirportCode: AirportSpec]
    public let seasonality: [SeasonalityCode: SeasonalityProfile]
    public let aircraftTypes: [AircraftTypeCode: AircraftTypeSpec]
    public let tuning: Tuning

    /// Codes in stable sorted order — the iteration order for any
    /// deterministic sweep.
    public let orderedAirportCodes: [AirportCode]
    public let orderedAircraftTypeCodes: [AircraftTypeCode]

    /// Empty catalog for kernel-only tests and tooling.
    public static let empty = try! ContentCatalog(
        version: "empty", airports: [], seasonality: [], aircraftTypes: [],
        tuning: .standard)

    public init(version: String, airports: [AirportSpec],
                seasonality: [SeasonalityProfile],
                aircraftTypes: [AircraftTypeSpec] = [],
                tuning: Tuning) throws {
        var airportMap: [AirportCode: AirportSpec] = [:]
        var seasonMap: [SeasonalityCode: SeasonalityProfile] = [:]
        var typeMap: [AircraftTypeCode: AircraftTypeSpec] = [:]
        var problems: [String] = []

        for type in aircraftTypes {
            if typeMap[type.code] != nil {
                problems.append("Duplicate aircraft type: \(type.code)")
            }
            if type.seats <= 0 || type.rangeKm <= 0 || type.cruiseSpeedKmh <= 0 {
                problems.append("Aircraft type \(type.code) has non-positive performance figures")
            }
            if type.fuelBurnKgPerKm <= 0 || !type.fuelBurnKgPerKm.isFinite {
                problems.append("Aircraft type \(type.code) has invalid fuel burn")
            }
            if type.listPrice <= .zero || type.leaseMonthly <= .zero
                || type.maintenancePerFlightHour <= .zero {
                problems.append("Aircraft type \(type.code) has non-positive economics")
            }
            if type.leaseMonthly.cents * 12 * 8 > type.listPrice.cents * 2 {
                problems.append("Aircraft type \(type.code) lease rate implausible vs list price")
            }
            if !(0.5...1.0).contains(type.reliabilityBaseline)
                || !(0.0...1.0).contains(type.comfortBaseline) {
                problems.append("Aircraft type \(type.code) has out-of-range indices")
            }
            if type.crewCockpit <= 0 || type.crewCabin < 0
                || type.turnaroundMinutes <= 0 || type.deliveryLeadDays < 0 {
                problems.append("Aircraft type \(type.code) has invalid crew/turnaround/lead values")
            }
            typeMap[type.code] = type
        }

        for profile in seasonality {
            if seasonMap[profile.code] != nil {
                problems.append("Duplicate seasonality profile: \(profile.code)")
            }
            if profile.leisureMonthly.count != 12 {
                problems.append("Profile \(profile.code) has \(profile.leisureMonthly.count) months")
            }
            if !profile.leisureMonthly.allSatisfy({ $0 > 0 && $0.isFinite }) {
                problems.append("Profile \(profile.code) has non-positive multipliers")
            }
            seasonMap[profile.code] = profile
        }

        for airport in airports {
            if airportMap[airport.code] != nil {
                problems.append("Duplicate airport code: \(airport.code)")
            }
            if airport.code.raw.isEmpty || airport.name.isEmpty {
                problems.append("Airport with empty code or name: \(airport.code)")
            }
            if !airport.coordinate.isValid {
                problems.append("Airport \(airport.code) has invalid coordinates")
            }
            if airport.slotCapacityPerDay <= 0 || airport.terminalCapacityPerDay <= 0 {
                problems.append("Airport \(airport.code) has non-positive capacity")
            }
            if airport.movementFee.isNegative || airport.passengerFee.isNegative {
                problems.append("Airport \(airport.code) has negative fees")
            }
            if !airport.demographics.indicesValid || airport.demographics.populationThousands <= 0 {
                problems.append("Airport \(airport.code) has invalid demographics")
            }
            if !(-14 * 60...14 * 60).contains(airport.utcOffsetMinutes) {
                problems.append("Airport \(airport.code) has impossible UTC offset")
            }
            if seasonMap[airport.seasonality] == nil {
                problems.append("Airport \(airport.code) references unknown seasonality \(airport.seasonality)")
            }
            airportMap[airport.code] = airport
        }

        guard problems.isEmpty else {
            throw ContentError.invalid(problems)
        }
        self.version = version
        self.airports = airportMap
        self.seasonality = seasonMap
        self.aircraftTypes = typeMap
        self.tuning = tuning
        self.orderedAirportCodes = airportMap.keys.sorted()
        self.orderedAircraftTypeCodes = typeMap.keys.sorted()
    }

    public func aircraftType(_ code: AircraftTypeCode) -> AircraftTypeSpec? {
        aircraftTypes[code]
    }

    // MARK: Lookup

    public func airport(_ code: AirportCode) -> AirportSpec? {
        airports[code]
    }

    public func airports(in region: WorldRegion) -> [AirportSpec] {
        orderedAirportCodes.compactMap { airports[$0] }.filter { $0.region == region }
    }

    /// Distance between two known airports, whole km.
    public func distanceKm(_ a: AirportCode, _ b: AirportCode) -> Int? {
        guard let sa = airports[a], let sb = airports[b] else { return nil }
        return Geo.distanceKm(from: sa.coordinate, to: sb.coordinate)
    }

    /// Nearest other airports by great-circle distance, ascending.
    public func nearestAirports(to code: AirportCode, limit: Int) -> [(AirportSpec, Int)] {
        guard let origin = airports[code] else { return [] }
        return orderedAirportCodes
            .compactMap { airports[$0] }
            .filter { $0.code != code }
            .map { ($0, Geo.distanceKm(from: origin.coordinate, to: $0.coordinate)) }
            .sorted { ($0.1, $0.0.code) < ($1.1, $1.0.code) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Route eligibility

    /// Static-world eligibility of a route (docs/AIRPORTS.md). Dynamic
    /// constraints (slots free today, aircraft availability) are checked by
    /// the systems that own that state.
    public func routeEligibility(from origin: AirportCode, to destination: AirportCode,
                                 aircraftRangeKm: Int,
                                 aircraftRunwayRequirement: RunwayClass) -> [RouteIneligibility] {
        var reasons: [RouteIneligibility] = []
        guard let a = airports[origin] else { return [.unknownAirport(origin)] }
        guard let b = airports[destination] else { return [.unknownAirport(destination)] }
        if origin == destination {
            return [.sameAirport]
        }
        let distance = Geo.distanceKm(from: a.coordinate, to: b.coordinate)
        if distance < tuning.minRouteDistanceKm {
            reasons.append(.belowMinimumDistance(distance: distance, minimum: tuning.minRouteDistanceKm))
        }
        if distance > aircraftRangeKm {
            reasons.append(.beyondAircraftRange(distance: distance, range: aircraftRangeKm))
        }
        if a.runwayClass < aircraftRunwayRequirement {
            reasons.append(.runwayTooSmall(airport: origin, has: a.runwayClass, needs: aircraftRunwayRequirement))
        }
        if b.runwayClass < aircraftRunwayRequirement {
            reasons.append(.runwayTooSmall(airport: destination, has: b.runwayClass, needs: aircraftRunwayRequirement))
        }
        return reasons
    }
}

public enum RouteIneligibility: Equatable, Sendable {
    case unknownAirport(AirportCode)
    case sameAirport
    case belowMinimumDistance(distance: Int, minimum: Int)
    case beyondAircraftRange(distance: Int, range: Int)
    case runwayTooSmall(airport: AirportCode, has: RunwayClass, needs: RunwayClass)
}

public enum ContentError: Error, Sendable {
    case invalid([String])
    case missingResource(String)
}

/// World-level balance constants (docs/GAME_BALANCE.md; content, not code).
public struct Tuning: Equatable, Codable, Sendable {
    /// Routes shorter than this are ground-transport territory.
    public let minRouteDistanceKm: Int
    public let fleet: FleetTuning
    public let ops: OpsTuning
    public let demand: DemandTuning

    public init(minRouteDistanceKm: Int, fleet: FleetTuning = .standard,
                ops: OpsTuning = .standard, demand: DemandTuning = .standard) {
        self.minRouteDistanceKm = minRouteDistanceKm
        self.fleet = fleet
        self.ops = ops
        self.demand = demand
    }

    /// Code-side defaults matching shipping content; content files override.
    public static let standard = Tuning(minRouteDistanceKm: 80)
}

/// Demand-engine constants (docs/ECONOMY.md documents each and the
/// calibration behind them).
public struct DemandTuning: Equatable, Codable, Sendable {
    public let gravityConstant: Double
    public let attenuationScaleKm: Double
    public let attenuationPower: Double
    public let businessWeight: Double
    public let leisureWeight: Double
    /// Exponential price-utility slopes around the reference fare.
    public let priceSensitivityBusiness: Double
    public let priceSensitivityLeisure: Double
    /// Reference fare = fareBase + farePerKm x distance.
    public let fareBase: Double
    public let farePerKm: Double
    /// Weight of "don't travel" in the share denominator.
    public let outsideOptionWeight: Double
    public let scheduleQualityTripCap: Int
    public let scheduleQualityReferenceTrips: Double
    public let scheduleQualityExponent: Double
    public let comfortBase: Double
    public let comfortWeight: Double
    public let operationsBase: Double
    public let operationsWeight: Double
    /// Monday-first weekday factors (7 entries, mean ~1).
    public let weekdayBusinessFactor: [Double]
    public let weekdayLeisureFactor: [Double]
    public let economyBusinessExponent: Double
    public let economyLeisureExponent: Double

    public init(gravityConstant: Double, attenuationScaleKm: Double,
                attenuationPower: Double, businessWeight: Double, leisureWeight: Double,
                priceSensitivityBusiness: Double, priceSensitivityLeisure: Double,
                fareBase: Double, farePerKm: Double, outsideOptionWeight: Double,
                scheduleQualityTripCap: Int, scheduleQualityReferenceTrips: Double,
                scheduleQualityExponent: Double, comfortBase: Double, comfortWeight: Double,
                operationsBase: Double, operationsWeight: Double,
                weekdayBusinessFactor: [Double], weekdayLeisureFactor: [Double],
                economyBusinessExponent: Double, economyLeisureExponent: Double) {
        self.gravityConstant = gravityConstant
        self.attenuationScaleKm = attenuationScaleKm
        self.attenuationPower = attenuationPower
        self.businessWeight = businessWeight
        self.leisureWeight = leisureWeight
        self.priceSensitivityBusiness = priceSensitivityBusiness
        self.priceSensitivityLeisure = priceSensitivityLeisure
        self.fareBase = fareBase
        self.farePerKm = farePerKm
        self.outsideOptionWeight = outsideOptionWeight
        self.scheduleQualityTripCap = scheduleQualityTripCap
        self.scheduleQualityReferenceTrips = scheduleQualityReferenceTrips
        self.scheduleQualityExponent = scheduleQualityExponent
        self.comfortBase = comfortBase
        self.comfortWeight = comfortWeight
        self.operationsBase = operationsBase
        self.operationsWeight = operationsWeight
        self.weekdayBusinessFactor = weekdayBusinessFactor
        self.weekdayLeisureFactor = weekdayLeisureFactor
        self.economyBusinessExponent = economyBusinessExponent
        self.economyLeisureExponent = economyLeisureExponent
    }

    public static let standard = DemandTuning(
        gravityConstant: 0.55, attenuationScaleKm: 3000, attenuationPower: 1.2,
        businessWeight: 0.35, leisureWeight: 0.65,
        priceSensitivityBusiness: 1.2, priceSensitivityLeisure: 2.2,
        fareBase: 35, farePerKm: 0.085, outsideOptionWeight: 1.0,
        scheduleQualityTripCap: 6, scheduleQualityReferenceTrips: 4.0,
        scheduleQualityExponent: 0.35, comfortBase: 0.85, comfortWeight: 0.3,
        operationsBase: 0.7, operationsWeight: 0.3,
        weekdayBusinessFactor: [1.2, 1.2, 1.2, 1.2, 1.1, 0.5, 0.7],
        weekdayLeisureFactor: [0.9, 0.9, 0.9, 0.9, 1.15, 1.25, 1.2],
        economyBusinessExponent: 1.5, economyLeisureExponent: 0.8)
}

/// Flight-operations constants (docs/ROUTES.md documents each).
public struct OpsTuning: Equatable, Codable, Sendable {
    /// Minute-of-day the operating day starts (first departures).
    public let operatingDayStartMinute: Int64
    /// Length of the scheduling window per day.
    public let operatingDayMinutes: Int64
    public let boardingMinutes: Int64
    /// Climb/descent/taxi overhead added to cruise time.
    public let flightOverheadMinutes: Int64
    /// Delay drawn uniformly from this range on a dispatch disruption.
    public let delayMinutesMin: Int
    public let delayMinutesMax: Int
    /// Of dispatch disruptions, this share cancels outright (rest delay).
    public let cancellationShareOfDisruptions: Double
    public let crewCostPerBlockHourCockpit: Money
    public let crewCostPerBlockHourCabin: Money
    public let baseFuelPricePerKg: Money
    /// Condition lost per flight hour (on top of daily decay).
    public let wearPerFlightHour: Double
    /// A scheduled flight that could not board (aircraft grounded/busy) is
    /// cancelled this long after its planned departure — no stale-flight
    /// pileups, no burst-flying when an aircraft returns to service.
    public let scheduledFlightExpiryMinutes: Int64

    public init(operatingDayStartMinute: Int64, operatingDayMinutes: Int64,
                boardingMinutes: Int64, flightOverheadMinutes: Int64,
                delayMinutesMin: Int, delayMinutesMax: Int,
                cancellationShareOfDisruptions: Double,
                crewCostPerBlockHourCockpit: Money, crewCostPerBlockHourCabin: Money,
                baseFuelPricePerKg: Money, wearPerFlightHour: Double,
                scheduledFlightExpiryMinutes: Int64) {
        self.operatingDayStartMinute = operatingDayStartMinute
        self.operatingDayMinutes = operatingDayMinutes
        self.boardingMinutes = boardingMinutes
        self.flightOverheadMinutes = flightOverheadMinutes
        self.delayMinutesMin = delayMinutesMin
        self.delayMinutesMax = delayMinutesMax
        self.cancellationShareOfDisruptions = cancellationShareOfDisruptions
        self.crewCostPerBlockHourCockpit = crewCostPerBlockHourCockpit
        self.crewCostPerBlockHourCabin = crewCostPerBlockHourCabin
        self.baseFuelPricePerKg = baseFuelPricePerKg
        self.wearPerFlightHour = wearPerFlightHour
        self.scheduledFlightExpiryMinutes = scheduledFlightExpiryMinutes
    }

    public static let standard = OpsTuning(
        operatingDayStartMinute: 6 * 60, operatingDayMinutes: 18 * 60,
        boardingMinutes: 30, flightOverheadMinutes: 20,
        delayMinutesMin: 45, delayMinutesMax: 240,
        cancellationShareOfDisruptions: 0.2,
        crewCostPerBlockHourCockpit: Money.dollars(180),
        crewCostPerBlockHourCabin: Money.dollars(45),
        baseFuelPricePerKg: Money(cents: 65), wearPerFlightHour: 0.00035,
        scheduledFlightExpiryMinutes: 240)
}

/// Fleet economy constants (docs/AIRCRAFT.md documents each).
public struct FleetTuning: Equatable, Codable, Sendable {
    public let annualDepreciationRate: Double
    public let residualValueFraction: Double
    public let saleFriction: Double
    public let usedPriceConditionFloor: Double
    public let usedMarketConditionFloor: Double
    public let usedMarketConditionLossPerYear: Double
    public let maxUsedPurchaseAgeYears: Int
    public let dailyConditionDecay: Double
    public let maintenanceConditionThreshold: Double
    public let maintenanceCheckDays: Int
    public let maintenanceCheckHoursEquivalent: Double
    public let maintenanceAgeCostGrowthPerYear: Double
    public let reliabilityConditionWeight: Double
    public let reliabilityAgePenaltyPerYear: Double
    public let reliabilityFloor: Double
    public let minLeaseTermMonths: Int
    public let maxLeaseTermMonths: Int
    public let earlyLeaseReturnPenaltyMonths: Int

    public init(annualDepreciationRate: Double, residualValueFraction: Double,
                saleFriction: Double, usedPriceConditionFloor: Double,
                usedMarketConditionFloor: Double, usedMarketConditionLossPerYear: Double,
                maxUsedPurchaseAgeYears: Int, dailyConditionDecay: Double,
                maintenanceConditionThreshold: Double, maintenanceCheckDays: Int,
                maintenanceCheckHoursEquivalent: Double,
                maintenanceAgeCostGrowthPerYear: Double,
                reliabilityConditionWeight: Double, reliabilityAgePenaltyPerYear: Double,
                reliabilityFloor: Double, minLeaseTermMonths: Int, maxLeaseTermMonths: Int,
                earlyLeaseReturnPenaltyMonths: Int) {
        self.annualDepreciationRate = annualDepreciationRate
        self.residualValueFraction = residualValueFraction
        self.saleFriction = saleFriction
        self.usedPriceConditionFloor = usedPriceConditionFloor
        self.usedMarketConditionFloor = usedMarketConditionFloor
        self.usedMarketConditionLossPerYear = usedMarketConditionLossPerYear
        self.maxUsedPurchaseAgeYears = maxUsedPurchaseAgeYears
        self.dailyConditionDecay = dailyConditionDecay
        self.maintenanceConditionThreshold = maintenanceConditionThreshold
        self.maintenanceCheckDays = maintenanceCheckDays
        self.maintenanceCheckHoursEquivalent = maintenanceCheckHoursEquivalent
        self.maintenanceAgeCostGrowthPerYear = maintenanceAgeCostGrowthPerYear
        self.reliabilityConditionWeight = reliabilityConditionWeight
        self.reliabilityAgePenaltyPerYear = reliabilityAgePenaltyPerYear
        self.reliabilityFloor = reliabilityFloor
        self.minLeaseTermMonths = minLeaseTermMonths
        self.maxLeaseTermMonths = maxLeaseTermMonths
        self.earlyLeaseReturnPenaltyMonths = earlyLeaseReturnPenaltyMonths
    }

    public static let standard = FleetTuning(
        annualDepreciationRate: 0.08, residualValueFraction: 0.25,
        saleFriction: 0.10, usedPriceConditionFloor: 0.70,
        usedMarketConditionFloor: 0.55, usedMarketConditionLossPerYear: 0.02,
        maxUsedPurchaseAgeYears: 22, dailyConditionDecay: 0.0006,
        maintenanceConditionThreshold: 0.75, maintenanceCheckDays: 3,
        maintenanceCheckHoursEquivalent: 60, maintenanceAgeCostGrowthPerYear: 0.045,
        reliabilityConditionWeight: 0.1, reliabilityAgePenaltyPerYear: 0.003,
        reliabilityFloor: 0.85, minLeaseTermMonths: 6, maxLeaseTermMonths: 144,
        earlyLeaseReturnPenaltyMonths: 2)
}

// MARK: Loading from bundled resources

extension ContentCatalog {
    struct AirportsFile: Codable {
        let version: String
        let airports: [AirportSpec]
    }

    struct SeasonalityFile: Codable {
        let profiles: [SeasonalityProfile]
    }

    struct AircraftFile: Codable {
        let types: [AircraftTypeSpec]
    }

    /// Loads and validates the shipped content. Fails loudly on any defect
    /// (docs/ARCHITECTURE.md §6): broken content is a build/test failure,
    /// never a runtime surprise.
    public static func loadBundled() throws -> ContentCatalog {
        let decoder = JSONDecoder()
        let airportsFile = try decoder.decode(AirportsFile.self, from: resourceData("airports"))
        let seasonalityFile = try decoder.decode(SeasonalityFile.self, from: resourceData("seasonality"))
        let aircraftFile = try decoder.decode(AircraftFile.self, from: resourceData("aircraft"))
        let tuning = try decoder.decode(Tuning.self, from: resourceData("tuning"))
        return try ContentCatalog(version: airportsFile.version,
                                  airports: airportsFile.airports,
                                  seasonality: seasonalityFile.profiles,
                                  aircraftTypes: aircraftFile.types,
                                  tuning: tuning)
    }

    private static func resourceData(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw ContentError.missingResource("\(name).json")
        }
        return try Data(contentsOf: url)
    }
}
