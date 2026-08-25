import SwiftUI
import AirlineEmpireCore

/// The interactive world map (Phase 15, docs/UI_ARCHITECTURE.md §3):
/// renders `MapModel` — Core-computed positions, arcs, and interpolated
/// flights — on a zoomable Canvas. Renderer-only: no gameplay math here.
struct MapScreen: View {
    @Environment(GameController.self) private var controller
    @State private var zoom: CGFloat = 1.6
    @State private var center = CGPoint(x: 0.42, y: 0.32) // Europe-ish start
    @State private var selectedAirport: AirportCode?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if let snapshot = controller.snapshot, let catalog = controller.catalog {
                    let model = snapshot.mapModel(catalog: catalog)
                    ZStack(alignment: .bottom) {
                        MapCanvas(model: model, zoom: zoom, center: center,
                                  size: geometry.size,
                                  selectedAirport: selectedAirport)
                            .background(AETheme.mapBackground)
                            .gesture(dragGesture(size: geometry.size))
                            .gesture(zoomGesture)
                            .onTapGesture { location in
                                select(at: location, model: model,
                                       size: geometry.size)
                            }
                        if let code = selectedAirport {
                            AirportCallout(code: code)
                                .padding()
                                .transition(.move(edge: .bottom))
                        }
                    }
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { SpeedControl() }
            }
        }
    }

    // MARK: Interaction

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let scale = zoom * min(size.width, size.height)
                center.x -= value.translation.width / scale * 0.05
                center.y -= value.translation.height / scale * 0.05
                center.x = min(1, max(0, center.x))
                center.y = min(1, max(0, center.y))
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(12, max(1, zoom * value.magnification))
            }
    }

    private func select(at location: CGPoint, model: MapModel, size: CGSize) {
        let projector = MapProjector(zoom: zoom, center: center, size: size)
        var best: (AirportCode, CGFloat)?
        for airport in model.airports {
            let point = projector.project(airport.position)
            let distance = hypot(point.x - location.x, point.y - location.y)
            if distance < 28, distance < (best?.1 ?? .infinity) {
                best = (airport.code, distance)
            }
        }
        withAnimation(.snappy) { selectedAirport = best?.0 }
    }
}

/// Normalized map space → screen points.
struct MapProjector {
    let zoom: CGFloat
    let center: CGPoint
    let size: CGSize

    func project(_ point: MapPoint) -> CGPoint {
        // World aspect 2:1 (equirectangular); fit width.
        let worldWidth = size.width * zoom
        let worldHeight = worldWidth / 2
        let x = (CGFloat(point.x) - center.x) * worldWidth + size.width / 2
        let y = (CGFloat(point.y) - center.y) * worldHeight + size.height / 2
        return CGPoint(x: x, y: y)
    }
}

struct MapCanvas: View {
    let model: MapModel
    let zoom: CGFloat
    let center: CGPoint
    let size: CGSize
    let selectedAirport: AirportCode?

    var body: some View {
        Canvas { context, canvasSize in
            let projector = MapProjector(zoom: zoom, center: center, size: canvasSize)

            // Routes first (under everything). LOD: rival routes fade at
            // low zoom to keep the picture readable.
            for route in model.routes {
                var path = Path()
                var first = true
                for point in route.arc {
                    let projected = projector.project(point)
                    if first { path.move(to: projected); first = false }
                    else { path.addLine(to: projected) }
                }
                let color = route.isPlayer
                    ? (route.profitable ? AETheme.playerRoute : AETheme.caution)
                    : AETheme.rivalRoute
                let width: CGFloat = route.isPlayer ? 1.8 : (zoom > 3 ? 1.0 : 0.5)
                context.stroke(path, with: .color(color.opacity(route.isPlayer ? 0.9 : 0.45)),
                               lineWidth: width)
            }

            // Airports. LOD by prominence: small fields appear as you zoom.
            for airport in model.airports {
                let visible = airport.servedByPlayer
                    || airport.prominence > 0.35
                    || zoom > 3
                guard visible else { continue }
                let point = projector.project(airport.position)
                guard point.x > -20, point.x < canvasSize.width + 20,
                      point.y > -20, point.y < canvasSize.height + 20 else { continue }
                let radius: CGFloat = 2 + CGFloat(airport.prominence) * 3
                    + (airport.servedByPlayer ? 1.5 : 0)
                let rect = CGRect(x: point.x - radius, y: point.y - radius,
                                  width: radius * 2, height: radius * 2)
                let color: Color = airport.closed ? AETheme.negative
                    : airport.servedByPlayer ? AETheme.playerRoute : .white.opacity(0.7)
                context.fill(Path(ellipseIn: rect), with: .color(color))
                if airport.code == selectedAirport {
                    context.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)),
                                   with: .color(.white), lineWidth: 1.5)
                }
                if zoom > 2.5 || airport.servedByPlayer {
                    context.draw(Text(airport.code.raw)
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.8)),
                        at: CGPoint(x: point.x, y: point.y - radius - 7))
                }
            }

            // Live aircraft on top.
            for flight in model.flights where flight.airborne {
                let point = projector.project(flight.position)
                guard point.x > -20, point.x < canvasSize.width + 20,
                      point.y > -20, point.y < canvasSize.height + 20 else { continue }
                var symbol = context
                symbol.translateBy(x: point.x, y: point.y)
                symbol.rotate(by: .degrees(flight.heading))
                symbol.draw(Text(Image(systemName: "airplane"))
                    .font(.system(size: flight.isPlayer ? 12 : 9))
                    .foregroundStyle(flight.isPlayer ? AETheme.playerRoute : .gray),
                    at: .zero)
            }
        }
        .accessibilityLabel("World map showing your network and live flights")
    }
}

/// Selection exposes useful information (docs/UI_ARCHITECTURE.md §3):
/// airport facts + the player's standing there, straight from read models.
struct AirportCallout: View {
    @Environment(GameController.self) private var controller
    let code: AirportCode

    var body: some View {
        AECard {
            if let catalog = controller.catalog,
               let spec = catalog.airport(code),
               let snapshot = controller.snapshot {
                VStack(alignment: .leading, spacing: AETheme.spacingXS) {
                    Text("\(spec.name) (\(code.raw))").font(.headline)
                    Text("\(spec.city), \(spec.country)")
                        .font(.caption)
                        .foregroundStyle(AETheme.mutedText)
                    HStack(spacing: AETheme.spacingS) {
                        AEBadge(text: "slots \(snapshot.world.slotsUsed(at: code))/\(spec.slotCapacityPerDay)",
                                color: AETheme.accent)
                        AEBadge(text: spec.runwayClass.rawValue, color: .secondary)
                        if snapshot.world.isAirportClosed(code, at: snapshot.clock.now) {
                            AEBadge(text: "CLOSED", color: AETheme.negative,
                                    icon: "xmark.octagon")
                        }
                    }
                }
            }
        }
    }
}
