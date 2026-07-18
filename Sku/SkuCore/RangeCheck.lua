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
   return Sku.deEn("Reichweitenprüfung", "Range check")
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
   -- Diagnostic: /skurangeprobe dumps item-cache warm-up progress + the live
   -- checker lists (with sources) to SkuDebugLog, and speaks a one-line summary.
   -- Run it repeatedly after a cold start to watch the client cache the probe
   -- items. Enable the log first with `/skudebug log on`.
   if SkuOptions and SkuOptions.RegisterChatCommand then
      SkuOptions:RegisterChatCommand("skurangeprobe", function() RangeCheck:SkuRangeProbe() end)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function RangeCheck:CHECKERS_CHANGED()
   -- A genuine checker change may be a NEW band appearing -> allow the announce.
   RangeCheck:RangeCheckUpdateRanges(true)
end
---------------------------------------------------------------------------------------------------------------------------------------
function RangeCheck:RangeCheckOnEnable()
   -- Populate the availability snapshot from the CURRENT library state right now,
   -- instead of waiting for a CHECKERS_CHANGED that may already have fired before
   -- we registered our callback. On a /reload or a quiet login the library can
   -- reach its final checker set and never fire again, which previously left the
   -- "Entfernung" config menu permanently empty (snapshot never filled). Re-run
   -- on a few short delays too, to catch async item caching
   -- (GET_ITEM_INFO_RECEIVED) settling in over the first several seconds. All
   -- these passes are SILENT (no "Neue Reichweite" spam); only real
   -- CHECKERS_CHANGED events announce.
   RangeCheck:RangeCheckUpdateRanges(false)
   for _, tDelay in ipairs({1, 3, 6, 10}) do
      C_Timer.After(tDelay, function()
         if RangeCheck:IsEnabled() then
            RangeCheck:RangeCheckUpdateRanges(false)
         end
      end)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
local tDefBands = {5, 8, 10, 15, 20, 25, 30, 35, 40, 45, 60}
local function tMakeDefaultBands()
   local t = {}
   for _, d in ipairs(tDefBands) do
      t[d] = {["sound"] = L["vocalized"]}
   end
   return t
end

local tFirstRangeUpdateSilent = true
function RangeCheck:RangeCheckUpdateRanges(aAnnounce)
   -- NOTE: no more `frame:IsVisible()` deferral. That guard watched the LIBRARY's
   -- internal update frame (shown on every player UNIT_AURA and while items
   -- cache), so a checker change arriving while it was visible got deferred and
   -- the retry chain could keep missing -> menu stuck empty. Reading the current
   -- checker lists (GetFriend/Harm/MiscCheckers) is safe at any time, so we just
   -- populate synchronously.
   local tRC = SkuSettings:Sub("SkuCore", nil, "char")
   if not tRC then
      return
   end

   -- Seed defaults when the config is missing OR structurally empty. The old
   -- guard was `if not RangeChecks`, but a profile reset (SkuZOptions/Options.lua)
   -- leaves empty {} sub-tables, which is truthy -> the user then got NO defaults.
   -- `next()` treats that empty shell as "needs seeding".
   if not tRC.RangeChecks or not next(tRC.RangeChecks) then
      tRC.RangeChecks = {
         ["Misc"] = {
            [8] = {["sound"] = L["vocalized"]},
            [28] = {["sound"] = L["vocalized"]},
         },
         ["Friendly"] = tMakeDefaultBands(),
         ["Hostile"] = tMakeDefaultBands(),
      }
   end
   -- Guard against a partially-populated table (e.g. only one category present).
   tRC.RangeChecks.Friendly = tRC.RangeChecks.Friendly or {}
   tRC.RangeChecks.Hostile = tRC.RangeChecks.Hostile or {}
   tRC.RangeChecks.Misc = tRC.RangeChecks.Misc or {}

   -- Rebuild the AVAILABILITY snapshot from scratch for EVERY category. The old
   -- code only wiped Friendly before repopulating; Hostile/Misc were never reset,
   -- so they accumulated a monotonic session-union (a band seen available once
   -- stayed "available" forever). That asymmetry is why the (former) prune hit
   -- Friendly hard but almost never touched Hostile/Misc. This snapshot now
   -- reflects the present, and drives the config menu only (see Options.lua
   -- RangecheckMenuBuilder) -- nothing here reads it back to gate playback.
   local tRanges = RangeCheck.RangeCheckValues.Ranges
   tRanges.Friendly = {}
   tRanges.Hostile = {}
   tRanges.Misc = {}
   for i, v in SkuOptions.RangeCheck:GetFriendCheckers() do
      tRanges.Friendly[i] = v
   end
   for i, v in SkuOptions.RangeCheck:GetHarmCheckers() do
      tRanges.Hostile[i] = v
   end
   for i, v in SkuOptions.RangeCheck:GetMiscCheckers() do
      tRanges.Misc[i] = v
   end

   -- IMPORTANT: we deliberately DO NOT prune char.RangeChecks against the
   -- availability snapshot any more. LibRangeCheck bands go transiently
   -- unavailable all the time -- items are still caching for a few seconds after
   -- login (async GET_ITEM_INFO_RECEIVED), after a respec, or simply when a
   -- given item isn't carried. The old prune deleted the user's saved sound for
   -- such a band PERMANENTLY, and nothing ever re-added it, so ranges
   -- "deactivated themselves". DoRangeCheck already no-ops for a band while
   -- GetRange doesn't return its distance, so keeping stale config costs nothing.

   -- Auto-enable newly AVAILABLE bands the user has never configured, so
   -- leveling / gearing into a new range announces by default instead of coming
   -- back silent. An explicit mute is stored as an error_silent sound entry
   -- (RangeCheckSounds), i.e. it HAS a config entry, so it is NOT overwritten
   -- here -- only genuinely-absent (never-touched) bands get seeded.
   local function tSeedNewBands(aCategory)
      for i in pairs(tRanges[aCategory]) do
         if tRC.RangeChecks[aCategory][i] == nil then
            tRC.RangeChecks[aCategory][i] = {["sound"] = L["vocalized"]}
         end
      end
   end
   tSeedNewBands("Friendly")
   tSeedNewBands("Hostile")
   tSeedNewBands("Misc")

   -- Announce "new range available" ONLY for a genuine CHECKERS_CHANGED event
   -- (aAnnounce), and never on the very first pass of the session (that one is
   -- just the initial fill). The silent enable-time / menu-open / retry passes
   -- pass aAnnounce = false, so they never speak.
   if aAnnounce then
      if tFirstRangeUpdateSilent then
         tFirstRangeUpdateSilent = nil
      else
         SkuOptions.Voice:OutputString(L["Neue Reichweite verfügbar"], true, true, 0.2)
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

   -- WowVision-style guard (core/windows/range.lua): the interact-distance
   -- checkers (Duel = 8yd / Follow = 28yd) that back friendly & neutral range
   -- readings are BLOCKED by Blizzard in combat (InCombatLockdownRestriction in
   -- LibRangeCheck), so GetRange returns unreliable bands for non-attackable
   -- targets while in combat. Skip them rather than announce a wrong distance.
   -- Hostile targets are unaffected (harm bands are spell-based, valid in combat).
   if InCombatLockdown() and UnitExists("target") and not UnitCanAttack("player", "target") then
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

end

---------------------------------------------------------------------------------------------------------------------------------------
-- Diagnostic probe (/skurangeprobe). Writes a detailed snapshot to SkuDebugLog
-- (enable with `/skudebug log on`) and speaks a one-line summary. Purpose: after
-- a cold start, tell apart WHY the bands are sparse:
--   * item cache counts low + growing  -> the CLIENT is still fetching item data
--     from the server (the real wall: Anniversary keeps no on-disk item cache and
--     throttles item queries); pre-warm can only feed the queue, not beat the cap.
--   * item cache counts HIGH but checker lists sparse -> the LIBRARY hasn't
--     re-inited to pick the cached items up; the forced init(true) below fixes
--     that in-place and its before/after dump proves it.
function RangeCheck:SkuRangeProbe()
   local rc = SkuOptions and SkuOptions.RangeCheck
   if not rc then
      return
   end

   local p = rc.SkuProbeItemCache and rc:SkuProbeItemCache()
   if p then
      dprint("rangeProbe items cached: friend "..p.friendCached.."/"..p.friendTotal
         .." ("..p.friendRangesCached.."/"..p.friendRangesTotal.." ranges); harm "
         ..p.harmCached.."/"..p.harmTotal.." ("..p.harmRangesCached.."/"..p.harmRangesTotal.." ranges)")
   end

   local function tDumpList(aName, aList)
      if type(aList) ~= "table" then
         dprint("rangeProbe "..aName..": nil")
         return
      end
      local tParts = {}
      for i = 1, #aList do
         tParts[#tParts + 1] = tostring(aList[i].range).."="..tostring(aList[i].info)
      end
      dprint("rangeProbe "..aName.." ("..#aList.."): "..table.concat(tParts, ", "))
   end

   tDumpList("harmRC (before)", rc.harmRC)
   tDumpList("friendRC (before)", rc.friendRC)
   tDumpList("miscRC", rc.miscRC)

   -- Force the library to rebuild from currently-cached items, then re-dump. If
   -- the "after" lists are richer than "before", the client HAD cached items the
   -- library simply hadn't re-read -> we should trigger this on our retries.
   if rc.init then
      local ok = pcall(function() rc:init(true) end)
      dprint("rangeProbe forced init(true): "..(ok and "ok" or "ERROR"))
      tDumpList("harmRC (after init)", rc.harmRC)
      tDumpList("friendRC (after init)", rc.friendRC)
   end

   if p then
      SkuOptions.Voice:OutputString(
         Sku.deEn(
            "Reichweiten-Probe: Freund "..p.friendCached.." von "..p.friendTotal
               ..", Feind "..p.harmCached.." von "..p.harmTotal.." Items im Cache",
            "Range probe: friend "..p.friendCached.." of "..p.friendTotal
               ..", enemy "..p.harmCached.." of "..p.harmTotal.." items cached"),
         true, true, 0.2)
   end
end
