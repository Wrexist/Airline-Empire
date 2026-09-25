# In-App Event — Game Center Arrives (1.1)

Status: **spec and media ready; not created in App Store Connect.**
Source of truth: [`store/in-app-events/game-center/event.json`](../store/in-app-events/game-center/event.json).
Limits are checked in CI by `scripts/asc/check-featuring.mjs`.

## Why this event, and why not a "launch week" one

An In-App Event has to be something **happening inside the app** for a
bounded time. A 1.0 "launch week" event has nothing in the app that changes
during that week — it would be an advertisement for the launch, which is the
kind of event App Review turns away, and the launch already has its
nomination and pre-order.

The 1.1 update is different: Game Center is genuinely new, and **Major
Update** is the badge Apple provides for exactly that. It gives the update a
card in search, on the product page and in editorial surfaces, and it can be
attached to the 1.1 featuring nomination.

## Fields

| Field | Value | Limit |
|---|---|---|
| Reference name | 1.1 Game Center arrives | 64 |
| Badge | Major Update | — |
| Event name | Game Center Arrives | 30 (19) |
| Short description | 17 achievements and three leaderboards to climb | 50 (47) |
| Long description | Every milestone your airline reaches now counts in Game Center. Compare passengers, network and fleet with friends. | 120 (115) |
| Purchase requirement | None — Game Center is in the free game | — |
| Priority | High | — |
| Deep link | None; opens the app | — |
| Territories | Same 173 as the app | — |
| Localisations | English (U.S.), English (U.K.) — identical copy | — |

## Media

| Slot | File | Size |
|---|---|---|
| Event card (16:9) | `store/in-app-events/game-center/event-card.png` | 1920×1080 |
| Details page (9:16) | `store/in-app-events/game-center/details-page.png` | 1080×1920 |

Rendered by `node store/in-app-events/game-center/render.mjs` from the
listing's existing text-free key art and the release's actual achievement
medallions. No words in either image: App Store surfaces lay the event name
over and beside the media. The medallions sit in the top of the frame, clear
of the aircraft and of the lower band where the name is overlaid.

## Schedule (owner decides)

- **Event start:** the day 1.1 is live. The event must describe what is in
  the live version, so it cannot start before the update is released.
- **Promotion start:** up to 14 days before the event start.
- **Duration:** 14 days proposed (Apple allows up to 31).
- **Submit** the event for review with, or after, the 1.1 version.

## Before submitting

1. 1.1 approved (or submitted alongside) with Game Center configured
   ([`GAME_CENTER.md`](GAME_CENTER.md) §3).
2. Open both images at full size once more; confirm nothing important is
   near the edges.
3. Attach the event to the 1.1 nomination.
