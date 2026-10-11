import SwiftUI
import AirlineEmpireCore

// The light glass dashboard over the 3D hub (docs/HUB_VIEW_3D.md §1,
// "Dashboard chrome"). Every panel is the same frosted card; the
// hierarchy comes from size and weight, not colour.

struct HubGlass: ViewModifier {
    var radius: CGFloat = HubChromeStyle.radius
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(HubChromeStyle.panelFill))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(HubChromeStyle.panelRim, lineWidth: 1))
                    .shadow(color: HubChromeStyle.panelShadow, radius: 18, x: 0, y: 8)
            }
    }
}

extension View {
    func hubGlass(radius: CGFloat = HubChromeStyle.radius, padding: CGFloat = 12) -> some View {
        modifier(HubGlass(radius: radius, padding: padding))
    }
}

/// A small rounded-square icon tile, as on every card in the reference.
struct HubIconTile: View {
    let systemName: String
    var tint: Color = HubChromeStyle.accent
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct HubStatusChip: View {
    let text: String
    var tint: Color = HubChromeStyle.good

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .lineLimit(1)
    }
}

extension HubBoardStatus {
    var tint: Color {
        switch self {
        case .scheduled, .landed: HubChromeStyle.good
        case .boarding: HubChromeStyle.accent
        case .delayed: HubChromeStyle.warn
        case .departed, .enRoute: HubChromeStyle.secondary
        }
    }
}

extension HubTurnaroundStage {
    var systemImage: String {
        switch self {
        case .deboarding: "figure.walk.departure"
        case .servicing: "fuelpump.fill"
        case .boarding: "figure.walk.arrival"
        case .pushback: "arrow.uturn.backward"
        case .departed: "airplane.departure"
        }
    }
}

// MARK: - Top bar

/// How the dashboard is arranged for the shape of the view.
enum HubChromeMode: Equatable {
    /// iPad and wide windows: the reference's layout.
    case regular
    /// iPhone on its side: one slim bar, chips, a slim timeline.
    case landscape
    /// A narrow window (iPad split view): stacked.
    case portrait

    init(size: CGSize) {
        if size.width > size.height && size.height < 520 {
            self = .landscape
        } else {
            self = size.width >= 760 ? .regular : .portrait
        }
    }

    var topBarHeight: CGFloat { self == .landscape ? 46 : 54 }
}

/// The springs every panel moves on: quick to answer, settled without a
/// wobble.
enum HubMotion {
    static let panel = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let snap = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let data = Animation.smooth(duration: 0.6)
}

/// A press that sinks a little, for every chrome button.
struct HubPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

@available(iOS 18.0, *)
struct HubTopBar: View {
    @Bindable var model: HubScreenModel
    let mode: HubChromeMode
    /// Less than ~790 pt across: the shots shrink to icons.
    var narrow = false
    let dismiss: () -> Void
    @FocusState private var searching: Bool

    var body: some View {
        HStack(spacing: mode == .regular ? 12 : 8) {
            Button(action: dismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HubChromeStyle.ink)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.7), in: Circle())
            }
            .buttonStyle(HubPressStyle())
            .accessibilityLabel("Close hub view")
            .accessibilityIdentifier("ae-hub-close")

            HStack(spacing: 8) {
                Image(systemName: "cube.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 1), HubChromeStyle.accent],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                if mode == .regular {
                    Text(model.snapshot?.airlineName ?? "Airline")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(HubChromeStyle.ink)
                        .lineLimit(1)
                }
            }

            if mode == .regular {
                searchField.frame(maxWidth: 420)
            }
            if mode == .landscape {
                HubShotPicker(model: model, compact: true, iconsOnly: narrow)
            }

            Spacer(minLength: 4)

            if mode != .regular {
                iconButton("magnifyingglass", "Search", panel: .search)
            }
            hubChip
            clock
            bell
            profile
        }
        .padding(.horizontal, 14)
        .frame(height: mode.topBarHeight)
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Color.white.opacity(0.66)))
                .overlay(alignment: .bottom) { Rectangle().fill(Color.white).frame(height: 1) }
                .shadow(color: HubChromeStyle.panelShadow, radius: 12, y: 4)
                .ignoresSafeArea(edges: [.top, .horizontal])
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(HubChromeStyle.tertiary)
            TextField("Search stands, flights, gates, aircraft…", text: $model.searchQuery)
                .font(.system(size: 13))
                .foregroundStyle(HubChromeStyle.ink)
                .focused($searching)
                .submitLabel(.search)
                .onSubmit {
                    if let first = model.searchResults.first { withAnimation(HubMotion.panel) { model.choose(first) } }
                }
                .accessibilityIdentifier("ae-hub-search")
            if model.searchQuery.isEmpty {
                Text("⌘K").font(.system(size: 11, weight: .medium)).foregroundStyle(HubChromeStyle.tertiary)
            } else {
                Button {
                    model.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(HubChromeStyle.tertiary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color.white.opacity(searching ? 0.9 : 0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(HubChromeStyle.accent.opacity(searching ? 0.5 : 0), lineWidth: 1.5))
        .animation(HubMotion.snap, value: searching)
        .onChange(of: model.searchQuery) { _, query in
            withAnimation(HubMotion.snap) {
                if !query.isEmpty { model.panel = .search } else if model.panel == .search { model.panel = nil }
            }
        }
        .background {
            // ⌘K focuses the field, as the reference's hint says.
            Button("") { searching = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private var hubChip: some View {
        Button {
            withAnimation(HubMotion.snap) { model.toggle(.hubs) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "airplane.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white, HubChromeStyle.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text(mode == .regular ? "\(model.snapshot?.city ?? model.airport.raw) Hub" : "\(model.airport.raw) Hub")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(HubChromeStyle.ink)
                        .lineLimit(1).fixedSize()
                    if mode == .regular {
                        Text("\(model.airport.raw) · \(model.layout.stands.count) stands")
                            .font(.system(size: 11)).foregroundStyle(HubChromeStyle.secondary)
                    }
                }
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(HubChromeStyle.tertiary)
                    .rotationEffect(.degrees(model.panel == .hubs ? 180 : 0))
            }
            .padding(.horizontal, 10)
            .frame(height: mode == .landscape ? 34 : 38)
            .background(Color.white.opacity(model.panel == .hubs ? 0.9 : 0.55),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(HubPressStyle())
        .accessibilityLabel("Switch hub")
        .accessibilityIdentifier("ae-hub-switcher")
    }

    private var clock: some View {
        HStack(spacing: 5) {
            Circle().fill(HubChromeStyle.good).frame(width: 7, height: 7)
            if mode == .regular {
                Text("Live").font(.system(size: 12, weight: .semibold)).foregroundStyle(HubChromeStyle.good)
            }
            Text(model.snapshot?.localTime ?? "--:--")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(HubChromeStyle.ink)
                .contentTransition(.numericText())
                .animation(.smooth, value: model.snapshot?.localTime)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(HubChromeStyle.goodSoft, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ae-hub-clock")
    }

    private var alertCount: Int { model.snapshot?.insights.alerts.count ?? 0 }

    private var bell: some View {
        Button {
            withAnimation(HubMotion.snap) { model.toggle(.alerts) }
        } label: {
            Image(systemName: alertCount > 0 ? "bell.badge" : "bell")
                .font(.system(size: 15))
                .foregroundStyle(HubChromeStyle.ink)
                .symbolEffect(.bounce, value: alertCount)
                .frame(width: 32, height: 32)
                .overlay(alignment: .topTrailing) {
                    if alertCount > 0 {
                        Text("\(alertCount)")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(HubChromeStyle.bad, in: Capsule())
                            .offset(x: 2, y: 1)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
        }
        .buttonStyle(HubPressStyle())
        .accessibilityLabel(alertCount > 0 ? "\(alertCount) alerts" : "No alerts")
        .accessibilityIdentifier("ae-hub-alerts")
    }

    private var profile: some View {
        Button {
            withAnimation(HubMotion.snap) { model.toggle(.profile) }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.78, blue: 0.62), Color(red: 0.82, green: 0.55, blue: 0.42)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "person.fill").font(.system(size: 14)).foregroundStyle(.white))
                if mode == .regular {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("You").font(.system(size: 13, weight: .semibold)).foregroundStyle(HubChromeStyle.ink)
                        Text("Chief Executive").font(.system(size: 11)).foregroundStyle(HubChromeStyle.secondary)
                    }
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(HubChromeStyle.tertiary)
                        .rotationEffect(.degrees(model.panel == .profile ? 180 : 0))
                }
            }
        }
        .buttonStyle(HubPressStyle())
        .accessibilityLabel("Airline summary")
        .accessibilityIdentifier("ae-hub-profile")
    }

    private func iconButton(_ icon: String, _ label: String, panel: HubPanel) -> some View {
        Button {
            withAnimation(HubMotion.snap) { model.toggle(panel) }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(model.panel == panel ? HubChromeStyle.accent : HubChromeStyle.ink)
                .frame(width: 32, height: 32)
                .background(model.panel == panel ? HubChromeStyle.accentSoft : Color.white.opacity(0.55), in: Circle())
        }
        .buttonStyle(HubPressStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier("ae-hub-\(label.lowercased())")
    }
}

// MARK: - KPIs

struct HubKPICard: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    var delta: String?
    var deltaGood = true
    var compact = false

    var body: some View {
        HStack(alignment: compact ? .center : .top, spacing: compact ? 7 : 10) {
            HubIconTile(systemName: icon, size: compact ? 26 : 34)
            VStack(alignment: .leading, spacing: compact ? 0 : 2) {
                Text(title).font(.system(size: compact ? 10 : 11, weight: .medium)).foregroundStyle(HubChromeStyle.secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value).font(.system(size: compact ? 15 : 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(HubChromeStyle.ink)
                        .contentTransition(.numericText())
                        .animation(HubMotion.data, value: value)
                    if let delta, !compact {
                        Text(delta).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(deltaGood ? HubChromeStyle.good : HubChromeStyle.bad)
                    }
                }
                if !compact {
                    Text(detail).font(.system(size: 11)).foregroundStyle(HubChromeStyle.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minWidth: compact ? 104 : 150, maxWidth: compact ? 150 : 210, alignment: .leading)
        .hubGlass(radius: compact ? 13 : HubChromeStyle.radius, padding: compact ? 7 : 11)
        .accessibilityElement(children: .combine)
    }
}

@available(iOS 18.0, *)
struct HubKPIRow: View {
    let model: HubScreenModel
    var compact = false

    var body: some View {
        let k = model.snapshot?.kpis
        HStack(spacing: compact ? 8 : 10) {
            card(.overview, HubKPICard(icon: "clock.badge.checkmark", title: compact ? "On time" : "On-time performance",
                                       value: k?.onTimeRate.map { String(format: "%.1f%%", $0 * 100) } ?? "—",
                                       detail: k?.onTimeRate == nil ? "No flights yet" : "avg delay \(k?.averageDelayMinutes ?? 0)m",
                                       delta: k?.onTimeRate.map { $0 >= 0.85 ? "▲ on target" : "▼ below 85%" },
                                       deltaGood: (k?.onTimeRate ?? 1) >= 0.85, compact: compact))
            card(.routes, HubKPICard(icon: "airplane", title: compact ? "Active" : "Active flights",
                                     value: "\(k?.activeFlights ?? 0)",
                                     detail: "\(k?.aircraftOnGround ?? 0) of yours on the ground", compact: compact))
            card(.slots, HubKPICard(icon: "timer", title: compact ? "Turnaround" : "Avg turnaround",
                                    value: "\(k?.averageTurnaroundMinutes ?? 0)m",
                                    detail: "\(k?.passengersToday ?? 0) passengers today",
                                    delta: k.map { String(format: "%.0f%% slots", $0.slotUse * 100) },
                                    deltaGood: (k?.slotUse ?? 0) < 0.9, compact: compact))
        }
        .accessibilityIdentifier("ae-hub-kpis")
    }

    /// Every card opens the insights behind it.
    private func card(_ tab: HubInsightsTab, _ content: HubKPICard) -> some View {
        Button {
            withAnimation(HubMotion.panel) {
                model.insightsTab = tab
                model.panel = .insights
            }
        } label: { content }
        .buttonStyle(HubPressStyle())
    }
}

// MARK: - Controls

@available(iOS 18.0, *)
struct HubControls: View {
    let model: HubScreenModel
    var compact = false

    var body: some View {
        VStack(spacing: 2) {
            control("plus", "Zoom in") { model.scene.zoom(by: 0.75) }
            divider
            control("minus", "Zoom out") { model.scene.zoom(by: 1.33) }
            divider
            control("arrow.counterclockwise", "Rotate") { model.scene.rotate(by: .pi / 8) }
            divider
            control("scope", "Recenter") { model.scene.recenter(focus: model.focus) }
            divider
            control(model.isNight ? "sun.max" : "moon.stars", model.isNight ? "Daylight" : "Night") {
                model.setLighting(model.isNight ? .day : .night)
            }
            divider
            control("square.3.layers.3d", "Layers", active: model.panel == .layers) {
                withAnimation(HubMotion.snap) { model.toggle(.layers) }
            }
            divider
            control("chart.bar.xaxis", "Insights", active: model.panel == .insights) {
                withAnimation(HubMotion.panel) { model.toggle(.insights) }
            }
        }
        .padding(.vertical, 4)
        .frame(width: compact ? 36 : 40)
        .background {
            Capsule(style: .continuous).fill(.ultraThinMaterial)
                .overlay(Capsule(style: .continuous).fill(HubChromeStyle.panelFill))
                .overlay(Capsule(style: .continuous).strokeBorder(HubChromeStyle.panelRim))
                .shadow(color: HubChromeStyle.panelShadow, radius: 12, y: 6)
        }
    }

    private var divider: some View {
        Rectangle().fill(HubChromeStyle.track).frame(width: 18, height: 1)
    }

    private func control(_ icon: String, _ label: String, active: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? HubChromeStyle.accent : HubChromeStyle.ink)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: compact ? 32 : 36, height: compact ? 30 : 36)
                .background(active ? HubChromeStyle.accentSoft : .clear, in: Circle())
        }
        .buttonStyle(HubPressStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier("ae-hub-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }
}

@available(iOS 18.0, *)
struct HubShotPicker: View {
    let model: HubScreenModel
    var compact = false
    /// A narrow phone on its side: icons only, the names in VoiceOver.
    var iconsOnly = false
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HubShot.allCases) { shot in
                let selected = model.shot == shot
                Button {
                    withAnimation(HubMotion.snap) { model.select(shot) }
                } label: {
                    Group {
                        if iconsOnly {
                            Image(systemName: shot.systemImage).frame(width: 20)
                        } else {
                            Label(shot.title, systemImage: shot.systemImage).labelStyle(.titleAndIcon)
                        }
                    }
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(selected ? Color.white : HubChromeStyle.ink)
                        .padding(.horizontal, compact ? 8 : 11)
                        .frame(height: compact ? 28 : 30)
                        .background {
                            if selected {
                                // The pill slides from shot to shot.
                                Capsule().fill(HubChromeStyle.accent)
                                    .shadow(color: HubChromeStyle.accent.opacity(0.35), radius: 6, y: 3)
                                    .matchedGeometryEffect(id: "selected", in: selection)
                            }
                        }
                }
                .buttonStyle(HubPressStyle())
                .accessibilityLabel(shot.title)
                .accessibilityIdentifier("ae-hub-shot-\(shot.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background {
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().fill(HubChromeStyle.panelFill))
                .overlay(Capsule().strokeBorder(HubChromeStyle.panelRim))
                .shadow(color: HubChromeStyle.panelShadow, radius: 10, y: 5)
        }
    }
}

// MARK: - Inspector

/// The jet in the airline's colours, for the inspector card: a studio
/// render of the authored model (gap F1), else a drawn side profile.
struct HubAircraftProfile: View {
    let category: AircraftCategory
    let livery: Livery

    @ViewBuilder
    var body: some View {
        if UIImage(named: "HubJet_\(category.rawValue)") != nil {
            rendered
        } else {
            drawn
        }
    }

    /// Rendered by scripts/hub-models/procedural/inspector_renders.py: a
    /// shaded jet with its livery parts in white, and masks of those parts
    /// the airline's colours are multiplied through.
    private var rendered: some View {
        let name = "HubJet_\(category.rawValue)"
        return ZStack {
            Image(name).resizable().scaledToFit()
            Color(uiColor: HubPalette.livery(livery))
                .mask(Image(name + "_livery").resizable().scaledToFit())
                .blendMode(.multiply)
            Color(uiColor: HubPalette.liveryAccent(livery))
                .mask(Image(name + "_accent").resizable().scaledToFit())
                .blendMode(.multiply)
        }
        .compositingGroup()
        .padding(.horizontal, 6)
        .accessibilityHidden(true)
    }

    private var drawn: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let tint = Color(uiColor: HubPalette.livery(livery))
            let accent = Color(uiColor: HubPalette.liveryAccent(livery))
            let bodyH = h * (category.isWidebody ? 0.22 : 0.18)
            let cy = h * 0.55
            let x0 = w * 0.08, x1 = w * 0.92
            // Shadow.
            ctx.fill(Path(ellipseIn: CGRect(x: x0 + w * 0.1, y: h * 0.86, width: w * 0.64, height: h * 0.06)),
                     with: .color(Color(red: 0.3, green: 0.33, blue: 0.6).opacity(0.18)))
            // Fin.
            var fin = Path()
            fin.move(to: CGPoint(x: x0 + w * 0.02, y: cy - bodyH * 0.4))
            fin.addLine(to: CGPoint(x: x0 - w * 0.01, y: cy - bodyH * 2.6))
            fin.addLine(to: CGPoint(x: x0 + w * 0.08, y: cy - bodyH * 2.6))
            fin.addLine(to: CGPoint(x: x0 + w * 0.2, y: cy - bodyH * 0.45))
            fin.closeSubpath()
            ctx.fill(fin, with: .color(tint))
            var flash = Path()
            flash.move(to: CGPoint(x: x0 + w * 0.045, y: cy - bodyH * 2.2))
            flash.addLine(to: CGPoint(x: x0 + w * 0.075, y: cy - bodyH * 2.55))
            flash.addLine(to: CGPoint(x: x0 + w * 0.12, y: cy - bodyH * 1.4))
            flash.addLine(to: CGPoint(x: x0 + w * 0.1, y: cy - bodyH * 1.2))
            flash.closeSubpath()
            ctx.fill(flash, with: .color(accent))
            // Fuselage.
            let fuselage = Path(roundedRect: CGRect(x: x0, y: cy - bodyH / 2, width: x1 - x0, height: bodyH),
                                cornerRadius: bodyH / 2)
            ctx.fill(fuselage, with: .linearGradient(Gradient(colors: [.white, Color(red: 0.86, green: 0.88, blue: 0.96)]),
                                                     startPoint: CGPoint(x: 0, y: cy - bodyH / 2),
                                                     endPoint: CGPoint(x: 0, y: cy + bodyH / 2)))
            // Cheat line and windows.
            ctx.fill(Path(CGRect(x: x0 + w * 0.12, y: cy + bodyH * 0.12, width: w * 0.66, height: bodyH * 0.1)),
                     with: .color(tint))
            var x = x0 + w * 0.16
            while x < x1 - w * 0.12 {
                ctx.fill(Path(roundedRect: CGRect(x: x, y: cy - bodyH * 0.2, width: 3, height: 4), cornerRadius: 1.2),
                         with: .color(Color(red: 0.25, green: 0.3, blue: 0.5)))
                x += 7
            }
            ctx.fill(Path(roundedRect: CGRect(x: x1 - w * 0.07, y: cy - bodyH * 0.3, width: w * 0.04, height: bodyH * 0.18),
                          cornerRadius: 2), with: .color(Color(red: 0.2, green: 0.25, blue: 0.45)))
            // Wing and engine.
            var wing = Path()
            wing.move(to: CGPoint(x: x0 + w * 0.42, y: cy + bodyH * 0.2))
            wing.addLine(to: CGPoint(x: x0 + w * 0.6, y: cy + bodyH * 0.25))
            wing.addLine(to: CGPoint(x: x0 + w * 0.36, y: cy + bodyH * 0.55))
            wing.closeSubpath()
            ctx.fill(wing, with: .color(Color(red: 0.8, green: 0.83, blue: 0.94)))
            ctx.fill(Path(roundedRect: CGRect(x: x0 + w * 0.44, y: cy + bodyH * 0.45, width: w * 0.13, height: bodyH * 0.55),
                          cornerRadius: bodyH * 0.25), with: .color(tint))
            // Gear.
            for gx in [x0 + w * 0.47, x1 - w * 0.1] {
                ctx.fill(Path(CGRect(x: gx, y: cy + bodyH / 2, width: 2, height: h * 0.86 - cy - bodyH / 2)),
                         with: .color(Color(red: 0.3, green: 0.32, blue: 0.45)))
                ctx.fill(Path(ellipseIn: CGRect(x: gx - 3, y: h * 0.82, width: 8, height: 8)),
                         with: .color(Color(red: 0.2, green: 0.22, blue: 0.32)))
            }
        }
        .accessibilityHidden(true)
    }
}

@available(iOS 18.0, *)
struct HubInspector: View {
    @Bindable var model: HubScreenModel
    let occupant: HubStandOccupant
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(spacing: 10) {
                HubIconTile(systemName: "airplane", size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(occupant.typeName).font(.system(size: 11)).foregroundStyle(HubChromeStyle.secondary)
                        .lineLimit(1)
                    Text(occupant.registration.isEmpty ? "Gate \(occupant.gate)" : occupant.registration)
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(HubChromeStyle.ink)
                        .contentTransition(.opacity)
                }
                Spacer()
                Button {
                    withAnimation(HubMotion.snap) { model.focusNext() }
                } label: {
                    Image(systemName: "arrow.right.circle").font(.system(size: 16))
                }
                .buttonStyle(HubPressStyle())
                .accessibilityLabel("Next aircraft")
                .accessibilityIdentifier("ae-hub-next-aircraft")
                Button {
                    withAnimation(HubMotion.panel) { model.showsInspector = false }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(HubPressStyle())
                .accessibilityLabel("Close inspector")
            }
            .foregroundStyle(HubChromeStyle.secondary)

            HubAircraftProfile(category: occupant.category, livery: occupant.livery)
                .frame(height: compact ? 58 : 92)
                .background(LinearGradient(colors: [Color(red: 0.93, green: 0.95, blue: 1), Color(red: 0.86, green: 0.89, blue: 0.98)],
                                           startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .id(occupant.standIndex)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

            // Page tabs: the active one widens to show its name.
            HStack(spacing: 5) {
                ForEach(HubInspectorPage.allCases) { page in
                    let active = model.inspectorPage == page
                    Button {
                        withAnimation(HubMotion.snap) { model.inspectorPage = page }
                    } label: {
                        Text(active ? page.title : "")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, active ? 7 : 0)
                            .frame(minWidth: active ? 0 : 6, minHeight: active ? 15 : 6)
                            .background(active ? HubChromeStyle.accent : HubChromeStyle.tertiary.opacity(0.6), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(page.title)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)

            TabView(selection: $model.inspectorPage) {
                ForEach(HubInspectorPage.allCases) { page in
                    VStack(spacing: 7) { rows(page) }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: compact ? 112 : 118)
        }
        .frame(width: compact ? 240 : 250)
        .hubGlass()
        .accessibilityIdentifier("ae-hub-inspector")
    }

    @ViewBuilder
    private func rows(_ page: HubInspectorPage) -> some View {
        switch page {
        case .flight:
            if let flight = occupant.flight {
                row("Flight", flight.code)
                row(flight.from == model.airport ? "Destination" : "From", flight.destinationCity)
                row("Departs", flight.time)
                loadRow(flight)
                row("Status", flight.delayMinutes > 0 ? "Delayed \(flight.delayMinutes)m" : flight.status.title,
                    tint: flight.status.tint)
            } else {
                row("Status", occupant.stage?.title ?? "Parked")
                row("Stand", "Gate \(occupant.gate)")
                row("Next flight", "Not scheduled")
            }
        case .aircraft:
            row("Type", occupant.typeName)
            row("Registration", occupant.registration.isEmpty ? "—" : occupant.registration)
            row("Class", categoryTitle)
            row("Operator", operatorName)
            row("Stand", "Gate \(occupant.gate)")
        case .route:
            if let link = model.focusedRoute {
                row("Route", "\(model.airport.raw)–\(link.other.raw) \(link.city)")
                row("Distance", "\(link.distanceKm.formatted()) km")
                row("Round trips", "\(link.dailyRoundTrips) a day · \(link.aircraftAssigned) aircraft")
                row("Load factor", link.loadFactor.map { Format.percent($0) } ?? "No flights yet",
                    tint: HubRouteStyle.tint(link.loadFactor))
                row("Profit this month", Format.money(Money(cents: link.profitThisMonthCents)),
                    tint: link.profitThisMonthCents >= 0 ? HubChromeStyle.good : HubChromeStyle.bad)
            } else {
                Text(occupant.operatorKind == .player ? "Not assigned to a route." : "Another carrier's aircraft.")
                    .font(.system(size: 12)).foregroundStyle(HubChromeStyle.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .turnaround:
            row("Stage", occupant.stage?.title ?? "Parked")
            row("Progress", Format.percent(overallProgress))
            ProgressView(value: overallProgress)
                .tint(HubChromeStyle.accent)
                .animation(HubMotion.data, value: overallProgress)
            row("Ground crew", ["Basic", "Standard", "Premium"][min(2, max(0, model.snapshot?.insights.groundServices ?? 0))])
        }
    }

    private var overallProgress: Double {
        guard let stage = occupant.stage else { return 0 }
        return min(1, (Double(stage.rawValue) + occupant.stageProgress) / Double(HubTurnaroundStage.allCases.count - 1))
    }

    private var categoryTitle: String {
        switch occupant.category {
        case .turboprop: "Turboprop"
        case .regionalJet: "Regional jet"
        case .narrowbody: "Narrowbody"
        case .largeNarrowbody: "Large narrowbody"
        case .widebody: "Widebody"
        case .largeWidebody: "Large widebody"
        }
    }

    private var operatorName: String {
        switch occupant.operatorKind {
        case .player: model.snapshot?.airlineName ?? "You"
        case .rival: "Rival carrier"
        case .traffic: "Other carrier"
        }
    }

    private func loadRow(_ flight: HubFlightCard) -> some View {
        HStack(spacing: 8) {
            Text("Passengers").font(.system(size: 12)).foregroundStyle(HubChromeStyle.secondary)
            Spacer()
            if flight.seats > 0 {
                Capsule().fill(HubChromeStyle.track).frame(width: 44, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule().fill(HubRouteStyle.tint(flight.loadFactor)).frame(width: 44 * min(1, flight.loadFactor), height: 4)
                    }
            }
            Text(flight.seats > 0 ? "\(flight.passengers) / \(flight.seats)" : "\(flight.passengers)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(HubChromeStyle.ink)
        }
    }

    private func row(_ label: String, _ value: String, tint: Color = HubChromeStyle.ink) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(HubChromeStyle.secondary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint).lineLimit(1)
                .contentTransition(.numericText())
        }
    }
}

// MARK: - Turnaround timeline

@available(iOS 18.0, *)
struct HubTimeline: View {
    let model: HubScreenModel
    let compact: Bool
    /// iPhone on its side: tighter, so the airport keeps the screen.
    var slim = false

    var body: some View {
        let occupant = model.focusedOccupant
        let stage = occupant?.stage
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: slim ? 6 : 12) {
                HStack(spacing: 8) {
                    HubIconTile(systemName: "arrow.triangle.2.circlepath", size: 26)
                    Text("Turnaround" + (occupant?.flight.map { " · \($0.code)" } ?? ""))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(HubChromeStyle.ink)
                    Spacer()
                    if let occupant {
                        Text("Gate \(occupant.gate)" + (occupant.flight.map { " · \($0.time)" } ?? ""))
                            .font(.system(size: 11)).foregroundStyle(HubChromeStyle.secondary)
                    }
                }
                track(stage: stage, progress: occupant?.stageProgress ?? 0)
            }
            if !compact {
                // Opens the inspector on the turnaround page.
                Button {
                    withAnimation(HubMotion.panel) {
                        model.inspectorPage = .turnaround
                        model.showsInspector = true
                    }
                } label: {
                    nextAction(occupant)
                }
                .buttonStyle(HubPressStyle())
                .frame(width: 190)
            }
        }
        .hubGlass(padding: slim ? 10 : 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ae-hub-timeline")
    }

    private func track(stage: HubTurnaroundStage?, progress: Double) -> some View {
        let stages = HubTurnaroundStage.allCases
        let current = stage?.rawValue ?? -1
        return GeometryReader { geo in
            let w = geo.size.width
            let step = w / CGFloat(stages.count - 1)
            let filled = current < 0 ? 0 : min(w, step * (CGFloat(current) + CGFloat(progress)))
            ZStack(alignment: .topLeading) {
                Capsule().fill(HubChromeStyle.track).frame(height: 4).offset(y: 9)
                Capsule().fill(HubChromeStyle.accent).frame(width: filled, height: 4).offset(y: 9)
                    .animation(HubMotion.data, value: filled)
                ForEach(stages, id: \.rawValue) { s in
                    let done = s.rawValue < current
                    let active = s.rawValue == current
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().fill(done || active ? HubChromeStyle.accent : Color.white)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(done || active ? Color.white : HubChromeStyle.track, lineWidth: 2))
                                .shadow(color: active ? HubChromeStyle.accent.opacity(0.45) : .clear, radius: 6)
                                .scaleEffect(active ? 1.12 : 1)
                                .animation(HubMotion.snap, value: active)
                            Image(systemName: done ? "checkmark" : s.systemImage)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(done || active ? Color.white : HubChromeStyle.tertiary)
                        }
                        Text(s.title).font(.system(size: 10, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? HubChromeStyle.ink : HubChromeStyle.secondary)
                            .fixedSize()
                    }
                    .position(x: CGFloat(s.rawValue) * step, y: 22)
                }
                // The tug riding the line.
                if current >= 0 {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(HubChromeStyle.ink)
                        .padding(4)
                        .background(Color.white, in: Capsule())
                        .shadow(color: HubChromeStyle.panelShadow, radius: 4)
                        .position(x: filled, y: -6)
                        .animation(HubMotion.data, value: filled)
                }
            }
        }
        .frame(height: slim ? 44 : 50)
        .padding(.horizontal, 22)
        .accessibilityElement()
        .accessibilityLabel("Turnaround stage")
        .accessibilityValue(stage?.title ?? "Parked")
        .accessibilityIdentifier("ae-hub-stage")
    }

    private func nextAction(_ occupant: HubStandOccupant?) -> some View {
        let (title, detail): (String, String) = {
            switch occupant?.stage {
            case .deboarding: ("Clean the cabin", "Passengers leaving")
            case .servicing: ("Fuel and cater", "Ground crew on stand")
            case .boarding: ("Close doors", occupant?.flight.map { "\($0.passengers) on board" } ?? "Boarding")
            case .pushback: ("Pushback", "Tug connected")
            case .departed: ("Next arrival", "Stand free")
            case nil: ("Await schedule", "Aircraft parked")
            }
        }()
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 18))
                .foregroundStyle(HubChromeStyle.accent)
                .frame(width: 34, height: 40)
                .background(HubChromeStyle.accentSoft, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text("Next action").font(.system(size: 10)).foregroundStyle(HubChromeStyle.secondary)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(HubChromeStyle.ink)
                HubStatusChip(text: occupant?.flight?.delayMinutes ?? 0 > 0 ? "Delayed" : "On track",
                              tint: occupant?.flight?.delayMinutes ?? 0 > 0 ? HubChromeStyle.warn : HubChromeStyle.good)
                Text(detail).font(.system(size: 10)).foregroundStyle(HubChromeStyle.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Departures board

extension HubBoardRow {
    /// Stable across refreshes, so rows slide rather than blink.
    var boardID: String { "\(code)-\(time)-\(isDeparture)" }
}

@available(iOS 18.0, *)
struct HubBoard: View {
    @Bindable var model: HubScreenModel
    var rows = 5
    var width: CGFloat = 340
    /// Inside another panel: no glass of its own.
    var bare = false

    var body: some View {
        if bare {
            card
        } else {
            card.hubGlass(padding: 12)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                HubIconTile(systemName: "list.bullet.rectangle", size: 24)
                ForEach(HubScreenModel.BoardTab.allCases, id: \.self) { tab in
                    let selected = model.boardTab == tab
                    Button {
                        withAnimation(HubMotion.snap) { model.boardTab = tab }
                    } label: {
                        HStack(spacing: 4) {
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
                            Text("\(model.count(tab))")
                                .font(.system(size: 9, weight: .bold).monospacedDigit())
                                .foregroundStyle(selected ? Color.white : HubChromeStyle.secondary)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 16, minHeight: 14)
                                .background(selected ? (tab == .delays ? HubChromeStyle.warn : HubChromeStyle.accent)
                                                     : HubChromeStyle.track, in: Capsule())
                                .contentTransition(.numericText())
                        }
                        .foregroundStyle(selected ? HubChromeStyle.accent : HubChromeStyle.secondary)
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                        .background(selected ? HubChromeStyle.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(HubPressStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            if model.boardRows.isEmpty {
                Text(model.boardTab == .delays ? "No delays." : "Nothing scheduled through this hub yet.")
                    .font(.system(size: 12)).foregroundStyle(HubChromeStyle.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(model.boardRows.prefix(rows)), id: \.boardID) { row in
                        Button {
                            withAnimation(HubMotion.panel) { model.open(row) }
                        } label: {
                            line(row)
                        }
                        .buttonStyle(HubPressStyle())
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .opacity))
                    }
                }
                .animation(HubMotion.panel, value: model.boardRows.prefix(rows).map(\.boardID))
            }
        }
        .frame(width: width)
        .accessibilityIdentifier("ae-hub-board")
    }

    private func line(_ row: HubBoardRow) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(row.gate.map { "Gate \($0)" } ?? "—").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HubChromeStyle.ink)
                Text(row.time).font(.system(size: 10).monospacedDigit()).foregroundStyle(HubChromeStyle.tertiary)
            }
            .frame(width: 52, alignment: .leading)
            Circle().fill(row.status.tint).frame(width: 6, height: 6)
            Text("\(row.code) · \(row.city)").font(.system(size: 12))
                .foregroundStyle(HubChromeStyle.ink).lineLimit(1)
            Spacer(minLength: 4)
            HubStatusChip(text: row.delayMinutes > 0 ? "+\(row.delayMinutes)m" : row.status.title,
                          tint: row.status.tint)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                .foregroundStyle(HubChromeStyle.tertiary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - World-anchored overlays

struct HubCallout: View {
    let occupant: HubStandOccupant
    /// iPhone on its side: the header and the bar, so the jet stays visible.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 6) {
                Image(systemName: "airplane").font(.system(size: 11, weight: .bold)).foregroundStyle(HubChromeStyle.accent)
                Text("Flight \(occupant.flight?.code ?? "Gate \(occupant.gate)")")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(HubChromeStyle.ink)
                Text("· \(occupant.stage?.title ?? "Parked")")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(HubChromeStyle.good)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(HubChromeStyle.track)
                    Capsule().fill(HubChromeStyle.accent)
                        .frame(width: geo.size.width * CGFloat(overall))
                }
            }
            .frame(height: 4)
            .animation(HubMotion.data, value: overall)
            if !compact {
                line("person.2.fill", "Passengers",
                     occupant.flight.map { $0.seats > 0 ? "\($0.passengers)/\($0.seats)" : "\($0.passengers)" } ?? "—")
                line("fuelpump.fill", "Fuel", (occupant.stage ?? .deboarding) >= .boarding ? "Loaded" : "Fuelling")
                line("bolt.fill", "Ground power", occupant.stage == .pushback ? "Off" : "On")
            }
        }
        .frame(width: compact ? 200 : 210)
        .hubGlass(radius: 14, padding: compact ? 9 : 11)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ae-hub-callout")
    }

    private var overall: Double {
        guard let stage = occupant.stage else { return 0 }
        return min(1, (Double(stage.rawValue) + occupant.stageProgress) / Double(HubTurnaroundStage.allCases.count - 1))
    }

    private func line(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(HubChromeStyle.accent).frame(width: 14)
            Text(label).font(.system(size: 11)).foregroundStyle(HubChromeStyle.secondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .semibold)).foregroundStyle(HubChromeStyle.good)
        }
    }
}

struct HubPin: View {
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HubChromeStyle.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.9), in: Capsule())
                .shadow(color: HubChromeStyle.panelShadow, radius: 4, y: 2)
            // The reference's blue teardrop with a white eye.
            ZStack {
                Image(systemName: "drop.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .rotationEffect(.degrees(180))
                    .foregroundStyle(HubChromeStyle.accent)
                Circle()
                    .fill(.white)
                    .frame(width: 11, height: 11)
                    .offset(y: -4)
            }
            .shadow(color: HubChromeStyle.accent.opacity(0.45), radius: 7, y: 3)
        }
    }
}

struct HubPill: View {
    let label: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(HubChromeStyle.accent, in: Circle())
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(HubChromeStyle.ink)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(height: 28)
        .background(Color.white.opacity(0.92), in: Capsule())
        .overlay(Capsule().strokeBorder(HubChromeStyle.accent.opacity(0.5), lineWidth: 1.5))
        .shadow(color: HubChromeStyle.accent.opacity(0.3), radius: 8, y: 3)
    }
}
