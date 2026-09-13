import SwiftUI
import AirlineEmpireCore

/// A quiet, static route atlas using the same geography as the game map.
/// Decorative only: no simulation, network request or perpetual animation.
struct MenuRouteAtlas: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width * 1.08
            func point(_ value: MapPoint) -> CGPoint {
                CGPoint(x: (value.x - 0.5) * scale + size.width / 2,
                        y: (value.y - 0.43) * scale / 2 + size.height / 2)
            }
            func path(_ points: [MapPoint], closed: Bool = false) -> Path {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: point(first))
                    for value in points.dropFirst() { path.addLine(to: point(value)) }
                    if closed { path.closeSubpath() }
                }
            }
            for line in WorldGeometry.graticule {
                context.stroke(path(line), with: .color(.white.opacity(0.045)), lineWidth: 0.5)
            }
            for land in WorldGeometry.landmasses(for: .world) {
                let shape = path(land.points, closed: true)
                context.fill(shape, with: .color(AETheme.mapLand.opacity(0.8)))
                context.stroke(shape, with: .color(AETheme.mapCoast.opacity(0.5)), lineWidth: 0.6)
            }
            let cities: [(String, Coordinate)] = [
                ("ARN", Coordinate(latitude: 59.65, longitude: 17.92)),
                ("JFK", Coordinate(latitude: 40.64, longitude: -73.78)),
                ("BCN", Coordinate(latitude: 41.30, longitude: 2.08)),
                ("SIN", Coordinate(latitude: 1.36, longitude: 103.99))
            ]
            let origin = point(MapPoint(coordinate: cities[0].1))
            for city in cities.dropFirst() {
                let destination = point(MapPoint(coordinate: city.1))
                var route = Path()
                route.move(to: origin)
                route.addQuadCurve(to: destination, control: CGPoint(
                    x: (origin.x + destination.x) / 2,
                    y: min(origin.y, destination.y) - abs(destination.x - origin.x) * 0.25))
                context.stroke(route, with: .color(AETheme.ember.opacity(0.65)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            for (index, city) in cities.enumerated() {
                let location = point(MapPoint(coordinate: city.1))
                let glow = CGRect(x: location.x - 7, y: location.y - 7, width: 14, height: 14)
                context.fill(Path(ellipseIn: glow), with: .color(AETheme.ember.opacity(0.12)))
                context.fill(Path(ellipseIn: CGRect(x: location.x - 2, y: location.y - 2,
                                                   width: 4, height: 4)),
                             with: .color(AETheme.ember))
                context.draw(Text(city.0).font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65)),
                    at: CGPoint(x: location.x, y: location.y + (index == 0 ? -14 : 14)))
            }
        }
        .mask {
            LinearGradient(colors: [.clear, .black, .black, .clear],
                           startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
