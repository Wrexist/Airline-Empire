import SwiftUI
import AirlineEmpireCore

enum AircraftDetailSection: String, CaseIterable {
    case cabin = "Cabin Layout", upgrades = "Upgrades", operations = "Operations"
    case condition = "Condition", history = "History"
}

struct AircraftDetailTabs: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var selection: AircraftDetailSection
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(AircraftDetailSection.allCases, id: \.self) { section in
                    Button { selection = section } label: {
                        Text(section.rawValue)
                            .font(.caption.weight(selection == section ? .semibold : .regular))
                            .padding(.horizontal, typeSize.isAccessibilitySize ? 16 : 8).frame(minHeight: 44)
                            .background(selection == section ? AETheme.accent.opacity(0.2) : .clear,
                                        in: .rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(selection == section ? AETheme.accent : .clear)
                            }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == section ? .primary : AETheme.mutedText)
                    .accessibilityAddTraits(selection == section ? .isSelected : [])
                    .accessibilityIdentifier("ae-aircraft-tab-\(section.rawValue)")
                }
            }.padding(4)
        }
        .scrollIndicators(.hidden)
        .background(AETheme.sky.opacity(0.7), in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AETheme.surfaceRim.opacity(0.6)) }
    }
}

struct AircraftOverviewCard: View {
    @Environment(GameController.self) private var controller
    @Environment(\.dynamicTypeSize) private var typeSize
    let card: FleetCardModel
    let spec: AircraftTypeSpec
    let change: () -> Void
    private var aircraft: Aircraft? { controller.snapshot?.aircraft[card.id] }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) { title; changeButton }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    title.frame(maxWidth: .infinity, alignment: .leading)
                    changeButton
                }
            }
            AircraftPanel {
                VStack(spacing: 12) {
                    HStack(alignment: .top) {
                        Label(card.status.isInMaintenance ? "Maintenance" : card.status.isOnOrder ? "On Order" : card.assignedRoute == nil ? "Available" : "In Service",
                              systemImage: "circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(card.status.isActive ? AETheme.positive : AETheme.caution)
                        Spacer()
                        if let routeID = card.assignedRoute, let route = controller.snapshot?.routes[routeID] {
                            NavigationLink(value: routeID) {
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("\(route.origin.raw) – \(route.destination.raw)")
                                    Text("\(route.dailyRoundTrips)×/day").foregroundStyle(AETheme.mutedText)
                                }.font(.caption)
                            }.accessibilityLabel("Open assigned route, \(route.origin.raw) to \(route.destination.raw)")
                        } else {
                            Text(card.location.raw).font(.caption).foregroundStyle(AETheme.mutedText)
                        }
                    }
                    if spec.manufacturer == "Pacifica", spec.category == .narrowbody || spec.category == .largeNarrowbody {
                        Image("AircraftPacificaHero")
                            .resizable().scaledToFit()
                            .clipShape(.rect(cornerRadius: 12))
                            .accessibilityHidden(true)
                    } else {
                        AEAircraftMedallion(category: card.category, tint: AETheme.accent, size: 130)
                            .frame(maxWidth: .infinity).accessibilityHidden(true)
                    }
                    LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.adaptive(minimum: 160))] : Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 12) {
                        specItem("Seats", "\(aircraft?.cabin(for: spec).totalSeats ?? spec.seats)", "chair.lounge.fill")
                        specItem("Range", "\(spec.rangeKm.formatted()) km", "arrow.left.and.right")
                        specItem("Cruise speed", "\(spec.cruiseSpeedKmh) km/h", "stopwatch")
                        specItem("runway", Vocab.runway(spec.runwayRequirement).replacingOccurrences(of: " runway", with: ""), "road.lanes")
                        specItem("Fuel / seat / km", "\(Format.decimal(spec.fuelBurnKgPerKm * 1000 / Double(max(1, aircraft?.cabin(for: spec).totalSeats ?? spec.seats)), places: 1)) g", "fuelpump")
                    }
                }
            }
        }
    }
    private var title: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(spec.manufacturer) \(spec.model)").font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
            Text(Vocab.role(spec.role)).font(.caption).foregroundStyle(AETheme.mutedText)
        }
    }
    private var changeButton: some View {
        Button(action: change) {
            HStack(spacing: 6) {
                Text("Change Aircraft").fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.right").accessibilityHidden(true)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(AETheme.accent.opacity(0.1), in: .capsule)
            .overlay { Capsule().strokeBorder(AETheme.surfaceRim) }
        }.buttonStyle(.plain).foregroundStyle(AETheme.accent)
    }
    private func specItem(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(AETheme.accent).accessibilityHidden(true)
            Text(value).font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text(label).font(.caption2).foregroundStyle(AETheme.mutedText).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
    }
}

struct AircraftPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [AETheme.sky, AETheme.canvas], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(AETheme.surfaceRim.opacity(0.65), lineWidth: 1) }
    }
}

extension CabinClass {
    var tint: Color {
        switch self { case .first: AETheme.negative; case .business: AETheme.accent; case .premiumEconomy: AETheme.fare; case .economy: AETheme.positive }
    }
    var abbreviation: String {
        switch self { case .first: "F"; case .business: "B"; case .premiumEconomy: "P"; case .economy: "E" }
    }
}

private struct AircraftPreviewRequest: Equatable {
    let configuration: AircraftConfiguration
    let installed: AircraftConfiguration
    let day: Int64
    let route: RouteID?
}

struct AircraftConfigurationEditor: View {
    @Environment(GameController.self) private var controller
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    let aircraft: Aircraft
    let spec: AircraftTypeSpec
    let snapshot: GameState
    let catalog: ContentCatalog
    let section: AircraftDetailSection
    @Binding var draft: AircraftConfiguration?
    @State private var confirming = false
    @State private var saved = false
    @State private var pending: AircraftConfiguration?
    @State private var preview: AircraftConfigurationPreview?
    @State private var baseline: AircraftConfigurationPreview?
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10),
              count: typeSize.isAccessibilitySize ? 1 : sizeClass == .regular ? 4 : 2)
    }
    private var current: AircraftConfiguration { draft ?? aircraft.cabin(for: spec) }
    private var original: AircraftConfiguration { aircraft.cabin(for: spec) }
    private var changed: Bool { current != original }
    private var command: ConfigureAircraftCommand {
        .init(airline: aircraft.owner, aircraftID: aircraft.id, configuration: current)
    }
    private var price: Money { current.installationCost(from: original, capacity: spec.seats, tuning: catalog.tuning.cabin) }

    var body: some View {
        VStack(spacing: 14) {
            if section == .cabin { cabinPanel.disabled(pending != nil) } else { upgradesPanel.disabled(pending != nil) }
            if changed { commitPanel }
            if saved { Label("Aircraft configuration saved", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(AETheme.positive) }
            performancePanel
            experiencePanel
        }
        .task(id: AircraftPreviewRequest(configuration: current, installed: original,
            day: snapshot.clock.now.dayIndex, route: aircraft.assignedRoute)) { await refreshPreview() }
        .onChange(of: aircraft.configuration) { _, _ in
            if let pending, pending == aircraft.cabin(for: spec) {
                draft = nil; self.pending = nil; saved = true
            }
        }
        .onChange(of: controller.lastRejection) { _, rejection in
            if rejection != nil { pending = nil }
        }
        .confirmationDialog("Apply aircraft refit?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Apply for \(exactMoney(price))") {
                if controller.submit(command) == nil { pending = current }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\(current.totalSeats) seats. Installation: \(exactMoney(price)). Onboard upgrades add \(exactMoney(current.serviceCostPerPassenger(tuning: catalog.tuning.cabin))) per passenger. Demand updates on the next game day.")
        }
    }

    private var cabinPanel: some View {
        AircraftPanel {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        heading("Cabin Layout", "Configure your cabin", "chair.lounge.fill")
                        Spacer(minLength: 8)
                        resetButton
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        heading("Cabin Layout", "Configure your cabin to match your strategy", "chair.lounge.fill")
                        resetButton
                    }
                }
                AircraftSeatMap(configuration: current)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(CabinClass.allCases, id: \.self) { cabin in
                        CabinClassControl(cabin: cabin, configuration: current, capacity: spec.seats) { count in
                            var next = current
                            next.setSeats(count, in: cabin, capacity: spec.seats)
                            draft = next; saved = false
                        }
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack { totalSeats; Spacer(); validLabel }
                    VStack(alignment: .leading, spacing: 8) { totalSeats; validLabel }
                }
                Text("Premium seats use more floor space. Economy fills the remaining cabin automatically.")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
            }
        }
    }
    private var resetButton: some View {
        Button("Reset to Default") {
            var next = current
            for cabin in CabinClass.allCases { next[cabin] = cabin == .economy ? spec.seats : 0 }
            draft = next; saved = false
        }
        .font(.caption).padding(.horizontal, 12).frame(minHeight: 44)
        .background(AETheme.accent.opacity(0.1), in: .capsule)
        .overlay { Capsule().strokeBorder(AETheme.surfaceRim) }
        .buttonStyle(.plain).foregroundStyle(AETheme.accent)
        .accessibilityIdentifier("ae-cabin-reset")
    }
    private var totalSeats: some View { Text("Total seats: \(current.totalSeats)").font(.subheadline.weight(.medium)).monospacedDigit() }
    private var validLabel: some View { Label("Valid configuration", systemImage: "checkmark.circle").font(.caption).foregroundStyle(AETheme.positive) }

    private var upgradesPanel: some View {
        AircraftPanel {
            VStack(alignment: .leading, spacing: 18) {
                heading("Aircraft Upgrades", "Make every journey feel considered", "sparkles")
                ForEach(AircraftUpgrade.allCases, id: \.self) { upgrade in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(upgrade.title, systemImage: icon(upgrade)).font(.headline)
                        Text(upgrade.explanation).font(.caption).foregroundStyle(AETheme.mutedText)
                        Picker(upgrade.title, selection: Binding(get: { current[upgrade] }, set: { value in
                            var next = current; next[upgrade] = value; draft = next; saved = false
                        })) {
                            ForEach(0..<3, id: \.self) { level in Text(upgrade.levels[level]).tag(level) }
                        }.pickerStyle(.menu).frame(minHeight: 44)
                            .accessibilityIdentifier("ae-upgrade-\(upgrade.rawValue)")
                        Text("Each level: +\(Format.decimal(catalog.tuning.cabin.comfortPerUpgradeLevel * 100, places: 1)) comfort points · +\(exactMoney(upgrade.serviceCostPerLevel(tuning: catalog.tuning.cabin))) per passenger. Higher comfort competes for business and leisure demand.")
                            .font(.caption2).foregroundStyle(AETheme.mutedText)
                        Divider()
                    }
                }
                Text("Upgrade service cost: \(exactMoney(current.serviceCostPerPassenger(tuning: catalog.tuning.cabin))) per passenger")
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    private var commitPanel: some View {
        AircraftPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Review your changes").font(.headline)
                Text("One-time refit · \(exactMoney(price))").font(.subheadline).monospacedDigit()
                Text("Demand responds next game day. Refits require an available aircraft on the ground.")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
                Button { confirming = true } label: {
                    Label("Apply Configuration", systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.aePrimary).disabled(pending != nil || controller.precheck(command) != nil)
                    .accessibilityIdentifier("ae-cabin-apply")
                if let rejection = controller.precheck(command) {
                    Text(rejection.message).font(.caption).foregroundStyle(AETheme.caution)
                }
                Button("Discard Changes") { draft = nil; saved = false }.frame(minHeight: 44)
            }
        }
    }

    private var performancePanel: some View {
        AircraftPanel {
            VStack(alignment: .leading, spacing: 14) {
                heading("Expected Route Performance", forecastSubtitle, "chart.bar.fill")
                if let preview {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        metric("Monthly Revenue", Format.money(preview.monthlyRevenue), change: delta(preview.monthlyRevenue, baseline?.monthlyRevenue))
                        metric("Monthly Costs", Format.money(preview.monthlyCosts), change: delta(preview.monthlyCosts, baseline?.monthlyCosts))
                        metric("Monthly Profit", Format.money(preview.monthlyProfit), change: delta(preview.monthlyProfit, baseline?.monthlyProfit))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Load Factor").font(.caption).foregroundStyle(AETheme.mutedText)
                            Text(preview.loadFactor.formatted(.percent.precision(.fractionLength(0)))).font(.title3.bold()).monospacedDigit()
                            ProgressView(value: preview.loadFactor).tint(AETheme.positive)
                        }.accessibilityElement(children: .combine)
                    }
                    if preview.monthlyProfit < .zero {
                        Label("This configuration is forecast to lose money on the assigned route.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(AETheme.caution)
                    }
                    DisclosureGroup("What this estimate includes") {
                        Text("30-day estimate at today's demand and prices. Includes fuel, fees, crew, service, maintenance reserve and lease. Excludes company overhead and fixed airport services, future disruptions and refit cost. Fleet scheduling can change the result.")
                            .font(.caption2).foregroundStyle(AETheme.mutedText)
                    }.font(.caption).tint(AETheme.mutedText)
                } else {
                    Text(aircraft.assignedRoute == nil ? "Assign a route in Operations to see a forecast for this aircraft." : "A forecast is available when this aircraft is operational.")
                        .font(.subheadline).foregroundStyle(AETheme.mutedText)
                }
            }
        }
    }
    private var forecastSubtitle: String {
        guard let id = aircraft.assignedRoute, let route = snapshot.routes[id] else { return "Estimates based on your assigned route" }
        return "\(route.origin.raw) – \(route.destination.raw) · \(route.distanceKm.formatted()) km · \(preview?.rotationsPerDay ?? 0) rotations/day"
    }
    private func metric(_ title: String, _ value: String, change: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(AETheme.mutedText)
            Text(value).font(.title3.bold()).monospacedDigit()
            if let change { Text(change).font(.caption).foregroundStyle(AETheme.accent) }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
    private func delta(_ value: Money, _ old: Money?) -> String? {
        guard changed, let old else { return nil }
        let difference = value - old
        return "\(difference.cents >= 0 ? "+" : "")\(Format.money(difference)) vs current"
    }
    private func refreshPreview() async {
        let configuration = current
        let installed = original
        let id = aircraft.id
        let state = snapshot
        let content = catalog
        // Debounce sliders; only pure Core work leaves the main actor.
        do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
        let results = await Task.detached(priority: .userInitiated) {
            (AircraftConfigurationPreview.make(aircraftID: id, configuration: configuration, state: state, catalog: content),
             AircraftConfigurationPreview.make(aircraftID: id, configuration: installed, state: state, catalog: content))
        }.value
        guard !Task.isCancelled else { return }
        preview = results.0; baseline = results.1
    }
    private var experiencePanel: some View {
        let experience = AircraftPassengerExperience(aircraft: aircraft, configuration: current,
            spec: spec, state: snapshot, catalog: catalog)
        return AircraftPanel {
            VStack(alignment: .leading, spacing: 14) {
                heading("Passenger Experience", "Better journeys build your airline's reputation", "person.2.fill")
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Expected happiness").font(.subheadline)
                        GeometryReader { geometry in
                            Capsule().fill(LinearGradient(colors: [AETheme.negative, AETheme.caution, AETheme.positive], startPoint: .leading, endPoint: .trailing))
                            Capsule().fill(.white).frame(width: 3, height: 18)
                                .offset(x: max(0, geometry.size.width - 3) * experience.happiness, y: -3)
                        }.frame(height: 12).accessibilityHidden(true)
                    }
                    Text(experience.happiness.formatted(.percent.precision(.fractionLength(0))))
                        .font(.title2.bold()).foregroundStyle(AETheme.positive).monospacedDigit()
                }.accessibilityElement(children: .combine)
                Text("Estimated from cabin comfort, service, reliability and punctuality.")
                    .font(.caption2).foregroundStyle(AETheme.mutedText)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(AircraftUpgrade.allCases, id: \.self) { upgrade in
                        HStack(spacing: 10) {
                            Image(systemName: icon(upgrade)).font(.title3).foregroundStyle(AETheme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(upgrade.title).font(.caption).foregroundStyle(AETheme.mutedText)
                                Text(upgrade.levels[current[upgrade]]).font(.caption.weight(.semibold))
                                ProgressView(value: Double(current[upgrade]), total: 2)
                                    .tint(upgrade == .dining ? AETheme.caution : AETheme.positive)
                                    .accessibilityLabel("Equipment level")
                                    .accessibilityValue("\(current[upgrade]) of 2")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10).background(AETheme.cardBackground.opacity(0.55), in: .rect(cornerRadius: 12))
                            .accessibilityElement(children: .combine)
                    }
                }
                Divider()
                Label("Reputation Impact", systemImage: "star.fill").font(.headline).foregroundStyle(AETheme.caution)
                Text("This aircraft contributes its seat-weighted comfort to your fleet's reputation. Reliability and punctuality also shape passenger experience.")
                    .font(.caption).foregroundStyle(AETheme.mutedText)
                HStack {
                    Text("Dispatch reliability").font(.caption)
                    Spacer()
                    Text(aircraft.currentReliability(type: spec, tuning: catalog.tuning.fleet).formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.weight(.semibold)).monospacedDigit()
                }
            }
        }
    }
    private func heading(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(AETheme.accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(AETheme.mutedText)
            }
        }
    }
    private func exactMoney(_ amount: Money) -> String {
        "$\(Format.decimal(amount.asDouble, places: 2))"
    }
    private func icon(_ upgrade: AircraftUpgrade) -> String {
        switch upgrade { case .wifi: "wifi"; case .dining: "cup.and.saucer.fill"; case .seats: "chair.lounge.fill"; case .entertainment: "play.rectangle" }
    }
}

struct CabinClassControl: View {
    let cabin: CabinClass
    let configuration: AircraftConfiguration
    let capacity: Int
    let set: (Int) -> Void
    private var count: Int { configuration[cabin] }
    private var maximum: Int { (configuration.economy + count * cabin.space) / cabin.space }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(cabin.title, systemImage: "chair.lounge.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(cabin.tint)
                .frame(minHeight: 32, alignment: .topLeading)
            Text("\(count) seats").font(.subheadline).monospacedDigit()
            Text((Double(count) / Double(max(1, configuration.totalSeats))).formatted(.percent.precision(.fractionLength(0))))
                .font(.caption.weight(.semibold)).monospacedDigit()
            if cabin == .economy {
                ProgressView(value: Double(count), total: Double(max(1, capacity))).tint(cabin.tint)
                Text("Fills remaining space").font(.caption2).foregroundStyle(AETheme.mutedText).frame(minHeight: 44)
            } else {
                Slider(value: Binding(get: { Double(count) }, set: { set(Int($0)) }), in: 0...Double(max(1, maximum)), step: 1)
                    .tint(cabin.tint).disabled(maximum == 0)
                    .accessibilityLabel("\(cabin.title) seats").accessibilityValue("\(count)")
                    .accessibilityIdentifier("ae-cabin-slider-\(cabin.rawValue)")
                HStack {
                    Button { set(count - 1) } label: { Image(systemName: "minus").frame(minWidth: 44, minHeight: 44) }
                        .disabled(count == 0).accessibilityLabel("Remove one \(cabin.title) seat")
                    Spacer(minLength: 4)
                    Button { set(count + 1) } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }
                        .disabled(count >= maximum).accessibilityLabel("Add one \(cabin.title) seat")
                        .accessibilityIdentifier("ae-cabin-plus-\(cabin.rawValue)")
                }.buttonStyle(AircraftSeatStepStyle(tint: cabin.tint))
            }
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AETheme.cardBackground.opacity(0.45), in: .rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(cabin.tint.opacity(0.25)) }
    }
}

private struct AircraftSeatStepStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? tint : AETheme.mutedText.opacity(0.4))
            .background(tint.opacity(configuration.isPressed ? 0.24 : 0.1), in: .circle)
            .overlay { Circle().strokeBorder(tint.opacity(0.25)) }
    }
}

/// A vector cutaway with exactly one mark per passenger seat. Class initials
/// and the textual legend supplement color for color-blind and VoiceOver use.
struct AircraftSeatMap: View {
    let configuration: AircraftConfiguration
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            var wing = Path()
            wing.move(to: CGPoint(x: w * 0.44, y: h * 0.4))
            wing.addLine(to: CGPoint(x: w * 0.62, y: 4))
            wing.addLine(to: CGPoint(x: w * 0.69, y: 4))
            wing.addLine(to: CGPoint(x: w * 0.6, y: h * 0.5))
            wing.addLine(to: CGPoint(x: w * 0.69, y: h - 4))
            wing.addLine(to: CGPoint(x: w * 0.62, y: h - 4))
            wing.closeSubpath()
            context.fill(wing, with: .linearGradient(Gradient(colors: [AETheme.surfaceRim, AETheme.sky]), startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
            let body = CGRect(x: 2, y: h * 0.23, width: w - 4, height: h * 0.54)
            let hull = Path(roundedRect: body, cornerRadius: h * 0.27)
            context.fill(hull, with: .linearGradient(Gradient(colors: [AETheme.mutedText, AETheme.canvas, AETheme.sky, AETheme.mutedText]), startPoint: CGPoint(x: 0, y: body.minY), endPoint: CGPoint(x: 0, y: body.maxY)))
            context.stroke(hull, with: .color(AETheme.mutedText.opacity(0.8)), lineWidth: 1.5)
            let inside = CGRect(x: w * 0.12, y: h * 0.28, width: w * 0.75, height: h * 0.44)
            context.fill(Path(roundedRect: inside, cornerRadius: 12), with: .color(AETheme.canvas))
            let rows = 4
            let totalColumns = CabinClass.allCases.reduce(0) { $0 + ((configuration[$1] + rows - 1) / rows) * $1.space }
            let gap: CGFloat = 3
            let columnWidth = (inside.width - 12 - gap * 3) / CGFloat(max(1, totalColumns))
            let seatHeight = (inside.height - 20) / 4
            var x = inside.minX + 6
            for cabin in CabinClass.allCases {
                let count = configuration[cabin]
                if count == 0 { continue }
                let classWidth = columnWidth * CGFloat(cabin.space)
                let sectionWidth = CGFloat((count + rows - 1) / rows) * classWidth
                context.draw(Text(cabin.abbreviation).font(.system(size: 9, weight: .bold)).foregroundStyle(cabin.tint),
                             at: CGPoint(x: x + sectionWidth / 2, y: h * 0.19))
                for seat in 0..<count {
                    let column = seat / rows, row = seat % rows
                    let y = inside.minY + 5 + CGFloat(row) * (seatHeight + 2) + (row >= 2 ? 6 : 0)
                    let rect = CGRect(x: x + CGFloat(column) * classWidth, y: y,
                                      width: max(1, classWidth - 1.5), height: seatHeight)
                    let shape = Path(roundedRect: rect, cornerRadius: min(2, columnWidth / 4))
                    context.fill(shape, with: .color(cabin.tint))
                    context.stroke(shape, with: .color(.white.opacity(0.35)), lineWidth: 0.5)
                    if rect.width > 4 {
                        let back = CGRect(x: rect.minX + 1, y: rect.maxY - 3, width: max(1, rect.width - 2), height: 2)
                        context.fill(Path(roundedRect: back, cornerRadius: 1), with: .color(.black.opacity(0.3)))
                    }
                }
                x += sectionWidth + gap
            }
            context.draw(Image(systemName: "cup.and.saucer.fill"), in: CGRect(x: w * 0.035, y: h * 0.44, width: w * 0.055, height: h * 0.12))
            context.draw(Text("WC").font(.system(size: 9, weight: .bold)).foregroundStyle(AETheme.mutedText), at: CGPoint(x: w * 0.92, y: h * 0.5))
        }
        .frame(height: 130)
        .accessibilityLabel("Cabin seat map. Front galley, rear lavatories. " + CabinClass.allCases.map { "\(configuration[$0]) \($0.title) seats" }.joined(separator: ", "))
        .accessibilityIdentifier("ae-aircraft-seat-map")
    }
}

struct AircraftHistoryCard: View {
    let aircraft: Aircraft
    let snapshot: GameState
    private var maintenanceEntries: [String] {
        snapshot.eventLog.recent.reversed().compactMap { event -> String? in
            let description: String
            switch event.kind {
            case .maintenanceStarted(let id, _, let cost) where id == aircraft.id:
                description = "Maintenance started · \(Format.money(cost))"
            case .maintenanceCompleted(let id) where id == aircraft.id:
                description = "Maintenance completed"
            case .aircraftDelivered(let id) where id == aircraft.id:
                description = "Aircraft delivered"
            default: return nil
            }
            return "\(Format.date(GameCalendar.date(at: event.at, startYear: snapshot.meta.startYear))) · \(description)"
        }.prefix(8).map { $0 }
    }
    var body: some View {
        AircraftPanel {
            VStack(alignment: .leading, spacing: 14) {
                Label("Configuration History", systemImage: "clock.arrow.circlepath").font(.headline)
                if let history = aircraft.configurationHistory, !history.isEmpty {
                    ForEach(history, id: \.id) { change in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Day \(change.at.dayIndex + 1) · Aircraft refit").font(.subheadline.weight(.semibold))
                            Text("\(change.configuration.totalSeats) seats · \(Format.money(change.cost))").font(.caption).foregroundStyle(AETheme.mutedText)
                        }
                    }
                } else {
                    Text("No cabin changes recorded yet.").font(.subheadline).foregroundStyle(AETheme.mutedText)
                }
                Text("The latest 50 refits are kept with this aircraft.").font(.caption2).foregroundStyle(AETheme.mutedText)
                Divider()
                Label("Recent Maintenance & Delivery", systemImage: "wrench.and.screwdriver").font(.headline)
                Text(maintenanceEntries.isEmpty ? "No maintenance or delivery events in the recent activity log." : maintenanceEntries.joined(separator: "\n\n"))
                    .font(.subheadline).foregroundStyle(AETheme.mutedText)
            }
        }
    }
}
