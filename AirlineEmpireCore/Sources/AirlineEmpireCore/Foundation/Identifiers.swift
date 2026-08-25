/// Typed identity (docs/DOMAIN_MODEL.md §1).
///
/// Runtime entities get `EntityID<Tag>` values from the save's monotonic
/// allocator — never UUIDs — so identity is deterministic and replay-stable.
/// Content entities use `ContentCode<Tag>` string codes from data files.
public struct EntityID<Tag>: Hashable, Codable, Comparable, Sendable {
    public let raw: Int64

    public init(raw: Int64) {
        self.raw = raw
    }

    public init(from decoder: Decoder) throws {
        raw = try decoder.singleValueContainer().decode(Int64.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.raw < rhs.raw }
}

public struct ContentCode<Tag>: Hashable, Codable, Comparable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible {
    public let raw: String

    public init(_ raw: String) {
        self.raw = raw
    }

    public init(stringLiteral value: String) {
        self.raw = value
    }

    public init(from decoder: Decoder) throws {
        raw = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.raw < rhs.raw }
    public var description: String { raw }
}

// Tag enums are uninhabited; they exist only to make IDs distinct types.
public enum AirlineTag: Sendable {}
public enum AircraftTag: Sendable {}
public enum RouteTag: Sendable {}
public enum FlightTag: Sendable {}
public enum AirportTag: Sendable {}
public enum AircraftTypeTag: Sendable {}
public enum ScenarioTag: Sendable {}

public typealias AirlineID = EntityID<AirlineTag>
public typealias AircraftID = EntityID<AircraftTag>
public typealias RouteID = EntityID<RouteTag>
public typealias FlightID = EntityID<FlightTag>
public typealias AirportCode = ContentCode<AirportTag>
public typealias AircraftTypeCode = ContentCode<AircraftTypeTag>
public typealias ScenarioCode = ContentCode<ScenarioTag>

/// Monotonic ID allocation, part of the save (docs/DOMAIN_MODEL.md §1).
public struct IDAllocator: Hashable, Codable, Sendable {
    public private(set) var nextByKind: [String: Int64]

    public init() {
        nextByKind = [:]
    }

    public mutating func allocate<Tag>(_ type: EntityID<Tag>.Type = EntityID<Tag>.self,
                                       kind: String) -> EntityID<Tag> {
        let next = nextByKind[kind, default: 1]
        nextByKind[kind] = next + 1
        return EntityID<Tag>(raw: next)
    }

    public mutating func allocateAirlineID() -> AirlineID { allocate(kind: "airline") }
    public mutating func allocateAircraftID() -> AircraftID { allocate(kind: "aircraft") }
    public mutating func allocateRouteID() -> RouteID { allocate(kind: "route") }
    public mutating func allocateFlightID() -> FlightID { allocate(kind: "flight") }
}

// Dictionary keys: with CodingKeyRepresentable, [EntityID: V] and
// [ContentCode: V] encode as JSON objects (string-keyed), which — combined
// with .sortedKeys — keeps every state encoding byte-deterministic.
// Without this, Codable encodes such dictionaries as flat arrays in
// dictionary iteration order, which is process-random and would break the
// stateHash determinism oracle.
extension EntityID: CodingKeyRepresentable {
    public var codingKey: any CodingKey { IndexKey(intValue: Int(raw)) }

    public init?<T: CodingKey>(codingKey: T) {
        // JSON object keys decode as strings even for numeric keys.
        if let value = codingKey.intValue {
            self.init(raw: Int64(value))
        } else if let value = Int64(codingKey.stringValue) {
            self.init(raw: value)
        } else {
            return nil
        }
    }
}

extension ContentCode: CodingKeyRepresentable {
    public var codingKey: any CodingKey { IndexKey(stringValue: raw) }

    public init?<T: CodingKey>(codingKey: T) {
        self.init(codingKey.stringValue)
    }
}

/// Minimal CodingKey carrier for the conformances above.
struct IndexKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
