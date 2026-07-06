---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME, MODULE_PART = "SkuCore", "gameWorldObjects"  
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- W4 Phase D: GameWorldObjects is a real AceAddon SUBMODULE of SkuCore so it can be
-- turned on/off at runtime (mirrors the JunkAndRepair pilot):
--   * OnEnable  arms the feature (the 3 cursor/mouseover events + the frame-counter
--     OnUpdate driver, plus the per-char scanConfigs defaults) — formerly done by
--     SkuCore:GameWorldObjectsOnInitialize / :GameWorldObjectsOnLogin.
--   * OnDisable disarms it (unregisters the events; stops any active scan).
-- AceAddon auto-enables modules when SkuCore enables, so this now re-arms on every
-- load (incl. /reload), replacing the explicit Core.lua init/login calls (which only
-- ran on the initial login). The scan START (GameWorldObjectsScan) is a safe no-op
-- while disabled (IsEnabled guard).
-- W4 Phase E1 (namespace extraction): every method and mutable state field now lives
-- on the module table `GameWorldObjects` (function GameWorldObjects:Method,
-- GameWorldObjects.gameWorldObjectsScanFrame, etc.) instead of on the shared SkuCore
-- god-object. The module mixes in AceEvent-3.0 and owns its own CURSOR_CHANGED /
-- CURSOR_UPDATE / UPDATE_MOUSEOVER_UNIT registrations. External callers use the
-- published handle SkuCore.GameWorldObjects (Core.lua keybind/PLAYER_STARTED_MOVING,
-- SkuNav, SkuZOptions, MinimapScanner). Settings stay under the "SkuCore" SkuSettings
-- namespace, so no SavedVariables migration.
local GameWorldObjects = SkuCore:NewModule("GameWorldObjects", "AceEvent-3.0")
SkuCore.GameWorldObjects = GameWorldObjects   -- published handle

-- Make this feature user-toggleable (Features menu + persisted on/off).
SkuCore:RegisterToggleableModule("GameWorldObjects", function()
   return (GetLocale and GetLocale() == "deDE") and "Spielweltobjekte" or "World objects"
end)

---------------------------------------------------------------------------------------------------------------------------------------
-- Local Unescape removed in the Sku 42 rework (W4 Phase A) — now uses the shared
-- SkuUtil:Unescape. The tostring() wrapper at the call sites preserves this
-- module's contract that a nil tooltip line becomes the string "nil": the
-- downstream output logic in GameWorldObjectsCheckResult compares against "nil"
-- (e.g. `if aTextLeft2 ~= "nil"`), so SkuUtil's real-nil return must be coerced.

---------------------------------------------------------------------------------------------------------------------------------------
-- The frame-counter driver frame (created once, reused across enable/disable
-- cycles). Module upvalue so OnEnable/OnDisable can start/stop its OnUpdate.
local gameWorldObjectsFrameCounter

function GameWorldObjects:GameWorldObjectsOnInitialize()
   if Sku.toc > 11403 then
      GameWorldObjects:RegisterEvent("CURSOR_CHANGED", "CURSOR_CHANGED")
   else
      GameWorldObjects:RegisterEvent("CURSOR_UPDATE", "CURSOR_UPDATE")
   end

   GameWorldObjects:RegisterEvent("UPDATE_MOUSEOVER_UNIT", "UPDATE_MOUSEOVER_UNIT")

   if not gameWorldObjectsFrameCounter then
      gameWorldObjectsFrameCounter = CreateFrame("Frame", "SkuCoregameWorldObjectsFrameCounter", _G["UIParent"])
      gameWorldObjectsFrameCounter:SetSize(1, 1)
      gameWorldObjectsFrameCounter:SetPoint("TOPLEFT", _G["UIParent"], "TOPLEFT", 0, 0)
   end
   GameWorldObjects.gameWorldObjectsFrameCounter = 0
   gameWorldObjectsFrameCounter:SetScript("OnUpdate", function(self, time)
      GameWorldObjects.gameWorldObjectsFrameCounter = GameWorldObjects.gameWorldObjectsFrameCounter + 1
      if GameWorldObjects.gameWorldObjectsFrameCounter > 40000 then
         GameWorldObjects.gameWorldObjectsFrameCounter = 0
      end
   end)
end

---------------------------------------------------------------------------------------------------------------------------------------
function GameWorldObjects:GameWorldObjectsOnLogin()
   -- set default values for scans to profile
   SkuSettings:Sub("SkuCore", nil, "char").scanConfigs = SkuSettings:Sub("SkuCore", nil, "char").scanConfigs or {}
   SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[1] = SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[1] or {type = 2, objects = {7, 8,},}
   SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[2] = SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[2] or {type = 1, objects = {9,},}
   SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[3] = SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[3] or {type = 2, objects = {10,},}
   SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[4] = SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[4] or {type = 2, objects = {1, 2,},}
   SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[5] = SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[5] or {type = 3, objects = {7, 8,},}
   SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[6] = SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[6] or {type = 3, objects = {10,},}
   SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[7] = SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[7] or {type = 3, objects = {1, 2,},}
   SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[8] = SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[8] or {type = 5, objects = {12,},}
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Arm the feature. Called automatically by AceAddon when the module is enabled
-- (at SkuCore enable, and again whenever the user toggles it back on). Re-runs the
-- former Core.lua init+login arming (the 3 events + frame-counter OnUpdate +
-- scanConfigs defaults), so the feature now re-arms on every /reload.
function GameWorldObjects:OnEnable()
   GameWorldObjects:GameWorldObjectsOnInitialize()
   GameWorldObjects:GameWorldObjectsOnLogin()
end

-- Disarm the feature: stop any active scan, unregister the cursor/mouseover events,
-- and stop the frame-counter OnUpdate so a disabled feature genuinely does nothing.
function GameWorldObjects:OnDisable()
   -- stop any in-progress scan / restore the camera
   if GameWorldObjects.GameWorldObjectsRestoreView then
      GameWorldObjects:GameWorldObjectsRestoreView()
   end
   GameWorldObjects:UnregisterAllEvents()
   if gameWorldObjectsFrameCounter then
      gameWorldObjectsFrameCounter:SetScript("OnUpdate", nil)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function GameWorldObjects:CURSOR_CHANGED(aEvent, isDefault, newCursorType, oldCursorType, oldCursorVirtualID)
   --print("CURSOR_CHANGED", aEvent, isDefault, newCursorType, oldCursorType, oldCursorVirtualID)
   if GameWorldObjects.gameWorldObjectsScanFrame and GameWorldObjects.gameWorldObjectsScanFrame.isScanningActive == true and GameWorldObjects.gameWorldObjectsScanFrame.isScanningPaused == false then

      GameWorldObjects.lastCursorUpdateFrame = GameWorldObjects.gameWorldObjectsFrameCounter
   end
   SkuCore.MinimapScanner:MinimapScannerCURSOR_CHANGED(aEvent, isDefault, newCursorType, oldCursorType, oldCursorVirtualID)
end

function GameWorldObjects:CURSOR_UPDATE(aEvent, isDefault, newCursorType, oldCursorType, oldCursorVirtualID)
   --print("CURSOR_UPDATE")
   if GameWorldObjects.gameWorldObjectsScanFrame and GameWorldObjects.gameWorldObjectsScanFrame.isScanningActive == true and GameWorldObjects.gameWorldObjectsScanFrame.isScanningPaused == false then

      GameWorldObjects.lastCursorUpdateFrame = GameWorldObjects.gameWorldObjectsFrameCounter
   end
   SkuCore.MinimapScanner:MinimapScannerCURSOR_CHANGED(aEvent, isDefault, newCursorType, oldCursorType, oldCursorVirtualID)
end

---------------------------------------------------------------------------------------------------------------------------------------
function GameWorldObjects:UPDATE_MOUSEOVER_UNIT()
   --print("UPDATE_MOUSEOVER_UNIT", GameWorldObjects.gameWorldObjectsFrameCounter, GetTime())
   if GameWorldObjects.gameWorldObjectsScanFrame and GameWorldObjects.gameWorldObjectsScanFrame.isScanningActive == true and GameWorldObjects.gameWorldObjectsScanFrame.isScanningPaused == false then
      GameWorldObjects.lastUpdateMouseoverUnitFrame = GameWorldObjects.gameWorldObjectsFrameCounter
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function GameWorldObjects:GameWorldObjectsCenterMouseCursor(aPos)
   dprint("GameWorldObjectsCenterMouseCursor", aPos)
   SetCVar("CursorCenteredYPos", aPos)
   SetCVar("CursorFreelookCentering", 1)
   SetCVar("CursorStickyCentering", 1)
   MouselookStart()
   C_Timer.After(0.1, function() 
      MouselookStop()
      SetCVar("CursorFreelookCentering", 0)
      SetCVar("CursorStickyCentering", 0)
   end)
end

---------------------------------------------------------------------------------------------------------------------------------------
local tResetRequired
function GameWorldObjects:GameWorldObjectsRestoreView()
   if GameWorldObjects.gameWorldObjectsScanFrame and tResetRequired then
      tResetRequired = nil
      GameWorldObjects.gameWorldObjectsScanFrame.isScanningActive = false
      GameWorldObjects.gameWorldObjectsScanFrame.isScanningPaused = true
      MoveViewUpStop()
      FlipCameraYaw(GameWorldObjects.gameWorldObjectsScanFrame.CameraYaw * -1)
      GameWorldObjects.gameWorldObjectsScanFrame.CameraYaw = 0
      SkuCore.MinimapScanner.noMouseOverNotification = nil
      SetCVar("cameraPitchMoveSpeed", GameWorldObjects.gameWorldObjectsScanFrame.oldCameraPitchMoveSpeed)
      SetView(2)
      --[[
      if Questie_BaseFrame and SkuCore.inCombat == false then
         Questie_BaseFrame:Show()
      end
      ]]
      SkuOptions:StartStopBackgroundSound(false)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function GameWorldObjects:GameWorldObjectsTurnToWp(aWaypointName)
   aWaypointName = aWaypointName or SkuOptions.db.profile["SkuNav"].selectedWaypoint
   if aWaypointName and aWaypointName ~= "" then
      local fPlayerPosX, fPlayerPosY = UnitPosition("player")
      local tData = SkuNav:GetWaypointData2(aWaypointName)
      local _, _, degree = SkuNav.Geo:GetDirectionTo(fPlayerPosX, fPlayerPosY, tData.worldX, tData.worldY)
      -- [Kamera-Entkopplung 41.02.07] Kamera-Snap NUR im SkuStandard.
      -- Der Drehwinkel (degree) ist oben rein rechnerisch ermittelt und
      -- kameraunabhaengig. Bei Freigabe bleibt die freie Kamera erhalten;
      -- die Wegpunkt-Drehung (MoveViewLeft/Right unten) funktioniert weiter.
      -- RUECKBAU: naechste Zeile wieder durch  SetView(2)  ersetzen.
      -- DOKU: Nachschlagewerke/"Kamera Freigabe Entkopplung.txt"
      if not SkuCore.CameraSkuStandardActive or SkuCore:CameraSkuStandardActive() then SetView(2) end
      --SkuCore:GameWorldObjectsCenterMouseCursor(0.5)
      
      local tOldCameraYawMoveSpeed = GetCVar("cameraYawMoveSpeed")

      local tFullTurnTime = 0.5
      local tOneDegreeTime = tFullTurnTime / 180
      local tYawMoveSpeedForOneSecond = 180 * (1 / tFullTurnTime)

      SetCVar("cameraYawMoveSpeed", tYawMoveSpeedForOneSecond)
      
      if degree < 0 then
         degree = degree - 5
      else
         degree = degree + 5
      end
      local tDuration = tOneDegreeTime * degree

      if tDuration < 0 then
         MoveViewRightStart(4)
         tDuration = tDuration * -1
      else
         MoveViewLeftStart(4)
      end
      C_Timer.After(tDuration / 4, function()
         MoveViewRightStop()
         MoveViewLeftStop()
         SetCVar("cameraYawMoveSpeed", tOldCameraYawMoveSpeed)
         MouselookStart()
         MouselookStop() 
      end)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function GameWorldObjectsVoiceOutput(aText, aSound)
   dprint("GameWorldObjectsVoiceOutput", aText, "------",  aSound)
   SkuOptions.Voice:OutputStringBTtts(aText, true, false, 0.2, nil, nil, nil, 4)
   if aSound then
      SkuOptions.Voice:OutputString(aSound, false, false, 0.2)
   end
end

local slower = string.lower
---------------------------------------------------------------------------------------------------------------------------------------
function GameWorldObjects:GameWorldObjectsCheckResult(aTextLeft1, aTextLeft2, aTextLeft3)
   dprint("GameWorldObjectsCheckResult", aTextLeft1, aTextLeft2, aTextLeft3)
   local tIsUpdateMouseoverUnitFrame = GameWorldObjects.lastUpdateMouseoverUnitFrame == GameWorldObjects.gameWorldObjectsFrameCounter
   local tIsCursorUpdate = GameWorldObjects.lastCursorUpdateFrame == GameWorldObjects.gameWorldObjectsFrameCounter
   
   aTextLeft1 = tostring(SkuUtil:Unescape(aTextLeft1))
   aTextLeft2 = tostring(SkuUtil:Unescape(aTextLeft2))
   aTextLeft3 = tostring(SkuUtil:Unescape(aTextLeft3))

   dprint("GameWorldObjectsCheckResult", aTextLeft1, aTextLeft2, aTextLeft3, tIsUpdateMouseoverUnitFrame, tIsCursorUpdate)

   local tFind = GameWorldObjects.gameWorldObjectsScanFrame.findList
   --local tFound = false

   local tSoundFile = "sound-on3_1"
   aTextLeft1 = aTextLeft1 or ""
   aTextLeft2 = aTextLeft2 or ""
   aTextLeft3 = aTextLeft3 or ""

   local tOutputText = aTextLeft1
   if aTextLeft2 ~= "nil" then
      tOutputText = tOutputText..", "..aTextLeft2
   end
   if aTextLeft3 ~= "nil" then
      tOutputText = tOutputText..", "..aTextLeft3
   end

   local tId = UnitGUID("mouseover") or "NoId"
   if not GameWorldObjects.gameWorldObjectsScanFrame.found[aTextLeft1..tId] then
      local taTextLeft1InCreatures
      local function taTextLeft1InCreaturesCheck()
         if not taTextLeft1InCreatures then
            local tTextLeftLower = slower(aTextLeft1)
            for i, v in pairs(SkuDB.NpcData.Names[Sku.L["locale"]]) do
               if slower(v[1]) == tTextLeftLower then
                  GameWorldObjectsVoiceOutput(tOutputText, tSoundFile)
                  return true
               end
            end
         end
      end
      taTextLeft1InCreatures = nil
      if tFind["CorpseLootable"] then
         if
            UnitName("mouseover") ~= nil and
            tIsCursorUpdate == true and
            tIsUpdateMouseoverUnitFrame == true and
            string.find(aTextLeft3, L["Skinnable"]) == nil and
            UnitIsDead("mouseover") == true
         then
            taTextLeft1InCreatures = taTextLeft1InCreaturesCheck()
            if taTextLeft1InCreatures then
               GameWorldObjects.gameWorldObjectsScanFrame.found[aTextLeft1..tId] = true
               GameWorldObjectsVoiceOutput(tOutputText, tSoundFile)
               return true
            end
         end
      end
      taTextLeft1InCreatures = nil
      if tFind["CorpseSkinnable"] then
         if
            UnitName("mouseover") ~= nil and
            tIsCursorUpdate == true and
            tIsUpdateMouseoverUnitFrame == true and
            UnitIsDead("mouseover") == true and
            string.find(aTextLeft3, L["Skinnable"]) ~= nil
         then
            taTextLeft1InCreatures = taTextLeft1InCreaturesCheck()
            if taTextLeft1InCreatures then
               GameWorldObjects.gameWorldObjectsScanFrame.found[aTextLeft1..tId] = true
               GameWorldObjectsVoiceOutput(tOutputText, tSoundFile)
               return true
            end
         end
      end
      taTextLeft1InCreatures = nil
      if tFind["CorpseNotLootable"] then
         if
            UnitName("mouseover") ~= nil and
            tIsUpdateMouseoverUnitFrame == true and
            tIsCursorUpdate == false and
            UnitIsDead("mouseover") == true
         then
            taTextLeft1InCreatures = taTextLeft1InCreaturesCheck()
            if taTextLeft1InCreatures then
               GameWorldObjects.gameWorldObjectsScanFrame.found[aTextLeft1..tId] = true
               GameWorldObjectsVoiceOutput(tOutputText, tSoundFile)
               return true
            end
         end
      end

      taTextLeft1InCreatures = nil
      if tFind["CreaturePlayerTarget"] then
         if
            (UnitName("mouseover") ~= nil and UnitName("target") ~= nil and UnitName("mouseover") == UnitName("target")) and
            tIsCursorUpdate == true and
            tIsUpdateMouseoverUnitFrame == true and
            UnitIsDead("mouseover") ~= true
         then
            taTextLeft1InCreatures = taTextLeft1InCreaturesCheck()
            if taTextLeft1InCreatures then
               GameWorldObjects.gameWorldObjectsScanFrame.found[aTextLeft1..tId] = true
               GameWorldObjectsVoiceOutput(tOutputText, tSoundFile)
               return true
            end
         end
      end
      taTextLeft1InCreatures = nil
      if tFind["CreatureAny"] then
         if
            UnitName("mouseover") ~= nil and
            tIsCursorUpdate == true and
            tIsUpdateMouseoverUnitFrame == true and
            UnitIsDead("mouseover") ~= true
         then
            taTextLeft1InCreatures = taTextLeft1InCreaturesCheck()
            if taTextLeft1InCreatures then
               GameWorldObjects.gameWorldObjectsScanFrame.found[aTextLeft1..tId] = true
               GameWorldObjectsVoiceOutput(tOutputText, tSoundFile)
               return true
            end
         end
      end

      local taTextLeft1InObjects
      local function taTextLeft1InObjectsCheck()
         if not taTextLeft1InObjects then
            local tTextLeftLower = slower(aTextLeft1)
            for i, v in pairs(SkuDB.objectLookup[Sku.L["locale"]]) do
               if slower(v) == tTextLeftLower then
                  return true
               end
            end
            for i, v in pairs(SkuDB.SpellDataTBC) do
               if slower(v[Sku.L["locale"]][1]) == tTextLeftLower then
                  return true
               end
            end
         end
      end
      taTextLeft1InObjects = nil
      if tFind["ObjectCurrentQuest"] then
         if
            UnitName("mouseover") == nil and
            tIsCursorUpdate == true and
            tIsUpdateMouseoverUnitFrame == false
         then
            taTextLeft1InObjects = taTextLeft1InObjectsCheck()
            if taTextLeft1InObjects then
               local tIsMining
               local tIsherb
               local tTextLeftLower = slower(aTextLeft1)
               for x = 1, #SkuCore.RessourceTypes.mining do
                  if slower(SkuCore.RessourceTypes.mining[x][Sku.LocP]) == tTextLeftLower then
                     tIsMining = true
                  end
               end
               for x = 1, #SkuCore.RessourceTypes.herbs do
                  if slower(SkuCore.RessourceTypes.herbs[x][Sku.LocP]) == tTextLeftLower then
                     tIsherb = true
                  end
               end
               if not tIsherb and not tIsMining then
                  local tQuestObjects = SkuQuest:GetAllQuestObjects()
                  if tQuestObjects[aTextLeft1] then
                     GameWorldObjects.gameWorldObjectsScanFrame.found[aTextLeft1..tId] = true
                     GameWorldObjectsVoiceOutput(tOutputText, tSoundFile)
                     return true
                  end
               end
            end
         end
      end
      taTextLeft1InObjects = nil
      if tFind["ObjectHerb"] then
         if
            UnitName("mouseover") == nil and
            tIsCursorUpdate == true and
            tIsUpdateMouseoverUnitFrame == false
         then
            --taTextLeft1InObjects = taTextLeft1InObjectsCheck()
            --if taTextLeft1InObjects then
               local tTextLeftLower = slower(aTextLeft1)
               for x = 1, #SkuCore.RessourceTypes.herbs do
                  if slower(SkuCore.RessourceTypes.herbs[x][Sku.LocP]) == tTextLeftLower then
                     if SkuSettings:Sub("SkuCore").ressourceScanning.herbs[x] == true then
                        GameWorldObjects.gameWorldObjectsScanFrame.found[aTextLeft1..tId] = true
                        GameWorldObjectsVoiceOutput(tOutputText, tSoundFile)
                        return true
                     end
                  end
               end
            --end
         end
      end
      taTextLeft1InObjects = nil
      if tFind["ObjectVein"] then
         if
            UnitName("mouseover") == nil and
            tIsCursorUpdate == true and
            tIsUpdateMouseoverUnitFrame == false
         then
            --taTextLeft1InObjects = taTextLeft1InObjectsCheck()
            --if taTextLeft1InObjects then
               local tTextLeftLower = slower(aTextLeft1)
               for x = 1, #SkuCore.RessourceTypes.mining do
                  if slower(SkuCore.RessourceTypes.mining[x][Sku.LocP]) == tTextLeftLower then
                     if SkuSettings:Sub("SkuCore").ressourceScanning.miningNodes[x] == true then
                        GameWorldObjects.gameWorldObjectsScanFrame.found[aTextLeft1..tId] = true
                        GameWorldObjectsVoiceOutput(tOutputText, tSoundFile)
                        return true
                     end
                  end
               end
            --end
         end
      end
      taTextLeft1InObjects = nil
      if tFind["Bobber"] then
         if
            UnitName("mouseover") == nil and
            tIsCursorUpdate == true and
            tIsUpdateMouseoverUnitFrame == false and
            aTextLeft1 == L["Fishing Bobber"]
         then
            GameWorldObjects.gameWorldObjectsScanFrame.found[aTextLeft1] = aTextLeft1
            GameWorldObjects.gameWorldObjectsScanFrame.found[aTextLeft1..tId] = true
            GameWorldObjectsVoiceOutput(tOutputText, tSoundFile)
            return true
         end
      end
      taTextLeft1InObjects = nil
      if tFind["ObjectUsable"] then
         if
            UnitName("mouseover") == nil and
            tIsCursorUpdate == true and
            tIsUpdateMouseoverUnitFrame == false
         then
            taTextLeft1InObjects = taTextLeft1InObjectsCheck()
            if taTextLeft1InObjects then
               GameWorldObjects.gameWorldObjectsScanFrame.found[aTextLeft1..tId] = true
               GameWorldObjectsVoiceOutput(tOutputText, tSoundFile)
               return true
            end
         end
      end
      taTextLeft1InObjects = nil
      if tFind["ObjectAny"] then
         if
            UnitName("mouseover") == nil and
            tIsUpdateMouseoverUnitFrame == false
         then
            taTextLeft1InObjects = taTextLeft1InObjectsCheck()
            if taTextLeft1InObjects then
               GameWorldObjects.gameWorldObjectsScanFrame.found[aTextLeft1..tId] = true
               GameWorldObjectsVoiceOutput(tOutputText, tSoundFile)
               return true
            end
         end
      end

      if tFind["Any"] then
         GameWorldObjects.gameWorldObjectsScanFrame.found[aTextLeft1..tId] = true
         GameWorldObjectsVoiceOutput(tOutputText, tSoundFile)
         return true
      end

   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function GameWorldObjects:GameWorldObjectsScan(aContinue, aFindList, aHStepSizeDeg, aHStepsMax, aVMoveSpeed, aVStepsMax, aCallback, aHStart)
   if not GameWorldObjects:IsEnabled() then return end
   dprint("GameWorldObjectsScan", aContinue, aFindList, aHStepSizeDeg, aHStepsMax, aVMoveSpeed, aVStepsMax, aCallback, aHStart)
   local tFrame = _G["SkuCoreGameWorldObjectsScanTicker"] or CreateFrame("Frame", "SkuCoreGameWorldObjectsScanTicker", _G["UIParent"])
   tFrame:SetSize(1, 1)
   tFrame:SetPoint("TOPLEFT", _G["UIParent"], "TOPLEFT", 0, 0)

   GameWorldObjects.gameWorldObjectsScanFrame = tFrame

   if aContinue == true and tFrame.isScanningActive ~= true then
      return
   end

   if aContinue ~= true and tFrame.isScanningActive == true then
      GameWorldObjects:GameWorldObjectsRestoreView()
   end

   tFrame.stopUpFlag = false
   if aContinue ~= true then
      tFrame.findList = aFindList
      tFrame.oldCameraPitchMoveSpeed = GetCVar("cameraPitchMoveSpeed")
      tFrame.hStepSizeDeg = aHStepSizeDeg
      tFrame.hStepsMax = aHStepsMax
      tFrame.vMoveSpeed = aVMoveSpeed
      tFrame.vStepsMax = aVStepsMax
      tFrame.callback = aCallback
      tFrame.found = {}
   end
      
   tFrame:SetScript("OnUpdate", function(self, time)
      if self.isScanningActive == true and self.isScanningPaused == false then
         if self.stopUpFlag == true then
            self.stopUpFlag = false
            MoveViewUpStop()
         end
   
         self.isScanningPaused = true
         local tTextLeft1 = _G["GameTooltipTextLeft1"]:GetText()
         local tTextLeft2 = _G["GameTooltipTextLeft2"]:GetText()
         local tTextLeft3 = _G["GameTooltipTextLeft3"]:GetText()
         GameTooltip:ClearLines()
         --GameTooltip:Hide()

         local t = (self.hStepSizeDeg * self.CameraYawMod) * (((self.DownSteps + 1) / self.vStepsMax) * 0.75)
         dprint(t, self.hStepSizeDeg * self.CameraYawMod, ((self.DownSteps + 1) / self.vStepsMax), (((self.DownSteps + 1) / self.vStepsMax) * 5), self.DownSteps, self.vStepsMax)
         if tTextLeft1 and GameWorldObjects:GameWorldObjectsCheckResult(tTextLeft1, tTextLeft2, tTextLeft3) then
            MoveViewUpStop()
            FlipCameraYaw((t) * -1)
            self.CameraYaw = self.CameraYaw + ((t) * -1)
            if self.callback then
               self.callback(tTextLeft1)
            end
            SkuOptions:StartStopBackgroundSound(false)
         else
            self.isScanningPaused = false
   
            FlipCameraYaw(t)
            self.CameraYaw = self.CameraYaw + t
   
            if self.CameraYaw >= (self.hStepSizeDeg * self.hStepsMax + self.DownSteps * 5)  or self.CameraYaw <= -(self.hStepSizeDeg * self.hStepsMax + self.DownSteps * 5) then
               self.CameraYawMod = self.CameraYawMod * -1
               self.DownSteps = self.DownSteps + 1
               SetCVar("cameraPitchMoveSpeed", self.vMoveSpeed)
               MoveViewUpStart(1)      
               self.stopUpFlag = true
               
               if self.DownSteps > self.vStepsMax then
                  GameWorldObjects:GameWorldObjectsRestoreView()
               end
            end
         end
      end
   end)
   tFrame:Show()

   SkuCore.MinimapScanner.noMouseOverNotification = true

   if aContinue ~= true then
      SetView(2)
      GameWorldObjects:GameWorldObjectsCenterMouseCursor(aHStart)
      tFrame.CameraYawMod = 1
      tFrame.CameraYaw = 0
      tFrame.DownSteps = 0
   end

   tResetRequired = true
   --[[
   if Questie_BaseFrame and SkuCore.inCombat == false then
      Questie_BaseFrame:Hide()
   end
   ]]

   tFrame.isScanningActive = true
   SkuOptions:StartStopBackgroundSound(true, SkuSettings:Sub("SkuCore").scanBackgroundSound)
   tFrame.isScanningPaused = false
end