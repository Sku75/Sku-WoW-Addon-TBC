# SkuCore/minimapScanner.lua
- Purpose: Scans the minimap for gatherable resource blips (mining nodes, herbs, gas clouds) and announces them by voice with direction and distance, since a blind player cannot see the minimap dots. Two scan strategies: a fast child-frame scan (reads OnEnter tooltips of interactive minimap child frames) and a fallback "template trick" (shrink the minimap to 15x15, alpha 0, park it under the screen-centered cursor and read the GameTooltip the client renders for the blip). Also drives a passive while-moving notification (OnUpdate every 0.5 s) and a manual grid scan that sets numbered Quick waypoints via SkuNav. Implemented as an AceAddon submodule of SkuCore (W4 Phase D/E), user-toggleable via RegisterToggleableModule; published handle is `SkuCore.MinimapScanner`.

## Public API / exports
- SkuCore.MinimapScanner — the module table (AceAddon submodule "MinimapScanner", AceConsole mixin); all methods below live on it.
- SkuCore.RessourceTypes — global-ish shared table of localized resource names (chests, mining, gasCollector, herbs), each entry {deDE, enUS, zhCN, ruRU}. Also read by gameWorldObjects.lua and the SkuCore options menu.
- MinimapScanner:MinimapScan(aRange) — manual scan entry (keybind path): tries child-frame scan, else starts the slow grid scan; sets Quick waypoints from results.
- MinimapScanner:MinimapScanFast() — passive fast scan (child-frame path, else template trick); announces one found resource, dedups against the previous result.
- MinimapScanner:MinimapScanFastStop(aResult) — finalize a fast scan: speak result (escapes backslash/pipe as " slash"), clear scan flags, reset the OnUpdate timeCounter.
- MinimapScanner:MinimapStopScan() — abort any scan, restore minimap state + pre-scan zoom/rotation, cancel notification ticker, empty the voice queue.
- MinimapScanner:MinimapScanChildFrames() — scan visible Minimap children by calling their OnEnter scripts and matching tooltip lines against enabled resources; returns {resourceName = {dx, dy}} pixel offsets from minimap center.
- MinimapScanner:MinimapScanFindActiveRessource(aX, aY) — grid-scan step matcher: reads GameTooltip lines, matches enabled resources, clusters hits into tFoundPositions bounding boxes; returns the localized resource name.
- MinimapScanner:MinimapScanProcessResults() — after a scan: computes cluster centers, converts minimap pixels to world yards (tMinimapYardsMod = 3.125), speaks "<n> <name> <direction> <meters>" and sets up to 4 SkuNav Quick waypoints.
- MinimapScanner:StoreMinimap() / :RestoreMinimap() — save/restore minimap anchor, parent, scale, zoom, alpha, tooltip scale, cluster frame level/strata and per-child visibility (MMA_* fields stamped on child frames).
- MinimapScanner:MinimapScannerOnLogin() — arming body: captures tMinimapDefaults, registers /as chat commands, (re)creates the 0.5 s OnUpdate driver frame.
- MinimapScanner:MinimapScannerCURSOR_CHANGED(...) — empty stub, still called by GameWorldObjects' CURSOR_CHANGED/CURSOR_UPDATE handlers.
- MinimapScanner:SlashActiveSeekings() — /as handler: lists active tracking types (chat + TTS).
- MinimapScanner:OnEnable() / :OnDisable() — arm (calls MinimapScannerOnLogin) / disarm (stop scan, remove OnUpdate driver).
- Cross-module state flags read by others: MinimapScanner.IsMMScanning, .MinimapScanFastRunning, .noMouseOverNotification (gameWorldObjects and voiceOutput paths read these), .IsScanning (declared, seemingly unused inside this file).
- Internal helper family: tCaptureMinimapState/tApplyMinimapState/tEnterScanState (zoom/rotation/altitude-hint/tracking save-restore), PrepareMinimap, SetMinimapPosition, MinimapScanStep (recursive C_Timer.After grid driver).

## Dependencies (outgoing)
- SkuNav: Distance, GetDirectionToAsString, GetDirectionTo (indirect), GetCurrentAreaId, GetAreaData, SetWaypoint (Quick waypoints).
- SkuCore.GameWorldObjects:GameWorldObjectsCenterMouseCursor (centers the cursor before scans).
- SkuOptions.Voice:OutputStringBTtts / :StopOutputEmptyQueue; SkuOptions:StartStopBackgroundSound.
- SkuSettings facade (SkuCore namespace); SkuUtil:Unescape (fast-scan tooltip lines); Sku.LocP / Sku.L; dprint.
- Questie (optional): forcibly sets Questie.db.global.enableMiniMapIcons = false before scans.
- WoW APIs: Minimap/MinimapCluster frame manipulation, GameTooltip line reading, GetNumTrackingTypes/GetTrackingInfo/SetTracking, ToggleMiniMapRotation, GetCVar/SetCVar (rotateMinimap, minimapAltitudeHintMode), UnitPosition, GetUnitSpeed, C_Timer.After.

## Key data structures
- SkuCore.RessourceTypes — {chests=…, mining=…, gasCollector=…, herbs=…}; arrays of {deDE=…, enUS=…, zhCN=…, ruRU=…}. NOTE: the chests table is never included in any scan list (only mining/herbs/gasCollector are).
- tScanResults — {localizedName = hitCount} for the current grid scan.
- tFoundPositions — {localizedName = { {xMin,xMax,yMin,yMax}, … }} hit clusters in minimap-relative units; clustering merges hits within 20 units.
- tMinimapStore / tMinimapDefaults — saved minimap geometry (point, parent, scale, zoom, alpha, tooltip scale, cluster level/strata); defaults captured once at login, store per scan.
- MinimapScanner.minimapChildren — array of Minimap child frames, each stamped with MMA_VISIBLE / MMA_FRAME_LEVEL / MMA_FRAME_STRATA for restore.
- MinimapScanner.tMinimapScanPrevState — captured zoom/rotate/altMode/tracking state to restore after manual scans.
- toptionTypes — maps scan-list index to settings key: {"miningNodes","herbs","gasCollector"}. Declared WITHOUT local (global leak, line 243).
- tMinimapYardsMod = 3.125 — minimap-pixel-to-yard conversion at zoom 0.

## Events
- No RegisterEvent in this file; arming is OnEnable (AceAddon lifecycle), formerly PLAYER_ENTERING_WORLD.
- OnUpdate driver frame (MinimapScanner.minimapScannerFrame): every 0.5 s while the player moves (GetUnitSpeed > 0), out of combat, fires MinimapScanFast when notifyOnRessources is on.
- C_Timer.After chains: MinimapScanStep recursion (grid scan), 0.1 s tooltip-read delay in MinimapScanFast, notification resets.
- Chat commands registered via AceConsole: /activeSeekings, /as.

## Settings keys
- SkuSettings:Sub("SkuCore").ressourceScanning.miningNodes[i] / .herbs[i] / .gasCollector[i] — per-resource enable flags (read; false = skip).
- SkuSettings:Sub("SkuCore").ressourceScanning.scanAccuracyS — grid step size (read).
- SkuSettings:Sub("SkuCore").ressourceScanning.notifyOnRessources — passive-notify master switch (read in OnUpdate).
- SkuSettings:Sub("SkuCore").scanBackgroundSound — background sound name during scans (read).
- SkuOptions.db.profile["SkuNav"].selectedWaypoint — not here (that is gameWorldObjects); none other written. Writes Questie.db.global.enableMiniMapIcons (external addon SavedVariables!).

## Entry points
- Chat commands /as and /activeSeekings (SlashActiveSeekings).
- Called from Core.lua keybind handlers via SkuCore.MinimapScanner:MinimapScan / :MinimapStopScan (SKU_KEY_* scan bindings live in Core/SkuKeyBinds).
- Toggleable-module registration: SkuCore:RegisterToggleableModule("MinimapScanner", …) → Features menu node.
- AceAddon OnEnable/OnDisable lifecycle.

## Invariants & gotchas
- The grid scan physically MOVES the Minimap under the cursor and mutates zoom/rotation/tracking; every code path must end in RestoreMinimap + tApplyMinimapState or the minimap "sticks" in scan configuration (several comments document past bugs here). InCombatLockdown() blocks RestoreMinimap/tApplyMinimapState — a scan aborted in combat restores only after combat.
- Child-frame scan results must have their axes NEGATED before MinimapScanProcessResults (lines 548-565): grid convention is inverted vs. screen convention; getting this wrong puts Quick waypoints in the mirrored quadrant.
- GetTrackingInfo returns a TABLE on TBC Anniversary (not multiple returns) — every call site has a type(result)=="table" dual path; keep it when touching tracking code.
- The OnUpdate driver frame is deliberately a plain Frame (no SecureActionButtonTemplate) to avoid tainting Minimap manipulation (line 868 comment).
- MinimapScanFast hides all minimap children while the minimap sits under the cursor, otherwise child frames (MiniMapTrackingFrame) swallow the click and cause a ping sound; RestoreMinimap re-shows them via MMA_VISIBLE.
- Sound-file names containing "|" or "\" are gsub'd to " slash" before TTS (escape-sequence safety in MinimapScanFastStop).
- Fast-scan tooltip matching MUST use the substring string.find match, not exact equality — the old gmatch/exact logic silently failed on special characters (comment lines 777-783).
- Kobalt: LibRangeCheck-independent name remap "Kobaltablagerung"→"Kobaltvorkommen" exists in TWO places (lines 629-634 and 798-799); change both or neither.

Notable cleanup candidates:
- `toptionTypes` (line 243) and `tRessourceTypes` inside MinimapScanFindActiveRessource (line 303) are accidental GLOBALS (missing local); a proper local tRessourceTypes exists at line 669 and tChildRessourceTypes at 249 — three near-identical scan-list tables.
- RestoreMinimap has two ~20-line branches (defaults vs store) that differ only in the source table; StoreMinimap and MinimapScannerOnLogin duplicate the same capture block.
- MinimapStopScan calls RestoreMinimap twice and clears noMouseOverNotification three times.
- RessourceTypes.chests is defined (15 entries, 4 locales) but excluded from every scan list — dead data unless the options menu uses it.
- MinimapScannerCURSOR_CHANGED is an empty stub still invoked from gameWorldObjects on every cursor event; fx/fy locals (line 146) and MinimapScanner.IsScanning (line 138) look unused.
