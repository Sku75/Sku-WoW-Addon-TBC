# SkuCore/gameWorldObjects.lua
- Purpose: The "camera sweep" world-object scanner: rotates the camera in horizontal/vertical steps while the mouse cursor is pinned to screen center, reads the GameTooltip under the cursor each frame, and voice-announces matches (lootable/skinnable corpses, creatures, quest objects, herbs, mining veins, fishing bobber, usable objects). Distinguishes creatures from world objects by correlating a frame counter with CURSOR_CHANGED/UPDATE_MOUSEOVER_UNIT event timing. Also hosts two camera utilities used addon-wide: GameWorldObjectsCenterMouseCursor (center the cursor via mouselook CVars) and GameWorldObjectsTurnToWp (turn the camera/character toward the selected SkuNav waypoint). AceAddon submodule of SkuCore (W4 Phase D/E), user-toggleable; published handle `SkuCore.GameWorldObjects`.

## Public API / exports
- SkuCore.GameWorldObjects — the module table (AceAddon submodule "GameWorldObjects", AceEvent mixin).
- GameWorldObjects:GameWorldObjectsScan(aContinue, aFindList, aHStepSizeDeg, aHStepsMax, aVMoveSpeed, aVStepsMax, aCallback, aHStart) — start or continue a camera sweep scan; drives the named frame SkuCoreGameWorldObjectsScanTicker via OnUpdate; no-op while disabled (IsEnabled guard). aFindList selects the match categories; aCallback fires on a hit with the tooltip line.
- GameWorldObjects:GameWorldObjectsCheckResult(aTextLeft1, aTextLeft2, aTextLeft3) — classify the current tooltip against the active findList; returns true (and voice-announces) on a match; dedups per session via found[aTextLeft1..mouseoverGUID].
- GameWorldObjects:GameWorldObjectsRestoreView() — end scan: stop camera movement, un-rotate accumulated yaw, restore cameraPitchMoveSpeed, SetView(2), stop background sound; guarded by the tResetRequired upvalue.
- GameWorldObjects:GameWorldObjectsCenterMouseCursor(aPos) — center the mouse cursor vertically at aPos via CursorCenteredYPos/CursorFreelookCentering/CursorStickyCentering CVars + a 0.1 s mouselook pulse. Shared utility (called by MinimapScanner and others).
- GameWorldObjects:GameWorldObjectsTurnToWp(aWaypointName) — compute bearing to a SkuNav waypoint and turn the view toward it with a timed MoveViewLeft/RightStart burst; defaults to the selected waypoint.
- GameWorldObjects:GameWorldObjectsOnInitialize() / :GameWorldObjectsOnLogin() — arming bodies (events + frame counter / char scanConfigs defaults); called from OnEnable.
- GameWorldObjects:OnEnable() / :OnDisable() — arm / disarm (restore view, UnregisterAllEvents, stop frame counter).
- Event methods: CURSOR_CHANGED, CURSOR_UPDATE, UPDATE_MOUSEOVER_UNIT — stamp lastCursorUpdateFrame / lastUpdateMouseoverUnitFrame with the current frame-counter value while a scan is active; the CURSOR handlers also forward to SkuCore.MinimapScanner:MinimapScannerCURSOR_CHANGED (an empty stub).
- Internal: GameWorldObjectsVoiceOutput(aText, aSound) — BTTS text (priority 4) plus optional sound via OutputString.

## Dependencies (outgoing)
- SkuCore.MinimapScanner — sets/clears .noMouseOverNotification around scans; forwards cursor events to its stub.
- SkuCore.RessourceTypes (from minimapScanner.lua — load-order coupling) for herb/vein name matching.
- SkuDB: NpcData.Names[locale] (creature check), objectLookup[locale] and SpellDataTBC (object check).
- SkuQuest:GetAllQuestObjects() (ObjectCurrentQuest category).
- SkuNav: GetWaypointData2, GetDirectionTo (TurnToWp); SkuOptions.db.profile["SkuNav"].selectedWaypoint.
- SkuUtil:Unescape (tooltip line normalization); SkuSettings facade; SkuOptions.Voice; SkuOptions:StartStopBackgroundSound; SkuCore.CameraSkuStandardActive (camera-decoupling gate); dprint; Sku.L / Sku.LocP / Sku.toc.
- WoW APIs: camera control (FlipCameraYaw, MoveViewUp/Left/Right Start/Stop, SetView, MouselookStart/Stop, SetCVar cameraPitchMoveSpeed/cameraYawMoveSpeed/Cursor* CVars), GameTooltip line frames, UnitName/UnitGUID/UnitIsDead("mouseover"), UnitPosition.

## Key data structures
- GameWorldObjects.gameWorldObjectsScanFrame — the named scan ticker frame; carries the whole scan state as fields: isScanningActive, isScanningPaused, findList, found (dedup set keyed name..GUID), hStepSizeDeg, hStepsMax, vMoveSpeed, vStepsMax, callback, CameraYaw (accumulated), CameraYawMod (+1/-1 sweep direction), DownSteps, stopUpFlag, oldCameraPitchMoveSpeed.
- findList categories checked in GameWorldObjectsCheckResult: CorpseLootable, CorpseSkinnable, CorpseNotLootable, CreaturePlayerTarget, CreatureAny, ObjectCurrentQuest, ObjectHerb, ObjectVein, Bobber, ObjectUsable, ObjectAny, Any. Creature-vs-object discrimination = frame-counter equality of the cursor/mouseover event stamps.
- GameWorldObjects.gameWorldObjectsFrameCounter — integer incremented every frame by the counter frame (wraps at 40000); lastCursorUpdateFrame / lastUpdateMouseoverUnitFrame compare against it.
- Char-scope scanConfigs[1..8] — default scan presets {type=n, objects={…}} seeded in GameWorldObjectsOnLogin (consumed by the scan keybind/menu layer elsewhere).

## Events
- AceEvent RegisterEvent: CURSOR_CHANGED (Sku.toc > 11403) OR CURSOR_UPDATE (older), plus UPDATE_MOUSEOVER_UNIT; all unregistered wholesale in OnDisable via UnregisterAllEvents.
- Two OnUpdate drivers: the frame-counter frame (SkuCoregameWorldObjectsFrameCounter, every frame) and the scan ticker (SkuCoreGameWorldObjectsScanTicker, one tooltip probe + yaw step per frame while scanning).
- C_Timer.After: 0.1 s mouselook pulse in CenterMouseCursor; turn-duration timer in TurnToWp.
- No SkuDispatcher usage in this file.

## Settings keys
- SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[1..8] — written (defaults seeded on enable).
- SkuSettings:Sub("SkuCore").ressourceScanning.herbs[x] / .miningNodes[x] — read (per-resource enable in ObjectHerb/ObjectVein branches).
- SkuSettings:Sub("SkuCore").scanBackgroundSound — read (scan background loop).
- SkuOptions.db.profile["SkuNav"].selectedWaypoint — read (TurnToWp default).

## Entry points
- SkuCore.GameWorldObjects:GameWorldObjectsScan — called from Core.lua keybind handlers (scan config keys) and stopped by PLAYER_STARTED_MOVING handling in Core.lua.
- GameWorldObjectsCenterMouseCursor / GameWorldObjectsTurnToWp — cross-module utilities (MinimapScanner, SkuNav/keybind layer).
- Toggleable-module registration ("Spielweltobjekte" / "World objects") → Features menu node.
- AceAddon OnEnable/OnDisable lifecycle.

## Invariants & gotchas
- Tooltip lines pass through tostring(SkuUtil:Unescape(...)) ON PURPOSE: downstream compares against the literal string "nil" (e.g. aTextLeft2 ~= "nil"), so SkuUtil's real-nil return must be coerced (comment lines 35-39). Do not "fix" this to real nils without rewriting CheckResult.
- Creature/object discrimination depends on the frame counter and the event handlers ONLY stamping while isScanningActive and not paused — reordering the pause flag writes in the scan OnUpdate breaks classification.
- The scan mutates cameraPitchMoveSpeed and accumulates CameraYaw; GameWorldObjectsRestoreView must run on every exit path (it un-rotates by CameraYaw * -1). tResetRequired guards double-restores.
- Camera decoupling (41.02.07): SetView(2) snaps only when SkuCore:CameraSkuStandardActive() — the `not SkuCore.CameraSkuStandardActive or …` pattern must be preserved (documented rollback: replace with plain SetView(2)).
- Load order: reads SkuCore.RessourceTypes which is defined in minimapScanner.lua — that file must load first (it does per the TOC today).
- Scan state lives as fields ON the named global frame, so a /reload wipes it but a mid-session re-enable reuses the same frame (frame is find-or-create).

Notable cleanup candidates:
- Double voice output in the creature branches: taTextLeft1InCreaturesCheck() itself calls GameWorldObjectsVoiceOutput on a match (line 262) and returns true, after which every caller calls GameWorldObjectsVoiceOutput AGAIN (e.g. lines 280, 297) — the same find is announced twice.
- The five creature branches and four object branches in GameWorldObjectsCheckResult are heavy copy-paste (same condition scaffold, same found[]-set + announce + return true body); a table-driven matcher would collapse ~200 lines.
- ObjectHerb/ObjectVein have their taTextLeft1InObjectsCheck guard commented out (lines 408-420, 430-442) — dead commented code plus asymmetry with the other object branches.
- Commented-out Questie_BaseFrame show/hide blocks in RestoreView and Scan (lines 160-164, 585-589) — dead code.
- Bobber branch writes found[aTextLeft1] = aTextLeft1 in addition to the normal found[name..id] key (line 453) — inconsistent dedup key, likely leftover.
