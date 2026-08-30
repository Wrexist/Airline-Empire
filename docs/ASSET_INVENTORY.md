# Asset Inventory

Every asset the project ships or generates, audited 2026-08-30 (AE-030) against
the code rather than against documentation.

**Headline finding: the shipping application contains one image file.**
Everything else visual is drawn at runtime from code. That is not an oversight
to correct — it is the property that lets aircraft be recoloured per airline and
rotated to any heading, and it is why this project has never had a missing-asset
bug.

---

## 1. Totals

| Category | Count | On disk | Notes |
| --- | --- | --- | --- |
| Raster images (shipped) | **1** | 1.5 MB | the app icon |
| Raster images (not shipped) | 2 | — | docs + website |
| Vector/procedural art | 4 planforms | 0 | `AircraftSilhouette`, code |
| Audio | 58 `.wav` | 8.4 MB | |
| SF Symbols referenced | 92 call sites | 0 | system-provided |
| `Image("name")` call sites | **0** | — | across 5,275 lines of screens |
| Asset catalogs | 1 | — | `AppIcon` + one colorset |
| Third-party dependencies | **0** | — | no SPM, no npm |

---

## 2. Shipped assets

### 2.1 App icon

| Field | Value |
| --- | --- |
| **Name** | `icon-1024.png` |
| **Location** | `AirlineEmpireApp/Resources/Assets.xcassets/AppIcon.appiconset/` |
| **Type / format** | Raster, PNG, 1024×1024 |
| **Size** | 1,554,373 bytes |
| **Current use** | Home screen and App Store icon |
| **Screens** | None in-app |
| **Quality** | Adequate; not visually validated on a device |
| **Action** | **KEEP.** |
| **Missing variants** | None — a single 1024 source is the modern requirement |
| **Performance** | Not decoded at runtime; packaged by the asset catalog |
| **Provenance** | Original, generated for this project. Source retained at `docs/design/icon-source-1254.png` |

**One concern, not acted on:** 1.5 MB is large for a 1024×1024 icon and
suggests it is stored without palette optimisation. It costs download size, not
runtime memory. Recorded as TD-017 rather than changed, because re-encoding an
icon nobody has seen rendered risks introducing a banding artefact that would
only be visible on a device.

### 2.2 Launch background colour set

| Field | Value |
| --- | --- |
| **Name** | `LaunchBackground.colorset` |
| **Location** | `AirlineEmpireApp/Resources/Assets.xcassets/` |
| **Type** | Colour definition, no image |
| **Current use** | Launch screen background |
| **Action** | **KEEP.** |
| **Provenance** | Original, authored values |

### 2.3 Audio — 58 files, 8.4 MB

Catalogued in full by `docs/AUDIO_ASSET_MANIFEST.md`; not duplicated here. In
scope for this inventory only as a size and provenance line.

| Field | Value |
| --- | --- |
| **Location** | `AirlineEmpireApp/Resources/Audio/` |
| **Format** | `.wav`, uncompressed |
| **Groups** | 4 music beds, 2 ambience, ~52 one-shots |
| **Action** | **IMPROVE (deferred).** |
| **Performance** | Uncompressed WAV is the single largest asset cost in the project. Converting to a compressed format would cut the bundle materially |
| **Provenance** | Original, generated for this project; `ae-audio-manifest` validates that every semantic event resolves to a file |

**Not changed in AE-030.** Re-encoding audio nobody has heard risks introducing
artefacts that are inaudible to a checksum and obvious to a player. Recorded as
TD-018. The right moment is the same one as every other deferred item here: when
somebody can run the game.

---

## 3. Procedural visual systems (the real asset library)

These are not files. They are code, and they are where this project's visual
identity actually lives.

### 3.1 Aircraft silhouettes

| Field | Value |
| --- | --- |
| **Name** | `AircraftSilhouette` |
| **Location** | `AirlineEmpireApp/Sources/Map/AircraftSilhouette.swift` (253 lines) |
| **Type** | Procedural vector — four `Path` planforms + a wedge |
| **Current use** | Map markers, market cards, aircraft detail header |
| **Screens** | Map, Aircraft Market, Aircraft Detail |
| **Quality** | **Adequate on the map, weak everywhere else** |
| **Action** | **IMPROVE — the primary work of AE-030** |
| **Missing variants** | Six categories collapse to four planforms; `narrowbody`/`largeNarrowbody` and `widebody`/`largeWidebody` share a shape *and* a scale, so five types draw identically (TD-014). No side-profile presentation exists at any size |
| **Performance** | Excellent. Zero disk, zero decode, zero memory; a `Path` per draw |
| **Provenance** | Original, authored as code. Generic planforms, not derived from any real aircraft outline or photograph |

### 3.2 World geometry

| Field | Value |
| --- | --- |
| **Name** | `WorldGeometry` |
| **Location** | `AirlineEmpireApp/Sources/Map/WorldGeometry.swift` (307 lines) |
| **Type** | Procedural vector coastlines |
| **Current use** | The map's landmasses |
| **Action** | **KEEP.** |
| **Performance** | Benchmarked by `ae-map-bench` |
| **Provenance** | Original, authored as code |

### 3.3 Map chrome and frame

| Field | Value |
| --- | --- |
| **Name** | `MapChrome`, `MapFrame` |
| **Location** | `AirlineEmpireApp/Sources/Map/` (378 + 534 lines) |
| **Type** | Procedural — `GraphicsContext` drawing; routes, airports, aircraft, event overlays, gradients |
| **Current use** | The entire map render |
| **Action** | **KEEP.** |
| **Performance** | The one place with a measured frame budget (`docs/MAP_ARCHITECTURE.md` §11) |
| **Provenance** | Original |

### 3.4 Design system

| Field | Value |
| --- | --- |
| **Name** | `AETheme`, `AEType`, `Components` |
| **Location** | `AirlineEmpireApp/Sources/DesignSystem/` (2,075 lines) |
| **Type** | Colour tokens, 12 type roles, container and metric components |
| **Action** | **KEEP.** |
| **Notes** | Three raw colour literals in the whole app; the palette is disciplined |
| **Provenance** | Original |

### 3.5 SF Symbols

| Field | Value |
| --- | --- |
| **Count** | 92 call sites |
| **Type** | System-provided, vector |
| **Current use** | Every icon in the app |
| **Action** | **KEEP.** MASTER ASSET PIPELINE §16 asks explicitly that ordinary UI not get custom raster artwork; that is already the case |
| **Performance** | Free — system cached, Dynamic Type aware, localised, accessible by default |
| **Provenance** | Apple system symbols, used under the standard SDK terms in an Apple-platform app |

---

## 4. Not shipped

| Asset | Location | Purpose | Action |
| --- | --- | --- | --- |
| `icon-source-1254.png` | `docs/design/` | Icon master | **KEEP** — provenance record for the shipped icon |
| `cover.png` | `site/assets/` | Website cover image | **KEEP** — not in the app bundle |

---

## 5. Categories with no assets at all

MASTER ASSET PIPELINE §3 asks for a category sweep. These are the categories
where the answer is "nothing exists", with an honest note on whether that is a
gap.

| Category | Status | Assessment |
| --- | --- | --- |
| **Airport** | No assets | Airports draw as map markers sized by tier. §11 warns against modelling 80 airports; the tiering already exists. **Not a gap.** |
| **Events** | No assets | Events use an SF Symbol plus a semantic tint and a severity band. §13 asks for exactly this. **Not a gap.** |
| **Illustrations** | None | — |
| **Empty states** | No illustrations | `EmptyStateView` is icon + title + message + action. A genuine but low-value gap: the copy is doing the work, and §14 warns against stylistically unrelated illustrations. **P2.** |
| **Onboarding** | No illustrations | Onboarding is a guided first route with real data. **Not a gap** — §15 says use visuals to clarify actions, and the map is the visual. |
| **Backgrounds** | None beyond `aeScreenBackground` | §17 warns against wallpaper. **Not a gap.** |
| **Finance / Economy** | No assets | Charts are drawn from data. **Not a gap.** |
| **Missions** | No assets | **Not a gap.** |
| **Effects / Animation** | `AEMotion` curves, no asset-backed effects | **Not a gap.** |

**The only genuine visual gap in the whole product is aircraft fidelity.**
Everything else the brief lists is either already solved procedurally or would
be decoration.

---

## 6. Provenance summary

| Class | Provenance | Risk |
| --- | --- | --- |
| App icon | Original, source retained | None |
| Audio | Original, generated | None |
| All procedural art | Original, authored as code | None |
| SF Symbols | Apple SDK | None |

**No third-party artwork, no downloaded images, no manufacturer or airline
references anywhere in the project.** Aircraft types, manufacturers, airport
codes and airline names are all fictional. See `docs/ASSET_PROVENANCE.md`.
