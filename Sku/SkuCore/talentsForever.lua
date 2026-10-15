---------------------------------------------------------------------------------------------------------------------------------------
-- Talent window on WoW Forever: PlayerSpellsFrame.
-- The N key opens the retail talent window with tabs for specialization (.SpecFrame, an empty stub on Forever), talent
-- tree (.TalentsFrame, nodes through C_Traits) and spellbook (.SpellBookFrame). Source: Blizzard_PlayerSpells (Camelot) /
-- Blizzard_SharedTalentUI.
-- The tree is a graph; for the menu it is sorted flat by row (posY) and column (posX), and grouped by the branches the
-- game knows (C_Traits.GetGroupDisplayInfoByTreeID). What is operated are the window's REAL buttons, through the same
-- calls as Blizzard's gamepad path (PurchaseRank, RefundRank, Click; not OnClick, which reacts to held modifier keys),
-- so Blizzard's own checks (cost, locks, confirmations) apply. Changes stay pending until "Apply" is pressed.
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

-- Name, description and availability of a talent entry (a spell talent or a subtree).
local function tEntryInfo(aConfigID, aEntryID)
	local tEntry = C_Traits.GetEntryInfo(aConfigID, aEntryID)
	if not tEntry then return nil, nil, false end
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
	return tName, tDesc, tEntry.isAvailable
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
-- Talent tree
local function tNodeEntry(aParentChilds, aConfigID, aButton, aNodeInfo)
	local tChoices = aButton.talentSelections
	local tRank = aNodeInfo.currentRank or 0
	local tMax = aNodeInfo.maxRanks or 0
	local tIsLocked = aButton.IsLocked and aButton:IsLocked()
	local tIdent = "trait:" .. tostring(aNodeInfo.ID)

	-- Choice node (either-or): a submenu with the entries. Its label is the same whatever is chosen, because the menu
	-- finds the way back to the cursor after a rebuild by the labels of the levels above it; the state is in the text and
	-- in the entries.
	if type(tChoices) == "table" and #tChoices > 0 and aButton.SetSelectedEntryID then
		local tSelectedID = aButton.GetSelectedEntryID and aButton:GetSelectedEntryID() or nil
		-- Blizzard's own check (TalentSelectionChoiceMixin:IsChoiceAvailable): cost, refund state and the tree's lock, not
		-- only the node's lock.
		local tCanChoose = aButton:CanSelectChoice() and not aButton:GetTalentFrame():IsLocked()
		local tNames = {}
		for _, tEntryID in ipairs(tChoices) do
			tNames[#tNames + 1] = tEntryInfo(aConfigID, tEntryID) or "?"
		end
		local tState = ""
		if tSelectedID then
			tState = (tEntryInfo(aConfigID, tSelectedID) or "?") .. " (" .. L["selected"] .. ")"
		elseif not tCanChoose then
			tState = L["disabled"]
		end
		local tNode = tAdd(aParentChilds, table.concat(tNames, " / "), {
			skuIdentity = tIdent,
			frameName = "PlayerSpellsFrameChoice",
			RoC = "Child",
			type = "Button",
			obj = PlayerSpellsFrame,
			textFull = tState,
			childs = {},
		})
		for _, tEntryID in ipairs(tChoices) do
			local tName, tDesc, tAvailable = tEntryInfo(aConfigID, tEntryID)
			local tSub = tName or "?"
			if tEntryID == tSelectedID then tSub = tSub .. " (" .. L["selected"] .. ")" end
			local tEntryFunc
			if tEntryID ~= tSelectedID and tCanChoose and tAvailable then
				tEntryFunc = function() aButton:SetSelectedEntryID(tEntryID) end
			end
			tAction(tNode.childs, tSub, tEntryFunc, tDesc or "", nil, tIdent .. ":" .. tEntryID)
		end
		-- take back
		if aButton.CanRefundRank and aButton:CanRefundRank() and tSelectedID then
			tAction(tNode.childs, L["Refund"], function() aButton:SetSelectedEntryID(nil) end, nil, nil, tIdent .. ":refund")
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
	tAction(aParentChilds, tLabel, function() if aButton:CanPurchaseRank() then aButton:PurchaseRank() end end, tDesc or "", tCanBuy and true or false, tIdent)
	if aButton.CanRefundRank and aButton:CanRefundRank() then
		tAction(aParentChilds, L["Refund"] .. ": " .. tName, function() if aButton:CanRefundRank() then aButton:RefundRank() end end, nil, nil, tIdent .. ":refund")
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
	-- whose talents are shown (and can be changed only if it is the active one). This is Forever's specialization
	-- switch: "Activate" on a selected group that is not the active one, as Blizzard's ActivateButton
	-- (ClassTalentActiveSpecMixin:ActivateSpec, C_SpecializationInfo.SetActiveSpecGroup).
	if aTalentsFrame.GetActiveTab and GetNumSpecGroups() > 1 then
		local tActiveTab, tShownTab = aTalentsFrame:GetActiveTab(), aTalentsFrame:GetTab()
		for _, tGroup in ipairs({ { id = aTalentsFrame.primarySpecTabID, text = DUAL_SPEC_PRIMARY }, { id = aTalentsFrame.secondarySpecTabID, text = DUAL_SPEC_SECONDARY } }) do
			local tLabel = L["Tab"] .. " " .. tostring(tGroup.text)
			if tActiveTab == tGroup.id then tLabel = tLabel .. " (" .. L["aktiv"] .. ")" end
			if tShownTab == tGroup.id then tLabel = tLabel .. " (" .. L["selected"] .. ")" end
			local tId = tGroup.id
			tAction(aParentChilds, tLabel, (tShownTab ~= tId) and function() aTalentsFrame:SetTab(tId) end or nil, nil, nil, "talentgroup:" .. tId)
		end
		if not aTalentsFrame:IsActiveTabSelected() then
			local tActiveSpec = aTalentsFrame.ActiveSpec
			tAction(aParentChilds, tActiveSpec.ActivateButton:GetText(), function() tActiveSpec:ActivateSpec() end, nil, nil, "talentgroup:activate")
		end
	end

	-- apply / undo
	local tApply = aTalentsFrame.ApplyButton
	if tApply and tApply:IsShown() then
		local tLabel = tApply:GetText() or TALENT_FRAME_APPLY_BUTTON_TEXT
		if not tApply:IsEnabled() then tLabel = tLabel .. " (" .. L["disabled"] .. ")" end
		tAction(aParentChilds, tLabel, tApply:IsEnabled() and function() tApply:Click() end or nil)
	end
	local tUndo = aTalentsFrame.UndoButton
	if tUndo and tUndo:IsShown() and tUndo:IsEnabled() then
		tAction(aParentChilds, L["Undo"], function() tUndo:Click() end)
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
	-- The points of a branch are its first line, not part of its label: spending a point inside must not rename the level
	-- the cursor is in.
	for _, tBranch in ipairs(tBranches) do
		if #tBranch.nodes > 0 then
			local tBranchEntry = tAdd(aParentChilds, tBranch.name, {
				skuIdentity = "branch:" .. tBranch.name,
				frameName = "PlayerSpellsFrameBranch",
				RoC = "Child",
				type = "Button",
				obj = PlayerSpellsFrame,
				textFull = "",
				childs = {},
			})
			tText(tBranchEntry.childs, "Text: " .. string.format(L["Points spent: %d"], tBranch.points), nil)
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

-- The window's name in the menu (friendlyFrameNames in Core.lua) follows the shown tab, as Blizzard's frame title does
-- (PlayerSpellsFrameMixin:UpdateFrameTitle): the spellbook key opens this same frame on its spellbook tab.
function SkuCore:PlayerSpellsFrameName()
	local tTab = PlayerSpellsFrame and PlayerSpellsFrame:GetTab()
	if tTab and tTab == PlayerSpellsFrame.spellBookTabID then return L["Spellbook"] end
	if tTab and tTab == PlayerSpellsFrame.specTabID then return SPECIALIZATION end
	return L["Talents"]
end

function SkuCore:Build_PlayerSpellsFrame(aParentChilds)
	local tFrame = PlayerSpellsFrame

	-- tabs. The spellbook tab is left out on purpose: without content it could only be switched to. The specialization
	-- tab is an empty stub on Forever (ClassSpecFrameTemplate, Camelot); specializations are switched as talent groups.
	local tCurrentTab = tFrame:GetTab()
	local tTabs = {
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

	if tCurrentTab == tFrame.talentTabID and tFrame.TalentsFrame then
		tTalentsSection(aParentChilds, tFrame.TalentsFrame)
	end

	-- never leave the window silent
	if #aParentChilds == 0 then
		tText(aParentChilds, "Text: " .. SkuCore:PlayerSpellsFrameName(), tFrame)
	end
end
