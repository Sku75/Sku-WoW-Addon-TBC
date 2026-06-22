---------------------------------------------------------------------------------------------------------------------------------------
-- Sku voice output device sync
-- Stellt sicher, dass Blizzards TTS (C_VoiceChat.SpeakText) auf demselben
-- Audiogeraet ausgegeben wird wie der normale Spiel-Sound.
-- Hintergrund: WoW hat zwei getrennte Output-Driver-CVars:
--   Sound_OutputDriverIndex          -> PlaySoundFile, Musik, SFX
--   Sound_VoiceChatOutputDriverIndex -> Voice-Chat + TTS (SpeakText)
-- Ohne diesen Sync kann die TTS-Stimme auf einem anderen Geraet (z.B.
-- Lautsprecher) landen, obwohl alle anderen Sku-Ausgaben korrekt aufs
-- Headset gehen.
--
-- Vorgehen: Wir wrappen C_VoiceChat.SpeakText global und synchronisieren
-- unmittelbar vor jedem Aufruf den Voice-Chat-Output-Driver mit dem
-- Haupt-Output-Driver. Dadurch bleibt Blizzards Stimme erhalten (nicht
-- die Sku-eigene Stimme), landet aber auf demselben Ausgabegeraet.
---------------------------------------------------------------------------------------------------------------------------------------
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

local function tGetCVar(name)
   if _G.C_CVar and _G.C_CVar.GetCVar then
      local ok, v = pcall(_G.C_CVar.GetCVar, name)
      if ok then return v end
   end
   if _G.GetCVar then
      local ok, v = pcall(_G.GetCVar, name)
      if ok then return v end
   end
   return nil
end

local function tSetCVar(name, value)
   if _G.C_CVar and _G.C_CVar.SetCVar then
      local ok = pcall(_G.C_CVar.SetCVar, name, value)
      if ok then return true end
   end
   if _G.SetCVar then
      local ok = pcall(_G.SetCVar, name, value)
      if ok then return true end
   end
   return false
end

function SkuCore:SyncVoiceChatOutputDriver()
   pcall(function()
      local mainIdx = tGetCVar("Sound_OutputDriverIndex")
      local voiceIdx = tGetCVar("Sound_VoiceChatOutputDriverIndex")
      if mainIdx and voiceIdx and mainIdx ~= voiceIdx then
         tSetCVar("Sound_VoiceChatOutputDriverIndex", mainIdx)
      end
   end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Globaler Wrapper fuer C_VoiceChat.SpeakText: vor jedem Aufruf CVars syncen.
---------------------------------------------------------------------------------------------------------------------------------------
local tSpeakPatchInstalled = false

local function tInstallSpeakPatch()
   if tSpeakPatchInstalled then return true end
   if not (_G.C_VoiceChat and _G.C_VoiceChat.SpeakText) then
      return false
   end
   local tOrig = _G.C_VoiceChat.SpeakText
   _G.C_VoiceChat._origSpeakText = tOrig
   _G.C_VoiceChat.SpeakText = function(...)
      pcall(function()
         local mainIdx = tGetCVar("Sound_OutputDriverIndex")
         local voiceIdx = tGetCVar("Sound_VoiceChatOutputDriverIndex")
         if mainIdx and voiceIdx and mainIdx ~= voiceIdx then
            tSetCVar("Sound_VoiceChatOutputDriverIndex", mainIdx)
         end
      end)
      return tOrig(...)
   end
   tSpeakPatchInstalled = true
   return true
end

function SkuCore:VoiceOutputOnInitialize()
   SkuCore:SyncVoiceChatOutputDriver()
   pcall(tInstallSpeakPatch)
   if _G.C_Timer and _G.C_Timer.After then
      for _, delay in ipairs({0.1, 0.5, 1, 2, 5}) do
         _G.C_Timer.After(delay, function()
            pcall(tInstallSpeakPatch)
            pcall(SkuCore.SyncVoiceChatOutputDriver, SkuCore)
         end)
      end
   end
end
