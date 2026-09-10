# Airline Empire — premium aviation screenshot collection

## Creative direction

Player ambition first; genuine gameplay as the evidence. Deep navy, electric
blue, warm amber, alternating light canvases, large editorial headlines and
subtle route lines create a cohesive six-frame story. The iPad compositions
use native iPad content crops rather than enlarged phone screenshots.

An image-generation study was used to explore art direction. It is not a
shipping screenshot. Every shipping gameplay image embeds original simulator
PNG pixels, with only cropping and uniform scaling. The first phone design
uses two clearly separated excerpts from the same screen: the route map and
the campaign statistics. No UI, cash, routes,
aircraft, achievements or competitor results are invented or retouched.

## Provenance

- Production baseline: merged PR #22, `8b95b1928a14151782f2f37210725e1a06618ea4`.
- Capture source commit: `cd302216728ee6d43632d6252835de0c446d5619`.
- [Passing native capture run](https://github.com/Wrexist/Airline-Empire/actions/runs/34281676647): iPhone 17 Pro Max and iPad Pro 13-inch, iOS 26.2, Xcode 26.2.
- Both device journeys produced all ten required source images.
- Both used byte-identical campaign saves, paused at 2035-01-01 12:00.
- Seed 2039; Campaign Air, Stockholm hub; five years advanced through ordinary
  simulation commands. The probe acquires and assigns real aircraft and routes.
- The DEBUG-only UI fixture enables Pro for the session; the release app and
  real purchase entitlement are not changed.
- `captures/` retains ten original captures per device, SHA-256 manifests,
  the generated save and the simulation ledger.
- Each locale's `export-manifest.json` records native source hashes, exact crop
  rectangles, exported dimensions, file sizes and SHA-256 checksums.

Facts in marketing copy are checked against `airports.json` (94 airports),
`aircraft.json` (14 aircraft types), `AIArchetype` (five personalities) and
`Era` (five progression eras). The geometric background uses the same
public-domain Natural Earth outlines as the game's `WorldGeometryData.swift`.

## Reproduce

Run the **Store screenshots** workflow to create new native sources. Download
both `store-captures-*` artifacts; place their device folders in `captures/`.
The campaign is generated with:

```sh
swift run --package-path AirlineEmpireCore -c release ae-rival-probe 2039 1825 ARN LHR-CDG:0.88 --snapshot-hour 12 --save store/artwork/captures/store-campaign.json
```

The editable composition and copy live in `scripts/store-art/build.cjs` and
`scripts/store-art/storyboard.json`. Rendering requires Node.js, `sharp` and
the Nimbus Sans fonts from the URW Base 35 font family. No network, Apple
credentials or image-generation call is used during artwork rendering.

```sh
npm install --prefix scripts/store-art
node scripts/store-art/build.cjs store/artwork/captures store/screenshots/en-US
node scripts/store-art/verify.cjs
node scripts/asc/selftest.mjs
node scripts/asc/validate-metadata.mjs --allow-placeholders
```

English wording is shared by en-US and en-GB. Copy the generated display-type
directories and manifest to en-GB after any render. Open each full-size image
and the gallery overview before upload. Hashes and dimensions alone cannot
prove that a chosen crop is visually appropriate.

The font must be installed when reproducing; the SVG embeds PNGs, not fonts.
Apple accepts the final raster PNGs, so no font installation is needed to
upload them. Simulator/system overlays are excluded by intentional crops.

## Submission

Upload only the six ordered PNGs per device slot from `store/screenshots/`.
Native sources and overview sheets are supporting material, not upload assets.
PR #23 was merged on 10 September. Screenshot uploads and contact completion
are recorded in `docs/APP_STORE_HANDOFF_STATUS.md`; App Review, fresh build
and physical-device acceptance remain separate release requirements.
Apple's [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
were checked on 2026-09-08.
