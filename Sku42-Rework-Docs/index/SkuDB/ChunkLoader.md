# SkuDB/ChunkLoader.lua
- Purpose: Streamed chunk loader and master init sequence for the converted SkuDB data files (DB-RESTRUCTURE-PLAN stage 3). The `SkuDB/assets/*` files register their rows as source-string chunks in a global `SkuDBChunks` list at file-load; this file, at load, only GROUPS those chunks by data family, then at PLAYER_LOGIN runs a frame-sliced master coroutine that compiles+builds the chunks, runs each family's fix + WotLK/SoD merge steps, and flips readiness flags (`Sku:IsDataReady("skudb.<family>")`) in user-relevance order. It moves the whole DB construction off the loading screen so menus stay responsive while data streams in.

## Public API / exports
- `SkuDB.chunkLoad` — build-progress state table `{families, failed, chunks, ms}`.
- `SkuDB.ChunkStreamForceFinish()` — synchronously drain the remaining stream NOW for a caller that needs complete data early (only external caller: `SkuNav/Core.lua` `EnsureWaypointCacheComplete` path). No-op if called from inside the running stream (can't resume a running coroutine).
- (module-locals, not exported) `SkuDBBudgetMs`, `SkuDBMaybeYield`, `SkuDBSpeak`, `SkuDBFail`, `SkuDBResolvePath`, `SkuDBBuildFamilyChunks`, `SkuDBMergeAbsent`, `SkuDBMasterSequence`, `SkuDBFamilyOfPath` — the internal build machinery.

## Dependencies (outgoing)
- `SkuDB.Fix*/WotLKFix*/SoDFix*` methods for each family (`FixQuestDB`, `FixCreaturesDB`, `FixObjectsDB`, `FixItemDB`, and WotLK/SoD variants) — defined in the `*_fixes.lua` asset files.
- `Sku.DeferredData.ready` / `.failed` (readiness registry), `Sku:IsDataReady`, `Sku:MetricPoint` (loadPerf capture), `Sku.IsEraSoD` (gates SoD merges).
- `SkuNav:CreateWaypointCache`, `SkuNav.wpcPendingArgs`, `SkuNav._wpcCo` (budget coordination + deferred wpc trigger).
- `SkuQuest:BuildQuestZoneCache/UpdateAllQuestObjects/CheckQuestProgress/UpdateZoneAvailableQuestList` (quest tail).
- `SkuAuras:BuildAttributeValueLists`, `SkuAuras.attributeListsPending`.
- `SkuOptions.Voice:OutputStringBTtts` (error voice line), `SkuErrorLog:Log`, `dprint`, `geterrorhandler`.
- WoW/Lua: `CreateFrame`, `PLAYER_LOGIN` event, `coroutine.*`, `loadstring`, `debugprofilestop`, `collectgarbage`, `string.gmatch/find/format`.

## Key data structures
- `SkuDBChunks` (global, consumed then niled) — array of `{targetPath, luaBodyString}`; `luaBodyString` is a `return {...}` chunk that yields rows to merge into the resolved target table.
- `SkuDB.chunkLoad.families[fam]` — list of chunks grouped by family; niled per-family as built.
- `SkuDBFamilySteps[fam]` — ordered list of atomic sub-step closures (fixes first, then WotLK merge, then SoD merge) per family.
- `FAMILY_ORDER = {"creatures","objects","quests","items","spells"}` — build order; creatures+objects first so the waypoint-cache build (which reads merged creature+object names) can start early.
- `SkuDBStreamFrame` / `SkuDBStreamCo` / `SkuDBFrameStart` — the OnUpdate driver frame, the master coroutine, and the per-frame start timestamp.

## Events
- `SkuDBStreamFrame` registers `PLAYER_LOGIN` (fires on /reload too → fresh idempotent run) and drives the coroutine from its `OnUpdate` within a per-frame time budget.
- Budget: 150 ms/frame total, split to 75 ms while the SkuNav waypoint-cache coroutine (`SkuNav._wpcCo`) is also alive (counterpart `tWpcBudgetMs` in SkuNav/Core.lua).

## Settings keys
- none directly (reads `Sku.IsEraSoD` flag, not a DB setting).

## Entry points
- No slash/keybind. Entry is the `PLAYER_LOGIN` OnEvent; external drain via `SkuDB.ChunkStreamForceFinish()`.

## Invariants & gotchas
- NEVER yield inside a pcall: Lua 5.1 cannot yield across a pcall/C-call boundary ("attempt to yield across metamethod/C-call boundary" — a real instance-/reload crash on 2026-07-06). Every fix/merge sub-step is pcall'ed and ATOMIC; `SkuDBMaybeYield()` runs only BETWEEN sub-steps, never inside one. Keep each sub-step bounded (~10-80 ms).
- Failure is per-family and non-fatal: a failed chunk/fix/merge marks the family failed, sets `DeferredData.failed`, logs+speaks once, and the sequence continues. Consumers must stay readiness-guarded (a family is absent-but-guarded or complete-including-merge, never pre-merge — risk A8).
- The quest tail requires ALL FOUR families (quests+creatures+objects+items), not just quests: `BuildQuestZoneCache` chains through `itemDataTBC` unchecked, so a failed items family would crash the tail — it is skipped instead.
- `objectLookup.enUS` is CREATED here from the merged `objectLookup.deDE` key set (objects step 4), not loaded — preserve that if refactoring merges.
- `ChunkStreamForceFinish` guards against resuming a coroutine that is `running` (called from inside the stream): it no-ops rather than erroring.
- `SkuDBMergeAbsent` is last-wins-preserving (copies only where the target key is absent) — merge order matters (base before WotLK before SoD).
