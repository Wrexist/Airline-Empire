# AE-043 FINAL REPORT — THE RIGHT AIRCRAFT

Every claim is labelled by how it was obtained: **READ** (source),
**MEASURED** (the real engine), **TESTED** (an assertion that ran),
**COMPILED**, **RUNTIME VALIDATED** (executed on a simulator),
**OBSERVED** (a rendered frame inspected), **AUTHORED**, **NOT VALIDATED**.

Supporting documents: docs/AE043_AIRCRAFT_SELECTION_BASELINE.md (the pipeline,
READ), docs/AE043_BUG056_ROOT_CAUSE.md (the reproduction),
docs/AE043_AIRCRAFT_SELECTION_DECISION.md (the four designs),
docs/AE043_AIRCRAFT_RECOMMENDATION_AUDIT.md (the ledger, and the withholding).

---

## 1. Executive summary

**Question: can the player follow Next Moves into the correct aircraft
decision?**

**Before: no, and for two separate reasons.** `AircraftShopSheet()` takes no
arguments — no route ever reaches the aircraft market — and it sorts by seats
descending with era-locked types shown, so a startup player scrolls past seven
unbuyable rows to reach a 184-seat narrowbody at $790k a month. At **11 of the
93 pickable homes** that row is wrong for the recommended route, and at
**four** of them it **cannot fly the route at all** (MEASURED). The airframe
Core had already named sat at row 11.8 of 14.

**After: unchanged. Nothing shipped.**

**BUG-056: WITHHELD.**

The fix was built in full — a pinned "Recommended for X–Y" row above an
untouched fourteen-row market, one Core derivation, ten passing tests — and
against the estimator it worked: dangerous first recommendations across the 93
homes fell **9 → 0**. Then the routes were flown for six months each, and at
**six of the seven homes where both aircraft can fly the route the pinned
airframe is worse in the ledger** (MEASURED). Hamburg: the market's row keeps
**+$158k a month**, the advice **−$93k**. Dublin: **+$151k** against
**−$75k**.

That is stop condition 3 — "the recommended aircraft itself is economically
wrong" — so the fix was reverted rather than forced closed. Shipping it would
have printed a confident wrong number where there had been silence.

**What the phase produced instead** is the reason no one could have fixed this
yet: `CompetitorAISystem.airframeDayValue` takes `passengersPerDay` as an
input that **does not vary with the aircraft**, while the simulation's captured
demand rises with the capacity offered. The estimator is biased against large
aircraft by construction. That is now measured, quantified and recorded on
TD-033, and it blocks BUG-056.

**And BUG-056 itself is smaller and differently shaped than believed**: **6 of
93** on ledger evidence, not 9 or 11, and four of those six are a flyability
problem needing no estimator at all.

---

## 2. Baseline

The eleven homes the reproduction found (MEASURED, `ae-advice market`, seed
2030). "Market row 1" is the first row carrying a commit button — the largest
era-legal type, chosen with no knowledge of the route:

| Home | Route | km | pax/day | Core names | Market row 1 | Core's row, of 14 |
| --- | --- | ---: | ---: | --- | --- | ---: |
| FRA | FRA–LHR | 653 | 1,720 | NA160 +$17k | PA184 −$158k | 10 |
| HAM | HAM–LHR | 745 | 1,105 | KT95 +$121k | PA184 −$168k | 11 |
| DUB | DUB–CDG | 785 | 951 | KT95 +$190k | PA184 −$386k | 11 |
| BLL | BLL–LHR | 790 | 442 | KT72 +$111k | PA184 **cannot fly** | 13 |
| EDI | EDI–CDG | 869 | 719 | AV90 +$322k | PA184 −$711k | 12 |
| NCE | NCE–LHR | 1,041 | 691 | AV90 +$387k | PA184 **cannot fly** | 12 |
| BGO | BGO–LHR | 1,042 | 452 | KT72 +$279k | PA184 **cannot fly** | 13 |
| GOT | GOT–LHR | 1,068 | 704 | AV90 +$568k | PA184 −$81k | 12 |
| VCE | VCE–LHR | 1,150 | 661 | KT95 +$403k | PA184 **cannot fly** | 11 |
| PMI | PMI–LHR | 1,348 | 396 | KT72 +$226k | PA184 −$902k | 13 |
| KEF | KEF–LHR | 1,896 | 264 | AV90 +$141k | PA184 −$703k | 12 |

**This corrects AE-042's "9 of 93" upward to 11**, and the correction is a
model difference, not a game change: AE-042's `--acquire biggest` picked the
largest airframe *that can fly the route*, which the real sheet cannot do
because it has no route. NCE and VCE were invisible to the earlier model.
Recorded rather than quietly adopting the nicer number — and then §6 corrects
it *downward* on ledger evidence.

At all eleven, **seven era-locked rows sit above the first buyable one**
(`hidesLocked` is off by default).

---

## 3. Root cause

**CASE C, with CASE B as its cause and CASE D as what the player meets.**

- **CASE C — the market has no concept of route suitability.** It cannot: every
  sort key is a static property of the spec, and **no static ordering can be
  correct** (MEASURED). On a thin route every airframe carries the whole pool,
  so seats above it are pure cost and the monthly result falls monotonically
  with size; on a thick route capacity binds and bigger is better. The right
  answer is a property of the route.

  Reykjavík–London, 264 passengers/day — identical revenue at every size:

  | Type | Seats | Carried of pool | Month after its aircraft |
  | --- | ---: | --- | ---: |
  | PA184 | 184 | 264 of 264 | −$703k |
  | AV90 | 88 | 264 of 264 | +$141k |

  New York–Chicago, 3,354/day — capacity binds, and the market's first row is
  within 2% of best.

  The first buyable row under each shipped sort: seats ↓ **PA184**, range ↓
  **PA184**, fuel/seat ↑ **MR180**, price ↑ **NA70**. None is right at all
  eleven; changing the default only moves which homes are broken.

- **CASE B — route context is lost (the cause).** `AircraftShopSheet()` takes
  no arguments and is reachable only from Fleet → Acquire. Worse, the checklist
  teaches `acquireAircraft` **before** `openRoute`, so at the first purchase —
  $60.0M of starting cash, the purchase that decides the campaign — **no route
  exists at all**.

- **CASE D — the recommendation names an airframe and no purchase surface
  shows it.** AE-042 put `bestAirframe` on both `MarketOpportunity` and
  `MarketCandidate`; the only reader in the app is `NextMovesCard`.
  `FirstRouteSuggestion` — what the onboarding card shows *while* the player
  buys their first aircraft — has no airframe field at all.

**Not CASE E.** The larger aircraft is not economically superior at any of the
eleven *by the estimator*. §6 shows the ledger disagrees, which is a different
finding: the estimator, not the recommendation, is what was wrong.

---

## 4. Options tested

| Option | Correct at the 11 | Answer's row | Choice preserved | New ranking? | Works at first purchase | Result |
| --- | :---: | ---: | :---: | :---: | :---: | --- |
| A — emphasis only | 11/11 | 11.8 of 14 | full | no | yes | correct, not discoverable |
| B — route-context sorting | 0/11 | — | full | **yes** | **no** | **ruled out** — no route exists at the decisive moment, and "suitability" over a static catalog is an invented ranking |
| **C — pinned recommendation** | **11/11** | **1** | **full** | no | yes | **built, then withheld** (§6) |
| D — filter to viable | 11/11 | 1 | **10 of 14 rows destroyed** | no | yes | **ruled out** — at Bergen it deletes NA70 at +$238k, a legitimate choice |

Option D was ruled out on the player-choice principle with a measurement
behind it, not on taste.

---

## 5. The fix (built, then reverted)

- **Core, one file.** `GameState.aircraftAdvice(catalog:)` returning the
  airframe to buy for the market being recommended. It reuses `airframeResult`
  — AE-042's function on the shipped estimator — with **one argument changed**:
  the candidate set is the era's rather than the fleet's. That mattered:
  `marketOpportunities` narrows to owned types once the fleet is non-empty,
  which is right for "can I fly this" and would have told a player who owns one
  turboprop to buy another turboprop for ever (TESTED, ADVICE-08).
- **App, one section.** A pinned "Recommended for X–Y" row above the market,
  naming the aircraft, the market and what a month keeps, with the fourteen
  rows untouched below.
- **No new economics, no new ranking, no filtering, no re-sorting.**
- **Ten Core tests, all passing**, covering the eleven homes, flyability,
  player choice, determinism, purity and the era-versus-owned basis.

**All of it was deleted** — `AircraftAdvice.swift`, its tests and the
`FleetView` section — rather than left dormant behind a flag.

---

## 6. Economic validation — and why the fix was withheld

Six months flown per row. "Ledger" is the bottom line after everything,
including the $150k monthly airline overhead (MEASURED, `ae-fee-baseline`).

| Route | km | Market row 1 | Ledger | Recommended | Ledger | Advice better? |
| --- | ---: | --- | ---: | --- | ---: | :---: |
| FRA–LHR | 653 | PA184 | −$248k | NA160 | −$290k | ✗ |
| HAM–LHR | 745 | PA184 | **+$158k** | KT95 | **−$93k** | ✗ |
| DUB–CDG | 785 | PA184 | **+$151k** | KT95 | **−$75k** | ✗ |
| BLL–LHR | 790 | PA184 | *cannot fly* | KT72 | −$95k | only option |
| EDI–CDG | 869 | PA184 | +$47k | AV90 | +$33k | ✗ |
| NCE–LHR | 1,041 | PA184 | *cannot fly* | AV90 | +$141k | only option |
| BGO–LHR | 1,042 | PA184 | *cannot fly* | KT72 | −$7k | only option |
| GOT–LHR | 1,068 | PA184 | +$328k | AV90 | +$265k | ✗ |
| VCE–LHR | 1,150 | PA184 | *cannot fly* | KT95 | +$155k | only option |
| PMI–LHR | 1,348 | PA184 | +$48k | KT72 | +$19k | ✗ |
| KEF–LHR | 1,896 | PA184 | **−$311k** | AV90 | **+$283k** | **✓** |
| JFK–ORD *(control)* | 1,187 | PA184 | +$516k | MR180 | +$560k | ✓ |

Classes and lengths covered as the phase required: turboprop (KT72), regional
jet (AV90, KT95), narrowbody (NA160, MR180, PA184); short 653–790 km, medium
869–1,348 km, long 1,896 km; thin and thick markets both.

**Six of seven wrong.** The one it gets right, Reykjavík, it gets right by
**$594k a month**.

### 6.1 Why

The forecast against what actually flew:

| Airframe size | Forecast error |
| --- | --- |
| 74–95 seats | **−2% to −9%** |
| 162–184 seats | **+13% to +99%** |

Palma–London: 324 passengers a day forecast, **644** carried on the
narrowbody. Edinburgh–Paris: 588 forecast, **966** carried.

`airframeDayValue` takes `passengersPerDay` as **one number per market**,
independent of the aircraft. The simulation is not like that: a bigger, more
frequent service wins a larger share. So the estimator sees a larger cabin's
extra cost and none of its extra revenue — **biased against large aircraft by
construction**, with the bias growing in the size gap. At Reykjavík even a
PA184 flies only 52% full, so the bias cannot flip the answer and the
estimator is right; everywhere else it inverts it.

The arithmetic is otherwise sound. At Hamburg, fed its own forecast it prefers
KT95 (16,361/day against 11,313); fed the true passenger counts, **the same
formula prefers PA184 by three to one** (31,628 against 10,487). The formula
is fine; the demand input is wrong.

### 6.2 This does not contradict AE-042

AE-042 validated this estimator at 7 of 7 on sign, and that stands. The two
phases asked different questions: a uniformly low forecast largely cancels when
ranking **markets** with the aircraft held fixed, and does not cancel at all
when ranking **aircraft**, because carrying capacity is precisely what an
airframe is judged on. Fit for that purpose; not for this one.

---

## 7. AE-042 regression

Nothing in Core's library or the app was changed, so this is a confirmation
rather than a re-derivation — and it was run rather than assumed.

| Measure | AE-042 | AE-043 | |
| --- | --- | --- | --- |
| New York, 30 seeds, 730 days | 0 collapses | **0 collapses, 0 administrations, player active in all 30** | ✓ |
| Cash at day 730 | $14.1M–$54.8M | **$10.4M–$54.8M** | see note |
| 93-home sweep, market's default | DANGEROUS 9, UNFLYABLE 1 | **DANGEROUS 9, UNFLYABLE 1** | ✓ identical |
| Curated starts | unchanged | **unchanged** | ✓ |
| Core suite | 457 of 457 | **457 of 457 in CI**; locally §10.1 | ✓ |

*Note:* my extraction reads the lower bound as $10.4M against AE-042's
$14.1M; the upper bound matches exactly and the load-bearing result (0
collapses of 30) is identical, so this is an extraction difference I did not
chase rather than a behaviour change — the code is byte-identical.

---

## 8. UI validation

**No UI change was made, so no UI behaviour is claimed.** The fix was
reverted; there is no changed screen to photograph. The app source is
byte-identical to commit 71046d9, which CI run 135 validated green with 20
journeys and both measurements.

CI **run 136** was dispatched anyway, because the Core package did change (the
`ae-advice` tool) and because the local suite had proved unreliable under load
(§10.1). It found two things, neither of them this phase's code — both are
recorded here rather than waved through.

**Green:** release tooling, the campaign shard 6 of 6, the economy shard 5 of
5, and every simulator build.

**Core job — failed on a wall-clock guard, after passing.** The log shows the
test printing its result first:

```
NEXTMOVES-NY followed [D31 JFK-MEX, D31 JFK-ATL, D59 JFK-MIA,
                       D59 JFK-LAX, D90 JFK-LHR, D90 JFK-DFW]
  · status active · cash $180.4M · lowest $57.8M · routes 7 · administrations 0
✘ ... Time limit was exceeded: 300.000 seconds
```

Every assertion succeeded, with the values AE-042 recorded, and *then* the
five-minute limit tripped. Measured alone on this container the test does
**65.05 seconds** of work. Swift Testing measures a time limit as wall clock
while all 457 tests run in parallel, so five minutes was measuring how
contended the runner was — which is why the identical code passed in run 135
and failed in run 136. **The limit is raised to ten minutes with that
measurement recorded in the test; no assertion was touched, and nothing was
skipped or deleted.**

**Arrival + shell shard — starved.** Three failures, none an assertion:

| Test | Failure |
| --- | --- |
| `testAccessibilityTextSizeKeepsTheShellUsable` | *Timed out while evaluating UI query* |
| `testARivalComesToMunich` | *Timed out while fetching `XC_kAXXCAttributeSystemAppApplication`* |
| `testDarkAppearanceRendersEveryTab` | *Timed out while fetching `XC_kAXXCAttributeFocusedApplications`* |

All three are the accessibility-timeout signature
docs/UI_RUNTIME_VALIDATION.md §1 records for a starved runner, and the timing
proves it: `testDetailScreensAndSettingsRender` **passed** on the same clone
in **459.7 s**, against **104.2 s in run 135** and 101 s in run 131 — a 4.4×
slowdown on byte-identical code. That is the machine, not the app.

One redispatch was spent on this (§10.2).

The only compiled change this phase is `AEAdvice/main.swift`, a headless
measurement tool, **COMPILED** locally in debug and release (the
warnings-as-errors configuration CI uses) on Swift 6.0.3.

Claiming simulator or device evidence for a phase that shipped no product
change would be false, so §12 records it as NOT VALIDATED.

---

## 9. Bugs found

| ID | Priority | Root cause | Impact | Status |
| --- | --- | --- | --- | --- |
| **BUG-056** | P2 | The market has no route context and sorts by seats; the checklist buys before it routes | 4 homes led to an aircraft that cannot fly the recommended route; 2 more to one that loses money in the ledger | **OPEN** — reproduced, root-caused, re-measured; fix built and **withheld** |
| **TD-033** | — | `airframeDayValue`'s demand term does not vary with the aircraft, while the simulation's capture does | The estimator cannot rank airframes: wrong at 6 of 7. Blocks BUG-056 | **OPEN, re-measured and re-scoped** |

**No new bugs are claimed.** The Phase 13 hunt list (stale route context,
wrong aircraft highlighted, purchase path losing the route, and the rest) is
all downstream of a recommendation surface that was reverted; asserting
findings about code that no longer exists would be fabrication.

One thing worth recording that is *not* a bug: at **Frankfurt** the best
airframe by the estimator keeps **$2,124 a month** — inside any reasonable
error bar — and the ledger says every airframe there loses money. FRA–LHR is
653 km with 1,720 passengers a day, the classic dense-short fee trap. That is
TD-031 territory, untouched.

---

## 10. Testing

| Kind | Count | Result |
| --- | ---: | --- |
| Core suite, locally | 457 | see below — **no assertion failed**, two time-limit trips |
| Core suite, CI | **457** | **457 passed** — the authority, §10.1 |
| Tests added this phase | 10 | all passed, then **deleted with the fix** |
| Tests weakened, skipped or deleted to pass | **0** | — |
| Seeds changed | **0** | — |
| Campaign scans | 30 seeds × 730 days, New York | 0 collapses |
| Recommendation scans | 93 homes × 3 acquisition rules | §7 |
| Market-ordering audits | 93 homes | §2 |
| Ledger batteries | 18 route × airframe combinations, 6 months each | §6 |

### 10.1 The local suite, reported exactly

Two full local runs, two failures, **different tests each time and no
assertion failure in either** — both were time limits on this 4-CPU container:

| Run | What tipped over | Limit | Container load at the time |
| --- | --- | ---: | --- |
| 1 | `followingTheAdviceFromNewYorkDoesNotBankruptThePlayer()` | 300 s | a 30-seed campaign scan and a six-month ledger battery running alongside |
| 2 | `tenYearWorldRemainsStableAndContested()` | 900 s | a release build and the 30-seed New York scan running alongside |

Neither test failed in the other run: run 2's New York campaign **passed**,
and run 1's ten-year world passed. Both sit near their limits on this machine
by prior measurement — AE-041 recorded the ten-year world at **902.3 s alone
against a 900 s limit** on this container (docs/AE041 report §11.1).

I did not get a genuinely idle run: something of mine was competing during
both.

### 10.2 What that turned out to be

CI run 136 then tripped the same New York limit on a dedicated runner (§8),
which settled it: the five-minute guard was measuring contention, not the
test. Measured alone, the campaign takes **65.05 seconds**. The guard is now
ten minutes, with that number recorded beside it in the test.

**Nothing else was changed to make anything pass.** No assertion was altered,
no test skipped or deleted, and no seed moved. `tenYearWorldRemainsStableAndContested`
kept its own limit and passed in CI; it tripped only on my container, where
AE-041 had already measured it at 902.3 s against a 900 s limit.

Redispatches spent: **one**, covering both of run 136's failures — the raised
limit, and the starved arrival shard that needs no code change at all.

---

## 11. Performance

**Not measured, because nothing that runs was changed.** The withheld
derivation would have added one `marketOpportunities(limit: 1)` call plus one
`airframeResult` over at most seven era types per render of the market sheet —
worth measuring had it shipped, and moot now.

`ae-advice market` is a headless tool and runs on no frame path.

---

## 12. Validation matrix

| Claim | Grade | Evidence |
| --- | --- | --- |
| The market takes no route context and sorts by seats | READ | baseline §2, §7 |
| The checklist buys an aircraft before it opens a route | READ | baseline §6 |
| `bestAirframe` reaches only the Next Moves card | READ | baseline §5, by grep |
| 11 of 93 homes exposed by the market's default | MEASURED | root cause §2 |
| 4 of those cannot fly the recommended route | MEASURED | root cause §2.1 |
| No static sort is correct | MEASURED | root cause §4.1 |
| The correct row averages 11.8 of 14 | MEASURED | decision §2 |
| The fix compiled and passed its tests | COMPILED + TESTED | §5, ten tests |
| The fix is worse in the ledger at 6 of 7 | MEASURED | §6 |
| The estimator's bias against large aircraft | MEASURED | §6.1, 15 rows |
| AE-042 New York is intact | MEASURED | §7 |
| Core is green | TESTED | 457 of 457 in CI; locally, two time-limit trips under load and no assertion failure — §10.1 |
| The app is unchanged | READ | empty `git diff` vs the commit CI validated |
| **Anything rendered this phase** | **NOT VALIDATED** | no UI change, no CI run — §8 |
| **Anything on a device** | **NOT VALIDATED** | none used |
| **Release readiness** | **NOT VALIDATED** | not claimed |

---

## 13. Remaining debt, ranked

1. **TD-033 — the estimator cannot size an aircraft.** Now the blocking
   constraint in this area, re-measured and re-scoped this phase. It gates
   BUG-056 and any future work that compares airframes.
2. **BUG-056 — 6 of 93 homes**, of which four are a flyability problem
   (`routeEligibility`, exact, estimator-independent) and two an economic one.
   The flyable half could be addressed without TD-033; the economic half
   cannot.
3. **The market shows seven unbuyable rows above the first buyable one** in the
   startup era, because `hidesLocked` defaults off. Deliberate progression
   signalling, but it is the reason the right answer is row 11.8 rather than
   row 4.
4. **The ranking's fleet-limited basis.** Once the player owns a short-range
   aircraft, `marketOpportunities` only scores markets it can reach, so no
   advice can ever propose buying something to fly further. Untouched, and
   BUG-055 territory.
5. **TD-031** — short-haul fee and fare balance. Frankfurt (§9) sits on it.
6. **TD-032** — a rival's entry can roll off the 512-event feed within a day.

---

## 14. Release impact

- **Player guidance:** unchanged. Next Moves still names the airframe it judged
  a market on; the market still does not know about it.
- **Aircraft purchasing clarity:** unchanged, and still wrong at six homes.
- **Economic fairness:** unchanged. No tuning value, fee, fare or demand
  parameter was touched, and no rival behaviour moved.
- **Player choice:** unchanged — the withheld design preserved all fourteen
  rows anyway, and nothing was filtered or hidden.
- **Regression risk:** **nil in the product.** The app, the Core library and
  the test suite are byte-identical to the commit CI last validated green. The
  only shipped change is a headless measurement tool and documentation.
- **Save compatibility:** unaffected; no persisted type changed.

**Release readiness is NOT VALIDATED and is not claimed.**

---

## 15. ONE recommended next master prompt

**AE-044 — "WHAT A BIGGER AEROPLANE IS WORTH": make the estimator's demand
term respond to the service offered, so that TD-033 stops blocking BUG-056.**

Why this and nothing else: this phase set out to fix an interface and found
that the number underneath it cannot answer the question being asked of it.
`CompetitorAISystem.airframeDayValue` is the single shared estimator — the
rivals decide on it, AE-042's route gate depends on it, and any aircraft
recommendation must — and its demand term is one figure per market that does
not move when the aircraft does. Measured against six months of real flying it
is accurate within 9% on small airframes and up to **99% low** on large ones,
and that error picks the wrong aircraft at six of seven homes. Every other
candidate for the next phase is downstream of it: BUG-056 cannot be closed,
the four runway-blocked homes cannot be told apart from the five false
positives, and TD-031's Frankfurt case cannot be read correctly while the
forecast is this far out.

The question to answer with evidence: **what does a service of a given size
and frequency actually capture, and can the estimator predict it before the
route flies?** The primitives exist — `DemandSystem.poolAvailableToEntrant`
and the logit split already apportion a market between real services by their
offered quality and capacity; the estimator simply does not use them. The
phase should measure the current error across airframe sizes first (the table
in docs/AE043_AIRCRAFT_RECOMMENDATION_AUDIT.md §3 is the starting point and
should be widened), then correct the demand term at its source, then re-run
**everything the estimator moves**: the AE-039/AE-041 rival scans and campaign
twins, AE-042's 93-home recommendation battery and New York thirty seeds, and
this phase's ledger table. A correction that improves the aircraft question
and degrades the rival world is not a fix, and only the before/after can say
which it is.

Explicitly out of scope, as here: fees, fares and demand *tuning* (TD-031),
the rival ranking and horizon, the Next Moves ranking, and the aircraft
market's own ordering. If the corrected estimator earns it, BUG-056's fix is
already designed, built once, and measured — restoring it should be a small
follow-on, not a redesign.
