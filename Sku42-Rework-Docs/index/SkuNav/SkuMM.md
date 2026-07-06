# SkuNav/SkuMM.lua
- Purpose: Implements the visual map rendering for SkuNav: (a) drawing waypoints and route lines onto the standard WoW Minimap (SkuNav:DrawAll path) and (b) the "Sku extra minimap" (SkuMM) — a large, standalone, movable/resizable world-map window (SkuNavMMMainFrame) built from 63x63 BLP map tiles with pan/zoom, a player arrow, waypoint/route overlay, quest-waypoint filters, a zone dropdown, and a developer-only polygon-recording toolbox (world/fly/faction zone polygons written into SkuDB.Polygons). This window is a sighted-helper / mapping-contributor tool rather than a screen-reader feature; it is toggled by the showSkuMM setting.

## Public API / exports
- SkuNav:SkuNavMMOpen() — main entry: lazily builds the whole SkuNavMMMainFrame UI on first call, then shows/hides it and restores size/position/collapse state from settings; hides the frame when showSkuMM is off.
- SkuNav:DrawAll(aFrame) — standard-Minimap overlay entry (called from SkuNav Core's minimap update loop); creates the texture/frame pools on first use, then clears and redraws waypoints when the global SkuDrawFlag is true.
- SkuNav:DrawTerrainData(aFrame) — draws SkuCoreDB.TerrainData points on the minimap; effectively dead (its only call site at line 264 is commented out, and it references DrawLine before that local exists — would hit a nil global if ever called).
- SkuNavDrawWaypointsMM(aFrame) — global; redraws all waypoints (with quest-filter, zone-select and link lines) onto the SkuMM overlay; also self-throttles by setting SkuNavMmDrawTimer from the drawn-widget count.
- SkuNavDrawLine(...) — global; rotated-texture line renderer for the SkuMM overlay (texture pool + precalculated sin/cos tables).
- SkuNavDrawWaypointWidgetMM(...) — global; acquires a pooled texture and places one waypoint dot on the SkuMM draw layer.
- SkuNavMMGetCursorPositionContent2(), SkuNavMMContentToWorld(x, y), SkuNavMMWorldToContent(y, x) — global coordinate converters between screen cursor, SkuMM content-frame space and world yards (tile size 533.33 yd).
- SkuNavMMContentToWorld/WorldToContent argument order is asymmetric (one takes x,y, the other y,x) — easy to misuse.
- Internal helper families: MinimapPointToWorldPoint/WorldPointToMinimapPoint (real-minimap projection using the indoor/outdoor zoom radius table), DrawWaypoints/DrawLine/DrawWaypointWidget/ClearWaypoints (minimap pools), ClearWaypointsMM/DrawPolyZonesMM/SkuNavMMUpdateContent (SkuMM pools, tile retexturing per continent), RotateTexture (player-arrow texcoord rotation), CreateButtonFrameTemplate (backdrop-frame pseudo button used for all SkuMM toolbox buttons), StartPolyRecording (begins a SkuDB.Polygons capture).

## Dependencies (outgoing)
- SkuNav Core.lua functions: GetBestMapForUnit, GetCurrentAreaId, GetAreaData, ListWaypoints2, GetWaypointData2 (waypoint cache API).
- SkuSettings:Sub("SkuNav") for all persisted state; SkuQuest (BuildQuestZoneCache, GetAllQuestWps, QuestWpCache, QuestZoneCache) for the quest-waypoint filter.
- SkuDB: Polygons (data + eTypes), questDataTBC, InternalAreaTable; SkuCoreDB.TerrainData (dead path).
- Sku.Loc for localized comments/zone names; SkuPrintMT metatable for the polygon read/write editbox round trip.
- WoW API: CreateFrame, CreateTexturePool, CreateFramePool, UnitPosition, GetPlayerFacing, GetCVar("minimapZoom"), Minimap/MinimapCluster, GetInstanceInfo, GameTooltip, PlaySound, loadstring (dev read button).
- Asset files under SkuNav/assets/ (line/line64 textures, MinimapData BLP tiles per continent, player_arrow, resize/expand button textures). Note the tile textures are gitignored binary assets.

## Key data structures
- minimap_size — indoor/outdoor radius per Minimap zoom level (0-5); basis for minimap projection.
- tSkuNavMMContent — array of {obj, x, y, w, h} for all 63x63 tile frames plus containers; iterated every content update to reposition/rescale by tSkuNavMMPosX/Y and tSkuNavMMZoom (file-local pan/zoom state).
- tContintentIdDataSubstrings — continentId -> MinimapData subfolder name (azeroth/kalimdor/expansion01/northrend); tile textures are swapped when the player's continent changes.
- SkuLineRepo/SkuWaypointWidgetRepo (minimap pools, widget repo is a deliberate global) and SkuWaypointWidgetRepoMM/SkuWaypointLineRepoMM (SkuMM texture pools, globals).
- SkuNavRecordingPoly / SkuNavRecordingPolySub / SkuNavRecordingPolyFor — globals holding the in-progress polygon type/subtype and its index in SkuDB.Polygons.data; nodes are appended elsewhere (SkuNav Core movement hook) while recording.
- Waypoint color coding by tWP.typeId: 1/4 red (custom/quest), 2 pink or teal by spawnNr, 3 green (object), else white; selectedWaypoint drawn larger.
- SkuNavMmDrawTimer (global) — adaptive redraw interval for the SkuMM overlay OnUpdate; SkuDrawFlag (global, set elsewhere) gates the minimap redraw.

## Events
- No RegisterEvent here. Two OnUpdate drivers: SkuNavMMMainFrameScrollFrameContent (pan-drag + tile reposition every 0.1 s) and ...Content1 (waypoint/polygon overlay redraw every SkuNavMmDrawTimer seconds, plus follow-player recentering and player-arrow rotation).
- Mouse scripts: OnMouseWheel zoom (0.01–150x), left-drag pan, OnDragStart/Stop window move, resize-button sizing loop.

## Settings keys
- SkuSettings:Sub("SkuNav") (profile): showRoutesOnMinimap (gates minimap drawing), showSkuMM (gates the whole SkuMM window), selectedWaypoint (read, for highlight), SkuNavMMMainIsCollapsed, SkuNavMMMainWidth/Height/PosX/PosY (window geometry, written on drag/resize/collapse).

## Entry points
- SkuNav:SkuNavMMOpen() is invoked from SkuNav Core/options when showSkuMM toggles or at load; SkuNav:DrawAll from the minimap update cycle.
- Mouse-only toolbox buttons inside the window: Follow, World/Fly/Alli/Horde/Aldor/Scryer/Other Start + End (polygon recording), Write/Read (serialize SkuDB.Polygons.data through the edit box via tostring/loadstring), Filter/Starts/Objectives/Finish/Limit (quest wp filters), zone-select dropdown.
- No slash commands, keybinds, or secure buttons.

## Invariants & gotchas
- Whole window is mouse-driven and sighted-oriented; it is a mapping/dev tool, not part of the accessible flow — keep it out of keyboard nav assumptions.
- The "Read" button executes loadstring on edit-box text into SkuDB.Polygons.data (dev-only; would be a script-injection surface if ever exposed further).
- DrawWaypoints (minimap path) reads SkuNavMMShowCustomWo/SkuNavMMShowDefaultWo at line 237 BEFORE the `local` declarations at lines 451-452, so it sees nil globals (condition still works because (nil==true or nil==true)==false); the locals only scope the SkuMM functions and SkuNavMMOpen. Fragile if reordered.
- tWP at line 202, tOldMMZoom/tOldMMScale (183-190), tUnitDbWaypointData-style leaks: several implicit globals; SkuNavDrawWaypointsMM keeps its own `local tWP`.
- First-call-builds-UI: SkuNavMMOpen assumes _G["SkuNavMMMainFrame"] existence check is the only guard; all sub-frames are looked up via _G by name, so renaming any frame string breaks many call sites.
- The overlay pools parent to SkuNavMMMainFrameScrollFrameMapMainDraw1 which must exist before SkuNavDrawWaypointsMM runs (created inside the same first-open branch).
- SkuNavMMUpdateContent retextures all 3969 tiles on continent change — expensive; do not call per frame outside the throttle.
