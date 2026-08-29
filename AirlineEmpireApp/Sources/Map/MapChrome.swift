import SwiftUI
import AirlineEmpireCore

/// The interface around the map (docs/MAP_ARCHITECTURE.md §9).
///
/// The rule everything here follows: **the map is the screen**. Chrome floats
/// over it, never boxes it in, and nothing permanent occupies the middle. What
/// appears at the bottom is a consequence of what the player selected, so an
/// unselected map is almost entirely map.

// MARK: - Top bar

/// Date, speed, and the two things a player must not miss — money trouble and
/// a live disruption.
struct MapTopBar: View {
    @Environment(GameController.self) private var controller
    let model: MapModel
    let snapshot: GameState

    var body: some View {
        VStack(spacing: AETheme.spacingS) {
            HStack(spacing: AETheme.spacingS) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Format.date(snapshot.currentDate))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .aeAnimation(AEMotion.content, value: snapshot.currentDate.day)
                    Text(Format.clock(snapshot.currentDate))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: AETheme.spacingS)
                SpeedControl()
            }
            .padding(.horizontal, AETheme.spacingM)
            .padding(.vertical, AETheme.spacingS)
            .aeGlass(in: Capsule(style: .continuous))

            if let banner = worldBanner {
                HStack(spacing: AETheme.spacingXS) {
                    Image(systemName: banner.icon)
                        .font(.caption)
                        .accessibilityHidden(true)
                    Text(banner.text)
                        .font(.caption.weight(.medium))
                        .lineLimit(2)
                }
                .foregroundStyle(banner.tint)
                .padding(.horizontal, AETheme.spacingM)
                .padding(.vertical, AETheme.spacingS)
                .frame(maxWidth: .infinity, alignment: .leading)
                .aeGlass(in: Capsule(style: .continuous),
                         tint: banner.tint.opacity(0.22))
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
        .aeAnimation(AEMotion.content, value: worldBanner?.text ?? "")
    }

    private struct Banner {
        let icon: String
        let text: String
        let tint: Color
    }

    /// One line, and only when it earns the space. Solvency outranks weather:
    /// a storm costs a day, insolvency costs the game.
    private var worldBanner: Banner? {
        if let player = snapshot.playerAirline?.id, let catalog = controller.catalog,
           let solvency = snapshot.solvencyModel(for: player, catalog: catalog),
           solvency.stage == .danger {
            let days = solvency.daysUntilAdministration.map(Format.days) ?? "days"
            return Banner(icon: "exclamationmark.octagon.fill",
                          text: "Administration in \(days) — \(Format.money(solvency.cash))",
                          tint: AETheme.negative)
        }
        // The most consequential live event that actually touches the player.
        let touching = model.events
            .filter { $0.hasStarted && !$0.affectedPlayerRoutes.isEmpty }
            .sorted { $0.affectedPlayerRoutes.count > $1.affectedPlayerRoutes.count }
        if let event = touching.first {
            let count = event.affectedPlayerRoutes.count
            return Banner(icon: Vocab.worldEventIcon(event.kind),
                          text: "\(Vocab.worldEvent(event.kind, state: snapshot)) — \(count) of your routes",
                          tint: AETheme.caution)
        }
        return nil
    }
}

// MARK: - Overlay picker

/// One overlay at a time, each labelled with the question it answers.
struct MapOverlayPicker: View {
    @Binding var selection: MapOverlay
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingXS) {
            Button {
                withAnimation(AEMotion.selection) { expanded.toggle() }
            } label: {
                HStack(spacing: AETheme.spacingXS) {
                    Image(systemName: selection.icon).font(.caption)
                    Text(selection.title).font(.caption.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, AETheme.spacingM)
                .frame(minHeight: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .aeGlass(in: Capsule(style: .continuous))
            .accessibilityLabel("Map layer")
            .accessibilityValue(selection.title)
            .accessibilityHint(selection.question)

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(MapOverlay.allCases) { option in
                        Button {
                            withAnimation(AEMotion.selection) {
                                selection = option
                                expanded = false
                            }
                        } label: {
                            HStack(alignment: .top, spacing: AETheme.spacingS) {
                                Image(systemName: option.icon)
                                    .font(.caption)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(option.title)
                                        .font(.caption.weight(.semibold))
                                    Text(option.question)
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                                Spacer(minLength: 0)
                                if option == selection {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.weight(.bold))
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, AETheme.spacingM)
                            .padding(.vertical, AETheme.spacingS)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(option == selection
                                                ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .frame(maxWidth: 250, alignment: .leading)
                .aeGlass(in: AETheme.cardShape)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Zoom controls

/// Zoom without pinching — the only way this map is reachable for anyone who
/// cannot make that gesture.
struct MapZoomControls: View {
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let frame: () -> Void

    var body: some View {
        VStack(spacing: 1) {
            button("plus", "Zoom in", zoomIn)
            Divider().frame(width: 26).overlay(Color.white.opacity(0.2))
            button("minus", "Zoom out", zoomOut)
            Divider().frame(width: 26).overlay(Color.white.opacity(0.2))
            button("scope", "Frame my network", frame)
        }
        .aeGlass(in: RoundedRectangle(cornerRadius: AETheme.cornerRadiusSmall,
                                      style: .continuous))
    }

    private func button(_ icon: String, _ label: String,
                        _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Selection

/// What the player selected, or — when nothing is selected — the one thing
/// the map most wants to tell them.
struct MapSelectionPanel: View {
    @Environment(GameController.self) private var controller
    let selection: MapHit?
    let model: MapModel
    let snapshot: GameState
    let overlay: MapOverlay
    let dismiss: () -> Void
    let openRoute: (FirstRouteSuggestion) -> Void

    var body: some View {
        Group {
            switch selection {
            case .airport(let code):
                if let airport = model.airports.first(where: { $0.code == code }) {
                    MapAirportCard(airport: airport, model: model, snapshot: snapshot,
                                   dismiss: dismiss, openRoute: openRoute)
                }
            case .route(let id):
                if let route = model.routes.first(where: { $0.id == id }) {
                    MapRouteCard(route: route, snapshot: snapshot, dismiss: dismiss)
                }
            case .aircraft(let id):
                if let flight = model.flights.first(where: { $0.id == id }) {
                    MapFlightCard(flight: flight, model: model, snapshot: snapshot,
                                  dismiss: dismiss)
                }
            case .none:
                MapIdlePanel(model: model, overlay: overlay, openRoute: openRoute)
            }
        }
        .aeAnimation(AEMotion.content, value: selection)
    }
}

/// Nothing selected. Rather than an empty strip, the map says the most useful
/// true thing it can — which for a new airline is "here is where to begin",
/// and for an established one is what the current overlay found.
struct MapIdlePanel: View {
    let model: MapModel
    let overlay: MapOverlay
    let openRoute: (FirstRouteSuggestion) -> Void

    var body: some View {
        if model.routes.filter(\.isPlayer).isEmpty {
            emptyAirline
        } else if let hint {
            HStack(spacing: AETheme.spacingS) {
                Image(systemName: hint.icon)
                    .font(.caption)
                    .foregroundStyle(hint.tint)
                    .accessibilityHidden(true)
                Text(hint.text)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AETheme.spacingM)
            .padding(.vertical, AETheme.spacingS)
            .aeGlass(in: Capsule(style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    /// The early-game map used to be dots on a dark field with nothing to do.
    /// It is the first screen of a strategy game; it should be an invitation.
    private var emptyAirline: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingS) {
            HStack(spacing: AETheme.spacingS) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundStyle(AETheme.positive)
                    .accessibilityHidden(true)
                Text("Your airline begins here")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            Text("The dashed lines are the strongest markets from your home airport. Pick one to open your first route.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(model.opportunities.prefix(2).enumerated()), id: \.offset) { _, market in
                Button {
                    openRoute(FirstRouteSuggestion(
                        origin: market.origin, destination: market.destination,
                        destinationCity: "", distanceKm: market.distanceKm,
                        expectedDailyPassengers: market.expectedDailyPassengers,
                        referenceFare: market.referenceFare))
                } label: {
                    HStack {
                        Text("\(market.origin.raw) → \(market.destination.raw)")
                            .font(.caption.weight(.semibold))
                        Text("≈\(Format.count(Int64(market.expectedDailyPassengers))) passengers/day")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AETheme.spacingM)
        .aeGlass(in: AETheme.cardShape, tint: AETheme.positive.opacity(0.12))
    }

    private struct Hint {
        let icon: String
        let text: String
        let tint: Color
    }

    /// One sentence, chosen by what the overlay is for.
    private var hint: Hint? {
        let mine = model.routes.filter(\.isPlayer)
        switch overlay {
        case .network:
            let grounded = mine.filter { $0.health == .grounded }.count
            if grounded > 0 {
                return Hint(icon: "pause.circle.fill",
                            text: "\(grounded) of your routes have no aircraft and are still paying fees.",
                            tint: AETheme.caution)
            }
            return Hint(icon: "hand.tap",
                        text: "Tap an airport, a route or an aircraft.",
                        tint: .white.opacity(0.6))
        case .opportunity:
            guard let best = model.opportunities.first else { return nil }
            return Hint(icon: "sparkle",
                        text: "Best unopened market: \(best.origin.raw) → \(best.destination.raw), about \(Format.count(Int64(best.expectedDailyPassengers))) passengers a day.",
                        tint: AETheme.positive)
        case .profitability:
            let weak = mine.filter { $0.health <= .weak }.count
            return Hint(icon: weak > 0 ? "arrow.down.right" : "checkmark.circle",
                        text: weak > 0
                            ? "\(weak) of your routes are losing money or flying half-empty."
                            : "Every route is carrying its weight.",
                        tint: weak > 0 ? AETheme.caution : AETheme.positive)
        case .competition:
            let contested = model.airports.filter {
                $0.servedByPlayer && $0.competitorCount > 0
            }.count
            return Hint(icon: "person.2.fill",
                        text: contested > 0
                            ? "You share \(contested) of your airports with a rival."
                            : "Nobody else flies where you fly.",
                        tint: AETheme.accent)
        case .disruption:
            let live = model.events.filter { $0.hasStarted && !$0.affectedPlayerRoutes.isEmpty }
            return Hint(icon: live.isEmpty ? "sun.max" : "exclamationmark.triangle.fill",
                        text: live.isEmpty
                            ? "Nothing is disrupting your network right now."
                            : "\(live.count) world event\(live.count == 1 ? "" : "s") touching your routes.",
                        tint: live.isEmpty ? AETheme.positive : AETheme.caution)
        }
    }
}
