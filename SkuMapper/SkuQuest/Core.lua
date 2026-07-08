---@diagnostic disable: undefined-global
local MODULE_NAME = "SkuQuest"
local _G = _G

SkuQuest = LibStub("AceAddon-3.0"):NewAddon("SkuQuest", "AceConsole-3.0", "AceEvent-3.0")
local L = Sku.L

---------------------------------------------------------------------------------------------------------------------------------------
function SkuQuest:OnInitialize()
	SkuQuest:RegisterEvent("PLAYER_ENTERING_WORLD")
	SkuQuest:RegisterEvent("PLAYER_LOGIN")
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuQuest:OnEnable()

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuQuest:OnDisable()
	
end

---------------------------------------------------------------------------------------------------------------------------------------

local function applyItemSpecificDataChangesHorde()
	SkuDB.itemDataTBC[56188][SkuDB.itemKeys.objectDrops] = {203410}
	SkuDB.itemDataTBC[71034][SkuDB.itemKeys.objectDrops] = {209058}
end

local function applyQuestSpecificDataChangesHorde()
	SkuDB.questDataTBC[12318][SkuDB.questKeys.startedBy] = {}
	SkuDB.questDataTBC[25619][SkuDB.questKeys.preQuestSingle] = {}
	SkuDB.questDataTBC[25619][SkuDB.questKeys.preQuestGroup] = {25952,25953,25954,25955,25956}
	SkuDB.questDataTBC[25858][SkuDB.questKeys.objectives] = {{{42072,nil,5},{42071,nil,5},{41455,nil,5}}}
	SkuDB.questDataTBC[25858][SkuDB.questKeys.preQuestSingle] = {}
	SkuDB.questDataTBC[25858][SkuDB.questKeys.preQuestGroup] = {25964,25965}
	SkuDB.questDataTBC[25629][SkuDB.questKeys.preQuestSingle] = {25973}
	SkuDB.questDataTBC[25896][SkuDB.questKeys.preQuestSingle] = {25973}
	SkuDB.questDataTBC[26111][SkuDB.questKeys.preQuestSingle] = {}
	SkuDB.questDataTBC[26111][SkuDB.questKeys.preQuestGroup] = {26071,26072,26096}
	SkuDB.questDataTBC[26191][SkuDB.questKeys.nextQuestInChain] = {25967}
	SkuDB.questDataTBC[27203][SkuDB.questKeys.startedBy] = {{45244}}
	SkuDB.questDataTBC[29389][SkuDB.questKeys.preQuestGroup] = {25612,25807,25520,25372}
	SkuDB.questDataTBC[29475][SkuDB.questKeys.startedBy] = {{11017,11031,16667,29513,52651}}
	SkuDB.questDataTBC[29475][SkuDB.questKeys.finishedBy] = {{11017,11031,16667,29513,52651}}
	SkuDB.questDataTBC[29475][SkuDB.questKeys.exclusiveTo] = {3526,3629,3633,4181,29476,29477,3630,3632,3634,3635,3637}
	SkuDB.questDataTBC[29477][SkuDB.questKeys.startedBy] = {{11017,11031,16667,29513,52651}}
	SkuDB.questDataTBC[29477][SkuDB.questKeys.finishedBy] = {{11017,11031,16667,29513,52651}}
	SkuDB.questDataTBC[29477][SkuDB.questKeys.exclusiveTo] = {3630,3632,3634,3635,3637,29475,29476,3526,3629,3633,4181}
	SkuDB.questDataTBC[29836][SkuDB.questKeys.exclusiveTo] = {13099}
	SkuDB.questDataTBC[29836][SkuDB.questKeys.nextQuestInChain] = 29840
end

local function applyObjectSpecificDataChangesHorde()
	SkuDB.objectDataTBC[186189][SkuDB.objectKeys.spawns] = {[SkuDB.zoneIDs.DUROTAR]={{41.56,17.56},{41.52,17.5},{41.39,17.42},{40.74,16.82},{40.34,16.81},{40.13,17.48},{40.39,18.04},{40.85,18.28},{40.9,18.31}}}
	SkuDB.objectDataTBC[203461][SkuDB.objectKeys.spawns] = {[SkuDB.zoneIDs.ABYSSAL_DEPTHS]={{51.49,60.41}}}
end

local function applyNpcSpecificDataChangesHorde()
	SkuDB.NpcData.Data[24108][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.DUROTAR] = {{41.74,17.2}}}
	SkuDB.NpcData.Data[24202][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.ORGRIMMAR]={{51.41,78.7}}}
	SkuDB.NpcData.Data[24203][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.ORGRIMMAR]={{67.64,47.83}}}
	SkuDB.NpcData.Data[24204][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.ORGRIMMAR]={{44.18,48.95}}}
	SkuDB.NpcData.Data[24205][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.ORGRIMMAR]={{37.68,75.58}}}
	SkuDB.NpcData.Data[26221][SkuDB.NpcData.Keys.spawns] = {
                [SkuDB.zoneIDs.TIRISFAL_GLADES]={{62.01,67.92}},
                [SkuDB.zoneIDs.ORGRIMMAR]={{47.26,37.89}},
                [SkuDB.zoneIDs.THUNDER_BLUFF]={{21.21,24.06}},
                [SkuDB.zoneIDs.SHATTRATH_CITY]={{60.68,30.62}},
                [SkuDB.zoneIDs.SILVERMOON_CITY]={{68.67,42.94}},
            }
	SkuDB.NpcData.Data[29579][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.STORM_PEAKS] = {{36.62,49.27}}}
	SkuDB.NpcData.Data[34907][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.HROTHGARS_LANDING]={{43.43,53.57},{43.1,53.5},{42.94,53.83},{43.92,54.36},{44.07,54.44},{43.82,54.64},{42.62,53.3},{42.85,53.33},{44.23,54.41},{43.36,53.87}}}
	SkuDB.NpcData.Data[34947][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.HROTHGARS_LANDING]={{43.43,53.57},{43.1,53.5},{42.94,53.83},{43.92,54.36},{44.07,54.44},{43.82,54.64},{42.62,53.3},{42.85,53.33},{44.23,54.41},{43.36,53.87}}}
	SkuDB.NpcData.Data[35060][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.ICECROWN]={{74.14,10.52},{74.7,9.72},{74.15,9.14},{73.76,9.69}}}
	SkuDB.NpcData.Data[35060][SkuDB.NpcData.Keys.zoneID] = SkuDB.zoneIDs.ICECROWN
	SkuDB.NpcData.Data[35061][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.ICECROWN]={{74.14,10.52},{74.7,9.72},{74.15,9.14},{73.76,9.69}}}
	SkuDB.NpcData.Data[35061][SkuDB.NpcData.Keys.zoneID] = SkuDB.zoneIDs.ICECROWN
	SkuDB.NpcData.Data[35071][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.ICECROWN]={{74.14,10.52},{74.7,9.72},{74.15,9.14},{73.76,9.69}}}
	SkuDB.NpcData.Data[35071][SkuDB.NpcData.Keys.zoneID] = SkuDB.zoneIDs.ICECROWN
	SkuDB.NpcData.Data[41600][SkuDB.NpcData.Keys.spawns] = {
                [SkuDB.zoneIDs.ABYSSAL_DEPTHS] = {
                    {51.57,60.9,1017},
                    {42.69,37.91,1018},
                },
            }
	SkuDB.NpcData.Data[41814][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.ABYSSAL_DEPTHS]={{51.49,60.85}}}
	SkuDB.NpcData.Data[42486][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.SHIMMERING_EXPANSE]={{50.72,66.47}}}
	SkuDB.NpcData.Data[42790][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.STRANGLETHORN_VALE]={{38.4,48.6}}}
	SkuDB.NpcData.Data[48416][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.ABYSSAL_DEPTHS]={{53.83,61.91}}}
	SkuDB.NpcData.Data[52234][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.STRANGLETHORN_VALE] = {{64.3,39.7}}}
	SkuDB.NpcData.Data[52762][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.THE_CAPE_OF_STRANGLETHORN] = {{35.13,29.33}}}
	SkuDB.NpcData.Data[52762][SkuDB.NpcData.Keys.zoneID] = SkuDB.zoneIDs.THE_CAPE_OF_STRANGLETHORN
end

local function applyItemSpecificDataChangesAlliance()
	SkuDB.itemDataTBC[56188][SkuDB.itemKeys.objectDrops] = {203403}
	SkuDB.itemDataTBC[71034][SkuDB.itemKeys.objectDrops] = {209242}
end

local function applyQuestSpecificDataChangesAlliance()
	SkuDB.questDataTBC[12318][SkuDB.questKeys.startedBy] = {{27584}}
	SkuDB.questDataTBC[25513][SkuDB.questKeys.preQuestGroup] = {25065,25095}
	SkuDB.questDataTBC[25619][SkuDB.questKeys.preQuestSingle] = {}
	SkuDB.questDataTBC[25619][SkuDB.questKeys.preQuestGroup] = {25579,25580,25581,25582,25583}
	SkuDB.questDataTBC[25629][SkuDB.questKeys.preQuestSingle] = {25911}
	SkuDB.questDataTBC[25896][SkuDB.questKeys.preQuestSingle] = {25911}
	SkuDB.questDataTBC[25858][SkuDB.questKeys.objectives] = {{{42072,nil,5},{42071,nil,5},{41455,nil,5}}}
	SkuDB.questDataTBC[25858][SkuDB.questKeys.preQuestSingle] = {}
	SkuDB.questDataTBC[25858][SkuDB.questKeys.preQuestGroup] = {25753,25754}
	SkuDB.questDataTBC[26111][SkuDB.questKeys.preQuestSingle] = {}
	SkuDB.questDataTBC[26111][SkuDB.questKeys.preQuestGroup] = {26070,26072,26096}
	SkuDB.questDataTBC[26191][SkuDB.questKeys.nextQuestInChain] = {25892}
	SkuDB.questDataTBC[27203][SkuDB.questKeys.startedBy] = {{45226}}
	SkuDB.questDataTBC[29389][SkuDB.questKeys.preQuestGroup] = {25611,25807,25520,25372}
	SkuDB.questDataTBC[29475][SkuDB.questKeys.startedBy] = {{5174,5518,16726,29513,52636}}
	SkuDB.questDataTBC[29475][SkuDB.questKeys.finishedBy] = {{5174,5518,16726,29513,52636}}
	SkuDB.questDataTBC[29475][SkuDB.questKeys.exclusiveTo] = {3526,3629,3633,4181,29476,29477,3630,3632,3634,3635,3637}
	SkuDB.questDataTBC[29477][SkuDB.questKeys.startedBy] = {{5174,5518,16726,29513,52636}}
	SkuDB.questDataTBC[29477][SkuDB.questKeys.finishedBy] = {{5174,5518,16726,29513,52636}}
	SkuDB.questDataTBC[29477][SkuDB.questKeys.exclusiveTo] = {3630,3632,3634,3635,3637,29475,29476,3526,3629,3633,4181}
    SkuDB.questDataTBC[29836][SkuDB.questKeys.exclusiveTo] = {13099}
	SkuDB.questDataTBC[29836][SkuDB.questKeys.nextQuestInChain] = 29844
end

local function applyObjectSpecificDataChangesAlliance()
	SkuDB.objectDataTBC[186189][SkuDB.objectKeys.spawns] = {[SkuDB.zoneIDs.DUN_MOROGH]={{54.03,38.92},{54.03,38.95},{54.17,38.31},{54.67,37.93},{54.8,37.9},{54.69,37.94},{55.32,37.26},{55.3,37.28},{55.7,38.16},{55.67,38.17},{56.53,36.68},{55.63,36.48},{55.65,36.48},{56.26,37.94},{56.26,37.97},{55.9,36.43},{55.9,36.4},{56.29,37.96},{59.79,33.5},{59.77,33.51}}}
	SkuDB.objectDataTBC[203461][SkuDB.objectKeys.spawns] = {[SkuDB.zoneIDs.ABYSSAL_DEPTHS]={{55.8,72.44}}}
end

local function applyNpcSpecificDataChangesAlliance()
	SkuDB.NpcData.Data[24108][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.DUN_MOROGH] = {{54.8,37.54}}}
	SkuDB.NpcData.Data[24202][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.IRONFORGE]={{30.2,66.5}}}
	SkuDB.NpcData.Data[24203][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.IRONFORGE]={{64,78.2}}}
	SkuDB.NpcData.Data[24204][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.IRONFORGE]={{64.3,24.3}}}
	SkuDB.NpcData.Data[24205][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.IRONFORGE]={{32.2,21}}}
	SkuDB.NpcData.Data[26221][SkuDB.NpcData.Keys.spawns] = {
                [SkuDB.zoneIDs.DARNASSUS]={{62.11,49.13}},
                [SkuDB.zoneIDs.SHATTRATH_CITY]={{60.68,30.62}},
                [SkuDB.zoneIDs.IRONFORGE]={{65.14,27.71}},
                [SkuDB.zoneIDs.STORMWIND_CITY]={{49.31,72.29}},
                [SkuDB.zoneIDs.THE_EXODAR]={{43.27,26.26}},
            }
	SkuDB.NpcData.Data[29579][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.STORM_PEAKS] = {{30.1,73.9}}}
	SkuDB.NpcData.Data[34907][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.HROTHGARS_LANDING]={{50.21,49.08},{50.14,49.47},{49.75,49.51},{50.06,49.08},{50.63,48.98},{51.18,48.81},{50.43,49.05},{49.9,49.59},{50.3,49.61},{51,48.53}}}
	SkuDB.NpcData.Data[34947][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.HROTHGARS_LANDING]={{50.21,49.08},{50.14,49.47},{49.75,49.51},{50.06,49.08},{50.63,48.98},{51.18,48.81},{50.43,49.05},{49.9,49.59},{50.3,49.61},{51,48.53}}}
	SkuDB.NpcData.Data[35060][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.ICECROWN]={{66.87,8.97},{66.36,8.08},{67.31,8.2},{66.92,7.55}}}
	SkuDB.NpcData.Data[35060][SkuDB.NpcData.Keys.zoneID] = SkuDB.zoneIDs.ICECROWN
	SkuDB.NpcData.Data[35061][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.ICECROWN]={{66.87,8.97},{66.36,8.08},{67.31,8.2},{66.92,7.55}}}
	SkuDB.NpcData.Data[35061][SkuDB.NpcData.Keys.zoneID] = SkuDB.zoneIDs.ICECROWN
	SkuDB.NpcData.Data[35071][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.ICECROWN]={{66.87,8.97},{66.36,8.08},{67.31,8.2},{66.92,7.55}}}
	SkuDB.NpcData.Data[35071][SkuDB.NpcData.Keys.zoneID] = SkuDB.zoneIDs.ICECROWN
	SkuDB.NpcData.Data[41600][SkuDB.NpcData.Keys.spawns] = {
                [SkuDB.zoneIDs.ABYSSAL_DEPTHS] = {
                    {55.71,72.98,1017},
                    {42.69,37.91,1018},
                },
            }
	SkuDB.NpcData.Data[41814][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.ABYSSAL_DEPTHS]={{55.51,72.9}}}
	SkuDB.NpcData.Data[42486][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.SHIMMERING_EXPANSE]={{56.68,76.62}}}
	SkuDB.NpcData.Data[42790][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.STRANGLETHORN_VALE]={{47.2,10.6}}}
    SkuDB.NpcData.Data[48416][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.ABYSSAL_DEPTHS]={{55.83,76.21}}}
    SkuDB.NpcData.Data[52234][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.STRANGLETHORN_VALE] = {{52.82,66.71}}}
    SkuDB.NpcData.Data[52762][SkuDB.NpcData.Keys.spawns] = {[SkuDB.zoneIDs.THE_CAPE_OF_STRANGLETHORN] = {{55.5,41.26}}}
	SkuDB.NpcData.Data[52762][SkuDB.NpcData.Keys.zoneID] = SkuDB.zoneIDs.THE_CAPE_OF_STRANGLETHORN
end

local function applyFactionSpecificDataChanges()
	if UnitFactionGroup("Player") == "Horde" then
		applyItemSpecificDataChangesHorde()
		applyQuestSpecificDataChangesHorde()
		applyObjectSpecificDataChangesHorde()
		applyNpcSpecificDataChangesHorde()
    else
        applyItemSpecificDataChangesAlliance()
		applyQuestSpecificDataChangesAlliance()
		applyObjectSpecificDataChangesAlliance()
		applyNpcSpecificDataChangesAlliance()
    end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function isTbcOrLkZone(areaIndex)
	local tbcAndLkContintentIds = {
		[530] = true,
		[571] = true, 
		[609] = true,
	}

	if SkuDB.InternalAreaTable[areaIndex] and tbcAndLkContintentIds[SkuDB.InternalAreaTable[areaIndex].ContinentID] and SkuDB.InternalAreaTable[areaIndex].ParentAreaID == 0 then
		return true
	end

	return false
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuQuest:PLAYER_LOGIN(...)
	applyFactionSpecificDataChanges()

	--update creatures and objects tables from TBC and WOTLK tables for all TBC and LK zone spawns to have appropiate spawn data for existing route/like data
	
	--apply fixes to TBC and LK tables
	SkuDB:TBCFixObjectsDB(SkuDB.oldExpansionsData.TBC)
	SkuDB:TBCFixCreaturesDB(SkuDB.oldExpansionsData.TBC)
	SkuDB:WotLKFixObjectsDB(SkuDB.oldExpansionsData.WotLK)
	SkuDB:WotLKFixCreaturesDB(SkuDB.oldExpansionsData.WotLK)

	--update cata creatures with appropiate data from tbc and lk
	for i, v in pairs(SkuDB.oldExpansionsData.WotLK.NpcData.Data) do
		if SkuDB.NpcData.Data[i] then
			if v[SkuDB.NpcData.Keys.spawns] then
				for areaIndex, areaValue in pairs(v[SkuDB.NpcData.Keys.spawns]) do
					if isTbcOrLkZone(areaIndex) == true then
						SkuDB.NpcData.Data[i][SkuDB.NpcData.Keys.spawns] = SkuDB.NpcData.Data[i][SkuDB.NpcData.Keys.spawns] or {}
						SkuDB.NpcData.Data[i][SkuDB.NpcData.Keys.spawns][areaIndex] = areaValue
					end
				end
			end
		end
	end

	for i, v in pairs(SkuDB.oldExpansionsData.TBC.NpcData.Data) do
		if SkuDB.NpcData.Data[i] then
			if v[SkuDB.NpcData.Keys.spawns] then
				for areaIndex, areaValue in pairs(v[SkuDB.NpcData.Keys.spawns]) do
					if isTbcOrLkZone(areaIndex) == true then
						SkuDB.NpcData.Data[i][SkuDB.NpcData.Keys.spawns] = SkuDB.NpcData.Data[i][SkuDB.NpcData.Keys.spawns] or {}
						SkuDB.NpcData.Data[i][SkuDB.NpcData.Keys.spawns][areaIndex] = areaValue
					end
				end
			end
		end
	end

	--update cata objects with appropiate data from tbc and lk
	for i, v in pairs(SkuDB.oldExpansionsData.WotLK.objectDataTBC) do
		if SkuDB.objectDataTBC[i] then
			if v[SkuDB.objectKeys.spawns] then
				for areaIndex, areaValue in pairs(v[SkuDB.objectKeys.spawns]) do
					if isTbcOrLkZone(areaIndex) == true then
						SkuDB.objectDataTBC[i][SkuDB.objectKeys.spawns] = SkuDB.objectDataTBC[i][SkuDB.objectKeys.spawns] or {}
						SkuDB.objectDataTBC[i][SkuDB.objectKeys.spawns][areaIndex] = areaValue
					end
				end
			end
		end
	end

	for i, v in pairs(SkuDB.oldExpansionsData.TBC.objectDataTBC) do
		if SkuDB.objectDataTBC[i] then
			if v[SkuDB.objectKeys.spawns] then
				for areaIndex, areaValue in pairs(v[SkuDB.objectKeys.spawns]) do
					if isTbcOrLkZone(areaIndex) == true then
						SkuDB.objectDataTBC[i][SkuDB.objectKeys.spawns] = SkuDB.objectDataTBC[i][SkuDB.objectKeys.spawns] or {}
						SkuDB.objectDataTBC[i][SkuDB.objectKeys.spawns][areaIndex] = areaValue
					end
				end
			end
		end
	end

	SkuQuest:BuildQuestZoneCache()

	SkuOptions.db.char[MODULE_NAME] = SkuOptions.db.char[MODULE_NAME] or {}
	C_Timer.NewTimer(10, function() PLAYER_ENTERING_WORLD_flag = false end)

	SkuQuest:UpdateAllQuestObjects()
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuQuest:PLAYER_ENTERING_WORLD(...)
	C_Timer.After(20, function()
		SkuQuest:LoadEventHandler()
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------
SkuQuest.QuestWpCache = {}
function SkuQuest:GetAllQuestWps(aQuestID, aStart, aObjective, aFinish, aOnly3)
	if aStart == true then
		if SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["startedBy"]] and (SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["startedBy"]][1] 
			or SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["startedBy"]][2]
			or SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["startedBy"]][3])
		then
			local tstartedBy = SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["startedBy"]]
			if tstartedBy then
				local tTargets = {}
				local tTargetType = nil
				tTargets, tTargetType = SkuQuest:GetQuestTargetIds(aQuestID, tstartedBy)
				if	tTargetType then
					local tResultWPs = {}
					SkuQuest:GetResultingWps(tTargets, tTargetType, aQuestID, tResultWPs, aOnly3)
					for i, v in pairs(tResultWPs) do
						for ri, rv in pairs(v) do
							SkuQuest.QuestWpCache[rv] = true
						end
					end
				end
			end
		end
	end

	if aObjective == true then
		local tObjectives = SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["objectives"]]
		if tObjectives then
			local tTargets = {}
			local tTargetType = nil
			tTargets, tTargetType = SkuQuest:GetQuestTargetIds(aQuestID, tObjectives)
			if	tTargetType then
				local tResultWPs = {}
				SkuQuest:GetResultingWps(tTargets, tTargetType, aQuestID, tResultWPs, aOnly3)
				for i, v in pairs(tResultWPs) do
					for ri, rv in pairs(v) do
						SkuQuest.QuestWpCache[rv] = true
					end
				end
			end
		end
	end
	if aFinish == true then
		if SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["finishedBy"]] and (SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["finishedBy"]][1] or SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["finishedBy"]][2] or SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["finishedBy"]][3]) then
			local tFinishedBy = SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["finishedBy"]]
			if tFinishedBy then
				local tTargets = {}
				local tTargetType = nil
				tTargets, tTargetType = SkuQuest:GetQuestTargetIds(aQuestID, tFinishedBy)
				if	tTargetType then
					local tResultWPs = {}
					SkuQuest:GetResultingWps(tTargets, tTargetType, aQuestID, tResultWPs, aOnly3)
					for i, v in pairs(tResultWPs) do
						for ri, rv in pairs(v) do
							SkuQuest.QuestWpCache[rv] = true
						end
					end
				end
			end
		end
	end

end

---------------------------------------------------------------------------------------------------------------------------------------
local function GetCreatureArea(aQuestID, aCreatureId)
	if SkuDB.NpcData.Data[aCreatureId] then
		local tSpawns = SkuDB.NpcData.Data[aCreatureId][7]
		if tSpawns then
			for is, vs in pairs(tSpawns) do
				SkuQuest.QuestZoneCache[aQuestID][is] = is
			end
		end
	end
end
local function GetObjectArea(aQuestID, aObjectId)
	if not SkuDB.objectDataTBC[aObjectId] then
		return
	end
	if SkuDB.objectDataTBC[aObjectId][SkuDB.objectKeys['spawns']] then
		for sAreaID, vi in pairs(SkuDB.objectDataTBC[aObjectId][SkuDB.objectKeys['spawns']]) do
			SkuQuest.QuestZoneCache[aQuestID][sAreaID] = sAreaID
		end
	end
end
function SkuQuest:BuildQuestZoneCache()
	SkuQuest.QuestZoneCache = {}
	for aQuestID = 1, 100000 do
		if SkuDB.questDataTBC[aQuestID] then
			SkuQuest.QuestZoneCache[aQuestID] = {}

			--starts
			local tstartedBy = SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["startedBy"]]
			if tstartedBy and tstartedBy[1] then
				--creatureStart
				for i, v in pairs(tstartedBy[1]) do
					GetCreatureArea(aQuestID, v)
				end
			end
			if tstartedBy and tstartedBy[2] then
				--objectStart
				for i, id in pairs(tstartedBy[2]) do
					GetObjectArea(aQuestID, id)
				end
			end
			if tstartedBy and tstartedBy[3] then
				--itemStart
				for i, v in pairs(tstartedBy[3]) do
					if SkuDB.itemDataTBC[v][SkuDB.itemKeys['npcDrops']] then
						for z = 1, #SkuDB.itemDataTBC[v][SkuDB.itemKeys['npcDrops']] do
							GetCreatureArea(aQuestID, SkuDB.itemDataTBC[v][SkuDB.itemKeys['npcDrops']][z])
						end
					end
					if SkuDB.itemDataTBC[v][SkuDB.itemKeys['objectDrops']] then
						for z = 1, #SkuDB.itemDataTBC[v][SkuDB.itemKeys['objectDrops']] do
							GetObjectArea(aQuestID, SkuDB.itemDataTBC[v][SkuDB.itemKeys['objectDrops']][z])
						end
					end
					if SkuDB.itemDataTBC[v][SkuDB.itemKeys['itemDrops']] then
						for z = 1, #SkuDB.itemDataTBC[v][SkuDB.itemKeys['itemDrops']] do
							local tItemId = SkuDB.itemDataTBC[v][SkuDB.itemKeys['itemDrops']][z]
							if SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['npcDrops']] then
								for z = 1, #SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['npcDrops']] do
									GetCreatureArea(aQuestID, SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['npcDrops']][z])
								end
							end
							if SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['objectDrops']] then
								for z = 1, #SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['objectDrops']] do
									GetObjectArea(aQuestID, SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['objectDrops']][z])
								end
							end
						end
					end
				end
			end

			--objectives
			local objectives = SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["objectives"]]
			if objectives then
				--['creatureObjective'] = 1, -- table {{creature(int), text(string)},...}, If text is nil the default "<Name> slain x/y" is used
				if objectives[1] then
					for i, v in pairs(objectives[1]) do
						GetCreatureArea(aQuestID, v[1])
					end
				end
				--['objectObjective'] = 2, -- table {{object(int), text(string)},...}
				if objectives[2] then
					for i, v in pairs(objectives[2]) do
						GetCreatureArea(aQuestID, v[1])
					end
				end
				--['itemObjective'] = 3, -- table {{item(int), text(string)},...}
				if objectives[3] then
					for i, v in pairs(objectives[3]) do
						local tItemId = v[1]
						if SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['npcDrops']] then
							for z = 1, #SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['npcDrops']] do
								GetCreatureArea(aQuestID, SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['npcDrops']][z])
							end
						end
						if SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['objectDrops']] then
							for z = 1, #SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['objectDrops']] do
								GetObjectArea(aQuestID, SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['objectDrops']][z])
							end
						end
						if SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['itemDrops']] then
							for z = 1, #SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['itemDrops']] do
								local tItemId = SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['itemDrops']][z]
								if SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['npcDrops']] then
									for z = 1, #SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['npcDrops']] do
										GetCreatureArea(aQuestID, SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['npcDrops']][z])
									end
								end
								if SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['objectDrops']] then
									for z = 1, #SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['objectDrops']] do
										GetObjectArea(aQuestID, SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys['objectDrops']][z])
									end
								end
							end
						end
					end
				end
			end

			--finishs
			local finishedBy = SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["finishedBy"]]
			if finishedBy and finishedBy[1] then
				--creature
				for i, v in pairs(finishedBy[1]) do
					GetCreatureArea(aQuestID, v)
				end
			end
			if finishedBy and finishedBy[2] then
				--object
				for i, id in pairs(finishedBy[2]) do
					GetObjectArea(aQuestID, id)
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
SkuQuest.questObjects = {}
function SkuQuest:GetAllQuestObjects()
	return SkuQuest.questObjects
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuQuest:UpdateAllQuestObjects()
	SkuQuest.questObjects = {}
	if GetNumQuestLogEntries() > 0 then
		for x = 1, GetNumQuestLogEntries() do
			if GetNumQuestLeaderBoards(x) > 0 then
				for y = 1, GetNumQuestLeaderBoards(x) do
					local description, objectiveType, isCompleted = GetQuestLogLeaderBoard(y, x)
					if isCompleted == false then
						if objectiveType == "object" then
							--print(x, y, description)
						elseif objectiveType == "item" then
							for i, v in pairs(SkuDB.itemLookup[Sku.L["locale"]]) do
								if string.find(description, v) then
									if SkuDB.itemDataTBC[i] and SkuDB.itemDataTBC[i][SkuDB.itemKeys.objectDrops] then
										for _, tObjectId in pairs(SkuDB.itemDataTBC[i][SkuDB.itemKeys.objectDrops]) do
											--print(v, tObjectId, SkuDB.objectLookup[Sku.L["locale"]][tObjectId])
											if SkuDB.objectLookup[Sku.L["locale"]][tObjectId] then
												SkuQuest.questObjects[SkuDB.objectLookup[Sku.L["locale"]][tObjectId]] = tObjectId
											end
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end
end