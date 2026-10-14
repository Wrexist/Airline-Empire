# Screenshots

The app itself, from one simulated campaign, in portrait: 9:16 on iPhone and
3:4 on iPad. English artwork is supplied for both en-US and en-GB.

App Review **rejected version 1.0** under Guideline 2.3.3: the majority of each
screenshot has to be the app in use, and marketing or promotional material that
does not reflect the UI is not appropriate. The set is therefore composed
app-dominant (`scripts/store-art/showcase.cjs`): every pixel inside a device
frame, callout or panel is a native capture, cropped and uniformly scaled.
The only drawn content is the headline, the frames, the labels and the
background. The decorative illustration set is
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

**1.2.1 set (ten shots, all portrait).** Two layouts alternate
(`scripts/store-art/showcase.json`):

- **hub** (01, 03, 06, 09) — the 3D Hub View as it plays, an iPhone (or iPad)
  turned on its side, over two to three large cut-aways from other hub
  moments: the gate turnaround, the terminal, construction, night, insights.
  The hub frames are `hub-*.png`, from `Hub view review` run 38348801758,
  turned upright.
- **phone** (02, 04, 05, 07, 08, 10) — one gameplay screen in a device frame
  with a magnified callout from the same campaign (the aircraft market, the
  routes board, the daily briefing, world events). Re-captured for 1.2.1
  from main `0b7809f` (Store screenshots run 38585649823).

The hub runs landscape on iPhone, so it is shown in a landscape device rather
than re-captured upright: nothing on the page is a screen the player cannot
see.

## Rules

- PNG, **no alpha channel** (Apple rejects transparency; the validator catches it first).
- At most ten per display type per locale (the 1.2 set uses all ten).
- Captured from a **real mid-game world**, one seed, one airline, across all ten.
- Caption text legible at gallery-thumbnail size.
- **The app is the majority of the image** (Guideline 2.3.3). No illustration;
  every claim in a headline is checked against the game by `verify.cjs`.
- Nothing on screen the app cannot actually do.

The UI is scaled and cropped from native captures, never regenerated. Numbers
in UI are actual simulation results, not a promise of what every player will
earn. Upload only the ten ordered PNGs per slot, not the overview sheets or
manifests. The 30 unique exports are reused for the two English locales.

```sh
npm ci --prefix scripts/store-art --ignore-scripts
node scripts/store-art/showcase.cjs store/artwork/captures store/screenshots/en-US
# copy the three display directories and export-manifest.json to en-GB, then
node scripts/store-art/verify.cjs && node scripts/store-art/overview.cjs
```

See [artwork provenance and reproduction](../artwork/README.md).
What each shot has to prove, and the captions:
[`docs/ASO.md`](../../docs/ASO.md) §5.
