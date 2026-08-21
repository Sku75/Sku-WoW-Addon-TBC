SkuDB.raceKeys = {
	ALL_ALLIANCE = VANILLA and 77 or 1101,
	ALL_HORDE = VANILLA and 178 or 690,
	--ALL = VANILLA and 255 or 2047,
	NONE = 0,

	HUMAN = 1,
	ORC = 2,
	DWARF = 4,
	NIGHT_ELF = 8,
	UNDEAD = 16,
	TAUREN = 32,
	GNOME = 64,
	TROLL = 128,
	--GOBLIN = 256,
	BLOOD_ELF = 512,
	DRAENEI = 1024,
}

SkuDB.classKeys = {
	NONE = 0,
	WARRIOR = 1,
	PALADIN = 2,
	HUNTER = 4,
	ROGUE = 8,
	PRIEST = 16,
	DEATHKNIGHT = 32,
	SHAMAN = 64,
	MAGE = 128,
	WARLOCK = 256,
	DRUID = 1024,
}

SkuDB.QuestFlags = {
	NONE = 0,
	SHARABLE = 8,
	EPIC = 32,
	RAID = 64,
	DAILY = 4096,
}

	

SkuDB.questKeys = {
   ['name'] = 1, -- string
   ['startedBy'] = 2, -- table
       --['creatureStart'] = 1, -- table {creature(int),...}
       --['objectStart'] = 2, -- table {object(int),...}
       --['itemStart'] = 3, -- table {item(int),...}
   ['finishedBy'] = 3, -- table
       --['creatureEnd'] = 1, -- table {creature(int),...}
       --['objectEnd'] = 2, -- table {object(int),...}
   ['requiredLevel'] = 4, -- int
   ['questLevel'] = 5, -- int
   ['requiredRaces'] = 6, -- bitmask
   ['requiredClasses'] = 7, -- bitmask
   ['objectivesText'] = 8, -- table: {string,...}, Description of the quest. Auto-complete if nil.
   ['triggerEnd'] = 9, -- table: {text, {[zoneID] = {coordPair,...},...}}
   ['objectives'] = 10, -- table
       --['creatureObjective'] = 1, -- table {{creature(int), text(string)},...}, If text is nil the default "<Name> slain x/y" is used
       --['objectObjective'] = 2, -- table {{object(int), text(string)},...}
       --['itemObjective'] = 3, -- table {{item(int), text(string)},...}
       --['reputationObjective'] = 4, -- table: {faction(int), value(int)}
       --???????? ['killCreditObjective'] = 5, -- table: {{creature(int), ...}, baseCreatureID, baseCreatureText}
   ['sourceItemId'] = 11, -- int, item provided by quest starter
   ['preQuestGroup'] = 12, -- table: {quest(int)}
   ['preQuestSingle'] = 13, -- table: {quest(int)}
   ['childQuests'] = 14, -- table: {quest(int)}
   ['inGroupWith'] = 15, -- table: {quest(int)}
   ['exclusiveTo'] = 16, -- table: {quest(int)}
   ['zoneOrSort'] = 17, -- int, >0: AreaTable.dbc ID; <0: QuestSort.dbc ID
   ['requiredSkill'] = 18, -- table: {skill(int), value(int)}
   ['requiredMinRep'] = 19, -- table: {faction(int), value(int)}
   ['requiredMaxRep'] = 20, -- table: {faction(int), value(int)}
   ['requiredSourceItems'] = 21, -- table: {item(int), ...} Items that are not an objective but still needed for the quest.
   ['nextQuestInChain'] = 22, -- int: if this quest is active/finished, the current quest is not available anymore
   ['questFlags'] = 23, -- bitmask: see https://github.com/cmangos/issues/wiki/Quest_template#questflags
   ['specialFlags'] = 24, -- bitmask: 1 = Repeatable, 2 = Needs event, 4 = Monthly reset (req. 1). See https://github.com/cmangos/issues/wiki/Quest_template#specialflags
   ['parentQuest'] = 25, -- int, the ID of the parent quest that needs to be active for the current one to be available. See also 'childQuests' (field 14)
	['rewardReputation'] = 26, --table: {{faction(int), value(int)},...}, a list of reputation rewarded upon quest completion
	['extraObjectives'] = 27, -- table: {{spawnlist, iconFile, text, objectiveIndex (optional), {{dbReferenceType, id}, ...} (optional)},...}, a list of hidden special objectives for a quest. Similar to requiredSourceItems
	['skuData'] = 28, -- table: {{isBlacklist, {blacklistComments}}, {extraComments}}
}

SkuDB.SoD.questLookup = {
	["deDE"] = {
		--[65610] = {"Wish You Were Here", nil, {"Investigate Fallen Sky Lake in Ashenvale and report your findings to Gan'rul Bloodeye in Orgrimmar.",},},
	},
	["enUS"] = {
		--[1] = {"The \"Chow\" Quest (123)aa", nil, {"Kill Kobold Vermin, 2 of em.",},},
	},
}


SkuDB.SoD.questDataTBC = {
	--[1] = {"The \"Chow\" Quest (123)aa",nil,nil,1,80,0,nil,{"Speak to Kanrethad to restore your talents, weapon and mount."},nil,nil,nil,nil,nil,nil,nil,nil,151,nil,nil,nil,nil,nil,nil,nil,nil,{{87,-250},{529,150}}},
}
	