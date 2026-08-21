---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME, MODULE_PART = "SkuCore", "LocalMenu"
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

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


---------------------------------------------------------------------------------------------------------------------------------------
-- Pending item data
--
-- [v42.13] Everything in this file that names an item does it by pointing a
-- scanning tooltip at it and reading line 1. When the client has not got the
-- item's data yet that line is RETRIEVING_ITEM_INFO ("Frage
-- Gegenstandsinformationen ab"), and Sku used to bake THAT in as the name -- with
-- no way back, because nothing ever asked the client to load the item and nothing
-- ever re-read the entry when the data arrived. So the name stayed stuck for the
-- rest of the session, no matter how often the menu was rebuilt.
--
-- Three pieces fix that, and all three are needed:
--   * ResolveItemName   -- a name we can produce WITHOUT the server, so a pending
--                          entry still says what it is. SkuDB.itemLookup is Sku's
--                          own shipped item-name table and knows most of TBC.
--   * RequestItemData   -- actually ask the client to load it. Poking a tooltip
--                          was never a request we owned or could follow up on.
--   * the driver below  -- GET_ITEM_INFO_RECEIVED -> one coalesced quiet rebuild,
--                          so the entry re-reads itself once the data lands.
-- See SkuUtil:IsRetrievingItemInfo for why the placeholder must not be the name.
---------------------------------------------------------------------------------------------------------------------------------------
local tPendingItemIds = {}
local tPendingRefreshQueued = false

-- Item name that needs no server round-trip: the client cache first (it can hold
-- the name while the rest of the tooltip is still pending), then Sku's own item
-- table, then the link's own [brackets].
--
-- [v42.13] aPreferOffline flips the first two steps for BULK callers. GetItemInfo
-- is the expensive path twice over: it is the heavy full-item variant, and on a
-- MISS it queues a server item query, so a caller that walks tens of thousands of
-- ids fires tens of thousands of queries the user never asked for. SkuDB.itemLookup
-- is Sku's own shipped, correctly localized name table and answers nearly all of
-- them offline, so bulk callers ask it first and only fall back to the client for
-- the ids it does not know. Single-item callers keep the original order: for ONE
-- item the client's own name is the more authoritative answer and the one query is
-- exactly what we want.
--
-- Names taken from SkuDB are returned as-is. They are plain data strings with no
-- |c/|H/|T markup in them, so running Unescape (six gsub passes) over each one is
-- pure cost - measurable once the caller is doing it 40,000 times.
function SkuCore:ResolveItemName(aItemId, aItemLink, aPreferOffline)
	local tLookup = (SkuDB and SkuDB.itemLookup and SkuDB.itemLookup[Sku.Loc]) or nil
	if aPreferOffline and aItemId and tLookup then
		local tOffline = tLookup[aItemId]
		if type(tOffline) == "string" and tOffline ~= "" then
			return tOffline
		end
	end
	local tName
	if aItemLink then tName = GetItemInfo(aItemLink) end
	if not tName and aItemId then tName = GetItemInfo(aItemId) end
	if type(tName) == "string" and tName ~= "" then
		return SkuUtil:Unescape(tName)
	end
	if aItemId and tLookup then
		local tOffline = tLookup[aItemId]
		if type(tOffline) == "string" and tOffline ~= "" then
			return tOffline
		end
	end
	if type(aItemLink) == "string" then
		local tBracketed = string.match(aItemLink, "%[(.-)%]")
		if tBracketed and tBracketed ~= "" then
			return SkuUtil:Unescape(tBracketed)
		end
	end
end

-- What a still-loading entry reads as: the real name plus a short marker, so the
-- "still fetching" state stays audible without costing the name or the ability to
-- tell two pending slots apart. Only when nothing at all resolves does the marker
-- stand alone -- and then it carries the item id, which is still unique per slot.
function SkuCore:PendingItemLabel(aItemId, aItemLink)
	local tMarker = Sku.deEn("lädt", "loading", "chargement")
	local tName = SkuCore:ResolveItemName(aItemId, aItemLink)
	if tName then
		return tName.." ("..tMarker..")"
	end
	return tMarker..", "..Sku.deEn("Gegenstand", "item", "objet").." "..tostring(aItemId or "?")
end

-- Ask the client for an item's data and remember that a menu entry waits on it.
function SkuCore:RequestItemData(aItemId)
	if type(aItemId) ~= "number" then return end
	tPendingItemIds[aItemId] = true
	pcall(function() Item:CreateFromItemID(aItemId):ContinueOnItemLoad(function() end) end)
end

-- Run aCallback once aItemId's data is available -- immediately when it already
-- is, since ContinueOnItemLoad fires straight away for a cached item. Replaces
-- the hand-rolled "call it once to warm the cache, re-read on a 0.1 s timer"
-- pattern, which raced the server instead of waiting for it.
function SkuCore:ContinueOnItemData(aItemId, aCallback)
	if type(aCallback) ~= "function" then return end
	if type(aItemId) ~= "number" then aCallback() return end
	local tOk = pcall(function() Item:CreateFromItemID(aItemId):ContinueOnItemLoad(aCallback) end)
	-- Error path, not a second strategy: if the id is not a real item we still owe
	-- the caller its one run, otherwise the menu entry would never be filled at all.
	if not tOk then aCallback() end
end

-- One quiet rebuild per burst of arrivals. GET_ITEM_INFO_RECEIVED fires once per
-- item, so a freshly opened bank full of uncached items would otherwise rebuild
-- the menu 28 times in a row.
local function tQueuePendingRefresh()
	if tPendingRefreshQueued then return end
	tPendingRefreshQueued = true
	C_Timer.After(0.3, function()
		tPendingRefreshQueued = false
		if _G.SkuBagIdleRefresh then pcall(_G.SkuBagIdleRefresh) end
	end)
end

-- Pre-warm a container's items. Without this the FIRST pass over a freshly opened
-- bank is guaranteed to be placeholders, because nothing has ever asked the server
-- for those items this session -- the bank is the one container whose contents the
-- player has not necessarily touched since login.
local function tPrewarmContainer(aBagId)
	local tNumSlots = GetContainerNumSlots(aBagId) or 0
	for tSlot = 1, tNumSlots do
		local tItemId = GetContainerItemID(aBagId, tSlot)
		if tItemId then SkuCore:RequestItemData(tItemId) end
	end
end

local tItemDataDriver = CreateFrame("Frame")
tItemDataDriver:SetScript("OnEvent", function(self, aEvent, arg1)
	if aEvent == "GET_ITEM_INFO_RECEIVED" then
		if arg1 and tPendingItemIds[arg1] then
			tPendingItemIds[arg1] = nil
			dprint("itemdata", "arrived", arg1)
			tQueuePendingRefresh()
		end
	elseif aEvent == "BANKFRAME_OPENED" then
		tPrewarmContainer(-1)
		for tBagId = 5, 11 do tPrewarmContainer(tBagId) end
		dprint("itemdata", "prewarm bank")
	elseif aEvent == "PLAYERBANKSLOTS_CHANGED" then
		local tItemId = arg1 and GetContainerItemID(-1, arg1)
		if tItemId then SkuCore:RequestItemData(tItemId) end
	end
end)
tItemDataDriver:RegisterEvent("GET_ITEM_INFO_RECEIVED")
tItemDataDriver:RegisterEvent("BANKFRAME_OPENED")
tItemDataDriver:RegisterEvent("PLAYERBANKSLOTS_CHANGED")

---------------------------------------------------------------------------------------------------------------------------------------
-- [v42.11] Quality and item level are resolved HERE from the tooltip we are
-- actually scanning, instead of being computed by each caller from a
-- possibly-stale :GetItem(). See the block comment on SkuUtil:TooltipItemLink.
local function tScanTooltipRegions(aTooltipObj)
	local tFirstLine = SkuUtil:TooltipFirstLine(aTooltipObj:GetRegions())
	local tItemLink = SkuUtil:TooltipItemLink(tFirstLine, aTooltipObj)
	local aQualityString = SkuUtil:ItemQualityString(tItemLink)
	local aEffectiveILvl = SkuUtil:ItemLevel(tItemLink)

	local tTooltipText = ""
	local tLineCounter = 1
	for i = 1, select("#", aTooltipObj:GetRegions()) do
		local region = select(i, aTooltipObj:GetRegions())
		if region and region:GetObjectType() == "FontString" then
			local text = region:GetText()
			if text then
				if tLineCounter == 1 and aQualityString and SkuSettings:Sub("SkuCore").itemSettings.ShowItemQality == true then
					tTooltipText = tTooltipText..text.." ("..aQualityString..")\r\n"
				elseif tLineCounter == 2 and aEffectiveILvl then
					tTooltipText = tTooltipText..L["Item Level"]..": "..aEffectiveILvl.."\r\n"
					tTooltipText = tTooltipText..text.."\r\n"
				else
					tTooltipText = tTooltipText..text.."\r\n"
				end
				tLineCounter = tLineCounter + 1
			end
		end
	end
	-- Second return: the VALIDATED link, so callers that need it (GetButtonTooltipLines
	-- hands it on to the merchant/bank menus) get the same one the text describes.
	return tTooltipText, tItemLink
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

	-- [v42.11] The GetSpell() fallback that used to sit here assigned a spell id
	-- (GetSpell's second return is not a link) into ItemLink and then handed it to
	-- GetDetailedItemLevelInfo -- an item-level lookup on a spell. It could never
	-- produce anything useful, so it is gone; tScanTooltipRegions now resolves the
	-- link itself, and returns no item level at all for a spell tooltip.
	local tTooltipText, ItemLink = tScanTooltipRegions(tTooltipObj)

	if not aTooltipObject then
		tTooltipObj:SetOwner(UIParent, "Center")
		tTooltipObj:Hide()
		if aButtonObj:GetScript("OnLeave") then
			aButtonObj:GetScript("OnLeave")(aButtonObj)
		end
	end
	
	-- [v42.13] Same demotion as in the bag reader, for every window that names an
	-- item by scanning a native button (merchant, quest rewards, guild bank, mail,
	-- trainer, tradeskill). Here there is usually no item id to resolve a real name
	-- from -- an uncached tooltip yields no link either -- so the best we can do is
	-- the short marker instead of the 33-character sentence, plus a load request so
	-- the next quiet rebuild resolves it.
	if SkuUtil:IsRetrievingItemInfo(tTooltipText) then
		local tItemId = aButtonObj and (aButtonObj.itemId or (aButtonObj.info and aButtonObj.info.id))
		if tItemId then SkuCore:RequestItemData(tItemId) end
		local tPendingLabel = SkuCore:PendingItemLabel(tItemId, nil)
		return tPendingLabel, tPendingLabel, nil
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
---@return boolean | nil True when the client has not sent the item's data yet
local function getItemTooltipTextHelper(tooltipSetter)
	local tooltip = _G["SkuScanningTooltip"]
	tooltip:ClearLines()
	tooltipSetter(tooltip)
	local tEscapedText = TooltipLines_helper(tooltip:GetRegions())
	-- [v42.13] "Frage Gegenstandsinformationen ab" is a state, not a name -- report
	-- it as one so the caller can name the item another way and ask for the data.
	if SkuUtil:IsRetrievingItemInfo(tEscapedText) then
		return nil, true
	end
	if tEscapedText ~= "asd" and tEscapedText ~= "" then
		return SkuUtil:Unescape(tEscapedText)
	end
end

-- Point a scanning/GameTooltip at a container slot's item.
--
-- The bank MAIN container (-1) needs a different setter: SetBagItem(-1, slot)
-- populates NOTHING on the 2.5.6 client, which is why every filled bank slot once
-- rendered as "Empty" (fixed in 67f2132). That fix reached for
-- SetHyperlink(GetContainerItemLink(...)) because it works for every container
-- generically -- but a hyperlink is precisely the path that depends on the
-- client's item cache, so the bank became the place where "Frage
-- Gegenstandsinformationen ab" turned up instead of a name.
--
-- [v42.13] Bank slots are real INVENTORY slots (bank slot n = inventory slot
-- n + 39), so SetInventoryItem reads them from local data exactly the way
-- SetBagItem reads a bag, no cache round-trip. That is what Blizzard's own
-- BankFrameItemButton_OnEnter does. It is NOT a return to the rendered-widget
-- reading that 5ce5ce0 retired: no frame, no OnEnter, no force-open -- just a
-- tooltip setter, the same class of call as SetBagItem. The bank node is only
-- built while BankFrame is visible (see Build_BagsFrame), which is exactly when
-- those inventory slots are valid.
--
-- Deliberately NO hyperlink fallback behind this: stacking a cache-dependent path
-- behind a local one only hides whether the local one works. If SetInventoryItem
-- ever comes up empty for the bank we want to see that and fix it, not mask it.
local function tSetTooltipContainerItem(tooltip, bag, slot)
	if bag == -1 then
		tooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(slot))
		return
	end
	-- [v43.0] The KEYRING (-2) has the same quirk as the bank: SetBagItem(-2, slot)
	-- populates nothing, so from v42.13 (which removed the hyperlink fallback) every
	-- key spoke as "Empty". Keyring slots are inventory slots too, and this is
	-- exactly what Blizzard's ContainerFrameItemButton_OnEnter does for the keyring.
	if bag == -2 and _G.KeyRingButtonIDToInvSlotID then
		tooltip:SetInventoryItem("player", KeyRingButtonIDToInvSlotID(slot))
		return
	end
	tooltip:SetBagItem(bag, slot)
end

local function getItemTooltipTextFromBagItem(bag, slot, itemId, button)
	if button then
		if button:GetScript("OnEnter") then
			button:GetScript("OnEnter")(button)

			local tTooltipText = tScanTooltipRegions(GameTooltip)
			getItemTooltipTextHelper(function(tooltip)
				if itemId then
					tooltip:SetItemByID(itemId)
				else
					tSetTooltipContainerItem(tooltip, bag, slot)
				end
			end)
			return SkuUtil:Unescape(tTooltipText)
		end
	else

		return getItemTooltipTextHelper(function(tooltip)
			if itemId then
				tooltip:SetItemByID(itemId)
			else
				tSetTooltipContainerItem(tooltip, bag, slot)
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
-- [v42.08] Helfer + Logik fuer die Gildenbank-Geld-Sektion (portiert aus Naxedims
-- SkuMoneyReplacement, nativ). Skus Build_GuildBankFrame liess das Geld als TODO
-- (--gold/--available/--witdraw/--deposit). Diese Eintraege sind rohe Gossip-Eintraege
-- im Stil des restlichen Builders: 'func' ohne 'click' wird vom Menue als OnAction
-- ausgefuehrt (SkuZOptions/Core.lua:5661), Eintraege mit 'childs' werden Untermenues.
local function tGbNewEntry(aName)
	return { frameName = "", RoC = "Child", type = "Button", obj = nil,
		textFirstLine = aName, textFull = "", noMenuNumbers = true, childs = {}, }
end

-- Info-Eintrag: bei Navigation wird textFirstLine gelesen (Schnappschuss); ENTER liest
-- ueber func den frischen Wert nach (Totale aendern sich nach Ein-/Auszahlung).
local function tGbAddInfo(aChilds, aName, aLiveFunc)
	local tEntry = tGbNewEntry(aName)
	if type(aLiveFunc) == "function" then
		tEntry.func = function()
			local ok, tText = pcall(aLiveFunc)
			pcall(function() SkuOptions.Voice:OutputStringBTtts(ok and tText or aName, false, true, 0.2, nil, nil, nil, 1) end)
		end
	end
	table.insert(aChilds, aName); aChilds[aName] = tEntry
	return tEntry
end

local function tGbAddAction(aChilds, aName, aFunc)
	local tEntry = tGbNewEntry(aName)
	tEntry.func = function(...)
		local ok, err = pcall(aFunc, ...)
		if not ok then dprint("gbankMoney", "action error", tostring(err)) end
	end
	table.insert(aChilds, aName); aChilds[aName] = tEntry
	return tEntry
end

local function tGbAddSubMenu(aChilds, aName)
	local tEntry = tGbNewEntry(aName)
	table.insert(aChilds, aName); aChilds[aName] = tEntry
	return tEntry.childs
end

-- Heute noch abhebbarer Betrag (Gildenbank-Tageslimit; -1 = unbegrenzt).
local function tGbWithdrawRemainingText()
	local tRemaining = (GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()) or 0
	if tRemaining < 0 then return Sku.deEn("unbegrenzt", "unlimited", "illimité") end
	local tBank = (GetGuildBankMoney and GetGuildBankMoney()) or 0
	if tRemaining > tBank then tRemaining = tBank end
	return SkuGetCoinText(tRemaining, true, true)
end

-- Ein-/Auszahlung mit Vorab-Pruefung (genug Gold / genug in der Bank / Tageslimit) und
-- Vorher/Nachher-Ansage (der Server antwortet mit leichter Verzoegerung).
local function tRunGuildBankMoney(aCopper, aIsDeposit)
	if not aCopper or aCopper <= 0 then
		pcall(function() SkuOptions.Voice:OutputStringBTtts(Sku.deEn("Betrag ist null", "Amount is zero", "Le montant est nul"), false, true, 0.2) end)
		return
	end
	if aIsDeposit then
		if aCopper > GetMoney() then
			pcall(function() SkuOptions.Voice:OutputStringBTtts(Sku.deEn("Nicht genug Gold dabei", "Not enough money on you", "Pas assez d'argent sur vous"), false, true, 0.2) end)
			return
		end
	else
		local tBank = (GetGuildBankMoney and GetGuildBankMoney()) or 0
		if aCopper > tBank then
			pcall(function() SkuOptions.Voice:OutputStringBTtts(Sku.deEn("Nicht genug in der Gildenbank", "Not enough in the guild bank", "Pas assez dans la banque de guilde"), false, true, 0.2) end)
			return
		end
		local tRemaining = (GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()) or 0
		if tRemaining >= 0 and aCopper > tRemaining then
			pcall(function() SkuOptions.Voice:OutputStringBTtts(Sku.deEn("Abhebe-Limit erreicht", "Withdraw limit reached", "Limite de retrait atteinte"), false, true, 0.2) end)
			return
		end
	end
	local tBefore = GetMoney()
	if aIsDeposit then pcall(DepositGuildBankMoney, aCopper) else pcall(WithdrawGuildBankMoney, aCopper) end
	C_Timer.After(0.6, function()
		local tAfter = GetMoney()
		local tOk = (aIsDeposit and (tAfter < tBefore)) or ((not aIsDeposit) and (tAfter > tBefore))
		if tOk then
			local tMsg = (aIsDeposit and Sku.deEn("Eingezahlt: ", "Deposited: ", "Déposé : ") or Sku.deEn("Abgehoben: ", "Withdrawn: ", "Retiré : "))..SkuGetCoinText(aCopper, true, true)
			pcall(function() SkuOptions.Voice:OutputStringBTtts(tMsg, false, true, 0.2, nil, nil, nil, 1) end)
		else
			pcall(function() SkuOptions.Voice:OutputStringBTtts(Sku.deEn("Aktion fehlgeschlagen", "Action failed", "Échec de l'action"), false, true, 0.2) end)
		end
	end)
end

-- Fragt einen Gold-Betrag per Editbox ab und fuehrt die Ein-/Auszahlung aus.
local function tGbPromptAndRun(aIsDeposit)
	PlaySound(88)
	pcall(function() SkuOptions.Voice:OutputStringBTtts(Sku.deEn("Betrag in Gold eingeben", "Enter amount in gold", "Saisir le montant en or"), false, true, 0.2) end)
	SkuOptions:EditBoxShow("", function()
		PlaySound(89)
		local tG = math.floor(tonumber(SkuOptionsEditBoxEditBox:GetText() or "") or 0)
		if tG < 0 then tG = 0 end
		tRunGuildBankMoney(tG * 10000, aIsDeposit)
	end)
end

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
	-- [v42.08] Gildenbank-Geld (vormals TODO): Lesen (in der Bank / heute noch abhebbar /
	-- dein Gold) + Ein-/Auszahlen in Gold. Rohe Gossip-Eintraege im Builder-Stil.
	do
		local tMoneyChilds = tGbAddSubMenu(aParentChilds, Sku.deEn("Gildenbank-Geld", "Guild bank money", "Argent de la banque de guilde"))

		local tInBankLabel = Sku.deEn("In der Gildenbank", "In the guild bank", "Dans la banque de guilde")
		tGbAddInfo(tMoneyChilds, tInBankLabel..": "..SkuGetCoinText((GetGuildBankMoney and GetGuildBankMoney()) or 0, true, true),
			function() return tInBankLabel..": "..SkuGetCoinText((GetGuildBankMoney and GetGuildBankMoney()) or 0, true, true) end)

		local tRemLabel = Sku.deEn("Heute noch abhebbar", "Withdrawable today", "Retirable aujourd'hui")
		tGbAddInfo(tMoneyChilds, tRemLabel..": "..tGbWithdrawRemainingText(),
			function() return tRemLabel..": "..tGbWithdrawRemainingText() end)

		local tYourLabel = Sku.deEn("Dein Gold", "Your money", "Votre argent")
		tGbAddInfo(tMoneyChilds, tYourLabel..": "..SkuGetCoinText(GetMoney(), true, true),
			function() return tYourLabel..": "..SkuGetCoinText(GetMoney(), true, true) end)

		tGbAddAction(tMoneyChilds, Sku.deEn("Gold einzahlen", "Deposit gold", "Déposer de l'or"), function() tGbPromptAndRun(true) end)
		tGbAddAction(tMoneyChilds, Sku.deEn("Gold abheben", "Withdraw gold", "Retirer de l'or"), function() tGbPromptAndRun(false) end)
	end



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
					if SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.parent then
						SkuOptions.currentMenuPosition.parent:OnUpdate()
					end
					SkuOptions.Voice:OutputStringBTtts("sound-notification16", false, true)--24
				end)
			end

		end)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Modern container-API bag sort engine (migration from the old click-simulation).
--
-- Item data is READ via C_Container.GetContainerItemInfo (falling back to the
-- classic globals) and items are MOVED with PickupContainerItem -- so sorting no
-- longer depends on the bags being physically open / rendered as ContainerFrameNItemM
-- frames (the reworked bag menu is container-API driven; this closes the last piece
-- that still drove the UI by simulated clicks).
--
-- Algorithm: a SELECTION sort per bag (place the correct item into each slot once),
-- executed ONE swap per BAG_UPDATE_DELAYED "settle" so we never act on a slot whose
-- item is still locked/in-flight. This guarantees termination (<= N-1 swaps per bag)
-- and removes the old bubble-sort death-loop (a swap that failed to change the slots
-- made the comparator re-fire forever). The "all bags" action processes bags ONE AT A
-- TIME (single game cursor) instead of spawning a coroutine per bag that fought over it.
--
-- Every step is pcall-guarded and traced via dprint("bagSort", ...) + SkuErrorLog;
-- errors and missing settle events abort/advance cleanly instead of wedging or
-- silently swallowing (the old coroutine.resume dropped every error on the floor).
---------------------------------------------------------------------------------------------------------------------------------------
local tSortSettleTimeout = 0.75           -- watchdog: proceed if no BAG_UPDATE_DELAYED lands
local tSortJob = nil                      -- singleton in-flight job (nil = idle)
local tSortDriver                         -- event frame for BAG_UPDATE_DELAYED
local tSortStep                           -- forward declaration (mutually referenced)

-- Read one slot. Returns an entry table for a filled slot, or nil for an empty slot.
-- Covers both the new (C_Container -> info table) and classic (multi-return) APIs.
local function tSortReadEntry(bag, slot)
	local id, link, quality, locked
	if _G.C_Container and _G.C_Container.GetContainerItemInfo then
		local ok, info = pcall(_G.C_Container.GetContainerItemInfo, bag, slot)
		if ok then
			if info == nil then
				return nil                -- confirmed empty
			elseif info.hyperlink or info.itemID then
				id, link, quality, locked = info.itemID, info.hyperlink, info.quality, info.isLocked
			end
		end
	end
	if not link and _G.GetContainerItemInfo then
		local ok, a, b, c, d, e, f, g, h, i2, j = pcall(_G.GetContainerItemInfo, bag, slot)
		if ok then
			if type(a) == "table" then
				id, link, quality, locked = a.itemID, a.hyperlink, a.quality, a.isLocked
			else
				-- classic multi-return: isLocked=3, quality=4, itemLink=7, itemID=10
				link, id, quality, locked = g, j, d, c
			end
		end
	end
	if not link and not id then return nil end
	local name
	if link and _G.C_Item and _G.C_Item.GetItemNameByID then
		name = _G.C_Item.GetItemNameByID(link)
	end
	if not name and link then
		name = link:match("%[(.-)%]")     -- localized name straight from the hyperlink
	end
	if not name and id and _G.C_Item and _G.C_Item.GetItemNameByID then
		name = _G.C_Item.GetItemNameByID(id)
	end
	return { id = id, link = link, quality = quality or 0, name = name or "", locked = locked }
end

-- Strict "a should come before b" ordering. Empty slots (nil) always sink to the end
-- in BOTH directions, so items pack toward the front. Ties return false (no move).
local function tSortMakeBefore(mode, dir)
	return function(a, b)
		if a == nil then return false end      -- empty is never "before"
		if b == nil then return true end       -- filled before empty
		if mode == "collapse" then
			return false                       -- keep item order; only empties move
		elseif mode == "quality" then
			if a.quality == b.quality then return false end
			if dir == "asc" then return a.quality < b.quality else return a.quality > b.quality end
		else -- name
			if a.name == b.name then return false end
			if dir == "asc" then return a.name < b.name else return a.name > b.name end
		end
	end
end

local function tSortNumSlots(bag)
	if _G.C_Container and _G.C_Container.GetContainerNumSlots then
		local ok, n = pcall(_G.C_Container.GetContainerNumSlots, bag)
		if ok and n then return n end
	end
	if _G.GetContainerNumSlots then
		local ok, n = pcall(_G.GetContainerNumSlots, bag)
		if ok and n then return n end
	end
	return 0
end

local function tSortPickup(bag, slot)
	if _G.PickupContainerItem then return pcall(_G.PickupContainerItem, bag, slot) end
	if _G.C_Container and _G.C_Container.PickupContainerItem then
		return pcall(_G.C_Container.PickupContainerItem, bag, slot)
	end
	return false
end

-- Occupancy-agnostic swap of two slots in the SAME bag. 2-3 pickups; guarantees the
-- cursor ends empty for every case (both filled / one empty / both empty) so the old
-- "item stranded on the cursor" desync can't happen.
local function tSortSwapSlots(bag, s1, s2)
	tSortPickup(bag, s1)
	tSortPickup(bag, s2)
	if _G.CursorHasItem and _G.CursorHasItem() then
		tSortPickup(bag, s1)
	end
	if _G.CursorHasItem and _G.CursorHasItem() and _G.ClearCursor then
		_G.ClearCursor()
	end
end

local function tSortBankVisible()
	return _G["BankFrame"] and _G["BankFrame"]:IsVisible() == true
end

-- Bank main (-1), bank bags (5..11) and the reagent bank (-3) can only be moved while
-- the bank UI is open; backpack/bags (0..4) and the keyring (-2) are always reachable
-- through the container API (no need to force the bag frames open anymore).
local function tSortBagEligible(bag)
	if tSortNumSlots(bag) <= 0 then return false end
	if bag == -1 or bag == -3 or (bag >= 5 and bag <= 11) then
		return tSortBankVisible()
	end
	return true
end

local function tSortFinish(aAbortMsg)
	local job = tSortJob
	if not job then return end
	tSortJob = nil
	if tSortDriver then tSortDriver:UnregisterEvent("BAG_UPDATE_DELAYED") end
	if job.watchdog then pcall(function() job.watchdog:Cancel() end) job.watchdog = nil end
	if tIsProcessing > 0 then tIsProcessing = tIsProcessing - 1 end
	SkuCore.CursorSilent = false
	SkuOptions.Voice.TutorialPlaying = 0
	pcall(function() SkuOptions.Voice:StopOutputEmptyQueue() end)
	SortProcessingSoundHelper()           -- plays the "done" chime once tIsProcessing hits 0
	if _G.SkuBagIdleRefresh then pcall(_G.SkuBagIdleRefresh) end   -- silent menu re-sync
	dprint("bagSort", aAbortMsg and ("aborted: "..aAbortMsg) or "done")
end

local function tSortArmWatchdog()
	local job = tSortJob
	if not job then return end
	if job.watchdog then pcall(function() job.watchdog:Cancel() end) end
	if _G.C_Timer and _G.C_Timer.NewTimer then
		job.watchdog = _G.C_Timer.NewTimer(tSortSettleTimeout, function()
			if tSortJob ~= job or not job.waiting then return end
			job.waiting = false
			dprint("bagSort", "settle timeout -> forcing next step")
			tSortStep()
		end)
	end
end

tSortStep = function()
	local job = tSortJob
	if not job then return end
	local ok, err = pcall(function()
		while true do
			local bag = job.bags[job.bagIdx]
			if bag == nil then
				tSortFinish()             -- all bags processed
				return
			end
			if not tSortBagEligible(bag) then
				dprint("bagSort", "skip bag", bag, "(ineligible)")
				job.bagIdx, job.p, job.steps = job.bagIdx + 1, 1, 0
			else
				local n = tSortNumSlots(bag)
				local entries = {}
				for s = 1, n do entries[s] = tSortReadEntry(bag, s) end

				local p = job.p
				while p <= n - 1 do
					if job.steps >= (n + 2) then     -- belt-and-suspenders swap cap
						dprint("bagSort", "step cap hit on bag", bag)
						p = n                        -- treat bag as done
						break
					end
					-- selection min in [p..n]
					local minIdx = p
					for q = p + 1, n do
						if job.before(entries[q], entries[minIdx]) then minIdx = q end
					end
					if minIdx ~= p then
						if (entries[p] and entries[p].locked) or (entries[minIdx] and entries[minIdx].locked) then
							dprint("bagSort", "locked slot, waiting", "bag="..bag, "p="..p, "q="..minIdx)
							job.waiting = true
							tSortArmWatchdog()
							return
						end
						dprint("bagSort", "swap", "bag="..bag, "p="..p, "q="..minIdx,
							(entries[minIdx] and entries[minIdx].name) or "empty")
						job.steps = job.steps + 1
						job.p = p + 1            -- slot p is final after this swap
						tSortSwapSlots(bag, p, minIdx)
						job.waiting = true
						tSortArmWatchdog()
						return                   -- wait for the bag to settle
					end
					p = p + 1
				end
				-- no swap needed through the rest of this bag -> bag done
				dprint("bagSort", "bag done", bag)
				job.bagIdx, job.p, job.steps = job.bagIdx + 1, 1, 0
			end
		end
	end)
	if not ok then
		if SkuErrorLog and SkuErrorLog.Log then pcall(function() SkuErrorLog:Log("bagSort", tostring(err)) end) end
		dprint("bagSort", "step error", tostring(err))
		tSortFinish("error")
	end
end

local function tSortOnEvent(self, event)
	if event == "BAG_UPDATE_DELAYED" and tSortJob and tSortJob.waiting then
		tSortJob.waiting = false
		if tSortJob.watchdog then pcall(function() tSortJob.watchdog:Cancel() end) tSortJob.watchdog = nil end
		dprint("bagSort", "settled (BAG_UPDATE_DELAYED)")
		tSortStep()
	end
end

-- Entry point for every sort/collapse menu action. mode = "collapse"|"quality"|"name",
-- dir = "asc"|"desc" (ignored for collapse), aBagId = a single bag or nil for all bags.
local function tSortStart(mode, dir, aBagId)
	if tSortJob then
		dprint("bagSort", "busy, ignoring request", mode, dir or "-", aBagId ~= nil and aBagId or "all")
		return
	end
	local bags = {}
	if aBagId ~= nil then
		bags[1] = aBagId
	else
		for q = 1, #tBagSlotListSorted do
			bags[#bags + 1] = tBagSlotListSorted[q]
		end
	end
	if not tSortDriver and _G.CreateFrame then
		tSortDriver = _G.CreateFrame("Frame")
		tSortDriver:SetScript("OnEvent", tSortOnEvent)
	end
	tSortJob = {
		bags = bags,
		bagIdx = 1,
		p = 1,
		steps = 0,
		before = tSortMakeBefore(mode, dir),
		waiting = false,
	}
	if tSortDriver then tSortDriver:RegisterEvent("BAG_UPDATE_DELAYED") end
	tIsProcessing = tIsProcessing + 1
	SkuCore.CursorSilent = true
	SkuOptions.Voice.TutorialPlaying = 1
	SortProcessingSoundHelper()
	dprint("bagSort", "start", "mode="..mode, "dir="..(dir or "-"),
		"bags="..(aBagId ~= nil and tostring(aBagId) or "all"))
	tSortStep()
end

-- Builds the 5 sort/cleanup leaf nodes under a "Sorting and cleanup" node. aBagId is a
-- single bag id, or nil for the top-level "all bags" variant. Node names/keys are
-- unchanged from the previous implementation.
local function BagSortMenuHelper(aParentChilds, aBagId)
	local function tAddSortNode(aName, aMode, aDir)
		table.insert(aParentChilds, aName)
		aParentChilds[aName] = {
			frameName = nil,
			RoC = "Child",
			type = "Button",
			textFirstLine = aName,
			textFull = "",
			noMenuNumbers = true,
			childs = {},
			func = function() tSortStart(aMode, aDir, aBagId) end,
		}
	end

	tAddSortNode(L["Remove empty bag slots (collapse)"], "collapse", nil)
	tAddSortNode(L["Sort items by quality"].." "..L["ascending"],  "quality", "asc")
	tAddSortNode(L["Sort items by quality"].." "..L["descending"], "quality", "desc")
	tAddSortNode(L["Sort items by name"].." "..L["ascending"],  "name", "asc")
	tAddSortNode(L["Sort items by name"].." "..L["descending"], "name", "desc")
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
		-- [v43.0] The keyring container reports its MAXIMUM (32) here, but most of
		-- those slots are unusable padding -- Blizzard's own keyring frame sizes
		-- itself with GetKeyRingSize() (filled slots rounded up to whole rows of 4),
		-- so mirror that instead of announcing dozens of phantom "Empty" slots.
		if bagId == -2 and _G.GetKeyRingSize then
			tNumSlots = GetKeyRingSize() or tNumSlots
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
			local _, tCount, tLocked = GetContainerItemInfo(bagId, slotId)
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
				local tText, tPending = getItemTooltipTextFromBagItem(bagId, slotId)
				if tPending then
					-- [v42.13] The client has not sent this item's data yet. Name it from
					-- what resolves offline, mark it as loading, and ASK for the data --
					-- the GET_ITEM_INFO_RECEIVED driver re-reads the entry when it lands.
					-- Never announce the placeholder itself: see SkuUtil:IsRetrievingItemInfo.
					SkuCore:RequestItemData(tItemId)
					isEmpty = false
					bagItemButton.textFirstLine = SkuCore:PendingItemLabel(tItemId, GetContainerItemLink(bagId, slotId))
					bagItemButton.textFull = { bagItemButton.textFirstLine }
				elseif tText then
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

			-- An item put into the OPEN trade window does NOT leave the bag: the client
			-- only flags the slot locked (Blizzard's own ContainerFrame reacts to
			-- ITEM_LOCK_CHANGED by merely desaturating the icon; the item is removed for
			-- real only when the trade COMPLETES). So the entry legitimately stays in this
			-- list -- which read as "the right-click did nothing". Mark it instead. Gated
			-- on the trade frame being open so the transient lock during an ordinary item
			-- move never adds noise.
			local tInTrade = (not isEmpty) and tLocked == true and _G["TradeFrame"] and _G["TradeFrame"]:IsVisible() == true
			bagItemButton.inTrade = tInTrade or nil

			if not isEmpty and tCount and tCount > 1 then
				bagItemButton.textFirstLine = bagItemButton.textFirstLine .. " " .. tCount
			end
			-- Plain name (no position number, no trade marker): what the flat "all items"
			-- copy shows and sorts on -- keeping the marker out of the sort key, the same
			-- way the "new" prefix is added only after the sort.
			local tPlainFirstLine = bagItemButton.textFirstLine

			-- position number prefix within the bag, then the trade marker: it reads as a
			-- PREFIX so the state is spoken before the item name, not tacked on at the end.
			bagItemButton.textFirstLine = (#tBagResultsByBag[bagId].childs + 1) .. " "
				.. (tInTrade and (L["TRADE_InTradeMarker"] .. " ") or "")
				.. tPlainFirstLine

			tBagResultsByBag[bagId].childs[#tBagResultsByBag[bagId].childs + 1] = bagItemButton
			-- non-empty items in the real bags also go into the flat "all items" list
			if not isEmpty and bagId >= 0 and bagId <= 4 then
				local copy = {}
				for k, v in pairs(bagItemButton) do
					copy[k] = v
				end
				copy.textFirstLine = tPlainFirstLine
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

	-- prepend "new" to all new items, then the trade marker so it ends up first in the
	-- spoken line here too. Both run AFTER the sort, so neither transient prefix moves
	-- the item out of its alphabetical place. (allBagResults holds every entry twice --
	-- once in the array part, once keyed by itself -- hence the already-prefixed guards.)
	for _, itemButton in pairs(allBagResults) do
		if itemButton.isNewItem then
			if not string.find(itemButton.textFirstLine, "^"..L["New"]) then
				itemButton.textFirstLine = L["New"] .. " " .. itemButton.textFirstLine
			end
		end
		if itemButton.inTrade and not itemButton.inTradeMarked then
			itemButton.inTradeMarked = true
			itemButton.textFirstLine = L["TRADE_InTradeMarker"] .. " " .. itemButton.textFirstLine
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
-- [Fix Nr17] Nach dem Umskillen zeigt der Blizzard-Talentrahmen weiter die zuvor
-- angezeigte Gruppe; Skus aktiver Builder liest diese Live-Widgets und braeuchte sonst
-- /reload. Darum den Rahmen erst auf die neue aktive Gruppe ziehen und neu zeichnen,
-- dann Skus Menue neu aufbauen. Alles pcall-geschuetzt (Blizzard-Interna).
local function tForcePlayerTalentFrameToActiveGroup()
	-- aktive Gruppe direkt ueber die API (Handler liegt vor den tGet*-Helfern)
	local tActive
	if _G.C_SpecializationInfo and _G.C_SpecializationInfo.GetActiveSpecGroup then
		local ok, v = pcall(_G.C_SpecializationInfo.GetActiveSpecGroup)
		if ok and type(v) == "number" then tActive = v end
	end
	if not tActive and _G.GetActiveTalentGroup then
		local ok, v = pcall(_G.GetActiveTalentGroup)
		if ok and type(v) == "number" then tActive = v end
	end
	-- 1) Ansicht auf die aktive Gruppe umschalten (Spec-Tabs, falls vorhanden)
	if tActive then
		local tTab = _G["PlayerSpecTab"..tostring(tActive)]
		if tTab and tTab.Click then pcall(function() tTab:Click() end) end
		local tPtf = _G["PlayerTalentFrame"]
		if type(tPtf) == "table" then
			pcall(function() tPtf.selectedPlayerSpec = tActive end)
			pcall(function() tPtf.talentGroup = tActive end)
		end
	end
	-- 2) Blizzard-Rahmen neu zeichnen
	if _G.PlayerTalentFrame_Refresh then pcall(_G.PlayerTalentFrame_Refresh)
	elseif _G.PlayerTalentFrame_Update then pcall(_G.PlayerTalentFrame_Update) end
end

function SkuCore:ACTIVE_TALENT_GROUP_CHANGED()
	if _G["PlayerTalentFrame"] and _G["PlayerTalentFrame"]:IsVisible() then
		tForcePlayerTalentFrameToActiveGroup()
		if SkuOptions and SkuOptions.IsMenuOpen and SkuOptions:IsMenuOpen() == true then
			C_Timer.After(0.3, function()
				-- vor dem Sku-Neuaufbau nochmal den Blizzard-Rahmen frisch zeichnen,
				-- damit die Live-Widgets die neue aktive Gruppe zeigen
				tForcePlayerTalentFrameToActiveGroup()
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
		-- [Fix Nr18] Der per groupIdx gelieferte tabName ist bei manchen Klassen (inaktive
		-- Gruppe) eine Zahl statt des Baumnamens. Die drei Talentbaeume heissen in beiden
		-- Spezialisierungen gleich, daher den echten lokalisierten Namen vom Blizzard-
		-- Reiterknopf PlayerTalentFrameTab{tab} holen; groupIdx nur fuer die Punkte.
		local tRealName
		local tTabBtn = _G["PlayerTalentFrameTab"..tab]
		if tTabBtn and tTabBtn.GetText then tRealName = tTabBtn:GetText() end
		if not tRealName or tRealName == "" or tostring(tRealName):match("^%d+$") then
			local okName, n2 = pcall(_G.GetTalentTabInfo, tab)
			if okName and type(n2) == "string" and not n2:match("^%d+$") then tRealName = n2 end
		end
		if tRealName and tRealName ~= "" and not tostring(tRealName):match("^%d+$") then tabName = tRealName end
		if ok2 and tabName then
			local tTabLabel = L["Tab"] .. " " .. tostring(tabName) .. " (" .. (points or 0) .. ")"
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
			-- GetText() can be nil while the talent frame is still initialising; a nil
			-- key here threw "table index is nil" (LocalMenu.lua BugGrabber entry). Fall
			-- back to a generic tab name so the node is still built.
			local tFriendlyName = tttFirst or (L["Tab"].." "..x)
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

		-- [v42.12] Read the tooltip Blizzard would show for a paperdoll stat
		-- frame and return it as ONE plain string.
		--
		-- Why not GetButtonTooltipLines: that helper pipes the scan through
		-- SkuCore:ItemName_helper, whose SECOND return (the "long form") is
		-- deliberately EMPTY whenever the text fits on one line -- which is most
		-- of a stat tooltip's headline. We want every line verbatim here.
		--
		-- Why NumLines/GameTooltipTextLeft|Right instead of :GetRegions(): the
		-- stat tooltips are full of AddDoubleLine (spell school breakdowns,
		-- weapon speed/damage/dps). GetRegions() hands back the left column and
		-- the right column as two separate runs, which would read as "Holy Fire
		-- Nature ... 120 118 118". Walking the named line font strings keeps
		-- each pair together.
		local function tReadStatFrameTooltip(aFrame)
			if not aFrame then return "" end
			GameTooltip:ClearLines()
			local tOnEnter = aFrame:GetScript("OnEnter")
			if tOnEnter then
				if not pcall(tOnEnter, aFrame) then
					GameTooltip:ClearLines()
				end
			end

			local tLines = {}
			for i = 1, GameTooltip:NumLines() do
				local tLeft = _G["GameTooltipTextLeft"..i]
				local tRight = _G["GameTooltipTextRight"..i]
				local tLeftText = tLeft and tLeft:GetText()
				local tRightText = tRight and tRight:IsShown() and tRight:GetText()
				if tLeftText and tLeftText ~= "" and tRightText and tRightText ~= "" then
					tLines[#tLines + 1] = tLeftText..": "..tRightText
				elseif tLeftText and tLeftText ~= "" then
					tLines[#tLines + 1] = tLeftText
				elseif tRightText and tRightText ~= "" then
					tLines[#tLines + 1] = tRightText
				end
			end

			GameTooltip:SetOwner(UIParent, "Center")
			GameTooltip:Hide()
			local tOnLeave = aFrame:GetScript("OnLeave")
			if tOnLeave then
				pcall(tOnLeave, aFrame)
			end

			if #tLines == 0 then return "" end
			return SkuUtil:Unescape(table.concat(tLines, "\r\n"))
		end

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

			for i, v in ipairs(tStatFrames) do
				local tFrameName = v
				local tFrame = _G[tFrameName]
				local tLabel, tValue = _G[v.."Label"], _G[v.."StatText"]
				if tFrame and tLabel and tValue then
					local tFriendlyName = SkuUtil:Unescape((tLabel:GetText() or "").." "..(tValue:GetText() or ""))
					-- [v42.12] Each Era stat has its OWN frame, already carrying the
					-- tooltip Blizzard last wrote, so there is no shared state to
					-- reset -- just read it.
					table.insert(tParentStats, tFriendlyName)
					tParentStats[tFriendlyName] = {
						frameName = tFrameName,
						RoC = "Child",
						type = "Button",
						obj = _G[tFrameName],
						textFirstLine = tFriendlyName,
						textFull = tReadStatFrameTooltip(tFrame),
						childs = {},
						--click = true,
					}
				end
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
			
			-- [v42.12] TBC drives all 29 stats through ONE shared widget
			-- (PlayerStatFrameLeft1), and the Blizzard setters leave their state
			-- ON that widget: .tooltip/.tooltip2 for the generic
			-- PaperDollStatTooltip, plus .bonusDamage/.spellCrit/.damage/... for
			-- the four stats that install their own OnEnter handler. No setter
			-- clears what the previous one left, and four of them overwrite
			-- OnEnter without ever putting it back -- Blizzard's own
			-- UpdatePaperdollStats re-points OnEnter at PaperDollStatTooltip
			-- before every group for exactly that reason (PaperDollFrame.lua,
			-- "reset any OnEnter scripts that may have been changed").
			--
			-- Sku never did that reset, so a tooltip read here would have handed
			-- stat N-1's text to stat N. That is why the read was commented out
			-- and every TBC stat leaf shipped with an empty textFull: the whole
			-- Stats branch (Zauberschaden, Zaubertrefferwertung, Ausdauer, ...)
			-- had a name but no readable description, while Resistances -- which
			-- have one dedicated frame each -- did.
			local function tPrepStatFrame()
				local tFrame = PlayerStatFrameLeft1
				if not tFrame then return nil end
				tFrame:SetScript("OnEnter", PaperDollStatTooltip)
				tFrame.tooltip, tFrame.tooltip2 = nil, nil
				tFrame.bonusDamage, tFrame.minModifier = nil, nil
				tFrame.spellCrit, tFrame.minCrit = nil, nil
				tFrame.damage, tFrame.dps, tFrame.attackSpeed = nil, nil, nil
				tFrame.offhandDamage, tFrame.offhandDps, tFrame.offhandAttackSpeed = nil, nil, nil
				return tFrame
			end

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
				-- ipairs, not pairs: within a group the setters are ORDER
				-- dependent (PaperDollFrame_SetRangedAttackSpeed reads the
				-- PaperDollFrame.noRanged flag that SetRangedDamage sets).
				for i1, v1 in ipairs(v) do
					-- Option 2 (live values): precompile this stat's PaperDoll
					-- setter once, then re-run it on demand to read the current
					-- value when the user lands on the entry. Same Blizzard
					-- setter the build used, re-read off the shared stat frame.
					-- Second return = the stat's tooltip, so the description the
					-- user reads is as current as the value they hear.
					local tStatFn = loadstring(v1)
					local tLiveName = function()
						if not tStatFn then return nil end
						local tFrame = tPrepStatFrame()
						if not tFrame then return nil end
						if not pcall(tStatFn) then return nil end
						local tLabel = PlayerStatFrameLeft1Label:GetText()
						if not tLabel or tLabel == "" then return nil end
						local tName = SkuUtil:Unescape(tLabel.." "..(PlayerStatFrameLeft1StatText:GetText() or ""))
						return tName, tReadStatFrameTooltip(tFrame)
					end

					local tFriendlyName, tFullText = tLiveName()
					dprint("charstats", tostring(i), tostring(tFriendlyName), "tooltip chars", tostring(tFullText and #tFullText or 0))
					if tFriendlyName then
						local tFrameName = v

						table.insert(tParentStatsValues, tFriendlyName)
						tParentStatsValues[tFriendlyName] = {
							frameName = tFrameName,
							RoC = "Child",
							type = "Button",
							obj = _G[tFrameName],
							textFirstLine = tFriendlyName,
							textFull = tFullText or "",
							childs = {},
							liveName = tLiveName,
							--click = true,
						}
					end
				end
			end

			-- Hand the shared widget back in the state Blizzard expects, so a
			-- real mouse hover on the paperdoll does not inherit the last stat
			-- we probed.
			if PlayerStatFrameLeft1 then
				PlayerStatFrameLeft1:SetScript("OnEnter", PaperDollStatTooltip)
			end
			if PaperDollFrame_UpdateStats then
				pcall(PaperDollFrame_UpdateStats)
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
							-- aQuiet: the index-based re-anchor inside CheckFrames may land
							-- anywhere after the skill list changed; only the identity re-pin
							-- below is spoken.
							pcall(function() SkuCore:CheckFrames(nil, nil, true) end)
							C_Timer.After(0.35, function()
								pcall(function()
									local tTarget = _G["ClassTrainerTrainButton"]
										and _G["ClassTrainerTrainButton"]:IsVisible()
										and _G["ClassTrainerTrainButton"]:IsEnabled()
										and _G["ClassTrainerTrainButton"]:GetText()
									if tTarget and SkuOptions.currentMenuPosition then
										tTarget = SkuUtil:Unescape(tTarget)
										-- CheckFrames re-anchors by INDEX, so after training the
										-- cursor can sit on any entry of the trainer window level
										-- (or on the window node itself). Search the level the
										-- cursor is on (siblings) AND its children, by name.
										local function tFindIn(aList)
											if type(aList) ~= "table" then return nil end
											for _, child in ipairs(aList) do
												if child.name == tTarget then
													return child
												end
											end
										end
										local tPos = SkuOptions.currentMenuPosition
										local tHit = (tPos.parent and tFindIn(tPos.parent.children))
											or tFindIn(tPos.children)
										if tHit then
											SkuOptions.currentMenuPosition = tHit
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

	-- Menue neu aufbauen und den Cursor per Name wieder auf denselben Eintrag setzen.
	-- Zweimal gebraucht (Handeln + Sicherheitsabfrage), deshalb einmal hier.
	local tRebuildAndRepin = function(aName)
		C_Timer.After(0.5, function()
			pcall(function() SkuCore:CheckFrames() end)
			C_Timer.After(0.35, function()
				pcall(function()
					if SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.children then
						for _, child in ipairs(SkuOptions.currentMenuPosition.children) do
							if child.name == aName then
								SkuOptions.currentMenuPosition = child
								break
							end
						end
					end
					SkuOptions:VocalizeCurrentMenuName()
				end)
			end)
		end)
	end

	-- Sicherheitsabfrage (Blizzards SecureTransferDialog). Nur vorhanden, solange der Server
	-- sie tatsaechlich verlangt -- siehe SkuCore:SECURE_TRANSFER_CONFIRM_TRADE_ACCEPT. Steht
	-- direkt VOR "Handeln", weil der Nutzer in genau dem Moment dort steht: der Handel wurde
	-- gerade bestaetigt und ist stattdessen in dieser zweiten Abfrage gelandet.
	if SkuCore._tSecureTradePending == true then
		local tSecureName = L["TRADE_SecureConfirmNode"]
		table.insert(aParentChilds, tSecureName)
		aParentChilds[tSecureName] = {
			frameName = "TradeSecureConfirm",
			RoC = "Child",
			type = "Button",
			obj = _G["TradeFrame"],
			textFirstLine = tSecureName,
			textFull = L["TRADE_SecureConfirmBlocked"],
			childs = {},
			func = function()
				SkuCore:SecureTradeConfirm()
				tRebuildAndRepin(L["TRADE_SecureConfirmNode"])
			end,
		}
	end

	-- Handeln-Button (AcceptTrade)
	if _G["TradeFrameTradeButton"] and _G["TradeFrameTradeButton"]:IsVisible() then
		local tAcceptName = L["TRADE_Accept"]
		-- Zusatzinfo auf dem Eintrag selbst: eine offene Sicherheitsabfrage bzw. ein nach
		-- einer Bestaetigung geaendertes Angebot sind der Grund, wenn "Handeln" nichts tut.
		local tAcceptDetail = ""
		if SkuCore._tSecureTradePending == true then
			tAcceptDetail = L["TRADE_SecureConfirmNeeded"]
		elseif SkuCore._tTradeOfferWarned == true then
			tAcceptDetail = L["TRADE_OfferChangedWarning"]
		end
		table.insert(aParentChilds, tAcceptName)
		aParentChilds[tAcceptName] = {
			frameName = "TradeFrameTradeButton",
			RoC = "Child",
			type = "Button",
			obj = _G["TradeFrameTradeButton"],
			textFirstLine = tAcceptName,
			textFull = tAcceptDetail,
			childs = {},
			func = function()
				-- Haengt eine Sicherheitsabfrage, ist NICHT der Handelsknopf der richtige
				-- Knopf -- der bleibt sichtbar und wirkungslos. Enter auf "Handeln" bedient
				-- dann das, was tatsaechlich auf eine Antwort wartet; sonst muesste der
				-- Nutzer erst raten, dass es einen zweiten Eintrag gibt.
				if SkuCore._tSecureTradePending == true then
					SkuCore:SecureTradeConfirm()
					tRebuildAndRepin(L["TRADE_Accept"])
					return
				end
				-- Deaktiviert ist der Knopf, solange die eigene Bestaetigung schon steht
				-- (TradeFrame_SetAcceptState) oder das eingetippte Gold das eigene Vermoegen
				-- uebersteigt. Ein Klick darauf ist folgenlos, also sagen statt schweigen.
				-- Der Grund kommt aus SkuCore:TradeAcceptBlockedReason, damit Menue und
				-- SKU_KEY_TRADEACCEPT dieselbe Auskunft geben.
				local tReason = SkuCore:TradeAcceptBlockedReason()
				if tReason then
					pcall(function() SkuOptions.Voice:OutputStringBTtts(tReason, true, true, 0.2, nil, nil, nil, 2) end)
					return
				end
				_G["TradeFrameTradeButton"]:Click()
				-- Kein "Handel bestaetigt" mehr an dieser Stelle: der Klick ist nur eine
				-- Anfrage. Bestaetigt wird ueber TRADE_ACCEPT_UPDATE (playerAccepted == 1)
				-- angesagt, abgelehnt ueber die Sicherheitsabfrage.
				pcall(function() SkuOptions.Voice:OutputStringBTtts(L["TRADE_WaitingConfirm"], true, true, 0.2, nil, nil, nil, 2) end)
				tRebuildAndRepin(L["TRADE_Accept"])
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
-- [Filter] Zustand des Ressourcen-Filters pro Charakter und Beruf (Standard Aus).
function SkuCore:GetResourceFilterState(aProf)
	local t = SkuSettings and SkuSettings:Sub("SkuCore", nil, "char")
	if not t then return false end
	t.resourceFilter = t.resourceFilter or {}
	return t.resourceFilter[aProf] == true
end
function SkuCore:SetResourceFilterState(aProf, aVal)
	local t = SkuSettings and SkuSettings:Sub("SkuCore", nil, "char")
	if not t then return end
	t.resourceFilter = t.resourceFilter or {}
	t.resourceFilter[aProf] = aVal and true or false
end

-- [Filter] Fuegt oben im Berufefenster den Umschalter "Filter: Ressourcen vorhanden" ein.
-- Enter schaltet Ein/Aus und sagt den neuen Zustand. Standard Aus, gemerkt pro Beruf und
-- Charakter. TradeSkill nutzt Blizzards Makeable-Filter; Craft/Verzauberkunst filtert der
-- Builder selbst ueber numAvailable. Tierausbildung bekommt keinen Filter.
function SkuCore:AddResourceFilterToggle(aParentChilds, aProf, aApi)
	if not aParentChilds then return end
	local tState = SkuCore:GetResourceFilterState(aProf)
	local tBase = L["Filter Ressourcen vorhanden"]
	local tLabel = tBase..": "..(tState and L["On"] or L["Off"])
	table.insert(aParentChilds, tLabel)
	aParentChilds[tLabel] = {
		frameName = "",
		RoC = "Child",
		type = "Button",
		obj = _G["UIParent"],
		textFirstLine = tLabel,
		textFull = "",
		childs = {},
		directAction = true,
		func = function()
			local tNew = not SkuCore:GetResourceFilterState(aProf)
			SkuCore:SetResourceFilterState(aProf, tNew)
			if aApi == "trade" and _G.TradeSkillOnlyShowMakeable then
				pcall(_G.TradeSkillOnlyShowMakeable, tNew)
				SkuCore.resFilterApplied = SkuCore.resFilterApplied or {}
				SkuCore.resFilterApplied["ts:"..aProf] = tNew
			end
			pcall(function() SkuOptions.Voice:OutputStringBTtts(tBase..": "..(tNew and L["On"] or L["Off"]), false, true, 0.2, true) end)
			if _G.C_Timer then _G.C_Timer.After(0.15, function() pcall(function() SkuCore:CheckFrames() end) end) end
		end,
	}
end

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

	-- [Filter] Gespeicherten Zustand beim Oeffnen anwenden (schleifensicher ueber
	-- resFilterApplied) und den Umschalter ganz oben einhaengen.
	local tProf = (_G["TradeSkillFrameTitleText"] and _G["TradeSkillFrameTitleText"]:GetText()) or "TradeSkill"
	SkuCore.resFilterApplied = SkuCore.resFilterApplied or {}
	local tWant = SkuCore:GetResourceFilterState(tProf)
	if _G.TradeSkillOnlyShowMakeable and SkuCore.resFilterApplied["ts:"..tProf] ~= tWant then
		pcall(_G.TradeSkillOnlyShowMakeable, tWant)
		SkuCore.resFilterApplied["ts:"..tProf] = tWant
	end
	SkuCore:AddResourceFilterToggle(aParentChilds, tProf, "trade")



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

				if aParentChilds[tFriendlyName] and tDifficulty ~= "subheader" and tDifficulty ~= "header" then
					aParentChilds[tFriendlyName].textFirstLine = aParentChilds[tFriendlyName].textFirstLine.." ("..(tDifficulty or "")..")"
					-- [Rezept-Tooltip] echten Rezept-Index (GetID der sichtbaren Listenzeile)
					-- merken, damit Shift Runter Materialien und Ergebnis per API lesen kann.
					aParentChilds[tFriendlyName].skuRecipeInfo = { api = "trade", index = _G[tFrameName]:GetID() }
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

	-- [Fix 42.06] Verzauberkunst bekommt den Umschalter, Tierausbildung nicht. ALLES
	-- pcall-geschuetzt, damit ein unerwartetes API-Verhalten auf diesem Backport (z.B.
	-- GetCraftSkillLine) das Craft-Fenster-Menue niemals crasht.
	local tCraftProf = "Craft"
	local tIsBeast = false
	pcall(function()
		if _G.GetCraftSkillLine then
			local okS, v = pcall(_G.GetCraftSkillLine)
			if okS and type(v) == "string" and v ~= "" then tCraftProf = v end
		end
		if tCraftProf == "Craft" and _G["CraftFrameTitleText"] and _G["CraftFrameTitleText"].GetText then
			local t = _G["CraftFrameTitleText"]:GetText()
			if t and t ~= "" then tCraftProf = t end
		end
		tIsBeast = (_G["CraftFramePointsText"] and _G["CraftFramePointsText"]:IsVisible() == true) and true or false
	end)
	if not tIsBeast then
		pcall(function() SkuCore:AddResourceFilterToggle(aParentChilds, tCraftProf, "craft") end)
	end

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
			-- [Filter] Bei aktivem Filter nicht-herstellbare Verzauberungen ueberspringen
			-- (numAvailable == 0); Header/Kategorien bleiben. Nur ausserhalb Tierausbildung.
			local tFilterSkip = false
			if (not tIsBeast) and SkuCore:GetResourceFilterState(tCraftProf) then
				local okc, _, _, cType, cAvail = pcall(_G.GetCraftInfo, _G[tFrameName]:GetID())
				if okc and cType ~= "header" and cType ~= "subheader" and (cAvail == nil or cAvail == 0) then
					tFilterSkip = true
				end
			end
			if (not tFilterSkip) and _G[tFrameName.."Text"]:GetText() then
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
					-- [Rezept-Tooltip] echten Craft-Index (GetID der sichtbaren Zeile) merken,
					-- damit Shift Runter Materialien und Ergebnis per API lesen kann.
					if aParentChilds[tFriendlyName] then
						aParentChilds[tFriendlyName].skuRecipeInfo = { api = "craft", index = _G[tFrameName]:GetID() }
					end
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
---------------------------------------------------------------------------------------------------------------------------------------
-- /skucheck -- in-game invariant sweeps ("every regression fix ships its tripwire").
-- [v43.0] This is NOT a scenario test suite: each check is a rule that must hold
-- in ANY valid live state, verified against the real client -- which is what
-- catches client quirks a mocked test would hide (the way SetBagItem populates
-- nothing for containers -1 and -2). Growth rule (agreed 2026-08-17): a new
-- invariant is added ONLY when a bug fix implies one, never speculatively.
-- Violations go to the SkuDebugLog ring as "skucheck" dprint lines; only a
-- one-line summary is spoken.
--
-- Invariant 1 (bags; from the v42.13 keyring regression): a container slot with
-- an item id must resolve to a speakable name. Id present but blank tooltip text
-- means the read path for that container is broken -- exactly how keyring keys
-- spoke as "Empty" while their ids and clicks worked fine.
local function tSkuCheckBags()
	local tChecked, tPending, tViolations = 0, 0, 0
	for q = 1, #tBagSlotListSorted do
		local tBagId = tBagSlotListSorted[q]
		local tNumSlots = GetContainerNumSlots(tBagId) or 0
		-- Same gate as Build_BagsFrame: the CLOSED bank still reports 28 slots but
		-- reads are not valid then -- sweeping it would only produce noise. Say so
		-- in the log instead of skipping silently.
		if tBagId == -1 and not (_G["BankFrame"] and _G["BankFrame"]:IsVisible() == true) then
			if tNumSlots > 0 then
				dprint("skucheck", "bags: bank (-1) skipped, bank closed")
			end
			tNumSlots = 0
		end
		-- Deliberately NO GetKeyRingSize clamp here: the sweep checks DATA, not the
		-- menu view, so all raw keyring slots are fair game (empty ones pass
		-- trivially, and a key parked beyond the display clamp must still resolve).
		for tSlotId = 1, tNumSlots do
			local tItemId = GetContainerItemID(tBagId, tSlotId)
			if tItemId then
				tChecked = tChecked + 1
				local tText, tIsPending = getItemTooltipTextFromBagItem(tBagId, tSlotId)
				if tIsPending then
					tPending = tPending + 1
				elseif not tText or tText == "" then
					tViolations = tViolations + 1
					dprint("skucheck", "VIOLATION bags: bag", tBagId, "slot", tSlotId, "itemId", tItemId, "link", GetContainerItemLink(tBagId, tSlotId) or "nil", "-- item id present but no name resolved")
				end
			end
		end
	end
	return tChecked, tPending, tViolations
end

-- Invariant 2 (auras; from the v43.0 evaluate-loop leak fix): EvaluateAllAuras
-- must not write globals. `tSpellNameOnCdValue` and `tLocalResult` leaked from
-- its attributes loop for years and injected STALE values across auras (an aura
-- without a spellNameOnCd condition could announce an earlier aura's cooldown
-- name). If either name reappears in _G after a session's evaluations, a leak
-- has regressed.
local tSkuCheckAuraGlobals = {"tSpellNameOnCdValue", "tLocalResult"}
local function tSkuCheckAuras()
	local tChecked, tViolations = 0, 0
	for x = 1, #tSkuCheckAuraGlobals do
		tChecked = tChecked + 1
		if rawget(_G, tSkuCheckAuraGlobals[x]) ~= nil then
			tViolations = tViolations + 1
			dprint("skucheck", "VIOLATION auras: global", tSkuCheckAuraGlobals[x], "leaked -- the evaluate loop wrote a global again")
		end
	end

	-- Tripwire tally (v43.0 "einmal" once-gate regression): an aura whose action is
	-- a single/"einmal" one AND which carries a bigger/smaller threshold is gated on
	-- a STATE, so it cannot legitimately fire twice inside one second. It did: the
	-- condition census was built INSIDE the evaluate loop, which breaks on the first
	-- false condition, so an aura that has a threshold looked like one that has none
	-- whenever an unrelated combat-log event failed a plain condition first -- and
	-- the no-threshold branch re-arms the gate unconditionally. SkuAuras counts every
	-- sub-second refire (SkuAuras/Core.lua, tSkuAuraLastSingleFire).
	local tRefires = (SkuAuras and SkuAuras.tSingleGateRefires) or 0
	tChecked = tChecked + 1
	if tRefires > 0 then
		tViolations = tViolations + tRefires
		dprint("skucheck", "VIOLATION auras:", tRefires,
			"once-gate refire(s) inside one second this session, last:",
			tostring(SkuAuras and SkuAuras.tSingleGateRefireLast))
	end

	return tChecked, 0, tViolations
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Invariant 3 (keybinds; from the v43.0 MENUQUICK1..4 regression): no two Sku
-- keybind consts may hold the same key. v42 wired four fixed actions onto the
-- SKU_KEY_MENUQUICK1..4 keys and returned before the generic quick-select loop
-- could see them, so one key served two consts, the four quick-access slots were
-- dead, and the fixed actions were only rebindable under a label that named the
-- slot. A key held by two consts is the machine-checkable shape of "this key does
-- not do what its menu entry says".
-- transientOverride consts are exempt BY DESIGN: the menu click keys and the
-- in-combat menu keys are armed only for a window and legally share their key
-- (see SkuOptions:SkuKeyBindsIsTransientOverride).
local function tSkuCheckKeys()
	local tChecked, tViolations = 0, 0
	local tStore = SkuSettings and SkuSettings:Sub("SkuOptions").SkuKeyBinds
	if not tStore then
		dprint("skucheck", "keys: no keybind store yet, skipped")
		return 0, 0, 0
	end
	local tSeen = {}
	for tConst in pairs(SkuOptions.skuDefaultKeyBindings) do
		if SkuOptions:SkuKeyBindsIsTransientOverride(tConst) ~= true then
			local tEntry = tStore[tConst]
			if tEntry then
				for _, tKey in ipairs({tEntry.key or "", tEntry.key2 or ""}) do
					if tKey ~= "" then
						tChecked = tChecked + 1
						if tSeen[tKey] then
							tViolations = tViolations + 1
							dprint("skucheck", "VIOLATION keys: key", tKey, "is held by BOTH", tSeen[tKey], "and", tConst, "-- one of the two cannot fire")
						else
							tSeen[tKey] = tConst
						end
					end
				end
			end
		end
	end
	return tChecked, 0, tViolations
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Invariant 4 (routes; from the 2026-08-20 per-section route builders,
-- ROUTE-LINK-BUILD-PLAN.md section 13): the route files define ONE builder per
-- top-level section and SkuDeferredData.lua picks the ones this flavour reads.
-- A wrong pick is silent -- half the link graph, or waypoints that never
-- arrive, look exactly like "the data is like that". So assert the shape:
--   1. no SkuDBBuildRoute* global survives EnsureData. That covers both halves
--      at once: a builder that was RUN is nil'ed after it succeeded, one that
--      was SKIPPED is nil'ed as unused -- so a survivor means a section the
--      selection does not know about (e.g. the wrapper emitted a new one and
--      nobody added it), still pinning its multi-MB source string.
--   2. the tables the nav path actually reads are present and non-empty.
--   3. per flavour: on TBC the WotLK LINKS are built and are the live union
--      table, and its waypoint half is absent; on Era the WotLK file is not
--      built at all.
local tSkuCheckRouteSections = {"WaypointsNew", "Waypoints", "SequenceNumbers", "WaypointLevels", "Links"}
local function tSkuCheckRoutes()
	local tChecked, tViolations = 0, 0
	if not (Sku.IsDataReady and Sku:IsDataReady("routes")) then
		dprint("skucheck", "routes: route data not built yet - skipped")
		return 0, 1, 0
	end
	local tCheck = function(aOk, aWhat)
		tChecked = tChecked + 1
		if not aOk then
			tViolations = tViolations + 1
			dprint("skucheck", "VIOLATION routes:", aWhat)
		end
	end
	local tNames = {"SkuDBBuildRouteWotlk", "SkuDBBuildRouteGlobal"}
	for x = 1, #tSkuCheckRouteSections do
		tNames[#tNames + 1] = "SkuDBBuildRouteWotlk"..tSkuCheckRouteSections[x]
		tNames[#tNames + 1] = "SkuDBBuildRouteGlobal"..tSkuCheckRouteSections[x]
	end
	for x = 1, #tNames do
		tCheck(rawget(_G, tNames[x]) == nil, "builder global "..tNames[x].." still alive after EnsureData -- it was neither built nor listed as unused, and its source blob stays pinned")
	end
	local tCount = function(aTable)
		if type(aTable) ~= "table" then return -1 end
		local c = 0
		for _ in pairs(aTable) do c = c + 1 end
		return c
	end
	local tGlobal = SkuDB and SkuDB.routedata and SkuDB.routedata["global"]
	local tSession = SkuDB and SkuDB.SessionRouteData
	tCheck(tCount(tSession and tSession.Waypoints) > 0, "SessionRouteData.Waypoints is empty -- the Era waypoint section was not built")
	tCheck(tCount(tSession and tSession.Links) > 0, "SessionRouteData.Links is empty -- no link section was built")
	tCheck(tCount(tGlobal and tGlobal.WaypointLevels) > 0, "routedata.global.WaypointLevels is empty -- GetWaypointLevel would answer nil for every waypoint")
	if Sku.isTBC then
		local tTmp = type(SkuDBTMP) == "table" and SkuDBTMP.routedata and SkuDBTMP.routedata["global"]
		if type(tTmp) ~= "table" then tTmp = nil end
		tCheck(tTmp ~= nil, "SkuDBTMP.routedata.global missing on TBC -- the WotLK link section was not built")
		tCheck(tTmp ~= nil and tTmp.Links ~= nil and tTmp.Links == (tSession and tSession.Links), "the live SessionRouteData.Links is not the WotLK link table -- the union did not happen")
		tCheck(tTmp == nil or tTmp.WaypointsNew == nil, "the WotLK waypoint half is present on TBC -- it is never read, it should not be built")
	else
		tCheck(SkuDBTMP == nil, "SkuDBTMP exists outside TBC -- the WotLK file is unused on this flavour and should not be built at all")
	end
	return tChecked, 0, tViolations
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Invariant 5 (menu; from the v43.0 "route list finished loading" regression):
-- inside a BUILT level, every child must carry the same selectTarget as the
-- level itself. That pointer is what makes ENTER on a leaf run the owning
-- list's OnAction (SkuGenericMenuItem.OnPostSelect); a child with a nil/foreign
-- one silently degrades to "step up a level, do nothing" -- which is exactly
-- what the waypoint push-refresh produced by rebuilding the children with a raw
-- children={} + BuildChildren instead of SkuOptions:RebuildNodeChildren.
-- Three parts, because a pure tree sweep is nearly always empty: dynamic levels
-- free their children when you leave them and the quick roots exist only for
-- their session, so nothing is built by the time a slash command can be typed.
--   1. live sweep over whatever IS built (read-only, never builds a level),
--   2. a rebuild probe on a throwaway level - the fix's contract, always runs,
--   3. the session tally of ENTERs that hit a leaf with no selectTarget under a
--      select level (the tripwire in SkuGenericMenuItem.OnPostSelect).
local function tSkuCheckMenu()
	local tChecked, tViolations = 0, 0
	local tWalk
	tWalk = function(aNode, aDepth)
		if aDepth > 12 or type(aNode) ~= "table" or type(aNode.children) ~= "table" then
			return
		end
		for x = 1, #aNode.children do
			local tChild = aNode.children[x]
			if type(tChild) == "table" then
				-- A child that is itself a select/multiselect level legitimately OWNS
				-- its target (OnPostSelect re-points it to itself on descent), so only
				-- a MISSING target is a violation.
				if aNode.selectTarget and tChild.isSelect ~= true and tChild.isMultiselect ~= true then
					tChecked = tChecked + 1
					if tChild.selectTarget == nil then
						tViolations = tViolations + 1
						dprint("skucheck", "VIOLATION menu: child", tostring(tChild.name), "of", tostring(aNode.name),
							"has no selectTarget -- expected", tostring(aNode.selectTarget.name),
							"; ENTER on it would run no action and only step up")
					end
				end
				tWalk(tChild, aDepth + 1)
			end
		end
	end
	if SkuOptions and SkuOptions.Menu then
		for x = 1, #SkuOptions.Menu do
			tWalk(SkuOptions.Menu[x], 1)
		end
	end
	local tSweepChecked = tChecked
	if tSweepChecked == 0 then
		-- Not a pass: dynamic levels drop their children when you leave them and the
		-- Shift-F9/F10 quick roots exist only during their session, so by the time a
		-- slash command can be typed the built tree is usually empty. Say so instead
		-- of reporting a silent, meaningless "no problems".
		dprint("skucheck", "menu: no built levels in the tree right now - the live sweep had nothing to look at")
	end

	-- Contract probe (always runs, so this domain is never vacuous): the fix for
	-- the loading-route-list bug IS SkuOptions:RebuildNodeChildren handing every
	-- fresh child the level's selectTarget. Rebuild a throwaway select level and
	-- verify it. Touches nothing live - the probe node is local and discarded.
	if SkuOptions and SkuOptions.RebuildNodeChildren and SkuGenericMenuItem then
		local tProbe = {name = "skucheckProbe", children = {}, isSelect = true, dynamic = true}
		tProbe.BuildChildren = function(self)
			SkuOptions:InjectMenuItems(self, {"skucheckProbeA", "skucheckProbeB"}, SkuGenericMenuItem)
		end
		local ok = pcall(function() SkuOptions:RebuildNodeChildren(tProbe) end)
		tChecked = tChecked + 1
		if not ok or #tProbe.children ~= 2 or tProbe.selectTarget ~= tProbe then
			tViolations = tViolations + 1
			dprint("skucheck", "VIOLATION menu: rebuild probe -- built", #tProbe.children, "children, level selectTarget",
				tostring(tProbe.selectTarget == tProbe), "-- expected 2 children and the level pointing at itself")
		else
			for x = 1, #tProbe.children do
				tChecked = tChecked + 1
				if tProbe.children[x].selectTarget ~= tProbe then
					tViolations = tViolations + 1
					dprint("skucheck", "VIOLATION menu: rebuild probe -- child", x, "got no selectTarget from the level; ENTER below such a level would do nothing but step up")
				end
			end
			-- and the keep-mode used by the live/volatile refresh must NOT re-seed the
			-- target (that would discard what the user already selected) but must
			-- still re-propagate it.
			local tKeepTarget = {name = "skucheckProbeTarget"}
			tProbe.selectTarget = tKeepTarget
			pcall(function() SkuOptions:RebuildNodeChildren(tProbe, true) end)
			tChecked = tChecked + 1
			if tProbe.selectTarget ~= tKeepTarget or (tProbe.children[1] and tProbe.children[1].selectTarget ~= tKeepTarget) then
				tViolations = tViolations + 1
				dprint("skucheck", "VIOLATION menu: rebuild probe -- keep mode lost the existing selectTarget")
			end
		end
	end

	-- Invariant (from the v43.0 path-walk regression): a path walk must never close
	-- the menu on a node that has a BuildChildren -- that node is a LEVEL, and closing
	-- the menu also closes every open interact window (the flightmaster's own gossip
	-- frame, which is how this surfaced).
	local tLeafCloses = (SkuOptions and SkuOptions.tMenuLeafCloseMisses) or 0
	if tLeafCloses > 0 then
		tViolations = tViolations + tLeafCloses
		dprint("skucheck", "VIOLATION menu:", tLeafCloses,
			"path walk(s) closed the menu on an unbuilt level this session, last:",
			tostring(SkuOptions.tMenuLeafCloseLast))
	end
	tChecked = tChecked + 1

	-- Tripwire tally: every ENTER this session that landed on a leaf with no
	-- selectTarget under a select level (SkuGenericMenuItem.OnPostSelect logs the
	-- detail). This is the shape the loading-route-list bug had in the live client.
	local tMisses = (SkuOptions and SkuOptions.tMenuSelectTargetMisses) or 0
	if tMisses > 0 then
		tViolations = tViolations + tMisses
		dprint("skucheck", "VIOLATION menu:", tMisses, "dead ENTER(s) this session, last:",
			tostring(SkuOptions.tMenuSelectTargetLast))
	end
	dprint("skucheck", "menu: live sweep checked", tSweepChecked, "built children,", tMisses, "dead ENTERs this session")
	return tChecked, 0, tViolations
end

-- [2026-08-19] The SkuDB verification tools are domains here now (wp / db /
-- mem, SkuDBTools.lua), not commands of their own: with three separate slash
-- commands it was possible to run "the check" and never touch the waypoint
-- invariants - which happened. They are BACKGROUND jobs, so they speak their
-- own summary when they finish instead of joining the count below.
--   wp  = waypoint cache + link graph. Part of a bare /skucheck (~9 s).
--   db  = dataset fingerprints (~40 s) - opt-in only, it is a measurement.
--   mem = memory ranking - opt-in only, same reason.
local tSkuCheckDomains = {
	bags = true, auras = true, keys = true, menu = true, taxi = true,
	routes = true, wp = true, db = true, mem = true,
}

SLASH_SKUCHECK1 = "/skucheck"
SlashCmdList["SKUCHECK"] = function(aParam)
	local tDomain, tArg = string.match(aParam or "", "^%s*(%S*)%s*(.-)%s*$")
	if tDomain ~= "" and not tSkuCheckDomains[tDomain] then
		pcall(function() SkuOptions.Voice:OutputStringBTtts(Sku.deEn("Unbekannte Prüfung. Verfügbar: bags, auras, keys, menu, taxi, routes, wp, db, mem", "Unknown check. Available: bags, auras, keys, menu, taxi, routes, wp, db, mem", "Vérification inconnue. Disponible : bags, auras, keys, menu, taxi, routes, wp, db, mem"), false, true, 0.2) end)
		return
	end
	-- the two measurement domains never run as part of a sweep: they are
	-- explicitly asked for, they take 40 s, and they answer with numbers to
	-- compare out of game rather than with a verdict.
	if tDomain == "db" or tDomain == "mem" then
		if not SkuDBTools then return end
		if tDomain == "db" then
			SkuDBTools.RunDbCheck(tArg ~= "" and tArg or nil)
		else
			SkuDBTools.RunMem()
		end
		return
	end
	local tChecked, tPending, tViolations = 0, 0, 0
	if tDomain == "" or tDomain == "bags" then
		local c, p, v = tSkuCheckBags()
		dprint("skucheck", "bags done:", c, "filled slots checked,", p, "pending,", v, "violations")
		tChecked, tPending, tViolations = tChecked + c, tPending + p, tViolations + v
	end
	if tDomain == "" or tDomain == "auras" then
		local c, p, v = tSkuCheckAuras()
		dprint("skucheck", "auras done:", c, "globals checked,", v, "violations")
		tChecked, tPending, tViolations = tChecked + c, tPending + p, tViolations + v
	end
	if tDomain == "" or tDomain == "keys" then
		local c, p, v = tSkuCheckKeys()
		dprint("skucheck", "keys done:", c, "bound keys checked,", v, "violations")
		tChecked, tPending, tViolations = tChecked + c, tPending + p, tViolations + v
	end
	if tDomain == "" or tDomain == "menu" then
		local c, p, v = tSkuCheckMenu()
		dprint("skucheck", "menu done:", c, "menu checks,", v, "violations")
		tChecked, tPending, tViolations = tChecked + c, tPending + p, tViolations + v
	end
	if tDomain == "" or tDomain == "routes" then
		local c, p, v = tSkuCheckRoutes()
		dprint("skucheck", "routes done:", c, "route-data checks,", p, "pending,", v, "violations")
		tChecked, tPending, tViolations = tChecked + c, tPending + p, tViolations + v
	end
	-- taxi: an early landing is never the flight's own start or end point
	-- (SkuCore/taxi.lua, Taxi.SkuCheck).
	if (tDomain == "" or tDomain == "taxi") and SkuCore.Taxi and SkuCore.Taxi.SkuCheck then
		local c, p, v = SkuCore.Taxi.SkuCheck()
		dprint("skucheck", "taxi done:", c, "taxi checks,", v, "violations")
		tChecked, tPending, tViolations = tChecked + c, tPending + (p or 0), tViolations + v
	end
	-- Keep the TESTED per-domain wording for an explicit `/skucheck bags`; the
	-- combined (no-arg) run and the auras domain speak the generic label.
	local tLabel
	if tDomain == "bags" then
		tLabel = Sku.deEn("Taschenprüfung: ", "Bag check: ", "Vérification des sacs : ")
	else
		tLabel = Sku.deEn("Sku-Prüfung: ", "Sku check: ", "Vérification Sku : ")
	end
	local tMsg
	if tViolations == 0 then
		tMsg = tLabel..tChecked..Sku.deEn(" geprüft, keine Probleme", " checked, no problems", " vérifiés, aucun problème")
	else
		tMsg = tLabel..tViolations..Sku.deEn(" Probleme, siehe Log", " problems, see log", " problèmes, voir le journal")
	end
	if tPending > 0 then
		tMsg = tMsg..", "..tPending..Sku.deEn(" ausstehend", " pending", " en attente")
	end
	-- `/skucheck wp` alone speaks only the waypoint job's own summary; the
	-- combined run speaks this one first and the job's when it finishes.
	if tDomain ~= "wp" then
		pcall(function() SkuOptions.Voice:OutputStringBTtts(tMsg, false, true, 0.2) end)
	end
	-- The waypoint sweep is a real invariant check, so a bare /skucheck runs it
	-- too - as a background job (~9 s over ~145k records), announced on its own
	-- when it is done. It declines politely while the cache is still building.
	if (tDomain == "" or tDomain == "wp") and SkuDBTools and SkuDBTools.RunWpCheck then
		SkuDBTools.RunWpCheck()
	end
end
