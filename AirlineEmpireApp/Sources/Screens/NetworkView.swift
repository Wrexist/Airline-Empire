import SwiftUI
import AirlineEmpireCore

/// Routes and Fleet, in one tab.
///
/// Six tabs overflowed into the system *More* list on iPhone, which buried
/// Finance and World (UIUX_FORENSIC_AUDIT UI-001). These two are the halves of
/// a single question — where you fly, and what you fly it with — and a player
/// moving an aircraft onto a route crosses between them constantly, so putting
/// them behind one segmented switch costs a tap only when changing subject.
struct NetworkView: View {
    @Environment(GameController.self) private var controller
    @State private var section: Section = .routes
    @State private var showingOpenRoute = false
    @State private var showingShop = false

    enum Section: String, CaseIterable, Hashable {
        case routes, fleet
        var title: String {
            switch self {
            case .routes: "Routes"
            case .fleet: "Fleet"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch section {
                case .routes: RoutesList()
                case .fleet: FleetList()
                }
            }
            .background(AEGameBackdrop())
            .navigationTitle(section.title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { picker }
            .aeTimeToolbar()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    switch section {
                    case .routes:
                        Button { showingOpenRoute = true } label: {
                            Label("Open route", systemImage: "plus")
                        }
                    case .fleet:
                        Button { showingShop = true } label: {
                            Label("Acquire", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingOpenRoute) { OpenRouteSheet() }
            .sheet(isPresented: $showingShop) { AircraftShopSheet() }
            .navigationDestination(for: RouteID.self) { RouteDetailView(routeID: $0) }
            .navigationDestination(for: AircraftID.self) { AircraftDetailView(aircraftID: $0) }
        }
    }

    private var picker: some View {
        Picker("Section", selection: $section) {
            ForEach(Section.allCases, id: \.self) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, AETheme.spacingM)
        .padding(.bottom, AETheme.spacingS)
        .background(.bar)
        .sensoryFeedback(.selection, trigger: section)
    }
}

/// How a list is ordered. Both lists grow past the point where creation order
/// is usable — thirty routes in the order they were opened is a wall
/// (UIUX_FORENSIC_AUDIT UI-017).
enum RouteSort: String, CaseIterable, Hashable {
    case profit, load, name, needsAttention

    var title: String {
        switch self {
        case .profit: "Profit"
        case .load: "Load factor"
        case .name: "Name"
        case .needsAttention: "Needs attention"
        }
    }
}

enum FleetSort: String, CaseIterable, Hashable {
    case status, type, age, condition

    var title: String {
        switch self {
        case .status: "Status"
        case .type: "Type"
        case .age: "Age"
        case .condition: "Condition"
        }
    }
}
