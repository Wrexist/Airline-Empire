# Featuring nomination — 1.2 (App Enhancements)

Status: **draft, not submitted.** Source of truth:
[`store/featuring-nomination-1.2.json`](../store/featuring-nomination-1.2.json);
CI checks it against Apple's field limits (`scripts/asc/check-featuring.mjs`).

The 1.0 launch nomination was submitted on 11 September
([`APP_STORE_FEATURING_NOMINATION.md`](APP_STORE_FEATURING_NOMINATION.md)).
This is a **separate** nomination for a separate release — the first update —
with new content of its own: Game Center, route shortcuts and the clearer
briefing. It does not re-nominate the launch.

## When to submit

As soon as the 1.2 publication date is set, and well ahead of it: editors
plan in advance and the nomination is only useful before the release. It
requires a planned date, so it cannot be submitted until one exists — the
JSON deliberately leaves `plannedPublishDate` for the owner.

Nominate **after** 1.1.0 publishes on 16 October, so the nomination describes
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

Only what is new since the approved 1.1.0 (13):

- Seventeen achievements, three leaderboards; ranked by passengers,
  network and fleet, never money; optional, sign-in only on request —
  `GameCenterCatalog.swift`, `GameCenter.swift`, `GameCenterCatalogTests`.
- "Watch your first takeoff", instant map response, the crash fix and the
  VoiceOver / Dynamic Type fixes — PR #39's whole-game audit
  (`docs/GAME_AUDIT_2026-09-25.md`), which records that 1.1.0 (13) is
  untouched and these ship in the next signed build.
- Shared forecast caveats said once — `BriefingView.swift`.

Route management tabs are **not** claimed: check whether they are already
in 1.1.0 before adding them. If any line above changes before 1.2 ships,
change the copy with it. A nomination that describes an update which is not
the one submitted is worse than no nomination.
