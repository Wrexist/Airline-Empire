# AE-043 — The four designs, and the one chosen

Written after the reproduction (docs/AE043_BUG056_ROOT_CAUSE.md) and before
the production change.

## 1. The constraint the measurements impose

From the root cause, three facts bound every design:

1. **No static ordering is correct** (root cause §4.1). The right airframe
   depends on whether the route's pool saturates the cabin, so seats, range,
   fuel-per-seat and price are all wrong somewhere. Re-sorting the catalog
   only moves which homes are broken.
2. **The correct answer already exists.** `GameState.airframeResult` — the
   AE-042 function, itself built on the shipped estimator — returns the best
   flyable airframe and what it keeps. Nothing needs computing.
3. **At the decisive moment there is no route.** The checklist teaches
   `acquireAircraft` before `openRoute` (baseline §6), so the first purchase
   — $60.0M of starting cash, the purchase that decides the campaign —
   happens when no route exists to be suitable for.

Fact 3 is what disqualifies the obvious answer, and it was not visible
before Phase 1.

## 2. A discoverability number

Where Core's airframe actually sits in the shipped market, at the eleven
exposed homes (MEASURED):

| Home | Core names | Row, of 14 |
| --- | --- | ---: |
| FRA | NA160 | 10 |
| HAM, DUB, VCE | KT95 | 11 |
| EDI, NCE, GOT, KEF | AV90 | 12 |
| BLL, BGO, PMI | KT72 | 13 |

**Mean row 11.8 of 14**, and seven era-locked rows sit above the first
buyable one. This is the number that separates "mark the right row" from
"put the right row first".

## 3. The four options

### Option A — keep the sorting, add emphasis

Mark the row Core named with "Recommended for this route". No new ranking.

- **Correctness:** the right answer is on screen and labelled at all eleven.
- **Choice preservation:** perfect — nothing moves, nothing is hidden.
- **Complexity:** low.
- **Weakness:** the label sits at row 11.8 of 14, below seven locked rows the
  player cannot buy. A player who does not scroll the whole list never sees
  it. Correct but not discoverable.

### Option B — route-context sorting

On arriving from a route, sort the market by suitability for it.

- **Fails on fact 3.** At the first purchase there is no route, so the option
  does nothing precisely where BUG-056 costs the most.
- **Fails on the rules.** "Suitability" over a static catalog is a new
  ranking; the phase forbids inventing a weighted score, and the only
  non-invented measure — `monthlyAfterAirframe` — is a property of a
  (route, airframe) pair, not of an airframe, so it cannot order the market
  when no route is in scope.
- **Regression surface:** every entry point into the sheet would need a route
  to thread, and one (Fleet → Acquire) has none by construction.
- **Ruled out**, on measurement, not on taste.

### Option C — put the evaluated choice first, leave the market intact

A pinned section above the market listing exactly one row: the airframe Core
named for the market the game is currently recommending, with what it keeps
and which pair it was judged on. The fourteen rows follow, in their existing
order, unchanged.

- **Correctness:** the right answer is row one at all eleven.
- **Choice preservation:** all fourteen rows remain, in the same order, with
  the same deal controls. The recommended aircraft also remains in its own
  place in the list.
- **Complexity:** low — one Core derivation reusing `airframeResult`, one
  section in the sheet.
- **No new ranking:** the market's own order is untouched; the pinned row is
  a *recommendation*, not a re-sort.
- **Chosen.**

### Option D — filter to viable aircraft

Not implemented, and the measurements say never: at Bergen it would delete
ten of fourteen rows, including NA70 at **+$238k a month** — a legitimate
choice a player might well prefer to KT72's +$279k for its lower lease and
cash outlay. Hiding a profitable aircraft because the game prefers another is
exactly what Phase 5 forbids. **Ruled out.**

## 4. The comparison

| Option | Correct at the 11 | Answer's row | Choice preserved | New ranking? | Works at first purchase | Verdict |
| --- | :---: | ---: | :---: | :---: | :---: | --- |
| A — emphasis only | 11/11 | 11.8 of 14 | full | no | yes | correct, not discoverable |
| B — route-context sort | 0/11 | — | full | **yes** | **no** | ruled out |
| **C — pinned recommendation** | **11/11** | **1** | **full** | **no** | **yes** | **chosen** |
| D — filter | 11/11 | 1 | **10 of 14 rows destroyed** | no | yes | ruled out |

Option C is Option A plus the one thing A lacks, and it buys that without
taking anything from the player.

## 5. One correction the design forced

`MarketOpportunity.bestAirframe` **cannot be reused directly.**
`marketOpportunities` sets its capability basis as:

```swift
let candidateSpecs = ownedSpecs.isEmpty ? eraSpecs : ownedSpecs
```

So once the airline owns anything, `bestAirframe` is the best type it
**already owns** — the right basis for "can I fly this with what I have", and
the wrong one for "what should I buy". A pinned purchase recommendation
reading that field would tell a player who owns one turboprop to buy another
turboprop for every market, for ever.

The fix is one argument, not a new calculation: call the same
`airframeResult` with the **era** specs. The arithmetic, the estimator and
the lease-and-payroll deduction are identical; only the candidate set
differs, and it differs because the question differs.

## 6. What is deliberately not fixed

- **The market's default sort stays `seats` descending.** It is right on the
  thick majority (root cause §4), and §1 fact 1 says no reordering is right
  everywhere.
- **`hidesLocked` stays off by default.** Seven locked rows above the first
  buyable one is a real cost, but showing what a later era brings is a
  deliberate progression choice, and the pinned row now sits above all of
  them anyway.
- **The checklist order stays.** Teaching aircraft before routes is a
  pedagogy decision outside this phase; the pinned recommendation makes it
  survivable by carrying the market's identity into the purchase.
- **The ranking's fleet-limited basis stays.** Once the player owns a
  short-range aircraft, `marketOpportunities` only scores markets that
  aircraft can reach, so the purchase advice inherits that horizon and will
  not propose buying a longer-range type to open a market the current fleet
  cannot serve. That is the ranking's semantics, changing it would reopen
  BUG-055's territory, and it is recorded as debt rather than touched here.
