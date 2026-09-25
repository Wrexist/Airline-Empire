# Airport services baseline — 15 September 2026

Recorded before production changes, against `df8754c` on
`codex/ae049-aircraft-configuration`. Existing unrelated launch/document edits
are preserved. No AGENTS.md was found.

## Audit and effect ownership

| Area inspected | Existing authoritative behavior | Decision |
|---|---|---|
| AirportManagementView / AirportBrowserView | Five real destinations: Overview, Your Network, Facilities, Competition, History; two icon-only service cards | Keep destinations; label the service destination Services; compact its header and cards |
| AirportSpec / WorldState | Runway class, terminal capacity/day, slots, demographic indices, fees, closures | Use these; no annual passenger count, runway count, airport reputation or formal hub tier exists |
| AirportFacilities / ConfigureAirportFacilitiesCommand | Airline-owned lounge and ground levels 0–2; atomic command, funds/presence/closure validation, bounded history | Preserve working command and economics |
| AirportFacilityTuning / tuning.json | Lounge $150k installation and $15k/month per level; ground $100k and $10k/month per level | Record scale scenarios before considering balance changes; no tuning changes planned |
| DemandSystem / passenger segmentation | Business/leisure competitive allocation; lounge adds 4 endpoint comfort points/level, averaged across endpoints and capped with aircraft comfort | Display actual comfort, never a fixed booking percentage or business-only claim |
| AircraftConfiguration / passenger experience | Aircraft service/comfort model, airline reputation; no separate airport happiness or complaint engine | Do not invent airport happiness/complaints; omit Food & Beverage and Wi-Fi purchases pending distinct authoritative effects and balance work |
| FlightOpsSystem / turnaround | Origin owner's ground services reduce technical dispatch risk 10%/level before storm risk is added; existing turnaround has no station service effect | Preserve weather; no claimed turnaround reduction or invented dollar savings |
| ReputationSystem | Actual daily completion/delays affect reliability/punctuality; service tier and aircraft comfort own their targets | No instant reputation bonus; test that investment alone does not change reputation |
| EconomySystem / ledger / Finance | Full monthly station charge under overhead, airport memo; installation under overhead; no proration/refunds | Surface recurring commitments in Finance; test actual engine boundaries and restored state |
| Persistence / migrations | Optional airline facilities/history decode old saves; v13 current format | This phase changes no persisted shape; retain existing save behavior, test codec round trips |
| AirportInvestmentPreview / route economics | Pure copied demand allocation plus shared aircraft economics; subtract incremental station cost once | Add honest allocated-demand totals and operational coverage; do not persist quotes |
| GameController / UI quote invalidation | Quote keyed only by day and levels | Refresh on relevant simulation input changes including paused commands |
| UI/Core tests | Eight airport Core tests; actual iPhone/iPad investment journey; hosted light/dark/AX5 evidence | Extend reset, confirmation, loss, ownership, deterministic previews, month boundaries and scale measurements |

## Architecture and product constraints consulted

`tasks/CURRENT_PHASE.md`, `tasks/BUGS.md`, `tasks/TECH_DEBT.md`,
`docs/GAME_EXPERIENCE_PRIORITY.md`, `ARCHITECTURE.md`,
`SIMULATION_ARCHITECTURE.md`, `PERSISTENCE_ARCHITECTURE.md`,
`UI_ARCHITECTURE.md`, `AE051_AIRPORT_MANAGEMENT.md`, AETheme, AEType and Vocab.
The priority documents emphasize honest economics, command-driven UI, reliable
saves and decoded runtime evidence. The current branch's later working systems
take precedence over older roadmap entries.

## Known limitations before work

- Route coverage currently includes routes without operational aircraft.
- Airport preview can be stale after a same-day fare/fleet/route change.
- Cards lack explicit current/proposed labels and show per-level prices rather
  than the selected tier's actual price. Header and repeated billing copy are tall.
- Finance groups airport spending with overhead, without a station commitment list.
- Existing monthly test calls EconomySystem directly; it does not demonstrate
  real boundary scheduling, save/load at a boundary or subsequent removal.
- No trustworthy expected cash value exists for avoided disruptions. A ground
  investment is deliberately negative in the direct cash forecast.

## Intended scope

Improve the real two-service investment system rather than selling unsupported
services. Food/Wi-Fi, segment-specific airport utility, complaint events, airport
happiness/reputation and turnaround bonuses are explicitly omitted. They require
their own effect ownership and measured balance; no placeholder purchase controls
or fake statistics will be introduced. No service photography is used.

Keep installation non-refundable, incremental upgrades chargeable, downgrades
free, ground effects immediate for future departures, lounge demand updated at
the next daily allocation, and recurring charges assessed at the next monthly
boundary from the configuration then installed. Preview taps never mutate state.
