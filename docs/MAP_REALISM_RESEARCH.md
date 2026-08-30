# Making the map real — research

**Question:** can the map be made ultra-realistic, or actually real? Is there
an asset or library we can use?

**Answer: yes, and the blocker recorded in the code no longer exists.**
Researched 2026-08-30 by fetching and measuring the data, not by reading about
it.

---

## 1. What the map is today

Established from the source, not assumed:

| | |
| --- | --- |
| World | **Real Earth.** Real latitude/longitude, hand-traced |
| Coastlines | **631 coordinate pairs across 16 polygons** |
| Airports | **80, at real airport coordinates** |
| Rendering | Procedural `Path`/`GraphicsContext`, no assets, no network |
| Palette | Fixed near-black, deliberately narrow value range |

The airports are the part worth dwelling on. They are not city centres — they
are the actual fields:

| Airport | In game | Really |
| --- | --- | --- |
| Stockholm | 59.65, 17.92 | Arlanda |
| London | 51.47, −0.45 | Heathrow |
| Paris | 49.01, 2.55 | Charles de Gaulle |
| New York | 40.64, −73.78 | JFK |
| Tokyo | 35.55, 139.78 | Haneda |
| Sydney | −33.95, 151.18 | Kingsford Smith |

**So the mismatch is precise data on imprecise geography.** Eighty real
airports are plotted to a few metres, on a coastline where Europe is a few
dozen points. Better geography does not just look better — it stops airports
sitting visibly off their own coasts.

## 2. The blocker in the code has expired

`WorldGeometry.swift` says why it is hand-traced:

> *"It is hand-authored rather than imported: **the environment has no network
> access to fetch Natural Earth**, and a coarse hand trace that ships beats an
> accurate one that does not."*

That was a correct decision under that constraint. The constraint is gone —
the data fetches fine now. Verified by downloading it.

---

## 3. Options, measured

### Option A — Natural Earth vectors ✅ **recommended**

Public domain (verified at naturaledata.com/about/terms-of-use: *"all Natural
Earth data is in the public domain… no permission is needed"*, commercial use
explicit, attribution optional). Fetched and measured:

| Source | Simplify | Polygons | Points | ≈ Swift source |
| --- | --- | --- | --- | --- |
| **current hand trace** | — | 16 | **631** | 12 KB |
| 110m land | none | 127 | 5,091 | 99 KB |
| 110m land | 0.3° | 117 | 2,375 | 46 KB |
| 50m land | 0.15° | 575 | **8,697** | 170 KB |
| 50m land | 0.3° | 282 | 4,308 | 84 KB |
| 50m land | none | 1,421 | 60,278 | 1.2 MB |

**50m simplified at 0.15° is the sweet spot: ~14× the current detail for
170 KB.** For comparison, the app already ships 8.4 MB of uncompressed audio.

Other layers, all public domain, all fetched successfully:

| Layer | Size | Why it matters |
| --- | --- | --- |
| `ne_110m_admin_0_countries` | 820 KB | Borders at low opacity are what make a dark map read as *Earth* rather than as blobs |
| `ne_110m_lakes` | 36 KB | Caspian, Great Lakes, Baikal, Victoria. Their absence is conspicuous — a lake-shaped hole in Africa is more noticeable than a missing fjord |
| `ne_50m_lakes` | 856 KB | Regional zoom |
| `ne_110m_rivers_lake_centerlines` | 38 KB | Probably too much; rivers compete with routes |

**Why this fits.** It is the same `[[MapPoint]]` structure the renderer
already consumes — more points, nothing else changes. No dependency, no
network at runtime, no asset files, still tintable, still theme-adaptive,
still deterministic, and the antimeridian and projection work already done
keeps working.

### Option B — MapKit (a genuinely real map) ❌

Technically the most "real" option, and the wrong one here. Four reasons, in
order of severity:

1. **The app makes zero network calls today.** That is declared: `project.yml`
   sets `ITSAppUsesNonExemptEncryption: NO` with the comment *"it makes no
   network calls at all"*, and the privacy manifest is built on it. MapKit
   fetches tiles. That changes the App Store declarations, adds a privacy
   surface, and gives a game that currently works offline on a plane a way to
   fail on a plane.
2. **The labels contradict the game.** Stockholm is `STV` here, London is
   `LNW`. A real map captioned "Stockholm" beside a marker captioned "STV"
   breaks the fiction in the one place the player looks most.
3. **The custom projection is lost**, and with it the antimeridian handling —
   solved, tested, and not trivial.
4. **It cannot be styled** to the dark operations-centre palette beyond
   MapKit's own map types.

### Option C — Satellite / photographic raster (NASA Blue Marble et al.) ❌

Public domain imagery exists and would give a photographic Earth. It fights
the design rather than serving it.

`MAP_ARCHITECTURE.md` §2 sets the rule the whole map is built on: the geography
sits *"inside a narrow, dark band so it can never compete with the network
drawn over it."* A photographic Earth does precisely the opposite — it is the
most visually dominant thing that could be put on the screen, under the routes
that are the actual subject.

Also: a raster cannot be tinted per theme, blurs or bloats on zoom (a decent
world texture is 8–20 MB), and would have to be re-authored for dark and light.

**It would photograph better and play worse.** That trade is worth stating
plainly rather than discovering after the work.

### Option D — Terrain relief shading 🤔 later

Natural Earth also ships public-domain shaded-relief and bathymetry rasters.
A very low-contrast relief layer under the vectors adds a real sense of
landmass without the labels or the dominance problems. Real, but a refinement
after Option A, not instead of it.

---

## 4. Recommendation

**Option A, in two stages.**

1. **Coastlines + lakes.** Replace `WorldGeometry.outlines` with Natural Earth
   50m simplified to ~0.15°, plus 110m lakes. One file changes; the renderer,
   the projection and the palette are untouched. Benchmarkable with the
   `ae-map-bench` target that already exists.
2. **Country borders**, drawn at very low opacity beneath the routes. This is
   the single biggest "that's Earth" cue after coastlines, and it is what
   currently makes the map read as abstract.

Deliberately **not** recommended: rivers (they compete with route lines),
50m unsimplified (1.2 MB and 60k points for detail invisible on a phone), and
anything raster.

**Attribution.** Not required. *"Made with Natural Earth."* in the credits is
the courtesy the project asks for, and costs nothing.

---

## 5. What would need checking during implementation

Stated up front because the honest answer to "will it look better" is that
nobody can know until it is rendered:

- **Frame cost at world zoom.** 8,697 points versus 631 is a real increase.
  `ae-map-bench` measures the map model; the renderer's own cost needs a look
  on a device or in the simulator.
- **Whether more coastline crowds the network.** MAP_ARCHITECTURE's rule is
  that geography must not compete. 14× the detail is exactly the kind of change
  that could break that rule, and the fix would be palette rather than fewer
  points.
- **Antimeridian.** Natural Earth polygons cross ±180°. The existing handling
  was written for hand-traced outlines and needs re-checking against real data,
  which has islands sitting on the seam.
