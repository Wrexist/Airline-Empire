import SwiftUI
import AirlineEmpireCore

struct RoutesView: View {
    @Environment(GameController.self) private var controller
    @State private var showingOpenSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = controller.snapshot,
                   let player = snapshot.playerAirline,
                   let catalog = controller.catalog {
                    let cards = snapshot.routeCards(for: player.id, catalog: catalog)
                    if cards.isEmpty {
                        EmptyStateView(icon: "point.topleft.down.to.point.bottomright.curvepath",
                                       title: "No routes yet",
                                       message: "Open your first route — pick a market and put an aircraft on it.")
                    } else {
                        List(cards, id: \.id) { card in
                            NavigationLink(value: card.id) {
                                RouteRow(card: card)
                            }
                        }
                        .navigationDestination(for: RouteID.self) { routeID in
                            RouteDetailView(routeID: routeID)
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Routes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingOpenSheet = true
                    } label: {
                        Label("Open route", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingOpenSheet) {
                OpenRouteSheet()
            }
        }
    }
}

struct RouteRow: View {
    let card: RouteCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: AETheme.spacingXS) {
            HStack {
                Text("\(card.origin.raw) – \(card.destination.raw)")
                    .font(.body.weight(.semibold))
                Spacer()
                MoneyText(money: card.lastMonthProfit).font(.subheadline)
            }
            HStack(spacing: AETheme.spacingS) {
                AEBadge(text: "\(card.dailyRoundTrips)×/day", color: AETheme.accent)
                AEBadge(text: "load \(Format.percent(card.loadFactor))",
                        color: card.loadFactor > 0.7 ? AETheme.positive : AETheme.caution)
                AEBadge(text: Format.money(card.ticketPrice), color: .purple)
                if card.assignedAircraftCount == 0 {
                    AEBadge(text: "no aircraft", color: AETheme.negative,
                            icon: "exclamationmark.triangle")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// The route P&L breakdown: "why did this route make or lose money"
/// (docs/ECONOMY.md) — the exact simulation figures, no UI math.
struct RouteDetailView: View {
    @Environment(GameController.self) private var controller
    let routeID: RouteID
    @State private var editedFare: Double = 0

    var body: some View {
        ScrollView {
            if let snapshot = controller.snapshot,
               let player = snapshot.playerAirline,
               let catalog = controller.catalog,
               let card = snapshot.routeCards(for: player.id, catalog: catalog)
                   .first(where: { $0.id == routeID }) {
                VStack(spacing: AETheme.spacingM) {
                    breakdown(card)
                    operations(card)
                    fareControls(card)
                    dangerZone(card, player: player.id)
                }
                .padding(.horizontal)
            } else {
                EmptyStateView(icon: "xmark.circle", title: "Route closed",
                               message: "This route no longer exists.")
            }
        }
        .navigationTitle(title)
    }

    private var title: String {
        guard let snapshot = controller.snapshot,
              let route = snapshot.routes[routeID] else { return "Route" }
        return "\(route.origin.raw) – \(route.destination.raw)"
    }

    private func breakdown(_ card: RouteCardModel) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                Text("Last month, where the money went").font(.headline)
                row("Ticket revenue", Money(cents: card.lastMonthBreakdown.revenueCents))
                row("Fuel", Money(cents: -card.lastMonthBreakdown.fuelCents))
                row("Airport fees", Money(cents: -card.lastMonthBreakdown.feesCents))
                row("Crew", Money(cents: -card.lastMonthBreakdown.crewCents))
                Divider()
                row("Direct operating profit", card.lastMonthProfit)
                Text("\(card.lastMonthPassengers) passengers · fleet costs and company overhead are airline-level (see Finance)")
                    .font(.caption)
                    .foregroundStyle(AETheme.mutedText)
            }
        }
    }

    private func operations(_ card: RouteCardModel) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                Text("Operations").font(.headline)
                row2("Load factor", Format.percent(card.loadFactor))
                row2("Punctuality", Format.percent(card.punctuality))
                row2("Completion", Format.percent(card.completionRate))
                row2("Distance", "\(card.distanceKm) km")
                row2("Aircraft assigned", "\(card.assignedAircraftCount)")
            }
        }
    }

    private func fareControls(_ card: RouteCardModel) -> some View {
        AECard {
            VStack(alignment: .leading, spacing: AETheme.spacingS) {
                Text("Fare").font(.headline)
                HStack {
                    Text(Format.money(card.ticketPrice)).monospacedDigit()
                    Spacer()
                    Text(String(format: "%.0f%% of market reference",
                                card.farePosition * 100))
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                }
                HStack(spacing: AETheme.spacingS) {
                    ForEach([-10, -5, 5, 10], id: \.self) { percent in
                        Button("\(percent > 0 ? "+" : "")\(percent)%") {
                            let newFare = Money(rounding: card.ticketPrice.asDouble
                                * (1 + Double(percent) / 100))
                            controller.submit(SetRoutePriceCommand(
                                airline: controller.snapshot!.playerAirline!.id,
                                route: routeID, ticketPrice: newFare))
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Stepper("Frequency: \(card.dailyRoundTrips)×/day",
                        onIncrement: { changeFrequency(card, by: 1) },
                        onDecrement: { changeFrequency(card, by: -1) })
            }
        }
    }

    private func dangerZone(_ card: RouteCardModel, player: AirlineID) -> some View {
        AECard {
            Button(role: .destructive) {
                controller.submit(CloseRouteCommand(airline: player, route: routeID))
            } label: {
                Label("Close route", systemImage: "xmark.circle")
            }
        }
    }

    private func changeFrequency(_ card: RouteCardModel, by delta: Int) {
        guard let player = controller.snapshot?.playerAirline?.id else { return }
        controller.submit(SetRouteFrequencyCommand(
            airline: player, route: routeID,
            dailyRoundTrips: card.dailyRoundTrips + delta))
    }

    private func row(_ label: String, _ money: Money) -> some View {
        HStack {
            Text(label)
            Spacer()
            MoneyText(money: money)
        }
        .font(.subheadline)
    }

    private func row2(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}

/// ≤4 taps from map or list to an open route (docs/CORE_LOOP.md §6).
struct OpenRouteSheet: View {
    @Environment(GameController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @State private var origin: AirportCode = "STV"
    @State private var destination: AirportCode = "LNW"
    @State private var trips = 2
    @State private var fare = 129.0

    var body: some View {
        NavigationStack {
            Form {
                if let catalog = controller.catalog {
                    Picker("From", selection: $origin) {
                        ForEach(catalog.orderedAirportCodes, id: \.self) { code in
                            Text("\(code.raw) — \(catalog.airports[code]?.city ?? "")")
                                .tag(code)
                        }
                    }
                    Picker("To", selection: $destination) {
                        ForEach(catalog.orderedAirportCodes, id: \.self) { code in
                            Text("\(code.raw) — \(catalog.airports[code]?.city ?? "")")
                                .tag(code)
                        }
                    }
                    Stepper("Round trips per day: \(trips)", value: $trips, in: 1...20)
                    VStack(alignment: .leading) {
                        Text("Fare: ¤\(Int(fare))")
                        Slider(value: $fare, in: 30...800, step: 1)
                        if let distance = catalog.distanceKm(origin, destination) {
                            let reference = DemandSystem.referenceFare(
                                distanceKm: distance, tuning: catalog.tuning.demand)
                            Text("Market reference for \(distance) km ≈ ¤\(Int(reference))")
                                .font(.caption)
                                .foregroundStyle(AETheme.mutedText)
                        }
                    }
                }
            }
            .navigationTitle("Open route")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") {
                        if let player = controller.snapshot?.playerAirline?.id {
                            controller.submit(OpenRouteCommand(
                                airline: player, origin: origin,
                                destination: destination, dailyRoundTrips: trips,
                                ticketPrice: Money.dollars(Int64(fare))))
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let home = controller.snapshot?.playerAirline?.homeAirport {
                    origin = home
                }
            }
        }
    }
}
