import RealityKit
import Metal
import os

/// Bloom for the hub (docs/HUB_HANDOFF.md §3 step 5): the cyan route,
/// queue and pulse rings and the kiosk screens glow by day; warm windows
/// and street lamps join them at night — the reference's pre-rendered
/// softness.
///
/// Runs in `ARView.renderCallbacks.postProcess` on RealityKit's render
/// thread: bright pass at half resolution, separable Gaussian, screen blend
/// over the frame. The bright pass is gated by hue rather than brightness
/// alone, so white clay, yellow taxi lines and orange tail flashes stay
/// matte while the overlays glow.
///
/// The shaders are compiled from source at first use, so the app target
/// needs no Metal toolchain at build time. Every failure — no pipelines,
/// a target the GPU cannot write, the Simulator (which cannot write sRGB
/// textures) — falls back to copying the frame through unchanged.
@available(iOS 18.0, *)
final class HubPostProcess: @unchecked Sendable {
    struct Params {
        var threshold: Float = 0.74
        var knee: Float = 0.2
        var minChroma: Float = 0.42
        var strength: Float = 0.9
        var night: Float = 0
    }

    private let params = OSAllocatedUnfairLock(initialState: Params())
    private var bright: MTLComputePipelineState?
    private var blurX: MTLComputePipelineState?
    private var blurY: MTLComputePipelineState?
    private var composite: MTLComputePipelineState?
    private var half: (MTLTexture, MTLTexture)?

    /// Day (0) to night (1): lowers the threshold and lets warm light glow.
    func setNight(_ value: Float) {
        params.withLock {
            $0.night = value
            $0.threshold = 0.74 - 0.16 * value
            $0.strength = 0.9 + 0.5 * value
        }
    }

    @MainActor
    func install(on view: ARView) {
        view.renderCallbacks.prepareWithDevice = Self.prepareCallback(self)
        view.renderCallbacks.postProcess = Self.postProcessCallback(self)
    }

    // Built outside the main actor: RealityKit calls these on its render
    // thread, and a closure formed in a @MainActor method would be
    // main-actor isolated.
    nonisolated private static func prepareCallback(_ pass: HubPostProcess) -> (MTLDevice) -> Void {
        { @Sendable device in pass.prepare(device) }
    }

    nonisolated private static func postProcessCallback(_ pass: HubPostProcess) -> (ARView.PostProcessContext) -> Void {
        { @Sendable context in pass.run(context) }
    }

    private func prepare(_ device: MTLDevice) {
        #if !targetEnvironment(simulator)
        do {
            let library = try device.makeLibrary(source: Self.source, options: nil)
            func pipeline(_ name: String) throws -> MTLComputePipelineState? {
                guard let function = library.makeFunction(name: name) else { return nil }
                return try device.makeComputePipelineState(function: function)
            }
            bright = try pipeline("hubBright")
            blurX = try pipeline("hubBlurX")
            blurY = try pipeline("hubBlurY")
            composite = try pipeline("hubComposite")
        } catch {
            bright = nil
            composite = nil
        }
        #endif
    }

    private func run(_ context: ARView.PostProcessContext) {
        let source = context.sourceColorTexture, target = context.targetColorTexture
        guard let bright, let blurX, let blurY, let composite,
              target.usage.contains(.shaderWrite),
              target.width == source.width, target.height == source.height else {
            return copy(context)
        }
        let w = max(1, source.width / 2), h = max(1, source.height / 2)
        if half == nil || half?.0.width != w || half?.0.height != h {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h,
                                                             mipmapped: false)
            d.usage = [.shaderRead, .shaderWrite]
            d.storageMode = .private
            if let a = context.device.makeTexture(descriptor: d), let b = context.device.makeTexture(descriptor: d) {
                half = (a, b)
            } else {
                half = nil
            }
        }
        guard let pair = half, let encoder = context.commandBuffer.makeComputeCommandEncoder() else {
            return copy(context)
        }
        let (a, b) = pair
        var p = params.withLock { $0 }
        let length = MemoryLayout<Params>.stride
        encoder.setComputePipelineState(bright)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(a, index: 1)
        encoder.setBytes(&p, length: length, index: 0)
        dispatch(encoder, bright, w, h)
        // Two rounds of the separable blur widen the halo without a wider
        // kernel.
        for _ in 0..<2 {
            encoder.setComputePipelineState(blurX)
            encoder.setTexture(a, index: 0)
            encoder.setTexture(b, index: 1)
            dispatch(encoder, blurX, w, h)
            encoder.setComputePipelineState(blurY)
            encoder.setTexture(b, index: 0)
            encoder.setTexture(a, index: 1)
            dispatch(encoder, blurY, w, h)
        }
        encoder.setComputePipelineState(composite)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(a, index: 1)
        encoder.setTexture(target, index: 2)
        encoder.setBytes(&p, length: length, index: 0)
        dispatch(encoder, composite, target.width, target.height)
        encoder.endEncoding()
    }

    private func dispatch(_ encoder: MTLComputeCommandEncoder, _ state: MTLComputePipelineState, _ w: Int, _ h: Int) {
        let tw = state.threadExecutionWidth
        let th = max(1, state.maxTotalThreadsPerThreadgroup / tw)
        encoder.dispatchThreads(MTLSize(width: w, height: h, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1))
    }

    private func copy(_ context: ARView.PostProcessContext) {
        guard let blit = context.commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: context.sourceColorTexture, to: context.targetColorTexture)
        blit.endEncoding()
    }

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Params { float threshold; float knee; float minChroma; float strength; float night; };

    static float hueOf(float3 c) {
        float hi = max(c.r, max(c.g, c.b)), lo = min(c.r, min(c.g, c.b));
        float d = hi - lo;
        if (d < 1e-4) { return 0.0; }
        float h;
        if (hi == c.r) { h = fmod((c.g - c.b) / d, 6.0); }
        else if (hi == c.g) { h = (c.b - c.r) / d + 2.0; }
        else { h = (c.r - c.g) / d + 4.0; }
        h /= 6.0;
        return h < 0.0 ? h + 1.0 : h;
    }

    static float band(float h, float a, float b, float soft) {
        return smoothstep(a - soft, a, h) * (1.0 - smoothstep(b, b + soft, h));
    }

    kernel void hubBright(texture2d<float, access::sample> src [[texture(0)]],
                          texture2d<float, access::write> dst [[texture(1)]],
                          constant Params& p [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float2 uv = (float2(gid) + 0.5) / float2(dst.get_width(), dst.get_height());
        float3 c = src.sample(s, uv).rgb;
        float hi = max(c.r, max(c.g, c.b)), lo = min(c.r, min(c.g, c.b));
        float h = hueOf(c);
        // Cyan to blue glows by day; warm window light only at night.
        float cool = band(h, 0.47, 0.64, 0.04);
        float warm = p.night * band(h, 0.04, 0.15, 0.03);
        float gate = max(cool, warm)
            * smoothstep(p.minChroma, p.minChroma + 0.2, hi - lo)
            * smoothstep(p.threshold, p.threshold + p.knee, hi);
        dst.write(float4(c * gate, 1.0), gid);
    }

    constant float weights[7] = { 0.1585, 0.1465, 0.1157, 0.0780, 0.0449, 0.0221, 0.0093 };

    kernel void hubBlurX(texture2d<float, access::read> src [[texture(0)]],
                         texture2d<float, access::write> dst [[texture(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
        int w = int(src.get_width());
        float3 sum = src.read(gid).rgb * weights[0];
        for (int k = 1; k < 7; k++) {
            int o = k * 2;
            sum += src.read(uint2(clamp(int(gid.x) + o, 0, w - 1), gid.y)).rgb * weights[k];
            sum += src.read(uint2(clamp(int(gid.x) - o, 0, w - 1), gid.y)).rgb * weights[k];
        }
        dst.write(float4(sum, 1.0), gid);
    }

    kernel void hubBlurY(texture2d<float, access::read> src [[texture(0)]],
                         texture2d<float, access::write> dst [[texture(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
        int h = int(src.get_height());
        float3 sum = src.read(gid).rgb * weights[0];
        for (int k = 1; k < 7; k++) {
            int o = k * 2;
            sum += src.read(uint2(gid.x, clamp(int(gid.y) + o, 0, h - 1))).rgb * weights[k];
            sum += src.read(uint2(gid.x, clamp(int(gid.y) - o, 0, h - 1))).rgb * weights[k];
        }
        dst.write(float4(sum, 1.0), gid);
    }

    kernel void hubComposite(texture2d<float, access::read> src [[texture(0)]],
                             texture2d<float, access::sample> bloom [[texture(1)]],
                             texture2d<float, access::write> dst [[texture(2)]],
                             constant Params& p [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float2 uv = (float2(gid) + 0.5) / float2(dst.get_width(), dst.get_height());
        float4 base = src.read(gid);
        float3 glow = saturate(bloom.sample(s, uv).rgb * p.strength);
        dst.write(float4(1.0 - (1.0 - base.rgb) * (1.0 - glow), base.a), gid);
    }
    """
}
