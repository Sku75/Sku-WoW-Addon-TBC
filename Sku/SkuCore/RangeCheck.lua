---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME, MODULE_PART = "SkuCore", "RangeCheck"
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- W4 Phase D: RangeCheck is a real AceAddon SUBMODULE of SkuCore, so it can be
-- turned on/off at runtime (OnEnable/OnDisable), mirroring the JunkAndRepair
-- pilot. RangeCheck is a SHARED SERVICE: SkuMob, SkuNav and a Core.lua OnUpdate
-- all call into it.
-- W4 Phase E (namespace extraction): all of RangeCheck's own methods and module
-- state now live on the module table `RangeCheck` (function RangeCheck:Method)
-- instead of on the shared SkuCore god-object. External callers use the published
-- handle SkuCore.RangeCheck (e.g. SkuCore.RangeCheck:DoRangeCheck).
--   * OnEnable  arms the feature (registers the LibRangeCheck CHECKERS_CHANGED
--     callback + runs RangeCheck:RangeCheckOnEnable).
--   * OnDisable unregisters that callback, and the IsEnabled guard at the top of
--     RangeCheck:DoRangeCheck makes the service a safe no-op while disabled.
-- AceAddon auto-enables the module at SkuCore enable (≈ PLAYER_LOGIN) and again
-- on every /reload, replacing the old explicit RangeCheckOnInitialize/OnEnable
-- calls in Core.lua (so it re-arms on every load, not just the initial login).
local RangeCheck = SkuCore:NewModule(MODULE_PART)
SkuCore.RangeCheck = RangeCheck   -- keep the published handle

-- Make this feature user-toggleable (Features menu + persisted on/off). One line;
-- the framework (SkuCore/ModuleManager.lua) handles the rest.
SkuCore:RegisterToggleableModule(MODULE_PART, function()
   return (GetLocale and GetLocale() == "deDE") and "Reichweitenprüfung" or "Range check"
end)

RangeCheck.RangeCheckValues = {
   Ranges = {
      Friendly = {},
      Hostile = {},
      Misc = {},
   },
}

---------------------------------------------------------------------------------------------------------------------------------------
function RangeCheck:RangeCheckOnInitialize()
   SkuOptions.RangeCheck.RegisterCallback(self, SkuOptions.RangeCheck.CHECKERS_CHANGED, "CHECKERS_CHANGED")
end

---------------------------------------------------------------------------------------------------------------------------------------
function RangeCheck:CHECKERS_CHANGED()
   RangeCheck:RangeCheckUpdateRanges()
end
---------------------------------------------------------------------------------------------------------------------------------------
function RangeCheck:RangeCheckOnEnable()
end

---------------------------------------------------------------------------------------------------------------------------------------
local tFirstRangeUpdateSilent = true
function RangeCheck:RangeCheckUpdateRanges()
   if SkuOptions.RangeCheck.frame:IsVisible() == true then
      C_Timer.After(0.1, function() RangeCheck:RangeCheckUpdateRanges() end)
      return
   end
   if not SkuSettings:Sub("SkuCore", nil, "char") then
      SkuSettings:Sub("SkuCore", nil, "char")
   end

   if not SkuSettings:Sub("SkuCore", nil, "char").RangeChecks then
      --[[
      SkuSettings:Sub("SkuCore", nil, "char").RangeChecks = {
         Friendly = {},
         Hostile = {},
         Misc = {},
      }
      ]]
      local tDefBands = {5, 8, 10, 15, 20, 25, 30, 35, 40, 45, 60}
      local function tMakeDefaultBands()
         local t = {}
         for _, d in ipairs(tDefBands) do
            t[d] = {["sound"] = L["vocalized"]}
         end
         return t
      end
      SkuSettings:Sub("SkuCore", nil, "char").RangeChecks = {
         ["Misc"] = {
            [8] = {["sound"] = L["vocalized"]},
            [28] = {["sound"] = L["vocalized"]},
         },
         ["Friendly"] = tMakeDefaultBands(),
         ["Hostile"] = tMakeDefaultBands(),
      }
   end

   if tFirstRangeUpdateSilent then
      tFirstRangeUpdateSilent = nil
   else
      SkuOptions.Voice:OutputString(L["Neue Reichweite verfügbar"], true, true, 0.2)
   end

   RangeCheck.RangeCheckValues.Ranges.Friendly = {}
   --query available ranges
   for i, v in SkuOptions.RangeCheck:GetFriendCheckers() do
      RangeCheck.RangeCheckValues.Ranges.Friendly[i] = v
   end
   --remove configured checks that a not longer available
   for i, v in pairs(SkuSettings:Sub("SkuCore", nil, "char").RangeChecks.Friendly) do
      if not RangeCheck.RangeCheckValues.Ranges.Friendly[i] then
         SkuSettings:Sub("SkuCore", nil, "char").RangeChecks.Friendly[i] = nil
      end
   end

   for i, v in SkuOptions.RangeCheck:GetHarmCheckers() do
      RangeCheck.RangeCheckValues.Ranges.Hostile[i] = v
   end
   for i, v in pairs(SkuSettings:Sub("SkuCore", nil, "char").RangeChecks.Hostile) do
      if not RangeCheck.RangeCheckValues.Ranges.Hostile[i] then
         SkuSettings:Sub("SkuCore", nil, "char").RangeChecks.Hostile[i] = nil
      end
   end

   for i, v in SkuOptions.RangeCheck:GetMiscCheckers() do
      RangeCheck.RangeCheckValues.Ranges.Misc[i] = v
   end
   for i, v in pairs(SkuSettings:Sub("SkuCore", nil, "char").RangeChecks.Misc) do
      if not RangeCheck.RangeCheckValues.Ranges.Misc[i] then
         SkuSettings:Sub("SkuCore", nil, "char").RangeChecks.Misc[i] = nil
      end
   end   

end
   
---------------------------------------------------------------------------------------------------------------------------------------
-- Arm the shared range-check service. Called automatically by AceAddon when the
-- module is enabled (at SkuCore enable, on every /reload, and whenever the user
-- toggles it back on). Mirrors the old Core.lua RangeCheckOnInitialize +
-- RangeCheckOnEnable calls.
function RangeCheck:OnEnable()
   RangeCheck:RangeCheckOnInitialize()
   RangeCheck:RangeCheckOnEnable()
end

-- Disarm: drop the LibRangeCheck CHECKERS_CHANGED subscription so a disabled
-- feature stops reacting to checker changes. The IsEnabled guard in
-- SkuCore:DoRangeCheck makes the per-target service itself a safe no-op.
function RangeCheck:OnDisable()
   if SkuOptions and SkuOptions.RangeCheck and SkuOptions.RangeCheck.UnregisterCallback then
      SkuOptions.RangeCheck.UnregisterCallback(RangeCheck, SkuOptions.RangeCheck.CHECKERS_CHANGED)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
local tRangeCheckLastTarget
local tRangeCheckLastTargetminRange = 0
function RangeCheck:DoRangeCheck(aForceFlag)
   if not RangeCheck:IsEnabled() then
      return
   end

   if not SkuSettings:Sub("SkuCore", nil, "char") then
      return
   end

   local tCheckRequired = false
   local tMaxRange, tMinRange = SkuOptions.RangeCheck:GetRange("target")
   if tRangeCheckLastTarget ~= UnitGUID("target") then
      tRangeCheckLastTarget = UnitGUID("target")
      tRangeCheckLastTargetminRange = tMinRange
      tCheckRequired = true
   else
      if tRangeCheckLastTargetminRange ~= tMinRange then
         tCheckRequired = true
         tRangeCheckLastTargetminRange = tMinRange
      end
   end

   if aForceFlag == true then
      tCheckRequired = true
   end

   if tCheckRequired == true then
      local tCheckType = "Misc"
      if UnitIsDead("target") == false then
         if UnitCanAttack("player", "target") then
            tCheckType = "Hostile"
         elseif UnitCanAssist("player", "target") then
            tCheckType = "Friendly"
         end
      end

      if SkuSettings:Sub("SkuCore", nil, "char").RangeChecks then
         if SkuSettings:Sub("SkuCore", nil, "char").RangeChecks[tCheckType][tRangeCheckLastTargetminRange] then
            local tSoundChannel = SkuOptions.db.profile.SkuCore.UIErrors.ErrorSoundChannel or "Talking Head"
            if SkuSettings:Sub("SkuCore", nil, "char").RangeChecks[tCheckType][tRangeCheckLastTargetminRange].sound == L["vocalized"] then
               --PlaySoundFile("Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\error\\marlene_de-de\\"..tRangeCheckLastTargetminRange..".mp3", tSoundChannel)
               if Sku.Loc == "deDE" then
                  PlaySoundFile("Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\error\\hans_de-de\\"..tRangeCheckLastTargetminRange..".mp3", tSoundChannel)
               elseif Sku.Loc == "enUS" or Sku.Loc == "enGB"  or Sku.Loc == "enAU" then
                  PlaySoundFile("Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\error\\hans_en-us\\"..tRangeCheckLastTargetminRange..".mp3", tSoundChannel)
               end
            else
               PlaySoundFile(SkuSettings:Sub("SkuCore", nil, "char").RangeChecks[tCheckType][tRangeCheckLastTargetminRange].sound, tSoundChannel)
            end
            
         end
      end
   end

   -- local meleeChecker = rc:GetFriendMaxChecker(rc.MeleeRange) or rc:GetFriendMinChecker(rc.MeleeRange) -- use the closest checker (MinChecker) if no valid Melee checker is found
   -- for i = 1, 4 do
   --     -- TODO: check if unit is valid, etc
   --     if meleeChecker("party" .. i) then
   --         print("Party member " .. i .. " is in Melee range")
   --     end
   -- end

   -- local safeDistanceChecker = rc:GetHarmMinChecker(30)
   -- -- negate the result of the checker!
   -- local isSafelyAway = not safeDistanceChecker('target')
end
