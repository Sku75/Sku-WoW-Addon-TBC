---------------------------------------------------------------------------------------------------------------------------------------
-- Forever: the text of a quest read from the quest log by quest ID.
-- The standalone QuestLogFrame of the other clients does not exist on Forever (the quest log lives in
-- the world map), so GetTTSText cannot read its widgets there. This reads the C_QuestLog data and the
-- quest reward functions instead; Blizzard's own quest UI (Mainline/QuestInfo.lua) uses the same ones.
---------------------------------------------------------------------------------------------------------------------------------------
local L = Sku.L
local GetCoinText = Sku.Compat.GetCoinText

SkuQuest = SkuQuest or LibStub("AceAddon-3.0"):NewAddon("SkuQuest", "AceConsole-3.0", "AceEvent-3.0")

-- Full item tooltip (stats, armour, slot, requirements) from the tooltip data. One section per item, so
-- CTRL-SHIFT-UP/DOWN steps from item to item and SHIFT-UP/DOWN reads its lines.
local function AddItemSection(aSections, aLabel, aLink, aName)
	if type(aLink) ~= "string" then return false end
	local tBare = string.match(aLink, "|H(item:[^|]+)|h") or string.match(aLink, "(item:[%d:%-]+)") or aLink
	local tLines = SkuCore:TooltipDataLines(C_TooltipInfo.GetHyperlink(tBare))
	if not tLines then return false end
	-- the first line is the item name, the label carries it already
	if aName and tLines[1] == aName then table.remove(tLines, 1) end
	aSections[#aSections + 1] = aLabel.."\r\n"..table.concat(tLines, "\r\n")
	return true
end

function SkuQuest:GetTTSTextForever(aQuestID, aNode)
	local questID = aQuestID
	if not questID then return {} end

	-- quest text and rewards load asynchronously; ask for them and read the quest as the selected one
	C_QuestLog.RequestLoadQuestByID(questID)
	C_QuestLog.SetSelectedQuest(questID)

	local tTitle = C_QuestLog.GetTitleForQuestID(questID)
	local tLogIndex = C_QuestLog.GetLogIndexForQuestID(questID)
	local tInfo = tLogIndex and C_QuestLog.GetInfo(tLogIndex)
	if tInfo then tTitle = tTitle or tInfo.title end
	if not tTitle then return {} end
	local tLevel = tInfo and tInfo.level

	local tSections = {}
	local tStatus
	if C_QuestLog.IsFailed(questID) then
		tStatus = L["Fehlgeschlagen"]
	elseif C_QuestLog.IsComplete(questID) then
		tStatus = L["Abgeschlossen"]
	end
	table.insert(tSections, tStatus and (tTitle.." ("..tStatus..")") or tTitle)
	if tLevel then
		table.insert(tSections, L["Level "]..tLevel)
	end

	-- objectives (progress)
	local tObjectives = C_QuestLog.GetQuestObjectives(questID)
	local tObjectiveCount = type(tObjectives) == "table" and #tObjectives or 0
	local tProgress = ""
	for i = 1, tObjectiveCount do
		local tObjective = tObjectives[i]
		if tObjective and tObjective.text then
			tProgress = tProgress..tObjective.text..(tObjective.finished and (" ("..COMPLETE..")") or "").."\r\n"
		end
	end
	if tProgress ~= "" then
		table.insert(tSections, L["Fortschritt\r\n"]..tProgress)
	end

	-- description
	local tDescription = GetQuestLogQuestText()
	if tDescription and tDescription ~= "" then
		table.insert(tSections, L["Questtext\r\n"]..tDescription)
	end

	-- rewards
	local tItemSections = {}
	local tRewardLines = {}
	-- Blizzard's quest window asks for the gold of the selected log entry WITHOUT a quest ID; with the ID
	-- a quest with an item reward answered 0. So the quest is selected above and asked without it first.
	local tMoney = GetQuestLogRewardMoney()
	if not (type(tMoney) == "number" and tMoney > 0) then
		tMoney = GetQuestLogRewardMoney(questID)
	end
	if type(tMoney) == "number" and tMoney > 0 then
		table.insert(tRewardLines, GetCoinText(tMoney, " "))
	end
	local tExperience = GetQuestLogRewardXP(questID)
	if type(tExperience) == "number" and tExperience > 0 then
		table.insert(tRewardLines, L["Experience"]..": "..tExperience)
	end
	for i = 1, GetNumQuestLogRewards(questID) do
		local tName, _, tCount = GetQuestLogRewardInfo(i, questID)
		if tName then
			local tHasSection = AddItemSection(tItemSections, L["Reward"]..": "..tName, GetQuestLogItemLink("reward", i, questID), tName)
			if not tHasSection then
				table.insert(tRewardLines, (tCount and tCount > 1) and (tName.." x"..tCount) or tName)
			end
		end
	end
	-- Blizzard's own quest UI asks for the choices with a second argument; without it the count can come
	-- back 0 although the quest has a choice.
	local tChoiceCount = GetNumQuestLogChoices(questID)
	if not (tChoiceCount and tChoiceCount > 0) then
		tChoiceCount = GetNumQuestLogChoices(questID, true)
	end
	local tChoiceLines = {}
	for i = 1, tChoiceCount or 0 do
		local tName, _, tCount = GetQuestLogChoiceInfo(i, questID)
		local tLink = GetQuestLogItemLink("choice", i, questID)
		-- item not cached yet: the name comes back empty, so take it from the item link
		if (not tName or tName == "") and type(tLink) == "string" then
			tName = string.match(tLink, "%[(.-)%]")
			local tItemId = tonumber(string.match(tLink, "item:(%d+)"))
			if tItemId then C_Item.RequestLoadItemDataByID(tItemId) end
		end
		if tName and tName ~= "" then
			if not AddItemSection(tItemSections, L["Choice"]..": "..tName, tLink, tName) then
				table.insert(tChoiceLines, (tCount and tCount > 1) and (tName.." x"..tCount) or tName)
			end
		end
	end
	if #tChoiceLines > 0 then
		table.insert(tRewardLines, L["Choice"]..":")
		for _, tChoiceLine in ipairs(tChoiceLines) do
			table.insert(tRewardLines, tChoiceLine)
		end
	end
	if #tRewardLines > 0 then
		table.insert(tSections, L["Belohnungen\r\n"]..table.concat(tRewardLines, "\r\n"))
	end
	for _, tItemSection in ipairs(tItemSections) do
		table.insert(tSections, tItemSection)
	end

	-- Objectives or rewards still empty: the quest data may not have arrived yet. For a quest menu entry
	-- (aNode) read once more shortly after and give the entry the fuller text, unless it shows another
	-- text by then. An open reading frame keeps its place and loads the new text the next time it opens.
	if aNode and (tObjectiveCount == 0 or #tRewardLines == 0) then
		C_Timer.After(0.6, function()
			if aNode.textFull ~= tSections then return end
			local tLateSections = SkuQuest:GetTTSTextForever(aQuestID)
			if tLateSections and #tLateSections > #tSections then
				aNode.textFull = tLateSections
			end
		end)
	end

	return tSections
end
