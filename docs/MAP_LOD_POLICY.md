# Map zoom LOD policy — AE-034

> One table for "what exists at this zoom", collected from the code that
> enforces it, so the next change to any tier is made against the whole
> picture rather than one file. Sources: `MapZoomLevel`, `MapDetailPolicy`,
> `MapLabelLayout`, `WorldGeometry`, `CountryLabels`, `MapRenderCache`.

## 1. The tiers

`MapZoomLevel` is what the map is *for* at a magnification: **world**
(< 2.6×), **regional** (2.6–6×), **local** (> 6×). Zoom runs 1–16×.

| | World | Regional | Local |
| --- | --- | --- | --- |
| Geography source (Natural Earth) | 110m — 103 polys / 2,384 pts | 50m — 314 / 6,950 | 10m — 1,084 / 28,937 |
| Borders | dashed hairline | 0.7 pt | 0.9 pt |
| Airports drawn | major+ (player's always) | regional+ | all |
| Airport label reveal (tier ≥) | global (0×) | major (2.8×), regional (5.0×) | small (8.0×) |
| Label budget | 6–~11 (cap 10) | grows 3/zoom (cap 32) | up to 30 (cap 32) |
| Label text | code only | full name → city → code ladder | full name ladder |
| Country labels | ≤ 10, by Natural Earth `MIN_LABEL` rank | ≤ 18 | ≤ 18, larger type |
| Aircraft | directional wedges, 9 pt | silhouettes, 13 pt | silhouettes, larger |
| Rival aircraft at 16× | hidden | shown | shown |
| Rival route opacity | 16% | 30% | 42% |
| Marker radius base (global/major/regional/small) | 4.4 / 3.5 / 2.6 / 2.0 pt × gentle zoom gain | same | same |

Invariants that hold at every tier: the player's own network is never
hidden; closed airports always draw; the selected thing always draws and
labels.

## 2. When transitions are evaluated

This is the AE-034 change. The *content* of each tier is untouched from
AE-033; **when** the map re-decides is now deliberate:

- Geography swaps its source exactly at the tier boundary (a counted cache
  rebuild, `lod`).
- Label reveal/budget/ladder decisions run at settle points, tier changes,
  ticks, and ±25% zoom drift — not per frame — with hysteresis so the
  boundary cannot flicker (a label keeps a 0.4-zoom grace on its reveal
  threshold; viewport enter/exit margins differ by 20 pt).
- Between decisions, everything on screen moves rigidly with the camera:
  the map never appears to rebuild itself mid-gesture.

## 3. Judgment calls, so they are not re-litigated by accident

- **Tier boundaries at 2.6 and 6.0** predate this phase and are kept: they
  sit just outside the label thresholds (2.8, 5.0) so a tier swap and a
  label reveal never land on the same frame of a zoom.
- **The ladder degrades text before it drops labels** ("Charles de Gaulle
  (Paris)" → "Paris" → "CDG"): a shorter true name beats a missing one.
- **World zoom is a command picture, not a directory** — the budget starts
  at 6 deliberately; density is the thing AE-033's design review asked for
  and run 84's frames confirmed.
