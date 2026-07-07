# SkuDB/ChunkLoader.lua
- Purpose: Streamed chunk loader and master init sequence for the converted SkuDB data files (DB-RESTRUCTURE-PLAN stage 3). The `SkuDB/assets/*` files register their rows as source-string chunks in a global `SkuDBChunks` list at file-load; this file, at load, only GROUPS those chunks by data family, then at PLAYER_LOGIN runs a frame-sliced master coroutine that compiles+builds the chunks, runs each family's fix + WotLK/SoD merge steps, and flips readiness flags (`Sku:IsDataReady("skudb.<family>")`) in user-relevance order. It moves the whole DB construction off the loading screen so menus stay responsive while data streams in.
- [W6-B #15] It is now a GENERIC SCHEDULER: it no longer hardcodes the three per-module post-login build tails (waypoint cache, quest zone-cache, SkuAuras value lists) nor reaches into their internals/pending-flags. Each owning module registers its own build step via `Sku:RegisterBuildStep{name, after=<family names>, once, run}` (infra in SkuDeferredData.lua); this loader's `SkuDBRunReadySteps()` runs each step the moment its `after` families are ready — after every family completes AND once at the end. The 150/75 ms frame budget is likewise no longer split by peeking at SkuNav's coroutine: it delegates to the shared `Sku:BuildFrameBudgetMs()` arbiter, and this loader registers its own stream coroutine as a build worker.

## Public API / exports
- `SkuDB.chunkLoad` — build-progress state table `{families, failed, chunks, ms}`.
- `SkuDB.ChunkStreamForceFinish()` — synchronously drain the remaining stream NOW for a caller that needs complete data early (only external caller: `SkuNav/Core.lua` `EnsureWaypointCacheComplete` path). No-op if called from inside the running stream (can't resume a running coroutine).
- (module-locals, not exported) `SkuDBBudgetMs` (now delegates to `Sku:BuildFrameBudgetMs`), `SkuDBMaybeYield`, `SkuDBSpeak`, `SkuDBFail`, `SkuDBResolvePath`, `SkuDBBuildFamilyChunks`, `SkuDBMergeAbsent`, `SkuDBRunReadySteps` (the #15 generic build-step scheduler), `SkuDBMasterSequence`, `SkuDBFamilyOfPath` — the internal build machinery.

## Dependencies (outgoing)
- `SkuDB.Fix*/WotLKFix*/SoDFix*` methods for each family (`FixQuestDB`, `FixCreaturesDB`, `FixObjectsDB`, `FixItemDB`, and WotLK/SoD variants) — defined in the `*_fixes.lua` asset files.
- `Sku.DeferredData.ready` / `.failed` (readiness registry), `Sku.DeferredData.buildSteps` (the #15 registered build-step list it iterates), `Sku:IsDataReady`, `Sku:MetricPoint` (loadPerf capture), `Sku.IsEraSoD` (gates SoD merges).
- [W6-B #15] `Sku:RegisterBuildWorker("skudbStream", …)` (self-registers its stream coroutine as a budget worker), `Sku:BuildFrameBudgetMs()` (shared arbiter; falls back to a flat 150 if absent). NO LONGER calls SkuNav/SkuQuest/SkuAuras build methods directly or reads their pending-flags — those modules now own their tails as registered build steps (SkuNav wpc, SkuQuest quest tail, SkuAuras value lists). It only calls each registered `step.run(ctx)`.
- `SkuOptions.Voice:OutputStringBTtts` (error voice line), `SkuErrorLog:Log`, `dprint`, `geterrorhandler`.
- WoW/Lua: `CreateFrame`, `PLAYER_LOGIN` event, `coroutine.*`, `loadstring`, `debugprofilestop`, `collectgarbage`, `string.gmatch/find/format`.

## Key data structures
- `SkuDBChunks` (global, consumed then niled) — array of `{targetPath, luaBodyString}`; `luaBodyString` is a `return {...}` chunk that yields rows to merge into the resolved target table.
- `SkuDB.chunkLoad.families[fam]` — list of chunks grouped by family; niled per-family as built.
- `SkuDBFamilySteps[fam]` — ordered list of atomic sub-step closures (fixes first, then WotLK merge, then SoD merge) per family. (Distinct from the #15 module-registered BUILD steps in `Sku.DeferredData.buildSteps` — those are cross-family tails, these are per-family fix/merge sub-steps.)
- `SkuDBBuildCtx = {yield = SkuDBMaybeYield, fail = SkuDBFail}` — [W6-B #15] the context object handed to each registered `step.run(ctx)`, so a module's build tail gets the master coroutine's frame-budget yield and the per-family failure path without needing this file's locals.
- `FAMILY_ORDER = {"creatures","objects","quests","items","spells"}` — build order; creatures+objects first so the waypoint-cache build (which reads merged creature+object names) can start early.
- `SkuDBStreamFrame` / `SkuDBStreamCo` / `SkuDBFrameStart` — the OnUpdate driver frame, the master coroutine, and the per-frame start timestamp.

## Events
- `SkuDBStreamFrame` registers `PLAYER_LOGIN` (fires on /reload too → fresh idempotent run) and drives the coroutine from its `OnUpdate` within a per-frame time budget.
- Budget [W6-B #15]: a fixed 150 ms/frame TOTAL, now split via the shared `Sku:BuildFrameBudgetMs()` arbiter — 75 ms each while both this stream and the SkuNav waypoint-cache coroutine are alive, the full 150 when this stream runs alone. This loader registers its own liveness probe (`SkuDBStreamCo ~= nil and status ~= "dead"`) as build worker `"skudbStream"`; it no longer names SkuNav's `_wpcCo` (and vice-versa).

## Settings keys
- none directly (reads `Sku.IsEraSoD` flag, not a DB setting).

## Entry points
- No slash/keybind. Entry is the `PLAYER_LOGIN` OnEvent; external drain via `SkuDB.ChunkStreamForceFinish()`.

## Invariants & gotchas
- NEVER yield inside a pcall: Lua 5.1 cannot yield across a pcall/C-call boundary ("attempt to yield across metamethod/C-call boundary" — a real instance-/reload crash on 2026-07-06). Every fix/merge sub-step is pcall'ed and ATOMIC; `SkuDBMaybeYield()` runs only BETWEEN sub-steps, never inside one. Keep each sub-step bounded (~10-80 ms).
- [W6-B #15] `SkuDBRunReadySteps` deliberately does NOT pcall-wrap `step.run(ctx)` — a registered step must pcall its OWN risky work and call `ctx.yield()` only at its top level (same yield-across-pcall landmine). The scheduler treats `run` as trivial orchestration. `once ~= false` steps are marked `_done` after firing; `once = false` steps (SkuNav's wpc safety net) stay armed and re-evaluate cheaply each pass.
- Failure is per-family and non-fatal: a failed chunk/fix/merge marks the family failed, sets `DeferredData.failed`, logs+speaks once, and the sequence continues. Consumers must stay readiness-guarded (a family is absent-but-guarded or complete-including-merge, never pre-merge — risk A8).
- [W6-B #15] The all-four-families guard for the quest tail (`BuildQuestZoneCache` chains through `itemDataTBC` unchecked, so a failed items family would crash it) now lives in the SkuQuest-registered step's `after = {quests, creatures, objects, items}` list, not here. Behaviour shift from #15: the quest tail fires after the ITEMS family instead of after spells (verified no spell dep in BuildQuestZoneCache/UpdateAllQuestObjects); everything else is behaviour-preserving.
- `objectLookup.enUS` is CREATED here from the merged `objectLookup.deDE` key set (objects step 4), not loaded — preserve that if refactoring merges.
- `ChunkStreamForceFinish` guards against resuming a coroutine that is `running` (called from inside the stream): it no-ops rather than erroring.
- `SkuDBMergeAbsent` is last-wins-preserving (copies only where the target key is absent) — merge order matters (base before WotLK before SoD).
