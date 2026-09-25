# Whole-game audit — 25 September 2026

Six read-only audits of the current development line
(`codex/ae049-aircraft-configuration` at `3acbb7a`, merged with `main`'s
privacy-policy commit), then fixes on `claude/game-audit-optimize-a28480`.
Approved build 1.1.0 (13) is untouched: everything here ships in the next
signed build.

| Audit | Scope | Findings |
|---|---|---|
| Core simulation | Systems, session read models, persistence, gating | 12 (4 P1) |
| App shell & persistence | Controller, lifecycle, audio, saves, project config | 14 (1 P0, 3 P1) |
| Monetization & conversion | StoreKit, paywall, gates, timing, copy | 9 correctness + 5 conversion |
| New player experience | First launch → first revenue | 5 bugs + 9 improvements |
| Management screens | Fleet, routes, finance, airports, passengers | 24 (5 P1) |
| World map | Rendering, hit-testing, labels, performance | 16 + label trace |

Status legend: **Fixed** (in this branch), **Follow-up** (deliberately not
changed here, with the reason).

## Crashes and data safety

- **Fixed — audio crash (P0).** The engine stops itself on a hardware route
  change (AirPods, CarPlay) or an interruption without backgrounding; the next
  `AVAudioPlayerNode.play()` raised an Objective-C exception. Every node start
  now checks the real engine state, and the engine recovers (or stays quiet
  after a media-services reset) instead of crashing. A cancelled crossfade no
  longer clears its successor's handle.
- **Fixed — IPA upload gate.** `scripts/inspect-release-ipa.py` demanded
  "Data Not Collected", which every build carrying the RevenueCat Purchase
  History disclosure fails. It now accepts exactly the published label.
- **Fixed — collapsed airline blocks the free save slot.** "Start a new
  airline" on the game-over screen clears the dead save; the simulation
  pauses on game over instead of running and autosaving behind it.

## Monetization and conversion

- **Fixed** — closing a paywall the player opened no longer cancels the
  one-time first-flight offer or spends the nudge budget.
- **Fixed** — unprompted offers wait for prices (no burning the one-time offer
  on "Prices are unavailable" while offline) and are retried on return.
- **Fixed** — the first-flight offer follows the landing itself (it waited
  for the next midnight's milestone pass), with its own headline: "Your first
  flight has landed". It is raised at once — a delayed sheet was measured
  swallowing a tap on the time controls.
- **Fixed** — the era wall appears when National is actually earned, with
  true copy ("National era earned"), instead of for the whole Regional era.
- **Fixed** — the paywall no longer sells two achievements free players earn.
- **Fixed** — the game pauses under any paywall; benefits lead with what was
  tapped; purchase, restore and Ask to Buy are thanked on the game; restore
  ignores a dismissed Apple sign-in; intro eligibility is re-checked on open;
  plan cards lock during a purchase.
- **Fixed** — free players are never *recommended* a city outside the free
  region (tutorial, Home row, map arcs, briefing); locked places stay visible.
- **Follow-up** — Lifetime upgrade for weekly subscribers; Yearly ranked
  above Weekly in the subscription group; pricing test of Lifetime vs Yearly
  (App Store Connect changes, owner decision).

## New player experience

- **Fixed** — "Watch your first takeoff" runs the world to boarding and plays
  at 1×. The first departure was 7.5 real minutes of an empty map away, and
  pressing the old "advance to next morning" row twice skipped the flight.
- **Fixed** — the first-flight guide never returns after a flight has landed.
- **Fixed** — airline names are capped at Core's 40 characters (a longer one
  wiped the whole setup screen).
- **Fixed** — the menu's session recap is cleared on start, load and delete.
- **Fixed** — VoiceOver hears every celebration.

## Performance

- **Fixed** — the controller publishes, invalidates caches and re-checks only
  when the world changed (tick, applied command or new session). It rebuilt
  every read model four times a second, forever while paused.
- **Fixed** — aircraft no longer run ahead and snap back after Control Center
  or a speed change.

## Presentation

- **Fixed** — dates inside sentences read "29 Jan 2035" (the clock headers
  keep ISO, which the UI journeys read); durations read "1h 14m"; money
  rounds into the next unit ("$1.0M", not "$1,000k"); Finance explains the
  normal early-month loss (leases, payroll and overhead bill on the 1st);
  Briefing no longer lists idle aircraft twice; menu music plays.
- **Fixed** — App Store promotional text leads with "Start free".

## Simulation (Core)

- **Fixed — money exploit.** A maintenance check restored an old airframe to
  full condition and the sale was priced from it: buy a 22-year-old MR180 at
  condition 0.56, let the check run, sell three days later at a profit,
  repeat. The sale now prices no better than the used market's condition for
  that age.
- **Fixed — daily cancellations at full utilisation.** The midnight scheduler
  planned from where an aircraft stood, not where its last pending leg lands;
  full-frequency routes lost their first flight every day.
- **Fixed** — aircraft on order no longer age, depreciate or draw payroll; a
  12-month lease takes 12 payments; early loan payoff charges interest for
  the days held; closing a route mid-turnaround keeps the flight's stats;
  strike risk no longer sticks after administration; ferries use the
  aircraft's own type and the reachable end.
- **Fixed — save integrity.** `SaveManager` refuses to write a state the
  loader would reject, so a Release-only invariant break cannot rotate
  through every backup.
- **Follow-up** — maintenance still starts after the day's flights exist
  (they expire as cancellations). Running `FleetSystem` before
  `FlightSchedulingSystem` fixes it but moves four seeded campaign tests
  (`MunichHorizonTests`, `FirstEraCampaignTests`,
  `RivalPressureCampaignTests`, `BalanceTests.archetypeParityAndSanity`),
  whose baselines need a Swift toolchain to regenerate.

## Management screens

- **Fixed** — sell and lease-return confirmations quote Core's real sale
  value and penalty; leases state the first payment due today; buying new
  states the delivery wait; the open-route fare slider reaches long-haul
  fares; forecast panels keep their figures while re-pricing (Apply buttons
  flickered off every tick); Unassign, Close route and Pay off check first
  and say why; dialogs are keyed to their item, not a row position; the
  airport list refreshes after paused actions.
- **Fixed** — idle aircraft open on Operations; the change-aircraft sheet
  names routes; a banner confirms a new aircraft; the market badges the best
  airframe for the route; iPad max widths; money rows stack at accessibility
  sizes; full-word VoiceOver labels; plurals, separators and real dates.
- **Fixed** — refusals read in the player's language everywhere, with
  corrected advice (loans are only repaid whole; "not right now" means a
  maintenance check or an undelivered aircraft) and a Pro refusal that says
  where the free line is.
- **Fixed** — locked airports, aircraft classes and the next chapter offer
  Pro honestly instead of dead-ending.

## World map

- **Fixed** — routes opened, assigned or closed while paused appear at once;
  taps select immediately and one nearest-wins pass picks aircraft, airports
  or labels; the antimeridian no longer cuts airports and aircraft out of
  the Pacific; a handled "view on map" request is cleared; chrome changes no
  longer snap the camera.
- **Fixed — labels.** Codes at world zoom, city names normally, full official
  names only when selected or zoomed in; measured widths and padded boxes;
  country names avoid markers and labels.
- **Fixed — frame cost.** Geography no longer rebuilds every game hour (only
  the night layer); per-frame chrome, allocations and double label layout
  removed; the timeline pauses under sheets and in the background.
- **Fixed** — arrivals keep their heading; the selection is panned into view
  and always drawn; follow ends when something else is tapped.

## Follow-ups (not changed here)

- Launch-screen colour key in `project.yml`
  (`INFOPLIST_KEY_UILaunchScreen_BackgroundColor` may not be honoured) —
  needs a macOS build to confirm with `plutil -p`.
- App target Swift language mode is not pinned to 6.
- Campaign import reads and decodes on the main thread.
- Saves do not record the content version; players never see their own
  aircraft sales in the feed; tourism-mission progress can regress after a
  route is closed.
