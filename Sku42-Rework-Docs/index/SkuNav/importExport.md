# SkuNav/importExport.lua
- Purpose: Intended home for SkuNav route import/export logic (per the `--todo` it should absorb the import/export code still living in SkuOptions). Currently near-empty: it declares/creates the `SkuNav` AceAddon and holds one leftover migration helper `tConvert` for converting the old name-keyed link format to the new id-keyed `LinksNew` format. Effectively a stub file.

## Public API / exports
- `SkuNav` (global) — created here via `LibStub("AceAddon-3.0"):NewAddon("SkuNav", "AceConsole-3.0", "AceEvent-3.0")` if not already defined (guarded `SkuNav = SkuNav or ...`).
- `tConvert()` (global, no colon) — one-off migration: rebuilds `SkuDB.SessionRouteData.LinksNew` from legacy `tSkuLinks` (name-keyed) into id-keyed links using `WaypointCacheLookupAll` + `WaypointCache` + `SkuNav:BuildWpIdFromData`. Marked "tmp helpers, to delete after migration".

## Dependencies (outgoing)
- `LibStub("AceAddon-3.0")` — addon object creation (AceConsole-3.0, AceEvent-3.0 mixins).
- `SkuNav:BuildWpIdFromData(typeId, dbIndex, spawn, areaId)` — id builder (defined elsewhere in SkuNav).
- Globals `tSkuLinks`, `WaypointCache`, `WaypointCacheLookupAll`, `SkuDB.SessionRouteData` — read/written by `tConvert`.
- `Sku.L`, `_G` (declared, unused).

## Key data structures
- `SkuDB.SessionRouteData.LinksNew`: `sourceWpId -> { targetWpId -> distance }` (rebuilt by tConvert).
- Legacy input `tSkuLinks`: `sourceWpName -> { targetWpName -> distance }`.

## Events
- none (AceEvent mixed in but nothing registered here)

## Settings keys
- none

## Entry points
- none wired (no slash command registered despite AceConsole mixin; `tConvert` is a bare global callable only manually / from other code)

## Invariants & gotchas
- This is the canonical file that OWNS/creates the `SkuNav` AceAddon object (`SkuNav = SkuNav or ...`). Load order matters: data.lua and Visited.lua assume `SkuNav` already exists, so importExport must load before them (or the guard elsewhere covers it) — verify TOC order before moving this file.
- `tConvert` is dead migration code explicitly flagged for deletion; it silently skips links whose names miss `WaypointCacheLookupAll`, and if `tSourceId` is nil it still creates `LinksNew[nil]` (assigns to a nil key path via `LinksNew[nil] = {}`), which errors — only safe because it's meant to run in a fully-populated legacy context.
- File is mostly blank (lines 9-20) with a stale `--todo` to migrate import/export out of SkuOptions — that migration never happened; the real import/export code still lives in SkuOptions.
