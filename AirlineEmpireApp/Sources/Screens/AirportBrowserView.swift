import SwiftUI
import AirlineEmpireCore

/// Every market in the world, browsable.
///
/// There were eighty airports in the content pack and exactly one way to reach
/// any of them: find a two-to-six point dot on the map and tap it. No list, no
/// search, no comparison, and no way to see a market's demand, fees or
/// competition before committing an aircraft to it (UIUX_FORENSIC_AUDIT
/// UI-019).
struct AirportBrowserView: View {
    @Environment(GameController.self) private var controller
    @State private var search = ""
    @State private var scope: Scope = .all

    enum Scope: String, CaseIterable, Hashable {
        case all, mine, reachable

        var title: String {
            switch self {
            case .all: "All"
            case .mine: "Mine"
            case .reachable: "Reachable"
            }
        }
    }

    var body: some View {
        Group {
            if let snapshot = controller.snapshot,
               let player = snapshot.playerAirline,
               let catalog = controller.catalog {
                let rows = airports(snapshot: snapshot, player: player, catalog: catalog)
                List {
                    Section {
                        Picker("Scope", selection: $scope) {
                            ForEach(Scope.allCases, id: \.self) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    if rows.isEmpty {
                        Text(scope == .reachable
                             ? "No airport is reachable from your network with the aircraft you own."
                             : "No airport matches “\(search)”.")
                            .font(.subheadline)
                            .foregroundStyle(AETheme.mutedText)
                    }
                    ForEach(rows, id: \.code) { row in
                        NavigationLink(value: row.code) { airportRow(row) }
                    }
                }
                .searchable(text: $search, prompt: "Airport code, city or country")
                .navigationDestination(for: AirportCode.self) {
                    AirportDetailView(code: $0)
                }
            } else {
                LoadingState(message: "Loading the world")
            }
        }
        .aeScreenBackground()
        .navigationTitle("Airports")
        .navigationBarTitleDisplayMode(.inline)
        .aeTimeToolbar()
    }

    struct Row {
        let code: AirportCode
        let spec: AirportSpec
        let distanceKm: Int?
        let served: Bool
        let reachable: Bool
        let slotsUsed: Int
        let closed: Bool
    }

    private func airports(snapshot: GameState, player: Airline,
                          catalog: ContentCatalog) -> [Row] {
        let mine = Set(snapshot.routes(of: player.id).flatMap {
            [$0.origin, $0.destination]
        })
        let fleet = snapshot.fleet(of: player.id)
            .compactMap { catalog.aircraftType($0.typeCode) }
        let needle = search.uppercased()
        return catalog.orderedAirportCodes.compactMap { code -> Row? in
            guard let spec = catalog.airport(code) else { return nil }
            if !needle.isEmpty,
               !code.raw.uppercased().contains(needle),
               !spec.city.uppercased().contains(needle),
               !spec.country.uppercased().contains(needle) { return nil }
            let served = mine.contains(code)
            let reachable = !fleet.isEmpty && mine.union([player.homeAirport]).contains {
                origin in
                origin != code && fleet.contains { type in
                    catalog.routeEligibility(
                        from: origin, to: code, aircraftRangeKm: type.rangeKm,
                        aircraftRunwayRequirement: type.runwayRequirement).isEmpty
                }
            }
            switch scope {
            case .mine where !served: return nil
            case .reachable where !reachable || served: return nil
            default: break
            }
            return Row(code: code, spec: spec,
                       distanceKm: catalog.distanceKm(player.homeAirport, code),
                       served: served, reachable: reachable,
                       slotsUsed: snapshot.world.slotsUsed(at: code),
                       closed: snapshot.world.isAirportClosed(code, at: snapshot.clock.now))
        }
        .sorted { lhs, rhs in
            if lhs.served != rhs.served { return lhs.served }
            return (lhs.distanceKm ?? .max) < (rhs.distanceKm ?? .max)
        }
    }

    private func airportRow(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: AETheme.spacingXS) {
            HStack(spacing: AETheme.spacingS) {
                Text(row.code.raw)
                    .font(.subheadline.weight(.semibold)).monospaced()
                Text(row.spec.city).font(.subheadline)
                Spacer()
                if row.closed {
                    AEBadge(text: "closed", color: AETheme.negative, icon: "xmark.octagon")
                } else if row.served {
                    AEBadge(text: "you fly here", color: AETheme.playerRoute)
                } else if !row.reachable {
                    AEBadge(text: "out of reach", color: .secondary, icon: "lock")
                }
            }
            HStack(spacing: AETheme.spacingS) {
                Text(row.spec.country)
                if let distance = row.distanceKm, distance > 0 {
                    Text("· \(distance) km from home")
                }
                Spacer()
                Text("\(row.slotsUsed)/\(row.spec.slotCapacityPerDay) slots")
            }
            .font(.caption)
            .foregroundStyle(AETheme.mutedText)
        }
        .padding(.vertical, 2)
    }
}

/// One market, in the terms that decide whether to fly there.
struct AirportDetailView: View {
    @Environment(GameController.self) private var controller
    @State private var routeSheet: RouteDraft?
    let code: AirportCode

    var body: some View {
        ScrollView {
            if let snapshot = controller.snapshot,
               let player = snapshot.playerAirline,
               let catalog = controller.catalog,
               let spec = catalog.airport(code) {
                VStack(spacing: AETheme.spacingM) {
                    identity(spec, snapshot: snapshot)
                    market(spec)
                    capacity(spec, snapshot: snapshot)
                    presence(spec, snapshot: snapshot, player: player, catalog: catalog)
                }
                .padding(.horizontal)
                .padding(.bottom, AETheme.spacingL)
            } else {
                LoadingState(message: "Loading the airport")
                    .frame(minHeight: 240)
            }
        }
        .aeScreenBackground()
        .navigationTitle(code.raw)
        .navigationBarTitleDisplayMode(.inline)
        .aeTimeToolbar()
        .sheet(item: $routeSheet) { draft in
            OpenRouteSheet(suggestion: draft.suggestion)
        }
        .navigationDestination(for: RouteID.self) { RouteDetailView(routeID: $0) }
    }

    private func identity(_ spec: AirportSpec, snapshot: GameState) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                Text(spec.name).font(.headline)
                Text("\(spec.city), \(spec.country)")
                    .font(.subheadline)
                    .foregroundStyle(AETheme.mutedText)
                HStack(spacing: AETheme.spacingXS) {
                    AEChip(icon: "globe", text: Vocab.region(spec.region))
                    AEChip(icon: "road.lanes", text: Vocab.runwayDetail(spec.runwayClass))
                    AEChip(icon: "cloud.rain.fill", text: Vocab.weatherRisk(spec.weatherRisk))
                }
                if snapshot.world.isAirportClosed(code, at: snapshot.clock.now) {
                    Label("Closed right now — nothing operates here.",
                          systemImage: "xmark.octagon.fill")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.negative)
                }
            }
        }
    }

    private func market(_ spec: AirportSpec) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "The market", systemImage: "person.3")
                labelled("Catchment",
                         "\(Format.count(Int64(spec.demographics.populationThousands))) thousand people")
                labelled("Business demand",
                         String(format: "%.2f", spec.demographics.businessIndex))
                labelled("Leisure demand",
                         String(format: "%.2f", spec.demographics.leisureIndex))
                labelled("Tourism draw",
                         String(format: "%.2f", spec.demographics.tourismIndex))
                Text(spec.demographics.businessIndex >= spec.demographics.leisureIndex
                     ? "Business-led: demand is steadier across the year and less sensitive to fare."
                     : "Leisure-led: demand swings with the season and reacts hard to price.")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func capacity(_ spec: AirportSpec, snapshot: GameState) -> some View {
        let used = snapshot.world.slotsUsed(at: code)
        let fraction = spec.slotCapacityPerDay > 0
            ? Double(used) / Double(spec.slotCapacityPerDay) : 0
        return AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Slots and fees", systemImage: "clock")
                HStack {
                    Text("Daily slots used").font(.subheadline)
                    Spacer()
                    Text("\(used) / \(spec.slotCapacityPerDay)")
                        .font(.subheadline).monospacedDigit()
                }
                ProgressView(value: fraction)
                    .tint(fraction > 0.85 ? AETheme.caution : AETheme.accent)
                if fraction > 0.85 {
                    Text("Nearly full. A new route here may be refused for want of slots.")
                        .font(.caption)
                        .foregroundStyle(AETheme.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }
                labelled("Movement fee", Format.money(spec.movementFee))
                labelled("Passenger fee", Format.money(spec.passengerFee))
            }
        }
    }

    private func presence(_ spec: AirportSpec, snapshot: GameState,
                          player: Airline, catalog: ContentCatalog) -> some View {
        let mine = snapshot.routes(of: player.id).filter {
            $0.origin == code || $0.destination == code
        }
        let rivals = snapshot.orderedRouteIDs.compactMap { id -> (Airline, Route)? in
            guard let route = snapshot.routes[id], route.airline != player.id,
                  route.origin == code || route.destination == code,
                  let airline = snapshot.airlines[route.airline] else { return nil }
            return (airline, route)
        }
        return AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                AESectionHeader(text: "Who flies here", systemImage: "airplane")
                if mine.isEmpty {
                    Text("You do not serve this airport.")
                        .font(.subheadline)
                        .foregroundStyle(AETheme.mutedText)
                } else {
                    ForEach(mine, id: \.id) { route in
                        NavigationLink(value: route.id) {
                            HStack {
                                Text("\(route.origin.raw) – \(route.destination.raw)")
                                    .font(.subheadline)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundStyle(AETheme.mutedText)
                            }
                            .frame(minHeight: 44)
                        }
                    }
                }
                if !rivals.isEmpty {
                    Divider()
                    Text("\(rivals.count) rival \(rivals.count == 1 ? "service" : "services")")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                    ForEach(Array(rivals.prefix(6)), id: \.1.id) { airline, route in
                        HStack {
                            Text(airline.name).font(.caption)
                            Spacer()
                            Text("\(route.origin.raw)–\(route.destination.raw) · \(Format.money(route.ticketPrice))")
                                .font(.caption).monospacedDigit()
                                .foregroundStyle(AETheme.mutedText)
                        }
                    }
                }
                if code != player.homeAirport,
                   let distance = catalog.distanceKm(player.homeAirport, code) {
                    Button {
                        routeSheet = RouteDraft(suggestion: FirstRouteSuggestion(
                            origin: player.homeAirport, destination: code,
                            destinationCity: spec.city, distanceKm: distance,
                            expectedDailyPassengers: 0,
                            referenceFare: Money(rounding: DemandSystem.referenceFare(
                                distanceKm: distance, tuning: catalog.tuning.demand))))
                    } label: {
                        Label("Open a route from \(player.homeAirport.raw)",
                              systemImage: "plus.circle")
                            .font(.subheadline.weight(.medium))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}
