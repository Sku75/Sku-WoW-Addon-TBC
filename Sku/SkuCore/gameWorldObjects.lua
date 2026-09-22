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
-- [v43.7] SELBSTKALIBRIERUNG der Drehung (Idee aus WowVision uebernommen, Modell
-- eigenes). Bisher: fester Zuschlag von 5 Grad und feste 360 Grad/s als
-- Untergrenze - beides auf EINEM Rechner eingemessen.
--
-- [v43.8] Drehung in FRAMES statt in Millisekunden. Das Log vom 2026-09-22
-- (20 fps, 132 Drehungen, plus 29 bei 80 fps als Vergleich) zeigt, wie die
-- Engine wirklich arbeitet: die Kamera bewegt sich EINMAL JE FRAME um
-- Geschwindigkeit mal Framedauer (bei 120 Grad/s und 20 fps: 6 Grad je
-- Frame, gedreht wurde 6, 12, 18, 24), ein Stopp greift nur an einer
-- Framegrenze, und der erste Frame nach dem Startbefehl bewegt NICHTS
-- (Latenz der Engine, bei 80 wie bei 20 fps, bis 700 Grad/s gemessen).
-- Modell je Gang:  gedreht = k * v * f * (m - c)
--   m = Frames vom Tastendruck bis zum Stoppbefehl, c = verlorene Frames
--   (~1), k = Gier-Massstab (dreht die Kamera so schnell wie verlangt?),
--   f = Framedauer. Gemessen wird y = gedreht / (v * f) = Bewegungsframes.
-- Der Planer waehlt darum ERST die Bewegungsframes n (so wenige, dass die
-- Geschwindigkeit unter dem Deckel bleibt) und DANN v = Winkel / (k*n*f):
-- der Winkel ist ein Vielfaches des Frame-Schritts, der Stopp trifft exakt,
-- bei jeder Framerate. Die alte Regel (Streuung = halbe Framedauer mal
-- Tempo, also langsam bei wenig fps, dann per 0.25-s-Deckel gestreckt)
-- machte langsame Rechner kuenstlich langsam (20 fps: 300 ms je Drehung
-- ueber 15 Grad, 25 Prozent aller Druecke im Sperrfenster verworfen, beritten
-- wieder das Kreisen um nahe Wegpunkte) und lernte die Latenz als
-- Millisekunden: -12 ms bei 80 fps, -50 bei 20 - kleine Drehungen verloren
-- bei 20 fps darum 35-40 Prozent. Der Stopp kommt aus einem OnUpdate-
-- ZAEHLER, nicht aus C_Timer: gezaehlte Frames stimmen auch, wenn ein Frame
-- haengt oder die Framezeit streut, ein Timer hingegen faellt bei 2 Prozent
-- Streuung um einen ganzen Frame (Log 12:12:08: 94 verlangt, 57 gedreht).
-- Kalibrierung: ab der ersten Messung k aus dem Median von y/(m-c) mit c = 1,
-- ab 8 Messungen mit mindestens 2 Frames Spreizung in m eine Gerade fuer k
-- UND c. Messwerte liegen accountweit in SkuOptions.db.global.SkuCore.turnCal
-- (die Kalibrierung gehoert zum Rechner, nicht zum Charakter). /skuturn zeigt
-- den Stand, /skuturn reset verwirft ihn, /skuturn legacy schaltet auf das
-- alte Tempo (+5 Grad, max(360, Winkel/0.25 s)), ebenfalls frameweise.
-- Log je Druck: "TurnCal" mit n (geplante Bewegungsframes), mp/m (erwarteter
-- und tatsaechlicher Stoppframe), steps (gemessene Bewegungsframes), lost =
-- m - steps (gemessen 2026-09-22: 1.01 bei 20 fps, 1.02 bei 80 fps, bei jedem
-- Tempo), fest/fact (angenommene/echte Framedauer), fmax (laengster Frame der
-- Drehung = Haenger), mt (Bewegungszeit beim Stopp), dts (alle Framedauern).
-- Der Stopp selbst faellt nicht blind im Frame m, sondern wo die Summe der
-- echten Framedauern die Bewegungszeit Winkel/(k*v) am besten trifft - siehe
-- Stoppregel in TurnToWorldPosition.
local TURN_TOLERANCE = 3          -- Grad: schon ausgerichtet -> gar nicht drehen
local TURN_SPEED_MIN = 60
local TURN_SPEED_MAX = 1440       -- CVar 360 mal Faktor 4; real ~1300-1400 (gemessen 2026-09-21)
local TURN_CVAR_MAX = 360         -- darueber dreht die Kamera NICHT schneller (gemessen 2026-09-21)
local TURN_MIN_STEPS = 1          -- Bewegungsframes je Drehung mindestens
local TURN_LOST_DEFAULT = 1       -- verlorene Frames (Start-/Stopplatenz), gemessen 2026-09-22
local TURN_LOST_MIN, TURN_LOST_MAX = 0, 3
local TURN_SETTLE_MIN_FRAMES = 2  -- nach dem Stopp: der Transfer-Impuls wirkt erst im Folgeframe
local TURN_SETTLE_MIN_TIME = 0.05
local TURN_LEGACY_MAX_TIME = 0.25 -- nur noch /skuturn legacy
local TURN_CAL_MIN_SAMPLES = 8
local TURN_CAL_MAX_SAMPLES = 80
-- Zwei "Gaenge": 1 = CVar allein (bis 360 Grad/s), 2 = CVar 360 mal Faktor im
-- MoveView-Argument. Jeder Gang misst seinen eigenen Massstab k, weil der
-- Faktor auf diesem Client nie eingemessen wurde.
local TURN_K_RANGE = {[1] = {0.5, 1.5}, [2] = {0.2, 3}}

local tManualTurnLeft, tManualTurnRight = false, false
local tManualTurnAt = 0
hooksecurefunc("TurnLeftStart", function() tManualTurnLeft = true tManualTurnAt = GetTime() end)
hooksecurefunc("TurnLeftStop", function() tManualTurnLeft = false end)
hooksecurefunc("TurnRightStart", function() tManualTurnRight = true tManualTurnAt = GetTime() end)
hooksecurefunc("TurnRightStop", function() tManualTurnRight = false end)

-- Der Frame-Zaehler der laufenden Drehung (OnUpdate nur waehrend einer Drehung).
local tTurnFrame = CreateFrame("Frame")

local tTurnCalFit       -- {[1] = {k=, c=, n=, how=}, [2] = ...} oder false = legacy
local function tTurnCalStore()
   if not (SkuSettings and SkuSettings.Sub and SkuOptions and SkuOptions.db) then return nil end
   local tOk, tStore = pcall(SkuSettings.Sub, SkuSettings, "SkuCore", "turnCal", "global")
   if not tOk or type(tStore) ~= "table" then return nil end
   -- v5 = Frame-Einheiten (y Bewegungsframes, m Frames bis Stopp); aeltere
   -- Millisekunden-Messungen sind unbrauchbar und werden verworfen.
   if tStore.v ~= 5 or type(tStore.samples) ~= "table" then
      tStore.v = 5
      tStore.samples = {}
      tStore.noGear2 = nil
   end
   return tStore
end

local function tMedianOf(aList)
   table.sort(aList)
   return aList[math.floor((#aList + 1) / 2)]
end

-- Modell je Gang: y = k * (m - c). Solange die Messungen nicht in m streuen,
-- ist c nicht bestimmbar: dann c = 1 (gemessen) und k aus dem Median von
-- y/(m-c). Ab 8 Messungen mit mindestens 2 Frames Spreizung in m wird erst
-- das c gesucht, unter dem die Verhaeltnisse y/(m-c) am wenigsten streuen
-- (0, 0.5, ... 3; bei Gleichstand bleibt 1), dann eine Gerade y = k*m + b
-- durch die Messungen nahe diesem Median gelegt (c = -b/k).
local function tTurnCalFitGear(aSamples, aGear)
   local tRange = TURN_K_RANGE[aGear]
   local tList, mMin, mMax = {}, nil, nil
   for x = 1, #aSamples do
      local tS = aSamples[x]
      if tS.g == aGear and tS.m and tS.y then
         tList[#tList + 1] = tS
         if not mMin or tS.m < mMin then mMin = tS.m end
         if not mMax or tS.m > mMax then mMax = tS.m end
      end
   end
   if #tList == 0 then return {k = 1, c = TURN_LOST_DEFAULT, n = 0, how = "default"} end
   local function tRatioFit(aC)
      local tRatios = {}
      for x = 1, #tList do
         local tS = tList[x]
         if tS.m - aC >= 0.5 then tRatios[#tRatios + 1] = tS.y / (tS.m - aC) end
      end
      if #tRatios == 0 then return nil end
      local tKMed = math.max(tRange[1], math.min(tRange[2], tMedianOf(tRatios)))
      -- Streuung als MITTLERE Abweichung: der Median waere 0, sobald mehr
      -- als die Haelfte der Messungen dasselbe m hat, und truege dann jeden
      -- c-Kandidaten gleich gut.
      local tDev = 0
      for x = 1, #tRatios do tDev = tDev + math.abs(tRatios[x] - tKMed) / tKMed end
      return {k = tKMed, c = aC, n = #tRatios, how = "ratio", disp = tDev / #tRatios}
   end
   local tFit = tRatioFit(TURN_LOST_DEFAULT) or {k = 1, c = TURN_LOST_DEFAULT, n = 0, how = "default", disp = 1}
   -- Schon EIN Frame Spreizung trennt die c-Kandidaten (bei m = 2 und 3
   -- streut nur das falsche c); die Gerade unten will zwei.
   if #tList < TURN_CAL_MIN_SAMPLES or mMax - mMin < 1 then
      tFit.disp = nil
      return tFit
   end
   local tBest = tFit
   for tC = TURN_LOST_MIN, TURN_LOST_MAX, 0.5 do
      local tTry = tRatioFit(tC)
      if tTry and tTry.disp < tBest.disp - 0.01 then tBest = tTry end
   end
   tFit = tBest
   local n, sm, sy, smm, smy, lMin, lMax = 0, 0, 0, 0, 0, nil, nil
   for x = 1, #tList do
      local tS = tList[x]
      if tS.m - tBest.c >= 0.5 and math.abs(tS.y / (tS.m - tBest.c) - tBest.k) <= 0.3 * tBest.k then
         n = n + 1
         sm, sy, smm, smy = sm + tS.m, sy + tS.y, smm + tS.m * tS.m, smy + tS.m * tS.y
         if not lMin or tS.m < lMin then lMin = tS.m end
         if not lMax or tS.m > lMax then lMax = tS.m end
      end
   end
   if n >= TURN_CAL_MIN_SAMPLES and lMax - lMin >= 2 then
      local tDenom = n * smm - sm * sm
      if tDenom > 1e-12 then
         local k = (n * smy - sm * sy) / tDenom
         if k >= tRange[1] and k <= tRange[2] then
            local c = -((sy - k * sm) / n) / k
            if c >= TURN_LOST_MIN and c <= TURN_LOST_MAX then
               tFit = {k = k, c = c, n = n, how = "line"}
            end
         end
      end
   end
   tFit.disp = nil
   return tFit
end

local function tTurnCalRefit()
   tTurnCalFit = false
   local tStore = tTurnCalStore()
   if not tStore or tStore.legacy == true then return end
   tTurnCalFit = {[1] = tTurnCalFitGear(tStore.samples, 1), [2] = tTurnCalFitGear(tStore.samples, 2)}
   -- Sicherung: multipliziert das MoveView-Argument auf diesem Client NICHT,
   -- drehen Gang-2-Drehungen trotz verlangter 540+ Grad/s weiter mit ~360.
   -- Dann Gang 2 stilllegen - lieber ehrlich 360 Grad/s und mehr Frames als
   -- ein Massstab, der fuer jeden Faktor ein anderer waere.
   local tReal = {}
   local tC = tTurnCalFit[2].c
   for x = 1, #tStore.samples do
      local tS = tStore.samples[x]
      if tS.g == 2 and tS.s and tS.s >= 540 and tS.m - tC >= 1 then
         tReal[#tReal + 1] = tS.y * tS.s / (tS.m - tC)   -- reale Grad/s
      end
   end
   -- Der Befund bleibt gespeichert (bis /skuturn reset): sonst probiert Gang 2
   -- es erneut, sobald seine Messungen aus dem Ring gefallen sind.
   if #tReal >= 6 and tMedianOf(tReal) < 450 then tStore.noGear2 = true end
   if tStore.noGear2 == true then tTurnCalFit.noGear2 = true end
end

local function tTurnFrameTime()
   local tFps = GetFramerate and GetFramerate() or 60
   if not tFps or tFps < 10 then tFps = 10 elseif tFps > 240 then tFps = 240 end
   return 1 / tFps
end

-- Plant eine Drehung um aAngle Grad (Betrag). Rueckgabe: Sollgeschwindigkeit,
-- Bewegungsframes n, Frames bis zum Stoppbefehl m (Erwartung), Modus,
-- CVar-Wert, MoveView-Faktor, angenommene Framedauer, Massstab k.
local function tTurnPlan(aAngle)
   if tTurnCalFit == nil then tTurnCalRefit() end
   local tF = tTurnFrameTime()
   if not tTurnCalFit then
      local tSweep = aAngle + 5
      local tSpeed = math.max(360, tSweep / TURN_LEGACY_MAX_TIME)
      local n = math.max(1, math.floor(tSweep / (tSpeed * tF) + 0.5))
      return tSpeed, n, n + TURN_LOST_DEFAULT, "legacy", tSpeed, 1, tF, 1
   end
   local tCap = tTurnCalFit.noGear2 and TURN_CVAR_MAX or TURN_SPEED_MAX
   -- Erst die Frames: so wenige, dass das Tempo unter dem Deckel bleibt. Dann
   -- das Tempo, das den Winkel genau trifft. Der Gang folgt aus dem Tempo;
   -- wechselt er, gilt dessen Massstab und die Rechnung laeuft einmal nach.
   local tGear = tCap > TURN_CVAR_MAX and 2 or 1
   local tSpeed, n
   for _ = 1, 2 do
      local tK = tTurnCalFit[tGear].k
      n = math.max(TURN_MIN_STEPS, math.ceil(aAngle / (tK * tCap * tF) - 1e-9))
      tSpeed = math.max(TURN_SPEED_MIN, math.min(tCap, aAngle / (tK * n * tF)))
      local tNewGear = tSpeed > TURN_CVAR_MAX and 2 or 1
      if tNewGear == tGear then break end
      tGear = tNewGear
   end
   tGear = tSpeed > TURN_CVAR_MAX and 2 or 1
   local m = math.max(1, math.floor(n + tTurnCalFit[tGear].c + 0.5))
   local tCVar = math.min(tSpeed, TURN_CVAR_MAX)
   return tSpeed, n, m, "g"..tGear, tCVar, tSpeed / tCVar, tF, tTurnCalFit[tGear].k
end

local function tTurnCalAddSample(aY, aM, aGear, aSpeed)
   local tStore = tTurnCalStore()
   if not tStore then return end
   tStore.samples[#tStore.samples + 1] = {y = aY, m = aM, g = aGear, s = aSpeed}
   while #tStore.samples > TURN_CAL_MAX_SAMPLES do table.remove(tStore.samples, 1) end
   tTurnCalRefit()
end

SLASH_SKUTURN1 = "/skuturn"
SlashCmdList["SKUTURN"] = function(aMsg)
   aMsg = (aMsg or ""):lower():match("^%s*(.-)%s*$")
   local tStore = tTurnCalStore()
   if not tStore then print("SkuTurn: settings not ready") return end
   if aMsg == "reset" then
      tStore.samples = {}
      tStore.noGear2 = nil
   elseif aMsg == "legacy" then
      tStore.legacy = (tStore.legacy ~= true) and true or nil
   end
   tTurnCalRefit()
   local tText = string.format("SkuTurn: %d samples, legacy %s, ", #tStore.samples, tostring(tStore.legacy == true))
   if tTurnCalFit then
      for tGear = 1, 2 do
         local tCal = tTurnCalFit[tGear]
         tText = tText..string.format("gear %d: k %.3f, lost %.2f frames, n %d, %s; ", tGear, tCal.k, tCal.c, tCal.n, tCal.how)
      end
      if tTurnCalFit.noGear2 then tText = tText.."gear 2 OFF (speed factor has no effect here)" end
   else
      tText = tText.."old fixed values in use"
   end
   dprint(tText)
   print(tText)
end

-- [v43.3] Der getestete Dreh-Kern (Snap + Geschwindigkeitsdeckel + Vorhalten +
-- Sequenz-Guards + Transfer-Impuls + Geradestell-Impuls) haengt nicht mehr am
-- Wegpunkt: TurnToWorldPosition dreht zu beliebigen Weltkoordinaten, damit
-- "zu Einheit drehen" (SkuCore/turnToUnit.lua) DENSELBEN Kern nutzt statt
-- einer eigenen, driftenden Kopie. Rueckgabe: true = Drehung angenommen,
-- false = verworfen (Drehung laeuft noch, oder Position/Peilung nicht
-- ermittelbar). Der Busy-Verwurf bleibt absichtlich still - das gewohnte
-- Mehrfachdruecken verfeinert einfach mit dem naechsten Druck nach dem Ende.
function GameWorldObjects:TurnToWorldPosition(aWorldX, aWorldY, aLabel)
   local fPlayerPosX, fPlayerPosY, fPlayerPosZ = UnitPosition("player")
   local degree
   if fPlayerPosX and aWorldX and aWorldY then
      degree = select(3, SkuNav.Geo:GetDirectionTo(fPlayerPosX, fPlayerPosY, aWorldX, aWorldY))
   end
   if degree then
      -- Logging: EINE Zeile je Tastendruck - "TurnCal" (gedreht, mit allen
      -- Messwerten), "TurnToWp skip" (schon ausgerichtet) oder "TurnToWp
      -- ignoriert". Bis 2026-09-21 waren es vier (start, lead, TurnCal, +1s)
      -- und damit beim Routenlaufen 57 Prozent aller Zeilen im Debug-Ring.
      -- Laeuft noch eine Drehung, den Tastendruck VERWERFEN statt neu zu
      -- starten: die laufende Drehung steuert eine keine Viertelsekunde alte
      -- Peilung an - sie abzubrechen wuerfe ihre halbe Arbeit weg (der
      -- Transfer-Impuls feuert erst am Ende). Genau das zeigte das Log
      -- 2026-08-31 16:08: vier Druecke im Drehtakt auf dieselbe 140-Grad-
      -- Peilung, drei davon annulliert. Der naechste Druck NACH dem Ende
      -- verfeinert dann mit frischer Peilung - das gewohnte Mehrfachdruecken
      -- bleibt sinnvoll.
      if SkuCore.gameWorldObjectsTurnBusyUntil and GetTime() < SkuCore.gameWorldObjectsTurnBusyUntil then
         dprint("TurnToWp ignoriert, Drehung laeuft noch",
            string.format("%.2f", SkuCore.gameWorldObjectsTurnBusyUntil - GetTime()))
         return false
      end
      -- VORHALTEN gegen das Kreisen um nahe Wegpunkte (Log 2026-08-31 16:26:
      -- 15 Druecke, jede Drehung ausgefuehrt, Peilung trotzdem konstant ~70
      -- Grad links - ein stabiler Orbit): degree oben ist die Peilung ZUM
      -- ZEITPUNKT DES DRUCKS, aber waehrend Drehung + Transfer laeuft man
      -- weiter, und nah am Punkt wandert die Peilung mit v/r - beim Gehen in
      -- 5 Metern Abstand ~80 Grad pro Sekunde. Darum wird hier auf die
      -- Peilung BEIM LANDEN der Drehung gezielt: Position um Geschwindigkeit
      -- mal (geschaetzte Drehdauer + Transferpuffer) in Blickrichtung
      -- vorgerueckt, Peilung von dort neu gerechnet. Im Stand ist v = 0 und
      -- nichts aendert sich. Der Vorhalteweg ist auf den halben Restabstand
      -- gedeckelt, damit nie HINTER den Wegpunkt gezielt wird (sonst
      -- kommandierte ein naher Frontal-Anlauf eine 180-Grad-Wende).
      -- Blickrichtungsvektor in den Koordinaten von GetDirectionTo: aus
      -- dessen eigener Algebra folgt "geradeaus" = (cos f, sin f) - fuer
      -- afinal = 0 muss atan2(dy, dx) gleich der Blickrichtung sein.
      local tRawDegree = degree
      local tSpeedNow = GetUnitSpeed("player")
      if tSpeedNow and tSpeedNow > 0 and GetPlayerFacing() then
         local _, _, tPlanFrames, _, _, _, tPlanF = tTurnPlan(math.abs(degree))
         -- Transferpuffer 0.05 s statt frueher 0.15: gemessen 2026-09-21 (65
         -- Drehungen beritten, 14 m/s) zielte das Vorhalten im Median ~30
         -- Prozent zu weit - die 0.15 stammten von der alten, langsamen
         -- Drehung. Nutzen hat es nur unter ~5 m Abstand (Fehler beim Landen
         -- 7 statt 16 Grad), darueber war es mit 0.15 eher leicht schaedlich.
         -- [v43.8] In Frames: m Frames bis zum Stopp plus einer fuer den
         -- Transfer, plus 0.03 s (bei 80 fps wie bisher ~0.16 s fuer 180 Grad,
         -- bei 20 fps ~0.28 statt 0.31).
         local tDurEst = (tPlanFrames + 1) * tPlanF + 0.03
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
      -- [v43.7] Schon ausgerichtet -> NICHT drehen. Frueher kommandierte auch
      -- ein Druck bei 0 Grad Peilung noch 5 Grad (der feste Zuschlag), samt
      -- Kameraschwenk und Mouselook-Impuls - der Ruhezustand pendelte darum
      -- bei ~7 Grad, und im Wasser war jeder dieser Druecke ein Tauchstups.
      -- Gilt als angenommen (true): "zu Einheit drehen" spielt dann sein
      -- Erfolgssignal. Die Rettung "naechste Beacon-Drehung stellt gerade"
      -- bleibt erhalten: nass + gesperrt gibt es weiter den Geradestell-
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
      -- Laufende Nummer der Drehung: der nachgelagerte Geradestell-Impuls
      -- unten verfaellt, wenn inzwischen eine NEUERE Drehung laeuft (deren
      -- eigener Impuls uebernimmt) - sonst wuerde sein Kamera-Schnapp einer
      -- gerade rotierenden Kamera die Gierung unter dem Hintern wegziehen.
      SkuCore.gameWorldObjectsTurnSeq = (SkuCore.gameWorldObjectsTurnSeq or 0) + 1
      local tMyTurnSeq = SkuCore.gameWorldObjectsTurnSeq
      -- Zeitstempel dazu: der Steig-/Sinktasten-Geradestell-Impuls (SkuCore/
      -- Core.lua) haelt sich zurueck, solange eine Drehung frisch ist.
      SkuCore.gameWorldObjectsTurnStartedAt = GetTime()
      local tFacingAtStart = GetPlayerFacing()
      -- Eine noch laufende Kamera-Drehung eines schnellen vorherigen
      -- Tastendrucks anhalten, BEVOR neu ausgerichtet wird - sonst dreht ihre
      -- Restbewegung nach dem Snap weiter und verfaelscht den Startpunkt.
      MoveViewRightStop()
      MoveViewLeftStop()
      -- Kamera-Snap auf die SkuStandard-Ansicht (Slot 2, hinter dem
      -- Charakter) - 43.2 entfernt, hier WIEDER EINGEBAUT: degree wird oben
      -- aus der Blickrichtung des CHARAKTERS berechnet, unten aber als
      -- KAMERA-Drehung ausgefuehrt und per Mouselook-Impuls zurueck-
      -- uebertragen. Die Rechnung geht nur auf, wenn Kamera und Charakter
      -- beim Start uebereinstimmen - genau das stellt der Snap her. Ohne ihn
      -- blieb im Stand jeder Versatz dauerhaft stehen (Smoothstyle richtet
      -- nur bei Bewegung nach) und jede weitere Drehung erbte ihn: Drehungen
      -- landeten teils in der falschen Richtung (Log 2026-08-31 15:25).
      -- Die kleine Abwaerts-Neigung der Voreinstellung, wegen der der Snap
      -- entfernt worden war, faengt beim Schwimmen/Fliegen jetzt die
      -- Neigungssperre samt Geradestell-Impuls unten ab.
      -- Der Mouselook-Impuls unten MUSS ebenfalls bleiben: er ist das, was
      -- die Kamera-Gierung auf die Blickrichtung des Charakters uebertraegt.
      local tSnapped = false
      if not SkuCore.CameraSkuStandardActive or SkuCore:CameraSkuStandardActive() then SetView(2) tSnapped = true end
      --SkuCore:GameWorldObjectsCenterMouseCursor(0.5)

      if tTurnYawSpeedSaved == nil then
         tTurnYawSpeedSaved = GetCVar("cameraYawMoveSpeed")
      end

      -- [v43.7] Der feste Zuschlag von 5 Grad und die feste Untergrenze von
      -- 360 Grad/s leben nur noch als Rueckfall in tTurnPlan ("legacy"), bis
      -- genug Messungen fuer die Kalibrierung da sind. Der folgende Absatz
      -- beschreibt diesen Rueckfall und bleibt als Herleitung stehen.
      -- Drehgeschwindigkeit nach Drehgroesse: C_Timer.After stoppt nur
      -- framegenau und feuert IMMER erst im Frame NACH Ablauf - der
      -- Ueberdreh-Fehler ist Drehgeschwindigkeit mal Frame-Verspaetung
      -- (gemessen 2026-08-31: ~3-8 ms auf diesem Rechner). Die alten festen
      -- 1440 Grad/s kosteten damit 8-24 Grad pro Druck, feste 360 Grad/s
      -- machten grosse Drehungen langsam genug, dass das gewohnte
      -- Mehrfachdruecken sie mitten in der Fahrt traf. Deshalb: kleine
      -- Drehungen (die Endkorrektur, Median 5 Grad) laufen praezise mit
      -- 360 Grad/s, groessere gerade so schnell, dass KEINE Drehung laenger
      -- als 0.25 s dauert - selbst 180 Grad kosten dann nur ~720 Grad/s,
      -- also ~3-6 Grad Frame-Fehler, und der Folge-Druck korrigiert langsam.
      local tTarget = math.abs(degree)
      -- [v43.7] Gemessen 2026-09-21: cameraYawMoveSpeed wirkt nur bis 360.
      -- Werte darueber drehen NICHT schneller (376, 453 und 731 ergaben in
      -- 0.25 s alle ~88 Grad). Mehr Tempo kommt nur ueber das Argument von
      -- MoveViewXStart, das die CVar multipliziert (so macht es WowVision).
      -- Also: CVar hoechstens 360, Rest als Faktor.
      -- [v43.8] Plan in Frames: n Bewegungsframes, Stoppbefehl im Frame m
      -- (Herleitung oben bei der Kalibrierung).
      local tSpeed, tSteps, tStopFrame, tPlanMode, tPlanCVar, tPlanFactor, tFrameEst, tPlanK = tTurnPlan(tTarget)
      -- Bewegungszeit, die die Kamera bei diesem Tempo braucht. Der Stopp
      -- unten faellt nicht blind im Frame m, sondern dort, wo die ECHTE
      -- Summe der Framezeiten dem am naechsten kommt: gemessen 2026-09-22
      -- (146 Drehungen, ~80 fps ohne Begrenzer) wich die echte Framedauer
      -- waehrend einer Drehung bis zu 70 Prozent von GetFramerate ab, und
      -- blindes Zaehlen machte daraus bis zu 54 Grad Fehler (Tempo mal
      -- Summe der Abweichungen). Bei begrenzter, stabiler Framerate (20 fps:
      -- Fehler 0.0 bis 1.4 Grad) sind beide Regeln identisch.
      local tMotionTarget = tTarget / (tPlanK * tSpeed)
      local tGear = tPlanMode == "g2" and 2 or 1
      local tDirection = degree < 0 and -1 or 1
      SetCVar("cameraYawMoveSpeed", tPlanCVar)
      if tDirection < 0 then MoveViewRightStart(tPlanFactor) else MoveViewLeftStart(tPlanFactor) end
      -- Nach dem Stopp noch ein paar Frames warten, bevor gemessen und der
      -- naechste Druck zugelassen wird: der Transfer-Impuls wirkt erst im
      -- Folgeframe - ein Druck davor rechnete mit der ALTEN Blickrichtung und
      -- kommandierte dieselbe Drehung noch einmal. Frueher 3 Frames bzw.
      -- 0.1 s; jetzt 2 Frames bzw. 0.05 s (Messung und Freigabe im selben
      -- Frame, dann geht keine Messung an einen schnellen Folgedruck
      -- verloren).
      local tSettleFrames = math.max(TURN_SETTLE_MIN_FRAMES, math.ceil(TURN_SETTLE_MIN_TIME / tFrameEst - 1e-9))
      local tTurnBegin = GetTime()
      -- Schaetzung fuer den Sperr-Guard oben; der Zaehler unten gibt frueher
      -- frei, der Wachhund unten spaetestens.
      SkuCore.gameWorldObjectsTurnBusyUntil = tTurnBegin + (tStopFrame + tSettleFrames) * tFrameEst + 0.25
      local tFrames, tLastFrameTime, tFrameMax = 0, tTurnBegin, 0
      local tMotionAcc, tDts = 0, {}
      local tStopAt, tStopAtFrame, tLandX, tLandY, tDone
      -- Notbremse: nie mehr als das Doppelte der erwarteten Frames.
      local tStopFrameMax = tStopFrame * 2 + 2

      local function tMeasure()
         local tFacingEnd = GetPlayerFacing()
         if not tFacingAtStart or not tFacingEnd or not tStopAt or not tStopAtFrame or tStopAtFrame < 1 then return end
         -- Peilung positiv = Blickrichtung muss SINKEN (afinal = facing - Zielwinkel).
         local tTurned = math.deg(tFacingAtStart - tFacingEnd)
         while tTurned > 180 do tTurned = tTurned - 360 end
         while tTurned <= -180 do tTurned = tTurned + 360 end
         tTurned = tTurned * tDirection
         -- Eine Drehung nahe 180 Grad, die leicht ueberschiesst (181), kaeme
         -- oben als -179 heraus und gaelte als "falsch herum" (Log 2026-09-21
         -- 00:59:05). Darum die Vollkreis-Entsprechung waehlen, die dem Ziel
         -- am naechsten liegt.
         if tTurned < tTarget - 180 then tTurned = tTurned + 360 end
         -- Echte mittlere Framedauer der Drehung: der Stopp fiel genau m
         -- Frames nach dem Druck (GetTime steht je Frame fest, der Zaehler
         -- zaehlt nur Fortschritte). Daraus die gemessenen Bewegungsframes.
         local tElapsed = tStopAt - tTurnBegin
         local tFrameAct = tElapsed / tStopAtFrame
         local tYSteps = (tFrameAct > 0) and tTurned / (tSpeed * tFrameAct) or 0
         local tRatio = tYSteps / tSteps
         local tVerdict = "ok"
         if tPlanMode == "legacy" then tVerdict = "legacy"
         elseif not tSnapped then tVerdict = "no snap"
         elseif tManualTurnLeft or tManualTurnRight or tManualTurnAt >= tTurnBegin then tVerdict = "manual turn"
         elseif tTurned < 1 then tVerdict = "not turned"
         elseif tRatio < 0.15 or tRatio > 4 then tVerdict = "out of range"
         end
         local tFlags = (InCombatLockdown() == true and "combat," or "")
            ..((HasFullControl ~= nil and HasFullControl() ~= true) and "nocontrol," or "")
            ..(IsSwimming() == true and "swim," or "")..(IsFlying() == true and "fly," or "")
         tFlags = tFlags == "" and "-" or string.sub(tFlags, 1, -2)
         if tVerdict == "ok" then tTurnCalAddSample(tYSteps, tStopAtFrame, tGear, tSpeed) end
         dprint("TurnCal", "target", string.format("%.1f", tTarget),
            "turned", string.format("%.1f", tTurned),
            "err", string.format("%.1f", tTurned - tTarget),
            "speed", string.format("%.0f", tSpeed),
            -- n geplante Bewegungsframes, m Frames bis Stoppbefehl, steps
            -- gemessene Bewegungsframes, lost = m - steps (Hypothese: ~1 bei
            -- jedem Tempo und jeder Framerate), fest/fact angenommene/echte
            -- Framedauer, fmax laengster Frame der Drehung (Haenger).
            -- mp = erwartetes m aus dem Plan, m = tatsaechlicher Stoppframe,
            -- mt = angesammelte Bewegungszeit beim Stopp (Hypothese: Frames
            -- 1..m-1 schreiten), dts = alle Framedauern der Drehung.
            "n", tSteps, "mp", tStopFrame, "m", tStopAtFrame,
            "steps", string.format("%.2f", tYSteps),
            "lost", string.format("%.2f", tStopAtFrame - tYSteps),
            "mt", string.format("%.1f", tMotionAcc * 1000),
            "dts", table.concat(tDts, "/"),
            "fest", string.format("%.1f", tFrameEst * 1000),
            "fact", string.format("%.1f", tFrameAct * 1000),
            "fmax", string.format("%.1f", tFrameMax * 1000),
            "elapsed_ms", string.format("%.1f", tElapsed * 1000),
            "fps", string.format("%.0f", tFrameAct > 0 and 1 / tFrameAct or 0),
            -- Braucht es das Vorhalten ueberhaupt? rest_land = Peilung zum Ziel
            -- vom Ort des Transfer-Impulses aus, mit der gelandeten
            -- Blickrichtung - also der echte Zielfehler beim Landen, nicht
            -- erst eine Sekunde spaeter (da ist man am nahen Wegpunkt laengst
            -- vorbei). lead_shift = um wie viel das Vorhalten das Ziel
            -- verschoben hat; rest_land + lead_shift waere der Fehler OHNE.
            "raw", string.format("%.1f", tRawDegree),
            "lead_shift", string.format("%.1f", degree - tRawDegree),
            "rest_land", string.format("%.1f", tLandX and (select(3, SkuNav.Geo:GetDirectionTo(tLandX, tLandY, aWorldX, aWorldY)) or 0) or 0),
            "dist_land", string.format("%.1f", tLandX and (select(2, SkuNav:Distance(tLandX, tLandY, aWorldX, aWorldY)) or -1) or -1),
            "v", string.format("%.1f", GetUnitSpeed("player") or 0),
            -- Zustaende nur nennen, wenn sie vom Normalfall abweichen (spart
            -- ~80 Zeichen je Zeile): combat, nocontrol, swim, fly - sonst "-".
            -- combat/nocontrol wegen der ungeklaerten Null-Drehungen im Stand
            -- (Log 2026-09-21 00:22:58 und 00:42:46). Bewegung steht in v.
            "flags", tFlags,
            "mode", tPlanMode, "sample", tVerdict, "wp", tostring(aLabel))
      end

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
         -- Der Impuls uebertraegt die Kamera-Gierung auf die Blickrichtung des
         -- Charakters - er IST die Drehung und muss bleiben. Beim Schwimmen/
         -- Fliegen nimmt er auch die Kamera-Neigung mit (der Tauchstups);
         -- dagegen steht die Neigungssperre (SkuCore:TogglePitchLock samt
         -- Automatik) und der Geradestell-Impuls unten. Alle Sackgassen:
         -- memory/camera-pitch-api-gap.
         MouselookStart()
         MouselookStop()
         tLandX, tLandY = UnitPosition("player")
         -- Nach JEDER Drehung im Wasser/in der Luft mit aktiver Sperre einmal
         -- aktiv geradestellen (PitchLockLevelPulse: Kamera auf die bekannte
         -- fast-waagerechte Voreinstellung, Transfer-Impuls, Sperre deckelt
         -- den Rest). Schliesst die Luecke "Anflug abgebrochen, kein
         -- NPC-Fenster, schief geblieben": die naechste Beacon-Drehung
         -- richtet wieder aus. VERZOEGERT um 0.5 s, weil die Engine den
         -- Gierungs-Transfer erst einen spaeteren Frame anwendet - ein
         -- sofortiger zweiter Impuls mit zurueckgeschnappter Kamera wuerde
         -- die alte Blickrichtung uebertragen und die Drehung aufheben.
         -- Ohne Sperre KEIN Impuls: er hinterlaesst die kleine Abwaerts-
         -- Restneigung der Voreinstellung - genau der alte Tauch-Bug.
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

      -- Der Frame-Zaehler: zaehlt nur echte Frame-Fortschritte (GetTime steht
      -- innerhalb eines Frames fest; ein OnUpdate noch im Druck-Frame zaehlt
      -- nicht). Im Frame m Stopp + Transfer, tSettleFrames spaeter Messung
      -- und Freigabe. Nur die NEUESTE Drehung zaehlt: laeuft schon eine
      -- neuere, hat DEREN Tastendruck oben unsere Bewegung bereits angehalten
      -- und neu gestartet - ein Stopp hier wuerde sie mitten in der Fahrt
      -- abwuergen, und der Impuls wuerde ihre halbe Drehung vorzeitig auf den
      -- Charakter uebertragen. (Der Guard oben laesst das nicht zu, der
      -- Wachhund unten aber schon.)
      -- [v43.7] Eine NACHKORREKTUR im selben Tastendruck (Rest langsam
      -- nachfahren, vor oder zurueck) wurde 2026-09-21 gebaut, im Spiel
      -- getestet und wieder AUSGEBAUT: die Kamera bewegt sich nach dem Stopp
      -- noch einen Frame weiter (die verlorene Latenz, in c mitgelernt). Ein
      -- Gegenbefehl in diesen Frame kostete ~35 statt 4 Grad, ein Vorwaerts-
      -- befehl schoss 7-21 Grad drueber, und die falsch zugerechneten
      -- Messungen vergifteten die Kalibrierung. Nicht wieder einbauen.
      tTurnFrame:SetScript("OnUpdate", function()
         if SkuCore.gameWorldObjectsTurnSeq ~= tMyTurnSeq then tTurnFrame:SetScript("OnUpdate", nil) return end
         local tNow = GetTime()
         if tNow <= tLastFrameTime then return end
         local tDelta = tNow - tLastFrameTime
         tLastFrameTime = tNow
         tFrames = tFrames + 1
         if not tStopAt then
            if tDelta > tFrameMax then tFrameMax = tDelta end
            if #tDts < 24 then tDts[#tDts + 1] = string.format("%.0f", tDelta * 1000) end
            -- Stoppregel: die Schritte der Frames 1..i-1 sind gelaufen
            -- (tMotionAcc); der naechste Schritt, nach diesem OnUpdate,
            -- braechte die eben gemessene Framedauer dazu. Stoppen, sobald
            -- das Ziel JETZT naeher liegt als nach einem weiteren Schritt -
            -- aber nie vor dem ersten Schritt.
            if (tFrames >= 2 and math.abs(tMotionAcc - tMotionTarget) <= math.abs(tMotionAcc + tDelta - tMotionTarget))
               or tFrames >= tStopFrameMax then
               tStopSweep()
            else
               tMotionAcc = tMotionAcc + tDelta
            end
         elseif tFrames >= tStopAtFrame + tSettleFrames then
            tRelease()
            tMeasure()
         end
      end)
      -- Wachhund: bleibt der Zaehler aus (Frame verborgen, Fehler im Handler),
      -- darf weder die Kamera weiterdrehen noch der Sperr-Guard haengen.
      C_Timer.After((tStopFrame + tSettleFrames) * tFrameEst * 4 + 1, function()
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
   return false
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