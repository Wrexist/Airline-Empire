# Airline Empire — Persistence Architecture

> Phase 1 document; Phase 13 implements the full system, but the format,
> versioning, and safety rules bind from the first serialized byte (Phase 3).

## 1. What is saved

Exactly one thing: the `GameState` value, wrapped in an envelope. Because all
authoritative data lives in `GameState` (ARCHITECTURE.md §3) there is no
"partial save" problem, no cross-store consistency problem, and no save
teardown ordering problem.

```
SaveEnvelope {
  magic: "AESAVE"
  formatVersion: Int          // starts at 1, bumps on ANY shape change
  contentVersion: String      // ContentCatalog version the save was written against
  appVersion: String          // informational
  savedAtTick: SimTime
  checksum: UInt64            // FNV-1a of payload bytes
  payload: <encoded GameState>
}
```

- Encoding: JSON via `Codable` initially (debuggable, diffable); the codec is
  behind a `SaveCodec` protocol so a binary codec can replace it later purely
  as an optimization (measured in Phase 20, not assumed).
- **[RULE]** `formatVersion` bumps whenever `GameState`'s encoded shape
  changes, with a migration (or an explicit documented refusal for
  pre-release versions — allowed only until the first public TestFlight).
- **[RULE]** RNG substream states, ID allocator counters, and the command
  batch boundary are part of the save — a restored game continues
  *identically* to an uninterrupted one (tested, SIMULATION_ARCHITECTURE §6).

## 2. Storage layout

```
Application Support/AirlineEmpire/
  saves/
    slot-<n>/
      current.aesave          // latest good save
      backup-1.aesave         // previous good save (rolled)
      backup-2.aesave
      meta.json               // slot metadata for the load screen (airline name, date, net worth, playtime)
  autosave/  (same shape)
  analytics/ (bounded local metrics; loss-tolerable)
  settings.json               // app settings, not game state
```

## 3. Write protocol (crash-safe) **[RULE]**

1. Encode snapshot (off the simulation actor's hot path — snapshot is a
   value; encoding cannot race the simulation).
2. Write to `current.aesave.tmp` in the same directory.
3. `fsync` file, rename over rotation: `backup-1 → backup-2`,
   `current → backup-1`, `tmp → current` (rename is atomic on APFS/ext4).
4. Update `meta.json` last (it is derivable; corruption of meta is cosmetic).

A kill at any step leaves at least one intact prior save. Repeated saves are
bounded I/O (no append-forever files).

## 4. When saves happen

- **Autosave:** on app backgrounding (scene phase), and every N game-days of
  fast-forward (N from Tuning). Autosave never blocks the UI thread and never
  tears state (value snapshot).
- **Manual slots:** explicit player saves; same protocol.
- **[RULE]** Any destructive UI action (new game over a slot) confirms and
  the old slot's backups survive until overwritten by new *successful* saves.

## 5. Load protocol

1. Read `current.aesave`; verify magic + checksum; decode envelope.
2. If damaged → try `backup-1`, then `backup-2`; report honestly to the
   player which generation loaded ("Restored from backup — you may have lost
   ~X of play").
3. If `formatVersion < current` → run migration chain vN→vN+1→… Each
   migration is a pure function over the *decoded generic form* (JSON tree),
   registered in one table, individually unit-tested against a fixture save
   captured at that version. **[RULE]** Fixture saves are committed to the
   repo per released format version.
4. If `contentVersion` differs → content reconciliation: unknown content IDs
   in the save fail loudly (a removed aircraft type is a design bug —
   content is append-only once shipped, **[RULE]**); new content is simply
   available.
5. Validate integrity (`GameState.validateIntegrity()`), then hand to
   `GameSession`.

## 6. Failure honesty

The player is never shown "everything is fine" over a recovered/backup load,
and never loses more than the backup window silently. Corruption events are
recorded in local analytics for Phase 19/22 review.

## 7. Explicit non-goals

No iCloud sync at v1 (offline-first; sync is a Phase 24 candidate with real
conflict design, not a checkbox). No backend. No encryption (saves are the
player's own data; obfuscation adds support cost, not value).
