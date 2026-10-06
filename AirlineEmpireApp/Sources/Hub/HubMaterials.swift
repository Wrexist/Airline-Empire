import RealityKit
import UIKit
import AirlineEmpireCore

/// Every surface the hub uses, keyed so a day/night switch can repaint the
/// whole scene by swapping materials rather than rebuilding geometry.
enum HubMaterialKey: Hashable {
    case concrete, concreteLight, asphalt, asphaltDark, building, buildingShade, roof
    case glass, grass, grassBright, tree(Int), trunk, marking, taxiLine
    case houseRoof, houseWood, windowDark, water, blob, tyre, darkMetal, hiVis, cone, white
    case safety, pulse, queueGlow, routeGlow, pinGlow, lamp, lampPool, heat
    case livery(Livery), liveryAccent(Livery), cloth(Int), skin(Int)
    case office(floors: Int), screen
}

@available(iOS 18.0, *)
@MainActor
final class HubMaterials {
    private(set) var palette: HubPalette
    private var cache: [HubMaterialKey: RealityKit.Material] = [:]
    private var textures: [String: TextureResource] = [:]
    var heatmap: TextureResource?

    init(palette: HubPalette) {
        self.palette = palette
    }

    func setPalette(_ palette: HubPalette) {
        guard palette != self.palette else { return }
        self.palette = palette
        cache.removeAll()
    }

    subscript(_ key: HubMaterialKey) -> RealityKit.Material {
        if let m = cache[key] { return m }
        let m = make(key)
        cache[key] = m
        return m
    }

    // MARK: Factory

    private func matte(_ color: UIColor, roughness: Float = 0.9) -> RealityKit.Material {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: 0)
        return m
    }

    private func glow(_ color: UIColor, intensity: Float) -> RealityKit.Material {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: 0.6)
        m.emissiveColor = .init(color: color)
        m.emissiveIntensity = intensity
        return m
    }

    private func unlit(_ color: UIColor, opacity: Float = 1, texture: TextureResource? = nil) -> RealityKit.Material {
        var m = UnlitMaterial()
        if let texture {
            m.color = .init(tint: color, texture: .init(texture))
        } else {
            m.color = .init(tint: color)
        }
        if opacity < 1 || texture != nil {
            m.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return m
    }

    private func make(_ key: HubMaterialKey) -> RealityKit.Material {
        let p = palette
        let night = p.windowGlow > 0
        switch key {
        case .concrete: return matte(p.concrete)
        case .concreteLight: return matte(p.concreteLight)
        case .asphalt: return matte(p.asphalt, roughness: 0.95)
        case .asphaltDark: return matte(p.asphaltDark, roughness: 0.95)
        case .building: return matte(p.building, roughness: 0.8)
        case .buildingShade: return matte(p.buildingShade, roughness: 0.85)
        case .roof: return matte(p.roof, roughness: 0.75)
        case .glass:
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: p.glass)
            m.roughness = .init(floatLiteral: 0.12)
            m.metallic = .init(floatLiteral: 0.1)
            m.blending = .transparent(opacity: .init(floatLiteral: p.glassOpacity))
            if night {
                m.emissiveColor = .init(color: p.windowLit)
                m.emissiveIntensity = 0.35
            }
            return m
        case .grass: return matte(p.grass, roughness: 1)
        case .grassBright: return matte(p.grassBright, roughness: 1)
        case .tree(let i): return matte(p.tree[i % p.tree.count], roughness: 0.95)
        case .trunk: return matte(p.trunk)
        case .marking: return matte(p.marking, roughness: 0.8)
        case .taxiLine: return night ? glow(p.taxiLine, intensity: 0.6) : matte(p.taxiLine, roughness: 0.7)
        case .houseRoof: return matte(p.houseRoof, roughness: 0.7)
        case .houseWood: return matte(p.houseWood, roughness: 0.85)
        case .windowDark: return night ? glow(p.windowLit, intensity: p.windowGlow) : matte(p.windowDark, roughness: 0.2)
        case .water: return matte(p.water, roughness: 0.15)
        case .blob: return unlit(p.blob, opacity: night ? 0.55 : 0.32, texture: texture("blob", Self.blobImage))
        case .tyre: return matte(HubPalette.tyre)
        case .darkMetal: return matte(HubPalette.darkMetal, roughness: 0.5)
        case .hiVis: return matte(HubPalette.hiVis, roughness: 0.7)
        case .cone: return matte(HubPalette.cone, roughness: 0.7)
        case .white: return matte(night ? p.building : .white, roughness: 0.55)
        case .safety: return unlit(HubPalette.safety)
        case .pulse: return unlit(HubPalette.pulse, opacity: 0.55, texture: texture("ring", Self.ringImage))
        case .queueGlow: return unlit(HubPalette.queueGlow, opacity: 0.85, texture: texture("strip", Self.stripImage))
        case .routeGlow: return unlit(HubPalette.queueGlow, opacity: 0.95)
        case .pinGlow: return unlit(HubPalette.pin, opacity: 0.4, texture: texture("blob", Self.blobImage))
        case .lamp: return night ? glow(p.windowLit, intensity: 3) : matte(p.building)
        case .lampPool: return unlit(p.windowLit, opacity: night ? 0.5 : 0, texture: texture("blob", Self.blobImage))
        case .heat:
            if let heatmap { return unlit(.white, opacity: 0.85, texture: heatmap) }
            return unlit(.clear, opacity: 0)
        case .livery(let l): return matte(HubPalette.livery(l), roughness: 0.45)
        case .liveryAccent(let l): return matte(HubPalette.liveryAccent(l), roughness: 0.5)
        case .cloth(let i):
            let colors: [UInt32] = [0x3A4A8C, 0xE85D75, 0x2FA88A, 0xF2B544, 0x7F6AD6, 0xEDEFF7, 0x4A90E2, 0xC25B3F]
            return matte(UIColor(hub: colors[i % colors.count]), roughness: 0.9)
        case .skin(let i):
            let colors: [UInt32] = [0xF1C7A5, 0xC68C64, 0x8D5A3B, 0xE3B18C]
            return matte(UIColor(hub: colors[i % colors.count]), roughness: 0.9)
        case .office(let floors):
            var m = PhysicallyBasedMaterial()
            let tex = texture("office\(floors)\(night)") { Self.officeImage(floors: floors, night: night) }
            m.baseColor = .init(tint: p.building, texture: .init(tex))
            m.roughness = .init(floatLiteral: 0.8)
            if night {
                m.emissiveColor = .init(color: .white, texture: .init(tex))
                m.emissiveIntensity = 0.9
            }
            return m
        case .screen: return glow(UIColor(hub: 0x1F3A7A), intensity: 0.8)
        }
    }

    private func texture(_ name: String, _ image: () -> CGImage?) -> TextureResource {
        if let t = textures[name] { return t }
        let t = image().flatMap { try? TextureResource(image: $0, options: .init(semantic: .color)) }
            ?? (try! TextureResource(image: Self.solid(), options: .init(semantic: .color)))
        textures[name] = t
        return t
    }

    func makeHeatmap(hotspots: [(x: CGFloat, y: CGFloat, weight: CGFloat)], load: CGFloat) {
        heatmap = Self.heatImage(hotspots: hotspots, load: load)
            .flatMap { try? TextureResource(image: $0, options: .init(semantic: .color)) }
        cache[.heat] = nil
    }

    // MARK: Generated images

    nonisolated static func render(_ size: CGSize, _ draw: (CGContext) -> Void) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }.cgImage
    }

    nonisolated static func solid() -> CGImage {
        render(CGSize(width: 4, height: 4)) { $0.setFillColor(UIColor.white.cgColor); $0.fill(CGRect(x: 0, y: 0, width: 4, height: 4)) }!
    }

    /// A soft radial falloff: contact shadows and glows.
    nonisolated static func blobImage() -> CGImage? {
        render(CGSize(width: 128, height: 128)) { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.55).cgColor,
                          UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1])!
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                                   endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
        }
    }

    /// A ring with a soft inner edge: the pulse around a selected aircraft.
    nonisolated static func ringImage() -> CGImage? {
        render(CGSize(width: 256, height: 256)) { ctx in
            let colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.withAlphaComponent(0.25).cgColor,
                          UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                               locations: [0, 0.7, 0.9, 1])!
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                                   endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [])
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(3)
            ctx.strokeEllipse(in: CGRect(x: 40, y: 40, width: 176, height: 176))
        }
    }

    /// A strip bright in the middle, fading to both long edges.
    nonisolated static func stripImage() -> CGImage? {
        render(CGSize(width: 8, height: 64)) { ctx in
            let colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.cgColor,
                          UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 64), options: [])
        }
    }

    /// Window bands for an office façade, one per floor.
    nonisolated static func officeImage(floors: Int, night: Bool) -> CGImage? {
        let h = 32 * max(1, floors)
        return render(CGSize(width: 128, height: h)) { ctx in
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 128, height: h))
            for f in 0..<floors {
                let y = CGFloat(f * 32) + 9
                for c in 0..<6 {
                    let lit = night && ((f * 7 + c * 3) % 5 != 0)
                    let color = night
                        ? (lit ? UIColor(hub: 0xFFE0A8) : UIColor(hub: 0x343866))
                        : UIColor(hub: 0x8A97C8)
                    ctx.setFillColor(color.cgColor)
                    ctx.fill(CGRect(x: CGFloat(c) * 21 + 4, y: y, width: 16, height: 15))
                }
            }
        }
    }

    /// The terminal crowding heatmap: blue → green → yellow → red pools.
    nonisolated static func heatImage(hotspots: [(x: CGFloat, y: CGFloat, weight: CGFloat)], load: CGFloat) -> CGImage? {
        let w = 256, h = 128
        var field = [CGFloat](repeating: 0, count: w * h)
        for spot in hotspots {
            let sx = spot.x * CGFloat(w), sy = spot.y * CGFloat(h)
            let radius = 26 + 40 * spot.weight * (0.5 + load)
            for y in 0..<h {
                for x in 0..<w {
                    let d = hypot(CGFloat(x) - sx, (CGFloat(y) - sy) * 1.4) / radius
                    if d < 1 { field[y * w + x] += (1 - d * d) * spot.weight * (0.45 + load) }
                }
            }
        }
        let stops: [(CGFloat, UInt32)] = [(0.0, 0x2F8BFF), (0.35, 0x3FD7A0), (0.6, 0xF5D547), (0.8, 0xF59A3D), (1.0, 0xE8445A)]
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let v = min(1, field[i])
            guard v > 0.02 else { continue }
            var c0 = stops[0], c1 = stops[stops.count - 1]
            for k in 0..<(stops.count - 1) where v >= stops[k].0 && v <= stops[k + 1].0 {
                c0 = stops[k]; c1 = stops[k + 1]
            }
            let t = (v - c0.0) / max(0.0001, c1.0 - c0.0)
            func ch(_ shift: UInt32) -> CGFloat {
                let a = CGFloat((c0.1 >> shift) & 0xFF), b = CGFloat((c1.1 >> shift) & 0xFF)
                return a + (b - a) * t
            }
            let alpha = min(1, v * 1.6) * 0.85
            pixels[i * 4] = UInt8(ch(16) * alpha)
            pixels[i * 4 + 1] = UInt8(ch(8) * alpha)
            pixels[i * 4 + 2] = UInt8(ch(0) * alpha)
            pixels[i * 4 + 3] = UInt8(255 * alpha)
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// The sky used for image-based lighting: zenith to horizon to ground.
    nonisolated static func skyImage(_ p: HubPalette) -> CGImage? {
        render(CGSize(width: 256, height: 128)) { ctx in
            let colors = [p.skyTop.cgColor, p.skyHorizon.cgColor, p.grass.mixed(with: p.concrete, 0.6).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 0.62])!
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 128), options: [])
        }
    }
}
