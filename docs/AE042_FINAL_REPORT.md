# AE-042 FINAL REPORT — TRUST THE ADVICE

Fixing BUG-055: the game's own advice could bankrupt the player.

Every claim below is labelled by how it was obtained — **READ** (from the
source), **MEASURED** (from the real engine), **TESTED** (an assertion that
runs), **COMPILED**, **RUNTIME VALIDATED** (executed on a simulator in CI),
**OBSERVED** (a rendered frame inspected), **AUTHORED** (written this phase),
**NOT VALIDATED**. Nothing is claimed at a higher grade than it was earned.

Supporting documents: docs/AE042_RECOMMENDATION_PIPELINE.md (the architecture,
READ), docs/AE042_NEXT_MOVES_BASELINE.md (the measurements before),
docs/AE042_BUG055_ROOT_CAUSE.md (the decision),
docs/AE042_RECOMMENDATION_AUDIT.md (before, after, and what is still true).

---

## 1. The answer

**Question: can a new player safely trust Next Moves?**

**Before this phase: no.** At **21 of the 93 homes a player can pick (23%)**,
Home's *first* suggestion either lost money after the aircraft it needed or
could not be flown at all (MEASURED). The scripted New York player who
followed the card collapsed into administration in **28 of 30 seeds**
(MEASURED). The heading over those suggestions read "Strong open markets from
your bases."

**After this phase: yes, for the decision the card actually asks the player to
make.** A recommended market now has to pay for the airframe it needs before
it can be recommended. Dangerous or unflyable first recommendations fall
**21 of 93 → 9 of 93**; the New York collapse goes **28 of 30 → 0 of 30**; and
each recommendation now names the aircraft it was judged on and what a month
on it is worth (MEASURED).

**The honest qualification.** The nine that remain are not the old failure.
Each pays on the airframe the recommendation names and loses on the larger one
the aircraft market's default sort puts in its first row. That is a second
defect on a different surface, measured, recorded as **BUG-056**, and
deliberately not fixed here. So the precise answer is: *the advice is now
trustworthy; following it while ignoring the aircraft it names is not yet.*

---

## 2. What was read (READ)

The recommendation pipeline, traced end to end before anything was changed
(docs/AE042_RECOMMENDATION_PIPELINE.md). Three findings decided the phase:

1. **One ranking, four surfaces.** `GameState.marketOpportunities` feeds the
   onboarding suggestions, the Next Moves card, the map's demand coach and the
   route sheet's prefill. A change there changes all four at once — which is
   why the campaign twins and UI journeys are pinned to its output.
2. **The score is `pool / (1 + incumbents)` and nothing else.** No cost, fee,
   capacity, rotation, lease, acquisition or cash term exists anywhere in the
   function. Aircraft enter only as a boolean range-and-runway gate: a market
   is admitted or excluded, never ranked lower for needing an airframe it
   cannot pay for.
3. **It is the rule the rivals abandoned.** AE-039 removed exactly this metric
   from the competitor AI because it "put every short large pair ahead of
   every longer one for ever" (docs/HORIZON_AUDIT.md §3.2). The player kept
   it.

Also READ: the estimator needed to price a market already exists and is
already trusted — `CompetitorAISystem.airframeDayValue`, corrected by AE-040
and shipped for rivals by AE-041. No second economy had to be built.

---

## 3. Scope decision

**In scope, and done:** the ranking's eligibility gate, the fields a
recommendation carries, and the one sentence the Next Moves card owes the
player about the aircraft.

**Out of scope, and untouched** (verified by diff): rival horizon and ranking,
TD-031 fee levels, the fare and demand model, competitor UI, archetypes,
missions, progression, the event feed (TD-032), device-only work, cosmetic
redesign, and the save format.

**The stop condition that had to be argued rather than assumed.** Stop
condition 10 asks whether this is really TD-031 — short-haul fee and fare
balance — or another economy defect out of scope. It is not, and the
distinction is the whole phase: the economy is doing what it is calibrated to
do, and no tuning value, fee, fare or demand parameter is touched by the fix.
A game may contain unprofitable routes. It may not recommend them under a
heading that says "strong". The defect is the advice, not the economy.

Stop condition 2 (the estimator is materially inaccurate) was cleared by
measurement before the estimator was used to rank anything — §11.

---

## 4. The baseline, before any change (MEASURED)

Taken with `ae-advice`, a new headless executable that reads the real read
model and follows its advice through real commands. Nothing in it changes the
simulation. Full tables in docs/AE042_NEXT_MOVES_BASELINE.md.

Held constant: scenario `entrepreneur` ($60.0M, five rivals), start year 2030,
seeds 2030–2059, shipped catalog and tuning at commit 60c1520. The airframe
assumed is the one the aircraft market's default sort puts first (seats
descending, lease) — READ from `FleetView`, so it is what a new player
actually meets.

**Every home a player can pick, first recommendation only:**

| Class | Homes |
| --- | ---: |
| SAFE | 7 |
| VIABLE | 50 |
| MARGINAL | 15 |
| **DANGEROUS** (loses money after its aircraft) | **20** |
| **UNFLYABLE** (no era airframe can fly it) | **1** |

**21 of 93 (23%)** given a first recommendation that loses money or cannot be
flown.

The dangerous ones are the game's most recognisable city pairs — Manchester is
told to fly London (243 km, fees **96% of revenue**, **−$1.5M a month**, a
market ranked **#42 of 45** from that home); London is told to fly Paris,
ranked **#44 of 44, dead last**. Meanwhile Lagos, Istanbul and New York sit
unmentioned at +$3.0M and better.

**The relationship is monotonic in distance**, which is the mechanism:

| Class | Mean distance recommended |
| --- | ---: |
| DANGEROUS | 658 km |
| MARGINAL | 799 km |
| VIABLE | 1,660 km |
| SAFE | 2,348 km |

**And the curated starts were not exempt.** Singapore's second recommendation
(Kuala Lumpur, 297 km) loses **$598k a month** and ranks **18 of 18 — last**
from its own home. New York's second (Toronto) loses **$214k** at **#21 of
22**. Neither is rescued by a different airframe: the best startup-era
aircraft still loses $242k and $174k respectively.

---

## 5. Root cause (CASE decision, on evidence)

**CASE B, with CASE A as its cause and CASE E at fleetless homes.**

- **CASE B — the eligibility filter is too weak (primary).** It asks "can some
  aircraft fly this?" and never "can this pay for the aircraft it needs?".
  The traps are excluded by no gate at all.
- **CASE A — the ranking metric is why the traps surface first.** A
  passenger-only metric does not merely fail to rank traps down, it ranks them
  top. The reference fare rises with distance; the two movement fees are
  charged per flight and do not. A short pair therefore maximises passengers
  per day while minimising revenue per movement, so the passenger-ranked list
  is sorted, in effect, **by fee share descending**. MEASURED support: the
  monotonic distance ordering above, and fee shares of 96%, 85%, 68% and 63%
  at the dangerous end against 40%, 28% and 18% at the safe end.
- **CASE E — at a fleetless home the filter admits the unflyable.** Nadi's two
  suggestions are 7,132 km and 3,170 km, beyond every startup airframe; the
  card's servable filter finds nothing and falls back to showing them anyway.

**Rejected on evidence, not on convenience:** CASE C (acquisition cost) and
CASE D (cash) are true as READ facts, but the traps fail on their own
operating economics before any question of affordability — Manchester–London
loses $1.18M a month in the ledger however the aircraft was paid for. Adding a
cash term is not needed to remove them and would make advice depend on the
player's balance sheet. CASE F (the UI oversells) is a symptom; once the traps
are gone the sentence is no longer false. One narrow exception was carried
into the fix (§7).

---

## 6. The designs measured, and the one chosen

Three candidates, each computed over **production's own candidate set** — same
origins, same already-served exclusion, same eligibility, same positive-pool
requirement — so only the ordering differed (MEASURED).

| Design | New York | Manchester | The curated starts | Verdict |
| --- | --- | --- | --- | --- |
| **Rank by what a market keeps** after its aircraft | Lisbon, London | Lagos, Istanbul | **all change** | Corrects everything and sends every home to its longest reachable route at one rotation a day, selling a fifth of the demand it names. A different game's advice. |
| **Gate out what cannot pay, keep the order** | Chicago, **Mexico City** | **Cairo, Istanbul** | **unchanged** | **Chosen.** Removes every trap; leaves sound advice untouched. |
| Add a cash/affordability term | — | — | — | Not required by the evidence (§5); makes advice depend on the balance sheet. |

The gate wins on the rule the phase set: **the smallest change that answers
the question.** It leaves Stockholm, Barcelona and Munich — the worlds the
AE-039 and AE-041 campaign twins and the UI journeys are pinned on —
byte-identical, and changes only the homes where the advice was a trap.

---

## 7. What shipped

**Core — `Session/MarketOpportunities.swift`. Two additions, no replacement.**

1. `GameState.airframeResult(from:to:distanceKm:passengersPerDay:candidateSpecs:catalog:)`
   — the best airframe the airline could operate that can actually fly the
   pair, and what a month on it keeps after that airframe's lease, its crew,
   and the route's own payroll. Every term is an existing public primitive:
   `airframeDayValue(basis: .profit)`, `AircraftTypeSpec.leaseMonthly`, and
   `FinanceTuning`'s two payroll lines. Nothing re-derived.
2. `marketOpportunities` walks its own passenger-ranked list and puts the
   markets that pay for their airframe first, stopping as soon as it has
   `limit` of them.

**The rule**, whose only boundary is zero — not a tuned threshold but the
definition of paying for itself:

```
max over flyable candidate specs of
    airframeDayValue(.profit) × 30 − leaseMonthly − payroll   >   0
```

**Never strand the player.** The gate reorders rather than deletes. A home
with fewer than `limit` qualifying markets still receives the rest of the
passenger-ranked list, so the Nadi player still sees the best available and
the onboarding checklist still has a first route to teach.

**App — `Screens/DashboardView.swift`.** One line of copy per recommendation:

> Best on a 180-seat Meridian MR-180 — about $874k a month after its lease.

and, where nothing from the player's bases pays for its own aircraft, a
heading that says so instead of calling the least bad option strong.

**Unchanged:** the ranking score itself (`pool / (1 + incumbents)`), every
tuning value, the fee model, the fare formula, the demand system, the rival
AI, the save format, and `marketCandidates`' own ordering (the route sheet
lists every destination on purpose).

---

## 8. Before / after (MEASURED)

### 8.1 Every home a player can pick

| | Before | After |
| --- | ---: | ---: |
| SAFE | 7 | 8 |
| VIABLE | 50 | 58 |
| MARGINAL | 15 | 17 |
| **DANGEROUS** | **20** | **9** |
| **UNFLYABLE** | **1** | **0** |
| **Advice that loses money or cannot be flown** | **21 of 93 (23%)** | **9 of 93 (10%)** |

### 8.2 The advice itself, seed 2030

| Home | Before | After |
| --- | --- | --- |
| Stockholm (curated) | LHR +$1.8M, CDG +$1.6M | **unchanged** |
| Barcelona (curated) | LHR +$1.0M, CDG +$825k | **unchanged** |
| Munich | LHR, CDG | **unchanged** |
| Singapore (curated) | CGK +$1.2M, **KUL −$598k** | CGK, **BKK +$2.7M** |
| New York | ORD +$858k, **YYZ −$214k** | ORD, **MEX +$2.3M** |
| London | **CDG −$1.3M**, IST | **IST +$3.3M**, CAI +$2.5M |
| Manchester | **LHR −$1.5M**, **CDG −$517k** | **CAI +$2.8M**, IST +$3.8M |
| Nadi | HND, SYD (neither flyable) | unchanged — nothing from Nadi pays; the card now says so |

### 8.3 The campaign BUG-055 was found on

AE-041's scripted New York campaign, **unchanged**, with only the advice
different (`ae-rival-scan 730 2030-2059 JFK --player`, run on both builds):

| | Before | After |
| --- | ---: | ---: |
| Seeds collapsed, of 30 | **28** | **0** |
| End state | administration, day 430, −$2.0M to −$2.9M | alive, $14.1M–$54.8M |

### 8.4 Following the advice, 30 seeds × 4 homes × 730 days

| Home | Collapses, before → after | Mean cash at day 730, before → after |
| --- | ---: | ---: |
| New York | 0 → 0 | $343.6M → **$469.4M** (+37%) |
| Stockholm | 0 → 0 | $282.2M → **$386.2M** (+37%) |
| Barcelona | 0 → 0 | $222.8M → **$255.7M** (+15%) |
| Singapore | 0 → 0 | $432.4M → **$471.0M** (+9%) |

**Stated plainly, because it corrects an inherited claim:** this harness does
**not** collapse before the fix either. It takes one recommendation a month,
and the first is sound at all four of these homes. The collapse in §8.3 needs
the *second* recommendation, which is where the traps were, plus the used
purchase AE-041's script makes. I re-ran AE-041's 28-of-30 result directly
rather than inheriting it, and both facts are reported. What §8.4 buys the
trusting player is not survival but a materially better airline.

---

## 9. The New York regression twin (TESTED)

`followingTheAdviceFromNewYorkDoesNotBankruptThePlayer()` in
`Tests/AirlineEmpireCoreTests/NextMovesTests.swift` — the campaign BUG-055 was
found on, as an assertion that runs in CI on every commit.

Founds at JFK, plays 500 days, takes the recommendation the card would show,
leases the airframe the aircraft market's default sort offers, opens at the
reference fare and assigns. Result (TESTED):

| | |
| --- | --- |
| Markets followed | MEX, ATL, MIA, LAX, LHR, DFW |
| End state | **active** — 0 administrations |
| Cash | **$180.4M** |
| Lowest cash reached | **$57.8M** |
| Routes flying | 7 |

Toronto — the trap the old advice named second — is asserted absent.

---

## 10. The curated-start battery (MEASURED and TESTED)

`theCuratedStartsAdviceIsUnchanged()` pins the worlds the earlier phases'
twins and journeys depend on: Stockholm → [LHR, CDG], Barcelona → [LHR, CDG],
Singapore → [CGK, BKK], Munich → [LHR, CDG]. Stockholm, Barcelona and Munich
are **byte-identical to the shipped build**; Singapore's second changes
because its second was the trap.

`everyRecommendedMarketPaysForTheAircraftItNeeds(_:)` runs over ARN, BCN, SIN,
MUC, JFK, LHR, MAN. `aMarketThatCannotPayForItsAircraftIsNotRecommended(_:)`
runs over the five measured traps: (LHR, CDG), (MAN, LHR), (JFK, YYZ),
(SIN, KUL), (BOS, JFK).

`aHomeWhereNothingPaysStillGetsAdviceAndSaysSo()` pins Nadi: the player is
never left without a first route, and the card tells the truth about it.

---

## 11. The estimator against the real ledger (MEASURED)

The gate is only worth having if reality agrees with it, so this was measured
**before** the estimator was used to rank anything. Seven pairs, six months
flown through the real pipeline; "after everything" is the ledger's own bottom
line, including the $150k a month of airline overhead the estimate
deliberately does not charge to one route.

**Before (the traps, and the sound recommendations):** sign agrees **7 of 7**,
and the estimate is optimistic by $0.3M–0.8M a month. A market the estimate
calls dangerous is therefore dangerous in the ledger too, with margin. That is
the direction a gate needs.

**After (what the fixed ranking now recommends, flown for real):**

| Pair | km | Airframe | Ledger, after everything | Margin |
| --- | ---: | --- | ---: | ---: |
| SIN–CGK | 884 | MR180 | **+$653k** | 17% |
| JFK–ORD | 1,187 | MR180 | **+$545k** | 14% |
| ARN–LHR | 1,462 | MR180 | **+$1.06M** | 26% |
| KEF–LHR | 1,896 | AV90 | **+$276k** | 15% |
| BGO–LHR | 1,042 | KT72 | **−$11k** | −1% |

And the pairs the gate now rejects, flown on the same basis: MAN–LHR −$1.18M,
LHR–CDG −$1.38M, SIN–KUL −$684k, JFK–YYZ −$494k a month.

**The one that does not clear, recorded rather than papered over.** BGO–LHR is
estimated at +$264k a month after its airframe and lands at −$11k after
everything. About $150k of that gap is airline overhead the estimate does not
charge; the rest is the estimator's known optimism on thin routes — it assumes
every scheduled rotation flies (AE-040's limitation) and its demand forecast
under-reads a thin pair. **So the gate's boundary is soft by roughly a fifth
of a million a month on the thinnest markets:** it reliably rejects routes
losing half a million or more, and can pass one that lands near break-even.
Recorded as **TD-033** rather than hidden behind a safety margin no
measurement supports.

One further divergence recorded rather than smoothed: on SIN–KUL the
estimator's demand forecast is pessimistic (1,232 forecast against 1,934
carried), so its per-day direct figure has the wrong sign. The verdict is
unchanged — the route still fails by $684k a month in the ledger — but the
forecast error is real.

---

## 12. Screenshots inspected (OBSERVED)

CI run 135, economy shard, `testNewYorkAdviceIsWorthFollowing` — the journey
added this phase. It founds New York at seed 2030 through the "Somewhere else"
picker, follows the card, and photographs the result past the day the old
advice was fatal. Frames decoded from the job log and **looked at**, not
inferred from the test passing.

| Frame | What is on it |
| --- | --- |
| **AE042-1**, day 0 | Home at JFK, $60.0M, startup era. The onboarding checklist is up ("Get your airline flying"), so there is no Next Moves card yet — the card takes over only when the checklist completes. The companion frame **AE042-NO-NEXT-MOVES-CARD** records that same state deliberately. |
| **AE042-2** | Fleet: one **Pacifica PA-184 Current**, lease **$790k/mo**, at JFK, idle. This is the airframe the aircraft market's default sort offers first, so the journey buys what a new player would — and it matches the airframe every baseline figure was computed on. |
| **AE042-5**, 2 Feb 2030 | **The change, rendered.** Heading "Strong open markets from your bases:", then two recommendations, each carrying the new sentence: **JFK → MEX Mexico City**, ≈2,803 passengers/day, 3,365 km, no competition yet — *"Best on a 184-seat PA-184 Current — about $1.5M a month after its lease."* And **JFK → MIA Miami**, ≈2,799/day, 1,757 km — *"about $1.2M a month after its lease."* **Toronto is absent.** Both figures are positive, both name the airframe. |
| **AE042-7**, 11 Mar 2031 | Day 435 — past day 430, where the old advice put the player into administration. Cash **$60.2M**, net worth $60.2M, reputation 81%, month to date **$442k**, last month +$35k. The card now offers Mexico City (+$1.5M) and **Atlanta** (+$999k). |
| **AE042-8**, same day | Finance: cash **$60.2M**, **debt $0**, leverage **0%**. Revenue month to date $994k, direct costs $551k, operating profit **$442k**. The runway panel reads *"Last month made money — there is no burn to run out of."* The Feb 2031 statement below it shows airport fees −$1.1M, crew −$112k, overhead −$150k. |
| **AE042-9**, same day | Routes: **JFK–ORD** at 2×/day, load **100%**, fare $135, **+$442k this month** — the first recommendation, flown and earning. |

What these frames establish, and only this: on a booted simulator, the new
sentence renders on the card with a named airframe and a positive monthly
figure; the trap the old advice named second is not offered; and the player
who followed the advice is solvent, debt-free and profitable 435 days in,
five days past the day the old advice ended the game.

**Not established by them:** anything about a physical device, and anything
about seeds other than 2030.

### 12.1 The one failure in the run, and why it is not this change's

The arrival + shell shard failed one test, `HorizonArrivalUITests.testARivalComesToMunich()`,
at 64.7 s with *"the home picker's search field never appeared."* The other
eight tests on that shard passed, as did all six campaign journeys and all
five economy journeys.

The failure frame was decoded and inspected: it is the **new-game setup
screen**, scrolled to the difficulty section, with Barcelona still selected
and the "Somewhere else" card not yet taken. The tap on that card did not
register inside the helper's 8-second wait
(`UITests/UITestSupport.swift:1099`).

Four pieces of evidence, not an assumption:

1. **It is before the game exists.** No `GameState` has been created at that
   point, so `marketOpportunities` has not been called and `NextMovesCard` is
   not on screen. AE-042 changes only those two things.
2. **The same code path passed in the same run.** The new
   `testNewYorkAdviceIsWorthFollowing` founds New York through the *identical*
   "Somewhere else" → search-field helper and passed in 558.9 s on the economy
   shard, on the same commit, in the same run.
3. **Munich's advice is asserted unchanged.** `theCuratedStartsAdviceIsUnchanged()`
   pins MUC → [LHR, CDG] and passed with the rest of Core.
4. **Run 132 failed this same test at this same step** — the first
   search-field tap on day 1 — and run 133 then passed it green
   (docs/UI_RUNTIME_VALIDATION.md §1).

**Where the evidence stops.** In run 132 the whole shard was starved and the
shell tests ran 5× slow; here the shell clone was healthy
(`testDetailScreensAndSettingsRender` 104.2 s against 101 s in run 131), so
this was a single tap that did not take, not shard-wide starvation. Calling it
"the same starvation" would be more than the log supports. It is a failed tap
on a screen this change does not touch.

**Confirmed by the one re-run.** That shard was re-run once — the single
re-run these rules allow for a failure established as not this change's. All
nine tests passed, `testARivalComesToMunich()` among them in **471.9 s**,
against 475.1 s in run 133 and 439.2 s in run 129. The failure did not
reproduce, and the Munich journey runs its full length with this change in
place.

### 12.2 The Munich frames, looked at (OBSERVED)

From that re-run, because Munich is the world the AE-039 and AE-041 twins are
pinned on and this change had to leave it alone.

**KEY-HZ2, 4 Mar 2030** — the rival arrival is intact: *"PacificBlue entered
your MUC–IST market yesterday."* Three routes, three aircraft, 100% load,
$94k month to date.

The same frame carries the **other** heading branch, the one the compile fix
refactored: with an idle-aircraft warning above it, the card reads *"One
aircraft is idle. It costs the same parked as flying — assign it in Airline →
Routes."* then **"Or grow the network:"**, then **MUC → MAD Madrid** (≈921/day,
1,497 km) *"Best on a 184-seat PA-184 Current — about $1.2M a month after its
lease"* and **MUC → BCN Barcelona** (≈901/day, 1,094 km) *"about $435k a month
after its lease."*

So both headings and both value magnitudes were rendered on a booted
simulator, not only the happy path. (These are Munich's advice at day 63 with
London, Paris and Istanbul already served — its *first* advice is the
[LHR, CDG] the Core twin pins, and is unchanged.)

---

## 13. Bugs found

| ID | Severity | What | Status |
| --- | --- | --- | --- |
| **BUG-055** | High | Next Moves ranks markets by passengers alone; 21 of 93 homes are given a first recommendation that loses money or cannot be flown, and the scripted New York player collapses in 28 of 30 seeds | **Fixed this phase** |
| **BUG-056** | Medium | The aircraft market's default sort is seats-descending regardless of the route, so 9 homes get a recommendation that pays on a small airframe and loses on the market's first row (Reykjavík–London: **−$703k** on a 184-seat narrowbody, **+$141k** on a 90-seat regional jet) | **Open — recorded, not fixed** |
| **TD-033** | Low | The estimate is soft on thin routes by roughly $150–250k a month (BGO–LHR estimated +$264k, ledger −$11k) | **Open — recorded** |
| App compile | — | `contains(\.paysForItsAirframe)` — a key path passed to the unlabeled `contains(_:)`, which takes an element, not a predicate. Parsed on Linux, rejected by the macOS type-checker; cost CI run 134 all three simulator shards | **Fixed this phase** |

BUG-056 is a separate surface's defect. Fixing it means teaching the
acquisition screen what the route is for, which is a larger change than the
evidence for BUG-055 demands, so it is measured, written down and left.

---

## 14. Bugs fixed

**BUG-055** — §7, with before/after in §8 and the twin in §9.

**The app compile failure**, and the reason it reached a 10x-billed runner at
all. `swiftc -parse` is the only compiler check a Linux session has; it
answers syntax and type-checks nothing, so a line that reads exactly like the
`filter(\.servableNow)` above it passed every local check and killed three
simulator shards. The fix is the closure form. The durable part is that
`scripts/check-app-symbols.mjs` — which exists for precisely this class of
mistake — grew a second rule covering key paths handed to `contains`,
`remove`, `append`, `firstIndex` and `lastIndex`, all of whose unlabeled forms
want an element. **The rule was verified by reintroducing the defect and
watching it fire on the exact line with the correction in its message, then
reverting** (TESTED). It runs on the cheap Linux runner, in milliseconds,
before the macOS build starts.

---

## 15. Testing and the validation matrix

**Core suite: 457 of 457 passed, 0 failures** — locally (987.7 s of test time
on this container) and in CI run 135 (1,491.3 s), with the release build clean
under the 45-minute limit AE-041 measured. That is the 451 tests the branch
had plus the 6 added this phase. **No test was disabled, weakened, skipped,
deleted or bypassed, and no seed was changed.**

**Simulator: 20 journeys and 2 measurements, all green** (RUNTIME VALIDATED,
CI run 135) — campaign 6 of 6, economy 5 of 5 (the fifth added this phase),
arrival + shell 9 of 9. The arrival shard needed the one re-run described in
§12.1; everything else passed first time.

The six added, all in `NextMovesTests.swift`:

| Test | What it pins |
| --- | --- |
| `everyRecommendedMarketPaysForTheAircraftItNeeds(_:)` | 7 homes: nothing recommended fails to cover its airframe |
| `aMarketThatCannotPayForItsAircraftIsNotRecommended(_:)` | The 5 measured traps stay out |
| `theCuratedStartsAdviceIsUnchanged()` | The worlds the earlier twins and journeys are pinned on |
| `aRecommendationNamesTheAirframeItWasJudgedOn()` | The card's new sentence corresponds to real state |
| `aHomeWhereNothingPaysStillGetsAdviceAndSaysSo()` | Nadi: never strand the player, and tell the truth |
| `followingTheAdviceFromNewYorkDoesNotBankruptThePlayer()` | The BUG-055 campaign, as an assertion |

**Validation matrix:**

| Claim | Grade | Evidence |
| --- | --- | --- |
| The pipeline is one ranking feeding four surfaces | READ | docs/AE042_RECOMMENDATION_PIPELINE.md |
| 21 of 93 homes were given dangerous or unflyable advice | MEASURED | `ae-advice sweep`, baseline §2 |
| The mechanism is fee share rising as distance falls | MEASURED + INFERRED | distance ordering and fee shares, root cause §3 |
| The estimator agrees with the ledger in sign | MEASURED | 7 of 7 pairs, six months flown |
| The gate removes the traps | MEASURED | 21 → 9 of 93; §8.1 |
| The New York collapse is gone | MEASURED + TESTED | 28 → 0 of 30; §9 |
| The curated starts are unchanged | MEASURED + TESTED | §8.2, §10 |
| Core is green and nothing was weakened | TESTED | 457 of 457, §15 |
| The app compiles for the simulator | COMPILED | run 135, all three shards built |
| The journey renders the new advice | OBSERVED | frames inspected, §12 |
| Munich's world is unchanged | OBSERVED + TESTED | KEY-HZ2 §12.2; the curated-start twin |
| The Munich shard failure is not this change's | MEASURED | §12.1 — four lines of evidence, confirmed by one re-run |
| Anything on a physical device | **NOT VALIDATED** | no device was used this phase |
| Release readiness | **NOT VALIDATED** | not claimed |

---

## 16. Performance (MEASURED)

One `marketOpportunities` call, release build, this container, 200 runs:

| Home | Before | After |
| --- | ---: | ---: |
| New York, limit 4 | 0.267 ms | 0.301 ms |
| Stockholm, limit 4 | 0.233 ms | 0.253 ms |
| Nadi, limit 4 — worst case, nothing qualifies so the whole list is priced | 0.321 ms | 0.545 ms |

`ae-map-bench` at late-game scale (200 routes, 450 live flights): the whole map
model 1.86 → 2.00 ms per rebuild. The pricing stops as soon as `limit`
qualifying markets are found, so the typical cost is a few evaluations and the
worst case is a home where none qualifies. Nothing here runs per frame.

---

## 17. Remaining debt and release impact

**Ranked debt, all recorded in tasks/:**

1. **BUG-056** (medium) — the aircraft market sorts by seats regardless of the
   route. Nine homes still get advice that loses money if the player takes the
   first row instead of the named airframe. This is now the largest remaining
   gap between the advice and the outcome.
2. **TD-033** (low) — the estimate is soft on the thinnest routes by roughly
   $150–250k a month. It never passes a route that loses half a million; it
   can pass one near break-even.
3. **The passenger ranking itself** — among markets that pay, the order is
   still passengers per incumbent, so the recommendation is the *biggest* safe
   market, not the most profitable one. Ranking by value was measured and
   rejected (§6) because it makes every home recommend the same shape of
   route. That is a design choice this phase deliberately did not make.
4. **Nadi** — one of 93 homes has no market that covers its own airframe in
   the startup era. The card now says so. Whether such a home should be
   offered to a new player is a content question.
5. **TD-032** — a rival's entry can roll off the 512-event feed within a day.
   Untouched.

**Release impact.** The save format is unchanged, so existing saves load and
play. The change is confined to a derived read model and one card's copy; no
tuning value, fee, fare or demand parameter moved, and the rival AI is
untouched. Three curated starts produce byte-identical worlds. **Release
readiness is NOT VALIDATED and is not claimed here** — no physical device was
used this phase, and the simulator evidence in §12 is simulator evidence.

**The CI cost of this phase, recorded rather than glossed.** Run 134 lost all
three simulator shards to one line of Swift that the Linux parser accepts and
the type-checker rejects. Run 135 fixed it and added the cheap-runner rule
that catches the class (§14), then needed one re-run of one shard for a
failure established as not this change's. Two dispatches and one shard re-run
in total.

---

## 18. ONE recommended next master prompt

**AE-043 — "THE AIRCRAFT FOR THE ROUTE": fix BUG-056, so that the screen that
sells aircraft knows what the player is buying one for.**

The reason this is the next thing rather than anything else: AE-042 closed the
gap between the advice and the economy, and in doing so measured exactly where
the remaining gap is. At nine of the ninety-three homes a player can pick, the
recommendation is sound, names the right airframe, and still ends in a losing
route — because the player goes to the aircraft market, which sorts by seats
descending and defaults to lease, and takes the first row. Reykjavík–London
keeps $141k a month on a ninety-seat regional jet and loses $703k on the
184-seat narrowbody the market offers first. The advice is now right and the
purchase is still wrong.

The question to answer with evidence: **can a new player who follows the
advice and buys the obvious aircraft build a viable airline?** It should
measure the acquisition surface the way AE-042 measured the ranking — every
home, every recommendation, what the default sort offers against what the
route needs, across the ledger and not just the estimate — decide a root cause
before changing anything, and prefer the smallest change that makes the two
surfaces agree. Candidate directions, to be chosen on measurement and not in
advance: sort the market by fitness for the route in the player's current
context; carry the recommended airframe into the acquisition screen as a
default or a marker; or state the consequence at the point of purchase. It
should also decide whether TD-033's soft boundary on thin routes matters once
the right airframe is the one being bought, since several of the nine are the
same thin markets.

Explicitly out of scope for it, as here: the fare and fee economy (TD-031),
the passenger ranking's own order, the rival AI, and progression.
