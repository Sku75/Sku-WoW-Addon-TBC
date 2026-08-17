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
   return Sku.deEn("Reichweitenprüfung", "Range check", "Vérification de portée")
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
      -- Log ONLY on the per-target-change force call; this function is also
      -- driven by an OnUpdate poll, which must not flood the ring.
      if aForceFlag == true then
         dprint("RangeCheck: silent - friendly range suppressed in combat (interact checkers combat-blocked)")
      end
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

      -- [v43.0] One line per forced (target-change) check: category, the band
      -- LibRangeCheck returned (nil = the library has NO checker for this unit
      -- right now - the lib/prune suspicion), and whether a sound is configured
      -- for that band. Makes "no range was announced" diagnosable from the ring.
      if aForceFlag == true then
         local tRCConf = SkuSettings:Sub("SkuCore", nil, "char").RangeChecks
         local tBand = tRCConf and tRCConf[tCheckType] and tRCConf[tCheckType][tRangeCheckLastTargetminRange]
         dprint("RangeCheck: force", tCheckType, "minRange", tostring(tRangeCheckLastTargetminRange), "bandConf", tBand and (tBand.sound or "?") or "none")
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
      if SkuOptions and SkuOptions.Voice then
         SkuOptions.Voice:OutputString(Sku.deEn("Reichweiten-Probe: keine Bibliothek", "Range probe: no library", "Sonde de portée : aucune bibliothèque"), true, true, 0.2)
      end
      return
   end

   -- Is the LIVE LibRangeCheck the copy WE patched? LibStub keeps only the
   -- highest MINOR_VERSION across all addons, and other addons (LootReserve
   -- ships minor 50, WeakAuras 34) can win the race over our embedded copy -> in
   -- that case our pre-warm + SkuProbeItemCache are NOT present on the running
   -- lib, so nothing we did to our file matters. This is the first thing to know.
   local tOurPatchLive = (rc.SkuProbeItemCache ~= nil)
   dprint("rangeProbe: our-patched-lib-live = "..tostring(tOurPatchLive))

   local p = tOurPatchLive and rc:SkuProbeItemCache() or nil
   if p then
      dprint("rangeProbe items cached: friend "..p.friendCached.."/"..p.friendTotal
         .." ("..p.friendRangesCached.."/"..p.friendRangesTotal.." ranges); harm "
         ..p.harmCached.."/"..p.harmTotal.." ("..p.harmRangesCached.."/"..p.harmRangesTotal.." ranges)")
      local function tJoin(t) return (type(t) == "table" and #t > 0) and table.concat(t, ",") or "-" end
      dprint("rangeProbe friend ranges  CACHED: "..tJoin(p.friendCachedRanges).."  |  MISSING: "..tJoin(p.friendUncachedRanges))
      dprint("rangeProbe harm   ranges  CACHED: "..tJoin(p.harmCachedRanges).."  |  MISSING: "..tJoin(p.harmUncachedRanges))
   end

   -- Directly probe specific high-range TBC item ids: is 60/80/100 reachable, and
   -- specifically do the range-100 elixirs resolve? If these stay uncached forever
   -- the item doesn't exist on this client (real ceiling); if they resolve on a
   -- later probe run, our burst was dropping them (need to batch/retry the pre-warm).
   local tCheck = {
      {32825, "Soul Cannon (harm 60)"},
      {35278, "Reinforced Net (80, WotLK)"},
      {41058, "Hyldnir Harpoon (100, WotLK)"},
      {23722, "Permanent R.O.I.D.S. (100)"},
      {23715, "Permanent Lung Juice (100)"},
      {23718, "Permanent Ground Scorpok (100)"},
   }
   for _, e in ipairs(tCheck) do
      local nm = C_Item and C_Item.GetItemInfo(e[1])
      dprint("rangeProbe item "..e[1].." "..e[2]..": "..(nm and ("CACHED ("..tostring(nm)..")") or "not cached"))
   end

   local function tDumpList(aName, aList)
      if type(aList) ~= "table" then
         dprint("rangeProbe "..aName..": nil")
         return 0
      end
      local tParts = {}
      for i = 1, #aList do
         tParts[#tParts + 1] = tostring(aList[i].range).."="..tostring(aList[i].info)
      end
      dprint("rangeProbe "..aName.." ("..#aList.."): "..table.concat(tParts, ", "))
      return #aList
   end

   local tNh = tDumpList("harmRC (before)", rc.harmRC)
   local tNf = tDumpList("friendRC (before)", rc.friendRC)
   tDumpList("miscRC", rc.miscRC)

   -- Force the LIVE library (whatever copy it is) to rebuild from currently-cached
   -- items via its public init(), then re-dump. Richer "after" than "before"
   -- means the client HAD cached items the lib just hadn't re-read.
   if type(rc.init) == "function" then
      local ok = pcall(function() rc:init(true) end)
      dprint("rangeProbe forced init(true): "..(ok and "ok" or "ERROR"))
      tNh = tDumpList("harmRC (after)", rc.harmRC) or tNh
      tNf = tDumpList("friendRC (after)", rc.friendRC) or tNf
   end

   -- Speak a summary that works regardless of which lib copy is live.
   local tMsg
   if p then
      tMsg = Sku.deEn("Freund "..p.friendCached.." von "..p.friendTotal..", Feind "..p.harmCached.." von "..p.harmTotal.." Items im Cache",
                      "friend "..p.friendCached.." of "..p.friendTotal..", enemy "..p.harmCached.." of "..p.harmTotal.." items cached")
   else
      tMsg = Sku.deEn("FREMDE Bibliothek aktiv, Feind "..tNh..", Freund "..tNf.." Baender",
                      "FOREIGN library active, enemy "..tNh..", friend "..tNf.." bands")
   end
   SkuOptions.Voice:OutputString(Sku.deEn("Reichweiten-Probe: ", "Range probe: ", "Sonde de portée : ")..tMsg, true, true, 0.2)
end
