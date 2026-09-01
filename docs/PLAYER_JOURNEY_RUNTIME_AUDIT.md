# Player journey runtime audit — AE-033/AE-034

> What a new player actually sees, step by step, on a booted iPhone 16 Pro
> simulator (iOS 26) — every claim below is **OBSERVED** from decoded CI
> screenshots of run 84 (the journey test that also carried the perf
> baseline) unless marked otherwise. Companion: `PLAYER_JOURNEY.md` (the
> design intent this is checked against).

## 1. Method, honestly

The journey UI test (`testFullPlayerJourney` + shell/layout/appearance
tests, 16 tests total) drives: launch → new game (ARN home) → Market →
lease a Pacifica PA-184 → Fleet → open route ARN–LHR → assign aircraft →
un-pause at 16× → first flight airborne → inspect every tab and detail
screen → home. 44 keyframes are exported per run and decoded locally.
This audit LOOKED at every frame; it did not merely check that tests
passed. What a static frame cannot prove (animation smoothness, gesture
feel, audio) is listed in §5 as not validated.

## 2. The journey, step by step (all OBSERVED)

| # | Step | Frame | Verdict |
| --- | --- | --- | --- |
| 1 | Launch → Home | KEY-20/KEY-01 | Clean. Speed pill, date/net-worth banner, "Get your airline flying" checklist with 5 concrete steps, stat tiles. No dead space. |
| 2 | Onboarding checklist | KEY-01 | Steps name the exact path ("Airline tab → Fleet → Acquire"). First unchecked step highlighted. Good. |
| 3 | Market sheet | KEY-02 | Sort chips, era-lock chips ("later era" with padlock), terms steppers, per-model guidance prose. Readable. |
| 4 | Lease confirm → owned | KEY-03 | Cash reflects lease immediately. |
| 5 | Fleet with aircraft | KEY-04 | Row correct (status, condition, lease cost) but ~60 % of the screen is empty below one row, and the 7-metric summary strip is heavy for a 1-aircraft fleet (§4, JRN-02). |
| 6 | Route sheet, destination picked | KEY-06 | Demand, distance, fare, frequency stepper all visible pre-commit. Good decision surface. |
| 7 | Routes with route | KEY-07 | "⚠ no aircraft" caution chip is the right nudge; same dead-space/strip-weight note as Fleet (JRN-02). |
| 8 | Assign + un-pause | KEY-80/85 | Route gains aircraft; clock advances at 16×; speed pill state matches. |
| 9 | First flight on map | KEY-81 | Aircraft silhouette mid-route with gradient trail between London and Stockholm; labeled markers; network line under it. The payoff moment reads well. |
| 10 | Flight close-up | KEY-82 | At regional zoom the flight, trail, and both endpoint labels hold up. One clipped label at the right edge (JRN-05). |
| 11 | Finance tab | KEY-23 | Pre-first-month states are written in plain language ("No month has closed yet…"). Honest empty states, not blank panels. |
| 12 | World tab | KEY-24 | Four navigation cards + fuel/economy ticker; lower half of the screen is empty (JRN-03). |
| 13 | Aircraft detail | KEY-90 | Assignment warning ("Idle at ARN. It earns nothing here, and a leased aircraft still bills.") is the best line of UX writing in the game. Condition/ownership sections complete. |
| 14 | Route detail | KEY-91 | Operations, market, competition, money sections all present pre-flight with honest zeros. |
| 15 | Settings | KEY-92 | Grouped, explained ("Fast-forward stops itself when your airline drops below the overdraft floor…"). |
| 16 | Dark mode | KEY-50–54 | All five tabs correct; no white flashes (status-bar bleed was fixed and re-verified by pixel medians in the AE-032 arc). |
| 17 | Dynamic Type XXL | KEY-95–97 | Text wraps, nothing truncates; market sheet content scrolls beneath the sheet header with no fade (JRN-06, cosmetic). |

## 3. What the journey gets right

- **Every empty state teaches.** Finance, Routes, Fleet, and the aircraft
  detail all explain what will happen and what to do, instead of showing
  a blank panel.
- **The checklist names real UI paths** and the caution chips ("no
  aircraft") carry the same vocabulary the checklist used.
- **The first-flight payoff exists**: within one un-pause the player sees
  their aircraft moving on the map with a trail, and the Home stats flip
  from em-dashes to numbers.

## 4. Findings (ranked; JRN-ids referenced by GAME_EXPERIENCE_PRIORITY.md)

- **JRN-01 (P2) — Home dead space in the mid-game frame.** Between the
  checklist and the stat tiles the composition is fine at game start, but
  the tiles answer "how big am I" while nothing on Home answers "what
  should I do next" once the checklist completes. (READ from
  DashboardView; the post-checklist state was not itself screenshotted —
  NOT VALIDATED beyond code reading.)
- **JRN-02 (P2) — Fleet/Routes summary strips outweigh their lists at
  small scale.** 7 metrics over one row, then ~60 % empty. The strip
  earns its place late-game; early it reads as chrome. OBSERVED
  (KEY-04, KEY-07).
- **JRN-03 (P3) — World tab bottom half empty.** Four cards + ticker,
  then nothing. OBSERVED (KEY-24).
- **JRN-04 (P3) — World-zoom map letterbox.** At 1× the world band plus
  the coach-mark card leaves a large black field above the map. OBSERVED
  (KEY-71). Cheap framing win: bias the band toward the visible center
  while the coach card is up.
- **JRN-05 (P3) — Edge-clipped labels.** A label whose marker sits near
  the screen edge can show cut text ("Langnes (Tro…", "BELA…" country
  label, and a bottom label under the tab bar). OBSERVED (KEY-82,
  KEY-51). Airport label placement clamps to the viewport; country labels
  and markers just offscreen do not.
- **JRN-06 (P3) — Sheet content scrolls behind the header without a
  fade** at XXL Dynamic Type. OBSERVED (KEY-97). Cosmetic.

## 5. Not validated (stated, per the honesty rules)

- Gesture *feel* (inertia, pinch anchoring) — frames prove end states,
  not motion. Needs a hand on a device.
- Audio/haptics — CI proves the engine starts (`engineIsRunning`), not
  that anything is heard or felt.
- The post-checklist Home state, a month-end statement, an era change,
  and any celebration overlay — the scripted journey ends before these
  occur, so no frame exists. Code paths exist (READ), runtime unproven.
- Device frame rate — all timing numbers in `MAP_RUNTIME_BASELINE.md` /
  `MAP_P0_PERFORMANCE_REPORT.md` are simulator measurements.
