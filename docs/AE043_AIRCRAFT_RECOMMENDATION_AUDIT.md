# AE-043 — What the ledger said, and why the fix was withheld

The measurement that ended this phase. Companion to
docs/AE043_BUG056_ROOT_CAUSE.md (the reproduction) and
docs/AE043_AIRCRAFT_SELECTION_DECISION.md (the design chosen before this
evidence existed).

Everything here is **MEASURED** from six months of real flying through
`ae-fee-baseline` — the ledger, not the estimate — unless a line says
otherwise.

## 1. What was built, and then taken out

Option C from the decision document was implemented in full:

- `GameState.aircraftAdvice(catalog:)` — the airframe to buy for the market
  the game is recommending, judged on what the era sells, reusing
  `airframeResult` unchanged.
- A pinned "Recommended for X–Y" section above the aircraft market, with the
  fourteen rows untouched below it.
- Ten Core tests, all passing, covering the eleven exposed homes, player
  choice, determinism, purity, and the era-versus-owned basis.

Against the estimator it worked exactly as designed: dangerous first
recommendations across the 93 homes fell **9 → 0** (`ae-advice sweep`,
`--acquire biggest` against `--acquire best`), and the pinned airframe agreed
with the Next Moves card at 11 of 11.

**Then the routes were flown, and the ledger disagreed.** All of it was
reverted. This document is why.

## 2. The ledger, six months per row

"Ledger" is the bottom line after everything — fees, fuel, crew, service,
maintenance, lease, payroll and the $150k monthly airline overhead.

| Home | Route | km | Market's first row | Ledger | The advice | Ledger | Advice better? |
| --- | --- | ---: | --- | ---: | --- | ---: | :---: |
| FRA | FRA–LHR | 653 | PA184 | −$248k | NA160 | **−$290k** | ✗ |
| HAM | HAM–LHR | 745 | PA184 | **+$158k** | KT95 | **−$93k** | ✗ |
| DUB | DUB–CDG | 785 | PA184 | **+$151k** | KT95 | **−$75k** | ✗ |
| BLL | BLL–LHR | 790 | PA184 | *cannot fly* | KT72 | −$95k | only option |
| EDI | EDI–CDG | 869 | PA184 | +$47k | AV90 | +$33k | ✗ |
| NCE | NCE–LHR | 1,041 | PA184 | *cannot fly* | AV90 | +$141k | only option |
| BGO | BGO–LHR | 1,042 | PA184 | *cannot fly* | KT72 | −$7k | only option |
| GOT | GOT–LHR | 1,068 | PA184 | +$328k | AV90 | +$265k | ✗ |
| VCE | VCE–LHR | 1,150 | PA184 | *cannot fly* | KT95 | +$155k | only option |
| PMI | PMI–LHR | 1,348 | PA184 | +$48k | KT72 | +$19k | ✗ |
| KEF | KEF–LHR | 1,896 | PA184 | **−$311k** | AV90 | **+$283k** | **✓** |
| *control* | JFK–ORD | 1,187 | PA184 | +$516k | MR180 | +$560k | ✓ (marginal) |

**Of the seven homes where both aircraft can fly the route, the advice is
worse in the ledger at six.** It is right at one — Reykjavík, where it is
right by $594k a month.

## 3. Why the estimator gets it wrong

The forecast against what actually flew, every row measured:

| Pair | Aircraft | Seats | Forecast pax/day | Actual pax/day | Error | Load |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| PMI–LHR | PA184 | 184 | 324 | 644 | **+99%** | 66% |
| EDI–CDG | PA184 | 184 | 588 | 966 | **+64%** | 82% |
| GOT–LHR | PA184 | 184 | 591 | 856 | **+45%** | 87% |
| DUB–CDG | PA184 | 184 | 817 | 1,131 | **+38%** | 95% |
| HAM–LHR | PA184 | 184 | 957 | 1,256 | **+31%** | 96% |
| FRA–LHR | PA184 | 184 | 1,376 | 1,560 | +13% | 100% |
| BLL–LHR | KT72 | 74 | 350 | 381 | +9% | 100% |
| GOT–LHR | AV90 | 88 | 612 | 586 | −4% | 100% |
| EDI–CDG | AV90 | 88 | 583 | 565 | −3% | 100% |
| NCE–LHR | AV90 | 88 | 591 | 582 | −2% | 100% |
| VCE–LHR | KT95 | 95 | 515 | 501 | −3% | 100% |
| BGO–LHR | KT72 | 74 | 347 | 331 | −4% | 100% |
| PMI–LHR | KT72 | 74 | 289 | 263 | −9% | 100% |
| HAM–LHR | KT95 | 95 | 943 | 673 | −29% | 100% |
| DUB–CDG | KT95 | 95 | 802 | 608 | −24% | 100% |

The pattern is not noise:

- **On a small aircraft the forecast is accurate** — within 9% on every row,
  usually within 4%.
- **On a large aircraft the forecast is far too low** — by 13% to 99%.

**The cause is structural.** `CompetitorAISystem.airframeDayValue` takes
`passengersPerDay` as an input that does not depend on the aircraft: it is
`expectedCapturedPassengers` at `representativeStarterQuality`, one number per
market. The simulation does not work that way — a bigger, more frequent
service **wins a larger share of the market**, so captured demand rises with
the capacity offered.

So the estimator holds capture fixed while varying seats, and therefore sees
only the extra cost of a larger cabin and none of the extra revenue. It is
biased against large aircraft by construction, and the bias grows with the
size gap. On Reykjavík — where even a PA184 flies only 52% full — the bias
does not change the answer and the estimator is right. Everywhere else it
inverts it.

The tool's own diagnostic line shows the arithmetic is otherwise sound. At
Hamburg:

```
PA184  forecast 957 pax → profit  11,313/day   actual pax → profit  31,628/day
KT95   forecast 943 pax → profit  16,361/day   actual pax → profit  10,487/day
```

Fed the forecast, the estimator prefers KT95. Fed the true passenger counts,
its own formula prefers PA184 by three to one. **The formula is fine; the
demand input is wrong.**

## 4. Why this did not show up in AE-042

AE-042 validated this estimator and found sign agreement on 7 of 7 pairs. That
result stands, and it is not in tension with this one, because the two phases
asked it different questions:

| | AE-042 | AE-043 |
| --- | --- | --- |
| Question | which **market** should I fly? | which **aircraft** for this market? |
| Aircraft held | fixed across the comparison | **the variable being compared** |
| Effect of a level error in the demand forecast | largely cancels — every candidate market is under-read | **does not cancel** — it is exactly the term that decides the right cabin size |

A forecast that is uniformly low still ranks markets correctly. It cannot rank
airframes at all, because the airframe's value *is* how much of the demand it
can carry. The estimator was fit for the purpose AE-042 put it to and is not
fit for this one. That is a limitation newly discovered here, not a defect
AE-042 missed.

## 5. What BUG-056 actually is, on ledger evidence

The reproduction (root cause §2) found 11 exposed homes using the estimator.
The ledger shrinks and re-shapes that:

| Kind | Homes | Real? |
| --- | --- | --- |
| **The market's first row cannot fly the recommended route** — a runway-class block at the home airport | **4** (BGO, BLL, NCE, VCE) | **Yes, exactly.** `routeEligibility` is arithmetic, not forecast. Nothing here depends on the estimator. |
| **The market's first row loses money in the ledger** | **2** (FRA −$248k, KEF −$311k) | **Yes, measured.** |
| The market's first row is fine, and the estimator was wrong to doubt it | 5 (HAM, DUB, EDI, GOT, PMI) | **No — these were false positives.** |

So BUG-056 is **6 of 93, not 11**, and half of it is a flyability problem
rather than an economic one. The economic half cannot currently be detected
ahead of time: the estimator identified Reykjavík correctly and five other
homes incorrectly, and nothing in the estimate distinguishes them.

## 6. Stop condition 3

> STOP if the recommended aircraft itself is economically wrong.

It is, at six of the seven homes where the comparison is possible. The fix was
therefore withheld rather than forced closed. Shipping it would have replaced
a market that is right more often than not with a recommendation that is wrong
more often than not — and, worse, would have printed a specific monthly figure
beside it. At Hamburg the card would have read *"On a 95-seat KT-95 Skylark it
keeps about $106k a month"* while the ledger took **$93k a month away**. A
confident wrong number is worse than the silence it replaced.

## 7. TD-033, and why it is now larger than recorded

TD-033 recorded the estimator as "soft on the thinnest routes by roughly
$150–250k a month", from AE-042's single BGO–LHR divergence. That framing is
too small in two ways, both measured here:

1. **It is not only thin routes.** The error is a function of the *aircraft*,
   not the market: −2% to −9% on small airframes, +13% to +99% on large ones,
   on the same pairs.
2. **It is not only a magnitude error.** On the airframe question it changes
   the answer's *sign* at six of seven homes.

TD-033 is updated rather than expanded in scope: the entry now names the
mechanism (capture held constant while capacity varies) and the measurement
above, and records that no ranking of airframes can be built on
`airframeDayValue` until it does.

## 8. What was kept

- `ae-advice market` — the mode that reproduces the shipped market's ordering
  and prices every airframe on the recommended route. Tooling only; it changes
  no product behaviour, and the next phase needs it.
- These four documents.
- **Nothing in the product.** `FleetView.swift` is at its committed state, and
  `AircraftAdvice.swift` and its tests were deleted rather than left dormant.
