---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME, MODULE_PART = "SkuCore", "LocalMenu"
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

local tRolenamesLookup = {
	[1] = "DAMAGER",
	[2] = "TANK",
	[3] = "HEALER",
	["DAMAGER"] = 1,
	["TANK"] = 2,
	["HEALER"] = 3,
}	

local tBagSlotListSorted = {
	[1] = 0,
	[2] = 1,
	[3] = 2,
	[4] = 3,
	[5] = 4,
	[6] = -1,
	[7] = 5,
	[8] = 6,
	[9] = 7,
	[10] = 8,
	[11] = 9,
	[12] = 10,
	[13] = 11,
	[14] = -2,
	[15] = -3,
}

---------------------------------------------------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------------------------------------------------

-- Local escapes/unescape removed in the Sku 42 rework (W4 Phase A) — now uses the
-- shared SkuUtil:Unescape. Behaviour is identical: SkuUtil's pattern set is this
-- same set plus an extra |A.-|a atlas pattern that is inert on TBC.

local function ItemName_helper(aText)
	aText = SkuUtil:Unescape(aText)
	local tShort, tLong = aText, ""

	local tStart, tEnd = string.find(tShort, "\r\n")
	local taTextWoLb = aText
	if tStart then
		taTextWoLb = string.sub(tShort, 1, tStart - 1)
		tLong = aText
	end

	if string.len(taTextWoLb) > SkuCore.maxItemNameLength then
		local tBlankPos = 1
		while (string.find(taTextWoLb, " ", tBlankPos + 1) and tBlankPos < SkuCore.maxItemNameLength) do
			tBlankPos = string.find(taTextWoLb, " ", tBlankPos + 1)
		end
		if tBlankPos > 1 then
			tShort = string.sub(taTextWoLb, 1, tBlankPos).."..."
		else
			tShort = string.sub(taTextWoLb, 1, SkuCore.maxItemNameLength).."..."
		end		
		tLong = aText
	else
		tShort = taTextWoLb
	end

	tShort = string.gsub(tShort, "\r\n", " ")
	tShort = string.gsub(tShort, "\n", " ")
	return tShort, tLong
end


local function GetButtonTooltipLines(aButtonObj, aTooltipObject)

	local tTooltipObj = aTooltipObject or GameTooltip

	if not aTooltipObject then
		GameTooltip:ClearLines()
		if aButtonObj.type then
			if aButtonObj.type ~= "" then
				if aButtonObj:GetScript("OnEnter") then
					aButtonObj:GetScript("OnEnter")(aButtonObj)
				end
			end
		end
	end

	local tQualityString = nil
	local itemName, ItemLink = tTooltipObj:GetItem()
	local tEffectiveILvl

	if not itemName then
		itemName, ItemLink = tTooltipObj:GetSpell()
	end

	if ItemLink then
		for x = 0, #ITEM_QUALITY_COLORS do
			local tItemCol = ITEM_QUALITY_COLORS[x].color:GenerateHexColor()
			if tItemCol == "ffa334ee" then 
				tItemCol = "ffa335ee"
			end
			if string.find(ItemLink, tItemCol) then
				if _G["ITEM_QUALITY"..x.."_DESC"] then
					tQualityString = _G["ITEM_QUALITY"..x.."_DESC"]
				end
			end
		end
		tEffectiveILvl = GetDetailedItemLevelInfo(ItemLink)
	end

	local tTooltipText = ""
	local tLineCounter = 1
	for i = 1, select("#", tTooltipObj:GetRegions()) do
		local region = select(i, tTooltipObj:GetRegions())
		if region and region:GetObjectType() == "FontString" then
			local text = region:GetText() -- string or nil
			if text then
				if tLineCounter == 1 and tQualityString and SkuSettings:Sub("SkuCore").itemSettings.ShowItemQality == true then
					tTooltipText = tTooltipText..text.." ("..tQualityString..")\r\n"
				elseif tLineCounter == 2 and tEffectiveILvl then
					tTooltipText = tTooltipText..L["Item Level"]..": "..tEffectiveILvl.."\r\n"
					tTooltipText = tTooltipText..text.."\r\n"
				else
					tTooltipText = tTooltipText..text.."\r\n"
				end
				tLineCounter = tLineCounter + 1
			end
		end
	end

	if not aTooltipObject then
		tTooltipObj:SetOwner(UIParent, "Center")
		tTooltipObj:Hide()
		if aButtonObj:GetScript("OnLeave") then
			aButtonObj:GetScript("OnLeave")(aButtonObj)
		end
	end
	
	if tTooltipText ~= "asd" then
		if tTooltipText ~= "" then
			tTooltipText = SkuUtil:Unescape(tTooltipText)
			if tTooltipText then
				local tText, tTextf = SkuCore:ItemName_helper(tTooltipText)
				return tText, tTextf, ItemLink
			end
		end
	end

	return "", ""
end

---------------------------------------------------------------------------------------------------------------------------------------
-- menu items
---------------------------------------------------------------------------------------------------------------------------------------

---@alias EquipLoc string See https://wowpedia.fandom.com/wiki/Enum.InventoryType
---@alias InvSlot integer See https://wowpedia.fandom.com/wiki/InventorySlotId

---Sets tooltip item and returns its cleaned up text.
---(Meant for defining other functions, not meant for direct use)
---@param tooltipSetter fun(tooltip: GameTooltip): void Define how the item tooltip should be set.
---@return string | nil Tooltip text
local function getItemTooltipTextHelper(tooltipSetter)
	local tooltip = _G["SkuScanningTooltip"]
	tooltip:ClearLines()
	tooltipSetter(tooltip)
	local getEscapedText = function() return TooltipLines_helper(tooltip:GetRegions()) end
	if getEscapedText() ~= "asd" and getEscapedText() ~= "" then
		return SkuUtil:Unescape(getEscapedText())
	end
end

local function getItemTooltipTextFromBagItem(bag, slot, itemId, button)
	if button then
		if button:GetScript("OnEnter") then
			button:GetScript("OnEnter")(button)

			local tQualityString = nil
			local itemName, ItemLink = GameTooltip:GetItem()
			local tEffectiveILvl

			if ItemLink then
				for x = 0, #ITEM_QUALITY_COLORS do
					local tItemCol = ITEM_QUALITY_COLORS[x].color:GenerateHexColor()
					if tItemCol == "ffa334ee" then 
						tItemCol = "ffa335ee"
					end
					if string.find(ItemLink, tItemCol) then
						if _G["ITEM_QUALITY"..x.."_DESC"] then
							tQualityString = _G["ITEM_QUALITY"..x.."_DESC"]
						end
					end
				end
				tEffectiveILvl = GetDetailedItemLevelInfo(ItemLink)
			end

			local tTooltipText = ""
			local tLineCounter = 1
			for i = 1, select("#", GameTooltip:GetRegions()) do
				local region = select(i, GameTooltip:GetRegions())
				if region and region:GetObjectType() == "FontString" then
					local text = region:GetText() -- string or nil
					if text then
						if tLineCounter == 1 and tQualityString and SkuSettings:Sub("SkuCore").itemSettings.ShowItemQality == true then
							tTooltipText = tTooltipText..text.." ("..tQualityString..")\r\n"
						elseif tLineCounter == 2 and tEffectiveILvl then
							tTooltipText = tTooltipText..L["Item Level"]..": "..tEffectiveILvl.."\r\n"
							tTooltipText = tTooltipText..text.."\r\n"
						else
							tTooltipText = tTooltipText..text.."\r\n"
						end
						tLineCounter = tLineCounter + 1
					end
				end
			end		
			getItemTooltipTextHelper(function(tooltip)
				if itemId then
					tooltip:SetItemByID(itemId)
				else
					tooltip:SetBagItem(bag, slot)
				end
			end)
			return SkuUtil:Unescape(tTooltipText)
		end
	else

		return getItemTooltipTextHelper(function(tooltip)
			if itemId then
				tooltip:SetItemByID(itemId)
			else
				tooltip:SetBagItem(bag, slot)
			end
		end)
	end
end

---Checks if item is soulbound
---@param bag number bag id
---@param slot number slot id
---@return boolean Whether item is soulbound
function SkuCore:IsItemSoulbound(bag, slot)
	local tooltip = getItemTooltipTextFromBagItem(bag, slot)
	local result = tooltip and  string.find(tooltip, L["Soulbound"])
	-- convert to boolean
	return result and true or false
end

---Gets tooltip text for given equipped item
---@param invSlot InvSlot
---@return string|nil
local function getEquippedItemTooltipText(invSlot)
	return getItemTooltipTextHelper(function(tooltip)
		tooltip:SetInventoryItem("player", invSlot)
	end)
end

-- to reduce repetition
local BOTH_HANDS = {INVSLOT_MAINHAND, INVSLOT_OFFHAND}
local JUST_MAINHAND = {INVSLOT_MAINHAND}
local JUST_OFFHAND = {INVSLOT_OFFHAND}
local RANGED = {INVSLOT_RANGED}

---See https://wowpedia.fandom.com/wiki/Enum.InventoryType
---@type table<EquipLoc, InvSlot[]> Maps what inventory slots (equipped items) correspond to an equip location.
local comparableInvSlotsforInvType = {
	INVTYPE_HEAD = {INVSLOT_HEAD},
	INVTYPE_NECK = {INVSLOT_NECK},
	INVTYPE_SHOULDER = {INVSLOT_SHOULDER},
	INVTYPE_BODY = {INVSLOT_BODY},
	INVTYPE_CHEST = {INVSLOT_CHEST},
	INVTYPE_WAIST = {INVSLOT_WAIST},
	INVTYPE_LEGS = {INVSLOT_LEGS},
	INVTYPE_FEET = {INVSLOT_FEET},
	INVTYPE_WRIST = {INVSLOT_WRIST},
	INVTYPE_HAND = {INVSLOT_HAND},
	INVTYPE_FINGER = {INVSLOT_FINGER1, INVSLOT_FINGER2},
	INVTYPE_TRINKET = {INVSLOT_TRINKET1, INVSLOT_TRINKET2},
	INVTYPE_WEAPON = CanDualWield() and BOTH_HANDS or JUST_MAINHAND,
	INVTYPE_SHIELD = JUST_OFFHAND,
	INVTYPE_RANGED = RANGED,
	INVTYPE_RANGEDRIGHT = RANGED,
	INVTYPE_RELIC = RANGED,
	INVTYPE_AMMO = {INVSLOT_AMMO},
	INVTYPE_2HWEAPON = BOTH_HANDS,
	INVTYPE_CLOAK = {INVSLOT_BACK},
	INVTYPE_TABARD = {INVSLOT_TABARD},
	INVTYPE_ROBE = {INVSLOT_CHEST},
	INVTYPE_THROWN = RANGED,
	INVTYPE_WEAPONMAINHAND = JUST_MAINHAND,
	INVTYPE_WEAPONOFFHAND = JUST_OFFHAND,
	INVTYPE_HOLDABLE = JUST_OFFHAND,
}

---For a given item, Returns item tooltip texts for comparable equipped items.
---@param itemId number Item ID for item for which comparisns will be returned.
---@param cache table|nil Optional lookup table for saving tooltip texts between calls to this function
---@return string[]|nil List of tooltip texts or nil if no slots to compare found
function SkuCore:getItemComparisnSections(itemId, cache)
	local invType = select(4, GetItemInfoInstant(itemId))
	local invSlotsToCompare = comparableInvSlotsforInvType[invType]
	--if offhand slot and equipped a 2H weapon, compare both hands instead
	if invSlotsToCompare == JUST_OFFHAND then
		local mainHandItemId = GetInventoryItemID("player", JUST_MAINHAND[1])
		if mainHandItemId and select(4, GetItemInfoInstant(mainHandItemId)) == "INVTYPE_2HWEAPON" then
			invSlotsToCompare = BOTH_HANDS
		end
	end

	if not invSlotsToCompare then
		return
	end

	local comparisnSections = {}
	for _, slot in pairs(invSlotsToCompare) do
		--local cacheEntry = cache and cache[slot]
		local text = getEquippedItemTooltipText(slot)
		if text then
			table.insert(comparisnSections, text)
			--if cache and not cacheEntry then cache[slot] = text end
		end
	end
	return comparisnSections
end

---Inserts comparisn sections if equipable item.
---@param itemId number Item ID for item for which comparisns will be returned.
---@param textFull string[] List of strings intwo which comparisn sections will be inserted
---@param cache table|nil Optional lookup table for saving tooltip texts between calls to this function
function SkuCore:InsertComparisnSections(itemId, textFull, cache)
	if itemId and IsEquippableItem(itemId) then
		local comparisnSections = SkuCore:getItemComparisnSections(itemId, cache)
		if comparisnSections then
			for i, section in ipairs(comparisnSections) do
				local sectionHeader = #comparisnSections > 1 and L["currently equipped"].." "..i.."\r\n" or L["currently equipped"].."\r\n"
				table.insert(textFull, i + 1, sectionHeader .. section)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local tBagSlotList = {
	[0] = L["Bag"].." 1",
	[1] = L["Bag"].." 2",
	[2] = L["Bag"].." 3",
	[3] = L["Bag"].." 4",
	[4] = L["Bag"].." 5",
	[-1] = L["Bank"],
	[5] = L["Bank"].." "..L["Bag"].." 1",
	[6] = L["Bank"].." "..L["Bag"].." 2",
	[7] = L["Bank"].." "..L["Bag"].." 3",
	[8] = L["Bank"].." "..L["Bag"].." 4",
	[9] = L["Bank"].." "..L["Bag"].." 5",
	[10] = L["Bank"].." "..L["Bag"].." 6",
	[11] = L["Bank"].." "..L["Bag"].." 7",
	[-2] = L["keyring"],
	[-3] = L["Reagent bank"],
}
local function OpenAllBagsHelper()
	-- OpenBag force-opens a container frame (protected in combat). In combat we
	-- only READ what the player already opened via Blizzard's own B key, so skip
	-- the force-open rather than risk a block. Reads use the container APIs and
	-- work regardless of whether we opened the frame.
	if InCombatLockdown and InCombatLockdown() then
		if SkuLogCombat then SkuLogCombat("OpenAllBagsHelper", "skip force-open in combat") end
		return
	end
	for i, v in pairs(tBagSlotList) do
		if i ~= -1 and GetContainerNumSlots(i) > 0 then
			if not IsBagOpen(i) then
				--print("----", i, v, OpenBag(i))
				OpenBag(i)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:Build_GuildBankFrame(aParentChilds)

	OpenAllBagsHelper()

	local tSelectedBankTab = 1
	local inventoryTooltipTextCache = {}
	local tgbf = _G["GuildBankFrame"]

	local friendlyName = L["Bankfächer"]
	table.insert(aParentChilds, friendlyName)
	aParentChilds[friendlyName] = {
		frameName = "",
		RoC = "Child",
		type = "Button",
		obj = nil,
		textFirstLine = friendlyName,
		textFull = "",
		--noMenuNumbers = true,
		childs = {},
	}   

		for x = 1, 20 do
			if _G["GuildBankTab"..x] and _G["GuildBankTab"..x].Button.tooltip and _G["GuildBankTab"..x]:IsVisible() == true then
				local tSelected = ""
				if _G["GuildBankTab"..x].Button:GetChecked() == true then
					tSelected = " ("..L["selected"]..")"
					tSelectedBankTab = x
				end
				local tTabName = _G["GuildBankTab"..x].Button.tooltip..tSelected
				local containerFrameName = "GuildBankTab"..x..".Button"
				table.insert(aParentChilds[friendlyName].childs, tTabName)
				aParentChilds[friendlyName].childs[tTabName] = {
					frameName = containerFrameName,
					RoC = "Child",
					type = "Button",
					obj = _G["GuildBankTab"..x].Button,
					textFirstLine = tTabName,
					textFull = "",
					noMenuNumbers = true,
					childs = {},
					click = true,
					func = _G["GuildBankTab"..x].Button:GetScript("OnClick"),
				}   
			end
		end
		
		
	local friendlyName = L["current Bank box"] --.." "..SkuUtil:Unescape(tgbf.TabTitle:GetText())
	table.insert(aParentChilds, friendlyName)
	aParentChilds[friendlyName] = {
		frameName = "",
		RoC = "Child",
		type = "Button",
		obj = nil,
		textFirstLine = friendlyName,
		textFull = friendlyName.."\r\n"..(_G["GuildBankLimitLabel"]:GetText() or ""),
		--noMenuNumbers = true,
		childs = {},
	}



	local bankVisible = _G["GuildBankFrame"].Column1.Button1:IsVisible()
	if bankVisible == true then

		for col = 1, 7 do
			for slot = 1, 14 do
				local slotIndex = (((col - 1) * 14) + slot)
				local tSlotName = slotIndex.." "..L["Empty"]
				local tText, tFullText = tSlotName, ""
				local containerFrame = tgbf["Column"..col]["Button"..slot]
				table.insert(aParentChilds[friendlyName].childs, tSlotName)
				aParentChilds[friendlyName].childs[tSlotName] = {
					frameName = "Column"..col..".Button"..slot,
					RoC = "Child",
					type = "Button",
					obj = tgbf["Column"..col]["Button"..slot],
					textFirstLine = tSlotName,
					textFull = "",
					noMenuNumbers = true,
					childs = {},
					click = true,
					func = tgbf["Column"..col]["Button"..slot]:GetScript("OnClick"),
				}   

				--update blizzard container object
				aParentChilds[friendlyName].childs[tSlotName].obj.info = aParentChilds[friendlyName].childs[tSlotName].obj.info or {}
				local tLink = GetGuildBankItemLink(tSelectedBankTab, slotIndex)
				if tLink then
					aParentChilds[friendlyName].childs[tSlotName].obj.info.id = Item:CreateFromItemLink(tLink):GetItemID()
					local _, itemCount, locked = GetGuildBankItemInfo(tSelectedBankTab, slotIndex)
					aParentChilds[friendlyName].childs[tSlotName].obj.info.count = itemCount
					aParentChilds[friendlyName].childs[tSlotName].obj.info.gbanktab = tSelectedBankTab
					aParentChilds[friendlyName].childs[tSlotName].obj.info.gbankslot = slotIndex
				end

				local bagItemButton = aParentChilds[friendlyName].childs[tSlotName]
				--get the onclick func if there is one
				if bagItemButton.obj:IsMouseClickEnabled() == true then
					if bagItemButton.obj:GetObjectType() == "Button" then
						bagItemButton.func = bagItemButton.obj:GetScript("OnClick")
					end
					bagItemButton.onActionFunc = function(self, aTable, aChildName)
					end
					if bagItemButton.func then
						bagItemButton.click = true
					end
				end
				
				if bagItemButton.obj.info.id then
					GameTooltip:SetGuildBankItem(bagItemButton.obj.info.gbanktab, bagItemButton.obj.info.gbankslot) 
					
					local _, maybeText = GetButtonTooltipLines(nil, GameTooltip)
					if maybeText then
						local tText = maybeText
						local isEmpty = false
						if bagItemButton.obj.info then
							if bagItemButton.obj.info.id then
								bagItemButton.itemId = bagItemButton.obj.info.id
								bagItemButton.textFirstLine = SkuCore:ItemName_helper(tText)
								bagItemButton.textFull = SkuCore.AuctionHouse:AuctionHouseGetAuctionPriceHistoryData(bagItemButton.obj.info.id)
							end
						end

						if not bagItemButton.textFull then
							bagItemButton.textFull = {}
						end

						local tFirst, tFull = SkuCore:ItemName_helper(tText)
						bagItemButton.textFirstLine = slotIndex.. " "..tFirst
						if type(bagItemButton.textFull) ~= "table" then
							bagItemButton.textFull = { (bagItemButton.textFull or bagItemButton.textFirstLine or ""), }
						end
						table.insert(bagItemButton.textFull, 1, tFull)
						
						SkuCore:InsertComparisnSections(bagItemButton.itemId, bagItemButton.textFull, inventoryTooltipTextCache)
					end

					if bagItemButton.textFirstLine == "" and bagItemButton.textFull == "" and bagItemButton.obj.ShowTooltip then
						GameTooltip:ClearLines()
						bagItemButton.obj:ShowTooltip()
						if TooltipLines_helper(GameTooltip:GetRegions()) ~= "asd" then
							if TooltipLines_helper(GameTooltip:GetRegions()) ~= "" then
								local tText = SkuUtil:Unescape(TooltipLines_helper(GameTooltip:GetRegions()))
								bagItemButton.textFirstLine, bagItemButton.textFull = SkuCore:ItemName_helper(tText)
								isEmpty = false
							end
						end
					end

					if containerFrame.info then
						bagItemButton.itemId = containerFrame.info.id
						if not containerFrame.info.count then
							bagItemButton.textFirstLine = bagItemButton.textFirstLine
						else
							if not isEmpty and containerFrame.info.count > 1 then
								bagItemButton.textFirstLine = bagItemButton.textFirstLine .. " " .. containerFrame.info.count
							end
						end								
					end					
				end
			end
		end
	else
		local tSlotName = L["anzeigen"]
		table.insert(aParentChilds[friendlyName].childs, "GuildBankFrameTab1")
		aParentChilds[friendlyName].childs["GuildBankFrameTab1"] = {
			frameName = "GuildBankFrameTab1",
			RoC = "Child",
			type = "Button",
			obj = _G["GuildBankFrameTab1"],
			textFirstLine = tSlotName,
			textFull = "",
			noMenuNumbers = true,
			childs = {},
			click = true,
			func = _G["GuildBankFrameTab1"]:GetScript("OnClick"),
		}   		
	end
--gold
	--available
	--witdraw
	--deposit



	--log
	local tName = _G["GuildBankFrameTab2"]:GetText()
	table.insert(aParentChilds, tName)
	aParentChilds[tName] = {
		frameName = "",
		RoC = "Child",
		type = "Button",
		obj = nil,
		textFirstLine = tName,
		textFull = "",
		--noMenuNumbers = true,
		childs = {},
	}

	if _G["GuildBankMessageFrame"].FontStringContainer:IsVisible() == true and _G["GuildBankLimitLabel"]:IsVisible() == true then
		local tMessageFull = ""

		local tMaxMsg = GetNumGuildBankTransactions(tSelectedBankTab)
		if tMaxMsg > 100 then tMaxMsg = 100 end
		for q = tMaxMsg, 1, -1 do
			local ttype, name, itemLink, count = GetGuildBankTransaction(tSelectedBankTab, q)
			tMessageFull = tMessageFull..ttype.." "..name.." "..(SkuUtil:Unescape(itemLink) or "").." "..count.."\r\n"
		end

		local tFrameName = "GuildBankMessageFrame"
		local tFriendlyName = SkuUtil:Unescape(tgbf.TabTitle:GetText()).." ..."
		table.insert(aParentChilds[tName].childs, "GuildBankMessageFrame")
		aParentChilds[tName].childs["GuildBankMessageFrame"] = {
			frameName = tFrameName,
			RoC = "Child",
			type = "FontString",
			obj = _G["GuildBankMessageFrame"].FontStringContainer,
			textFirstLine = tFriendlyName,
			textFull = tMessageFull,
			childs = {},
		}
	else
		local tSlotName = L["anzeigen"]
		table.insert(aParentChilds[tName].childs, "GuildBankFrameTab2")
		aParentChilds[tName].childs["GuildBankFrameTab2"] = {
			frameName = "GuildBankFrameTab2",
			RoC = "Child",
			type = "Button",
			obj = _G["GuildBankFrameTab2"],
			textFirstLine = tSlotName,
			textFull = "",
			noMenuNumbers = true,
			childs = {},
			click = true,
			func = _G["GuildBankFrameTab2"]:GetScript("OnClick"),
		}   		
	end

	--money log
	local tName = _G["GuildBankFrameTab3"]:GetText()
	table.insert(aParentChilds, tName)
	aParentChilds[tName] = {
		frameName = "",
		RoC = "Child",
		type = "Button",
		obj = nil,
		textFirstLine = tName,
		textFull = "",
		--noMenuNumbers = true,
		childs = {},
	}

	if _G["GuildBankMessageFrame"].FontStringContainer:IsVisible() == true and _G["GuildBankFrame"].TabTitle:GetText() == _G["GuildBankFrameTab3"]:GetText() then
		local tMessageFull = ""

		local tMaxMsg = GetNumGuildBankMoneyTransactions()
		if tMaxMsg > 100 then tMaxMsg = 100 end
		for q = tMaxMsg, 1, -1 do
			local ttype, name, amount = GetGuildBankMoneyTransaction(q)
			tMessageFull = tMessageFull..ttype.." "..(name or "").." "..(SkuGetCoinText(amount) or "").."\r\n"
		end
		
		local tFrameName = "GuildBankMessageFrame"
		local tFriendlyName = SkuUtil:Unescape(tgbf.TabTitle:GetText()).." ..."
		table.insert(aParentChilds[tName].childs, "GuildBankMessageFrame")
		aParentChilds[tName].childs["GuildBankMessageFrame"] = {
			frameName = tFrameName,
			RoC = "Child",
			type = "FontString",
			obj = _G["GuildBankMessageFrame"].FontStringContainer,
			textFirstLine = tFriendlyName,
			textFull = tMessageFull,
			childs = {},
		}
	else
		local tSlotName = L["anzeigen"]
		table.insert(aParentChilds[tName].childs, "GuildBankFrameTab3")
		aParentChilds[tName].childs["GuildBankFrameTab3"] = {
			frameName = "GuildBankFrameTab3",
			RoC = "Child",
			type = "Button",
			obj = _G["GuildBankFrameTab3"],
			textFirstLine = tSlotName,
			textFull = "",
			noMenuNumbers = true,
			childs = {},
			click = true,
			func = _G["GuildBankFrameTab3"]:GetScript("OnClick"),
		}   		
	end

--[[
	--info
	local tName = _G["GuildBankFrameTab4"]:GetText()
	table.insert(aParentChilds, tName)
	aParentChilds[tName] = {
		frameName = "",
		RoC = "Child",
		type = "Button",
		obj = nil,
		textFirstLine = tName,
		textFull = "",
		--noMenuNumbers = true,
		childs = {},
	}

	if _G["GuildBankInfoScrollFrame"]:IsVisible() == true and _G["GuildBankInfoSaveButton"]:IsVisible() == true then


	else
		local tSlotName = L["anzeigen"]
		table.insert(aParentChilds[tName].childs, "GuildBankFrameTab4")
		aParentChilds[tName].childs["GuildBankFrameTab4"] = {
			frameName = "GuildBankFrameTab4",
			RoC = "Child",
			type = "Button",
			obj = _G["GuildBankFrameTab4"],
			textFirstLine = tSlotName,
			textFull = "",
			noMenuNumbers = true,
			childs = {},
			click = true,
			func = _G["GuildBankFrameTab4"]:GetScript("OnClick"),
		}   		
	end
]]
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:Build_BankFrame(aParentChilds)
	OpenAllBagsHelper()
end

---------------------------------------------------------------------------------------------------------------------------------------
local tIsProcessing = 0
local tIsProcessingHandle
local function SortProcessingSoundHelper()
	if tIsProcessingHandle == nil then
		tIsProcessingHandle = C_Timer.NewTicker(0.5, function(self)
			if tIsProcessing > 0 then
				--SkuOptions.Voice:OutputStringBTtts("sound-notification24", false, true)
			else
				self:Cancel() 
				tIsProcessingHandle = nil
				C_Timer.After(0.1, function()
					SkuOptions.currentMenuPosition.parent:OnUpdate()
					SkuOptions.Voice:OutputStringBTtts("sound-notification16", false, true)--24
				end)
			end
		
		end)
	end
end

local function BagSortMenuHelper(aParentChilds, aBagId)

	local function tGetContainerFrameHelper(tCurrentContainerFrameNumber, tNumSlots, slotId)
		local containerFrameName = ""
		if tCurrentContainerFrameNumber then
			containerFrameName = "ContainerFrame"..(tCurrentContainerFrameNumber).."Item"..(tNumSlots - slotId + 1)
		end
		if tCurrentContainerFrameNumber == nil and _G["BankFrame"] and _G["BankFrame"]:IsVisible() == true then
			tCurrentContainerFrameNumber = -1
			containerFrameName = "BankFrameItem"..slotId
		end
		return _G[containerFrameName]
	end


	--collapse
	local tFriendlyName = L["Remove empty bag slots (collapse)"]
	table.insert(aParentChilds, tFriendlyName)
	aParentChilds[tFriendlyName] = {
		frameName = nil,
		RoC = "Child",
		type = "Button",
		textFirstLine = tFriendlyName,
		textFull = "",
		noMenuNumbers = true,
		childs = {},
		func = function()
			SkuCore.CursorSilent = true
			SkuOptions.Voice.TutorialPlaying = 1
			for i, v in pairs(tBagSlotList) do
				if i == aBagId or aBagId == nil then
					local tCurrentContainerFrameNumber = IsBagOpen(i)
					local tNumSlots = GetContainerNumSlots(i)
					if tNumSlots > 0 and (tCurrentContainerFrameNumber or (i == -1 and _G["BankFrame"] and _G["BankFrame"]:IsVisible() == true)) then
						local tCompleted = true
						local co = coroutine.create(function ()
							while tCompleted == true do
								local tLastEmptySlotFrame = nil
								tCompleted = false
								for slotId = 1, tNumSlots do
									local containerFrameName = ""
									if tCurrentContainerFrameNumber then
										containerFrameName = "ContainerFrame"..(tCurrentContainerFrameNumber).."Item"..(tNumSlots - slotId + 1)
									end
									if i == -1 and _G["BankFrame"] and _G["BankFrame"]:IsVisible() == true then
										tCurrentContainerFrameNumber = -1
										containerFrameName = "BankFrameItem"..slotId
									end
						
									local containerFrame = _G[containerFrameName]
									local maybeText = getItemTooltipTextFromBagItem(nil, nil, nil, containerFrame)
									local tFirst, tFull
									if maybeText then
										tFirst, tFull = SkuCore:ItemName_helper(maybeText)
										if tFirst == "" then tFirst = nil end
									end

									if tFirst and tLastEmptySlotFrame ~= nil then
										containerFrame:GetScript("OnClick")(containerFrame, "LeftButton")
										tLastEmptySlotFrame:GetScript("OnClick")(tLastEmptySlotFrame, "LeftButton") 
										tLastEmptySlotFrame = containerFrame
										tCompleted = true
										coroutine.yield()
										break
									elseif not tFirst and tLastEmptySlotFrame == nil then
										tLastEmptySlotFrame = containerFrame
										if slotId == tNumSlots then
											tCompleted = false
										end
									elseif slotId == tNumSlots and tLastEmptySlotFrame == nil then
										tCompleted = false
									end
								end
							end
						end)

						tIsProcessing = tIsProcessing + 1
						SortProcessingSoundHelper()
						cbObject = C_Timer.NewTicker(0.5, function(self) 
							if coroutine.status(co) == "suspended" then
								SortProcessingSoundHelper()
								coroutine.resume(co)
							else
								tIsProcessing = tIsProcessing - 1
								self:Cancel() 
								SkuCore.CursorSilent = false
								SkuOptions.Voice.TutorialPlaying = 0
								SkuOptions.Voice:StopOutputEmptyQueue()
								SortProcessingSoundHelper()
							end
						end)
					end
				end
			end
		end,
	}   



	--sort by quality
	local function SortByQualityHelper(tCurrentContainerFrameNumber, tNumSlots, i, aEvaluateFunc)
		SkuCore.CursorSilent = true
		SkuOptions.Voice.TutorialPlaying = 1
		local co = coroutine.create(function ()
			local tProcess = true
			while tProcess do
				tProcess = nil
				for count = 1, tNumSlots - 1 do
					local tPickContainerFrame = tGetContainerFrameHelper(tCurrentContainerFrameNumber, tNumSlots, count)
					local tPlaceContainerFrame = tGetContainerFrameHelper(tCurrentContainerFrameNumber, tNumSlots, count + 1)
					local tPickQuali, tPlaceQuali
					if i == -1 then
						local invSlot = BankButtonIDToInvSlotID(count)
						local pickItemLink = GetInventoryItemLink("player", invSlot)
						if not pickItemLink then
							tPickQuali = "zzzzzzzzzz"
						else
							tPickQuali = C_Item.GetItemQualityByID(pickItemLink)
						end

						local invSlot = BankButtonIDToInvSlotID(count + 1)
						local placeItemlink = GetInventoryItemLink("player", invSlot)
						if not placeItemlink then
							tPlaceQuali = "zzzzzzzzzz"
						else
							tPlaceQuali = C_Item.GetItemQualityByID(placeItemlink)
						end
					else
						_G["SkuScanningTooltip"]:ClearLines()
						_G["SkuScanningTooltip"]:SetBagItem(i, count)
						local itemName, pickItemLink = _G["SkuScanningTooltip"]:GetItem()
						tPickQuali = 99999
						if pickItemLink then
							tPickQuali = C_Item.GetItemQualityByID(pickItemLink)
						end
						_G["SkuScanningTooltip"]:ClearLines()
						_G["SkuScanningTooltip"]:SetBagItem(i, count + 1)
						local itemName, placeItemLink = _G["SkuScanningTooltip"]:GetItem()
						tPlaceQuali = 99999
						if placeItemLink then
							tPlaceQuali = C_Item.GetItemQualityByID(placeItemLink)
						end
					end

					if aEvaluateFunc(tPickQuali, tPlaceQuali) == true then
						if pickItemLink then
							tPickContainerFrame:GetScript("OnClick")(tPickContainerFrame, "LeftButton")
							tPlaceContainerFrame:GetScript("OnClick")(tPlaceContainerFrame, "LeftButton")
						else
							tPlaceContainerFrame:GetScript("OnClick")(tPlaceContainerFrame, "LeftButton")
							tPickContainerFrame:GetScript("OnClick")(tPickContainerFrame, "LeftButton")
						end
						tProcess = true
						break
					end
				end
				coroutine.yield()
			end
		end)

		tIsProcessing = tIsProcessing + 1
		SortProcessingSoundHelper()
		cbObject = C_Timer.NewTicker(0.01, function(self) 
			if coroutine.status(co) == "suspended" then
				SortProcessingSoundHelper()
				local tret = coroutine.resume(co)
			else
				tIsProcessing = tIsProcessing - 1
				self:Cancel() 
				SkuCore.CursorSilent = false
				SkuOptions.Voice.TutorialPlaying = 0
				SkuOptions.Voice:StopOutputEmptyQueue()
				SortProcessingSoundHelper()
			end
		end)
	end

	local tFriendlyName = L["Sort items by quality"].." "..L["ascending"]
	table.insert(aParentChilds, tFriendlyName)
	aParentChilds[tFriendlyName] = {
		frameName = nil,
		RoC = "Child",
		type = "Button",
		textFirstLine = tFriendlyName,
		textFull = "",
		noMenuNumbers = true,
		childs = {},
		func = function()
			for i, v in pairs(tBagSlotList) do
				if i == aBagId or aBagId == nil then
					local tCurrentContainerFrameNumber = IsBagOpen(i)
					local tNumSlots = GetContainerNumSlots(i)
					if tNumSlots > 0 and (tCurrentContainerFrameNumber or (i == -1 and _G["BankFrame"] and _G["BankFrame"]:IsVisible() == true)) then
						SortByQualityHelper(tCurrentContainerFrameNumber, tNumSlots, i, function(a, b)
						 	return a > b
						end)
					end
				end
			end
		end,
	}   
	local tFriendlyName = L["Sort items by quality"].." "..L["descending"]
	table.insert(aParentChilds, tFriendlyName)
	aParentChilds[tFriendlyName] = {
		frameName = nil,
		RoC = "Child",
		type = "Button",
		textFirstLine = tFriendlyName,
		textFull = "",
		noMenuNumbers = true,
		childs = {},
		func = function()
			--print("func Sort by quality descending", aBagId)
			for i, v in pairs(tBagSlotList) do
				if i == aBagId or aBagId == nil then
					local tCurrentContainerFrameNumber = IsBagOpen(i)
					local tNumSlots = GetContainerNumSlots(i)
					if tNumSlots > 0 and (tCurrentContainerFrameNumber or (i == -1 and _G["BankFrame"] and _G["BankFrame"]:IsVisible() == true)) then
						SortByQualityHelper(tCurrentContainerFrameNumber, tNumSlots, i, function(a, b)
						 	return a < b
						end)
					end
				end
			end
		end,
	}   





	--sort by name
	local function SortByNameHelper(tCurrentContainerFrameNumber, tNumSlots, i, aEvaluateFunc)
		SkuCore.CursorSilent = true
		SkuOptions.Voice.TutorialPlaying = 1
		local co = coroutine.create(function ()
			local tProcess = true
			while tProcess do
				tProcess = nil
				for count = 1, tNumSlots - 1 do
					local tPickContainerFrame = tGetContainerFrameHelper(tCurrentContainerFrameNumber, tNumSlots, count)
					local tPlaceContainerFrame = tGetContainerFrameHelper(tCurrentContainerFrameNumber, tNumSlots, count + 1)
					local pickitemName, placeitemName
					if i == -1 then
						local invSlot = BankButtonIDToInvSlotID(count)
						local pickItemLink = GetInventoryItemLink("player", invSlot)
						if not pickItemLink then
							pickitemName = "zzzzzzzzzz"
						else
							pickitemName = C_Item.GetItemNameByID(pickItemLink)
						end

						local invSlot = BankButtonIDToInvSlotID(count + 1)
						local placeItemlink = GetInventoryItemLink("player", invSlot)
						if not placeItemlink then
							placeitemName = "zzzzzzzzzz"
						else
							placeitemName = C_Item.GetItemNameByID(placeItemlink)
						end
					else
						_G["SkuScanningTooltip"]:ClearLines()
						_G["SkuScanningTooltip"]:SetBagItem(i, count)
						pickitemName, pickItemLink = _G["SkuScanningTooltip"]:GetItem()
						if not pickitemName then
							pickitemName = "zzzzzzzzzz"
						end
						_G["SkuScanningTooltip"]:ClearLines()
						_G["SkuScanningTooltip"]:SetBagItem(i, count + 1)
						placeitemName = _G["SkuScanningTooltip"]:GetItem()
						if not placeitemName then
							placeitemName = "zzzzzzzzzz"
						end
					end
					if aEvaluateFunc(pickitemName, placeitemName) == true then
						if pickItemLink then
							tPickContainerFrame:GetScript("OnClick")(tPickContainerFrame, "LeftButton")
							tPlaceContainerFrame:GetScript("OnClick")(tPlaceContainerFrame, "LeftButton")
						else
							tPlaceContainerFrame:GetScript("OnClick")(tPlaceContainerFrame, "LeftButton")
							tPickContainerFrame:GetScript("OnClick")(tPickContainerFrame, "LeftButton")
						end
						tProcess = true
						break
					end
				end
				coroutine.yield()
			end
		end)

		tIsProcessing = tIsProcessing + 1
		SortProcessingSoundHelper()
		cbObject = C_Timer.NewTicker(0.01, function(self) 
			if coroutine.status(co) == "suspended" then
				SortProcessingSoundHelper()
				local tret = coroutine.resume(co)
			else
				tIsProcessing = tIsProcessing - 1
				self:Cancel() 
				SkuCore.CursorSilent = false
				SkuOptions.Voice.TutorialPlaying = 0
				SkuOptions.Voice:StopOutputEmptyQueue()
				SortProcessingSoundHelper()
			end
		end)
	end

	--sort by name
	local tFriendlyName = L["Sort items by name"].." "..L["ascending"]
	table.insert(aParentChilds, tFriendlyName)
	aParentChilds[tFriendlyName] = {
		frameName = nil,
		RoC = "Child",
		type = "Button",
		textFirstLine = tFriendlyName,
		textFull = "",
		noMenuNumbers = true,
		childs = {},
		func = function()
			for i, v in pairs(tBagSlotList) do
				if i == aBagId or aBagId == nil then
					local tCurrentContainerFrameNumber = IsBagOpen(i)
					local tNumSlots = GetContainerNumSlots(i)
					if tNumSlots > 0 and (tCurrentContainerFrameNumber or (i == -1 and _G["BankFrame"] and _G["BankFrame"]:IsVisible() == true)) then
						SortByNameHelper(tCurrentContainerFrameNumber, tNumSlots, i, function(a, b)
						 	return a > b
						end)
					end
				end
			end
		end,
	}   
	local tFriendlyName = L["Sort items by name"].." "..L["descending"]
	table.insert(aParentChilds, tFriendlyName)
	aParentChilds[tFriendlyName] = {
		frameName = nil,
		RoC = "Child",
		type = "Button",
		textFirstLine = tFriendlyName,
		textFull = "",
		noMenuNumbers = true,
		childs = {},
		func = function()
			for i, v in pairs(tBagSlotList) do
				if i == aBagId or aBagId == nil then
					local tCurrentContainerFrameNumber = IsBagOpen(i)
					local tNumSlots = GetContainerNumSlots(i)
					if tNumSlots > 0 and (tCurrentContainerFrameNumber or (i == -1 and _G["BankFrame"] and _G["BankFrame"]:IsVisible() == true)) then
						SortByNameHelper(tCurrentContainerFrameNumber, tNumSlots, i, function(a, b)
						 	return a < b
						end)
					end
				end
			end
		end,
	}   






end

---------------------------------------------------------------------------------------------------------------------------------------
local ContainerFrame1Hook
function SkuCore:Build_BagsFrame(aParentChilds)
	if not ContainerFrame1Hook then
		hooksecurefunc(_G["ContainerFrame1"], "Hide", function()
			for x = 2, 15 do
				if _G["ContainerFrame"..x] then
					_G["ContainerFrame"..x]:Hide()
				end
			end
		end)
		ContainerFrame1Hook = true
	end

	local tEmptyCounter = 1
	local tCurrentParentContainer = nil
	local allBagResults = {}
	local tBagResultsByBag = {}
	local inventoryTooltipTextCache = {}

	-- Container-API driven enumeration: bags no longer need to be OPEN/rendered. Item
	-- data is read via the API on (bagId, slotId) and each entry stores bag/slot; the bag
	-- menu actions (SkuZOptions/Core.lua) act via PickupContainerItem/UseContainerItem/
	-- SocketContainerItem on those. Removed OpenAllBagsHelper() -- nothing force-opens the
	-- bags now (that proactive render was the login-stuck-menu cause). Bank slots keep the
	-- rendered BankFrameItem name for their existing /click path (the bank is only
	-- reachable with its frame already up).
	for q = 1, #tBagSlotListSorted do
		local bagId = tBagSlotListSorted[q]
		local tIsBankSlot = (bagId == -1 and _G["BankFrame"] and _G["BankFrame"]:IsVisible() == true)
		local tNumSlots = GetContainerNumSlots(bagId) or 0
		-- BUGFIX: the bank container (-1) reports its 28 slots even when the bank UI is
		-- closed, producing a phantom "Bank" view in the bags menu. Only include it while the
		-- bank frame is actually open (0 slots -> the slot loop skips it, no bag node created).
		if bagId == -1 and not (_G["BankFrame"] and _G["BankFrame"]:IsVisible() == true) then
			tNumSlots = 0
		end
		for slotId = 1, tNumSlots do
			-- bag (parent) node, once per bag, keyed by bagId
			if not tBagResultsByBag[bagId] then
				local bagName = tBagSlotList[bagId]
				table.insert(aParentChilds, bagName)
				aParentChilds[bagName] = {
					frameName = nil,
					RoC = "Child",
					type = "Button",
					obj = nil,
					textFirstLine = bagName,
					textFull = "",
					noMenuNumbers = true,
					childs = {},
					bag = bagId,
				}
				tBagResultsByBag[bagId] = { obj = aParentChilds[bagName], childs = {} }
			end

			local tFriendlyName = L["Bag"] .. bagId .. "-" .. slotId
			local tItemId = GetContainerItemID(bagId, slotId)
			local _, tCount = GetContainerItemInfo(bagId, slotId)
			local isEmpty = (tItemId == nil)

			local bagItemButton = {
				frameName = nil,
				RoC = "Child",
				type = "Button",
				obj = nil,
				textFirstLine = L["Empty"],
				textFull = "",
				noMenuNumbers = true,
				childs = {},
				isNewItem = (C_NewItems and C_NewItems.IsNewItem(bagId, slotId)) or false,
				-- stable per-slot identity for view-aware cursor restore
				bagSlot = bagId .. ":" .. slotId,
				bag = bagId,
				slot = slotId,
			}
			if tIsBankSlot then
				bagItemButton.containerFrameName = "BankFrameItem" .. slotId
			end
			aParentChilds[tFriendlyName] = bagItemButton

			-- Make EVERY slot -- empty or filled -- a click item. The gossip menu only
			-- attaches the click actions when the entry has BOTH click==true AND a func
			-- (SkuZOptions/Core.lua, click==true branch); the container-API migration set
			-- these only for non-empty slots, which dropped the actions on EMPTY slots --
			-- and with them the ability to DROP a held item into an empty slot (left
			-- click / ENTER -> PickupContainerItem(bag, slot), which places the cursor
			-- item). The real actions come from the .bag/.slot fields, so this func is a
			-- never-called no-op placeholder. (For an empty slot the right-click "/use"
			-- and "Sockeln" are simply no-ops -- nothing there to use.)
			bagItemButton.click = true
			bagItemButton.func = function() end
			if not isEmpty then
				bagItemButton.itemId = tItemId
				if tCount and tCount > 1 then
					bagItemButton.stackSize = tostring(tCount)
				end
				-- Pass NO itemId so the reader uses tooltip:SetBagItem(bag, slot) -- the
				-- actual item instance (full description, use-effects, charges, bound,
				-- flavour), matching what the old rendered-button OnEnter tooltip gave.
				-- Passing itemId would route to SetItemByID (generic) and lose that.
				local tText = getItemTooltipTextFromBagItem(bagId, slotId)
				if tText then
					isEmpty = false
					bagItemButton.textFirstLine = SkuCore:ItemName_helper(tText)
					bagItemButton.textFull = SkuCore.AuctionHouse:AuctionHouseGetAuctionPriceHistoryData(tItemId)
					if type(bagItemButton.textFull) ~= "table" then
						bagItemButton.textFull = { (bagItemButton.textFull or bagItemButton.textFirstLine or "") }
					end
					table.insert(bagItemButton.textFull, 1, tText)
					SkuCore:InsertComparisnSections(tItemId, bagItemButton.textFull, inventoryTooltipTextCache)
				end
			end

			-- position number prefix within the bag
			bagItemButton.textFirstLine = (#tBagResultsByBag[bagId].childs + 1) .. " " .. bagItemButton.textFirstLine
			tEmptyCounter = tEmptyCounter + 1
			if not isEmpty and tCount and tCount > 1 then
				bagItemButton.textFirstLine = bagItemButton.textFirstLine .. " " .. tCount
			end

			tBagResultsByBag[bagId].childs[#tBagResultsByBag[bagId].childs + 1] = bagItemButton
			-- non-empty items in the real bags also go into the flat "all items" list
			if not isEmpty and bagId >= 0 and bagId <= 4 then
				local copy = {}
				for k, v in pairs(bagItemButton) do
					copy[k] = v
				end
				copy.textFirstLine = string.sub(copy.textFirstLine, string.find(copy.textFirstLine, " ") + 1)
				-- bagSlot stays the precise identity for cursor restore / duplicate stacks
				table.insert(allBagResults, copy)
				allBagResults[copy] = copy
			end
		end
	end

	for q = -3, 40 do
		local i, v = q, tBagResultsByBag[q]
		if v then
			for ic, vc in pairs(v.childs) do
				table.insert(v.obj.childs, vc)
				v.obj.childs[vc] = vc
			end

			--sort button
			local tFriendlyName = L["Sorting and cleanup"]
			table.insert(v.obj.childs, tFriendlyName)
			v.obj.childs[tFriendlyName] = {
				frameName = nil,
				RoC = "Child",
				type = "Button",
				obj = nil,
				textFirstLine = tFriendlyName,
				textFull = "",
				noMenuNumbers = true,
				childs = {},
				func = nil,
				click = true,
			}   
			BagSortMenuHelper(v.obj.childs[tFriendlyName].childs, v.obj.bag, v)
		end
	end

	-- sort all items alphabetically, putting newly acquired on top
	table.sort(allBagResults, function(item1, item2)
		if item1.isNewItem and not item2.isNewItem then
			return true
		elseif item2.isNewItem and not item1.isNewItem then
			return false
		end
		return item1.textFirstLine < item2.textFirstLine
	end)

	-- Capture the exact "all items" display order for the combat-actions mirror -- a single
	-- source of truth so the in-combat secure /use always matches the item the menu shows
	-- (no re-deriving the sort, no locale/tie drift). The mirror pre-stages from this at
	-- combat start. See SkuCore/combatMenuKeys.lua / [[sku42-combat-item-use-design]].
	SkuCore.combatBagOrder = {}
	for _, itemButton in ipairs(allBagResults) do
		if itemButton.bag ~= nil and itemButton.slot ~= nil then
			SkuCore.combatBagOrder[#SkuCore.combatBagOrder + 1] = { bag = itemButton.bag, slot = itemButton.slot }
		end
	end

	-- prepend "new" to all new items
	for _, itemButton in pairs(allBagResults) do
		if itemButton.isNewItem then
			if not string.find(itemButton.textFirstLine, "^"..L["New"]) then
				itemButton.textFirstLine = L["New"] .. " " .. itemButton.textFirstLine
			end
		end
	end
	-- all items menu item
	do
		local allItemsMenuItemName = L["all items"]
		table.insert(aParentChilds, allItemsMenuItemName)
		aParentChilds[allItemsMenuItemName] = {
			RoC = "Child",
			type = "Button",
			textFirstLine = allItemsMenuItemName,
			noMenuNumbers = true,
			childs = allBagResults,
		}
	end

	local tFriendlyName = L["Bags"]
	table.insert(aParentChilds, tFriendlyName)
	aParentChilds[tFriendlyName] = {
		frameName = nil,
		RoC = "Child",
		type = "Button",
		obj = nil,
		textFirstLine = tFriendlyName,
		textFull = "",
		noMenuNumbers = true,
		childs = {},
		func = nil,
		click = true,
	}   

	tCurrentParentContainer = aParentChilds[tFriendlyName]

	local tBarBagSlots = {
		[1] = _G["MainMenuBarBackpackButton"],
		[2] = _G["CharacterBag0Slot"],
		[3] = _G["CharacterBag1Slot"],
		[4] = _G["CharacterBag2Slot"],
		[5] = _G["CharacterBag3Slot"],
	}

	for x = 1, #tBarBagSlots do
		local containerFrameName = "CharacterBag".. x.."Slot"
		if tBarBagSlots[x] then
			local tFriendlyName = L["Bag-slot"] .. " " .. (x)
			if tBarBagSlots[x]:IsEnabled() == true then
				aParentChilds[tFriendlyName] = {
					frameName = tBarBagSlots[x]:GetName(),--L["Bag-slot"]..(x),
					RoC = "Child",
					type = "Button",
					obj = tBarBagSlots[x],
					textFirstLine = tFriendlyName,
					textFull = "",
					noMenuNumbers = true,
					childs = {},
					func = tBarBagSlots[x]:GetScript("OnClick"),
					click = true,
					isBag = true,
				}   
				if x == 1 or x == 6 then
					aParentChilds[tFriendlyName].childs = {}
					aParentChilds[tFriendlyName].type = "Text"
					aParentChilds[tFriendlyName].func = nil
				end   

				GameTooltip:ClearLines()
				aParentChilds[tFriendlyName].obj:GetScript("OnEnter")(aParentChilds[tFriendlyName].obj)
				if TooltipLines_helper(GameTooltip:GetRegions()) ~= "asd" then
					if TooltipLines_helper(GameTooltip:GetRegions()) ~= "" then
						local tText = SkuUtil:Unescape(TooltipLines_helper(GameTooltip:GetRegions()))
						--[[
						if string.find(tText, "Equip Container") then
							tText = L["Empty"]
						end
						]]
						tText = x.." "..tText
						aParentChilds[tFriendlyName].textFirstLine, aParentChilds[tFriendlyName].textFull = SkuCore:ItemName_helper(tText)
					end
				end
			end

			table.insert(tCurrentParentContainer.childs, aParentChilds[tFriendlyName])
			tCurrentParentContainer.childs[aParentChilds[tFriendlyName] ] = aParentChilds[tFriendlyName]
		end
	end    
	
	if _G["BankSlotsFrame"] and _G["BankSlotsFrame"].Bag1:IsVisible() == true then
		local numPurBankSlots, fullBankSlots = GetNumBankSlots()
		local costForNextPur = GetBankSlotCost(numPurBankSlots)

		for x = 1, numPurBankSlots do
			local containerFrameName = "Bag"..x
			local tFriendlyName = ""--"Bank Bag slot".." "..(x)
			if _G["BankSlotsFrame"]["Bag"..x]:IsEnabled() == true then


				--local tText = _G["BankSlotsFrame"]["Bag"..x].tooltipText
				--print(x, tText)--Purchasable

				aParentChilds[tFriendlyName] = {
					frameName = "BankSlotsFrame.Bag"..x,
					RoC = "Child",
					type = "Button",
					obj = _G["BankSlotsFrame"]["Bag"..x],
					textFirstLine = tFriendlyName,
					textFull = "",
					noMenuNumbers = true,
					childs = {},
					func = _G["BankSlotsFrame"]["Bag"..x]:GetScript("OnClick"),
					click = true,
					isBag = true,
				}   

				GameTooltip:ClearLines()
				aParentChilds[tFriendlyName].obj:GetScript("OnEnter")(aParentChilds[tFriendlyName].obj)
				if TooltipLines_helper(GameTooltip:GetRegions()) ~= "asd" then
					if TooltipLines_helper(GameTooltip:GetRegions()) ~= "" then
						local tText = SkuUtil:Unescape(TooltipLines_helper(GameTooltip:GetRegions()))
						tText = x.." "..tText
						aParentChilds[tFriendlyName].textFirstLine, aParentChilds[tFriendlyName].textFull = SkuCore:ItemName_helper(tText)
						aParentChilds[tFriendlyName].textFirstLine = L["Bank"].. " "..aParentChilds[tFriendlyName].textFirstLine
					end
				end
			end

			table.insert(tCurrentParentContainer.childs, aParentChilds[tFriendlyName])
			tCurrentParentContainer.childs[aParentChilds[tFriendlyName] ] = aParentChilds[tFriendlyName]
		end  	

		if fullBankSlots ~= true then
			local cost = SkuGetCoinText(GetBankSlotCost(numPurBankSlots))
			local x = numPurBankSlots + 1
			local containerFrameName = "Bag"..x
			local tFriendlyName = L["Bank"].." "..x.." ".._G["BankSlotsFrame"]["Bag"..x].tooltipText.." "..cost
			if _G["BankSlotsFrame"]["Bag"..x]:IsEnabled() == true then
				aParentChilds[tFriendlyName] = {
					frameName = "BankSlotsFrame.Bag"..x,
					RoC = "Child",
					type = "Button",
					obj = _G["BankSlotsFrame"]["Bag"..x],
					textFirstLine = tFriendlyName,
					textFull = "",
					noMenuNumbers = true,
					childs = {},
					func = PurchaseSlot,
					click = true,
					isBag = true,
					isPurchasable = true,
				}   
			end

			table.insert(tCurrentParentContainer.childs, aParentChilds[tFriendlyName])
			tCurrentParentContainer.childs[aParentChilds[tFriendlyName] ] = aParentChilds[tFriendlyName]
		end
	end

	--sort all button
	local tFriendlyName = L["Sorting and cleanup all bags"]
	table.insert(aParentChilds, tFriendlyName)
	aParentChilds[tFriendlyName] = {
		frameName = nil,
		RoC = "Child",
		type = "Button",
		obj = nil,
		textFirstLine = tFriendlyName,
		textFull = "",
		noMenuNumbers = true,
		childs = {},
		func = nil,
		click = true,
	}   

	BagSortMenuHelper(aParentChilds[tFriendlyName].childs, nil)

	-- Capture the per-view bag TREE for the combat-actions mirror: every top-level view in
	-- display order (per-bag lists, all-items, keyring, ...) with its usable items (bag/slot)
	-- in child order. Single source of truth so the in-combat tree mirror matches the menu
	-- exactly (order + ties). Non-item views are kept (empty item list) so the view-level
	-- index stays aligned with the menu. See SkuCore/combatMenuKeys.lua / [[sku42-combat-item-use-design]].
	do
		local tTree = {}
		for _, tViewName in ipairs(aParentChilds) do
			local tNode = aParentChilds[tViewName]
			if type(tNode) == "table" and type(tNode.childs) == "table" then
				local tItems = {}
				for _, tChild in ipairs(tNode.childs) do
					if type(tChild) == "table" and tChild.bag ~= nil and tChild.slot ~= nil then
						tItems[#tItems + 1] = { bag = tChild.bag, slot = tChild.slot }
					end
				end
				tTree[#tTree + 1] = { label = tostring(tViewName), items = tItems }
			end
		end
		SkuCore.combatBagTree = tTree
		if SkuLogCombat then
			local tSummary = ""
			for i, v in ipairs(tTree) do tSummary = tSummary .. i .. ":" .. v.label .. "(" .. #v.items .. ") " end
			SkuLogCombat("bagTree", tSummary)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function round(num)
	local mult = 10^(2 or 0)
	return math.floor(num * mult + 0.5) / mult
end

---------------------------------------------------------------------------------------------------------------------------------------
--calendar














---------------------------------------------------------------------------------------------------------------------------------------
--addons









---------------------------------------------------------------------------------------------------------------------------------------
local function GetTooltipLines(aObj, aTooltipObject)
	local tTooltipObj = aTooltipObject or GameTooltip
	tTooltipObj:ClearLines()
	if aObj.GetScript and aObj:GetScript("OnEnter") then
		aObj:GetScript("OnEnter")(aObj)
	end

	local tFirstText
	local tTooltipText = ""
	for i = 1, select("#", tTooltipObj:GetRegions()) do
		local region = select(i, tTooltipObj:GetRegions())
		if region and region:GetObjectType() == "FontString" then
			local text = region:GetText() -- string or nil
			if text then
				if not tFirstText then
					tFirstText = text
				end
				if i == 1 and tQualityString and SkuSettings:Sub("SkuCore").itemSettings.ShowItemQality == true then
					tTooltipText = tTooltipText..text.." ("..tQualityString..")\r\n"
				else
					tTooltipText = tTooltipText..text.."\r\n"
				end

			end
		end
	end

	return tFirstText, tTooltipText
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PLAYER_TALENT_UPDATE()
	--print("PLAYER_TALENT_UPDATE")
	if _G["PlayerTalentFrame"] and _G["PlayerTalentFrame"]:IsVisible() then
		if SkuOptions:IsMenuOpen() == true then
			C_Timer.After(0.3, function()
				SkuOptions.currentMenuPosition:OnUpdate()
			end)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Fired when the player switches between dual talent specializations.
-- Triggers a full rebuild so the "(aktiv)" markers and spec-specific contents
-- update correctly.
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:ACTIVE_TALENT_GROUP_CHANGED()
	if _G["PlayerTalentFrame"] and _G["PlayerTalentFrame"]:IsVisible() then
		if SkuOptions and SkuOptions.IsMenuOpen and SkuOptions:IsMenuOpen() == true then
			C_Timer.After(0.3, function()
				pcall(function() SkuCore:CheckFrames() end)
				if SkuOptions and SkuOptions.currentMenuPosition then
					local tPos = SkuOptions.currentMenuPosition
					while tPos and tPos.parent and tPos.parent.parent do
						tPos = tPos.parent
					end
					if tPos and tPos.OnUpdate then
						pcall(function() tPos:OnUpdate() end)
					end
				end
			end)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Helpers for dual talent specialization (WotLK+). Safe no-ops on older clients.
---------------------------------------------------------------------------------------------------------------------------------------
-- This Anniversary TBC server backports dual-spec via the modern
-- C_SpecializationInfo namespace (Retail-style) rather than the
-- WotLK-era SetActiveTalentGroup. We prefer that namespace and fall
-- back to the legacy API on stock clients.
local function tGetNumTalentGroups()
	if _G.C_SpecializationInfo and _G.C_SpecializationInfo.GetNumSpecGroups then
		local ok, v = pcall(_G.C_SpecializationInfo.GetNumSpecGroups)
		if ok and type(v) == "number" then return v end
	end
	if _G.GetNumTalentGroups then
		local ok, v = pcall(_G.GetNumTalentGroups)
		if ok and type(v) == "number" then return v end
	end
	return 1
end

local function tGetActiveTalentGroup()
	if _G.C_SpecializationInfo and _G.C_SpecializationInfo.GetActiveSpecGroup then
		local ok, v = pcall(_G.C_SpecializationInfo.GetActiveSpecGroup)
		if ok and type(v) == "number" then return v end
	end
	if _G.GetActiveTalentGroup then
		local ok, v = pcall(_G.GetActiveTalentGroup)
		if ok and type(v) == "number" then return v end
	end
	return 1
end

-- Server-aware spec switch. Prefer C_SpecializationInfo.SetActiveSpecGroup
-- (works on the Anniversary backport) and fall back to SetActiveTalentGroup.
-- Returns: ok (bool), errorMessage (string or nil), apiUsed (string).
local function tSwitchSpec(groupIdx)
	if _G.C_SpecializationInfo and _G.C_SpecializationInfo.SetActiveSpecGroup then
		local ok, e = pcall(_G.C_SpecializationInfo.SetActiveSpecGroup, groupIdx)
		return ok, (not ok) and tostring(e) or nil, "C_SpecializationInfo.SetActiveSpecGroup"
	end
	if _G.SetActiveTalentGroup then
		local ok, e = pcall(_G.SetActiveTalentGroup, groupIdx)
		return ok, (not ok) and tostring(e) or nil, "SetActiveTalentGroup"
	end
	return false, "no switch API available", "none"
end

-- Returns a descriptive spec name: the talent tab with the most points spent
-- (e.g. "Heilig", "Schatten") or a fallback "Spezialisierung N".
local function tGetSpecName(groupIdx)
	local bestName, bestPoints = nil, -1
	if _G.GetNumTalentTabs and _G.GetTalentTabInfo then
		local ok, numTabs = pcall(_G.GetNumTalentTabs)
		if ok and type(numTabs) == "number" then
			for tab = 1, numTabs do
				local ok2, name, icon, points = pcall(_G.GetTalentTabInfo, tab, false, false, groupIdx)
				if ok2 and type(points) == "number" and points > bestPoints then
					bestPoints = points
					bestName = name
				end
			end
		end
	end
	if bestName and bestPoints and bestPoints > 0 then
		return bestName .. " (" .. bestPoints .. ")"
	end
	return (L["Spezialisierung"] or "Spezialisierung") .. " " .. tostring(groupIdx)
end

-- Read-only content for the inactive spec using the API
local function tBuildInactiveSpec(aParent, groupIdx)
	-- Activation action
	local tActivateLabel = L["Diese Spezialisierung aktivieren"] or "Diese Spezialisierung aktivieren"
	table.insert(aParent, tActivateLabel)
	aParent[tActivateLabel] = {
		frameName = "",
		RoC = "Child",
		type = "Button",
		obj = _G["PlayerTalentFrame"] or _G["UIParent"],
		textFirstLine = tActivateLabel,
		textFull = "",
		childs = {},
		-- directAction = true makes the entry fire `func` immediately on
		-- Enter, without expanding into a Linksklick/Rechtsklick submenu.
		directAction = true,
		-- Secure macrotext path: routed through the secure ENTER button
		-- so SetActiveTalentGroup is invoked from a hardware-event
		-- context. Some Classic-era builds reject the call when made
		-- from a plain Lua handler. The /run line is the actual switch;
		-- a follow-up TTS announcement runs unconditionally so the user
		-- gets feedback either way.
		-- /script (TBC client uses /script, /run is WotLK+). Calls the
		-- modern namespace first, then the legacy API. Whichever exists
		-- wins; the other is a nil-check no-op.
		-- macrotext: switch only. The TTS announcement is queued from
		-- `func` AFTER the menu's auto re-read (which would otherwise
		-- interrupt it and the user would only hear the new menu node).
		macrotext = "/script if C_SpecializationInfo and C_SpecializationInfo.SetActiveSpecGroup then C_SpecializationInfo.SetActiveSpecGroup(" .. tostring(groupIdx) .. ") elseif SetActiveTalentGroup then SetActiveTalentGroup(" .. tostring(groupIdx) .. ") end",
		-- Lua fallback path (also runs through directAction.OnAction).
		-- Logs detailed state to SkuErrorLog so we can diagnose if the
		-- API call silently no-ops on this client build.
		func = function()
			local tBefore = tGetActiveTalentGroup()
			local tOk, tErr, tApiUsed = tSwitchSpec(groupIdx)
			local tAfter = tGetActiveTalentGroup()
			-- Log every attempt so we can see in SkuErrorLog whether
			-- the call landed and whether the active group changed.
			dprint("talentSwitch", "spec switch attempt", {
				requested  = groupIdx,
				before     = tBefore,
				after      = tAfter,
				apiUsed    = tApiUsed,
				callOk     = tOk,
				inCombat   = (UnitAffectingCombat and UnitAffectingCombat("player")) and true or false,
				err        = tErr,
			})
			-- The directAction wrapper steps to the parent and triggers
			-- OnUpdate at +0.35s, which makes Sku read the new menu node.
			-- We delay our confirmation past that read so it isn't
			-- interrupted, and use a non-replacing call (false, false)
			-- so the menu read finishes before we speak.
			local tMsg = L["Spezialisierung wird gewechselt"] or "Spezialisierung wird gewechselt"
			if _G.C_Timer and _G.C_Timer.After then
				_G.C_Timer.After(1.2, function()
					pcall(function()
						SkuOptions.Voice:OutputStringBTtts(tMsg, false, false, 0.2, nil, nil, nil, 2)
					end)
				end)
			else
				pcall(function()
					SkuOptions.Voice:OutputStringBTtts(tMsg, false, false, 0.2, nil, nil, nil, 2)
				end)
			end
			-- Stale-block: kept for symmetry; the directAction wrapper
			-- already does CheckFrames + OnUpdate, but we also walk up
			-- to the top-level so the "(aktiv)" labels rebuild.
			if _G.C_Timer and _G.C_Timer.After then
				_G.C_Timer.After(0.6, function()
					pcall(function() SkuCore:CheckFrames() end)
					if SkuOptions and SkuOptions.currentMenuPosition then
						local tPos = SkuOptions.currentMenuPosition
						while tPos and tPos.parent and tPos.parent.parent do
							tPos = tPos.parent
						end
						if tPos and tPos.OnUpdate then
							pcall(function() tPos:OnUpdate() end)
						end
					end
				end)
			end
		end,
	}

	if not (_G.GetNumTalentTabs and _G.GetTalentTabInfo and _G.GetNumTalents and _G.GetTalentInfo) then
		return
	end

	local ok, numTabs = pcall(_G.GetNumTalentTabs)
	if not ok or type(numTabs) ~= "number" then return end

	for tab = 1, numTabs do
		local ok2, tabName, _, points = pcall(_G.GetTalentTabInfo, tab, false, false, groupIdx)
		if ok2 and tabName then
			local tTabLabel = L["Tab"] .. " " .. tabName .. " (" .. (points or 0) .. ")"
			table.insert(aParent, tTabLabel)
			local tTabEntry = {
				frameName = "",
				RoC = "Child",
				type = "Text",
				obj = _G["PlayerTalentFrame"] or _G["UIParent"],
				textFirstLine = tTabLabel,
				textFull = "",
				childs = {},
			}
			aParent[tTabLabel] = tTabEntry

			local ok3, numTalents = pcall(_G.GetNumTalents, tab, false, false)
			if ok3 and type(numTalents) == "number" then
				for t = 1, numTalents do
					local ok4, tName, tIcon, tTier, tColumn, tRank, tMaxRank =
						pcall(_G.GetTalentInfo, tab, t, false, false, groupIdx)
					if ok4 and tName then
						local tLabel = tName .. " (" .. tostring(tRank or 0) .. "/" .. tostring(tMaxRank or 0) .. ")"
						-- Avoid duplicate labels
						if tTabEntry.childs[tLabel] then tLabel = tLabel .. " #" .. tostring(t) end
						table.insert(tTabEntry.childs, tLabel)
						tTabEntry.childs[tLabel] = {
							frameName = "",
							RoC = "Child",
							type = "Text",
							obj = _G["PlayerTalentFrame"] or _G["UIParent"],
							textFirstLine = tLabel,
							textFull = "",
							childs = {},
						}
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Active-spec content: the original UI-driven build, extracted into a helper so
-- it can either populate the top-level list (single-spec) or a submenu
-- (dual-spec, active group).
---------------------------------------------------------------------------------------------------------------------------------------
local function tBuildActiveSpecUI(aParentChilds)

	local tFrameName = "PlayerTalentFrameTitleText"
	if _G["GlyphFrame"] and _G["GlyphFrame"]:IsVisible() == true then
		tFrameName = "GlyphFrameTitleText"
	end
	local tFriendlyName = "Text: ".._G[tFrameName]:GetText()
	table.insert(aParentChilds, tFriendlyName)
	aParentChilds[tFriendlyName] = {
		frameName = tFrameName,
		RoC = "Child",
		type = "Text",
		obj = _G[tFrameName],
		textFirstLine = tFriendlyName,
		textFull = "",
		childs = {},
	}

	for x = 1, 4 do
		local tFrameName = "PlayerTalentFrameTab"..x
		if _G[tFrameName] and _G[tFrameName]:IsVisible() == true then
			local tttFirst, tttFull = _G[tFrameName]:GetText()
			local tFriendlyName = tttFirst
			table.insert(aParentChilds, tFriendlyName)
			aParentChilds[tFriendlyName] = {
				frameName = tFrameName,
				RoC = "Child",
				type = "Button",
				obj = _G[tFrameName],
				textFirstLine = tFriendlyName,
				textFull = tttFull,
				childs = {},
				func = _G[tFrameName]:GetScript("OnClick"),
				click = true,
			}   	
			
			local tSelected
			for i, v in pairs({_G[tFrameName]:GetRegions()}) do
				if v.GetText then
					if v:GetText() == _G[tFrameName]:GetText() then
						local r, g, b, a = v:GetTextColor()
						if r > 0.9 and g > 0.9 and b > 0.9 then
							tSelected = true
						end
					end
				end
			end
			if tSelected then
				aParentChilds[tFriendlyName].textFirstLine = aParentChilds[tFriendlyName].textFirstLine.." ("..L["selected"]..")"
				aParentChilds[tFriendlyName].func = nil
				aParentChilds[tFriendlyName].click = false
			end
			aParentChilds[tFriendlyName].textFirstLine = L["Tab"].." "..aParentChilds[tFriendlyName].textFirstLine
		end
	end		
	
	if not _G["GlyphFrame"] or _G["GlyphFrame"]:IsVisible() == false then

		local tFrameName = "PlayerTalentFrameSpentPointsText"
		if _G[tFrameName]:IsVisible() == true then
			local tFriendlyName = SkuUtil:Unescape("Text: "..L["Spent for"].." ".._G[tFrameName]:GetText())
			table.insert(aParentChilds, tFriendlyName)
			aParentChilds[tFriendlyName] = {
				frameName = tFrameName,
				RoC = "Child",
				type = "Text",
				obj = _G[tFrameName],
				textFirstLine = tFriendlyName,
				textFull = "",
				childs = {},
			}   
		end
		local tFrameName = "PlayerTalentFrameTalentPointsText"
		if _G[tFrameName]:IsVisible() == true then
			local tFriendlyName = SkuUtil:Unescape("Text: ".._G[tFrameName]:GetText())
			table.insert(aParentChilds, tFriendlyName)
			aParentChilds[tFriendlyName] = {
				frameName = tFrameName,
				RoC = "Child",
				type = "Text",
				obj = _G[tFrameName],
				textFirstLine = tFriendlyName,
				textFull = "",
				childs = {},
			}   
		end


		local tTalentsUnsorted = {}
		local tMax = 0
		for x = 1, 100 do
			local tFrameName = "PlayerTalentFrameTalent"..x
			if _G[tFrameName] and _G[tFrameName]:IsVisible() == true then
				local tttFirst, tttFull = GetTooltipLines(_G[tFrameName])
				local p1, parent, p2, px, py = _G[tFrameName]:GetPoint(1)
				local column = math.floor(px / 63) + 1
				local tier = math.floor(py / 63) * -1
				tMax = column + (tier * 4)
				tTalentsUnsorted[tMax] = tFrameName
			end
		end

		local tTalentsSorted = {}
		local tCounter = 1
		for x = 1, 10000 do
			if tTalentsUnsorted[x] then
				tTalentsSorted[tCounter] = tTalentsUnsorted[x]
				tCounter = tCounter + 1
			end
		end

		for i, v in ipairs(tTalentsSorted) do
			local tFrameName = v
			if _G[tFrameName] and _G[tFrameName]:IsVisible() == true then
				local tttFirst, tttFull = GetTooltipLines(_G[tFrameName])
				if _G[tFrameName.."Rank"] and _G[tFrameName.."Rank"].GetText then
					tttFirst = tttFirst.." ("..(_G[tFrameName.."Rank"]:GetText() or "nil")..")"
				end
				local tFriendlyName = tttFirst
				table.insert(aParentChilds, tFriendlyName)
				aParentChilds[tFriendlyName] = {
					frameName = tFrameName,
					RoC = "Child",
					type = "Button",
					obj = _G[tFrameName],
					textFirstLine = tFriendlyName,
					textFull = tttFull,
					childs = {},
					func = _G[tFrameName]:GetScript("OnClick"),
					click = true,
				}
				
				local tTexture = _G[tFrameName]:GetRegions()
				if tTexture:GetDesaturation() > 0 then
					-- Nur visueller Hinweis — Submenü bleibt aktiv,
					-- damit der User auch bei (vermeintlich) gesperrten
					-- Talenten Linksklick auswählen kann. Auf 2.5.5 sind
					-- ungelernt-aber-lernbare Talente teilweise auch
					-- desaturiert, was die alte Logik fälschlich
					-- als "disabled" interpretierte.
					aParentChilds[tFriendlyName].textFirstLine =
						aParentChilds[tFriendlyName].textFirstLine
						.. " (" .. L["disabled"] .. ")"
				end
			end
		end
	end


end

---------------------------------------------------------------------------------------------------------------------------------------
-- Top-level dispatcher: if dual talent spec is unlocked (GetNumTalentGroups > 1),
-- show both specs as top-level submenus. Otherwise keep the original flat
-- UI-driven layout.
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:Build_TalentFrame(aParentChilds)
	local tNumGroups = tGetNumTalentGroups()
	-- Note: dual talent specialization is officially a WotLK 3.1 feature,
	-- but custom servers (e.g. this Anniversary TBC build) backport it.
	-- We therefore do NOT gate on interface version — only on the actual
	-- talent-group count returned by the server. If the server says the
	-- player has 2 groups, we show the dual-spec menu and let the
	-- activation path try whatever switch mechanism the server provides.
	if tNumGroups <= 1 then
		-- no dual spec: preserve original behavior exactly
		tBuildActiveSpecUI(aParentChilds)
		return
	end

	local tActive = tGetActiveTalentGroup()
	for g = 1, tNumGroups do
		local tSpecName = tGetSpecName(g)
		local tLabel
		if g == tActive then
			tLabel = tSpecName .. " (" .. (L["aktiv"] or "aktiv") .. ")"
		else
			tLabel = tSpecName
		end

		-- Deduplicate identical labels (rare, but handle it)
		if aParentChilds[tLabel] then tLabel = tLabel .. " #" .. tostring(g) end

		table.insert(aParentChilds, tLabel)
		local tEntry = {
			frameName = "",
			RoC = "Child",
			type = "Button",
			obj = _G["PlayerTalentFrame"] or _G["UIParent"],
			textFirstLine = tLabel,
			textFull = "",
			childs = {},
		}
		aParentChilds[tLabel] = tEntry

		if g == tActive then
			-- active: use existing UI-driven builder
			tBuildActiveSpecUI(tEntry.childs)
		else
			-- inactive: API-driven read-only + activation action
			tBuildInactiveSpec(tEntry.childs, g)
		end
	end
end


---------------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:Build_RolePollPopup(aParentChilds)

	local tButtons = {
		[1] = _G["RolePollPopupRoleButtonTank"],
		[2] = _G["RolePollPopupRoleButtonHealer"],
		[3] = _G["RolePollPopupRoleButtonDPS"],
	}
	local tFallbackRoles = { "TANK", "HEALER", "DAMAGER" }
	local tLocalizedNames = { L["ROLE_Tank"], L["ROLE_Healer"], L["ROLE_Damage"] }

	for x = 1, #tButtons do
		if tButtons[x] then
			local tRoleKey = tButtons[x].role or tFallbackRoles[x]
			local tFriendlyName = tLocalizedNames[x] or _G[tRoleKey] or tRoleKey or ("Role " .. x)

			if tButtons[x].checkButton and tButtons[x].checkButton:GetChecked() == true then
				tFriendlyName = tFriendlyName.." ("..L["selected"]..")"
			end

			table.insert(aParentChilds, tFriendlyName)
			aParentChilds[tFriendlyName] = {
				frameName = "",
				RoC = "Child",
				type = "Button",
				obj = tButtons[x],
				textFirstLine = SkuUtil:Unescape(tFriendlyName),
				textFull = "",
				childs = {},
				directAction = true,
				func = function()
					-- Pruefen ob Rolle bereits gewaehlt ist
					local tAlreadyChecked = tButtons[x].checkButton
						and tButtons[x].checkButton:GetChecked()
					if not tAlreadyChecked then
						-- Rolle erst waehlen (Toggle an)
						pcall(function() tButtons[x]:Click("LeftMouse") end)
					end
					-- Dann bestaetigen
					C_Timer.After(0.1, function()
						if _G["RolePollPopupAcceptButton"] and _G["RolePollPopupAcceptButton"]:IsEnabled() then
							pcall(function() _G["RolePollPopupAcceptButton"]:Click("LeftMouse") end)
						end
					end)
				end,
			}
		end
	end

end

-----------------------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:BuildEngravingFrame(aParentChilds)
	local tFrameName = "EngravingFrame"
	local tFriendlyName = L["Runes"]
	table.insert(aParentChilds, tFriendlyName)
	aParentChilds[tFriendlyName] = {
		frameName = tFrameName,
		RoC = "Child",
		type = "Button",
		obj = _G[tFrameName],
		textFirstLine = tFriendlyName,
		textFull = "",
		childs = {},
	}

	local tParentEngravingFrame = aParentChilds[tFriendlyName].childs

   local tHasEntries = false

	local categories = C_Engraving.GetRuneCategories(true, true);
	for _, category in ipairs(categories) do
		local tCatName = GetItemInventorySlotInfo(category)

		tHasEntries = true

		local runes = C_Engraving.GetRunesForCategory(category, true);
		for tindex, rune in ipairs(runes) do
			local tFull = ""
			_G["SkuScanningTooltip"]:ClearLines()
			_G["SkuScanningTooltip"]:SetEngravingRune(rune.skillLineAbilityID)
			if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "asd" then
				if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "" then
					local tText = SkuUtil:Unescape(TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()))
					_, tFull = SkuCore:ItemName_helper(tText)
				end
			end
		
			local tFrameName = tindex
			local tFriendlyName = SkuUtil:Unescape(rune.name)
			table.insert(tParentEngravingFrame, tFriendlyName)
			tParentEngravingFrame[tFriendlyName] = {
				frameName = tFrameName,
				RoC = "Child",
				type = "Button",
				textFirstLine = tFriendlyName,
				textFull = tFull,
				childs = {},
			}
			
			local tParentRuneFrame = tParentEngravingFrame[tFriendlyName].childs
			table.insert(tParentRuneFrame, L["Engrave"])
			tParentRuneFrame[L["Engrave"]] = {
				frameName = nil,
				RoC = "Child",
				type = "Button",
				obj = EngravingFrame,
				textFirstLine = L["Engrave"],
				textFull = "",
				childs = {},
				func = function(self, aButton)
					C_Engraving.CastRune(rune.skillLineAbilityID)
				end,            
				click = true,
			}
		end
   end

   if tHasEntries == false then
		local tFriendlyName = L["Empty"]
		table.insert(tParentEngravingFrame, tFriendlyName)
		tParentEngravingFrame[tFriendlyName] = {
			frameName = nil,
			RoC = "Child",
			type = "Button",
			textFirstLine = tFriendlyName,
			textFull = "",
			childs = {},
		}
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:Build_CharacterFrame(aParentChilds)
	-- GearManagerToggleButton:Click() is a protected click (blocked in combat).
	-- Skip it in combat; the stat/equipment reads below use non-protected APIs and
	-- the always-present PaperDoll widgets, so they still populate. Out of combat
	-- this is unchanged.
	if _G["GearManagerToggleButton"] and not (InCombatLockdown and InCombatLockdown()) then
		_G["GearManagerToggleButton"]:Click("LeftMouse")
	elseif _G["GearManagerToggleButton"] and SkuLogCombat then
		SkuLogCombat("Build_CharacterFrame", "skip GearManagerToggleButton:Click in combat")
	end

	local tFrameName = "CharacterLevelText"
	local tFriendlyName = _G["CharacterLevelText"]:GetText()
	table.insert(aParentChilds, tFriendlyName)
	aParentChilds[tFriendlyName] = {
		frameName = tFrameName,
		RoC = "Child",
		type = "FontString",
		obj = _G[tFrameName],
		textFirstLine = tFriendlyName,
		textFull = "",
		childs = {},
	}

	--items (flattened: the former "Gegenstände"/L["Items"] node was the ONLY child of
	-- "Ausrüstung", so it is removed -- the equipment slot list now hangs directly under
	-- "Ausrüstung". The in-combat character mirror needs NO change: it walks whatever tree
	-- shape aParentChilds has (see the combatCharTree tWalk below) and detects slot nodes by
	-- the "^Character.+Slot$" key pattern, not by depth, so it just gets one level shallower.)
	local tFrameName = ""
	local tFriendlyName = L["Equipment"]
	table.insert(aParentChilds, tFriendlyName)
	aParentChilds[tFriendlyName] = {
		frameName = tFrameName,
		RoC = "Child",
		type = "Button",
		obj = _G[tFrameName],
		textFirstLine = tFriendlyName,
		textFull = "",
		childs = {},
		--click = true,
	}
	local tParentEquipment = aParentChilds[tFriendlyName]
	tParentEquipment.childs = SkuCore:IterateChildren(_G["PaperDollItemsFrame"], 2)

	for x = 1, #tParentEquipment.childs do
		if tParentEquipment.childs[x] == "GearManagerToggleButton" then
			tParentEquipment.childs[x] = nil
			tParentEquipment.childs["GearManagerToggleButton"] = nil
		end
	end

		-- (The in-combat character mirror is captured as a FULL tree at the very end of this
		-- function, once every branch -- Equipment, Stats, Professions, Sets -- has been built.
		-- See the "combatCharTree" capture below. Kept there so it mirrors the whole screen, not
		-- just the equipment list.)

	--stats
	do
		local tFrameName = ""
		local tFriendlyName = L["Stats"]
		table.insert(aParentChilds, tFriendlyName)
		aParentChilds[tFriendlyName] = {
			frameName = tFrameName,
			RoC = "Child",
			type = "Button",
			obj = _G[tFrameName],
			textFirstLine = tFriendlyName,
			textFull = "",
			childs = {},
			--click = true,
		}   
		local tParentStats = aParentChilds[tFriendlyName].childs

		if not Sku.isTBC then
			local tStatFrames = {
				"CharacterStatFrame1",
				"CharacterStatFrame2",
				"CharacterStatFrame3",
				"CharacterStatFrame4",
				"CharacterStatFrame5",
				"CharacterArmorFrame",
				"CharacterAttackFrame",
				"CharacterAttackPowerFrame",
				"CharacterDamageFrame",
				"CharacterRangedAttackFrame",
				"CharacterRangedAttackPowerFrame",
				"CharacterRangedDamageFrame",
			}

			for i, v in pairs(tStatFrames) do
				local tFrameName = v
				local tFriendlyName = SkuUtil:Unescape(_G[v.."Label"]:GetText().." ".._G[v.."StatText"]:GetText())
				table.insert(tParentStats, tFriendlyName)
				tParentStats[tFriendlyName] = {
					frameName = tFrameName,
					RoC = "Child",
					type = "Button",
					obj = _G[tFrameName],
					textFirstLine = tFriendlyName,
					textFull = "",
					childs = {},
					--click = true,
				}

			end
		else
			local tUpdateCode = {
				[PLAYERSTAT_BASE_STATS] = {
					[[PaperDollFrame_SetStat(PlayerStatFrameLeft1, 1)]],
					[[PaperDollFrame_SetStat(PlayerStatFrameLeft1, 2)]],
					[[PaperDollFrame_SetStat(PlayerStatFrameLeft1, 3)]],
					[[PaperDollFrame_SetStat(PlayerStatFrameLeft1, 4)]],
					[[PaperDollFrame_SetStat(PlayerStatFrameLeft1, 5)]],
					[[PaperDollFrame_SetArmor(PlayerStatFrameLeft1)]],
				},
				[PLAYERSTAT_MELEE_COMBAT] = {
					[[PaperDollFrame_SetDamage(PlayerStatFrameLeft1) PlayerStatFrameLeft1:SetScript("OnEnter", CharacterDamageFrame_OnEnter)]],
					[[PaperDollFrame_SetAttackSpeed(PlayerStatFrameLeft1)]],
					[[PaperDollFrame_SetAttackPower(PlayerStatFrameLeft1)]],
					[[PaperDollFrame_SetRating(PlayerStatFrameLeft1, CR_HIT_MELEE)]],
					[[PaperDollFrame_SetMeleeCritChance(PlayerStatFrameLeft1)]],
					[[PaperDollFrame_SetExpertise(PlayerStatFrameLeft1)]],
				},
				[PLAYERSTAT_RANGED_COMBAT] = {
					[[PaperDollFrame_SetRangedDamage(PlayerStatFrameLeft1) PlayerStatFrameLeft1:SetScript("OnEnter", CharacterRangedDamageFrame_OnEnter)]],
					[[PaperDollFrame_SetRangedAttackSpeed(PlayerStatFrameLeft1)]],
					[[PaperDollFrame_SetRangedAttackPower(PlayerStatFrameLeft1)]],
					[[PaperDollFrame_SetRating(PlayerStatFrameLeft1, CR_HIT_RANGED)]],
					[[PaperDollFrame_SetRangedCritChance(PlayerStatFrameLeft1)]],
				},
				[PLAYERSTAT_SPELL_COMBAT] = {
					[[PaperDollFrame_SetSpellBonusDamage(PlayerStatFrameLeft1) PlayerStatFrameLeft1:SetScript("OnEnter", CharacterSpellBonusDamage_OnEnter)]],
					[[PaperDollFrame_SetSpellBonusHealing(PlayerStatFrameLeft1)]],
					[[PaperDollFrame_SetRating(PlayerStatFrameLeft1, CR_HIT_SPELL)]],
					[[PaperDollFrame_SetSpellCritChance(PlayerStatFrameLeft1) PlayerStatFrameLeft1:SetScript("OnEnter", CharacterSpellCritChance_OnEnter)]],
					[[PaperDollFrame_SetSpellHaste(PlayerStatFrameLeft1)]],
					[[PaperDollFrame_SetManaRegen(PlayerStatFrameLeft1)]],
				},
				[PLAYERSTAT_DEFENSES] = {
					[[PaperDollFrame_SetArmor(PlayerStatFrameLeft1)]],
					[[PaperDollFrame_SetDefense(PlayerStatFrameLeft1)]],
					[[PaperDollFrame_SetDodge(PlayerStatFrameLeft1)]],
					[[PaperDollFrame_SetParry(PlayerStatFrameLeft1)]],
					[[PaperDollFrame_SetBlock(PlayerStatFrameLeft1)]],
					[[PaperDollFrame_SetResilience(PlayerStatFrameLeft1)]],
				},
			}
			
			for i, v in pairs(tUpdateCode) do
				local tFrameName = i
				local tFriendlyName = i
				table.insert(tParentStats, tFriendlyName)
				tParentStats[tFriendlyName] = {
					frameName = tFrameName,
					RoC = "Child",
					type = "Button",
					obj = _G[tFrameName],
					textFirstLine = i,
					textFull = "",
					childs = {},
					--click = true,
				}

				local tParentStatsValues = tParentStats[tFriendlyName].childs
				for i1, v1 in pairs(v) do
					loadstring(v1)()

					if PlayerStatFrameLeft1Label:GetText() and PlayerStatFrameLeft1Label:GetText() ~= "" then
						local tFrameName = v
						local tFriendlyName = SkuUtil:Unescape(PlayerStatFrameLeft1Label:GetText().." "..PlayerStatFrameLeft1StatText:GetText())
						--local tName, tFullText = GetButtonTooltipLines(PlayerStatFrameLeft1, GameTooltip)

						-- Option 2 (live values): precompile this stat's PaperDoll
						-- setter once, then re-run it on demand to read the current
						-- value when the user lands on the entry. Same Blizzard
						-- setter the build used, re-read off the shared stat frame.
						local tStatFn = loadstring(v1)
						local tLiveName = function()
							if not tStatFn then return nil end
							tStatFn()
							if PlayerStatFrameLeft1Label:GetText() and PlayerStatFrameLeft1Label:GetText() ~= "" then
								return SkuUtil:Unescape(PlayerStatFrameLeft1Label:GetText().." "..PlayerStatFrameLeft1StatText:GetText())
							end
							return nil
						end

						table.insert(tParentStatsValues, tFriendlyName)
						tParentStatsValues[tFriendlyName] = {
							frameName = tFrameName,
							RoC = "Child",
							type = "Button",
							obj = _G[tFrameName],
							textFirstLine = tFriendlyName,
							textFull = "",--tFullText,
							childs = {},
							liveName = tLiveName,
							--click = true,
						}
					end
				end
			end

		end

		local tFrameName = v
		local tFriendlyName = L["Resistances"]
		table.insert(tParentStats, tFriendlyName)
		tParentStats[tFriendlyName] = {
			frameName = tFrameName,
			RoC = "Child",
			type = "Button",
			obj = _G[tFrameName],
			textFirstLine = L["Resistances"],
			textFull = "",
			childs = {},
			--click = true,
		}
		local tParentStatsValues = tParentStats[tFriendlyName].childs

		for x = 1, NUM_RESISTANCE_TYPES do
			local text = getglobal("MagicResText"..x);
			local frame = getglobal("MagicResFrame"..x);
			frame.type = "stat"
			local tName, tFullText = GetButtonTooltipLines(frame)

			local tFrameName = ""
			local tFriendlyName = SkuUtil:Unescape(tName)
			table.insert(tParentStatsValues, tFriendlyName)
			tParentStatsValues[tFriendlyName] = {
				frameName = tFrameName,
				RoC = "Child",
				type = "Button",
				obj = _G[tFrameName],
				textFirstLine = tFriendlyName,
				textFull = SkuUtil:Unescape(tFullText),
				childs = {},
				--click = true,
			}
		end
	end

	if Sku.IsEraSoD == true then
		SkuCore:BuildEngravingFrame(aParentChilds)
	end

--[[
	--Currency
	local tFrameName = ""
	local tFriendlyName = L["Currency"]
	table.insert(aParentChilds, tFriendlyName)
	aParentChilds[tFriendlyName] = {
		frameName = tFrameName,
		RoC = "Child",
		type = "Button",
		obj = _G[tFrameName],
		textFirstLine = tFriendlyName,
		textFull = "",
		childs = {},
		--click = true,
	}   
	local tParentCurrency = aParentChilds[tFriendlyName].childs

		for i = 1, 10 do
			local name, isHeader, isExpanded, isUnused, isWatched, count, icon, maxQuantity, maxEarnable, quantityEarned, isTradeable, itemID = GetCurrencyListInfo(i)
			--print(name, isHeader, isExpanded, isUnused, isWatched, count, icon, maxQuantity, maxEarnable, quantityEarned, isTradeable, itemID)
			if name and isHeader ~= true then
				--print(, itemID)
				local tFrameName = ""
				local tFriendlyName = SkuUtil:Unescape(name.." "..count)
				table.insert(tParentCurrency, tFriendlyName)
				tParentCurrency[tFriendlyName] = {
					frameName = tFrameName,
					RoC = "Child",
					type = "Button",
					obj = _G[tFrameName],
					textFirstLine = tFriendlyName,
					textFull = "",
					childs = {},
					--click = true,
				}
			end
		end
]]

	-- ====================================================================
	-- Berufe (Professions)
	-- Auf gleicher Ebene wie Equipment / Stats. Listet jeden gelernten
	-- Beruf und bietet pro Beruf zwei Aktionen:
	--   * Öffnen   — macrotext /cast <Beruf>, öffnet die Beruf-UI
	--   * Verlernen — Bestätigungs-Popup (analog zum AH-Kauf-Popup)
	--                 → AbandonSkill(<Beruf>)
	-- ====================================================================
	do
		local tFrameName = ""
		local tFriendlyName = L["Berufe"] or "Berufe"
		table.insert(aParentChilds, tFriendlyName)
		aParentChilds[tFriendlyName] = {
			frameName = tFrameName,
			RoC = "Child",
			type = "Button",
			obj = _G[tFrameName],
			textFirstLine = tFriendlyName,
			textFull = L["Erlernte Berufe öffnen oder verlernen."],
			childs = {},
		}
		local tProfParent = aParentChilds[tFriendlyName].childs

		-- Sammel-Berufe (gathering): haben keine Crafting-UI, also kein
		-- "Öffnen"-Button. Nur "Verlernen" anbieten.
		local tGatheringProfessions = {
			["Kürschnerei"] = true, ["Skinning"] = true,
			["Bergbau"] = true,     ["Mining"] = true,
			["Kräuterkunde"] = true,["Herbalism"] = true,
		}

		-- Sekundär-Berufe (Erste Hilfe / Kochkunst / Angeln). Diese
		-- haben in der TBC-API isAbandonable = false und würden vom
		-- normalen Filter herausfallen. Wir nehmen sie über diese
		-- Namens-Whitelist (DE+EN) trotzdem in die Übersicht auf, damit
		-- der User auch sie über "Öffnen" / Cast aufmachen kann.
		-- Sie sind in TBC nicht verlernbar (AbandonSkill liefert keinen
		-- Effekt), deshalb wird unten KEIN Verlernen-Eintrag angeboten.
		local tSecondaryProfessions = {
			["Erste Hilfe"] = true, ["First Aid"] = true,
			["Kochkunst"]   = true, ["Cooking"]   = true,
			["Angeln"]      = true, ["Fishing"]   = true,
		}

		-- Berufe via SkillFrame-API einsammeln. GetProfessions ist auf
		-- TBC-Anniversary nicht zuverlässig; GetNumSkillLines/GetSkillLineInfo
		-- funktioniert auf allen Versionen.
		-- Wichtig: vorher ExpandSkillHeader(0) ausführen, sonst sind unter
		-- eingeklappten Kategorien stehende Skills nicht enthalten.
		if _G.ExpandSkillHeader then
			pcall(_G.ExpandSkillHeader, 0)
		end
		local tProfs = {}
		if _G.GetNumSkillLines and _G.GetSkillLineInfo then
			local n = GetNumSkillLines() or 0
			for i = 1, n do
				local skillName, isHeader, _, skillRank, _, _, skillMaxRank,
					isAbandonable = GetSkillLineInfo(i)
				if not isHeader then
					local isSecondary = skillName and tSecondaryProfessions[skillName] == true
					if isAbandonable or isSecondary then
						tProfs[#tProfs + 1] = {
							name        = skillName,
							rank        = skillRank,
							max         = skillMaxRank,
							isSecondary = isSecondary,
						}
					end
				end
			end
		end

		if #tProfs == 0 then
			-- Hinweistext, falls (noch) keine Berufe erlernt sind.
			local tName = L["Keine Berufe erlernt"] or "Keine Berufe erlernt"
			table.insert(tProfParent, tName)
			tProfParent[tName] = {
				frameName = "",
				RoC = "Child",
				type = "FontString",
				obj = nil,
				textFirstLine = tName,
				textFull = "",
				childs = {},
			}
		else
			for _, p in ipairs(tProfs) do
				local pName  = p.name
				local pSkill = p.rank
				local pMax   = p.max
				local pIsGathering = tGatheringProfessions[pName] == true
				local pIsSecondary = p.isSecondary == true

				-- Label: "Schneiderei 300 / 375"
				local label = pName
				if pSkill and pMax then
					label = pName .. " " .. tostring(pSkill) .. " / " .. tostring(pMax)
				end
				table.insert(tProfParent, label)
				tProfParent[label] = {
					frameName = "",
					RoC = "Child",
					type = "Button",
					obj = nil,
					textFirstLine = label,
					textFull = "",
					childs = {},
				}
				local tProfChilds = tProfParent[label].childs

				-- Öffnen-Eintrag — nur für Crafting-Berufe (nicht für
				-- Sammelberufe, die kein eigenes Fenster haben).
				if not pIsGathering then
					local tOpen = L["Öffnen"] or "Öffnen"
					table.insert(tProfChilds, tOpen)
					tProfChilds[tOpen] = {
						frameName = "",
						RoC = "Child",
						type = "Button",
						obj = nil,
						textFirstLine = tOpen,
						textFull = L["Öffnet das Beruf-Fenster für "] .. pName .. ".",
						childs = {},
						directAction = true,
						macrotext = "/cast " .. pName,
					}
				end

				-- Verlernen-Eintrag — nicht für Sekundär-Berufe (Erste Hilfe /
				-- Kochkunst / Angeln). Diese sind in TBC nicht verlernbar
				-- (AbandonSkill ist hier wirkungslos), deshalb blenden wir
				-- den Eintrag dort komplett aus, statt einen funktionslosen
				-- Button anzubieten.
				if not pIsSecondary then
					-- Nutzt SkuCore:ConfirmButtonShow mit Sound + TTS-Vorlesen
					-- exakt wie das Auktionshaus-Kauf-Popup. Die Editbox des
					-- Popups erhält Fokus → Enter = Ja, Escape = Nein.
					local tUnlearn = L["Verlernen"] or "Verlernen"
					local lProfName = pName -- Closure-Variable
					table.insert(tProfChilds, tUnlearn)
					tProfChilds[tUnlearn] = {
						frameName = "",
						RoC = "Child",
						type = "Button",
						obj = nil,
						textFirstLine = tUnlearn,
						textFull = L["Verlernt "] .. pName
							.. L[". Eine Bestätigungs-Abfrage erscheint."],
						childs = {},
						directAction = true,
						func = function()
							if not SkuCore.ConfirmButtonShow then return end
							local tPrompt = lProfName
								.. L[" wirklich verlernen? Eingabe Ja, Escape Nein."]

							-- Fix: Popup ZEITVERSETZT öffnen (analog AH-
							-- Kauf-Popup, das in einem 1s-Timer aufgemacht
							-- wird). Der directAction-Wrapper macht nach
							-- diesem func-Aufruf synchron currentMenuPosition
							-- = parent + CheckFrames() und ~0.35s später ein
							-- OnUpdate auf den Eltern-Knoten. Wenn wir das
							-- Popup synchron öffnen, entzieht diese Folge der
							-- Editbox den Fokus — Enter erreicht den OK-
							-- Callback dann nicht mehr und AbandonSkill läuft
							-- nie. Mit 0,5s Delay ist der Refresh durch, das
							-- Popup behält den Fokus, und Enter / Escape
							-- gehen wie erwartet an OkScript / EscScript.
							local fnShow = function()
								SkuCore:ConfirmButtonShow(
									tPrompt,
									-- OK-Callback (Enter / Klick auf "OK")
									function(self)
										if _G.PlaySound then PlaySound(89) end
										-- Fix: AbandonSkill auf TBC-Classic
										-- 2.5.x erwartet den Skill-Line-Index
										-- (Zahl), nicht den lokalisierten
										-- Namen. Der bisherige Aufruf
										-- AbandonSkill(name) wurde vom Client
										-- lautlos verworfen — die Sapi
										-- meldete "verlernt", real passierte
										-- nichts. Wir resolven den Index zur
										-- Laufzeit aus der aktuellen Skill-
										-- Liste (Reihenfolge kann sich
										-- zwischen Menü-Aufbau und Bestätigung
										-- verschieben).
										if _G.AbandonSkill and _G.GetNumSkillLines
											and _G.GetSkillLineInfo then
											if _G.ExpandSkillHeader then
												pcall(_G.ExpandSkillHeader, 0)
											end
											local tIdx
											local n = _G.GetNumSkillLines() or 0
											for i = 1, n do
												local sName, sHeader = _G.GetSkillLineInfo(i)
												if not sHeader and sName == lProfName then
													tIdx = i
													break
												end
											end
											if tIdx then
												pcall(_G.AbandonSkill, tIdx)
											else
												-- Fallback: alter Namens-Aufruf,
												-- falls die Index-Auflösung
												-- (z. B. wegen API-Änderung)
												-- fehlschlägt.
												pcall(_G.AbandonSkill, lProfName)
											end
										end
										if SkuOptions and SkuOptions.Voice
											and SkuOptions.Voice.OutputStringBTtts then
											pcall(function()
												SkuOptions.Voice:OutputStringBTtts(
													lProfName .. L[" verlernt"],
													false, true, 0.1, nil, nil, nil, 1)
											end)
										end

										-- Menü nach dem Verlernen neu aufbauen,
										-- sonst steht der gerade verlernte
										-- Beruf weiter im Charakter-Untermenü.
										-- Der Cursor steht im Moment des
										-- Bestätigens noch auf "Verlernen" →
										-- nach dem Rebuild existiert dieser
										-- Knoten samt Eltern-Eintrag (z. B.
										-- "Schneiderei 300 / 375") nicht mehr.
										-- Wir setzen die Position deshalb
										-- vorab zwei Ebenen höher auf den
										-- "Berufe"-Knoten, damit der User
										-- nach dem Refresh auf einer noch
										-- existierenden Position landet.
										-- Kurzer Delay, damit der Server das
										-- Verlernen verarbeiten konnte —
										-- danach liefert GetSkillLineInfo den
										-- neuen Stand und CheckFrames baut
										-- die Übersicht ohne den Beruf neu.
										if _G.C_Timer and _G.C_Timer.After then
											_G.C_Timer.After(0.4, function()
												pcall(function()
													local cmp = SkuOptions and SkuOptions.currentMenuPosition
													-- "Verlernen" → "Beruf-Eintrag" → "Berufe"
													if cmp and cmp.parent and cmp.parent.parent then
														SkuOptions.currentMenuPosition = cmp.parent.parent
													elseif cmp and cmp.parent then
														SkuOptions.currentMenuPosition = cmp.parent
													end
													SkuCore:CheckFrames()
													if SkuOptions and SkuOptions.currentMenuPosition
														and SkuOptions.currentMenuPosition.OnUpdate then
														pcall(function() SkuOptions.currentMenuPosition:OnUpdate() end)
													end
												end)
											end)
										end
									end,
									-- Escape-Callback
									function()
										if SkuOptions and SkuOptions.Voice
											and SkuOptions.Voice.OutputStringBTtts then
											pcall(function()
												SkuOptions.Voice:OutputStringBTtts(
													L["Abgebrochen, "] .. lProfName
													.. L[" nicht verlernt"],
													true, true, 0.1, nil, nil, nil, 1)
											end)
										end
									end
								)

								-- Prompt nach dem (verzögerten) Show
								-- vorlesen, damit der User die Frage hört
								-- und weiß, dass das Popup jetzt offen ist.
								if SkuOptions and SkuOptions.Voice
									and SkuOptions.Voice.OutputStringBTtts then
									pcall(function()
										SkuOptions.Voice:OutputStringBTtts(
											tPrompt, true, true, 0.1, nil, nil, nil, 1)
									end)
								end
							end

							if _G.PlaySound then PlaySound(88) end
							if _G.C_Timer and _G.C_Timer.After then
								_G.C_Timer.After(0.5, fnShow)
							else
								-- Fallback ohne Timer: synchron öffnen.
								fnShow()
							end
						end,
					}
				end
			end
		end
	end

	-- ====================================================================
	-- Ausrüstungssets — direkt unter "Berufe"
	-- ====================================================================
	if SkuCore.EquipmentSets and SkuCore.EquipmentSets.BuildChilds then
		local tEqName = L["Equipment sets"]
		table.insert(aParentChilds, tEqName)
		aParentChilds[tEqName] = {
			frameName = "",
			RoC = "Child",
			type = "Button",
			obj = nil,
			textFirstLine = tEqName,
			textFull = L["EQ_MenuTip"],
			childs = {},
		}
		SkuCore.EquipmentSets:BuildChilds(aParentChilds[tEqName].childs)
	end

	-- ====================================================================
	-- In-combat CHARACTER mirror -- FULL tree (Text / Equipment / Stats /
	-- Professions / Sets), captured the same way the bag mirror captures its
	-- tree (combatBagTree), just N-level instead of the fixed views/items/submenu.
	-- Nothing on the character screen can change position in combat (gear/stats
	-- are frozen), so this static snapshot stays valid the whole fight.
	--
	-- Model: a flat node array. Node i = { parent, kids, use, and the precomputed
	-- neighbours down/up/right/left/first/last }. The secure snippet just FOLLOWS
	-- these pointers (no loops) -- Down/Up cycle siblings, Right descends to the
	-- first child, Left ascends (or leaves the mirror at the top level). Equipment
	-- slot nodes carry "/use <slotID>" directly -- the USE key on the slot node
	-- fires the on-use item in combat. (The former synthetic Links/Rechtsklick
	-- child pair was removed together with the out-of-combat click submenu, so the
	-- combat shape matches: no extra level anywhere.) Everything else is read-only
	-- (empty macro); reading itself is handled by the normal insecure menu nav, so
	-- the mirror only needs the structure + the slot /use points.
	do
		local tNodes = {}
		local function tAdd(aParent)
			local i = #tNodes + 1
			tNodes[i] = { parent = aParent or 0, kids = {}, use = "" }
			if aParent and aParent > 0 then table.insert(tNodes[aParent].kids, i) end
			return i
		end
		local function tWalk(aChilds, aParentIdx)
			if type(aChilds) ~= "table" then return end
			for _, tKey in ipairs(aChilds) do
				local tNode = aChilds[tKey]
				if type(tNode) == "table" then
					local i = tAdd(aParentIdx)
					local tIsSlot = tNode.obj and tNode.obj.GetID and type(tKey) == "string"
						and string.match(tKey, "^Character.+Slot$")
					local tSid = tIsSlot and tNode.obj:GetID() or nil
					if tSid and tSid > 0 then
						-- equipment slot: arm "/use <slotID>" on the slot node itself
						-- (no synthetic Links/Rechtsklick children anymore -- USE fires
						-- directly on the slot, matching the reworked insecure menu).
						tNodes[i].use = "/use " .. tSid
					elseif type(tNode.childs) == "table" and #tNode.childs > 0 then
						tWalk(tNode.childs, i)
					end
				end
			end
		end
		tWalk(aParentChilds, 0)   -- parent 0 = the virtual root (the Character window itself)

		-- Precompute the four navigation neighbours + first/last sibling per node.
		local tRootKids = {}
		for i, n in ipairs(tNodes) do if n.parent == 0 then tRootKids[#tRootKids + 1] = i end end
		for i, n in ipairs(tNodes) do
			local tSibs = (n.parent == 0) and tRootKids or tNodes[n.parent].kids
			local tCnt = #tSibs
			local tIdx = 1
			for j, v in ipairs(tSibs) do if v == i then tIdx = j break end end
			n.down  = tSibs[tIdx % tCnt + 1]
			n.up    = tSibs[(tIdx - 2) % tCnt + 1]
			n.first = tSibs[1]
			n.last  = tSibs[tCnt]
			n.right = (#n.kids > 0) and n.kids[1] or 0   -- 0 = leaf (Right stays put)
			n.left  = n.parent                           -- 0 = top level (Left leaves the mirror)
		end

		SkuCore.combatCharTree = tNodes
		SkuCore.combatCharStart = tRootKids[1] or 0      -- first top-level node (the level text)
		if SkuLogCombat then
			local tUseCount = 0
			for _, n in ipairs(tNodes) do if n.use ~= "" then tUseCount = tUseCount + 1 end end
			SkuLogCombat("charTree", "nodes=" .. #tNodes .. " top=" .. #tRootKids
				.. " useNodes=" .. tUseCount .. " start=" .. (SkuCore.combatCharStart or 0))
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local tTradeSkillTypeColor = {
	--[L["optimal"]] = { r = 1, g = 0.50, b = 0.25},
	--[L["medium"]] = { r = 1, g = 1, b = 0},
	[L["New"]] = { r = 0, g = 1, b = 0},
	[L["bekannt"]] = { r = 0.50, g = 0.50, b = 0.50},
	["header"] = { r = 1, g = 0.82, b = 0},
	["subheader"] = { r = 1, g = 0.82, b = 0},
	[L["nodifficulty"]] = { r = 0.96, g = 0.96, b = 0.96},
	[L["selected"]] = { r = 1, g = 1, b = 1},
}
function SkuCore:Build_ClassTrainerFrame(aParentChilds)

	local tFrameName = "ClassTrainerFrame"
	local tFriendlyName = _G["ClassTrainerNameText"]:GetText()
	if _G["ClassTrainerGreetingText"] and _G["ClassTrainerGreetingText"].GetText and _G["ClassTrainerGreetingText"]:GetText() then
		tFriendlyName = _G["ClassTrainerGreetingText"]:GetText()
	end
	table.insert(aParentChilds, tFriendlyName)
	aParentChilds[tFriendlyName] = {
		frameName = tFrameName,
		RoC = "Child",
		type = "FontString",
		obj = _G[tFrameName],
		textFirstLine = tFriendlyName,
		textFull = "",
		childs = {},
	}

	local tFrameName = "ClassTrainerListScrollFrameScrollBarScrollUpButton"
	if _G[tFrameName] then
		if _G[tFrameName]:IsVisible() == true and _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
			local tFriendlyName = L["Hoch blättern"]
			table.insert(aParentChilds, tFriendlyName)
			aParentChilds[tFriendlyName] = {
				frameName = tFrameName,
				RoC = "Child",
				type = "Button",
				obj = _G[tFrameName],
				textFirstLine = tFriendlyName,
				textFull = "",
				childs = {},
				func = function(self, aButton)
					self:GetScript("OnClick")(self, aButton)             
					self:GetScript("OnClick")(self, aButton)             
				end,            
				click = true,
			}   
		end
	end

	local tHasOfSkills
	for x = 1, 10 do
		local tFrameName = "ClassTrainerSkill"..x
		if _G[tFrameName] and _G[tFrameName].text and _G[tFrameName]:IsVisible() == true and _G[tFrameName]:IsEnabled() == true then
			if _G[tFrameName].text:GetText() then
				local tDifficulty = ""
				local r, g, b, a = _G[tFrameName].text:GetTextColor()
				r, g, b, a = round(r), round(g), round(b), round(a)
				if r == 1 and g == 1 and  b == 1 then
					if _G["ClassTrainerHighlightFrame"] and _G["ClassTrainerHighlightFrame"]:GetRegions() then
						r, g, b, a = _G["ClassTrainerHighlightFrame"]:GetRegions():GetVertexColor()
						if r then
							r, g, b, a = round(r), round(g), round(b), round(a)
						end
					end
				end
				for i, v in pairs(tTradeSkillTypeColor) do
					if v.r == r and v.g == g and  v.b == b then
						tDifficulty = i
					end
				end

				local tFriendlyName = SkuUtil:Unescape(_G[tFrameName].text:GetText())
				local tText, tFullText = "", ""
				if _G[tFrameName]:IsEnabled() == true then
					table.insert(aParentChilds, tFriendlyName)
					aParentChilds[tFriendlyName] = {
						frameName = tFrameName,
						RoC = "Child",
						type = "Button",
						obj = _G[tFrameName],
						textFirstLine = tFriendlyName,
						textFull = "",
						childs = {},
						func = _G[tFrameName]:GetScript("OnClick"),
						click = true,
					}   
				end

				if tDifficulty == "subheader" or tDifficulty == "header" then
					aParentChilds[tFriendlyName].click = false
					aParentChilds[tFriendlyName].textFirstLine = aParentChilds[tFriendlyName].textFirstLine.." ("..L["category"]..")"
				else
					aParentChilds[tFriendlyName].textFirstLine = aParentChilds[tFriendlyName].textFirstLine.." ("..(tDifficulty or "")..")"
				end

				tHasOfSkills = true
			end
		end
	end

	local tFrameName = "ClassTrainerListScrollFrameScrollBarScrollDownButton"
	if _G[tFrameName] then
		if _G[tFrameName]:IsVisible() == true and _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
			local tFriendlyName = L["Runter blättern"]
			table.insert(aParentChilds, tFriendlyName)
			aParentChilds[tFriendlyName] = {
				frameName = tFrameName,
				RoC = "Child",
				type = "Button",
				obj = _G[tFrameName],
				textFirstLine = tFriendlyName,
				textFull = "",
				childs = {},
				func = function(self, aButton)
					self:GetScript("OnClick")(self, aButton)             
					self:GetScript("OnClick")(self, aButton)             
				end,            
				click = true,
			}   
		end
	end



	local tName = ""
	if _G["ClassTrainerSkillName"] and _G["ClassTrainerSkillName"]:IsVisible() == true then
		tName = SkuUtil:Unescape(_G["ClassTrainerSkillName"]:GetText()) or ""
	end
	local tRequirements = ""
	if _G["ClassTrainerSkillRequirements"] and _G["ClassTrainerSkillRequirements"]:IsVisible() and _G["ClassTrainerSkillRequirements"]:GetText() then
		for i, v in string.gmatch(_G["ClassTrainerSkillRequirements"]:GetText(), "([^,]+)") do 
			if string.sub(i, 1, 1) == " " then
				i = string.sub(i, 2)
			end
			local tReqStr = SkuUtil:Unescape(i) or ""
			if string.find(i, "ff2020") then
				tReqStr = tReqStr.." ("..L["missing"]..")"
			end
			tRequirements = tRequirements..tReqStr.."\r\n"
		end
	end
	local tCost = ""
	if _G["ClassTrainerDetailMoneyFrame"] and _G["ClassTrainerDetailMoneyFrame"].staticMoney then
		tCost = SkuGetCoinText(_G["ClassTrainerDetailMoneyFrame"].staticMoney, true)
	end

	if tHasOfSkills and _G["ClassTrainerSkillIcon"] then
		_G["ClassTrainerSkillIcon"].type = "sku"
		local tSkillText, tSkillFullText = GetButtonTooltipLines(_G["ClassTrainerSkillIcon"])
		local tFrameName = "ClassTrainerDetailScrollFrame"
		if tName and tName ~= "" then
			local tFriendlyName = L["Ausgewählt: "]..tName
			table.insert(aParentChilds, tFriendlyName)
			aParentChilds[tFriendlyName] = {
				frameName = tFrameName,
				RoC = "Child",
				type = "FontString",
				obj = _G[tFrameName],
				textFirstLine = tFriendlyName.."...",
				textFull = tName..(("\r\n"..tCost) or "")..(("\r\n"..tRequirements) or "").."\r\n"..tSkillFullText,
				childs = {},
			}   
		end
	end

	local tFrameName = "ClassTrainerTrainButton"
	if _G[tFrameName] then
		if _G[tFrameName]:IsVisible() == true and _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
			if _G[tFrameName]:GetText() then
				local tFriendlyName = SkuUtil:Unescape(_G[tFrameName]:GetText())
				table.insert(aParentChilds, tFriendlyName)
				aParentChilds[tFriendlyName] = {
					frameName = tFrameName,
					RoC = "Child",
					type = "Button",
					obj = _G[tFrameName],
					textFirstLine = tFriendlyName,
					textFull = "",
					childs = {},
					func = function()
						_G["ClassTrainerTrainButton"]:Click()
						pcall(function() SkuOptions.Voice:OutputStringBTtts("sound-notification24", false, true) end)
						C_Timer.After(0.5, function()
							pcall(function() SkuCore:CheckFrames() end)
							C_Timer.After(0.35, function()
								pcall(function()
									if SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.children then
										local tTarget = _G["ClassTrainerTrainButton"]
											and _G["ClassTrainerTrainButton"]:IsVisible()
											and _G["ClassTrainerTrainButton"]:IsEnabled()
											and _G["ClassTrainerTrainButton"]:GetText()
										if tTarget then
											tTarget = SkuUtil:Unescape(tTarget)
											for _, child in ipairs(SkuOptions.currentMenuPosition.children) do
												if child.name == tTarget then
													SkuOptions.currentMenuPosition = child
													break
												end
											end
										end
									end
									SkuOptions:VocalizeCurrentMenuName()
								end)
							end)
						end)
					end,
				}
			end
		end
	end


	-- Close button intentionally not listed: Escape already closes the window, so a
	-- redundant Close entry is just noise for a screen-reader user (matches the other
	-- windows -- gossip/quest/bags/... -- which never listed one).
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:Build_TradeFrame(aParentChilds)
	local L = Sku.L

	-- Handelspartner-Name
	local tPartnerName = _G["TradeFrameRecipientNameText"] and _G["TradeFrameRecipientNameText"]:GetText() or L["Trade"]
	table.insert(aParentChilds, tPartnerName)
	aParentChilds[tPartnerName] = {
		frameName = "TradeFrame",
		RoC = "Child",
		type = "FontString",
		obj = _G["TradeFrame"],
		textFirstLine = tPartnerName,
		textFull = "",
		childs = {},
	}

	-- Gegenstände des Partners (Slots 1-6)
	local tPartnerHeader = L["TRADE_PartnerItems"]
	table.insert(aParentChilds, tPartnerHeader)
	aParentChilds[tPartnerHeader] = {
		frameName = "TradeFramePartnerItems",
		RoC = "Child",
		type = "FontString",
		obj = _G["TradeFrame"],
		textFirstLine = tPartnerHeader,
		textFull = "",
		childs = {},
	}
	local tHasPartnerItems = false
	for slot = 1, 6 do
		local tName, tTexture, tNumItems, tQuality = GetTradeTargetItemInfo(slot)
		if tName then
			local tLink = GetTradeTargetItemLink(slot)
			local tDisplay = tName
			if tNumItems and tNumItems > 1 then
				tDisplay = tName .. " x" .. tNumItems
			end
			table.insert(aParentChilds, tDisplay)
			aParentChilds[tDisplay] = {
				frameName = "TradeRecipientItem" .. slot,
				RoC = "Child",
				type = "FontString",
				obj = _G["TradeFrame"],
				textFirstLine = tDisplay,
				textFull = tLink and SkuUtil:Unescape(tLink) or tDisplay,
				childs = {},
			}
			tHasPartnerItems = true
		end
	end
	if not tHasPartnerItems then
		local tEmpty = L["TRADE_EmptySlot"]
		table.insert(aParentChilds, tEmpty)
		aParentChilds[tEmpty] = {
			frameName = "TradePartnerEmpty",
			RoC = "Child",
			type = "FontString",
			obj = _G["TradeFrame"],
			textFirstLine = tEmpty,
			textFull = "",
			childs = {},
		}
	end

	-- Gold des Partners
	local tTargetMoney = GetTargetTradeMoney() or 0
	local tPartnerGoldText = L["TRADE_PartnerGold"] .. ": "
	if tTargetMoney > 0 then
		tPartnerGoldText = tPartnerGoldText .. SkuGetCoinText(tTargetMoney, true)
	else
		tPartnerGoldText = tPartnerGoldText .. L["TRADE_NoGold"]
	end
	table.insert(aParentChilds, tPartnerGoldText)
	aParentChilds[tPartnerGoldText] = {
		frameName = "TradePartnerGold",
		RoC = "Child",
		type = "FontString",
		obj = _G["TradeFrame"],
		textFirstLine = tPartnerGoldText,
		textFull = "",
		childs = {},
	}

	-- Deine Gegenstände (Slots 1-6)
	local tYourHeader = L["TRADE_YourItems"]
	table.insert(aParentChilds, tYourHeader)
	aParentChilds[tYourHeader] = {
		frameName = "TradeFrameYourItems",
		RoC = "Child",
		type = "FontString",
		obj = _G["TradeFrame"],
		textFirstLine = tYourHeader,
		textFull = "",
		childs = {},
	}
	for slot = 1, 6 do
		local tName, tTexture, tNumItems, tQuality = GetTradePlayerItemInfo(slot)
		if tName then
			local tLink = GetTradePlayerItemLink(slot)
			local tDisplay = tName
			if tNumItems and tNumItems > 1 then
				tDisplay = tName .. " x" .. tNumItems
			end
			table.insert(aParentChilds, tDisplay)
			aParentChilds[tDisplay] = {
				frameName = "TradePlayerItem" .. slot,
				RoC = "Child",
				type = "FontString",
				obj = _G["TradeFrame"],
				textFirstLine = tDisplay,
				textFull = tLink and SkuUtil:Unescape(tLink) or tDisplay,
				childs = {},
			}
		end
	end

	-- Dein Gold
	local tPlayerMoney = GetPlayerTradeMoney() or 0
	local tYourGoldText = L["TRADE_YourGold"] .. ": "
	if tPlayerMoney > 0 then
		tYourGoldText = tYourGoldText .. SkuGetCoinText(tPlayerMoney, true)
	else
		tYourGoldText = tYourGoldText .. L["TRADE_NoGold"]
	end
	table.insert(aParentChilds, tYourGoldText)
	aParentChilds[tYourGoldText] = {
		frameName = "TradePlayerGold",
		RoC = "Child",
		type = "FontString",
		obj = _G["TradeFrame"],
		textFirstLine = tYourGoldText,
		textFull = "",
		childs = {},
	}

	-- Verzauberungsplatz (Slot 7) — Partner
	local tPartnerEnchantName = GetTradeTargetItemInfo(7)
	if tPartnerEnchantName then
		local tPartnerEnchantLink = GetTradeTargetItemLink(7)
		local tDisplay = L["TRADE_EnchantSlot"] .. ": " .. tPartnerEnchantName
		table.insert(aParentChilds, tDisplay)
		aParentChilds[tDisplay] = {
			frameName = "TradeRecipientItem7",
			RoC = "Child",
			type = "FontString",
			obj = _G["TradeFrame"],
			textFirstLine = tDisplay,
			textFull = tPartnerEnchantLink and SkuUtil:Unescape(tPartnerEnchantLink) or tDisplay,
			childs = {},
		}
	end

	-- Verzauberungsplatz (Slot 7) — Spieler (klickbar per macrotext)
	local tPlayerEnchantName = GetTradePlayerItemInfo(7)
	local tEnchantDisplay
	if tPlayerEnchantName then
		tEnchantDisplay = L["TRADE_EnchantSlot"] .. ": " .. tPlayerEnchantName
	else
		tEnchantDisplay = L["TRADE_EnchantSlot"] .. ": " .. L["TRADE_EnchantEmpty"]
	end
	table.insert(aParentChilds, tEnchantDisplay)
	aParentChilds[tEnchantDisplay] = {
		frameName = "TradePlayerItem7",
		RoC = "Child",
		type = "Button",
		obj = _G["TradePlayerItem7"] or _G["TradeFrame"],
		textFirstLine = tEnchantDisplay,
		textFull = "",
		childs = {},
		click = true,
		func = function() end,
		containerFrameName = "TradePlayerItem7",
	}

	-- Aktualisieren-Button
	local tRefreshName = L["TRADE_Refresh"]
	table.insert(aParentChilds, tRefreshName)
	aParentChilds[tRefreshName] = {
		frameName = "TradeRefresh",
		RoC = "Child",
		type = "Button",
		obj = _G["TradeFrame"],
		textFirstLine = tRefreshName,
		textFull = "",
		childs = {},
		func = function()
			pcall(function() SkuCore:CheckFrames() end)
			C_Timer.After(0.35, function()
				pcall(function()
					if SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.children then
						for _, child in ipairs(SkuOptions.currentMenuPosition.children) do
							if child.name == L["TRADE_Refresh"] then
								SkuOptions.currentMenuPosition = child
								break
							end
						end
					end
					SkuOptions:VocalizeCurrentMenuName()
				end)
			end)
		end,
	}

	-- Handeln-Button (AcceptTrade)
	if _G["TradeFrameTradeButton"] and _G["TradeFrameTradeButton"]:IsVisible() then
		local tAcceptName = L["TRADE_Accept"]
		table.insert(aParentChilds, tAcceptName)
		aParentChilds[tAcceptName] = {
			frameName = "TradeFrameTradeButton",
			RoC = "Child",
			type = "Button",
			obj = _G["TradeFrameTradeButton"],
			textFirstLine = tAcceptName,
			textFull = "",
			childs = {},
			func = function()
				_G["TradeFrameTradeButton"]:Click()
				pcall(function() SkuOptions.Voice:OutputStringBTtts(L["TRADE_Accepted"], true, true, 0.2, nil, nil, nil, 2) end)
				C_Timer.After(0.5, function()
					pcall(function() SkuCore:CheckFrames() end)
					C_Timer.After(0.35, function()
						pcall(function()
							if SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.children then
								for _, child in ipairs(SkuOptions.currentMenuPosition.children) do
									if child.name == L["TRADE_Accept"] then
										SkuOptions.currentMenuPosition = child
										break
									end
								end
							end
							SkuOptions:VocalizeCurrentMenuName()
						end)
					end)
				end)
			end,
		}
	end

	-- Close button intentionally not listed: Escape already closes the window, so a
	-- redundant Close entry is just noise for a screen-reader user (matches the other
	-- windows -- gossip/quest/bags/... -- which never listed one).
end

---------------------------------------------------------------------------------------------------------------------------------------
local tTradeSkillTypeColor = {
	[L["optimal"]] = { r = 1.00, g = 0.50, b = 0.25},
	[L["medium"]] = { r = 1.00, g = 1.00, b = 0.00},
	[L["easy"]] = { r = 0.25, g = 0.75, b = 0.25},
	[L["trivial"]] = { r = 0.50, g = 0.50, b = 0.50},
	["header"] = { r = 1.00, g = 0.82, b = 0},
	["subheader"] = { r = 1.00, g = 0.82, b = 0},
	[L["nodifficulty"]] = { r = 0.96, g = 0.96, b = 0.96},
}
function SkuCore:Build_TradeSkillFrame(aParentChilds)

	local tFrameName = "TradeSkillFrame"
	local tFriendlyName = _G["TradeSkillFrameTitleText"]:GetText()
	table.insert(aParentChilds, tFriendlyName)
	aParentChilds[tFriendlyName] = {
		frameName = tFrameName,
		RoC = "Child",
		type = "FontString",
		obj = _G[tFrameName],
		textFirstLine = tFriendlyName,
		textFull = "",
		childs = {},
	}

	--[[

	local tFrameName = ""
	--local tSearchText = TradeSkillFrameEditBox:GetText() or ""
	local tFriendlyName = L["Filter"]
	local tLabel = tFriendlyName
	if tSearchText ~= "" and tSearchText ~= L["Search"] then
		tLabel = tLabel.." = "..tSearchText
	end
	table.insert(aParentChilds, tFriendlyName)
	aParentChilds[tFriendlyName] = {
		frameName = tFrameName,
		RoC = "Child",
		type = "Button",
		obj = _G["TradeSkillFrameEditBox"],
		textFirstLine = tLabel,
		textFull = "",
		childs = {},
		func = function()
			C_Timer.After(0.8, function()
				SkuOptions.Voice:OutputStringBTtts(L["Enter search term and complete with enter or press escape to clear the search term"], true, true, 0.8, true, nil, nil, 1, nil, nil, true)
			end)
			if _G["TradeSkillFrameEditBox"] then
				TradeSkillFrameEditBox:SetFocus()
				TradeSkillFrameEditBox:HookScript("OnEscapePressed", function(self)
					C_Timer.After(0.1, function()
						PlaySound(89) 
						TradeSkillFrameEditBox:SetText("")
						SkuOptions.currentMenuPosition:OnUpdate()
					end)

				end)
				TradeSkillFrameEditBox:HookScript("OnEnterPressed", function(self)
					C_Timer.After(0.1, function()
						PlaySound(89) 
						SkuOptions.currentMenuPosition:OnUpdate()
					end)

				end)
				
			end
		end,            
		click = true,
	}
	]]

	--[[
	local tFrameName = "TradeSkillFrameAvailableFilterCheckButton"
	if _G[tFrameName] then
		if _G[tFrameName]:IsVisible() == true and _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
			local tChecked = L["not checked"]
			if _G[tFrameName]:GetChecked() == true then
				tChecked = L["checked"]
			end
			local tFriendlyName = L["Have materials"]
			table.insert(aParentChilds, tFriendlyName)
			aParentChilds[tFriendlyName] = {
				frameName = tFrameName,
				RoC = "Child",
				type = "Button",
				obj = _G[tFrameName],
				textFirstLine = tFriendlyName.." ("..tChecked..")",
				textFull = "",
				childs = {},
				func = function(self, aButton)
					if self:GetChecked() == true then
						self:SetChecked(false)
					else
						self:SetChecked(true)
					end

					self:GetScript("OnClick")(self, aButton)             
				end,            
				click = true,
			}   
		end
	end
	]]

	local tFrameName = "TradeSkillListScrollFrameScrollBarScrollUpButton"
	if _G[tFrameName] then
		if _G[tFrameName]:IsVisible() == true and _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
			local tFriendlyName = L["Hoch blättern"]
			table.insert(aParentChilds, tFriendlyName)
			aParentChilds[tFriendlyName] = {
				frameName = tFrameName,
				RoC = "Child",
				type = "Button",
				obj = _G[tFrameName],
				textFirstLine = tFriendlyName,
				textFull = "",
				childs = {},
				func = function(self, aButton)
					self:GetScript("OnClick")(self, aButton)             
					self:GetScript("OnClick")(self, aButton)             
				end,            
				click = true,
			}   
		end
	end




	for x = 1, 8 do
		local tFrameName = "TradeSkillSkill"..x
		if _G[tFrameName] and _G[tFrameName].text and _G[tFrameName]:IsVisible() == true and _G[tFrameName]:IsEnabled() == true then
			if _G[tFrameName].text:GetText() then
				local tDifficulty = ""
				local r, g, b, a = _G[tFrameName].text:GetTextColor()
				r, g, b, a = round(r), round(g), round(b), round(a)
				if r == 1 and g == 1 and  b == 1 then
					if _G["TradeSkillHighlightFrame"] and _G["TradeSkillHighlightFrame"]:GetRegions() then
						r, g, b, a = _G["TradeSkillHighlightFrame"]:GetRegions():GetVertexColor()
						if r then
							r, g, b, a = round(r), round(g), round(b), round(a)
						end
					end
				end

				for i, v in pairs(tTradeSkillTypeColor) do
					if v.r == r and v.g == g and  v.b == b then
						tDifficulty = i
					end
				end

				--local tCountText = _G[tFrameName.."Count"]:GetText()
				local tFriendlyName = SkuUtil:Unescape(_G[tFrameName].text:GetText())
				--[[
				if tCountText then
					tFriendlyName = tFriendlyName.." "..tCountText
				end
				]]

				if tDifficulty == "subheader" or tDifficulty == "header" then
					tFriendlyName = tFriendlyName.." ("..L["category"]..")"
				end

				local tText, tFullText = "", ""
				if _G[tFrameName]:IsEnabled() == true then
					table.insert(aParentChilds, tFriendlyName)
					aParentChilds[tFriendlyName] = {
						frameName = tFrameName,
						RoC = "Child",
						type = "Button",
						obj = _G[tFrameName],
						textFirstLine = tFriendlyName,
						textFull = "",
						childs = {},
						func = _G[tFrameName]:GetScript("OnClick"),
						click = true,
					}   
				end

				if tDifficulty ~= "subheader" and tDifficulty ~= "header" then
					aParentChilds[tFriendlyName].textFirstLine = aParentChilds[tFriendlyName].textFirstLine.." ("..(tDifficulty or "")..")"
				end
			end
		end
	end

	local tFrameName = "TradeSkillListScrollFrameScrollBarScrollDownButton"
	if _G[tFrameName] then
		if _G[tFrameName]:IsVisible() == true and _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
			local tFriendlyName = L["Runter blättern"]
			table.insert(aParentChilds, tFriendlyName)
			aParentChilds[tFriendlyName] = {
				frameName = tFrameName,
				RoC = "Child",
				type = "Button",
				obj = _G[tFrameName],
				textFirstLine = tFriendlyName,
				textFull = "",
				childs = {},
				func = function(self, aButton)
					self:GetScript("OnClick")(self, aButton)             
					self:GetScript("OnClick")(self, aButton)             
				end,            
				click = true,
			}   
		end
	end

	local tName = ""
	if _G["TradeSkillSkillName"] then
		tName = SkuUtil:Unescape(_G["TradeSkillSkillName"]:GetText()) or ""
	end
	local tRequirements = ""
	if _G["TradeSkillRequirementText"] and _G["TradeSkillRequirementText"]:IsVisible() and _G["TradeSkillRequirementText"]:GetText() then
		for i, v in string.gmatch(_G["TradeSkillRequirementText"]:GetText(), "([^,]+)") do 
			if string.sub(i, 1, 1) == " " then
				i = string.sub(i, 2)
			end
			local tReqStr = SkuUtil:Unescape(i) or ""
			if string.find(i, "ff2020") then
				tReqStr = tReqStr.." ("..L["missing"]..")"
			end
			tRequirements = tRequirements..tReqStr.."\r\n"
		end
	end
	--[[
	local tCost = ""
	if _G["CraftCost"] and _G["CraftCost"]:GetText() then
		tCost = SkuUtil:Unescape(_G["CraftCost"]:GetText()) or ""
	end
]]	
	local tDescription = ""
	if _G["TradeSkillDescription"] and _G["TradeSkillDescription"]:GetText() then
		tDescription = SkuUtil:Unescape(_G["TradeSkillDescription"]:GetText()) or ""
	end
	

	local tReagents = ""
	if _G["TradeSkillReagentLabel"] and _G["TradeSkillReagentLabel"]:IsVisible() == true then
		tReagents = _G["TradeSkillReagentLabel"]:GetText()
	end
	for x = 1, 15 do
		if _G["TradeSkillReagent"..x] then
			if _G["TradeSkillReagent"..x]:IsVisible() == true then
				tReagents = tReagents.."\r\n"..SkuUtil:Unescape(_G["TradeSkillReagent"..x.."Name"]:GetText())
				tReagents = tReagents.." "..SkuUtil:Unescape(_G["TradeSkillReagent"..x.."Count"]:GetText())
			end
		end   
	end

	_G["TradeSkillSkillIcon"].type = "sku"
	local tSkillText, tSkillFullText = GetButtonTooltipLines(_G["TradeSkillSkillIcon"])

	local tFrameName = "TradeSkillDetailScrollChildFrame"
	if tName and tName ~= "" then
		local tFriendlyName = L["Ausgewählt: "]..tName
		table.insert(aParentChilds, tFriendlyName)
		aParentChilds[tFriendlyName] = {
			frameName = tFrameName,
			RoC = "Child",
			type = "FontString",
			obj = _G[tFrameName],
			textFirstLine = tFriendlyName.."...",
			textFull = tName..(("\r\n"..tRequirements) or "")..(("\r\n"..tReagents) or "")..(("\r\n"..L["gegenstand"]..":\r\n"..tSkillFullText) or "")..(("\r\n"..L["description"]..": "..tDescription) or ""),
			childs = {},
		}   
	end
	
	local tFrameName = "TradeSkillCreateButton"
	if _G[tFrameName] then
		if _G[tFrameName]:IsVisible() == true and _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
			if _G[tFrameName]:GetText() then
				local tFriendlyName = SkuUtil:Unescape(_G[tFrameName]:GetText())
				table.insert(aParentChilds, tFriendlyName)
				aParentChilds[tFriendlyName] = {
					frameName = tFrameName,
					RoC = "Child",
					type = "Button",
					obj = _G[tFrameName],
					textFirstLine = tFriendlyName,
					textFull = "",
					childs = {},
					func = _G[tFrameName]:GetScript("OnClick"),
					click = true,
					--containerFrameName = "TradeSkillCreateButton",
					onActionFunc = function(self, aTable, aChildName) end,
				}   
			end
		end
	end
	local tFrameName = "TradeSkillCreateAllButton"
	if _G[tFrameName] then
		if _G[tFrameName]:IsVisible() == true and _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
			if _G[tFrameName]:GetText() then
				local tFriendlyName = SkuUtil:Unescape(_G[tFrameName]:GetText())
				table.insert(aParentChilds, tFriendlyName)
				aParentChilds[tFriendlyName] = {
					frameName = tFrameName,
					RoC = "Child",
					type = "Button",
					obj = _G[tFrameName],
					textFirstLine = tFriendlyName,
					textFull = "",
					childs = {},
					func = _G[tFrameName]:GetScript("OnClick"),
					click = true,
					--containerFrameName = "TradeSkillCreateAllButton",
					onActionFunc = function(self, aTable, aChildName) end,
				}   
			end
		end
	end


	-- Close ("Schließen") button intentionally not listed: Escape already closes
	-- the window, so a redundant Close entry is just noise for a screen-reader user
	-- (matches the other windows -- gossip/quest/bags/... -- which never listed one).
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:Build_CraftFrame(aParentChilds)

	local tFrameName = "CraftFrame"
	local tFriendlyName = _G["CraftFrameTitleText"]:GetText()
	table.insert(aParentChilds, tFriendlyName)
	aParentChilds[tFriendlyName] = {
		frameName = tFrameName,
		RoC = "Child",
		type = "FontString",
		obj = _G[tFrameName],
		textFirstLine = tFriendlyName,
		textFull = "",
		childs = {},
	}

	if _G["CraftFramePointsText"] and _G["CraftFramePointsText"]:IsVisible() == true then
		local tFrameName = "CraftFramePointsText"
		local tFriendlyName = L["Verfügbare punkte: "]
		tFriendlyName = tFriendlyName..(_G["CraftFramePointsText"]:GetText() or "")
		table.insert(aParentChilds, tFriendlyName)
		aParentChilds[tFriendlyName] = {
			frameName = tFrameName,
			RoC = "Child",
			type = "FontString",
			obj = _G[tFrameName],
			textFirstLine = tFriendlyName,
			textFull = "",
			childs = {},
		}  
	end

	local tFrameName = "CraftListScrollFrameScrollBarScrollUpButton"
	if _G[tFrameName] then
		if _G[tFrameName]:IsVisible() == true and _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
			local tFriendlyName = L["Hoch blättern"]
			table.insert(aParentChilds, tFriendlyName)
			aParentChilds[tFriendlyName] = {
				frameName = tFrameName,
				RoC = "Child",
				type = "Button",
				obj = _G[tFrameName],
				textFirstLine = tFriendlyName,
				textFull = "",
				childs = {},
				func = function(self, aButton)
					self:GetScript("OnClick")(self, aButton)             
					self:GetScript("OnClick")(self, aButton)             
				end,            
				click = true,
			}   
		end
	end

	for x = 1, 8 do
		local tFrameName = "Craft"..x
		if _G[tFrameName] then
			if _G[tFrameName.."Text"]:GetText() then
				local tKnown = ""
				local tDifficulty = ""
				local r, g, b, a = _G[tFrameName].text:GetTextColor()
				r, g, b, a = round(r), round(g), round(b), round(a)
				if r == 1 and g == 1 and  b == 1 then
					if _G["CraftHighlightFrame"] and _G["CraftHighlightFrame"]:GetRegions() then
						r, g, b, a = _G["CraftHighlightFrame"]:GetRegions():GetVertexColor()
						if r then
							r, g, b, a = round(r), round(g), round(b), round(a)
						end
					end
				end

				for i, v in pairs(tTradeSkillTypeColor) do
					if v.r == r and v.g == g and  v.b == b then
						tDifficulty = i
					end
				end

				local tFriendlyName = SkuUtil:Unescape(_G[tFrameName.."Text"]:GetText()).." ".. (SkuUtil:Unescape(_G[tFrameName.."SubText"]:GetText()) or "").." ".. (SkuUtil:Unescape(_G[tFrameName.."Cost"]:GetText()) or "").." "..tKnown
				local tText, tFullText = "", ""
				if _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
					table.insert(aParentChilds, tFriendlyName)
					aParentChilds[tFriendlyName] = {
						frameName = tFrameName,
						RoC = "Child",
						type = "Button",
						obj = _G[tFrameName],
						textFirstLine = tFriendlyName,
						textFull = "",
						childs = {},
						func = _G[tFrameName]:GetScript("OnClick"),
						click = true,
					}   
				end

				if tDifficulty == "subheader" or tDifficulty == "header" then
					aParentChilds[tFriendlyName].click = false
					aParentChilds[tFriendlyName].textFirstLine = aParentChilds[tFriendlyName].textFirstLine.." ("..L["category"]..")"
				else
					aParentChilds[tFriendlyName].textFirstLine = aParentChilds[tFriendlyName].textFirstLine.." ("..(tDifficulty or "")..")"
				end            
			end
		end
	end

	local tFrameName = "CraftListScrollFrameScrollBarScrollDownButton"
	if _G[tFrameName] then
		if _G[tFrameName]:IsVisible() == true and _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
			local tFriendlyName = L["Runter blättern"]
			table.insert(aParentChilds, tFriendlyName)
			aParentChilds[tFriendlyName] = {
				frameName = tFrameName,
				RoC = "Child",
				type = "Button",
				obj = _G[tFrameName],
				textFirstLine = tFriendlyName,
				textFull = "",
				childs = {},
				func = function(self, aButton)
					self:GetScript("OnClick")(self, aButton)             
					self:GetScript("OnClick")(self, aButton)             
				end,            
				click = true,
			}   
		end
	end

	local tName = ""
	if _G["CraftName"] then
		tName = SkuUtil:Unescape(_G["CraftName"]:GetText()) or ""
	end
	local tRequirements = ""
	if _G["CraftRequirements"] and _G["CraftRequirements"]:IsVisible() and _G["CraftRequirements"]:GetText() then
		tRequirements = SkuUtil:Unescape(_G["CraftRequirements"]:GetText()) or ""
		if string.find(_G["CraftRequirements"]:GetText(), "ff2020") then
			tRequirements = tRequirements.." ("..L["missing"]..")"
		end
	end
	local tCost = ""
	if _G["CraftCost"] and _G["CraftCost"]:GetText() then
		tCost = SkuUtil:Unescape(_G["CraftCost"]:GetText()) or ""
	end
	local tDescription = ""
	if _G["CraftDescription"] and _G["CraftDescription"]:GetText() then
		tDescription = SkuUtil:Unescape(_G["CraftDescription"]:GetText()) or ""
	end

	local tReagents = ""
	if _G["CraftReagentLabel"] and _G["CraftReagentLabel"]:IsVisible() == true then
		tReagents = _G["CraftReagentLabel"]:GetText()
	end
	for x = 1, 15 do
		if _G["CraftReagent"..x] then
			if _G["CraftReagent"..x]:IsVisible() == true then
				tReagents = tReagents.."\r\n"..SkuUtil:Unescape(_G["CraftReagent"..x.."Name"]:GetText())
				tReagents = tReagents.." "..SkuUtil:Unescape(_G["CraftReagent"..x.."Count"]:GetText())
			end
		end   
	end

	_G["CraftIcon"].type = "sku"
	local tSkillText, tSkillFullText = GetButtonTooltipLines(_G["CraftIcon"])


	local tFrameName = "CraftDetailScrollChildFrame"
	if tName and tName ~= "" then
		local tFriendlyName = L["Ausgewählt: "]..tName
		table.insert(aParentChilds, tFriendlyName)
		aParentChilds[tFriendlyName] = {
			frameName = tFrameName,
			RoC = "Child",
			type = "FontString",
			obj = _G[tFrameName],
			textFirstLine = tFriendlyName.."...",
			textFull = tName..(("\r\n"..tRequirements) or "")..(("\r\n"..tCost) or "")..(("\r\n"..tDescription) or "")..(("\r\n"..tReagents) or "")..(("\r\n"..L["gegenstand"]..":\r\n"..tSkillFullText) or ""),
			childs = {},
		}   
	end

	local tFrameName = "CraftCreateButton"
	if _G[tFrameName] then
		if _G[tFrameName]:IsVisible() == true and _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
			if _G[tFrameName]:GetText() then
				local tFriendlyName = SkuUtil:Unescape(_G[tFrameName]:GetText())
				table.insert(aParentChilds, tFriendlyName)
				aParentChilds[tFriendlyName] = {
					frameName = tFrameName,
					RoC = "Child",
					type = "Button",
					obj = _G[tFrameName],
					textFirstLine = tFriendlyName,
					textFull = "",
					childs = {},
					-- directAction: Enter fires the craft immediately, no
					-- Linksklick/Rechtsklick submenu (a "create" has no left/
					-- right semantics).
					directAction = true,
					-- DoCraft is TAINT-protected (confirmed: "/script DoCraft(...)"
					-- throws ADDON_ACTION_FORBIDDEN). It also silently no-ops when
					-- reached via "/click CraftCreateButton" -> :Click() -> OnClick
					-- (the hardware event is lost through the chat SlashCommand
					-- parser). The only path that both stays untainted AND is a real
					-- hardware event is a direct key->button binding: while this
					-- entry is focused we bind the menu's Enter directly to the real
					-- Blizzard CraftCreateButton (see directClickButton handling in
					-- the generic OnEnter). That runs DoCraft in Blizzard's own
					-- secure OnClick from a genuine keypress, like a mouse click.
					directClickButton = "CraftCreateButton",
				}
			end
		end
	end

	-- Close ("Schließen") button intentionally not listed: Escape already closes
	-- the window, so a redundant Close entry is just noise for a screen-reader user
	-- (matches the other windows -- gossip/quest/bags/... -- which never listed one).
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:Build_PetStableFrame(aParentChilds)

	local tId, tName, tLevel, _, tType = GetStablePetInfo(0)
	local tFrame = _G["PetStableCurrentPet"]
	local tText, tFullText = GetButtonTooltipLines(tFrame)
	if tId then
		tText, tFullText = tName, tName.."\r\n"..tLevel.."\r\n"..tType
	else
		tText, tFullText = L["Empty"], ""
	end

	table.insert(aParentChilds, L["Derzeitiger Begleiter"])
	aParentChilds[L["Derzeitiger Begleiter"]] = {
		frameName = "PetStableCurrentPet",
		RoC = "Child",
		type = "Button",
		obj = tFrame,
		textFirstLine = L["Derzeitiger Begleiter"].." "..tText,
		textFull = L["Derzeitiger Begleiter"].." "..tFullText,
		childs = {},
		func = function(...)
			local tCursorInfo = GetCursorInfo()
			if tCursorInfo then
				tFrame:GetScript("OnReceiveDrag")(...)
			else
				tFrame:GetScript("OnDragStart")(...)
			end
		end,
		click = true,
	}

	for x = 1, 4 do
		local tId, tName, tLevel, _, tType = GetStablePetInfo(x)
		if _G["PetStableStabledPet"..x] and _G["PetStableStabledPet"..x]:IsEnabled() == true then
			local tFrame = _G["PetStableStabledPet"..x]
			local tText, tFullText = GetButtonTooltipLines(tFrame)
			if tId then
				tText, tFullText = tName, tName.."\r\n"..tLevel.."\r\n"..tType
			else
				tText, tFullText = L["Empty"], ""
			end
			table.insert(aParentChilds, L["Stall "..x])
			aParentChilds[L["Stall "..x]] = {
				frameName = "PetStableStabledPet"..x,
				RoC = "Child",
				type = "Button",
				obj = tFrame,
				textFirstLine = L["Stall "..x].." "..tText,
				textFull = L["Stall "..x].." "..tFullText,
				childs = {},
				func = function(...)
					local tCursorInfo = GetCursorInfo()
					if tCursorInfo then
						tFrame:GetScript("OnReceiveDrag")(...)
					else
						tFrame:GetScript("OnDragStart")(...)
					end
				end,
				click = true,
			}
		end
	end

	local tFrame = _G["PetStablePurchaseButton"]
	if tFrame:IsEnabled() == true then --IsMouseClickEnabled()
		if tFrame:IsShown() == true then --IsMouseClickEnabled()
			table.insert(aParentChilds, L["Weiteren Platz kaufen"])
			aParentChilds[L["Weiteren Platz kaufen"]] = {
				frameName = "PetStablePurchaseButton",
				RoC = "Child",
				type = "Button",
				obj = tFrame,
				textFirstLine = L["Weiteren Platz kaufen"],
				textFull = "",
				childs = {},
				func = tFrame:GetScript("OnClick"),
				click = true,
			}
		end
	end

	-- Close ("Schließen") button intentionally not listed: Escape already closes the
	-- window, so a redundant Close entry is just noise for a screen-reader user
	-- (matches the other windows -- gossip/quest/bags/... -- which never listed one).
end

-----------------------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:ItemTextFrame(aParent)
	local tFrameName = "ItemTextTitleText"
	if _G[tFrameName]:IsShown() == true  then
		local tText = _G[tFrameName]:GetText()
		local tFrst, tFll = SkuCore:ItemName_helper(tText)
		local tFriendlyName = tFrst
		table.insert(aParent, tFriendlyName)
		aParent[tFriendlyName] = {
			frameName = tFrameName,
			RoC = "Child",
			type = "FontString",
			obj = _G[tFrameName],
			textFirstLine = tFrst,
			textFull = tFll,
			childs = {},
		}
	end

	local tFrameName = "ItemTextPageText"
	if _G[tFrameName]:IsShown() == true  then
		local tHtmlTable = _G[tFrameName]:GetTextData()

		local tText = ""
		for i, v in pairs(tHtmlTable) do
			if v.text then
				tText = SkuUtil:Unescape(v.text).."\r\n"
			end
		end

		local tFrst, tFll = SkuCore:ItemName_helper(tText)
		local tFriendlyName = tFrst
		table.insert(aParent, tFriendlyName)
		aParent[tFriendlyName] = {
			frameName = tFrameName,
			RoC = "Child",
			type = "FontString",
			obj = _G[tFrameName],
			textFirstLine = tFrst,
			textFull = tFll,
			childs = {},
		}
	end

	local tFrameName = "ItemTextPrevPageButton"
	if _G[tFrameName]:IsShown() == true  then
		local tFriendlyName = L["Previous"]
		local tFrst, tFll = tFriendlyName, ""
		table.insert(aParent, tFriendlyName)
		aParent[tFriendlyName] = {
			frameName = tFrameName,
			RoC = "Child",
			type = "Button",
			obj = _G[tFrameName],
			textFirstLine = tFrst,
			textFull = tFll,
			childs = {},
			func = _G[tFrameName]:GetScript("OnClick"),
			click = true,
		}
	end

	local tFrameName = "ItemTextNextPageButton"
	if _G[tFrameName]:IsShown() == true  then
		local tFriendlyName = L["Next"]
		local tFrst, tFll = tFriendlyName, ""
		table.insert(aParent, tFriendlyName)
		aParent[tFriendlyName] = {
			frameName = tFrameName,
			RoC = "Child",
			type = "Button",
			obj = _G[tFrameName],
			textFirstLine = tFrst,
			textFull = tFll,
			childs = {},
			func = _G[tFrameName]:GetScript("OnClick"),
			click = true,
		}
	end
end

-----------------------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:GossipFrame(aParentChilds)

	if _G["GossipGreetingScrollChildFrame"] then
		local dtc = { _G["GossipGreetingScrollChildFrame"]:GetRegions() }
		for x = 1, #dtc do
			if dtc[x].GetText then
				local tText = dtc[x]:GetText()
				if tText then
					local tFrameName = "GossipText"
					local tFriendlyName = tText
					local tFrst, tFll = ItemName_helper(tText)
					table.insert(aParentChilds, tFriendlyName)
					aParentChilds[tFriendlyName] = {
						frameName = tFrameName,
						RoC = "Child",
						type = "FontString",
						obj = _G[tFrameName],
						textFirstLine = tFrst,
						textFull = tFll,
						childs = {},
					}  
				end
			end
		end


		local tIconStrings = {
			[132048] = L["Accepted Quest"],
			[132049] = L["Available Quest"],
		}

		for x = 1, GossipFrame.buttonIndex - 1 do
			local tFrameName = "GossipTitleButton"..x
			if _G[tFrameName] then
				if _G[tFrameName]:IsShown() == true  then
					if _G[tFrameName]:GetText() then
						local tFriendlyName = SkuUtil:Unescape(_G[tFrameName]:GetText())
						if _G["GossipTitleButton"..x.."GossipIcon"]:IsShown() == true then
							tFriendlyName = (tIconStrings[_G["GossipTitleButton"..x.."GossipIcon"]:GetTextureFileID()] or "").." "..SkuUtil:Unescape(_G[tFrameName]:GetText())
						end
						local tText, tFullText = "", ""
						if _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
							table.insert(aParentChilds, tFriendlyName)
							aParentChilds[tFriendlyName] = {
								frameName = tFrameName,
								RoC = "Child",
								type = "Button",
								obj = _G[tFrameName],
								textFirstLine = tFriendlyName,
								textFull = "",
								childs = {},
								func = _G[tFrameName]:GetScript("OnClick"),
								click = true,
							} 
						end
					end
				end
			end
		end

	else
			
		local dtc

		local tIconStrings = {
			[132048] = L["Accepted Quest"],
			[132049] = L["Available Quest"],
		}


		local gossipText = C_GossipInfo.GetText()
		if gossipText and gossipText ~= "" then
			table.insert(aParentChilds, gossipText)
			aParentChilds[gossipText] = {
				frameName = tFrameName,
				RoC = "Child",
				type = "string",
				--obj = nil,
				textFirstLine = gossipText,
				textFull = gossipText,
				childs = {},
			} 
		end

		local info = C_GossipInfo.GetOptions()
		for i, v in ipairs(info) do
			local tFriendlyName = (tIconStrings[v.icon] or "").." "..v.name
			-- Iteration-Index in lokaler Closure-Variable festhalten.
			-- Wichtig für den TBC/Anniversary-Fallback: dort hat v
			-- typischerweise KEIN gossipOptionID-Feld, und der
			-- klassische Aufruf ist SelectGossipOption(<index>).
			local lOrderIdx = i
			local lGossipOpt = v
			table.insert(aParentChilds, tFriendlyName)
			aParentChilds[tFriendlyName] = {
				frameName = _G["GossipFrame"],
				RoC = "Child",
				type = "Button",
				obj = _G["GossipFrame"],
				textFirstLine = tFriendlyName,
				textFull = "",
				childs = {},
				func = function()
					-- 1) Moderner Pfad mit gossipOptionID (Retail)
					local tID = lGossipOpt and (lGossipOpt.gossipOptionID
						or lGossipOpt.selection)
					if tID and _G.C_GossipInfo
						and _G.C_GossipInfo.SelectOption then
						local ok = pcall(_G.C_GossipInfo.SelectOption, tID)
						if ok then return end
					end
					-- 2) TBC/Anniversary-Fallback: globaler
					-- SelectGossipOption mit 1-basiertem Index.
					-- Das ist der Pfad, der Flugmeister-Optionen
					-- ("Wohin kann ich fliegen") überhaupt erst dazu
					-- bringt, den TaxiFrame zu öffnen.
					if _G.SelectGossipOption then
						pcall(_G.SelectGossipOption, lOrderIdx)
					end
				end,
				click = true,
			} 
		end
		
		local info = C_GossipInfo.GetAvailableQuests()
		for i, v in pairs(info) do
			local tBl = ""
			if SkuDB.questDataTBC[v.questID] ~= nil and SkuDB.questDataTBC[v.questID][SkuDB.questKeys.skuData] ~= nil and SkuDB.questDataTBC[v.questID][SkuDB.questKeys.skuData][1] and SkuDB.questDataTBC[v.questID][SkuDB.questKeys.skuData][1][1] == true then
				tBl = L["Blacklisted"]
			end

			local tFriendlyName = L["Available Quest"].." "..v.title.." "..tBl
			table.insert(aParentChilds, tFriendlyName)
			aParentChilds[tFriendlyName] = {
				frameName = _G["GossipFrame"],
				RoC = "Child",
				type = "Button",
				obj = _G["GossipFrame"],
				textFirstLine = tFriendlyName,
				textFull = "",
				childs = {},
				func = function()
					C_GossipInfo.SelectAvailableQuest(v.questID)
				end,
				click = true,
			} 
		end		

		local info = C_GossipInfo.GetActiveQuests()
		for i, v in pairs(info) do
			local tBl = ""
			if SkuDB.questDataTBC[v.questID] ~= nil and SkuDB.questDataTBC[v.questID][SkuDB.questKeys.skuData] ~= nil and SkuDB.questDataTBC[v.questID][SkuDB.questKeys.skuData][1] and SkuDB.questDataTBC[v.questID][SkuDB.questKeys.skuData][1][1] == true then
				tBl = L["Blacklisted"]
			end

			local tFriendlyName = L["Accepted Quest"].." "..v.title.." "..tBl
			table.insert(aParentChilds, tFriendlyName)
			aParentChilds[tFriendlyName] = {
				frameName = _G["GossipFrame"],
				RoC = "Child",
				type = "Button",
				obj = _G["GossipFrame"],
				textFirstLine = tFriendlyName,
				textFull = "",
				childs = {},
				func = function()
					C_GossipInfo.SelectActiveQuest(v.questID)
				end,
				click = true,
			} 
		end	
	end

end


-----------------------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:QuestFrame(aParentChilds)


	local function QuestInfoRewardsFrameHelper(aParent, aInfoOnly)
		if QuestInfoRewardsFrame.ItemChooseText:IsVisible() == true or QuestInfoRewardsFrame.ItemReceiveText:IsVisible() == true or (QuestInfoMoneyFrame:IsVisible() == true and QuestInfoMoneyFrame:IsVisible() == true and QuestInfoMoneyFrame.staticMoney) then
			local tFrameName = "QuestInfoRewardsFrame"
			local tFriendlyName = L["Rewards"]
			local tFrst, tFll = tFriendlyName, ""
			table.insert(aParent, tFriendlyName)
			aParent[tFriendlyName] = {
				frameName = tFrameName,
				RoC = "Child",
				type = "Button",
				obj = _G[tFrameName],
				textFirstLine = tFrst,
				textFull = tFll,
				childs = {},
			}

			local tTaken = {}
			local tQuestInfoRewardsFrameChilds = aParent[tFriendlyName].childs

			local tc = 1
			if QuestInfoRewardsFrame.spellHeaderPool and QuestInfoRewardsFrame.spellHeaderPool.numActiveObjects then
				if QuestInfoRewardsFrame.spellHeaderPool.numActiveObjects > 0 then
					for i, v in QuestInfoRewardsFrame.spellHeaderPool:EnumerateActive() do
						local tButton = i
						if tButton then
							if tButton:IsVisible() == true then
								if tButton.GetText then
									local tText = tButton:GetText()
									if tText then
										local tFriendlyName = SkuUtil:Unescape(tText)
										table.insert(tQuestInfoRewardsFrameChilds, tFriendlyName)
										tQuestInfoRewardsFrameChilds[tFriendlyName] = {
											frameName = "",
											RoC = "Child",
											type = "FontString",
											obj = tButton,
											textFirstLine = tText,
											textFull = "",
											childs = {},
										} 
										tc = tc + 1
									end
								end
							end
						end
					end

				end
			end

			local tc = 1
			if QuestInfoRewardsFrame.spellRewardPool and QuestInfoRewardsFrame.spellRewardPool.numActiveObjects then
				if QuestInfoRewardsFrame.spellRewardPool.numActiveObjects > 0 then
					for i, v in QuestInfoRewardsFrame.spellRewardPool:EnumerateActive() do
						local tButton = i
						if tButton then
							if tButton:IsVisible() == true then
								tButton.type = "spell"
								local tText, tFullText = GetButtonTooltipLines(tButton)
								if tText then
									tText = tText.." "..(tButton.count or "")
									local tFriendlyName = SkuUtil:Unescape(tText)
									table.insert(tQuestInfoRewardsFrameChilds, tFriendlyName)
									tQuestInfoRewardsFrameChilds[tFriendlyName] = {
										frameName = tFrameName,
										RoC = "Child",
										type = "Button",
										obj = tButton,
										textFirstLine = tText,
										textFull = tFullText,
										childs = {},
									} 
									tc = tc + 1
								end
							end
						end
					end

				end
			end

			local compCache = {}
			if QuestInfoRewardsFrame.ItemChooseText then
				if QuestInfoRewardsFrame.ItemChooseText:IsVisible() == true then
					local tText = QuestInfoRewardsFrame.ItemChooseText:GetText()
					local tFrst, tFll = SkuCore:ItemName_helper(tText)
					local tFriendlyName = tFrst
					table.insert(tQuestInfoRewardsFrameChilds, tFriendlyName)
					tQuestInfoRewardsFrameChilds[tFriendlyName] = {
						frameName = tFrameName,
						RoC = "Child",
						type = "FontString",
						obj = _G[tFrameName],
						textFirstLine = tFrst,
						textFull = tFll,
						childs = {},
					} 

					for x = 1, 10 do
						local tFrameName = "QuestInfoRewardsFrameQuestInfoItem"..x
						if _G[tFrameName] then
							if _G[tFrameName]:IsVisible() == true  and _G[tFrameName.."Name"]:GetText() then
								local tText, tFullText, itemLink = GetButtonTooltipLines(_G[tFrameName])
								if tText then
									tFullText = {tFullText}
									if itemLink then
										SkuCore:InsertComparisnSections(select(1, GetItemInfoInstant(itemLink)), tFullText, compCache)
									end
									tTaken[x] = true
									tText = tText.." "..(_G[tFrameName].count or "")
									local tFriendlyName = SkuUtil:Unescape(tText)
									if _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
										table.insert(tQuestInfoRewardsFrameChilds, tFriendlyName)
										tQuestInfoRewardsFrameChilds[tFriendlyName] = {
											frameName = tFrameName,
											RoC = "Child",
											type = "Button",
											obj = _G[tFrameName],
											textFirstLine = tText,
											textFull = tFullText,
											childs = {},
											func = _G[tFrameName]:GetScript("OnClick"),
											click = true,
										} 
										if aInfoOnly then
											tQuestInfoRewardsFrameChilds[tFriendlyName].func = nil
											tQuestInfoRewardsFrameChilds[tFriendlyName].click = nil
										end
									end
								end
							end
						end
					end
				end
			end


			local tQuestInfoRewardsFrameChilds = aParent[tFriendlyName].childs
			if QuestInfoRewardsFrame.ItemReceiveText then
				if QuestInfoRewardsFrame.ItemReceiveText:IsVisible() == true then
					local tText = QuestInfoRewardsFrame.ItemReceiveText:GetText()
					local tFrst, tFll = SkuCore:ItemName_helper(tText)
					local tFriendlyName = tFrst
					table.insert(tQuestInfoRewardsFrameChilds, tFriendlyName)
					tQuestInfoRewardsFrameChilds[tFriendlyName] = {
						frameName = tFrameName,
						RoC = "Child",
						type = "FontString",
						obj = _G[tFrameName],
						textFirstLine = tFrst,
						textFull = tFll,
						childs = {},
					} 
					for x = 1, 10 do
						if not tTaken[x] then
							local tFrameName = "QuestInfoRewardsFrameQuestInfoItem"..x
							if _G[tFrameName] then
								if _G[tFrameName]:IsVisible() == true and _G[tFrameName.."Name"]:GetText() then
									local tText, tFullText, itemLink = GetButtonTooltipLines(_G[tFrameName])
									if tText then
										tFullText = {tFullText}
										if itemLink then
											SkuCore:InsertComparisnSections(select(1, GetItemInfoInstant(itemLink)), tFullText, compCache)
										end
										tTaken[x] = true
										tText = tText.." "..(_G[tFrameName].count or "")
										local tFriendlyName = SkuUtil:Unescape(tText)
										if _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
											table.insert(tQuestInfoRewardsFrameChilds, tFriendlyName)
											tQuestInfoRewardsFrameChilds[tFriendlyName] = {
												frameName = tFrameName,
												RoC = "Child",
												type = "Button",
												obj = _G[tFrameName],
												textFirstLine = tText,
												textFull = tFullText,
												childs = {},
												func = _G[tFrameName]:GetScript("OnClick"),
												click = true,
											} 
											if aInfoOnly then
												tQuestInfoRewardsFrameChilds[tFriendlyName].func = nil
												tQuestInfoRewardsFrameChilds[tFriendlyName].click = nil
											end
										end
									end
								end
							end
						end
					end

				end
			end

			if _G["QuestInfoMoneyFrame"] then
				if _G["QuestInfoMoneyFrame"]:IsVisible() == true then
					if _G["QuestInfoMoneyFrame"].staticMoney then
						local tFrst, tFll = SkuGetCoinText(_G["QuestInfoMoneyFrame"].staticMoney, true), ""
						local tFriendlyName = tFrst
						table.insert(tQuestInfoRewardsFrameChilds, tFriendlyName)
						tQuestInfoRewardsFrameChilds[tFriendlyName] = {
							frameName = tFrameName,
							RoC = "Child",
							type = "FontString",
							obj = _G[tFrameName],
							textFirstLine = tFrst,
							textFull = tFll,
							childs = {},
						}
					end
				end
			end   


			if _G["QuestInfoTalentFrame"] then
				if _G["QuestInfoTalentFrame"]:IsVisible() == true then
					if _G["QuestInfoTalentFrame"].ReceiveText then
						local tFrst = _G["QuestInfoTalentFrame"].ReceiveText:GetText().." ".._G["QuestInfoTalentFrame"].ValueText:GetText()
						local tFriendlyName = tFrst
						table.insert(tQuestInfoRewardsFrameChilds, tFriendlyName)
						tQuestInfoRewardsFrameChilds[tFriendlyName] = {
							frameName = tFrameName,
							RoC = "Child",
							type = "FontString",
							obj = _G[tFrameName],
							textFirstLine = tFrst,
							textFull = "",
							childs = {},
						}
					end
				end
			end 			
				


			if _G["QuestInfoXPFrame"] then
				if _G["QuestInfoXPFrame"]:IsVisible() == true then
					if _G["QuestInfoXPFrame"].ReceiveText then
						local tFrst = _G["QuestInfoXPFrame"].ReceiveText:GetText().." ".._G["QuestInfoXPFrame"].ValueText:GetText()
						local tFriendlyName = tFrst
						table.insert(tQuestInfoRewardsFrameChilds, tFriendlyName)
						tQuestInfoRewardsFrameChilds[tFriendlyName] = {
							frameName = tFrameName,
							RoC = "Child",
							type = "FontString",
							obj = _G[tFrameName],
							textFirstLine = tFrst,
							textFull = "",
							childs = {},
						}
					end
				end
			end 			
				




			--QuestInfoXPFrame.ReceiveText
			--.ValueText










		end

	end


	--QuestFrameGreetingPanel
	if _G["QuestFrameGreetingPanel"] then 
		if _G["QuestFrameGreetingPanel"]:IsVisible() == true then

			-- W7/quest: flattened - no intermediate "Greeting" state node, the
			-- greeting text + selectable quest list go straight into the window
			-- so auto-descend lands on the content, not a bare state label.
			local tGreetingChilds = aParentChilds
			local dtc = { _G["QuestGreetingScrollChildFrame"]:GetRegions() }
			for x = 1, 1 do --#dtc do
				if dtc[x].GetText then
					local tText = dtc[x]:GetText()
					if tText then
						local tFrameName = "GreetingText"
						local tFriendlyName = tText
						local tFrst, tFll = SkuCore:ItemName_helper(tText)
						table.insert(tGreetingChilds, tFriendlyName)
						tGreetingChilds[tFriendlyName] = {
							frameName = tFrameName,
							RoC = "Child",
							type = "FontString",
							obj = _G[tFrameName],
							textFirstLine = tFrst,
							textFull = tFll,
							childs = {},
						}  
					end
				end
			end

			local tIconStrings = {
				[132048] = L["Accepted Quest"],
				[132049] = L["Available Quest"],
			}

			for x = 1, 10 do
				local tFrameName = "QuestTitleButton"..x
				if _G[tFrameName] then
					if _G[tFrameName]:IsVisible() == true then
						if _G[tFrameName]:GetText() then
							local tFriendlyName = SkuUtil:Unescape(_G[tFrameName]:GetText())
							if _G["QuestTitleButton"..x.."QuestIcon"]:IsVisible() == true  then
								tFriendlyName = (tIconStrings[_G["QuestTitleButton"..x.."QuestIcon"]:GetTextureFileID()] or "").." "..SkuUtil:Unescape(_G[tFrameName]:GetText())
							end
							local tText, tFullText = "", ""
							if _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
								table.insert(tGreetingChilds, tFriendlyName)
								tGreetingChilds[tFriendlyName] = {
									frameName = tFrameName,
									RoC = "Child",
									type = "Button",
									obj = _G[tFrameName],
									textFirstLine = tFriendlyName,
									textFull = "",
									childs = {},
									func = _G[tFrameName]:GetScript("OnClick"),
									click = true,
								} 
							end
						end
					end
				end
			end
		end
	end

	--QuestFrameProgressPanel
	if _G["QuestFrameProgressPanel"] then 
		if _G["QuestFrameProgressPanel"]:IsVisible() == true then
			-- W7/quest: flattened - the quest content goes straight into the
			-- window. The state used to be the "Fortschritt" node; it is now
			-- prefixed onto the quest name (dtc[1] = QuestProgressTitleText) so
			-- auto-descend lands on "Fortschritt <quest name>".
			local tProgressChilds = aParentChilds
			local dtc = { _G["QuestProgressScrollChildFrame"]:GetRegions() }
			for x = 1, 2 do
				if dtc[x].GetText then
					local tText = dtc[x]:GetText()
					if tText then
						if x == 1 then tText = L["Progress"].." "..tText end
						local tFrameName = "QuestInfo"
						local tFriendlyName = tText
						local tFrst, tFll = SkuCore:ItemName_helper(tText)
						table.insert(tProgressChilds, tFriendlyName)
						tProgressChilds[tFriendlyName] = {
							frameName = tFrameName,
							RoC = "Child",
							type = "FontString",
							obj = _G[tFrameName],
							textFirstLine = tFrst,
							textFull = tFll,
							childs = {},
						}  
					end
				end
			end
			if dtc[3]:IsVisible() == true then
				if dtc[3].GetText then
					local tText = dtc[3]:GetText()
					if tText then
						local tFrameName = "QuestInfo"
						local tFriendlyName = tText
						local tFrst, tFll = SkuCore:ItemName_helper(tText)
						table.insert(tProgressChilds, tFriendlyName)
						tProgressChilds[tFriendlyName] = {
							frameName = tFrameName,
							RoC = "Child",
							type = "FontString",
							obj = _G[tFrameName],
							textFirstLine = tFrst,
							textFull = tFll,
							childs = {},
						}  
					end
				end

				for x = 1, 10 do
					local tFrameName = "QuestProgressItem"..x
					if _G[tFrameName] then
						if _G[tFrameName]:IsVisible() == true then
							local tText, tFullText = GetButtonTooltipLines(_G[tFrameName])
							if tText then
								tText = tText.." "..(_G[tFrameName].count or "")
								local tFriendlyName = SkuUtil:Unescape(tText)
								--if _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
									table.insert(tProgressChilds, tFriendlyName)
									tProgressChilds[tFriendlyName] = {
										frameName = tFrameName,
										RoC = "Child",
										type = "Button",
										obj = _G[tFrameName],
										textFirstLine = tText,
										textFull = tFullText,
										childs = {},
										--func = _G[tFrameName]:GetScript("OnClick"),
										--click = true,
									} 
								--end
							end
						end
					end
				end
			end

			if dtc[4]:IsVisible() == true then
				if dtc[4].GetText then
					local tText = dtc[4]:GetText()
					if tText then
						local tFrameName = "QuestInfo"
						local tFriendlyName = tText
						local tFrst, tFll = SkuCore:ItemName_helper(tText)
						table.insert(tProgressChilds, tFriendlyName)
						tProgressChilds[tFriendlyName] = {
							frameName = tFrameName,
							RoC = "Child",
							type = "FontString",
							obj = _G[tFrameName],
							textFirstLine = tFrst,
							textFull = tFll,
							childs = {},
						}  
					end
				end
			end

			local tFrameName = "QuestFrameCompleteButton"
			if _G[tFrameName] then
				if _G[tFrameName]:IsVisible() == true then
					if _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
						local tFriendlyName = _G[tFrameName]:GetText()
						table.insert(tProgressChilds, tFriendlyName)
						tProgressChilds[tFriendlyName] = {
							frameName = tFrameName,
							RoC = "Child",
							type = "Button",
							obj = _G[tFrameName],
							textFirstLine = tFriendlyName,
							textFull = "",
							childs = {},
							func = _G[tFrameName]:GetScript("OnClick"),
							click = true,
						} 
					end
				end
			end
		end
	end

	--QuestFrameDetailPanel
	if _G["QuestFrameDetailPanel"] then 
		if _G["QuestFrameDetailPanel"]:IsVisible() == true then
			-- W7/quest: flattened - the quest content goes straight into the
			-- window. The state used to be the "Details" node; it is now prefixed
			-- (as "Annehmen") onto the quest name (QuestInfoTitleHeader) so
			-- auto-descend lands on "Annehmen <quest name>".
			local tDetailChilds = aParentChilds
			local dtc = { _G["QuestDetailScrollChildFrame"]:GetRegions() }
			local tFrameName = "QuestInfoTitleHeader"
			if _G[tFrameName] then
				local tText = _G[tFrameName]:GetText()
				if tText then

					for i, v in pairs(SkuDB.questLookup[Sku.Loc]) do
						if v[1] == tText then
							if SkuDB.questDataTBC[i][SkuDB.questKeys.skuData] then
								if SkuDB.questDataTBC[i][SkuDB.questKeys.skuData][1] and SkuDB.questDataTBC[i][SkuDB.questKeys.skuData][1][1] == true then
									tText = tText.." "..L["Blacklisted"]
									break
								end
							end
						end
					end

					tText = L["Accept"].." "..tText
					local tFriendlyName = tText
					local tFrst, tFll = SkuCore:ItemName_helper(tText)
					table.insert(tDetailChilds, tFriendlyName)
					tDetailChilds[tFriendlyName] = {
						frameName = tFrameName,
						RoC = "Child",
						type = "FontString",
						obj = _G[tFrameName],
						textFirstLine = tFrst,
						textFull = tFll,
						childs = {},
					}
				end
			end
			local tFrameName = "QuestInfoDescriptionText"
			if _G[tFrameName] then
				local tText = _G[tFrameName]:GetText()
				if tText then
					local tFriendlyName = tText
					local tFrst, tFll = SkuCore:ItemName_helper(tText)
					table.insert(tDetailChilds, tFriendlyName)
					tDetailChilds[tFriendlyName] = {
						frameName = tFrameName,
						RoC = "Child",
						type = "FontString",
						obj = _G[tFrameName],
						textFirstLine = tFrst,
						textFull = tFll,
						childs = {},
					}  
				end
			end

			local tFrameName = "QuestInfoObjectivesHeader"
			if _G[tFrameName] then
				local tText = _G[tFrameName]:GetText()
				if tText then
					local tFriendlyName = tText
					local tFrst, tFll = SkuCore:ItemName_helper(tText)
					table.insert(tDetailChilds, tFriendlyName)
					tDetailChilds[tFriendlyName] = {
						frameName = tFrameName,
						RoC = "Child",
						type = "FontString",
						obj = _G[tFrameName],
						textFirstLine = tFrst,
						textFull = tFll,
						childs = {},
					}  
				end
			end
			local tFrameName = "QuestInfoObjectivesText"
			if _G[tFrameName] then
				local tText = _G[tFrameName]:GetText()
				if tText then
					local tFriendlyName = tText
					local tFrst, tFll = SkuCore:ItemName_helper(tText)
					table.insert(tDetailChilds, tFriendlyName)
					tDetailChilds[tFriendlyName] = {
						frameName = tFrameName,
						RoC = "Child",
						type = "FontString",
						obj = _G[tFrameName],
						textFirstLine = tFrst,
						textFull = tFll,
						childs = {},
					}  
				end
			end

			--rewards
			if _G["QuestInfoRewardsFrame"] then 
				QuestInfoRewardsFrameHelper(tDetailChilds, true)
			end

			local tFrameName = "QuestFrameAcceptButton"
			local tFriendlyName = L["Accept"]
			local tFrst, tFll = tFriendlyName, ""
			if _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
				table.insert(tDetailChilds, tFriendlyName)
				tDetailChilds[tFriendlyName] = {
					frameName = tFrameName,
					RoC = "Child",
					type = "Button",
					obj = _G[tFrameName],
					textFirstLine = tFrst,
					textFull = tFll,
					childs = {},
					func = _G[tFrameName]:GetScript("OnClick"),
					click = true,
				}  
			end
			local tFrameName = "QuestFrameDeclineButton"
			local tFriendlyName = L["Ablehnen"]
			local tFrst, tFll = tFriendlyName, ""
			if _G[tFrameName]:IsEnabled() == true then --IsMouseClickEnabled()
				table.insert(tDetailChilds, tFriendlyName)
				tDetailChilds[tFriendlyName] = {
					frameName = tFrameName,
					RoC = "Child",
					type = "Button",
					obj = _G[tFrameName],
					textFirstLine = tFrst,
					textFull = tFll,
					childs = {},
					func = _G[tFrameName]:GetScript("OnClick"),
					click = true,
				}  			
			end
		end
	end


	--QuestFrameRewardPanel
	if _G["QuestFrameRewardPanel"] then 
		if _G["QuestFrameRewardPanel"]:IsVisible() == true then
			-- W7/quest: flattened - the quest content goes straight into the
			-- window. The state used to be the "Abgabe" node; it is now prefixed
			-- onto the quest name (QuestInfoTitleHeader) so auto-descend lands on
			-- "Abgabe <quest name>".
			local tDetailChilds = aParentChilds

			local tFrameName = "QuestInfoTitleHeader"
			if _G[tFrameName] then
				local tText = _G[tFrameName]:GetText()
				if tText then
					tText = L["Abgabe"].." "..tText
					local tFriendlyName = tText
					local tFrst, tFll = SkuCore:ItemName_helper(tText)
					table.insert(tDetailChilds, tFriendlyName)
					tDetailChilds[tFriendlyName] = {
						frameName = tFrameName,
						RoC = "Child",
						type = "FontString",
						obj = _G[tFrameName],
						textFirstLine = tFrst,
						textFull = tFll,
						childs = {},
					}  
				end
			end
			local tFrameName = "QuestInfoRewardText"
			if _G[tFrameName] then
				local tText = _G[tFrameName]:GetText()
				if tText then
					local tFriendlyName = tText
					local tFrst, tFll = SkuCore:ItemName_helper(tText)
					table.insert(tDetailChilds, tFriendlyName)
					tDetailChilds[tFriendlyName] = {
						frameName = tFrameName,
						RoC = "Child",
						type = "FontString",
						obj = _G[tFrameName],
						textFirstLine = tFrst,
						textFull = tFll,
						childs = {},
					}  
				end
			end

			if QuestInfoRewardsFrame.ItemChooseText:IsVisible() == true or QuestInfoRewardsFrame.ItemReceiveText:IsVisible() == true or (QuestInfoMoneyFrame:IsVisible() == true and QuestInfoMoneyFrame:IsVisible() == true and QuestInfoMoneyFrame.staticMoney) then
				QuestInfoRewardsFrameHelper(tDetailChilds)
			end
			
			local tFrameName = "QuestFrameCompleteQuestButton"
			local tFriendlyName = L["Complete"]
			local tFrst, tFll = tFriendlyName, ""
			table.insert(tDetailChilds, tFriendlyName)
			tDetailChilds[tFriendlyName] = {
				frameName = tFrameName,
				RoC = "Child",
				type = "Button",
				obj = _G[tFrameName],
				textFirstLine = tFrst,
				textFull = tFll,
				childs = {},
				func = _G[tFrameName]:GetScript("OnClick"),
				click = true,
			}  
						
		end
	end
end