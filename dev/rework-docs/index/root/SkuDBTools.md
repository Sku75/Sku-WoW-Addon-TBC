# SkuDBTools.lua
- Purpose: Developer/verification tooling for the SkuDB restructuring effort (DB-RESTRUCTURE-PLAN.md). Provides three slash commands that compute deterministic fingerprints, memory estimates, and structural validation of the built game-data tables and the SkuNav waypoint cache, then speak a summary and persist the raw capture into `SkuDebugLog` for out-of-game reading by companion `_*.py` scripts. All heavy walks run sliced in a shared coroutine so they never freeze the client. This is measurement-only scaffolding, not a runtime feature.

## Public API / exports
- `SLASH_SKUDBCHECK1` / `SlashCmdList["SKUDBCHECK"]` — `/skudbcheck [label]`: deterministic per-dataset FNV-1a fingerprint + record counts of the built data tables; persists to `SkuDebugLog.dbCheck` (ring capped at 12).
- `SLASH_SKUDBMEM1` / `SlashCmdList["SKUDBMEM"]` — `/skudbmem`: per-subtree memory estimator over `SkuDB.*`, `SkuDB.WotLK.*`, `SkuDBTMP`, and the SkuNav waypoint cache; persists to `SkuDebugLog.dbMem`.
- `SLASH_SKUDBWPCHECK1` / `SlashCmdList["SKUDBWPCHECK"]` — `/skudbwpcheck`: structural type-check + wpId round-trip + lookup-consistency validation of slim waypoint-cache records; persists to `SkuDebugLog.wpCheck`.
- All helper functions (`SkuDBToolsPrint/Speak/Resolve/MixString/MaybeYield/StartJob/HashValue/RunCheck/Measure/MemTargets/RunMem/RunWpCheck`) are file-local; nothing else is exported.

## Dependencies (outgoing)
- `SkuOptions.Voice:OutputStringBTtts` (wrapped in pcall) for voice summaries.
- `SkuDB`, `SkuDB.WotLK`, `SkuDBTMP` globals (the data being measured/fingerprinted).
- `SkuNav:DevGetWaypointCacheTables()`, `SkuNav:BuildWpIdFromData()`, `SkuNav:GetWpIdForWpName()`, `SkuNav.wpCacheReady` — waypoint-cache dev accessors.
- `SkuDebugLog` global (persisted output store).
- WoW APIs: `CreateFrame`, `debugprofilestop`, `date`, `collectgarbage("count")`, `bit.bxor`, coroutine library, `string.byte/format/gmatch`.

## Key data structures
- `SkuDBToolsDatasets` — ordered list of dotted global paths (keys/legend tables, the nine convertible big tables + their WotLK twins, small eager datasets). Route data / waypoint cache deliberately excluded (mutable per session).
- `SkuDBToolsJob` — `{co, onDone, what}`; the single active coroutine job (only one runs at a time).
- `SkuDebugLog.dbCheck` entries — `{t, label, took, lines={"path|count|hash08X|nodeCount", ...}}`.
- `SkuDebugLog.dbMem` — `{t, totalMB, took, lines={"name|tables|strings|stringBytes|numbers|booleans|estKB", ...}}`.
- `SkuDebugLog.wpCheck` — `{total, byType, sessionRecords, commentsNil, shadowed, dupNames, linked, errors, examples, t, took, wpCacheReady}`.

## Events
- OnUpdate script on a hidden `SkuDBToolsFrame` pumps the active coroutine within an 8 ms/frame budget; frame Hides itself when idle. No WoW events, no SkuDispatcher subscriptions, no timers/tickers.

## Settings keys
- none (reads/writes only `SkuDebugLog`, not `SkuOptions.db`/SkuSettings).

## Entry points
- Slash commands `/skudbcheck`, `/skudbmem`, `/skudbwpcheck` (listed above). No keybinds, secure buttons, menu nodes, or Blizzard hooks.

## Invariants & gotchas
- FNV-1a is hand-rolled to stay exact in doubles (16-bit split multiply; only the low byte enters bxor) so the client `bit` library's 32-bit sign behavior can never leak in — do not "simplify" to a plain 32-bit multiply.
- `SkuDBToolsHashValue` type-tags every key and value (`s:`/`n:`/`b:`/`T{`) so nil/false/0/"" cannot collapse into the same hash; numbers formatted `%.17g` for round-trip stability. Fingerprints must be computed by the SAME code before and after a conversion, else comparisons cross implementations.
- `/skudbwpcheck` refuses to run until `SkuNav.wpCacheReady` is true (cache still building). Duplicate waypoint names are expected (last-wins name lookups); the check counts them as `dupNames`, not errors.
- Only one job runs at a time (`SkuDBToolsStartJob` rejects a second) — the shared frame/coroutine is a global singleton.
- Header comment says stage-0 tooling; if the DB rework closes this whole file is a cleanup-removal candidate.
