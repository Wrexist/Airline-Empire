/// Static aircraft type definition, loaded from content
/// (docs/DOMAIN_MODEL.md §2). Individual aircraft are runtime entities
/// referencing a type by code.
public struct AircraftTypeSpec: Equatable, Codable, Sendable {
    public let code: AircraftTypeCode
    public let manufacturer: String
    public let model: String
    public let category: AircraftCategory
    /// Standard single-class-equivalent seat count (cabin configuration
    /// choices arrive with Era III per PROGRESSION.md).
    public let seats: Int
    public let rangeKm: Int
    public let cruiseSpeedKmh: Int
    public let fuelBurnKgPerKm: Double
    public let listPrice: Money
    public let leaseMonthly: Money
    /// Maintenance reserve per flight hour at age 0 / full condition.
    public let maintenancePerFlightHour: Money
    public let crewCockpit: Int
    public let crewCabin: Int
    /// Dispatch reliability baseline at delivery (0…1); degrades with age
    /// and condition (docs/AIRCRAFT.md).
    public let reliabilityBaseline: Double
    public let runwayRequirement: RunwayClass
    /// Passenger comfort baseline (0…1); demand model input (Phase 7).
    public let comfortBaseline: Double
    public let turnaroundMinutes: Int
    /// Days between a new-aircraft order and delivery.
    public let deliveryLeadDays: Int

    public init(code: AircraftTypeCode, manufacturer: String, model: String,
                category: AircraftCategory, seats: Int, rangeKm: Int,
                cruiseSpeedKmh: Int, fuelBurnKgPerKm: Double, listPrice: Money,
                leaseMonthly: Money, maintenancePerFlightHour: Money,
                crewCockpit: Int, crewCabin: Int, reliabilityBaseline: Double,
                runwayRequirement: RunwayClass, comfortBaseline: Double,
                turnaroundMinutes: Int, deliveryLeadDays: Int) {
        self.code = code
        self.manufacturer = manufacturer
        self.model = model
        self.category = category
        self.seats = seats
        self.rangeKm = rangeKm
        self.cruiseSpeedKmh = cruiseSpeedKmh
        self.fuelBurnKgPerKm = fuelBurnKgPerKm
        self.listPrice = listPrice
        self.leaseMonthly = leaseMonthly
        self.maintenancePerFlightHour = maintenancePerFlightHour
        self.crewCockpit = crewCockpit
        self.crewCabin = crewCabin
        self.reliabilityBaseline = reliabilityBaseline
        self.runwayRequirement = runwayRequirement
        self.comfortBaseline = comfortBaseline
        self.turnaroundMinutes = turnaroundMinutes
        self.deliveryLeadDays = deliveryLeadDays
    }
}

public enum AircraftCategory: String, Codable, Sendable, CaseIterable {
    case turboprop
    case regionalJet
    case narrowbody
    case largeNarrowbody
    case widebody
    case largeWidebody
}
