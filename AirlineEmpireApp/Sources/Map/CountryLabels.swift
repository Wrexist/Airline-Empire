import CoreGraphics
import Foundation
import AirlineEmpireCore

/// A country label: its name, its flag, and where the label belongs.
struct CountryLabel {
    let name: String
    /// The ISO 3166-1 alpha-2 code rendered as a flag, e.g. 🇸🇪.
    let flag: String
    let point: MapPoint
    /// The zoom at or beyond which this label is worth drawing.
    let minZoom: CGFloat

    /// Flag and name, in that order, as one string to draw and measure.
    var display: String { "\(flag) \(name)" }
}

enum CountryLabels {

    /// Parsed once. 175 rows is not worth re-splitting per frame at 30fps.
    static let all: [CountryLabel] = parse(CountryLabelData.all)

    /// The countries worth labelling at this zoom.
    ///
    /// Culled by zoom before projection, because projecting 175 points and
    /// then discarding 150 of them is work done 30 times a second for nothing.
    /// The remaining off-screen ones are culled by the frame, which is the
    /// only place that knows where the camera is.
    static func visible(atZoom zoom: CGFloat) -> [CountryLabel] {
        all.filter { zoom >= $0.minZoom }
    }

    /// A two-letter country code as its flag.
    ///
    /// Regional indicator symbols: `A`–`Z` map to U+1F1E6–U+1F1FF, and a pair
    /// of them is a flag. So the flags are Unicode, not artwork — nothing is
    /// bundled, nothing is licensed, and every one renders in the system font
    /// (docs/ASSET_INVENTORY.md's rule about shipping no third-party imagery).
    static func flag(for isoCode: String) -> String {
        let base: UInt32 = 0x1F1E6
        var scalars = String.UnicodeScalarView()
        for scalar in isoCode.uppercased().unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90,
                  let indicator = Unicode.Scalar(base + scalar.value - 65) else {
                return ""
            }
            scalars.append(indicator)
        }
        return String(scalars)
    }

    private static func parse(_ data: String) -> [CountryLabel] {
        data.split(separator: "\n").compactMap { row in
            let fields = row.split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count == 5,
                  let longitude = Double(fields[2]),
                  let latitude = Double(fields[3]),
                  let minLabel = Double(fields[4]) else { return nil }
            let flag = flag(for: String(fields[1]))
            guard !flag.isEmpty else { return nil }
            return CountryLabel(
                name: String(fields[0]),
                flag: flag,
                point: MapPoint(coordinate: Coordinate(latitude: latitude,
                                                       longitude: longitude)),
                // Natural Earth's MIN_LABEL is a scale rank, and this map's
                // zoom is "how many viewport widths the world spans". They are
                // not the same quantity, but they run the same way and over a
                // usefully similar range (1.7–6 against 1–16), so the rank is
                // used directly rather than fitted. The consequence is worth
                // stating: Russia and Brazil appear at the default 2.2, and
                // Luxembourg needs a deliberate zoom. That is the behaviour
                // wanted, arrived at cheaply.
                minZoom: CGFloat(minLabel))
        }
    }
}
