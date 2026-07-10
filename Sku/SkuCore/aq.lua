---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME, MODULE_PART = "SkuCore", "aq"
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- W4 Phase D: Aq (the health & power monitor — the largest SkuCore feature) is now
-- a real AceAddon SUBMODULE of SkuCore, so it can be turned on/off at runtime
-- (OnEnable/OnDisable), mirroring the JunkAndRepair pilot. Every existing
-- SkuCore:* method and SkuCore.* state stays exactly where it is so external
-- callers (keybinds, the menu builder, SkuAuras) keep working; the module only
-- owns the LIFECYCLE:
--   * OnInitialize builds SkuCore.Monitor.UnitNumbersIndexedRaid UNCONDITIONALLY
--     (AceAddon runs OnInitialize even for a module that will be disabled),
--     because SkuAuras READS that table even while Aq is off.
--   * OnEnable  arms the feature (AqCreateControlFrame OnUpdate + 7 events + 6
--     dispatcher callbacks via Aq:AqOnInitialize, then the settings schema
--     migration/defaults via Aq:AqOnLogin).
--   * OnDisable disarms it: unregister those events + dispatcher callbacks and
--     stop the OnUpdate, so a disabled monitor genuinely does nothing.
-- AceAddon auto-enables the module at SkuCore enable (≈ PLAYER_LOGIN) and again
-- on every /reload, replacing the old explicit AqOnInitialize/AqOnLogin calls in
-- Core.lua. SkuAuras coupling is handled defensively (RoleCheckerGetUnitRole
-- calls are guarded; the existing nil-role handling stands).
-- W4 Phase E (namespace extraction): every former `function SkuCore:Monitor*`/
-- `Aq*`/`UNIT_*`/`MIRROR_*` method now lives on this module table
-- (`function Aq:Method`); the published handle `SkuCore.Aq` IS this table, so
-- external callers use `SkuCore.Aq:Method`. The module mixes in AceEvent-3.0 and
-- owns its 7 AceEvent registrations (MIRROR_TIMER_*, UNIT_HEALTH/AURA/POWER_*);
-- the 6 group/roster dispatcher callbacks stay on SkuDispatcher (dot-ref values).
-- Feature STATE stays on `SkuCore.<field>` — notably `SkuCore.Monitor` (the combat
-- monitor index, read by SkuAuras) keeps its location untouched, so SkuAuras needs
-- no repoint; moving state onto a service is a later pass.
local Aq = SkuCore:NewModule("Aq", "AceEvent-3.0")
SkuCore.Aq = Aq   -- keep the published handle

-- Make this feature user-toggleable (Features menu + persisted on/off).
SkuCore:RegisterToggleableModule("Aq", function()
	return Sku.deEn("Lebens- & Energiemonitor", "Health & power monitor")
end)

-- Frame handle for the AqCreateControlFrame OnUpdate driver, so OnDisable can stop it.
local AqControlFrame

SkuCore.aq = {}
SkuCore.aq.mirrorBars = {}

local tVoices = {
	[1] = {name = "Justin", path = "jus"},
	[2] = {name = "Kimberly", path = "kim"},
	[3] = {name = "Kevin", path = "kev"},
}

local tOutputStyles = {
	[1] = L["long"],
	[2] = L["short"],
}

local tPowerTypes = {
	["NOTHING"] = {name = L["nichts"], number = -1},
	["MANA"] = {name = L["MANA"], number = 0},
	["RAGE"] = {name = L["RAGE"], number = 1},
	["ENERGY"] = {name = L["ENERGY"], number = 3},
	["RUNIC_POWER"] = {name = L["RUNIC_POWER"], number = 6},
}

local tDebuffTypes = {
	["magic"] = L["magic"],
	["curse"] = L["curse"],
	["poison"] = L["poison"],
	["disease"] = L["disease"],
}
local tDebuffTypesShort = {
	["magic"] = L["magic_short"],
	["curse"] = L["curse_short"],
	["poison"] = L["poison_short"],
	["disease"] = L["disease_short"],
}
local tRoles = {
	[1] = L["Tanks"],
	[2] = L["Healers"],
	[3] = L["Damagers"],
	[4] = L["No role"],
	[5] = L["Main Tank"],
}

local tUnitNumbers = {
	["player"] = 1,
	["party1"] = 2,
	["party2"] = 3,
	["party3"] = 4,
	["party4"] = 5,
}
local tUnitNumbersIndexed = {
	[1] = "player",
	[2] = "party1",
	[3] = "party2",
	[4] = "party3",
	[5] = "party4",
}

local tUnitNumbersRaid = {}
for x = 1, MAX_RAID_MEMBERS do
	tUnitNumbersRaid["raid"..x] = x
end

SkuCore.Monitor = SkuCore.Monitor or {}
SkuCore.Monitor.UnitNumbersIndexedRaid = {}
for x = 1, MAX_RAID_MEMBERS do
	SkuCore.Monitor.UnitNumbersIndexedRaid[x] = "raid"..x
end

tDTRaidRoster = {}

local tEventOutputFilters = {
	minAbsoluteSincePrevEvent = {name = L["minimum percent difference since previous event"], values = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,20,22,25,30}, defaults = {5, 10, 20, 30, 5}, id = 1, },
	minStepsSincePrevEvent = {name = L["minimum steps difference since previous event"], values = {0,1,2,3,4,5,6,7,}, defaults = {0, 1, 2, 3, 0}, id = 2, },
}

local tAuraRepo = {}
local ttimeMonParty2Queue = {}
local ttimeMonParty2QueueCurrentTime = 0
local ttimeMonParty2QueueDefaultOutputLength = 0.2

local ttimeMonRaid2Queue = {}
local ttimeMonRaid2QueueCurrentTime = 0
local ttimeMonRaid2QueueDefaultOutputLength = 0.2

---------------------------------------------------------------------------------------------------------------------------------------
local function tHealth2QueueAdd(aQueue, aBranch, aDefaultLen, aUnitNumber, aVolume, aPitch, aLength, aRole, aHealthAbsoluteValue, aIgnorePrio)
	aLength = aLength or aDefaultLen

	if #aQueue > 0 then
		if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][aBranch].health2.prioOutput[aRole] == true and aIgnorePrio ~= true then
			local tFound
			local tFoundVol
			for x = 1, #aQueue do
				if aQueue[x].tUnitNumber == aUnitNumber then
					tFound = x
					tFoundVol = aQueue[x].tVolume
				end
			end
			if tFound then
				table.remove(aQueue, tFound)
			end
			if tFoundVol and tFoundVol > aVolume then
				aVolume = tFoundVol
			end
			if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][aBranch].health2.addDeadOn0Percent == true and aHealthAbsoluteValue == 0 then
				table.insert(aQueue, 1, {tUnitNumber = "dead", tVolume = aVolume, tPitch = 0, lenght = 0.5,})
			elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][aBranch].health2.addSoundOn100Percent == true and aHealthAbsoluteValue == 100 then
				table.insert(aQueue, 1, {tUnitNumber = "full", tVolume = aVolume, tPitch = 0, lenght = 0.15,})
			end
			table.insert(aQueue, 1, {tUnitNumber = aUnitNumber, tVolume = aVolume, tPitch = aPitch, lenght = aLength,})
			return
		else
			for x = 1, #aQueue do
				if aQueue[x].tUnitNumber == aUnitNumber then
					aQueue[x].tPitch = aPitch	
					if aQueue[x].tVolume < aVolume	then
						aQueue[x].tVolume = aVolume
					end
					aQueue[x].lenght = aLength
					if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][aBranch].health2.addDeadOn0Percent == true and aHealthAbsoluteValue == 0 then
						table.insert(aQueue, x + 1, {tUnitNumber = "dead", tVolume = aVolume, tPitch = 0, lenght = 0.5,})
					elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][aBranch].health2.addSoundOn100Percent == true and aHealthAbsoluteValue == 100 then
						table.insert(aQueue, x + 1, {tUnitNumber = "full", tVolume = aVolume, tPitch = 0, lenght = 0.15,})
					end
		
					return
				end
			end
		end
	end

	aQueue[#aQueue + 1] = {tUnitNumber = aUnitNumber, tVolume = aVolume, tPitch = aPitch, lenght = aLength,}
	if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][aBranch].health2.addDeadOn0Percent == true and aHealthAbsoluteValue == 0 then
		aQueue[#aQueue + 1] = {tUnitNumber = "dead", tVolume = aVolume, tPitch = 0, lenght = 0.5,}
	elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][aBranch].health2.addSoundOn100Percent == true and aHealthAbsoluteValue == 100 then
		aQueue[#aQueue + 1] = {tUnitNumber = "full", tVolume = aVolume, tPitch = 0, lenght = 0.15,}
	end	
end

local function ttimeMonParty2QueueAdd(aUnitNumber, aVolume, aPitch, aLength, aRole, aHealthAbsoluteValue, aIgnorePrio)
	tHealth2QueueAdd(ttimeMonParty2Queue, "party", ttimeMonParty2QueueDefaultOutputLength, aUnitNumber, aVolume, aPitch, aLength, aRole, aHealthAbsoluteValue, aIgnorePrio)
end


---------------------------------------------------------------------------------------------------------------------------------------
local function monitorPartyHealth2ContiOutput(aForce)
	if aForce == true then
		ttimeMonParty2Queue = {}
		ttimeMonParty2QueueCurrentTime = 0
	end

	for x = 1, #tUnitNumbersIndexed do
		local tIndex, tUnitID = x, tUnitNumbersIndexed[x]
		local tUnitGUID = UnitGUID(tUnitID)
		if tUnitGUID then
			local tRoleID = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.roleAssigments[tUnitNumbers[tUnitID]]
			if tRoleID == 0 then
				tRoleID = (SkuAuras and SkuAuras.RoleCheckerGetUnitRole and (not SkuAuras.IsEnabled or SkuAuras:IsEnabled())) and SkuAuras:RoleCheckerGetUnitRole(tUnitGUID) or nil
			end
			local tHealthAbsoluteValue = math.floor((UnitHealth(tUnitID) / UnitHealthMax(tUnitID)) * 100)
			local tHealthStepsValue = math.floor(tHealthAbsoluteValue / (100 / 15))
			if tHealthStepsValue > 14 then
				tHealthStepsValue = 14
			end
		
			if tRoleID and ((SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.silentOn100and0 == false or (SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.silentOn100and0 == true and tHealthAbsoluteValue ~= 0 and tHealthAbsoluteValue ~= 100)) or aForce== true) then
				if tHealthAbsoluteValue and SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.continouslyStartAt[tRoleID] then
					if tHealthAbsoluteValue <= SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.continouslyStartAt[tRoleID] or aForce== true then
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.prevHealth = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.prevHealth or {
							["player"] = {absolute = 100, steps = 14, lastOutput = 0, },
							["party1"] = {absolute = 100, steps = 14, lastOutput = 0, },
							["party2"] = {absolute = 100, steps = 14, lastOutput = 0, },
							["party3"] = {absolute = 100, steps = 14, lastOutput = 0, },
							["party4"] = {absolute = 100, steps = 14, lastOutput = 0, },
						}

						local tUnitNumber, tVolume, tPitch = tUnitNumbers[tUnitID], SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.continouslyVolume, (((tHealthStepsValue * 5) - 35) * -1)
						if tPitch == 0 then tPitch = 0 end --dnd, we need this in case of -0
						local tAddlSpeedMod = 1
						if aForce then
							tAddlSpeedMod = 0.5
						end
						ttimeMonParty2QueueAdd(tUnitNumber, tVolume, tPitch, (ttimeMonParty2QueueDefaultOutputLength * (SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.outputQueueDelay / 100)) * tAddlSpeedMod, tRoleID, tHealthAbsoluteValue, true)
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function Aq:MonitorPartyHealth2Conti()
	if not Aq:IsEnabled() then return end
	if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.enabled == true then
		monitorPartyHealth2ContiOutput(true)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function GetUnitsRaidSubgroup(aUnitID)
	local tUnitName = UnitName(aUnitID)
	for x = 1, MAX_RAID_MEMBERS do
		local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(x)
		if name == tUnitName then
			return subgroup
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function ttimeMonRaid2QueueAdd(aUnitNumber, aVolume, aPitch, aLength, aRole, aHealthAbsoluteValue, aIgnorePrio, aUnitID)
	--check if subgroup is enabled
	if GetUnitsRaidSubgroup(aUnitID) == nil or SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.unitsAndSubgroupsSelection[L["Subgroup"].." "..GetUnitsRaidSubgroup(aUnitID)] == false then
		return
	end
	--check if mt/ot is enabled
	if aRole == 5 then
		if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.unitsAndSubgroupsSelection[tRoles[aRole]] == false then
			return
		end
	end

	tHealth2QueueAdd(ttimeMonRaid2Queue, "raid", ttimeMonRaid2QueueDefaultOutputLength, aUnitNumber, aVolume, aPitch, aLength, aRole, aHealthAbsoluteValue, aIgnorePrio)
end


---------------------------------------------------------------------------------------------------------------------------------------
local function monitorRaidHealth2ContiOutput(aForce)
	if aForce == true then
		ttimeMonRaid2Queue = {}
		ttimeMonRaid2QueueCurrentTime = 0
	end

	for w = 1, MAX_RAID_MEMBERS do
		for i, v in pairs(tDTRaidRoster) do
			if v == w then


				local tUnitID = i
				local tUnitGUID = UnitGUID(tUnitID)
				if tUnitGUID then
					local tRoleID = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.roleAssigments[tUnitNumbersRaid[tUnitID]]
					if tRoleID == 0 then
						tRoleID = (SkuAuras and SkuAuras.RoleCheckerGetUnitRole and (not SkuAuras.IsEnabled or SkuAuras:IsEnabled())) and SkuAuras:RoleCheckerGetUnitRole(tUnitGUID) or nil
					end
					local tHealthAbsoluteValue = math.floor((UnitHealth(tUnitID) / UnitHealthMax(tUnitID)) * 100)
					local tHealthStepsValue = math.floor(tHealthAbsoluteValue / (100 / 15))
					if tHealthStepsValue > 14 then
						tHealthStepsValue = 14
					end
				
					if tRoleID and ((SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.silentOn100and0 == false or (SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.silentOn100and0 == true and tHealthAbsoluteValue ~= 0 and tHealthAbsoluteValue ~= 100)) or aForce== true) then
						if tHealthAbsoluteValue <= SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.continouslyStartAt[tRoleID] or aForce== true then
							if not SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prevHealth then
								SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prevHealth = {}
								for x = 1, MAX_RAID_MEMBERS do
									SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prevHealth["raid"..x] = {absolute = 100, steps = 14, lastOutput = 0, }
								end
							end
		
							local tUnitNumber, tVolume, tPitch = tUnitNumbersRaid[tUnitID], SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.continouslyVolume, (((tHealthStepsValue * 5) - 35) * -1)
							if tPitch == 0 then tPitch = 0 end --dnd, we need this in case of -0
							local tAddlSpeedMod = 1
							if aForce then
								tAddlSpeedMod = 0.5
							end
							ttimeMonRaid2QueueAdd(tUnitNumber, tVolume, tPitch, (ttimeMonRaid2QueueDefaultOutputLength * (SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.outputQueueDelay / 100)) * tAddlSpeedMod, tRoleID, tHealthAbsoluteValue, true, tUnitID)
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function Aq:MonitorRaidHealth2Conti()
	if not Aq:IsEnabled() then return end
	if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.enabled == true then
		monitorRaidHealth2ContiOutput(true)
	end
end

--------------------------------------------------------------------------------------------------------------------------------------
function Aq:Monitor_PLAYER_ENTERING_WORLD()
	C_Timer.After(5, function()
		Aq:MonitorRaidRosterUpdate()
	end)
	C_Timer.After(15, function()
		Aq:MonitorRaidRosterUpdate()
	end)
	C_Timer.After(25, function()
		Aq:MonitorRaidRosterUpdate()
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------
function Aq:Monitor_PARTY_LEADER_CHANGED()
   dprint("Monitor_PARTY_LEADER_CHANGED", UnitInRaid("player"), UnitInParty("player"))
   if UnitInRaid("player") then
   	Aq:MonitorRaidRosterUpdate()
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function Aq:Monitor_GROUP_FORMED()
   dprint("Monitor_PARTY_LEADER_CHANGED")
   if UnitInRaid("player") then
   	Aq:MonitorRaidRosterUpdate()
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function Aq:Monitor_GROUP_JOINED()
   dprint("Monitor_PARTY_LEADER_CHANGED")
   if UnitInRaid("player") then
   	Aq:MonitorRaidRosterUpdate()
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function Aq:Monitor_GROUP_LEFT()
   dprint("Monitor_PARTY_LEADER_CHANGED")
   if UnitInRaid("player") then
   	Aq:MonitorRaidRosterUpdate()
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function Aq:Monitor_GROUP_ROSTER_UPDATE()
   dprint("Monitor_PARTY_LEADER_CHANGED")
   if UnitInRaid("player") then
   	Aq:MonitorRaidRosterUpdate()
	end
end
---------------------------------------------------------------------------------------------------------------------------------------
function Aq:MonitorRaidRosterUpdate()
	--[[
   if SkuCore.Monitor.enabled == false then
      return
   end
	]]
	if not Aq:IsEnabled() then
		SkuDispatcher:UnregisterEventCallback("PLAYER_REGEN_ENABLED", Aq.MonitorRaidRosterUpdate)
		return
	end

   if SkuCore.inCombat == true then
      SkuDispatcher:RegisterEventCallback("PLAYER_REGEN_ENABLED", Aq.MonitorRaidRosterUpdate, true)
      return
   end
   SkuDispatcher:UnregisterEventCallback("PLAYER_REGEN_ENABLED", Aq.MonitorRaidRosterUpdate)

   if UnitInRaid("player") then
		local tRaidRoster = {}
      local tsubgroupcounter = {}
      for x = 1, MAX_RAID_MEMBERS do
         local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(x)
         if name and subgroup then
            tsubgroupcounter[subgroup] = tsubgroupcounter[subgroup] or 0
            tsubgroupcounter[subgroup] = tsubgroupcounter[subgroup] + 1
            tRaidRoster[name] = ((subgroup - 1) * 5) + tsubgroupcounter[subgroup]
         end
      end

		tDTRaidRoster = {}

      for x = 1, MAX_RAID_MEMBERS do
			local trN = UnitName("raid"..x)
			if trN and tRaidRoster[trN] then
				tDTRaidRoster["raid"..x] = tRaidRoster[trN]
			end
      end

		--[[
		C_Timer.After(1, function()
			if SkuCore.inCombat ~= true then
				print("SkuCore.inCombat", SkuCore.inCombat)
				for x = 1, 10 do 
					if _G["CompactRaidGroup"..x] then
						CompactRaidGroup_InitializeForGroup(_G["CompactRaidGroup"..x], x)
					end
				end
			end
		end)
		]]
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
local tHealthMonitorPause = false
local tDebuffMonitorPause = false
local tPowerMonitorPause = false
local tPlayerDebuffsMonitorPause = false
local tPartyDebuffsMonitorPause = false
local tRaidDebuffsMonitorPause = false
local tPrevNumberToUtterance = 10
local tPrevNumberToUtterancePet = 10
local tPrevNumberToUtterancePlPwr = 10
local tPrevHpPer = 100
local tPrevHpDir = false
local tPrevPwrPer = 100
local tPrevPwrDir = false
local tPrevHpPetPer = 100
local tPrevHpPetDir = false

local function AqCreateControlFrame()
   local f = _G["SkuCoreAqControl"] or CreateFrame("Frame", "SkuCoreAqControl", UIParent)
   AqControlFrame = f
   local ttime = 0
   local ttimeMonHp = 0
   local ttimeMonHpPet = 0
   local ttimeMonPwr = 0
	local ttimeMonParty = 0
	local ttimeMonParty2 = 0
	local ttimeMonRaid = 0
	local ttimeMonRaid2 = 0
	local ttimeMonPlayerDebuff = 0
	local ttimeMonPartyDebuff = 0
	local ttimeMonRaidDebuff = 0

   f:SetScript("OnUpdate", function(self, time)
		--party health 2 queue manager

local beginTime = debugprofilestop()




		if #ttimeMonParty2Queue > 0 then
			if ttimeMonParty2QueueCurrentTime <= 0 then
				local tUnitNumber, tVolume, tPitch, tLength = ttimeMonParty2Queue[1].tUnitNumber , ttimeMonParty2Queue[1].tVolume , ttimeMonParty2Queue[1].tPitch , ttimeMonParty2Queue[1].lenght
				ttimeMonParty2QueueCurrentTime = tLength
				Aq:MonitorOutputPartyPercent2(tUnitNumber, tVolume, tPitch)
				table.remove(ttimeMonParty2Queue, 1)
			else
				ttimeMonParty2QueueCurrentTime = ttimeMonParty2QueueCurrentTime - time
			end
		end

		--raid health 2 queue manager
		if #ttimeMonRaid2Queue > 0 then
			if ttimeMonRaid2QueueCurrentTime <= 0 then
				local tUnitNumber, tVolume, tPitch, tLength = ttimeMonRaid2Queue[1].tUnitNumber , ttimeMonRaid2Queue[1].tVolume , ttimeMonRaid2Queue[1].tPitch , ttimeMonRaid2Queue[1].lenght
				ttimeMonRaid2QueueCurrentTime = tLength
				Aq:MonitorOutputRaidPercent2(tUnitNumber, tVolume, tPitch)
				table.remove(ttimeMonRaid2Queue, 1)
			else
				ttimeMonRaid2QueueCurrentTime = ttimeMonRaid2QueueCurrentTime - time
			end
		end

      ttime = ttime + time
      if ttime > 0.05 then
			--mirror bars
			for i, v in pairs(SkuCore.aq.mirrorBars) do
				v.value = GetMirrorTimerProgress(v.name)
				
				local tValue = v.value
				if tValue < 0 then
					tValue = 0
				end
				
				if math.floor(tValue / (v.maxValue / 100)) <= (v.prevStepPct - v.stepPct) then
					v.prevStepPct = math.floor(tValue / (v.maxValue / 100))
					SkuOptions.Voice:OutputStringBTtts(v.label.." "..math.floor(tValue / (v.maxValue / 100)), false, true, 0.2)
				end
			end
			ttime = 0
		end

		if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet] then
			if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.enabled == true then
				ttimeMonHp = ttimeMonHp + time
				if ttimeMonHp > (SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.continouslyTimer) and tHealthMonitorPause == false then
					local health = UnitHealth("player")
					local healthMax = UnitHealthMax("player")
					if healthMax > 0 then
						local healthPer = math.floor((health / healthMax) * 100)
						if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.continouslyStartAt >= 0 and (math.floor(healthPer / 10) <= SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.continouslyStartAt) then
							local tsinglestep = math.floor(100 / SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.steps)
							local tNumberToUtterance = ((math.floor(healthPer / tsinglestep)) * tsinglestep) / 10
			
							tPrevHpDir = healthPer > tPrevHpPer
							local tPrevNumberToUtteranceOutput = tNumberToUtterance
							if tPrevHpDir == false then
								tPrevNumberToUtteranceOutput = tPrevNumberToUtteranceOutput + 1
							end

							tPrevHpPer = healthPer

							if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.silentOn100and0 == false or (tPrevNumberToUtteranceOutput < 10 and tPrevNumberToUtteranceOutput > 0) then
								Aq:MonitorOutputPlayerPercent(tPrevNumberToUtteranceOutput, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.continouslyVolume, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.instancesOnly, tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.voice].path)
							end							
						end
					end
					
					ttimeMonHp = 0

					if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.continouslyTimer == SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.continouslyTimer then
						ttimeMonPwr = 10000000
					end
				end
			end

			if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.enabled == true and UnitName("pet") then
				ttimeMonHpPet = ttimeMonHpPet + time
				if ttimeMonHpPet > (SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.continouslyTimer) and tHealthMonitorPause == false then
					local health = UnitHealth("pet")
					local healthMax = UnitHealthMax("pet")
					local healthPer = math.floor((health / healthMax) * 100)
					if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.continouslyStartAt >= 0 and (math.floor(healthPer / 10) <= SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.continouslyStartAt) then
						local tsinglestep = math.floor(100 / SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.steps)
						local tNumberToUtterance = ((math.floor(healthPer / tsinglestep)) * tsinglestep) / 10

						tPrevHpPetDir = healthPer > tPrevHpPetPer
						local tPrevNumberToUtteranceOutput = tNumberToUtterance
						if tPrevHpPetDir == false then
							tPrevNumberToUtteranceOutput = tPrevNumberToUtteranceOutput + 1
						end

						tPrevHpPetPer = healthPer

						if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.silentOn100and0 == false or (tPrevNumberToUtteranceOutput < 10 and tPrevNumberToUtteranceOutput > 0) then
							Aq:MonitorOutputPlayerPercent(tPrevNumberToUtteranceOutput, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.continouslyVolume, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.instancesOnly, tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.voice].path, "pet")
						end							
					end

					ttimeMonHpPet = 0
				end
			end


			if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.enabled == true then
				ttimeMonPwr = ttimeMonPwr + time
				if ttimeMonPwr > (SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.continouslyTimer) and tPowerMonitorPause == false then
					local power = UnitPower("player", tPowerTypes[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.type].number)
					local powerMax = UnitPowerMax("player", tPowerTypes[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.type].number)
					local pwrPer = math.floor((power / powerMax) * 100)
					if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.continouslyStartAt >= 0 and (math.floor(pwrPer / 10) <= SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.continouslyStartAt) then
						local tsinglestep = math.floor(100 / SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.steps)
						local tNumberToUtterance = ((math.floor(pwrPer / tsinglestep)) * tsinglestep) / 10

						tPrevPwrDir = pwrPer > tPrevPwrPer
						local tPrevNumberToUtteranceOutput = tNumberToUtterance
						if tPrevPwrDir == false then
							tPrevNumberToUtteranceOutput = tPrevNumberToUtteranceOutput + 1
						end

						tPrevPwrPer = pwrPer

						if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.silentOn100and0 == false or (tPrevNumberToUtteranceOutput < 10 and tPrevNumberToUtteranceOutput > 0) then
							C_Timer.After(0.25, function()
								Aq:MonitorOutputPlayerPercent(tPrevNumberToUtteranceOutput, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.continouslyVolume, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.instancesOnly, tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.voice].path)
							end)
						end							
					end
					ttimeMonPwr = 0
				end
			end

			--[=[
			if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.enabled == true then
				ttimeMonParty = ttimeMonParty + time
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.continouslyEnabled == true then
					ttimeMonParty = ttimeMonParty + time
					if ttimeMonParty > (SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.continouslyTimer) then
						local tUtterances = {}

						local tLast = 0
						for x = 1, 4 do
							local health = UnitHealth("party"..x)
							local healthMax = UnitHealthMax("party"..x)
							local healthPer = math.floor((health / healthMax) * 100)
							if healthMax == 0 then
								healthPer = -1
							else
								tLast = x
							end
							tUtterances[x] = healthPer
						end
						if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.includeSelf == true then
							local health = UnitHealth("player")
							local healthMax = UnitHealthMax("player")
							local healthPer = math.floor((health / healthMax) * 100)
							tUtterances[tLast + 1] = healthPer
						else
							tUtterances[tLast + 1] = -1
						end						

						--[[
						-------------------------- party test
						tUtterances = tTestParty
						--------------------------
						]]

						local tAll100 = true
						for x = 1, #tUtterances do
							if tUtterances[x] < 100 and tUtterances[x] ~= -1 then
								tAll100 = false
							end
						end

						if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.silentAtAll100 == false or tAll100 == false then
							Aq:MonitorOutputPartyPercent(tUtterances, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.continouslyVolume, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.instancesOnly, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.continouslySpeed)
						end

						ttimeMonParty = 0
					end
				end
			end
			]=]

			if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.enabled == true then
				ttimeMonPlayerDebuff = ttimeMonPlayerDebuff + time
				if ttimeMonPlayerDebuff > SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.continouslyTimer and tPlayerDebuffsMonitorPause == false then
					if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.continouslyStartAfter > -1 then
						local tUnitGUID = UnitGUID("player")
						if tAuraRepo["player"] and tAuraRepo["player"][tUnitGUID] then
							local tPause = 0
							for i, v in pairs(tDebuffTypes) do
								if tAuraRepo["player"][tUnitGUID][i].start > 0 and tAuraRepo["player"][tUnitGUID][i].count > 0 and (GetTime() - tAuraRepo["player"][tUnitGUID][i].start > SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.continouslyStartAfter) then
									if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.types[i] == true then									
										C_Timer.After(tPause, function()
											Aq:MonitorOutputPlayerStatus({[1] = i}, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.continouslyVolume, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.instancesOnly, tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.voice].path)
										end)
										tPause = tPause + 0.3
									end
								end
							end
						end
					end
					ttimeMonPlayerDebuff = 0
				end
			end

			if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.enabled == true then
				ttimeMonPartyDebuff = ttimeMonPartyDebuff + time
				if ttimeMonPartyDebuff > SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.continouslyTimer and tPartyDebuffsMonitorPause == false then
					if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.continouslyStartAfter > -1 then
						local tUnitIdList = Aq:UnitIsInUnitGroup("party", "player")
						if tUnitIdList then
							local tPause = 0
							for _, tUnitID in pairs(tUnitIdList) do
								local tUnitGUID = UnitGUID(tUnitID)
								if tAuraRepo["party"] and tAuraRepo["party"][tUnitGUID] then
									for i, v in pairs(tDebuffTypes) do
										if tAuraRepo["party"][tUnitGUID][i].start > 0 and tAuraRepo["party"][tUnitGUID][i].count > 0 and (GetTime() - tAuraRepo["party"][tUnitGUID][i].start > SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.continouslyStartAfter) then
											if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.types[i] == true then		
												local tNumber
												if string.sub(tUnitID, 1, 6) == "player" then
													tNumber = 1
												elseif string.sub(tUnitID, 1, 5) == "party" then
													tNumber = tonumber(string.sub(tUnitID, 6))
													if tNumber then
														tNumber = tNumber + 1
													end
												elseif string.sub(tUnitID, 1, 4) == "raid" then
													tNumber = tonumber(string.sub(tUnitID, 5))
													if tNumber then
														tNumber = tNumber + 1
													end
												end
												if tNumber then
													local tTypeString = tDebuffTypesShort[i]
													if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.outputStyle == 1 then
														tTypeString = i
													end
													C_Timer.After(tPause, function()
														if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].global.numberFirst == true then
															Aq:MonitorOutputPlayerStatus({[1] = tNumber, [2] = tTypeString}, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.continouslyVolume, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.instancesOnly, tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.voice].path)
														else
															Aq:MonitorOutputPlayerStatus({[1] = tTypeString, [2] = tNumber}, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.continouslyVolume, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.instancesOnly, tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.voice].path)
														end
													end)
													tPause = tPause + ((string.len(tTypeString) + string.len(tNumber)) * 0.4)
												end
											end
										end
									end
								end
							end
						end
					end
					ttimeMonPartyDebuff = 0
				end
			end

			if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.enabled == true then
				ttimeMonParty2 = ttimeMonParty2 + time
				if ttimeMonParty2 > SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.continouslyTimer then
					monitorPartyHealth2ContiOutput()
					ttimeMonParty2 = 0
				end
			end


			if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.enabled == true then
				ttimeMonRaidDebuff = ttimeMonRaidDebuff + time
				if ttimeMonRaidDebuff > SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.continouslyTimer and tRaidDebuffsMonitorPause == false then
					if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.continouslyStartAfter > -1 then
						local tUnitIdList = Aq:UnitIsInUnitGroup("raid", "player")
						if tUnitIdList then
							local tPause = 0
							for _, tUnitID in pairs(tUnitIdList) do
								local tUnitGUID = UnitGUID(tUnitID)
								if tAuraRepo["raid"] and tAuraRepo["raid"][tUnitGUID] then
									for i, v in pairs(tDebuffTypes) do
										if tAuraRepo["raid"][tUnitGUID][i].start > 0 and tAuraRepo["raid"][tUnitGUID][i].count > 0 and (GetTime() - tAuraRepo["raid"][tUnitGUID][i].start > SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.continouslyStartAfter) then
											if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.types[i] == true then		
												local tNumber
												if string.sub(tUnitID, 1, 4) == "raid" then
													tNumber = tonumber(string.sub(tUnitID, 5))
													if tNumber then
														tNumber = tNumber + 1
													end
												end
												if tNumber then
													local tTypeString = tDebuffTypesShort[i]
													if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.outputStyle == 1 then
														tTypeString = i
													end
													C_Timer.After(tPause, function()
														if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].global.numberFirst == true then
															Aq:MonitorOutputPlayerStatus({[1] = tNumber, [2] = tTypeString}, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.continouslyVolume, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.instancesOnly, tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.voice].path)
														else
															Aq:MonitorOutputPlayerStatus({[1] = tTypeString, [2] = tNumber}, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.continouslyVolume, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.instancesOnly, tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.voice].path)
														end
													end)
													tPause = tPause + ((string.len(tTypeString) + string.len(tNumber)) * 0.4)
												end
											end
										end
									end
								end
							end
						end
					end
					ttimeMonRaidDebuff = 0
				end
			end

			if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.enabled == true then
				ttimeMonRaid2 = ttimeMonRaid2 + time
				if ttimeMonRaid2 > SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.continouslyTimer then
					monitorRaidHealth2ContiOutput()
					ttimeMonRaid2 = 0
				end
			end			
		end

		Sku.PerformanceData["aq onupdate"] = ((Sku.PerformanceData["aq onupdate"] or 0) + (debugprofilestop() - beginTime)) / 2
   end)
end

--mirror bars
---------------------------------------------------------------------------------------------------------------------------------------
function Aq:MIRROR_TIMER_START(eventName, timerName, value, maxValue, scale, paused, timerLabel)
	SkuCore.aq.mirrorBars[timerName] = {}
	SkuCore.aq.mirrorBars[timerName].name = timerName
	SkuCore.aq.mirrorBars[timerName].value = value
	SkuCore.aq.mirrorBars[timerName].maxValue = maxValue
	SkuCore.aq.mirrorBars[timerName].scale = scale
	SkuCore.aq.mirrorBars[timerName].paused = paused
	SkuCore.aq.mirrorBars[timerName].pausedDuration = 0
	SkuCore.aq.mirrorBars[timerName].label = timerLabel
	SkuCore.aq.mirrorBars[timerName].stepPct = 10
	SkuCore.aq.mirrorBars[timerName].prevStepPct = 100
end

---------------------------------------------------------------------------------------------------------------------------------------
function Aq:MIRROR_TIMER_STOP(eventName, timerName)
	SkuCore.aq.mirrorBars[timerName] = nil
end

---------------------------------------------------------------------------------------------------------------------------------------
function Aq:MIRROR_TIMER_PAUSE(eventName, timerName, pause)
	SkuCore.aq.mirrorBars[timerName].paused = true
	SkuCore.aq.mirrorBars[timerName].pausedDuration = pause
end

--global
---------------------------------------------------------------------------------------------------------------------------------------
function Aq:AqOnInitialize()
	AqCreateControlFrame()

	Aq:RegisterEvent("MIRROR_TIMER_START")
	Aq:RegisterEvent("MIRROR_TIMER_STOP")
	Aq:RegisterEvent("MIRROR_TIMER_PAUSE")
	Aq:RegisterEvent("UNIT_HEALTH")
	Aq:RegisterEvent("UNIT_POWER_UPDATE")

	Aq:RegisterEvent("UNIT_AURA")

   SkuDispatcher:RegisterEventCallback("PLAYER_ENTERING_WORLD", Aq.Monitor_PLAYER_ENTERING_WORLD)
   SkuDispatcher:RegisterEventCallback("PARTY_LEADER_CHANGED", Aq.Monitor_PARTY_LEADER_CHANGED)
   SkuDispatcher:RegisterEventCallback("GROUP_FORMED", Aq.Monitor_GROUP_FORMED)
   SkuDispatcher:RegisterEventCallback("GROUP_JOINED", Aq.Monitor_GROUP_JOINED)
   SkuDispatcher:RegisterEventCallback("GROUP_LEFT", Aq.Monitor_GROUP_LEFT)
   SkuDispatcher:RegisterEventCallback("GROUP_ROSTER_UPDATE", Aq.Monitor_GROUP_ROSTER_UPDATE)	

	--SkuCore.aqCombat:aqCombatOnInitialize()
end

---------------------------------------------------------------------------------------------------------------------------------------
function Aq:AqOnLogin()

	if SkuSettings:Sub("SkuCore", nil, "char").aq and not SkuSettings:Sub("SkuCore", nil, "char").aq[1] then
		local tExisting = SkuSettings:Sub("SkuCore", nil, "char").aq
		SkuSettings:Sub("SkuCore", nil, "char").aq = {}
		SkuSettings:Sub("SkuCore", nil, "char").aq[1] = tExisting
		SkuSettings:Sub("SkuCore", nil, "char").aq[2] = tExisting
	end

	SkuSettings:Sub("SkuCore", nil, "char").aq = SkuSettings:Sub("SkuCore", nil, "char").aq or {}
	
	for q = 1, 2 do
		SkuSettings:Sub("SkuCore", nil, "char").aq[q] = SkuSettings:Sub("SkuCore", nil, "char").aq[q] or {}
		SkuSettings:Sub("SkuCore", nil, "char").aq[q].player = SkuSettings:Sub("SkuCore", nil, "char").aq[q].player or {}
		SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet = SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet or {}
		SkuSettings:Sub("SkuCore", nil, "char").aq[q].party = SkuSettings:Sub("SkuCore", nil, "char").aq[q].party or {}
		SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid = SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid or {}
		SkuSettings:Sub("SkuCore", nil, "char").aq[q].global = SkuSettings:Sub("SkuCore", nil, "char").aq[q].global or {}

		--global
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].global.numberFirst == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].global.numberFirst = false
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].global.numberOnly == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].global.numberOnly = false
		end


		--party health 2
		SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2 = SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2 or {}
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.enabled == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.enabled = false
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.factorInIncomingHeals == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.factorInIncomingHeals = false
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.roleAssigments == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.roleAssigments = {[1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0, }
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.continouslyStartAt == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.continouslyStartAt = {}
			for x = 1, #tRoles do
				SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.continouslyStartAt[x] = 0
			end
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.eventOutputFilters == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.eventOutputFilters = {}
			for x = 1, #tRoles do
				SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.eventOutputFilters[x] = {}
				for i, v in pairs(tEventOutputFilters) do
					SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.eventOutputFilters[x][v.id] = v.defaults[x]
				end
			end
		end	
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.silentOn100and0 == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.silentOn100and0 = true
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.addDeadOn0Percent == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.addDeadOn0Percent = true
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.addSoundOn100Percent == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.addSoundOn100Percent = true
		end

		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.continouslyTimer == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.continouslyTimer = 3
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.continouslyVolume == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.continouslyVolume = 100
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.eventVolume == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.eventVolume = 100
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.outputQueueDelay == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.outputQueueDelay = 100
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.prioOutput == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.health2.prioOutput = {[1] = false, [2] = false, [3] = false, [4] = false, }
		end

		--raid health 2
		SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2 = SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2 or {}

		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.enabled == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.enabled = false
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.factorInIncomingHeals == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.factorInIncomingHeals = false
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.roleAssigments == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.roleAssigments = {}
			for x = 1, MAX_RAID_MEMBERS do
				SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.roleAssigments[x] = 0
			end
		end


		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.unitsAndSubgroupsSelection == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.unitsAndSubgroupsSelection = {}
			for x = 1, 5 do
				SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.unitsAndSubgroupsSelection[L["Subgroup"].." "..x] = true
			end
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.unitsAndSubgroupsSelection[L["Main Tank"]] = true
		end
		

		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.continouslyStartAt == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.continouslyStartAt = {}
			for x = 1, #tRoles do
				SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.continouslyStartAt[x] = 0
			end
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.eventOutputFilters == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.eventOutputFilters = {}
			for x = 1, #tRoles do
				SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.eventOutputFilters[x] = {}
				for i, v in pairs(tEventOutputFilters) do
					SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.eventOutputFilters[x][v.id] = v.defaults[x]
				end
			end
		end	
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.silentOn100and0 == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.silentOn100and0 = true
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.addDeadOn0Percent == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.addDeadOn0Percent = true
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.addSoundOn100Percent == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.addSoundOn100Percent = true
		end

		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.continouslyTimer == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.continouslyTimer = 3
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.continouslyVolume == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.continouslyVolume = 100
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.eventVolume == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.eventVolume = 100
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.outputQueueDelay == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.outputQueueDelay = 100
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.prioOutput == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.health2.prioOutput = {[1] = false, [2] = false, [3] = false, [4] = false, }
		end

		--player health
		SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health = SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health or {}
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.enabled == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.enabled = true
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.factorInIncomingHeals == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.factorInIncomingHeals = true
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.instancesOnly == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.instancesOnly = false
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.silentOn100and0 == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.silentOn100and0 = true
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.continouslyTimer == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.continouslyTimer = 3
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.continouslyStartAt == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.continouslyStartAt = -1
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.continouslyVolume == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.continouslyVolume = 100
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.eventVolume == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.eventVolume = 80
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.steps == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.steps = 10
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.voice == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.health.voice = 1
		end

		--pet health
		SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health = SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health or {}
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.enabled == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.enabled = true
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.factorInIncomingHeals == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.factorInIncomingHeals = true
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.instancesOnly == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.instancesOnly = false
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.silentOn100and0 == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.silentOn100and0 = true
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.continouslyTimer == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.continouslyTimer = 3
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.continouslyStartAt == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.continouslyStartAt = -1
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.continouslyVolume == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.continouslyVolume = 100
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.eventVolume == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.eventVolume = 80
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.steps == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.steps = 10
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.voice == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].pet.health.voice = 1
		end

		--player power
		SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power = SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power or {}
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.enabled == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.enabled = true
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.type == nil then
			local _, powerToken = UnitPowerType("player")
			if not powerToken or tPowerTypes[powerToken] == nil then
				powerToken = "NOTHING"
			end
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.type = powerToken
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.instancesOnly == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.instancesOnly = false
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.silentOn100and0 == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.silentOn100and0 = true
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.continouslyTimer == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.continouslyTimer = 6
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.continouslyStartAt == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.continouslyStartAt = -1
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.continouslyVolume == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.continouslyVolume = 30
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.eventVolume == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.eventVolume = 60
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.steps == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.steps = 5
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.voice == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.power.voice = 2
		end	

		--player debuffs
		SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs = SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs or {}
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs.enabled == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs.enabled = false
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs.types == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs.types = {["magic"] = false, ["curse"] = false, ["poison"] = false, ["disease"] = false, }
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs.ignored == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs.ignored = {}
		end

		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs.instancesOnly == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs.instancesOnly = false
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs.continouslyStartAfter == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs.continouslyStartAfter = -1
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs.continouslyTimer == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs.continouslyTimer = 6
		end

		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs.continouslyVolume == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs.continouslyVolume = 30
		end	
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs.eventVolume == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs.eventVolume = 60
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs.voice == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].player.debuffs.voice = 2
		end

		--party debuffs
		SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs = SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs or {}
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.enabled == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.enabled = false
		end

		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.types == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.types = {["magic"] = false, ["curse"] = false, ["poison"] = false, ["disease"] = false, }
		end

		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.ignored == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.ignored = {}
		end

		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.instancesOnly == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.instancesOnly = false
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.continouslyStartAfter == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.continouslyStartAfter = -1
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.outputStyle == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.outputStyle = 2
		end

		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.continouslyTimer == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.continouslyTimer = 6
		end

		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.continouslyVolume == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.continouslyVolume = 30
		end	
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.eventVolume == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.eventVolume = 60
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.voice == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].party.debuffs.voice = 3
		end

		--raid debuffs
		SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs = SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs or {}
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.enabled == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.enabled = false
		end

		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.types == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.types = {["magic"] = false, ["curse"] = false, ["poison"] = false, ["disease"] = false, }
		end

		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.ignored == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.ignored = {}
		end

		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.instancesOnly == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.instancesOnly = false
		end

		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.unitsAndSubgroupsSelection == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.unitsAndSubgroupsSelection = {}
			for x = 1, 5 do
				SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.unitsAndSubgroupsSelection[L["Subgroup"].." "..x] = true
			end
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.unitsAndSubgroupsSelection[L["Main Tank"]] = true
		end

		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.continouslyStartAfter == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.continouslyStartAfter = -1
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.outputStyle == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.outputStyle = 2
		end

		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.continouslyTimer == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.continouslyTimer = 6
		end

		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.continouslyVolume == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.continouslyVolume = 30
		end	
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.eventVolume == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.eventVolume = 60
		end
		if SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.voice == nil then
			SkuSettings:Sub("SkuCore", nil, "char").aq[q].raid.debuffs.voice = 3
		end	
	end

	-- W4 Phase D: aqCombat is now its own self-enabling AceAddon module; it
	-- arms via its own OnEnable, so Aq no longer calls aqCombatOnLogin here
	-- (calling it would double-init it).
end

---------------------------------------------------------------------------------------------------------------------------------------
-- AceAddon runs OnInitialize for EVERY module, even one that will be disabled.
-- SkuCore.Monitor.UnitNumbersIndexedRaid is READ by SkuAuras and must exist even
-- when Aq is OFF, so (re)build it here unconditionally (it is also built at file
-- scope; this keeps it present across enable/disable cycles).
function Aq:OnInitialize()
	SkuCore.Monitor = SkuCore.Monitor or {}
	SkuCore.Monitor.UnitNumbersIndexedRaid = SkuCore.Monitor.UnitNumbersIndexedRaid or {}
	for x = 1, MAX_RAID_MEMBERS do
		SkuCore.Monitor.UnitNumbersIndexedRaid[x] = "raid"..x
	end
end

-- Arm the monitor. Called automatically by AceAddon when the module is enabled
-- (at SkuCore enable, on every /reload, and whenever the user toggles it back on).
-- Mirrors the old Core.lua AqOnInitialize + AqOnLogin calls.
function Aq:OnEnable()
	Aq:AqOnInitialize()
	Aq:AqOnLogin()
end

-- Disarm: stop the OnUpdate driver and drop every event + dispatcher callback
-- armed by AqOnInitialize, so a disabled monitor genuinely does nothing.
-- SkuCore.Monitor is intentionally NOT nilled (SkuAuras still reads it).
function Aq:OnDisable()
	if AqControlFrame then
		AqControlFrame:SetScript("OnUpdate", nil)
	end

	Aq:UnregisterEvent("MIRROR_TIMER_START")
	Aq:UnregisterEvent("MIRROR_TIMER_STOP")
	Aq:UnregisterEvent("MIRROR_TIMER_PAUSE")
	Aq:UnregisterEvent("UNIT_HEALTH")
	Aq:UnregisterEvent("UNIT_POWER_UPDATE")
	Aq:UnregisterEvent("UNIT_AURA")

	SkuDispatcher:UnregisterEventCallback("PLAYER_ENTERING_WORLD", Aq.Monitor_PLAYER_ENTERING_WORLD)
	SkuDispatcher:UnregisterEventCallback("PARTY_LEADER_CHANGED", Aq.Monitor_PARTY_LEADER_CHANGED)
	SkuDispatcher:UnregisterEventCallback("GROUP_FORMED", Aq.Monitor_GROUP_FORMED)
	SkuDispatcher:UnregisterEventCallback("GROUP_JOINED", Aq.Monitor_GROUP_JOINED)
	SkuDispatcher:UnregisterEventCallback("GROUP_LEFT", Aq.Monitor_GROUP_LEFT)
	SkuDispatcher:UnregisterEventCallback("GROUP_ROSTER_UPDATE", Aq.Monitor_GROUP_ROSTER_UPDATE)
end

--Monitor
---------------------------------------------------------------------------------------------------------------------------------------
function Aq:AqSlashHandler(aFieldsTable)
	if aFieldsTable[2] == "player" and aFieldsTable[3] == "health" then
		SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.enabled = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.enabled == false		
	elseif aFieldsTable[2] == "combat" and aFieldsTable[3] == "follow" and aFieldsTable[4] == "target" then
		if UnitName("target") and UnitIsPlayer("target") then
			SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.oorUnitName = UnitName("target")
		else
			SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.oorUnitName = L["Nothing selected"]
		end
		print("New follow target: "..SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].combat.friendly.oorUnitName)

	elseif aFieldsTable[2] == "player" and aFieldsTable[3] == "power" then
		SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.enabled = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.enabled == false		
	elseif aFieldsTable[2] == "player" and aFieldsTable[3] == "debuffs" then
		SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.enabled = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.enabled == false		
	elseif aFieldsTable[2] == "pet" and aFieldsTable[3] == "health" then
		SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.enabled = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.enabled == false		
	elseif aFieldsTable[2] == "party" and aFieldsTable[3] == "debuffs" then
		SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.enabled = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.enabled == false		
	elseif aFieldsTable[2] == "party" and aFieldsTable[3] == "health" then
		SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.enabled = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.enabled == false		
	elseif aFieldsTable[2] == "party" and aFieldsTable[3] == "roles" and aFieldsTable[4] == "reset" then
		SkuAuras:RoleCheckerResetData()
	elseif aFieldsTable[2] == "party" and aFieldsTable[3] == "roles" and aFieldsTable[4] == "print" then
		for x = 1, #tUnitNumbersIndexed do
			local tUnitGUID = UnitGUID(tUnitNumbersIndexed[x])
			if tUnitGUID then
				local tRoleID = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.roleAssigments[tUnitNumbers[aUnitID]]
				if tRoleID == 0 or tRoleID == nil then
					tRoleID = (SkuAuras and SkuAuras.RoleCheckerGetUnitRole and (not SkuAuras.IsEnabled or SkuAuras:IsEnabled())) and SkuAuras:RoleCheckerGetUnitRole(tUnitGUID) or nil
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function Aq:UNIT_HEALTH(eventName, aUnitID)
	local tIncomingHealAmount = 0
	if aUnitID == "player" and SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.factorInIncomingHeals == true then
		local tIncomingHealAll = UnitGetIncomingHeals(aUnitID) or 0
		local tIncomingHealPlayer = UnitGetIncomingHeals(aUnitID, "player") or 0
		tIncomingHealAmount = (tIncomingHealAll - tIncomingHealPlayer)
	elseif (aUnitID == "playerpet" or aUnitID == "pet") and SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.factorInIncomingHeals == true then
		local tIncomingHealAll = UnitGetIncomingHeals(aUnitID) or 0
		local tIncomingHealPlayer = UnitGetIncomingHeals(aUnitID, "player") or 0
		tIncomingHealAmount = (tIncomingHealAll - tIncomingHealPlayer)
	elseif (aUnitID == "player" or aUnitID == "party1" or aUnitID == "party2" or aUnitID == "party3" or aUnitID == "party4") and SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.factorInIncomingHeals == true then
		local tIncomingHealAll = UnitGetIncomingHeals(aUnitID) or 0
		local tIncomingHealPlayer = UnitGetIncomingHeals(aUnitID, "player") or 0
		tIncomingHealAmount = (tIncomingHealAll - tIncomingHealPlayer)
	elseif (string.sub(aUnitID, 1, 4) == "raid" and string.sub(aUnitID, 1, 7) ~= "raidpet") and SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.factorInIncomingHeals == true then
		local tIncomingHealAll = UnitGetIncomingHeals(aUnitID) or 0
		local tIncomingHealPlayer = UnitGetIncomingHeals(aUnitID, "player") or 0
		tIncomingHealAmount = (tIncomingHealAll - tIncomingHealPlayer)
	end

	if aUnitID == "player" then
		if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet] then
			if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.enabled == true then
				local health = UnitHealth("player")
				local healthMax = UnitHealthMax("player")
				health = health + tIncomingHealAmount
				if health > healthMax then
					health = healthMax
				end
				local healthPer = math.floor((health / healthMax) * 100)
				local tsinglestep = math.floor(100 / SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.steps)
				local tNumberToUtterance = ((math.floor(healthPer / tsinglestep)) * tsinglestep) / 10
				tPrevHpDir = healthPer > tPrevHpPer
				local tPrevNumberToUtteranceOutput = tNumberToUtterance
				if tPrevHpDir == false then
					tPrevNumberToUtteranceOutput = tPrevNumberToUtteranceOutput + 1
				end
				if tNumberToUtterance ~= tPrevNumberToUtterance then
					Aq:MonitorOutputPlayerPercent(tPrevNumberToUtteranceOutput, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.eventVolume, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.instancesOnly, tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.voice].path)
					tHealthMonitorPause = true
					tPowerMonitorPause = true
					C_Timer.After(SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.continouslyTimer, function()
						tHealthMonitorPause = false
						tPowerMonitorPause = false
					end)
					tPrevNumberToUtterance = tNumberToUtterance
				end
				tPrevHpPer = healthPer
			end
		end
	elseif aUnitID == "playerpet" or aUnitID == "pet" then
		if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet] then
			if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.enabled == true and UnitName("pet") then
				local health = UnitHealth("pet")
				local healthMax = UnitHealthMax("pet")
				health = health + tIncomingHealAmount
				if health > healthMax then
					health = healthMax
				end

				local healthPer = math.floor((health / healthMax) * 100)
				local tsinglestep = math.floor(100 / SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.steps)
				local tNumberToUtterance = ((math.floor(healthPer / tsinglestep)) * tsinglestep) / 10
				tPrevHpPetDir = healthPer > tPrevHpPetPer
				local tPrevNumberToUtteranceOutput = tNumberToUtterance
				if tPrevHpPetDir == false then
					tPrevNumberToUtteranceOutput = tPrevNumberToUtteranceOutput + 1
				end

				if tNumberToUtterance ~= tPrevNumberToUtterancePet then
					Aq:MonitorOutputPlayerPercent(tPrevNumberToUtteranceOutput, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.eventVolume, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.instancesOnly, tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.voice].path, "pet")
					tHealthMonitorPause = true
					tPowerMonitorPause = true
					C_Timer.After(SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.continouslyTimer, function()
						tHealthMonitorPause = false
						tPowerMonitorPause = false
					end)
					tPrevNumberToUtterancePet = tNumberToUtterance
				end
				tPrevHpPetPer = healthPer
			end
		end
	end

	--party health 2
	if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet] then
		if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.enabled == true then
			if aUnitID == "player" or aUnitID == "party1" or aUnitID == "party2" or aUnitID == "party3" or aUnitID == "party4" then
				local tUnitGUID = UnitGUID(aUnitID)
				local tRoleID = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.roleAssigments[tUnitNumbers[aUnitID]]
				if tRoleID == 0 then
					tRoleID = (SkuAuras and SkuAuras.RoleCheckerGetUnitRole and (not SkuAuras.IsEnabled or SkuAuras:IsEnabled())) and SkuAuras:RoleCheckerGetUnitRole(tUnitGUID) or nil
				end
				
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.prevHealth = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.prevHealth or {
					["player"] = {absolute = 100, steps = 14, lastOutput = 0, },
					["party1"] = {absolute = 100, steps = 14, lastOutput = 0, },
					["party2"] = {absolute = 100, steps = 14, lastOutput = 0, },
					["party3"] = {absolute = 100, steps = 14, lastOutput = 0, },
					["party4"] = {absolute = 100, steps = 14, lastOutput = 0, },
				}

				local health = UnitHealth(aUnitID)
				local healthMax = UnitHealthMax(aUnitID)
				health = health + tIncomingHealAmount
				if health > healthMax then
					health = healthMax
				end

				local tHealthAbsoluteValue = math.floor((health / healthMax) * 100)
				--if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.silentOn100and0 == true and (tHealthAbsoluteValue < 1 or tHealthAbsoluteValue > 99) then
					--return
				--end

				local tHealthStepsValue = math.floor(tHealthAbsoluteValue / (100 / 15))
				if tHealthStepsValue > 14 then
					tHealthStepsValue = 14
				end

				local tminAbsoluteSincePrevEventValue = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.eventOutputFilters[tRoleID][tEventOutputFilters["minAbsoluteSincePrevEvent"].id]
				local tminStepsSincePrevEventValue = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.eventOutputFilters[tRoleID][tEventOutputFilters["minStepsSincePrevEvent"].id]

				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.prevHealth[aUnitID].absolute = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.prevHealth[aUnitID].absolute or 100

				if (
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.prevHealth[aUnitID].absolute - tHealthAbsoluteValue >= tminAbsoluteSincePrevEventValue 
						or 
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.prevHealth[aUnitID].absolute - tHealthAbsoluteValue <= -tminAbsoluteSincePrevEventValue 
					)
					and
					(
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.prevHealth[aUnitID].steps - tHealthStepsValue >= tminStepsSincePrevEventValue 
						or 
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.prevHealth[aUnitID].steps - tHealthStepsValue <= -tminStepsSincePrevEventValue 
					)
				then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.prevHealth[aUnitID].absolute = tHealthAbsoluteValue
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.prevHealth[aUnitID].steps = tHealthStepsValue
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.prevHealth[aUnitID].lastOutput = GetTime()

					local tUnitNumber, tVolume, tPitch = tUnitNumbers[aUnitID], SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.eventVolume, (((tHealthStepsValue * 5) - 35) * -1)
					if tPitch == 0 then tPitch = 0 end --dnd, we need this in case of -0

					ttimeMonParty2QueueAdd(tUnitNumber, tVolume, tPitch, (ttimeMonParty2QueueDefaultOutputLength * (SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.outputQueueDelay / 100)), tRoleID, tHealthAbsoluteValue)
				end
			end
		end
	end

	--raid health 2
	if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet] then
		if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.enabled == true then
			if string.sub(aUnitID, 1, 4) == "raid" and string.sub(aUnitID, 1, 7) ~= "raidpet" then
				local tUnitGUID = UnitGUID(aUnitID)
				local tRoleID = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.roleAssigments[tUnitNumbersRaid[aUnitID]]
				if tRoleID == 0 then
					tRoleID = (SkuAuras and SkuAuras.RoleCheckerGetUnitRole and (not SkuAuras.IsEnabled or SkuAuras:IsEnabled())) and SkuAuras:RoleCheckerGetUnitRole(tUnitGUID) or nil
				end
				
				if not SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prevHealth then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prevHealth = {}
					for x = 1, MAX_RAID_MEMBERS do
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prevHealth["raid"..x] = {absolute = 100, steps = 14, lastOutput = 0, }
					end
				end

				local health = UnitHealth(aUnitID)
				local healthMax = UnitHealthMax(aUnitID)
				health = health + tIncomingHealAmount
				if health > healthMax then
					health = healthMax
				end

				local tHealthAbsoluteValue = math.floor((health / healthMax) * 100)
				--if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.silentOn100and0 == true and (tHealthAbsoluteValue < 1 or tHealthAbsoluteValue > 99) then
					--return
				--end

				local tHealthStepsValue = math.floor(tHealthAbsoluteValue / (100 / 15))
				if tHealthStepsValue > 14 then
					tHealthStepsValue = 14
				end
				
				local tminAbsoluteSincePrevEventValue = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.eventOutputFilters[tRoleID][tEventOutputFilters["minAbsoluteSincePrevEvent"].id]
				local tminStepsSincePrevEventValue = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.eventOutputFilters[tRoleID][tEventOutputFilters["minStepsSincePrevEvent"].id]

				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prevHealth[aUnitID].absolute = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prevHealth[aUnitID].absolute or 100

				if (
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prevHealth[aUnitID].absolute - tHealthAbsoluteValue >= tminAbsoluteSincePrevEventValue 
						or 
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prevHealth[aUnitID].absolute - tHealthAbsoluteValue <= -tminAbsoluteSincePrevEventValue 
					)
					and
					(
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prevHealth[aUnitID].steps - tHealthStepsValue >= tminStepsSincePrevEventValue 
						or 
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prevHealth[aUnitID].steps - tHealthStepsValue <= -tminStepsSincePrevEventValue 
					)
				then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prevHealth[aUnitID].absolute = tHealthAbsoluteValue
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prevHealth[aUnitID].steps = tHealthStepsValue
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prevHealth[aUnitID].lastOutput = GetTime()

					local tUnitNumber, tVolume, tPitch = tUnitNumbersRaid[aUnitID], SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.eventVolume, (((tHealthStepsValue * 5) - 35) * -1)
					if tPitch == 0 then tPitch = 0 end --dnd, we need this in case of -0

					ttimeMonRaid2QueueAdd(tUnitNumber, tVolume, tPitch, (ttimeMonRaid2QueueDefaultOutputLength * (SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.outputQueueDelay / 100)), tRoleID, tHealthAbsoluteValue, nil, aUnitID)
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function Aq:UNIT_POWER_UPDATE(eventName, unitTarget, powerType)
	if unitTarget == "player" then
		if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet] then
			if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.enabled == true then
				if powerType == SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.type then
					local power = UnitPower("player", tPowerTypes[powerType].number)
					local powerMax = UnitPowerMax("player", tPowerTypes[powerType].number)
					local pwrPer = math.floor((power / powerMax) * 100)
					local tsinglestep = math.floor(100 / SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.steps)
					local tNumberToUtterance = ((math.floor(pwrPer / tsinglestep)) * tsinglestep) / 10
					if tPrevPwrPer == pwrPer then
						return
					end
					tPrevPwrDir = pwrPer >= tPrevPwrPer
					local tPrevNumberToUtteranceOutput = tNumberToUtterance					
					if tPrevPwrDir == false then
						tPrevNumberToUtteranceOutput = tPrevNumberToUtteranceOutput + 1
					end

					if tNumberToUtterance ~= tPrevNumberToUtterancePlPwr then
						Aq:MonitorOutputPlayerPercent(tPrevNumberToUtteranceOutput, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.eventVolume, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.instancesOnly, tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.voice].path)
						tHealthMonitorPause = true
						tPowerMonitorPause = true
						C_Timer.After(SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.continouslyTimer, function()
							tHealthMonitorPause = false
							tPowerMonitorPause = false
						end)
						tPrevNumberToUtterancePlPwr = tNumberToUtterance
					end
					tPrevPwrPer = pwrPer
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
---@param aFilter string "player"
---@param aFilter string "playerpet"
---@param aFilter string "party"
---@param aFilter string "partyandpets"
---@param aFilter string "raid"
---@param aFilter string "raidandpets"
---@param aUnitID string
function Aq:UnitIsInUnitGroup(aFilter, aUnitID)
	if not aUnitID then
		return
	end

	if not string.find(aUnitID, "player") and not string.find(aUnitID, "party") and not string.find(aUnitID, "raid") then
		return
	end

	if aFilter == "player" then
		local tUnit = UnitGUID(aUnitID)
		local tPlayer = UnitGUID("player")
		if tUnit == tPlayer then
			return {"player",}
		end
	elseif aFilter == "playerpet" then
		local tUnit = UnitGUID(aUnitID)
		local tPet = UnitGUID("playerpet")
		if tUnit == tPet then
			return {"playerpet",}
		end	
	elseif aFilter == "party" then
		if UnitPlayerOrPetInParty(aUnitID) and UnitIsPlayer(aUnitID) then
			return {"player", "party1", "party2", "party3", "party4"}
		end
	elseif aFilter == "partyandpets" then
		if UnitPlayerOrPetInParty(aUnitID) then
			return {"player", "party1", "party2", "party3", "party4", "playerpet", "party1pet", "party2pet", "party3pet", "party4pet"}
		end
	elseif aFilter == "raid" then
		if UnitPlayerOrPetInRaid(aUnitID) and UnitIsPlayer(aUnitID) then
			local tTable = {}
			for x = 1, MAX_RAID_MEMBERS do
				tTable[x] = "raid"..x
			end
			return tTable
		end
	elseif aFilter == "raidandpets" then
		if UnitPlayerOrPetInRaid(aUnitID) then
			local tTable = {}
			for x = 1, MAX_RAID_MEMBERS do
				tTable[x] = "raid"..x
			end
			for x = MAX_RAID_MEMBERS + 1, MAX_RAID_MEMBERS * 2 do
				tTable[x] = "raid"..x.."pet"
			end
			return tTable
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function Aq:UNIT_AURA(aEventName, aUnitID)
	local tSubR
	local tUnitIdList = {}
	if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.enabled == true and Aq:UnitIsInUnitGroup("party", aUnitID) then
		tSubR = "party"
	end
	if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.enabled == true and Aq:UnitIsInUnitGroup("raid", aUnitID) then
		tSubR = "raid"
	end
	if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.enabled == true and Aq:UnitIsInUnitGroup("player", aUnitID) then
		tSubR = "player"
	end

	if tSubR == nil then
		return
	end

	if not string.find(aUnitID, tSubR) then
		return
	end

	local tUnitGUID = UnitGUID(aUnitID)
	local tUnitName = UnitName(aUnitID) 
	local tDebuff = UnitDebuff(aUnitID, 1)
	

	tAuraRepo[tSubR] = tAuraRepo[tSubR] or {}

	if tDebuff == nil then
		tAuraRepo[tSubR][tUnitGUID] = nil
	else
		local tPause = 0

		local tCurrentDebuffType = {
			["magic"] = 0,
			["curse"] = 0,
			["poison"] = 0,
			["disease"] = 0,
		}
		local tFound
		for x = 1, 100 do
			local name, icon, count, dispelType, duration, expirationTime,	source, isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossDebuff, castByPlayer = UnitDebuff(aUnitID, x) --UnitDebuffTest(x)
			if name then
				if dispelType then
					if not SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tSubR].debuffs.ignored[name] then
						if count == 0 then count = 1 end
						tCurrentDebuffType[string.lower(dispelType)] = tCurrentDebuffType[string.lower(dispelType)] + count
						tFound = true
					end
				end
			end
		end
		if tFound then
			tAuraRepo[tSubR][tUnitGUID] = tAuraRepo[tSubR][tUnitGUID] or {
				["magic"] = {count = 0, start = 0,},
				["curse"] = {count = 0, start = 0,},
				["poison"] = {count = 0, start = 0,},
				["disease"] = {count = 0, start = 0,},
			}
			for i, v in pairs(tDebuffTypes) do
				if tCurrentDebuffType[i] > 0 and tCurrentDebuffType[i] ~= tAuraRepo[tSubR][tUnitGUID][i].count then
					tAuraRepo[tSubR][tUnitGUID][i].count = tCurrentDebuffType[i]
					tAuraRepo[tSubR][tUnitGUID][i].start = GetTime()
					if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tSubR].debuffs.types[i] == true then
						C_Timer.After(tPause, function()
							if tSubR == "player" then
								Aq:MonitorOutputPlayerStatus({[1] = i,}, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tSubR].debuffs.eventVolume, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tSubR].debuffs.instancesOnly, tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tSubR].debuffs.voice].path)
							elseif tSubR == "party" then
								local tNumber
								if string.sub(aUnitID, 1, 6) == "player" then
									tNumber = 1
								elseif string.sub(aUnitID, 1, 5) == "party" then
									tNumber = tonumber(string.sub(aUnitID, 6))
									if tNumber then
										tNumber = tNumber + 1
									end
								end
								if tNumber then
									local tTypeString = tDebuffTypesShort[i]
									if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.outputStyle == 1 then
										tTypeString = i
									end

									if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].global.numberFirst == true then
										Aq:MonitorOutputPlayerStatus({[1] = tNumber, [2] = tTypeString,}, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tSubR].debuffs.eventVolume, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tSubR].debuffs.instancesOnly, tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tSubR].debuffs.voice].path)								
									else
										Aq:MonitorOutputPlayerStatus({[1] = tTypeString, [2] = tNumber,}, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tSubR].debuffs.eventVolume, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tSubR].debuffs.instancesOnly, tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tSubR].debuffs.voice].path)								
									end


									tPause = tPause + 0.3
								end
							elseif tSubR == "raid" then
								local tNumber
								if string.sub(aUnitID, 1, 4) == "raid" then
									tNumber = tonumber(string.sub(aUnitID, 5))
									if tNumber then
										--tNumber = tNumber + 1
										tNumber = tDTRaidRoster[aUnitID]
									end
								end
								if tNumber then
									local tTypeString = tDebuffTypesShort[i]
									if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.outputStyle == 1 then
										tTypeString = i
									end
									if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].global.numberFirst == true then
										Aq:MonitorOutputPlayerStatus({[1] = tNumber, [2] = tTypeString,}, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tSubR].debuffs.eventVolume, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tSubR].debuffs.instancesOnly, tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tSubR].debuffs.voice].path)								
									else
										Aq:MonitorOutputPlayerStatus({[1] = tTypeString, [2] = tNumber,}, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tSubR].debuffs.eventVolume, SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tSubR].debuffs.instancesOnly, tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tSubR].debuffs.voice].path)								
									end
									tPause = tPause + 0.3
								end
							end
						end)
						tPartyDebuffsMonitorPause = true
						tPlayerDebuffsMonitorPause = true
						C_Timer.After(SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tSubR].debuffs.continouslyTimer, function()
							tPartyDebuffsMonitorPause = false
							tPlayerDebuffsMonitorPause = false
							end)
					end
				elseif tCurrentDebuffType[i] == 0 then
					tAuraRepo[tSubR][tUnitGUID][i].count = 0
					tAuraRepo[tSubR][tUnitGUID][i].start = 0
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function Aq:MonitorOutputPlayerStatus(aStatusTable, aVol, aInstancesOnly, aVoice)
	local inInstance = IsInInstance() 
	if aInstancesOnly == true and inInstance ~= true then
		return
	end
	local tPause = 0
	for x = 1, #aStatusTable do
		C_Timer.After(tPause, function()
			PlaySoundFile("Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\aq\\"..aVoice.."\\"..aVoice.."_"..aStatusTable[x].."_"..aVol..".mp3", SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel or "Talking Head")
		end)
		tPause = tPause + (string.len(aStatusTable[x]) * 0.03) + 0.3
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local tSounds = {
	[0] = {min = 0, max = 0,},
	[1] = {min = 1, max = 17,},
	[2] = {min = 18, max = 33,},
	[3] = {min = 34, max = 50,},
	[4] = {min = 51, max = 67,},
	[5] = {min = 68, max = 83,},
	[6] = {min = 84, max = 99,},
	[7] = {min = 100, max = 100,},
}
function Aq:MonitorOutputPartyPercent(aHealthValues, aVolume, aInstancesOnly, aSpeed)
	local inInstance = IsInInstance() 
	if aInstancesOnly == true and inInstance ~= true then
		return
	end

	local tStartTime = 0 -- + 0.3
	local tSpeed = 0.6 * (aSpeed / 100)
	for x = 1, #aHealthValues do
		if aHealthValues[x] ~= -1 then
			C_Timer.After(tStartTime, function()
				local tFile
				for y = 0, #tSounds do
					if aHealthValues[x] >= tSounds[y].min and aHealthValues[x] <= tSounds[y].max then
						PlaySoundFile("Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\aq\\health_"..y..".mp3", SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel or "Talking Head")
					end
				end
			end)
		end
		tStartTime = tStartTime + tSpeed
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function Aq:MonitorOutputPartyPercent2(aUnitNumber, aVolume, aPitch)
	PlaySoundFile("Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\aq\\jus\\pitch\\jus_"..aUnitNumber.."_"..aVolume.."_"..aPitch..".mp3", SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel or "Talking Head")
end

---------------------------------------------------------------------------------------------------------------------------------------
function Aq:MonitorOutputRaidPercent2(aUnitNumber, aVolume, aPitch)
	if aUnitNumber ~= "full" and aUnitNumber ~= "dead" then
		aUnitNumber = tDTRaidRoster["raid"..aUnitNumber]
	else
		aPitch = 0
	end
	if aUnitNumber then
		PlaySoundFile("Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\aq\\jus\\pitch\\jus_"..aUnitNumber.."_"..aVolume.."_"..aPitch..".mp3", SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel or "Talking Head")
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local tRandomStC = 1
local tRandomSt = {
	[1] = "kimberlyteasesme",
	[2] = "iwantanicecream",
	[3] = "ineedtopee",
	[4] = "ifeeldizzy",
	[5] = "howarewedoing",
	[6] = "arewethereyet",
	[7] = "arewedoneyet",
}
local tPrevOutputHandle = {}
function Aq:MonitorOutputPlayerPercent(aValue, aVol, aInstancesOnly, aVoice, aPrefix)
	local inInstance = IsInInstance() 
	if aInstancesOnly == true and inInstance ~= true then
		return
	end

	if aValue >= 10 then
		aValue = 10--"full"
	elseif aValue < 0 then
		aValue = 0
	end

	if tPrevOutputHandle[aVoice] then
		StopSound(tPrevOutputHandle[aVoice])
	end

	local tPause = 0
	if aPrefix then
		PlaySoundFile("Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\aq\\"..aVoice.."\\"..aVoice.."_"..aPrefix.."_"..aVol..".mp3", SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel or "Talking Head")	
		tPause = tPause + (string.len(aPrefix) * 0.03) + 0.2	
	end
	C_Timer.After(tPause, function()
		local a, b = PlaySoundFile("Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\aq\\"..aVoice.."\\"..aVoice.."_"..aValue.."_"..aVol..".mp3", SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel or "Talking Head")
		tPrevOutputHandle[aVoice] = b
	end)

	if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.iceCreamBought ~= true then
		if math.random(1, 750) == 750 then	
			C_Timer.After(tPause + 1, function()
				local a, b = PlaySoundFile("Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\aq\\"..aVoice.."\\"..aVoice.."_"..tRandomSt[tRandomStC].."_"..aVol..".mp3", SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel or "Talking Head")
				tPrevOutputHandle[aVoice] = b
			end)
			tRandomStC = tRandomStC + 1
			if tRandomStC > 7 then
				tRandomStC = 1
			end
		end
	end

end

--menu
---------------------------------------------------------------------------------------------------------------------------------------
local function MonitorSpellMenuBuilder(self)
	local tUnitType = "player"
	if self.parent.parent.name == L["Party"] then
		tUnitType = "party"
	end

	local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["ignored"]}, SkuGenericMenuItem)
	tNewMenuEntry.dynamic = true
	tNewMenuEntry.sorting = true
	tNewMenuEntry.isSelect = true
	tNewMenuEntry.OnAction = function(self, aValue, aName)
		if aName ~= L["Empty"] then
			SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tUnitType].debuffs.ignored[self.spellName] = nil
		end
	end
	tNewMenuEntry.BuildChildren = function(self)
		local tFound
		for spellName, _ in pairs(SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tUnitType].debuffs.ignored) do
			local tSpellEntry = SkuOptions:InjectMenuItems(self, {spellName}, SkuGenericMenuItem)
			tSpellEntry.dynamic = true
			tSpellEntry.BuildChildren = function(self)
				local tActionEntry = SkuOptions:InjectMenuItems(self, {L["remove from ignore list"]}, SkuGenericMenuItem)
				tActionEntry.OnEnter = function(self, aValue, aName)
					self.selectTarget.spellName = spellName
				end
			end
			tFound = true
		end
		if not tFound then
			local tSpellEntry = SkuOptions:InjectMenuItems(self, {L["Empty"]}, SkuGenericMenuItem)
		end
	end

	local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["not ignored"]}, SkuGenericMenuItem)
	tNewMenuEntry.dynamic = true
	tNewMenuEntry.sorting = true
	tNewMenuEntry.isSelect = true
	tNewMenuEntry.OnAction = function(self, aValue, aName)
		SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tUnitType].debuffs.ignored[self.spellName] = true
	end
	tNewMenuEntry.BuildChildren = function(self)
		local tFoundNames = {}
		for spellId, spellData in pairs(SkuDB.SpellDataTBC) do
			local spellName = spellData[Sku.Loc][SkuDB.spellKeys["name_lang"]]
			if not SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet][tUnitType].debuffs.ignored[spellName] then
				if not tFoundNames[spellName] then
					tFoundNames[spellName] = true
					local tSpellEntry = SkuOptions:InjectMenuItems(self, {spellName}, SkuGenericMenuItem)
					tSpellEntry.dynamic = true
					tSpellEntry.BuildChildren = function(self)
						local tActionEntry = SkuOptions:InjectMenuItems(self, {L["add to ignore list"]}, SkuGenericMenuItem)
						tActionEntry.OnEnter = function(self, aValue, aName)
							self.selectTarget.spellName = spellName
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function Aq:MonitorMenuBuilder()
   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Global"]}, SkuGenericMenuItem)
	tNewMenuEntry.dynamic = true
	tNewMenuEntry.BuildChildren = function(self)
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Unit number first"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.sorting = true
		tNewMenuEntry.isSelect = true
		tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
			if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].global.numberFirst == true then
				return L["Yes"]
			else
				return L["No"]
			end
		end
		tNewMenuEntry.OnAction = function(self, aValue, aName)
			if aName == L["No"] then
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].global.numberFirst = false
			elseif aName == L["Yes"] then
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].global.numberFirst = true
			end
		end
		tNewMenuEntry.BuildChildren = function(self)
			SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
			SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
		end
		
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Only unit numbers"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.sorting = true
		tNewMenuEntry.isSelect = true
		tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
			if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].global.numberOnly == true then
				return L["Yes"]
			else
				return L["No"]
			end
		end
		tNewMenuEntry.OnAction = function(self, aValue, aName)
			if aName == L["No"] then
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].global.numberOnly = false
			elseif aName == L["Yes"] then
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].global.numberOnly = true
			end
		end
		tNewMenuEntry.BuildChildren = function(self)
			SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
			SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
		end		
	end

	--player
   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["player"]}, SkuGenericMenuItem)
	tNewMenuEntry.dynamic = true
	tNewMenuEntry.BuildChildren = function(self)
		--health
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Health"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.BuildChildren = function(self)
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Enabled"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.enabled == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.enabled = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.enabled = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Factor in incoming heals"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.factorInIncomingHeals == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.factorInIncomingHeals = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.factorInIncomingHeals = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Enable in dungeons/raids only"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.instancesOnly == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.instancesOnly = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.instancesOnly = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous output start at"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if aName == -1 then
					return L["Never"]
				else
					return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.continouslyStartAt
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["Never"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.continouslyStartAt = -1
				else
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.continouslyStartAt = tonumber(aName)
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Never"]}, SkuGenericMenuItem)
				for x = 0, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous output every seconds"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.continouslyTimer
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.continouslyTimer = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, 60 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Silent on 100 and 0 percent"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.silentOn100and0 == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.silentOn100and0 = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.silentOn100and0 = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end
			

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous volume"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.continouslyVolume
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.continouslyVolume = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 10, 100, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Event volume"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.eventVolume
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.eventVolume = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 10, 100, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end
			
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Event Steps"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return tonumber(SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.steps)
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.steps = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {10}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {5}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {2}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Voice"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.voice].name
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				for x = 1, #tVoices do
					if aName == tVoices[x].name then
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.voice = x
					end
				end
				C_Timer.After(0.001, function()
					SkuOptions.currentMenuPosition.parent:OnUpdate(SkuOptions.currentMenuPosition.parent)						
				end)				
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, #tVoices do
					SkuOptions:InjectMenuItems(self, {tVoices[x].name}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Buy "]..tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.voice].name..L[" ice cream"]}, SkuGenericMenuItem)
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				local willPlay, tPrevOutputHandle = PlaySoundFile("Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\aq\\"..tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.voice].path.."\\"..tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.voice].path.."_yay_"..SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.eventVolume..".mp3", SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel or "Talking Head")
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.health.iceCreamBought = true
			end			
		end
		--power
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Power"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.BuildChildren = function(self)
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Enabled"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.enabled == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.enabled = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.enabled = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Power Type"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				for i, v in pairs(tPowerTypes) do
					if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.type == i then
						return v.name
					end
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				for i, v in pairs(tPowerTypes) do
					if aName == v.name then
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.type = i
					end
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				for i, v in pairs(tPowerTypes) do
					SkuOptions:InjectMenuItems(self, {v.name}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Enable in dungeons/raids only"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.instancesOnly == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.instancesOnly = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.instancesOnly = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous output start at"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if aName == -1 then
					return L["Never"]
				else
					return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.continouslyStartAt
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["Never"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.continouslyStartAt = -1
				else
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.continouslyStartAt = tonumber(aName)
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Never"]}, SkuGenericMenuItem)
				for x = 0, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous output every seconds"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.continouslyTimer
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.continouslyTimer = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, 60 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Silent on 100 and 0 percent"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.silentOn100and0 == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.silentOn100and0 = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.silentOn100and0 = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end
			

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous volume"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.continouslyVolume
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.continouslyVolume = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 10, 100, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Event volume"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.eventVolume
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.eventVolume = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 10, 100, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end
			
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Event Steps"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return tonumber(SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.steps)
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.steps = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {10}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {5}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {2}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Voice"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.voice].name
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				for x = 1, #tVoices do
					if aName == tVoices[x].name then
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.power.voice = x
					end
				end
				C_Timer.After(0.001, function()
					SkuOptions.currentMenuPosition.parent:OnUpdate(SkuOptions.currentMenuPosition.parent)						
				end)				
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, #tVoices do
					SkuOptions:InjectMenuItems(self, {tVoices[x].name}, SkuGenericMenuItem)
				end
			end
		end

		--debuffs
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Debuffs"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.BuildChildren = function(self)
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Enabled"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.enabled == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.enabled = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.enabled = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["debuff types"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["Enabled"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.types[self.itemName] = true
				else
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.types[self.itemName] = false
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				for i, v in pairs(tDebuffTypes) do
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {v}, SkuGenericMenuItem)
					tNewMenuEntry.dynamic = true
					tNewMenuEntry.OnEnter = function(self, aValue, aName)
						self.selectTarget.itemName = i
					end
					tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
						if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.types[i] == true then
							return L["Enabled"]
						else
							return L["disabled"]
						end
					end
					tNewMenuEntry.BuildChildren = function(self)
						SkuOptions:InjectMenuItems(self, {L["Enabled"]}, SkuGenericMenuItem)
						SkuOptions:InjectMenuItems(self, {L["disabled"]}, SkuGenericMenuItem)
					end
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["ignored debuffs"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.BuildChildren = MonitorSpellMenuBuilder

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Enable in dungeons/raids only"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.instancesOnly == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.instancesOnly = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.instancesOnly = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end
			
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous output starts after seconds"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if aName == -1 then
					return L["Never"]
				else
					return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.continouslyStartAfter
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["Never"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.continouslyStartAfter = -1
				else
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.continouslyStartAfter = tonumber(aName)
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Never"]}, SkuGenericMenuItem)
				for x = 0, 50 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous output every seconds"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.continouslyTimer
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.continouslyTimer = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, 60 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous volume"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.continouslyVolume
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.continouslyVolume = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 10, 100, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end
			
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Event volume"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.eventVolume
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.eventVolume = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 10, 100, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Voice"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.voice].name
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				for x = 1, #tVoices do
					if aName == tVoices[x].name then
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].player.debuffs.voice = x
					end
				end
				C_Timer.After(0.001, function()
					SkuOptions.currentMenuPosition.parent:OnUpdate(SkuOptions.currentMenuPosition.parent)						
				end)				
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, #tVoices do
					SkuOptions:InjectMenuItems(self, {tVoices[x].name}, SkuGenericMenuItem)
				end
			end
		end		
	end

	--pet
	local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Pet"]}, SkuGenericMenuItem)
	tNewMenuEntry.dynamic = true
	tNewMenuEntry.BuildChildren = function(self)
		--health
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Health"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.BuildChildren = function(self)
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Enabled"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.enabled == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.enabled = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.enabled = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Factor in incoming heals"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.factorInIncomingHeals == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.factorInIncomingHeals = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.factorInIncomingHeals = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Enable in dungeons/raids only"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.instancesOnly == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.instancesOnly = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.instancesOnly = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous output start at"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if aName == -1 then
					return L["Never"]
				else
					return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.continouslyStartAt
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["Never"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.continouslyStartAt = -1
				else
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.continouslyStartAt = tonumber(aName)
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Never"]}, SkuGenericMenuItem)
				for x = 0, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous output every seconds"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.continouslyTimer
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.continouslyTimer = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, 60 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Silent on 100 and 0 percent"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.silentOn100and0 == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.silentOn100and0 = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.silentOn100and0 = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end
			

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous volume"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.continouslyVolume
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.continouslyVolume = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 10, 100, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Event volume"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.eventVolume
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.eventVolume = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 10, 100, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end
			
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Event Steps"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return tonumber(SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.steps)
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.steps = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {10}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {5}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {2}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Voice"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.voice].name
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				for x = 1, #tVoices do
					if aName == tVoices[x].name then
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].pet.health.voice = x
					end
				end
				C_Timer.After(0.001, function()
					SkuOptions.currentMenuPosition.parent:OnUpdate(SkuOptions.currentMenuPosition.parent)						
				end)				
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, #tVoices do
					SkuOptions:InjectMenuItems(self, {tVoices[x].name}, SkuGenericMenuItem)
				end
			end
		end
	end

	--party
   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Party"]}, SkuGenericMenuItem)
	tNewMenuEntry.dynamic = true
	tNewMenuEntry.BuildChildren = function(self)
		--health
		--[[
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Health Chord Style"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.BuildChildren = function(self)
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Enabled"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.enabled == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.enabled = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.enabled = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Enable in dungeons/raids only"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.instancesOnly == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.instancesOnly = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.instancesOnly = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous output"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.continouslyEnabled == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.continouslyEnabled = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.continouslyEnabled = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous output every seconds"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.continouslyTimer
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.continouslyTimer = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, 60 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Silent on all at 100 percent"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.silentAtAll100 == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.silentAtAll100 = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.silentAtAll100 = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Speed"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.continouslySpeed
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.continouslySpeed = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 20, 100 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Include self"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.includeSelf == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.includeSelf = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health.includeSelf = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end			
		end
		]]

		--party health 2
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Health Pitch style"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.BuildChildren = function(self)
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Enabled"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.enabled == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.enabled = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.enabled = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Factor in incoming heals"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.factorInIncomingHeals == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.factorInIncomingHeals = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.factorInIncomingHeals = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Role assignment"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.BuildChildren = function(self)
				local tPartyMembers = {
					[1] = L["party member"].." "..1,
					[2] = L["party member"].." "..2,
					[3] = L["party member"].." "..3,
					[4] = L["party member"].." "..4,
					[5] = L["party member"].." "..5,
				}

				for x = 1, #tPartyMembers do
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tPartyMembers[x]}, SkuGenericMenuItem)
					tNewMenuEntry.dynamic = true
					tNewMenuEntry.isSelect = true
					tNewMenuEntry.OnAction = function(self, aValue, aName)
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.roleAssigments[x] = 0
						for w = 1, #tRoles do
							if aName == tRoles[w] then
								SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.roleAssigments[x] = w
							end
						end
					end
					tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
						if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.roleAssigments[x] == 0 then
							return L["Auto"]
						else
							return tRoles[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.roleAssigments[x]]
						end
					end
					tNewMenuEntry.BuildChildren = function(self)
						SkuOptions:InjectMenuItems(self, {L["Auto"]}, SkuGenericMenuItem)
						for q = 1, #tRoles do
							SkuOptions:InjectMenuItems(self, {tRoles[q]}, SkuGenericMenuItem)
						end
					end
				end

				local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Set all to auto"]}, SkuGenericMenuItem)
				tNewMenuEntry.isSelect = true
				tNewMenuEntry.OnAction = function(self, aValue, aName)
					for x = 1, #tPartyMembers do
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.roleAssigments[x] = 0
					end
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous output start at"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, #tRoles do
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tRoles[x]}, SkuGenericMenuItem)
					tNewMenuEntry.dynamic = true
					tNewMenuEntry.isSelect = true
					tNewMenuEntry.OnAction = function(self, aValue, aName)
						if aName == L["Never"] then
							SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.continouslyStartAt[x] = 0
						else
							SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.continouslyStartAt[x] = tonumber(aName)
						end
					end
					tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
						return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.continouslyStartAt[x]
					end
					tNewMenuEntry.BuildChildren = function(self)
						SkuOptions:InjectMenuItems(self, {L["Never"]}, SkuGenericMenuItem)
						for x = 10, 100, 10 do
							SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
						end
					end
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous output every seconds"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.continouslyTimer
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.continouslyTimer = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 2, 60 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Event output filters"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, #tRoles do
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tRoles[x]}, SkuGenericMenuItem)
					tNewMenuEntry.dynamic = true
					tNewMenuEntry.BuildChildren = function(self)
						for i, v in pairs(tEventOutputFilters) do
							local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {v.name}, SkuGenericMenuItem)
							tNewMenuEntry.dynamic = true
							tNewMenuEntry.isSelect = true
							tNewMenuEntry.OnAction = function(self, aValue, aName)
								SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.eventOutputFilters[x][v.id] = tonumber(aName)
							end
							tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
								return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.eventOutputFilters[x][v.id]
							end
							tNewMenuEntry.BuildChildren = function(self)
								for i1, v1 in pairs(v.values) do
									local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {v1}, SkuGenericMenuItem)
								end
							end
						end
					end
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Prio output"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, #tRoles do
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tRoles[x]}, SkuGenericMenuItem)
					tNewMenuEntry.dynamic = true
					tNewMenuEntry.isSelect = true
					tNewMenuEntry.OnAction = function(self, aValue, aName)
						if aName == L["No"] then
							SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.prioOutput[x] = false
						elseif aName == L["Yes"] then
							SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.prioOutput[x] = true
						end
					end
					tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
						if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.prioOutput[x] == false then
							return L["No"]
						elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.prioOutput[x] == true then
							return L["Yes"]
						end
					end
					tNewMenuEntry.BuildChildren = function(self)
						SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
						SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
					end
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Silent on 100 and 0 percent"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.silentOn100and0 == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.silentOn100and0 = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.silentOn100and0 = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Add sound on 100 percent"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.addSoundOn100Percent == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.addSoundOn100Percent = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.addSoundOn100Percent = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end		
			
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Add Dead on 0 percent"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.addDeadOn0Percent == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.addDeadOn0Percent = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.addDeadOn0Percent = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end				
			
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous volume"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.continouslyVolume
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.continouslyVolume = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 10, 100, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Event volume"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.eventVolume
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.eventVolume = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 10, 100, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Percent delay for next output in queue"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.outputQueueDelay
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.health2.outputQueueDelay = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 20, 150, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end
		end		

		--party debuffs
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Debuffs"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.BuildChildren = function(self)
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Enabled"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.enabled == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.enabled = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.enabled = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["debuff types"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["Enabled"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.types[self.itemName] = true
				else
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.types[self.itemName] = false
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				for i, v in pairs(tDebuffTypes) do
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {v}, SkuGenericMenuItem)
					tNewMenuEntry.dynamic = true
					tNewMenuEntry.OnEnter = function(self, aValue, aName)
						self.selectTarget.itemName = i
					end
					tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
						if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.types[i] == true then
							return L["Enabled"]
						else
							return L["disabled"]
						end
					end
					tNewMenuEntry.BuildChildren = function(self)
						SkuOptions:InjectMenuItems(self, {L["Enabled"]}, SkuGenericMenuItem)
						SkuOptions:InjectMenuItems(self, {L["disabled"]}, SkuGenericMenuItem)
					end
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["ignored debuffs"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.BuildChildren = MonitorSpellMenuBuilder

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Enable in dungeons/raids only"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.instancesOnly == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.instancesOnly = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.instancesOnly = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end
			
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous output starts after seconds"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if aName == -1 then
					return L["Never"]
				else
					return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.continouslyStartAfter
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["Never"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.continouslyStartAfter = -1
				else
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.continouslyStartAfter = tonumber(aName)
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Never"]}, SkuGenericMenuItem)
				for x = 0, 50 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Output style"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.toutputStyle = 1
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return tOutputStyles[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.outputStyle]
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.outputStyle = self.toutputStyle
				C_Timer.After(0.001, function()
					SkuOptions.currentMenuPosition.parent:OnUpdate(SkuOptions.currentMenuPosition.parent)						
				end)				
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, #tOutputStyles do
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tOutputStyles[x]}, SkuGenericMenuItem)
					tNewMenuEntry.OnEnter = function(self, aValue, aName)
						self.selectTarget.toutputStyle = x
					end
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous output every seconds"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.continouslyTimer
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.continouslyTimer = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, 60 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous volume"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.continouslyVolume
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.continouslyVolume = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 10, 100, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end
			
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Event volume"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.eventVolume
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.eventVolume = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 10, 100, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Voice"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.voice].name
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				for x = 1, #tVoices do
					if aName == tVoices[x].name then
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].party.debuffs.voice = x
					end
				end
				C_Timer.After(0.001, function()
					SkuOptions.currentMenuPosition.parent:OnUpdate(SkuOptions.currentMenuPosition.parent)						
				end)				
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, #tVoices do
					SkuOptions:InjectMenuItems(self, {tVoices[x].name}, SkuGenericMenuItem)
				end
			end
		end			
	end

	--raid
   local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Raid"]}, SkuGenericMenuItem)
	tNewMenuEntry.dynamic = true
	tNewMenuEntry.BuildChildren = function(self)
		--health
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Health"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.BuildChildren = function(self)
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Enabled"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.enabled == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.enabled = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.enabled = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Factor in incoming heals"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.factorInIncomingHeals == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.factorInIncomingHeals = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.factorInIncomingHeals = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Role assignment"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.BuildChildren = function(self)
				local traidMembers = {}

				local tHasEntries
				for x = 1, MAX_RAID_MEMBERS do
					if tDTRaidRoster["raid"..x] then
						local tUnitName = UnitName("raid"..x)
						local className = UnitClass("raid"..x)
						traidMembers[tDTRaidRoster["raid"..x]] = tDTRaidRoster["raid"..x]..": "..className.." "..tUnitName
						tHasEntries = true
					end
				end

				if not tHasEntries then
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty"]}, SkuGenericMenuItem)
				else
					for x = 1, MAX_RAID_MEMBERS do
						if traidMembers[x] then
							local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {traidMembers[x]}, SkuGenericMenuItem)
							tNewMenuEntry.dynamic = true
							tNewMenuEntry.isSelect = true
							tNewMenuEntry.OnAction = function(self, aValue, aName)
								SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.roleAssigments[x] = 0
								for w = 1, #tRoles do
									if aName == tRoles[w] then
										SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.roleAssigments[x] = w
									end
								end
							end
							tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
								if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.roleAssigments[x] == 0 then
									return L["Auto"]
								else
									return tRoles[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.roleAssigments[x]]
								end
							end
							tNewMenuEntry.BuildChildren = function(self)
								SkuOptions:InjectMenuItems(self, {L["Auto"]}, SkuGenericMenuItem)
								for q = 1, #tRoles do
									SkuOptions:InjectMenuItems(self, {tRoles[q]}, SkuGenericMenuItem)
								end
							end
						end
					end

					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Set all to auto"]}, SkuGenericMenuItem)
					tNewMenuEntry.isSelect = true
					tNewMenuEntry.OnAction = function(self, aValue, aName)
						for x = 1, #traidMembers do
							SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.roleAssigments[x] = 0
						end
					end
				end
			end


			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Subgroups selection"]}, SkuGenericMenuItem)
         local tSortedList = {}
         for k, v in SkuSpairs(SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.unitsAndSubgroupsSelection, function(t,a,b) 
				return a < b
			end) do 
				tSortedList[#tSortedList+1] = k
			end
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				local tsubstring = string.sub(aName, 1, string.find(aName, " %(") - 1)
				if tsubstring and SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.unitsAndSubgroupsSelection[tsubstring] ~= nil then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.unitsAndSubgroupsSelection[tsubstring] = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.unitsAndSubgroupsSelection[tsubstring] ~= true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				local tNewMenuEntryEnabled = SkuOptions:InjectMenuItems(self, {L["Enabled"]}, SkuGenericMenuItem)
				tNewMenuEntryEnabled.dynamic = true
				tNewMenuEntryEnabled.BuildChildren = function(self)
					local tNewMenuEntryEnabledHasEntries
					for w = 1, #tSortedList do
						local tUnit, tValue = tSortedList[w], SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.unitsAndSubgroupsSelection[tSortedList[w]]
						if tValue == true then
							local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tUnit.." ("..L["Select to disable"]..")"}, SkuGenericMenuItem)
							tNewMenuEntryEnabledHasEntries = true
						end
					end
					if not tNewMenuEntryEnabledHasEntries then
						local tNewMenuEntry = SkuOptions:InjectMenuItems(tNewMenuEntryEnabled, {L["empty"]}, SkuGenericMenuItem)
					end
				end
				local tNewMenuEntryDisabled = SkuOptions:InjectMenuItems(self, {L["disabled"].." ("..L["overrides enabled"]..")"}, SkuGenericMenuItem)
				tNewMenuEntryDisabled.dynamic = true
				tNewMenuEntryDisabled.BuildChildren = function(self)
					local tNewMenuEntryDisabledHasEntries
					for w = 1, #tSortedList do
						local tUnit, tValue = tSortedList[w], SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.unitsAndSubgroupsSelection[tSortedList[w]]
						if tValue == false then
							local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tUnit.." ("..L["Select to enable"]..")"}, SkuGenericMenuItem)
							tNewMenuEntryDisabledHasEntries = true
						end
					end
					if not tNewMenuEntryDisabledHasEntries then
						local tNewMenuEntry = SkuOptions:InjectMenuItems(tNewMenuEntryDisabled, {L["empty"]}, SkuGenericMenuItem)
					end
				end
			end


			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous output start at"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, #tRoles do
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tRoles[x]}, SkuGenericMenuItem)
					tNewMenuEntry.dynamic = true
					tNewMenuEntry.isSelect = true
					tNewMenuEntry.OnAction = function(self, aValue, aName)
						if aName == L["Never"] then
							SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.continouslyStartAt[x] = 0
						else
							SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.continouslyStartAt[x] = tonumber(aName)
						end
					end
					tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
						return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.continouslyStartAt[x]
					end
					tNewMenuEntry.BuildChildren = function(self)
						SkuOptions:InjectMenuItems(self, {L["Never"]}, SkuGenericMenuItem)
						for x = 10, 100, 10 do
							SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
						end
					end
				end
			end


			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous output every seconds"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.continouslyTimer
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.continouslyTimer = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 2, 60 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end


			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Event output filters"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, #tRoles do
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tRoles[x]}, SkuGenericMenuItem)
					tNewMenuEntry.dynamic = true
					tNewMenuEntry.BuildChildren = function(self)
						for i, v in pairs(tEventOutputFilters) do
							local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {v.name}, SkuGenericMenuItem)
							tNewMenuEntry.dynamic = true
							tNewMenuEntry.isSelect = true
							tNewMenuEntry.OnAction = function(self, aValue, aName)
								SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.eventOutputFilters[x][v.id] = tonumber(aName)
							end
							tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
								return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.eventOutputFilters[x][v.id]
							end
							tNewMenuEntry.BuildChildren = function(self)
								for i1, v1 in pairs(v.values) do
									local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {v1}, SkuGenericMenuItem)
								end
							end
						end
					end
				end
			end


			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Prio output"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, #tRoles do
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tRoles[x]}, SkuGenericMenuItem)
					tNewMenuEntry.dynamic = true
					tNewMenuEntry.isSelect = true
					tNewMenuEntry.OnAction = function(self, aValue, aName)
						if aName == L["No"] then
							SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prioOutput[x] = false
						elseif aName == L["Yes"] then
							SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prioOutput[x] = true
						end
					end
					tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
						if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prioOutput[x] == false then
							return L["No"]
						elseif SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.prioOutput[x] == true then
							return L["Yes"]
						end
					end
					tNewMenuEntry.BuildChildren = function(self)
						SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
						SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
					end
				end
			end


			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Silent on 100 and 0 percent"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.silentOn100and0 == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.silentOn100and0 = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.silentOn100and0 = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end


			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Add sound on 100 percent"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.addSoundOn100Percent == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.addSoundOn100Percent = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.addSoundOn100Percent = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end		
			

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Add Dead on 0 percent"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.addDeadOn0Percent == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.addDeadOn0Percent = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.addDeadOn0Percent = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end				
			

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous volume"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.continouslyVolume
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.continouslyVolume = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 10, 100, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end


			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Event volume"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.eventVolume
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.eventVolume = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 10, 100, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end


			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Percent delay for next output in queue"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.outputQueueDelay
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.health2.outputQueueDelay = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 20, 150, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end
		end		

		--debuffs
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Debuffs"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.BuildChildren = function(self)
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Enabled"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.enabled == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.enabled = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.enabled = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["debuff types"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["Enabled"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.types[self.itemName] = true
				else
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.types[self.itemName] = false
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				for i, v in pairs(tDebuffTypes) do
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {v}, SkuGenericMenuItem)
					tNewMenuEntry.dynamic = true
					tNewMenuEntry.OnEnter = function(self, aValue, aName)
						self.selectTarget.itemName = i
					end
					tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
						if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.types[i] == true then
							return L["Enabled"]
						else
							return L["disabled"]
						end
					end
					tNewMenuEntry.BuildChildren = function(self)
						SkuOptions:InjectMenuItems(self, {L["Enabled"]}, SkuGenericMenuItem)
						SkuOptions:InjectMenuItems(self, {L["disabled"]}, SkuGenericMenuItem)
					end
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["ignored debuffs"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.BuildChildren = MonitorSpellMenuBuilder

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Enable in dungeons/raids only"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.instancesOnly == true then
					return L["Yes"]
				else
					return L["No"]
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["No"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.instancesOnly = false
				elseif aName == L["Yes"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.instancesOnly = true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
				SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			end
			


			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Subgroups selection"]}, SkuGenericMenuItem)
         local tSortedList = {}
         for k, v in SkuSpairs(SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.unitsAndSubgroupsSelection, function(t,a,b) 
				return a < b
			end) do 
				tSortedList[#tSortedList+1] = k
			end
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				local tsubstring = string.sub(aName, 1, string.find(aName, " %(") - 1)
				if tsubstring and SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.unitsAndSubgroupsSelection[tsubstring] ~= nil then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.unitsAndSubgroupsSelection[tsubstring] = SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.unitsAndSubgroupsSelection[tsubstring] ~= true
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				local tNewMenuEntryEnabled = SkuOptions:InjectMenuItems(self, {L["Enabled"]}, SkuGenericMenuItem)
				tNewMenuEntryEnabled.dynamic = true
				tNewMenuEntryEnabled.BuildChildren = function(self)
					local tNewMenuEntryEnabledHasEntries
					for w = 1, #tSortedList do
						local tUnit, tValue = tSortedList[w], SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.unitsAndSubgroupsSelection[tSortedList[w]]
						if tValue == true then
							local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tUnit.." ("..L["Select to disable"]..")"}, SkuGenericMenuItem)
							tNewMenuEntryEnabledHasEntries = true
						end
					end
					if not tNewMenuEntryEnabledHasEntries then
						local tNewMenuEntry = SkuOptions:InjectMenuItems(tNewMenuEntryEnabled, {L["empty"]}, SkuGenericMenuItem)
					end
				end
				local tNewMenuEntryDisabled = SkuOptions:InjectMenuItems(self, {L["disabled"].." ("..L["overrides enabled"]..")"}, SkuGenericMenuItem)
				tNewMenuEntryDisabled.dynamic = true
				tNewMenuEntryDisabled.BuildChildren = function(self)
					local tNewMenuEntryDisabledHasEntries
					for w = 1, #tSortedList do
						local tUnit, tValue = tSortedList[w], SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.unitsAndSubgroupsSelection[tSortedList[w]]
						if tValue == false then
							local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tUnit.." ("..L["Select to enable"]..")"}, SkuGenericMenuItem)
							tNewMenuEntryDisabledHasEntries = true
						end
					end
					if not tNewMenuEntryDisabledHasEntries then
						local tNewMenuEntry = SkuOptions:InjectMenuItems(tNewMenuEntryDisabled, {L["empty"]}, SkuGenericMenuItem)
					end
				end
			end




			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous output starts after seconds"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				if aName == -1 then
					return L["Never"]
				else
					return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.continouslyStartAfter
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				if aName == L["Never"] then
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.continouslyStartAfter = -1
				else
					SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.continouslyStartAfter = tonumber(aName)
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Never"]}, SkuGenericMenuItem)
				for x = 0, 50 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Output style"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.toutputStyle = 1
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return tOutputStyles[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.outputStyle]
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.outputStyle = self.toutputStyle
				C_Timer.After(0.001, function()
					SkuOptions.currentMenuPosition.parent:OnUpdate(SkuOptions.currentMenuPosition.parent)						
				end)				
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, #tOutputStyles do
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tOutputStyles[x]}, SkuGenericMenuItem)
					tNewMenuEntry.OnEnter = function(self, aValue, aName)
						self.selectTarget.toutputStyle = x
					end
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous output every seconds"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.continouslyTimer
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.continouslyTimer = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, 60 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Continuous volume"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.continouslyVolume
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.continouslyVolume = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 10, 100, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end
			
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Event volume"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.eventVolume
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.eventVolume = tonumber(aName)
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 10, 100, 10 do
					SkuOptions:InjectMenuItems(self, {x}, SkuGenericMenuItem)
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Voice"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.sorting = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
				return tVoices[SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.voice].name
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				for x = 1, #tVoices do
					if aName == tVoices[x].name then
						SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet].raid.debuffs.voice = x
					end
				end
				C_Timer.After(0.001, function()
					SkuOptions.currentMenuPosition.parent:OnUpdate(SkuOptions.currentMenuPosition.parent)						
				end)				
			end
			tNewMenuEntry.BuildChildren = function(self)
				for x = 1, #tVoices do
					SkuOptions:InjectMenuItems(self, {tVoices[x].name}, SkuGenericMenuItem)
				end
			end
		end			
	end


	--combat
	local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Combat"]}, SkuGenericMenuItem)
	tNewMenuEntry.dynamic = true
	tNewMenuEntry.sorting = true
	tNewMenuEntry.BuildChildren = SkuCore.aqCombat.aqCombatMenuBuilder

	-- Entfernung (Reichweiten-Checks): relocated here from the Kampf menu. Reuses the
	-- shared RangecheckMenuBuilder exposed by SkuCore\Options.lua.
	local tRangeEntry = SkuOptions:InjectMenuItems(self, {L["Entfernung"]}, SkuGenericMenuItem)
	tRangeEntry.dynamic = true
	tRangeEntry.BuildChildren = function(self)
		local tFriendly = SkuOptions:InjectMenuItems(self, {L["Freundlich"]}, SkuGenericMenuItem)
		tFriendly.dynamic = true
		tFriendly.BuildChildren = function(self)
			SkuCore.RangecheckMenuBuilder(self, "Friendly")
		end
		local tHostile = SkuOptions:InjectMenuItems(self, {L["Feindlich"]}, SkuGenericMenuItem)
		tHostile.dynamic = true
		tHostile.BuildChildren = function(self)
			SkuCore.RangecheckMenuBuilder(self, "Hostile")
		end
		local tMisc = SkuOptions:InjectMenuItems(self, {L["Unbekannt"]}, SkuGenericMenuItem)
		tMisc.dynamic = true
		tMisc.BuildChildren = function(self)
			SkuCore.RangecheckMenuBuilder(self, "Misc")
		end
	end

	-- Fall detection ("Fallerkennungs Einstellungen"): relocated here from the
	-- Einstellungen -> Sonstiges menu (flagged forAudioMenu=false there, so
	-- aIncludeHidden=true is needed to render it). Same db/keyPrefix -> saved values.
	if SkuCore.options and SkuCore.options.args then
		SkuOptions:IterateOptionsArgs({
			fallSettings = SkuCore.options.args.fallSettings,
		}, self, SkuSettings:Sub("SkuCore"), "SkuCore", "", true)
	end

	-- Error feedback ("Fehlerfeedback"): custom nested builder (per category: TTS
	-- voice / Sprachhinweis / Tonhinweis / Stumm). Replaces the old flat select
	-- list; same saved values (SkuCore.UIErrors.*), fully backward compatible. See
	-- SkuCore.UIErrors:MenuBuilder in SkuCore/UIErrors.lua.
	if SkuCore.UIErrors and SkuCore.UIErrors.MenuBuilder then
		local tErrFb = SkuOptions:InjectMenuItems(self, {L["Error feedback"]}, SkuGenericMenuItem)
		tErrFb.dynamic = true
		tErrFb.sorting = false
		tErrFb.BuildChildren = SkuCore.UIErrors.MenuBuilder
	end

	-- Quest notifications ("Quest Benachrichtigungen"): MIRRORED here (also still shown
	-- under Einstellungen -> Quest). Same args/db/keyPrefix, so both locations edit the
	-- exact same saved values.
	if SkuQuest and SkuQuest.options and SkuQuest.options.args and SkuQuest.options.args.questMarkerBeacons then
		SkuOptions:IterateOptionsArgs({
			questMarkerBeacons = SkuQuest.options.args.questMarkerBeacons,
		}, self, SkuSettings:Sub("SkuQuest"), "SkuQuest")
	end

	-- Ziel Optionen (SkuMob's target options): relocated here from Einstellungen -> Kampf.
	-- Same args/db -> saved values preserved.
	if SkuMob and SkuMob.options and SkuMob.options.args then
		local tTargetOpts = SkuOptions:InjectMenuItems(self, {Sku.deEn("Ziel Optionen", "Target options")}, SkuGenericMenuItem)
		tTargetOpts.dynamic = true
		tTargetOpts.sorting = true
		tTargetOpts.BuildChildren = function(self)
			SkuOptions:IterateOptionsArgs(SkuMob.options.args, self, SkuSettings:Sub("SkuMob"), "SkuMob")
		end
	end

end