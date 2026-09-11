import SwiftUI
import AirlineEmpireCore

/// The briefing (docs/ROADMAP_DIRECTION_II.md Phase 27 — AE-048).
///
/// The map is the home screen. This is the strip that makes it a *home*
/// rather than a diagram: who the player is (Layer 2 — the airline's state)
/// and what is worth doing (Layer 3 — one move, from real state), with
/// everything the dashboard used to hold one tap away behind the first row.
///
/// ## Nothing here is a second simulation
///
/// Every value is read from Core's own read models and nothing is recomputed:
/// the money and the counts come from `DashboardModel`, `NetworkSummary` and
/// `FleetSummary`; the next move comes from `OnboardingModel` while the first
/// session's arc is running and from `marketOpportunities` after it — the same
/// ranking the briefing's own Next Moves card and the map's demand overlay
/// draw. There is one onboarding model in this game and this is a second
/// *view* of it, not a second copy.
///
/// ## Two rows, and why not four
///
/// The map's rule is that nothing permanent occupies the middle
/// (`MapChrome`). A home screen that answers "what is happening in my
/// airline" with fourteen numbers is the dashboard this phase moved out of
/// the way. So: one row of state, one move, and a handle. Everything else is
/// behind the handle, where it stays reachable and stops competing with the
/// Atlantic.
struct MapHomeBriefing: View {
    @Environment(GameController.self) private var controller
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let snapshot: GameState
    /// Raise the full briefing — the dashboard, as a sheet over the world.
    let openBriefing: () -> Void
    /// The guided route sheet, pre-filled. Same flow the checklist and the
    /// map's airport card already use.
    let openRoute: (FirstRouteSuggestion) -> Void
    /// The aircraft market, as a sheet. The Airline tab presents the same one.
    let openAircraftMarket: () -> Void
    /// Ride with a flight: selects it and locks the camera (AE-046).
    let followFlight: (FlightID) -> Void

    /// Both derivations are taken **once** per pass, and both are cached on
    /// the controller for one published snapshot.
    ///
    /// This strip is rebuilt on every `MapScreen` body pass — which a finger
    /// on the map drives, because the camera is observable and a drag writes
    /// to it. `HomeNextMove.resolve` reaches `marketOpportunities`, which
    /// ranks every servable market from the airline's bases, and the facts
    /// reach `dashboardModel()`. Neither may run per gesture frame, so both
    /// go through `GameController`'s existing per-snapshot cache, beside the
    /// map model and the network summary and for exactly the reason they are
    /// there (UIUX_FORENSIC_AUDIT UI-016).
    var body: some View {
        let facts = self.facts
        let move = controller.homeNextMove
        return VStack(alignment: .leading, spacing: AETheme.spacingS) {
            stateRow(facts)
            if snapshot.progression.hasMilestone("firstFlight"),
               let model = controller.progressionModel, let next = model.nextEra {
                Button(action: openBriefing) {
                    Text("\(Vocab.era(next)): \(Format.percent(model.nextEraProgress)) of requirements met")
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.aePress)
                .accessibilityIdentifier("ae-home-era-progress")
            }
            if let move {
                Divider().overlay(Color.white.opacity(0.14))
                moveRow(move)
                if !move.suggestions.isEmpty {
                    suggestionRows(move.suggestions)
                }
            }
        }
        .padding(.horizontal, AETheme.spacingM)
        .padding(.vertical, AETheme.spacingS)
        .aeGlass(in: AETheme.cardShape)
        .aeAnimation(AEMotion.content, value: move?.title ?? "")
    }

    // MARK: Layer 2 — the airline, and the way into everything else

    /// The state row *is* the handle. Two controls where one will do is how a
    /// map ends up with a dashboard bolted to its foot: the numbers a player
    /// glances at and the thing they press to see more of them are the same
    /// gesture, so they are the same button.
    private func stateRow(_ facts: [Fact]) -> some View {
        Button(action: openBriefing) {
            HStack(alignment: .center, spacing: AETheme.spacingM) {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: AETheme.spacingXS) {
                        ForEach(facts, id: \.label) { fact($0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(facts, id: \.label) {
                        fact($0).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.aePress)
        .accessibilityIdentifier("ae-home-briefing")
        .accessibilityLabel("Briefing")
        .accessibilityValue(facts.map { "\($0.label) \($0.value)" }
            .joined(separator: ", "))
        .accessibilityHint("Opens the full briefing: next moves, the feed, the month and the world")
    }

    private struct Fact {
        let label: String
        let value: String
        var tint: Color = .white
    }

    /// Four, and only four — two at accessibility sizes.
    ///
    /// Cash because it decides everything; aircraft in the air because it is
    /// the one number that is alive; the fleet and the network because they
    /// are the shape of what the map is drawing.
    ///
    /// The accessibility cap is not a nicety. These stack vertically at those
    /// sizes, and run 172's AccessibilityL frame showed four of them taking a
    /// third of the screen with the top bar taking another — the world, on the
    /// screen whose whole point is the world, was a band a centimetre high.
    /// Two facts is the most this strip can spend there; the other two are on
    /// the briefing behind it, where there is room to read them.
    private var facts: [Fact] {
        var result: [Fact] = []
        if let dashboard = controller.dashboard {
            result.append(Fact(label: "cash", value: Format.money(dashboard.cash),
                               tint: dashboard.cash.isNegative
                                   ? AETheme.negative : .white))
        }
        if let network = controller.networkSummary {
            result.append(Fact(label: "in the air", value: "\(network.liveFlights)",
                               tint: network.liveFlights > 0
                                   ? AETheme.positive : .white.opacity(0.7)))
            result.append(Fact(label: network.routeCount == 1 ? "route" : "routes",
                               value: "\(network.routeCount)"))
        }
        if let fleet = controller.fleetSummary {
            result.append(Fact(label: "aircraft",
                               value: "\(fleet.total)",
                               tint: fleet.idle > 0 ? AETheme.caution : .white))
        }
        return typeSize.isAccessibilitySize ? Array(result.prefix(2)) : result
    }

    private func fact(_ fact: Fact) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(fact.value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(fact.tint)
                .contentTransition(.numericText())
                .aeAnimation(AEMotion.content, value: fact.value)
            Text(fact.label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityHidden(true)
    }

    // MARK: Layer 3 — one move

    @ViewBuilder
    private func moveRow(_ move: HomeNextMove) -> some View {
        switch move.move {
        case .route(let id):
            NavigationLink(value: id) { moveLabel(move) }
                .buttonStyle(.aePress)
                .accessibilityIdentifier("ae-home-next-action")
        case .aircraft(let id):
            NavigationLink(value: id) { moveLabel(move) }
                .buttonStyle(.aePress)
                .accessibilityIdentifier("ae-home-next-action")
        default:
            Button { perform(move.move) } label: { moveLabel(move) }
                .buttonStyle(.aePress)
                .accessibilityIdentifier("ae-home-next-action")
        }
    }

    private func perform(_ move: HomeNextMove.Move) {
        switch move {
        case .aircraftMarket: openAircraftMarket()
        case .openRoute(let suggestion): openRoute(suggestion)
        case .startClock: controller.setSpeed(.x1)
        case .follow(let flight): followFlight(flight)
        case .briefing: openBriefing()
        case .route, .aircraft: break   // navigation links, handled above
        }
    }

    /// The map's own dark-glass version of `AENextStepLabel`. The design
    /// system's row is built for a card on a system background and draws its
    /// text in `.primary`; over the ocean at night that is the same failure
    /// BUG-036 was, one row further down.
    private func moveLabel(_ move: HomeNextMove) -> some View {
        HStack(spacing: AETheme.spacingS) {
            Group {
                if move.attention && !reduceMotion {
                    icon(move).symbolEffect(.pulse)
                } else {
                    icon(move)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(move.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(move.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(move.title). \(move.detail)")
    }

    /// The tone, as the map's palette. `HomeNextMove` deliberately carries a
    /// meaning rather than a colour, so `GameController` can cache it without
    /// importing SwiftUI and so the palette stays in one file.
    private func color(_ tone: HomeNextMove.Tone) -> Color {
        switch tone {
        case .accent: AETheme.accent
        case .positive: AETheme.positive
        case .caution: AETheme.caution
        case .negative: AETheme.negative
        case .livery(let livery): Vocab.liveryColor(livery)
        }
    }

    private func icon(_ move: HomeNextMove) -> some View {
        Image(systemName: move.icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color(move.tone))
            .frame(width: 30, height: 30)
            .background(color(move.tone).opacity(0.18), in: Circle())
    }

    /// The first-route candidates, offered on the map where the dashed arcs
    /// they name are already drawn. This is the one move that is worth more
    /// than a row: a brand-new airline has no vocabulary for "open a route"
    /// yet, and the arcs on screen are the explanation.
    @ViewBuilder
    private func suggestionRows(_ suggestions: [FirstRouteSuggestion]) -> some View {
        ForEach(suggestions, id: \.destination) { suggestion in
            Button { openRoute(suggestion) } label: {
                HStack(spacing: AETheme.spacingS) {
                    Text("\(suggestion.origin.raw) → \(suggestion.destination.raw)")
                        .font(.caption.weight(.semibold))
                    Text("≈\(Format.count(Int64(suggestion.expectedDailyPassengers))) passengers/day")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .foregroundStyle(.white)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.aePress)
            .accessibilityElement(children: .combine)
            // The arrow stays *in the label*, not only in the glyphs. Four
            // journeys find the game's own recommendation with
            // `label CONTAINS "→"` — the shape the checklist's suggestion rows
            // have always had — and a hand-written label that reads "ARN to
            // LHR" would have silently stopped matching, which is the
            // BUG-033 family: a string that matches nothing, and a test that
            // says the advice is missing when it is on screen.
            .accessibilityLabel("\(suggestion.origin.raw) → \(suggestion.destination.raw), \(suggestion.destinationCity), about \(suggestion.expectedDailyPassengers) passengers a day")
        }
    }
}
