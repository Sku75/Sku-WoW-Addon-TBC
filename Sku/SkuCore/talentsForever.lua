---------------------------------------------------------------------------------------------------------------------------------------
-- Talent window on WoW Forever: PlayerSpellsFrame.
-- The N key opens the retail talent window with tabs for specialization (.SpecFrame), talent tree (.TalentsFrame, nodes
-- through C_Traits) and spellbook (.SpellBookFrame). Source: Blizzard_PlayerSpells / Blizzard_SharedTalentUI.
-- The tree is a graph; for the menu it is sorted flat by row (posY) and column (posX), and grouped by the branches the
-- game knows (C_Traits.GetGroupDisplayInfoByTreeID). What is operated are the window's REAL buttons (OnClick), so
-- Blizzard's own checks (cost, locks, confirmations) apply. Changes stay pending until "Apply" is pressed.
-- Not in the menu yet: hero talents and loadouts, and the spellbook tab (the spellbook is in the action bar menus).
-- SkuCore.BuildTalentTreeSection is also used by the legacy window (achievementsForever.lua): the legacy tree is a
-- TalentFrameBase like the class talent tree.
---------------------------------------------------------------------------------------------------------------------------------------
if not Sku.isForever then return end

local L = Sku.L

-- Entry in a list; a second label on the same level gets a number (otherwise one overwrites the other).
local function tAdd(aParentChilds, aLabel, aEntry)
	aLabel = SkuUtil:Unescape(tostring(aLabel or "?"))
	local tKey, tN = aLabel, 1
	while aParentChilds[tKey] do
		tN = tN + 1
		tKey = aLabel .. " #" .. tN
	end
	aEntry.textFirstLine = tKey
	table.insert(aParentChilds, tKey)
	aParentChilds[tKey] = aEntry
	return aEntry
end

local function tText(aParentChilds, aLabel, aFrame)
	tAdd(aParentChilds, aLabel, {
		frameName = aFrame and aFrame.GetName and aFrame:GetName() or "",
		RoC = "Child",
		type = "Text",
		obj = aFrame or PlayerSpellsFrame,
		textFull = "",
		childs = {},
	})
end

-- Name and description of a talent entry (a spell talent or a subtree).
local function tEntryInfo(aConfigID, aEntryID)
	local tEntry = C_Traits.GetEntryInfo(aConfigID, aEntryID)
	if not tEntry then return nil, nil end
	local tName, tDesc
	if tEntry.definitionID then
		local tDef = C_Traits.GetDefinitionInfo(tEntry.definitionID)
		local tSpellID = tDef and (tDef.overriddenSpellID or tDef.spellID)
		if tSpellID then
			tName = C_Spell.GetSpellName(tSpellID)
			tDesc = C_Spell.GetSpellDescription(tSpellID)
		end
		if tDef and not tName then tName = tDef.overrideName end
	elseif tEntry.subTreeID then
		local tSub = C_Traits.GetSubTreeInfo(aConfigID, tEntry.subTreeID)
		tName = tSub and tSub.name
		tDesc = tSub and tSub.description
	end
	return tName, tDesc
end

local function tClick(aButton, aMouseButton)
	return function()
		if aButton.OnClick then
			aButton:OnClick(aMouseButton or "LeftButton")
		else
			aButton:GetScript("OnClick")(aButton, aMouseButton or "LeftButton")
		end
	end
end

-- A click entry. aIdentity pins the cursor to the entry across the quiet refresh that follows the click, because
-- the label changes with the action (rank, selected).
local function tAction(aParentChilds, aLabel, aFunc, aFull, aEnabled, aIdentity)
	return tAdd(aParentChilds, aLabel, {
		frameName = "PlayerSpellsFrameAction",
		RoC = "Child",
		type = "Button",
		obj = PlayerSpellsFrame,
		textFull = aFull or "",
		childs = {},
		func = aFunc,
		click = aFunc ~= nil and aEnabled ~= false,
		quietClick = aIdentity and true or nil,
		skuIdentity = aIdentity,
	})
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Specializations. All indexes of the class are asked, not only those Blizzard's tab shows (for some characters it
-- knows only ONE specialization).
local function tSpecSection(aParentChilds, aSpecFrame)
	if not C_SpecializationInfo.IsInitialized() then return end
	local tActive = C_SpecializationInfo.GetSpecialization()
	local tClassID = select(3, UnitClass("player"))
	local tClassNum = tClassID and C_SpecializationInfo.GetNumSpecializationsForClassID(tClassID) or 0
	for tIdx = 1, math.max(tClassNum, GetNumSpecializations(), 4) do
		local _, tName, tDesc, _, tRole = C_SpecializationInfo.GetSpecializationInfo(tIdx)
		if tName then
			local tLabel = tName
			if tRole and _G[tRole] then tLabel = tLabel .. " (" .. _G[tRole] .. ")" end
			local tIsActive = (tActive == tIdx)
			if tIsActive then tLabel = tLabel .. " (" .. L["aktiv"] .. ")" end
			local tFunc
			if not tIsActive then
				tFunc = function()
					-- the direct way, like Blizzard's activate button (ClassSpecContentFrameMixin:OnActivateClicked)
					if C_SpecializationInfo.SetSpecialization(tIdx) and aSpecFrame and aSpecFrame.SetSpecActivateStarted then
						aSpecFrame:SetSpecActivateStarted(tIdx)
					end
				end
			end
			tAction(aParentChilds, tLabel, tFunc, tDesc or "")
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Talent tree
local function tNodeEntry(aParentChilds, aConfigID, aButton, aNodeInfo)
	local tChoices = aButton.talentSelections
	local tRank = aNodeInfo.currentRank or 0
	local tMax = aNodeInfo.maxRanks or 0
	local tIsLocked = aButton.IsLocked and aButton:IsLocked()
	local tIdent = "trait:" .. tostring(aNodeInfo.ID)

	-- choice node (either-or): a submenu with the entries
	if type(tChoices) == "table" and #tChoices > 0 and aButton.SetSelectedEntryID then
		local tSelectedID = aButton.GetSelectedEntryID and aButton:GetSelectedEntryID() or nil
		local tNames = {}
		for _, tEntryID in ipairs(tChoices) do
			tNames[#tNames + 1] = tEntryInfo(aConfigID, tEntryID) or "?"
		end
		local tLabel = table.concat(tNames, " / ")
		if tSelectedID then
			tLabel = (tEntryInfo(aConfigID, tSelectedID) or tLabel) .. " (" .. L["selected"] .. ")"
		elseif tIsLocked then
			tLabel = tLabel .. " (" .. L["disabled"] .. ")"
		end
		local tNode = tAdd(aParentChilds, tLabel, {
			skuIdentity = tIdent,
			frameName = "PlayerSpellsFrameChoice",
			RoC = "Child",
			type = "Button",
			obj = PlayerSpellsFrame,
			textFull = "",
			childs = {},
		})
		for _, tEntryID in ipairs(tChoices) do
			local tName, tDesc = tEntryInfo(aConfigID, tEntryID)
			local tSub = tName or "?"
			if tEntryID == tSelectedID then tSub = tSub .. " (" .. L["selected"] .. ")" end
			local tEntryFunc
			if tEntryID ~= tSelectedID and not tIsLocked then
				tEntryFunc = function() aButton:SetSelectedEntryID(tEntryID) end
			end
			tAction(tNode.childs, tSub, tEntryFunc, tDesc or "", nil, tIdent .. ":" .. tEntryID)
		end
		-- take back
		if aButton.CanRefundRank and aButton:CanRefundRank() and tSelectedID then
			tAction(tNode.childs, L["Refund"], tClick(aButton, "RightButton"), nil, nil, tIdent .. ":refund")
		end
		return
	end

	-- normal node (buy a rank)
	local tEntryID = aNodeInfo.entryIDs and aNodeInfo.entryIDs[1]
	local tName, tDesc = tEntryInfo(aConfigID, (aNodeInfo.activeEntry and aNodeInfo.activeEntry.entryID) or tEntryID)
	tName = tName or "?"
	local tLabel = tName
	if tMax > 1 or tRank > 0 then tLabel = tLabel .. " (" .. tRank .. "/" .. tMax .. ")" end
	local tCanBuy = aButton.CanPurchaseRank and aButton:CanPurchaseRank()
	if tRank >= tMax and tMax > 0 then
		tLabel = tLabel .. " (" .. L["selected"] .. ")"
	elseif tIsLocked or not tCanBuy then
		tLabel = tLabel .. " (" .. L["disabled"] .. ")"
	end
	tAction(aParentChilds, tLabel, tClick(aButton, "LeftButton"), tDesc or "", tCanBuy and true or false, tIdent)
	if aButton.CanRefundRank and aButton:CanRefundRank() then
		tAction(aParentChilds, L["Refund"] .. ": " .. tName, tClick(aButton, "RightButton"), nil, nil, tIdent .. ":refund")
	end
end

local function tTalentsSection(aParentChilds, aTalentsFrame)
	local tConfigID = aTalentsFrame.GetConfigID and aTalentsFrame:GetConfigID()
	local tTreeID = aTalentsFrame.GetTalentTreeID and aTalentsFrame:GetTalentTreeID()
	if not tConfigID then return end

	-- points
	if tTreeID then
		for _, tCur in ipairs(C_Traits.GetTreeCurrencyInfo(tConfigID, tTreeID, false) or {}) do
			local tCurName
			local _, _, tTypesID = C_Traits.GetTraitCurrencyInfo(tCur.traitCurrencyID)
			if tTypesID then
				local tCi = C_CurrencyInfo.GetCurrencyInfo(tTypesID)
				tCurName = tCi and tCi.name
			end
			tText(aParentChilds, "Text: " .. (tCurName or TALENTS) .. ": " .. tostring(tCur.quantity or 0), nil)
		end
	end

	-- Talent groups (dual specialization): primary and secondary are tabs of the talent frame. Shown only once the
	-- second group is unlocked. The active group is the one the character plays with; the selected one is the one
	-- whose talents are shown (and can be changed only if it is the active one).
	if aTalentsFrame.GetActiveTab and GetNumSpecGroups() > 1 then
		local tActiveTab, tShownTab = aTalentsFrame:GetActiveTab(), aTalentsFrame:GetTab()
		for _, tGroup in ipairs({ { id = aTalentsFrame.primarySpecTabID, text = DUAL_SPEC_PRIMARY }, { id = aTalentsFrame.secondarySpecTabID, text = DUAL_SPEC_SECONDARY } }) do
			local tLabel = L["Tab"] .. " " .. tostring(tGroup.text)
			if tActiveTab == tGroup.id then tLabel = tLabel .. " (" .. L["aktiv"] .. ")" end
			if tShownTab == tGroup.id then tLabel = tLabel .. " (" .. L["selected"] .. ")" end
			local tId = tGroup.id
			tAction(aParentChilds, tLabel, (tShownTab ~= tId) and function() aTalentsFrame:SetTab(tId) end or nil, nil, nil, "talentgroup:" .. tId)
		end
	end

	-- apply / undo
	local tApply = aTalentsFrame.ApplyButton
	if tApply and tApply:IsShown() then
		local tLabel = tApply:GetText() or TALENT_FRAME_APPLY_BUTTON_TEXT
		if not tApply:IsEnabled() then tLabel = tLabel .. " (" .. L["disabled"] .. ")" end
		tAction(aParentChilds, tLabel, tApply:IsEnabled() and tClick(tApply) or nil)
	end
	local tUndo = aTalentsFrame.UndoButton
	if tUndo and tUndo:IsShown() and tUndo:IsEnabled() then
		tAction(aParentChilds, L["Undo"], tClick(tUndo))
	end

	-- collect the nodes, order by row and column
	local tNodes = {}
	for tButton in aTalentsFrame:EnumerateAllTalentButtons() do
		local tInfo = tButton.GetNodeInfo and tButton:GetNodeInfo()
		if tInfo and tInfo.isVisible ~= false and tInfo.posX and tInfo.posY then
			tNodes[#tNodes + 1] = { button = tButton, info = tInfo }
		end
	end
	table.sort(tNodes, function(a, b)
		if a.info.posY ~= b.info.posY then return a.info.posY < b.info.posY end
		return a.info.posX < b.info.posX
	end)

	-- Branches (for a hunter: Beast Mastery / Marksmanship / Survival): the game knows them as "groups" of the tree.
	-- Every node carries its group IDs; the first one that is a branch decides. Without branch data the list stays flat.
	local tBranches, tBranchByGroup = {}, {}
	if tTreeID then
		for _, tG in ipairs(C_Traits.GetGroupDisplayInfoByTreeID(tTreeID) or {}) do
			if tG.groupID and tG.displayName and tG.displayName ~= "" then
				local tBranch = { name = tG.displayName, order = tG.orderIndex or 0, nodes = {}, points = 0 }
				tBranches[#tBranches + 1] = tBranch
				tBranchByGroup[tG.groupID] = tBranch
			end
		end
		table.sort(tBranches, function(a, b) return a.order < b.order end)
	end
	local tLoose = {}
	for _, tNode in ipairs(tNodes) do
		local tBranch
		for _, tGroupID in ipairs(tNode.info.groupIDs or {}) do
			if tBranchByGroup[tGroupID] then tBranch = tBranchByGroup[tGroupID] break end
		end
		if tBranch then
			tBranch.nodes[#tBranch.nodes + 1] = tNode
			tBranch.points = tBranch.points + (tNode.info.currentRank or 0)
		else
			tLoose[#tLoose + 1] = tNode
		end
	end
	for _, tBranch in ipairs(tBranches) do
		if #tBranch.nodes > 0 then
			local tBranchEntry = tAdd(aParentChilds, tBranch.name .. " (" .. tBranch.points .. ")", {
				skuIdentity = "branch:" .. tBranch.name,
				frameName = "PlayerSpellsFrameBranch",
				RoC = "Child",
				type = "Button",
				obj = PlayerSpellsFrame,
				textFull = "",
				childs = {},
			})
			for _, tNode in ipairs(tBranch.nodes) do
				tNodeEntry(tBranchEntry.childs, tConfigID, tNode.button, tNode.info)
			end
		end
	end
	for _, tNode in ipairs(tLoose) do
		tNodeEntry(aParentChilds, tConfigID, tNode.button, tNode.info)
	end
end

SkuCore.BuildTalentTreeSection = tTalentsSection

-- A click only stages the change: Blizzard updates the buttons' nodeInfo in the tree's next OnUpdate and then fires
-- "TalentFrameBase.ButtonsUpdated" (Blizzard_SharedTalentFrame.lua); loading a tree fires it too. One quiet rebuild on
-- that event keeps the labels current, in the talent window and in the legacy tree. Run a frame later: the class talent
-- frame updates its Apply and Undo buttons only after firing the event.
local tRefreshPending = false
EventRegistry:RegisterCallback("TalentFrameBase.ButtonsUpdated", function()
	if tRefreshPending then return end
	if not ((PlayerSpellsFrame and PlayerSpellsFrame:IsVisible()) or (LegacySystemFrame and LegacySystemFrame:IsVisible())) then return end
	tRefreshPending = true
	C_Timer.After(0, function()
		tRefreshPending = false
		SkuCore:RefreshWindowMenuQuietly()
	end)
end)

function SkuCore:Build_PlayerSpellsFrame(aParentChilds)
	local tFrame = PlayerSpellsFrame

	-- tabs. The spellbook tab is left out on purpose: without content it could only be switched to.
	local tCurrentTab = tFrame:GetTab()
	local tTabs = {
		{ id = tFrame.specTabID, text = TALENT_FRAME_TAB_LABEL_SPEC },
		{ id = tFrame.talentTabID, text = TALENT_FRAME_TAB_LABEL_TALENTS },
	}
	for _, tTab in ipairs(tTabs) do
		if tTab.id and tFrame:IsTabAvailable(tTab.id) then
			local tLabel = L["Tab"] .. " " .. tostring(tTab.text or tTab.id)
			local tSelected = (tCurrentTab == tTab.id)
			if tSelected then tLabel = tLabel .. " (" .. L["selected"] .. ")" end
			local tId = tTab.id
			tAction(aParentChilds, tLabel, (not tSelected) and function() tFrame:SetTab(tId) end or nil, nil, nil, "tab:" .. tId)
		end
	end

	-- Specializations are always reachable, also when the tab is missing.
	local tSpecAvailable, tSpecReason = C_SpecializationInfo.CanPlayerUseTalentSpecUI()
	local tSpecNode = tAdd(aParentChilds, SPECIALIZATION, {
		frameName = "PlayerSpellsFrameSpecs",
		RoC = "Child",
		type = "Button",
		obj = tFrame,
		textFull = "",
		childs = {},
	})
	if tSpecAvailable == false and tSpecReason and tSpecReason ~= "" then
		tText(tSpecNode.childs, "Text: " .. tSpecReason, tFrame)
	end
	tSpecSection(tSpecNode.childs, tFrame.SpecFrame)

	if tCurrentTab == tFrame.talentTabID and tFrame.TalentsFrame then
		tTalentsSection(aParentChilds, tFrame.TalentsFrame)
	end

	-- never leave the window silent
	if #aParentChilds == 0 then
		tText(aParentChilds, "Text: " .. L["Talents"], tFrame)
	end
end
