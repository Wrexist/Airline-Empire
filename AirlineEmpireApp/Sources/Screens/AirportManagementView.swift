import SwiftUI
import AirlineEmpireCore

enum AirportManagementSection: String, CaseIterable {
    case overview = "Overview", network = "Your Network", facilities = "Facilities"
    case competition = "Competition", history = "History"
}

struct AirportDetailView: View {
    @Environment(GameController.self) private var controller
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var section: AirportManagementSection
    @State private var draft: AirportFacilities?
    @State private var routeSheet: RouteDraft?
    let code: AirportCode

    init(code: AirportCode, initialSection: AirportManagementSection = .overview) {
        self.code = code; _section = State(initialValue: initialSection)
    }
    var body: some View {
        ScrollView {
            if let state = controller.snapshot, let player = state.playerAirline,
               let catalog = controller.catalog, let spec = catalog.airport(code) {
                let routes = state.routes(of: player.id).filter { $0.origin == code || $0.destination == code }
                VStack(spacing: 14) {
                    hero(spec, state: state, player: player, routes: routes)
                    tabs
                    switch section {
                    case .overview:
                        market(spec)
                        capacity(spec, state: state, player: player)
                        AircraftPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                AirportHeading(title: "Build your airport presence", icon: "building.2.crop.circle")
                                Text("Connect cities, compare local rivals and invest in the experience your passengers receive on the ground.")
                                    .font(.subheadline).foregroundStyle(AETheme.mutedText)
                                Button("Manage airport services") { section = .facilities }
                                    .buttonStyle(.bordered).frame(minHeight: 44)
                            }
                        }
                    case .network: network(spec, routes: routes, player: player, catalog: catalog)
                    case .facilities:
                        AirportFacilityEditor(airport: code, player: player, snapshot: state, catalog: catalog, draft: $draft)
                    case .competition: competition(state: state, player: player)
                    case .history: history(player: player)
                    }
                }.frame(maxWidth: 920).frame(maxWidth: .infinity).aePageInsets()
            } else { LoadingState(message: "Loading the airport").frame(minHeight: 240) }
        }
        .aeScreenBackground().navigationTitle(code.raw).navigationBarTitleDisplayMode(.inline).aeTimeToolbar()
        .sheet(item: $routeSheet) { OpenRouteSheet(suggestion: $0.suggestion) }
        .navigationDestination(for: RouteID.self) { RouteDetailView(routeID: $0) }
        .navigationDestination(for: AircraftID.self) { AircraftDetailView(aircraftID: $0) }
    }
    private var tabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(AirportManagementSection.allCases, id: \.self) { item in
                    Button { section = item } label: {
                        Text(item.rawValue).font(.caption.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 44)
                            .background(section == item ? AETheme.accent.opacity(0.2) : .clear, in: .rect(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(section == item ? AETheme.accent : .clear) }
                    }.buttonStyle(.plain).foregroundStyle(section == item ? .primary : AETheme.mutedText)
                        .accessibilityAddTraits(section == item ? .isSelected : [])
                        .accessibilityIdentifier("ae-airport-tab-\(item.rawValue)")
                }
            }.padding(4)
        }.scrollIndicators(.hidden).background(AETheme.sky, in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AETheme.surfaceRim) }
    }
    private func hero(_ spec: AirportSpec, state: GameState, player: Airline, routes: [Route]) -> some View {
        let closed = state.world.isAirportClosed(code, at: state.clock.now)
        return AircraftPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(code.raw).font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text(spec.city).font(.title3.weight(.semibold))
                        Text(spec.name).font(.caption).foregroundStyle(AETheme.mutedText)
                    }
                    Spacer()
                    if !typeSize.isAccessibilitySize {
                        Image(systemName: "airplane.departure").font(.system(size: 42)).foregroundStyle(AETheme.accent)
                            .padding(14).background(AETheme.accent.opacity(0.1), in: .rect(cornerRadius: 20)).accessibilityHidden(true)
                    }
                }
                AEChipRow {
                    AEBadge(text: closed ? "Temporarily closed" : "Open", color: closed ? AETheme.caution : AETheme.positive, icon: closed ? "xmark.octagon" : "checkmark.circle")
                    AEBadge(text: code == player.homeAirport ? "Home airport" : routes.isEmpty ? "Potential destination" : "Network airport", color: AETheme.accent)
                    AEBadge(text: spec.country, color: .secondary)
                }
                LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 120))], alignment: .leading, spacing: 12) {
                    AirportMetric(title: "Your routes", value: "\(routes.count)", icon: "point.topleft.down.to.point.bottomright.curvepath")
                    AirportMetric(title: "Daily round trips", value: "\(routes.reduce(0) { $0 + $1.dailyRoundTrips })", icon: "arrow.triangle.2.circlepath")
                    AirportMetric(title: "Your daily slots", value: "\(state.world.slotsHeld(by: player.id, at: code))", icon: "clock")
                }
                Text("\(Vocab.runwayDetail(spec.runwayClass)) · \(Vocab.weatherRisk(spec.weatherRisk))")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
            }
        }
    }
    private func market(_ spec: AirportSpec) -> some View {
        AircraftPanel {
            VStack(alignment: .leading, spacing: 14) {
                AirportHeading(title: "Local demand", icon: "person.3.fill")
                Text("\(Format.count(Int64(spec.demographics.populationThousands))) thousand people in the catchment")
                    .font(.subheadline).foregroundStyle(AETheme.mutedText)
                demandBar("Business", value: spec.demographics.businessIndex, color: AETheme.accent)
                demandBar("Leisure", value: spec.demographics.leisureIndex, color: AETheme.positive)
                demandBar("Tourism", value: spec.demographics.tourismIndex, color: .purple)
                Text("These are market strength indices, not passenger shares. Actual route demand also depends on distance, season, fares and competitors.")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
            }
        }
    }
    private func demandBar(_ title: String, value: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack { Text(title); Spacer(); Text("\(Int((value * 100).rounded())) / 100").monospacedDigit() }.font(.subheadline)
            ProgressView(value: value).tint(color).accessibilityLabel("\(title) strength")
        }
    }
    private func capacity(_ spec: AirportSpec, state: GameState, player: Airline) -> some View {
        let used = state.world.slotsUsed(at: code), held = state.world.slotsHeld(by: player.id, at: code)
        return AircraftPanel {
            VStack(alignment: .leading, spacing: 12) {
                AirportHeading(title: "Slots & airport fees", icon: "clock.fill")
                AirportFact(title: "Available daily slots", value: "\(max(0, spec.slotCapacityPerDay - used)) / \(spec.slotCapacityPerDay)")
                ProgressView(value: min(1, Double(used) / Double(max(1, spec.slotCapacityPerDay))))
                    .tint(used > spec.slotCapacityPerDay * 85 / 100 ? AETheme.caution : AETheme.accent)
                    .accessibilityLabel("Daily slot utilization")
                AirportFact(title: "Your slots / other airlines", value: "\(held) / \(max(0, used - held))")
                Text("Each round trip reserves two movements here. Investments do not increase the airport's slot capacity.")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
                Divider()
                AirportFact(title: "Reference movement fee", value: Format.money(spec.movementFee))
                AirportFact(title: "Per departing passenger", value: Format.money(spec.passengerFee))
                Text("Movement charges scale with aircraft size. Final fees are included in route forecasts.")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
            }
        }
    }
    private func network(_ spec: AirportSpec, routes: [Route], player: Airline, catalog: ContentCatalog) -> some View {
        AircraftPanel {
            VStack(alignment: .leading, spacing: 14) {
                AirportHeading(title: "Your network at \(code.raw)", icon: "point.3.connected.trianglepath.dotted")
                if routes.isEmpty { Text("You do not serve this airport yet.").foregroundStyle(AETheme.mutedText) }
                ForEach(routes, id: \.id) { route in
                    NavigationLink(value: route.id) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text("\(route.origin.raw) – \(route.destination.raw)").font(.headline); Spacer(); Image(systemName: "chevron.right") }
                            Text("\(route.dailyRoundTrips) round trips/day · \(route.assignedAircraft.count) aircraft · \(Format.money(route.ticketPrice)) base fare")
                                .font(.caption).foregroundStyle(AETheme.mutedText)
                        }.frame(minHeight: 54)
                    }.buttonStyle(.plain)
                }
                if code != player.homeAirport, let distance = catalog.distanceKm(player.homeAirport, code) {
                    Button {
                        routeSheet = RouteDraft(suggestion: FirstRouteSuggestion(origin: player.homeAirport, destination: code,
                            destinationCity: spec.city, distanceKm: distance, expectedDailyPassengers: 0,
                            referenceFare: Money(rounding: DemandSystem.referenceFare(distanceKm: distance, tuning: catalog.tuning.demand))))
                    } label: { Label("Open a route from \(player.homeAirport.raw)", systemImage: "plus.circle").frame(minHeight: 44) }
                        .buttonStyle(.bordered)
                }
                Text("Manage each route to change fares, frequency or aircraft. Your home airport remains \(player.homeAirport.raw).")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
            }
        }
    }
    private func competition(state: GameState, player: Airline) -> some View {
        let rivals = state.orderedAirlineIDs.compactMap { state.airlines[$0] }.filter { $0.id != player.id && state.world.slotsHeld(by: $0.id, at: code) > 0 }
            .sorted { state.world.slotsHeld(by: $0.id, at: code) > state.world.slotsHeld(by: $1.id, at: code) }
        return AircraftPanel {
            VStack(alignment: .leading, spacing: 14) {
                AirportHeading(title: "Airport competition", icon: "chart.bar.xaxis")
                Text("Presence is measured by reserved daily movements, not passenger market share.")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
                if rivals.isEmpty { Text("No rival airlines currently reserve slots here.").font(.subheadline) }
                ForEach(rivals, id: \.id) { rival in
                    VStack(alignment: .leading, spacing: 5) {
                        AirportFact(title: rival.name, value: "\(state.world.slotsHeld(by: rival.id, at: code)) slots")
                        let routes = state.routes(of: rival.id).filter { $0.origin == code || $0.destination == code }
                        ForEach(routes, id: \.id) { route in
                            Text("\(route.origin.raw)–\(route.destination.raw) · \(route.dailyRoundTrips)/day · \(Format.money(route.ticketPrice))")
                                .font(.caption).foregroundStyle(AETheme.mutedText)
                        }
                    }
                    Divider()
                }
                Text("Open a route's Competition section to compare fares and demand on that specific market.")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
            }
        }
    }
    private func history(player: Airline) -> some View {
        let changes = (player.airportFacilityHistory ?? []).filter { $0.airport == code }
        return AircraftPanel {
            VStack(alignment: .leading, spacing: 14) {
                AirportHeading(title: "Airport investment history", icon: "clock.arrow.circlepath")
                if changes.isEmpty { Text("Confirmed facility changes will appear here.").foregroundStyle(AETheme.mutedText) }
                ForEach(changes, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        AirportFact(title: "Day \(item.at.dayIndex + 1)", value: Format.money(item.cost))
                        Text("Lounge: \(item.previous.lounge) → \(item.updated.lounge) · Ground services: \(item.previous.groundServices) → \(item.updated.groundServices)")
                            .font(.caption).foregroundStyle(AETheme.mutedText)
                    }
                    Divider()
                }
                Text("Shows this airport's changes from your airline's latest 100 facility decisions.")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
            }
        }
    }
}

private struct AirportHeading: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let icon: String
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize { Text(title) }
            else { Label(title, systemImage: icon) }
        }.font(.headline).accessibilityAddTraits(.isHeader)
    }
}

private struct AirportMetric: View {
    let title: String; let value: String; let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(AETheme.mutedText)
            Text(value).font(.title3.bold()).monospacedDigit()
        }.accessibilityElement(children: .combine)
    }
}

struct AirportFact: View {
    let title: String; let value: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) { Text(title); Spacer(); Text(value).monospacedDigit().fontWeight(.semibold) }
            VStack(alignment: .leading, spacing: 5) { Text(title); Text(value).monospacedDigit().fontWeight(.semibold) }
        }.font(.subheadline).accessibilityElement(children: .combine)
    }
}

private struct AirportQuoteRequest: Equatable {
    let proposed: AirportFacilities; let installed: AirportFacilities; let day: Int64
}

struct AirportFacilityEditor: View {
    @Environment(GameController.self) private var controller
    @Environment(\.dynamicTypeSize) private var typeSize
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
    private var command: ConfigureAirportFacilitiesCommand { .init(airline: player.id, airport: airport, facilities: proposed) }

    var body: some View {
        VStack(spacing: 14) {
            AircraftPanel {
                VStack(alignment: .leading, spacing: 12) {
                    AirportHeading(title: "Airport services", icon: "building.2.fill")
                    Text("Create a better experience at \(airport.raw). Services belong to your airline and benefit your routes here.")
                        .font(.subheadline).foregroundStyle(AETheme.mutedText)
                    AirportFact(title: "Installed monthly cost", value: Format.money(installed.monthlyCost(tuning: tuning)))
                }
            }
            facility(title: "Passenger lounge", icon: "cup.and.saucer.fill", color: .purple, keyPath: \.lounge,
                description: "A quieter place to wait, with refreshments and space to work.",
                benefit: "Up to +\(Int((Double(proposed.lounge) * tuning.loungeComfortPerLevel * 100).rounded())) comfort points here. Route comfort averages its two airports and is capped at 100.",
                monthly: tuning.loungeMonthly, setup: tuning.loungeInstallation)
            facility(title: "Ground services", icon: "person.2.gearshape.fill", color: AETheme.accent, keyPath: \.groundServices,
                description: "Dedicated support helps your aircraft depart reliably.",
                benefit: "\(Int((Double(proposed.groundServices) * tuning.groundRiskReductionPerLevel * 100).rounded()))% lower technical disruption risk on departures here. Weather risk is unchanged.",
                monthly: tuning.groundMonthly, setup: tuning.groundInstallation)
            AircraftPanel {
                VStack(alignment: .leading, spacing: 12) {
                    AirportHeading(title: "Investment preview", icon: "chart.line.uptrend.xyaxis")
                    AirportFact(title: "Installation now", value: Format.money(cost))
                    AirportFact(title: "Proposed monthly services", value: Format.money(proposed.monthlyCost(tuning: tuning)))
                    if let preview {
                        Divider()
                        AirportFact(title: "Monthly route revenue change", value: Format.money(preview.monthlyRevenueChange))
                        AirportFact(title: "Monthly net change", value: Format.money(preview.monthlyNetChange))
                            .foregroundStyle(preview.monthlyNetChange >= .zero ? AETheme.positive : AETheme.caution)
                        Text("Across \(preview.servedRoutes) routes at current fares, cabins and demand. Includes the change in route costs and this airport's monthly services; excludes installation and future disruption savings.")
                            .font(.caption).foregroundStyle(AETheme.mutedText)
                        if proposed != installed && preview.monthlyNetChange < .zero {
                            Label("Current demand gains do not cover the added monthly cost.", systemImage: "info.circle")
                                .font(.caption).foregroundStyle(AETheme.caution)
                        }
                    } else { ProgressView("Calculating route effects…").font(.caption) }
                    Text("Ground service benefits appear in actual operations over time. The forecast does not assume guaranteed savings or passenger growth.")
                        .font(.caption).foregroundStyle(AETheme.mutedText)
                }
            }
            if proposed != installed {
                AircraftPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Review investment").font(.headline)
                        Text("Lounge: \(installed.lounge) → \(proposed.lounge)\nGround services: \(installed.groundServices) → \(proposed.groundServices)").font(.subheadline)
                        Text("Installation is non-refundable. Monthly charges begin at the next month boundary and continue even if routes close. Set both levels to 0 to stop future service charges; reopening requires installation again.")
                            .font(.caption).foregroundStyle(AETheme.mutedText)
                        Button { confirming = true } label: { Text("Apply Airport Investment").frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(.aePrimary).disabled(pending != nil || controller.precheck(command) != nil)
                            .accessibilityIdentifier("ae-airport-investment-apply")
                        if let rejection = controller.precheck(command) { Text(rejection.message).font(.caption).foregroundStyle(AETheme.caution) }
                        Button("Discard Changes") { draft = nil; saved = false }.frame(minHeight: 44).disabled(pending != nil)
                    }
                }
            }
            if saved { Label("Airport investment saved", systemImage: "checkmark.circle.fill").foregroundStyle(AETheme.positive) }
        }
        .task(id: AirportQuoteRequest(proposed: proposed, installed: installed, day: snapshot.clock.now.dayIndex)) {
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
        .confirmationDialog("Apply airport investment?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Confirm Airport Investment") { if controller.submit(command) == nil { pending = proposed } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Pay \(Format.money(cost)) now. Services cost \(Format.money(proposed.monthlyCost(tuning: tuning))) each month. Lounge demand changes apply at the next daily update; ground services apply to future departures.")
        }
    }
    private func facility(title: String, icon: String, color: Color, keyPath: WritableKeyPath<AirportFacilities, Int>,
                          description: String, benefit: String, monthly: Money, setup: Money) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return AircraftPanel {
            VStack(alignment: .leading, spacing: 12) {
                if typeSize.isAccessibilitySize {
                    Text(title).font(.headline).foregroundStyle(color)
                } else {
                    Label(title, systemImage: icon).font(.headline).foregroundStyle(color)
                }
                Text(description).font(.caption).foregroundStyle(AETheme.mutedText)
                layout {
                    ForEach(0...2, id: \.self) { level in
                        Button {
                            var next = proposed; next[keyPath: keyPath] = level; draft = next; saved = false
                        } label: {
                            VStack(spacing: 5) {
                                Text(level == 0 ? "None" : level == 1 ? "Standard" : "Premium").font(.caption.weight(.semibold))
                                Text("Level \(level)").font(.caption2)
                            }.frame(maxWidth: .infinity, minHeight: 52)
                                .background(proposed[keyPath: keyPath] == level ? color.opacity(0.18) : .clear, in: .rect(cornerRadius: 12))
                                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(proposed[keyPath: keyPath] == level ? color : AETheme.surfaceRim) }
                        }.buttonStyle(.plain).disabled(pending != nil)
                            .accessibilityLabel("\(title), level \(level)")
                            .accessibilityAddTraits(proposed[keyPath: keyPath] == level ? .isSelected : [])
                            .accessibilityIdentifier("ae-airport-\(keyPath == \.lounge ? "lounge" : "ground")-\(level)")
                    }
                }
                Text(benefit).font(.subheadline)
                Text("Per level: \(Format.money(setup)) installation · \(Format.money(monthly))/month")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
            }
        }
    }
}
