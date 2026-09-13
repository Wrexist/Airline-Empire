# Airline Empire — cinematic store collection

Six coordinated App Store images pair original cinematic aviation artwork with genuine native gameplay. Midnight navy, pearl silver and warm gold connect the sequence: ambition, fleet, routes, finance, rivals and progression.

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
