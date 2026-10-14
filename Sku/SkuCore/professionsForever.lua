---------------------------------------------------------------------------------------------------------------------------------------
-- Professions window on WoW Forever, built from the crafting API.
-- Forever uses Blizzard's new crafting window (Blizzard_Professions, ProfessionsFrame) for ALL professions, cooking,
-- first aid and fishing included. The old TradeSkillFrame/CraftFrame that SkuCore/LocalMenu.lua is built on do not exist
-- there. So the menu is built from C_TradeSkillUI without reading or clicking a single Blizzard widget:
--   GetBaseProfessionInfo              profession and level
--   GetFilteredRecipeIDs, GetRecipeInfo, GetCategoryInfo   recipes (learned ones only) and their categories
--   GetCraftableCount, GetRecipeSchematic                  how often a recipe can be made, reagents
--   GetRecipeRequirements, GetRecipeDescription            requirements and description
--   CraftRecipe, CraftEnchant, CraftSalvage                crafting
-- The layout is that of the old windows (SkuCore:GetResourceFilterState, AddResourceFilterToggle and the fold state of
-- the categories come from LocalMenu.lua): the filter "resources available", then the categories (foldable) with their
-- recipes. Every recipe has a submenu (create / create all); Shift-Down reads reagents, requirements, description and
-- the tooltip of the result item.
-- Not covered: recrafting and recipes with selectable reagent qualities.
---------------------------------------------------------------------------------------------------------------------------------------
if not Sku.isForever then return end

local L = Sku.L

local DIFFICULTY = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }
local DIFFICULTY_LABEL = {
	optimal = L["optimal"],
	medium = L["medium"],
	easy = L["easy"],
	trivial = L["trivial"],
}

SkuCore.recipeListSig = SkuCore.recipeListSig or {}

local function tSpeak(aText)
	SkuOptions.Voice:OutputStringBTtts(aText, false, true, 0.1)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Reagents in possession. Blizzard counts reagents from the bank only while the game allows it (ReagentsFromBankAllowed,
-- that is with the bank open; see ItemUtil.GetCraftingReagentCount). C_TradeSkillUI.GetCraftableCount also counted
-- leather that only lay in the bank. So Sku counts itself: normally only what the character carries, with the bank
-- open (when Blizzard allows it) the bank too.
local function tCountInPossession(aItemId, aIncludeBank)
	return C_Item.GetItemCount(aItemId, aIncludeBank, false, aIncludeBank, aIncludeBank) or 0
end

-- Reagent slots of a recipe (they do not change): { { qty = n, itemIds = { ... } }, ... }, basic reagents only.
local gRecipeSlots = {}
local function tRecipeSlots(aRecipeId)
	if gRecipeSlots[aRecipeId] ~= nil then return gRecipeSlots[aRecipeId] or nil end
	local tSlots
	local tSchem = C_TradeSkillUI.GetRecipeSchematic(aRecipeId, false)
	if tSchem then
		tSlots = {}
		for _, tSlot in ipairs(tSchem.reagentSlotSchematics or {}) do
			if tSlot.reagentType == Enum.CraftingReagentType.Basic and (tSlot.quantityRequired or 0) > 0 then
				local tIds = {}
				for _, tRe in ipairs(tSlot.reagents or {}) do
					if tRe.itemID then tIds[#tIds + 1] = tRe.itemID end
				end
				if #tIds > 0 then tSlots[#tSlots + 1] = { qty = tSlot.quantityRequired, itemIds = tIds } end
			end
		end
	end
	gRecipeSlots[aRecipeId] = tSlots or false
	return tSlots
end

-- How often the recipe can be made with the reagents at hand (basic reagents only; recipes without them, and
-- enchanting, salvaging and recrafting, fall back to Blizzard's count).
local function tCraftableCount(aRecipeId, aKind)
	if not aKind then
		local tSlots = tRecipeSlots(aRecipeId)
		if tSlots and #tSlots > 0 then
			local tIncludeBank = ReagentsFromBankAllowed()
			local tBest
			for _, tSlot in ipairs(tSlots) do
				local tHave = 0
				for _, tId in ipairs(tSlot.itemIds) do tHave = tHave + tCountInPossession(tId, tIncludeBank) end
				local tN = math.floor(tHave / tSlot.qty)
				if not tBest or tN < tBest then tBest = tN end
			end
			return tBest or 0
		end
	end
	return C_TradeSkillUI.GetCraftableCount(aRecipeId) or 0
end

---------------------------------------------------------------------------------------------------------------------------------------
-- The recipe list as a flat list of headers (skillType "header") and recipes
-- { index = recipeID, name, skillType = difficulty, avail = count, kind }.
function SkuCore:ReadProfessionsList()
	local tList = {}
	local tIds = C_TradeSkillUI.GetFilteredRecipeIDs()
	-- For some professions (skinning: "Sonnen") GetFilteredRecipeIDs gives 0 although GetAllRecipeIDs knows the
	-- recipes (Blizzard's window filter acts before the list is there). Then take all recipes; only learned ones
	-- are kept below anyway.
	if #tIds == 0 then
		local tAll = C_TradeSkillUI.GetAllRecipeIDs()
		if #tAll > 0 then
			dprint("ProfList", "filtered 0, taking all recipes", #tAll)
			tIds = tAll
		end
	end

	local tGroups, tOrder = {}, {}
	for _, tId in ipairs(tIds) do
		local tInfo = C_TradeSkillUI.GetRecipeInfo(tId)
		-- learned recipes only; Blizzard's filter "show unlearned" must not fill the menu
		if tInfo and tInfo.learned ~= false and type(tInfo.name) == "string" and tInfo.name ~= "" then
			local tCatName = ""
			if tInfo.categoryID then
				local tCat = C_TradeSkillUI.GetCategoryInfo(tInfo.categoryID)
				if tCat and type(tCat.name) == "string" then tCatName = tCat.name end
			end
			if not tGroups[tCatName] then
				tGroups[tCatName] = {}
				tOrder[#tOrder + 1] = tCatName
			end
			local tKind = (tInfo.isEnchantingRecipe and "enchant") or (tInfo.isSalvageRecipe and "salvage") or (tInfo.isRecraft and "recraft") or nil
			local g = tGroups[tCatName]
			g[#g + 1] = {
				index = tId,
				name = SkuUtil:Unescape(tInfo.name),
				skillType = DIFFICULTY[tInfo.relativeDifficulty] or "",
				avail = tCraftableCount(tId, tKind),
				kind = tKind,
			}
		end
	end

	for _, tCatName in ipairs(tOrder) do
		if tCatName ~= "" then
			tList[#tList + 1] = { name = SkuUtil:Unescape(tCatName), skillType = "header", avail = 0 }
		end
		for _, r in ipairs(tGroups[tCatName]) do
			tList[#tList + 1] = r
		end
	end
	return tList
end

local function tSignature(aList)
	local tParts = {}
	for x = 1, #aList do
		tParts[#tParts + 1] = aList[x].name .. "#" .. aList[x].skillType .. "#" .. aList[x].avail
	end
	return table.concat(tParts, "|")
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Item names. C_Item.GetItemNameByID gives nothing for items that are not cached (and does not ask for them), which left
-- "wird abgerufen" for reagents. C_Item.GetItemInfo also asks the server for the item; the tooltip text is the last resort.
local function tItemName(aItemId)
	if not aItemId then return nil end
	local tName = C_Item.GetItemNameByID(aItemId) or C_Item.GetItemInfo(aItemId)
	if type(tName) == "string" and tName ~= "" then return tName end
	local tLines = SkuCore:TooltipDataLines(C_TooltipInfo.GetItemByID(aItemId))
	if tLines then return tLines[1] end
	C_Item.RequestLoadItemDataByID(aItemId)
	return nil
end

-- A finished text (all names known) holds as long as the list does not change (the signature contains the craftable
-- counts, so also the reagents in possession). A second Shift-Down on the same recipe then builds nothing again.
local gTextCache = {}

-- The text of a recipe (Shift-Down). Returns the text and whether it is incomplete (an item name was not cached yet;
-- the next press builds again).
function SkuCore:ProfessionRecipeText(aRecipeId)
	if not aRecipeId then return "", false end
	local tSigNow = SkuCore.recipeListSig.prof
	local tCached = gTextCache[aRecipeId]
	if tCached and tCached.sig == tSigNow then return tCached.text, false end

	local tIncomplete = false
	local tOut = {}

	local tInfo = C_TradeSkillUI.GetRecipeInfo(aRecipeId)
	if tInfo and tInfo.name then
		tOut[#tOut + 1] = SkuUtil:Unescape(tInfo.name)
	end

	-- requirements (tool, vicinity of a place, ...)
	for _, tReq in ipairs(C_TradeSkillUI.GetRecipeRequirements(aRecipeId) or {}) do
		if type(tReq.name) == "string" and tReq.name ~= "" then
			tOut[#tOut + 1] = SkuUtil:Unescape(tReq.name) .. ((tReq.met == false) and (" (" .. L["missing"] .. ")") or "")
		end
	end

	-- reagents: name, have/needed. A slot with several quality tiers reads "A / B / C".
	local tSchem = C_TradeSkillUI.GetRecipeSchematic(aRecipeId, false)
	local tOutputItemId
	if tSchem then
		tOutputItemId = tSchem.outputItemID
		for _, tSlot in ipairs(tSchem.reagentSlotSchematics or {}) do
			if tSlot.reagentType == Enum.CraftingReagentType.Basic and (tSlot.quantityRequired or 0) > 0 then
				local tNames, tHave = {}, 0
				for _, tRe in ipairs(tSlot.reagents or {}) do
					if tRe.itemID then
						local tName = tItemName(tRe.itemID)
						if tName then
							tNames[#tNames + 1] = tName
						else
							tIncomplete = true
						end
						tHave = tHave + tCountInPossession(tRe.itemID, ReagentsFromBankAllowed())
					end
				end
				local tNameText = (#tNames > 0) and table.concat(tNames, " / ") or L["wird abgerufen"]
				tOut[#tOut + 1] = SkuUtil:Unescape(tNameText) .. " " .. tHave .. "/" .. tSlot.quantityRequired
			end
		end
	end

	-- description
	local tDesc = C_TradeSkillUI.GetRecipeDescription(aRecipeId, {})
	if type(tDesc) == "string" and tDesc ~= "" then
		tOut[#tOut + 1] = L["description"] .. ": " .. SkuUtil:Unescape(tDesc)
	end

	-- the result item: full tooltip from Blizzard's tooltip data (the scanning tooltip has no SetHyperlink on Forever)
	if tOutputItemId then
		local tLines = SkuCore:TooltipDataLines(C_TooltipInfo.GetItemByID(tOutputItemId))
		if tLines then
			tOut[#tOut + 1] = L["gegenstand"] .. ":"
			tOut[#tOut + 1] = SkuUtil:Unescape(table.concat(tLines, "\r\n"))
		else
			tIncomplete = true
			C_Item.RequestLoadItemDataByID(tOutputItemId)
		end
	end

	local tText = table.concat(tOut, "\r\n")
	if not tIncomplete then gTextCache[aRecipeId] = { sig = tSigNow, text = tText } end
	return tText, tIncomplete
end

-- Preload: after the menu is built, the reagents and result items of all recipes are asked from the server in small
-- batches, so that their names and tooltips are there at Shift-Down (otherwise they come with the server's answer, the
-- text is incomplete and needs a second press). A new build stops a running pass.
local gWarmGeneration = 0
local function tWarmUp(aIds)
	gWarmGeneration = gWarmGeneration + 1
	local tGeneration = gWarmGeneration
	local tBatch = 4
	local function tStep(aPos)
		if tGeneration ~= gWarmGeneration then return end
		for i = aPos, math.min(aPos + tBatch - 1, #aIds) do
			local tSchem = C_TradeSkillUI.GetRecipeSchematic(aIds[i], false)
			if tSchem then
				if tSchem.outputItemID then C_Item.RequestLoadItemDataByID(tSchem.outputItemID) end
				for _, tSlot in ipairs(tSchem.reagentSlotSchematics or {}) do
					for _, tRe in ipairs(tSlot.reagents or {}) do
						if tRe.itemID then C_Item.RequestLoadItemDataByID(tRe.itemID) end
					end
				end
			end
		end
		if aPos + tBatch <= #aIds then
			C_Timer.After(0.2, function() tStep(aPos + tBatch) end)
		end
	end
	tStep(1)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Crafting. CraftRecipe is not protected on Forever (only "AllowedWhenUntainted" for secret arguments); it runs from
-- the key press of the menu.
function SkuCore:ProfessionsCraft(aRecipeId, aCount)
	C_TradeSkillUI.CraftRecipe(aRecipeId, aCount or 1)
end

-- Enchanting and salvaging need a target item. Both go through CraftEnchant/CraftSalvage with an ItemLocation of the
-- target (Blizzard does it the same way: ProfessionsRecipeTransactionMixin:CraftEnchant/CraftSalvage). The target list
-- is only computed when the recipe's submenu opens (lazyChilds), not at every menu build.
function SkuCore:ProfessionsCraftOnTarget(aKind, aRecipeId, aItemGuid, aCount)
	local tLoc = C_Item.GetItemLocation(aItemGuid)
	if not tLoc then
		tSpeak(L["Item no longer available"])
		return
	end
	if aKind == "enchant" then
		C_TradeSkillUI.CraftEnchant(aRecipeId, aCount or 1, {}, tLoc, false)
	elseif aKind == "salvage" then
		C_TradeSkillUI.CraftSalvage(aRecipeId, aCount or 1, tLoc, {}, false)
	end
end

local function tLinkName(aLink)
	if type(aLink) ~= "string" then return nil end
	local tName = aLink:match("%[(.-)%]")
	if tName and tName ~= "" then return SkuUtil:Unescape(tName) end
	return nil
end

local function tInfoNode(aText)
	return { frameName = "", RoC = "Child", type = "Text", textFirstLine = aText, textFull = "", noMenuNumbers = true, childs = {} }
end

local function tTargetActionNode(aLabel, aFunc)
	return { frameName = "", RoC = "Child", type = "Button", textFirstLine = aLabel, textFull = "",
		noMenuNumbers = true, childs = {}, directAction = true, func = aFunc }
end

-- Target items for enchanting: Blizzard's own list (fitting level and slot, equipped or in the bags).
local function tBuildEnchantTargets(aRecipeId)
	local tChilds, tSeen = {}, {}
	for _, tGuid in ipairs(C_TradeSkillUI.GetEnchantItems(aRecipeId, {}) or {}) do
		local tName = tLinkName(C_Item.GetItemLinkByGUID(tGuid)) or L["wird abgerufen"]
		local tWhere = L["in bags"]
		local tLoc = C_Item.GetItemLocation(tGuid)
		if tLoc and tLoc:IsEquipmentSlot() then tWhere = L["equipped"] end
		local tLabel = tName .. " (" .. tWhere .. ")"
		tSeen[tLabel] = (tSeen[tLabel] or 0) + 1
		if tSeen[tLabel] > 1 then tLabel = tLabel .. " " .. tSeen[tLabel] end
		local tGuidNow = tGuid
		tChilds[#tChilds + 1] = tLabel
		tChilds[tLabel] = tTargetActionNode(tLabel, function() SkuCore:ProfessionsCraftOnTarget("enchant", aRecipeId, tGuidNow, 1) end)
	end
	if #tChilds == 0 then
		local tText = L["No suitable item"]
		tChilds[1] = tText
		tChilds[tText] = tInfoNode(tText)
	end
	return tChilds
end

-- Target items for salvaging: items the recipe can salvage that the player owns, in sufficient quantity.
local function tBuildSalvageTargets(aRecipeId)
	local tChilds, tSeen = {}, {}
	local tNeeded = 1
	local tSchem = C_TradeSkillUI.GetRecipeSchematic(aRecipeId, false)
	if tSchem and tSchem.quantityMax and tSchem.quantityMax > 0 then tNeeded = tSchem.quantityMax end
	local tItemIds = C_TradeSkillUI.GetSalvagableItemIDs(aRecipeId)
	for _, tT in ipairs(C_TradeSkillUI.GetCraftingTargetItems(tItemIds or {}) or {}) do
		local tCasts = math.floor((tT.quantity or 0) / tNeeded)
		if tCasts >= 1 and tT.itemGUID then
			local tName = tLinkName(tT.hyperlink) or tItemName(tT.itemID) or L["wird abgerufen"]
			local tLabel = tName .. " x" .. tT.quantity
			tSeen[tLabel] = (tSeen[tLabel] or 0) + 1
			if tSeen[tLabel] > 1 then tLabel = tLabel .. " " .. tSeen[tLabel] end
			local tGuid = tT.itemGUID
			-- one entry with the actions below it: salvage (once) and, where several casts are possible, all
			local tNode = { frameName = "", RoC = "Child", type = "Button", textFirstLine = tLabel, textFull = "",
				noMenuNumbers = true, childs = {} }
			local tOne = L["Salvage"]
			tNode.childs[#tNode.childs + 1] = tOne
			tNode.childs[tOne] = tTargetActionNode(tOne, function() SkuCore:ProfessionsCraftOnTarget("salvage", aRecipeId, tGuid, 1) end)
			if tCasts > 1 then
				local tAll = L["Salvage all"] .. " (" .. tCasts .. ")"
				tNode.childs[#tNode.childs + 1] = tAll
				tNode.childs[tAll] = tTargetActionNode(tAll, function() SkuCore:ProfessionsCraftOnTarget("salvage", aRecipeId, tGuid, tCasts) end)
			end
			tChilds[#tChilds + 1] = tLabel
			tChilds[tLabel] = tNode
		end
	end
	if #tChilds == 0 then
		local tText = L["No suitable item"]
		tChilds[1] = tText
		tChilds[tText] = tInfoNode(tText)
	end
	return tChilds
end

-- The actions below a recipe. Returns a function that delivers the children later, for enchanting and salvaging only.
local function tAddCraftActions(aChilds, aRecipe)
	local function tAdd(aLabel, aCount)
		table.insert(aChilds, aLabel)
		aChilds[aLabel] = tTargetActionNode(aLabel, function() SkuCore:ProfessionsCraft(aRecipe.index, aCount) end)
	end
	if aRecipe.kind == "enchant" then
		return function() return tBuildEnchantTargets(aRecipe.index) end
	elseif aRecipe.kind == "salvage" then
		return function() return tBuildSalvageTargets(aRecipe.index) end
	elseif aRecipe.kind == "recraft" then
		local tNote = L["Recrafting is not supported here yet"]
		table.insert(aChilds, tNote)
		aChilds[tNote] = tInfoNode(tNote)
		return nil
	end
	tAdd(L["Create"], 1)
	if aRecipe.avail > 1 then
		tAdd(L["Create all"] .. " (" .. aRecipe.avail .. ")", aRecipe.avail)
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------------------------
-- The menu
function SkuCore:Build_ProfessionsFrame(aParentChilds)
	local tFrameName = "ProfessionsFrame"

	-- title: profession and level
	local tProfName, tTitle = nil, L["Professions"]
	local tBase = C_TradeSkillUI.GetBaseProfessionInfo()
	if tBase and type(tBase.professionName) == "string" and tBase.professionName ~= "" then
		tProfName = tBase.professionName
		tTitle = tProfName
		if tBase.skillLevel and tBase.maxSkillLevel and tBase.maxSkillLevel > 0 then
			tTitle = tTitle .. " " .. tBase.skillLevel .. "/" .. tBase.maxSkillLevel
		end
	end
	tTitle = SkuUtil:Unescape(tTitle)
	table.insert(aParentChilds, tTitle)
	aParentChilds[tTitle] = {
		frameName = tFrameName, RoC = "Child", type = "FontString", obj = _G[tFrameName],
		textFirstLine = tTitle, textFull = "", childs = {},
	}

	-- filter "resources available" (same switch and setting as in the old windows)
	local tProf = tProfName or tFrameName
	local tFilterOn = SkuCore:GetResourceFilterState(tProf)
	SkuCore:AddResourceFilterToggle(aParentChilds, tProf)

	local tList = SkuCore:ReadProfessionsList()
	SkuCore.recipeListSig.prof = tSignature(tList)

	-- names are keys on this level: a second one of the same name gets an ordinal
	local tSeen = {}
	local function tUnique(aName)
		tSeen[aName] = (tSeen[aName] or 0) + 1
		if tSeen[aName] > 1 then return aName .. " " .. tSeen[aName] end
		return aName
	end

	-- pass 1: group, apply the filter
	local tGroups = { { recipes = {} } }
	for x = 1, #tList do
		local r = tList[x]
		if r.skillType == "header" then
			tGroups[#tGroups + 1] = { name = r.name, recipes = {} }
		elseif not (tFilterOn and r.avail == 0) then
			local g = tGroups[#tGroups].recipes
			g[#g + 1] = r
		end
	end

	-- pass 2: output
	local tShown = 0
	local tWarmIds = {}
	for g = 1, #tGroups do
		local tGroup = tGroups[g]
		local tCollapsed = false
		if tGroup.name and #tGroup.recipes > 0 then
			local tCat = tUnique(tGroup.name)
			local tKey = tCat .. " (" .. L["category"] .. ")"
			tCollapsed = SkuCore:IsRecipeCategoryCollapsed(tProf, tCat)
			table.insert(aParentChilds, tKey)
			aParentChilds[tKey] = {
				frameName = tFrameName, RoC = "Child", type = "Button", obj = _G[tFrameName],
				textFirstLine = tKey, textFull = "", childs = {},
				isSectionHeader = true,
				toggle = {
					label = tKey,
					onLabel = L["eingeklappt"],
					offLabel = L["ausgeklappt"],
					get = function() return SkuCore:IsRecipeCategoryCollapsed(tProf, tCat) end,
					set = function(_, aVal) SkuCore:SetRecipeCategoryCollapsed(tProf, tCat, aVal) end,
					onChange = function() SkuCore:CheckFrames(nil, nil, true) end,
				},
			}
			tShown = tShown + 1
		end

		if tCollapsed ~= true then
			for x = 1, #tGroup.recipes do
				local r = tGroup.recipes[x]
				local tLabel = r.name
				if r.avail > 0 then tLabel = tLabel .. " [" .. r.avail .. "]" end
				if DIFFICULTY_LABEL[r.skillType] then tLabel = tLabel .. " (" .. DIFFICULTY_LABEL[r.skillType] .. ")" end
				tLabel = tUnique(tLabel)

				local tNode = {
					frameName = tFrameName, RoC = "Child", type = "Button", obj = _G[tFrameName],
					textFirstLine = tLabel, textFull = "", childs = {},
					-- Shift-Down builds the text from the API (SkuZOptions/Core.lua, SHIFT-DOWN)
					skuRecipeInfo = { api = "prof", index = r.index },
					-- the label carries the count and changes with it, so pin the cursor by recipe
					skuIdentity = "recipe:" .. r.index,
				}
				tNode.lazyChilds = tAddCraftActions(tNode.childs, r)
				table.insert(aParentChilds, tLabel)
				aParentChilds[tLabel] = tNode
				tWarmIds[#tWarmIds + 1] = r.index
				tShown = tShown + 1
			end
		end
	end

	if tShown == 0 then
		table.insert(aParentChilds, L["Empty"])
		aParentChilds[L["Empty"]] = {
			frameName = tFrameName, RoC = "Child", type = "FontString", obj = _G[tFrameName],
			textFirstLine = L["Empty"], textFull = "", childs = {},
		}
	end

	-- names and tooltips are preloaded in the background (see tWarmUp)
	if #tWarmIds > 0 then
		C_Timer.After(0.3, function() tWarmUp(tWarmIds) end)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Update: the list behind the open window changed (crafted, recipe learned, material moved). Debounced, and only if what
-- WE show changes -- an unconditional rebuild broke the navigation once elsewhere (see the comment at the events in
-- Core.lua).
function SkuCore:RefreshProfessionsMenu()
	if not (ProfessionsFrame and ProfessionsFrame:IsVisible()) then return end
	if tSignature(SkuCore:ReadProfessionsList()) == SkuCore.recipeListSig.prof then return end
	if not SkuOptions:IsMenuOpen() then return end
	SkuCore:RefreshWindowMenuQuietly()
end

local gRefreshPending = false
function SkuCore.PROFESSIONS_LIST_UPDATE(aEvent)
	if gRefreshPending == true then return end
	gRefreshPending = true
	C_Timer.After(0.3, function()
		gRefreshPending = false
		SkuCore:RefreshProfessionsMenu()
	end)
end
