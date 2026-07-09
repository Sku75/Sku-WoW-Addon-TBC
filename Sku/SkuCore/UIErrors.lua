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

   if aSound and aSound ~= "voice" then
      if tPrevError == aSound and (time() - tPrevErrorTime < tPrevErrorLimit) then
         return
      end

      PlaySoundFile(aSound, aChannel)

      tPrevError = aSound
      tPrevErrorTime = time()
   else
      SkuOptions.Voice:OutputStringBTtts(aMessage, false, false, 0.8, nil, nil, nil, 1, nil, nil, true)
   end
end