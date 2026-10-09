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

@available(iOS 18.0, *)
struct HubTopBar: View {
    let model: HubScreenModel
    let wide: Bool
    let dismiss: () -> Void
    @State private var query = ""

    var body: some View {
        HStack(spacing: 12) {
            Button(action: dismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HubChromeStyle.ink)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.7), in: Circle())
            }
            .accessibilityLabel("Close hub view")
            .accessibilityIdentifier("ae-hub-close")

            HStack(spacing: 8) {
                Image(systemName: "cube.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 1), HubChromeStyle.accent],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(model.snapshot?.airlineName ?? "Airline")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(HubChromeStyle.ink)
                    .lineLimit(1)
            }

            if wide {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(HubChromeStyle.tertiary)
                    TextField("Search stands, flights, gates, aircraft…", text: $query)
                        .font(.system(size: 13))
                        .foregroundStyle(HubChromeStyle.ink)
                    Text("⌘K").font(.system(size: 11, weight: .medium)).foregroundStyle(HubChromeStyle.tertiary)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(maxWidth: 420)
            }

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                Image(systemName: "airplane.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white, HubChromeStyle.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text(wide ? "\(model.snapshot?.city ?? model.airport.raw) Hub" : "\(model.airport.raw) Hub")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(HubChromeStyle.ink)
                        .lineLimit(1).fixedSize()
                    if wide {
                        Text("\(model.airport.raw) · \(model.layout.stands.count) stands")
                            .font(.system(size: 11)).foregroundStyle(HubChromeStyle.secondary)
                    }
                }
                if wide {
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(HubChromeStyle.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            HStack(spacing: 5) {
                Circle().fill(HubChromeStyle.good).frame(width: 7, height: 7)
                Text("Live").font(.system(size: 12, weight: .semibold)).foregroundStyle(HubChromeStyle.good)
                Text(model.snapshot?.localTime ?? "--:--")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(HubChromeStyle.ink)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(HubChromeStyle.goodSoft, in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ae-hub-clock")

            if wide {
                Image(systemName: "bell")
                    .font(.system(size: 15))
                    .foregroundStyle(HubChromeStyle.ink)
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(HubChromeStyle.bad).frame(width: 7, height: 7).offset(x: 2, y: -2)
                    }
                HStack(spacing: 8) {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.78, blue: 0.62), Color(red: 0.82, green: 0.55, blue: 0.42)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 30, height: 30)
                        .overlay(Image(systemName: "person.fill").font(.system(size: 14)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("You").font(.system(size: 13, weight: .semibold)).foregroundStyle(HubChromeStyle.ink)
                        Text("Chief Executive").font(.system(size: 11)).foregroundStyle(HubChromeStyle.secondary)
                    }
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(HubChromeStyle.tertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Color.white.opacity(0.66)))
                .overlay(alignment: .bottom) { Rectangle().fill(Color.white).frame(height: 1) }
                .shadow(color: HubChromeStyle.panelShadow, radius: 12, y: 4)
                .ignoresSafeArea(edges: .top)
        }
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HubIconTile(systemName: icon, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(HubChromeStyle.secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value).font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(HubChromeStyle.ink)
                        .contentTransition(.numericText())
                    if let delta {
                        Text(delta).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(deltaGood ? HubChromeStyle.good : HubChromeStyle.bad)
                    }
                }
                Text(detail).font(.system(size: 11)).foregroundStyle(HubChromeStyle.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minWidth: 150, maxWidth: 210, alignment: .leading)
        .hubGlass(padding: 11)
        .accessibilityElement(children: .combine)
    }
}

struct HubKPIRow: View {
    let snapshot: HubSnapshot?

    var body: some View {
        let k = snapshot?.kpis
        HStack(spacing: 10) {
            HubKPICard(icon: "clock.badge.checkmark", title: "On-time performance",
                       value: k?.onTimeRate.map { String(format: "%.1f%%", $0 * 100) } ?? "—",
                       detail: k?.onTimeRate == nil ? "No flights yet" : "avg delay \(k?.averageDelayMinutes ?? 0)m",
                       delta: k?.onTimeRate.map { $0 >= 0.85 ? "▲ on target" : "▼ below 85%" },
                       deltaGood: (k?.onTimeRate ?? 1) >= 0.85)
            HubKPICard(icon: "airplane", title: "Active flights",
                       value: "\(k?.activeFlights ?? 0)",
                       detail: "\(k?.aircraftOnGround ?? 0) of yours on the ground")
            HubKPICard(icon: "timer", title: "Avg turnaround",
                       value: "\(k?.averageTurnaroundMinutes ?? 0)m",
                       detail: "\(k?.passengersToday ?? 0) passengers today",
                       delta: k.map { String(format: "%.0f%% slots", $0.slotUse * 100) },
                       deltaGood: (k?.slotUse ?? 0) < 0.9)
        }
        .accessibilityIdentifier("ae-hub-kpis")
    }
}

// MARK: - Controls

@available(iOS 18.0, *)
struct HubControls: View {
    let model: HubScreenModel

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
        }
        .padding(.vertical, 4)
        .frame(width: 40)
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

    private func control(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HubChromeStyle.ink)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier("ae-hub-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }
}

@available(iOS 18.0, *)
struct HubShotPicker: View {
    let model: HubScreenModel
    var compact = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HubShot.allCases) { shot in
                let selected = model.shot == shot
                Button {
                    withAnimation(.snappy(duration: 0.25)) { model.select(shot) }
                } label: {
                    Label(shot.title, systemImage: shot.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(selected ? Color.white : HubChromeStyle.ink)
                        .padding(.horizontal, compact ? 8 : 11)
                        .frame(height: 30)
                        .background {
                            if selected {
                                Capsule().fill(HubChromeStyle.accent)
                                    .shadow(color: HubChromeStyle.accent.opacity(0.35), radius: 6, y: 3)
                            }
                        }
                }
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

/// Side profile of a jet in the airline's colours, for the inspector card.
struct HubAircraftProfile: View {
    let category: AircraftCategory
    let livery: Livery

    var body: some View {
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
    let model: HubScreenModel
    let occupant: HubStandOccupant

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HubIconTile(systemName: "airplane", size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(occupant.typeName).font(.system(size: 11)).foregroundStyle(HubChromeStyle.secondary)
                        .lineLimit(1)
                    Text(occupant.registration.isEmpty ? "Gate \(occupant.gate)" : occupant.registration)
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(HubChromeStyle.ink)
                }
                Spacer()
                Button { model.focusNext() } label: {
                    Image(systemName: "arrow.right.circle").font(.system(size: 16))
                }
                .accessibilityLabel("Next aircraft")
                .accessibilityIdentifier("ae-hub-next-aircraft")
                Button { model.showsInspector = false } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                }
                .accessibilityLabel("Close inspector")
            }
            .foregroundStyle(HubChromeStyle.secondary)

            HubAircraftProfile(category: occupant.category, livery: occupant.livery)
                .frame(height: 92)
                .background(LinearGradient(colors: [Color(red: 0.93, green: 0.95, blue: 1), Color(red: 0.86, green: 0.89, blue: 0.98)],
                                           startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(spacing: 5) {
                ForEach(0..<4) { i in
                    Circle().fill(i == 0 ? HubChromeStyle.accent : HubChromeStyle.track).frame(width: 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 7) {
                if let flight = occupant.flight {
                    row("Flight", flight.code)
                    row(flight.from == model.airport ? "Destination" : "From", flight.destinationCity)
                    row("Departs", flight.time)
                    row("Passengers", flight.seats > 0 ? "\(flight.passengers) / \(flight.seats)" : "\(flight.passengers)")
                    row("Status", flight.delayMinutes > 0 ? "Delayed \(flight.delayMinutes)m" : flight.status.title,
                        tint: flight.status.tint)
                } else {
                    row("Status", occupant.stage?.title ?? "Parked")
                }
                row("Stand", "Gate \(occupant.gate)")
                row("Operator", operatorName)
            }
        }
        .frame(width: 250)
        .hubGlass()
        .accessibilityIdentifier("ae-hub-inspector")
    }

    private var operatorName: String {
        switch occupant.operatorKind {
        case .player: model.snapshot?.airlineName ?? "You"
        case .rival: "Rival carrier"
        case .traffic: "Other carrier"
        }
    }

    private func row(_ label: String, _ value: String, tint: Color = HubChromeStyle.ink) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(HubChromeStyle.secondary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint).lineLimit(1)
        }
    }
}

// MARK: - Turnaround timeline

@available(iOS 18.0, *)
struct HubTimeline: View {
    let model: HubScreenModel
    let compact: Bool

    var body: some View {
        let occupant = model.focusedOccupant
        let stage = occupant?.stage
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
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
                nextAction(occupant)
                    .frame(width: 190)
            }
        }
        .hubGlass(padding: 14)
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
                ForEach(stages, id: \.rawValue) { s in
                    let done = s.rawValue < current
                    let active = s.rawValue == current
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().fill(done || active ? HubChromeStyle.accent : Color.white)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(done || active ? Color.white : HubChromeStyle.track, lineWidth: 2))
                                .shadow(color: active ? HubChromeStyle.accent.opacity(0.45) : .clear, radius: 6)
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
                }
            }
        }
        .frame(height: 50)
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

@available(iOS 18.0, *)
struct HubBoard: View {
    @Bindable var model: HubScreenModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                HubIconTile(systemName: "list.bullet.rectangle", size: 24)
                ForEach(HubScreenModel.BoardTab.allCases, id: \.self) { tab in
                    let selected = model.boardTab == tab
                    Button { model.boardTab = tab } label: {
                        Text("\(tab.rawValue) \(model.count(tab))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(selected ? HubChromeStyle.accent : HubChromeStyle.secondary)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(selected ? HubChromeStyle.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                }
                Spacer()
                Text(model.snapshot?.airportName ?? "")
                    .font(.system(size: 10)).foregroundStyle(HubChromeStyle.tertiary).lineLimit(1)
            }
            if model.boardRows.isEmpty {
                Text(model.boardTab == .delays ? "No delays." : "Nothing scheduled through this hub yet.")
                    .font(.system(size: 12)).foregroundStyle(HubChromeStyle.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(model.boardRows.prefix(4).enumerated()), id: \.offset) { _, row in
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
                    }
                }
            }
        }
        .frame(width: 330)
        .hubGlass(padding: 12)
        .accessibilityIdentifier("ae-hub-board")
    }
}

// MARK: - World-anchored overlays

struct HubCallout: View {
    let occupant: HubStandOccupant

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            line("person.2.fill", "Passengers",
                 occupant.flight.map { $0.seats > 0 ? "\($0.passengers)/\($0.seats)" : "\($0.passengers)" } ?? "—")
            line("fuelpump.fill", "Fuel", (occupant.stage ?? .deboarding) >= .boarding ? "Loaded" : "Fuelling")
            line("bolt.fill", "Ground power", occupant.stage == .pushback ? "Off" : "On")
        }
        .frame(width: 210)
        .hubGlass(radius: 14, padding: 11)
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
