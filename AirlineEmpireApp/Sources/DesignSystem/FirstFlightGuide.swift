import SwiftUI
import AirlineEmpireCore

/// One progress model shared by the map, route setup and aircraft market.
struct FirstFlightProgress: View {
    @Environment(GameController.self) private var controller

    var compact = false

    var body: some View {
        if let state = controller.snapshot, let catalog = controller.catalog,
           let model = state.onboardingModel(catalog: catalog, suggestionLimit: 0),
           !model.isComplete {
            VStack(alignment: .leading, spacing: AETheme.spacingXS) {
                HStack {
                    Text("Your first flight").font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(model.completed.count) of \(OnboardingModel.Step.allCases.count) complete")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(model.completed.count),
                             total: Double(OnboardingModel.Step.allCases.count))
                    .tint(AETheme.accent)
                if !compact, let step = model.nextStep {
                    Text(Vocab.onboardingStep(step))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ae-first-flight-progress")
            .aeAnimation(AEMotion.content, value: model.completed.count)
        }
    }
}

/// Describes actual scheduled flights rather than promising a departure.
struct RouteFlightStatus: View {
    @Environment(GameController.self) private var controller
    let routeID: RouteID
    let viewOnMap: () -> Void

    var body: some View {
        if let state = controller.snapshot, let route = state.routes[routeID],
           !route.assignedAircraft.isEmpty {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                Label(title(state: state, route: route), systemImage: "airplane.departure")
                    .font(.subheadline.weight(.semibold))
                Text(RouteScheduleSummary.text(
                    flights: state.flights.values.filter { $0.route == routeID },
                    now: state.clock.now,
                    paused: controller.speed == .paused,
                    hasOperationalAircraft: route.assignedAircraft.contains {
                        state.aircraft[$0]?.isOperational == true
                    }))
                    .font(.caption).foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ae-route-schedule-summary")
                DisclosureGroup("Schedule details") {
                    Text(detail(state: state, route: route))
                        .font(.caption).foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .font(.caption)
                .tint(AETheme.mutedText)
                if controller.speed == .paused {
                    Button("Resume flights", systemImage: "play.fill") { controller.setSpeed(.x1) }
                        .buttonStyle(.aePrimary)
                        .accessibilityIdentifier("ae-route-resume-flights")
                }
                Button("View on map", systemImage: "map", action: viewOnMap)
                    .buttonStyle(.aeSecondary)
                    .accessibilityIdentifier("ae-route-view-map")
            }
            .padding(AETheme.spacingM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .aeClay(in: AETheme.cardShape)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ae-route-flight-status")
        }
    }

    private func title(state: GameState, route: Route) -> String {
        if controller.speed == .paused { return "Aircraft assigned - Paused" }
        if state.flights.values.contains(where: { flight in
            guard flight.route == routeID else { return false }
            if case .enRoute = flight.phase { return true }
            return false
        }) { return "Flying" }
        if route.assignedAircraft.contains(where: { state.aircraft[$0]?.isOperational == true }) {
            return "Waiting for departure"
        }
        return "Waiting for aircraft readiness"
    }

    private func detail(state: GameState, route: Route) -> String {
        let next = state.flights.values.filter {
            guard $0.route == routeID else { return false }
            switch $0.phase { case .scheduled, .boarding: return true; default: return false }
        }.min { $0.departureTime < $1.departureTime }
        if let next {
            let minutes = max(0, next.departureTime.rawMinutes - state.clock.now.rawMinutes)
            return "Next scheduled departure: \(next.from.raw) to \(next.to.raw), in \(Format.duration(minutes: minutes)) of game time. Delays may change this."
        }
        if state.flights.values.contains(where: {
            guard $0.route == routeID else { return false }
            if case .enRoute = $0.phase { return true }
            return false
        }) {
            return "Your aircraft is in the air. Follow the route on the map; ticket revenue is recorded after landing."
        }
        if !route.assignedAircraft.contains(where: { state.aircraft[$0]?.isOperational == true }) {
            return "Your aircraft is assigned. Check its delivery or maintenance status below before it can fly."
        }
        return "The schedule updates at midnight. Keep time running to dispatch available aircraft; ticket revenue is recorded when flights land."
    }
}

/// A concise, always-visible explanation of what the route is waiting for.
/// Uses game time and planned departures; it never promises a takeoff.
enum RouteScheduleSummary {
    static func text(flights: [Flight], now: SimTime, paused: Bool,
                     hasOperationalAircraft: Bool) -> String {
        let next = flights.filter {
            switch $0.phase {
            case .scheduled, .boarding: return true
            default: return false
            }
        }.min { $0.departureTime < $1.departureTime }
        if let next {
            let minutes = next.departureTime.rawMinutes - now.rawMinutes
            if minutes <= 0 {
                return paused ? "Departure pending. Resume time to continue."
                    : "Departure pending. Check schedule details for delays."
            }
            // "1h 14m", not "74 game minutes": a duration is read at a glance.
            let timing = "Next planned departure in \(Format.duration(minutes: minutes)) of game time."
            return paused ? timing + " Time is paused." : timing
        }
        if flights.contains(where: {
            if case .enRoute = $0.phase { return true }
            return false
        }) {
            return paused ? "Flight paused in the air. Resume time to continue."
                : "Aircraft in flight. Revenue is recorded after landing."
        }
        if !hasOperationalAircraft {
            return "Check delivery or maintenance before this route can fly."
        }
        return paused ? "Resume time; schedules update at midnight."
            : "Schedules update at midnight. Keep time running."
    }
}
