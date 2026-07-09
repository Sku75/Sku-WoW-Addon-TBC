# SkuNav/Geo.lua

- Purpose: The stateless geo/map-math service of SkuNav, extracted verbatim from SkuNav/Core.lua in W6-B #16. Pure map / area / coordinate / direction / distance helpers with NO beacon-navigation state, isolated so callers (SkuQuest above all — the addon's single largest inter-module edge — plus SkuCore/SkuMob) can depend on just this math instead of the whole nav runtime. Every function is still defined under the `SkuNav:` names (behaviour-identical relocation, not a rename); the `SkuNav.Geo` facade in SkuNav/Core.lua (lines ~4531-4540) exposes the same 12 as the narrow interface callers were repointed onto (`SkuNav.Geo:GetAreaData` etc.). Loaded right after SkuNav/Core.lua in the TOC (SkuNav already `NewAddon`-created there). Not an AceAddon module of its own — it just adds methods to the existing SkuNav table.

## Public API / exports
- SkuNav:GetBestMapForUnit(aUnitId) — C_Map.GetBestMapForUnit plus hardcoded zone fixups (continent-id returns 1415/1414 remapped via GetMinimapZoneText for Timbermaw/Südstrom/Wehklagen/Höhle der Nebel/Schmiedevaters Grabmal/Schwarzfelsspitze; Deeprun Tram → 2257; 126 → 125).
- SkuNav:GetDirectionTo(aP1x, aP1y, aP2x, aP2y) — returns (uhr, uhrfloat, afinal): clock o'clock 1-12 relative to GetPlayerFacing, the fractional clock, and the signed degree offset. Returns 0 on nil inputs / nil facing / target at origin.
- SkuNav:Distance(sx, sy, dx, dy) — returns (flooredDistance, exactDistance); nil if any coord missing.
- SkuNav:GetContinentNameFromContinentId(aContinentId) — SkuDB.ContinentIds[id].Name_lang[Sku.Loc]; nil if unknown.
- SkuNav:GetUiMapIdFromAreaId(aAreaId) — walk InternalAreaTable ParentAreaID chain to the root area, match against ExternalMapID.AreaId → uiMapId; memoized in the file-local GetUiMapIdFromAreaIdCache.
- SkuNav:GetAreaIdFromUiMapId(aUiMapId) — ExternalMapID[uiMapId].AreaId, with the Deeprun Tram (2257) special case.
- SkuNav:GetAreaIdFromAreaName(aAreaName) — InternalAreaTable name match constrained to the player's current uiMap.
- SkuNav:GetAreaData(aAreaId) — 6 returns: ZoneName, localized AreaName, ContinentID, ParentAreaID, Faction, Flags; nil if unknown.
- SkuNav:GetSubAreaIds(aAreaId) — set of direct + grandchild area ids under aAreaId.
- SkuNav:GetCurrentAreaId(aUnitId) — resolve the player's (or unit's) current area id from GetMinimapZoneText, falling back to the ExternalMapID name of GetBestMapForUnit.
- SkuNav:GetDirectionToAsString(tx, ty) — coarse localized compass word ("north"/"south-east"/…) from player world pos to target; "" on nil/degenerate input. Uses the file-local tDeg ladder.
- SkuNav:IntersectionPoint(x1, y1, x2, y2, x3, y3, x4, y4) — segment-segment intersection point (x, y, Ua) or nil; used by the polygon-zone test in Core.lua.

## Dependencies (outgoing)
- SkuDB: InternalAreaTable (AreaName_lang / ParentAreaID / ContinentID / ZoneName / Faction / Flags), ExternalMapID (AreaId / Name_lang), ContinentIds (Name_lang).
- Sku core: Sku.L (file-local `L`), Sku.Loc, dprint (global; used by GetAreaIdFromUiMapId + commented traces).
- Locals grabbed at file top: `L = Sku.L`, `floor = math.floor`, `sqrt = math.sqrt` (also uses math.acos/sqrt/pi/floor inline).
- WoW APIs: C_Map.GetBestMapForUnit, GetMinimapZoneText, GetPlayerFacing, UnitPosition("player").

## Key data structures
- GetUiMapIdFromAreaIdCache (file-local) — areaId → uiMapId memo; grows for the lifetime of the session (area→map mapping is static).
- tDeg (file-local) — 11-row {a = degree threshold, f = localized compass word} ladder for GetDirectionToAsString. Moved here WITH the function in the #16 fix (it was orphaned in Core.lua at the extraction; see gotchas).

## Events
- none — no frames, no AceEvent, no SkuDispatcher, no timers. Pure query functions.

## Settings keys
- none.

## Entry points
- No slash commands / keybinds / secure buttons / hooks. Every function is a query invoked by SkuNav/Core.lua (ProcessPolyZones IntersectionPoint, direction announcers) and by external modules through the SkuNav.Geo facade (SkuQuest 44 sites, minimapScanner, SkuCore/Core, SkuZOptions/utilities, gameWorldObjects — repointed in #16).

## Invariants & gotchas
- Behaviour-identical relocation: functions keep the `SkuNav:` names and byte-identical bodies; the `SkuNav.Geo` facade in Core.lua delegates (delegation-style call, NOT ref-copy, per the original author's self-binding caution). Do not "rename" these to SkuNav.Geo: — external callers reach them through the facade, internal callers still use SkuNav:.
- GetDirectionToAsString assigns aP1x/aP1y/aP2x/aP2y as bare GLOBALS (no `local`) — a pre-existing namespace leak carried over verbatim; harmless but do not treat those as locals.
- GetCurrentAreaId's first loop compares `SkuNav:GetUiMapIdFromAreaId(i) == tPlayerUIMap` where `tPlayerUIMap` is an undefined global (nil) — a pre-existing quirk that makes the first (minimap-text) match path effectively always fall through to the ExternalMapID fallback. Verbatim from Core.lua; not introduced by the extraction.
- ★#16 extraction lesson (memory `sku42-w6-cleanup`): moving a function must also carry its file-local upvalues. tDeg was left in Core.lua at Stage 1, so GetDirectionToAsString read a nil global tDeg and errored on `#tDeg`, breaking the routes (Shift-F10) and waypoints (Shift-F9) lists until b300c77 moved tDeg here and deleted the dead Core copy. AST-scan a freshly-extracted file for genuine global reads after any future extract.
- KEPT in Core.lua (NOT moved here): GetWorldCoordinatesFromZone (mapData-coupled), GetDirectionToWp / GetDistanceToWp (WaypointCache-coupled). Those touch nav state, so they stayed with the runtime.
- The memoization cache is never invalidated — correct because area↔uiMap topology is static DB data, not runtime state.
