/// Exact game currency: Int64 cents. Floating point never stores balances
/// (docs/ARCHITECTURE.md §5); Double enters only through the single rounding
/// initializer below.
public struct Money: Hashable, Codable, Comparable, Sendable, AdditiveArithmetic {
    public var cents: Int64

    public init(cents: Int64) {
        self.cents = cents
    }

    /// Whole game-dollars convenience.
    public static func dollars(_ d: Int64) -> Money { Money(cents: d * 100) }

    public static let zero = Money(cents: 0)

    /// The project-wide rounding choke point for Double-valued economic
    /// math entering the ledger: round half away from zero, so gains and
    /// losses are treated symmetrically.
    public init(rounding amount: Double) {
        precondition(amount.isFinite, "Non-finite amount entering Money")
        self.cents = Int64((amount * 100).rounded(.toNearestOrAwayFromZero))
    }

    public var asDouble: Double { Double(cents) / 100 }

    public static func + (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents + rhs.cents) }
    public static func - (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents - rhs.cents) }
    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.cents < rhs.cents }
    public static prefix func - (value: Money) -> Money { Money(cents: -value.cents) }

    /// Integer scaling (counts × unit price). Double scaling must go
    /// through `Money(rounding:)` explicitly at the call site.
    public static func * (lhs: Money, rhs: Int64) -> Money { Money(cents: lhs.cents * rhs) }
    public static func * (lhs: Int64, rhs: Money) -> Money { rhs * lhs }

    public var isNegative: Bool { cents < 0 }

    /// A compact human rendering — `$110.0M`, `$790k`, `$1,234` — for the
    /// few places Core itself speaks to the player: rejection messages.
    ///
    /// Core used to interpolate `cents / 100` there, and the market rendered
    /// "Need 110000000 for this aircraft" under a blocked offer — spotted in
    /// the first screenshot that ever showed a blocked market row (BUG-037).
    /// The thresholds mirror the app's `Format.money`, so a number in a
    /// refusal reads like every other number on the same screen. Deliberately
    /// a named property rather than `CustomStringConvertible`: nothing that
    /// interpolates a Money by accident should silently get a formatted
    /// string it did not ask for.
    public var compact: String {
        let dollars = Double(cents) / 100
        let magnitude = abs(dollars)
        let sign = dollars < 0 ? "−" : ""
        func decimal(_ value: Double, places: Int) -> String {
            String(format: "%.\(places)f", value)
        }
        switch magnitude {
        case 1_000_000_000...:
            return "\(sign)$\(decimal(magnitude / 1_000_000_000, places: 2))B"
        case 1_000_000...:
            return "\(sign)$\(decimal(magnitude / 1_000_000, places: 1))M"
        case 10_000...:
            return "\(sign)$\(decimal(magnitude / 1_000, places: 0))k"
        default:
            let whole = Int64(magnitude.rounded())
            var digits = "\(whole)", grouped = ""
            while digits.count > 3 {
                grouped = "," + digits.suffix(3) + grouped
                digits = String(digits.dropLast(3))
            }
            return "\(sign)$\(digits)\(grouped)"
        }
    }
}
