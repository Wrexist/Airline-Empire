import SwiftUI
import Charts
import AirlineEmpireCore

// The dashboard's floating panels (docs/HUB_VIEW_3D.md §1): the insights
// side panel, and the dropdowns under the top bar — alerts, airline
// summary, hub switcher, layers, search. Same frosted glass as every card.

/// Route colours, matching the fan in the world (`HubMaterialKey.routeArc`).
enum HubRouteStyle {
    static let colors: [Color] = [
        Color(red: 0.25, green: 0.88, blue: 0.91), // no flights yet
        Color(red: 0.13, green: 0.72, blue: 0.55), // full
        Color(red: 0.93, green: 0.64, blue: 0.20), // fair
        Color(red: 0.90, green: 0.36, blue: 0.48), // thin
    ]

    static func band(_ loadFactor: Double?) -> Int {
        guard let lf = loadFactor else { return 0 }
        return lf >= 0.75 ? 1 : lf >= 0.55 ? 2 : 3
    }

    static func tint(_ loadFactor: Double?) -> Color { colors[band(loadFactor)] }
}

extension HubAlert.Kind {
    var systemImage: String {
        switch self {
        case .delay: "clock.badge.exclamationmark"
        case .lowLoad: "person.2.slash"
        case .slots: "square.grid.3x3.fill"
        case .terminal: "person.3.sequence.fill"
        case .maintenance: "wrench.and.screwdriver.fill"
        }
    }

    var tint: Color {
        switch self {
        case .delay, .slots: HubChromeStyle.warn
        case .lowLoad, .terminal: HubChromeStyle.bad
        case .maintenance: HubChromeStyle.accent
        }
    }
}

/// A labelled bar, 0…1, for gauges and shares.
struct HubMeter: View {
    let title: String
    let value: Double
    var detail: String?
    var tint: Color = HubChromeStyle.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11)).foregroundStyle(HubChromeStyle.secondary)
                Spacer()
                Text(detail ?? Format.percent(value))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(HubChromeStyle.ink)
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(HubChromeStyle.track)
                    Capsule().fill(tint)
                        .frame(width: max(4, geo.size.width * CGFloat(min(1, max(0, value)))))
                }
            }
            .frame(height: 6)
            .animation(HubMotion.data, value: value)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Insights

@available(iOS 18.0, *)
struct HubInsightsPanel: View {
    @Bindable var model: HubScreenModel
    let mode: HubChromeMode

    var body: some View {
        let insights = model.snapshot?.insights ?? .empty
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HubIconTile(systemName: "chart.bar.xaxis", size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hub insights").font(.system(size: 15, weight: .bold)).foregroundStyle(HubChromeStyle.ink)
                    Text("\(model.snapshot?.airportName ?? model.airport.raw)")
                        .font(.system(size: 11)).foregroundStyle(HubChromeStyle.secondary).lineLimit(1)
                }
                Spacer()
                Button {
                    withAnimation(HubMotion.panel) { model.panel = nil }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(HubChromeStyle.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.6), in: Circle())
                }
                .buttonStyle(HubPressStyle())
                .accessibilityLabel("Close insights")
            }
            Picker("Section", selection: $model.insightsTab) {
                ForEach(HubInsightsTab.allCases) { tab in Text(tab.rawValue).tag(tab) }
            }
            .pickerStyle(.segmented)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    switch model.insightsTab {
                    case .overview: overview(insights)
                    case .routes: routes(insights)
                    case .slots: slots(insights)
                    case .airline: airline(insights)
                    }
                }
                .padding(.bottom, 6)
                .id(model.insightsTab)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .animation(HubMotion.snap, value: model.insightsTab)
        }
        .frame(width: mode == .regular ? 380 : 350)
        .frame(maxHeight: .infinity, alignment: .top)
        .hubGlass(padding: 14)
        .accessibilityIdentifier("ae-hub-insights-panel")
    }

    // MARK: Overview

    @ViewBuilder
    private func overview(_ insights: HubInsights) -> some View {
        let k = model.snapshot?.kpis
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            tile("clock.badge.checkmark", "On time", k?.onTimeRate.map { Format.percent($0) } ?? "—")
            tile("person.2.fill", "Load factor", k?.loadFactor.map { Format.percent($0) } ?? "—")
            tile("figure.walk", "Passengers today", "\(k?.passengersToday ?? 0)")
            tile("arrow.left.arrow.right", "Movements / hour",
                 String(format: "%.1f", model.snapshot?.movementsPerHour ?? 0))
        }
        VStack(spacing: 10) {
            HubMeter(title: "Terminal load", value: k?.terminalLoad ?? 0,
                     tint: (k?.terminalLoad ?? 0) >= 0.85 ? HubChromeStyle.bad : HubChromeStyle.accent)
            HubMeter(title: "Slot use", value: k?.slotUse ?? 0,
                     tint: (k?.slotUse ?? 0) >= 0.9 ? HubChromeStyle.warn : HubChromeStyle.accent)
        }
        section("Your movements today") {
            let now = (model.snapshot?.localMinuteOfDay ?? 0) / 60
            Chart(Array(insights.movementsByHour.enumerated()), id: \.offset) { hour, count in
                BarMark(x: .value("Hour", hour), y: .value("Movements", count), width: .fixed(8))
                    .foregroundStyle(hour == now ? HubChromeStyle.accent : HubChromeStyle.accent.opacity(0.35))
                    .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18]) { value in
                    AxisValueLabel {
                        if let h = value.as(Int.self) { Text(String(format: "%02d:00", h)) }
                    }
                }
            }
            .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() } }
            .frame(height: 110)
            .animation(HubMotion.data, value: insights.movementsByHour)
        }
        section("Alerts") {
            if insights.alerts.isEmpty {
                empty("checkmark.seal.fill", "All clear at this hub.")
            } else {
                ForEach(insights.alerts.prefix(5)) { alert in alertRow(alert) }
            }
        }
    }

    // MARK: Routes

    @ViewBuilder
    private func routes(_ insights: HubInsights) -> some View {
        if insights.routes.isEmpty {
            empty("point.3.connected.trianglepath.dotted", "No routes through this hub yet.")
        } else {
            HStack(spacing: 10) {
                ForEach(0..<4) { band in
                    HStack(spacing: 4) {
                        Circle().fill(HubRouteStyle.colors[band]).frame(width: 7, height: 7)
                        Text(["New", "≥75%", "55–75%", "<55%"][band]).font(.system(size: 10))
                            .foregroundStyle(HubChromeStyle.secondary)
                    }
                }
            }
            ForEach(insights.routes) { link in
                Button {
                    withAnimation(HubMotion.panel) { model.highlight(link.routeID) }
                } label: {
                    routeRow(link)
                }
                .buttonStyle(HubPressStyle())
            }
        }
    }

    private func routeRow(_ link: HubRouteLink) -> some View {
        let selected = model.highlightedRoute == link.routeID
        let profit = link.profitThisMonthCents
        let trend = profit - link.profitLastMonthCents
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(link.other.raw)
                    .font(.system(size: 12, weight: .bold).monospaced())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(HubRouteStyle.tint(link.loadFactor), in: RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 0) {
                    Text(link.city).font(.system(size: 13, weight: .semibold)).foregroundStyle(HubChromeStyle.ink)
                        .lineLimit(1)
                    Text("\(link.distanceKm.formatted()) km · \(link.dailyRoundTrips) a day · \(Self.compass(link.bearing))")
                        .font(.system(size: 10)).foregroundStyle(HubChromeStyle.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Format.money(Money(cents: profit)))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(profit >= 0 ? HubChromeStyle.good : HubChromeStyle.bad)
                    HStack(spacing: 2) {
                        Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text("month")
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(trend >= 0 ? HubChromeStyle.good : HubChromeStyle.bad)
                }
            }
            HubMeter(title: "Load factor", value: link.loadFactor ?? 0,
                     detail: link.loadFactor.map { Format.percent($0) } ?? "No flights yet",
                     tint: HubRouteStyle.tint(link.loadFactor))
        }
        .padding(10)
        .background(Color.white.opacity(selected ? 0.92 : 0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(selected ? HubChromeStyle.accent : .clear, lineWidth: 1.5))
        .animation(HubMotion.snap, value: selected)
    }

    private static func compass(_ bearing: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return names[Int((bearing / 45).rounded()) % 8]
    }

    // MARK: Slots

    @ViewBuilder
    private func slots(_ insights: HubInsights) -> some View {
        let capacity = max(1, insights.slotCapacity)
        HubMeter(title: "Daily slots allocated", value: Double(insights.slotsUsed) / Double(capacity),
                 detail: "\(insights.slotsUsed) of \(insights.slotCapacity)")
        section("Who holds them") {
            let total = max(1, insights.carriers.reduce(0) { $0 + $1.slots })
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(insights.carriers) { carrier in
                        Rectangle().fill(color(carrier))
                            .frame(width: max(2, (geo.size.width - CGFloat(insights.carriers.count) * 2)
                                * CGFloat(carrier.slots) / CGFloat(total)))
                    }
                    Spacer(minLength: 0)
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)
            ForEach(insights.carriers) { carrier in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(color(carrier)).frame(width: 10, height: 10)
                    Text(carrier.name).font(.system(size: 12, weight: carrier.isPlayer ? .semibold : .regular))
                        .foregroundStyle(HubChromeStyle.ink).lineLimit(1)
                    Spacer()
                    Text("\(carrier.slots)").font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(HubChromeStyle.ink)
                    Text(Format.percent(Double(carrier.slots) / Double(total)))
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(HubChromeStyle.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }

    private func color(_ carrier: HubCarrierShare) -> Color {
        guard let livery = carrier.livery else { return HubChromeStyle.tertiary }
        return Color(uiColor: HubPalette.livery(livery))
    }

    // MARK: Airline

    @ViewBuilder
    private func airline(_ insights: HubInsights) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            tile("banknote.fill", "Cash", Format.money(Money(cents: insights.cashCents)))
            tile("chart.line.uptrend.xyaxis", "Hub profit (month)", Format.money(Money(cents: insights.monthProfitCents)),
                 tint: insights.monthProfitCents >= 0 ? HubChromeStyle.good : HubChromeStyle.bad)
            tile("dollarsign.circle.fill", "Hub revenue (month)", Format.money(Money(cents: insights.monthRevenueCents)))
            tile("airplane", "Fleet here", "\(insights.fleetAtHub) of \(insights.fleetTotal)")
        }
        section("Reputation") {
            HubMeter(title: "Overall", value: insights.reputation, tint: HubChromeStyle.accent)
            HubMeter(title: "Punctuality", value: insights.punctuality, tint: HubChromeStyle.good)
            HubMeter(title: "Reliability", value: insights.reliability, tint: HubChromeStyle.good)
            HubMeter(title: "Service", value: insights.service, tint: HubChromeStyle.warn)
            HubMeter(title: "Comfort", value: insights.comfort, tint: HubChromeStyle.warn)
        }
        if let snapshot = model.snapshot, model.upgradeOffers.isEmpty == false {
            section("Hub status") {
                HubStatusSection(status: snapshot.status, timeline: snapshot.timeline)
            }
        }
        section("Buildings here") {
            ForEach(model.upgradeOffers) { offer in
                facility(offer)
            }
        }
        section("Network") {
            HStack {
                Text("Routes flown").font(.system(size: 12)).foregroundStyle(HubChromeStyle.secondary)
                Spacer()
                Text("\(insights.routes.count) here · \(insights.routesTotal) in all")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(HubChromeStyle.ink)
            }
        }
    }

    /// A facility row; tapping it opens the upgrade card at its site.
    private func facility(_ offer: HubUpgradeOffer) -> some View {
        Button {
            withAnimation(HubMotion.panel) { model.openUpgrade(offer.kind) }
        } label: {
            facilityRow(offer)
        }
        .buttonStyle(HubPressStyle())
        .accessibilityIdentifier("ae-hub-facility-\(offer.kind.rawValue)")
    }

    private func facilityRow(_ offer: HubUpgradeOffer) -> some View {
        let state: String = offer.construction.map { "Building · \($0.daysLeft)d" }
            ?? offer.lockedUntil.map { "\(EraNames.title($0)) era" }
            ?? (offer.level == 0 ? "None" : offer.buildingName)
        return HStack(spacing: 8) {
            Image(systemName: offer.isLocked ? "lock.fill" : offer.kind.systemImage).font(.system(size: 12))
                .foregroundStyle(offer.isLocked ? HubChromeStyle.tertiary : HubChromeStyle.accent).frame(width: 18)
            Text(offer.title).font(.system(size: 12)).foregroundStyle(HubChromeStyle.secondary).lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                ForEach(0..<offer.maxLevel, id: \.self) { i in
                    Capsule().fill(i < offer.level ? HubChromeStyle.accent
                                   : i < (offer.construction?.level ?? 0) ? HubChromeStyle.warn : HubChromeStyle.track)
                        .frame(width: 14, height: 5)
                }
            }
            Text(state).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(offer.isBuilding ? HubChromeStyle.warn : HubChromeStyle.ink)
                .lineLimit(1).minimumScaleFactor(0.75)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                .foregroundStyle(HubChromeStyle.tertiary)
        }
        .padding(.vertical, 4)
        // The whole row is the button, the gap by the spacer included.
        .contentShape(Rectangle())
    }

    // MARK: Pieces

    private func tile(_ icon: String, _ title: String, _ value: String, tint: Color = HubChromeStyle.ink) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(HubChromeStyle.accent)
                Text(title).font(.system(size: 10)).foregroundStyle(HubChromeStyle.secondary).lineLimit(1)
            }
            Text(value).font(.system(size: 17, weight: .bold).monospacedDigit()).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(HubMotion.data, value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10, weight: .bold)).kerning(0.6)
                .foregroundStyle(HubChromeStyle.tertiary)
            content()
        }
    }

    private func empty(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(HubChromeStyle.good)
            Text(text).font(.system(size: 12)).foregroundStyle(HubChromeStyle.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func alertRow(_ alert: HubAlert) -> some View {
        Button {
            withAnimation(HubMotion.panel) { model.open(alert) }
        } label: {
            HubAlertRow(alert: alert)
        }
        .buttonStyle(HubPressStyle())
    }
}

struct HubAlertRow: View {
    let alert: HubAlert

    var body: some View {
        HStack(spacing: 10) {
            HubIconTile(systemName: alert.kind.systemImage, tint: alert.kind.tint, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(alert.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(HubChromeStyle.ink)
                    .lineLimit(1)
                Text(alert.detail).font(.system(size: 11)).foregroundStyle(HubChromeStyle.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(HubChromeStyle.tertiary)
        }
        .padding(8)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}

// MARK: - Dropdowns

/// The panel under the top bar for whichever menu is open.
@available(iOS 18.0, *)
struct HubDropdown: View {
    @Bindable var model: HubScreenModel
    let panel: HubPanel
    let mode: HubChromeMode
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch panel {
            case .alerts: alerts
            case .profile: profile
            case .hubs: hubs
            case .layers: layers
            case .search: search
            case .board: HubBoard(model: model, rows: 6, width: 316, bare: true)
            case .insights, .upgrade: EmptyView()
            }
        }
        .frame(width: panel == .search && mode == .regular ? 420 : 316)
        .hubGlass(padding: 12)
    }

    private var alerts: some View {
        let list = model.snapshot?.insights.alerts ?? []
        return VStack(alignment: .leading, spacing: 8) {
            header("bell.fill", "Alerts", list.isEmpty ? "Nothing needs you" : "\(list.count) need attention")
            if list.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(HubChromeStyle.good)
                    Text("All clear at \(model.airport.raw).").font(.system(size: 12)).foregroundStyle(HubChromeStyle.secondary)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(list) { alert in
                            Button {
                                withAnimation(HubMotion.panel) { model.open(alert) }
                            } label: {
                                HubAlertRow(alert: alert)
                            }
                            .buttonStyle(HubPressStyle())
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .accessibilityIdentifier("ae-hub-alerts-panel")
    }

    private var profile: some View {
        let insights = model.snapshot?.insights ?? .empty
        return VStack(alignment: .leading, spacing: 10) {
            header("person.crop.circle.fill", model.snapshot?.airlineName ?? "Your airline", "Chief Executive")
            HStack(spacing: 8) {
                stat("Cash", Format.money(Money(cents: insights.cashCents)))
                stat("Fleet", "\(insights.fleetTotal)")
                stat("Routes", "\(insights.routesTotal)")
            }
            HubMeter(title: "Reputation", value: insights.reputation)
            Text("LIGHTING").font(.system(size: 10, weight: .bold)).kerning(0.6).foregroundStyle(HubChromeStyle.tertiary)
            Picker("Lighting", selection: Binding(get: { model.lighting }, set: { model.setLighting($0) })) {
                Text("Auto").tag(HubScreenModel.Lighting.auto)
                Text("Day").tag(HubScreenModel.Lighting.day)
                Text("Night").tag(HubScreenModel.Lighting.night)
            }
            .pickerStyle(.segmented)
            Button {
                withAnimation(HubMotion.panel) {
                    model.insightsTab = .airline
                    model.panel = .insights
                }
            } label: {
                Label("Open hub insights", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .foregroundStyle(.white)
                    .background(HubChromeStyle.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(HubPressStyle())
        }
        .accessibilityIdentifier("ae-hub-profile-panel")
    }

    private var hubs: some View {
        let network = model.snapshot?.insights.network ?? []
        return VStack(alignment: .leading, spacing: 8) {
            header("airplane.circle.fill", "Your network", "\(network.count) airports")
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(network) { airport in
                        let current = airport.code == model.airport
                        Button {
                            withAnimation(HubMotion.panel) { model.panel = nil }
                            if !current { model.switchHub?(airport.code) }
                        } label: {
                            HStack(spacing: 10) {
                                Text(airport.code.raw)
                                    .font(.system(size: 12, weight: .bold).monospaced())
                                    .foregroundStyle(current ? .white : HubChromeStyle.accent)
                                    .frame(width: 44, height: 24)
                                    .background(current ? HubChromeStyle.accent : HubChromeStyle.accentSoft,
                                                in: RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(airport.city).font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(HubChromeStyle.ink).lineLimit(1)
                                    Text(airport.isHome ? "Home base · \(airport.routes) routes" : "\(airport.routes) routes")
                                        .font(.system(size: 10)).foregroundStyle(HubChromeStyle.secondary)
                                }
                                Spacer()
                                if current {
                                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(HubChromeStyle.accent)
                                }
                            }
                            .padding(6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HubPressStyle())
                        .accessibilityIdentifier("ae-hub-switch-\(airport.code.raw)")
                    }
                }
            }
            .frame(maxHeight: 320)
        }
    }

    private var layers: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("square.3.layers.3d", "Layers", "What the world shows")
            ForEach(HubOverlay.allCases) { overlay in
                Toggle(isOn: Binding(get: { model.overlays.contains(overlay) },
                                     set: { on in withAnimation(HubMotion.snap) { model.setOverlay(overlay, on) } })) {
                    HStack(spacing: 10) {
                        HubIconTile(systemName: overlay.systemImage, size: 26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(overlay.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(HubChromeStyle.ink)
                            Text(overlay.detail).font(.system(size: 10)).foregroundStyle(HubChromeStyle.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .tint(HubChromeStyle.accent)
                .accessibilityIdentifier("ae-hub-layer-\(overlay.rawValue)")
            }
        }
    }

    private var search: some View {
        let results = model.searchResults
        return VStack(alignment: .leading, spacing: 8) {
            if mode != .regular {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(HubChromeStyle.tertiary)
                    TextField("Stands, flights, aircraft, routes…", text: $model.searchQuery)
                        .font(.system(size: 13))
                        .focused($fieldFocused)
                        .submitLabel(.search)
                        .onSubmit {
                            if let first = results.first { withAnimation(HubMotion.panel) { model.choose(first) } }
                        }
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onAppear { fieldFocused = true }
            }
            if results.isEmpty {
                Text(model.searchQuery.isEmpty ? "Try a gate number, a flight, a city or “security”."
                                               : "Nothing at this hub matches “\(model.searchQuery)”.")
                    .font(.system(size: 12)).foregroundStyle(HubChromeStyle.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 2) {
                    ForEach(results) { result in
                        Button {
                            withAnimation(HubMotion.panel) { model.choose(result) }
                        } label: {
                            HStack(spacing: 10) {
                                HubIconTile(systemName: Self.symbol(result.kind), size: 26)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(result.title).font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(HubChromeStyle.ink).lineLimit(1)
                                    Text(result.detail).font(.system(size: 11))
                                        .foregroundStyle(HubChromeStyle.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(HubChromeStyle.tertiary)
                            }
                            .padding(6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HubPressStyle())
                    }
                }
            }
        }
        .accessibilityIdentifier("ae-hub-search-results")
    }

    private static func symbol(_ kind: HubSearchResult.Kind) -> String {
        switch kind {
        case .gate: "door.left.hand.open"
        case .flight: "airplane"
        case .aircraft: "airplane.circle"
        case .route: "point.3.connected.trianglepath.dotted"
        case .place: "mappin.and.ellipse"
        }
    }

    private func header(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            HubIconTile(systemName: icon, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(HubChromeStyle.ink).lineLimit(1)
                Text(detail).font(.system(size: 11)).foregroundStyle(HubChromeStyle.secondary)
            }
            Spacer()
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundStyle(HubChromeStyle.secondary)
            Text(value).font(.system(size: 14, weight: .bold).monospacedDigit()).foregroundStyle(HubChromeStyle.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - World labels

/// A player's stand, tagged over its jet in the overview.
struct HubStandTagView: View {
    let tag: HubStandTag

    var body: some View {
        HStack(spacing: 5) {
            Text("\(tag.gate)")
                .font(.system(size: 10, weight: .heavy).monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 18, minHeight: 18)
                .background(tint, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Image(systemName: tag.systemImage).font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
            Text(tag.code).font(.system(size: 10, weight: .semibold)).foregroundStyle(HubChromeStyle.ink)
            Text(tag.stage).font(.system(size: 10)).foregroundStyle(HubChromeStyle.secondary)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.leading, 3)
        .padding(.trailing, 7)
        .frame(height: 24)
        .background(Color.white.opacity(0.92), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1))
        .shadow(color: HubChromeStyle.panelShadow, radius: 5, y: 2)
        .overlay(alignment: .bottom) {
            // The stem down to the jet.
            Rectangle().fill(tint.opacity(0.6)).frame(width: 1.5, height: 10).offset(y: 10)
        }
    }

    private var tint: Color {
        switch tag.tone {
        case .good: HubChromeStyle.good
        case .accent: HubChromeStyle.accent
        case .warn: HubChromeStyle.warn
        case .neutral: HubChromeStyle.secondary
        }
    }
}

/// A route of the fan, labelled part-way along its arc.
struct HubRouteLabel: View {
    let tag: HubRouteTag

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(HubRouteStyle.colors[max(0, min(3, tag.band))]).frame(width: 7, height: 7)
            Text(tag.code).font(.system(size: 11, weight: .bold).monospaced()).foregroundStyle(HubChromeStyle.ink)
            Text(tag.detail).font(.system(size: 10)).foregroundStyle(HubChromeStyle.secondary)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Color.white.opacity(tag.highlighted ? 0.98 : 0.86), in: Capsule())
        .overlay(Capsule().strokeBorder(tag.highlighted ? HubChromeStyle.accent : .clear, lineWidth: 1.5))
        .scaleEffect(tag.highlighted ? 1.12 : 1)
        .shadow(color: HubChromeStyle.panelShadow, radius: 4, y: 2)
    }
}
