# SkuDB/Core.lua
- Purpose: The namespace bootstrap for the static game database module. Loaded first in the SkuDB block of the TOC, it just declares the top-level `SkuDB` table and its two expansion sub-namespaces (`SkuDB.WotLK`, `SkuDB.SoD`) that every later data/asset file and the chunk loader populate. Trivial — six lines, no logic.

## Public API / exports
- `SkuDB` — global root table for all game-data (maps, creatures, objects, items, quests, spells, waypoints, polygons, lookups).
- `SkuDB.WotLK` — WotLK-content sub-namespace (merged into base at login by the chunk loader).
- `SkuDB.SoD` — Season-of-Discovery sub-namespace (merged only when `Sku.IsEraSoD`).

## Dependencies (outgoing)
- Globals: `_G` (aliased, unused here). No libs, no WoW APIs.

## Key data structures
- `SkuDB`, `SkuDB.WotLK`, `SkuDB.SoD` — empty tables here; their shape (`NpcData`, `questDataTBC`, `questLookup.deDE`, `itemDataTBC`, `itemLookup`, `objectDataTBC`, `objectLookup`, `SpellDataTBC`, `raceKeys`, waypoint/route tables, etc.) is filled by the asset files and the chunk loader.

## Events
- none

## Settings keys
- none

## Entry points
- none

## Invariants & gotchas
- Note on the data itself: the bulk SkuDB tables live under `SkuDB/assets/` (e.g. `creatures.lua`, `items.lua`, `objects.lua`, `quests.lua`, `spells.lua`, their `WotLK/`+`SoD/` variants, and `routedata_global_wotlk.lua`) and are **gitignored generated data** (~290 MB, not hand-edited). Those files register their rows as `SkuDBChunks[...] = {targetPath, luaBodyString}` entries; `SkuDB/ChunkLoader.lua` streams and builds them at PLAYER_LOGIN. So `SkuDB.*` data tables are empty until that streamed build completes — always go through `Sku:IsDataReady("skudb.<family>")` before reading them.
- `MODULE_NAME` local is set but unused; the file must load before every `SkuDB/assets/*` file (TOC order) so the root table exists.
