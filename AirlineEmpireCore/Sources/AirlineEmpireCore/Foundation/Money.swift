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
}
