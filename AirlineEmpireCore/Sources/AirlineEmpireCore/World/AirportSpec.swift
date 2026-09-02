/// Static airport definition, loaded from content
/// (docs/DOMAIN_MODEL.md §2 content entities). Runtime airport state (slot
/// allocations, disruptions) lives in `WorldState`, never here.
public struct AirportSpec: Equatable, Codable, Sendable {
    public let code: AirportCode
    public let name: String
    public let city: String
    public let country: String
    public let region: WorldRegion
    public let coordinate: Coordinate
    /// Fixed UTC offset in minutes (no DST — deliberate simplification,
    /// consistent with the game calendar).
    public let utcOffsetMinutes: Int
    public let runwayClass: RunwayClass
    /// Aircraft movements (departure or arrival counts as one) per day the
    /// airport can host across all airlines.
    public let slotCapacityPerDay: Int
    /// Passengers per day the terminals can process.
    public let terminalCapacityPerDay: Int
    /// Per-movement fee (landing + handling), before per-passenger fees.
    public let movementFee: Money
    /// Per-departing-passenger fee.
    public let passengerFee: Money
    public let demographics: Demographics
    public let seasonality: SeasonalityCode
    public let weatherRisk: WeatherRisk

    public init(code: AirportCode, name: String, city: String, country: String,
                region: WorldRegion, coordinate: Coordinate, utcOffsetMinutes: Int,
                runwayClass: RunwayClass, slotCapacityPerDay: Int,
                terminalCapacityPerDay: Int, movementFee: Money, passengerFee: Money,
                demographics: Demographics, seasonality: SeasonalityCode,
                weatherRisk: WeatherRisk) {
        self.code = code
        self.name = name
        self.city = city
        self.country = country
        self.region = region
        self.coordinate = coordinate
        self.utcOffsetMinutes = utcOffsetMinutes
        self.runwayClass = runwayClass
        self.slotCapacityPerDay = slotCapacityPerDay
        self.terminalCapacityPerDay = terminalCapacityPerDay
        self.movementFee = movementFee
        self.passengerFee = passengerFee
        self.demographics = demographics
        self.seasonality = seasonality
        self.weatherRisk = weatherRisk
    }

    /// What one movement of `type` costs here: the quoted fee in
    /// proportion to the aircraft's seats over the reference cabin
    /// (`OpsTuning.movementFeeReferenceSeats`). Integer cents, so the
    /// ledger and the AI's estimate are the same arithmetic. The one place
    /// the size of what lands enters the fee (AE-040).
    public func movementFee(for type: AircraftTypeSpec, ops: OpsTuning) -> Money {
        Money(cents: movementFee.cents * Int64(type.seats) / Int64(ops.movementFeeReferenceSeats))
    }
}

/// Market characteristics that drive demand (Phase 7 consumes these).
public struct Demographics: Equatable, Codable, Sendable {
    /// Metro population in thousands.
    public var populationThousands: Int
    /// 0...1: strength of business travel generation (HQ density, finance).
    public var businessIndex: Double
    /// 0...1: propensity of residents to travel for leisure.
    public var leisureIndex: Double
    /// 0...1: attractiveness as a destination (tourism draw).
    public var tourismIndex: Double
    /// 0...1: cargo market strength (reserved for the cargo expansion seam).
    public var cargoIndex: Double

    public init(populationThousands: Int, businessIndex: Double, leisureIndex: Double,
                tourismIndex: Double, cargoIndex: Double) {
        self.populationThousands = populationThousands
        self.businessIndex = businessIndex
        self.leisureIndex = leisureIndex
        self.tourismIndex = tourismIndex
        self.cargoIndex = cargoIndex
    }

    var indicesValid: Bool {
        [businessIndex, leisureIndex, tourismIndex, cargoIndex]
            .allSatisfy { (0.0...1.0).contains($0) }
    }
}

/// Longest-runway capability, ordered: an airport serves an aircraft whose
/// requirement is <= its class.
public enum RunwayClass: String, Codable, Sendable, CaseIterable, Comparable {
    case small       // turboprops
    case medium      // regional jets
    case large       // narrowbodies
    case veryLarge   // widebodies and up

    private var rank: Int {
        switch self {
        case .small: 0
        case .medium: 1
        case .large: 2
        case .veryLarge: 3
        }
    }

    public static func < (lhs: RunwayClass, rhs: RunwayClass) -> Bool {
        lhs.rank < rhs.rank
    }
}

public enum WorldRegion: String, Codable, Sendable, CaseIterable {
    case northAmerica
    case southAmerica
    case europe
    case middleEast
    case africa
    case southAsia
    case eastAsia
    case southeastAsia
    case oceania
}

public enum WeatherRisk: String, Codable, Sendable, CaseIterable {
    case low        // rare disruption
    case moderate   // seasonal storms
    case high       // frequent fog/snow/monsoon exposure
    case severe     // hurricane/typhoon belt
}

public enum SeasonalityTag: Sendable {}
public typealias SeasonalityCode = ContentCode<SeasonalityTag>

/// Monthly demand multipliers for the leisure segment (business demand is
/// far flatter and is shaped in the demand model itself, Phase 7).
public struct SeasonalityProfile: Equatable, Codable, Sendable {
    public let code: SeasonalityCode
    /// Exactly 12 values, January first; 1.0 = neutral month.
    public let leisureMonthly: [Double]

    public init(code: SeasonalityCode, leisureMonthly: [Double]) {
        self.code = code
        self.leisureMonthly = leisureMonthly
    }

    public func leisureMultiplier(month: Int) -> Double {
        precondition((1...12).contains(month))
        return leisureMonthly[month - 1]
    }
}
