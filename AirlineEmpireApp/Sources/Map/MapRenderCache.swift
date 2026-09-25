import SwiftUI
import AirlineEmpireCore

/// The map's cached geometry, and the affine replay that makes a drag cheap.
///
/// The baseline (docs/MAP_RUNTIME_BASELINE.md §5, run 84) measured what the
/// old path cost: every finger event rebuilt the whole frame — thousands of
/// re-projected geography points, every route waypoint, the terminator —
/// for **16.8 ms average and 256 ms worst** during drags. But the projection
/// is affine: a camera move maps every already-projected point by one
/// uniform scale and one translation. So the expensive layers are built
/// *once* at a reference camera, and every frame between rebuilds replays
/// them under that transform — a pan costs a translation, exactly as the
/// geometry always allowed.
///
/// **What is cached, in which space:** two independent path sets, both in
/// screen space at the camera they were built with —
/// - *geography*: graticule, equator, land (fill + coast), lakes, borders,
///   and the day/night terminator, keyed by LOD tier, world-offset set and
///   canvas size. The terminator alone also follows the game hour, and is
///   rebuilt alone when the hour turns — at the reference camera the rest
///   was built at, so the one replay transform still serves all of it;
/// - *routes*: one stroke list per route (glow underlay + main stroke, in
///   z-order, rivals before players), plus each route's hit polylines, keyed
///   by the same camera terms plus overlay, simulation revision and
///   selection.
///
/// **Invalidation, exhaustively** (each cause counted, for the probe):
/// LOD tier change, world-offset set change, canvas size change, game-hour
/// change (the night layer only), simulation revision (routes only —
/// health and frequency restyle per tick, and a route opened, assigned or
/// closed while paused has to appear without a tick), overlay or
/// selected-route change (routes only), zoom drifting past ±25% of the
/// built zoom, or the camera panning beyond the culling headroom. Nothing
/// else rebuilds; in particular a finger move never does.
///
/// **Headroom:** paths are built with the viewport expanded by
/// `panHeadroom` screens on every side, and a rebuild triggers at 80% of
/// that, so content panned into view was already built. Memory stays
/// bounded: one geography set, one route set, no history.
///
/// **Stroke widths under replay:** a uniform context scale `s` would scale
/// stroke widths and dashes too, so replay strokes divide both by `s` —
/// geometry scales, line weights hold. (Between rebuilds `s` stays within
/// [0.75, 1.33] by the zoom trigger, so compensation never distorts dashes
/// visibly.)
///
/// A plain class, deliberately not `@Observable`, for `MapHitGeometry`'s
/// reason: it is read and written from inside the draw, and observing it
/// would let a frame's own output invalidate the view that drew it.
final class MapRenderCache {

    // MARK: - Probe counters

    /// Deterministic evidence for the structural targets
    /// (docs/MAP_PERFORMANCE_TARGETS.md D1/D2): a drag sequence must show
    /// `replays` climbing while `rebuilds` stands still.
    private(set) var rebuilds = 0
    private(set) var replays = 0
    private(set) var rebuildReasons: [String: Int] = [:]

    private func countRebuild(_ reason: String) {
        rebuilds += 1
        rebuildReasons[reason, default: 0] += 1
    }

    var counterSummary: String {
        let reasons = rebuildReasons.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }.joined(separator: ",")
        return "cache rebuilds \(rebuilds) replays \(replays) " +
               "placements \(placementRuns) reasons [\(reasons)]"
    }

    /// How far, in screens, the cache builds beyond the viewport on each
    /// side. Rebuild triggers at 80% of it so revealed content always
    /// already exists.
    private let panHeadroom: CGFloat = 0.75

    // MARK: - The affine replay

    struct Replay {
        let transform: CGAffineTransform
        let scale: CGFloat
    }

    private func replayTransform(builtZoom: CGFloat, builtCenter: CGPoint,
                                 projector: MapProjector) -> Replay {
        let s = projector.zoom / builtZoom
        // screen_now = s * screen_built + t, solved from the projector's own
        // equation at both cameras.
        let tx = projector.size.width / 2 * (1 - s)
            + (builtCenter.x - projector.center.x) * projector.worldWidth
        let ty = projector.size.height / 2 * (1 - s)
            + (builtCenter.y - projector.center.y) * projector.worldHeight
        return Replay(transform: CGAffineTransform(a: s, b: 0, c: 0, d: s,
                                                   tx: tx, ty: ty),
                      scale: s)
    }

    private func cameraDrifted(builtZoom: CGFloat, builtCenter: CGPoint,
                               projector: MapProjector) -> String? {
        let s = projector.zoom / builtZoom
        if s < 0.75 || s > 1.33 { return "zoomBand" }
        let dx = abs(builtCenter.x - projector.center.x) * projector.worldWidth
        let dy = abs(builtCenter.y - projector.center.y) * projector.worldHeight
        if dx > panHeadroom * 0.8 * projector.size.width
            || dy > panHeadroom * 0.8 * projector.size.height {
            return "panMargin"
        }
        return nil
    }

    /// The viewport in map space with the pan headroom applied — what the
    /// builders cull against, so a replayed pan never reveals unbuilt world.
    private func headroomRect(_ projector: MapProjector)
        -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        let topLeft = projector.unproject(.zero)
        let bottomRight = projector.unproject(
            CGPoint(x: projector.size.width, y: projector.size.height))
        let mx = Double(panHeadroom / projector.zoom)
        let my = Double(panHeadroom * projector.size.height / projector.worldHeight)
        let x0 = Double(topLeft.x), x1 = Double(bottomRight.x)
        let y0 = Double(topLeft.y), y1 = Double(bottomRight.y)
        return (min(x0, x1) - mx, max(x0, x1) + mx,
                min(y0, y1) - my, max(y0, y1) + my)
    }

    // MARK: - Geography

    /// No clock in the key. The game hour used to be part of it, so the
    /// terminator's hourly step threw away every coastline with it — about
    /// once a real second at 16×, each a 29,000-point rebuild the player
    /// felt as a hitch. The night layer now keeps its own hour
    /// (`nightHour`).
    private struct GeographyKey: Equatable {
        let level: MapZoomLevel
        let offsets: [Double]
        let size: CGSize
    }

    private struct Geography {
        var grid = Path()
        var equator = Path()
        var land = Path()
        var lakes = Path()
        var borders = Path()
        var landStrokeWidth: CGFloat = 0.7
        var borderStyle = StrokeStyle(lineWidth: 0.7)
        /// Terminator fills with their alphas, widest first.
        var night: [(Path, Double)] = []
    }

    private var geography: Geography?
    private var geographyKey: GeographyKey?
    private var geographyZoom: CGFloat = 1
    private var geographyCenter = CGPoint.zero
    /// The game hour the night layer was last built for.
    private var nightHour: Int?

    /// Ensures the geography cache is valid for this camera, then draws it —
    /// grid, equator, land, lakes, borders, night, in the exact order the
    /// un-cached path used.
    func drawGeography(into context: inout GraphicsContext,
                       projector: MapProjector, policy: MapDetailPolicy,
                       date: GameDate) {
        let key = GeographyKey(level: policy.level,
                               offsets: projector.visibleWorldOffsets,
                               size: projector.size)
        // The terminator's clock, one step per game hour. The year is in it
        // so a save reopened a year later to the hour cannot keep a stale
        // night.
        let hour = ((date.year * 12 + date.month) * 31 + date.day) * 24
            + date.hour
        if geography == nil {
            countRebuild("first")
            buildGeography(projector: projector, policy: policy, date: date, key: key)
        } else if geographyKey != key {
            countRebuild(reasonForKeyChange(old: geographyKey, new: key))
            buildGeography(projector: projector, policy: policy, date: date, key: key)
        } else if let drift = cameraDrifted(builtZoom: geographyZoom,
                                            builtCenter: geographyCenter,
                                            projector: projector) {
            countRebuild(drift)
            buildGeography(projector: projector, policy: policy, date: date, key: key)
        } else if nightHour != hour {
            // Only the terminator moved. Built at the camera the rest of the
            // geography was built at, so the one replay transform below still
            // places it: two 97-point polygons instead of the whole world.
            countRebuild("night")
            let reference = MapProjector(zoom: geographyZoom,
                                         center: geographyCenter,
                                         size: projector.size)
            geography?.night = Self.nightPolygons(projector: reference, date: date)
        } else {
            replays += 1
        }
        nightHour = hour
        guard let geography else { return }

        let replay = replayTransform(builtZoom: geographyZoom,
                                     builtCenter: geographyCenter,
                                     projector: projector)
        var layer = context
        layer.translateBy(x: replay.transform.tx, y: replay.transform.ty)
        layer.scaleBy(x: replay.scale, y: replay.scale)
        let s = replay.scale

        layer.stroke(geography.grid, with: .color(AETheme.mapGraticule),
                     lineWidth: 0.5 / s)
        layer.stroke(geography.equator,
                     with: .color(AETheme.mapGraticule.opacity(1.6)),
                     lineWidth: 0.7 / s)
        layer.fill(geography.land, with: .color(AETheme.mapLand))
        layer.stroke(geography.land, with: .color(AETheme.mapCoast),
                     lineWidth: geography.landStrokeWidth / s)
        layer.fill(geography.lakes, with: .color(AETheme.mapBackground))
        layer.stroke(geography.lakes,
                     with: .color(AETheme.mapCoast.opacity(0.6)),
                     lineWidth: 0.5 / s)
        layer.stroke(geography.borders, with: .color(AETheme.mapBorder),
                     style: compensated(geography.borderStyle, by: s))
        for (path, alpha) in geography.night {
            layer.fill(path, with: .color(.black.opacity(alpha)))
        }
    }

    private func reasonForKeyChange(old: GeographyKey?, new: GeographyKey) -> String {
        guard let old else { return "first" }
        if old.level != new.level { return "lod" }
        if old.size != new.size { return "size" }
        if old.offsets != new.offsets { return "offsets" }
        return "key"
    }

    private func buildGeography(projector: MapProjector, policy: MapDetailPolicy,
                                date: GameDate, key: GeographyKey) {
        var built = Geography()
        let view = headroomRect(projector)
        let level = policy.level

        for offset in projector.visibleWorldOffsets {
            for line in WorldGeometry.graticule {
                Self.append(line, offset: offset, projector: projector,
                            to: &built.grid)
            }
            Self.append(WorldGeometry.equator, offset: offset,
                        projector: projector, to: &built.equator)

            for landmass in WorldGeometry.landmasses(for: level) {
                guard landmass.intersects(minX: view.minX, maxX: view.maxX,
                                          minY: view.minY, maxY: view.maxY,
                                          offset: offset) else { continue }
                Self.append(landmass.points, offset: offset,
                            projector: projector, to: &built.land, close: true)
            }
            for lake in WorldGeometry.lakes(for: level) {
                guard lake.intersects(minX: view.minX, maxX: view.maxX,
                                      minY: view.minY, maxY: view.maxY,
                                      offset: offset) else { continue }
                Self.append(lake.points, offset: offset,
                            projector: projector, to: &built.lakes, close: true)
            }
            for border in WorldGeometry.borders(for: level) {
                guard border.intersects(minX: view.minX, maxX: view.maxX,
                                        minY: view.minY, maxY: view.maxY,
                                        offset: offset) else { continue }
                Self.append(border.points, offset: offset,
                            projector: projector, to: &built.borders)
            }
        }
        built.landStrokeWidth = level == .local ? 0.5 : 0.7
        built.borderStyle = level == .world
            ? StrokeStyle(lineWidth: 0.5, dash: [2.5, 2.5])
            : StrokeStyle(lineWidth: level == .local ? 0.9 : 0.7)
        built.night = Self.nightPolygons(projector: projector, date: date)

        geography = built
        geographyKey = key
        geographyZoom = projector.zoom
        geographyCenter = projector.center
    }

    /// The day/night terminator, moved here verbatim from `MapFrame` so it is
    /// built on the cache's schedule (with every geography rebuild, and on
    /// its own when the game hour turns) instead of 30 times a second.
    /// Astronomy unchanged (docs/MAP_RUNTIME_BASELINE.md §4 · P3).
    private static func nightPolygons(projector: MapProjector,
                                      date: GameDate) -> [(Path, Double)] {
        // One source for where the sun is (`SolarGeometry`, in Core with
        // the rest of the map's testable geometry), shared with the city
        // lights that have to appear on this polygon's own dark side.
        let declination = SolarGeometry.declination(date)
        let subsolarLon = SolarGeometry.subsolarLongitude(date)

        var result: [(Path, Double)] = []
        for (inset, alpha) in [(0.0, 0.14), (6.0, 0.10)] {
            var night = Path()
            var first = true
            let poleY: CGFloat = declination >= 0 ? 1 : 0
            for step in 0...96 {
                let lon = -540.0 + Double(step) * (1080.0 / 96.0)
                var lat = atan(-cos((lon - subsolarLon) * .pi / 180)
                               / tan(declination == 0 ? 1e-6 : declination))
                lat -= inset * .pi / 180 * (declination >= 0 ? 1 : -1)
                let mapPoint = MapPoint(coordinate: Coordinate(
                    latitude: max(-89, min(89, lat * 180 / .pi)),
                    longitude: lon.truncatingRemainder(dividingBy: 360)))
                let x = (lon + 180) / 360
                let p = projector.project(MapPoint(x: x, y: mapPoint.y))
                if first { night.move(to: p); first = false }
                else { night.addLine(to: p) }
            }
            let poleScreenY = projector.project(MapPoint(x: 0, y: Double(poleY))).y
            night.addLine(to: CGPoint(x: night.currentPoint?.x ?? projector.size.width,
                                      y: poleScreenY))
            night.addLine(to: CGPoint(x: night.boundingRect.minX, y: poleScreenY))
            night.closeSubpath()
            result.append((night, alpha))
        }
        return result
    }

    private static func append(_ points: [MapPoint], offset: Double,
                               projector: MapProjector, to path: inout Path,
                               close: Bool = false) {
        var started = false
        for point in points {
            let projected = projector.project(MapPoint(x: point.x + offset,
                                                       y: point.y))
            if !started {
                path.move(to: projected)
                started = true
            } else {
                path.addLine(to: projected)
            }
        }
        if close, started { path.closeSubpath() }
    }

    // MARK: - Routes

    /// `revision` is `GameController.mapRevision`, not the tick's arrival
    /// time: it also moves when a command lands while the game is paused,
    /// which is when most routes are opened, assigned and closed.
    private struct RoutesKey: Equatable {
        let level: MapZoomLevel
        let offsets: [Double]
        let size: CGSize
        let overlay: MapOverlay
        let revision: UInt64
        let selectedRoute: RouteID?
    }

    struct CachedStroke {
        let path: Path
        let color: Color
        let width: CGFloat
        let dash: [CGFloat]
    }

    struct CachedRouteHit {
        let route: MapModel.MapRoute
        let points: [CGPoint]
    }

    private var routeStrokes: [CachedStroke] = []
    private var routeHits: [CachedRouteHit] = []
    private var routesKey: RoutesKey?
    private var routesZoom: CGFloat = 1
    private var routesCenter = CGPoint.zero
    private var routesBuilt = false

    /// Ensures the route cache is valid, draws it, and returns the hit
    /// polylines with the transform they are currently displayed under —
    /// which is what keeps hit-testing honest against a replayed frame
    /// (`MapHitGeometry` inverse-transforms the tap instead of the map
    /// re-projecting five thousand points).
    ///
    /// The currently selected route is *excluded* from the cache (its id is
    /// part of the key) so `MapFrame` can draw it per frame with its halo
    /// underneath — a selection change costs one rebuild, a tap-rate event.
    func drawRoutes(into context: inout GraphicsContext,
                    model: MapModel, projector: MapProjector,
                    policy: MapDetailPolicy, overlay: MapOverlay,
                    revision: UInt64, selectedRoute: RouteID?,
                    playerColor: Color,
                    style: (MapModel.MapRoute, Bool) -> MapFrame.RouteStyle,
                    shows: (MapModel.MapRoute) -> Bool)
        -> (hits: [CachedRouteHit], transform: CGAffineTransform) {
        let key = RoutesKey(level: policy.level,
                            offsets: projector.visibleWorldOffsets,
                            size: projector.size, overlay: overlay,
                            revision: revision, selectedRoute: selectedRoute)
        if !routesBuilt {
            countRebuild("routesFirst")
            buildRoutes(model: model, projector: projector, key: key,
                        style: style, shows: shows)
        } else if routesKey != key {
            countRebuild(routesReason(old: routesKey, new: key))
            buildRoutes(model: model, projector: projector, key: key,
                        style: style, shows: shows)
        } else if let drift = cameraDrifted(builtZoom: routesZoom,
                                            builtCenter: routesCenter,
                                            projector: projector) {
            countRebuild("routes\(drift.prefix(1).uppercased() + drift.dropFirst())")
            buildRoutes(model: model, projector: projector, key: key,
                        style: style, shows: shows)
        } else {
            replays += 1
        }

        let replay = replayTransform(builtZoom: routesZoom,
                                     builtCenter: routesCenter,
                                     projector: projector)
        var layer = context
        layer.translateBy(x: replay.transform.tx, y: replay.transform.ty)
        layer.scaleBy(x: replay.scale, y: replay.scale)
        let s = replay.scale
        for stroke in routeStrokes {
            layer.stroke(stroke.path, with: .color(stroke.color),
                         style: StrokeStyle(lineWidth: stroke.width / s,
                                            lineCap: .round, lineJoin: .round,
                                            dash: stroke.dash.map { $0 / s }))
        }
        return (routeHits, replay.transform)
    }

    private func routesReason(old: RoutesKey?, new: RoutesKey) -> String {
        guard let old else { return "routesFirst" }
        if old.revision != new.revision { return "revision" }
        if old.overlay != new.overlay { return "overlay" }
        if old.selectedRoute != new.selectedRoute { return "selection" }
        if old.level != new.level { return "routesLod" }
        if old.size != new.size { return "routesSize" }
        if old.offsets != new.offsets { return "routesOffsets" }
        return "routesKey"
    }

    private func buildRoutes(model: MapModel, projector: MapProjector,
                             key: RoutesKey,
                             style: (MapModel.MapRoute, Bool) -> MapFrame.RouteStyle,
                             shows: (MapModel.MapRoute) -> Bool) {
        routeStrokes = []
        routeHits = []
        let cullMargin = 120 + panHeadroom * projector.size.width

        // Rivals first, players second — the z-order the un-cached draw kept.
        let ordered = model.routes.filter { !$0.isPlayer }
            + model.routes.filter(\.isPlayer)
        for route in ordered {
            guard route.id != key.selectedRoute, shows(route) else { continue }
            let unwrapped = MapGeodesy.unwrap(route.arc)
            guard !unwrapped.isEmpty else { continue }
            let routeStyle = style(route, route.isPlayer)

            // Every copy of the world on screen, not only the first: the
            // geography draws each visible copy, and a network that exists
            // on one of them reads as missing on the others.
            for offset in MapGeodesy.copies(of: unwrapped, visible: key.offsets) {
                let points = unwrapped.map {
                    projector.project(MapPoint(x: $0.x + offset, y: $0.y))
                }
                guard points.contains(where: {
                    projector.isVisible($0, margin: cullMargin)
                }) else { continue }

                var path = Path()
                for (index, point) in points.enumerated() {
                    if index == 0 { path.move(to: point) }
                    else { path.addLine(to: point) }
                }
                if route.isPlayer, route.health != .grounded {
                    routeStrokes.append(CachedStroke(
                        path: path, color: routeStyle.color.opacity(0.16),
                        width: routeStyle.width + 5, dash: []))
                }
                routeStrokes.append(CachedStroke(
                    path: path,
                    color: routeStyle.color.opacity(routeStyle.opacity),
                    width: routeStyle.width, dash: routeStyle.dash))
                // One hit polyline per drawn copy: whichever copy the
                // player taps is the route.
                routeHits.append(CachedRouteHit(route: route, points: points))
            }
        }
        routesKey = key
        routesZoom = projector.zoom
        routesCenter = projector.center
        routesBuilt = true
    }

    // MARK: - Label memory (P0-2)

    /// When placement last ran, and under what conditions. Placement is a
    /// *decision*, and the baseline measured what deciding per frame did:
    /// 3.92 identity changes and 1.72 position hops per frame while panning
    /// (docs/MAP_RUNTIME_BASELINE.md §5). So the decision runs only when
    /// something decision-worthy changes — a gesture settles, the LOD tier
    /// or selection or simulation revision changes, or the camera drifts
    /// past the same bands the geometry cache uses — and every frame in
    /// between simply re-projects the remembered choices, which move exactly
    /// with the world.
    private struct PlacementKey: Equatable {
        let level: MapZoomLevel
        let size: CGSize
        let offsets: [Double]
        let revision: UInt64
        let selection: AirportCode?
        let settle: Int
    }

    private var placementKey: PlacementKey?
    private var placementZoom: CGFloat = 1
    private var placementCenter = CGPoint.zero
    private var airportMemory: [MapLabelLayout.Remembered] = []
    /// Country label memory: map-space anchor, caption, and the box's
    /// width — everything needed to redraw without re-deciding.
    private var countryMemory: [(anchor: CGPoint, text: String, width: CGFloat)] = []
    private(set) var placementRuns = 0

    /// Label widths, measured once per string (`MapTextMetrics`). Kept here
    /// because this is the object that outlives a frame.
    let textMetrics = MapTextMetrics()

    /// Airport labels for this frame: re-projected memory while the
    /// placement key holds, a fresh (memory-seeded) placement when it does
    /// not. `placedNow` tells the country pass whether to re-decide too.
    ///
    /// `airports` is one copy per airport — `MapFrame` passes the copy
    /// nearest the middle of the canvas — and the replay below re-projects
    /// each remembered label onto that same copy.
    func airportLabels(airports: [(MapModel.MapAirport, CGPoint)],
                       byCode: [AirportCode: MapModel.MapAirport],
                       projector: MapProjector, policy: MapDetailPolicy,
                       selected: AirportCode?, revision: UInt64, settle: Int,
                       limit: Int, labelBounds: CGRect,
                       markerRadius: (MapModel.MapAirport) -> CGFloat,
                       textWidth: (String) -> CGFloat)
        -> (labels: [MapLabel], placedNow: Bool) {
        let offsets = projector.visibleWorldOffsets
        let key = PlacementKey(level: policy.level, size: projector.size,
                               offsets: offsets,
                               revision: revision, selection: selected,
                               settle: settle)
        if placementKey == key,
           cameraDrifted(builtZoom: placementZoom,
                         builtCenter: placementCenter,
                         projector: projector) == nil {
            var out: [MapLabel] = []
            out.reserveCapacity(airportMemory.count)
            // Full containment, not the placer's ±12pt keep margin: run 94
            // re-photographed "Langnes (Tron" torn at the edge because a
            // 12pt overhang still draws 12pt of shredded text. Between
            // placements labels ride the camera by re-projection (run 85's
            // KEY-82 first showed the tear, EXP-03); a box that no longer
            // fits entirely on the legible canvas skips this frame — the
            // memory itself survives, so the label returns the moment the
            // camera gives it room.
            let keep = labelBounds
            for memory in airportMemory {
                guard let airport = byCode[memory.code] else { continue }
                let anchor = projector.projectNearestCopy(airport.position,
                                                          among: offsets)
                let centre = CGPoint(x: anchor.x + memory.offset.width,
                                     y: anchor.y + memory.offset.height)
                // The box the placer measured, not a re-estimate of it.
                let box = CGRect(x: centre.x - memory.size.width / 2,
                                 y: centre.y - memory.size.height / 2,
                                 width: memory.size.width,
                                 height: memory.size.height)
                guard keep.contains(box) else { continue }
                out.append(MapLabel(
                    text: memory.text, point: centre,
                    priority: memory.priority, isPlayer: memory.isPlayer,
                    emphasis: memory.emphasis,
                    box: box,
                    code: memory.code, anchorOffset: memory.offset))
            }
            return (out, false)
        }

        placementRuns += 1
        let labels = MapLabelLayout.place(
            airports, level: policy.level, zoom: policy.zoom,
            selected: selected, limit: limit,
            bounds: labelBounds,
            markerRadius: markerRadius, textWidth: textWidth,
            remembered: airportMemory)
        let fullNames = policy.zoom >= MapLabelLayout.fullNameZoom
        airportMemory = labels.compactMap { label in
            guard let code = label.code else { return nil }
            return MapLabelLayout.Remembered(
                code: code, text: label.text, offset: label.anchorOffset,
                priority: label.priority, isPlayer: label.isPlayer,
                emphasis: label.emphasis, size: label.box.size,
                level: policy.level, fullNames: fullNames)
        }
        placementKey = key
        placementZoom = projector.zoom
        placementCenter = projector.center
        return (labels, true)
    }

    /// Country labels: decided alongside the airports (against their boxes),
    /// frozen with them between placements. Anchors are stored in map space
    /// via `unproject`, so re-projection moves them exactly with the world.
    func countryLabels(projector: MapProjector, policy: MapDetailPolicy,
                       blocked: [CGRect], placedNow: Bool,
                       labelBounds: CGRect,
                       textWidth: (String) -> CGFloat) -> [MapLabel] {
        if !placedNow {
            // Same edge rule as the airports: full containment, or the
            // label sits this frame out rather than drawing torn.
            let keep = labelBounds
            return countryMemory.compactMap { memory in
                let point = projector.project(MapPoint(x: Double(memory.anchor.x),
                                                       y: Double(memory.anchor.y)))
                let box = CGRect(x: point.x - memory.width / 2, y: point.y - 8,
                                 width: memory.width, height: 16)
                guard keep.contains(box) else { return nil }
                return MapLabel(
                    text: memory.text, point: point, priority: 0,
                    isPlayer: false, emphasis: false,
                    box: box)
            }
        }
        let candidates = CountryLabels.visible(atZoom: policy.zoom)
        var projected: [(CountryLabel, CGPoint)] = []
        for offset in projector.visibleWorldOffsets {
            for country in candidates {
                let point = projector.project(
                    MapPoint(x: country.point.x + offset, y: country.point.y))
                guard projector.isVisible(point, margin: 60) else { continue }
                projected.append((country, point))
            }
        }
        let labels = MapLabelLayout.placeCountries(
            projected, blocked: blocked,
            limit: policy.level == .world ? 10 : 18,
            bounds: labelBounds, textWidth: textWidth)
        countryMemory = labels.map {
            (anchor: projector.unproject($0.point), text: $0.text,
             width: $0.box.width)
        }
        return labels
    }

    // MARK: - Airport index

    private var indexedAirports: [AirportCode: MapModel.MapAirport] = [:]
    private var indexedRevision: UInt64?

    /// The model's airports by code, rebuilt when the simulation revision
    /// moves rather than per frame. Frames read positions from it (which
    /// never change) and the label replay reads the same, so an index one
    /// publish old is still exact.
    func airportIndex(for model: MapModel,
                      revision: UInt64) -> [AirportCode: MapModel.MapAirport] {
        if indexedRevision != revision {
            indexedAirports = Dictionary(
                model.airports.map { ($0.code, $0) },
                uniquingKeysWith: { first, _ in first })
            indexedRevision = revision
        }
        return indexedAirports
    }

    // MARK: - Flight trail arcs

    /// The full great-circle sample set for a flight's route, cached per
    /// simulation revision. The trail draw used to slerp 21 points per
    /// player flight per frame; the arc itself only changes when the flight
    /// does, so it is computed once per (flight, revision) and the per-frame
    /// work drops to one slerp for the moving tip. Cleared wholesale when
    /// the revision moves — at most one entry per live player flight, so
    /// memory is bounded by the fleet.
    private var trailArcs: [FlightID: [MapPoint]] = [:]
    private var trailRevision: UInt64?

    func trailArc(for flight: FlightID, revision: UInt64,
                  compute: () -> [MapPoint]) -> [MapPoint] {
        if trailRevision != revision {
            trailArcs.removeAll(keepingCapacity: true)
            trailRevision = revision
        }
        if let cached = trailArcs[flight] { return cached }
        let arc = compute()
        trailArcs[flight] = arc
        return arc
    }

    private func compensated(_ style: StrokeStyle, by s: CGFloat) -> StrokeStyle {
        var out = style
        out.lineWidth /= s
        out.dash = style.dash.map { $0 / s }
        return out
    }
}
