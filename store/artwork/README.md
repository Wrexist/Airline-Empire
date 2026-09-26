# Airline Empire — cinematic store collection

> **Not used by the App Store listing.** App Review rejected version 1.0 under
> Guideline 2.3.3 because the majority of each screenshot was decorative
> illustration rather than the app in use. The listing is now composed
> app-dominant by `scripts/store-art/build.cjs --native` — see
> [`../screenshots/README.md`](../screenshots/README.md). This collection is
> kept as the source of the artwork and the cinematic composition path, and
> `build.cjs` without `--native` still renders it for non-store use.

Six coordinated images pair original cinematic aviation artwork with genuine native gameplay. Midnight navy, pearl silver and warm gold connect the sequence: ambition, fleet, routes, finance, rivals and progression.

The artwork was generated with the built-in image_gen tool. It is decorative marketing illustration, not 3D gameplay or an asset added to the game. Every final image clearly identifies the actual gameplay panel and Pro content. Captures are embedded as original pixels with only cropping and uniform scaling; no numbers, aircraft, achievements or UI are invented or retouched.

## Editable sources

- scripts/store-art/build.cjs: vector composition, native-pixel placement and export.
- scripts/store-art/storyboard.json: six headlines, copy and source crops.
- cinematic/: six original 3D-style artwork PNGs and the generation prompt set.
- captures/: native iPhone/iPad screenshots, manifests and earned campaign save.
- Each locale export manifest records output, native capture and artwork SHA-256 hashes.

## Export

```sh
npm ci --prefix scripts/store-art --ignore-scripts
node scripts/store-art/build.cjs store/artwork/captures store/screenshots/en-US
```

Copy the three output display directories and export manifest to en-GB, then run:

```sh
node scripts/store-art/verify.cjs
node scripts/store-art/overview.cjs
node scripts/asc/validate-metadata.mjs --allow-placeholders
```

The composition uses Arial with Helvetica/sans-serif fallback. Reproduction requires Node and the pinned sharp dependency; no image generation or Apple credential is needed to render the saved artwork.

Exports: six ordered RGB PNGs for each of 1320×2868, 1242×2688 and 2064×2752. English wording is shared by en-US and en-GB, giving 18 unique images and 36 upload files. The overview JPEGs are review material, not upload assets.

Apple [screenshot sizes](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) and [accurate metadata guidance](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata) were checked on 13 September 2026. Native capture provenance and final visual review are recorded in capture-review.json.

## App Store Connect upload

Uploaded to Airline Empire: Flight Tycoon (6806410538), iOS listing version 1.0,
on 13 September 2026. [The upload run](https://github.com/Wrexist/Airline-Empire/actions/runs/34784324536)
changed screenshots only. All 36 source checksums, six ordered sets and Apple's
COMPLETE processing states were verified; see [verification report](upload-verification.json).

**That uploaded set was rejected and is superseded.** App Review rejected
version 1.0 on 17 September 2026 under Guideline 2.3.3 — the set was
cinematic artwork with a minority of app UI. The repository now holds an
app-dominant set rendered from re-captured screens
([35191948365](https://github.com/Wrexist/Airline-Empire/actions/runs/35191948365)),
and `upload-verification.json` carries a `supersededBy` note. The live listing
keeps the rejected images until the next `screenshots_only` apply run replaces
them.

The version was removed from its unsubmitted review draft to unlock screenshot
editing. The open page subsequently showed build 1.0.21 (10) selected and
concurrent unsaved listing edits. Those edits were left intact, with the version
in Prepare for Submission. No review submission or publication was performed.
