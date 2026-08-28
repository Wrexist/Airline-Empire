# `store/` — the App Store listing, as files

Everything App Store Connect shows about the app, kept in version control:
the copy, the categories, the review contact, and (when they exist) the
screenshots.

```
config.json                     non-localised settings — bundle id, categories,
                                release type, review contact, required canvases
metadata/en-US/*.txt            one file per field, one directory per locale
metadata/en-GB/*.txt
metadata/review/notes.txt       what App Review reads before opening the app
screenshots/<locale>/<TYPE>/    NN-name.png, uploaded in filename order
```

The field files map one-to-one onto App Store Connect's own fields — the
mapping table is in the header of `scripts/asc/push-metadata.mjs`. The layout
deliberately matches fastlane `deliver`'s, although nothing here uses fastlane:
it is the layout every iOS engineer already recognises, and it keeps the option
of swapping the tooling without moving a word of copy.

## Why it is here rather than in a web form

A listing is content, and it gets reviewed, diffed and rolled back like any
other content. In a textarea it has no history, no review and no way back;
here, reverting a commit and re-running the workflow restores the previous
listing exactly.

## Working on it

```sh
node scripts/asc/validate-metadata.mjs --allow-placeholders   # what CI runs on a PR
node scripts/asc/validate-metadata.mjs                        # what a release requires
```

The validator prints the character budget per locale — `keywords 94/100` is the
number you actually want while editing — and fails on anything Apple would
reject: an over-long field, a space after a comma in the keyword list, a
duplicate keyword, a third-party trademark, a non-https URL, a screenshot with
an alpha channel or a canvas Apple does not accept.

`REPLACE_ME` marks a value only the Apple account holder can supply. It is a
warning on a pull request and an error on a release, so the tree can be
complete and reviewable today while a real submission stays blocked until those
values are real.

Changing any of this copy means regenerating the fill-in sheet:

```sh
node scripts/asc/build-fill-in-sheet.mjs
```

That writes [`docs/APP_STORE_CONNECT_FILL_IN.md`](../docs/APP_STORE_CONNECT_FILL_IN.md),
the page a human pastes from. CI fails when it is stale, because a listing
that disagrees with the sheet means the wrong version reaches the store.

**Why each word is the word it is:** [`docs/ASO.md`](../docs/ASO.md).
**How it reaches Apple:** [`docs/RELEASE_PIPELINE.md`](../docs/RELEASE_PIPELINE.md).
