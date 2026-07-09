# SkuPerfFileStamp.lua (+ _psA…_psF stub files)
- Purpose: A temporary per-file load-time measurement harness (Workstream 3 / load profiling). `SkuPerfFileStamp.lua` defines a global stamp recorder; the six one-line `_ps*.lua` stub files are interleaved in the TOC around the heavy data files (the two big route files and the SkuDB block) so the delta between consecutive stamps attributes the load-screen freeze to specific files. Measurement-only scaffolding, not a runtime feature.

## Public API / exports
- `SkuFileLoadStamps` (global array) — accumulates `{label, time}` pairs across the whole addon load.
- `SkuStampFile(aLabel)` (global function) — appends one stamp with the current high-res clock reading.
- The six stubs each make exactly one call: `_psA_start.lua` = "start (pre routedata_global_wotlk)"; `_psB_postWotlkRoutes.lua` = "post routedata_global_wotlk (~30MB)"; `_psC_preSkuDB.lua` = "pre SkuDB block (Core + modules done)"; `_psD_preGlobalRoutes.lua` = "pre routedata_global (base data done)"; `_psE_postGlobalRoutes.lua` = "post routedata_global (~18MB)"; `_psF_postSkuDB.lua` = "post SkuDB block (all data done)".

## Dependencies (outgoing)
- `GetTimePreciseSec` (preferred high-res monotonic clock), falling back to `debugprofilestop()/1000` if absent.

## Key data structures
- `SkuFileLoadStamps` — flat array of `{label:string, time:number}` in TOC load order.

## Events
- none (pure load-time execution; no frames, events, timers).

## Settings keys
- none.

## Entry points
- none directly; the stubs are load-order probes placed by their position in `Sku.toc`. The stamp dump/read is done by external tooling.

## Invariants & gotchas
- `SkuFileLoadStamps` is a STANDALONE global on purpose: Core.lua does `Sku = {}` at load, which would wipe any `Sku.*` field stamped before Core.lua runs.
- Clock choice matters: `GetTime` is frozen through the load screen (per-frame) and useless; `debugprofilestop` gets reset by Core.lua's `debugprofilestart` mid-load, so fallback stamps that straddle that reset are not comparable (the dumper shows negatives rather than lying).
- The exact stub file NAMES and their TOC positions relative to the route/SkuDB files are load-bearing — moving a stub changes what interval it measures. Whole set is a cleanup-removal candidate once load profiling is done.
