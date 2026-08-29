import SwiftUI
import AirlineEmpireCore

/// The three selection cards (docs/MAP_ARCHITECTURE.md §10).
///
/// Selecting something on a strategy map should answer a question and offer a
/// move. Each card is built the same way: what it is, how it is doing, and the
/// one or two things you can do about it from here — with everything read from
/// `MapModel` and `GameState`, never re-derived.

private struct MapCardShell<Content: View>: View {
    let title: String
    let subtitle: String
    let accent: Color
    let dismiss: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingS) {
            HStack(alignment: .top, spacing: AETheme.spacingS) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 3)
                    .frame(maxHeight: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: AETheme.spacingS)
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.aePress)
                .accessibilityLabel("Clear selection")
            }
            content
        }
        .padding(AETheme.spacingM)
        .aeGlass(in: AETheme.cardShape)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// A compact fact, used across all three cards so they read as one system.
private struct MapFact: View {
    let label: String
    let value: String
    var tint: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}

// MARK: - Airport

struct MapAirportCard: View {
    @Environment(GameController.self) private var controller
    let airport: MapModel.MapAirport
    let model: MapModel
    let snapshot: GameState
    let dismiss: () -> Void
    let openRoute: (FirstRouteSuggestion) -> Void

    var body: some View {
        MapCardShell(title: "\(airport.city) · \(airport.code.raw)",
                     subtitle: "\(airport.country) · \(Vocab.region(airport.region))",
                     accent: accent, dismiss: dismiss) {
            HStack(spacing: AETheme.spacingS) {
                MapFact(label: tierLabel, value: "\(Int(airport.prominence * 100))",
                        tint: .white)
                MapFact(label: "slots used",
                        value: Format.percent(airport.slotPressure),
                        tint: airport.slotPressure > 0.85 ? AETheme.caution : .white)
                MapFact(label: "your routes", value: "\(airport.playerRouteCount)",
                        tint: airport.playerRouteCount > 0
                            ? Vocab.liveryColor(snapshot.playerAirline?.livery ?? .default)
                            : .white.opacity(0.6))
                MapFact(label: "rivals", value: "\(airport.competitorCount)",
                        tint: airport.competitorCount > 0 ? AETheme.rivalRoute : .white)
            }

            if airport.closed {
                Label("Closed — nothing operates here until it reopens.",
                      systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(AETheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            } else if airport.competitorHubCount > 0 {
                Label(airport.competitorHubCount == 1
                      ? "A rival is based here."
                      : "\(airport.competitorHubCount) rivals are based here.",
                      systemImage: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(AETheme.rivalRoute)
            }

            actions
        }
    }

    private var accent: Color {
        airport.closed ? AETheme.negative
            : airport.isPlayerHome ? AETheme.ember
            : airport.servedByPlayer
                ? Vocab.liveryColor(snapshot.playerAirline?.livery ?? .default)
            : .white.opacity(0.4)
    }

    private var tierLabel: String {
        switch airport.tier {
        case .global: "global hub"
        case .major: "major"
        case .regional: "regional"
        case .small: "small field"
        }
    }

    @ViewBuilder
    private var actions: some View {
        let mine = snapshot.playerAirline.map { player in
            snapshot.routes(of: player.id).filter {
                $0.origin == airport.code || $0.destination == airport.code
            }
        } ?? []
        if !mine.isEmpty {
            ForEach(mine.prefix(3), id: \.id) { route in
                NavigationLink(value: route.id) {
                    HStack {
                        Text("\(route.origin.raw) – \(route.destination.raw)")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
            }
        }
        if let player = snapshot.playerAirline, airport.code != player.homeAirport,
           let market = model.opportunities.first(where: {
               $0.destination == airport.code || $0.origin == airport.code
           }) {
            Button {
                openRoute(FirstRouteSuggestion(
                    origin: market.origin, destination: market.destination,
                    destinationCity: airport.city, distanceKm: market.distanceKm,
                    expectedDailyPassengers: market.expectedDailyPassengers,
                    referenceFare: market.referenceFare))
            } label: {
                Label("Open a route here — about \(Format.count(Int64(market.expectedDailyPassengers))) passengers a day",
                      systemImage: "plus.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AETheme.positive)
                    .frame(minHeight: 44)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.aePress)
        }
    }
}

// MARK: - Route

struct MapRouteCard: View {
    let route: MapModel.MapRoute
    let snapshot: GameState
    let dismiss: () -> Void

    var body: some View {
        MapCardShell(title: "\(route.origin.raw) – \(route.destination.raw)",
                     subtitle: subtitle, accent: accent, dismiss: dismiss) {
            HStack(spacing: AETheme.spacingS) {
                MapFact(label: "load", value: Format.percent(route.loadFactor),
                        tint: route.loadFactor > 0.7 ? AETheme.positive : AETheme.caution)
                MapFact(label: "per day", value: "\(route.dailyRoundTrips)×")
                if let real = snapshot.routes[route.id] {
                    MapFact(label: "this month",
                            value: Format.money(real.economicsThisMonth.directOperatingProfit),
                            tint: real.economicsThisMonth.directOperatingProfit.isNegative
                                ? AETheme.negative : AETheme.positive)
                    MapFact(label: "fare", value: Format.money(real.ticketPrice))
                }
            }
            Text(healthAdvice)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(value: route.id) {
                HStack {
                    Text("Open route detail").font(.caption.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .foregroundStyle(.white)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
    }

    private var subtitle: String {
        let carrier = snapshot.airlines[route.airline]?.name ?? "A rival"
        return route.isPlayer ? "Your route" : carrier
    }

    private var accent: Color {
        switch route.health {
        case .grounded: AETheme.mutedText
        case .disrupted: AETheme.negative
        case .weak: AETheme.caution
        case .healthy, .strong: Vocab.liveryColor(route.livery)
        }
    }

    private var healthAdvice: String {
        switch route.health {
        case .grounded:
            "No aircraft assigned. This route is paying its airport fees and flying nothing."
        case .disrupted:
            "Disrupted — an airport on this route is closed, or too many flights are being cancelled."
        case .weak:
            "Underperforming: losing money or flying half-empty. Try a lower fare, or fewer rotations."
        case .healthy:
            "Operating normally."
        case .strong:
            "Full and profitable. More frequency here would likely pay."
        }
    }
}

// MARK: - Aircraft

struct MapFlightCard: View {
    let flight: MapModel.MapFlight
    let model: MapModel
    let snapshot: GameState
    let dismiss: () -> Void

    var body: some View {
        MapCardShell(title: title, subtitle: subtitle, accent: accent,
                     dismiss: dismiss) {
            HStack(spacing: AETheme.spacingM) {
                AircraftShape(category: flight.category)
                    .fill(Vocab.liveryColor(flight.livery))
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AETheme.spacingXS) {
                    HStack(spacing: AETheme.spacingS) {
                        MapFact(label: "progress",
                                value: Format.percent(flight.progress))
                        MapFact(label: "status", value: statusText,
                                tint: flight.delayMinutes > 20
                                    ? AETheme.caution : .white)
                    }
                    ProgressView(value: flight.progress)
                        .tint(Vocab.liveryColor(flight.livery))
                }
            }
            if flight.isFerry {
                Label("Repositioning flight — no passengers aboard.",
                      systemImage: "arrow.triangle.swap")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            if flight.isPlayer {
                NavigationLink(value: flight.aircraft) {
                    HStack {
                        Text("Open aircraft").font(.caption.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
            }
        }
    }

    private var title: String {
        "\(flight.origin.raw) → \(flight.destination.raw)"
    }

    private var subtitle: String {
        let carrier = flight.isPlayer
            ? (snapshot.playerAirline?.name ?? "Your airline")
            : (snapshot.airlines[flight.airline]?.name ?? "A rival")
        return "\(carrier) · \(Vocab.category(flight.category))"
    }

    private var accent: Color { Vocab.liveryColor(flight.livery) }

    private var statusText: String {
        if !flight.airborne { return "on stand" }
        if flight.delayMinutes > 20 { return "\(flight.delayMinutes) min late" }
        return "en route"
    }
}
