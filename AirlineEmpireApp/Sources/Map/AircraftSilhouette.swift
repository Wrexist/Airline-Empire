import SwiftUI
import AirlineEmpireCore

/// Aircraft as drawable shapes (docs/MAP_ARCHITECTURE.md §6).
///
/// Every aircraft in the game was the same SF Symbol at 10–13pt, so a
/// turboprop and a widebody were the same object and the map could not say
/// what was flying. These are original silhouettes — four planforms, drawn
/// programmatically rather than shipped as art, for three reasons:
///
/// - **They scale.** A vector traced at unit size is exact at 8pt and at 40pt,
///   which matters because the map draws the same aircraft at both.
/// - **They are recolourable.** Every aircraft carries its operator's livery;
///   a bitmap would need one asset per colour.
/// - **They are ours.** No real manufacturer's planform, no airline's
///   branding, nothing traced from a photograph.
///
/// The shapes are deliberately generic aviation forms — a high-wing twin, a
/// T-tail regional jet, a swept narrowbody, a twin-aisle widebody. They read
/// as *classes* of aircraft, which is the information the map is carrying,
/// rather than as any particular type.
///
/// ## Coordinate space
///
/// Each path is drawn in a unit box, nose at `(0.5, 0)`, tail at `(0.5, 1)`,
/// centred on `(0.5, 0.5)` so the renderer can rotate about the centre and
/// scale by one number. Y increases toward the tail, which matches the
/// screen-space convention the projector uses.
enum AircraftSilhouette {

    /// The four planforms the map distinguishes. `AircraftCategory` has six
    /// cases; two pairs share a silhouette because at map scale a narrowbody
    /// and a large narrowbody are the same shape, and drawing them apart would
    /// be a difference the player cannot see.
    enum Planform: String, CaseIterable {
        case turboprop
        case regionalJet
        case narrowbody
        case widebody

        /// Spelled out rather than written with leading dots: a `switch`
        /// *expression* whose branches are implicit members needs a contextual
        /// type to resolve them, and this toolchain has already refused that
        /// once in this project (`MapModel.tier`, same shape, same session).
        static func of(_ category: AircraftCategory) -> Planform {
            switch category {
            case .turboprop: Planform.turboprop
            case .regionalJet: Planform.regionalJet
            case .narrowbody, .largeNarrowbody: Planform.narrowbody
            case .widebody, .largeWidebody: Planform.widebody
            }
        }

        /// Relative on-screen size. A widebody should read as a bigger object
        /// than a turboprop at the same zoom — that is most of the
        /// information these shapes carry.
        var scale: CGFloat {
            switch self {
            case .turboprop: 0.82
            case .regionalJet: 0.9
            case .narrowbody: 1.0
            case .widebody: 1.22
            }
        }
    }

    /// The silhouette for a category, in a unit box.
    static func path(for category: AircraftCategory) -> Path {
        path(for: Planform.of(category))
    }

    static func path(for planform: Planform) -> Path {
        switch planform {
        case .turboprop: turboprop
        case .regionalJet: regionalJet
        case .narrowbody: narrowbody
        case .widebody: widebody
        }
    }

    /// A simplified mark for the smallest zooms, where a planform is a smudge.
    /// A directional wedge still says *which way it is going*, which is the
    /// one thing that survives at four points across.
    static var wedge: Path {
        var path = Path()
        path.move(to: CGPoint(x: 0.5, y: 0.0))
        path.addLine(to: CGPoint(x: 0.92, y: 0.9))
        path.addLine(to: CGPoint(x: 0.5, y: 0.68))
        path.addLine(to: CGPoint(x: 0.08, y: 0.9))
        path.closeSubpath()
        return path
    }

    // MARK: - Planforms

    /// High straight wing, deep nose, broad tailplane: the shape of a
    /// short-field turboprop seen from above.
    private static var turboprop: Path {
        var path = Path()
        path.move(to: CGPoint(x: 0.50, y: 0.00))
        path.addQuadCurve(to: CGPoint(x: 0.57, y: 0.20),
                          control: CGPoint(x: 0.57, y: 0.07))
        // Straight, high-aspect wing
        path.addLine(to: CGPoint(x: 0.58, y: 0.34))
        path.addLine(to: CGPoint(x: 1.00, y: 0.40))
        path.addLine(to: CGPoint(x: 1.00, y: 0.47))
        path.addLine(to: CGPoint(x: 0.57, y: 0.48))
        path.addLine(to: CGPoint(x: 0.56, y: 0.80))
        // Tailplane
        path.addLine(to: CGPoint(x: 0.76, y: 0.90))
        path.addLine(to: CGPoint(x: 0.76, y: 0.96))
        path.addLine(to: CGPoint(x: 0.50, y: 1.00))
        path.addLine(to: CGPoint(x: 0.24, y: 0.96))
        path.addLine(to: CGPoint(x: 0.24, y: 0.90))
        path.addLine(to: CGPoint(x: 0.44, y: 0.80))
        path.addLine(to: CGPoint(x: 0.43, y: 0.48))
        path.addLine(to: CGPoint(x: 0.00, y: 0.47))
        path.addLine(to: CGPoint(x: 0.00, y: 0.40))
        path.addLine(to: CGPoint(x: 0.42, y: 0.34))
        path.addLine(to: CGPoint(x: 0.43, y: 0.20))
        path.addQuadCurve(to: CGPoint(x: 0.50, y: 0.00),
                          control: CGPoint(x: 0.43, y: 0.07))
        path.closeSubpath()
        return path
    }

    /// Slim fuselage, modest sweep, tall T-tail — a regional jet.
    private static var regionalJet: Path {
        var path = Path()
        path.move(to: CGPoint(x: 0.50, y: 0.00))
        path.addQuadCurve(to: CGPoint(x: 0.56, y: 0.22),
                          control: CGPoint(x: 0.56, y: 0.08))
        path.addLine(to: CGPoint(x: 0.57, y: 0.40))
        path.addLine(to: CGPoint(x: 0.97, y: 0.60))
        path.addLine(to: CGPoint(x: 0.97, y: 0.66))
        path.addLine(to: CGPoint(x: 0.57, y: 0.58))
        path.addLine(to: CGPoint(x: 0.56, y: 0.82))
        path.addLine(to: CGPoint(x: 0.72, y: 0.92))
        path.addLine(to: CGPoint(x: 0.72, y: 0.97))
        path.addLine(to: CGPoint(x: 0.50, y: 1.00))
        path.addLine(to: CGPoint(x: 0.28, y: 0.97))
        path.addLine(to: CGPoint(x: 0.28, y: 0.92))
        path.addLine(to: CGPoint(x: 0.44, y: 0.82))
        path.addLine(to: CGPoint(x: 0.43, y: 0.58))
        path.addLine(to: CGPoint(x: 0.03, y: 0.66))
        path.addLine(to: CGPoint(x: 0.03, y: 0.60))
        path.addLine(to: CGPoint(x: 0.43, y: 0.40))
        path.addLine(to: CGPoint(x: 0.44, y: 0.22))
        path.addQuadCurve(to: CGPoint(x: 0.50, y: 0.00),
                          control: CGPoint(x: 0.44, y: 0.08))
        path.closeSubpath()
        return path
    }

    /// The familiar single-aisle: pronounced sweep, wing at mid-body.
    private static var narrowbody: Path {
        var path = Path()
        path.move(to: CGPoint(x: 0.50, y: 0.00))
        path.addQuadCurve(to: CGPoint(x: 0.57, y: 0.20),
                          control: CGPoint(x: 0.57, y: 0.06))
        path.addLine(to: CGPoint(x: 0.58, y: 0.38))
        path.addLine(to: CGPoint(x: 1.00, y: 0.64))
        path.addLine(to: CGPoint(x: 1.00, y: 0.71))
        path.addLine(to: CGPoint(x: 0.58, y: 0.60))
        path.addLine(to: CGPoint(x: 0.57, y: 0.83))
        path.addLine(to: CGPoint(x: 0.76, y: 0.94))
        path.addLine(to: CGPoint(x: 0.76, y: 0.99))
        path.addLine(to: CGPoint(x: 0.50, y: 1.00))
        path.addLine(to: CGPoint(x: 0.24, y: 0.99))
        path.addLine(to: CGPoint(x: 0.24, y: 0.94))
        path.addLine(to: CGPoint(x: 0.43, y: 0.83))
        path.addLine(to: CGPoint(x: 0.42, y: 0.60))
        path.addLine(to: CGPoint(x: 0.00, y: 0.71))
        path.addLine(to: CGPoint(x: 0.00, y: 0.64))
        path.addLine(to: CGPoint(x: 0.42, y: 0.38))
        path.addLine(to: CGPoint(x: 0.43, y: 0.20))
        path.addQuadCurve(to: CGPoint(x: 0.50, y: 0.00),
                          control: CGPoint(x: 0.43, y: 0.06))
        path.closeSubpath()
        return path
    }

    /// Twin-aisle: a wide body, long span, and four visible engine pylons —
    /// the notch pattern is what makes it read as "big" at small sizes.
    private static var widebody: Path {
        var path = Path()
        path.move(to: CGPoint(x: 0.50, y: 0.00))
        path.addQuadCurve(to: CGPoint(x: 0.60, y: 0.18),
                          control: CGPoint(x: 0.60, y: 0.05))
        path.addLine(to: CGPoint(x: 0.61, y: 0.36))
        // Outboard pylon
        path.addLine(to: CGPoint(x: 0.80, y: 0.50))
        path.addLine(to: CGPoint(x: 0.82, y: 0.58))
        path.addLine(to: CGPoint(x: 0.86, y: 0.55))
        path.addLine(to: CGPoint(x: 1.00, y: 0.66))
        path.addLine(to: CGPoint(x: 1.00, y: 0.73))
        path.addLine(to: CGPoint(x: 0.61, y: 0.62))
        path.addLine(to: CGPoint(x: 0.60, y: 0.84))
        path.addLine(to: CGPoint(x: 0.79, y: 0.95))
        path.addLine(to: CGPoint(x: 0.79, y: 1.00))
        path.addLine(to: CGPoint(x: 0.50, y: 0.98))
        path.addLine(to: CGPoint(x: 0.21, y: 1.00))
        path.addLine(to: CGPoint(x: 0.21, y: 0.95))
        path.addLine(to: CGPoint(x: 0.40, y: 0.84))
        path.addLine(to: CGPoint(x: 0.39, y: 0.62))
        path.addLine(to: CGPoint(x: 0.00, y: 0.73))
        path.addLine(to: CGPoint(x: 0.00, y: 0.66))
        path.addLine(to: CGPoint(x: 0.14, y: 0.55))
        path.addLine(to: CGPoint(x: 0.18, y: 0.58))
        path.addLine(to: CGPoint(x: 0.20, y: 0.50))
        path.addLine(to: CGPoint(x: 0.39, y: 0.36))
        path.addLine(to: CGPoint(x: 0.40, y: 0.18))
        path.addQuadCurve(to: CGPoint(x: 0.50, y: 0.00),
                          control: CGPoint(x: 0.40, y: 0.05))
        path.closeSubpath()
        return path
    }

    // MARK: - Placement

    /// A silhouette placed on the map: scaled to `size`, rotated to `heading`
    /// (degrees clockwise from north), centred on `point`.
    ///
    /// The unit path points *up the screen* at heading 0, which is north, so
    /// the rotation is the heading directly with no offset to remember.
    static func placed(_ category: AircraftCategory, at point: CGPoint,
                       heading: Double, size: CGFloat,
                       simplified: Bool) -> Path {
        let planform = Planform.of(category)
        let box = size * (simplified ? 1.0 : planform.scale)
        let base = simplified ? wedge : path(for: planform)
        let transform = CGAffineTransform.identity
            .translatedBy(x: point.x, y: point.y)
            .rotated(by: heading * .pi / 180)
            .translatedBy(x: -box / 2, y: -box / 2)
            .scaledBy(x: box, y: box)
        return base.applying(transform)
    }
}

/// A SwiftUI `Shape` wrapper, so a silhouette can also be used outside the
/// map — a fleet row, a detail header — from the same single definition.
struct AircraftShape: Shape {
    let category: AircraftCategory

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let transform = CGAffineTransform.identity
            .translatedBy(x: rect.midX - side / 2, y: rect.midY - side / 2)
            .scaledBy(x: side, y: side)
        return AircraftSilhouette.path(for: category).applying(transform)
    }
}
