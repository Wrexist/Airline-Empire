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
    @State private var cache = RowCache()
    @State private var selectedAirport: AirportCode?

    /// Per-tick memo for the row list (UIUX_FORENSIC_AUDIT UI-016, the same
    /// problem `GameController` solved for the map).
    ///
    /// The reachability scan runs once per catalog airport and, inside that,
    /// once per served origin and owned aircraft type — O(world) work that
    /// `body` repeated on all four snapshots a second the pump publishes. A
    /// reference type deliberately: it is a memo of what the snapshot already
    /// says, not state a view should observe, so writing to it must not
    /// invalidate the render that filled it.
    @MainActor private final class RowCache {
        private struct Key: Equatable {
            let tick: Int64
            let scope: Scope
            let search: String
        }

        private var key: Key?
        private var rows: [Row] = []

        func rows(tick: Int64, scope: Scope, search: String,
                  build: () -> [Row]) -> [Row] {
            let wanted = Key(tick: tick, scope: scope, search: search)
            if key == wanted { return rows }
            rows = build()
            key = wanted
            return rows
        }
    }

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
                let rows = cache.rows(tick: snapshot.clock.tickCount,
                                      scope: scope, search: search) {
                    airports(snapshot: snapshot, player: player, catalog: catalog)
                }
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
                        EmptyStateView(icon: "magnifyingglass",
                                       title: "No airports found",
                                       message: emptyMessage,
                                       actionTitle: "Show all airports",
                                       action: { search = ""; scope = .all })
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(rows, id: \.code) { row in
                        Button { selectedAirport = row.code } label: {
                            HStack(spacing: 12) {
                                airportRow(row)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(AETheme.mutedText)
                            }
                        }.buttonStyle(.plain)
                            .aeListRow()
                            .accessibilityIdentifier("ae-airport-row-\(row.code.raw)")
                    }
                }
                .listStyle(.plain)
                .searchable(text: $search,
                            placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "Airport code, city or country")
                .aeScreenBackground()
            } else {
                LoadingState(message: "Loading the world")
            }
        }
        .aeScreenBackground()
        .navigationTitle("Airports")
        .navigationBarTitleDisplayMode(.inline)
        .aeTimeToolbar()
        .navigationDestination(item: $selectedAirport) { AirportDetailView(code: $0) }
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

    /// The empty list has three different causes and they read nothing alike.
    /// The quotes-around-nothing version — "No airport matches “”." — is
    /// reachable at the very start of a game, when the airline serves none.
    private var emptyMessage: String {
        if scope == .reachable {
            return "No airport is reachable from your network with the aircraft you own."
        }
        if search.isEmpty {
            return scope == .mine
                ? "You do not serve any airport yet."
                : "No airports are available."
        }
        return "No airport matches “\(search)”."
    }

    private func airports(snapshot: GameState, player: Airline,
                          catalog: ContentCatalog) -> [Row] {
        let mine = Set(snapshot.routes(of: player.id).flatMap {
            [$0.origin, $0.destination]
        }).union([player.homeAirport]).union((player.airportFacilities ?? [:]).keys)
        // Distinct types, not aircraft: a player with ten of one type used to
        // run the eligibility check ten times for the same answer.
        var seenTypes = Set<AircraftTypeCode>()
        let fleet = snapshot.fleet(of: player.id)
            .filter { seenTypes.insert($0.typeCode).inserted }
            .compactMap { catalog.aircraftType($0.typeCode) }
        // Hoisted: this was rebuilt inside the loop, once per airport.
        let origins = mine.union([player.homeAirport])
        let needle = search.uppercased()
        return catalog.orderedAirportCodes.compactMap { code -> Row? in
            guard let spec = catalog.airport(code) else { return nil }
            if !needle.isEmpty,
               !code.raw.uppercased().contains(needle),
               !spec.city.uppercased().contains(needle),
               !spec.country.uppercased().contains(needle) { return nil }
            let served = mine.contains(code)
            let reachable = !fleet.isEmpty && origins.contains { origin in
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(row.code.raw)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(AETheme.accent)
                    .padding(10)
                    .background(AETheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(Vocab.airportDisplay(row.spec)).font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(row.spec.country).font(.caption).foregroundStyle(AETheme.mutedText)
                }
            }
            AEChipRow {
                if row.closed {
                    AEBadge(text: "closed", color: AETheme.negative, icon: "xmark.octagon")
                } else if row.served {
                    AEBadge(text: "your network", color: AETheme.positive, icon: "checkmark")
                } else if !row.reachable {
                    AEBadge(text: "out of reach", color: .secondary, icon: "lock")
                }
                if let distance = row.distanceKm, distance > 0 {
                    AEBadge(text: "\(distance) km from home", color: .secondary)
                }
                AEBadge(text: "\(row.slotsUsed)/\(row.spec.slotCapacityPerDay) slots", color: .secondary)
            }
        }
    }

}
