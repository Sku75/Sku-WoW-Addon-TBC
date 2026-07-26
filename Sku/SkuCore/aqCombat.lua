---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME, MODULE_PART = "SkuCore", "aqCombat"
local L = Sku.L
local _G = _G

local sfind = string.find

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- W4 Phase D: aqCombat is a real AceAddon SUBMODULE of SkuCore, so the combat
-- monitor can be turned on/off at runtime (OnEnable/OnDisable), mirroring the
-- JunkAndRepair pilot. Every existing SkuCore:aqCombat* method and SkuCore.*
-- state stays EXACTLY where it is so external callers keep working unchanged
-- (TurnToUnit + SkuMob call aqCombat:aqCombatGetSkuRaidTarget; SkuZOptions reads
-- SkuCore.inOutCombatQueue); the module only owns the LIFECYCLE:
--   * OnEnable  arms the monitor (aqCombat:aqCombatOnInitialize registers the
--     SkuDispatcher event callbacks + 2 control OnUpdate frames + the
--     SetRaidTarget hooksecurefunc, then aqCombat:aqCombatOnLogin seeds the
--     settings defaults).
--   * OnDisable unregisters every dispatcher callback and stops both control
--     OnUpdate frames, so a disabled monitor genuinely does nothing.
-- The SetRaidTarget hooksecurefunc cannot be removed once installed, so its body
-- is IsEnabled-guarded instead.
-- AceAddon auto-enables the module at SkuCore enable (≈ PLAYER_LOGIN) and again
-- on every /reload, replacing the old explicit Core.lua aqCombatOnInitialize /
-- aqCombatOnLogin calls (so it re-arms on every load, not just initial login).
-- Registered AFTER aq in TOC order, so aqCombat enables after aq.
local aqCombat = SkuCore:NewModule(MODULE_PART)
SkuCore.aqCombat = aqCombat   -- keep the published handle
-- NOTE: the combat-monitor STATE table is SkuCore.aq.combat (set below), a
-- distinct field; SkuCore.aqCombat (no dot) was previously unused, so taking it
-- for the module handle clashes with nothing.

-- Make this feature user-toggleable (Features menu + persisted on/off). One line;
-- the framework (SkuCore/ModuleManager.lua) handles the rest.
SkuCore:RegisterToggleableModule(MODULE_PART, function()
   return Sku.deEn("Kampf-Monitor", "Combat monitor")
end)

local aqCombatVoices = {
   "emma",
   "brian",
}

local aqCombatAudioOutputs = {
   ["vocalized"] = "1 "..L["vocalized"],
}
--[[
for x = 12, 61, 4 do
   aqCombatAudioOutputs["sound-synth"..(string.format("%02d", x))] = L["Synth"].." "..(string.format("%02d", x))
   aqCombatAudioOutputs["sound-synth"..(string.format("%02d", x))..";vocalized"] = L["Synth"].." "..(string.format("%02d", x)).." "..L["plus"].." "..L["vocalized"]
end
]]

for x = 1, 20 do
   aqCombatAudioOutputs["sound-combat-notification"..(string.format("%02d", x))] = L["combat notification"].." "..(string.format("%02d", x))
   aqCombatAudioOutputs["sound-combat-notification"..(string.format("%02d", x))..";vocalized"] = L["combat notification"].." "..(string.format("%02d", x)).." "..L["plus"].." "..L["vocalized"]
end

SkuCore.RaidTargetValues = {
	[1] = {name = L["Star"], color = L["Yellow"]},
	[2] = {name = L["Circle"], color = L["Orange"]},
	[3] = {name = L["Diamond"], color = L["Purple"]},
	[4] = {name = L["Triangle"], color = L["Green"]},
	[5] = {name = L["Moon"], color = L["Grey"]},
	[6] = {name = L["Square"], color = L["Blue"]},
	[7] = {name = L["Cross"], color = L["Red"]},
	[8] = {name = L["Skull"], color = L["White"]},
}

SkuCore.SkuRaidTargetIndex = {
	[1] = 8,
	[2] = 7,
	[3] = 6,
	[4] = 4,
	[5] = 3,
	[6] = 1,
	[7] = 2,
	[8] = 5,
}

local tAllPartyRaidUnits = {
   "player",
   "pet",
}

local tUnitsToTestOnGameRaidTargets = {
   "player",
   "pet",
   "focus",
   "target",
   "pettarget",
   "focustarget",
   "playertargettarget",
   "pettargettarget",
   "focustargettarget",
   "targettarget",
}
for x = 1, 4 do
   table.insert(tAllPartyRaidUnits, "party"..x)
   table.insert(tAllPartyRaidUnits, "partypet"..x)
   
   table.insert(tUnitsToTestOnGameRaidTargets, "party"..x)
   table.insert(tUnitsToTestOnGameRaidTargets, "partypet"..x)
   table.insert(tUnitsToTestOnGameRaidTargets, "party"..x.."target")
   table.insert(tUnitsToTestOnGameRaidTargets, "partypet"..x.."target")
   table.insert(tUnitsToTestOnGameRaidTargets, "party"..x.."targettarget")
   table.insert(tUnitsToTestOnGameRaidTargets, "partypet"..x.."targettarget")
end
for x = 1, 25 do
   table.insert(tAllPartyRaidUnits, "raid"..x)
   table.insert(tAllPartyRaidUnits, "raidpet"..x)

   table.insert(tUnitsToTestOnGameRaidTargets, "raid"..x)
   table.insert(tUnitsToTestOnGameRaidTargets, "raidpet"..x)
   table.insert(tUnitsToTestOnGameRaidTargets, "raid"..x.."target")
   table.insert(tUnitsToTestOnGameRaidTargets, "raidpet"..x.."target")
   table.insert(tUnitsToTestOnGameRaidTargets, "raid"..x.."targettarget")
   table.insert(tUnitsToTestOnGameRaidTargets, "raidpet"..x.."targettarget")
end
for x = 1, 40 do
   table.insert(tUnitsToTestOnGameRaidTargets, "nameplate"..x)
end

SkuCore.SkuRaidTargetRepo = {} --[unitGUID] = SkuRaidTargetIndex,
SkuCore.SkuRaidTargetRepoDead = {} --[unitGUID] = SkuRaidTargetIndex,

SkuCore.aq.combat = {}
SkuCore.threatTable = {}
SkuCore.inOutCombatQueue = {
   current = 0,
   combatIn = {},
   combatOut = {},
}

SkuCore.partyDeadCountCounter = 0

local aqCombatIsPartyOrRaidMemberCache = {}

local tCurrentUpdateRate = 1

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCoreAqCombatGetVoiceString(aString, aTable)
   local tResult = (aString:gsub('($%b{})', function(w) 
      local tFinalString = aTable[w:sub(3, -2)] or w
      if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.numberOnly == true then
         if sfind(tFinalString, "raidpet") then
            tFinalString = string.gsub(tFinalString, "raidpet", "")
         elseif sfind(tFinalString, "raid") then
            tFinalString = string.gsub(tFinalString, "raid", "")
         elseif sfind(tFinalString, "partypet") then
            tFinalString = string.gsub(tFinalString, "partypet", "")
         elseif sfind(tFinalString, "party") then
            tFinalString = string.gsub(tFinalString, "party", "")
         end
      end

      if sfind(tFinalString, "nameplate") then
         tFinalString = "creature"
      end

      return tFinalString
   end))

   if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.notificationVolume == 1 then
      tResult = string.gsub(tResult, "sound%-combat%-notification%d%d;", "sound-combat-notification-low%d%d;")
   end

   if string.sub(tResult, 1, 5) == "-low;" then
      tResult = string.sub(tResult, 6)
   end

   return tResult
end
 
---------------------------------------------------------------------------------------------------------------------------------------
local function SkuCoreAqCombatOutput(aPattern, aValuesTable, aQueueSettings, aSkuSetting, aExtraSound)
   if aValuesTable.Unit1 then
      if sfind(aValuesTable.Unit1, "nameplate") then
         aValuesTable.Unit1 = "creature"
      end
   end
   if aValuesTable.Unit2 then
      if sfind(aValuesTable.Unit2, "nameplate") then
         aValuesTable.Unit2 = "creature"
      end
   end

   local tVoice = aqCombatVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.voice] or "brian"
   aValuesTable.voice = tVoice

   local tSound = ""
   if sfind(aExtraSound or aSkuSetting.sound, ";") then
      tSound = string.match(aExtraSound or aSkuSetting.sound, "(.+);(.+)")
   elseif sfind(aExtraSound or aSkuSetting.sound, "sound-") then
      aValuesTable = {
         voice = tVoice,
      }
      aPattern = "${sound}"
      tSound = aExtraSound or aSkuSetting.sound
   end
   aValuesTable.sound = tSound
   aPattern = string.gsub(aPattern, ";", ";${voice}-")

   if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.voiceVolume == 1 then
      aPattern = string.gsub(aPattern, ";", "-low;")
      aPattern = aPattern.."-low"
   end

   SkuOptions.Voice:OutputString(SkuCoreAqCombatGetVoiceString(aPattern, aValuesTable), {wait = aQueueSettings.wait, overwrite = aQueueSettings.overwrite, instant = aQueueSettings.instant, doNotOverwrite = aQueueSettings.doNotOverwrite,}) 
end

---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombatCreatureGuidToUnitId(aUnitGUID)
   for i = 1, #tUnitsToTestOnGameRaidTargets do
      local tCreatureGUID = UnitGUID(tUnitsToTestOnGameRaidTargets[i])
      if tCreatureGUID then
         if tCreatureGUID == aUnitGUID then
            return tUnitsToTestOnGameRaidTargets[i]
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombatGroupGuidToUnitId(aUnitGUID)
   if aqCombatIsPartyOrRaidMemberCache[aUnitGUID] then
      return aqCombatIsPartyOrRaidMemberCache[aUnitGUID]
   end

   for i = 1, #tAllPartyRaidUnits do
      local tTargetUnitIdToTest = tAllPartyRaidUnits[i]
      local tCreatureGUID = UnitGUID(tTargetUnitIdToTest)
      if tCreatureGUID then
         if tCreatureGUID == aUnitGUID then
            return tTargetUnitIdToTest
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombatGroupNameToUnitId(aName)
   for i = 1, #tAllPartyRaidUnits do
      local tTargetUnitIdToTest = tAllPartyRaidUnits[i]
      local tName = UnitName(tTargetUnitIdToTest)
      if tName then
         if tName == aName then
            return tTargetUnitIdToTest
         end
      end
   end
end


---------------------------------------------------------------------------------------------------------------------------------------
local tAqCombatGetUnitIndexFromUnitGUIDCache = {}
local function aqCombatGetUnitIndexFromUnitGUID(aUnitGUID)
   if aUnitGUID == nil then
      return
   end   

   if tAqCombatGetUnitIndexFromUnitGUIDCache[aUnitGUID] then
      return tAqCombatGetUnitIndexFromUnitGUIDCache[aUnitGUID]
   end

   local unit_type = strsplit("-", aUnitGUID)
   if unit_type == "Creature" or unit_type == "Vehicle" then
      local _, _, server_id, instance_id, zone_uid, npc_id, spawn_uid = strsplit("-", aUnitGUID)
      tAqCombatGetUnitIndexFromUnitGUIDCache[aUnitGUID] = npc_id
      return npc_id
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
local tUnitClassificationCache = {}
local tKeysRank
local function aqCombatCheckElite(aUnitGUID, aTargetUnitIdToTest)
   if aUnitGUID == nil and aTargetUnitIdToTest == nil then
      return
   end

   local beginTime6 = debugprofilestop() 

   if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.ignoreNonElite == true then   

      if aUnitGUID and tUnitClassificationCache[aUnitGUID] then
         return tUnitClassificationCache[aUnitGUID]
      end


      if aTargetUnitIdToTest == nil then
         local tUnitId = aqCombat:aqCombatCreatureGuidToUnitId(aUnitGUID)
         if tUnitId then
            aTargetUnitIdToTest = tUnitId
         end
      end

      if aTargetUnitIdToTest ~= nil  then
         aUnitGUID = UnitGUID(aTargetUnitIdToTest)
         local tUnitClassification = UnitClassification(aTargetUnitIdToTest)
         Sku.PerformanceData["aqCombatCheckElite"] = ((Sku.PerformanceData["aqCombatCheckElite"] or 0) + (debugprofilestop() - beginTime6)) / 2

         if aUnitGUID then
            if (tUnitClassification == "elite" or tUnitClassification == "rareelite" or tUnitClassification == "worldboss") then
               tUnitClassificationCache[aUnitGUID] = true
            else
               tUnitClassificationCache[aUnitGUID] = false
            end
            return tUnitClassificationCache[aUnitGUID]
         end
      end
         
      local index = aqCombatGetUnitIndexFromUnitGUID(aUnitGUID)
      if index then
         local tData = SkuDB.NpcData.Data[index]
         if tData then
            if tData[tKeysRank] then
               Sku.PerformanceData["aqCombatCheckElite1"] = ((Sku.PerformanceData["aqCombatCheckElite1"] or 0) + (debugprofilestop() - beginTime6)) / 2
               if 
                  tData[tKeysRank] ~= 1 and
                  tData[tKeysRank] ~= 2 and
                  tData[tKeysRank] ~= 3
               then
                  tUnitClassificationCache[aUnitGUID] = false
               else
                  tUnitClassificationCache[aUnitGUID] = true
               end
               return tUnitClassificationCache[aUnitGUID]
            end
         end
      end

      local tUnitId = aqCombat:aqCombatCreatureGuidToUnitId(aUnitGUID)
      if tUnitId then
         aUnitGUID = UnitGUID(aTargetUnitIdToTest)
         local t = UnitClassification(tUnitId)
         if aUnitGUID and t then
            Sku.PerformanceData["aqCombatCheckElite2"] = ((Sku.PerformanceData["aqCombatCheckElite2"] or 0) + (debugprofilestop() - beginTime6)) / 2
            if t ~= "worldboss" and t ~= "rareelite" and t ~= "elite" then
               tUnitClassificationCache[aUnitGUID] = false
            else
               tUnitClassificationCache[aUnitGUID] = true
            end
            return tUnitClassificationCache[aUnitGUID]
         end
      end
   else
      Sku.PerformanceData["aqCombatCheckElite3"] = ((Sku.PerformanceData["aqCombatCheckElite3"] or 0) + (debugprofilestop() - beginTime6)) / 2
      return true
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombatIsPartyOrRaidMember(aUnitId, aUnitGUID)
   local beginTime2 = debugprofilestop()   

   if aUnitId then
      local aUnitIdGuid = UnitGUID(aUnitId)

      if not aUnitIdGuid then
         return
      end
      
      if aqCombatIsPartyOrRaidMemberCache[aUnitIdGuid] then
         return aqCombatIsPartyOrRaidMemberCache[aUnitIdGuid]
      end
      
      if UnitGUID("player") == aUnitIdGuid then
         aqCombatIsPartyOrRaidMemberCache[aUnitIdGuid] = "player"
         Sku.PerformanceData["aqCombatIsPartyOrRaidMember"] = ((Sku.PerformanceData["aqCombatIsPartyOrRaidMember"] or 0) + (debugprofilestop() - beginTime2)) / 2                              
         return "player"
      end
      if UnitGUID("pet") == aUnitIdGuid then
         aqCombatIsPartyOrRaidMemberCache[aUnitIdGuid] = "pet"
         Sku.PerformanceData["aqCombatIsPartyOrRaidMember"] = ((Sku.PerformanceData["aqCombatIsPartyOrRaidMember"] or 0) + (debugprofilestop() - beginTime2)) / 2                              
         return "pet"
      end
      for x = 1, 4 do
         if UnitGUID("party"..x) == aUnitIdGuid then
            aqCombatIsPartyOrRaidMemberCache[aUnitIdGuid] = "party"..x
            Sku.PerformanceData["aqCombatIsPartyOrRaidMember"] = ((Sku.PerformanceData["aqCombatIsPartyOrRaidMember"] or 0) + (debugprofilestop() - beginTime2)) / 2                              
            return "party"..x
         end
         if UnitGUID("partypet"..x) == aUnitIdGuid then
            aqCombatIsPartyOrRaidMemberCache[aUnitIdGuid] = "partypet"..x
            Sku.PerformanceData["aqCombatIsPartyOrRaidMember"] = ((Sku.PerformanceData["aqCombatIsPartyOrRaidMember"] or 0) + (debugprofilestop() - beginTime2)) / 2                              
            return "partypet"..x
         end
      end
      for x = 1, 40 do
         if UnitGUID("raid"..x) == aUnitIdGuid then
            aqCombatIsPartyOrRaidMemberCache[aUnitIdGuid] = "raid"..x
            Sku.PerformanceData["aqCombatIsPartyOrRaidMember"] = ((Sku.PerformanceData["aqCombatIsPartyOrRaidMember"] or 0) + (debugprofilestop() - beginTime2)) / 2                              
            return "raid"..x
         end
         if UnitGUID("raidpet"..x) == aUnitIdGuid then
            aqCombatIsPartyOrRaidMemberCache[aUnitIdGuid] = "raidpet"..x
            Sku.PerformanceData["aqCombatIsPartyOrRaidMember"] = ((Sku.PerformanceData["aqCombatIsPartyOrRaidMember"] or 0) + (debugprofilestop() - beginTime2)) / 2                              
            return "raidpet"..x
         end
      end

      if UnitIsEnemy("player", aUnitId) ~= true then
         Sku.PerformanceData["aqCombatIsPartyOrRaidMember"] = ((Sku.PerformanceData["aqCombatIsPartyOrRaidMember"] or 0) + (debugprofilestop() - beginTime2)) / 2                              
         return
      end
      

      return --"unknown"
   elseif aUnitGUID then
      for q = 1, #tAllPartyRaidUnits do
         local tPartyUnitToTest = tAllPartyRaidUnits[q]
         local tPartyGuid = UnitGUID(tPartyUnitToTest)
         if tPartyGuid == aUnitGUID then
            aqCombatIsPartyOrRaidMemberCache[aUnitGUID] = tPartyUnitToTest
            Sku.PerformanceData["aqCombatIsPartyOrRaidMember2"] = ((Sku.PerformanceData["aqCombatIsPartyOrRaidMember2"] or 0) + (debugprofilestop() - beginTime2)) / 2                     
            return tPartyUnitToTest
         end
      end
   end

   Sku.PerformanceData["aqCombatIsPartyOrRaidMember3"] = ((Sku.PerformanceData["aqCombatIsPartyOrRaidMember3"] or 0) + (debugprofilestop() - beginTime2)) / 2                              
end

---------------------------------------------------------------------------------------------------------------------------------------
local tthreatWarningNotFirstHigherThanLastWarning = 0
local tthreatWarningIsFirstSecondHigherThanLastWarning = 0
local tOorIntervalTime = -2
-- Last value the relative-enemies-in-combat feature spoke. The counter recounts
-- the live enemy set every tick and announces only when this changes; kept as a
-- file upvalue (NOT reset in PLAYER_REGEN_ENABLED) so the final "0" after combat
-- is still announced once threatTable is cleared.
local tRelativeLastAnnounced = 0

-- Crowd-control tracking (INVESTIGATION / diagnostic instrumentation, 2026-07-18).
-- Goal: know when a tracked enemy is under a CC that pulls it OUT of active combat
-- (polymorph/banish/sap/shackle/hibernate/trap/repentance/sleep/blind), because
-- such a mob goes quiet, gets dropped by the 6s stale-sweep, then re-added when the
-- CC breaks -- the "counts down and up again on sheeped/banished targets" the user
-- reported. Keyed by spellId, so it is LOCALE-PROOF (this is a German client) and
-- INDEPENDENT of the recent retail-nameplate change: it reads only the combat log,
-- never a nameplate or aura unit-token. tCcState lives decoupled from the
-- threatTable lifecycle (a CC applied a moment before the coalesced add-flush
-- creates the entry would otherwise be lost) and is fed in the combat-log handler,
-- consulted by the recount detail log, cleared on aura-remove / death / combat end.
-- Declared HERE (above the recount closure at aqCombatCreateQueueControlFrame) so
-- every reader binds it as an upvalue. NOT yet wired to announcements -- that
-- follows once a live capture confirms detection. Extend tCcSpells after the
-- in-game aura probe (see the CC investigation notes).
local tCcAuraEvents = {
   SPELL_AURA_APPLIED = true, SPELL_AURA_REFRESH = true,
   SPELL_AURA_REMOVED = true, SPELL_AURA_BROKEN = true, SPELL_AURA_BROKEN_SPELL = true,
}
local tCcSpells = {
   -- Polymorph (sheep) + TBC variants
   [118] = "sheep", [12824] = "sheep", [12825] = "sheep", [12826] = "sheep",
   [28271] = "sheep", [28272] = "sheep",
   -- Banish
   [710] = "banish", [18647] = "banish",
   -- Sap
   [6770] = "sap", [2070] = "sap", [11297] = "sap",
   -- Shackle Undead
   [9484] = "shackle", [9485] = "shackle", [10955] = "shackle",
   -- Hibernate
   [2637] = "hibernate", [18657] = "hibernate", [18658] = "hibernate",
   -- Freezing Trap effect
   [3355] = "trap", [14308] = "trap", [14309] = "trap",
   -- Repentance
   [20066] = "repentance",
   -- Wyvern Sting (sleep)
   [19386] = "sleep", [24132] = "sleep", [24133] = "sleep", [27068] = "sleep",
   -- Blind
   [2094] = "blind",
}
local tCcState = {}              -- [creatureGUID] = {key = "sheep", t = <precise sec>}

---------------------------------------------------------------------------------------------------------------------------------------
-- Coalesced combat-log add path (state). Declared HERE, above every function that
-- touches it (the death handler must be able to drop a pending add, and
-- aqCombat_CREATURE_ADDED_TO_COMBAT sits earlier in the file than the flush), so
-- all of them bind the same upvalues. The flush itself is further down.
local tPendingAdds = {}          -- [creatureGUID] = {name=, partyGuid=, partyName=, friendly=}
local tPendingAddScheduled = false

-- Enemies that DIED during the current fight. threatTable marks both a death and
-- a stale-sweep drop with the same value (false), but the two must behave
-- differently on re-add: a stale-swept mob is alive and quiet, so it may come
-- back; a dead one may not. Without this set a combat-log event recorded in the
-- 0.3s window around the killing blow flushes AFTER the death and revives the
-- corpse -- the "0, then 1, then 0 again" flicker. Cleared when the group's fight
-- ends, and lifted per-GUID if the mob is later seen alive on a unit token (the
-- rare in-fight resurrect), so this can never permanently hide a live enemy.
local tDeadGuids = {}            -- [creatureGUID] = true (died this fight)

-- Enemies with positive evidence of hostility, so the check below is asked ONCE
-- per mob and never re-evaluated. Encounters routinely flag a boss or add as
-- immune / non-attackable mid-fight while it is still very much part of the
-- fight; anything derived from "can I attack it right now" (UnitCanAttack) would
-- drop it from the count exactly then. Reaction does not change under immunity,
-- and once a mob is admitted as hostile it stays admitted.
local tKnownHostile = {}         -- [creatureGUID] = true

local tReactionFriendlyFlag = COMBATLOG_OBJECT_REACTION_FRIENDLY or 0x00000010
local tReactionNeutralFlag = COMBATLOG_OBJECT_REACTION_NEUTRAL or 0x00000020
local tReactionHostileFlag = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040
local tBand = bit and bit.band

-- Hostility from the combat-log unit flags of the event that mentioned the mob.
-- Returns true (hostile or neutral -> counts), false (friendly -> does not), or
-- nil (unknown -> caller stays permissive: over-counting once beats losing a boss
-- from the count). Works without any unit token, so it also covers mobs that have
-- no nameplate and are targeted by nobody.
local function tFlagsSayHostile(aFlags)
   if not aFlags or not tBand then return nil end
   if tBand(aFlags, tReactionHostileFlag) ~= 0 then return true end
   if tBand(aFlags, tReactionNeutralFlag) ~= 0 then return true end
   if tBand(aFlags, tReactionFriendlyFlag) ~= 0 then return false end
   return nil
end

-- Same question for a resolvable unit token. UnitReaction is 1..4 for
-- hated/hostile/unfriendly/neutral and 5+ for friendly and better; it is NOT
-- affected by immunity or by the non-attackable flag, which is exactly why it is
-- used here instead of UnitCanAttack. nil (unknown) again means "stay permissive".
local function tUnitSaysHostile(aUnitId)
   if not aUnitId then return nil end
   local tReaction = UnitReaction("player", aUnitId)
   if not tReaction then return nil end
   return tReaction <= 4
end

-- Final admission verdict for a creature: known-hostile wins, then the live
-- token, then the combat-log flags, and unknown counts as hostile.
local function tShouldAdmitAsEnemy(aCreatureGUID, aUnitId, aFlagVerdict)
   if tKnownHostile[aCreatureGUID] then return true end
   local tVerdict = tUnitSaysHostile(aUnitId)
   if tVerdict == nil then tVerdict = aFlagVerdict end
   if tVerdict == false then return false end
   -- Remember only a DEFINITE yes. An unknown verdict still admits (permissive),
   -- but stays open to a clear friendly answer from a later, better-informed event.
   if tVerdict == true then
      tKnownHostile[aCreatureGUID] = true
   end
   return true
end

local function tCombatInCounts(value, creatureGUID, tPlayerGUID, tAllPartyRaidUnits)
   -- [W6-C #20] shared "does this in-combat creature count?" classifier, extracted
   -- from the two identical value==4/3/2 cascades (relativeNumberUnitsInCombat and
   -- unitsAddedToCombat branches). Each caller keeps its own counter increment.
   if value == 4 then
      local tt = SkuCore.threatTable[creatureGUID]
      if tt and tt[tPlayerGUID] and tt[tPlayerGUID].status and tt[tPlayerGUID].isTanking == true then
         return true
      end
   elseif value == 3 then
      local tt = SkuCore.threatTable[creatureGUID]
      if tt then
         -- Eager path: the combat log already recorded a party/raid member
         -- engaging this mob (combatIn attacker, stored when it was added). For
         -- "enemies attacking party or you" that alone is sufficient, so count
         -- it immediately WITHOUT waiting for the threat API (.status) to
         -- populate -- in a busy raid that threat data lags the pull by seconds.
         -- This restores the historical behaviour of starting the count as soon
         -- as anyone in the group is fighting, independent of the player's own
         -- combat state. (Dead/left mobs are already excluded before this by the
         -- recount's live-entry check, so eagerness cannot re-inflate the count.)
         if aqCombat:aqCombatIsPartyOrRaidMember(SkuCore.inOutCombatQueue.combatIn[creatureGUID]) then
            return true
         end
         -- Threat path: a party/raid member holds actual aggro. Covers mobs the
         -- periodic threat scan surfaced where no combatIn attacker was recorded.
         for q = 1, #tAllPartyRaidUnits do
            local tPartyGuid = UnitGUID(tAllPartyRaidUnits[q])
            local tEntry = tt[tPartyGuid]
            if tEntry and tEntry.status and tEntry.isTanking == true then
               return true
            end
         end
      end
   elseif value == 2 then
      return true
   end
   return false
end

local function aqCombatCreateControlFrame()
   local f = _G["SkuCoreaqCombatControl"] or CreateFrame("Frame", "SkuCoreaqCombatControl", UIParent)
   local ttime = 0
   f:SetScript("OnUpdate", function(self, time)
      ttime = ttime + time
      if ttime < (0.1 * tCurrentUpdateRate) then
         return
      end

      local tCurrentSettings = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet]
      tCurrentUpdateRate = (21 - tCurrentSettings.combat.updateRate)

      if tCurrentSettings.combat.friendly.outOfRangeEnabled.value == true and tCurrentSettings.combat.enabled == true then
         local beginTime1 = debugprofilestop()

         if tCurrentSettings.combat.friendly.oorUnitName ~= L["Nothing selected"] then
            local tUniId = aqCombat:aqCombatGroupNameToUnitId(tCurrentSettings.combat.friendly.oorUnitName)
            if tUniId then
               local _, tMinRange = SkuOptions.RangeCheck:GetRange(tUniId)
               if tMinRange and tMinRange > tCurrentSettings.combat.friendly.oorAt then
                  local tDoOutput = false
                  if tCurrentSettings.combat.friendly.oorInterval == 0 then
                     if tOorIntervalTime ~= -1 then
                        tDoOutput = true
                        tOorIntervalTime = -1
                     end
                  else
                     if tOorIntervalTime < 0 then
                        tDoOutput = true
                        tOorIntervalTime = GetTimePreciseSec() 
                     else
                        if GetTimePreciseSec() - tOorIntervalTime > tCurrentSettings.combat.friendly.oorInterval then
                           tDoOutput = true
                           tOorIntervalTime = GetTimePreciseSec() 
                        end
                     end
                  end
                  if tDoOutput == true then
                     local tSetting = tCurrentSettings.combat.friendly.outOfRangeEnabled
                     SkuCoreAqCombatOutput(tSetting.voiceOutput, {unit1 = tUniId,}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
                  end
               else
                  tOorIntervalTime = -2
               end
            end
         end
         Sku.PerformanceData["combat.friendly.outOfRangeEnabled"] = ((Sku.PerformanceData["combat.friendly.outOfRangeEnabled"] or 0) + (debugprofilestop() - beginTime1)) / 2

      end
            
      --clearnup lost guids from SkuCore.SkuRaidTargetRepo?

      if tCurrentSettings.combat.enabled == true then
         local beginTime2 = debugprofilestop()

         for i = 1, #tUnitsToTestOnGameRaidTargets do
            local tTargetUnitIdToTest = tUnitsToTestOnGameRaidTargets[i]
            local tCreatureGUID = UnitGUID(tTargetUnitIdToTest)
            if tCreatureGUID then
               -- LIVENESS: a tracked mob that is visible in one of the polled unit
               -- slots (nameplate, someone's target, ...) AND still carries the
               -- in-combat flag is demonstrably still in the fight, whether or not
               -- it produced a combat-log line or a threat reading this second.
               -- Previously lastUpdate was only refreshed deep inside the "has a
               -- threat status" branch below, so a boss that stood there doing
               -- nothing for six seconds -- during a fear, a cast phase, a CC --
               -- was stale-swept out of the count and re-added on its next swing.
               -- The UnitAffectingCombat condition is what keeps the sweep's real
               -- job intact: an evading / leashing mob is still visible for a while
               -- but drops out of combat, so it is NOT refreshed and the 6s sweep
               -- removes it exactly as before.
               local tTracked = SkuCore.threatTable[tCreatureGUID]
               if type(tTracked) == "table"
                  and UnitIsDeadOrGhost(tTargetUnitIdToTest) ~= true
                  and UnitAffectingCombat(tTargetUnitIdToTest)
               then
                  tTracked.lastUpdate = GetTimePreciseSec()
               end
               if aqCombatCheckElite(tCreatureGUID, tTargetUnitIdToTest) == true then
                  if tCreatureGUID and SkuCore.threatTable[tCreatureGUID] ~= false and not tDeadGuids[tCreatureGUID] then
                     local t = aqCombat:aqCombatIsPartyOrRaidMember(tTargetUnitIdToTest)
                     if t == nil then
                        -- is mob
                        for q = 1, #tAllPartyRaidUnits do
                           local tPartyUnitToTest = tAllPartyRaidUnits[q]
                           local isTanking, status, scaledPercentage, rawPercentage, threatValue = UnitDetailedThreatSituation(tPartyUnitToTest, tTargetUnitIdToTest)
                           if status then
                              local tPartyGuid = UnitGUID(tPartyUnitToTest)
                              -- Hostility is asked at the admission point only, so
                              -- the verdict (and the tKnownHostile bookkeeping) is
                              -- not paid for every unit slot polled every tick.
                              if UnitIsDeadOrGhost(tPartyUnitToTest) ~= true
                                 and tShouldAdmitAsEnemy(tCreatureGUID, tTargetUnitIdToTest, nil) then
                                 aqCombat:aqCombat_CREATURE_ADDED_TO_COMBAT(tCreatureGUID, tTargetUnitIdToTest, UnitName(tTargetUnitIdToTest), UnitGUID(tPartyUnitToTest), tPartyUnitToTest, UnitName(tPartyUnitToTest))

                                 local tPlayerGUID = UnitGUID("player")
                                 if tCreatureGUID == UnitGUID("target") and tPartyGuid == tPlayerGUID then
                                    if SkuCore.threatTable[tCreatureGUID] then
                                       if SkuCore.threatTable[tCreatureGUID][tPartyGuid] then
                                          if SkuCore.threatTable[tCreatureGUID][tPartyGuid].isTanking == true and SkuCore.threatTable[tCreatureGUID][tPartyGuid].wasTanking ~= true then
                                             if tCurrentSettings.combat.hostile.warnIfTargetSwitchingToYou.value == true then
                                                local tSetting = tCurrentSettings.combat.hostile.warnIfTargetSwitchingToYou
                                                SkuCoreAqCombatOutput(tSetting.voiceOutput, {}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
                                             end
                                             SkuCore.threatTable[tCreatureGUID][tPartyGuid].wasTanking = true
                                          elseif SkuCore.threatTable[tCreatureGUID][tPartyGuid].isTanking ~= true and SkuCore.threatTable[tCreatureGUID][tPartyGuid].wasTanking == true then
                                             if tCurrentSettings.combat.hostile.warnIfTargetSwitchingToParty.value == true then
                                                local tSetting = tCurrentSettings.combat.hostile.warnIfTargetSwitchingToParty
                                                SkuCoreAqCombatOutput(tSetting.voiceOutput, {}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
                                             end
                                             SkuCore.threatTable[tCreatureGUID][tPartyGuid].wasTanking = false                                      
                                          end
                                       end
                                    end
                                 end

                                 -- The add above can legitimately refuse (mob died
                                 -- this fight), leaving a `false` entry -- so never
                                 -- index it blind.
                                 if type(SkuCore.threatTable[tCreatureGUID]) == "table" then
                                 SkuCore.threatTable[tCreatureGUID].name = UnitName(tTargetUnitIdToTest)
                                 SkuCore.threatTable[tCreatureGUID].lastUpdate = GetTimePreciseSec()
                                 SkuCore.threatTable[tCreatureGUID][tPartyGuid] = SkuCore.threatTable[tCreatureGUID][tPartyGuid] or {}
                                 SkuCore.threatTable[tCreatureGUID][tPartyGuid].lastUpdate = GetTimePreciseSec()
                                 SkuCore.threatTable[tCreatureGUID][tPartyGuid].isTanking = isTanking
                                 SkuCore.threatTable[tCreatureGUID][tPartyGuid].status = status
                                 SkuCore.threatTable[tCreatureGUID][tPartyGuid].scaledPercentage = scaledPercentage
                                 SkuCore.threatTable[tCreatureGUID][tPartyGuid].rawPercentage = rawPercentage
                                 SkuCore.threatTable[tCreatureGUID][tPartyGuid].threatValue = threatValue
                                 end
                              end
                           end
                        end
                     end
                  end
               end
            end
         end
         Sku.PerformanceData["combat num in c"] = ((Sku.PerformanceData["combat num in c"] or 0) + (debugprofilestop() - beginTime2)) / 2         

      end

      if SkuCore.aqCombatCheckThreat then
         if tCurrentSettings.combat.enabled == true then
            local beginTime3 = debugprofilestop()

            local tPlayerGUID = UnitGUID("player")
            local tTargetGUID = UnitGUID("target")

            if tTargetGUID then
               if aqCombatCheckElite(tTargetGUID, "target") == true then               
                  if SkuCore.threatTable[tTargetGUID] then
                     if SkuCore.threatTable[tTargetGUID][tPlayerGUID] and SkuCore.threatTable[tTargetGUID][tPlayerGUID].isTanking ~= nil then
                        --Threat warning if you are first place (tanking) and second place threat percentage is higher than
                        if SkuCore.threatTable[tTargetGUID][tPlayerGUID].scaledPercentage >= 100 then
                           tthreatWarningNotFirstHigherThanLastWarning = 0
                           if tCurrentSettings.combat.hostile.threatWarningIsFirstSecondHigherThan.value > 0 then
                              local tWarnUnitId, tWarnPercent = nil, 0
                              for i, v in pairs(SkuCore.threatTable[tTargetGUID]) do
                                 if type(v) == "table" then
                                    if i ~= tPlayerGUID then
                                       if v.scaledPercentage then
                                          if v.scaledPercentage > tCurrentSettings.combat.hostile.threatWarningIsFirstSecondHigherThan.value then
                                             if v.scaledPercentage < 110 then
                                                if tWarnPercent < v.scaledPercentage then
                                                   tWarnUnitId = i
                                                   tWarnPercent = v.scaledPercentage
                                                end
                                             end
                                          end
                                       end
                                    end
                                 end
                              end
                              
                              if tWarnUnitId then
                                 if tCurrentSettings.combat.hostile.threatWarningInterval > 0 then
                                    if tthreatWarningIsFirstSecondHigherThanLastWarning == -1 or GetTimePreciseSec() - tthreatWarningIsFirstSecondHigherThanLastWarning > tCurrentSettings.combat.hostile.threatWarningInterval then
                                       tthreatWarningIsFirstSecondHigherThanLastWarning = GetTimePreciseSec() 
                                       local tSetting = tCurrentSettings.combat.hostile.threatWarningIsFirstSecondHigherThan
                                       SkuCoreAqCombatOutput(tSetting.voiceOutput, {unit1 = tAllPartyRaidUnits[x],}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
                                    end
                                 else
                                    if tthreatWarningIsFirstSecondHigherThanLastWarning > -1  then
                                       local tSetting = tCurrentSettings.combat.hostile.threatWarningIsFirstSecondHigherThan
                                       SkuCoreAqCombatOutput(tSetting.voiceOutput, {unit1 = tAllPartyRaidUnits[x],}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
                                       tthreatWarningIsFirstSecondHigherThanLastWarning = -1
                                    end
                                 end
                              else
                                 tthreatWarningIsFirstSecondHigherThanLastWarning = 0
                              end
                           end

                        --Threat warning if you are not first place (not tanking) and your threat percentage is higher than
                        --elseif SkuCore.threatTable[tTargetGUID][tPlayerGUID].isTanking == false then
                        else
                           tthreatWarningIsFirstSecondHigherThanLastWarning = 0
                           if tCurrentSettings.combat.hostile.threatWarningNotFirstHigherThan.value > 0  then
                              if SkuCore.threatTable[tTargetGUID][tPlayerGUID].scaledPercentage > tCurrentSettings.combat.hostile.threatWarningNotFirstHigherThan.value then
                                 if tCurrentSettings.combat.hostile.threatWarningInterval > 0 then
                                    if tthreatWarningNotFirstHigherThanLastWarning == -1 or GetTimePreciseSec() - tthreatWarningNotFirstHigherThanLastWarning > tCurrentSettings.combat.hostile.threatWarningInterval then
                                       tthreatWarningNotFirstHigherThanLastWarning = GetTimePreciseSec() 
                                       local tSetting = tCurrentSettings.combat.hostile.threatWarningNotFirstHigherThan
                                       SkuCoreAqCombatOutput(tSetting.voiceOutput, {unit1 = tAllPartyRaidUnits[x],}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
                                    end
                                 else
                                    if tthreatWarningNotFirstHigherThanLastWarning > -1  then
                                       local tSetting = tCurrentSettings.combat.hostile.threatWarningNotFirstHigherThan
                                       SkuCoreAqCombatOutput(tSetting.voiceOutput, {unit1 = tAllPartyRaidUnits[x],}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
                                       tthreatWarningNotFirstHigherThanLastWarning = -1
                                    end
                                 end
                              else
                                 tthreatWarningNotFirstHigherThanLastWarning = 0
                              end
                           end
                        end
                     end
                  end
               end
            end
            Sku.PerformanceData["combat threat 2"] = ((Sku.PerformanceData["combat threat 2"] or 0) + (debugprofilestop() - beginTime3)) / 2                     

         end

         --[[
         for q = 1, #tAllPartyRaidUnits do
            local tPartyUnitToTest = tAllPartyRaidUnits[q]
            local tPartyGuid = UnitGUID(tPartyUnitToTest)
            if tPartyGuid then
               --print(tPartyUnitToTest)
               for tCreatureGUID, tvalue in pairs(SkuCore.threatTable) do
                  if tvalue ~= false and tvalue[tPartyGuid] then
                     --print("  ", tvalue.name, tvalue[tPartyGuid].status, tvalue[tPartyGuid].scaledPercentage)
                  end
               end
            end
         end
         ]]
      end

      ttime = 0
   end)

   ---
   local f = _G["SkuCoreaqCombatQueueControl"] or CreateFrame("Frame", "SkuCoreaqCombatQueueControl", UIParent)
   local ttime1 = 0
   local ttime2 = 0
   -- Stale-sweep threshold (seconds). When a creature's threatTable entry has
   -- not been touched for this long and it is not already marked dead (false),
   -- we assume it silently left combat (evade / leash / despawn / out-of-range
   -- without a UNIT_DIED event) and push it into combatOut so the counter
   -- decrements properly. Previously those mobs lingered forever in the
   -- threat table and the counter only fell to 0 via the hard reset in
   -- PLAYER_REGEN_ENABLED — which made the user "lose" the final countdown
   -- especially in group play, where mobs frequently evade after a wipe,
   -- leash after a pull-break, or die off-screen without a combat-log entry
   -- that maps to a tracked GUID.
   local tStaleThreshold = 6.0

   local function tStaleSweep()
      if not SkuCore.threatTable then return end
      local tNow = GetTimePreciseSec()
      for tGuid, tEntry in pairs(SkuCore.threatTable) do
         if tEntry and tEntry ~= false and type(tEntry) == "table" then
            local tLast = tEntry.lastUpdate
            if tLast and (tNow - tLast) > tStaleThreshold then
               -- Diagnostic: a mob dropped for going quiet (no combat-log/threat
               -- refresh for tStaleThreshold s). This is the event that would
               -- wrongly lower the count if a boss/add merely changed appearance
               -- or briefly lost its nameplate while still alive. If one shows up
               -- right before a count drop on such a boss, the sweep is the cause.
               dprint("aqCombat stale-sweep drop:", (tEntry.name or "?").."#"..tGuid:sub(-6), "idle", string.format("%.1f", tNow - tLast).."s",
                  "onUnitSlot", aqCombat:aqCombatCreatureGuidToUnitId(tGuid) or "no")
               -- Already queued for removal? Skip to avoid double-decrement.
               if not SkuCore.inOutCombatQueue.combatOut[tGuid] then
                  SkuCore.inOutCombatQueue.combatOut[tGuid] = true
               end
               SkuCore.threatTable[tGuid] = false
            end
         end
      end
   end

   f:SetScript("OnUpdate", function(self, time)
      local tCurrentSettings = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet]

      if tCurrentSettings.combat.enabled == true then
         local beginTime = debugprofilestop()
         if tCurrentSettings.combat.hostile.relativeNumberUnitsInCombat.value > 1 then
            ttime2 = ttime2 + time
            if ttime2 > (0.1 * tCurrentUpdateRate) then
               tCurrentUpdateRate = (21 - tCurrentSettings.combat.updateRate)

               -- Sweep entries that silently left combat (evade/leash/despawn
               -- without a death event) so they drop out of the recount below.
               tStaleSweep()

               -- Authoritative RECOUNT instead of a running plus/minus delta.
               -- threatTable holds one entry per discovered enemy (found via the
               -- unchanged nameplate + group-target scan): a table while it is
               -- alive/in combat, false once it dies (SKU_UNIT_DIED) or is
               -- stale-swept. Counting the live entries that pass the current
               -- mode filter every tick makes the number self-healing -- a missed
               -- add or a double-remove can no longer drift it. The old delta
               -- underflowed to a false "0" because deaths decremented
               -- unconditionally while adds were mode-gated (tCombatInCounts);
               -- applying the SAME filter to every candidate here removes that
               -- asymmetry, so modes 3/4 can no longer collapse to 0 while
               -- enemies remain.
               local tPlayerGUID = UnitGUID("player")
               local tCount = 0
               for creatureGUID, tEntry in pairs(SkuCore.threatTable) do
                  if type(tEntry) == "table" then
                     if aqCombatCheckElite(creatureGUID) == true then
                        if tCombatInCounts(tCurrentSettings.combat.hostile.relativeNumberUnitsInCombat.value, creatureGUID, tPlayerGUID, tAllPartyRaidUnits) then
                           tCount = tCount + 1
                        end
                     end
                  end
               end

               -- Keep the published field in sync for external readers.
               SkuCore.inOutCombatQueue.current = tCount

               if tCount ~= tRelativeLastAnnounced then
                  local tMode = tCurrentSettings.combat.hostile.relativeNumberUnitsInCombat.value
                  dprint("aqCombat enemies-in-combat recount:", tCount, "prev", tRelativeLastAnnounced, "mode", tMode)
                  -- Per-mob breakdown at the exact tick the number changes: WHY each
                  -- live entry is/isn't counted (c=Y/N), whether it passed the elite
                  -- gate, how long since it was last touched (idle -> stale-sweep
                  -- candidate at 6s) and any crowd-control state. A count DROP on a
                  -- still-alive mob showing "cc=sheep" or a large idle is the
                  -- CC/stale-sweep down-then-up behaviour, not a real combat leave.
                  if Sku.debug and (Sku.debug.log or Sku.debug.print) then
                     local tNow2 = GetTimePreciseSec()
                     local tParts, tShown, tCcCount = {}, 0, 0
                     for tGuid, tEntry in pairs(SkuCore.threatTable) do
                        if type(tEntry) == "table" then
                           local tCc = tCcState[tGuid] and tCcState[tGuid].key
                           if tCc then tCcCount = tCcCount + 1 end
                           if tShown < 15 then
                              tShown = tShown + 1
                              local tElite = aqCombatCheckElite(tGuid)
                              local tCounts = tElite and tCombatInCounts(tMode, tGuid, tPlayerGUID, tAllPartyRaidUnits)
                              local tIdle = tEntry.lastUpdate and (tNow2 - tEntry.lastUpdate) or -1
                              -- Name + GUID tail: several entries can share a name
                              -- (boss images, identical adds), and without the tail
                              -- a genuine double-count is indistinguishable from two
                              -- real mobs in this line.
                              tParts[#tParts + 1] = string.format("[%s#%s c=%s%s%s idle%.1f]",
                                 tostring(tEntry.name or "?"), tGuid:sub(-6),
                                 tCounts and "Y" or "N",
                                 tElite and "" or " noElite",
                                 tCc and (" cc=" .. tCc) or "",
                                 tIdle)
                           end
                        end
                     end
                     dprint("aqCombat recount detail: ccInSet=" .. tCcCount, table.concat(tParts, " "))
                  end
                  tRelativeLastAnnounced = tCount
                  local tSetting = tCurrentSettings.combat.hostile.relativeNumberUnitsInCombat
                  SkuCoreAqCombatOutput(tSetting.voiceOutput, {number1 = tCount,}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
               end

               ttime2 = 0
            end

         elseif tCurrentSettings.combat.hostile.unitsAddedToCombat.value > 1 or tCurrentSettings.combat.hostile.unitsLeavingCombat.value > 1 then
            ttime1 = ttime1 + time

            if ttime1 > (1.0) then
               tCurrentUpdateRate = (21 - tCurrentSettings.combat.updateRate)

               -- Sweep entries that silently left combat (evade/leash/despawn
               -- without a death event) so the counter can decrement cleanly.
               tStaleSweep()

               local tCountIn = 0

               local tPlayerGUID = UnitGUID("player")
               local tChanged = false

               for creatureGUID, value in pairs(SkuCore.inOutCombatQueue.combatIn) do
                  if aqCombatCheckElite(creatureGUID) == true then
                     if tCombatInCounts(tCurrentSettings.combat.hostile.unitsAddedToCombat.value, creatureGUID, tPlayerGUID, tAllPartyRaidUnits) then
                        tCountIn = tCountIn + 1
                        tChanged = true
                     end

                     SkuCore.inOutCombatQueue.combatIn[creatureGUID] = nil
                  end
               end

               local tCountOut = 0
               for unitGUID, _ in pairs(SkuCore.inOutCombatQueue.combatOut) do
                  if aqCombatCheckElite(unitGUID) == true then
                     tCountOut = tCountOut + 1
                  end
               end

               SkuCore.inOutCombatQueue.current = SkuCore.inOutCombatQueue.current + tCountIn - tCountOut

               if SkuCore.inOutCombatQueue.current < 0 then
                  SkuCore.inOutCombatQueue.current = 0
               end
               
               SkuCore.inOutCombatQueue.combatOut = {}

               if tCountIn > 0 and tCurrentSettings.combat.hostile.unitsAddedToCombat.value > 1 then
                  local tSetting = tCurrentSettings.combat.hostile.unitsAddedToCombat
                  SkuCoreAqCombatOutput(tSetting.voiceOutput, {number1 = tCountIn, action1 = "in",}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
               end
               if tCountOut > 0 and tCurrentSettings.combat.hostile.unitsLeavingCombat.value > 1 then
                  local tSetting = tCurrentSettings.combat.hostile.unitsLeavingCombat
                  SkuCoreAqCombatOutput(tSetting.voiceOutput, {number1 = tCountOut, action1 = "out",}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
               end

               ttime1 = 0
            end

         end

         Sku.PerformanceData["aqCombatQueue onupdate"] = ((Sku.PerformanceData["aqCombatQueue onupdate"] or 0) + (debugprofilestop() - beginTime)) / 2
      end
   end)   
end

---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombat_CREATURE_REMOVED_FROM_COMBAT(aCreatureGuid, aCreatureUnitId, aCreatureName)
   if SkuCore.threatTable[aCreatureGuid] == nil then
      return
   end
   SkuCore.inOutCombatQueue.combatOut[aCreatureGuid] = true
   SkuCore.threatTable[aCreatureGuid] = false
   tCcState[aCreatureGuid] = nil
end

---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombat_CREATURE_ADDED_TO_COMBAT(aCreatureGuid, aCreatureUnitId, aCreatureName, aPartyGuid, aPartyUnitId, aPartyName)
   if SkuCore.threatTable[aCreatureGuid] then
      return
   end
   -- Central resurrection guard. A dead mob is stored as `false`, which is falsy,
   -- so the line below ("false or {}") used to hand it a fresh, alive entry. Every
   -- add path funnels through here, so refusing dead GUIDs once covers the
   -- combat-log flush, the threat scan and any future caller. Callers must not
   -- assume the entry exists after this returns (see the type() guards).
   if tDeadGuids[aCreatureGuid] then
      return
   end
   SkuCore.threatTable[aCreatureGuid] = SkuCore.threatTable[aCreatureGuid] or {}
   SkuCore.inOutCombatQueue.combatIn[aCreatureGuid] = aPartyUnitId
end

---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombatOnInitialize()
   tKeysRank = SkuDB.NpcData.Keys.rank

	aqCombatCreateControlFrame()

   SkuDispatcher:RegisterEventCallback("COMBAT_LOG_EVENT_UNFILTERED", aqCombat.aqCombat_COMBAT_LOG_EVENT_UNFILTERED)
   SkuDispatcher:RegisterEventCallback("SKU_UNIT_DIED", aqCombat.aqCombat_SKU_UNIT_DIED)
   SkuDispatcher:RegisterEventCallback("SKU_SPELL_CAST_START", aqCombat.aqCombat_SKU_SPELL_CAST_START)
   SkuDispatcher:RegisterEventCallback("SKU_SPELL_INTERRUPT", aqCombat.aqCombat_SKU_SPELL_INTERRUPT)

   SkuDispatcher:RegisterEventCallback("RAID_TARGET_UPDATE", aqCombat.aqCombatCheckGameRaidTargets)
	SkuDispatcher:RegisterEventCallback("PLAYER_REGEN_DISABLED", aqCombat.aqCombat_PLAYER_REGEN_DISABLED)
	SkuDispatcher:RegisterEventCallback("PLAYER_REGEN_ENABLED", aqCombat.aqCombat_PLAYER_REGEN_ENABLED)

	SkuDispatcher:RegisterEventCallback("PLAYER_TARGET_CHANGED", aqCombat.aqCombatPLAYER_TARGET_CHANGED)
   SkuDispatcher:RegisterEventCallback("GROUP_ROSTER_UPDATE", aqCombat.aqCombat_GROUP_ROSTER_UPDATE)
   SkuDispatcher:RegisterEventCallback("GROUP_FORMED", aqCombat.aqCombat_GROUP_ROSTER_UPDATE)
   SkuDispatcher:RegisterEventCallback("GROUP_JOINED", aqCombat.aqCombat_GROUP_ROSTER_UPDATE)

   
   -- hooksecurefunc can't be unhooked; guard with IsEnabled so a disabled
   -- monitor is a no-op. Install only once (OnEnable may run again after a
   -- toggle/reload) to avoid stacking duplicate hooks.
   if not SkuCore.aqCombatSetRaidTargetHooked then
      SkuCore.aqCombatSetRaidTargetHooked = true
      hooksecurefunc("SetRaidTarget", function(aUnit, aIconIndex)
         if not aqCombat:IsEnabled() then return end
         if aIconIndex == 0 then
            local tGUID = UnitGUID(aUnit)
            if tGUID then
               aqCombat:aqCombatSetSkuRaidTarget(tGUID)
            end
         end
      end)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombatOnLogin()
   for x = 1, 2 do
      SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat or {}

      if SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.enabled == nil then
         SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.enabled = false
      end

      if SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.updateRate == nil then
         SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.updateRate = 20
      end

      if SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.voice == nil then
         SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.voice = 1
      end

      if SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.notificationVolume == nil then
         SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.notificationVolume = 1
      end

      if SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.voiceVolume == nil then
         SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.voiceVolume = 2
      end

      --moved here from the removed Monitor "Global" menu; seed once from the old
      --global.numberOnly so existing users keep their choice
      if SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.numberOnly == nil then
         local tOldGlobal = SkuSettings:Sub("SkuCore", nil, "char").aq[x].global
         SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.numberOnly = (tOldGlobal and tOldGlobal.numberOnly) == true
      end
      

      --hostile
         if SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile == nil then
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile = {}
         end

         --ignoreNonElite
            if SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.ignoreNonElite == nil then
               SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.ignoreNonElite = true
            end

         --threat
            --Output target of target on target change
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.threatOutputTot = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.threatOutputTot or 
            {
               value = 1,
               sound = "vocalized",
            }
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.threatOutputTot.voiceOutput = "${sound};target;${unit1}"

            --Threat warning if you are not first place (not tanking) and your threat percentage is higher than
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.threatWarningNotFirstHigherThan = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.threatWarningNotFirstHigherThan or 
            {
               value = 0,
               sound = "vocalized",
            }
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.threatWarningNotFirstHigherThan.voiceOutput = "${sound};threat;high"

            --Threat warning if you are first place (tanking) and second place threat percentage is higher than
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.threatWarningIsFirstSecondHigherThan = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.threatWarningIsFirstSecondHigherThan or
            {
               value = 0,
               sound = "vocalized",
            }
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.threatWarningIsFirstSecondHigherThan.voiceOutput = "${sound};threat;low"

            --threatWarningInterval
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.threatWarningInterval = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.threatWarningInterval or 0

            --Warning if your target is switching from you to party member
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.warnIfTargetSwitchingToParty = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.warnIfTargetSwitchingToParty or 
            {
               value = false,
               sound = "vocalized",
            }
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.warnIfTargetSwitchingToParty.voiceOutput = "${sound};target;lost"
            
            --Warning if your target is switching from party member to you
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.warnIfTargetSwitchingToYou = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.warnIfTargetSwitchingToYou or 
            {
               value = false,
               sound = "vocalized",
            }
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.warnIfTargetSwitchingToYou.voiceOutput = "${sound};target;gained"
            
         --casting
            --Output your target casting
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.yourTargetCasting = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.yourTargetCasting or 
            {
               value = 0,
               sound = "vocalized",
            }
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.yourTargetCasting.voiceOutput = "${sound};target;casting"
            
            --Output all enemies casting
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.allEnemiesCasting = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.allEnemiesCasting or 
            {
               value = 0,
               sound = "vocalized",
            }
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.allEnemiesCasting.voiceOutput = "${sound};creature;casting"
            
            --minimumCastDuration
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.minimumCastDuration = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.minimumCastDuration or 0

            --only announce interruptible casts
            if SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.onlyInterruptibleCasts == nil then
               SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.onlyInterruptibleCasts = false
            end

            --announce interrupts by you/party/raid (default ON; nil-fill also
            --switches it on once for existing profiles that predate the setting)
            if SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.outputInterrupts == nil then
               SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.outputInterrupts = true
            end

         
         --deaths
            --ignore dead units not in combat
            if SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.deathsIgnoreUnitsNotInCombat == nil then
               SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.deathsIgnoreUnitsNotInCombat = true
            end

            --Output dead units
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.outputDeadUnits = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.outputDeadUnits or 
            {
               value = 1,
               sound = "vocalized",
            }
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.outputDeadUnits.voiceOutput = "${sound};${unit1};dead"


         --units in combat
            --Announce enemies entering combat
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.unitsAddedToCombat = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.unitsAddedToCombat or 
            {
               value = 1,
               sound = "vocalized",
            }
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.unitsAddedToCombat.voiceOutput = "${sound};${number1};${action1}"

            --Announce enemies leaving combat
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.unitsLeavingCombat = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.unitsLeavingCombat or 
            {
               value = 1,
               sound = "vocalized",
            }
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.unitsLeavingCombat.voiceOutput = "${sound};${number1};${action1}"

            if SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.shortUnitsAddedOrLeavingToCombatMessages == nil then
               SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.shortUnitsAddedOrLeavingToCombatMessages = false
            end

            --Announce relative number of enemies in combat
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.relativeNumberUnitsInCombat = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.relativeNumberUnitsInCombat or 
            {
               value = 1,
               sound = "vocalized",
            }
            SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.hostile.relativeNumberUnitsInCombat.voiceOutput = "${sound};${number1}"

      --friendly
      SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly or {}
         --
         SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly.partyDead = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly.partyDead or
         {
            value = false,
            sound = "vocalized",
         }
         SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly.partyDead.voiceOutput = "${sound};${unit1};dead"

         --
         SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly.partyDeadCount = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly.partyDeadCount or
         {
            value = false,
            sound = "vocalized",
         }
         SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly.partyDeadCount.voiceOutput = "${sound};${number1};dead"

         --
         SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly.outOfRangeEnabled = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly.outOfRangeEnabled or
         {
            value = false,
            sound = "vocalized",
         }
         SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly.outOfRangeEnabled.voiceOutput = "${sound};${unit1};leaving"

         --
         SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly.ignoreDeadPartyPets = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly.ignoreDeadPartyPets or true

         --
         SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly.oorAt = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly.oorAt or 10

         --
         SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly.oorUnitName = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly.oorUnitName or L["Nothing selected"]

         --
         SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly.oorInterval = SkuSettings:Sub("SkuCore", nil, "char").aq[x].combat.friendly.oorInterval or 0

   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Module lifecycle (W4 Phase D). AceAddon calls OnEnable at SkuCore enable, on
-- every /reload, and whenever the user toggles the feature back on; OnDisable
-- when toggled off. The combat-on/off SETTING (aq[talentSet].combat.enabled)
-- is unchanged and independent of this module on/off.
---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:OnEnable()
   -- Arm: register the dispatcher callbacks + control OnUpdate frames + the
   -- SetRaidTarget hook (idempotent: dispatcher callbacks key by function so
   -- re-registering is a no-op, control frames are reused via _G[...], and the
   -- hook installs only once), then seed the settings defaults.
   aqCombat:aqCombatOnInitialize()
   aqCombat:aqCombatOnLogin()
end

function aqCombat:OnDisable()
   -- Real teardown: unregister every dispatcher callback this feature armed and
   -- stop both control OnUpdate frames so a disabled monitor does nothing. The
   -- SetRaidTarget hooksecurefunc can't be removed; its body is IsEnabled-guarded.
   SkuDispatcher:UnregisterEventCallback("COMBAT_LOG_EVENT_UNFILTERED", aqCombat.aqCombat_COMBAT_LOG_EVENT_UNFILTERED)
   SkuDispatcher:UnregisterEventCallback("SKU_UNIT_DIED", aqCombat.aqCombat_SKU_UNIT_DIED)
   SkuDispatcher:UnregisterEventCallback("SKU_SPELL_CAST_START", aqCombat.aqCombat_SKU_SPELL_CAST_START)
   SkuDispatcher:UnregisterEventCallback("SKU_SPELL_INTERRUPT", aqCombat.aqCombat_SKU_SPELL_INTERRUPT)
   SkuDispatcher:UnregisterEventCallback("RAID_TARGET_UPDATE", aqCombat.aqCombatCheckGameRaidTargets)
   SkuDispatcher:UnregisterEventCallback("PLAYER_REGEN_DISABLED", aqCombat.aqCombat_PLAYER_REGEN_DISABLED)
   SkuDispatcher:UnregisterEventCallback("PLAYER_REGEN_ENABLED", aqCombat.aqCombat_PLAYER_REGEN_ENABLED)
   SkuDispatcher:UnregisterEventCallback("PLAYER_TARGET_CHANGED", aqCombat.aqCombatPLAYER_TARGET_CHANGED)
   SkuDispatcher:UnregisterEventCallback("GROUP_ROSTER_UPDATE", aqCombat.aqCombat_GROUP_ROSTER_UPDATE)
   SkuDispatcher:UnregisterEventCallback("GROUP_FORMED", aqCombat.aqCombat_GROUP_ROSTER_UPDATE)
   SkuDispatcher:UnregisterEventCallback("GROUP_JOINED", aqCombat.aqCombat_GROUP_ROSTER_UPDATE)

   if _G["SkuCoreaqCombatControl"] then
      _G["SkuCoreaqCombatControl"]:SetScript("OnUpdate", nil)
   end
   if _G["SkuCoreaqCombatQueueControl"] then
      _G["SkuCoreaqCombatQueueControl"]:SetScript("OnUpdate", nil)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombat_GROUP_ROSTER_UPDATE()
   aqCombatIsPartyOrRaidMemberCache = {}
   
   if UnitGUID("player") then
      aqCombatIsPartyOrRaidMemberCache[UnitGUID("player")] = "player"
   end

   if UnitGUID("pet") then
      aqCombatIsPartyOrRaidMemberCache[UnitGUID("pet")] = "pet"
   end

   for x = 1, 4 do
      if UnitGUID("party"..x) then
         aqCombatIsPartyOrRaidMemberCache[UnitGUID("party"..x)] = "party"..x
      end
      if UnitGUID("partypet"..x) then
         aqCombatIsPartyOrRaidMemberCache[UnitGUID("partypet"..x)] = "partypet"..x
      end
   end

   for x = 1, 40 do
      if UnitGUID("raid"..x) then
         aqCombatIsPartyOrRaidMemberCache[UnitGUID("raid"..x)] = "raid"..x
      end
      if UnitGUID("raidpet"..x) then
         aqCombatIsPartyOrRaidMemberCache[UnitGUID("raidpet"..x)] = "raidpet"..x
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombatPLAYER_TARGET_CHANGED(aEvent, a, b, c, d)
   local tCurrentSettings = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet]
   if tCurrentSettings.combat.enabled == true then
      if tCurrentSettings.combat.hostile.threatOutputTot.value > 1 then
         if UnitExists("playertargettarget") then
            local tOutput = tCurrentSettings.combat.hostile.threatOutputTot.voiceOutput
            for x = 1, #tAllPartyRaidUnits do
               if UnitGUID(tAllPartyRaidUnits[x]) == UnitGUID("playertargettarget") then
                  if aqCombatCheckElite(UnitGUID("playertargettarget")) == true then
                     if tCurrentSettings.combat.hostile.threatOutputTot.value == 2 then
                        SkuCoreAqCombatOutput(tOutput, {unit1 = tAllPartyRaidUnits[x],}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tCurrentSettings.combat.hostile.threatOutputTot)
                     elseif tCurrentSettings.combat.hostile.threatOutputTot.value == 3 then
                        if UnitGUID(tAllPartyRaidUnits[x]) ~= UnitGUID("player") then
                           SkuCoreAqCombatOutput(tOutput, {unit1 = tAllPartyRaidUnits[x],}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tCurrentSettings.combat.hostile.threatOutputTot)
                        end
                     end
                     break
                  end
               end
            end
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Coalesced combat-log add path. Instead of one C_Timer.After(0.5) per
-- qualifying combat-log event -- which in a raid means hundreds of short-lived
-- closures/tables per second and the GC churn that hitches the frame -- events
-- are recorded into a pending set (a cheap table write) and a SINGLE 0.5s flush
-- is scheduled per burst. Same ~0.5s settle delay (so a fresh mob's unit token
-- has time to exist before we resolve it), but the whole burst is applied
-- atomically, so a multi-pull is announced as one number by the next recount.
-- (tPendingAdds / tPendingAddScheduled are declared near the top of the file so
-- the earlier add + death handlers can see them.)
-- Coalescing window: how long the shared flush waits after the first pending add
-- before applying the whole burst. Smaller = the first number is announced sooner,
-- but a pull whose mobs engage over a longer span may split into two
-- announcements. 0.3s reacts faster than 0.5s while still catching near-
-- simultaneous (AoE / pack) pulls, which cluster within a frame or two. The
-- add-flush breadcrumb below logs batch sizes so this can be confirmed/tuned.
local tFlushWindow = 0.3

local function tFlushPendingAdds()
   tPendingAddScheduled = false
   local tBatch, tAdded, tGuidAdd, tKept, tDeadSkip, tFriendSkip = 0, 0, 0, 0, 0, 0
   for tCreatureGUID, tInfo in pairs(tPendingAdds) do
      tPendingAdds[tCreatureGUID] = nil
      tBatch = tBatch + 1

      local tMobUnitId = aqCombat:aqCombatCreatureGuidToUnitId(tCreatureGUID)
      local tPartyUnitId = aqCombat:aqCombatCreatureGuidToUnitId(tInfo.partyGuid)
         or aqCombat:aqCombatIsPartyOrRaidMember(nil, tInfo.partyGuid)

      -- Died this fight? Then this is a leftover event from the window around the
      -- killing blow and must not revive the corpse. Sole exception, and it needs
      -- hard proof: a unit token that says the mob is alive again (in-fight
      -- resurrect / same-GUID revive), in which case the death mark is lifted.
      local tIsDead = tDeadGuids[tCreatureGUID]
      if tIsDead and tMobUnitId and UnitIsDeadOrGhost(tMobUnitId) == false then
         tDeadGuids[tCreatureGUID] = nil
         tIsDead = false
      end

      -- Hostility: ask once, on admission only. An entry already in the table is
      -- never re-judged here, so an encounter turning a mob immune or
      -- non-attackable mid-fight cannot drop it out of the count.
      local tAlreadyTracked = (type(SkuCore.threatTable[tCreatureGUID]) == "table")
      local tHostile = tAlreadyTracked or tShouldAdmitAsEnemy(tCreatureGUID, tMobUnitId, tInfo.hostile)

      if tIsDead then
         tDeadSkip = tDeadSkip + 1
      elseif not tHostile then
         tFriendSkip = tFriendSkip + 1
      elseif tMobUnitId and tPartyUnitId and UnitIsDeadOrGhost(tMobUnitId) ~= true then
         -- Resolved & alive: full token-based add. Also seeds this party member's
         -- threat sub-entry so mode 4 / threat warnings have data to work with.
         aqCombat:aqCombat_CREATURE_ADDED_TO_COMBAT(tCreatureGUID, tMobUnitId, tInfo.name, tInfo.partyGuid, tPartyUnitId, tInfo.partyName)

         if type(SkuCore.threatTable[tCreatureGUID]) == "table" then
            SkuCore.threatTable[tCreatureGUID].name = tInfo.name
            SkuCore.threatTable[tCreatureGUID].lastUpdate = GetTimePreciseSec()

            if SkuCore.threatTable[tCreatureGUID][tInfo.partyGuid] == nil then
               SkuCore.threatTable[tCreatureGUID][tInfo.partyGuid] = {
                  isTanking = nil,
                  wasTanking = nil,
                  status = nil,
                  scaledPercentage = nil,
                  rawPercentage = nil,
                  threatValue = nil,
               }
            end

            SkuCore.threatTable[tCreatureGUID][tInfo.partyGuid].lastUpdate = GetTimePreciseSec()
            SkuCore.aqCombatCheckThreat = true
            tAdded = tAdded + 1
         end
      elseif tPartyUnitId and not tMobUnitId then
         -- Admit-by-GUID (this also subsumes the old keep-alive refresh). We can't
         -- resolve the MOB to a live unit token this window -- e.g. a boss just
         -- summoned a swarm of adds and only a few have nameplates / are targeted
         -- -- but the combat log proves a party/raid member is engaging it. For
         -- mode 3 ("enemies attacking party or you") that evidence alone counts,
         -- so admit it by its GUID. combatIn stores the resolved PARTY token, which
         -- is exactly what the mode-3 eager gate checks, so the recount counts it.
         -- This lets the number reach the true total in a swarm instead of capping
         -- at whatever subset currently has a token, and holds already-admitted
         -- mobs across resolution gaps. Elite filtering still works from the GUID
         -- via NpcData; removal stays reliable via SKU_UNIT_DIED (GUID-based) and
         -- the stale sweep once the mob goes quiet. Mode 4 is unaffected: with no
         -- threat sub-entry a GUID-only mob is not known to be attacking YOU, so it
         -- correctly does not count there.
         local tWasNew = (SkuCore.threatTable[tCreatureGUID] == nil)
         aqCombat:aqCombat_CREATURE_ADDED_TO_COMBAT(tCreatureGUID, nil, tInfo.name, tInfo.partyGuid, tPartyUnitId, tInfo.partyName)
         if type(SkuCore.threatTable[tCreatureGUID]) == "table" then
            SkuCore.threatTable[tCreatureGUID].name = SkuCore.threatTable[tCreatureGUID].name or tInfo.name
            SkuCore.threatTable[tCreatureGUID].lastUpdate = GetTimePreciseSec()
            if tWasNew then
               tGuidAdd = tGuidAdd + 1
            else
               tKept = tKept + 1
            end
         end
      end
   end
   if tBatch > 0 then
      dprint("aqCombat add-flush: window", tFlushWindow, "batch", tBatch, "resolved+added", tAdded, "guid-added", tGuidAdd,
         "kept-alive", tKept, "dead-skip", tDeadSkip, "friendly-skip", tFriendSkip)
   end
end

local function tAddHelper(event, tCreatureGUID, tMobName, tPartyGuid, tPartyname, aHostile)
   if
      sfind(event, "_DAMAGE") or
      sfind(event, "_MISSED") or
      sfind(event, "_APPLIED") or
      sfind(event, "_CAST_SUCCESS") or
      sfind(event, "_CAST_START") or
      sfind(event, "_CAST_FAILED")
   then
      -- Record the pending add (last party attacker in the window wins; the
      -- periodic control-frame threat scan fills in the other party members'
      -- threat entries anyway) and arm one shared flush for the burst. aHostile
      -- carries the reaction read off this very event's unit flags, which is the
      -- only hostility evidence available for a mob with no unit token.
      tPendingAdds[tCreatureGUID] = {name = tMobName, partyGuid = tPartyGuid, partyName = tPartyname, hostile = aHostile}
      if not tPendingAddScheduled then
         tPendingAddScheduled = true
         C_Timer.After(tFlushWindow, tFlushPendingAdds)
      end
   end
end

local tGUIDCache = {creatures = {}, nonCreatures = {}}
function aqCombat:aqCombat_COMBAT_LOG_EVENT_UNFILTERED()
   local arg1, event, arg3, sourceGUID, sourceName, tSourceFlags, arg7, targetGUID, targetName, tDestFlags = CombatLogGetCurrentEventInfo()

   -- LIVENESS: any combat-log line that so much as mentions a tracked enemy proves
   -- it is still in the fight -- as attacker, as victim, hitting a non-party
   -- friendly NPC, taking a DoT tick. The add path below only ever looks at
   -- events between the party and a mob, and only at a subset of event types, so
   -- plenty of proof-of-life used to go unused and the 6s stale sweep dropped
   -- mobs that were plainly still fighting. Two hash lookups per event; the
   -- type() check keeps dead/swept entries (false) untouched, so this can never
   -- resurrect anything.
   local tLiveTable = SkuCore.threatTable
   if tLiveTable then
      local tSrcEntry = sourceGUID and tLiveTable[sourceGUID]
      local tDstEntry = targetGUID and tLiveTable[targetGUID]
      if type(tSrcEntry) == "table" or type(tDstEntry) == "table" then
         local tSeenAt = GetTimePreciseSec()
         if type(tSrcEntry) == "table" then tSrcEntry.lastUpdate = tSeenAt end
         if type(tDstEntry) == "table" then tDstEntry.lastUpdate = tSeenAt end
      end
   end

   -- CC state maintenance (see tCcSpells). Runs regardless of the party-source gate
   -- below, since CC can come from the player, a pet, or any group member.
   if targetGUID and tCcAuraEvents[event] then
      local tSpellId = select(12, CombatLogGetCurrentEventInfo())
      local tCc = tSpellId and tCcSpells[tSpellId]
      if tCc then
         if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
            if not (tCcState[targetGUID] and tCcState[targetGUID].key == tCc) then
               dprint("aqCombat cc-applied:", targetName or "?", tCc, "spell", tSpellId)
            end
            tCcState[targetGUID] = {key = tCc, t = GetTimePreciseSec()}
         elseif tCcState[targetGUID] then
            dprint("aqCombat cc-removed:", targetName or "?", tCcState[targetGUID].key, "via", event)
            tCcState[targetGUID] = nil
         end
      end
   end

   if sourceGUID and targetGUID then
      if aqCombat:aqCombatIsPartyOrRaidMember(nil, sourceGUID) then
         if not tGUIDCache.nonCreatures[targetGUID] then
            if sfind(targetGUID, "Creature-") then
               tGUIDCache.creatures[targetGUID] = true
            else
               tGUIDCache.nonCreatures[targetGUID] = true
            end
         end
         if tGUIDCache.creatures[targetGUID] then
            -- Party member acted on a creature. The creature's own reaction flags
            -- decide whether it is an enemy at all: a heal, a buff or a stray AoE
            -- on a friendly escort NPC (Millhouse Manastorm and friends) hits this
            -- same path and used to add that NPC to the enemy count.
            tAddHelper(event, targetGUID, targetName, sourceGUID, sourceName, tFlagsSayHostile(tDestFlags))
         end
      elseif aqCombat:aqCombatIsPartyOrRaidMember(nil, targetGUID) then
         if not tGUIDCache.creatures[sourceGUID] then
            if sfind(sourceGUID, "Creature-") then
               tGUIDCache.creatures[sourceGUID] = true
            else
               tGUIDCache.nonCreatures[sourceGUID] = true
            end
         end

         if tGUIDCache.creatures[sourceGUID] then
            tAddHelper(event, sourceGUID, sourceName, targetGUID, targetName, tFlagsSayHostile(tSourceFlags))
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- The notInterruptible API flag is dead data on this client (always nil, verified
-- 2026-07-26), so interruptibility comes from SkuDB.uninterruptibleCasts:
-- spellID, localized spell name (multi-rank spells), or npcID..spellName.
local function aqCombatCastIsUninterruptible(aSpellId, aSpellName, aSourceGUID)
   local tDb = SkuDB.uninterruptibleCasts
   if not tDb then return false end
   if aSpellId and tDb.spells[aSpellId] then return true end
   if aSpellName and tDb.spells[aSpellName] then return true end
   if aSourceGUID and aSpellName then
      local tNpcId = select(6, strsplit("-", aSourceGUID))
      if tNpcId and tDb.npcSpells[tNpcId..aSpellName] then return true end
   end
   return false
end

---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombat_SKU_SPELL_CAST_START(aEvent, aEventData)
   --[[
	sourceGUID = 4,
	sourceName = 5,
	sourceFlags = 6,
	sourceRaidFlags = 7,
	destGUID = 8,
	destName = 9,
	destFlags = 10,
	destRaidFlags = 11,
	spellId = 12,
	spellName = 13,
   ]]

   local tCurrentSettings = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet]

   if tCurrentSettings.combat.hostile.onlyInterruptibleCasts == true then
      if aqCombatCastIsUninterruptible(aEventData[12], aEventData[13], aEventData[4]) then
         return
      end
   end

   if tCurrentSettings.combat.enabled == true then
      if aqCombatCheckElite(aEventData[4]) == true then
         if tCurrentSettings.combat.hostile.yourTargetCasting.value > 1 then
            local tUnitGUID = aEventData[4]
            if tUnitGUID and tUnitGUID == UnitGUID("target") then
               local tTargetTargetGuid = UnitGUID("targettarget")
               if tTargetTargetGuid then
                  local name, rank, icon, castTime
                  if aEventData[12] then
                     name, rank, icon, castTime = GetSpellInfo(aEventData[12])
                  end
                  if castTime == nil or (castTime > (tCurrentSettings.combat.hostile.minimumCastDuration * 1000)) then
                     if tCurrentSettings.combat.hostile.yourTargetCasting.value == 2 then
                        if tTargetTargetGuid == UnitGUID("player") then
                           local tSetting = tCurrentSettings.combat.hostile.yourTargetCasting
                           SkuCoreAqCombatOutput(tSetting.voiceOutput, {}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
                        end
                     elseif tCurrentSettings.combat.hostile.yourTargetCasting.value == 3 then
                        if aqCombat:aqCombatIsPartyOrRaidMember(nil, tTargetTargetGuid) then
                           local tSetting = tCurrentSettings.combat.hostile.yourTargetCasting
                           SkuCoreAqCombatOutput(tSetting.voiceOutput, {}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
                        end
                     end
                  end
               end
            end
         end

         if tCurrentSettings.combat.hostile.allEnemiesCasting.value > 1 then
            local tUnitGUID = aEventData[4]
            if tUnitGUID then
               if aqCombat:aqCombatGroupGuidToUnitId(tUnitGUID) == nil then
                  local name, rank, icon, castTime
                  if aEventData[12] then
                     name, rank, icon, castTime = GetSpellInfo(aEventData[12])
                  end
                  if castTime == nil or (castTime > (tCurrentSettings.combat.hostile.minimumCastDuration * 1000)) then
                     if tCurrentSettings.combat.hostile.allEnemiesCasting.value == 2 then
                        if SkuCore.threatTable[tUnitGUID] then
                           local tSetting = tCurrentSettings.combat.hostile.allEnemiesCasting
                           SkuCoreAqCombatOutput(tSetting.voiceOutput, {}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
                        end
                     elseif tCurrentSettings.combat.hostile.allEnemiesCasting.value == 3 then
                        local tSetting = tCurrentSettings.combat.hostile.allEnemiesCasting
                        SkuCoreAqCombatOutput(tSetting.voiceOutput, {}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
                     end
                  end
               end
            end
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- SPELL_INTERRUPT: source = who interrupted, dest = whose cast broke. Affiliation
-- flags instead of GUID lists so pet interrupts (felhunter Spell Lock etc.) count
-- for their owner side: MINE covers you incl. your pet, PARTY/RAID the group.
local tInterruptGroupMask = bit.bor(COMBATLOG_OBJECT_AFFILIATION_PARTY, COMBATLOG_OBJECT_AFFILIATION_RAID)
function aqCombat:aqCombat_SKU_SPELL_INTERRUPT(aEvent, aEventData)
   local tCurrentSettings = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet]
   if tCurrentSettings.combat.enabled ~= true then return end
   if tCurrentSettings.combat.hostile.outputInterrupts ~= true then return end
   local tSourceFlags = aEventData[6]
   if not tSourceFlags then return end
   if bit.band(tSourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) > 0 then
      SkuOptions.Voice:OutputStringBTtts(Sku.deEn("Du hast unterbrochen", "You interrupted"), false, true, 0.2, true)
   elseif bit.band(tSourceFlags, tInterruptGroupMask) > 0 then
      SkuOptions.Voice:OutputStringBTtts(Sku.deEn("Zauber unterbrochen", "Spell interrupted"), false, true, 0.2, true)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombat_SKU_UNIT_DIED(aEvent, aUnitGUID, aUnitName)
   local tCurrentSettings = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet]

   if tCurrentSettings.combat.enabled == true then
      if aqCombatCheckElite(aUnitGUID) == true then
         if tCurrentSettings.combat.hostile.outputDeadUnits.value > 1 then
            if (tCurrentSettings.combat.hostile.deathsIgnoreUnitsNotInCombat == true and SkuCore.threatTable[aUnitGUID] ~= nil) or tCurrentSettings.combat.hostile.deathsIgnoreUnitsNotInCombat == false then
               local tCreateUnitId = aqCombat:aqCombatCreatureGuidToUnitId(aUnitGUID)
               if tCreateUnitId == nil then
                  tCreateUnitId = "creature"
               end

               if tCurrentSettings.combat.hostile.outputDeadUnits.value == 2 then
                  local tSetting = tCurrentSettings.combat.hostile.outputDeadUnits
                  SkuCoreAqCombatOutput(tSetting.voiceOutput, {unit1 = tCreateUnitId,}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
               elseif tCurrentSettings.combat.hostile.outputDeadUnits.value == 3 then
                  if SkuCore.threatTable[aUnitGUID] and SkuCore.threatTable[aUnitGUID][UnitGUID("player")] then
                     if SkuCore.threatTable[aUnitGUID][UnitGUID("player")].scaledPercentage >= 100 then
                        local tSetting = tCurrentSettings.combat.hostile.outputDeadUnits
                        SkuCoreAqCombatOutput(tSetting.voiceOutput, {unit1 = tCreateUnitId,}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
                     end
                  end
               elseif tCurrentSettings.combat.hostile.outputDeadUnits.value == 4 then
                  if SkuCore.threatTable[aUnitGUID] then
                     local tSetting = tCurrentSettings.combat.hostile.outputDeadUnits
                     SkuCoreAqCombatOutput(tSetting.voiceOutput, {unit1 = tCreateUnitId,}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
                  end
               end
            end
         end
      end
   end

   if SkuCore.SkuRaidTargetRepo[aUnitGUID] then
      local tIndex = SkuCore.SkuRaidTargetRepo[aUnitGUID]
      SkuCore.SkuRaidTargetRepoDead[aUnitGUID] = tIndex
      SkuCore.SkuRaidTargetRepo[aUnitGUID] = nil
   end

   if tCurrentSettings.combat.enabled == true then
      if aqCombat:aqCombatIsPartyOrRaidMember(nil, aUnitGUID) == nil then
         if sfind(aUnitGUID, "Creature-") then
            -- Mark the death BEFORE the removal, and drop any add for this mob that
            -- is still sitting in the coalescing window: combat-log lines from the
            -- moment of the killing blow flush up to tFlushWindow seconds later and
            -- would otherwise re-add the corpse right after the count reached 0.
            tDeadGuids[aUnitGUID] = true
            tPendingAdds[aUnitGUID] = nil
            aqCombat:aqCombat_CREATURE_REMOVED_FROM_COMBAT(aUnitGUID, nil, aUnitName)
         end
      else
         local tPartyUnitId = aqCombat:aqCombatGroupGuidToUnitId(aUnitGUID)
         if tPartyUnitId == nil then
            tPartyUnitId = ""
         end
         
         if 
            tCurrentSettings.combat.friendly.ignoreDeadPartyPets == false or
            tPartyUnitId == "" or
            (
               tCurrentSettings.combat.friendly.ignoreDeadPartyPets == true and
               sfind(tPartyUnitId, "pet") == nil and
               UnitIsOtherPlayersPet(tPartyUnitId) == false and
               aUnitGUID ~= UnitGUID("pet")
            )
         then
            if tPartyUnitId == "" or UnitIsDeadOrGhost(tPartyUnitId) == true then
               SkuCore.partyDeadCountCounter = SkuCore.partyDeadCountCounter + 1
               if tCurrentSettings.combat.friendly.partyDeadCount.value == true then
                  local tSetting = tCurrentSettings.combat.friendly.partyDeadCount
                  SkuCoreAqCombatOutput(tSetting.voiceOutput, {number1 = SkuCore.partyDeadCountCounter,}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
               end

               if tCurrentSettings.combat.friendly.partyDead.value == true then
                  local tSetting = tCurrentSettings.combat.friendly.partyDead
                  SkuCoreAqCombatOutput(tSetting.voiceOutput, {unit1 = tPartyUnitId,}, {wait = true, overwrite = false, instant = true, doNotOverwrite = true}, tSetting)
               end
            end
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombat_PLAYER_REGEN_DISABLED()
   SkuCore.aqCombatCheckThreat = true
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Is anyone in the group (or their pet) still fighting? PLAYER_REGEN_ENABLED is
-- named after health/mana regeneration resuming, but it simply means "YOU left
-- combat" -- your personal combat flag expiring a few seconds after the last blow
-- traded. Being feared away from the pack, or having your last attacker die while
-- the group fights on, fires it mid-fight.
local function tGroupStillInCombat()
   for i = 1, #tAllPartyRaidUnits do
      local tUnit = tAllPartyRaidUnits[i]
      if UnitExists(tUnit) and UnitAffectingCombat(tUnit) then
         return true
      end
   end
   return false
end

-- PLAYER_REGEN_ENABLED does not repeat, so when the wipe is deferred a light poll
-- takes over until the group's fight really ends.
local tRegenRecheck
local tRegenRecheckScheduled = false

---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombat_PLAYER_REGEN_ENABLED()
   -- Modes 2 and 3 count enemies fighting the PARTY, explicitly independent of the
   -- player's own combat state, so YOUR combat ending is not the fight ending:
   -- wiping the table here announced a false 0 and then climbed back up as the
   -- same mobs were rediscovered. Hold the reset until nobody in the group is in
   -- combat any more. Mode 4 ("attacking you") keeps the immediate reset -- with
   -- you out of combat, nothing is attacking you, and 0 is the right answer.
   local tMode = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.relativeNumberUnitsInCombat.value
   if (tMode == 2 or tMode == 3) and tGroupStillInCombat() then
      if not tRegenRecheckScheduled then
         tRegenRecheckScheduled = true
         C_Timer.After(2, tRegenRecheck)
      end
      return
   end

   SkuCore.partyDeadCountCounter = 0
   SkuCore.aqCombatCheckThreat = nil
   aqCombat:aqCombatClearSkuRaidTargets()

   -- The relative-enemies counter no longer needs a hand-placed "force 0" here:
   -- clearing threatTable below empties the live set, and the queue OnUpdate keeps
   -- running out of combat, so its next recount tick naturally reports 0 and
   -- announces it (tRelativeLastAnnounced is deliberately NOT reset here, so the
   -- transition to 0 is still detected). This is the self-healing property of the
   -- recount replacing the old drift-prone delta.

   -- Drop any combat-log adds still waiting to flush so a late flush can't
   -- resurrect a phantom enemy into the freshly-cleared threatTable.
   for tGuid in pairs(tPendingAdds) do
      tPendingAdds[tGuid] = nil
   end

   SkuCore.threatTable = {}
   SkuCore.inOutCombatQueue = {
      current = 0,
      combatIn = {},
		combatOut = {},
   }

   -- Combat over: drop all tracked crowd-control state so it can't leak into the
   -- next fight (tCcState is decoupled from threatTable, cleared here + on death).
   for tGuid in pairs(tCcState) do
      tCcState[tGuid] = nil
   end

   -- Fight over: this fight's deaths and hostility verdicts stop applying. A GUID
   -- is unique per spawn, so nothing here needs to survive into the next pull.
   for tGuid in pairs(tDeadGuids) do
      tDeadGuids[tGuid] = nil
   end
   for tGuid in pairs(tKnownHostile) do
      tKnownHostile[tGuid] = nil
   end
end

-- Deferred end-of-combat cleanup (see aqCombat_PLAYER_REGEN_ENABLED). Re-arms
-- itself every 2s while the group is still fighting; if the player is back in
-- combat the poll simply stops, because the next real PLAYER_REGEN_ENABLED will
-- take over.
tRegenRecheck = function()
   tRegenRecheckScheduled = false
   if UnitAffectingCombat("player") then
      return
   end
   if tGroupStillInCombat() then
      tRegenRecheckScheduled = true
      C_Timer.After(2, tRegenRecheck)
      return
   end
   dprint("aqCombat deferred combat-end cleanup: group left combat")
   aqCombat:aqCombat_PLAYER_REGEN_ENABLED()
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Sku raid target
---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombatGetSkuRaidTarget(aUnitGUID)
   -- W6-C: the two loops only ever matched by GUID key, so they are plain hash
   -- lookups on the GUID-keyed repos (reading t[nil] is safe -> nil).
   local tLive = SkuCore.SkuRaidTargetRepo[aUnitGUID]
   if tLive ~= nil then
      return tLive
   end
   local tDead = SkuCore.SkuRaidTargetRepoDead[aUnitGUID]
   if tDead ~= nil then
      return tDead, true
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombatSetSkuRaidTarget(aUnitGUID, aRaidTargetId)
   if not aUnitGUID then
      return
   end

   if aRaidTargetId == nil then
      --clear
      if SkuCore.SkuRaidTargetRepo[aUnitGUID] then
         SkuCore.SkuRaidTargetRepo[aUnitGUID] = nil
         return true
      end
      if SkuCore.SkuRaidTargetRepoDead[aUnitGUID] then
         SkuCore.SkuRaidTargetRepoDead[aUnitGUID] = nil
         return true
      end
   elseif aRaidTargetId == 0 then
      for x = 1, #SkuCore.SkuRaidTargetIndex do
         local tAvailable = true
         for i, v in pairs(SkuCore.SkuRaidTargetRepo) do
            if v == SkuCore.SkuRaidTargetIndex[x] then
               tAvailable = false
            end
         end
         for i, v in pairs(SkuCore.SkuRaidTargetRepoDead) do
            if v == SkuCore.SkuRaidTargetIndex[x] then
               tAvailable = false
            end
         end
         if tAvailable == true then
            SkuCore.SkuRaidTargetRepo[aUnitGUID] = SkuCore.SkuRaidTargetIndex[x]
            return SkuCore.SkuRaidTargetIndex[x]
         end
      end
   elseif aRaidTargetId > 0 then
      --raid target index
      SkuCore.SkuRaidTargetRepo[aUnitGUID] = nil
      SkuCore.SkuRaidTargetRepoDead[aUnitGUID] = nil
      SkuCore.SkuRaidTargetRepo[aUnitGUID] = aRaidTargetId
      return aRaidTargetId
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombatClearSkuRaidTargets()
   SkuCore.SkuRaidTargetRepo = {}
   SkuCore.SkuRaidTargetRepoDead = {}
end

---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombatCheckGameRaidTargets()
   for i = 1, #tUnitsToTestOnGameRaidTargets do
      local tguid = UnitGUID(tUnitsToTestOnGameRaidTargets[i])
      if tguid then
         local tRti = GetRaidTargetIndex(tUnitsToTestOnGameRaidTargets[i])
         if tRti then
            SkuCore.SkuRaidTargetRepo[tguid] = nil
            SkuCore.SkuRaidTargetRepoDead[tguid] = nil
            return
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- combat monitor Menu
local function tSoundMenuBuilder(self, aSetting)
   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Audio"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.sorting = true   
   tNewMenuEntry.isSelect = true
   tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
      for i, v in pairs(aqCombatAudioOutputs) do
         if aSetting.sound == i then
            return v
         end
      end
   end

   tNewMenuEntry.OnAction = function(self, aValue, aName)
      for i, v in pairs(aqCombatAudioOutputs) do
         if aName == v then
            aSetting.sound = i
         end
      end
   end
   tNewMenuEntry.BuildChildren = function(self)
      local tSortedList = {}
      for k, v in SkuSpairs(aqCombatAudioOutputs, function(t,a,b) 
         return a > b
      end) do 
         tSortedList[#tSortedList+1] = v
      end      

      for i = 1, #tSortedList do
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tSortedList[i]}, SkuGenericMenuItem)
         tNewMenuEntry.OnEnter = function(self, aValue, aName)
            aName = SkuOptions.currentMenuPosition.name
            local tSetting = aSetting
            for i, v in pairs(aqCombatAudioOutputs) do
               if aName == v then
                  C_Timer.After(0.2, function()
                     SkuOptions.Voice:StopOutputEmptyQueue(true, true)
                     C_Timer.After(0.01, function()
                        SkuCoreAqCombatOutput(tSetting.voiceOutput, {unit1 = "party1", unit2 = "party2", action1 = "out", number1 = "1"}, {wait = false, overwrite = true}, tSetting, i)
                        C_Timer.After(1.0, function()
                           SkuOptions.Voice:OutputStringBTtts(SkuOptions.currentMenuPosition.name, false, true, 0.2, true, nil, nil, 2)
                        end)
                     end)
                  end)
               end
            end
         end            
      end
   end  
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Combat menu accessibility toggle (open/read/navigate Sku menu, bags, character,
-- quest log while in combat). Profile-scoped SkuSettings:Sub("SkuCore").combatMenuOpen
-- (registered default ON). Same flag /skucombatmenu toggles.
-- Relocated from the Monitor -> Kampf menu to Einstellungen -> Kampf (built by
-- SkuCore:MenuBuilder in SkuCore/Options.lua); same setting -> saved value intact.
function aqCombat.CombatMenuOpenMenuBuilder(aParentEntry)
   local tNewMenuEntry = SkuOptions:InjectMenuItems(aParentEntry, {L["Sku menu in combat"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.sorting = true
   tNewMenuEntry.isSelect = true
   tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
      if SkuSettings:Sub("SkuCore").combatMenuOpen == true then
         return L["Yes"]
      else
         return L["No"]
      end
   end
   tNewMenuEntry.OnAction = function(self, aValue, aName)
      if aName == L["No"] then
         SkuSettings:Sub("SkuCore").combatMenuOpen = false
      elseif aName == L["Yes"] then
         SkuSettings:Sub("SkuCore").combatMenuOpen = true
      end
   end
   tNewMenuEntry.BuildChildren = function(self)
      SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
      SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function aqCombat:aqCombatMenuBuilder()
   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Enabled"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.sorting = true
   tNewMenuEntry.isSelect = true
   tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
      if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.enabled == true then
         return L["Yes"]
      else
         return L["No"]
      end
   end
   tNewMenuEntry.OnAction = function(self, aValue, aName)
      if aName == L["No"] then
         SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.enabled = false
      elseif aName == L["Yes"] then
         SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.enabled = true
      end
   end
   tNewMenuEntry.BuildChildren = function(self)
      SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
      SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
   end

   ----
   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Voice"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.sorting = true
   tNewMenuEntry.isSelect = true
   tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
      return aqCombatVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.voice]
   end
   tNewMenuEntry.OnAction = function(self, aValue, aName)
      for x = 1, #aqCombatVoices do
         if aqCombatVoices[x] == aName then
            SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.voice = x
         end
      end
   end
   tNewMenuEntry.BuildChildren = function(self)
      for x = 1, #aqCombatVoices do
         SkuOptions:InjectMenuItems(self, {aqCombatVoices[x]}, SkuGenericMenuItem)
      end
   end

   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Notification volume"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.sorting = true
   tNewMenuEntry.isSelect = true
   tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
      if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.notificationVolume == 1 then
         return L["Low"]
      else
         return L["High"]
      end
   end
   tNewMenuEntry.OnAction = function(self, aValue, aName)
      if aName == L["Low"] then
         SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.notificationVolume = 1
      elseif aName == L["High"] then
         SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.notificationVolume = 2
      end
   end
   tNewMenuEntry.BuildChildren = function(self)
      SkuOptions:InjectMenuItems(self, {L["Low"]}, SkuGenericMenuItem)
      SkuOptions:InjectMenuItems(self, {L["High"]}, SkuGenericMenuItem)
   end

   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Voice volume"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.sorting = true
   tNewMenuEntry.isSelect = true
   tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
      if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.voiceVolume == 1 then
         return L["Low"]
      else
         return L["High"]
      end
   end
   tNewMenuEntry.OnAction = function(self, aValue, aName)
      if aName == L["Low"] then
         SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.voiceVolume = 1
      elseif aName == L["High"] then
         SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.voiceVolume = 2
      end
   end
   tNewMenuEntry.BuildChildren = function(self)
      SkuOptions:InjectMenuItems(self, {L["Low"]}, SkuGenericMenuItem)
      SkuOptions:InjectMenuItems(self, {L["High"]}, SkuGenericMenuItem)
   end

   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Only unit numbers"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.sorting = true
   tNewMenuEntry.isSelect = true
   tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
      if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.numberOnly == true then
         return L["Yes"]
      else
         return L["No"]
      end
   end
   tNewMenuEntry.OnAction = function(self, aValue, aName)
      if aName == L["No"] then
         SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.numberOnly = false
      elseif aName == L["Yes"] then
         SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.numberOnly = true
      end
   end
   tNewMenuEntry.BuildChildren = function(self)
      SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
      SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
   end



   ----
   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Hostile"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.BuildChildren = function(self)
      ----
      local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["ignore non-elite"]}, SkuGenericMenuItem)
      tNewMenuEntry.dynamic = true
      tNewMenuEntry.sorting = true
      tNewMenuEntry.isSelect = true
      tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
         if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.ignoreNonElite == true then
            return L["Yes"]
         else
            return L["No"]
         end
      end
      tNewMenuEntry.OnAction = function(self, aValue, aName)
         if aName == L["No"] then
            SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.ignoreNonElite = false
         elseif aName == L["Yes"] then
            SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.ignoreNonElite = true
         end
      end
      tNewMenuEntry.BuildChildren = function(self)
         SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
         SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
      end      

      ----
      local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Threat"]}, SkuGenericMenuItem)
      tNewMenuEntry.dynamic = true
      tNewMenuEntry.BuildChildren = function(self)
         ---
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Output target of target on target change"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.sorting = true
         tNewMenuEntry.BuildChildren = function(self)
            local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Setting"]}, SkuGenericMenuItem)
            tNewMenuEntry.dynamic = true
            tNewMenuEntry.isSelect = true
            tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
               if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatOutputTot.value == 1 then
                  return L["Never"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatOutputTot.value == 2 then
                  return L["Always"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatOutputTot.value == 3 then
                  return L["If target of target isn't you"]
               end
            end
            tNewMenuEntry.OnAction = function(self, aValue, aName)
               if aName == L["Never"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatOutputTot.value = 1
               elseif aName == L["Always"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatOutputTot.value = 2
               elseif aName == L["If target of target isn't you"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatOutputTot.value = 3
               end
            end
            tNewMenuEntry.BuildChildren = function(self)
               SkuOptions:InjectMenuItems(self, {L["Never"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["Always"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["If target of target isn't you"]}, SkuGenericMenuItem)
            end     
            tSoundMenuBuilder(self, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatOutputTot)
         end

         ---
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Threat warning if you are not first place (not tanking) and your threat percentage is higher than"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
         tNewMenuEntry.BuildChildren = function(self)
            local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Setting"]}, SkuGenericMenuItem)
            tNewMenuEntry.dynamic = true
            tNewMenuEntry.sorting = true
            tNewMenuEntry.isSelect = true
            tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
               if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatWarningNotFirstHigherThan.value == 0 then
                  return L["Off"]
               else
                  return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatWarningNotFirstHigherThan.value
               end
            end
            tNewMenuEntry.OnAction = function(self, aValue, aName)
               if tonumber(aName) then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatWarningNotFirstHigherThan.value = tonumber(aName)
               else
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatWarningNotFirstHigherThan.value = 0
               end
            end
            tNewMenuEntry.BuildChildren = function(self)
               SkuOptions:InjectMenuItems(self, {L["Off"]}, SkuGenericMenuItem)
               for x = 1, 150 do
                  SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
               end
            end
            tSoundMenuBuilder(self, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatWarningNotFirstHigherThan)
         end

         ---
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Threat warning if you are first place (tanking) and second place threat percentage is higher than"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
         tNewMenuEntry.BuildChildren = function(self)
            local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Setting"]}, SkuGenericMenuItem)
            tNewMenuEntry.dynamic = true
            tNewMenuEntry.sorting = true
            tNewMenuEntry.isSelect = true
            tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
               if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatWarningIsFirstSecondHigherThan.value == 0 then
                  return L["Off"]
               else
                  return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatWarningIsFirstSecondHigherThan.value
               end
            end
            tNewMenuEntry.OnAction = function(self, aValue, aName)
               if tonumber(aName) then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatWarningIsFirstSecondHigherThan.value = tonumber(aName)
               else
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatWarningIsFirstSecondHigherThan.value = 0
               end
            end
            tNewMenuEntry.BuildChildren = function(self)
               SkuOptions:InjectMenuItems(self, {L["Off"]}, SkuGenericMenuItem)
               for x = 1, 150 do
                  SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
               end
            end   
            tSoundMenuBuilder(self, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatWarningIsFirstSecondHigherThan)
         end

         ---
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Theat warning repeating interval (0 is once)"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.sorting = true
         tNewMenuEntry.isSelect = true
         tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
            return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatWarningInterval
         end
         tNewMenuEntry.OnAction = function(self, aValue, aName)
            SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.threatWarningInterval = tonumber(aName)
         end
         tNewMenuEntry.BuildChildren = function(self)
            for x = 0, 30 do
               SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
            end
         end         

         ----
			local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Warning if your target is switching from you"]}, SkuGenericMenuItem)
			tNewSubMenuEntry.dynamic = true
         tNewSubMenuEntry.sorting = true
         tNewSubMenuEntry.BuildChildren = function(self)
            local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Setting"]}, SkuGenericMenuItem)
            tNewSubMenuEntry.dynamic = true
            tNewSubMenuEntry.isSelect = true
            tNewSubMenuEntry.GetCurrentValue = function(self, aValue, aName)
               if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.warnIfTargetSwitchingToParty.value == true then
                  return L["On"]
               else
                  return L["Off"]
               end
            end
            tNewSubMenuEntry.OnAction = function(self, aValue, aName)
               if aName == L["Off"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.warnIfTargetSwitchingToParty.value = false
               elseif aName == L["On"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.warnIfTargetSwitchingToParty.value = true
               end
            end
            tNewSubMenuEntry.BuildChildren = function(self)
               SkuOptions:InjectMenuItems(self, {L["Off"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["On"]}, SkuGenericMenuItem)
            end

			   tSoundMenuBuilder(self, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.warnIfTargetSwitchingToParty)
         end

         ----
			local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Warning if your target is switching to you"]}, SkuGenericMenuItem)
			tNewSubMenuEntry.dynamic = true
         tNewSubMenuEntry.sorting = true
         tNewSubMenuEntry.BuildChildren = function(self)
            local tNewSubMenuEntry = SkuOptions:InjectMenuItems(self, {L["Setting"]}, SkuGenericMenuItem)
            tNewSubMenuEntry.dynamic = true
            tNewSubMenuEntry.isSelect = true
            tNewSubMenuEntry.GetCurrentValue = function(self, aValue, aName)
               if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.warnIfTargetSwitchingToYou.value == true then
                  return L["On"]
               else
                  return L["Off"]
               end
            end
            tNewSubMenuEntry.OnAction = function(self, aValue, aName)
               if aName == L["Off"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.warnIfTargetSwitchingToYou.value = false
               elseif aName == L["On"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.warnIfTargetSwitchingToYou.value = true
               end
            end
            tNewSubMenuEntry.BuildChildren = function(self)
               SkuOptions:InjectMenuItems(self, {L["Off"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["On"]}, SkuGenericMenuItem)
            end

			   tSoundMenuBuilder(self, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.warnIfTargetSwitchingToYou)
         end         
      end

      ----
      local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Casting"]}, SkuGenericMenuItem)
      tNewMenuEntry.dynamic = true
      tNewMenuEntry.BuildChildren = function(self)
         ---
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Output your target casting"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.sorting = true
         tNewMenuEntry.BuildChildren = function(self)
            local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Setting"]}, SkuGenericMenuItem)
            tNewMenuEntry.dynamic = true
            tNewMenuEntry.isSelect = true
            tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
               if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.yourTargetCasting.value == 1 then
                  return L["Off"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.yourTargetCasting.value == 2 then
                  return L["If cast target is you"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.yourTargetCasting.value == 3 then
                  return L["If cast target is any party member"]
               end
            end
            tNewMenuEntry.OnAction = function(self, aValue, aName)
               if aName == L["Off"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.yourTargetCasting.value = 1
               elseif aName == L["If cast target is you"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.yourTargetCasting.value = 2
               elseif aName == L["If cast target is any party member"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.yourTargetCasting.value = 3
               end
            end
            tNewMenuEntry.BuildChildren = function(self)
               SkuOptions:InjectMenuItems(self, {L["Off"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["If cast target is you"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["If cast target is any party member"]}, SkuGenericMenuItem)
            end     
            tSoundMenuBuilder(self, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.yourTargetCasting)
         end
         
         ---
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Output all enemies casting"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.sorting = true
         tNewMenuEntry.BuildChildren = function(self)
            local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Setting"]}, SkuGenericMenuItem)
            tNewMenuEntry.dynamic = true
            tNewMenuEntry.isSelect = true
            tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
               if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.allEnemiesCasting.value == 1 then
                  return L["Off"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.allEnemiesCasting.value == 2 then
                  return L["Only in combat"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.allEnemiesCasting.value == 3 then
                  return L["All"]
               end
            end
            tNewMenuEntry.OnAction = function(self, aValue, aName)
               if aName == L["Off"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.allEnemiesCasting.value = 1
               elseif aName == L["Only in combat"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.allEnemiesCasting.value = 2
               elseif aName == L["All"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.allEnemiesCasting.value = 3
               end
            end
            tNewMenuEntry.BuildChildren = function(self)
               SkuOptions:InjectMenuItems(self, {L["Off"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["Only in combat"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["All"]}, SkuGenericMenuItem)
            end     
            tSoundMenuBuilder(self, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.allEnemiesCasting)
         end

         ---
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Minimum cast time"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.sorting = true
         tNewMenuEntry.isSelect = true
         tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
            return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.minimumCastDuration
         end
         tNewMenuEntry.OnAction = function(self, aValue, aName)
            SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.minimumCastDuration = tonumber(aName)
         end
         tNewMenuEntry.BuildChildren = function(self)
            for x = 0, 30 do
               SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
            end
         end

         ---
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Nur unterbrechbare Zauber ansagen"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.sorting = true
         tNewMenuEntry.isSelect = true
         tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
            if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.onlyInterruptibleCasts == true then
               return L["On"]
            else
               return L["Off"]
            end
         end
         tNewMenuEntry.OnAction = function(self, aValue, aName)
            if aName == L["Off"] then
               SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.onlyInterruptibleCasts = false
            elseif aName == L["On"] then
               SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.onlyInterruptibleCasts = true
            end
         end
         tNewMenuEntry.BuildChildren = function(self)
            SkuOptions:InjectMenuItems(self, {L["Off"]}, SkuGenericMenuItem)
            SkuOptions:InjectMenuItems(self, {L["On"]}, SkuGenericMenuItem)
         end

         ---
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Unterbrechungen ansagen"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.sorting = true
         tNewMenuEntry.isSelect = true
         tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
            if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.outputInterrupts == true then
               return L["On"]
            else
               return L["Off"]
            end
         end
         tNewMenuEntry.OnAction = function(self, aValue, aName)
            if aName == L["Off"] then
               SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.outputInterrupts = false
            elseif aName == L["On"] then
               SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.outputInterrupts = true
            end
         end
         tNewMenuEntry.BuildChildren = function(self)
            SkuOptions:InjectMenuItems(self, {L["Off"]}, SkuGenericMenuItem)
            SkuOptions:InjectMenuItems(self, {L["On"]}, SkuGenericMenuItem)
         end
      end

      ----
      local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Deaths"]}, SkuGenericMenuItem)
      tNewMenuEntry.dynamic = true
      tNewMenuEntry.BuildChildren = function(self)
         ----
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["ignore dead units not in combat"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.sorting = true
         tNewMenuEntry.isSelect = true
         tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
            if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.deathsIgnoreUnitsNotInCombat == true then
               return L["Yes"]
            else
               return L["No"]
            end
         end
         tNewMenuEntry.OnAction = function(self, aValue, aName)
            if aName == L["No"] then
               SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.deathsIgnoreUnitsNotInCombat = false
            elseif aName == L["Yes"] then
               SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.deathsIgnoreUnitsNotInCombat = true
            end
         end
         tNewMenuEntry.BuildChildren = function(self)
            SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
            SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
         end  

         ---
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Output dead units"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.sorting = true
         tNewMenuEntry.BuildChildren = function(self)
            local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Setting"]}, SkuGenericMenuItem)
            tNewMenuEntry.dynamic = true
            tNewMenuEntry.isSelect = true
            tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
               if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.outputDeadUnits.value == 1 then
                  return L["Never"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.outputDeadUnits.value == 2 then
                  return L["Always"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.outputDeadUnits.value == 3 then
                  return L["If unit was attacking you"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.outputDeadUnits.value == 4 then
                  return L["If unit was attacking any party member"]
               end
            end
            tNewMenuEntry.OnAction = function(self, aValue, aName)
               if aName == L["Never"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.outputDeadUnits.value = 1
               elseif aName == L["Always"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.outputDeadUnits.value = 2
               elseif aName == L["If unit was attacking you"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.outputDeadUnits.value = 3
               elseif aName == L["If unit was attacking any party member"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.outputDeadUnits.value = 4
               end
            end
            tNewMenuEntry.BuildChildren = function(self)
               SkuOptions:InjectMenuItems(self, {L["Never"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["Always"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["If unit was attacking you"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["If unit was attacking any party member"]}, SkuGenericMenuItem)
            end     
            tSoundMenuBuilder(self, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.outputDeadUnits)
         end         
      end         

      ----
      local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Units in combat"]}, SkuGenericMenuItem)
      tNewMenuEntry.dynamic = true
      tNewMenuEntry.BuildChildren = function(self)
         ---
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Announce enemies entering combat"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.sorting = true
         tNewMenuEntry.BuildChildren = function(self)
            local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Setting"]}, SkuGenericMenuItem)
            tNewMenuEntry.dynamic = true
            tNewMenuEntry.isSelect = true
            tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
               if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.unitsAddedToCombat.value == 1 then
                  return L["Off"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.unitsAddedToCombat.value == 2 then
                  return L["All enemies"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.unitsAddedToCombat.value == 3 then
                  return L["Enemies attacking party or you"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.unitsAddedToCombat.value == 4 then
                  return L["Enemies attacking you"]
               end
            end
            tNewMenuEntry.OnAction = function(self, aValue, aName)
               if aName == L["Off"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.unitsAddedToCombat.value = 1
               elseif aName == L["All enemies"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.unitsAddedToCombat.value = 2
               elseif aName == L["Enemies attacking party or you"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.unitsAddedToCombat.value = 3
               elseif aName == L["Enemies attacking you"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.unitsAddedToCombat.value = 4
               end
            end
            tNewMenuEntry.BuildChildren = function(self)
               SkuOptions:InjectMenuItems(self, {L["Off"]}, SkuGenericMenuItem)
               --SkuOptions:InjectMenuItems(self, {L["All enemies"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["Enemies attacking party or you"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["Enemies attacking you"]}, SkuGenericMenuItem)
            end     
            tSoundMenuBuilder(self, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.unitsAddedToCombat)
         end   

         ---
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Announce enemies leaving combat"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.sorting = true
         tNewMenuEntry.BuildChildren = function(self)
            local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Setting"]}, SkuGenericMenuItem)
            tNewMenuEntry.dynamic = true
            tNewMenuEntry.isSelect = true
            tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
               if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.unitsLeavingCombat.value == 1 then
                  return L["Off"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.unitsLeavingCombat.value == 2 then
                  return L["All enemies"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.unitsLeavingCombat.value == 3 then
                  return L["Enemies attacking party or you"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.unitsLeavingCombat.value == 4 then
                  return L["Enemies attacking you"]
               end
            end
            tNewMenuEntry.OnAction = function(self, aValue, aName)
               if aName == L["Off"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.unitsLeavingCombat.value = 1
               elseif aName == L["All enemies"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.unitsLeavingCombat.value = 2
               elseif aName == L["Enemies attacking party or you"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.unitsLeavingCombat.value = 3
               elseif aName == L["Enemies attacking you"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.unitsLeavingCombat.value = 4
               end
            end
            tNewMenuEntry.BuildChildren = function(self)
               SkuOptions:InjectMenuItems(self, {L["Off"]}, SkuGenericMenuItem)
               --SkuOptions:InjectMenuItems(self, {L["All enemies"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["Enemies attacking party or you"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["Enemies attacking you"]}, SkuGenericMenuItem)
            end     
            tSoundMenuBuilder(self, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.unitsLeavingCombat)
         end            

         ---
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Announce relative number of enemies in combat"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.sorting = true
         tNewMenuEntry.BuildChildren = function(self)
            local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Setting"]}, SkuGenericMenuItem)
            tNewMenuEntry.dynamic = true
            tNewMenuEntry.isSelect = true
            tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
               if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.relativeNumberUnitsInCombat.value == 1 then
                  return L["Off"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.relativeNumberUnitsInCombat.value == 2 then
                  return L["All enemies"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.relativeNumberUnitsInCombat.value == 3 then
                  return L["Enemies attacking party or you"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.relativeNumberUnitsInCombat.value == 4 then
                  return L["Enemies attacking you"]
               end
            end
            tNewMenuEntry.OnAction = function(self, aValue, aName)
               if aName == L["Off"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.relativeNumberUnitsInCombat.value = 1
               elseif aName == L["All enemies"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.relativeNumberUnitsInCombat.value = 2
               elseif aName == L["Enemies attacking party or you"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.relativeNumberUnitsInCombat.value = 3
               elseif aName == L["Enemies attacking you"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.relativeNumberUnitsInCombat.value = 4
               end
            end
            tNewMenuEntry.BuildChildren = function(self)
               SkuOptions:InjectMenuItems(self, {L["Off"]}, SkuGenericMenuItem)
               --SkuOptions:InjectMenuItems(self, {L["All enemies"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["Enemies attacking party or you"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["Enemies attacking you"]}, SkuGenericMenuItem)
            end     
            tSoundMenuBuilder(self, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.relativeNumberUnitsInCombat)
         end          
         
         --[[
         ----
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Announce only numbers for entering or leaving combat notifications"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.sorting = true
         tNewMenuEntry.isSelect = true
         tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
            if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.shortUnitsAddedOrLeavingToCombatMessages == true then
               return L["Yes"]
            else
               return L["No"]
            end
         end
         tNewMenuEntry.OnAction = function(self, aValue, aName)
            if aName == L["No"] then
               SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.shortUnitsAddedOrLeavingToCombatMessages = false
            elseif aName == L["Yes"] then
               SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.hostile.shortUnitsAddedOrLeavingToCombatMessages = true
            end
         end
         tNewMenuEntry.BuildChildren = function(self)
            SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
            SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
         end               
         ]]

      end      
   end
   
   ----
   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Friendly"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.BuildChildren = function(self)
      ----
      local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Announce deaths"]}, SkuGenericMenuItem)
      tNewMenuEntry.dynamic = true
      tNewMenuEntry.sorting = true
      tNewMenuEntry.BuildChildren = function(self)
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Setting"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.isSelect = true
         tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
            if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.partyDead.value == false then
               return L["Off"]
            elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.partyDead.value == true then
               return L["On"]
            end
         end
         tNewMenuEntry.OnAction = function(self, aValue, aName)
            if aName == L["Off"] then
               SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.partyDead.value = false
            elseif aName == L["On"] then
               SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.partyDead.value = true
            end
         end
         tNewMenuEntry.BuildChildren = function(self)
            SkuOptions:InjectMenuItems(self, {L["Off"]}, SkuGenericMenuItem)
            SkuOptions:InjectMenuItems(self, {L["On"]}, SkuGenericMenuItem)
         end     
         tSoundMenuBuilder(self, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.partyDead)
      end

      ----
      local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Count deaths up"]}, SkuGenericMenuItem)
      tNewMenuEntry.dynamic = true
      tNewMenuEntry.sorting = true
      tNewMenuEntry.BuildChildren = function(self)
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Setting"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.isSelect = true
         tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
            if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.partyDeadCount.value == false then
               return L["Off"]
            elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.partyDeadCount.value == true then
               return L["On"]
            end
         end
         tNewMenuEntry.OnAction = function(self, aValue, aName)
            if aName == L["Off"] then
               SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.partyDeadCount.value = false
            elseif aName == L["On"] then
               SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.partyDeadCount.value = true
            end
         end
         tNewMenuEntry.BuildChildren = function(self)
            SkuOptions:InjectMenuItems(self, {L["Off"]}, SkuGenericMenuItem)
            SkuOptions:InjectMenuItems(self, {L["On"]}, SkuGenericMenuItem)
         end     
         tSoundMenuBuilder(self, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.partyDeadCount)
      end

      local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Ignore dead party pets"]}, SkuGenericMenuItem)
      tNewMenuEntry.dynamic = true
      tNewMenuEntry.sorting = true
      tNewMenuEntry.isSelect = true
      tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
         if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.ignoreDeadPartyPets == true then
            return L["Yes"]
         else
            return L["No"]
         end
      end
      tNewMenuEntry.OnAction = function(self, aValue, aName)
         if aName == L["No"] then
            SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.ignoreDeadPartyPets = false
         elseif aName == L["Yes"] then
            SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.ignoreDeadPartyPets = true
         end
      end
      tNewMenuEntry.BuildChildren = function(self)
         SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
         SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
      end

      ----
      local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Distance to party member"]}, SkuGenericMenuItem)
      tNewMenuEntry.dynamic = true
      tNewMenuEntry.BuildChildren = function(self)
         ----
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Announce out of range"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.BuildChildren = function(self)
            local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Setting"]}, SkuGenericMenuItem)
            tNewMenuEntry.dynamic = true
            tNewMenuEntry.isSelect = true
            tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
               if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.outOfRangeEnabled.value == false then
                  return L["Off"]
               elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.outOfRangeEnabled.value == true then
                  return L["On"]
               end
            end
            tNewMenuEntry.OnAction = function(self, aValue, aName)
               if aName == L["Off"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.outOfRangeEnabled.value = false
               elseif aName == L["On"] then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.outOfRangeEnabled.value = true
               end
            end
            tNewMenuEntry.BuildChildren = function(self)
               SkuOptions:InjectMenuItems(self, {L["Off"]}, SkuGenericMenuItem)
               SkuOptions:InjectMenuItems(self, {L["On"]}, SkuGenericMenuItem)
            end     
            tSoundMenuBuilder(self, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.outOfRangeEnabled)
         end

         ---
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Out of range at"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.sorting = true
         tNewMenuEntry.isSelect = true
         tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
            return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.oorAt
         end
         tNewMenuEntry.OnAction = function(self, aValue, aName)
            SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.oorAt = tonumber(aName)
         end
         tNewMenuEntry.BuildChildren = function(self)
            for x = 1, 100 do
               SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
            end
         end

         ---
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Set unit for out of range"].." ("..L["current"]..": "..(SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.oorUnitName or L["Nothing selected"])..")"}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.isSelect = true
         tNewMenuEntry.OnAction = function(self, aValue, aName)
            if aName == L["Current target"] then
               if UnitName("target") and UnitIsPlayer("target") then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.oorUnitName = UnitName("target")
               end
            elseif aName == L["Clear"] then
               SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.oorUnitName = L["Nothing selected"]
            elseif aName == L["Current focus target"] then
               if UnitName("focus") and UnitIsPlayer("focus") then
                  SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.oorUnitName = UnitName("focus")
               end
            elseif sfind(aName, L["Party"]) then
               local tName = strsplit(";", aName)
               SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.oorUnitName = tName
            elseif sfind(aName, L["Raid"]) then
               local tName = strsplit(";", aName)
               SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.oorUnitName = tName
            end
				C_Timer.After(0.001, function()
					SkuOptions.currentMenuPosition:OnUpdate(SkuOptions.currentMenuPosition)
				end)				

         end
         tNewMenuEntry.BuildChildren = function(self)
            SkuOptions:InjectMenuItems(self, {L["Clear"]}, SkuGenericMenuItem)
            SkuOptions:InjectMenuItems(self, {L["Current target"]}, SkuGenericMenuItem)
            SkuOptions:InjectMenuItems(self, {L["Current focus target"]}, SkuGenericMenuItem)
            for x = 1, 4 do
               if UnitName("party"..x) then
                  SkuOptions:InjectMenuItems(self, {UnitName("party"..x)..";"..L["Party"].." "..x}, SkuGenericMenuItem)
               end
            end
            for x = 1, 40 do
               if UnitName("raid"..x) then
                  SkuOptions:InjectMenuItems(self, {UnitName("raid"..x)..";"..L["Raid"].." "..x}, SkuGenericMenuItem)
               end
            end
         end     
         
         ---
         local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Repeating interval (0 is once)"]}, SkuGenericMenuItem)
         tNewMenuEntry.dynamic = true
         tNewMenuEntry.sorting = true
         tNewMenuEntry.isSelect = true
         tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
            return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.oorInterval
         end
         tNewMenuEntry.OnAction = function(self, aValue, aName)
            SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.oorInterval = tonumber(aName)
         end
         tNewMenuEntry.BuildChildren = function(self)
            for x = 0, 30 do
               SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
            end
         end
      end
   end

   --Update rate: legacy pre-optimization performance lever, rarely needed nowadays,
   --so it sits at the very end of the menu
   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Update rate (performance)"]}, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.sorting = true
   tNewMenuEntry.isSelect = true
   tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
      return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.updateRate
   end
   tNewMenuEntry.OnAction = function(self, aValue, aName)
      SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.updateRate = tonumber(aName)
      tCurrentUpdateRate = (21 - SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.updateRate)
   end
   tNewMenuEntry.BuildChildren = function(self)
      for x = 1, 20 do
         SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
      end
   end
end