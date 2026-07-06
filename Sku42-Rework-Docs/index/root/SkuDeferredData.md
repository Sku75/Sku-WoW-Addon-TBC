# SkuDeferredData.lua
- Purpose: Lazy loader for large SkuDB datasets whose data files are wrapped as builder FUNCTIONS (e.g. `SkuDBBuildRouteGlobal`, produced by _wrap_deferred.py) so the expensive table construction is deferred out of the file-load phase (W3 load profiling / DB rework). Provides the single chokepoint `Sku:EnsureData(key)` that consumers call at their entry points; build cost is recorded into the load timeline and the perf probes.

## Public API / exports
- `Sku.DeferredData` — registry state: `{registered = {key -> {builderGlobalNames}}, ready = {key -> true}, failed = {key -> true}, buildMs = {key -> ms}}`.
- `Sku:RegisterDeferredData(aKey, aBuilderNames)` — register a dataset's list of GLOBAL builder function names.
- `Sku:EnsureData(aKey)` — guarantee the dataset is built; idempotent and cheap once ready; returns true/false (false = failed). Runs each builder under pcall; nils the builder global after success (frees ~48 MB of pinned source strings for the route builders) and forces a full GC after a successful build; on failure logs to SkuErrorLog, prints, and SPEAKS a German error via OutputStringBTtts.
- `Sku:IsDataReady(aKey)` — non-forcing readiness check for continuous consumers (e.g. the SkuMob scanner skips a tick instead of blocking mid-frame).
- Registration at load: `Sku:RegisterDeferredData("routes", {"SkuDBBuildRouteWotlk", "SkuDBBuildRouteGlobal"})`.

## Dependencies (outgoing)
- Sku (Core.lua: MetricPoint, Probe), _G builder globals defined by the wrapped data files, SkuErrorLog + SkuOptions.Voice (call-time, failure path only), debugprofilestop, collectgarbage.

## Key data structures
- `Sku.DeferredData` (see above). Three-state semantics: not-ready / ready / FAILED — failed never re-loops and never claims ready (risks A9/A10 of DB-RESTRUCTURE-PLAN).

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
