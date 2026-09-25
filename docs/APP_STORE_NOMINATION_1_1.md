# Featuring nomination — 1.1 (App Enhancements)

Status: **draft, not submitted.** Source of truth:
[`store/featuring-nomination-1.1.json`](../store/featuring-nomination-1.1.json);
CI checks it against Apple's field limits (`scripts/asc/check-featuring.mjs`).

The 1.0 launch nomination was submitted on 11 September
([`APP_STORE_FEATURING_NOMINATION.md`](APP_STORE_FEATURING_NOMINATION.md)).
This is a **separate** nomination for a separate release — the first update —
with new content of its own: Game Center, route shortcuts and the clearer
briefing. It does not re-nominate the launch.

## When to submit

As soon as the 1.1 publication date is set, and well ahead of it: editors
plan in advance and the nomination is only useful before the release. It
requires a planned date, so it cannot be submitted until one exists — the
JSON deliberately leaves `plannedPublishDate` for the owner.

Nominate **after** 1.0 publishes on 16 October, so the nomination describes
an app editors can already open.

## Fields (paste into App Store Connect → Distribution → Nominations → +)

Type: **App Enhancements**. Platforms: iOS (iPhone), iOS (iPad).
Localisations: English (U.S.), English (U.K.). Pre-order: No.
In-App Event: attach **Game Center Arrives** once it exists
([`APP_STORE_IN_APP_EVENT.md`](APP_STORE_IN_APP_EVENT.md)).

**Name** (57/60)

```text
Airline Empire: Game Center achievements and leaderboards
```

**Description** (895/1000) and **Helpful details** (363/500): copy from the
JSON, which is what CI measures.

**Supplemental material**

```text
https://wrexist.github.io/Airline-Empire/press.html
```

## Every claim is a shipped fact

- Seventeen achievements, three leaderboards: `GameCenterCatalog.swift`, and
  the tests in `GameCenterCatalogTests.swift`.
- Leaderboards rank passengers, network, fleet — never money: same file.
- Optional, sign-in only on request: `GameCenter.swift`.
- Fares and aircraft one tap from every route, with VoiceOver focus:
  `RoutesView.swift` (`manageRow`).
- Shared caveats said once: `BriefingView.swift`, `OperationsView.swift`.

If any of those changes before 1.1 ships, change the copy with it. A
nomination that describes an update which is not the one submitted is worse
than no nomination.
