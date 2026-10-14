---------------------------------------------------------------------------------------------------------------------------------------
-- Merchant window on WoW Forever, built from the merchant API.
-- The generic frame scan finds no readable item tooltips there (the scanning tooltip has no SetMerchantItem), so
-- SkuCore.interactFramesListManual (SkuCore/Core.lua) points MerchantFrame at Build_MerchantFrame on Forever.
-- Three parts: wares, buyback and repair.
--
-- Buying: Enter on a ware buys the remembered amount at once, Arrow right opens a submenu (enter an amount and buy,
-- remember the amount, a full stack, as many as possible). Before buying, money, stock, bag space and extended costs are
-- checked; expensive and extended-cost wares ask for a confirmation like Blizzard's window does; afterwards the real
-- result is read back from the bag count and the money. Amounts count in single items; wares sold in packs (for
-- example arrows by 200) are always bought and entered in whole packs.
---------------------------------------------------------------------------------------------------------------------------------------
if not Sku.isForever then return end

local L = Sku.L
local GetContainerNumFreeSlots = Sku.Compat.GetContainerNumFreeSlots

-- Same threshold as Blizzard's MERCHANT_HIGH_PRICE_COST: from 150 gold the window asks first.
local HIGH_PRICE_COST = 1500000

local function tSay(aText)
	SkuOptions.Voice:OutputStringBTtts(aText, true, true, 0.2, nil, nil, nil, 2)
end

local function tCoin(aCopper)
	return SkuGetCoinText(aCopper, true)
end

-- Remembered buy amounts per ware, account wide.
local function tAmounts()
	local tGlobal = SkuSettings:Sub("SkuCore", nil, "global")
	tGlobal.merchantBuyAmounts = tGlobal.merchantBuyAmounts or {}
	return tGlobal.merchantBuyAmounts
end

local function tItemCount(aLink)
	if type(aLink) ~= "string" then return 0 end
	return C_Item.GetItemCount(aLink, false, false, true) or 0
end

-- Fresh data of one ware: name, price, pack size, stock, usable, extended cost, link, item id.
local function tWareInfo(aIndex)
	local t = { link = GetMerchantItemLink(aIndex) }
	local tData = C_MerchantFrame.GetItemInfo(aIndex)
	if tData then
		t.name, t.price, t.quantity, t.available, t.usable, t.extended = tData.name, tData.price, tData.stackCount, tData.numAvailable, tData.isUsable, tData.hasExtendedCost
	end
	if not t.name and t.link then t.name = string.match(t.link, "%[(.-)%]") end
	t.quantity = math.max(1, tonumber(t.quantity) or 1)
	t.price = tonumber(t.price) or 0
	t.itemID = t.link and tonumber(string.match(t.link, "item:(%d+)")) or nil
	return t
end

-- Extended cost: its text, and how many packs the items in the bags pay for (nil = unknown, e.g. currencies).
local function tExtendedCost(aIndex, aStack)
	local tParts, tAfford = {}, nil
	for i = 1, GetMerchantItemCostInfo(aIndex) or 0 do
		local _, tValue, tLink, tCurrency = GetMerchantItemCostItem(aIndex, i)
		if tValue then
			tParts[#tParts + 1] = tValue .. " " .. (tCurrency or (type(tLink) == "string" and string.match(tLink, "%[(.-)%]")) or "?")
			if tLink and not tCurrency then
				local tCan = math.floor(tItemCount(tLink) / (tValue / aStack))
				tAfford = tAfford and math.min(tAfford, tCan) or tCan
			end
		end
	end
	return table.concat(tParts, ", "), tAfford
end

-- Room for this ware in the normal bags, in items: free slots times the stack size, plus what still fits on a
-- partly filled stack. Special bags do not count (only bag family 0).
local function tBagRoom(aLink, aStackSize)
	if type(aStackSize) ~= "number" or aStackSize < 1 then return nil end
	local tFree = 0
	for tBag = 0, 4 do
		local tNum, tFamily = GetContainerNumFreeSlots(tBag)
		if tNum and (tFamily == nil or tFamily == 0) then tFree = tFree + tNum end
	end
	local tTop = (aStackSize - (tItemCount(aLink) % aStackSize)) % aStackSize
	return tFree * aStackSize + tTop
end

-- The most items that can be bought now: affordable, in stock and fitting into the bags (whole packs only).
-- Second return: true when the bag room sets the limit.
local function tMaxAffordable(aIndex, aInfo)
	local tCan = 100000
	if aInfo.price > 0 then
		tCan = math.floor(GetMoney() / (aInfo.price / aInfo.quantity))
	end
	if aInfo.extended then
		local _, tAfford = tExtendedCost(aIndex, aInfo.quantity)
		if tAfford then tCan = math.min(tCan, tAfford) end
	end
	-- numAvailable counts packs, -1 is unlimited
	if type(aInfo.available) == "number" and aInfo.available >= 0 then
		tCan = math.min(tCan, aInfo.available * aInfo.quantity)
	end
	local tMaxStack = GetMerchantItemMaxStack(aIndex) or 0
	local tRoom = tBagRoom(aInfo.link, tMaxStack > 0 and tMaxStack or aInfo.quantity)
	local tRoomLimited = false
	if tRoom and tRoom < tCan then
		tCan = tRoom
		tRoomLimited = true
	end
	return math.max(0, math.floor(tCan / aInfo.quantity) * aInfo.quantity), tRoomLimited
end

-- The last error line the game printed while a purchase ran ("Inventory is full" and the like).
local tErrorFrame, tLastError
local function tErrorStart()
	tLastError = nil
	if not tErrorFrame then
		tErrorFrame = CreateFrame("Frame")
		tErrorFrame:SetScript("OnEvent", function(_, _, _, aMessage)
			if type(aMessage) == "string" then tLastError = aMessage end
		end)
	end
	tErrorFrame:RegisterEvent("UI_ERROR_MESSAGE")
end

-- Buy. aWanted = items wanted (nil = one pack).
function SkuCore:MerchantBuy(aIndex, aWanted)
	local tInfo = tWareInfo(aIndex)
	if not tInfo.name then
		tSay(L["This item is no longer for sale."])
		return
	end
	local tStack = tInfo.quantity
	local tMaxStack = math.max(GetMerchantItemMaxStack(aIndex) or 0, tStack)

	local tAmount = math.max(tStack, math.ceil((tonumber(aWanted) or tStack) / tStack) * tStack)
	local tPossible, tRoomLimited = tMaxAffordable(aIndex, tInfo)
	if tPossible < tStack then
		if tRoomLimited then
			tSay(tInfo.name .. ": " .. L["not enough bag space"])
		elseif type(tInfo.available) == "number" and tInfo.available == 0 then
			tSay(tInfo.name .. ": " .. L["sold out"])
		else
			tSay(tInfo.name .. ": " .. (tInfo.extended and L["not enough materials"] or L["not enough money"]))
		end
		return
	end
	local tNote = ""
	if tAmount > tPossible then
		tAmount = tPossible
		tNote = (tRoomLimited and L["Only this many fit in your bags: "] or L["Only this many possible: "]) .. tAmount .. ". "
	end

	local tTotal = tInfo.price * (tAmount / tStack)
	local tExtText = tInfo.extended and tExtendedCost(aIndex, tStack) or ""
	local tCostText = (tExtText ~= "") and tExtText or ((tTotal > 0) and tCoin(tTotal) or "")

	local function tDoBuy()
		local tCountBefore, tMoneyBefore = tItemCount(tInfo.link), GetMoney()
		tErrorStart()
		local tRemaining, tCalls = tAmount, 0
		while tRemaining > 0 and tCalls < 60 do
			local tChunk = math.max(tStack, math.floor(math.min(tRemaining, tMaxStack) / tStack) * tStack)
			if tChunk == tStack then BuyMerchantItem(aIndex) else BuyMerchantItem(aIndex, tChunk) end
			tRemaining = tRemaining - tChunk
			tCalls = tCalls + 1
		end
		dprint("merchantBuy", "sent", tInfo.name, "items", tAmount, "calls", tCalls)
		-- Say nothing before the bag count and the money have shown what really happened.
		C_Timer.After(1.0, function()
			tErrorFrame:UnregisterEvent("UI_ERROR_MESSAGE")
			local tGained = tItemCount(tInfo.link) - tCountBefore
			local tSpent = tMoneyBefore - GetMoney()
			dprint("merchantBuy", "result", tInfo.name, "wanted", tAmount, "got", tGained, "paid", tSpent, "error", tostring(tLastError))
			if tGained >= tAmount or (tGained <= 0 and tSpent > 0 and not tInfo.link) then
				SkuOptions.Voice:OutputStringBTtts("sound-notification24", false, true)
				local tText = L["Gekauft"] .. ": " .. tAmount .. " x " .. tInfo.name
				if tSpent > 0 then tText = tText .. ", " .. tCoin(tSpent) end
				tSay(tNote .. tText)
			elseif tGained > 0 then
				tSay(string.format(L["Only %d of %d x %s bought"], tGained, tAmount, tInfo.name) .. (tLastError and (". " .. tLastError) or ""))
			else
				tSay(tInfo.name .. ": " .. L["nothing bought"] .. (tLastError and (". " .. tLastError) or ""))
			end
		end)
	end

	-- Ask first for extended costs and expensive wares, like Blizzard's window.
	if tInfo.extended or tTotal >= HIGH_PRICE_COST then
		local tAsk = L["Really buy? "] .. tAmount .. " x " .. tInfo.name
			.. ((tCostText ~= "") and (", " .. tCostText) or "") .. L[". Enter Yes, Escape for No."]
		PlaySound(88)
		C_Timer.After(0.5, function()
			SkuCore:ConfirmButtonShow(tAsk,
				function()
					PlaySound(89)
					tDoBuy()
				end,
				function()
					tSay(L["Abgebrochen"])
				end)
			SkuOptions.Voice:OutputStringBTtts(tAsk, true, true, 0.1, nil, nil, nil, 2)
		end)
		return
	end
	tDoBuy()
end

-- Ask for an amount in an edit box. aMode "buy": buy that amount at once (not remembered). aMode "save": remember it as
-- the buy amount of this ware (Enter on the ware then buys it). An empty or invalid entry resets to one pack when
-- saving and cancels when buying. For wares sold in packs the entry counts packs.
function SkuCore:MerchantPromptAmount(aIndex, aMode)
	local tInfo = tWareInfo(aIndex)
	if not tInfo.name then return end
	local tKey = tInfo.itemID or tInfo.name
	local tStack = tInfo.quantity
	local tCurItems = tAmounts()[tKey] or tStack
	local tPacked = tStack > 1
	local tCurShown = tPacked and math.floor(tCurItems / tStack) or tCurItems
	local tUnit = tPacked and string.format(L[" packs of %d"], tStack) or ""
	PlaySound(88)
	local tPrompt = L["Enter amount"] .. tUnit
	if aMode == "buy" then
		tPrompt = tPrompt .. L[", press Enter to buy"]
	else
		tPrompt = tPrompt .. L[", currently "] .. tCurShown
	end
	SkuOptions.Voice:OutputStringBTtts(tPrompt, false, true, 0.2)
	SkuOptions:EditBoxShow(tostring(tCurShown), function()
		PlaySound(89)
		local tN = math.floor(tonumber(SkuOptionsEditBoxEditBox:GetText() or "") or 0)
		local tItems = tPacked and (tN * tStack) or tN
		if aMode == "buy" then
			if tN < 1 then
				tSay(L["Abgebrochen"])
			else
				-- one tick later: the edit box is only fully closed once the menu has the focus back
				C_Timer.After(0.2, function() SkuCore:MerchantBuy(aIndex, tItems) end)
			end
			return
		end
		if tN < 1 then
			tAmounts()[tKey] = nil
			tSay(tInfo.name .. ": " .. L["buy amount reset to "] .. tStack)
		else
			tAmounts()[tKey] = tItems
			tSay(tInfo.name .. ": " .. L["Buy amount"] .. " " .. tItems .. (tPacked and (" (" .. tN .. tUnit .. ")") or ""))
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- The item tooltip of a link, from the tooltip data API (no tooltip frame needed). nil while the item is not cached;
-- the data is asked for then, and the next rebuild finds it.
local function tLinkText(aLink)
	if type(aLink) ~= "string" then return nil end
	local tBare = string.match(aLink, "|H(item:[^|]+)|h") or string.match(aLink, "(item:[%d:%-]+)") or aLink
	local tLines = SkuCore:TooltipDataLines(C_TooltipInfo.GetHyperlink(tBare))
	if not tLines then
		local tId = tonumber(string.match(tBare, "item:(%d+)"))
		if tId then C_Item.RequestLoadItemDataByID(tId) end
		return nil
	end
	return SkuUtil:Unescape(table.concat(tLines, "\r\n"))
end

-- One menu entry. With aFunc it is a click entry; quietClick runs the quiet menu refresh after the click
-- (SkuCore:RefreshWindowMenuQuietly), so the menu stays on the entry after a purchase.
local function tEntry(aLabel, aFull, aFunc)
	local tNode = {
		RoC = "Child",
		type = "Button",
		textFirstLine = aLabel,
		textFull = aFull or "",
		childs = {},
		noMenuNumbers = true,
	}
	if aFunc then
		tNode.click = true
		tNode.quietClick = true
		tNode.func = aFunc
	end
	return tNode
end

local function tAddChild(aParent, aNode)
	table.insert(aParent.childs, aNode)
	aParent.childs[aNode] = aNode
end

local function tSection(aParentChilds, aLabel)
	local tNode = tEntry(aLabel, "", nil)
	table.insert(aParentChilds, aLabel)
	aParentChilds[aLabel] = tNode
	return tNode
end

local function tBuildWare(aIndex)
	local tInfo = tWareInfo(aIndex)
	if not tInfo.name or tInfo.name == "" then return nil end
	local tLabel = tInfo.name
	if tInfo.quantity > 1 then tLabel = tLabel .. " x" .. tInfo.quantity end
	if tInfo.price > 0 then
		tLabel = tLabel .. ", " .. tCoin(tInfo.price)
	elseif tInfo.extended then
		tLabel = tLabel .. ", " .. L["extended cost"]
	end
	if type(tInfo.available) == "number" and tInfo.available >= 0 then
		tLabel = tLabel .. " (" .. tInfo.available .. " " .. L["available"] .. ")"
	end
	if tInfo.usable == false then tLabel = tLabel .. " (" .. L["not usable"] .. ")" end

	local tFull = { tLinkText(tInfo.link) or tInfo.name }
	if tInfo.price > 0 then
		tFull[#tFull + 1] = L["Price"] .. ": " .. tCoin(tInfo.price)
	end
	local tKey = tInfo.itemID or tInfo.name
	local tSaved = tAmounts()[tKey]
	if tSaved and tSaved ~= tInfo.quantity then
		tLabel = tLabel .. " " .. L["Buy amount"] .. " " .. tSaved
	end
	local tNode = tEntry(tLabel, tFull, function()
		SkuCore:MerchantBuy(aIndex, tAmounts()[tKey])
	end)
	-- The label carries the price and changes with every purchase, so pin the cursor by index.
	tNode.skuIdentity = "merchantware" .. aIndex

	tAddChild(tNode, tEntry(L["Enter amount and buy"], "", function()
		SkuCore:MerchantPromptAmount(aIndex, "buy")
	end))
	tAddChild(tNode, tEntry(L["Remember buy amount"], "", function()
		SkuCore:MerchantPromptAmount(aIndex, "save")
	end))

	local tPossible = tMaxAffordable(aIndex, tInfo)
	local tMaxStack = GetMerchantItemMaxStack(aIndex) or 0
	if tMaxStack > tInfo.quantity and tPossible >= tMaxStack then
		tAddChild(tNode, tEntry(L["Buy a full stack: "] .. tMaxStack, "", function()
			SkuCore:MerchantBuy(aIndex, tMaxStack)
		end))
	end
	if tPossible > tInfo.quantity and tPossible ~= tMaxStack then
		tAddChild(tNode, tEntry(L["Buy as many as I can afford and fit: "] .. tPossible, "", function()
			SkuCore:MerchantBuy(aIndex, tPossible)
		end))
	end
	return tNode
end

function SkuCore:Build_MerchantFrame(aParentChilds)
	-- the merchant's name as the first, read-only line
	local tMerchantName = UnitName("npc")
	if not tMerchantName or tMerchantName == "" then tMerchantName = L["Merchant"] end
	table.insert(aParentChilds, tMerchantName)
	aParentChilds[tMerchantName] = {
		frameName = "MerchantFrame", RoC = "Child", type = "FontString", obj = _G["MerchantFrame"],
		textFirstLine = tMerchantName, textFull = "", childs = {},
	}

	-- wares
	local tWares = tSection(aParentChilds, L["Wares"])
	for i = 1, GetMerchantNumItems() do
		local tNode = tBuildWare(i)
		if tNode then tAddChild(tWares, tNode) end
	end
	if #tWares.childs == 0 then
		tAddChild(tWares, tEntry(L["Menu empty"], "", nil))
	end

	-- buyback
	local tBuyback = tSection(aParentChilds, L["Buyback"])
	for i = 1, GetNumBuybackItems() do
		local tName, _, tPrice, tQuantity = GetBuybackItemInfo(i)
		if tName and tName ~= "" then
			local tLabel = tName
			if tQuantity and tQuantity > 1 then tLabel = tLabel .. " x" .. tQuantity end
			if tPrice and tPrice > 0 then tLabel = tLabel .. ", " .. tCoin(tPrice) end
			local tFull = { tLinkText(GetBuybackItemLink(i)) or tName }
			if tPrice and tPrice > 0 then tFull[#tFull + 1] = L["Price"] .. ": " .. tCoin(tPrice) end
			tAddChild(tBuyback, tEntry(tLabel, tFull, function()
				BuybackItem(i)
				SkuOptions.Voice:OutputStringBTtts("sound-notification24", false, true)
			end))
		end
	end
	if #tBuyback.childs == 0 then
		tAddChild(tBuyback, tEntry(L["Menu empty"], "", nil))
	end

	-- repair, where this merchant can
	if CanMerchantRepair() then
		local tCost = GetRepairAllCost() or 0
		local tRepair = tSection(aParentChilds, L["Repair"])
		local tLabel = L["Repair all"]
		if tCost > 0 then tLabel = tLabel .. ", " .. tCoin(tCost) end
		tAddChild(tRepair, tEntry(tLabel, "", function()
			RepairAllItems()
			SkuOptions.Voice:OutputStringBTtts("sound-notification24", false, true)
		end))
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Sometimes the bags do not open with the merchant window (Blizzard's MerchantFrame_OnShow asks for OpenAllBags and gets
-- nothing, last seen at the first merchant after the game start), and the menu then holds only the merchant part.
-- SkuCore:MERCHANT_SHOW is not registered as an event on purpose (the menu is built through ShowUIPanel), so this frame
-- listens on its own. If the bags are still closed shortly after the window opened, open them (not in combat).
local tBagsFrame = CreateFrame("Frame")
tBagsFrame:RegisterEvent("MERCHANT_SHOW")
tBagsFrame:SetScript("OnEvent", function()
	C_Timer.After(0.4, function()
		if InCombatLockdown() or not MerchantFrame:IsVisible() then return end
		local tBags = _G["ContainerFrame1"]
		if tBags:IsVisible() then return end
		dprint("merchantBags", "bags closed, opening them")
		OpenAllBags()
		if not tBags:IsVisible() then
			for tBag = 0, NUM_BAG_SLOTS do
				if Sku.Compat.GetContainerNumSlots(tBag) > 0 then OpenBag(tBag) end
			end
		end
		if not tBags:IsVisible() then OpenBackpack() end
		SkuCore:CheckFrames()
	end)
end)
