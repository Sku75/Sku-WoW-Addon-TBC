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
   return Sku.deEn("Spielweltobjekte", "World objects", "Objets du monde")
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
   -- Alle DREI CVars sichern und wieder zuruecksetzen. Frueher wurden nur
   -- CursorFreelookCentering/CursorStickyCentering zurueckgesetzt (und zwar
   -- hart auf 0 statt auf den Vorwert), CursorCenteredYPos aber NIE - der
   -- Scan-Wert (0.5/0.6/0.65) blieb dauerhaft stehen, ueber /reload und
   -- Logout hinweg, weil es eine gespeicherte CVar ist.
   local tOldYPos = GetCVar("CursorCenteredYPos")
   local tOldFreelook = GetCVar("CursorFreelookCentering")
   local tOldSticky = GetCVar("CursorStickyCentering")
   SetCVar("CursorCenteredYPos", aPos)
   SetCVar("CursorFreelookCentering", 1)
   SetCVar("CursorStickyCentering", 1)
   MouselookStart()
   C_Timer.After(0.1, function() 
      MouselookStop()
      SetCVar("CursorCenteredYPos", tOldYPos)
      SetCVar("CursorFreelookCentering", tOldFreelook)
      SetCVar("CursorStickyCentering", tOldSticky)
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
      -- Die Gierung (Yaw) wird oben exakt zurueckgerechnet, die Neigung
      -- (Pitch) KANN nicht zurueckgerechnet werden: es gibt keinen Getter
      -- dafuer in der API. Frueher stand hier SetView(2) - das ist aber kein
      -- "zurueck", sondern ein Sprung auf eine feste Voreinstellung, die
      -- leicht nach unten schaut. Beim Fliegen/Schwimmen wurde diese Neigung
      -- auf den Charakter uebertragen -> ungewolltes Sinken/Abtauchen.
      -- Jetzt: SetView auf den in GameWorldObjectsScan gesicherten Slot, das
      -- gibt Neigung UND Zoom exakt zurueck. Siehe SkuCore.CameraScratchView.
      pcall(SetView, SkuCore.CameraScratchView or 5)
      SkuOptions:StartStopBackgroundSound(false)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Der Nutzerwert von cameraYawMoveSpeed, solange eine Drehung offen ist.
-- Lebt AUSSERHALB der Funktion: ein schneller zweiter Tastendruck darf nicht
-- unseren eigenen, gerade gesetzten Drehwert als "alt" einfangen - sonst wird
-- beim Zuruecksetzen der Drehwert verewigt und die Kamera-Tasten des Nutzers
-- laufen dauerhaft schneller.
local tTurnYawSpeedSaved

---------------------------------------------------------------------------------------------------------------------------------------
-- DIE DREHUNG (zu Wegpunkt oder Einheit). So arbeitet die Engine, gemessen
-- 2026-09-22 an 340 Drehungen bei 20 und 80 fps (Restfehler 0.5 ms):
--   1. Die Kamera bewegt sich EINMAL JE FRAME um Tempo mal die ECHTE Dauer
--      dieses Frames. Zwischen zwei Frames passiert nichts.
--   2. Der Frame, in dessen OnUpdate der Stoppbefehl faellt, bewegt nichts
--      mehr; alle Frames davor (ab dem ersten nach dem Tastendruck) bewegen.
--   3. Die im OnUpdate gemessene Framedauer ist genau die Dauer, mit der der
--      NAECHSTE Schritt rechnet.
-- Daraus folgt alles Weitere: Tempo so waehlen, dass der Winkel eine ganze
-- Zahl von Frame-Schritten ist (n Schritte, v = Winkel/(n*f)); im OnUpdate
-- die echten Framedauern aufsummieren und stoppen, sobald die Summe die
-- Bewegungszeit Winkel/v erreicht; wuerde der letzte Schritt drueber
-- hinausschiessen, die CVar fuer diesen einen Frame auf den Rest skalieren
-- (Trim). Kein Timer: C_Timer feuert nur an Framegrenzen und faellt bei 2
-- Prozent Streuung um einen ganzen Frame. Keine Kalibrierung mehr: der
-- Massstab war auf beiden Gaengen 1.00 und der Leerframe 1.00 (Streuung
-- 0.01); die Selbstlern-Fassung (v43.7/43.8) lernte nur Millisekunden-
-- Latenzen, die in Wahrheit Frames waren, und vergiftete sich beim Wechsel
-- der Framerate. Einzige Sicherung: multipliziert das MoveView-Argument das
-- Tempo auf einem Client NICHT, wird Gang 2 abgeschaltet (/skuturn).
-- cameraYawMoveSpeed wirkt nur bis 360 (gemessen 2026-09-21); mehr Tempo
-- kommt aus dem Faktor-Argument von MoveViewXStart (Gang 2, bis 1440).
-- Frueherer Irrweg, nicht wiederholen: eine Nachkorrektur nach dem Stopp
-- (vor oder zurueck) - sie kaempfte gegen den Leerframe an ("Schwung").
local TURN_TOLERANCE = 3          -- Grad: schon ausgerichtet -> gar nicht drehen
local TURN_SPEED_MIN = 60
local TURN_SPEED_MAX = 1440       -- CVar 360 mal Faktor 4
local TURN_CVAR_MAX = 360
local TURN_SETTLE_MIN_FRAMES = 2  -- nach dem Stopp: der Transfer-Impuls wirkt erst im Folgeframe
local TURN_SETTLE_MIN_TIME = 0.05
local TURN_TRIM_MIN = 0.05        -- kleinerer Rest-Schritt: lieber hier stoppen
local TURN_GEAR2_MIN_REAL = 0.7   -- Gang 2 liefert unter 70 Prozent des verlangten Tempos -> abschalten

local tTurnFrame = CreateFrame("Frame")   -- OnUpdate nur waehrend einer Drehung
local tGear2Ratios = {}                   -- letzte Gang-2-Messungen: echtes/verlangtes Tempo

local function tTurnStore()
   if not (SkuSettings and SkuSettings.Sub and SkuOptions and SkuOptions.db) then return nil end
   local tOk, tStore = pcall(SkuSettings.Sub, SkuSettings, "SkuCore", "turnCal", "global")
   if not tOk or type(tStore) ~= "table" then return nil end
   if tStore.v ~= 6 then
      -- Aeltere Kalibrierungsdaten (v4/v5) sind ohne Nutzen.
      for k in pairs(tStore) do tStore[k] = nil end
      tStore.v = 6
   end
   return tStore
end

local function tTurnFrameTime()
   local tFps = GetFramerate and GetFramerate() or 60
   if not tFps or tFps < 10 then tFps = 10 elseif tFps > 240 then tFps = 240 end
   return 1 / tFps
end

-- Tempo, Schrittzahl und Framedauer fuer aAngle Grad: so wenige Schritte,
-- dass das Tempo unter dem Deckel bleibt, und das Tempo, das den Winkel
-- damit genau trifft.
local function tTurnPlan(aAngle)
   local tF = tTurnFrameTime()
   local tStore = tTurnStore()
   local tCap = (tStore and tStore.noGear2 == true) and TURN_CVAR_MAX or TURN_SPEED_MAX
   local n = math.max(1, math.ceil(aAngle / (tCap * tF) - 1e-9))
   local tSpeed = math.max(TURN_SPEED_MIN, math.min(tCap, aAngle / (n * tF)))
   return tSpeed, n, tF
end

SLASH_SKUTURN1 = "/skuturn"
SlashCmdList["SKUTURN"] = function(aMsg)
   aMsg = (aMsg or ""):lower():match("^%s*(.-)%s*$")
   local tStore = tTurnStore()
   if not tStore then print("SkuTurn: settings not ready") return end
   if aMsg == "reset" then
      tStore.noGear2 = nil
      tGear2Ratios = {}
   end
   local tText = string.format("SkuTurn: gear 2 %s, %d gear-2 measurements this session", tStore.noGear2 == true and "OFF (speed factor has no effect here)" or "on", #tGear2Ratios)
   if #tGear2Ratios > 0 then
      local tSorted = {}
      for x = 1, #tGear2Ratios do tSorted[x] = tGear2Ratios[x] end
      table.sort(tSorted)
      tText = tText..string.format(", real/asked median %.2f", tSorted[math.floor((#tSorted + 1) / 2)])
   end
   dprint(tText)
   print(tText)
end

-- [v43.3] Der Dreh-Kern haengt nicht am Wegpunkt: TurnToWorldPosition dreht zu
-- beliebigen Weltkoordinaten, damit "zu Einheit drehen" (SkuCore/turnToUnit.lua)
-- DENSELBEN Kern nutzt. Rueckgabe: true = Drehung angenommen (oder schon
-- ausgerichtet), false = verworfen (Drehung laeuft noch, oder Position/Peilung
-- nicht ermittelbar). Der Busy-Verwurf bleibt absichtlich still - das gewohnte
-- Mehrfachdruecken verfeinert einfach mit dem naechsten Druck nach dem Ende.
function GameWorldObjects:TurnToWorldPosition(aWorldX, aWorldY, aLabel)
   local fPlayerPosX, fPlayerPosY, fPlayerPosZ = UnitPosition("player")
   local degree
   if fPlayerPosX and aWorldX and aWorldY then
      degree = select(3, SkuNav.Geo:GetDirectionTo(fPlayerPosX, fPlayerPosY, aWorldX, aWorldY))
   end
   if not degree then return false end
   -- Logging: EINE Zeile je Tastendruck - "TurnCal" (gedreht), "TurnToWp
   -- skip" (schon ausgerichtet) oder "TurnToWp ignoriert" (Drehung laeuft).
   -- Laeuft noch eine Drehung, den Druck VERWERFEN statt neu zu starten: die
   -- laufende steuert eine frische Peilung an, ein Abbruch wuerfe ihre halbe
   -- Arbeit weg (der Transfer-Impuls feuert erst am Ende).
   if SkuCore.gameWorldObjectsTurnBusyUntil and GetTime() < SkuCore.gameWorldObjectsTurnBusyUntil then
      dprint("TurnToWp ignoriert, Drehung laeuft noch",
         string.format("%.2f", SkuCore.gameWorldObjectsTurnBusyUntil - GetTime()))
      return false
   end
   -- VORHALTEN gegen das Kreisen um nahe Wegpunkte: degree ist die Peilung
   -- beim Druck, gelandet wird aber erst nach Drehung + Transfer, und nah am
   -- Punkt wandert die Peilung mit v/r. Darum auf die Peilung vom
   -- vorausberechneten Landeort zielen, gedeckelt auf den halben Restabstand
   -- (nie HINTER den Punkt zielen). Gemessen 2026-09-22 (139 bewegte
   -- Drehungen): Landefehler unter 5 m 4.2 statt 8.7 Grad, half in 106 von 139.
   -- Blickrichtungsvektor in den Koordinaten von GetDirectionTo: "geradeaus"
   -- = (cos f, sin f).
   local tRawDegree = degree
   local tSpeedNow = GetUnitSpeed("player")
   if tSpeedNow and tSpeedNow > 0 and GetPlayerFacing() then
      local _, tPlanN, tPlanF = tTurnPlan(math.abs(degree))
      -- n Schritte + Leerframe + Transferframe, plus 0.03 s.
      local tDurEst = (tPlanN + 2) * tPlanF + 0.03
      local tLeadDist = tSpeedNow * tDurEst
      local _, tDist = SkuNav:Distance(fPlayerPosX, fPlayerPosY, aWorldX, aWorldY)
      if tDist and tDist > 0 then
         tLeadDist = math.min(tLeadDist, tDist * 0.5)
      end
      local tFacingNow = GetPlayerFacing()
      local tPredX = fPlayerPosX + math.cos(tFacingNow) * tLeadDist
      local tPredY = fPlayerPosY + math.sin(tFacingNow) * tLeadDist
      local _, _, tLeadDegree = SkuNav.Geo:GetDirectionTo(tPredX, tPredY, aWorldX, aWorldY)
      if tLeadDegree then
         degree = tLeadDegree
      end
   end
   -- Schon ausgerichtet -> NICHT drehen (frueher kommandierte auch 0 Grad noch
   -- einen 5-Grad-Zuschlag samt Mouselook-Impuls; im Wasser war jeder dieser
   -- Druecke ein Tauchstups). Nass + gesperrt gibt es weiter den Geradestell-
   -- Impuls, entprellt, und nur wenn keine Drehung frisch ist.
   if math.abs(degree) <= TURN_TOLERANCE then
      dprint("TurnToWp skip", aLabel, "degree", string.format("%.1f", degree))
      if SkuCore.pitchLocked == true and (IsSwimming() == true or IsFlying() == true)
         and GetTime() - (SkuCore.gameWorldObjectsTurnStartedAt or 0) > 1.0
         and GetTime() - (SkuCore.gameWorldObjectsSkipLevelAt or 0) > 0.75 then
         SkuCore.gameWorldObjectsSkipLevelAt = GetTime()
         SkuCore:PitchLockLevelPulse()
      end
      return true
   end
   -- Laufende Nummer: der nachgelagerte Geradestell-Impuls verfaellt, wenn
   -- inzwischen eine NEUERE Drehung laeuft. Zeitstempel: der Steig-/Sinktasten-
   -- Impuls (SkuCore/Core.lua) haelt sich zurueck, solange eine Drehung frisch ist.
   SkuCore.gameWorldObjectsTurnSeq = (SkuCore.gameWorldObjectsTurnSeq or 0) + 1
   local tMyTurnSeq = SkuCore.gameWorldObjectsTurnSeq
   SkuCore.gameWorldObjectsTurnStartedAt = GetTime()
   local tFacingAtStart = GetPlayerFacing()
   MoveViewRightStop()
   MoveViewLeftStop()
   -- Kamera-Snap auf die SkuStandard-Ansicht (Slot 2, hinter dem Charakter):
   -- degree ist aus der Blickrichtung des CHARAKTERS gerechnet, ausgefuehrt
   -- wird eine KAMERA-Drehung, per Mouselook-Impuls zurueckuebertragen. Das
   -- geht nur auf, wenn Kamera und Charakter beim Start uebereinstimmen.
   if not SkuCore.CameraSkuStandardActive or SkuCore:CameraSkuStandardActive() then SetView(2) end
   if tTurnYawSpeedSaved == nil then
      tTurnYawSpeedSaved = GetCVar("cameraYawMoveSpeed")
   end

   local tTarget = math.abs(degree)
   local tSpeed, tSteps, tFrameEst = tTurnPlan(tTarget)
   local tCVar = math.min(tSpeed, TURN_CVAR_MAX)
   local tFactor = tSpeed / tCVar
   local tGear = tSpeed > TURN_CVAR_MAX and 2 or 1
   local tDirection = degree < 0 and -1 or 1
   local tMotionTarget = tTarget / tSpeed     -- Bewegungszeit, die die Kamera braucht
   SetCVar("cameraYawMoveSpeed", tCVar)
   if tDirection < 0 then MoveViewRightStart(tFactor) else MoveViewLeftStart(tFactor) end

   -- Nach dem Stopp 2 Frames (mindestens 0.05 s) warten, bevor gemessen und
   -- der naechste Druck zugelassen wird: der Transfer-Impuls wirkt erst im
   -- Folgeframe, ein Druck davor rechnete mit der ALTEN Blickrichtung.
   local tSettleFrames = math.max(TURN_SETTLE_MIN_FRAMES, math.ceil(TURN_SETTLE_MIN_TIME / tFrameEst - 1e-9))
   local tTurnBegin = GetTime()
   SkuCore.gameWorldObjectsTurnBusyUntil = tTurnBegin + (tSteps + 1 + tSettleFrames) * tFrameEst + 0.25
   local tFrames, tLastFrameTime, tFrameMax = 0, tTurnBegin, 0
   local tMotionAcc, tDts, tTrim = 0, {}, nil
   local tStopAt, tStopAtFrame, tStopNext, tLandX, tLandY, tDone
   local tFrameCap = tSteps * 2 + 3     -- Notbremse

   local function tRestoreYawSpeed()
      if tTurnYawSpeedSaved ~= nil then
         SetCVar("cameraYawMoveSpeed", tTurnYawSpeedSaved)
         tTurnYawSpeedSaved = nil
      end
   end

   local function tStopSweep()
      MoveViewRightStop()
      MoveViewLeftStop()
      tStopAt = GetTime()
      tStopAtFrame = tFrames
      tRestoreYawSpeed()
      -- Der Impuls uebertraegt die Kamera-Gierung auf den Charakter - er IST
      -- die Drehung. Beim Schwimmen/Fliegen nimmt er die Kamera-Neigung mit
      -- (Tauchstups); dagegen stehen Neigungssperre und Geradestell-Impuls
      -- unten (Sackgassen: memory/camera-pitch-api-gap).
      MouselookStart()
      MouselookStop()
      tLandX, tLandY = UnitPosition("player")
      -- Nach JEDER Drehung im Wasser/in der Luft mit aktiver Sperre einmal
      -- geradestellen, verzoegert um 0.5 s (die Engine wendet den Gierungs-
      -- Transfer erst spaeter an; ein sofortiger zweiter Impuls hoebe die
      -- Drehung auf). Ohne Sperre KEIN Impuls (alter Tauch-Bug).
      if SkuCore.pitchLocked == true and (IsSwimming() == true or IsFlying() == true) then
         C_Timer.After(0.5, function()
            if SkuCore.gameWorldObjectsTurnSeq == tMyTurnSeq
               and SkuCore.pitchLocked == true
               and (IsSwimming() == true or IsFlying() == true) then
               SkuCore:PitchLockLevelPulse()
               dprint("PitchLock", "level pulse nach Drehung", tMyTurnSeq)
            end
         end)
      end
   end

   local function tRelease()
      tDone = true
      tTurnFrame:SetScript("OnUpdate", nil)
      SkuCore.gameWorldObjectsTurnBusyUntil = GetTime()
   end

   local function tMeasure()
      local tFacingEnd = GetPlayerFacing()
      if not tFacingAtStart or not tFacingEnd or not tStopAt or not tStopAtFrame or tStopAtFrame < 1 then return end
      -- Peilung positiv = Blickrichtung muss SINKEN (afinal = facing - Zielwinkel).
      local tTurned = math.deg(tFacingAtStart - tFacingEnd)
      while tTurned > 180 do tTurned = tTurned - 360 end
      while tTurned <= -180 do tTurned = tTurned + 360 end
      tTurned = tTurned * tDirection
      -- 181 Grad kaeme oben als -179 heraus: die Vollkreis-Entsprechung
      -- naechst dem Ziel waehlen.
      if tTurned < tTarget - 180 then tTurned = tTurned + 360 end
      local tElapsed = tStopAt - tTurnBegin
      local tFrameAct = tElapsed / tStopAtFrame
      -- Sicherung Gang 2: echtes Tempo gegen verlangtes, ueber die
      -- angesammelte Bewegungszeit. Liefert der Faktor nichts (Median unter
      -- 70 Prozent bei 6+ Messungen), Gang 2 dauerhaft aus - lieber ehrlich
      -- 360 Grad/s und mehr Frames.
      if tGear == 2 and tSpeed >= 540 and tMotionAcc > 0 and tTurned >= 1 then
         tGear2Ratios[#tGear2Ratios + 1] = (tTurned / tMotionAcc) / tSpeed
         while #tGear2Ratios > 12 do table.remove(tGear2Ratios, 1) end
         if #tGear2Ratios >= 6 then
            local tSorted = {}
            for x = 1, #tGear2Ratios do tSorted[x] = tGear2Ratios[x] end
            table.sort(tSorted)
            local tStore = tTurnStore()
            if tStore and tSorted[math.floor((#tSorted + 1) / 2)] < TURN_GEAR2_MIN_REAL and tStore.noGear2 ~= true then
               tStore.noGear2 = true
               dprint("TurnCal", "gear 2 OFF: speed factor has no effect on this client")
            end
         end
      end
      local tFlags = (InCombatLockdown() == true and "combat," or "")
         ..((HasFullControl ~= nil and HasFullControl() ~= true) and "nocontrol," or "")
         ..(IsSwimming() == true and "swim," or "")..(IsFlying() == true and "fly," or "")
      tFlags = tFlags == "" and "-" or string.sub(tFlags, 1, -2)
      -- n geplante Schritte, m Stoppframe, mt angesammelte Bewegungszeit (ms),
      -- trim Anteil des letzten Schritts (- = kein Trim), dts alle Framedauern,
      -- fest/fact angenommene/echte Framedauer, fmax laengster Frame.
      -- rest_land = Peilung zum Ziel vom Landeort mit der gelandeten
      -- Blickrichtung (der echte Zielfehler), lead_shift = Verschiebung durch
      -- das Vorhalten; rest_land + lead_shift waere der Fehler OHNE.
      -- flags nur bei Abweichung vom Normalfall: combat, nocontrol, swim, fly.
      dprint("TurnCal", "target", string.format("%.1f", tTarget),
         "turned", string.format("%.1f", tTurned),
         "err", string.format("%.1f", tTurned - tTarget),
         "speed", string.format("%.0f", tSpeed),
         "n", tSteps, "m", tStopAtFrame,
         "mt", string.format("%.1f", tMotionAcc * 1000),
         "trim", tTrim and string.format("%.2f", tTrim) or "-",
         "dts", table.concat(tDts, "/"),
         "fest", string.format("%.1f", tFrameEst * 1000),
         "fact", string.format("%.1f", tFrameAct * 1000),
         "fmax", string.format("%.1f", tFrameMax * 1000),
         "elapsed_ms", string.format("%.1f", tElapsed * 1000),
         "fps", string.format("%.0f", tFrameAct > 0 and 1 / tFrameAct or 0),
         "raw", string.format("%.1f", tRawDegree),
         "lead_shift", string.format("%.1f", degree - tRawDegree),
         "rest_land", string.format("%.1f", tLandX and (select(3, SkuNav.Geo:GetDirectionTo(tLandX, tLandY, aWorldX, aWorldY)) or 0) or 0),
         "dist_land", string.format("%.1f", tLandX and (select(2, SkuNav:Distance(tLandX, tLandY, aWorldX, aWorldY)) or -1) or -1),
         "v", string.format("%.1f", GetUnitSpeed("player") or 0),
         "flags", tFlags, "mode", "g"..tGear, "wp", tostring(aLabel))
   end

   -- Der Frame-Zaehler. Zaehlt nur echte Frame-Fortschritte (GetTime steht
   -- innerhalb eines Frames fest). Nur die NEUESTE Drehung zaehlt.
   tTurnFrame:SetScript("OnUpdate", function()
      if SkuCore.gameWorldObjectsTurnSeq ~= tMyTurnSeq then tTurnFrame:SetScript("OnUpdate", nil) return end
      local tNow = GetTime()
      if tNow <= tLastFrameTime then return end
      local tDelta = tNow - tLastFrameTime
      tLastFrameTime = tNow
      tFrames = tFrames + 1
      if tStopAt then
         if tFrames >= tStopAtFrame + tSettleFrames then
            tRelease()
            tMeasure()
         end
         return
      end
      if tDelta > tFrameMax then tFrameMax = tDelta end
      if #tDts < 24 then tDts[#tDts + 1] = string.format("%.0f", tDelta * 1000) end
      -- Stoppregel. Gelaufen sind die Schritte der Frames 1..i-1 (tMotionAcc);
      -- der naechste Schritt, nach diesem OnUpdate, dauert tDelta. Passt er
      -- ganz in den Rest, weiter. Sonst ist dies der letzte Schritt: die CVar
      -- fuer diesen einen Frame auf den Rest skalieren (Gang 2 multipliziert
      -- die CVar, also skaliert das Produkt mit) und im naechsten Frame
      -- stoppen. Ist der Rest kleiner als 5 Prozent eines Schritts, jetzt
      -- stoppen - ausser es ist noch kein Schritt gelaufen.
      if tStopNext or tFrames >= tFrameCap then
         tStopSweep()
         return
      end
      local tRest = tMotionTarget - tMotionAcc
      if tDelta <= tRest then
         tMotionAcc = tMotionAcc + tDelta
         return
      end
      local tFrac = tRest / tDelta
      if tFrac < TURN_TRIM_MIN and tFrames >= 2 then
         tStopSweep()
         return
      end
      if tFrac < 1 then
         tFrac = math.max(tFrac, TURN_TRIM_MIN)
         SetCVar("cameraYawMoveSpeed", tCVar * tFrac)
         tTrim = tFrac
         tMotionAcc = tMotionAcc + tDelta * tFrac
      else
         tMotionAcc = tMotionAcc + tDelta
      end
      tStopNext = true
   end)
   -- Wachhund: bleibt der Zaehler aus (Frame verborgen, Fehler im Handler),
   -- darf weder die Kamera weiterdrehen noch der Sperr-Guard haengen.
   C_Timer.After((tSteps + 1 + tSettleFrames) * tFrameEst * 4 + 1, function()
      if tDone or SkuCore.gameWorldObjectsTurnSeq ~= tMyTurnSeq then return end
      if not tStopAt then
         MoveViewRightStop()
         MoveViewLeftStop()
      end
      tRestoreYawSpeed()
      tRelease()
      dprint("TurnCal watchdog", "frames", tFrames, "stopped", tostring(tStopAt ~= nil), "wp", tostring(aLabel))
   end)
   return true
end

---------------------------------------------------------------------------------------------------------------------------------------
function GameWorldObjects:GameWorldObjectsTurnToWp(aWaypointName)
   aWaypointName = aWaypointName or SkuOptions.db.profile["SkuNav"].selectedWaypoint
   if aWaypointName and aWaypointName ~= "" then
      local tData = SkuNav:GetWaypointData2(aWaypointName)
      if tData then
         GameWorldObjects:TurnToWorldPosition(tData.worldX, tData.worldY, aWaypointName)
      end
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
            -- Die Ansicht wird hier bewusst NICHT zurueckgesetzt - der Fund
            -- soll im Blick bleiben. Die Scan-Neigungsgeschwindigkeit muss
            -- aber trotzdem weg, sonst laufen die eigenen Kameratasten des
            -- Nutzers bis zum naechsten Restore mit dem Scan-Wert (0.2 bis
            -- 6.0 je nach Scantyp) weiter.
            SetCVar("cameraPitchMoveSpeed", self.oldCameraPitchMoveSpeed)
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
      -- Erst die echte Kamera des Nutzers sichern (Neigung UND Zoom), DANN
      -- auf die Voreinstellung schnappen. SetView(2) bleibt bewusst stehen:
      -- es normiert die Start-Neigung, und genau daran haengt, auf welche
      -- Boden-Ringe die vertikalen Baender treffen - also die Trefferqualitaet
      -- des Scans. GameWorldObjectsRestoreView holt den Slot wieder zurueck.
      pcall(SaveView, SkuCore.CameraScratchView or 5)
      SetView(2)
      GameWorldObjects:GameWorldObjectsCenterMouseCursor(aHStart)
      tFrame.CameraYawMod = 1
      tFrame.CameraYaw = 0
      tFrame.DownSteps = 0
   end

   tResetRequired = true

   tFrame.isScanningActive = true
   SkuOptions:StartStopBackgroundSound(true, SkuSettings:Sub("SkuCore").scanBackgroundSound)
   tFrame.isScanningPaused = false
end