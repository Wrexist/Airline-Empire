import SwiftUI
import AirlineEmpireCore

struct FleetView: View {
    @Environment(GameController.self) private var controller
    @State private var showingShop = false

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = controller.snapshot,
                   let player = snapshot.playerAirline,
                   let catalog = controller.catalog {
                    let cards = snapshot.fleetCards(for: player.id, catalog: catalog)
                    if cards.isEmpty {
                        EmptyStateView(icon: "airplane",
                                       title: "No aircraft",
                                       message: "Buy or lease your first aircraft to start flying.")
                    } else {
                        List(cards, id: \.id) { card in
                            FleetRow(card: card)
                                .swipeActions {
                                    fleetActions(card, player: player.id)
                                }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Fleet")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingShop = true
                    } label: {
                        Label("Acquire", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingShop) {
                AircraftShopSheet()
            }
        }
    }

    @ViewBuilder
    private func fleetActions(_ card: FleetCardModel, player: AirlineID) -> some View {
        if card.assignedRoute != nil {
            Button("Unassign") {
                controller.submit(UnassignAircraftCommand(
                    airline: player, aircraftID: card.id))
            }
        } else {
            switch card.ownershipDescription {
            case .owned:
                Button("Sell", role: .destructive) {
                    controller.submit(SellAircraftCommand(
                        seller: player, aircraftID: card.id))
                }
            case .leased:
                Button("Return", role: .destructive) {
                    controller.submit(ReturnLeasedAircraftCommand(
                        lessee: player, aircraftID: card.id))
                }
            }
        }
    }
}

struct FleetRow: View {
    let card: FleetCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingXS) {
            HStack {
                Text(card.typeName).font(.body.weight(.semibold))
                Spacer()
                statusBadge
            }
            HStack(spacing: AETheme.spacingS) {
                AEBadge(text: "\(String(format: "%.0f", card.ageYears))y",
                        color: .secondary)
                AEBadge(text: "cond \(Format.percent(card.condition))",
                        color: card.condition > 0.8 ? AETheme.positive : AETheme.caution)
                switch card.ownershipDescription {
                case .owned(let book):
                    AEBadge(text: "owned · \(Format.money(book))", color: .indigo)
                case .leased(let rate, _):
                    AEBadge(text: "lease \(Format.money(rate))/mo", color: .teal)
                }
                if card.assignedRoute == nil {
                    AEBadge(text: "idle", color: AETheme.caution, icon: "pause")
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch card.status {
        case .active:
            AEBadge(text: "at \(card.location.raw)", color: AETheme.positive)
        case .ordered:
            AEBadge(text: "on order", color: AETheme.accent, icon: "shippingbox")
        case .inMaintenance:
            AEBadge(text: "maintenance", color: AETheme.caution, icon: "wrench")
        }
    }
}

struct AircraftShopSheet: View {
    @Environment(GameController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @State private var usedAge = 8

    var body: some View {
        NavigationStack {
            List {
                if let catalog = controller.catalog,
                   let snapshot = controller.snapshot,
                   let player = snapshot.playerAirline {
                    Section("Used market age: \(usedAge) years") {
                        Stepper("Age", value: $usedAge,
                                in: 1...catalog.tuning.fleet.maxUsedPurchaseAgeYears)
                    }
                    ForEach(catalog.orderedAircraftTypeCodes, id: \.self) { code in
                        if let spec = catalog.aircraftTypes[code] {
                            shopRow(spec, catalog: catalog, snapshot: snapshot,
                                    player: player.id)
                        }
                    }
                }
            }
            .navigationTitle("Aircraft market")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func shopRow(_ spec: AircraftTypeSpec, catalog: ContentCatalog,
                         snapshot: GameState, player: AirlineID) -> some View {
        let locked = !snapshot.progression.era.allowedCategories.contains(spec.category)
        let usedPrice = FleetEconomics.usedPrice(
            type: spec, ageYears: Double(usedAge),
            condition: FleetEconomics.usedMarketCondition(
                ageYears: Double(usedAge), tuning: catalog.tuning.fleet),
            tuning: catalog.tuning.fleet)
        return VStack(alignment: .leading, spacing: AETheme.spacingXS) {
            HStack {
                Text("\(spec.manufacturer) \(spec.model)")
                    .font(.body.weight(.semibold))
                Spacer()
                if locked {
                    AEBadge(text: "later era", color: .secondary, icon: "lock")
                }
            }
            Text("\(spec.seats) seats · \(spec.rangeKm) km · burn \(String(format: "%.1f", spec.fuelBurnKgPerKm)) kg/km")
                .font(.caption)
                .foregroundStyle(AETheme.mutedText)
            if !locked {
                HStack(spacing: AETheme.spacingS) {
                    Button("New \(Format.money(spec.listPrice))") {
                        controller.submit(BuyNewAircraftCommand(buyer: player,
                                                                type: spec.code))
                    }
                    Button("Used \(Format.money(usedPrice))") {
                        controller.submit(BuyUsedAircraftCommand(
                            buyer: player, type: spec.code, ageYears: usedAge))
                    }
                    Button("Lease \(Format.money(spec.leaseMonthly))/mo") {
                        controller.submit(LeaseAircraftCommand(
                            lessee: player, type: spec.code, termMonths: 60))
                    }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}
