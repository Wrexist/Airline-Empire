# The first era — runtime audit (AE-035 "The First Era")

> Evidence ledger for the campaign from month two to the first era gate.
> Labels: MEASURED / OBSERVED / READ / AUTHORED / NOT VALIDATED.
> Companions: `FIRST_MONTH_RUNTIME_AUDIT.md` (the month this builds on),
> `CAMPAIGN_EXPERIENCE_AUDIT.md` (the experience read of the same run),
> `DECISION_EXPERIENCE_AUDIT.md` (AE-036, the findings this phase raised).

## 1. The progression map (READ, from the implementation)

```
STARTUP ERA  ("One aircraft, one route, everything to prove")
   │
   ├─ GOALS the game states: the era card's requirement rows
   │     • Routes that made money last month .......... 3      (tuning)
   │     • An aircraft you own outright ............... 1
   │
   ├─ MISSIONS  — offers, not chores
   │     Source: tourism-boom world events only (0.002/day, one at a
   │     time, `WorldEventSystem.triggerTourismBoom`).
   │     Shape: boomRush(region, targetPassengers), target =
   │     0.6 × the player's daily seats into that region × boom days,
   │     floored at 500. Resolution measures passengers carried on
   │     region-touching routes since the offer's baseline
   │     (`MissionMath`), so the screen's bar and the resolver are one
   │     arithmetic. Reward = $40/pax × target (AE-036 adds a floor).
   │
   ├─ CAPABILITY PROGRAMS — visible, explained, and LOCKED
   │     `CapabilityProgram.unlockEra == .national`, one era beyond this
   │     phase's target. `StartCapabilityProgramCommand` rejects with
   │     "Capability programs open in the National era". This is a
   │     PROVEN DETERMINISTIC BLOCKER for AE-035's stop condition 7:
   │     the observable state is the locked state, and it was observed.
   │
   └─ THE GATE: `EraGate.isPassed` — the same requirements the screen
         renders (`EraGate.requirements`), so gate and UI cannot drift.
         `ProgressionSystem.advanceEra` runs each tick; passing the gate
         advances the era and emits `.eraAdvanced`, which the app turns
         into the "A new era" celebration. No player confirmation step —
         the era arrives when the airline earns it.
                    ↓
REGIONAL ERA → next goals: "To reach National" (trailing-12-month
         profit positive, 8 destinations, reputation ≥ 0.55) and large
         narrowbodies unlock in the market.
```

## 2. The deterministic campaign (MEASURED, Core twin)

`FirstEraCampaignTests.campaignReachesTheRegionalEraDeterministically`
walks the whole arc headlessly through the real command surface. World
seed **2039** was chosen by a local 50-seed scan — it is the seed whose
world offers a mission early enough to react to inside one campaign.

| Fact | Value | How |
| --- | --- | --- |
| Tourism boom (Africa) begins | day 8 | MEASURED |
| Mission offered | "Carry 500 passengers in Africa" | MEASURED |
| Mission reward | $20k → **$250k** after AE-036's floor | MEASURED both sides |
| Mission completed | day 11, by opening ARN–Cairo | MEASURED |
| First statement (January) | $2.0M net | MEASURED |
| Second statement (February) | $5.4M net | MEASURED |
| Regional era reached | day 59 (with the February close) | MEASURED |
| Routes profitable last month | 4 (gate asks 3) | MEASURED |
| Cash at day 70 | $17.3M | MEASURED |

The script is a plausible player, not a cheat: real commands, real
economy, no state injection, no production cheat controls. The UI
journey founds on the same seed through the game's own World-seed field.

## 3. Never-seen states (status at this writing)

| State | Reached | Evidence | Validation |
| --- | --- | --- | --- |
| Mission offered, visible, explained | yes | run 97 KEY-30 | OBSERVED |
| Gate requirements answering "what do I need" | yes | run 97 KEY-30 | OBSERVED |
| Capability programs (locked state + explanations) | yes | run 97 KEY-30 | OBSERVED |
| Mission progress bar (0/500 at offer) | yes | run 97 KEY-30 | OBSERVED |
| Mission completion | Core only | campaign twin, day 11 | MEASURED, not yet OBSERVED |
| Second statement | Core only | $5.4M | MEASURED, not yet OBSERVED |
| Era transition + celebration + post-era goals | Core only | day 59 | MEASURED, not yet OBSERVED |

The simulator journey reached KEY-30 in run 97 and then failed on a
navigation defect of its own (see §4). The states below KEY-30 are
proven in Core and pending their frames.

## 4. Defects found

- **FE-01 (fixed).** `buttons["Progression"]` matched nothing: the World
  hub's cards are NavigationLinks whose accessibility label is the whole
  card (title + badge + subtitle). `openProgression()` matches by prefix
  and proves arrival by the screen's own ERA header. Run 96 → fixed.
- **FE-02 (fixed).** The campaign tapped the Airline tab's "Fleet"
  segment while the tab was still on a pushed route detail — left there
  by `assignFirstAircraft`, deliberately, so the flight journey can
  photograph the assignment. `openAirlineSection(_:)` pops first. Run 97
  → fixed.
- **FE-03 (raised to AE-036, fixed there).** The mission asking for the
  biggest change — enter a region the airline does not serve — paid the
  least, because its target bottoms out at the 500-passenger floor:
  $20k against $1.8–5.4M months. OBSERVED in KEY-30 as the player sees
  it ("$20k · 73 days left").
- **FE-04 (raised to AE-036, fixed there).** A route the fleet cannot
  fly can be opened with no warning at the commit, and the destination
  row could not say whether the market sells a capable aircraft or
  whether it is a later era's route.

## 5. Limits, stated

Capability *progress* and *completion* are unreachable in the Startup and
Regional eras by design; only the locked state is observable here. Era
transitions beyond Regional, game over, and the late-game density and
antimeridian cases (TD-021) remain unrendered.
