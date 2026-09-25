import SwiftUI
import AirlineEmpireCore

enum RouteManagementSection: String, CaseIterable {
    case overview = "Overview", planning = "Pricing & Schedule", aircraft = "Aircraft"
    case competition = "Competition", history = "History"
}

struct RouteManagementTabs: View {
    @Binding var selection: RouteManagementSection
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(RouteManagementSection.allCases, id: \.self) { item in
                    Button { selection = item } label: {
                        Text(item.rawValue).font(.caption.weight(.semibold))
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .background(selection == item ? AETheme.accent.opacity(0.2) : .clear, in: .rect(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selection == item ? AETheme.accent : .clear) }
                    }.buttonStyle(.plain)
                        .foregroundStyle(selection == item ? .primary : AETheme.mutedText)
                        .accessibilityAddTraits(selection == item ? .isSelected : [])
                        .accessibilityIdentifier("ae-route-tab-\(item.rawValue)")
                }
            }.padding(4)
        }.scrollIndicators(.hidden)
            .background(AETheme.sky, in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AETheme.surfaceRim) }
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
                RouteAirportDiagram(route: route, catalog: catalog)
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

/// Geographic airport diagram, centered on the endpoints, including date-line crossings.
private struct RouteAirportDiagram: View {
    let route: Route
    let catalog: ContentCatalog
    var body: some View {
        Canvas { context, size in
            guard let a = catalog.airport(route.origin), let b = catalog.airport(route.destination) else { return }
            func longitude(_ value: Double) -> Double {
                let delta = value - a.coordinate.longitude
                return delta - floor((delta + 180) / 360) * 360
            }
            let dx = longitude(b.coordinate.longitude)
            let west = min(0, dx) - 5, spanX = max(10, abs(dx) + 10)
            let south = min(a.coordinate.latitude, b.coordinate.latitude) - 5
            let spanY = max(10, abs(a.coordinate.latitude - b.coordinate.latitude) + 10)
            func point(_ airport: AirportSpec) -> CGPoint {
                CGPoint(x: (longitude(airport.coordinate.longitude) - west) / spanX * size.width,
                        y: (1 - (airport.coordinate.latitude - south) / spanY) * size.height)
            }
            for index in 1..<6 {
                var grid = Path()
                let x = size.width * Double(index) / 6
                grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(grid, with: .color(AETheme.surfaceRim.opacity(0.3)), lineWidth: 0.5)
            }
            for airport in catalog.airports.values {
                let p = point(airport)
                if p.x > 0 && p.x < size.width && p.y > 0 && p.y < size.height {
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)), with: .color(AETheme.mutedText.opacity(0.4)))
                }
            }
            let start = point(a), end = point(b)
            var line = Path(); line.move(to: start); line.addLine(to: end)
            context.stroke(line, with: .color(AETheme.accent.opacity(0.15)), lineWidth: 12)
            context.stroke(line, with: .color(AETheme.accent), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            for (airport, p) in [(a, start), (b, end)] {
                context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(AETheme.positive))
                context.draw(Text(airport.code.raw).font(.caption.bold()).foregroundStyle(AETheme.mutedText), at: CGPoint(x: min(size.width - 20, max(20, p.x)), y: min(size.height - 10, max(10, p.y + 17))))
            }
        }.frame(height: 140).clipped()
            .background(AETheme.canvas.opacity(0.6), in: .rect(cornerRadius: 12))
            .accessibilityLabel("Airport map, \(route.origin.raw) to \(route.destination.raw)")
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
                            Text(rejection.message).font(.caption).foregroundStyle(AETheme.caution)
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
