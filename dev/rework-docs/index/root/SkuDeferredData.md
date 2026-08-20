# SkuDeferredData.lua
- Purpose: Lazy loader for large SkuDB datasets whose data files are wrapped as builder FUNCTIONS (e.g. `SkuDBBuildRouteGlobal`, produced by _wrap_deferred.py) so the expensive table construction is deferred out of the file-load phase (W3 load profiling / DB rework). Provides the single chokepoint `Sku:EnsureData(key)` that consumers call at their entry points; build cost is recorded into the load timeline and the perf probes.

## Public API / exports
- `Sku.DeferredData` — registry state: `{registered = {key -> {builderGlobalNames}}, unused = {key -> {skippedBuilderGlobalNames}}, ready = {key -> true}, failed = {key -> true}, buildMs = {key -> ms}, buildSteps = {…}, buildWorkers = {name -> isAliveFn}}` (last two added in #15).
- `Sku:RegisterDeferredData(aKey, aBuilderNames, aUnusedBuilderNames)` — register a dataset's list of GLOBAL builder function names, plus (optional) the builders this flavour deliberately does NOT run.
- `Sku:EnsureData(aKey)` — guarantee the dataset is built; idempotent and cheap once ready; returns true/false (false = failed). Runs each builder under pcall; nils the builder global after success — and the UNUSED ones too, or a section skipped for this flavour would save the construct time but none of the memory (frees ~48 MB of pinned source strings for the route builders) and forces a full GC after a successful build; on failure logs to SkuErrorLog, prints, and SPEAKS a German error via OutputStringBTtts.
- `Sku:IsDataReady(aKey)` — non-forcing readiness check for continuous consumers (e.g. the SkuMob scanner skips a tick instead of blocking mid-frame).
- [W6-B #15] `Sku:RegisterBuildStep(aSpec)` — register a cross-family post-login build step `{name, after = {bare family names}, once = default true, run = function(ctx) … end}`; appended to `Sku.DeferredData.buildSteps`. SkuDB/ChunkLoader's scheduler runs it the moment its `after` families are ready. `ctx.yield()` = frame-budget yield BETWEEN atomic sub-steps (NEVER inside a pcall — the yield-across-pcall crash); `ctx.fail(fam, msg)` = per-family failure isolation. Registered by SkuNav (waypoint cache), SkuQuest (quest tail), SkuAuras (value lists).
- [W6-B #15] `Sku:RegisterBuildWorker(aName, aIsAliveFn)` — register a background build coroutine's liveness probe into `buildWorkers` so the shared budget arbiter can count live workers. Registered by ChunkLoader ("skudbStream") and SkuNav ("waypointCache").
- [W6-B #15] `Sku:BuildFrameBudgetMs()` — the shared frame-budget arbiter: returns `150 / <count of live workers>` (min 1 → 150), i.e. 75 each while both the SkuDB stream and the wpc build run, 150 alone. Each side owns its own probe, so neither names the other's coroutine.
- Registration at load: `routes` is built from the per-SECTION builders the two wrapped route files define (`SkuDBBuildRoute{Wotlk,Global}{WaypointsNew,Waypoints,SequenceNumbers,WaypointLevels,Links}`, _wrap_deferred.py mode "sections"). TBC runs every `…Global*` section plus `SkuDBBuildRouteWotlkLinks` (only the WotLK LINKS are read — the union); Era runs the `…Global*` sections only. Everything else goes in as `aUnusedBuilderNames`. Saves ~265 ms on TBC / ~375 ms on Era per login, ROUTE-LINK-BUILD-PLAN.md section 13. `/skucheck routes` asserts no `SkuDBBuildRoute*` global survives EnsureData.

## Dependencies (outgoing)
- Sku (Core.lua: MetricPoint, Probe), _G builder globals defined by the wrapped data files, SkuErrorLog + SkuOptions.Voice (call-time, failure path only), debugprofilestop, collectgarbage.

## Key data structures
- `Sku.DeferredData` (see above). Three-state semantics: not-ready / ready / FAILED — failed never re-loops and never claims ready (risks A9/A10 of DB-RESTRUCTURE-PLAN).
- [W6-B #15] `buildSteps` (array of step specs, iterated by SkuDB/ChunkLoader's SkuDBRunReadySteps) and `buildWorkers` (name→liveness-fn map, counted by BuildFrameBudgetMs). This file only DECLARES these tables + the register/arbiter functions; the SCHEDULING lives in ChunkLoader — the inversion that lets the DB loader stay generic while modules own their build tails.

## Events
- none

## Settings keys
- none

## Entry points
- none directly; the "routes" dataset is built via `Sku:EnsureData("routes")` from SkuNav:LoadDefaultMapData (the single chokepoint every nav path passes).

## Invariants & gotchas
- `failed[key] = true` is set BEFORE running builders so a builder error can never cause an infinite rebuild loop; ready is only set after ALL builders succeed.
- Builder globals are nil'ed after success — nothing may call a builder twice or hold a reference; a rebuild after EnsureData is impossible by design (relevant to the lever-E reset paths).
- Unregistered keys are trivially ready (returns true) — a typo'd key silently "succeeds"; consumers must use the exact registered key string.
- Never yield inside the pcall'd builders (the coroutine-in-pcall instance-reload crash lesson); builds run synchronously behind the loading screen.
