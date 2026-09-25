# Screenshots

The app itself, full screen, from one simulated campaign — with a compact
caption band at the top. English artwork is supplied for both en-US and en-GB.

App Review **rejected version 1.0** under Guideline 2.3.3: the majority of each
screenshot has to be the app in use, and marketing or promotional material that
does not reflect the UI is not appropriate. The set is therefore composed
app-dominant (`scripts/store-art/build.cjs --native`): the native capture is
full-bleed at its native aspect and nothing is drawn over it except the caption
band, which is under a tenth of the canvas. The decorative illustration set is
kept in [`../artwork/cinematic/`](../artwork/cinematic/) but is no longer part
of the listing.

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
- **The app is the majority of the image** (Guideline 2.3.3). No illustration,
  no promotional proof line, no crop that hides the screen.
- Nothing on screen the app cannot actually do.

The caption band names Pro gameplay; the UI is scaled and cropped from native
captures, never regenerated. Numbers in UI are actual simulation results, not a
promise of what every player will earn. Upload only the six ordered PNGs per
slot, not the overview sheets or manifests. The 18 unique exports are reused for
the two English locales. Re-run `node scripts/store-art/verify.cjs` after any
regeneration.

See [artwork provenance and reproduction](../artwork/README.md).
The six shots, what each one has to prove, and the captions:
[`docs/ASO.md`](../../docs/ASO.md) §5.
