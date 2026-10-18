# Next screen revamps ? 15 September 2026

## Scope and evidence

Source review at `79c1e93`, following the Airport Services refresh. This is a
product and implementation audit, not a fresh simulator visual-validation pass.
No gameplay or UI code changed. Existing user changes were left intact.

Reviewed the current Home/Briefing, Airline Routes/Fleet, aircraft market,
Finance, World Events, Competitors, Progression and Reputation surfaces;
checked the reputation simulation, fleet planning, progression state, current
phase and experience-priority documents. Historical backlog items were checked
against current code rather than assumed still missing.

## Recommended order

### 1. Passenger Experience & Reputation

**Current:** `ReputationDetailView` in `OperationsView.swift:753` shows overall
reputation, five component bars and airline service tiers. Each tier tap submits
`SetServiceTierCommand` immediately. Aircraft configuration and airport services
now have richer decision flows, but their relationship to airline reputation is
not explained here. The comfort description still emphasizes newer/larger cabins,
while `ReputationSystem` uses seat-weighted `passengerComfort` from the configured
fleet.

**Revamp:** a clear overall score, five compact driver cards, current versus
proposed airline service tier, Core-backed recurring-cost comparison, review/apply,
and direct links to relevant aircraft, routes and airport services. Explain the
source and scope of each effect. Separate current reputation from its gradual
response to decisions; never imply an immediate reputation purchase.

**Core work:** a pure service-policy preview/read model and accurate explanations
of configured fleet comfort. Show cost per passenger and a stated volume-based
estimate where appropriate. Do not invent historical trends or complaint data.
Audit aircraft/airline/airport effect ownership before adding new bonuses.

**Why first:** completes the connection between the two screens just upgraded and
affects a real recurring economic decision. A bounded, high-value next feature.

### 2. Fleet Operations & Maintenance

**Current:** `FleetView.swift` already has summaries, an idle-aircraft action,
status/type/age/condition sorting and filters. Individual aircraft management is
richer than the fleet-wide overview.

**Revamp:** an actionable fleet health board: idle aircraft, current maintenance,
poor condition, assignments and upcoming returns. Use compact comparable rows and
links to the existing aircraft actions. Distinguish currently unavailable aircraft
from aircraft that merely merit inspection.

**Core work:** a shared attention/read model for ranking and maintenance impact;
use actual maintenance quotes and status. Replacement forecasts and batch economic
commands would require separate authoritative work. Do not promise them as UI-only.

### 3. Finance ? Profit, Cash Flow & Commitments

**Current:** `FinanceView.swift:29` already includes cash/net worth/debt, operating
results, monthly profit history, route winners/losers, statements, loans and the
new station commitments.

**Revamp:** clearer grouping of operating performance, cash movements and recurring
commitments; consistent period labels; a readable cost breakdown and links from
expenses to the decisions behind them. Retain existing loan/solvency workflows.

**Core work:** derived statement/ledger breakdowns as needed. Do not confuse cash
change with profit or imply money is reserved when it is not. Do not reconstruct
missing history beyond the retained ledger/statement coverage.

### 4. Progression & Contracts

**Current:** `OperationsView.swift:531` combines era requirements, missions,
`ContractBoard`, capabilities and honours in one scroll. Next-era guidance already
exists in `CampaignProgressViews.swift`; it is not a missing feature.

**Revamp:** a clear next goal, active commitments and optional opportunities, with
unlocks and costs explained before acceptance. Give completed work a discoverable
record rather than relying solely on the fast-moving operations feed.

**Core work:** verify retained completion records before designing a history.
Persistent mission history may need bounded state and migration; never manufacture
past completions from incomplete event data.

### 5. Home Briefing

**Current:** `BriefingView.swift:18` already has onboarding/next moves, solvency,
rivals, next era, pulse, stats, yesterday, upcoming events and a feed.

**Revamp:** consolidate those into a short decision hierarchy: urgent action,
airline performance, next opportunity, then history. Make recommendations explain
why they matter and link to their real action. Preserve map-first Home.

**Core work:** reuse current models; any new combined prioritization belongs in a
pure read model. Validate mature networks as well as the first-flight state.

### 6. World Events & Competition

**Current:** World Events already shows severity, forecast timing and affected
routes; Competitors already shows contested markets and direct route links.

**Revamp:** clearer grouping of current versus upcoming disruption and the player's
exposure; prioritize relevant rival moves and make route comparisons easier to
scan. Retain existing working affected-route and market-share information.

**Core work:** any new impact estimate must use actual operational/economic logic.
No invented rival intentions or guaranteed disruption savings.

### 7. Aircraft Market comparison

**Current:** `FleetView.swift:960` already has purchase terms, route selection,
route matching, filters and new/used/lease options. Historical notes claiming no
route matching are stale. `FleetPlanning.swift` explicitly describes fit ranking
as not a profit forecast.

**Revamp:** compare a small shortlist for one actual route: runway/range fit,
capacity, availability, immediate payment and recurring terms. Preserve the
existing purchase-and-assignment flow.

**Core work:** comparable economics must hold route, fare and frequency constant
and use shared allocation. Do not label the existing fit rank ?most profitable.?

## Shared visual direction

Reuse AETheme, AEType, the existing panels and semantic accents. Carry over compact
icon headers, clear metric hierarchy and current/proposed states for economic
changes. Each screen should prioritize its own player decision. Keep real
navigation destinations, readable Dynamic Type, selected-state accessibility and
light/dark support. Avoid adding tabs or decorative imagery merely for symmetry.

## Next implementation slice

Start with Passenger Experience & Reputation: baseline its real costs and effects,
create the authoritative preview, replace immediate tier commits with draft/review,
update driver explanations and add relevant navigation. Verify costs, reset,
confirmation, delayed reputation response and save/load; inspect normal iPhone,
accessibility and iPad frames. Food & Beverage / airport Wi-Fi should follow as a
separate balanced extension once effect ownership is clear.
