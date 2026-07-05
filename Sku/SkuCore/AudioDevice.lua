-- =====================================================================
-- Sku Audio Device Switcher
-- ---------------------------------------------------------------------
-- The audio device picker in the WoW options panel is not accessible
-- via screen-reader / keyboard for blind players. This module exposes
-- the same functionality as simple slash commands so the output device
-- (speakers vs. headset) can be changed without touching the mouse or
-- reading the visual options menu.
--
-- Slash:
--   /skuaudio              - spricht Hilfe + aktuelles Gerät
--   /skuaudio list         - spricht alle verfügbaren Geräte + Index
--   /skuaudio current      - spricht das aktuell gewählte Gerät
--   /skuaudio set <N>      - setzt Gerät Nummer N und startet Sound neu
--   /skuaudio find <text>  - sucht Gerät nach Name (z.B. "headset") und setzt es
--   /skuaudio restart      - Soundsystem neu starten (ohne Gerätewechsel)
--
-- All output goes through print() so SkuChat's screen-reader pipeline
-- speaks it automatically. If SkuOptions:OutputStringB is available it
-- is used additionally for direct TTS, as a belt-and-braces fallback.
-- =====================================================================

local MODULE_NAME, MODULE_PART = "SkuCore", "AudioDevice"
local L = Sku.L

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- W4 Phase D: AudioDevice is a real AceAddon SUBMODULE of SkuCore so it can be
-- turned on/off at runtime. The only thing this feature "arms" is its slash
-- command (/skuaudio, /audio). The slash handler stays registered for the whole
-- session (a SlashCmdList entry cannot be cleanly removed), but its body is gated
-- by IsEnabled(): when the module is disabled the command is a harmless no-op.
-- OnEnable installs the slash entry (idempotent across enable/disable cycles).
local AudioDevice = SkuCore:NewModule(MODULE_PART)
SkuCore.AudioDevice = AudioDevice   -- keep a published handle (harmless if unused elsewhere)

-- Make this feature user-toggleable (Features menu + persisted on/off). One line;
-- the framework (SkuCore/ModuleManager.lua) handles the rest.
SkuCore:RegisterToggleableModule(MODULE_PART, function()
   return (GetLocale and GetLocale() == "deDE") and "Audiogerät" or "Audio device"
end)

local function tSay(aText)
   if type(aText) ~= "string" then aText = tostring(aText) end
   -- Go through default chat frame so SkuChat reads it.
   if DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffSkuAudio|r: " .. aText)
   end
   -- Direct TTS path if available
   if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringB then
      pcall(function()
         SkuOptions.Voice:OutputStringB(aText, true, true, 0.3, true, false, false)
      end)
   elseif SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputString then
      pcall(function() SkuOptions.Voice:OutputString(aText, true) end)
   end
end

local function tGetDeviceCount()
   if _G.Sound_GameSystem_GetNumOutputDrivers then
      local ok, n = pcall(Sound_GameSystem_GetNumOutputDrivers)
      if ok and type(n) == "number" then return n end
   end
   return 0
end

local function tGetDeviceName(aIndex)
   if _G.Sound_GameSystem_GetOutputDriverNameByIndex then
      local ok, name = pcall(Sound_GameSystem_GetOutputDriverNameByIndex, aIndex)
      if ok and type(name) == "string" then return name end
   end
   return L["unbekannt"]
end

local function tGetCurrentIndex()
   local tOk, tVal = pcall(GetCVar, "Sound_OutputDriverIndex")
   if tOk and tVal then
      return tonumber(tVal) or 0
   end
   return 0
end

local function tRestartSound()
   if _G.Sound_GameSystem_RestartSoundSystem then
      pcall(Sound_GameSystem_RestartSoundSystem)
      return true
   end
   return false
end

local function tSetDevice(aIndex)
   local tCount = tGetDeviceCount()
   if tCount == 0 then
      tSay(L["Keine Audiogeräte gefunden."])
      return
   end
   -- WoW uses 0-based index for this CVar
   if aIndex < 0 or aIndex >= tCount then
      tSay(string.format(L["Ungültige Nummer. Gültig: 0 bis %s. Benutze /skuaudio list."], tCount - 1))
      return
   end
   local tName = tGetDeviceName(aIndex)
   local tOk = pcall(SetCVar, "Sound_OutputDriverIndex", tostring(aIndex))
   if not tOk then
      tSay(L["Konnte CVar nicht setzen."])
      return
   end
   tRestartSound()
   tSay(string.format(L["Gerät gewechselt auf Nummer %s: %s"], aIndex, tName))
end

local function tListDevices()
   local tCount = tGetDeviceCount()
   if tCount == 0 then
      tSay(L["Keine Audiogeräte gefunden."])
      return
   end
   local tCurrent = tGetCurrentIndex()
   tSay(string.format(L["%s Audiogeräte verfügbar. Aktuell Nummer %s."], tCount, tCurrent))
   -- WoW indexes are 0-based
   for i = 0, tCount - 1 do
      local tMark = (i == tCurrent) and L[" (aktiv)"] or ""
      tSay(string.format(L["Nummer %s: %s"], i, tGetDeviceName(i)) .. tMark)
   end
   tSay(L["Zum Wechseln: /skuaudio set <Nummer>  oder  /skuaudio find headset"])
end

local function tCurrent()
   local tIdx = tGetCurrentIndex()
   tSay(string.format(L["Aktuelles Ausgabegerät: Nummer %s: %s"], tIdx, tGetDeviceName(tIdx)))
end

local function tFindAndSet(aQuery)
   aQuery = (aQuery or ""):lower():match("^%s*(.-)%s*$")
   if aQuery == "" then
      tSay(L["Suchbegriff fehlt. Beispiel: /skuaudio find headset"])
      return
   end
   local tCount = tGetDeviceCount()
   local tMatches = {}
   for i = 0, tCount - 1 do
      local tName = tGetDeviceName(i)
      if tName:lower():find(aQuery, 1, true) then
         tMatches[#tMatches + 1] = { idx = i, name = tName }
      end
   end
   if #tMatches == 0 then
      tSay(string.format(L["Kein Gerät enthält '%s'. /skuaudio list für alle Namen."], aQuery))
      return
   end
   if #tMatches > 1 then
      tSay(string.format(L["%s Treffer — bitte genauer:"], #tMatches))
      for _, m in ipairs(tMatches) do
         tSay(string.format(L["Nummer %s: %s"], m.idx, m.name))
      end
      return
   end
   tSetDevice(tMatches[1].idx)
end

-- The slash handler. Gated by IsEnabled() so a disabled feature is a safe no-op
-- (the SlashCmdList entry itself is installed once in OnEnable and left in place).
local function SkuAudioSlashHandler(aMsg)
   if not AudioDevice:IsEnabled() then return end
   aMsg = aMsg or ""
   local tCmd, tArg = aMsg:match("^%s*(%S+)%s*(.*)$")
   tCmd = (tCmd or ""):lower()
   if tCmd == "" then
      tCurrent()
      tSay(L["Befehle: list, current, set N, find <text>, restart"])
      return
   end
   if tCmd == "list" then
      tListDevices()
   elseif tCmd == "current" then
      tCurrent()
   elseif tCmd == "set" then
      local tN = tonumber(tArg)
      if not tN then
         tSay(L["Bitte eine Zahl angeben. Beispiel: /skuaudio set 2"])
         return
      end
      tSetDevice(tN)
   elseif tCmd == "find" then
      tFindAndSet(tArg)
   elseif tCmd == "restart" then
      if tRestartSound() then
         tSay(L["Soundsystem neu gestartet."])
      else
         tSay(L["Funktion nicht verfügbar."])
      end
   else
      tSay(L["Unbekannt. Verfügbar: list, current, set N, find <text>, restart"])
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Arm the feature: install the slash command. Called automatically by AceAddon
-- when the module is enabled (at SkuCore enable, and again on user re-enable).
-- Installing is idempotent, so re-enabling does no harm.
function AudioDevice:OnEnable()
   SLASH_SKUAUDIO1 = "/skuaudio"
   SLASH_SKUAUDIO2 = "/audio"
   SlashCmdList["SKUAUDIO"] = SkuAudioSlashHandler
end

-- Disarm the feature. The slash entry stays registered (SlashCmdList entries
-- cannot be cleanly removed), but its handler body short-circuits via IsEnabled(),
-- so a disabled AudioDevice does nothing.
function AudioDevice:OnDisable()
end
