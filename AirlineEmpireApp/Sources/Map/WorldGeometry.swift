import Foundation
import AirlineEmpireCore

/// The world the network is drawn on (docs/MAP_ARCHITECTURE.md §3).
///
/// ## Where this geography comes from
///
/// **Natural Earth, public domain**, at three scales, chosen by zoom.
///
/// It replaces a hand trace, and that trace's own comment explained why it
/// existed: *"the environment has no network access to fetch Natural Earth,
/// and a coarse hand trace that ships beats an accurate one that does not."*
/// The right call under that constraint. The constraint expired, so the
/// decision was re-made rather than inherited.
///
/// | zoom | source | polygons | points |
/// | --- | --- | --- | --- |
/// | *(was)* | hand-traced | 16 | 631 |
/// | world | 1:110m | 103 | 2,384 |
/// | regional | 1:50m | 314 | 6,950 |
/// | local | 1:10m | 1,084 | 28,937 |
///
/// ## Why three scales and not one good one
///
/// Detail that helps at one zoom hurts at another, and both directions are
/// real. Twenty-nine thousand points at world zoom is a grey fringe along
/// every coast that competes with the routes the map exists to show —
/// `docs/MAP_ARCHITECTURE.md` §2 is explicit that geography must never do
/// that. Two thousand points at local zoom is a polygon, not a coastline.
///
/// Picking by `MapZoomLevel` costs one switch and gets both: the world view
/// stays clean, and zooming in resolves genuine coastline rather than
/// magnifying the same corners. It is also cheaper — the expensive tier is
/// only ever parsed if the player actually zooms to it, because a `static let`
/// is lazy.
///
/// ## Why the airports made this worth doing
///
/// Not prettiness. The eighty airports sit at real coordinates — Arlanda,
/// Heathrow, Charles de Gaulle, JFK, Haneda — and were being plotted onto a
/// coastline where Europe was a few dozen points. Precise data on imprecise
/// geography puts airports in the sea.
///
/// ## What is deliberately left out
///
/// - **Antarctica.** The hand trace omitted it and so does this: no airline in
///   the game flies there, it is a 2,805-point polygon spanning every
///   longitude, and the projection already clips at ±80°.
/// - **Islands below the per-tier span threshold**, which are sub-pixel at
///   their own zoom and would be a thousand polygons of noise.
/// - **Rivers.** They are line work in the same weight as routes, on a map
///   whose subject is routes.
///
/// One landmass legitimately spans 197° of longitude — Afro-Eurasia, West
/// Africa to the Bering Strait — exactly as the hand-traced `africaEurasia`
/// did. Verified as real geography rather than an antimeridian wrap; the
/// renderer's existing `visibleWorldOffsets` handling covers it.
///
/// Presentation only. Nothing here reaches the simulation; airport positions
/// come from `airports.json` through `MapModel`, never from this file.
///
/// *Made with Natural Earth.*
enum WorldGeometry {

    /// Coastlines at the detail the current zoom can actually show.
    static func landmasses(for level: MapZoomLevel) -> [[MapPoint]] {
        switch level {
        case .world: coarseLand
        case .regional: mediumLand
        case .local: fineLand
        }
    }

    /// Inland water, drawn in the ocean's own colour over the land it sits in.
    /// A lake is the same substance as the sea; giving it a third value would
    /// widen a palette deliberately kept narrow.
    static func lakes(for level: MapZoomLevel) -> [[MapPoint]] {
        level == .local ? fineLakes : mediumLakes
    }

    /// Land borders, and only from regional zoom in.
    ///
    /// At world zoom they are the difference between a map and a diagram, and
    /// also the difference between a clean field and a mesh — 2,589 points of
    /// hairline over a silhouette, under the routes that matter. Empty at
    /// world zoom is a decision, not an omission.
    /// Political borders, at every level.
    ///
    /// They used to be withheld at world zoom, on the reasoning that a border
    /// is line work in the same weight as a route and world zoom is where
    /// routes are longest. True of the weight, wrong about the need: world
    /// zoom is precisely where a player cannot tell one country from another,
    /// and a coastline alone does not say where France stops and Spain starts.
    /// `MapFrame` dashes them there instead, which separates them from routes
    /// by pattern rather than by absence.
    static func borders(for level: MapZoomLevel) -> [[MapPoint]] {
        borderLines
    }

    private static let coarseLand = points(WorldGeometryData.coarseLand)
    private static let mediumLand = points(WorldGeometryData.mediumLand)
    private static let fineLand = points(WorldGeometryData.fineLand)
    private static let mediumLakes = points(WorldGeometryData.mediumLakes)
    private static let fineLakes = points(WorldGeometryData.fineLakes)
    private static let borderLines = points(WorldGeometryData.borders)

    /// One polygon or line per row; `lat,lon` pairs separated by spaces.
    private static func points(_ data: String) -> [[MapPoint]] {
        data.split(separator: "\n").map { row in
            row.split(separator: " ").compactMap { pair -> MapPoint? in
                let parts = pair.split(separator: ",")
                guard parts.count == 2,
                      let latitude = Double(parts[0]),
                      let longitude = Double(parts[1]) else { return nil }
                return MapPoint(coordinate: Coordinate(latitude: latitude,
                                                       longitude: longitude))
            }
        }
    }

    /// Meridians and parallels, as pre-projected line segments.
    ///
    /// A graticule is what makes a dark field read as a *map* rather than a
    /// background, and it gives the eye something to measure a route against.
    /// Every 30° — dense enough to structure the plane, sparse enough to stay
    /// out of the way.
    static let graticule: [[MapPoint]] = {
        var lines: [[MapPoint]] = []
        for longitude in stride(from: -180.0, through: 180.0, by: 30) {
            lines.append(stride(from: -80.0, through: 80.0, by: 10).map {
                MapPoint(coordinate: Coordinate(latitude: $0, longitude: longitude))
            })
        }
        for latitude in stride(from: -60.0, through: 80.0, by: 30) {
            lines.append(stride(from: -180.0, through: 180.0, by: 10).map {
                MapPoint(coordinate: Coordinate(latitude: latitude, longitude: $0))
            })
        }
        return lines
    }()

    /// The equator, drawn a shade stronger than the rest of the grid.
    static let equator: [MapPoint] = stride(from: -180.0, through: 180.0, by: 10)
        .map { MapPoint(coordinate: Coordinate(latitude: 0, longitude: $0)) }

    // MARK: - Coastlines, (latitude, longitude)

}
