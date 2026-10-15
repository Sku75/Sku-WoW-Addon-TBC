---------------------------------------------------------------------------------------------------------------------------------------
-- Legacy window (LegacySystemFrame) on WoW Forever.
-- Forever keeps the achievements in the legacy system (Blizzard_LegacySystem): ToggleAchievementFrame and the key
-- TOGGLELEGACYSYSTEM open it, /skulegacy opens it from Sku. Three pages, all in the menu:
--   * Challenges (= achievements, about 110 in 29 categories): the normal achievement API (GetCategoryList,
--     GetCategoryInfo, GetCategoryNumAchievements, GetAchievementInfo, GetAchievementCriteriaInfo), read only; new
--     categories show up by themselves.
--   * Reward track: levels and rewards (C_MajorFactions, RenownRewardUtil), read only.
--   * Legacy tree: three trees, points are spent like talents. It operates the REAL buttons of Blizzard's window; the
--     tree itself comes from SkuCore.BuildTalentTreeSection (talentsForever.lua), the same builder as the class talent tree.
-- Hooked up in SkuCore/Core.lua (interactFramesListManual, interactFramesList, friendlyFrameNames).
---------------------------------------------------------------------------------------------------------------------------------------
if not Sku.isForever then return end

local L = Sku.L

local MAX_CRITERIA_CHILDREN = 60   -- above that only as a number in the text, not as entries of their own
local MAX_DEPTH = 6
local LEGACY_TREE_PAGE = 3

-- Entry in a list (at aIndex, else at the end); a second label on the same level gets a number (otherwise one
-- overwrites the other).
local function tAdd(aList, aLabel, aEntry, aIndex)
	local tLabel, tN = aLabel, 1
	while aList[tLabel] ~= nil do
		tN = tN + 1
		tLabel = aLabel .. " " .. tN
	end
	aEntry.textFirstLine = tLabel
	aEntry.frameName = "LegacySystemFrame"
	aEntry.RoC = "Child"
	aEntry.childs = aEntry.childs or {}
	aEntry.textFull = aEntry.textFull or ""
	table.insert(aList, aIndex or (#aList + 1), tLabel)
	aList[tLabel] = aEntry
	return aEntry
end

local function tSay(aText)
	SkuOptions.Voice:OutputStringBTtts(aText, true, true, 0.1, nil, nil, nil, 1)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Challenges
local function tCriteriaChildren(aId, aNum)
	local tChilds, tOpen = {}, 0
	for c = 1, aNum do
		local tName, _, tDone, tQty, tReq, _, _, _, tQtyString = GetAchievementCriteriaInfo(aId, c)
		if not tDone then tOpen = tOpen + 1 end
		if tName and tName ~= "" then
			local tLabel = tName .. ", " .. (tDone and L["done"] or L["open"])
			if not tDone and type(tReq) == "number" and tReq > 1 then
				tLabel = tLabel .. ", " .. (tQtyString and tostring(tQtyString) or (tostring(tQty or 0) .. " / " .. tostring(tReq)))
			end
			tAdd(tChilds, tLabel, { type = "FontString", obj = nil })
		end
	end
	return tChilds, tOpen
end

-- One achievement: description, state, progress; criteria as sub entries (for example areas not explored yet).
local function tBuildAchievement(aList, aCat, aIndex)
	local tId, tName, _, tCompleted, tMonth, tDay, tYear, tDesc, _, _, tReward, _, tEarnedByMe = GetAchievementInfo(aCat, aIndex)
	if not (tId and tName and tName ~= "") then return false end
	-- Like Blizzard's legacy window (AchievementFrame_ShowAsComplete): earned counts only if the character earned it.
	tCompleted = tCompleted and tEarnedByMe and true or false
	-- Legacy points instead of achievement points (AchievementFrame_GetOverridePoints).
	local tPoints = tonumber((C_Traits.GetTraitCurrencyForAchievement(Constants.LegacyConsts.LEGACY_POINTS_TRAIT_CURRENCY_ID, tId)))

	local tNumCrit = GetAchievementNumCriteria(tId) or 0
	local tState = tCompleted and L["earned"] or L["open"]

	local tParts = { tName }
	if tDesc and tDesc ~= "" then tParts[#tParts + 1] = tDesc end
	if tCompleted then
		if tDay and tMonth and tYear and tDay > 0 then
			tParts[#tParts + 1] = L["Earned on"] .. " " .. FormatShortDate(tDay, tMonth, tYear)
		end
	elseif tNumCrit == 1 then
		-- a single criterion with a counter (for example skill 13 / 150): in the text and in the line
		local _, _, tDone, tQty, tReq, _, _, _, tQtyString = GetAchievementCriteriaInfo(tId, 1)
		if not tDone and type(tReq) == "number" and tReq > 1 then
			local tProgress = tQtyString and tostring(tQtyString) or (tostring(tQty or 0) .. " / " .. tostring(tReq))
			tState = tState .. ", " .. tProgress
			tParts[#tParts + 1] = L["Progress"] .. ": " .. tProgress
		end
	end
	if tPoints and tPoints > 0 then
		tParts[#tParts + 1] = L["Legacy points"] .. ": " .. tPoints
	end
	if tReward and tReward ~= "" then tParts[#tParts + 1] = tReward end

	local tChilds
	if tNumCrit > 1 and tNumCrit <= MAX_CRITERIA_CHILDREN then
		local tOpen
		tChilds, tOpen = tCriteriaChildren(tId, tNumCrit)
		if not tCompleted then
			tState = tState .. ", " .. string.format(L["%d of %d open"], tOpen, tNumCrit)
		end
	end

	-- With criteria the achievement is a level of its own: its label is the bare name, so that it does not change with
	-- the state (after a rebuild the menu finds the cursor again by the labels of the levels above it), and the state is
	-- the first line inside.
	if tChilds and #tChilds > 0 then
		tAdd(tChilds, tState, { type = "FontString", obj = nil }, 1)
		tAdd(aList, tName, { type = "Button", obj = nil, textFull = table.concat(tParts, "\r\n"), childs = tChilds, skuIdentity = "ach:" .. tId })
	else
		tAdd(aList, tName .. ", " .. tState, { type = "FontString", obj = nil, textFull = table.concat(tParts, "\r\n") })
	end
	return true
end

-- A category, recursively: subcategories first, then the achievements of the category itself. Empty ones are left out.
local function tBuildCategory(aList, aCat, aChildrenOf, aDepth)
	if aDepth > MAX_DEPTH then return false end
	local tTitle = GetCategoryInfo(aCat)
	if not tTitle or tTitle == "" then return false end

	local tChilds = {}
	local tCount = 0
	for _, tSub in ipairs(aChildrenOf[aCat] or {}) do
		if tBuildCategory(tChilds, tSub, aChildrenOf, aDepth + 1) then tCount = tCount + 1 end
	end
	for i = 1, GetCategoryNumAchievements(aCat) or 0 do
		if tBuildAchievement(tChilds, aCat, i) then tCount = tCount + 1 end
	end
	if tCount == 0 then return false end

	-- counter "x of y earned" over all achievements below this category, as the first line inside (not in the label, see
	-- tBuildAchievement)
	local function tTotals(aId, aD)
		local tN, tC = GetCategoryNumAchievements(aId)
		local tTotal, tDoneCount = tonumber(tN) or 0, tonumber(tC) or 0
		if aD < MAX_DEPTH then
			for _, tSub in ipairs(aChildrenOf[aId] or {}) do
				local a, b = tTotals(tSub, aD + 1)
				tTotal, tDoneCount = tTotal + a, tDoneCount + b
			end
		end
		return tTotal, tDoneCount
	end
	local tAll, tDoneAll = tTotals(aCat, aDepth)
	tAdd(tChilds, string.format(L["%d of %d earned"], tDoneAll, tAll), { type = "FontString", obj = nil }, 1)

	tAdd(aList, tTitle, { type = "Button", obj = nil, textFull = tTitle, childs = tChilds, skuIdentity = "achcat:" .. aCat })
	return true
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Reward track (Blizzard_LegacyRewardTrack): one level per legacy point milestone, the state is the renown level of the
-- major faction LEGACY_REWARD_TRACK_FACTION_ID. A level <= the current one counts as earned. Reward names come from
-- RenownRewardUtil as in Blizzard's tooltip; if items are not loaded yet, the name is missing until the next opening.
local function tBuildRewardTrack(aList)
	local tFactionID = Constants.LegacyConsts.LEGACY_REWARD_TRACK_FACTION_ID
	local tData = C_MajorFactions.GetMajorFactionData(tFactionID)
	local tLevels = C_MajorFactions.GetRenownLevels(tFactionID)
	if type(tData) ~= "table" or type(tLevels) ~= "table" or #tLevels == 0 then return end

	local tCurrent = tonumber((C_MajorFactions.GetCurrentRenownLevel(tFactionID))) or tonumber(tData.renownLevel) or 0
	local tNextFound = false
	local tChilds = {}

	for _, tLevelInfo in ipairs(tLevels) do
		local tLevel = tLevelInfo.level
		if tLevel then
			local tNames, tParts = {}, {}
			for _, tReward in ipairs(C_MajorFactions.GetRenownRewardsForLevel(tFactionID, tLevel) or {}) do
				local _, tName, tDesc = RenownRewardUtil.GetRenownRewardInfo(tReward, function() end)
				tName = tName or tReward.name
				if tName and tName ~= "" then
					tNames[#tNames + 1] = tName
					tParts[#tParts + 1] = tName .. ((tDesc and tDesc ~= "") and (": " .. tDesc) or "")
				end
			end

			local tState
			if tLevel <= tCurrent then
				tState = L["earned"]
			elseif not tNextFound then
				tNextFound = true
				tState = L["next reward"]
			else
				tState = L["not yet earned"]
			end

			local tLabel = L["Level"] .. " " .. tLevel .. ", " .. tState
			if #tNames > 0 then tLabel = tLabel .. ": " .. table.concat(tNames, ", ") end
			tAdd(tChilds, tLabel, { type = "FontString", obj = nil, textFull = table.concat(tParts, "\r\n") })
		end
	end
	if #tChilds == 0 then return end

	local tLevelLine
	if tData.maxLevel and tData.maxLevel > 0 then
		tLevelLine = string.format(L["Reward track, level %d of %d"], tCurrent, tData.maxLevel)
	else
		tLevelLine = string.format(L["Reward track, level %d"], tCurrent)
	end
	tAdd(tChilds, tLevelLine, { type = "FontString", obj = nil }, 1)
	tAdd(aList, L["Reward track"], { type = "Button", obj = nil, textFull = tData.name or "", childs = tChilds, skuIdentity = "legacyrewards" })
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Legacy tree (Blizzard_LegacyTree): three trees (professions, adventure, progress); legacy points are spent like talents.
-- LegacyTreeTraitPanel is a TalentFrameBase; the same builder as for the class talent tree builds the tree
-- (SkuCore.BuildTalentTreeSection), operating the REAL buttons of the window. The panel has its nodes only while the tree
-- page is visible; otherwise there is an entry that opens the page.
-- Opening the page, selecting a tree and every point spent make the panel fire "TalentFrameBase.ButtonsUpdated" once its
-- buttons are current; the menu is rebuilt on that event (talentsForever.lua).

-- A click entry. The cursor stays on it across the quiet refresh that follows (quietClick, pinned by aIdentity).
local function tAction(aList, aLabel, aFunc, aIdentity)
	return tAdd(aList, aLabel, {
		type = "Button",
		obj = nil,
		func = aFunc,
		click = aFunc ~= nil,
		quietClick = aFunc ~= nil or nil,
		skuIdentity = aIdentity,
	})
end

-- "Reset tree" with a confirmation (Enter Yes, Escape No, as when unlearning a profession). It operates Blizzard's own
-- ResetButton; the reset is then only pending and takes effect with "Apply" (Undo takes it back). The prompt opens a
-- moment later, otherwise the menu refresh after the entry takes the focus away from the input.
local function tAddResetEntry(aList, aPanel, aTreeName, aIndex)
	local tButton = aPanel.ResetButton
	if not tButton then return end
	local tUsable = tButton:IsShown() and (not tButton.IsEnabled or tButton:IsEnabled())
	local tLabel = L["Reset tree"]
	if not tUsable then
		tLabel = tLabel .. " (" .. L["not possible right now"] .. ")"
	end

	local tAsk = string.format(L["Really reset all points in the %s tree? Enter Yes, Escape for No."], aTreeName)

	tAdd(aList, tLabel, {
		type = "Button",
		obj = nil,
		textFull = L["Resets the whole tree. A confirmation prompt appears. The reset only takes effect with Apply."],
		directAction = tUsable and true or nil,
		skuIdentity = "legacyreset",
		func = tUsable and function()
			PlaySound(88)
			C_Timer.After(0.5, function()
				SkuCore:ConfirmButtonShow(tAsk,
					function()
						PlaySound(89)
						tButton:Click()
						tSay(string.format(L["%s reset. Confirm with Apply, or Undo."], aTreeName))
					end,
					function()
						tSay(L["Canceled, not reset"])
					end)
				tSay(tAsk)
			end)
		end or nil,
	}, aIndex)
end

-- Number of head entries of a tree (points, apply, undo): "Reset tree" belongs behind them, as in Blizzard's window
-- where the reset button sits next to Apply.
local function tCountTreeHead(aList, aPanel)
	local tApplyLabel = aPanel.ApplyButton and aPanel.ApplyButton.GetText and aPanel.ApplyButton:GetText()
	local tCount = 0
	for _, tEntryLabel in ipairs(aList) do
		local tIsHead = tEntryLabel:find("^Text:")
			or (tApplyLabel and tEntryLabel:sub(1, #tApplyLabel) == tApplyLabel)
			or tEntryLabel == L["Undo"]
		if not tIsHead then break end
		tCount = tCount + 1
	end
	return tCount
end

local function tBuildTree(aList)
	local tFrame = LegacySystemFrame
	local tPage = tFrame and tFrame.TreePage
	if not tPage then return end

	local tChilds = {}
	local tHead = L["Legacy tree"]

	if not tPage:IsShown() then
		tAction(tChilds, L["Open the legacy tree page"], function()
			EventRegistry:TriggerEvent("Legacy.SelectPage", LEGACY_TREE_PAGE)
			tSay(L["Legacy tree opened"])
		end, "legacyopen")
		tAdd(aList, tHead, { type = "Button", obj = nil, textFull = "", childs = tChilds })
		return
	end

	-- Every tree is an entry of its own (like the branches in the class talent menu). The selected tree holds its nodes
	-- (right arrow to go in); a tree that is not selected is an entry that selects it with Enter. The identity of the
	-- entry stays the same, so the cursor stays on it when the menu is rebuilt and the tree has its nodes.
	local tButtons = tPage.LegacyTreeSelectionPanel and tPage.LegacyTreeSelectionPanel.treeButtons
	local tPanel = tPage.LegacyTreeTraitPanel
	for i, tButton in ipairs(type(tButtons) == "table" and tButtons or {}) do
		local tData = LegacyTreeData and LegacyTreeData[i]
		local tName = (tData and tData.name) or (L["Tree"] .. " " .. i)
		local tSelected = tButton.GetChecked and tButton:GetChecked()
		if tSelected then
			local tTreeChilds = {}
			if tPanel then
				SkuCore.BuildTalentTreeSection(tTreeChilds, tPanel)
				tAddResetEntry(tTreeChilds, tPanel, tName, tCountTreeHead(tTreeChilds, tPanel) + 1)
			end
			tAdd(tChilds, tName .. " (" .. L["selected"] .. ")", { type = "Button", obj = nil, textFull = "", childs = tTreeChilds, skuIdentity = "legacytree" .. i })
		else
			tAdd(tChilds, tName, {
				type = "Button",
				obj = nil,
				textFull = L["Show this tree"],
				click = true,
				quietClick = true,
				skuIdentity = "legacytree" .. i,
				func = function()
					-- the event Blizzard's own tree button triggers: the panel selects the tree and the buttons follow
					EventRegistry:TriggerEvent("Legacy.SelectTree", i)
					tSay(tName .. " " .. L["selected"])
				end,
			})
		end
	end

	tAdd(aList, tHead, { type = "Button", obj = nil, textFull = "", childs = tChilds, skuIdentity = "legacytreepage" })
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:Build_LegacySystemFrame(aParentChilds)
	local tTitle = L["Legacy"]
	local tTotal, tCompleted = GetNumCompletedAchievements()
	tTotal, tCompleted = tonumber(tTotal), tonumber(tCompleted)

	local tSummary = tTitle
	if tTotal and tCompleted then
		tSummary = string.format(L["Legacy: challenges %d of %d earned"], tCompleted, tTotal)
	end
	table.insert(aParentChilds, tSummary)
	aParentChilds[tSummary] = {
		frameName = "LegacySystemFrame",
		RoC = "Child",
		type = "FontString",
		obj = LegacySystemFrame,
		textFirstLine = tSummary,
		textFull = "",
		childs = {},
	}

	-- Legacy points (like LegacySystem.UpdateCurrencyInfo / ChallengePointBarMixin:Update): current of maximum
	local tLegacy = Constants.LegacyConsts
	local tTreeID = LegacyTreeData[1].treeID
	local tConfigID = C_Traits.GetConfigIDByTreeID(tTreeID)
	local tCurrencies = tConfigID and C_Traits.GetTreeCurrencyInfo(tConfigID, tTreeID, true)
	local tCurrency = tCurrencies and tCurrencies[1]
	local tLevel = C_MajorFactions.GetCurrentRenownLevel(tLegacy.LEGACY_REWARD_TRACK_FACTION_ID)
	if tCurrency then
		local tMax = C_Traits.GetMaxAvailableTraitCurrency(tCurrency.traitCurrencyID, false)
		tAdd(aParentChilds, LEGACY_POINTS_CURR_MAX:format(tLevel, tMax), { type = "FontString", obj = nil })
	end

	tBuildRewardTrack(aParentChilds)
	tBuildTree(aParentChilds)

	local tCats = GetCategoryList()
	if type(tCats) ~= "table" then
		tAdd(aParentChilds, L["Achievements not available"], { type = "FontString", obj = nil })
		return
	end

	-- parent -> children in the order of the API; a root is whoever has no (valid) parent
	local tChildrenOf, tKnown, tRoots = {}, {}, {}
	for _, tCat in ipairs(tCats) do tKnown[tCat] = true end
	for _, tCat in ipairs(tCats) do
		local _, tParent = GetCategoryInfo(tCat)
		if tParent and tParent > 0 and tKnown[tParent] and tParent ~= tCat then
			tChildrenOf[tParent] = tChildrenOf[tParent] or {}
			table.insert(tChildrenOf[tParent], tCat)
		else
			table.insert(tRoots, tCat)
		end
	end

	local tAny = false
	for _, tCat in ipairs(tRoots) do
		if tBuildCategory(aParentChilds, tCat, tChildrenOf, 1) then tAny = true end
	end
	if not tAny then
		tAdd(aParentChilds, L["No achievements"], { type = "FontString", obj = nil })
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Access: Forever redirects "Achievements" (ToggleAchievementFrame) to the legacy window; it has a key of its own
-- (TOGGLELEGACYSYSTEM). The command /skulegacy opens it regardless of the key binding. ToggleLegacySystemUI does nothing
-- while the legacy system is locked (renown level 0, Blizzard_LegacySystem_Bootstrap.lua); then the command says why,
-- with the text of Blizzard's disabled micro button.
SLASH_SKULEGACY1 = "/skulegacy"
SlashCmdList["SKULEGACY"] = function()
	if C_MajorFactions.GetCurrentRenownLevel(Constants.LegacyConsts.LEGACY_REWARD_TRACK_FACTION_ID) <= 0 then
		tSay(LEGACY_MICRO_BUTTON_LOCKED_TOOLTIP)
		return
	end
	ToggleLegacySystemUI()
end
