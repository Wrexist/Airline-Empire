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
    @Environment(\.dynamicTypeSize) private var typeSize
    let model: MapModel
    let snapshot: GameState

    var body: some View {
        VStack(spacing: AETheme.spacingS) {
            // Beside the speed control at reading sizes; above it at
            // accessibility sizes, where the two together are wider than any
            // phone.
            //
            // Both halves of this are things CI photographed rather than
            // things anybody reasoned out. AE-048 first put the cash on the
            // clock line, and run 171's frames showed the *date* wrapping to
            // "2030-" / "01-01" — a one-line bar became four (BUG-063). The
            // cash came out and the date was pinned with `fixedSize`, and run
            // 172's frames showed what *that* cost: a date that refuses to
            // compress makes this row wider than the screen, so the capsule
            // ran past its own margin and the `Spacer()` in the row below
            // pushed `MapZoomControls` — the only way to zoom without a pinch,
            // and therefore an accessibility control — clean off the right
            // edge (BUG-065). At AccessibilityL the same overflow put the
            // whole speed control off-screen.
            //
            // So: never wrap, never force a width. The date shrinks a little
            // before it does either, and at accessibility sizes the row stops
            // being a row.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AETheme.spacingS) {
                    clock
                    SpeedControl()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AETheme.spacingM)
                .padding(.vertical, AETheme.spacingS)
                .aeGlass(in: AETheme.cardShape)
            } else {
                HStack(spacing: AETheme.spacingS) {
                    clock
                    Spacer(minLength: AETheme.spacingS)
                    SpeedControl()
                }
                .padding(.horizontal, AETheme.spacingM)
                .padding(.vertical, AETheme.spacingS)
                .aeGlass(in: Capsule(style: .continuous))
            }

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

    /// The date over the clock. One line each, and allowed to shrink a little
    /// rather than wrap or force the row wider than the screen.
    private var clock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(Format.date(snapshot.currentDate))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())
                .aeAnimation(AEMotion.content, value: snapshot.currentDate.day)
            Text(Format.clock(snapshot.currentDate))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
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
            .buttonStyle(.aePress)
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
                        .buttonStyle(.aePress)
                        .accessibilityAddTraits(option == selection
                                                ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .frame(maxWidth: 250, alignment: .leading)
                .aeGlass(in: AETheme.cardShape)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .aeFeedback(.uiSelect, on: selection)
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
        .buttonStyle(.aePress)
        .accessibilityLabel(label)
    }
}

// MARK: - Selection

/// What the player selected. Nothing, when nothing is: the home briefing owns
/// the bottom of an unselected map (AE-048).
struct MapSelectionPanel: View {
    let selection: MapHit?
    let model: MapModel
    let snapshot: GameState
    /// The flight the camera is riding with, so the card can offer the
    /// opposite of whatever is happening.
    let followed: FlightID?
    let toggleFollow: (FlightID) -> Void
    let dismiss: () -> Void
    let openRoute: (FirstRouteSuggestion) -> Void

    var body: some View {
        Group {
            // `.some(...)` spelled out: this switches over an *optional*
            // `MapHit`, and being explicit about the layer costs one word and
            // removes a question.
            switch selection {
            case .some(.airport(let code)):
                if let airport = model.airports.first(where: { $0.code == code }) {
                    MapAirportCard(airport: airport, model: model, snapshot: snapshot,
                                   dismiss: dismiss, openRoute: openRoute)
                }
            case .some(.route(let id)):
                if let route = model.routes.first(where: { $0.id == id }) {
                    MapRouteCard(route: route, snapshot: snapshot, dismiss: dismiss)
                }
            case .some(.aircraft(let id)):
                if let flight = model.flights.first(where: { $0.id == id }) {
                    MapFlightCard(flight: flight, model: model, snapshot: snapshot,
                                  isFollowing: followed == flight.id,
                                  toggleFollow: { toggleFollow(flight.id) },
                                  dismiss: dismiss)
                }
            case .none:
                // Nothing. The home briefing owns the empty bottom now
                // (AE-048): one surface answers "what should I do", and it
                // is the one that can see the whole airline rather than only
                // the layer currently drawn.
                EmptyView()
            }
        }
        // A stable handle on "something is selected", so the journey that taps
        // an airport can prove the panel opened rather than photographing the
        // map and hoping. The identifier is on the selected states only: the
        // briefing below is not a selection and must not answer to the name.
        .accessibilityIdentifier(selection == nil ? "" : "ae-map-selection")
        .aeAnimation(AEMotion.content, value: selection)
    }
}

/// What the layer currently drawn has found, in one sentence.
///
/// Before AE-048 this was the map's whole answer to "what now" — it carried
/// the first-route invitation as well, because Home was a different screen and
/// the map had nobody to hand the question to. Home *is* the map now, and
/// `MapHomeBriefing` answers it from the whole airline rather than from one
/// overlay. What is left here is the thing only this panel can say: what the
/// layer you are looking at has found in the world underneath it.
struct MapOverlayHint: View {
    @Environment(GameController.self) private var controller
    let model: MapModel
    let overlay: MapOverlay

    var body: some View {
        if let hint {
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
            .accessibilityIdentifier("ae-map-overlay-hint")
        }
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
            // Nothing at all when the network is healthy. This used to fall
            // through to "Tap an airport, a route or an aircraft." — a line
            // that says nothing about the world and, since AE-048, sits
            // directly above a briefing that says what to do. Two rows of
            // chrome for one row of meaning is the map's own rule broken
            // (`MapChrome`: nothing permanent occupies the middle, and the
            // bottom is a consequence of what is happening).
            let grounded = mine.filter { $0.health == .grounded }.count
            guard grounded > 0 else { return nil }
            return Hint(icon: "pause.circle.fill",
                        text: "\(grounded) of your routes have no aircraft and are still paying fees.",
                        tint: AETheme.caution)
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
            // Shared *pairs* are the fight; shared airports are presence.
            // The old line counted airports, which reads as competition and
            // is not: no demand is shared at an airport (AE-037).
            if let summary = controller.competitionSummary, summary.contestedRoutes > 0 {
                let losing = summary.trailingRoutes
                return Hint(icon: "person.2.fill",
                            text: losing > 0
                                ? "\(summary.contestedRoutes) of your routes \(summary.contestedRoutes == 1 ? "is" : "are") contested — you are losing \(losing)."
                                : summary.contestedRoutes == 1
                                    ? "One of your routes is contested; you hold your own on it."
                                    : "\(summary.contestedRoutes) of your routes are contested; you hold your own on each.",
                            tint: losing > 0 ? AETheme.caution : AETheme.accent)
            }
            let shared = model.airports.filter {
                $0.servedByPlayer && $0.competitorCount > 0
            }.count
            return Hint(icon: "person.2.fill",
                        text: shared > 0
                            ? "Rivals fly from \(shared) of your airports, but not on your routes — yet."
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
