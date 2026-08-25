# Airline Empire — Core Loop

> Phase 2 document. The moment-to-moment shape of play. Numbers here are
> design anchors; tuning lives in content (`Tuning`) and `GAME_BALANCE.md`.

## 1. The loop, one sentence

**Observe the world → decide (price, route, fleet, response) → let the
simulation run → read the consequences → decide again.**

The player alternates between *lean-back* (watching the airline operate,
skimming the feed, map ambience) and *lean-in* (a decision burst triggered by
something the simulation surfaced). The game's job is making the transition
between the two effortless and the reasons to lean in legible.

## 2. Time & speed

- Speeds: **Pause · 1× · 4× · 16×** (+ "advance to next morning" button).
- Anchor: at 1×, one game-day ≈ **6 real minutes** (heartbeat pace: watch
  individual flights); at 4× ≈ 90s (default cruising speed); at 16× ≈ 22s
  (fast-forward through stable stretches).
- Auto-pause (settable): administration risk, aircraft delivery, major event
  strike, milestone reached. Fast-forward never skips a decision the player
  opted to be paused for.
- A session of ~10 minutes must contain: ≥1 meaningful decision, ≥1 visible
  consequence of a previous decision, and ≥1 forward hook (delivery arriving,
  season turning, competitor rumor). This is the session contract the UX
  phases test against.

## 3. The daily heartbeat (simulation-driven)

Morning: flights materialize from schedules → day: departures/arrivals
stream across the map and feed, delays ripple → evening rollup: the day's
P&L, punctuality, and notable happenings condense into a digest card. The
evening digest is the game's natural breath — the moment the player is
*invited* (never forced) to lean in.

## 4. The decision surfaces

| Surface | Cadence | Decisions |
|---------|---------|-----------|
| Ops feed & map | continuous | respond to disruptions, watch, select entities |
| Evening digest | daily | triage: anything underperforming? anything to exploit? |
| Route board | weekly-ish | open/close/reprice/refrequency, aircraft reassignment |
| Fleet office | on delivery/lease events, monthly review | acquire, retire, reconfigure |
| Finance desk | monthly statement, loan events | borrow, repay, restructure |
| Capability programs | per program (weeks–months) | pick next 1–3, sequence |
| Season/cycle outlook | monthly/quarterly | position for what's coming |

## 5. Feedback contract

Every decision answers, within one game-week, through visible artifacts:
- **Immediately:** cost/commitment shown before confirm (no hidden totals);
  the change echoes in the ops feed.
- **Within days:** load factors and punctuality move; the route card trends.
- **Within weeks:** route P&L verdict; reputation components drift; the
  weekly digest names the causes (pillar 3: cards cite *why*, e.g. "load
  −12%: PacificBlue undercut fare by 18%").

## 6. Friction budget

Opening a route ≤ 4 taps from the map (select origin → destination →
aircraft/frequency/price sheet → confirm). Repricing ≤ 2 taps from a route
card. Nothing routine requires visiting more than one screen; bulk actions
(fleet-wide fare posture, pause route) exist from Phase 14, not retrofitted.

## 7. Anti-patterns (binding)

No timers that gate fun (only simulation time, which the player controls);
no attention taxes (nothing decays because the player didn't log in — the
world runs only while playing); no notification spam (digest > drip); no
decision without information; no information without a possible decision.
