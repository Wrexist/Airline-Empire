import Foundation

/// Geographic math for the world layer.
public enum Geo {
    /// Mean Earth radius in km (physical constant, not tuning).
    static let earthRadiusKm = 6371.0

    /// Great-circle distance, quantized to whole kilometers.
    ///
    /// Quantization is deliberate: trig comes from libm, whose last-ulp
    /// behavior can differ across platforms; whole-km results make the
    /// value save- and determinism-safe (docs/SIMULATION_ARCHITECTURE.md §2).
    public static func distanceKm(from a: Coordinate, to b: Coordinate) -> Int {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(h.squareRoot(), (1 - h).squareRoot())
        return Int((earthRadiusKm * c).rounded())
    }
}

public struct Coordinate: Hashable, Codable, Sendable {
    /// Degrees, positive north. Valid range -90...90.
    public var latitude: Double
    /// Degrees, positive east. Valid range -180...180.
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        (-90.0...90.0).contains(latitude) && (-180.0...180.0).contains(longitude)
    }
}
