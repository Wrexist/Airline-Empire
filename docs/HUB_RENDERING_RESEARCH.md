# Hub View — rendering research and audit (2026-10-09)

> What RealityKit on iOS 18–26 can and cannot do for the Hub View's
> "pre-rendered clay diorama" look, checked against Apple's documentation,
> WWDC sessions and DTS (Apple developer technical support) forum answers.
> Also the audit of the first build's renderer and what was changed.
> Read with [`HUB_HANDOFF.md`](HUB_HANDOFF.md).

The app's floor is iOS 17; the hub is iOS 18+. CI builds with Xcode 26.2
(iOS 26.2 SDK). Every API below is marked with its minimum OS. **[V]** =
verified in an Apple source, **[U]** = unverified or community-only.

---

## 1. Post-processing (bloom, AO, tilt-shift)

- `ARView.renderCallbacks.postProcess: ((ARView.PostProcessContext) -> Void)?`
  and `prepareWithDevice` — iOS 15 [V]. The context gives `device`,
  `commandBuffer`, `sourceColorTexture`, `sourceDepthTexture`,
  `targetColorTexture`, `projection`, `time`.
- **The target must be written every frame** [V]; when an effect is off,
  blit source → target. RealityKit's own effects run *before* the callback;
  the input is tone-mapped LDR colour.
- Target format is `bgra8Unorm_srgb` [V, DTS]. Compute writes to sRGB are
  fine on every Apple GPU family, **but the Simulator cannot write sRGB
  textures** [V] — so bloom is a passthrough there and **the CI captures
  never show it**. It can only be judged on a device.
- Depth is an infinite reverse-Z buffer (1 near, 0 at infinity) [V]; whether
  it is populated in `.nonAR` mode is undocumented [U] — check on device
  before building SSAO on it.
- Xcode 26 ships the Metal toolchain as a separate component; a `.metal`
  file in the target would make CI depend on it. **The hub compiles its
  kernels from source at runtime** (`device.makeLibrary(source:)`), which
  needs no toolchain.
- `MPSImageThresholdToZero` thresholds on luminance (greys out colour), and
  in-place MPS blurs often fail [V] — hence hand-written kernels.
- `BloomComponent` / `ToneMappingComponent` are iOS 27; the
  `PostProcessEffect` protocol (iOS 26) is RealityView-only [V]. Not usable
  here.

**Implemented:** `HubPostProcess.swift` — bright pass gated by *hue* (cyan →
blue by day; warm windows join at night), half resolution, two rounds of a
separable 13-tap Gaussian, screen blend. Gating by hue rather than
brightness keeps white clay, yellow taxi lines and orange tail flashes
matte. Any failure (no pipelines, unwritable target) falls back to the
blit. `-AEHubNoBloom` turns it off.

## 2. Shadows

- `DirectionalLightComponent.Shadow(maximumDistance:depthBias:)` —
  `maximumDistance` is **deprecated in iOS 18** in favour of
  `shadowProjection: .automatic(maximumDistance:)` / `.fixed(zNear:zFar:orthographicScale:)` [V].
  The hub still uses the deprecated initialiser (a warning, not an error);
  moving to `shadowProjection` is a small follow-up once verified on a
  device. Cascades are iOS 27.
- **Implemented:** the shadow range follows the camera
  (`HubSceneController.fitShadows`, ≈ 2.4 × camera distance) instead of one
  2.4 km map for every shot, so the gate and terminal shots get crisp
  shadows.
- `DynamicLightShadowComponent(castsShadow:)` (iOS 18) [V] opts props out of
  casting — a cheap win for markings and small props if the shadow pass
  shows up in Instruments.
- `GroundingShadowComponent` (iOS 18) is a fake top-down shadow aimed at AR;
  unverified in `.nonAR` [U]. The blob decals stay.
- `UnlitMaterial` receives no light or shadow [V].

## 3. Lighting

- `EnvironmentResource(equirectangular:withName:) async throws` — iOS 18 [V]
  (deprecated in the iOS 27.2 SDK for a newer initialiser). Already used for
  the generated sky.
- `ImageBasedLightComponent(source: .blend(a, b, t))` + receiver (iOS 18) [V]
  could crossfade day ↔ night instead of swapping; not needed yet.

## 4. Materials

- **Additive blending exists** (iOS 18): `UnlitMaterial.Program.Descriptor`
  `.blendMode = .add`, `applyPostProcessToneMap = false` [V]. Needs an async
  `Program` — worth it for the pulse rings and route once the material
  factory can wait for programs. `.add` ignores alpha: fade by darkening.
- `PhysicallyBasedMaterial` has `clearcoat`, `sheen`, `specular`; iOS 18
  adds `readsDepth`/`writesDepth` [V]. Clay: roughness ≈ 0.8, low specular.
- `ModelSortGroupComponent` (iOS 18) [V]: put all glass in one `.prePass`
  group if transparent sorting artefacts appear on the vaults and tubes.
- `CustomMaterial` throws in the iOS 18 Simulator for lit surface shaders
  (constant-buffer limit) [V] — keep fallbacks if it is ever used.
- `ShaderGraphMaterial(named:from:in:)` loads from a plain bundled `.usda`
  [V] — the route to node-based materials without Reality Composer Pro.

## 5. Performance

- Draw calls and transparent overdraw cost more than triangles [V].
  **Implemented:** static turnaround dressing (vehicles, cones, crew, their
  shadows) and the hall crowd are merged into one mesh per material
  (`HubStaticBatcher`, `HubMeshBatch.append`). A busy stand went from ~70
  entities to ~12; a full hall from ~960 to ~14.
- `MeshInstancesComponent` (GPU instancing) is **iOS 26** [V]; behind
  `#available` it would suit trees and parked cars.
- `LowLevelMesh` (iOS 18) [V] would let the moving crowds and vehicles
  share one draw.
- `OrthographicCameraComponent` (iOS 18) works in `.nonAR` [U, community];
  the hub keeps a 24° perspective, which reads isometric and keeps the
  slight convergence of reference shot B.

## 6. Audit of the first build — what was wrong and what changed

| # | Finding | Fix |
|---|---|---|
| 1 | Overview aimed at the empty middle of the apron; terminal a thin bar at the edge, no landside. | `HubFraming` solves every shot from a subject (terminal + piers + stands + kerb for the overview) into the screen area the dashboard leaves free. Tested for every airport, iPad and iPhone. |
| 2 | Stands filled pier faces in order: ARN's east pier had a bare face. | Stands spread evenly over every face, inner faces first (`standsAreSpreadOverEveryPierFace`). |
| 3 | Apron sized with a fixed 70 m + stand-depth margin → > 50 % empty concrete. | Apron = parked envelopes + piers + pushbacks + one taxilane (`apronIsTightAroundTheStands`). |
| 4 | Near plane 2 m against a 12 km far plane: depth precision too low for the stacked ground layers. | Near/far scale with the camera distance. |
| 5 | One shadow map for 2.4 km in every shot. | Shadow range follows the camera. |
| 6 | Each person 4 entities, each parked vehicle 6–8: the hall alone could reach ~960 entities against a 2 500 budget. | Static dressing and crowds batched per material. |
| 7 | Heatmap pools sized in texture pixels on a non-square texture; a wide blue/green halo washed the hall out. | Pools in metres on both axes, 4–9 m, red→orange→yellow→clear, alpha ≤ 0.85. |
| 8 | District service route drawn straight across lawns and garden walls. | Route follows the streets past each stop's gate (`serviceRouteFollowsTheStreets`). |
| 9 | Gate callout clipped under the KPI cards. | Clamped between the KPI row and the timeline, clear of the inspector. |
| 10 | A shot change could spin the camera the long way round. | Yaw interpolates the short way. |
| 11 | Captures always showed "Servicing"; the reference's gate is the boarding moment. | `-AEUITestHubStage boarding` holds the focused stand (`HubSnapshot.holding`). |

## 7. Next, in order of value

1. Judge bloom on a device (A15 iPhone, M-series iPad); tune `HubPostProcess.Params`.
2. Authored models via the pipeline (`HUB_MODEL_PIPELINE.md`), narrowbody first.
3. SSAO from `sourceDepthTexture` once depth is confirmed in `.nonAR`.
4. Additive programs for glows; `ModelSortGroup` for glass if sorting shows.
5. `shadowProjection` instead of the deprecated `maximumDistance`, on device.
6. `MeshInstancesComponent` for trees and parked cars behind `#available(iOS 26, *)`.
