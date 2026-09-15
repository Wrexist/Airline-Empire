import SwiftUI
import AirlineEmpireCore

private struct AirportQuoteRequest: Equatable {
    let airport: AirportCode
    let proposed: AirportFacilities
    let installed: AirportFacilities
    let revision: UInt64
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
    @State private var pending: AirportFacilities?
    @State private var confirming = false
    @State private var saved = false
    private var installed: AirportFacilities { player.facilities(at: airport) }
    private var proposed: AirportFacilities { draft ?? installed }
    private var tuning: AirportFacilityTuning { catalog.tuning.airportServices }
    private var cost: Money { proposed.installationCost(from: installed, tuning: tuning) }
    private var command: ConfigureAirportFacilitiesCommand {
        .init(airline: player.id, airport: airport, facilities: proposed)
    }
    private var changes: String {
        AirportService.allCases.filter { $0.level(in: installed) != $0.level(in: proposed) }
            .map { "\($0.title): \(AirportService.levelName($0.level(in: installed))) → \(AirportService.levelName($0.level(in: proposed)))" }
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
        .task(id: AirportQuoteRequest(airport: airport, proposed: proposed, installed: installed,
                                     revision: controller.airportInvestmentRevision)) {
            let next = proposed, state = snapshot, content = catalog, id = player.id, code = airport
            preview = nil
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            let result = await Task.detached(priority: .userInitiated) {
                AirportInvestmentPreview.make(airline: id, airport: code, proposed: next, state: state, catalog: content)
            }.value
            guard !Task.isCancelled else { return }
            preview = result
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
            Text("\(changes)\n\nInstallation: \(Format.money(cost)), non-refundable. New monthly cost: \(Format.money(proposed.monthlyCost(tuning: tuning))).")
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Invest in a better airport experience").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Improve route comfort and departure reliability with services for your airline at \(airport.raw).")
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
        let model = AirportServiceReadModel(service: service, installed: installed, proposed: proposed, tuning: tuning)
        let color = service == .lounge ? AETheme.fare : AETheme.accent
        let wide = sizeClass == .regular && !typeSize.isAccessibilitySize
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 20))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
        return AircraftPanel {
            VStack(alignment: .leading, spacing: 10) {
                layout {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            if !typeSize.isAccessibilitySize {
                                Image(systemName: service == .lounge ? "cup.and.saucer.fill" : "wrench.fill")
                                    .font(.title2).foregroundStyle(color).padding(10)
                                    .background(color.opacity(0.12), in: .rect(cornerRadius: AETheme.cornerRadiusSmall))
                                    .accessibilityHidden(true)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(service.title).font(.headline).accessibilityAddTraits(.isHeader)
                                Text(service == .lounge ? "A quieter space to wait, work and recharge." : "Dedicated support for more reliable departures.")
                                    .font(.caption).foregroundStyle(AETheme.mutedText)
                            }
                        }
                        tiers(service, model: model, color: color)
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
                AirportFact(title: "Monthly cost", value: Format.money(model.monthly))
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("Current: \(AirportService.levelName(model.current))")
                        Spacer()
                        Text(model.current == model.proposed ? "No change" : "Proposed: \(AirportService.levelName(model.proposed)) →")
                            .foregroundStyle(color)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Current: \(AirportService.levelName(model.current))")
                        Text("Proposed: \(AirportService.levelName(model.proposed))").foregroundStyle(color)
                    }
                }.font(.caption).accessibilityElement(children: .combine)
            }
        }
    }

    private func tiers(_ service: AirportService, model: AirportServiceReadModel, color: Color) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
        return layout {
            ForEach(0...2, id: \.self) { level in
                Button {
                    draft = service.setting(level, in: proposed); saved = false
                } label: {
                    VStack(spacing: 3) {
                        Text(AirportService.levelName(level)).font(.caption.weight(.semibold))
                        Text("Level \(level)").font(.caption2)
                    }.frame(maxWidth: .infinity, minHeight: 52)
                        .background(model.proposed == level ? color.opacity(0.18) : .clear, in: .rect(cornerRadius: AETheme.cornerRadiusSmall))
                        .overlay { RoundedRectangle(cornerRadius: AETheme.cornerRadiusSmall).strokeBorder(model.proposed == level ? color : AETheme.surfaceRim, lineWidth: model.proposed == level ? 2 : 1) }
                }.buttonStyle(.plain).disabled(pending != nil)
                    .accessibilityLabel("\(service.title), \(AirportService.levelName(level)), level \(level)")
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
                            Text("Installation is non-refundable. Monthly charges use your installed levels at the next month boundary, without proration, even if routes close. Removing services stops future charges. Reopening pays installation again.")
                            Text("Lounge demand changes take effect at the next daily update. Ground-service changes apply to future departures.")
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
                Text("Installation is non-refundable. New monthly charges apply at the next month boundary.")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
            }
            Button { confirming = true } label: {
                VStack(spacing: 4) {
                    Text("Apply Airport Upgrades").font(.headline)
                    Text("\(Format.money(cost)) now · \(Format.money(proposed.monthlyCost(tuning: tuning)))/month").font(.caption)
                }.frame(maxWidth: .infinity, minHeight: 52)
            }.buttonStyle(.aePrimary)
                .disabled(proposed == installed || pending != nil || preview == nil || controller.precheck(command) != nil)
                .accessibilityIdentifier("ae-airport-investment-apply")
            if proposed != installed, let rejection = controller.precheck(command) {
                Text(rejection.message).font(.caption).foregroundStyle(AETheme.caution)
            }
            Button("Reset Changes") { draft = nil; saved = false }
                .frame(minHeight: 44).disabled(proposed == installed || pending != nil)
                .accessibilityIdentifier("ae-airport-investment-reset")
        }
    }
}
