import SwiftUI
import AirlineEmpireCore

enum RouteManagementSection: String, CaseIterable {
    case overview = "Overview", planning = "Pricing & Schedule", aircraft = "Aircraft"
    case competition = "Competition", history = "History"
}

extension RouteManagementSection {
    /// The tab's short label: all five fit one row on a phone. The full name
    /// stays the accessibility label and the test identifier.
    var shortTitle: String {
        switch self {
        case .overview: "Overview"
        case .planning: "Plan"
        case .aircraft: "Aircraft"
        case .competition: "Rivals"
        case .history: "History"
        }
    }
}

struct RouteManagementTabs: View {
    @Binding var selection: RouteManagementSection
    var body: some View {
        // Five equal tabs in one row; at the largest text sizes a row that
        // scrolls, rather than one that clips the last tab to a sliver.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { tabs(fill: true) }.padding(4)
            ScrollView(.horizontal) {
                HStack(spacing: 4) { tabs(fill: false) }.padding(4)
            }.scrollIndicators(.hidden)
        }
        .background(AETheme.sky, in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AETheme.surfaceRim) }
    }

    @ViewBuilder
    private func tabs(fill: Bool) -> some View {
        ForEach(RouteManagementSection.allCases, id: \.self) { item in
            Button { selection = item } label: {
                Text(item.shortTitle).font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, fill ? 4 : 12).frame(minHeight: 44)
                    .frame(maxWidth: fill ? .infinity : nil)
                    .background(selection == item ? AETheme.accent.opacity(0.2) : .clear, in: .rect(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selection == item ? AETheme.accent : .clear) }
                    .contentShape(.rect)
            }.buttonStyle(.plain)
                .foregroundStyle(selection == item ? .primary : AETheme.mutedText)
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(selection == item ? .isSelected : [])
                .accessibilityIdentifier("ae-route-tab-\(item.rawValue)")
        }
    }
}

struct RouteOverviewHero: View {
    let route: Route
    let catalog: ContentCatalog
    let showMap: () -> Void
    var body: some View {
        AircraftPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    endpoint(route.origin)
                    Spacer()
                    Image(systemName: "airplane").foregroundStyle(AETheme.accent).accessibilityHidden(true)
                    Spacer()
                    endpoint(route.destination)
                }
                RouteAirportDiagram(origin: route.origin, destination: route.destination,
                                    catalog: catalog)
                    .equatable()
                ViewThatFits(in: .horizontal) {
                    HStack { facts; Spacer(); mapButton }
                    VStack(alignment: .leading, spacing: 8) { facts; mapButton }
                }
            }
        }
    }
    private var facts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(route.distanceKm.formatted()) km · \(roundTripsLabel(route.dailyRoundTrips))").font(.caption.weight(.semibold))
            Text("\(route.assignedAircraft.count) aircraft assigned").font(.caption).foregroundStyle(AETheme.mutedText)
        }
    }
    private var mapButton: some View {
        Button(action: showMap) { Label("View on map", systemImage: "map").font(.caption).frame(minHeight: 44) }
            .buttonStyle(.plain).foregroundStyle(AETheme.accent)
    }
    private func endpoint(_ code: AirportCode) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(code.raw).font(.title.bold())
            Text(catalog.airport(code)?.city ?? code.raw).font(.subheadline).foregroundStyle(AETheme.mutedText)
        }.fixedSize(horizontal: false, vertical: true)
    }
}

/// The route on real geography: the game map's own Natural Earth coastlines
/// (`WorldGeometry`), framed on the two airports, with the great-circle path
/// the aircraft fly rather than a straight line on an empty grid. Date-line
/// crossings stay one continuous curve.
///
/// Given the two codes and nothing else, and equatable on them. It took the
/// whole `Route`, whose statistics change on every tick, so the coastline
/// culling and the great circle were redrawn four times a second for a
/// picture of two fixed airports.
private struct RouteAirportDiagram: View, Equatable {
    let origin: AirportCode
    let destination: AirportCode
    let catalog: ContentCatalog

    /// Nonisolated, as `Equatable` requires; it reads only immutable,
    /// `Sendable` inputs.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.origin == rhs.origin && lhs.destination == rhs.destination
            && lhs.catalog === rhs.catalog
    }

    var body: some View {
        Canvas { context, size in
            guard let a = catalog.airport(origin), let b = catalog.airport(destination) else { return }
            // The path, longitudes unwrapped from the origin.
            var path: [(lat: Double, lon: Double)] = []
            var previous = a.coordinate.longitude
            for k in 0...48 {
                let c = MapMath.greatCirclePoint(from: a.coordinate, to: b.coordinate, fraction: Double(k) / 48)
                var lon = c.longitude
                while lon - previous > 180 { lon -= 360 }
                while lon - previous < -180 { lon += 360 }
                previous = lon
                path.append((c.latitude, lon))
            }
            // Frame the path with a margin, scaled by the cosine of the middle
            // latitude so northern routes aren't stretched sideways.
            let lats = path.map(\.lat), lons = path.map(\.lon)
            let latMin = lats.min() ?? 0, latMax = lats.max() ?? 0
            let lonMin = lons.min() ?? 0, lonMax = lons.max() ?? 0
            let latSpan = max(latMax - latMin, 2), lonSpan = max(lonMax - lonMin, 2)
            let midLat = (latMax + latMin) / 2, midLon = (lonMax + lonMin) / 2
            let cosine = max(0.25, cos(midLat * .pi / 180))
            let scale = min(size.width / ((lonSpan * 1.6 + 6) * cosine), size.height / (latSpan * 1.6 + 6))
            func point(_ lat: Double, _ lon: Double) -> CGPoint {
                CGPoint(x: (lon - midLon) * cosine * scale + size.width / 2,
                        y: (midLat - lat) * scale + size.height / 2)
            }
            let halfLon = size.width / 2 / (cosine * scale), halfLat = size.height / 2 / scale
            let level: MapZoomLevel = max(lonSpan, latSpan) > 45 ? .world : .regional
            // Sea, then land, coast and borders in every world copy the frame
            // touches (a frame across the date line needs two).
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [AETheme.mapBackground, AETheme.mapDeep]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            func shape(_ polygon: WorldGeometry.Polygon, shift: Double, closed: Bool) -> Path {
                Path { p in
                    for (i, m) in polygon.points.enumerated() {
                        let q = point(90 - m.y * 180, m.x * 360 - 180 + shift)
                        if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
                    }
                    if closed { p.closeSubpath() }
                }
            }
            for shift in [-360.0, 0, 360] {
                let west = midLon - halfLon - shift, east = midLon + halfLon - shift
                let north = midLat + halfLat, south = midLat - halfLat
                func visible(_ polygon: WorldGeometry.Polygon) -> Bool {
                    polygon.maxX * 360 - 180 >= west && polygon.minX * 360 - 180 <= east
                        && 90 - polygon.minY * 180 >= south && 90 - polygon.maxY * 180 <= north
                }
                for land in WorldGeometry.landmasses(for: level) where visible(land) {
                    let outline = shape(land, shift: shift, closed: true)
                    context.fill(outline, with: .color(AETheme.mapLand))
                    context.stroke(outline, with: .color(AETheme.mapCoast.opacity(0.7)), lineWidth: 0.6)
                }
                for border in WorldGeometry.borders(for: level) where visible(border) {
                    context.stroke(shape(border, shift: shift, closed: false),
                                   with: .color(AETheme.mapBorder.opacity(0.35)), lineWidth: 0.4)
                }
            }
            // The route: a soft glow under the line itself.
            let line = Path { p in
                for (i, c) in path.enumerated() {
                    let q = point(c.lat, c.lon)
                    if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
                }
            }
            context.stroke(line, with: .color(AETheme.accent.opacity(0.18)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
            context.stroke(line, with: .color(AETheme.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            // An aircraft at the midpoint, nose along the path.
            let mid = point(path[24].lat, path[24].lon), ahead = point(path[25].lat, path[25].lon)
            var plane = context
            plane.translateBy(x: mid.x, y: mid.y)
            plane.rotate(by: .radians(atan2(ahead.y - mid.y, ahead.x - mid.x)))
            plane.draw(Text(Image(systemName: "airplane")).font(.system(size: 13, weight: .bold))
                .foregroundStyle(AETheme.accent), at: .zero)
            // Airports: a ringed dot and the code, on the side away from the
            // other end, kept inside the frame.
            let start = point(path[0].lat, path[0].lon), end = point(path[48].lat, path[48].lon)
            for (code, p, other) in [(a.code.raw, start, end), (b.code.raw, end, start)] {
                context.fill(Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)),
                             with: .color(AETheme.positive.opacity(0.22)))
                context.fill(Path(ellipseIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)),
                             with: .color(AETheme.positive))
                let below = p.y >= other.y - 4
                context.draw(Text(code).font(.caption.bold()).foregroundStyle(.white.opacity(0.85)),
                             at: CGPoint(x: min(size.width - 22, max(22, p.x)),
                                         y: min(size.height - 10, max(10, p.y + (below ? 17 : -17)))))
            }
        }.frame(height: 150)
            .clipShape(.rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(AETheme.surfaceRim.opacity(0.6)) }
            .accessibilityLabel("Map of the route from \(origin.raw) to \(destination.raw)")
    }
}

/// "1 round trip/day", "3 round trips/day".
private func roundTripsLabel(_ count: Int) -> String {
    count == 1 ? "1 round trip/day" : "\(count) round trips/day"
}

/// What a route forecast is keyed on.
///
/// The day and the fleet's *identities* — not `Aircraft` values, whose
/// position and condition change every tick. Keyed on those, the forecast
/// restarted every 3.75 s at 1×, blanked itself each time and re-ran two
/// demand passes for figures that only move at the daily update. Operational
/// aircraft only, so a check that grounds one still re-quotes.
private struct RouteQuoteRequest: Equatable {
    let plan: RoutePlan
    let original: RoutePlan
    let day: Int64
    let fleet: [AircraftID]
    let comparison: AircraftID?

    /// Whether `other` asked the same question, perhaps on an earlier day or
    /// with a different fleet. Its figures may stay on screen while this one
    /// is calculated; figures for a different plan may not.
    func asks(sameAs other: RouteQuoteRequest?) -> Bool {
        guard let other else { return false }
        return other.plan == plan && other.original == original
            && other.comparison == comparison
    }
}

struct RoutePlanEditor: View {
    @Environment(GameController.self) private var controller
    let route: Route
    let snapshot: GameState
    let catalog: ContentCatalog
    @Binding var draft: RoutePlan?
    @State private var quote: RoutePlanPreview?
    @State private var baseline: RoutePlanPreview?
    /// The request `quote` answers, so a re-quote of the same plan can keep
    /// it on screen.
    @State private var quoted: RouteQuoteRequest?
    @State private var pending: RoutePlan?
    @State private var confirming = false
    @State private var saved = false
    private var original: RoutePlan { RoutePlan(route: route) }
    private var current: RoutePlan { draft ?? original }
    private var command: ApplyRoutePlanCommand { .init(airline: route.airline, route: route.id, plan: current) }
    private var quoteRequest: RouteQuoteRequest {
        RouteQuoteRequest(plan: current, original: original, day: snapshot.clock.now.dayIndex,
                          fleet: route.assignedAircraft.filter { snapshot.aircraft[$0]?.isOperational == true },
                          comparison: nil)
    }
    var body: some View {
        VStack(spacing: 14) {
            AircraftPanel {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Pricing & Schedule", systemImage: "slider.horizontal.3").font(.headline)
                    Text("Explore a plan before changing your route.").font(.caption).foregroundStyle(AETheme.mutedText)
                    Text("Base one-way fare").font(.subheadline)
                    Text(Format.money(current.fare)).font(.largeTitle.bold()).monospacedDigit()
                    Text("\((current.fare.asDouble / DemandSystem.referenceFare(distanceKm: route.distanceKm, tuning: catalog.tuning.demand)).formatted(.percent.precision(.fractionLength(0)))) of market reference")
                        .font(.caption.weight(.medium)).foregroundStyle(AETheme.accent)
                    Text("Premium cabin yields are applied on top of this base fare.").font(.caption).foregroundStyle(AETheme.mutedText)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 65))]) {
                        ForEach([-10, -5, 5, 10], id: \.self) { percent in
                            Button("\(percent > 0 ? "+" : "")\(percent)%") {
                                var plan = current
                                plan.fare = Money(rounding: min(1_000_000, max(1, plan.fare.asDouble * (1 + Double(percent) / 100))))
                                draft = plan; saved = false
                            }.frame(minHeight: 44).buttonStyle(.bordered)
                                .accessibilityIdentifier("ae-route-fare-\(percent)")
                        }
                    }
                    Stepper(roundTripsLabel(current.frequency), value: Binding(get: { current.frequency }, set: {
                        var plan = current; plan.frequency = $0; draft = plan; saved = false
                    }), in: 1...20).frame(minHeight: 44)
                        .accessibilityIdentifier("ae-route-frequency")
                    Text("Frequency is a target across the assigned fleet. Aircraft range, flight time and availability limit what can fly.")
                        .font(.caption).foregroundStyle(AETheme.mutedText)
                }.disabled(pending != nil)
            }
            RouteForecastCard(quote: quote, baseline: baseline, target: current.frequency)
            if current != original {
                AircraftPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Review changes").font(.headline)
                        Text("Fare: \(Format.money(original.fare)) to \(Format.money(current.fare))")
                            .font(.subheadline)
                        Text("Frequency: \(original.frequency) to \(roundTripsLabel(current.frequency))")
                            .font(.subheadline)
                        Button { confirming = true } label: {
                            Text("Apply Route Plan").frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.aePrimary).disabled(pending != nil || controller.precheck(command) != nil)
                            .accessibilityIdentifier("ae-route-plan-apply")
                        if let rejection = controller.precheck(command) {
                            // The player-facing refusal, as every other screen shows
                            // it. Core's message is written for the simulation's
                            // reader ("No such route", an inequality of slots) and
                            // was printed here verbatim.
                            RefusalNote(rejection: rejection, detail: .reason)
                        }
                        Button("Discard Changes") { draft = nil; saved = false }.frame(minHeight: 44).disabled(pending != nil)
                    }
                }
            }
            if saved { Label("Route plan saved", systemImage: "checkmark.circle.fill").foregroundStyle(AETheme.positive) }
        }
        .task(id: quoteRequest) {
            let request = quoteRequest
            let plan = request.plan, installed = request.original, state = snapshot, content = catalog, id = route.id
            // The same plan on a new day keeps its figures up until the new
            // ones land; blanking them made the card flash its placeholder on
            // every re-quote. A different plan clears them — they describe a
            // choice the player has moved away from.
            if !request.asks(sameAs: quoted) { quote = nil }
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            let results = await Task.detached(priority: .userInitiated) {
                (RoutePlanPreview.make(routeID: id, plan: plan, state: state, catalog: content),
                 RoutePlanPreview.make(routeID: id, plan: installed, state: state, catalog: content))
            }.value
            guard !Task.isCancelled else { return }
            quote = results.0; baseline = results.1; quoted = request
        }
        .onChange(of: original) { _, value in
            if pending == value { draft = nil; pending = nil; saved = true }
        }
        .onChange(of: controller.lastRejection) { _, value in if value != nil { pending = nil } }
        .confirmationDialog("Apply this route plan?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Confirm Route Plan") { if controller.submit(command) == nil { pending = current } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Base fare \(Format.money(current.fare)), \(roundTripsLabel(current.frequency)). Slots update together with the plan. Demand and scheduling respond at their next simulation update; existing flights are retained.")
        }
    }
}

struct RouteForecastCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let quote: RoutePlanPreview?
    let baseline: RoutePlanPreview?
    let target: Int
    var body: some View {
        AircraftPanel {
            VStack(alignment: .leading, spacing: 14) {
                Label("Expected Route Performance", systemImage: "chart.bar.fill").font(.headline)
                Text("30-day planning estimate").font(.caption).foregroundStyle(AETheme.mutedText)
                if let quote {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: typeSize.isAccessibilitySize ? 1 : 2), alignment: .leading, spacing: 16) {
                        metric("Revenue", quote.revenue)
                        metric("Operating & aircraft costs", quote.costs)
                        metric("Profit", quote.profit)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Load factor").font(.caption).foregroundStyle(AETheme.mutedText)
                            Text(quote.loadFactor.formatted(.percent.precision(.fractionLength(0)))).font(.title2.bold())
                            ProgressView(value: quote.loadFactor).tint(AETheme.positive)
                        }
                    }
                    if let baseline, baseline != quote {
                        let change = quote.profit - baseline.profit
                        Text("Profit change: \(change.cents >= 0 ? "+" : "")\(Format.money(change)) / month")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(change.cents >= 0 ? AETheme.positive : AETheme.caution)
                    }
                    Text("\(roundTripsLabel(quote.rotations)) achievable · \(Format.count(Int64(quote.seatsPerDay))) seats/day")
                        .font(.caption).foregroundStyle(AETheme.mutedText)
                    if quote.rotations < target {
                        Label("The fleet cannot cover the full frequency target.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(AETheme.caution)
                    }
                    if quote.profit < .zero {
                        Label("This plan is forecast to lose money.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(AETheme.caution)
                    }
                } else {
                    Text("A forecast requires a valid plan and an operational assigned aircraft. It appears after calculation completes.")
                        .font(.subheadline).foregroundStyle(AETheme.mutedText)
                }
                DisclosureGroup("What the estimate includes") {
                    Text("Uses current demand, competition, installed cabins and equipment. Includes fuel, airport fees, crew, onboard service, maintenance reserve and aircraft leases. Excludes company overhead and fixed airport services and future disruptions. Scheduling and boarding can differ from this steady-state estimate. Historical route profit uses direct booked costs and is a different measure.")
                        .font(.caption).foregroundStyle(AETheme.mutedText)
                }.font(.caption)
            }
        }.accessibilityIdentifier("ae-route-forecast")
    }
    private func metric(_ label: String, _ value: Money) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(AETheme.mutedText)
            Text(Format.money(value)).font(.title2.bold()).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}

struct RouteAircraftComparison: View {
    let route: Route
    let snapshot: GameState
    let catalog: ContentCatalog
    /// Core's eligibility for this route, asked once by the route screen and
    /// shared with its aircraft section rather than asked again here.
    let eligibility: [AssignmentCandidate]
    @State private var selected: AircraftID?
    @State private var quote: RoutePlanPreview?
    @State private var baseline: RoutePlanPreview?
    /// The request `quote` answers (see `RouteQuoteRequest.asks(sameAs:)`).
    @State private var quoted: RouteQuoteRequest?
    private func comparisonAircraft() -> [Aircraft] {
        let eligible = Set(eligibility.filter(\.isEligible).map(\.aircraftID))
        return snapshot.aircraft.values.filter { $0.owner == route.airline && $0.isOperational && (route.assignedAircraft.contains($0.id) || eligible.contains($0.id)) }.sorted { $0.id < $1.id }
    }
    var body: some View {
        // Once per pass: the picker and the task key each rebuilt this list.
        let candidates = comparisonAircraft()
        let request = RouteQuoteRequest(plan: RoutePlan(route: route), original: RoutePlan(route: route),
                                        day: snapshot.clock.now.dayIndex,
                                        fleet: candidates.map(\.id), comparison: selected)
        VStack(spacing: 14) {
            AircraftPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Compare aircraft", systemImage: "airplane").font(.headline)
                    Text("Compare your current fleet with one aircraft flying this route alone. Its installed cabin and upgrades are included. This comparison does not change assignments.")
                        .font(.caption).foregroundStyle(AETheme.mutedText)
                    Picker("Comparison aircraft", selection: $selected) {
                        Text("Current assigned fleet").tag(nil as AircraftID?)
                        ForEach(candidates, id: \.id) { aircraft in
                            if let spec = catalog.aircraftType(aircraft.typeCode) {
                                Text("\(spec.model) · \(aircraft.cabin(for: spec).totalSeats) seats · #\(aircraft.id.raw)").tag(Optional(aircraft.id))
                            }
                        }
                    }.pickerStyle(.menu).frame(minHeight: 44).accessibilityIdentifier("ae-route-aircraft-comparison")
                    if let selected, let aircraft = snapshot.aircraft[selected], let spec = catalog.aircraftType(aircraft.typeCode) {
                        AircraftSeatMap(configuration: aircraft.cabin(for: spec))
                        NavigationLink(value: selected) { Label("Open cabin & upgrades", systemImage: "chair.lounge.fill").frame(minHeight: 44) }
                    }
                }
            }
            RouteForecastCard(quote: quote, baseline: selected == nil ? nil : baseline, target: route.dailyRoundTrips)
        }
        .task(id: request) {
            let state = snapshot, content = catalog, id = route.id, comparison = request.comparison, plan = request.plan
            // Same rule as the planner: a new day or a changed fleet keeps the
            // last figures up while they are re-quoted; another aircraft
            // clears them.
            if !request.asks(sameAs: quoted) { quote = nil }
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            let result = await Task.detached(priority: .userInitiated) {
                (RoutePlanPreview.make(routeID: id, plan: plan, comparisonAircraft: comparison, state: state, catalog: content),
                 RoutePlanPreview.make(routeID: id, plan: plan, state: state, catalog: content))
            }.value
            guard !Task.isCancelled else { return }
            quote = result.0; baseline = result.1; quoted = request
        }
    }
}

struct RoutePlanHistoryCard: View {
    let route: Route
    /// The campaign's first year, so a change reads as a date ("14 Mar
    /// 2031") rather than as "Day 412", a count the player never sees
    /// anywhere else.
    let startYear: Int
    var body: some View {
        AircraftPanel {
            VStack(alignment: .leading, spacing: 14) {
                Label("Plan history", systemImage: "clock.arrow.circlepath").font(.headline)
                if let history = route.planHistory, !history.isEmpty {
                    ForEach(history, id: \.id) { change in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Format.longDate(GameCalendar.date(at: change.at, startYear: startYear)))
                                .font(.subheadline.bold())
                            Text("Fare: \(Format.money(change.previous.fare)) → \(Format.money(change.updated.fare))")
                            Text("Frequency: \(change.previous.frequency) → \(roundTripsLabel(change.updated.frequency))")
                        }.font(.caption).accessibilityElement(children: .combine)
                    }
                } else {
                    Text("No route plans changed yet. Your next confirmed change will appear here.").font(.subheadline).foregroundStyle(AETheme.mutedText)
                }
                Text("The latest 50 changes made through the route planner are saved.").font(.caption2).foregroundStyle(AETheme.mutedText)
            }
        }
    }
}
