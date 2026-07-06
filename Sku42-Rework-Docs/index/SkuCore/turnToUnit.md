# SkuCore/turnToUnit.lua
- Purpose: "Turn to unit" feature — rotates the camera/character to face a chosen target (party member, raid marker, or Sku marker) using view-movement CVars and a search loop that watches mouseover/nameplate events until the target is acquired. Also provides a fast 180-degree turn. A user-toggleable AceAddon submodule of SkuCore (`SkuCore.TurnToUnit`), armed on every load/reload via OnEnable.

## Public API / exports
- `TurnToUnit:OnEnable()` — arm: create control frame, register the two dispatcher callbacks, set nameplateMaxDistance CVar.
- `TurnToUnit:OnDisable()` — disarm: StopSearch + unregister the two callbacks.
- `TurnToUnit:TurnToUnit_UPDATE_MOUSEOVER_UNIT(aEvent)` — dispatcher handler; success-check the mouseover unit/marker during a search.
- `TurnToUnit:TurnToUnit_NAME_PLATE_UNIT_ADDED(aEvent, aNameplateId)` — dispatcher handler; success-check a newly added nameplate against the search target.
- `TurnToUnit:TurnToUnitStartTuring(aUnitId, aGameMarker, aSkuMarker)` — begin turning toward a unit, a game raid-target index, or a Sku raid target (note: method name is misspelled "Turing").
- `TurnToUnit:TurnToUnitTurn180()` — quick 180-degree spin.
- `TurnToUnit.availableTargetsListNames` / `TurnToUnit.availableTargetsList` — ordered name list + name→{unit, gameMarker, skuMarker} lookup (read by Options.lua for the menu).

## Dependencies (outgoing)
- SkuCore.aqCombat (`aqCombatGetSkuRaidTarget`), SkuOptions.Voice:OutputString, SkuSettings:Sub("SkuCore").turnToUnit, SkuDispatcher, Sku.L.
- WoW APIs: MoveViewRightStart/UpStart/DownStart, MouselookStart/Stop, CameraZoomIn/Out, GetCameraZoom, SetView, SetCVar/C_CVar, C_NamePlate.GetNamePlateForUnit, GetRaidTargetIndex, UnitIsUnit/UnitName/UnitGUID, C_Timer.After.

## Key data structures
- Module state on `TurnToUnit`: searching (bool), time (timeout budget or -1), unit/gameMarker/skuMarker (current search target), CameraZoom/CameraZoomSpeed (saved to restore).
- availableTargetsList: 22 entries (target, party1-4, 8 raid markers, 8 sku markers, "nothing"); value triple {unitId, gameMarkerIndex, skuMarkerIndex}.

## Events
- SkuDispatcher: registers NAME_PLATE_UNIT_ADDED, UPDATE_MOUSEOVER_UNIT (both in OnEnable, unregistered in OnDisable).
- Control frame `SkuCoreTurnToUnitControl` OnUpdate poll drives the timeout + mouseover success check. C_Timer.After delays for camera setup and 180 spin.

## Settings keys
- SkuSettings:Sub("SkuCore").turnToUnit: soundOnFail, soundOnSuccess, speed, enhancedSettings.delayOnPlate (read only; defaults set elsewhere).

## Entry points
- Menu: availableTargetsList consumed by Options.lua. Keybinds in Core.lua call TurnToUnitStartTuring/TurnToUnitTurn180. Feature toggle registered via RegisterToggleableModule.

## Invariants & gotchas
- SetView(2) camera snap only fires when SkuCore camera "SkuStandard" is active (line 266) — a 41.02.07 decoupling so free-camera users keep their view; do not unconditionally re-add SetView(2).
- StopSearch must fully reset camera CVars (cameraZoomSpeed) it clobbered; forgetting leaves the user's zoom speed at 1000.
- Method name `TurnToUnitStartTuring` is misspelled but external callers depend on it — renaming needs a coordinated sweep.
