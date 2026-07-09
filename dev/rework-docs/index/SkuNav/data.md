# SkuNav/data.lua
- Purpose: Static data/constants module for SkuNav (audio-beacon navigation). Defines waypoint beacon sizes, the full set of `UNIT_NPC_FLAG_*` bitmask globals, a localized map from NPC-role flags to display names, and the parameters for the different route-recording waypoint-spacing methods. Pure declarations — no functions, no runtime logic.

## Public API / exports
- `SkuNavWpSize` (global table): maps waypoint size tier 1..5 to a numeric size (1,2,3,4,8).
- `UNIT_NPC_FLAG_*` (global constants): 27 bitmask flags for NPC roles (GOSSIP, QUESTGIVER, TRAINER, VENDOR variants, REPAIR, FLIGHTMASTER, etc.). Declared as bare globals, not localized.
- `SkuNav.NPCRolesToRecognize`: per-locale (`deDE`, `enUS`) table mapping a subset of the NPC-flag constants to human-readable role names.
- `SkuNav.routeRecordingIntWpMethods`: `names` list + `values` map keyed by localized method name, each `{rot=, dist=}` (rotation-degrees / distance-meters thresholds) for auto-placing waypoints while recording a route; "Manually" uses sentinel-huge thresholds (rot=1000, dist=100000).

## Dependencies (outgoing)
- `Sku.L` (localization table) — used to key the recording-method names/values.
- `SkuNav` global addon table (must already exist; populated by SkuNav Core / importExport).
- No WoW API calls.

## Key data structures
- `SkuNavWpSize`: tier -> size number.
- `SkuNav.NPCRolesToRecognize[locale][flag] = string`.
- `SkuNav.routeRecordingIntWpMethods = { names = {L...}, values = { [L name] = {rot, dist} } }`.

## Events
- none

## Settings keys
- none (constants only; consumed elsewhere)

## Entry points
- none (data module, no commands/hooks)

## Invariants & gotchas
- `UNIT_NPC_FLAG_*` and `SkuNavWpSize` leak into the global namespace (no `local`) — other modules rely on the globals. Renaming or localizing them would break consumers.
- `NPCRolesToRecognize` only covers `deDE`/`enUS`; any other client locale finds no table (consumers must guard). It also omits several flags present as constants (GOSSIP, PETITIONER, BATTLEMASTER, etc.) — intentional subset.
- `values` is keyed by the localized string, so it only resolves for the active locale's `L` values; the same `L[...]` lookups must match between `names` and `values`.
