# Finance — Profit, Cash Flow & Commitments — implementation and evidence

## Result

The Finance tab now answers three questions in order, as three labelled
groups: **Operating performance** (this month to date, from the ledger's live
month accumulator, plus the network's direct contribution), **Cash movements**
(operating, capital and financing cash, and the net change, with the note that
cash change is not profit), and the last closed month's **statement**, grouped
as a P&L with the largest cost first and a link from each expense to the
screen that owns the decision. **Monthly commitments** follows: leases, loan
payments, station services (links), payroll and overhead, and the total.

Nothing about the simulation changed. The only Core edits are a read-only
ledger accessor and a new pure read model.

## Audit before implementing

Audited at `5c7b5f6` on `codex/ae049-aircraft-configuration`, before any change.
Existing unrelated edits were preserved.

| Area inspected | Existing authoritative behavior | Decision |
|---|---|---|
| `FinanceView` / `FinanceContent` | Cash, net worth, debt, leverage; a route-direct "operating profit" strip; monthly net-profit chart; runway disclosure; best/weakest routes; a flat statement list; an airport-services-only commitment card; loans. | Regroup; keep the chart, runway, route extremes and loans. |
| `Ledger` / `MonthlyStatement` | Categorized signed postings and closed statements; `monthAccumulator` holds the live month but had no read accessor. | Add `monthTotals(for:)` (read-only, does not drain); derive everything else. |
| `TransactionCategory.classification` | Exhaustive P&L classification (operating revenue/expense, financing, capital). | Use it to split the month's cash movements; never restate it. |
| `StatementRollupSystem` | Closes the previous month **before** the boundary's new billings, so a statement contains exactly the previous month's postings. | Do not change. State the timing on screen. |
| `EconomySystem` (monthly) | Payroll from fleet + route counts, base overhead, station services (inside `.overhead`), and loan interest + principal. | Quote the recurring charges from the same constants; note that stations land in overhead. |
| `FleetBillingSystem` (monthly) | Lease billing. | Quote the monthly lease bill; link to Fleet. |
| `CreditMath` / `Loan` | Annuity payments, debt ratio, offered rate. | Keep the loan sheet and payoff flow unchanged. |
| `NetworkSummary` | Route-direct month-to-date revenue/costs/profit. | Keep as the "routes this month" line, labelled as direct contribution. |
| Persistence / migrations | v13 current; ledger, statements and loans already persisted. | No persisted shape changed. |
| Tests | `FinanceTests` (loans, statements, solvency, save/load), `SummaryModelTests`. | Add `FinanceBreakdownTests` for the split, the read accessor and the commitments. |

### Old explanations that were misleading

- The strip called the **route-direct** figure "operating profit". It excludes
  maintenance, leases, payroll, overhead and loan service. It is now "Routes
  this month — direct contribution", with the exclusions named, and the
  fully-loaded operating profit sits in the operating group.
- The first closed statement omits the boundary's fixed charges (the rollup
  runs before them). The screen now says the monthly charges land in the
  following month's statement, so the first month is not read as a full month.
- Nothing claims money is reserved: commitments are stated as charges assessed
  at the boundary, and the cash group says plainly that cash change is not
  profit.

## Core read model

`AirlineEmpireCore/Sources/AirlineEmpireCore/Session/FinanceBreakdown.swift`

- `MonthFlow` — this month's totals split by classification: operating
  revenue, operating expenses, financing and capital movements, plus
  `operatingProfit`, `netCashChange` and `hasOperatingActivity`.
- `RecurringCommitments` — leases, loan payments, station services (with the
  per-airport amounts), payroll and overhead, from the same tuning and
  contracts the monthly systems bill.
- `FinanceBreakdown` — the three groups in one value; `GameState
  .financeBreakdown(for:catalog:)` derives it purely from the ledger and
  statements.

`Ledger.monthTotals(for:)` is the read-only accessor beside the existing
`drainMonthAccumulator`.

## Screen

`AirlineEmpireApp/Sources/Screens/FinanceView.swift`

- `operatingPanel` — this month to date (revenue, operating costs, operating
  profit) and the network's direct contribution line.
- `cashPanel` — from operations, capital movements, loan interest, net cash
  change, and the cash-in-hand note.
- `statementCard` — the closed month, grouped into revenue, operating costs,
  the operating line, financing and net, with capital movements behind a
  disclosure. Every cost with an owner links out (fuel/fees/crew/revenue →
  Routes; maintenance and leases → Fleet; onboard service → Passenger
  experience).
- `commitmentsPanel` — the recurring charges, with leases and station
  services linked, and the boundary-timing note.
- The loan sheet, payoff flow, solvency banner, runway disclosure, monthly
  chart and best/weakest routes are unchanged. The statement header keeps its
  exact `"Mar 2030 statement"` shape and the `"Net profit"` label, which a
  journey queries.

## Validation

**Core.** `FinanceBreakdownTests`: the month totals read without draining;
`MonthFlow` splits by classification and its cash change differs from operating
profit; an empty month has no flow; recurring commitments equal the lease rate,
loan payment, station monthly, payroll formula and base overhead; the breakdown
is deterministic and does not mutate; and the latest statement crosses the
month boundary.

**Runs.** Branch validation
[35066817316](https://github.com/Wrexist/Airline-Empire/actions/runs/35066817316):
the 169-test focused Core suite (which now includes `FinanceBreakdownTests`,
`FinanceTests` and `SummaryModelTests`) and the release build with warnings as
errors, then the iPhone journeys (airport, passenger, fleet and finance), the
iPad journeys and both hosted capture suites.

The **full** Core suite then ran on the same revision through `ci.yml`
([35074093478](https://github.com/Wrexist/Airline-Empire/actions/runs/35074093478)):
**580 tests passed** (579 in the parallel run plus the isolated campaign test),
and the release build was clean with warnings as errors, covering the read-only
ledger accessor and the new read model against the whole simulation.

## Frames inspected, and what looking found

- **Full page, light and dark, 393 pt** (`FIN-01-breakdown-*`): the three
  groups, the chart, the grouped statement with its links, and the commitments
  panel with the total.
- **iPad, regular width** (`FIN-08-iPad-*`, `KEY-FIN-01-groups` on the iPad
  shell).
- **Large Dynamic Type** (`FIN-07-AX5-*`, `KEY-FIN-AX-groups` at
  AccessibilityL): the rows stack rather than squeezing a figure onto its
  label, and Borrow stays reachable.

One layout decision came from looking: the figure rows use `ViewThatFits`, so a
long label and its money stack at large text rather than colliding.

One cosmetic limitation is recorded rather than claimed clean: at the very
largest accessibility size (AX5) the shared `AESectionHeader` wraps a long
single word mid-syllable ("Operating perfor-mance") because the icon keeps its
place. It is legible and unchanged from every other screen that uses the
component; fixing it means changing `AESectionHeader` app-wide, which is not
this phase's scope.

### Screenshot evidence map

| Requested evidence | Evidence |
|---|---|
| Actual iPhone screenshot | `KEY-FIN-01-groups`, `KEY-FIN-02-linked-expense` (iPhone simulator, dark) |
| Full-page native capture | Hosted `AX-COMPONENT-FIN-01-breakdown-light` / `-dark`, 393 pt |
| Light and dark | Hosted `FIN-01-breakdown-*` and `FIN-08-iPad-*` |
| Large Dynamic Type | Hosted `FIN-07-AX5-*` (375 pt); device `KEY-FIN-AX-groups` |
| iPad | Device `KEY-FIN-01-groups` on the iPad shell; hosted `FIN-08-iPad-*` |
| Expense links to its decision | `KEY-FIN-02-linked-expense` (Fuel opens the Routes board) |

Local exports are under `build/ae-run-35066817316` on the machine that ran the
review; the GitHub run retains the `airport-review` artifact with the source
PNGs, manifests and logs.

## Next recommendation

From `docs/NEXT_SCREEN_REVAMPS_2026-09-15.md`, the next slice is **Progression
& Contracts** (`OperationsView.swift:531`): a clear next goal, active
commitments and optional opportunities, unlocks and costs explained before
acceptance, and a discoverable record of completed work. The document warns
that a persistent mission history may need bounded state and migration, and
that past completions must never be manufactured from incomplete event data —
so the first step there is to verify what retained completion record actually
exists before designing a history.
