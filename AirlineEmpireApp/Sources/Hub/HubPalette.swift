import UIKit
import SwiftUI
import AirlineEmpireCore

/// The hub's colours (docs/HUB_VIEW_3D.md §2): a periwinkle-graded clay
/// world. Every neutral leans blue-violet so shadows read lavender, which is
/// most of what makes the reference look the way it does.
struct HubPalette: Equatable {
    var concrete: UIColor
    var concreteLight: UIColor
    var asphalt: UIColor
    var asphaltDark: UIColor
    var building: UIColor
    var buildingShade: UIColor
    var roof: UIColor
    var glass: UIColor
    var glassOpacity: Float
    var grass: UIColor
    var grassBright: UIColor
    var tree: [UIColor]
    var trunk: UIColor
    var marking: UIColor
    var taxiLine: UIColor
    var houseRoof: UIColor
    var houseWood: UIColor
    var windowDark: UIColor
    var windowLit: UIColor
    var windowGlow: Float
    var water: UIColor
    var background: UIColor
    var skyTop: UIColor
    var skyHorizon: UIColor
    var blob: UIColor
    var lampGlow: Float
    var keyIntensity: Float
    var keyColor: UIColor
    var iblExponent: Float
    /// 0 by day, 1 at night; in between while the world crossfades. The
    /// materials scale every glow by it (`HubMaterials.make`).
    var dusk: Float = 0

    static let safety = UIColor(hub: 0xE8517A)
    static let pulse = UIColor(hub: 0x2F8BFF)
    static let queueGlow = UIColor(hub: 0x3FE0E8)
    static let pin = UIColor(hub: 0x2F6BFF)
    static let hiVis = UIColor(hub: 0xF5B83D)
    static let cone = UIColor(hub: 0xF2843A)
    static let tyre = UIColor(hub: 0x2B2F45)
    static let darkMetal = UIColor(hub: 0x3A3F5C)

    static let day = HubPalette(
        concrete: UIColor(hub: 0xA7AED6), concreteLight: UIColor(hub: 0xBAC2E3),
        asphalt: UIColor(hub: 0x6C779F), asphaltDark: UIColor(hub: 0x5A638C),
        building: UIColor(hub: 0xD6DCF1), buildingShade: UIColor(hub: 0xBFC7E8),
        roof: UIColor(hub: 0xCDD5F1), glass: UIColor(hub: 0x7DB6E4), glassOpacity: 0.55,
        grass: UIColor(hub: 0x6CC290), grassBright: UIColor(hub: 0x8AD6AB),
        tree: [UIColor(hub: 0x4DA16E), UIColor(hub: 0x5DB57C), UIColor(hub: 0x43925F)],
        trunk: UIColor(hub: 0x8A8FAE), marking: UIColor(hub: 0xF6F7FD), taxiLine: UIColor(hub: 0xF2C94C),
        houseRoof: UIColor(hub: 0x3D5A9C), houseWood: UIColor(hub: 0xB9805C),
        windowDark: UIColor(hub: 0x56648F), windowLit: UIColor(hub: 0xFFE2B0), windowGlow: 0,
        water: UIColor(hub: 0x6FC6EA), background: UIColor(hub: 0xC9D0EC),
        skyTop: UIColor(hub: 0xF4F6FF), skyHorizon: UIColor(hub: 0xC7CEF0),
        blob: UIColor(hub: 0x4A4F86), lampGlow: 0, keyIntensity: 1_900,
        keyColor: UIColor(hub: 0xFFF6EA), iblExponent: 0.7)

    /// The reference's night is a luminous blue-grey indigo, not black or
    /// saturated navy: ground `#5A5E8E`, roads `#4A4C78`, teal trees, warm
    /// windows `#FFD9A0` (docs/HUB_HANDOFF.md E1–E4). The fill comes up and
    /// the key goes low and blue, so the world stays readable.
    static let night = HubPalette(
        concrete: UIColor(hub: 0x5C6090), concreteLight: UIColor(hub: 0x686C9C),
        asphalt: UIColor(hub: 0x4A4C78), asphaltDark: UIColor(hub: 0x42446E),
        building: UIColor(hub: 0x9EA4CF), buildingShade: UIColor(hub: 0x878DBD),
        roof: UIColor(hub: 0x9096C6), glass: UIColor(hub: 0x5A8FCB), glassOpacity: 0.62,
        grass: UIColor(hub: 0x4A6B82), grassBright: UIColor(hub: 0x56797F),
        tree: [UIColor(hub: 0x3B7564), UIColor(hub: 0x448170), UIColor(hub: 0x366B5B)],
        trunk: UIColor(hub: 0x575B82), marking: UIColor(hub: 0xC8CCEA), taxiLine: UIColor(hub: 0xF2C94C),
        houseRoof: UIColor(hub: 0x3A4680), houseWood: UIColor(hub: 0x8A6650),
        windowDark: UIColor(hub: 0xFFD9A0), windowLit: UIColor(hub: 0xFFD9A0), windowGlow: 2.1,
        water: UIColor(hub: 0x3A8FE0), background: UIColor(hub: 0x40457E),
        // Measured on the first captures: a blue-tinted fill rendered roads
        // at 0.7x red and green but 1.0x blue. The albedos already carry the
        // reference's blue-grey, so the fill is a cool grey, bright enough
        // to give them back at about 1x.
        skyTop: UIColor(hub: 0xB4B6C8), skyHorizon: UIColor(hub: 0x8E90A8),
        blob: UIColor(hub: 0x161842), lampGlow: 2.6, keyIntensity: 1_100,
        keyColor: UIColor(hub: 0xD8DCF5), iblExponent: 1.45, dusk: 1)

    /// `a` crossfaded towards `b`, `t` 0…1: the dusk transition's frames.
    static func mix(_ a: HubPalette, _ b: HubPalette, _ t: Float) -> HubPalette {
        let t = max(0, min(1, t))
        if t == 0 { return a }
        if t == 1 { return b }
        let c = CGFloat(t)
        func m(_ x: UIColor, _ y: UIColor) -> UIColor { x.mixed(with: y, c) }
        func f(_ x: Float, _ y: Float) -> Float { x + (y - x) * t }
        return HubPalette(
            concrete: m(a.concrete, b.concrete), concreteLight: m(a.concreteLight, b.concreteLight),
            asphalt: m(a.asphalt, b.asphalt), asphaltDark: m(a.asphaltDark, b.asphaltDark),
            building: m(a.building, b.building), buildingShade: m(a.buildingShade, b.buildingShade),
            roof: m(a.roof, b.roof), glass: m(a.glass, b.glass), glassOpacity: f(a.glassOpacity, b.glassOpacity),
            grass: m(a.grass, b.grass), grassBright: m(a.grassBright, b.grassBright),
            tree: zip(a.tree, b.tree).map { m($0, $1) },
            trunk: m(a.trunk, b.trunk), marking: m(a.marking, b.marking), taxiLine: m(a.taxiLine, b.taxiLine),
            houseRoof: m(a.houseRoof, b.houseRoof), houseWood: m(a.houseWood, b.houseWood),
            windowDark: m(a.windowDark, b.windowDark), windowLit: m(a.windowLit, b.windowLit),
            windowGlow: f(a.windowGlow, b.windowGlow),
            water: m(a.water, b.water), background: m(a.background, b.background),
            skyTop: m(a.skyTop, b.skyTop), skyHorizon: m(a.skyHorizon, b.skyHorizon),
            blob: m(a.blob, b.blob), lampGlow: f(a.lampGlow, b.lampGlow), keyIntensity: f(a.keyIntensity, b.keyIntensity),
            keyColor: m(a.keyColor, b.keyColor), iblExponent: f(a.iblExponent, b.iblExponent),
            dusk: f(a.dusk, b.dusk))
    }

    static func livery(_ livery: Livery) -> UIColor {
        switch livery {
        case .azure: UIColor(hub: 0x3B4FC4)
        case .ember: UIColor(hub: 0xE07A2E)
        case .jade: UIColor(hub: 0x22A27A)
        case .crimson: UIColor(hub: 0xD23C55)
        case .violet: UIColor(hub: 0x5B45B8)
        case .slate: UIColor(hub: 0x5D6A8A)
        case .gold: UIColor(hub: 0xD9A531)
        case .teal: UIColor(hub: 0x1F9AAE)
        }
    }

    /// The second livery colour: the reference's indigo tails carry a warm
    /// flash, so every livery gets a contrasting accent.
    static func liveryAccent(_ livery: Livery) -> UIColor {
        switch livery {
        case .azure, .violet, .slate, .teal: UIColor(hub: 0xF5A623)
        case .ember, .gold: UIColor(hub: 0x2A3A8C)
        case .jade, .crimson: UIColor(hub: 0xFFFFFF)
        }
    }
}

extension UIColor {
    convenience init(hub hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    func mixed(with other: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}

/// The light glass dashboard's tokens. Light in every mode, as in the
/// reference, where the panels stay light even at night.
enum HubChromeStyle {
    static let ink = Color(red: 0.11, green: 0.15, blue: 0.29)
    static let secondary = Color(red: 0.42, green: 0.46, blue: 0.60)
    static let tertiary = Color(red: 0.60, green: 0.64, blue: 0.76)
    static let accent = Color(red: 0.18, green: 0.42, blue: 1.0)
    static let accentSoft = Color(red: 0.18, green: 0.42, blue: 1.0).opacity(0.12)
    static let good = Color(red: 0.13, green: 0.66, blue: 0.47)
    static let goodSoft = Color(red: 0.13, green: 0.66, blue: 0.47).opacity(0.14)
    static let warn = Color(red: 0.93, green: 0.55, blue: 0.13)
    static let bad = Color(red: 0.88, green: 0.27, blue: 0.36)
    static let panelFill = Color.white.opacity(0.62)
    static let panelRim = Color.white.opacity(0.9)
    static let panelShadow = Color(red: 0.22, green: 0.26, blue: 0.52).opacity(0.16)
    static let track = Color(red: 0.86, green: 0.88, blue: 0.95)
    static let radius: CGFloat = 16
}
