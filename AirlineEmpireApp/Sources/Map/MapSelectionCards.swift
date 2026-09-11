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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var expanded = false
    let airport: MapModel.MapAirport
    let model: MapModel
    let snapshot: GameState
    let dismiss: () -> Void
    let openRoute: (AirportCode) -> Void

    var body: some View {
        MapCardShell(title: "\(airport.city) · \(airport.code.raw)",
                     subtitle: "\(airport.country) · \(Vocab.region(airport.region))",
                     accent: accent, dismiss: dismiss) {
            HStack(spacing: AETheme.spacingS) {
                // The tier is the fact; it used to be the *label* over a bare
                // "\(prominence * 100)" — so Arlanda's panel read "6" above
                // the words "small field", a number of nothing under a
                // caption that was itself wrong (AE-033 audit §6.11).
                MapFact(label: "size", value: tierLabel, tint: .white)
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

            Button { expanded.toggle() } label: {
                Label(expanded ? "Collapse airport" : "Routes and aircraft",
                      systemImage: expanded ? "chevron.down" : "chevron.up")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.aePress)
            .accessibilityIdentifier("ae-airport-expand")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                Group {
                    if playerRoutes.count > 2 || (typeSize.isAccessibilitySize && !playerRoutes.isEmpty) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: AETheme.spacingS) { actions }
                        }
                        .frame(maxHeight: 220)
                    } else {
                        VStack(alignment: .leading, spacing: AETheme.spacingS) { actions }
                    }
                }
                .transition(.opacity)
            }
        }
        .aeAnimation(AEMotion.content, value: expanded)
        .onChange(of: airport.code) { expanded = false }
    }

    private var accent: Color {
        airport.closed ? AETheme.negative
            : airport.isPlayerHome ? AETheme.ember
            : airport.servedByPlayer
                ? Vocab.liveryColor(snapshot.playerAirline?.livery ?? .default)
            : .white.opacity(0.4)
    }

    /// One word, because it sits in a four-across strip of compact facts.
    private var tierLabel: String {
        switch airport.tier {
        case .global: "global"
        case .major: "major"
        case .regional: "regional"
        case .small: "small"
        }
    }

    private var playerRoutes: [Route] {
        snapshot.playerAirline.map { player in
            snapshot.routes(of: player.id).filter {
                $0.origin == airport.code || $0.destination == airport.code
            }
        } ?? []
    }

    @ViewBuilder
    private var actions: some View {
        let mine = playerRoutes
        if !mine.isEmpty {
            ForEach(mine, id: \.id) { route in
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
        Button { openRoute(airport.code) } label: {
            Label(airport.servedByPlayer || airport.isPlayerHome
                  ? "Create a route from \(airport.code.raw)"
                  : "Create a route to \(airport.code.raw)",
                  systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity, minHeight: 44)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.aePrimary)
        .disabled(airport.closed)
        .accessibilityIdentifier("ae-airport-create-route")
        if let player = snapshot.playerAirline, airport.code != player.homeAirport,
           let market = model.opportunities.first(where: {
               $0.destination == airport.code || $0.origin == airport.code
           }) {
            Label("About \(Format.count(Int64(market.expectedDailyPassengers))) passengers a day in this market",
                  systemImage: "person.2")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

/// A flight, live: where it is, who is aboard, when it lands, and why it is
/// late if it is.
///
/// This is the map's reason to be watched (AE-046). It used to say a
/// percentage and "en route", which is the same sentence for a flight ten
/// minutes out of Stockholm and one on approach to Cairo. Everything added
/// here is a fact the simulation already had and the map had never asked for:
/// the seats sold on this leg, the arrival its schedule implies, and the
/// weather over either end when the departure slipped.
struct MapFlightCard: View {
    let flight: MapModel.MapFlight
    let model: MapModel
    let snapshot: GameState
    let isFollowing: Bool
    let toggleFollow: () -> Void
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
                        MapFact(label: arrivalLabel, value: arrivalValue,
                                tint: flight.delayMinutes > 20
                                    ? AETheme.caution : .white)
                        if !flight.isFerry {
                            MapFact(label: "aboard",
                                    value: Format.count(Int64(flight.passengers)))
                        }
                    }
                    ProgressView(value: flight.progress)
                        .tint(Vocab.liveryColor(flight.livery))
                }
            }
            // The leg, in the terms a tracker is read in: how far it is, and
            // when it lands on the game's own clock.
            Text(legDetail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            if flight.delayMinutes > 0 {
                Label(delayLine, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AETheme.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if flight.isFerry {
                Label("Repositioning flight — no passengers aboard.",
                      systemImage: "arrow.triangle.swap")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            // Following is offered for anyone's aircraft, not only the
            // player's: watching a rival cross your market is worth as much
            // as watching your own, and costs nothing to allow.
            // Offered while it is flying, and kept while the camera is riding
            // with it: a flight that lands mid-follow would otherwise take
            // the only control that stops the camera away with it.
            if flight.airborne || isFollowing {
                Button(action: toggleFollow) {
                    HStack {
                        Label(isFollowing ? "Stop following" : "Follow this flight",
                              systemImage: isFollowing ? "xmark.circle" : "scope")
                            .font(.caption.weight(.semibold))
                        Spacer()
                    }
                    .foregroundStyle(isFollowing ? .white : accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.aePress)
                .accessibilityIdentifier("ae-map-follow")
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

    /// Minutes from now until this leg is on the ground. Negative means the
    /// schedule has been overtaken — the aircraft is still flying past the
    /// time it was due — which is a thing that happens and must read as
    /// "any minute now" rather than as a negative number.
    private var minutesToArrival: Int64 {
        flight.arrival.rawMinutes - snapshot.clock.now.rawMinutes
    }

    private var arrivalLabel: String {
        flight.airborne ? "lands in" : "status"
    }

    private var arrivalValue: String {
        guard flight.airborne else { return "on stand" }
        return minutesToArrival <= 0 ? "any minute"
                                     : Format.duration(minutes: minutesToArrival)
    }

    private var legDetail: String {
        let distance = "\(Format.count(Int64(flight.distanceKm))) km"
        guard flight.airborne else { return distance }
        let clock = Format.clock(GameCalendar.date(at: flight.arrival,
                                                   startYear: snapshot.meta.startYear))
        return "\(distance) · lands \(clock)"
    }

    private var delayLine: String {
        let late = "\(Format.duration(minutes: flight.delayMinutes)) behind schedule"
        guard let context = flight.delayContext else { return late }
        return "\(late) · \(Vocab.delayContext(context))"
    }
}
