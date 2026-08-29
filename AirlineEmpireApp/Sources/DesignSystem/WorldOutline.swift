import Foundation
import AirlineEmpireCore

/// The world under the network.
///
/// `AETheme.mapLand` was declared in the design tokens and never referenced by
/// anything, so the map — the screen `docs/GAME_DESIGN.md` calls "the primary
/// lens" and "the emotional centerpiece" — was dots and arcs on a flat navy
/// rectangle. You could not tell the Atlantic from the Pacific, and a route
/// across either looked the same.
///
/// These are deliberately coarse coastlines: a few dozen points per landmass,
/// hand-listed in degrees, filled as flat shapes. That is all a strategy map
/// needs — enough silhouette to recognise where you are flying, and cheap
/// enough to redraw inside a `Canvas` at map cadence. It is presentation, so
/// it lives in the app rather than in Core, and it is geography rather than
/// politics: no borders, no names, nothing that dates.
enum WorldOutline {
    /// Coastlines in map space, ready to project.
    static let landmasses: [[MapPoint]] = outlines.map { outline in
        outline.map { MapPoint(coordinate: Coordinate(latitude: $0.0, longitude: $0.1)) }
    }

    /// (latitude, longitude) pairs, clockwise, closed implicitly.
    private static let outlines: [[(Double, Double)]] = [
        africaAndEurasia, northAmerica, southAmerica, australia, greenland,
        madagascar, britishIsles, japan, newZealand, iceland, sriLanka,
        philippines, borneo, sumatra, newGuinea,
    ]

    // Africa, Europe and Asia are one continuous landmass; drawing them as one
    // polygon avoids seams at Suez and the Urals that no map should show.
    private static let africaAndEurasia: [(Double, Double)] = [
        (35.9, -5.9), (37.0, -9.5), (43.5, -9.2), (48.5, -4.8), (50.9, 1.5),
        (58.0, 5.5), (62.5, 5.0), (68.0, 15.0), (71.1, 25.8), (69.7, 33.0),
        (68.9, 44.0), (73.5, 55.0), (76.0, 68.0), (73.5, 80.0), (75.5, 95.0),
        (73.5, 113.0), (71.5, 129.0), (72.5, 140.0), (69.5, 161.0), (66.0, 170.0),
        (62.0, 179.0), (60.0, 170.0), (59.0, 163.0), (54.0, 156.0), (51.0, 157.0),
        (45.0, 142.0), (43.0, 132.0), (39.0, 127.0), (35.5, 129.5), (34.5, 126.0),
        (39.0, 122.0), (37.5, 119.0), (32.0, 121.5), (27.0, 120.5), (22.5, 114.0),
        (20.5, 107.0), (10.5, 107.0), (8.5, 100.0), (13.0, 100.5), (16.0, 96.5),
        (21.5, 92.0), (19.5, 85.5), (13.0, 80.3), (8.1, 77.5), (15.0, 73.8),
        (22.5, 69.0), (25.0, 62.0), (25.5, 57.0), (29.0, 48.5), (20.0, 39.0),
        (12.7, 43.4), (11.0, 51.0), (2.0, 45.5), (-4.0, 39.5), (-16.0, 40.0),
        (-25.5, 33.0), (-34.0, 25.5), (-34.4, 18.5), (-28.0, 16.0), (-17.0, 11.7),
        (-5.9, 12.0), (0.5, 9.3), (4.5, 8.5), (6.4, 3.4), (4.8, -2.0),
        (7.5, -13.5), (14.7, -17.4), (20.8, -17.0), (27.7, -13.2), (33.7, -7.4),
    ]

    private static let northAmerica: [(Double, Double)] = [
        (71.4, -156.8), (70.2, -143.0), (69.5, -130.0), (68.5, -113.0),
        (67.0, -95.0), (63.0, -90.5), (58.5, -94.0), (55.5, -87.0),
        (51.5, -80.0), (55.0, -77.5), (58.5, -70.0), (60.5, -64.5),
        (55.0, -60.0), (50.0, -66.0), (45.5, -61.0), (44.5, -66.5),
        (40.7, -74.0), (35.0, -75.5), (30.0, -81.5), (25.5, -80.2),
        (29.0, -83.0), (29.5, -94.8), (25.9, -97.2), (21.0, -97.0),
        (18.5, -94.5), (21.4, -87.0), (16.0, -88.5), (12.0, -83.5),
        (9.0, -79.5), (8.0, -77.5), (13.5, -87.5), (16.0, -96.0),
        (20.0, -105.5), (23.5, -110.0), (28.0, -114.0), (32.7, -117.2),
        (37.8, -122.5), (44.0, -124.0), (48.5, -124.8), (55.0, -132.0),
        (59.5, -139.5), (60.0, -148.0), (58.5, -155.0), (55.0, -162.0),
        (58.5, -161.0), (63.0, -165.5), (65.5, -168.0), (70.0, -161.0),
    ]

    private static let southAmerica: [(Double, Double)] = [
        (11.5, -72.0), (10.5, -64.0), (8.5, -60.0), (4.5, -51.5),
        (-1.0, -47.0), (-5.5, -35.5), (-13.0, -38.5), (-23.0, -43.2),
        (-27.5, -48.5), (-34.0, -53.5), (-38.5, -57.5), (-41.0, -62.5),
        (-46.5, -66.5), (-51.0, -68.5), (-54.9, -67.5), (-53.0, -72.0),
        (-46.0, -75.0), (-41.5, -73.5), (-36.5, -73.0), (-30.0, -71.5),
        (-23.5, -70.5), (-18.0, -70.5), (-12.0, -77.0), (-6.0, -81.0),
        (-2.0, -80.9), (2.0, -78.5), (6.5, -77.5), (9.5, -75.5),
    ]

    private static let australia: [(Double, Double)] = [
        (-10.7, 142.5), (-14.5, 145.5), (-19.5, 147.5), (-24.5, 153.0),
        (-31.5, 153.0), (-37.5, 150.0), (-38.8, 146.0), (-38.3, 141.0),
        (-35.0, 136.5), (-32.0, 134.0), (-33.5, 121.0), (-35.0, 117.0),
        (-31.5, 115.7), (-26.0, 113.5), (-21.0, 115.0), (-17.5, 122.0),
        (-14.0, 126.5), (-12.0, 130.8), (-14.5, 135.5), (-12.5, 136.8),
    ]

    private static let greenland: [(Double, Double)] = [
        (83.5, -35.0), (81.5, -18.0), (76.5, -19.0), (70.5, -22.0),
        (65.5, -37.0), (60.0, -43.5), (63.0, -50.5), (68.0, -53.0),
        (73.0, -56.5), (77.5, -66.0), (81.0, -62.0), (82.5, -45.0),
    ]

    private static let madagascar: [(Double, Double)] = [
        (-12.0, 49.3), (-15.5, 50.5), (-20.0, 48.7), (-25.5, 47.0),
        (-24.0, 43.7), (-18.0, 44.0), (-14.0, 47.5),
    ]

    private static let britishIsles: [(Double, Double)] = [
        (58.6, -3.0), (57.5, -2.0), (55.0, -1.5), (52.8, 1.7), (51.0, 1.4),
        (50.1, -5.2), (53.4, -4.8), (55.0, -5.0), (57.0, -6.5), (58.5, -5.0),
    ]

    private static let japan: [(Double, Double)] = [
        (45.5, 141.9), (43.3, 145.6), (41.5, 141.0), (38.3, 141.5),
        (35.7, 140.9), (34.6, 138.9), (33.5, 135.8), (34.4, 132.0),
        (33.9, 130.9), (31.5, 130.6), (33.0, 129.5), (35.5, 133.0),
        (37.9, 138.9), (41.4, 140.0), (43.5, 140.0), (45.3, 141.6),
    ]

    private static let newZealand: [(Double, Double)] = [
        (-34.4, 172.7), (-36.9, 175.5), (-39.3, 177.0), (-41.3, 174.8),
        (-46.5, 169.0), (-45.0, 167.0), (-42.0, 171.0), (-38.0, 174.5),
    ]

    private static let iceland: [(Double, Double)] = [
        (66.5, -18.0), (65.5, -14.0), (63.4, -18.5), (63.9, -22.7), (65.5, -24.5),
    ]

    private static let sriLanka: [(Double, Double)] = [
        (9.8, 80.2), (8.5, 81.3), (6.0, 81.8), (5.9, 80.0), (8.0, 79.7),
    ]

    private static let philippines: [(Double, Double)] = [
        (18.5, 121.5), (14.5, 123.0), (12.5, 125.5), (9.0, 126.5),
        (5.9, 125.4), (7.0, 122.0), (10.0, 122.5), (13.5, 120.5), (16.5, 119.8),
    ]

    private static let borneo: [(Double, Double)] = [
        (7.0, 117.0), (4.0, 119.0), (-1.0, 117.5), (-4.2, 114.5),
        (-2.5, 110.0), (1.5, 109.0), (4.5, 114.0),
    ]

    private static let sumatra: [(Double, Double)] = [
        (5.5, 95.3), (2.0, 100.0), (-3.0, 104.5), (-5.9, 105.8),
        (-5.0, 102.0), (-1.0, 98.0), (3.0, 96.0),
    ]

    private static let newGuinea: [(Double, Double)] = [
        (-0.5, 132.5), (-2.5, 138.0), (-4.0, 144.0), (-8.0, 147.5),
        (-10.5, 150.5), (-9.0, 143.0), (-8.5, 137.5), (-4.5, 134.0),
    ]
}
