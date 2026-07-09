# SkuNav/Options.lua
- Purpose: Defines SkuNav's user-facing settings (SkuNav.options AceConfig-style args table, SkuNav.defaults, and the W1/W2 SkuSettings:Register schema) and builds the whole SkuNav menu tree via SkuNav:MenuBuilder — the "Navigation" branch of the Sku menu: deselect-all, waypoint selection (recent / current map by distance / whole continent / with auto-wps), nearby-route entry points, quick waypoints by coordinates, route following ("Route folgen" with "Ziele Entfernung" metaroute targets and "Einheiten Route" NPC-spawn routes), and the Options leaf. Also contains the timing fix that re-populates the beacon click-clack soundset list after SkuBeaconSoundsets registers.

## Public API / exports
- SkuNav.options — menu/settings definition table (beacon volume/soundsets, click-clack, direction/distance vocalization, visited tracking, gather waypoints, minimap/SkuMM toggles, tomtomWp, autoNextWaypoint group, routesMaxDistance, ...). Some nodes keep inline get/set/OnAction closures (beaconSoundSetNarrow/Wide play a sample beacon; showGatherWaypoints rebuilds map data + waypoint cache + quick wps).
- SkuNav.defaults — default values matching the schema.
- SkuNav.ClickClackSoundsets, SkuNav.StandardWpReachedRanges, SkuNav.RoutesMaxDistances — value tables for select nodes.
- SkuNav:getAnnotatedWaypointLabel(originalLabel, id) — prefixes a waypoint menu label with visited marker and layer text; inserts a space so TTS does not glue ";" to a leading distance number (comment at lines 366-371 explains the digit-by-digit TTS bug).
- SkuNav:MenuBuilder(aParentEntry) — builds the whole SkuNav menu subtree through SkuMenu:Build specs + SkuOptions:InjectMenuItems; ends with a schema-managed "settings" spec binding SkuNav.options.args to SkuSettings:Sub("SkuNav").
- Internal helpers: SkuSpairs (sorted pairs iterator, file-local copy), SkuNav_MenuBuilder_WaypointSelectionMenu (per-waypoint submenu: Auswählen + Nahe Routen with metaroute end-target scoring).

## Dependencies (outgoing)
- SkuMenu:Build + SkuOptions:InjectMenuItems / SkuGenericMenuItem / SkuOptions:EditBoxShow / SkuOptions:CloseMenu (SkuZOptions menu framework).
- SkuSettings (Register schema + Sub("SkuNav") everywhere, including one global-scope key hasCustomMapData in commented code).
- SkuNav Core.lua: SelectWP, EndFollowingWpOrRt, ClearWaypointsTemporary, CreateWaypoint, UpdateQuickWP, GetAllMetaTargetsFromWp5, GetAllLinkedWPsInRangeToCoords, GetNearestWpsWithLinksToWp, ListWaypoints2, GetWaypointData2, Distance, GetDirectionToAsString, GetLayerText, GetNonAutoLevel, GetAreaIdFromUiMapId, GetUiMapIdFromAreaId, GetSubAreaIds, GetCurrentAreaId, GetAreaData, GetBestMapForUnit, GetWorldCoordinatesFromZone, StripBaseNameFromWaypointName, InjectWpListEmptyHint, LoadDefaultMapData, CreateWaypointCache, GetNpcRoles; constants MaxMetaEntryRange, MaxMetaWPs, BestRouteWeightedLengthModForMetaDistance.
- SkuNav/Visited.lua (waypointWasVisited, clearVisitedWaypoints); SkuOptions.BeaconLib (sample beacons, GetClickClackSoundSets, GetBeaconStatus, DestroyBeacon); SkuOptions.Voice:OutputStringBTtts; SkuDispatcher:TriggerSkuEvent; SkuDB (NpcData, InternalAreaTable); Sku.L / Sku.Loc.
- WoW API: UnitPosition, C_Map.GetWorldPosFromMapPos, CreateVector2D, C_Timer.After, PlaySound, CreateFrame.

## Key data structures
- metapathFollowing* state bundle stored in SkuSettings:Sub("SkuNav"): metapathFollowing (bool), metapathFollowingStart / Target / EndTarget / TargetName, metapathFollowingMetapaths (map target-wp-name -> {pathWps = {names...}, distance, distanceToStartWp}), metapathFollowingCurrentWp, metapathFollowingUnitDbWaypoint(+Data), plus TMP staging (metapathFollowingStartTMP and the GLOBAL SkuMetapathFollowingMetapathsTMP).
- Waypoint label wire format: "<distance>;Meter[;<direction>]#<realWaypointName>" — menu code repeatedly splits on "#" to recover the real name; getAnnotatedWaypointLabel prepends "visited;<layer> ".
- SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_NPC / _CloseRoute — cross-menu handoff globals-on-SkuOptions set by OnEnter and consumed by the Auswählen OnAction (select plain wp vs. build+start a close-route).
- tUnitDbWaypointData — NPC-route staging table mapping full waypoint name -> extra-waypoint coordinate list from SkuDB.NpcData.Data[npc][8]; note it is an implicit GLOBAL (line 1151).

## Events
- One anonymous frame registers PLAYER_ENTERING_WORLD and, 2 s later (C_Timer.After + pcall), rebuilds SkuNav.ClickClackSoundsets from SkuOptions.BeaconLib:GetClickClackSoundSets() and re-points options.args.clickClackSoundset.values (41.05 timing-race fix; additive no-op on failure).
- SkuDispatcher:TriggerSkuEvent published: SKU_CLOSEROUTE_STARTED, SKU_WAYPOINT_STARTED, SKU_NAVIGATION_STOPPED, SKU_UNITROUTE_STARTED, SKU_ROUTE_STARTED.
- C_Timer.After used for sample-beacon teardown and the two-step x/y coordinate edit boxes.

## Settings keys
- Registered schema (all profile scope): beaconVolume, beaconSoundSetNarrow/Wide, clickClackEnabled/Range/Soundset, vocalizeFullDirectionDistance, vocalizeZoneNames, nearbyWpRange, standardWpReachedRange, autoGlobalDirection, showGlobalDirectionInWaypointLists, trackVisited, timeForVisitedToExpire, showGatherWaypoints, showRoutesOnMinimap, showSkuMM, tomtomWp, autoNextWaypoint.nonVocalized, autoNextWaypoint.reachRange, outputDistance, routesMaxDistance.
- Read/written outside the schema (runtime nav state, same Sub): selectedWaypoint, routeRecording, RecentWPs, WaypointsTemporary, metapathFollowing* family, lastSelectedWaypointFullName (on SkuNav itself); SkuSettings:Sub("SkuNav", nil, "global").hasCustomMapData (commented-out blocks only).

## Entry points
- SkuNav:MenuBuilder is called by the menu framework to populate the Navigation branch; leaf OnAction/OnEnter/BuildChildren closures are the actual behavior carriers.
- No slash commands, keybinds, or secure buttons in this file.

## Invariants & gotchas
- Select value tables are keyed by the STORED value: number keys for standardWpReachedRange/timeForVisitedToExpire/routesMaxDistance, string keys for soundsets — the schema comment (lines 301-309) documents this contract; don't change key types.
- timeForVisitedToExpire is stored as index N meaning N-1 minutes (default 6 = 5 minutes); Visited.lua does the -1 math.
- The "#"-suffix label convention couples label building and name recovery across this file, getAnnotatedWaypointLabel and Core.lua; changing the separator breaks selection everywhere.
- SkuBeaconSoundsets registers its click sounds only at PLAYER_ENTERING_WORLD; the clickClackSoundset values list must be refreshed AFTER that (the tCCFixFrame nachzieher) — do not "simplify" back to synchronous population.
- The "Daten" import/export menu is deliberately hidden behind `if false then` (lines 1224-1268, user request 41.02.08) with a documented rollback path; a dangerous "delete all routes" node was removed in 41.01.03 — keep both dead blocks' intent in mind before deleting.
- showGatherWaypoints OnAction must call LoadDefaultMapData(true) rather than hand-wiring SessionRouteData (DB rework lever E comment, lines 193-197): the TBC link half is freed after login.
- Menu state passes through OnEnter side effects (SkuNav_MenuBuilder_WaypointSelectionMenu_NPC/_CloseRoute, tQWPNumber on parent) — reordering entries or skipping OnEnter breaks OnAction.
