# Screenshots

Six cinematic designs combine original 3D-style aviation illustrations with
genuine iPhone and iPad gameplay from one simulated campaign. English artwork
is supplied for both en-US and en-GB.

## Layout

```
screenshots/<locale>/<APP_STORE_CONNECT_DISPLAY_TYPE>/01-map.png
```

The directory name is the App Store Connect `screenshotDisplayType` enum value
and is passed to the API verbatim — no mapping table in this repository can go
stale that way. The two required today, from `config.json`:

| Directory | Canvas | Device |
|---|---|---|
| `APP_IPHONE_67` | 1320×2868 (or 1290×2796) | iPhone 6.9" / 6.7" |
| `APP_IPHONE_65` | 1242×2688 | iPhone 6.5" (additional export) |
| `APP_IPAD_PRO_3GEN_129` | 2064×2752 (or 2048×2732) | iPad 13" / 12.9" |

Sizes read off Apple's screenshot specification on 2026-09-08. Apple revises
them most years and a guessed dimension is a rejected submission — re-verify
before the first upload.

Files upload in **filename order**, which is the order they appear on the
product page, so the numeric prefix is the storyboard.

## Rules

- PNG, **no alpha channel** (Apple rejects transparency; the validator catches it first).
- At most ten per display type per locale.
- Captured from a **real mid-game world**, one seed, one airline, across all six.
- Caption text legible at gallery-thumbnail size.
- Nothing on screen the app cannot actually do.

The artwork identifies Pro gameplay and labels the aviation art as illustrative.
Numbers in UI are actual simulation results, not a promise of what every player
will earn. UI is cropped and uniformly scaled from native captures, never
regenerated. Upload only the six ordered PNGs per slot, not the overview sheets
or manifests. The 18 unique exports are reused for the two English locales.
This collection was uploaded to App Store Connect version 1.0 on 13 September
2026. All 36 files across both English locales and all three display types
passed remote checksum, order and COMPLETE-processing verification in
[run 34784324536](https://github.com/Wrexist/Airline-Empire/actions/runs/34784324536).
The upload did not submit or publish the app.

See [artwork provenance and reproduction](../artwork/README.md).
The six shots, what each one has to prove, and the captions:
[`docs/ASO.md`](../../docs/ASO.md) §5.
