/// An actionable read of the fleet: what wants a decision, what cannot fly
/// today, and what a check is quoted to cost.
///
/// A flat list sorted by status tells a player the facts but not the order to
/// act in. This groups the same aircraft into the three questions a fleet
/// manager actually asks — *which aeroplane needs me now*, *which one is not
/// flyable at all*, and *which are simply working* — and ranks the first
/// group by what it costs to ignore.
///
/// It is pure: derived from the state, never written back to it, and quoting
/// the same `FleetEconomics` numbers `FleetSystem` will post when the check
/// happens. Nothing here estimates a replacement, a resale, or a future
/// schedule; those need their own authoritative work (docs/NEXT_SCREEN_REVAMPS_2026-09-15.md §2).
public struct FleetBoard: Equatable, Sendable {
    /// The whole fleet, most-in-need-of-attention first.
    public let rows: [Row]

    public init(rows: [Row]) { self.rows = rows }

    /// Flyable now, with something a player can act on.
    public var needsDecision: [Row] {
        rows.filter { $0.availability.isAvailable && !$0.issues.isEmpty }
    }
    /// Not flyable today — in a check or still on order. The player cannot
    /// fix this, so it is not a decision.
    public var unavailable: [Row] { rows.filter { !$0.availability.isAvailable } }
    /// Flyable, assigned, and nothing worth flagging.
    public var flying: [Row] {
        rows.filter {
            $0.availability.isAvailable && $0.issues.isEmpty && $0.card.assignedRoute != nil
        }
    }

    public var idleCount: Int { count(of: .idle) }
    public var lowConditionCount: Int { count(of: .lowCondition) }
    public var wornReliabilityCount: Int { count(of: .wornReliability) }
    public var leaseEndingCount: Int { count(of: .leaseEnding) }
    public var inCheckCount: Int { rows.filter { $0.availability.isInCheck }.count }
    public var onOrderCount: Int { rows.filter { $0.availability.isOnOrder }.count }

    /// Aircraft whose next check is estimated inside `checkSoonDays`.
    public var dueSoon: [Row] {
        rows.filter { ($0.checkDueInDays ?? .max) <= FleetAttentionThresholds.checkSoonDays }
    }
    /// What those checks are quoted at today, in total.
    public var dueSoonCost: Money {
        dueSoon.reduce(Money.zero) { $0 + $1.checkCost }
    }

    private func count(of issue: Issue) -> Int {
        rows.filter { $0.issues.contains(issue) }.count
    }

    /// One aeroplane on the board.
    public struct Row: Equatable, Sendable {
        /// The same card the fleet list and aircraft screen render, so the
        /// board cannot describe an aircraft differently from the list.
        public let card: FleetCardModel
        public let availability: Availability
        /// The route it flies, when it is assigned one, so a screen can name
        /// the pair without a second lookup.
        public let assignment: Assignment?
        /// Actionable concerns, most urgent first. Empty means nothing to do.
        public let issues: [Issue]
        /// Estimated whole days until the next scheduled check, at today's
        /// flying. Nil while the aircraft is not flyable (it is being checked,
        /// or not delivered), and zero when a check is already due.
        public let checkDueInDays: Int?
        /// What a check is quoted at today's age — the exact figure the fleet
        /// system posts when it grounds the airframe.
        public let checkCost: Money

        public init(card: FleetCardModel, availability: Availability,
                    assignment: Assignment?, issues: [Issue],
                    checkDueInDays: Int?, checkCost: Money) {
            self.card = card
            self.availability = availability
            self.assignment = assignment
            self.issues = issues
            self.checkDueInDays = checkDueInDays
            self.checkCost = checkCost
        }

        public var aircraftID: AircraftID { card.id }

        /// Months left on the lease, when it is leased. Nil for owned.
        public var leaseMonthsRemaining: Int? {
            if case .leased(_, let remaining) = card.ownershipDescription { return remaining }
            return nil
        }

        public var isUnavailable: Bool { !availability.isAvailable }
        public var isIdle: Bool { issues.contains(.idle) }
    }

    /// Where an assigned aircraft flies.
    public struct Assignment: Equatable, Sendable {
        public let routeID: RouteID
        public let origin: AirportCode
        public let destination: AirportCode
        public let dailyRoundTrips: Int

        public init(routeID: RouteID, origin: AirportCode,
                    destination: AirportCode, dailyRoundTrips: Int) {
            self.routeID = routeID
            self.origin = origin
            self.destination = destination
            self.dailyRoundTrips = dailyRoundTrips
        }
    }

    /// Whether the aeroplane can fly today, and if not, when it can.
    public enum Availability: Equatable, Sendable {
        case available
        case inCheck(until: SimTime)
        case onOrder(deliveryAt: SimTime)

        public var isAvailable: Bool { if case .available = self { true } else { false } }
        public var isInCheck: Bool { if case .inCheck = self { true } else { false } }
        public var isOnOrder: Bool { if case .onOrder = self { true } else { false } }

        /// When it becomes flyable, for the two statuses that are waiting on
        /// a date.
        public var availableAt: SimTime? {
            switch self {
            case .available: nil
            case .inCheck(let until): until
            case .onOrder(let deliveryAt): deliveryAt
            }
        }
    }

    /// A reason an available aircraft is on the board. Ordered by urgency,
    /// which is also the order a row names its chips in.
    public enum Issue: String, Equatable, Hashable, Sendable, CaseIterable {
        /// Airworthy, unassigned, and costing money to own.
        case idle
        /// Condition is closing on the check threshold.
        case lowCondition
        /// Reliability has fallen below its healthy band.
        case wornReliability
        /// The lease term is nearly up: keep, extend or return.
        case leaseEnding

        /// Lower sorts first. Idle burns cash today; a check is a cost
        /// coming; a worn airframe is a risk; a lease is a planned decision.
        var priority: Int {
            switch self {
            case .idle: 0
            case .lowCondition: 1
            case .leaseEnding: 2
            case .wornReliability: 3
            }
        }
    }
}

/// Classification thresholds for the board. Design constants, like
/// `AssignmentThresholds`: they classify what the simulation already knows,
/// they do not feed it, and each is wide enough that a healthy aeroplane
/// triggers nothing.
public enum FleetAttentionThresholds {
    /// Condition below this merits a look before it reaches the
    /// maintenance threshold of 0.75 that grounds the aircraft.
    public static let lowCondition = 0.80
    /// Reliability below this is a worn airframe. The floor is 0.85; the
    /// catalogue's baselines are 0.965–0.982, so this catches an aeroplane
    /// several years old rather than a new one.
    public static let wornReliability = 0.93
    /// A lease inside this many months of its term end is a decision coming.
    public static let leaseEndingMonths = 3
    /// A check estimated inside this many days is worth planning for.
    public static let checkSoonDays = 14
}

extension GameState {
    /// The fleet as a ranked board. Deterministic; built on `fleetCards` so
    /// the board and the list cannot describe one aircraft differently.
    public func fleetBoard(for airline: AirlineID, catalog: ContentCatalog) -> FleetBoard {
        let tuning = catalog.tuning.fleet
        let ops = catalog.tuning.ops

        let rows = fleetCards(for: airline, catalog: catalog).compactMap { card -> FleetBoard.Row? in
            guard let aircraft = aircraft[card.id],
                  let spec = catalog.aircraftType(card.typeCode) else { return nil }

            let availability: FleetBoard.Availability
            switch aircraft.status {
            case .active: availability = .available
            case .inMaintenance(let until): availability = .inCheck(until: until)
            case .ordered(let deliveryAt): availability = .onOrder(deliveryAt: deliveryAt)
            }

            let assignment: FleetBoard.Assignment?
            if let routeID = card.assignedRoute, let route = routes[routeID] {
                assignment = FleetBoard.Assignment(
                    routeID: routeID, origin: route.origin,
                    destination: route.destination, dailyRoundTrips: route.dailyRoundTrips)
            } else {
                assignment = nil
            }

            var issues: [FleetBoard.Issue] = []
            if availability.isAvailable {
                if card.assignedRoute == nil { issues.append(.idle) }
                if card.condition < FleetAttentionThresholds.lowCondition {
                    issues.append(.lowCondition)
                }
                if card.reliability < FleetAttentionThresholds.wornReliability {
                    issues.append(.wornReliability)
                }
            }
            if case .leased(_, let remaining) = card.ownershipDescription,
               remaining > 0, remaining <= FleetAttentionThresholds.leaseEndingMonths {
                issues.append(.leaseEnding)
            }
            issues.sort { $0.priority < $1.priority }

            // The check estimate only means something for an aircraft that can
            // fly. An airframe in the shop is already being checked; one on
            // order has no wear yet.
            var checkDueInDays: Int?
            if availability.isAvailable {
                var blockHours = 0.0
                if let routeID = card.assignedRoute, let route = routes[routeID],
                   let hours = FlightSchedulingSystem.blockHoursPerDay(
                    route: route, aircraftID: card.id, state: self, spec: spec, ops: ops) {
                    blockHours = hours
                }
                let decayPerDay = FleetEconomics.conditionPerDay(
                    blockHoursPerDay: blockHours, fleet: tuning, ops: ops)
                checkDueInDays = FleetEconomics.daysUntilCheck(
                    condition: card.condition, conditionPerDay: decayPerDay,
                    threshold: tuning.maintenanceConditionThreshold)
            }

            return FleetBoard.Row(
                card: card, availability: availability, assignment: assignment,
                issues: issues, checkDueInDays: checkDueInDays,
                checkCost: FleetEconomics.maintenanceCheckCost(
                    type: spec, ageYears: card.ageYears, tuning: tuning))
        }
        .sorted(by: rank)

        return FleetBoard(rows: rows)
    }

    /// Idle first, then the inspection concerns, then the airframes that
    /// cannot fly, then the working fleet. Within a rank, whichever check is
    /// soonest, then by id so the order is stable.
    private func rank(_ lhs: FleetBoard.Row, _ rhs: FleetBoard.Row) -> Bool {
        let left = Self.rank(lhs), right = Self.rank(rhs)
        if left != right { return left < right }
        let leftDays = lhs.checkDueInDays ?? Int.max
        let rightDays = rhs.checkDueInDays ?? Int.max
        if leftDays != rightDays { return leftDays < rightDays }
        return lhs.card.id < rhs.card.id
    }

    private static func rank(_ row: FleetBoard.Row) -> Int {
        if row.issues.contains(.idle) { return 0 }
        if row.issues.contains(.lowCondition) { return 1 }
        if row.issues.contains(.leaseEnding) { return 2 }
        if row.issues.contains(.wornReliability) { return 3 }
        if row.availability.isInCheck { return 4 }
        if row.availability.isOnOrder { return 5 }
        return 6
    }
}
