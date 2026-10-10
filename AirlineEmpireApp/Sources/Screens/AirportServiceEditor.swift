import SwiftUI
import AirlineEmpireCore

/// What an airport quote answers.
///
/// Keyed on the game day, not on the controller's revision: that moves on
/// every tick, so the quote restarted every 3.75 s at 1× — two demand passes
/// each time — and blanked itself while it ran, switching Apply off under the
/// player's finger. The demand it prices changes at the daily update, and a
/// change to this airport's services changes `installed`.
private struct AirportQuoteRequest: Equatable {
    let airport: AirportCode
    let proposed: AirportFacilities
    let installed: AirportFacilities
    let day: Int64

    /// Whether `other` priced the same proposal, perhaps on an earlier day.
    func asks(sameAs other: AirportQuoteRequest?) -> Bool {
        guard let other else { return false }
        return other.airport == airport && other.proposed == proposed
            && other.installed == installed
    }
}

struct AirportFacilityEditor: View {
    @Environment(GameController.self) private var controller
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    let airport: AirportCode
    let player: Airline
    let snapshot: GameState
    let catalog: ContentCatalog
    @Binding var draft: AirportFacilities?
    @State private var preview: AirportInvestmentPreview?
    /// The request `preview` answers, so a new day can re-price the same
    /// proposal without taking the old figures down first.
    @State private var quoted: AirportQuoteRequest?
    @State private var pending: AirportFacilities?
    @State private var confirming = false
    @State private var saved = false
    /// The station as it will stand once everything ordered has opened: the
    /// baseline a proposal is priced and confirmed against.
    private var installed: AirportFacilities { player.plannedFacilities(at: airport) }
    private var proposed: AirportFacilities { draft ?? installed }
    private var quoteRequest: AirportQuoteRequest {
        AirportQuoteRequest(airport: airport, proposed: proposed, installed: installed,
                            day: snapshot.clock.now.dayIndex)
    }
    private var tuning: AirportFacilityTuning { catalog.tuning.airportServices }
    private var cost: Money { proposed.installationCost(from: installed, tuning: tuning) }
    private var command: ConfigureAirportFacilitiesCommand {
        .init(airline: player.id, airport: airport, facilities: proposed)
    }
    private var changes: String {
        AirportService.allCases.filter { $0.level(in: installed) != $0.level(in: proposed) }
            .map { "\($0.title): \($0.levelName($0.level(in: installed))) → \($0.levelName($0.level(in: proposed)))" }
            .joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: AETheme.spacingM) {
            introduction
            ForEach(AirportService.allCases, id: \.self) { service in
                serviceCard(service)
            }
            investment
            actions
            if saved {
                Label("Airport investment saved", systemImage: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(AETheme.positive)
                    .accessibilityIdentifier("ae-airport-investment-saved")
            }
        }
        .task(id: quoteRequest) {
            let request = quoteRequest
            let next = request.proposed, state = snapshot, content = catalog, id = player.id, code = request.airport
            // A different proposal clears the old figures — they price
            // something else. The same one on a new day keeps them up while
            // it is re-priced.
            if !request.asks(sameAs: quoted) { preview = nil }
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            let result = await Task.detached(priority: .userInitiated) {
                AirportInvestmentPreview.make(airline: id, airport: code, proposed: next, state: state, catalog: content)
            }.value
            guard !Task.isCancelled else { return }
            preview = result; quoted = request
        }
        .onChange(of: installed) { _, value in
            if pending == value { pending = nil; draft = nil; saved = true }
        }
        .onChange(of: controller.lastRejection) { _, value in if value != nil { pending = nil } }
        .confirmationDialog("Apply upgrades at \(airport.raw)?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Confirm Airport Upgrades") {
                if controller.submit(command) == nil { pending = proposed }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\(changes)\n\nInstallation: \(Format.money(cost)), non-refundable.\(buildNote) New monthly cost once open: \(Format.money(proposed.monthlyCost(tuning: tuning))).")
        }
    }

    /// "Opens in 30 days." for the longest build in the proposal.
    private var buildNote: String {
        let days = AirportService.allCases.map {
            $0.buildDays(from: $0.level(in: installed), to: $0.level(in: proposed), tuning: tuning)
        }.max() ?? 0
        return days > 0 ? " Building takes up to \(days) days." : ""
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Invest in a better airport experience").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Build lounges, ground crews, hangars and crew bases for your airline at \(airport.raw). Each takes game days to build and costs upkeep once open.")
                .font(.subheadline).foregroundStyle(AETheme.mutedText)
            if let spec = catalog.airport(airport) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Label(Vocab.runway(spec.runwayClass), systemImage: "airplane.departure")
                        Spacer()
                        Text("\(Format.count(Int64(spec.terminalCapacityPerDay))) terminal capacity/day")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Vocab.runway(spec.runwayClass))
                        Text("\(Format.count(Int64(spec.terminalCapacityPerDay))) terminal capacity/day")
                    }
                }.font(.caption).foregroundStyle(AETheme.mutedText)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func serviceCard(_ service: AirportService) -> some View {
        let model = AirportServiceReadModel(service: service, installed: installed, proposed: proposed, tuning: tuning,
                                            ops: catalog.tuning.ops)
        let color = service == .lounge ? AETheme.fare : AETheme.accent
        let building = player.construction(at: airport, of: service)
        let locked = snapshot.progression.era < service.unlockEra
        let wide = sizeClass == .regular && !typeSize.isAccessibilitySize
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 20))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
        return AircraftPanel {
            VStack(alignment: .leading, spacing: 10) {
                layout {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            if !typeSize.isAccessibilitySize {
                                Image(systemName: Self.icon(service))
                                    .font(.title2).foregroundStyle(color).padding(10)
                                    .background(color.opacity(0.12), in: .rect(cornerRadius: AETheme.cornerRadiusSmall))
                                    .accessibilityHidden(true)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(service.title).font(.headline).accessibilityAddTraits(.isHeader)
                                Text(Self.blurb(service))
                                    .font(.caption).foregroundStyle(AETheme.mutedText)
                            }
                        }
                        if let building {
                            Label("Under construction: \(service.levelName(building.level)) opens in \(building.daysLeft(at: snapshot.clock.now)) days",
                                  systemImage: "hammer.fill")
                                .font(.caption.weight(.semibold)).foregroundStyle(AETheme.caution)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("ae-airport-\(service.rawValue)-building")
                        } else if locked {
                            Label("Unlocks in the \(EraNames.title(service.unlockEra)) era", systemImage: "lock.fill")
                                .font(.caption.weight(.semibold)).foregroundStyle(AETheme.mutedText)
                        }
                        tiers(service, model: model, color: color, frozen: building != nil, locked: locked)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 7) {
                        Label(model.effect, systemImage: service == .lounge ? "star" : "checkmark.shield")
                            .font(.subheadline).foregroundStyle(color)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(model.scope).font(.caption).foregroundStyle(AETheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                AirportFact(title: "Installation now", value: Format.money(model.installation))
                AirportFact(title: "Monthly cost once open", value: Format.money(model.monthly))
                if model.buildDays > 0 {
                    AirportFact(title: "Build time", value: "\(model.buildDays) days")
                }
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("Current: \(service.levelName(model.current))")
                        Spacer()
                        Text(model.current == model.proposed ? "No change" : "Proposed: \(service.levelName(model.proposed)) →")
                            .foregroundStyle(color)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Current: \(service.levelName(model.current))")
                        Text("Proposed: \(service.levelName(model.proposed))").foregroundStyle(color)
                    }
                }.font(.caption).accessibilityElement(children: .combine)
            }
        }
    }

    private static func icon(_ service: AirportService) -> String {
        switch service {
        case .lounge: "cup.and.saucer.fill"
        case .ground: "wrench.fill"
        case .hangar: "wrench.and.screwdriver.fill"
        case .crewBase: "person.2.badge.gearshape.fill"
        }
    }

    private static func blurb(_ service: AirportService) -> String {
        switch service {
        case .lounge: "A quieter space to wait, work and recharge."
        case .ground: "Dedicated support for more reliable departures."
        case .hangar: "Your own maintenance: shorter, cheaper checks for aircraft flying here."
        case .crewBase: "Crews based here: a longer operating day and lower crew costs."
        }
    }

    private func tiers(_ service: AirportService, model: AirportServiceReadModel, color: Color,
                       frozen: Bool, locked: Bool) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
        return layout {
            ForEach(0...service.maxLevel, id: \.self) { level in
                Button {
                    draft = service.setting(level, in: proposed); saved = false
                } label: {
                    VStack(spacing: 3) {
                        Text(service.levelName(level)).font(.caption.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text("Level \(level)").font(.caption2)
                    }.frame(maxWidth: .infinity, minHeight: 52)
                        .background(model.proposed == level ? color.opacity(0.18) : .clear, in: .rect(cornerRadius: AETheme.cornerRadiusSmall))
                        .overlay { RoundedRectangle(cornerRadius: AETheme.cornerRadiusSmall).strokeBorder(model.proposed == level ? color : AETheme.surfaceRim, lineWidth: model.proposed == level ? 2 : 1) }
                }.buttonStyle(.plain).disabled(pending != nil || frozen || (locked && level > 0))
                    .accessibilityLabel("\(service.title), \(service.levelName(level)), level \(level)")
                    .accessibilityValue(model.current == level ? "Currently installed" : "")
                    .accessibilityHint("Preview this tier before applying upgrades")
                    .accessibilityAddTraits(model.proposed == level ? .isSelected : [])
                    .accessibilityIdentifier("ae-airport-\(service.rawValue)-\(level)")
            }
        }
    }

    private var investment: some View {
        AircraftPanel {
            VStack(alignment: .leading, spacing: 12) {
                AirportHeading(title: "Investment preview", icon: "chart.bar.fill")
                Text("Changes relative to your installed services").font(.caption).foregroundStyle(AETheme.mutedText)
                if let preview {
                    LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 140))], alignment: .leading, spacing: 14) {
                        metric("Installation now", Format.money(preview.installationCost))
                        metric("Monthly service cost", Format.money(preview.monthlyServiceCost))
                        metric("Monthly demand change", "\(preview.monthlyDemandChange > 0 ? "+" : "")\(Format.count(Int64(preview.monthlyDemandChange)))")
                        metric("Monthly revenue change", Format.money(preview.monthlyRevenueChange))
                        metric("Monthly net change", Format.money(preview.monthlyNetChange), color: preview.monthlyNetChange < .zero ? AETheme.caution : AETheme.positive)
                    }
                    Text("Benefits \(preview.servedRoutes) \(preview.servedRoutes == 1 ? "route" : "routes") with operational aircraft at \(airport.raw).")
                        .font(.caption).foregroundStyle(AETheme.mutedText)
                    if proposed != installed && preview.monthlyNetChange < .zero {
                        Label("Current demand gains do not cover the added monthly cost.", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(AETheme.caution)
                            .accessibilityIdentifier("ae-airport-negative-investment")
                    }
                    DisclosureGroup("Forecast & billing details") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Demand means allocated bookings before seat limits, over a 30-day reference month. Fares, aircraft and market conditions are held constant. Revenue includes seat limits; net change includes route costs and the change in monthly services, excluding installation.")
                            Text("Ground-service benefits appear in actual operations over time. Future disruption savings and reputation changes are not priced into this estimate.")
                            Text("Installation is non-refundable and paid when you order. Each building opens after its build time; monthly charges start with the first month boundary after it opens, without proration, even if routes close. Removing a building stops future charges. Rebuilding pays installation again.")
                            Text("A lounge changes demand from the daily update after it opens. Ground services, hangars and crew bases apply to flights and checks from opening day.")
                        }.font(.caption).foregroundStyle(AETheme.mutedText).padding(.top, 8)
                    }.font(.subheadline)
                } else {
                    ProgressView("Calculating route effects…").font(.caption)
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(AETheme.mutedText)
            Text(value).font(.title3.bold()).monospacedDigit().foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if proposed != installed {
                Text("Installation is non-refundable.\(buildNote) Monthly charges start once open.")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
            }
            Button { confirming = true } label: {
                VStack(spacing: 4) {
                    Text("Apply Airport Upgrades").font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text("\(Format.money(cost)) now · \(Format.money(proposed.monthlyCost(tuning: tuning)))/month")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, minHeight: 52)
                    .multilineTextAlignment(.center)
            }.buttonStyle(AEButtonStyle(role: .primary, expandedLabel: typeSize.isAccessibilitySize))
                // `preview` is nil only until this proposal has been priced
                // once: a daily re-quote keeps the last figures, so Apply no
                // longer switches off while one runs.
                .disabled(proposed == installed || pending != nil || preview == nil || controller.precheck(command) != nil)
                .accessibilityIdentifier("ae-airport-investment-apply")
            if proposed != installed, let rejection = controller.precheck(command) {
                Text(rejection.message).font(.caption).foregroundStyle(AETheme.caution)
            }
            Button { draft = nil; saved = false } label: {
                Text("Reset Changes").fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 44)
            }.disabled(proposed == installed || pending != nil)
                .accessibilityIdentifier("ae-airport-investment-reset")
        }
    }
}
