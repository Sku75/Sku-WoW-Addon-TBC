local MODULE_NAME, MODULE_PART = "SkuCore", "TurnToUnit"
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- W4 Phase D: TurnToUnit is a real AceAddon SUBMODULE of SkuCore so it can be
-- turned on/off at runtime:
--   * OnEnable  arms the feature (control OnUpdate frame, the two SkuDispatcher
--     callbacks NAME_PLATE_UNIT_ADDED/UPDATE_MOUSEOVER_UNIT, and the
--     nameplateMaxDistance CVar) — formerly TurnToUnitOnInitialize/OnLogin.
--   * OnDisable disarms it (stop the search + frame OnUpdate, unregister the two
--     dispatcher callbacks), so a disabled feature genuinely does nothing.
-- AceAddon auto-enables modules when SkuCore enables (≈ PLAYER_LOGIN), replacing
-- the old explicit TurnToUnitOnInitialize/TurnToUnitOnLogin calls in Core.lua
-- (so the feature now re-arms on every /reload, not only the initial login).
-- W4 Phase E (namespace extraction): the feature's own state and methods now live
-- on the module table TurnToUnit itself (function TurnToUnit:Method); the published
-- handle SkuCore.TurnToUnit IS that module table, so external callers (Core.lua
-- keybinds via SkuCore.TurnToUnit:TurnToUnit*, Options.lua reads of
-- availableTargetsListNames) are unchanged in reach.
local TurnToUnit = SkuCore:NewModule(MODULE_PART)
SkuCore.TurnToUnit = TurnToUnit   -- keep the published handle (also the state table)

-- Make this feature user-toggleable (Features menu + persisted on/off).
SkuCore:RegisterToggleableModule(MODULE_PART, function()
   return Sku.deEn("Zu Einheit drehen", "Turn to unit", "Se tourner vers l'unité")
end)

-- W4 Phase E (namespace extraction): the feature's own state and methods now live
-- directly on the module table `TurnToUnit` (== SkuCore.TurnToUnit), not split onto
-- the shared SkuCore god-object. External callers use the published handle
-- SkuCore.TurnToUnit; in-file references use `TurnToUnit` / `self`.
TurnToUnit.searching = false
TurnToUnit.time = -1
TurnToUnit.CameraZoomSpeed = C_CVar.GetCVar("cameraZoomSpeed")
TurnToUnit.CameraZoom = GetCameraZoom()
TurnToUnit.unit = nil
TurnToUnit.gameMarker = nil
TurnToUnit.skuMarker = nil

TurnToUnit.availableTargetsListNames = {
   [1] = "target",
   [2] = "party member 1",
   [3] = "party member 2",
   [4] = "party member 3",
   [5] = "party member 4",
	[6] = "raid marker "..L["Star"],
	[7] = "raid marker "..L["Circle"],
	[8] = "raid marker "..L["Diamond"],
	[9] = "raid marker "..L["Triangle"],
	[10] = "raid marker "..L["Moon"],
	[11] = "raid marker "..L["Square"],
	[12] = "raid marker "..L["Cross"],
	[13] = "raid marker "..L["Skull"],
   [14] = "sku marker "..L["Yellow"],
   [15] = "sku marker "..L["Orange"],
   [16] = "sku marker "..L["Purple"],
   [17] = "sku marker "..L["Green"],
   [18] = "sku marker "..L["Grey"],
   [19] = "sku marker "..L["Blue"],
   [20] = "sku marker "..L["Red"],
   [21] = "sku marker "..L["White"],
   [22] = "nothing",

}

TurnToUnit.availableTargetsList = {
   ["target"] = {"target", nil, nil,},
   ["party member 1"] = {"party1", nil, nil,},
   ["party member 2"] = {"party2", nil, nil,},
   ["party member 3"] = {"party3", nil, nil,},
   ["party member 4"] = {"party4", nil, nil,},
	["raid marker "..L["Star"]] = {nil, 1, nil,},
	["raid marker "..L["Circle"]] = {nil, 2, nil,},
	["raid marker "..L["Diamond"]] = {nil, 3, nil,},
	["raid marker "..L["Triangle"]] = {nil, 4, nil,},
	["raid marker "..L["Moon"]] = {nil, 5, nil,},
	["raid marker "..L["Square"]] = {nil, 6, nil,},
	["raid marker "..L["Cross"]] = {nil, 7, nil,},
	["raid marker "..L["Skull"]] = {nil, 8, nil,},
   ["sku marker "..L["Yellow"]] = {nil, nil, 1,},
   ["sku marker "..L["Orange"]] = {nil, nil, 2,},
   ["sku marker "..L["Purple"]] = {nil, nil, 3,},
   ["sku marker "..L["Green"]] = {nil, nil, 4,},
   ["sku marker "..L["Grey"]] = {nil, nil, 5,},
   ["sku marker "..L["Blue"]] = {nil, nil, 6,},
   ["sku marker "..L["Red"]] = {nil, nil, 7,},
   ["sku marker "..L["White"]] = {nil, nil, 8,},
   ["nothing"] = {nil, nil, nil,},
}

---------------------------------------------------------------------------------------------------------------------------------------
local function StopSearch()
   TurnToUnit.time = -1
   TurnToUnit.searching = false
   TurnToUnit.unit = nil
   TurnToUnit.gameMarker = nil
   TurnToUnit.skuMarker = nil

   -- Echte Stop-Aufrufe statt Start(0). Start(0) haelt die Bewegung zwar an,
   -- laesst den Bewegungszustand aber eingeschaltet - MoveViewUpStop und
   -- MoveViewDownStop wurden in dieser Datei bisher NIE aufgerufen, die
   -- Zustaende "Kamera faehrt hoch" und "Kamera faehrt runter" blieben also
   -- ab der ersten Drehung dauerhaft aktiv.
   MoveViewRightStop()
   MoveViewUpStop()
   MoveViewDownStop()
   -- Der Mouselook-Impuls MUSS vor dem Zuruecksetzen liegen: er ist das, was
   -- die Kamera-Gierung auf die Blickrichtung des Charakters uebertraegt,
   -- also das eigentliche "dreh dich zum Ziel".
   MouselookStart()
   MouselookStop() 
   -- Ersetzt CameraZoomOut(TurnToUnit.CameraZoom): SetView gibt Zoom UND
   -- Neigung exakt zurueck, CameraZoomOut nur den Zoom - die Neigung des
   -- SetView(2)-Snaps blieb stehen und wurde beim Fliegen/Schwimmen auf den
   -- Charakter uebertragen. Siehe SkuCore.CameraScratchView.
   pcall(SetView, SkuCore.CameraScratchView or 5)
   C_CVar.SetCVar("cameraZoomSpeed", TurnToUnit.CameraZoomSpeed)
   if TurnToUnit.oldCursorCenteredYPos then
      SetCVar("CursorCenteredYPos", TurnToUnit.oldCursorCenteredYPos)
      TurnToUnit.oldCursorCenteredYPos = nil
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function CreateControlFrame()
   local f = _G["SkuCoreTurnToUnitControl"] or CreateFrame("Frame", "SkuCoreTurnToUnitControl", UIParent)
   local ttime = 0

   f:SetScript("OnUpdate", function(self, time)
      if TurnToUnit.searching == true then
         if TurnToUnit.time ~= -1 then
            ttime = ttime + time
            if ttime > TurnToUnit.time then
               StopSearch()
               dprint("found nothing")
               SkuOptions.Voice:OutputString(SkuSettings:Sub("SkuCore").turnToUnit.soundOnFail, {overwrite = false, wait = false, length = 0.3, doNotOverwrite = true,})
               ttime = 0
               return
            end
            if UnitName("mouseover") then
               local tFound = false
               if TurnToUnit.unit and UnitIsUnit("mouseover", TurnToUnit.unit) then
                  tFound = true
               elseif TurnToUnit.gameMarker and GetRaidTargetIndex("mouseover") and TurnToUnit.gameMarker == GetRaidTargetIndex("mouseover") then
                  tFound = true
               elseif TurnToUnit.skuMarker and SkuCore.aqCombat:aqCombatGetSkuRaidTarget(UnitGUID("mouseover")) == TurnToUnit.skuMarker then
                  tFound = true
               end      
               if tFound == true then
                  StopSearch()
                  dprint("found mouseover")
                  SkuOptions.Voice:OutputString(SkuSettings:Sub("SkuCore").turnToUnit.soundOnSuccess, {overwrite = false, wait = false, length = 0.3, doNotOverwrite = true,})
                  ttime = 0
                  return
               end
            end
         end      
         return
      end

      ttime = 0
   end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Arm the feature. Called automatically by AceAddon when the module is enabled
-- (at SkuCore enable, and again whenever the user toggles it back on). Combines
-- the old TurnToUnitOnInitialize (frame + dispatcher callbacks) and
-- TurnToUnitOnLogin (nameplate CVar).
function TurnToUnit:OnEnable()
   CreateControlFrame()
   SkuDispatcher:RegisterEventCallback("NAME_PLATE_UNIT_ADDED", TurnToUnit.TurnToUnit_NAME_PLATE_UNIT_ADDED)
   SkuDispatcher:RegisterEventCallback("UPDATE_MOUSEOVER_UNIT", TurnToUnit.TurnToUnit_UPDATE_MOUSEOVER_UNIT)
   SetCVar("nameplateMaxDistance", 41)
end

-- Disarm the feature: stop any in-progress turn and unregister the dispatcher
-- callbacks so a disabled TurnToUnit does nothing.
function TurnToUnit:OnDisable()
   StopSearch()
   SkuDispatcher:UnregisterEventCallback("NAME_PLATE_UNIT_ADDED", TurnToUnit.TurnToUnit_NAME_PLATE_UNIT_ADDED)
   SkuDispatcher:UnregisterEventCallback("UPDATE_MOUSEOVER_UNIT", TurnToUnit.TurnToUnit_UPDATE_MOUSEOVER_UNIT)
end

---------------------------------------------------------------------------------------------------------------------------------------
function TurnToUnit:TurnToUnit_UPDATE_MOUSEOVER_UNIT(aEvent)
   if TurnToUnit.searching == true then
      if TurnToUnit.time ~= -1 then
         local tFound = false
         if TurnToUnit.unit and UnitIsUnit("mouseover",  TurnToUnit.unit) then
            dprint("found UPDATE_MOUSEOVER_UNIT")
            tFound = true
         end

         if UnitName("mouseover") then
            if TurnToUnit.gameMarker and GetRaidTargetIndex("mouseover") and TurnToUnit.gameMarker == GetRaidTargetIndex("mouseover") then
               tFound = true
            end
            if TurnToUnit.skuMarker then
               if SkuCore.aqCombat:aqCombatGetSkuRaidTarget(UnitGUID("mouseover")) == TurnToUnit.skuMarker then
                  tFound = true
               end
            end      
         end

         if tFound == true then
            StopSearch()
            SkuOptions.Voice:OutputString(SkuSettings:Sub("SkuCore").turnToUnit.soundOnSuccess, {overwrite = false, wait = false, length = 0.3, doNotOverwrite = true,})            
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function TurnToUnit:TurnToUnit_NAME_PLATE_UNIT_ADDED(aEvent, aNameplateId)
   if TurnToUnit.searching == true then
      local tFound = false
      if TurnToUnit.unit then
         if C_NamePlate.GetNamePlateForUnit(TurnToUnit.unit) then 
            if aNameplateId == C_NamePlate.GetNamePlateForUnit(TurnToUnit.unit).UnitFrame.unit then
               tFound = true
            end
         end
      end

      if TurnToUnit.gameMarker and GetRaidTargetIndex(aNameplateId) and TurnToUnit.gameMarker == GetRaidTargetIndex(aNameplateId) then
         tFound = true
      end

      if TurnToUnit.skuMarker then
         if SkuCore.aqCombat:aqCombatGetSkuRaidTarget(UnitGUID(aNameplateId)) == TurnToUnit.skuMarker then
            tFound = true
         end
      end      

      if tFound == true then
         dprint("found NAME_PLATE")
         TurnToUnit.time = -1
         TurnToUnit.searching = false
         SkuOptions.Voice:OutputString(SkuSettings:Sub("SkuCore").turnToUnit.soundOnSuccess, {overwrite = false, wait = false, length = 0.3, doNotOverwrite = true,})
         C_Timer.After((0.4 / SkuSettings:Sub("SkuCore").turnToUnit.enhancedSettings.delayOnPlate) / SkuSettings:Sub("SkuCore").turnToUnit.speed, function()
            StopSearch()
         end)
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function TurnToUnit:TurnToUnitStartTuring(aUnitId, aGameMarker, aSkuMarker)
   if not TurnToUnit:IsEnabled() then return end
   if (aUnitId and UnitName(aUnitId) == nil) or TurnToUnit.searching == true then
      SkuOptions.Voice:OutputString(SkuSettings:Sub("SkuCore").turnToUnit.soundOnFail, {overwrite = false, wait = false, length = 0.3, doNotOverwrite = true,})
      return
   end

   -- CursorCenteredYPos wurde frueher gesetzt und nie zurueckgegeben (es ist
   -- eine gespeicherte CVar, der Wert ueberlebte /reload und Logout).
   -- Zuruecksetzen erst in StopSearch, weil er waehrend der Suche gilt.
   TurnToUnit.oldCursorCenteredYPos = TurnToUnit.oldCursorCenteredYPos or GetCVar("CursorCenteredYPos")
   local tOldFreelook = GetCVar("CursorFreelookCentering")
   local tOldSticky = GetCVar("CursorStickyCentering")
   SetCVar("CursorCenteredYPos", 0.6)
   SetCVar("CursorFreelookCentering", 1)
   SetCVar("CursorStickyCentering", 1)
   MouselookStart()
   C_Timer.After(0.01, function() 
      MouselookStop()
      SetCVar("CursorFreelookCentering", tOldFreelook)
      SetCVar("CursorStickyCentering", tOldSticky)

      C_Timer.After(0.01, function() 
         TurnToUnit.unit = aUnitId
         TurnToUnit.gameMarker = aGameMarker
         TurnToUnit.skuMarker = aSkuMarker
      
         TurnToUnit.searching = true
         TurnToUnit.time = 1.5 / SkuSettings:Sub("SkuCore").turnToUnit.speed
         -- [Kamera-Entkopplung 41.02.07] Kamera-Snap NUR im SkuStandard.
         -- Bei Freigabe (skuStandard==false) bleibt die freie Kamera des
         -- Nutzers erhalten; die Drehung selbst (MoveViewRightStart unten)
         -- laeuft unveraendert weiter -> der Charakter dreht sich weiterhin
         -- zum Ziel, nur ohne erzwungenen View-Snap.
         -- RUECKBAU: naechste Zeile wieder durch  SetView(2)  ersetzen.
         -- DOKU: Nachschlagewerke/"Kamera Freigabe Entkopplung.txt"
         -- Reihenfolge: erst messen und sichern, DANN veraendern. Vorher stand
         -- GetCameraZoom() eine Zeile NACH dem SetView(2) und hat damit den
         -- Zoom der Voreinstellung erfasst, nicht den des Nutzers.
         TurnToUnit.CameraZoom = GetCameraZoom()
         TurnToUnit.CameraZoomSpeed = C_CVar.GetCVar("cameraZoomSpeed")
         -- Ganze Kamera (Neigung UND Zoom) sichern - StopSearch holt sie
         -- ueber SetView zurueck. Ungetaktet vom SkuStandard-Schalter, weil
         -- CameraZoomIn(50) unten in JEDEM Fall laeuft.
         pcall(SaveView, SkuCore.CameraScratchView or 5)
         if not SkuCore.CameraSkuStandardActive or SkuCore:CameraSkuStandardActive() then SetView(2) end
         C_CVar.SetCVar("cameraZoomSpeed", 1000)
      
         CameraZoomIn(50)
         MoveViewRightStart(1 * SkuSettings:Sub("SkuCore").turnToUnit.speed)
         -- Echte Stop-Aufrufe: hier soll nur die Neigungsbewegung aus sein,
         -- Start(0) haette den Bewegungszustand eingeschaltet gelassen.
         MoveViewDownStop()
         MoveViewUpStop()
      end)
   end)
end

---------------------------------------------------------------------------------------------------------------------------------------
function TurnToUnit:TurnToUnitTurn180()
   if not TurnToUnit:IsEnabled() then return end
   if TurnToUnit.searching == true then
      return
   end

   TurnToUnit.searching = true
   MoveViewRightStart(6.7)
   MoveViewDownStop()
   MoveViewUpStop()
   C_Timer.After(0.1, function()
      TurnToUnit.searching = false
      MoveViewRightStop()
      MoveViewUpStop()
      MoveViewDownStop()
      MouselookStart()
      MouselookStop() 
   end)
end

