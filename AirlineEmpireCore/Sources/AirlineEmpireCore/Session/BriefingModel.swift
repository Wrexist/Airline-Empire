/// The briefing's decision hierarchy, in one pure value: what needs the
/// player now, how the airline is doing, and — from the screen's own
/// sections — what to do next and what already happened.
///
/// The *order* is the product decision. A briefing is something handed to a
/// player before they go back to the world, so it must lead with the thing
/// that is costing them, then how they are doing, then the opportunity, then
/// the history. That order lives here rather than in a view's body, and every
/// number is read from the read models that already own it — nothing is
/// recomputed, so the briefing cannot disagree with the screen a number
/// opens.
public struct BriefingModel: Equatable, Sendable {
    /// What needs the player now, most urgent first. An empty stack is a
    /// real, common answer: a cozy builder is allowed to have nothing to nag
    /// about.
    public let alerts: [Alert]
    /// How the airline is doing, from the three summaries the rest of the app
    /// already publishes.
    public let performance: Performance
    /// The first-session arc's next step, while it is still running; nil once
    /// the arc is complete.
    public let firstSession: OnboardingModel.Step?

    public var isFirstSessionComplete: Bool { firstSession == nil }

    public init(alerts: [Alert], performance: Performance,
                firstSession: OnboardingModel.Step?) {
        self.alerts = alerts
        self.performance = performance
        self.firstSession = firstSession
    }

    public struct Performance: Equatable, Sendable {
        public let dashboard: DashboardModel
        public let network: NetworkSummary
        public let fleet: FleetSummary

        public init(dashboard: DashboardModel, network: NetworkSummary,
                    fleet: FleetSummary) {
            self.dashboard = dashboard
            self.network = network
            self.fleet = fleet
        }
    }

    /// One thing that wants the player, with how alarmed to be and the facts
    /// behind it. The words are presentation's; this is the state.
    public struct Alert: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// Below the overdraft floor (`danger`) or close to it (`watch`).
            case insolvency(daysUntilAdministration: Int?, fatal: Bool)
            /// Airworthy, unassigned, and billing like a flying aircraft.
            case idleAircraft(count: Int)
            /// Open routes with nothing assigned — capacity holding slots and
            /// earning nothing.
            case groundedRoutes(count: Int)
            /// Routes whose month to date is a loss.
            case losingRoutes(count: Int)

            public var isInsolvency: Bool {
                if case .insolvency = self { true } else { false }
            }

            public var isGroundedRoutes: Bool {
                if case .groundedRoutes = self { true } else { false }
            }

            public var isLosingRoutes: Bool {
                if case .losingRoutes = self { true } else { false }
            }
        }

        public enum Severity: Int, Comparable, Sendable {
            /// Worth knowing; act when you get to it.
            case watch = 0
            /// Costing money today.
            case warning
            /// The airline may not survive it.
            case critical

            public static func < (lhs: Self, rhs: Self) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }

        public let kind: Kind
        public let severity: Severity

        public init(kind: Kind, severity: Severity) {
            self.kind = kind
            self.severity = severity
        }
    }
}

extension GameState {
    /// The briefing, or nil when there is no active airline to brief.
    ///
    /// Composed from `dashboardModel`, `networkSummary`, `fleetSummary`,
    /// `solvencyModel` and `onboardingModel`, so every figure on the briefing
    /// is the one the screen it links to will show.
    public func briefingModel(catalog: ContentCatalog) -> BriefingModel? {
        guard let player = playerAirline, player.status == .active,
              let dashboard = dashboardModel() else { return nil }
        let network = networkSummary(for: player.id)
        let fleet = fleetSummary(for: player.id)

        var alerts: [BriefingModel.Alert] = []
        if let solvency = solvencyModel(for: player.id, catalog: catalog) {
            switch solvency.stage {
            case .danger:
                alerts.append(.init(
                    kind: .insolvency(
                        daysUntilAdministration: solvency.daysUntilAdministration,
                        fatal: solvency.nextFailureIsFatal),
                    severity: .critical))
            case .watch:
                // `.watch` already folds in "overdrawn" and "less than three
                // months of runway", so one alert covers both.
                alerts.append(.init(
                    kind: .insolvency(daysUntilAdministration: nil,
                                      fatal: solvency.nextFailureIsFatal),
                    severity: .warning))
            case .healthy:
                break
            }
        }
        if fleet.idle > 0 {
            alerts.append(.init(kind: .idleAircraft(count: fleet.idle),
                                severity: .warning))
        }
        if network.idleRoutes > 0 {
            alerts.append(.init(kind: .groundedRoutes(count: network.idleRoutes),
                                severity: .warning))
        }
        if network.losingRoutes > 0 {
            alerts.append(.init(kind: .losingRoutes(count: network.losingRoutes),
                                severity: .watch))
        }
        alerts.sort { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return Self.alertRank(lhs.kind) < Self.alertRank(rhs.kind)
        }

        let onboarding = onboardingModel(catalog: catalog)
        let firstSession = (onboarding?.isComplete == false) ? onboarding?.nextStep : nil

        return BriefingModel(
            alerts: alerts,
            performance: .init(dashboard: dashboard, network: network, fleet: fleet),
            firstSession: firstSession)
    }

    /// The tie-break for equal severity: an airline that may die outranks an
    /// aircraft doing nothing, which outranks an empty route, which outranks
    /// a route merely losing money this month.
    private static func alertRank(_ kind: BriefingModel.Alert.Kind) -> Int {
        switch kind {
        case .insolvency: 0
        case .idleAircraft: 1
        case .groundedRoutes: 2
        case .losingRoutes: 3
        }
    }
}
