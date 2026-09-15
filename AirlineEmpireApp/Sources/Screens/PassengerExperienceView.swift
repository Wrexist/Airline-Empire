import SwiftUI
import AirlineEmpireCore

/// A quote is keyed by the airline, the proposed tier and a controller
/// revision that moves on a new tick or any applied command — so a paused
/// route, fare or fleet change also invalidates it.
private struct ServiceQuoteRequest: Equatable {
    let airline: AirlineID
    let proposed: ServiceTier
    let installed: ServiceTier
    let revision: UInt64
}

/// Passenger Experience & Reputation: what the airline's reputation is made
/// of, where it is heading, and what a service-tier decision costs.
///
/// This replaces the old tier radio buttons that submitted
/// `SetServiceTierCommand` on tap. Choosing a tier now sets a draft; the
/// screen quotes the change from Core and only submits after a confirmation.
/// Nothing here calculates a gameplay effect of its own — the forecast is
/// `ServicePolicyPreview`, and the components are the simulation's own state.
struct PassengerExperienceView: View {
    @Environment(GameController.self) private var controller
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var draft: ServiceTier?
    @State private var preview: ServicePolicyPreview?
    @State private var pending: ServiceTier?
    @State private var confirming = false
    @State private var saved = false

    /// The capture tests render the review state without a tap.
    init(initialDraft: ServiceTier? = nil) {
        _draft = State(initialValue: initialDraft)
    }

    private var installedTier: ServiceTier? {
        controller.snapshot?.playerAirline?.serviceTier
    }

    private var proposedTier: ServiceTier? {
        guard let installed = installedTier else { return nil }
        return draft ?? installed
    }

    private var isChange: Bool {
        guard let installed = installedTier, let proposed = proposedTier else { return false }
        return proposed != installed
    }

    private var command: SetServiceTierCommand? {
        guard let player = controller.snapshot?.playerAirline,
              let proposed = proposedTier, proposed != player.serviceTier else { return nil }
        return SetServiceTierCommand(airline: player.id, tier: proposed)
    }

    private var quoteRequest: ServiceQuoteRequest? {
        guard let player = controller.snapshot?.playerAirline else { return nil }
        return ServiceQuoteRequest(airline: player.id, proposed: proposedTier ?? player.serviceTier,
                                   installed: player.serviceTier,
                                   revision: controller.passengerExperienceRevision)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AETheme.spacingM) {
                if let snapshot = controller.snapshot,
                   let player = snapshot.playerAirline,
                   let catalog = controller.catalog {
                    overallCard(player: player, catalog: catalog)
                    driversPanel(snapshot: snapshot, player: player, catalog: catalog)
                    tierPanel(installed: player.serviceTier,
                              proposed: proposedTier ?? player.serviceTier,
                              catalog: catalog)
                    forecastPanel(installed: player.serviceTier,
                                  proposed: proposedTier ?? player.serviceTier)
                    inputsPanel(snapshot: snapshot, player: player, catalog: catalog)
                    actions
                    if saved {
                        Label("Service tier saved", systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(AETheme.positive)
                            .accessibilityIdentifier("ae-service-saved")
                    }
                } else {
                    LoadingState(message: "Reading your passenger experience")
                        .frame(minHeight: 240)
                }
            }
            .aePageInsets()
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .aeScreenBackground()
        .navigationTitle("Passenger experience")
        .navigationBarTitleDisplayMode(.inline)
        .aeTimeToolbar()
        // The links onward go to real routes and aircraft, so a stack that can
        // push this screen must be able to push those too — otherwise the link
        // is silently inert from wherever it was reached (tasks/BUGS.md
        // BUG-030). Declared here rather than relied on from a parent.
        .navigationDestination(for: RouteID.self) { RouteDetailView(routeID: $0) }
        .navigationDestination(for: AircraftID.self) { AircraftDetailView(aircraftID: $0) }
        .task(id: quoteRequest) { await refreshQuote() }
        .onChange(of: controller.snapshot?.playerAirline?.serviceTier) { _, value in
            if let pending, pending == value {
                draft = nil
                self.pending = nil
                saved = true
            } else if value != nil {
                saved = false
            }
        }
        .onChange(of: controller.lastRejection) { _, value in if value != nil { pending = nil } }
        .confirmationDialog(
            "Change to \(proposedTier.map(Vocab.serviceTier) ?? "this") service?",
            isPresented: $confirming, titleVisibility: .visible) {
            if let command {
                Button("Apply Service Tier") {
                    if controller.submit(command) == nil { pending = command.tier }
                }
                Button("Cancel", role: .cancel) { }
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    // MARK: Overall

    private func overallCard(player: Airline, catalog: ContentCatalog) -> some View {
        let multiplier = player.reputation.demandMultiplier(tuning: catalog.tuning.reputation)
        return AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Overall reputation", systemImage: "star.circle")
                HStack(alignment: .firstTextBaseline, spacing: AETheme.spacingS) {
                    Text(Format.percent(player.reputation.score))
                        .font(AEType.hero)
                        .accessibilityIdentifier("ae-reputation-score")
                    Spacer(minLength: AETheme.spacingS)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("demand ×\(Format.decimal(multiplier, places: 2))")
                            .font(AEType.metricCompact)
                            .foregroundStyle(multiplier >= 1 ? AETheme.positive : AETheme.caution)
                        Text("today").font(AEType.caption).foregroundStyle(AETheme.mutedText)
                    }
                }
                Text("Reputation multiplies how attractive your fares look to passengers. It blends five parts — punctuality 25%, reliability 25%, service 20%, comfort 15% and value 15% — and moves slowly in both directions, over weeks rather than days. A good history buys grace, never immunity: no decision raises it today.")
                    .font(.subheadline)
                    .foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                if player.administrationCount > 0 {
                    Label("After \(player.administrationCount) administration\(player.administrationCount == 1 ? "" : "s"), every component still carries a lasting scar.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(AETheme.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Drivers

    private func driversPanel(snapshot: GameState, player: Airline,
                              catalog: ContentCatalog) -> some View {
        let comfort = FleetComfortSnapshot.make(airline: player.id, state: snapshot, catalog: catalog)
        let hasGroundExperience = snapshot.playerHasCapability(.groundExperience)
        let serviceTarget = ReputationSystem.serviceTarget(
            for: player.serviceTier, isPlayer: true,
            hasGroundExperience: hasGroundExperience, tuning: catalog.tuning.reputation)
        let columns = typeSize.isAccessibilitySize
            ? [GridItem(.flexible(), alignment: .topLeading)]
            : [GridItem(.adaptive(minimum: 165), spacing: AETheme.spacingS, alignment: .topLeading)]
        return VStack(alignment: .leading, spacing: AETheme.spacingS) {
            AESectionHeader(text: "What it is made of", systemImage: "chart.bar.doc.horizontal")
            LazyVGrid(columns: columns, alignment: .leading, spacing: AETheme.spacingS) {
                driverCard(
                    icon: "clock.badge.checkmark", title: "Punctuality",
                    value: player.reputation.punctuality,
                    detail: "On-time share of the flights you complete. Aircraft condition, tight schedules and storms cause delays.")
                driverCard(
                    icon: "checkmark.shield", title: "Reliability",
                    value: player.reputation.reliability,
                    detail: "Share of scheduled flights you complete rather than cancel. Worn airframes, airport closures and strikes cost you here.")
                driverCard(
                    icon: "cup.and.saucer", title: "Service",
                    value: player.reputation.service,
                    detail: serviceDetail(target: serviceTarget, hasGroundExperience: hasGroundExperience))
                driverCard(
                    icon: "chair.lounge", title: "Comfort",
                    value: player.reputation.comfort,
                    detail: comfortDetail(comfort))
                driverCard(
                    icon: "tag", title: "Value",
                    value: player.reputation.valuePerception,
                    detail: "Whether your fares feel worth it: the quality you deliver measured against how your fares compare with the market. Your average fare sits at \(Format.percent(player.reputation.farePositionEWMA)) of the reference fare.")
            }
        }
    }

    private func serviceDetail(target: Double, hasGroundExperience: Bool) -> String {
        var detail = "The onboard product you pay for. Your service tier sets the level this drifts toward: \(Format.percent(target))."
        if hasGroundExperience {
            detail += " Your ground-experience capability adds 8 points."
        }
        return detail
    }

    private func comfortDetail(_ comfort: FleetComfortSnapshot?) -> String {
        guard let comfort else {
            return "Seat-weighted comfort of your cabins: premium seats and onboard upgrades. Aircraft age affects reliability, not comfort."
        }
        return "Seat-weighted comfort of your cabins across \(comfort.aircraftCount) aircraft — \(Format.percent(comfort.premiumSeatShare)) premium seats, \(Format.decimal(comfort.upgradeLevelsPerSeat, places: 1)) onboard upgrade levels per seat. Aircraft age affects reliability, not comfort."
    }

    private func driverCard(icon: String, title: String, value: Double,
                            detail: String) -> some View {
        let clamped = min(1, max(0, value))
        let tint = clamped >= 0.75 ? AETheme.positive : clamped >= 0.45 ? AETheme.caution : AETheme.negative
        return VStack(alignment: .leading, spacing: AETheme.spacingS) {
            HStack(spacing: AETheme.spacingS) {
                if !typeSize.isAccessibilitySize {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(tint)
                        .frame(width: 30, height: 30)
                        .background(tint.opacity(0.12), in: .rect(cornerRadius: AETheme.cornerRadiusSmall))
                        .accessibilityHidden(true)
                }
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: AETheme.spacingXS)
                Text(Format.percent(clamped))
                    .font(AEType.metricCompact)
                    .foregroundStyle(tint)
            }
            ProgressView(value: clamped).tint(tint)
            Text(detail)
                .font(AEType.caption)
                .foregroundStyle(AETheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AETheme.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AETheme.cardBackground, in: AETheme.cardShape)
        .overlay(AETheme.cardShape.stroke(AETheme.surfaceRim.opacity(0.45), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(Format.percent(clamped)). \(detail)")
    }

    // MARK: Service tier

    private func tierPanel(installed: ServiceTier, proposed: ServiceTier,
                           catalog: ContentCatalog) -> some View {
        AircraftPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingM) {
                AirportHeading(title: "Airline service tier", icon: "cup.and.saucer")
                Text("One tier for the whole airline. Every carried passenger costs more as the tier rises, and the service component drifts toward the tier's target over the following weeks.")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: AETheme.spacingS) {
                    ForEach(ServiceTier.allCases, id: \.self) { tier in
                        tierChoice(tier, installed: installed, proposed: proposed, catalog: catalog)
                    }
                }
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack {
                        currentProposed(installed: installed, proposed: proposed)
                        Spacer(minLength: AETheme.spacingS)
                        if !isChange {
                            Text("No change selected")
                                .font(.caption).foregroundStyle(AETheme.mutedText)
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        currentProposed(installed: installed, proposed: proposed)
                        if !isChange {
                            Text("No change selected").font(.caption).foregroundStyle(AETheme.mutedText)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func currentProposed(installed: ServiceTier, proposed: ServiceTier) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Current: \(Vocab.serviceTier(installed))")
                .font(.caption)
            Text(installed == proposed ? "Proposed: \(Vocab.serviceTier(proposed))"
                 : "Proposed: \(Vocab.serviceTier(proposed)) →")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isChange ? AETheme.accent : AETheme.mutedText)
                .accessibilityIdentifier("ae-service-proposed")
        }
    }

    private func tierChoice(_ tier: ServiceTier, installed: ServiceTier,
                            proposed: ServiceTier, catalog: ContentCatalog) -> some View {
        let perPax = catalog.tuning.reputation.serviceCostPerPax(tier)
        let target = catalog.tuning.reputation.serviceTarget(tier)
        let selected = proposed == tier
        let color = selected ? AETheme.accent : AETheme.surfaceRim
        return Button {
            draft = tier
            saved = false
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: AETheme.spacingS) {
                    Text(Vocab.serviceTier(tier)).font(.headline)
                    if tier == installed {
                        AEBadge(text: "current", color: AETheme.positive, icon: "checkmark")
                    }
                    if selected && tier != installed {
                        AEBadge(text: "proposed", color: AETheme.accent)
                    }
                    Spacer(minLength: 0)
                }
                Text(Vocab.serviceTierDetail(tier))
                    .font(.caption).foregroundStyle(AETheme.mutedText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(exactMoney(perPax)) per passenger · service target \(Format.percent(target))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selected ? AETheme.accent : AETheme.mutedText)
            }
            .padding(AETheme.spacingM)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(selected ? AETheme.accent.opacity(0.12) : .clear,
                        in: .rect(cornerRadius: AETheme.cornerRadiusSmall))
            .overlay {
                RoundedRectangle(cornerRadius: AETheme.cornerRadiusSmall)
                    .strokeBorder(color, lineWidth: selected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: AETheme.cornerRadiusSmall))
        }
        .buttonStyle(.aePress)
        .disabled(pending != nil)
        .accessibilityIdentifier("ae-service-tier-\(tier.rawValue)")
        .accessibilityLabel("\(Vocab.serviceTier(tier)) service, \(exactMoney(perPax)) per passenger, service target \(Format.percent(target))")
        .accessibilityValue(tier == installed ? "Currently installed" : selected ? "Proposed" : "")
        .accessibilityHint("Preview this tier before applying")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Forecast

    private func forecastPanel(installed: ServiceTier, proposed: ServiceTier) -> some View {
        AircraftPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingM) {
                AirportHeading(title: "Forecast", icon: "chart.bar.fill")
                Text(isChange
                     ? "Simulated change from your installed \(Vocab.serviceTier(installed)) tier."
                     : "Your installed tier. Choose a different tier to compare.")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
                if let preview {
                    LazyVGrid(columns: typeSize.isAccessibilitySize
                              ? [GridItem(.flexible())]
                              : [GridItem(.adaptive(minimum: 150), spacing: AETheme.spacingM)],
                              alignment: .leading, spacing: AETheme.spacingM) {
                        metric("Service cost / passenger",
                               Format.money(preview.proposedCostPerPassenger),
                               change: moneyChange(preview.costPerPassengerChange, preview.isChange))
                        metric("Monthly service cost",
                               Format.money(preview.estimatedMonthlyCostProposed),
                               change: moneyChange(preview.estimatedMonthlyCostChange, preview.isChange))
                        metric("Service heading toward",
                               Format.percent(preview.proposedServiceTarget),
                               change: pointsChange(preview.proposedServiceTarget - preview.currentServiceTarget, preview.isChange))
                        metric("Demand once settled",
                               "×\(Format.decimal(preview.multiplierIfServiceSettlesProposed, places: 2))",
                               change: multiplierChange(preview, preview.isChange))
                    }
                    .accessibilityIdentifier("ae-service-forecast")
                    Text(preview.referenceMonthlyPassengers == 0 || preview.servedRoutes == 0
                         ? "No routes with operational aircraft are flying yet, so the recurring cost is quoted at zero passengers."
                         : "Based on \(Format.count(Int64(preview.referenceMonthlyPassengers))) passengers over a 30-day reference month across \(preview.servedRoutes) \(preview.servedRoutes == 1 ? "route" : "routes") at today's demand, fares and aircraft assignment.")
                        .font(.caption).foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    if isChange, preview.estimatedMonthlyCostChange > .zero {
                        Label("This raises your recurring service cost. Reputation does not change on the day you apply — the service component drifts toward its target over the following weeks.", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(AETheme.caution)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("ae-service-gradual-note")
                    }
                    DisclosureGroup("How this is estimated") {
                        VStack(alignment: .leading, spacing: AETheme.spacingS) {
                            Text("Service is charged per carried passenger. The monthly figure applies the tier's rate to a 30-day reference volume from today's demand, fares and aircraft assignment; your actual spend follows the passengers you actually carry.")
                            Text("Reputation responds gradually. The service component drifts toward the tier's target at the simulation's own daily rate, so applying a tier changes no reputation today.")
                            Text("“Demand once settled” is the engine's own demand multiplier if service reaches its target and punctuality, reliability, comfort and fares stay where they are. It is not a passenger forecast.")
                            Text("Onboard aircraft upgrades are billed separately and are unchanged here. Airport lounges improve ground comfort, which the demand engine counts separately from the comfort component.")
                        }
                        .font(.caption2).foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, AETheme.spacingS)
                    }
                    .font(.subheadline)
                    .tint(AETheme.mutedText)
                } else {
                    ProgressView("Calculating your service forecast…").font(.caption)
                        .accessibilityIdentifier("ae-service-forecast-loading")
                }
            }
        }
    }

    private func multiplierChange(_ preview: ServicePolicyPreview, _ show: Bool) -> String? {
        guard show else { return nil }
        let difference = preview.multiplierIfServiceSettlesProposed - preview.multiplierIfServiceSettlesNow
        let sign = difference >= 0 ? "+" : "−"
        return "\(sign)\(Format.decimal(abs(difference), places: 2)) once settled"
    }

    private func metric(_ title: String, _ value: String, change: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(AETheme.mutedText)
            Text(value).font(.title3.bold()).monospacedDigit()
            if let change {
                Text(change).font(.caption).foregroundStyle(AETheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Inputs

    private func inputsPanel(snapshot: GameState, player: Airline,
                             catalog: ContentCatalog) -> some View {
        let routes = snapshot.routes(of: player.id)
        let fleet = snapshot.fleet(of: player.id)
        let commitments = player.airportServiceCommitments(tuning: catalog.tuning.airportServices)
        return AEPanel {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Manage what drives this", systemImage: "slider.horizontal.3")
                inputLink(icon: "point.topleft.down.to.point.bottomright.curvepath",
                          title: "Route fares",
                          detail: "\(routes.count) \(routes.count == 1 ? "route" : "routes") · value and punctuality") {
                    RoutesList().navigationTitle("Routes").aeTimeToolbar()
                }
                inputLink(icon: "airplane",
                          title: "Aircraft cabins",
                          detail: "\(fleet.count) aircraft · comfort and reliability") {
                    FleetList().navigationTitle("Fleet").aeTimeToolbar()
                }
                if commitments.isEmpty {
                    inputLink(icon: "building.2",
                              title: "Airport services",
                              detail: "None yet · lounges and ground services") {
                        AirportBrowserView()
                    }
                } else {
                    ForEach(Array(commitments.prefix(4)), id: \.airport) { commitment in
                        inputLink(icon: "building.2",
                                  title: "\(commitment.airport.raw) services",
                                  detail: "\(Format.money(commitment.monthly))/month") {
                            AirportDetailView(code: commitment.airport, initialSection: .facilities)
                        }
                    }
                    if commitments.count > 4 {
                        Text("+\(commitments.count - 4) more station\(commitments.count - 4 == 1 ? "" : "s") in Airports")
                            .font(.caption).foregroundStyle(AETheme.mutedText)
                    }
                }
            }
        }
    }

    private func inputLink<Destination: View>(icon: String, title: String, detail: String,
                                              @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: AETheme.spacingS) {
                Image(systemName: icon)
                    .font(.subheadline).foregroundStyle(AETheme.accent)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(AETheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: AETheme.spacingS)
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.aePress)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: AETheme.spacingS) {
            if isChange {
                Text("Service cost is recurring, per passenger. Reputation responds gradually.")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { confirming = true } label: {
                VStack(spacing: 4) {
                    Text("Apply Service Tier").font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let preview, isChange {
                        Text("about \(signedMoney(preview.estimatedMonthlyCostChange)) per month at today's passengers")
                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .multilineTextAlignment(.center)
            }
            .buttonStyle(AEButtonStyle(role: .primary, expandedLabel: typeSize.isAccessibilitySize))
            .disabled(!isChange || pending != nil || preview == nil
                || command.map { controller.precheck($0) != nil } ?? true)
            .accessibilityIdentifier("ae-service-apply")
            if let command, let rejection = controller.precheck(command) {
                Text(rejection.message).font(.caption).foregroundStyle(AETheme.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                draft = nil
                saved = false
            } label: {
                Text("Reset Changes")
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(!isChange || pending != nil)
            .accessibilityIdentifier("ae-service-reset")
        }
    }

    // MARK: Plumbing

    private func refreshQuote() async {
        guard let request = quoteRequest,
              let state = controller.snapshot,
              let catalog = controller.catalog else { return }
        preview = nil
        // Debounce a rapid run through the tiers; only pure Core work leaves
        // the main actor and a cancelled result is discarded.
        do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
        let airline = request.airline, tier = request.proposed
        let result = await Task.detached(priority: .userInitiated) {
            ServicePolicyPreview.make(airline: airline, tier: tier, state: state, catalog: catalog)
        }.value
        guard !Task.isCancelled else { return }
        preview = result
    }

    private var confirmationMessage: String {
        guard let preview, let proposed = proposedTier else { return "" }
        return "\(signedMoney(preview.costPerPassengerChange)) per passenger — about \(signedMoney(preview.estimatedMonthlyCostChange)) a month at today's passengers. Service reputation drifts toward \(Format.percent(preview.proposedServiceTarget)) over the following weeks; it does not change today. \(Vocab.serviceTier(proposed)) service is a recurring commitment."
    }

    private func moneyChange(_ change: Money, _ show: Bool) -> String? {
        guard show else { return nil }
        return "\(signedMoney(change)) vs current"
    }

    private func pointsChange(_ change: Double, _ show: Bool) -> String? {
        guard show else { return nil }
        let sign = change >= 0 ? "+" : "−"
        return "\(sign)\(Format.percent(abs(change))) vs current"
    }

    private func signedMoney(_ amount: Money) -> String {
        "\(amount.cents >= 0 ? "+" : "−")\(Format.money(Money(cents: abs(amount.cents))))"
    }

    private func exactMoney(_ amount: Money) -> String {
        "$\(Format.decimal(amount.asDouble, places: 2))"
    }
}
