# SkuNav/importExport.lua
- Purpose: SkuNav's route/link data import & export. [W6-B #7] The real (de)serialization code was moved here from SkuZOptions/Core.lua so it lives with the SkuNav route data model it operates on (the old `SkuOptions:ImportWpAndLinkData`/`:ExportWpAndLinkData` were stranded in the menu framework). The dead `tConvert` migration helper and a stale commented-out older Export copy were dropped in the move. This file also creates the `SkuNav` AceAddon object (guarded), so it still doubles as the addon-object owner.

## Public API / exports
- `SkuNav` (global) — created here via `LibStub("AceAddon-3.0"):NewAddon("SkuNav", "AceConsole-3.0", "AceEvent-3.0")` if not already defined (guarded `SkuNav = SkuNav or ...`). NOTE: SkuNav/Core.lua also guard-creates SkuNav and loads earlier in the TOC, so in practice Core wins and this NewAddon is a no-op — this file's own registrations (AceConsole slash etc.) would be inert. It survives as the canonical guard only for load-order safety.
- `SkuNav:ImportWpAndLinkData()` — prompt (paste editbox) → Deserialize → replace SkuDB.SessionRouteData.Waypoints + .Links → rebuild the waypoint cache + quick waypoints, set hasCustomMapData. Speaks German success/failure lines.
- `SkuNav:ExportWpAndLinkData()` — save link data to profile, assemble {version, links, waypoints, SequenceNumbers, WaypointLevels} from SessionRouteData + SkuDB.routedata["global"], strip per-wp comments/createdAt, Serialize into the show-editbox for the user to copy. Prints per-section counts.

## Dependencies (outgoing)
- `LibStub("AceAddon-3.0")` — addon object creation (AceConsole-3.0, AceEvent-3.0 mixins), guarded.
- SkuOptions: Voice:OutputStringBTtts, Deserialize/Serialize, EditBoxPasteShow/EditBoxShow, db.global["SkuNav"].hasCustomMapData; the SkuOptionsEditBoxPaste text buffer global.
- SkuNav: CreateWaypointCache, UpdateQuickWP, SaveLinkDataToProfile.
- SkuDB.SessionRouteData (.Waypoints/.Links) and SkuDB.routedata["global"] (SequenceNumbers, WaypointLevels).
- WoW/Lua: PlaySound (88/89 open/close pings), strtrim, table.concat/insert, GetAddOnMetadata / C_AddOns.GetAddOnMetadata, Sku.L, `_G`.

## Key data structures
- Serialized export table: `{version, links = sourceWpId→{targetWpId→distance}, waypoints = array, SequenceNumbers, WaypointLevels}`.
- SkuDB.SessionRouteData.Waypoints (array, dbIndex = position) and .Links — REPLACED wholesale on import.

## Events
- none (AceEvent mixed in but nothing registered here).

## Settings keys
- `db.global["SkuNav"].hasCustomMapData` — set true after a successful import (marks the session route data as user-edited so PLAYER_LEAVING_WORLD keeps it).

## Entry points
- `SkuNav:ImportWpAndLinkData` / `:ExportWpAndLinkData` are called from `/sku import|export` (SkuZOptions/Core.lua) and the Nav > Export menu (SkuNav/Options.lua) — the 4 call sites repointed in #7 from `SkuOptions:` to `SkuNav:`.

## Invariants & gotchas
- Import REPLACES SessionRouteData.Waypoints and .Links wholesale (`= {}` then refill) and then rebuilds the cache — there is no merge; a bad paste that Deserializes but is structurally wrong could wipe live routes. Guarded by the `tSuccess ~= true` bail and the "hasCustomMapData" flag.
- The version check (`tVersion ~= 22`) is commented out — imports of any version are accepted as long as Deserialize succeeds.
- Load order: Core.lua creates SkuNav first (TOC ~line 127) and importExport loads later (~133), so the NewAddon guard here is defensive only; do not rely on this file to own SkuNav.
- Export reads `SkuDB.routedata["global"]` directly — requires the routes dataset to be built (Sku:EnsureData("routes")) before export, which the normal nav flow has already triggered.
