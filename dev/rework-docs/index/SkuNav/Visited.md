# SkuNav/Visited.lua
- Purpose: Tracks which navigation waypoints the player has recently "visited" so SkuNav can avoid re-announcing farmed hostile NPCs/objects. Maintains an in-memory dict of waypoint-name -> last-visit server timestamp, with expiry driven by user settings. Small helper layer on top of SkuNav's waypoint data.

## Public API / exports
- `SkuNav:setWaypointVisited(wpName)` — records now (GetServerTime) as visit time, but only for objects (typeId 3) or role-less hostile-assumed NPCs (typeId 1 or 2 with empty role); gated by the `trackVisited` setting.
- `SkuNav:waypointWasVisited(wpName)` — returns bool; false if tracking off or never visited; expires (and clears) the entry once older than `(timeForVisitedToExpire - 1) * 60` seconds; `timeForVisitedToExpire == 1` -> expire time 0 means never-expire (always true once visited).
- `SkuNav:clearVisitedWaypoints()` — resets the whole visited dict.

## Dependencies (outgoing)
- `SkuSettings:Sub("SkuNav")` — reads `trackVisited` and `timeForVisitedToExpire`.
- `SkuNav:GetWaypointData2(wpName)` — resolves waypoint record (typeId/role) in `setWaypointVisited`.
- `GetServerTime()` (WoW API) — timestamps and expiry math.
- `Sku.L` (declared, unused here).

## Key data structures
- `waypointVisitedDict` (file-local): `wpName (string) -> lastVisitedServerTime (number)` or nil when unvisited/expired.

## Events
- none (no WoW events, no dispatcher subs; called by SkuNav navigation code)

## Settings keys
- `SkuSettings:Sub("SkuNav").trackVisited` — read (on/off gate).
- `SkuSettings:Sub("SkuNav").timeForVisitedToExpire` — read (minutes; value 1 -> never expire due to the `-1` offset).

## Entry points
- none (internal API; no slash/keybind/hook)

## Invariants & gotchas
- Expiry formula `(timeForVisitedToExpire - 1) * 60`: a setting value of 1 yields 0 = "refresh disabled" = permanently visited. Editors changing the setting's UI range must preserve this off-by-one sentinel meaning.
- `clearVisitedWaypoints` reassigns `waypointVisitedDict = {}` (new table). Fine because all access is via the upvalue closure — but any future code capturing the old table reference would go stale.
- Visited-tracking heuristic hard-codes typeId semantics (1/2 = NPC, 3 = object) and treats empty `role` as hostile; comments (lines 11-14) flag this as an intentional approximation because reliable friendly/hostile mask data isn't available in SkuDB.
