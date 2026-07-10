---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_PART = "UIErrors"
local L = Sku.L

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- W4 Phase D: UIErrors is a real AceAddon SUBMODULE of SkuCore so it can be turned
-- on/off independently at runtime:
--   * OnEnable  arms the feature (registers UI_ERROR_MESSAGE / UI_INFO_MESSAGE /
--     UNIT_SPELLCAST_INTERRUPTED), replacing the old explicit
--     SkuCore:UIErrorsOnInitialize() call in Core.lua's OnInitialize. Because
--     AceAddon auto-enables modules on every load (not just the initial login),
--     UI-error announcements now re-arm after a /reload too.
--   * OnDisable disarms it (unregisters those events) so a disabled feature is
--     silent.
-- W4 Phase E (namespace extraction): all of UIErrors' own methods now live on the
-- module table `UIErrors` itself (function UIErrors:Method) instead of on the shared
-- SkuCore god-object. The module mixes in AceEvent-3.0 and owns its own UI_ERROR_*/
-- UI_INFO_* event registrations; external callers use the published handle
-- SkuCore.UIErrors. Core.lua's SkuDispatcher callback for UNIT_SPELLCAST_INTERRUPTED
-- is repointed to SkuCore.UIErrors.UNIT_SPELLCAST_INTERRUPTED. The public entry
-- methods short-circuit when the module is disabled. Settings stay under the
-- "SkuCore".UIErrors SkuSettings namespace (Options.lua reads them), so there is no
-- SavedVariables migration.
local UIErrors = SkuCore:NewModule(MODULE_PART, "AceEvent-3.0")
SkuCore.UIErrors = UIErrors   -- keep the published handle

-- Make this feature user-toggleable (Features menu + persisted on/off).
SkuCore:RegisterToggleableModule(MODULE_PART, function()
   return Sku.deEn("Oberflächenfehler", "UI errors")
end)

---------------------------------------------------------------------------------------------------------------------------------------
-- Arm the feature. Called automatically by AceAddon when the module is enabled.
function UIErrors:OnEnable()
   UIErrors:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
   UIErrors:RegisterEvent("UI_ERROR_MESSAGE")
   UIErrors:RegisterEvent("UI_INFO_MESSAGE")
end

-- Disarm the feature: unregister the module's own UI-error events so a disabled
-- UIErrors is silent. (UNIT_SPELLCAST_INTERRUPTED is also driven via a Core.lua
-- SkuDispatcher callback that cannot be unregistered from here; its handler body is
-- guarded with an IsEnabled() check below so it is a no-op when disabled.)
function UIErrors:OnDisable()
   UIErrors:UnregisterAllEvents()
end

---------------------------------------------------------------------------------------------------------------------------------------
function UIErrors:UI_INFO_MESSAGE(aEvent, tMessage, tMessage1)
   if not UIErrors:IsEnabled() then return end
   UIErrors:UIErrorEventHandler(aEvent, tMessage, tMessage1)
end

---------------------------------------------------------------------------------------------------------------------------------------
function UIErrors:UI_ERROR_MESSAGE(aEvent, tMessage, tMessage1)
   if not UIErrors:IsEnabled() then return end
   UIErrors:UIErrorEventHandler(aEvent, tMessage, tMessage1)
end

---------------------------------------------------------------------------------------------------------------------------------------
local tPrevError
local tPrevErrorLimit = 1
local tPrevErrorTime = time()
function UIErrors:UIErrorEventHandler(aEvent, tMessage, tMessage1)
   if not UIErrors:IsEnabled() then return end
      --https://wowwiki-archive.fandom.com/wiki/WoW_Constants/Errors#ERR_SPELL

   local tSoundChannel = SkuOptions.db.profile.SkuCore.UIErrors.ErrorSoundChannel or "Talking Head"
   local tOff = "Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\error\\error_silent.mp3"

   if tonumber(tMessage) and tMessage1 then
      tMessage = tMessage1
   end

   --ERR_BAG_FULL  That bag is full.

   local tIsBase

   --OutOfRangeMelee
   if (tMessage == ERR_BADATTACKPOS or tMessage == ERR_OUT_OF_RANGE) then
      if SkuSettings:Sub("SkuCore").UIErrors.OutOfRangeMelee ~= tOff then
         UIErrors:OutputError(SkuSettings:Sub("SkuCore").UIErrors.OutOfRangeMelee, tSoundChannel, L["Range"])
      end
      tIsBase = true
   end

   --OutOfRangeCast
   if (tMessage == ERR_SPELL_OUT_OF_RANGE or tMessage == SPELL_FAILED_TOO_CLOSE) then
      if SkuSettings:Sub("SkuCore").UIErrors.OutOfRangeCast ~= tOff then
         UIErrors:OutputError(SkuSettings:Sub("SkuCore").UIErrors.OutOfRangeCast, tSoundChannel, L["Range"])
      end
      tIsBase = true
   end
   
   --Moving
   if (tMessage == SPELL_FAILED_MOVING) then
      if SkuSettings:Sub("SkuCore").UIErrors.Moving ~= tOff then
         UIErrors:OutputError(SkuSettings:Sub("SkuCore").UIErrors.Moving, tSoundChannel, L["Move"])
      end
      tIsBase = true
   end

   --NoLoS
   if (tMessage == SPELL_FAILED_LINE_OF_SIGHT or tMessage == SPELL_FAILED_VISION_OBSCURED) then
      if (SkuSettings:Sub("SkuCore").UIErrors.NoLoS ~= tOff) then
         UIErrors:OutputError(SkuSettings:Sub("SkuCore").UIErrors.NoLoS, tSoundChannel, L["LOS"])
      end
      tIsBase = true
   end

   --BadTarget
   if (tMessage == SPELL_FAILED_BAD_TARGETS or tMessage == ERR_INVALID_ATTACK_TARGET or tMessage == SPELL_FAILED_TARGETS_DEAD or tMessage == SPELL_FAILED_BAD_IMPLICIT_TARGETS or tMessage == ERR_NO_ATTACK_TARGET) then
      if (SkuSettings:Sub("SkuCore").UIErrors.BadTarget ~= tOff) then
         UIErrors:OutputError(SkuSettings:Sub("SkuCore").UIErrors.BadTarget, tSoundChannel, L["Target"])
      end
      tIsBase = true
   end

   --InCombat
   if (tMessage == SPELL_FAILED_AFFECTING_COMBAT and SkuSettings:Sub("SkuCore").UIErrors.InCombat ~= tOff) then
      UIErrors:OutputError(SkuSettings:Sub("SkuCore").UIErrors.InCombat, tSoundChannel, L["IC"])
      tIsBase = true
   end

   --NoMana
   if (tMessage == ERR_OUT_OF_MANA or tMessage == ERR_OUT_OF_RAGE or tMessage == ERR_OUT_OF_ENERGY) then
      if SkuSettings:Sub("SkuCore").UIErrors.NoMana ~= tOff then
         UIErrors:OutputError(SkuSettings:Sub("SkuCore").UIErrors.NoMana, tSoundChannel, L["Res"])
      end
      tIsBase = true
   end

   --ObjectBusy

   if (tMessage == ERR_OBJECT_IS_BUSY or tMessage == SPELL_FAILED_CHEST_IN_USE or tMessage == ERR_CHEST_IN_USE or tMessage == ERR_INV_FULL) then
      if (SkuSettings:Sub("SkuCore").UIErrors.ObjectBusy ~= tOff) then
         UIErrors:OutputError(SkuSettings:Sub("SkuCore").UIErrors.ObjectBusy, tSoundChannel, L["Busy"])
      end
      tIsBase = true
   end

   --NotFacing

   if (tMessage == ERR_BADATTACKFACING or tMessage == SPELL_FAILED_UNIT_NOT_INFRONT or tMessage == SPELL_FAILED_NOT_BEHIND or tMessage == SPELL_FAILED_UNIT_NOT_BEHIND) then
      if (SkuSettings:Sub("SkuCore").UIErrors.NotFacing ~= tOff) then
         UIErrors:OutputError(SkuSettings:Sub("SkuCore").UIErrors.NotFacing, tSoundChannel, L["Dir"])
      end
      tIsBase = true
   end

   --CrowdControlled

   if (tMessage == SPELL_FAILED_SILENCED or tMessage == SPELL_FAILED_STUNNED or tMessage == ERR_ATTACK_PACIFIED or tMessage == ERR_ATTACK_CHARMED or tMessage == ERR_ATTACK_CONFUSED or tMessage == ERR_ATTACK_FLEEING or string.find(tMessage, string.sub(ERR_ATTACK_PREVENTED_BY_MECHANIC_S, 1, string.len(ERR_ATTACK_PREVENTED_BY_MECHANIC_S) - 5))) then
      if (SkuSettings:Sub("SkuCore").UIErrors.CrowdControlled ~= tOff) then
         UIErrors:OutputError(SkuSettings:Sub("SkuCore").UIErrors.CrowdControlled, tSoundChannel, L["Stun"])
      end
      tIsBase = true
   end

   --cd
   if (tMessage == ERR_SPELL_COOLDOWN or tMessage == ERR_ABILITY_COOLDOWN) then
      if (SkuSettings:Sub("SkuCore").UIErrors.Cooldown ~= tOff) then
         UIErrors:OutputError(SkuSettings:Sub("SkuCore").UIErrors.Cooldown, tSoundChannel, L["cooldown"])
      end
      tIsBase = true
   end
   
   if tMessage == 50 then --"interrupted"; unknown constant
      if UIErrors:UNIT_SPELLCAST_INTERRUPTED("UNIT_SPELLCAST_INTERRUPTED", "player") then
         tIsBase = true
      end
   end

   if not tIsBase then
      if (SkuSettings:Sub("SkuCore").UIErrors.Other ~= tOff) then
         UIErrors:OutputError(nil, nil, tMessage)
      end
   end

end
---------------------------------------------------------------------------------------------------------------------------------------
function UIErrors:UNIT_SPELLCAST_INTERRUPTED(aEvent, aUnit)
   if not UIErrors:IsEnabled() then return end
   local tSoundChannel = SkuOptions.db.profile.SkuCore.UIErrors.ErrorSoundChannel or "Talking Head"
   local tOff = "Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\error\\error_silent.mp3"
   
   --Interrupted
   if (SkuSettings:Sub("SkuCore").UIErrors.Interrupted ~= tOff) then
      if (aUnit == "player") then
         UIErrors:OutputError(SkuSettings:Sub("SkuCore").UIErrors.Interrupted, tSoundChannel, L["Inter"])
         return true
      end
   end
  
end

---------------------------------------------------------------------------------------------------------------------------------------
function UIErrors:OutputError(aSound, aChannel, aMessage)
   --print(aSound, aChannel, aMessage)

   -- aSound vocabulary (a single persisted string per error category):
   --   "voice"      -> Blizzard TTS with the user's global/default voice
   --   "voice#<n>"  -> Blizzard TTS with a specific voice (1-based index into
   --                   SkuChat.WowTtsVoices, same domain as the per-channel chat
   --                   voice; SkuVoice applies the "-1" API convention)
   --   any file path -> PlaySoundFile (abstract beep, spoken clip, or the
   --                    error_silent.mp3 "off" file)
   local tVoiceIndex
   if aSound == "voice" then
      aSound = nil
   elseif type(aSound) == "string" then
      local tIdx = aSound:match("^voice#(%d+)$")
      if tIdx then
         tVoiceIndex = tonumber(tIdx)
         aSound = nil
      end
   end

   if aSound then
      if tPrevError == aSound and (time() - tPrevErrorTime < tPrevErrorLimit) then
         return
      end

      PlaySoundFile(aSound, aChannel)

      tPrevError = aSound
      tPrevErrorTime = time()
   else
      SkuOptions.Voice:OutputStringBTtts(aMessage, {overwrite = false, wait = false, length = 0.8, engine = 1, instant = true, voice = tVoiceIndex})
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Error-feedback menu (Monitor -> "Fehlerfeedback").
--
-- Each error category is a dynamic node whose label shows its current output mode
-- and which descends into four choices:
--   * TTS            -> a submenu of ALL Blizzard TTS voices (+ "Standardstimme" =
--                       the user's global voice). Same voice list/domain as the
--                       per-channel chat voices.
--   * Sprachhinweis  -> the pre-recorded spoken clips (Marlene/Hans, de + en), one
--     (voice hint)      per category that has a clip.
--   * Tonhinweis     -> the abstract beeps (brang/bring/dang/...).
--     (sound hint)
--   * Stumm          -> silence (the error_silent.mp3 sentinel).
--     (silence)
--
-- The chosen value is persisted as ONE string in SkuCore.UIErrors.<key>, keeping
-- the old select's storage shape (backward compatible, no migration):
--   "voice" / "voice#<n>" / <clip.mp3 path> / <beep.ogg path> / error_silent.mp3
-- OutputError above decodes this vocabulary. Focus-preview (audition on OnEnter) is
-- driven by the errorPreviewFile / errorPreviewVoiceIndex fields the leaves carry
-- (handled generically in SkuZOptions/templates.lua).
local UIERR_DIR = "Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\error\\"
local UIERR_SILENT = UIERR_DIR.."error_silent.mp3"

-- key   = SkuCore.UIErrors.<key> settings field
-- label = spoken menu label (existing localized strings)
-- clip  = voice-hint clip basename, or nil when no spoken clip exists (Cooldown/Other)
local UIERR_CATEGORIES = {
   {key = "OutOfRangeMelee", label = L["out of range melee"], clip = "Range"},
   {key = "OutOfRangeCast",  label = L["out of range cast"],  clip = "Range"},
   {key = "Moving",          label = L["Moving"],             clip = "Move"},
   {key = "NoLoS",           label = L["No LoS"],             clip = "LOS"},
   {key = "BadTarget",       label = L["Bad Target"],         clip = "Target"},
   {key = "InCombat",        label = L["In Combat"],          clip = "IC"},
   {key = "NoMana",          label = L["No ressource"],       clip = "Res"},
   {key = "ObjectBusy",      label = L["Object Busy"],        clip = "Busy"},
   {key = "NotFacing",       label = L["Not Facing"],         clip = "Dir"},
   {key = "CrowdControlled", label = L["Crowd Controlled"],   clip = "Stun"},
   {key = "Interrupted",     label = L["Interrupted"],        clip = "Inter"},
   {key = "Cooldown",        label = L["cooldown"],           clip = nil},
   {key = "Other",           label = L["other"],              clip = nil},
}

-- speaker/language sets for the voice hints (folder naming differs per set on disk)
local function UIErr_VoiceHintSets()
   return {
      {label = "Marlene ("..Sku.deEn("Deutsch", "German")..")",   folder = "marlene_deDE"},
      {label = "Hans ("..Sku.deEn("Deutsch", "German")..")",      folder = "hans_de-de"},
      {label = "Marlene ("..Sku.deEn("Englisch", "English")..")", folder = "marlene_enUS"},
      {label = "Hans ("..Sku.deEn("Englisch", "English")..")",    folder = "hans_en-us"},
   }
end

-- the abstract beeps (labels reuse the existing localized sound names)
local function UIErr_SoundHints()
   return {
      {label = L["brang"],   file = UIERR_DIR.."error_brang.ogg"},
      {label = L["bring"],   file = UIERR_DIR.."error_bring.ogg"},
      {label = L["dang"],    file = UIERR_DIR.."error_dang.ogg"},
      {label = L["drmm"],    file = UIERR_DIR.."error_drmm.ogg"},
      {label = L["shhhup"],  file = UIERR_DIR.."error_shhhup.ogg"},
      {label = L["spoing"],  file = UIERR_DIR.."error_spoing.ogg"},
      {label = L["swoosh"],  file = UIERR_DIR.."error_swoosh.ogg"},
      {label = L["tsching"], file = UIERR_DIR.."error_tsching.ogg"},
   }
end

local function UIErr_Read(aKey)
   return SkuSettings:Sub("SkuCore").UIErrors[aKey]
end
local function UIErr_Write(aKey, aVal)
   SkuSettings:Sub("SkuCore").UIErrors[aKey] = aVal
end

-- human-readable state suffix appended to a category's node label
local function UIErr_StateSuffix(aVal)
   if aVal == nil or aVal == UIERR_SILENT then
      return Sku.deEn("Stumm", "Silence")
   end
   if aVal == "voice" then
      return "TTS: "..Sku.deEn("Standardstimme", "Default voice")
   end
   if type(aVal) == "string" then
      local tIdx = aVal:match("^voice#(%d+)$")
      if tIdx then
         local tName = SkuChat and SkuChat.WowTtsVoices and SkuChat.WowTtsVoices[tonumber(tIdx)]
         return "TTS: "..(tName or tIdx)
      end
      if aVal:find("marlene_", 1, true) or aVal:find("hans_", 1, true) then
         for _, tSet in ipairs(UIErr_VoiceHintSets()) do
            if aVal:find(tSet.folder, 1, true) then
               return Sku.deEn("Sprachhinweis", "Voice hint")..": "..tSet.label
            end
         end
         return Sku.deEn("Sprachhinweis", "Voice hint")
      end
      for _, tSnd in ipairs(UIErr_SoundHints()) do
         if aVal == tSnd.file then
            return Sku.deEn("Tonhinweis", "Sound hint")..": "..tSnd.label
         end
      end
   end
   return tostring(aVal)
end

-- build one category node (shows its state + descends into the four modes)
local function UIErr_BuildCategoryNode(aParent, aCat)
   local tNode = SkuOptions:InjectMenuItems(aParent,
      {aCat.label.." ("..UIErr_StateSuffix(UIErr_Read(aCat.key))..")"}, SkuGenericMenuItem)
   tNode.dynamic = true
   tNode.sorting = false

   local function Refresh()
      tNode:OnUpdate(tNode)
   end

   tNode.BuildChildren = function(self)
      -- 1) TTS -> every Blizzard TTS voice. There is no separate "Standardstimme"
      -- entry: the standard voice is already one of the listed voices, so on open the
      -- menu just pre-positions (GetCurrentValue) on the currently selected voice,
      -- resolving the "voice" default to the user's global standard voice.
      local tTts = SkuOptions:InjectMenuItems(self, {"TTS"}, SkuGenericMenuItem)
      tTts.dynamic = true
      tTts.sorting = true
      tTts.GetCurrentValue = function(self)
         local tVal = UIErr_Read(aCat.key)
         local tIdx = (type(tVal) == "string") and tonumber(tVal:match("^voice#(%d+)$")) or nil
         tIdx = tIdx or (SkuOptions.db.profile.SkuChat and SkuOptions.db.profile.SkuChat.WowTtsVoice) or 1
         local tVoices = SkuChat and SkuChat.WowTtsVoices or {}
         return tVoices[tIdx]
      end
      tTts.BuildChildren = function(self)
         for tIdx, tVName in pairs(SkuChat and SkuChat.WowTtsVoices or {}) do
            local tV = SkuOptions:InjectMenuItems(self, {tVName}, SkuGenericMenuItem)
            tV.errorPreviewVoiceIndex = tIdx
            tV.errorPreviewText = aCat.label
            tV.OnAction = function() UIErr_Write(aCat.key, "voice#"..tIdx) Refresh() end
         end
      end

      -- 2) Sprachhinweis (voice hint) -> speaker/language sets (only if a clip exists)
      if aCat.clip then
         local tVh = SkuOptions:InjectMenuItems(self,
            {Sku.deEn("Sprachhinweis", "Voice hint")}, SkuGenericMenuItem)
         tVh.dynamic = true
         tVh.sorting = false
         tVh.BuildChildren = function(self)
            for _, tSet in ipairs(UIErr_VoiceHintSets()) do
               local tPath = UIERR_DIR..tSet.folder.."\\error_"..aCat.clip..".mp3"
               local tE = SkuOptions:InjectMenuItems(self, {tSet.label}, SkuGenericMenuItem)
               tE.errorPreviewFile = tPath
               tE.OnAction = function() UIErr_Write(aCat.key, tPath) Refresh() end
            end
         end
      end

      -- 3) Tonhinweis (sound hint) -> the abstract beeps
      local tSh = SkuOptions:InjectMenuItems(self,
         {Sku.deEn("Tonhinweis", "Sound hint")}, SkuGenericMenuItem)
      tSh.dynamic = true
      tSh.sorting = false
      tSh.BuildChildren = function(self)
         for _, tSnd in ipairs(UIErr_SoundHints()) do
            local tE = SkuOptions:InjectMenuItems(self, {tSnd.label}, SkuGenericMenuItem)
            tE.errorPreviewFile = tSnd.file
            tE.OnAction = function() UIErr_Write(aCat.key, tSnd.file) Refresh() end
         end
      end

      -- 4) Stumm (silence) — a leaf
      local tSil = SkuOptions:InjectMenuItems(self,
         {Sku.deEn("Stumm", "Silence")}, SkuGenericMenuItem)
      tSil.OnAction = function() UIErr_Write(aCat.key, UIERR_SILENT) Refresh() end
   end

   return tNode
end

-- BuildChildren for the "Fehlerfeedback" node. Assigned in aq.lua's Monitor menu and
-- called as node:BuildChildren(node), so `self` here is that menu node.
function UIErrors:MenuBuilder()
   -- sound channel used for beep/clip playback (first entry, mirrors the old group)
   local tCur = SkuOptions.db.profile.SkuCore.UIErrors.ErrorSoundChannel or "Talking Head"
   local tCurName = (SKU_CONSTANTS and SKU_CONSTANTS.SOUNDCHANNELS and SKU_CONSTANTS.SOUNDCHANNELS[tCur]) or tCur
   local tChan = SkuOptions:InjectMenuItems(self,
      {L["sound channel"].." ("..tCurName..")"}, SkuGenericMenuItem)
   tChan.dynamic = true
   tChan.sorting = true
   tChan.BuildChildren = function(self)
      for tVal, tName in pairs(SKU_CONSTANTS.SOUNDCHANNELS) do
         local tE = SkuOptions:InjectMenuItems(self, {tName}, SkuGenericMenuItem)
         tE.OnAction = function()
            SkuOptions.db.profile.SkuCore.UIErrors.ErrorSoundChannel = tVal
            tChan:OnUpdate(tChan)
         end
      end
   end

   for _, tCat in ipairs(UIERR_CATEGORIES) do
      UIErr_BuildCategoryNode(self, tCat)
   end
end