import Foundation

/// Which aircraft may fly which route, and what it would mean if one did
/// (MASTER PROMPT 5 §23, §24).
///
/// Both assignment pickers in the app used to decide this for themselves, and
/// both got it wrong in the same way: they filtered on "unassigned and active"
/// and stopped. `AssignAircraftToRouteCommand` checks six things. The two the
/// UI missed — range and runway class — are exactly the ones a player cannot
/// work out by looking, so the app offered aeroplanes for routes they could
/// not reach and the command refused the tap that the app had just invited.
///
/// It was also wrong in the other direction. Core permits assigning an
/// aircraft that is in a maintenance check; the UI's `isActive` filter hid
/// those, so a grounded aeroplane could not be given its next job while it sat
/// in the hangar. One picker, too permissive and too restrictive at once,
/// which is what re-deriving another layer's rules tends to produce.
///
/// So the rules live here, next to the validator they mirror, and
/// `assignmentBlockersAgreeWithTheValidator` in the tests fails the day the
/// two disagree. The UI's job is to render this, never to recompute it.
public struct AssignmentCandidate: Equatable, Sendable {
    public let aircraftID: AircraftID
    public let routeID: RouteID
    /// Why Core would refuse. Nil means it would accept.
    public let blocker: Blocker?
    /// What is worth knowing about an assignment Core *would* accept.
    /// Nil when there is nothing the data supports saying.
    public let note: Note?

    public var isEligible: Bool { blocker == nil }

    /// Why the command would be rejected.
    ///
    /// One case per rejection `AssignAircraftToRouteCommand.validate` can
    /// return for a route and aircraft the player owns. Ownership itself is
    /// not represented: these are only ever built from one airline's own
    /// routes and fleet, so a foreign-owner blocker would be unreachable and
    /// an unreachable case invites a caller to handle a state that cannot
    /// happen.
    public enum Blocker: Equatable, Sendable {
        /// Still on order. Carries the date so a screen can say when.
        case notDelivered(deliveryAt: SimTime)
        /// Already flying something else.
        case alreadyAssigned(RouteID)
        /// The route is longer than the aeroplane can fly.
        case beyondRange(rangeKm: Int, distanceKm: Int)
        /// One end cannot take an aircraft this size. Names which end —
        /// "this route is unsuitable" is not something a player can act on,
        /// and the two ends are usually not equally replaceable.
        case runwayTooSmall(airport: AirportCode, needs: RunwayClass,
                            has: RunwayClass)
    }

    /// A fact about an allowed assignment, where the data supports one.
    ///
    /// Deliberately restrained, on the same reasoning as `RouteVerdict`: a
    /// signal that fires on every candidate ranks nothing, and one that
    /// guesses is worse than silence. Capacity notes are only emitted for a
    /// route the demand engine has actually priced — before the first daily
    /// tick every route reads as zero demand, and calling a brand-new route
    /// "far more seats than demand" on that basis would be an artefact of
    /// timing rather than a fact about the market.
    public enum Note: Equatable, Sendable {
        /// In a maintenance check. Core allows the assignment; the aeroplane
        /// simply cannot fly until the check finishes.
        case inMaintenance(until: SimTime)
        /// Legal, but with little room. A diversion or a headwind is a real
        /// operational risk the player should get to weigh.
        case tightRange(marginKm: Int)
        /// Demand well beyond what this aircraft can lift at the route's
        /// current frequency: passengers will be turned away.
        case seatsShortOfDemand(seatsPerDay: Int, demandPerDay: Int)
        /// Far more seats than the market wants: the aeroplane flies empty
        /// and the trip still costs full price.
        case seatsAboveDemand(seatsPerDay: Int, demandPerDay: Int)
        /// Comfortable range margin and capacity that suits the demand.
        /// Only claimed when both are actually known.
        case strongMatch
    }

    public init(aircraftID: AircraftID, routeID: RouteID,
                blocker: Blocker? = nil, note: Note? = nil) {
        self.aircraftID = aircraftID
        self.routeID = routeID
        self.blocker = blocker
        self.note = note
    }
}

/// Thresholds for the notes above.
///
/// These classify; they do not simulate. Nothing here feeds the engine, so
/// they live beside the classification rather than in `tuning.json`, which is
/// the balance surface. Each is wide enough that an ordinary assignment
/// triggers nothing.
enum AssignmentThresholds {
    /// A route using at least this share of an aircraft's range is "tight".
    /// At 0.9 a 3000 km aeroplane says nothing until the route passes 2700 km.
    static let tightRangeFraction = 0.9
    /// Seats must fall below this share of demand before we say so — a route
    /// that turns away a handful of passengers is normal and profitable.
    static let shortOfDemandFraction = 0.7
    /// ...and above this multiple of demand before we say the reverse.
    static let aboveDemandMultiple = 1.8
    /// Bands within which capacity counts as well matched for `strongMatch`.
    static let strongMatchLower = 0.85
    static let strongMatchUpper = 1.35
}

extension GameState {

    /// Every route of `airline` as a target for one aircraft.
    ///
    /// Returns the ineligible ones too, carrying their reason. A picker that
    /// silently omits them answers "why can't I see my new route here?" with
    /// nothing, which is how the old one hid every range and runway problem
    /// until the command refused.
    public func assignmentCandidates(forAircraft aircraftID: AircraftID,
                                     catalog: ContentCatalog)
        -> [AssignmentCandidate] {
        guard let aircraft = aircraft[aircraftID] else { return [] }
        return routes(of: aircraft.owner).map {
            candidate(aircraft: aircraft, route: $0, catalog: catalog)
        }
    }

    /// Every aircraft of the route's airline as a candidate for one route.
    public func assignmentCandidates(forRoute routeID: RouteID,
                                     catalog: ContentCatalog)
        -> [AssignmentCandidate] {
        guard let route = routes[routeID] else { return [] }
        return fleet(of: route.airline).map {
            candidate(aircraft: $0, route: route, catalog: catalog)
        }
    }

    /// The single pairing. Mirrors `AssignAircraftToRouteCommand.validate`.
    func candidate(aircraft: Aircraft, route: Route,
                   catalog: ContentCatalog) -> AssignmentCandidate {
        // Blocker order follows the validator's, so that when a pairing fails
        // for two reasons both agree on which one is reported.
        if let assigned = aircraft.assignedRoute {
            return AssignmentCandidate(aircraftID: aircraft.id, routeID: route.id,
                                       blocker: .alreadyAssigned(assigned))
        }
        if case .ordered(let deliveryAt) = aircraft.status {
            return AssignmentCandidate(aircraftID: aircraft.id, routeID: route.id,
                                       blocker: .notDelivered(deliveryAt: deliveryAt))
        }
        guard let spec = catalog.aircraftType(aircraft.typeCode) else {
            // No spec means no range and no runway class to check against, so
            // there is nothing honest to say about this pairing. The catalog
            // validates type references at load, so this is unreachable in a
            // real game; returning "eligible with no note" rather than
            // inventing a blocker keeps it from becoming a phantom refusal if
            // it ever does happen.
            return AssignmentCandidate(aircraftID: aircraft.id, routeID: route.id)
        }
        if route.distanceKm > spec.rangeKm {
            return AssignmentCandidate(
                aircraftID: aircraft.id, routeID: route.id,
                blocker: .beyondRange(rangeKm: spec.rangeKm,
                                      distanceKm: route.distanceKm))
        }
        for end in [route.origin, route.destination] {
            guard let airport = catalog.airport(end) else { continue }
            if airport.runwayClass < spec.runwayRequirement {
                return AssignmentCandidate(
                    aircraftID: aircraft.id, routeID: route.id,
                    blocker: .runwayTooSmall(airport: end,
                                             needs: spec.runwayRequirement,
                                             has: airport.runwayClass))
            }
        }
        return AssignmentCandidate(aircraftID: aircraft.id, routeID: route.id,
                                   note: note(aircraft: aircraft, route: route,
                                              spec: spec))
    }

    /// What is worth saying about a pairing Core would accept.
    private func note(aircraft: Aircraft, route: Route,
                      spec: AircraftTypeSpec) -> AssignmentCandidate.Note? {
        // Availability first: whether the aeroplane can fly at all this week
        // outranks how well it would suit the route if it could.
        if case .inMaintenance(let until) = aircraft.status {
            return .inMaintenance(until: until)
        }

        let margin = spec.rangeKm - route.distanceKm
        let tight = Double(route.distanceKm)
            >= AssignmentThresholds.tightRangeFraction * Double(spec.rangeKm)
        if tight { return .tightRange(marginKm: margin) }

        // Capacity, only where the demand engine has actually run. Both
        // directions, because a round trip carries both.
        let demandPerDay = route.demandOutboundToday + route.demandInboundToday
        guard demandPerDay > 0 else { return nil }
        // This aircraft's own contribution: one round trip is two legs of
        // `seats`. Frequency is the route's target across everything assigned,
        // so this is what adding *this* aeroplane offers, not the total.
        let seatsPerDay = spec.seats * route.dailyRoundTrips * 2
        let ratio = Double(seatsPerDay) / Double(demandPerDay)

        if ratio < AssignmentThresholds.shortOfDemandFraction {
            return .seatsShortOfDemand(seatsPerDay: seatsPerDay,
                                       demandPerDay: demandPerDay)
        }
        if ratio > AssignmentThresholds.aboveDemandMultiple {
            return .seatsAboveDemand(seatsPerDay: seatsPerDay,
                                     demandPerDay: demandPerDay)
        }
        if ratio >= AssignmentThresholds.strongMatchLower
            && ratio <= AssignmentThresholds.strongMatchUpper {
            return .strongMatch
        }
        // Between the bands: allowed, unremarkable, and nothing to say.
        return nil
    }
}
