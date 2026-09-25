# Progression & Contracts — implementation and evidence

## Result

The Progression screen is now a campaign, not a table of codes. It opens on
**your airline's chapter**: the era, when it began and how much has happened in
it, with the campaign's own totals. Then **next chapter** — what the next era
asks for, how far along each requirement is, and what it opens that this era
does not. Then the work in flight: **active commitments** with live progress
bars and deadlines, the monthly **optional contracts**, and **capability
programmes** ordered running-first. Then **honours** with the day each was
earned, and a **campaign log** — the dated record of completed work, so the
story outlives the fast-moving event feed.

The one Core change that makes this possible is a bounded, dated progression
record persisted with the save (format **v14**, migrated). Nothing about the
simulation's behaviour changed: the same milestones, achievements, programs,
missions and eras fire, and every moment is logged where it already happened.

## Audit before implementing

Audited at `30fa396` on `codex/ae049-aircraft-configuration`, before any
change. Existing unrelated edits were preserved.

| Area inspected | Existing authoritative behavior | Decision |
|---|---|---|
| `ProgressionView` (OperationsView.swift:531) | Era card, missions card, `ContractBoard`, a flat capability list and an honours list, in one scroll. | Move to its own file and rebuild as a campaign screen. |
| `ProgressionState` | `era`, `milestones`/`achievements` (codes, **no dates**), `activePrograms`, `completedPrograms` (codes, no dates), `missions` (**active only**), counters, `gameOver`. | Add a dated, bounded `record`; leave every existing field's meaning untouched. |
| `ProgressionSystem` | Daily: completes programs, advances the era, fires milestones/achievements, resolves and offers missions. | Note each completion into the record at the same point; no logic change. |
| `MissionMath` / `Mission` | One measurement for the bar and the payout; missions are offers, ignoring is free. | Keep; the commitments card renders the model's progress. |
| `ContractOffer` / `ContractBoard` | One offer per calendar month, real deadline, no penalty for missing. | Keep `ContractBoard` as the opportunities card; do not duplicate its rules. |
| `ProgressionModel` | Era, next era + requirements, capability states, missions, milestone/achievement codes. | Add counters, the record, what the next era unlocks, and when the era began. |
| Event feed | Bounded (512) and fast-moving; a completion can roll off within a day. | Not a history; the record is the retained one. |
| Persistence / migrations | v13 current; `marketMoves` set the pattern for a new bounded record. | Add `record` as **v13 → v14**, set to empty for older saves. |

### What the audit found, and what it refused to do

- **Completion records exist but are undated and partial.** Milestones,
  achievements and completed programs are retained as bare codes; missions are
  removed as soon as they resolve. There is no retained history of completions
  with dates, and no mission history at all.
- **The event feed is not a substitute.** It is bounded at 512 events and can
  drop a completion within a day in a busy world (recorded as TD-032's family).
- **Nothing is reconstructed backwards.** The migration starts the log empty
  and keeps the retained codes as they are; the log begins from this build.
  Manufacturing dates for old milestones from the feed would be invention.

## Core: the campaign record

`AirlineEmpireCore/Sources/AirlineEmpireCore/Domain/Progression.swift`

- `ProgressionMoment` — one completed thing and when it happened:
  `eraAdvanced`, `milestone`, `achievement`, `capability` or
  `mission(kind, reward)`.
- `ProgressionState.record` — bounded to `recordLimit` (200), oldest dropped
  first; `note(_:at:)` is the only writer and every call site is in
  `ProgressionSystem`; `eraSince` reads the latest era advance.

`Persistence/SaveEnvelope.swift` and `Persistence/Migrations.swift`

- `SaveFormat.currentVersion` is **14**;
  `MigrationV13AddProgressionRecord` sets an empty record for older saves.
  The same pattern `world.marketMoves` used at v12.

`Session/AdvisoryModels.swift` — `ProgressionModel` gained `counters`,
`record`, `nextEraUnlocks` (the classes the next era opens) and `eraSince`.

## Screen

`AirlineEmpireApp/Sources/Screens/ProgressionView.swift` (moved out of
`OperationsView.swift`)

- `campaignHero` — era glyph, era name, "Since …" and the totals; the
  `ae-progression-era` identifier and the era name are unchanged.
- `nextChapterCard` — progress, per-requirement rows from the same `EraGate`
  arithmetic the gate uses, and the classes it opens.
- `commitmentsCard` — each mission with its kind, live progress, target,
  reward and deadline, and what counts toward it.
- `capabilitiesCard` — running first, then startable, built, and era-locked;
  the existing Start-with-confirmation flow is untouched.
- `honoursCard` — milestones and achievements with "Earned <date>" from the
  record where it is known.
- `campaignLogCard` — the latest 12 moments, newest first, as a dated
  timeline.

## Validation

**Core.** `CampaignRecordTests`: notes are bounded and oldest-first; `eraSince`
reads the latest advance; the system logs a real first flight; the model names
what the next era unlocks and exposes counters and the record; a v13 payload
without a record migrates to empty with its milestones intact; and the record
survives save/load. `LiveryMigrationTests` now expects v14.

**Runs.** Branch validation
[35084477333](https://github.com/Wrexist/Airline-Empire/actions/runs/35084477333):
the focused Core suite (which now includes `CampaignRecordTests`,
`ProgressionTests`, `AdvisoryModelTests` and `LiveryMigrationTests`) and the
release build with warnings as errors, then the iPhone journeys (airport,
passenger, fleet, finance and campaign), the iPad journeys and both hosted
capture suites.

The **full** Core suite then ran on the same revision through `ci.yml`
([35087831610](https://github.com/Wrexist/Airline-Empire/actions/runs/35087831610)):
**586 tests passed** (585 in the parallel run plus the isolated campaign test),
and the release build was clean with warnings as errors — so the new record and
the v13 → v14 migration are verified against the whole simulation and every
persistence fixture, not only the campaign filters.

## Frames inspected, and what looking found

- **Full page, light and dark, 393 pt** (`CAMPAIGN-01-*`): the chapter with its
  totals and "Since …", the next chapter's requirement rows and unlock, the
  running commitment with its bar and reward, both contract offers, the
  capability programmes ordered running-first, honours with "Earned" dates and
  the dated log.
- **iPad, regular width** (`CAMPAIGN-08-iPad-*`).
- **Large Dynamic Type** (`CAMPAIGN-07-AX5-*`, `KEY-CAMPAIGN-AX-record`).
- **Device** (`KEY-CAMPAIGN-01-chapter`, `KEY-CAMPAIGN-02-record`).

One staging defect was found by looking and fixed: the evidence fixture gave
the tourism mission a zero baseline, so its row read "81,555 of 5,000" with a
full bar. The fixture now stages it part-way through, so the frame shows a
mission in flight rather than one already past its target.

One cosmetic limitation is recorded rather than claimed clean: at the largest
accessibility size a long word in the chapter header can break mid-syllable
("destina-tions"), the same shared-`Text` behaviour noted on the Finance
review. It is legible and unchanged from other screens.

### Screenshot evidence map

| Requested evidence | Evidence |
|---|---|
| Actual iPhone screenshot | `KEY-CAMPAIGN-01-chapter`, `KEY-CAMPAIGN-02-record` (iPhone simulator, dark) |
| Full-page native capture | Hosted `AX-COMPONENT-CAMPAIGN-01-light` / `-dark`, 393 pt |
| Light and dark | Hosted `CAMPAIGN-01-*` and `CAMPAIGN-08-iPad-*` |
| Large Dynamic Type | Hosted `CAMPAIGN-07-AX5-*`; device `KEY-CAMPAIGN-AX-record` |
| iPad | Hosted `CAMPAIGN-08-iPad-*`; device `KEY-CAMPAIGN-01-chapter` on the iPad shell |
| The record, dated | `KEY-CAMPAIGN-02-record`; the "Earned …" lines in the hosted frames |

Local exports are under `build/ae-run-35084477333` on the machine that ran the
review; the GitHub run retains the `airport-review` artifact with the source
PNGs, manifests and logs.

## Next recommendation

From `docs/NEXT_SCREEN_REVAMPS_2026-09-15.md`, the next slice is the **Home
Briefing** (`BriefingView.swift:18`): consolidate onboarding, next moves,
solvency, rivals, the next era, the pulse, stats, yesterday, upcoming events
and the feed into a short decision hierarchy — urgent action, airline
performance, next opportunity, then history — with each recommendation saying
why it matters and linking to its real action. The document's Core note is
that any new combined prioritisation belongs in a pure read model, and the
validation must cover a mature network as well as the first-flight state.
