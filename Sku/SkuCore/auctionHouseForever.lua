---@diagnostic disable: undefined-global
-- =====================================================================
-- Auction house on WoW Forever (Camelot): AuctionHouseFrame / C_AuctionHouse.
-- SkuCore/auctionHouse.lua is built on the OLD classic Blizzard_AuctionUI (AuctionFrame, GetOwnerAuctionItems,
-- PlaceAuctionBid, ...), none of which exists on Forever: there AuctionFrame is nil and AuctionHouseFrame and
-- C_AuctionHouse are present, the same modern auction house as on retail.
--
-- This file is the Forever-only replacement and a no-op on every other client (early return below). It has its own
-- frame and does not use the AceEvent mixin of SkuCore.AuctionHouse.
--
-- Menu: Auctions > [search by name, by category, favorites, filters]; Sales > [new auction, my auctions]; My bids.
-- Browse: name search or category tree (Blizzard's own AuctionCategories), cheapest price and quantity per item.
-- Detail: the individual listings of one item with tooltip; buy at buyout (items), two-step price quote (commodities),
--   bid below buyout, favorites.
-- Sell: pick an item from the bags, quantity, duration, price, deposit, market price hint, post (with the posting warning).
-- Own auctions and own bids: list, cancel.
-- Protected calls (PlaceBid, StartCommoditiesPurchase, PostItem, PostCommodity, ConfirmCommoditiesPurchase, ...)
-- only run from a menu action, i.e. from a real key press.
-- Not built: a full-market scan. Blizzard's own auction house does not call ReplicateItems either.
-- =====================================================================

if not Sku or not Sku.isForever then return end

local L = Sku.L
local GetCoinText = Sku.Compat.GetCoinText

SkuCore.AuctionHouseForever = SkuCore.AuctionHouseForever or {}
local AHF = SkuCore.AuctionHouseForever

-- ---------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------
-- Browse = the name search's result list (one row per distinct item).
local gBrowse = { state = "idle", results = {}, searchText = nil, entry = nil }
-- Detail = the individual listings of ONE item, opened by drilling into a
-- browse row.
local gDetail = { state = "idle", itemKey = nil, isCommodity = false, results = {}, entry = nil }
-- CommodityBuy = the two-step quote/confirm dance StartCommoditiesPurchase
-- requires (see Blizzard's own Blizzard_AuctionHouseBuyDialog.lua).
local gCommodityBuy = { itemID = nil, quantity = nil, unitPrice = nil, totalPrice = nil, entry = nil }
-- NOTE: there is no full-market scan. C_AuctionHouse.ReplicateItems is documented, but Blizzard's own new auction
-- house UI never calls ReplicateItems/GetReplicateItemInfo, it only has name search and category browse. Sku does
-- not pretend to have more.

local function tMoneyText(aCopper)
	return GetCoinText(aCopper, " ")
end

-- Shared small helpers (used by browse, detail, bids, sell and own auctions below).
local function tSay(aText)
	SkuOptions.Voice:OutputStringBTtts(aText, false, true, 0.2)
end

local function tHours(aN)
	return aN.." "..L["hours"]
end

-- Time left of an auction: exact seconds when the server sends them, else Blizzard's band
-- (AuctionHouseTimeLeftBand 0..3: short .. very long).
local function tTimeLeftText(aInfo)
	local tSec = aInfo.timeLeftSeconds
	if tSec and tSec > 0 then
		if tSec >= 3600 then return tHours(math.floor(tSec / 3600 + 0.5)) end
		return math.max(1, math.floor(tSec / 60 + 0.5)).." "..L["minutes"]
	end
	local tBand = aInfo.timeLeft
	if tBand ~= nil then
		return ({
			[0] = L["under 30 minutes"],
			[1] = L["under 2 hours"],
			[2] = L["under 12 hours"],
			[3] = L["over 12 hours"],
		})[tBand] or ""
	end
	return ""
end

-- A menu leaf that changes something in place (value toggles, "load more", ...).
local function tSettingLeaf(aParent, aName, aOnAction)
	local tE = SkuOptions:InjectMenuItems(aParent, {aName}, SkuGenericMenuItem)
	tE.dynamic = false
	tE.actionInPlace = true
	tE.OnAction = aOnAction
	return tE
end

local function tIsOwnGuid(aGuid)
	return aGuid ~= nil and aGuid == UnitGUID("player")
end

local function tVocalize()
	SkuOptions:VocalizeCurrentMenuName()
end

-- "12g 5s 3k", "12 gold 5 silber", "1.5" (= 1g 50s), plain number = gold
local function tParseMoney(aText)
	if type(aText) ~= "string" then return nil end
	local tS = aText:lower():gsub(",", "."):gsub("^%s+", ""):gsub("%s+$", "")
	if tS == "" then return nil end
	local tPlain = tonumber(tS)
	local tTotal
	if tPlain then
		tTotal = math.floor(tPlain * 10000 + 0.5)
	else
		tTotal = 0
		for tNum, tUnit in tS:gmatch("(%d+)%s*(%a*)") do
			local tC = tUnit:sub(1, 1)
			local tN = tonumber(tNum)
			if tC == "g" then tTotal = tTotal + tN * 10000
			elseif tC == "s" then tTotal = tTotal + tN * 100
			elseif tC == "k" or tC == "c" then tTotal = tTotal + tN end
		end
	end
	if not tTotal or tTotal <= 0 then return nil end
	local tCopper = C_AuctionHouse.SupportsCopperValues()
	if not tCopper then tTotal = math.max(100, math.floor(tTotal / 100 + 0.5) * 100) end
	return tTotal
end

-- Asks for a money amount in the edit box ("12g 5s 3k", "1.5" = 1 gold 50 silver) and hands the
-- parsed copper value to aApply. Only the answer is read here - anything protected (bids,
-- buying, posting) happens afterwards in a separate menu action from a real key press.
local function tAskMoney(aPrompt, aApply)
	SkuOptions:EditBoxShow("", function()
		local tText = SkuOptionsEditBoxEditBox:GetText()
		if tText and tText ~= "" then
			local tAmount = tParseMoney(tText)
			if tAmount then
				aApply(tAmount)
			else
				tSay(L["Amount not understood"])
			end
		end
		tVocalize()
	end, nil)
	C_Timer.After(0.1, function()
		SkuOptions.Voice:OutputStringBTtts(aPrompt, true, true, 0.1, nil, nil, nil, 1)
	end)
end

-- ---------------------------------------------------------------------
-- Rebuilds aEntry's children after a server answer and keeps the cursor sensible.
-- SkuOptions:RebuildNodeChildren gives the fresh children their selectTarget wiring; a raw
-- "children = {}; BuildChildren" does not, and ENTER on such children does nothing.
-- The rebuild replaces every child with a new node, so a cursor on an old child would sit on an
-- orphan. Therefore:
-- - The cursor is on a child (or deeper) whose node has a skuIdentity, and the new list has a child
--   with the same identity: the old node takes the new node's place and gets its fields, keeping
--   its own children. The cursor does not move and nothing is spoken.
-- - Otherwise, when the cursor is on aEntry, below it, or aForce is set: the cursor goes to the
--   child flagged ahfPrimary (else the first child) and that child is spoken. A cursor that was
--   deeper than a child lands there silently: the row it was inside is gone.
-- aQuiet: never speak (a key press caller, whose key handler speaks the position anyway).
local function tAdoptNode(aOld, aNew, aParent, aIndex)
	for tKey in pairs(aOld) do
		if tKey ~= "children" and rawget(aNew, tKey) == nil then aOld[tKey] = nil end
	end
	for tKey, tValue in pairs(aNew) do
		if tKey ~= "children" then aOld[tKey] = tValue end
	end
	aParent.children[aIndex] = aOld
	if aOld.prev then aOld.prev.next = aOld end
	if aOld.next then aOld.next.prev = aOld end
end

local function tRebuildAndFocus(aEntry, aForce, aQuiet)
	if not aEntry then return end
	local tPos = SkuOptions.currentMenuPosition
	-- The child of aEntry on the cursor's path (nil when the cursor is not below aEntry).
	local tChild, tDepth = tPos, 0
	while tChild and tChild.parent ~= aEntry and tDepth < 12 do
		tChild = tChild.parent
		tDepth = tDepth + 1
	end
	if tChild and tChild.parent ~= aEntry then tChild = nil end
	local tIdentity = tChild and tChild.skuIdentity
	SkuOptions:RebuildNodeChildren(aEntry, true)
	if tIdentity then
		for i, tNew in ipairs(aEntry.children) do
			if tNew.skuIdentity == tIdentity then
				tAdoptNode(tChild, tNew, aEntry, i)
				return
			end
		end
	end
	if not (aForce or tPos == aEntry or tChild) or not aEntry.children[1] then return end
	local tTarget = aEntry.children[1]
	for _, tNew in ipairs(aEntry.children) do
		if tNew.ahfPrimary then tTarget = tNew break end
	end
	SkuOptions.currentMenuPosition = tTarget
	if not aQuiet and not (tChild and tPos ~= tChild) then
		SkuOptions:VocalizeCurrentMenuName()
	end
end

-- Sku calls BuildChildren on a node merely LANDED on (cursor passes over it),
-- not only when the user enters it. A builder that starts a server query then
-- fires queries for every entry you walk past, and when the answer arrives
-- tRebuildAndFocus pulls the cursor into that entry's children. Entering goes
-- through OnPostSelect, so mark the node as "entering" only during that call;
-- query-starting builders check ahfEntering and stay passive otherwise.
local function tMarkEntering(aNode)
	local tOrig = aNode.OnPostSelect or SkuGenericMenuItem.OnPostSelect
	aNode.OnPostSelect = function(self, ...)
		self.ahfEntering = true
		local tArgs = { n = select("#", ...), ... }
		xpcall(function() tOrig(self, unpack(tArgs, 1, tArgs.n)) end, geterrorhandler())
		self.ahfEntering = nil
	end
end

-- ---------------------------------------------------------------------
-- BROWSE (search by name OR by category - both are just a browse query with
-- different fields set: a name search sets searchString, a category browse
-- sets itemClassFilters with an empty searchString. Same result shape, same
-- state, same result-list UI either way.)
-- ---------------------------------------------------------------------
-- aSend (optional): replaces the plain SendBrowseQuery call, e.g. SearchForFavorites - the
-- answer arrives through the same browse events and is read the same way.
function AHF:StartBrowseQuery(aQuery, aEntry, aSend)
	gBrowse.state = "waiting"
	gBrowse.results = {}
	gBrowse.focusIndex = nil
	gBrowse.entry = aEntry
	gBrowse.searchText = (type(aQuery.searchString) == "string" and aQuery.searchString ~= "") and aQuery.searchString or nil
	gBrowse.localFilter = nil
	gBrowse.generation = (gBrowse.generation or 0) + 1
	local tGen = gBrowse.generation
	-- The game throttles auction house queries: a query sent while the system is not ready vanishes without any
	-- feedback. Such a query is kept and sent on AUCTION_HOUSE_THROTTLED_SYSTEM_READY.
	local tReady = C_AuctionHouse.IsThrottledMessageSystemReady()
	if tReady == false then
		gBrowse.pendingSend = { aQuery, aSend }
	else
		gBrowse.pendingSend = nil
		local tSend = aSend or C_AuctionHouse.SendBrowseQuery
		tSend(aQuery)
	end
	-- Safety net: AUCTION_HOUSE_BROWSE_FAILURE (no matches, or the query is
	-- refused for some other server-side reason) is not always guaranteed to
	-- fire, and there is no positive "zero results" signal distinct from
	-- "no signal at all yet". Without this, a failed/empty query left the
	-- menu stuck on "Warten" forever (seen live: a typed
	-- a search and it never resolved). aGeneration guards against a LATE
	-- timeout firing after a newer search already replaced this one.
	-- Results sometimes arrive without an event: read what the game holds after the query anyway.
	C_Timer.After(3, function()
		if gBrowse.generation ~= tGen then return end
		local tRaw = C_AuctionHouse.GetBrowseResults()
		local tFull = C_AuctionHouse.HasFullBrowseResults()
		-- Treffer ohne Ereignis trotzdem lesen
		if type(tRaw) == "table" and #tRaw > 0 and gBrowse.state == "waiting" then
			AHF:RefreshBrowseResults()
		end
	end)
	C_Timer.After(10, function()
		if gBrowse.generation == tGen and gBrowse.state == "waiting" then
			gBrowse.pendingSend = nil
			if AHF:BrowseFallback() then return end
			gBrowse.state = "done"
			tRebuildAndFocus(gBrowse.entry)
		end
	end)
end

-- ---------------------------------------------------------------------
-- FILTER (Blizzard: the filter menu next to the search). Applies to name search and categories, saved per character.
-- Fields: usable, upgrades, uncollected, currentExp, exact (name search only), minQuality (1 = any .. 7), minLevel, maxLevel.
-- ---------------------------------------------------------------------
function AHF:GetFilter()
	local tS = SkuSettings:Sub("SkuCore", nil, "char")
	tS.ahfFilter = tS.ahfFilter or {}
	return tS.ahfFilter
end

local AHF_QUALITY_FILTERS = { "PoorQuality", "CommonQuality", "UncommonQuality", "RareQuality", "EpicQuality", "LegendaryQuality", "ArtifactQuality" }

-- Adds the filters to the query table. aIsName: name search ("filters" is always set there, the search needs the empty field).
function AHF:ApplyFilterToQuery(aQuery, aIsName)
	local f = AHF:GetFilter()
	local E = _G.Enum and Enum.AuctionHouseFilter
	local tList = {}
	if E then
		if f.usable and E.UsableOnly then tList[#tList + 1] = E.UsableOnly end
		if f.upgrades and E.UpgradesOnly then tList[#tList + 1] = E.UpgradesOnly end
		if f.uncollected and E.UncollectedOnly then tList[#tList + 1] = E.UncollectedOnly end
		if f.currentExp and E.CurrentExpansionOnly then tList[#tList + 1] = E.CurrentExpansionOnly end
		if f.exact and aIsName and E.ExactMatch then tList[#tList + 1] = E.ExactMatch end
		if (f.minQuality or 1) > 1 then
			for i = f.minQuality, #AHF_QUALITY_FILTERS do
				local tV = E[AHF_QUALITY_FILTERS[i]]
				if tV then tList[#tList + 1] = tV end
			end
		end
	end
	if aIsName or #tList > 0 then aQuery.filters = tList end
	if f.minLevel then aQuery.minLevel = f.minLevel end
	if f.maxLevel then aQuery.maxLevel = f.maxLevel end
end

local function tQualityName(aIndex)
	return _G["ITEM_QUALITY"..((aIndex or 1) - 1).."_DESC"] or tostring(aIndex)
end

-- Short text of the active filters (nil when none is active)
function AHF:FilterSummary()
	local f = AHF:GetFilter()
	local tP = {}
	if f.usable then tP[#tP + 1] = L["usable only"] end
	if f.upgrades then tP[#tP + 1] = L["upgrades only"] end
	if f.uncollected then tP[#tP + 1] = L["uncollected only"] end
	if f.currentExp then tP[#tP + 1] = L["current expansion only"] end
	if f.exact then tP[#tP + 1] = L["exact name"] end
	if (f.minQuality or 1) > 1 then tP[#tP + 1] = L["quality from "]..tQualityName(f.minQuality) end
	if f.minLevel then tP[#tP + 1] = L["from level "]..f.minLevel end
	if f.maxLevel then tP[#tP + 1] = L["up to level "]..f.maxLevel end
	if #tP == 0 then return nil end
	return table.concat(tP, ", ")
end

function AHF:StartBrowse(aSearchText, aEntry)
	-- itemClassFilters/filters explicitly empty: without these fields the name search always returned 0 results on Forever.
	local tQuery = { searchString = aSearchText, sorts = {}, itemClassFilters = {}, filters = {} }
	AHF:ApplyFilterToQuery(tQuery, true)
	local tSummary = AHF:FilterSummary()
	if tSummary then tSay(L["Filters active: "]..tSummary) end
	AHF:StartBrowseQuery(tQuery, aEntry)
end

-- The player's favourite items (Blizzard: the star in the search bar). Same result shape as a
-- name search, so it feeds the same list.
function AHF:StartFavorites(aEntry)
	AHF:StartBrowseQuery({ sorts = {} }, aEntry, function(aQuery)
		return C_AuctionHouse.SearchForFavorites(aQuery.sorts)
	end)
end

-- aFilters: one category's accumulated {classID, subClassID, inventoryType}
-- list (see AuctionCategories in the menu section below) - every level of
-- the category tree carries its own, from the leaf up to the top category.
function AHF:StartCategoryBrowse(aFilters, aEntry)
	local tQuery = { searchString = "", itemClassFilters = aFilters, sorts = {} }
	AHF:ApplyFilterToQuery(tQuery, false)
	local tSummary = AHF:FilterSummary()
	if tSummary then tSay(L["Filters active: "]..tSummary) end
	AHF:StartBrowseQuery(tQuery, aEntry)
end

-- Re-reads the full current browse result set. The new API always hands
-- back the complete set on GetBrowseResults() (not a delta), so both the
-- "…UPDATED" (full refresh) and "…ADDED" (incremental) events funnel here.
function AHF:RefreshBrowseResults()
	if gBrowse.state == "idle" then return end
	local tRaw = C_AuctionHouse.GetBrowseResults()
	if type(tRaw) ~= "table" then
		gBrowse.state = "done"
		tRebuildAndFocus(gBrowse.entry)
		return
	end
	-- An empty UPDATED right after sending only resets the old list, it is not an answer yet: keep waiting for results
	-- (ADDED), BROWSE_FAILURE or the timeout.
	if #tRaw == 0 and gBrowse.state == "waiting" then return end
	-- Fallback search: the list comes in pages; request more until it is complete (the timeout ends it otherwise).
	local tNotFull = false
	if gBrowse.localFilter and C_AuctionHouse.HasFullBrowseResults then
		local tFull = C_AuctionHouse.HasFullBrowseResults()
		if tFull == false then
			tNotFull = true
			C_AuctionHouse.RequestMoreBrowseResults()
		end
	end
	local tRows, tStillPending = {}, false
	for i = 1, #tRaw do
		local tItem = tRaw[i]
		local tInfo = C_AuctionHouse.GetItemKeyInfo(tItem.itemKey, false)
		if tInfo then
			tRows[#tRows + 1] = {
				itemKey = tItem.itemKey,
				name = tInfo.itemName,
				isCommodity = tInfo.isCommodity,
				minPrice = tItem.minPrice,
				totalQuantity = tItem.totalQuantity,
			}
		else
			-- Name not cached yet - ITEM_KEY_ITEM_INFO_RECEIVED will fire once the
			-- server answers; re-run this same refresh then.
			tStillPending = true
		end
	end
	table.sort(tRows, function(a, b) return (a.minPrice or 0) < (b.minPrice or 0) end)
	-- Fallback search (see AHF:BrowseFallback): check the names against the typed text ourselves.
	if gBrowse.localFilter then
		local tKept = {}
		for _, tRow in ipairs(tRows) do
			if type(tRow.name) == "string" and string.find(string.lower(tRow.name), gBrowse.localFilter, 1, true) then tKept[#tKept + 1] = tRow end
		end
		tRows = tKept
	end
	gBrowse.results = tRows
	gBrowse.state = (tStillPending or tNotFull) and "waiting" or "done"
	if gBrowse.state == "done" and #tRows == 0 and AHF:BrowseFallback() then return end
	tRebuildAndFocus(gBrowse.entry)
	gBrowse.focusIndex = nil
end

-- Fallback search: when the game answers a name search with nothing although the item is for sale (seen live: a
-- category listed it with 1355 pieces, the name search stayed empty), Sku asks for the whole list and filters the
-- names itself (case-insensitive, partial word). Once per search; true = the fallback is running, the caller does
-- nothing more.
function AHF:BrowseFallback()
	if not gBrowse.searchText or gBrowse.localFilter then return false end
	-- No fallback with an active filter: it would bypass the filters and show items they exclude.
	if AHF:FilterSummary() then return false end
	local tText, tEntry = gBrowse.searchText, gBrowse.entry
	AHF:StartBrowseQuery({ searchString = "", sorts = {} }, tEntry)
	gBrowse.searchText = tText
	gBrowse.localFilter = string.lower(tText)
	return true
end

-- ---------------------------------------------------------------------
-- DETAIL (individual listings of one item, after drilling into a browse row)
-- ---------------------------------------------------------------------
function AHF:StartDetail(aRow, aEntry)
	gDetail.state = "waiting"
	gDetail.itemKey = aRow.itemKey
	gDetail.focusIndex = nil
	gDetail.isCommodity = aRow.isCommodity
	gDetail.name = aRow.name
	gDetail.results = {}
	gDetail.entry = aEntry
	gDetail.generation = (gDetail.generation or 0) + 1
	local tGen = gDetail.generation
	C_AuctionHouse.SendSearchQuery(aRow.itemKey, {}, false)
	-- Same stuck-on-"Warten" safety net as StartBrowse - see there for why.
	C_Timer.After(6, function()
		if gDetail.generation == tGen and gDetail.state == "waiting" then
			gDetail.state = "done"
			tRebuildAndFocus(gDetail.entry)
		end
	end)
end

function AHF:RefreshDetailResults(aItemID)
	if gDetail.state == "idle" or not gDetail.itemKey then return end
	if aItemID and aItemID ~= gDetail.itemKey.itemID then return end
	local tRows = {}
	if gDetail.isCommodity then
		local tQty = C_AuctionHouse.GetCommoditySearchResultsQuantity(gDetail.itemKey.itemID)
		if tQty then
			for i = 1, tQty do
				local tResult = C_AuctionHouse.GetCommoditySearchResultInfo(gDetail.itemKey.itemID, i)
				if tResult then
					tRows[#tRows + 1] = {
						isCommodity = true,
						index = i,
						itemID = gDetail.itemKey.itemID,
						unitPrice = tResult.unitPrice,
						quantity = tResult.quantity,
						timeLeftSeconds = tResult.timeLeftSeconds,
						isOwn = tResult.containsOwnerItem,
					}
				end
			end
		end
	else
		local tQty = C_AuctionHouse.GetItemSearchResultsQuantity(gDetail.itemKey)
		if tQty then
			for i = 1, tQty do
				local tResult = C_AuctionHouse.GetItemSearchResultInfo(gDetail.itemKey, i)
				if tResult then
					tRows[#tRows + 1] = {
						isCommodity = false,
						auctionID = tResult.auctionID,
						quantity = tResult.quantity,
						buyoutAmount = tResult.buyoutAmount,
						bidAmount = tResult.bidAmount,
						minBid = tResult.minBid,
						timeLeft = tResult.timeLeft,
						timeLeftSeconds = tResult.timeLeftSeconds,
						bidder = tResult.bidder,
						itemLink = tResult.itemLink,
						isOwn = tResult.containsOwnerItem,
					}
				end
			end
		end
	end
	gDetail.results = tRows
	gDetail.state = "done"
	tRebuildAndFocus(gDetail.entry)
	gDetail.focusIndex = nil
end

-- ---------------------------------------------------------------------
-- BUY - regular (non-commodity) item: buyout is a single protected call.
-- Must run directly inside a real keypress handler (OnAction), same
-- requirement the legacy module's buy path already relies on elsewhere.
-- ---------------------------------------------------------------------
function AHF:BuyItemAuction(aAuctionID, aBuyoutAmount, aName)
	local tNamePrefix = aName and (aName..": ") or ""
	if (GetMoney() or 0) < (aBuyoutAmount or 0) then
		tSay(tNamePrefix..L["Not enough money"])
		return
	end
	local tOk = pcall(C_AuctionHouse.PlaceBid, aAuctionID, aBuyoutAmount)
	if tOk then
		SkuOptions.Voice:OutputStringBTtts(tNamePrefix..L["Purchase started"], false, true, 0.2)
	else
		SkuOptions.Voice:OutputStringBTtts(tNamePrefix..L["Purchase failed"], false, true, 0.2)
	end
end

-- ---------------------------------------------------------------------
-- BUY - commodity: StartCommoditiesPurchase (quote) -> COMMODITY_PRICE_UPDATED
-- (announce the confirmed price) -> ConfirmCommoditiesPurchase (second real
-- keypress). Mirrors Blizzard's own Blizzard_AuctionHouseBuyDialog.lua flow;
-- both calls are HasRestrictions=true (protected), so both must originate
-- from a real key press, never a timer callback.
-- ---------------------------------------------------------------------
function AHF:StartCommodityBuy(aItemID, aQuantity, aEntry, aName, aIndex)
	gCommodityBuy.index = aIndex
	gCommodityBuy.itemID = aItemID
	gCommodityBuy.quantity = aQuantity
	gCommodityBuy.unitPrice = nil
	gCommodityBuy.totalPrice = nil
	gCommodityBuy.warning = nil
	gCommodityBuy.entry = aEntry
	gCommodityBuy.name = aName
	gCommodityBuy.startedAt = GetTime()
	local tReady = C_AuctionHouse.IsThrottledMessageSystemReady()
	local tOk = pcall(C_AuctionHouse.StartCommoditiesPurchase, aItemID, aQuantity)
	if not tOk then
		gCommodityBuy.itemID = nil
		SkuOptions.Voice:OutputStringBTtts(L["Purchase could not be started"], false, true, 0.2)
		return
	end
	-- If the game does not answer with a price, do not hang silently.
	local tStartedAt = gCommodityBuy.startedAt
	C_Timer.After(4, function()
		if gCommodityBuy.itemID == aItemID and gCommodityBuy.startedAt == tStartedAt and not gCommodityBuy.unitPrice then
			SkuOptions.Voice:OutputStringBTtts(L["No price confirmation from the game. Please try again."], false, true, 0.2)
		end
	end)
end

-- Price preview from the listings shown: the game always buys the cheapest first. If the cheapest listing does not
-- cover the quantity, the unit price rises with every further listing. Returns: lowest unit price, highest used unit
-- price, quantity at the lowest price, expected total cost (nil when the listings do not suffice or are missing).
local function tCommodityPriceSpread(aQuantity)
	local tRows = {}
	for _, tR in ipairs(gDetail.results or {}) do
		if tR.isCommodity and tR.unitPrice and (tR.quantity or 0) > 0 then tRows[#tRows + 1] = tR end
	end
	if #tRows == 0 or not aQuantity or aQuantity < 1 then return nil end
	table.sort(tRows, function(a, b) return a.unitPrice < b.unitPrice end)
	local tLow, tHigh, tLowQty, tCost, tLeft = tRows[1].unitPrice, tRows[1].unitPrice, 0, 0, aQuantity
	for _, tR in ipairs(tRows) do
		if tLeft <= 0 then break end
		local tTake = math.min(tLeft, tR.quantity)
		tCost = tCost + tTake * tR.unitPrice
		tHigh = tR.unitPrice
		if tR.unitPrice == tLow then tLowQty = tLowQty + tTake end
		tLeft = tLeft - tTake
	end
	if tLeft > 0 then return tLow, tHigh, tLowQty, nil end
	return tLow, tHigh, tLowQty, tCost
end

function AHF:OnCommodityPriceUpdated(aUnitPrice, aTotalPrice)
	if not gCommodityBuy.itemID then return end
	gCommodityBuy.unitPrice = aUnitPrice
	gCommodityBuy.totalPrice = aTotalPrice
	-- Warn when the price is not what one expects:
	-- 1) several price levels (e.g. only 1 piece at 19, the second costs 21)
	-- 2) the total differs from the listings shown (someone bought or posted in the meantime)
	local tLow, tHigh, tLowQty, tExpected = tCommodityPriceSpread(gCommodityBuy.quantity)
	local tWarn = ""
	if tLow and tHigh and tHigh > tLow then
		tWarn = L["Note: the unit price rises from "]
			..tMoneyText(tLow)..L[" to "]..tMoneyText(tHigh)..L[", because only "]
			..tLowQty..L[" pieces are offered at the lowest price. "]
	end
	if tExpected and aTotalPrice and aTotalPrice ~= tExpected then
		tWarn = tWarn..L["The price changed since it was listed: expected "]
			..tMoneyText(tExpected)..L[", now "]..tMoneyText(aTotalPrice)..". "
	end
	gCommodityBuy.warning = (tWarn ~= "") and tWarn or nil
	SkuOptions.Voice:OutputStringBTtts(
		(gCommodityBuy.name and (gCommodityBuy.name..": ") or "")
			..tWarn
			..L["Total price "]..tMoneyText(aTotalPrice)..". "
			..L["Confirm or cancel?"],
		true, true, 0.2, nil, nil, nil, 1)
	tRebuildAndFocus(gCommodityBuy.entry)
end

function AHF:ConfirmCommodityBuy()
	if not gCommodityBuy.itemID then return end
	C_AuctionHouse.ConfirmCommoditiesPurchase(gCommodityBuy.itemID, gCommodityBuy.quantity)
end

function AHF:CancelCommodityBuy()
	if not gCommodityBuy.itemID then return end
	C_AuctionHouse.CancelCommoditiesPurchase()
	gCommodityBuy.itemID = nil
end

function AHF:OnCommodityPurchaseDone(aSucceeded)
	local tNamePrefix = gCommodityBuy.name and (gCommodityBuy.name..": ") or ""
	gCommodityBuy.itemID = nil
	-- interrupts the running speech: the result must not get lost behind a chat line
	SkuOptions.Voice:OutputStringBTtts(
		tNamePrefix..(aSucceeded and L["Purchase complete"]
			or L["Purchase failed"]),
		true, true, 0.2, nil, nil, nil, 1)
end

-- ---------------------------------------------------------------------
-- Event plumbing. Own frame, independent of SkuCore.AuctionHouse's
-- AceEvent mixin - these events only exist on Forever, so this whole
-- frame only ever fires there anyway, but keeping it separate means the
-- legacy module's event set (auctionHouse.lua, Classic API) is untouched.
-- ---------------------------------------------------------------------
local gEventFrame = CreateFrame("Frame")
gEventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
gEventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
gEventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_FAILURE")
gEventFrame:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
gEventFrame:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
gEventFrame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
gEventFrame:RegisterEvent("ITEM_SEARCH_RESULTS_ADDED")
gEventFrame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
gEventFrame:RegisterEvent("COMMODITY_SEARCH_RESULTS_ADDED")
gEventFrame:RegisterEvent("COMMODITY_PRICE_UPDATED")
gEventFrame:RegisterEvent("COMMODITY_PRICE_UNAVAILABLE")
gEventFrame:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
gEventFrame:RegisterEvent("COMMODITY_PURCHASE_FAILED")
gEventFrame:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")
gEventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
gEventFrame:SetScript("OnEvent", function(self, aEvent, ...)
	if aEvent == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or aEvent == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
		AHF:RefreshBrowseResults()
	elseif aEvent == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
		local tPending = gBrowse.pendingSend
		if tPending and gBrowse.state == "waiting" then
			gBrowse.pendingSend = nil
			local tSend = tPending[2] or C_AuctionHouse.SendBrowseQuery
			tSend(tPending[1])
		end
	elseif aEvent == "AUCTION_HOUSE_BROWSE_FAILURE" then
		-- No positive "zero results" event exists separately from this - a
		-- search with no matches (or a refused query) fires ONLY this, never
		-- the …UPDATED/…ADDED pair. Without handling it, the menu was stuck
		-- on "Warten" forever (seen live).
		if AHF:BrowseFallback() then return end
		gBrowse.state = "done"
		tRebuildAndFocus(gBrowse.entry)
	elseif aEvent == "ITEM_KEY_ITEM_INFO_RECEIVED" then
		if gBrowse.state == "waiting" then AHF:RefreshBrowseResults() end
	elseif aEvent == "ITEM_SEARCH_RESULTS_UPDATED" or aEvent == "ITEM_SEARCH_RESULTS_ADDED" then
		local tKey = ...
		local tItemID = type(tKey) == "table" and tKey.itemID or nil
		AHF:RefreshDetailResults(tItemID)
		if AHF.OnSellMarketResult then AHF:OnSellMarketResult(false, tItemID) end
	elseif aEvent == "COMMODITY_SEARCH_RESULTS_UPDATED" or aEvent == "COMMODITY_SEARCH_RESULTS_ADDED" then
		AHF:RefreshDetailResults((...))
		if AHF.OnSellMarketResult then AHF:OnSellMarketResult(true, (...)) end
	elseif aEvent == "COMMODITY_PRICE_UPDATED" then
		AHF:OnCommodityPriceUpdated(...)
	elseif aEvent == "COMMODITY_PRICE_UNAVAILABLE" then
		gCommodityBuy.itemID = nil
		SkuOptions.Voice:OutputStringBTtts(L["Price unavailable"], false, true, 0.2)
	elseif aEvent == "COMMODITY_PURCHASE_SUCCEEDED" then
		AHF:OnCommodityPurchaseDone(true)
	elseif aEvent == "COMMODITY_PURCHASE_FAILED" then
		AHF:OnCommodityPurchaseDone(false)
	elseif aEvent == "AUCTION_HOUSE_SHOW_ERROR" then
		-- Never leave "Warten" stuck on a rejected browse/detail query.
		if gBrowse.state == "waiting" and not AHF:BrowseFallback() then gBrowse.state = "done"; tRebuildAndFocus(gBrowse.entry) end
		if gDetail.state == "waiting" then gDetail.state = "done"; tRebuildAndFocus(gDetail.entry) end
	elseif aEvent == "AUCTION_HOUSE_CLOSED" then
		if gCommodityBuy.itemID then C_AuctionHouse.CancelCommoditiesPurchase() end
		gBrowse.state, gDetail.state, gCommodityBuy.itemID = "idle", "idle", nil
		gBrowse.entry, gBrowse.results, gDetail.entry, gDetail.itemKey, gDetail.results = nil, {}, nil, nil, {}
	end
end)

-- ---------------------------------------------------------------------
-- Menu
-- ---------------------------------------------------------------------
-- Tooltip text of an auction house item (read with Shift+Down etc.). No tooltip frame: Blizzard's tooltip data
-- (C_TooltipInfo) reads the item by key, link or ID; the source with the most lines wins.
local function tAhItemTooltipText(aItemKey, aLink)
	local tBest
	local function tConsider(aData)
		if type(aData) == "table" and type(aData.lines) == "table" then
			if not tBest or #aData.lines > #tBest.lines then tBest = aData end
		end
	end
	if aItemKey and aItemKey.itemID then
		if C_TooltipInfo.GetItemKey then
			tConsider(C_TooltipInfo.GetItemKey(aItemKey.itemID, aItemKey.itemLevel or 0, aItemKey.itemSuffix or 0))
		end
		tConsider(C_TooltipInfo.GetItemByID(aItemKey.itemID))
	end
	if aLink then tConsider(C_TooltipInfo.GetHyperlink(aLink)) end
	if not tBest then return nil end
	local tOut = {}
	for _, tLine in ipairs(tBest.lines) do
		local tLeft, tRight = tLine.leftText, tLine.rightText
		if type(tLeft) == "string" and not Sku.IsSecret(tLeft) and tLeft ~= "" and not string.find(tLeft, "Open Issue Report", 1, true) then
			if type(tRight) == "string" and not Sku.IsSecret(tRight) and tRight ~= "" then tLeft = tLeft.." "..tRight end
			tOut[#tOut + 1] = tLeft
		end
	end
	-- Like the other tooltips in Sku: quality behind the name (per setting) and the item level as the second line.
	local tQualityText, tLevel
	if aLink then
		tQualityText = SkuUtil:ItemQualityString(aLink)
		tLevel = SkuUtil:ItemLevel(aLink)
	elseif aItemKey then
		local tKeyInfo = C_AuctionHouse.GetItemKeyInfo(aItemKey, false)
		if type(tKeyInfo) == "table" and tKeyInfo.quality then tQualityText = _G["ITEM_QUALITY"..tKeyInfo.quality.."_DESC"] end
		if aItemKey.itemLevel and aItemKey.itemLevel > 1 then tLevel = aItemKey.itemLevel end
	end
	local tShowQuality = false
	tShowQuality = SkuOptions.db.profile["SkuCore"].itemSettings.ShowItemQality == true
	if tQualityText and tShowQuality and tOut[1] then tOut[1] = tOut[1].." ("..tQualityText..")" end
	if tLevel and #tOut > 0 then table.insert(tOut, 2, L["Item Level"]..": "..tLevel) end
	-- Required level: missing in the auction's tooltip data, so it is added from the item data (unless a line has it).
	if #tOut > 0 then
		local tItemRef = aLink or (aItemKey and aItemKey.itemID)
		local tMinLevel
		if tItemRef then
			local _, _, _, _, tMin = C_Item.GetItemInfo(tItemRef)
			if type(tMin) == "number" and not Sku.IsSecret(tMin) then tMinLevel = tMin end
		end
		if tMinLevel and tMinLevel > 1 then
			local tFormat = _G.ITEM_MIN_LEVEL or "Requires Level %d"
			local tPattern = string.gsub(tFormat, "[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
			tPattern = "^"..string.gsub(tPattern, "%%d", "%%d+")
			local tFound = false
			for _, tLineText in ipairs(tOut) do
				if string.find(tLineText, tPattern) then tFound = true break end
			end
			if not tFound then table.insert(tOut, (tLevel and 3) or 2, string.format(tFormat, tMinLevel)) end
		end
	end
	if #tOut == 0 then return nil end
	return SkuUtil:Unescape(table.concat(tOut, "\r\n"))
end

-- Sets the tooltip text on the menu entry (built on reading) and the item reference for the comparison with the equipped item.
local function tSetAhTooltip(aEntry, aItemKey, aLink)
	aEntry.itemId = aLink or (aItemKey and aItemKey.itemID)
	aEntry.textFirstLine = aEntry.name
	aEntry.textFull = function()
		local tText = tAhItemTooltipText(aItemKey, aLink)
		if tText and tText ~= "" then return { tText } end
		return { L["No tooltip available"] }
	end
end

local function tBrowseRowLabel(aRow)
	local tPriceText = tMoneyText(aRow.minPrice)
	if aRow.totalQuantity and aRow.totalQuantity > 1 then
		return aRow.name.." - "..L["from "]..tPriceText..", "
			..aRow.totalQuantity.." "..L["for sale"]
	end
	return aRow.name.." - "..tPriceText
end

-- Special children for the post-quote commodity confirm step: replaces the
-- item's normal listing children while a quote is pending, so "rechts" (the
-- announced next step) actually lands on Confirm/Cancel. Declared
-- BEFORE tBuildDetailChildren, which references it - Lua resolves a local
-- function name lexically, so a forward reference here would silently
-- resolve to a global (nil) instead of this function.
local function tBuildCommodityConfirmChildren(aParentEntry)
	aParentEntry.children = {}
	if not gCommodityBuy.unitPrice then
		local tW = SkuOptions:InjectMenuItems(aParentEntry, {L["Warten"]}, SkuGenericMenuItem)
		tW.dynamic = false
		return
	end
	local tConfirm = SkuOptions:InjectMenuItems(aParentEntry, {L["Confirm: "]..tMoneyText(gCommodityBuy.totalPrice)..(gCommodityBuy.warning and (", "..L["price rises"]) or "")}, SkuGenericMenuItem)
	tConfirm.dynamic = false
	tConfirm.actionInPlace = true   -- ENTER runs the own action; otherwise an isSelect ancestor (search) redirects ENTER to the search
	tConfirm.OnAction = function() AHF:ConfirmCommodityBuy() end
	local tCancel = SkuOptions:InjectMenuItems(aParentEntry, {L["Cancel"]}, SkuGenericMenuItem)
	tCancel.dynamic = false
	tCancel.actionInPlace = true   -- ENTER runs the own action; otherwise an isSelect ancestor (search) redirects ENTER to the search
	tCancel.OnAction = function()
		AHF:CancelCommodityBuy()
		tRebuildAndFocus(aParentEntry, true)
	end
end

-- Bid on a regular auction. A bid at or above the buyout price is a buyout (Blizzard's own
-- bid dialog does the same). Runs inside a menu action, i.e. from a real key press.
function AHF:PlaceItemBid(aRow, aAmount, aName)
	local tPrefix = aName and (aName..": ") or ""
	if aRow.isOwn then
		tSay(tPrefix..L["That is your own auction"])
		return
	end
	if aRow.buyoutAmount and aRow.buyoutAmount > 0 and aAmount >= aRow.buyoutAmount then
		AHF:BuyItemAuction(aRow.auctionID, aRow.buyoutAmount, aName)
		return
	end
	if aRow.minBid and aAmount < aRow.minBid then
		tSay(tPrefix..L["The bid is too low, at least "]..tMoneyText(aRow.minBid))
		return
	end
	if (GetMoney() or 0) < aAmount then
		tSay(tPrefix..L["Not enough money"])
		return
	end
	local tOk = pcall(C_AuctionHouse.PlaceBid, aRow.auctionID, aAmount)
	tSay(tPrefix..(tOk and (L["Bid sent: "]..tMoneyText(aAmount))
		or L["Bid failed"]))
end

-- The three bid leaves shared by the item detail and "My bids": bid the minimum, set an
-- own amount, place that amount. Setting and placing are separate leaves so the protected
-- PlaceBid always runs from its own real key press. aData: {auctionID, minBid, buyoutAmount,
-- isOwn, customBid}. Returns true when bidding is possible at all.
local function tAddBidLeaves(aParent, aData, aName)
	if not (aData.minBid and aData.minBid > 0) then return false end
	local tBidMin = SkuOptions:InjectMenuItems(aParent, {L["Bid the minimum: "]..tMoneyText(aData.minBid)}, SkuGenericMenuItem)
	tBidMin.dynamic = false
	tBidMin.actionInPlace = true   -- ENTER runs the own action; otherwise an isSelect ancestor (search) redirects ENTER to the search
	tBidMin.OnAction = function()
		AHF:PlaceItemBid(aData, aData.minBid, aName)
	end
	local tCustomPlace
	tSettingLeaf(aParent, L["Set your own bid"], function()
		tAskMoney(L["Enter bid, for example 12g 5s 3k"], function(aAmount)
			aData.customBid = aAmount
			if tCustomPlace then
				tCustomPlace.name = L["Place your bid: "]..tMoneyText(aAmount)
			end
		end)
	end)
	tCustomPlace = tSettingLeaf(aParent, aData.customBid
		and (L["Place your bid: "]..tMoneyText(aData.customBid))
		or L["Place your bid, set it first"],
		function()
			if not aData.customBid then
				tSay(L["Set a bid first"])
				return
			end
			AHF:PlaceItemBid(aData, aData.customBid, aName)
		end)
	return true
end

-- Favourites (Blizzard: the star next to an item). Only offered where the server supports them.
local function tFavoritesAvailable()
	local tAvail = C_AuctionHouse.FavoritesAreAvailable()
	return tAvail == true
end

local function tIsFavorite(aItemKey)
	local tIs = C_AuctionHouse.IsFavoriteItem(aItemKey)
	return tIs == true
end

local function tFavoriteLabel(aItemKey)
	if tIsFavorite(aItemKey) then
		return L["Remove from favorites"]
	end
	return L["Add to favorites"]
end

local function tAddFavoriteLeaf(aParent, aItemKey)
	if not aItemKey or not tFavoritesAvailable() then return end
	tSettingLeaf(aParent, tFavoriteLabel(aItemKey), function(aLeaf)
		local tFav = tIsFavorite(aItemKey)
		if not tFav then
			local tMax = C_AuctionHouse.HasMaxFavorites()
			if tMax then
				aLeaf.name = L["Your favorites list is full"]
				return
			end
		end
		C_AuctionHouse.SetFavoriteItem(aItemKey, not tFav)
		-- the server confirms with AUCTION_HOUSE_FAVORITES_UPDATED; show the expected state right away
		aLeaf.name = (not tFav) and L["Added to favorites"]
			or L["Removed from favorites"]
	end)
end

-- "Load more": the server hands out results in pages (HasFull*Results is false until all are in).
local function tDetailIsComplete()
	if not gDetail.itemKey then return true end
	local tFull
	if gDetail.isCommodity then
		tFull = C_AuctionHouse.HasFullCommoditySearchResults(gDetail.itemKey.itemID)
	else
		tFull = C_AuctionHouse.HasFullItemSearchResults(gDetail.itemKey)
	end
	return tFull ~= false
end

local function tBuildDetailChildren(aParentEntry)
	aParentEntry.children = {}
	if gDetail.state == "waiting" then
		local tW = SkuOptions:InjectMenuItems(aParentEntry, {L["Warten"]}, SkuGenericMenuItem)
		tW.dynamic = false
		return
	end
	tAddFavoriteLeaf(aParentEntry, gDetail.itemKey)
	if #gDetail.results == 0 then
		local tNone = SkuOptions:InjectMenuItems(aParentEntry, {L["AH_NoResults"]}, SkuGenericMenuItem)
		tNone.dynamic = false
		tNone.ahfPrimary = true
		return
	end
	-- Every row repeats the item name (gDetail.name) - without it, a line like
	-- "2x zu je 24 Kupfer" is meaningless out of context, e.g. after navigating
	-- away and back, or the first time you land here at all. Confirmed live
	-- Seen live: players heard exactly that and could not tell what it referred to.
	local tNamePrefix = (gDetail.name or "?")..": "
	local tPrimaryIndex = gDetail.focusIndex or 1
	for i, tRow in ipairs(gDetail.results) do
		local tBody
		if tRow.isCommodity then
			tBody = tRow.quantity.." "..L["for "]..tMoneyText(tRow.unitPrice)
		else
			tBody = tRow.buyoutAmount and (L["Buyout "]..tMoneyText(tRow.buyoutAmount))
				or (L["Bid from "]..tMoneyText(tRow.minBid or tRow.bidAmount or 0))
			if tRow.quantity and tRow.quantity > 1 then tBody = tRow.quantity.."x "..tBody end
			if tIsOwnGuid(tRow.bidder) then
				tBody = tBody..", "..L["your bid is highest"]
			end
		end
		local tLeft = tTimeLeftText(tRow)
		if tLeft ~= "" then tBody = tBody..", "..L["left: "]..tLeft end
		if tRow.isOwn then tBody = tBody..", "..L["your own auction"] end
		local tLabel = tNamePrefix..tBody
		local tRowEntry = SkuOptions:InjectMenuItems(aParentEntry, {tLabel}, SkuGenericMenuItem)
		tRowEntry.dynamic = true
		tRowEntry.data = tRow
		tRowEntry.skuIdentity = tRow.isCommodity and ("commodity:"..tRow.unitPrice) or ("auction:"..tRow.auctionID)
		tSetAhTooltip(tRowEntry, gDetail.itemKey, tRow.itemLink)
		if i == tPrimaryIndex then tRowEntry.ahfPrimary = true end
		tRowEntry.BuildChildren = function(self)
			self.children = {}
			-- Post-quote confirm step takes over THIS row's children until the
			-- purchase is confirmed or cancelled (mirrors Blizzard's own modal
			-- buy dialog covering the screen after StartCommoditiesPurchase).
			if self.data.isCommodity and gCommodityBuy.itemID == self.data.itemID and gCommodityBuy.index == self.data.index then
				tBuildCommodityConfirmChildren(self)
				return
			end
			if self.data.isCommodity then
				-- Pick the quantity before buying. The game always buys the cheapest listings first, whichever row one is on;
				-- at most what is offered in total. Default: the quantity of this listing.
				local tTotalAvail = 0
				for _, tR in ipairs(gDetail.results) do tTotalAvail = tTotalAvail + (tR.quantity or 0) end
				local tMaxQty = math.max(1, tTotalAvail)
				local tData = self.data
				tData.buyQty = math.max(1, math.min(tData.buyQty or tData.quantity or 1, tMaxQty))
				local function tQtyName() return L["Quantity: "]..tData.buyQty..L[" of at most "]..tMaxQty end
				local function tBuyName() return L["Kaufen"]..": "..tData.buyQty..L[" pieces"] end
				local tBuyEntry
				local tQtyLeaf = tSettingLeaf(self, tQtyName(), function(aLeaf)
					SkuOptions:EditBoxShow("", function()
						local tN = tonumber((SkuOptionsEditBoxEditBox:GetText() or ""):match("%d+"))
						if tN and tN >= 1 then
							tData.buyQty = math.min(math.floor(tN), tMaxQty)
							aLeaf.name = tQtyName()
							if tBuyEntry then tBuyEntry.name = tBuyName() end
						else
							tSay(L["Quantity not understood"])
						end
						tVocalize()
					end, nil)
					C_Timer.After(0.1, function()
						SkuOptions.Voice:OutputStringBTtts(L["Enter quantity, at most "]..tMaxQty, true, true, 0.1, nil, nil, nil, 1)
					end)
				end)
				tBuyEntry = SkuOptions:InjectMenuItems(self, {tBuyName()}, SkuGenericMenuItem)
				tBuyEntry.dynamic = false
				tBuyEntry.actionInPlace = true   -- ENTER runs the own action; otherwise an isSelect ancestor (search) redirects ENTER to the search
				tBuyEntry.OnAction = function()
					AHF:StartCommodityBuy(tData.itemID, tData.buyQty, self, gDetail.name, tData.index)
					tRebuildAndFocus(self, true)
				end
			elseif self.data.isOwn then
				local tOwn = SkuOptions:InjectMenuItems(self, {L["That is your own auction"]}, SkuGenericMenuItem)
				tOwn.dynamic = false
			else
				local tData = self.data
				if tData.buyoutAmount then
					local tBuyEntry = SkuOptions:InjectMenuItems(self, {L["Kaufen"]..": "..tMoneyText(tData.buyoutAmount)}, SkuGenericMenuItem)
					tBuyEntry.dynamic = false
					tBuyEntry.actionInPlace = true   -- ENTER runs the own action; otherwise an isSelect ancestor (search) redirects ENTER to the search
					tBuyEntry.OnAction = function()
						AHF:BuyItemAuction(tData.auctionID, tData.buyoutAmount, gDetail.name)
					end
				end
				-- Bidding below the buyout (Blizzard: the bid box next to the buyout button).
				local tHasBid = tAddBidLeaves(self, tData, gDetail.name)
				if not tData.buyoutAmount and not tHasBid then
					local tNoBuyout = SkuOptions:InjectMenuItems(self, {L["Neither buyout nor bid possible"]}, SkuGenericMenuItem)
					tNoBuyout.dynamic = false
				end
			end
		end
	end
	if not tDetailIsComplete() then
		tSettingLeaf(aParentEntry, L["Load more auctions, so far "]..#gDetail.results, function(aLeaf)
			gDetail.focusIndex = #gDetail.results + 1
			if gDetail.isCommodity then
				C_AuctionHouse.RequestMoreCommoditySearchResults(gDetail.itemKey.itemID)
			else
				C_AuctionHouse.RequestMoreItemSearchResults(gDetail.itemKey)
			end
			aLeaf.name = L["Loading more auctions"]
		end)
	end
end

-- One row for one item found by name search: {itemKey, name, isCommodity,
-- minPrice, totalQuantity} -> drills into the live detail/buy step.
local function tInjectItemRow(aParentEntry, aRow)
	local tRowEntry = SkuOptions:InjectMenuItems(aParentEntry, {tBrowseRowLabel(aRow)}, SkuGenericMenuItem)
	tRowEntry.dynamic = true
	tRowEntry.data = aRow
	local tKey = aRow.itemKey
	tRowEntry.skuIdentity = "browse:"..tKey.itemID..":"..tKey.itemLevel..":"..tKey.itemSuffix..":"..tKey.battlePetSpeciesID
	tSetAhTooltip(tRowEntry, aRow.itemKey, nil)
	tMarkEntering(tRowEntry)
	tRowEntry.BuildChildren = function(selfRow)
		if gDetail.entry ~= selfRow or gDetail.state == "idle" then
			if not selfRow.ahfEntering then selfRow.children = {} return end
			AHF:StartDetail(selfRow.data, selfRow)
		end
		tBuildDetailChildren(selfRow)
	end
	return tRowEntry
end

-- Appends the current gBrowse state (waiting / no results / result rows)
-- to aParentEntry - does NOT clear children first, so the caller can put its
-- own leaves (e.g. the name search's "Suchbegriff eingeben") before it.
local function tAppendBrowseResultChildren(aParentEntry)
	-- gBrowse holds ONE result set shared by name search and every category
	-- node. Only the node that started the current query may show it, else the
	-- search list shows category results and vice versa.
	if gBrowse.entry ~= aParentEntry then return end
	if gBrowse.state == "waiting" then
		local tW = SkuOptions:InjectMenuItems(aParentEntry, {L["Warten"]}, SkuGenericMenuItem)
		tW.dynamic = false
	elseif gBrowse.state == "done" then
		if #gBrowse.results == 0 then
			local tNone = SkuOptions:InjectMenuItems(aParentEntry, {L["AH_NoResults"]}, SkuGenericMenuItem)
			tNone.dynamic = false
		else
			for i, tRow in ipairs(gBrowse.results) do
				local tRowEntry = tInjectItemRow(aParentEntry, tRow)
				if gBrowse.focusIndex and i == gBrowse.focusIndex then tRowEntry.ahfPrimary = true end
			end
			-- More results on the server (HasFullBrowseResults is false until all pages are in).
			local tFull = C_AuctionHouse.HasFullBrowseResults()
			if tFull == false then
				tSettingLeaf(aParentEntry, L["Load more results, so far "]..#gBrowse.results, function(aLeaf)
					gBrowse.focusIndex = #gBrowse.results + 1
					C_AuctionHouse.RequestMoreBrowseResults()
					aLeaf.name = L["Loading more results"]
				end)
			end
		end
	end
end

-- Builds one menu level of Blizzard's own AuctionCategories tree (see
-- Shared/Blizzard_AuctionData.lua - real client data, not something Sku invents). Self-recursive, so
-- declared as an upvalue first (a bare "local function X() ... X() ... end"
-- can call itself, but this needs the pre-declaration for the OnAction/
-- BuildChildren closures below to resolve it correctly either way - kept
-- explicit to avoid the exact lexical-scoping trap fixed earlier in this file).
-- Does NOT clear aParentEntry.children itself (same "append" contract as
-- tAppendBrowseResultChildren) - the "Alles in X" leaf below needs to sit
-- BEFORE the subcategories it's called to add, and clearing here would wipe
-- it back out. Every call site clears first if it needs to.
local tBuildCategoryChildren
tBuildCategoryChildren = function(aParentEntry, aCategoryList)
	for i, tCat in ipairs(aCategoryList) do
		local tCatEntry = SkuOptions:InjectMenuItems(aParentEntry, {tCat.name}, SkuGenericMenuItem)
		tCatEntry.dynamic = true
		tCatEntry.data = tCat
		tMarkEntering(tCatEntry)
		tCatEntry.BuildChildren = function(self)
			if self.data.subCategories and #self.data.subCategories > 0 then
				self.children = {}
				-- Subcategories first, "Alles in X" last: going right into Waffen must
				-- land on Einhand/Zweihand/..., not straight on a result list.
				tBuildCategoryChildren(self, self.data.subCategories)
				-- Every node (not just leaves) accumulates its descendants' filters
				-- (AuctionCategoryMixin:AddFilter walks up to self.parent), so "Alles
				-- in Waffen" is a real, meaningful browse even though Waffen itself
				-- has subcategories.
				if self.data.filters and #self.data.filters > 0 then
					local tAll = SkuOptions:InjectMenuItems(self, {L["Everything in "]..self.data.name}, SkuGenericMenuItem)
					tAll.dynamic = true
					tMarkEntering(tAll)
					tAll.BuildChildren = function(selfAll)
						if gBrowse.entry ~= selfAll then
							if not selfAll.ahfEntering then selfAll.children = {} return end
							AHF:StartCategoryBrowse(self.data.filters, selfAll)
						end
						selfAll.children = {}
						tAppendBrowseResultChildren(selfAll)
					end
				end
			else
				if gBrowse.entry ~= self then
					if not self.ahfEntering then self.children = {} return end
					AHF:StartCategoryBrowse(self.data.filters or {}, self)
				end
				self.children = {}
				tAppendBrowseResultChildren(self)
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- SELL + OWN AUCTIONS (Auktionen > Verkaeufe). Mirrors Blizzard's own
-- ItemSellFrame/CommoditiesSellFrame flow: PostItem/PostCommodity (protected,
-- must run from a real keypress) returns needsConfirmation; then
-- AUCTION_HOUSE_POST_WARNING -> ConfirmPostItem/ConfirmPostCommodity with the
-- same args. Item prices are per item/auction, commodity prices per unit
-- (Blizzard's GetTotalPrice multiplies by quantity). Max quantity =
-- C_AuctionHouse.GetAvailablePostCount(itemLocation).
-- ---------------------------------------------------------------------
local gSell = { duration = nil }
local gSellList = nil
local gOwned = { state = "idle", rows = {}, entry = nil, generation = 0 }

local function tPack(...)
	return { n = select("#", ...), ... }
end

local function tDurationText(aIndex)
	local tG = ({ _G.AUCTION_DURATION_ONE, _G.AUCTION_DURATION_TWO, _G.AUCTION_DURATION_THREE })[aIndex]
	if type(tG) == "string" and tG ~= "" then return tG end
	return ({ tHours(12), tHours(24), tHours(48) })[aIndex] or "?"
end

local function tGetDuration()
	if not gSell.duration then
		local tV = tonumber(GetCVar and GetCVar("auctionHouseDurationDropdown") or nil) or 3
		gSell.duration = math.max(1, math.min(3, tV))
	end
	return gSell.duration
end

local function tItemNameFor(aItemID, aLink)
	local tName
	if aItemID and C_Item and C_Item.GetItemNameByID then
		local tN = C_Item.GetItemNameByID(aItemID)
		if type(tN) == "string" and tN ~= "" then tName = tN end
	end
	if not tName and type(aLink) == "string" then tName = aLink:match("%[(.-)%]") end
	return tName or ("Item "..tostring(aItemID))
end

local function tDepositAmount()
	if not gSell.loc then return 0 end
	local tD
	if gSell.isCommodity then
		tD = C_AuctionHouse.CalculateCommodityDeposit(gSell.itemID, tGetDuration(), gSell.quantity or 1)
	else
		tD = C_AuctionHouse.CalculateItemDeposit(gSell.loc, tGetDuration(), gSell.quantity or 1)
	end
	return (tonumber(tD)) or 0
end

local function tMoneyOrNone(aAmount)
	if aAmount and aAmount > 0 then return tMoneyText(aAmount) end
	return L["not set"]
end

local function tQuantityLabel()
	return L["Quantity: "]..(gSell.quantity or 1)
		.." ("..L["at most "]..(gSell.maxQuantity or 1)..")"
end
local function tDurationLabel()
	return L["Duration: "]..tDurationText(tGetDuration())
end
local function tPriceLabel()
	if gSell.isCommodity then
		return L["Price per unit: "]..tMoneyOrNone(gSell.buyout)
	end
	return L["Buyout price: "]..tMoneyOrNone(gSell.buyout)
end
local function tTotalLabel()
	local tTotal = gSell.buyout and gSell.buyout > 0 and (gSell.buyout * (gSell.quantity or 1)) or nil
	return L["Total price for the quantity: "]..tMoneyOrNone(tTotal)
end
local function tBidLabel()
	return L["Starting bid, optional: "]..tMoneyOrNone(gSell.bid)
end
local function tDepositLabel()
	local tText = L["Deposit: "]..tMoneyText(tDepositAmount())
	if gSell.buyout and gSell.buyout > 0 and (gSell.quantity or 1) > 1 then
		tText = tText..", "..L["total price "]..tMoneyText(gSell.buyout * gSell.quantity)
	end
	return tText
end
local function tPostLabel()
	if gSell.pending then
		return L["Confirm: post with warning"]
	end
	return L["Post auction"]
end

-- Market price hint while selling (Blizzard's sell frame lists the current offers and fills the
-- price from the cheapest one). SendSellSearchQuery -> the usual search result events; the
-- cheapest buyout / unit price is offered as the new price on the next Enter.
local function tMarketLabel()
	if gSell.marketState == "waiting" then
		return L["Looking up the market price"]
	end
	if gSell.marketState == "done" then
		if gSell.marketLowest then
			return L["Cheapest price on the market: "]
				..tMoneyText(gSell.marketLowest)..". "..L["Enter uses it as your price"]
		end
		return L["No offers on the market, you set the price. Enter asks again"]
	end
	return L["Look up the market price"]
end

local function tRefreshSellLabels()
	local tL = gSell.leaves
	if not tL then return end
	if tL.quantity then tL.quantity.name = tQuantityLabel() end
	if tL.duration then tL.duration.name = tDurationLabel() end
	if tL.price then tL.price.name = tPriceLabel() end
	if tL.market then tL.market.name = tMarketLabel() end
	if tL.total then tL.total.name = tTotalLabel() end
	if tL.bid then tL.bid.name = tBidLabel() end
	if tL.deposit then tL.deposit.name = tDepositLabel() end
	if tL.post then tL.post.name = tPostLabel() end
end

function AHF:StartMarketQuery()
	if not gSell.loc or gSell.marketState == "waiting" then return end
	local tKey = C_AuctionHouse.GetItemKeyFromItem(gSell.loc)
	if type(tKey) ~= "table" then
		gSell.marketState = "done"
		return
	end
	gSell.marketState = "waiting"
	gSell.marketLowest = nil
	gSell.marketKey = tKey
	local tItem = gSell.loc
	C_AuctionHouse.SendSellSearchQuery(tKey, {}, true)
	C_Timer.After(6, function()
		if gSell.marketState == "waiting" and gSell.loc == tItem then
			gSell.marketState = "done"
			tRefreshSellLabels()
			tSay(tMarketLabel())
		end
	end)
end

-- Called from the search result events (see the event frame above).
function AHF:OnSellMarketResult(aIsCommodity, aItemID)
	if gSell.marketState ~= "waiting" or not gSell.marketKey then return end
	if aItemID and aItemID ~= gSell.marketKey.itemID then return end
	local tLowest
	if aIsCommodity then
		local tNum = C_AuctionHouse.GetNumCommoditySearchResults(gSell.marketKey.itemID)
		for i = 1, math.min((tonumber(tNum)) or 0, 20) do
			local tR = C_AuctionHouse.GetCommoditySearchResultInfo(gSell.marketKey.itemID, i)
			if tR and tR.unitPrice and (not tLowest or tR.unitPrice < tLowest) then tLowest = tR.unitPrice end
		end
	else
		local tNum = C_AuctionHouse.GetNumItemSearchResults(gSell.marketKey)
		for i = 1, math.min((tonumber(tNum)) or 0, 20) do
			local tR = C_AuctionHouse.GetItemSearchResultInfo(gSell.marketKey, i)
			if tR and tR.buyoutAmount and tR.buyoutAmount > 0 then
				local tEach = math.floor(tR.buyoutAmount / math.max(1, tR.quantity or 1))
				if not tLowest or tEach < tLowest then tLowest = tEach end
			end
		end
	end
	gSell.marketState = "done"
	gSell.marketLowest = tLowest
	tRefreshSellLabels()
	tSay(tMarketLabel())
end

-- Returns true when the draft is ready, false when item data is not loaded yet.
function AHF:SelectSellItem(aBag, aSlot)
	if gSell.bag == aBag and gSell.slot == aSlot and gSell.loc then return true end
	local tLoc = ItemLocation:CreateFromBagAndSlot(aBag, aSlot)
	local tStatus = C_AuctionHouse.GetItemCommodityStatus(tLoc)
	local tUnknown = (Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Unknown) or 0
	local tCommodity = (Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity) or 2
	if tStatus == nil or tStatus == tUnknown then return false end
	local tInfo = C_Container.GetContainerItemInfo(aBag, aSlot)
	local tItemID = tInfo and tInfo.itemID
	local tMax = 1
	local tM = C_AuctionHouse.GetAvailablePostCount(tLoc)
	if tonumber(tM) and tM > 0 then tMax = tM end
	local tKeepDuration = gSell.duration
	gSell = {
		bag = aBag, slot = aSlot, loc = tLoc, itemID = tItemID,
		name = tItemNameFor(tItemID, tInfo and tInfo.hyperlink),
		isCommodity = (tStatus == tCommodity), maxQuantity = tMax,
		quantity = 1, duration = tKeepDuration,
	}
	if gSell.isCommodity then gSell.quantity = math.min(tMax, (tInfo and tInfo.stackCount) or 1) end
	return true
end

local function tAskAmount(aPrompt, aApply)
	SkuOptions:EditBoxShow("", function()
		local tText = SkuOptionsEditBoxEditBox:GetText()
		if tText and tText ~= "" then aApply(tText) end
		tRefreshSellLabels()
		tVocalize()
	end, nil)
	C_Timer.After(0.1, function()
		SkuOptions.Voice:OutputStringBTtts(aPrompt, true, true, 0.1, nil, nil, nil, 1)
	end)
end

function AHF:PostDraft()
	if not gSell.loc then return end
	if gSell.pending then
		local tP = gSell.pending
		gSell.pending = nil
		if gSell.isCommodity then
			C_AuctionHouse.ConfirmPostCommodity(unpack(tP, 1, tP.n))
		else
			C_AuctionHouse.ConfirmPostItem(unpack(tP, 1, tP.n))
		end
		tRefreshSellLabels()
		tSay(gSell.name..": "..L["Confirmed, posting"])
		return
	end
	if not gSell.buyout or gSell.buyout <= 0 then
		tSay(L["Set a price first"])
		return
	end
	if gSell.bid and gSell.bid >= gSell.buyout and not gSell.isCommodity then
		tSay(L["The starting bid must be below the buyout price"])
		return
	end
	if (GetMoney() or 0) < tDepositAmount() then
		tSay(L["Not enough money for the deposit"])
		return
	end
	local tReady = C_AuctionHouse.IsThrottledMessageSystemReady()
	if tReady == false then
		tSay(L["Please wait a moment and try again"])
		return
	end
	local tDuration, tQuantity = tGetDuration(), gSell.quantity or 1
	local tOk, tNeeds, tArgs
	if gSell.isCommodity then
		tArgs = tPack(gSell.loc, tDuration, tQuantity, gSell.buyout)
		tOk, tNeeds = pcall(C_AuctionHouse.PostCommodity, unpack(tArgs, 1, tArgs.n))
	else
		tArgs = tPack(gSell.loc, tDuration, tQuantity, gSell.bid, gSell.buyout)
		tOk, tNeeds = pcall(C_AuctionHouse.PostItem, unpack(tArgs, 1, tArgs.n))
	end
	if not tOk then
		tSay(gSell.name..": "..L["Posting failed"])
		return
	end
	if tNeeds then
		gSell.pending = tArgs
		tRefreshSellLabels()
		tSay(gSell.name..": "..L["Confirmation needed. Press Enter again to confirm."])
	else
		tSay(gSell.name..": "..L["Posting"])
	end
end

local function tBuildSellItemChildren(aParent)
	aParent.children = {}
	local tLeaves = {}
	gSell.leaves = tLeaves
	if (gSell.maxQuantity or 1) > 1 then
		tLeaves.quantity = tSettingLeaf(aParent, tQuantityLabel(), function()
			tAskAmount(L["Enter quantity"], function(aText)
				local tN = math.floor(tonumber(aText) or 0)
				if tN >= 1 then gSell.quantity = math.min(tN, gSell.maxQuantity or 1) end
			end)
		end)
	end
	tLeaves.duration = tSettingLeaf(aParent, tDurationLabel(), function()
		gSell.duration = (tGetDuration() % 3) + 1
		SetCVar("auctionHouseDurationDropdown", gSell.duration)
		tRefreshSellLabels()
	end)
	tLeaves.price = tSettingLeaf(aParent, tPriceLabel(), function()
		tAskAmount(L["Enter price, for example 12g 5s 3k"], function(aText)
			local tP = tParseMoney(aText)
			if tP then gSell.buyout = tP else tSay(L["Price not understood"]) end
		end)
	end)
	tLeaves.market = tSettingLeaf(aParent, tMarketLabel(), function()
		if gSell.marketState == "done" and gSell.marketLowest then
			gSell.buyout = gSell.marketLowest
			tRefreshSellLabels()
			return
		end
		AHF:StartMarketQuery()
		tRefreshSellLabels()
	end)
	if (gSell.maxQuantity or 1) > 1 then
		tLeaves.total = tSettingLeaf(aParent, tTotalLabel(), function()
			tAskAmount(L["Enter the total price for the chosen quantity, for example 5g"], function(aText)
				local tTotal = tParseMoney(aText)
				if not tTotal then
					tSay(L["Price not understood"])
					return
				end
				local tQty = gSell.quantity or 1
				local tPer = math.max(1, math.floor(tTotal / tQty + 0.5))
				local tCopper = C_AuctionHouse.SupportsCopperValues()
				if not tCopper then tPer = math.max(100, math.floor(tPer / 100 + 0.5) * 100) end
				gSell.buyout = tPer
				tSay(tPriceLabel()..", "..L["total "]..tMoneyText(tPer * tQty))
			end)
		end)
	end
	if not gSell.isCommodity then
		tLeaves.bid = tSettingLeaf(aParent, tBidLabel(), function()
			tAskAmount(L["Enter starting bid, or 0 to clear"], function(aText)
				if tonumber(aText) == 0 then gSell.bid = nil return end
				local tP = tParseMoney(aText)
				if tP then gSell.bid = tP else tSay(L["Amount not understood"]) end
			end)
		end)
	end
	local tDep = SkuOptions:InjectMenuItems(aParent, {tDepositLabel()}, SkuGenericMenuItem)
	tDep.dynamic = false
	tLeaves.deposit = tDep
	tLeaves.post = tSettingLeaf(aParent, tPostLabel(), function() AHF:PostDraft() end)
end

local function tBuildSellList(aSelf)
	aSelf.children = {}
	gSellList = aSelf
	local tAny = false
	for tBag = 0, (NUM_BAG_SLOTS or 4) do
		local tNum = C_Container.GetContainerNumSlots(tBag) or 0
		for tSlot = 1, tNum do
			local tInfo = C_Container.GetContainerItemInfo(tBag, tSlot)
			if tInfo and tInfo.itemID then
				local tValid = C_AuctionHouse.IsSellItemValid(ItemLocation:CreateFromBagAndSlot(tBag, tSlot), false)
				if tValid then
					tAny = true
					local tName = tItemNameFor(tInfo.itemID, tInfo.hyperlink)
					if (tInfo.stackCount or 1) > 1 then tName = tName.." x"..tInfo.stackCount end
					local tE = SkuOptions:InjectMenuItems(aSelf, {tName}, SkuGenericMenuItem)
					tE.dynamic = true
					tMarkEntering(tE)
					tE.BuildChildren = function(self)
						if not self.ahfEntering then self.children = {} return end
						if not AHF:SelectSellItem(tBag, tSlot) then
							self.children = {}
							local tW = SkuOptions:InjectMenuItems(self, {L["Item data still loading, please open again in a moment"]}, SkuGenericMenuItem)
							tW.dynamic = false
							return
						end
						tBuildSellItemChildren(self)
					end
				end
			end
		end
	end
	if not tAny then
		local tNone = SkuOptions:InjectMenuItems(aSelf, {L["No sellable items in your bags"]}, SkuGenericMenuItem)
		tNone.dynamic = false
	end
end

-- ---- Own auctions ---------------------------------------------------
local function tCursorDeeperThan(aEntry)
	local tDepth, tPos = 0, SkuOptions and SkuOptions.currentMenuPosition
	while tPos and tPos ~= aEntry and tDepth < 10 do
		tPos = tPos.parent
		tDepth = tDepth + 1
	end
	return tPos == aEntry and tDepth >= 2
end

function AHF:StartOwnedQuery(aEntry)
	gOwned.state = "waiting"
	gOwned.entry = aEntry
	gOwned.generation = gOwned.generation + 1
	local tGen = gOwned.generation
	C_AuctionHouse.QueryOwnedAuctions({})
	C_Timer.After(6, function()
		if gOwned.generation == tGen and gOwned.state == "waiting" then
			gOwned.state = "done"
			tRebuildAndFocus(gOwned.entry)
		end
	end)
end

function AHF:RefreshOwned()
	if gOwned.state == "idle" or not gOwned.entry then return end
	local tRows = {}
	local tNum = C_AuctionHouse.GetNumOwnedAuctions()
	if tNum then
		for i = 1, tNum do
			local tInfo = C_AuctionHouse.GetOwnedAuctionInfo(i)
			if tInfo then
				local tName
				if tInfo.itemLink then tName = tInfo.itemLink:match("%[(.-)%]") end
				if not tName and tInfo.itemKey then
					local tK = C_AuctionHouse.GetItemKeyInfo(tInfo.itemKey, false)
					if tK then tName = tK.itemName end
				end
				tRows[#tRows + 1] = { info = tInfo, name = tName or ("Item "..tostring(tInfo.itemKey and tInfo.itemKey.itemID)) }
			end
		end
	end
	gOwned.rows = tRows
	gOwned.state = "done"
	if not tCursorDeeperThan(gOwned.entry) then tRebuildAndFocus(gOwned.entry) end
end

local function tOwnedRowLabel(aRow)
	local tI = aRow.info
	local tSold = Enum.AuctionStatus and tI.status == Enum.AuctionStatus.Sold
	local tParts = { aRow.name }
	if (tI.quantity or 1) > 1 then tParts[#tParts + 1] = tI.quantity.."x" end
	if tSold then
		tParts[#tParts + 1] = L["sold"]
		if tI.buyoutAmount and tI.buyoutAmount > 0 then tParts[#tParts + 1] = tMoneyText(tI.buyoutAmount) end
	else
		if tI.buyoutAmount and tI.buyoutAmount > 0 then
			tParts[#tParts + 1] = L["buyout "]..tMoneyText(tI.buyoutAmount)
		end
		if tI.bidAmount and tI.bidAmount > 0 then
			tParts[#tParts + 1] = L["bid "]..tMoneyText(tI.bidAmount)
			if tI.bidder then tParts[#tParts + 1] = L["by "]..tI.bidder end
		end
		local tLeft = tTimeLeftText(tI)
		if tLeft ~= "" then tParts[#tParts + 1] = L["left: "]..tLeft end
	end
	return table.concat(tParts, ", ")
end

local function tAppendOwnedChildren(aParent)
	if gOwned.entry ~= aParent then return end
	if gOwned.state == "waiting" then
		local tW = SkuOptions:InjectMenuItems(aParent, {L["Warten"]}, SkuGenericMenuItem)
		tW.dynamic = false
		return
	end
	if #gOwned.rows == 0 then
		local tNone = SkuOptions:InjectMenuItems(aParent, {L["No current sales"]}, SkuGenericMenuItem)
		tNone.dynamic = false
		return
	end
	for _, tRow in ipairs(gOwned.rows) do
		local tE = SkuOptions:InjectMenuItems(aParent, {tOwnedRowLabel(tRow)}, SkuGenericMenuItem)
		tE.dynamic = true
		tE.data = tRow
		tE.BuildChildren = function(self)
			self.children = {}
			local tI = self.data.info
			if Enum.AuctionStatus and tI.status == Enum.AuctionStatus.Sold then
				local tS = SkuOptions:InjectMenuItems(self, {L["Sold, the money arrives by mail"]}, SkuGenericMenuItem)
				tS.dynamic = false
				return
			end
			local tArmed = false
			tSettingLeaf(self, L["Cancel auction"], function(aLeaf)
				if not tArmed then
					tArmed = true
					local tText = L["Really cancel? Press Enter again"]
					local tCost = C_AuctionHouse.GetCancelCost(tI.auctionID)
					if tonumber(tCost) and tCost > 0 then
						tText = tText..", "..L["cost "]..tMoneyText(tCost)
					end
					aLeaf.name = tText
				else
					tArmed = false
					C_AuctionHouse.CancelAuction(tI.auctionID)
					aLeaf.name = L["Cancel sent"]
				end
			end)
		end
	end
end

-- ---- My bids (Blizzard: Auctions tab > Bids) -------------------------------
-- Auctions the player has bid on. QueryBids -> BIDS_UPDATED -> GetBidInfo(i). A row says whether
-- the player is still the highest bidder or was outbid, and offers buyout / raising the bid.
local gBids = { state = "idle", rows = {}, entry = nil, generation = 0 }

function AHF:StartBidsQuery(aEntry)
	gBids.state = "waiting"
	gBids.entry = aEntry
	gBids.generation = gBids.generation + 1
	local tGen = gBids.generation
	C_AuctionHouse.QueryBids({}, {})
	C_Timer.After(6, function()
		if gBids.generation == tGen and gBids.state == "waiting" then
			gBids.state = "done"
			tRebuildAndFocus(gBids.entry)
		end
	end)
end

function AHF:RefreshBids()
	if gBids.state == "idle" or not gBids.entry then return end
	local tRows = {}
	local tNum = C_AuctionHouse.GetNumBids()
	if tNum then
		for i = 1, tNum do
			local tInfo = C_AuctionHouse.GetBidInfo(i)
			if tInfo then
				local tName
				if tInfo.itemLink then tName = tInfo.itemLink:match("%[(.-)%]") end
				if not tName and tInfo.itemKey then
					local tK = C_AuctionHouse.GetItemKeyInfo(tInfo.itemKey, false)
					if tK then tName = tK.itemName end
				end
				tRows[#tRows + 1] = {
					name = tName or ("Item "..tostring(tInfo.itemKey and tInfo.itemKey.itemID)),
					auctionID = tInfo.auctionID,
					bidAmount = tInfo.bidAmount,
					minBid = tInfo.minBid,
					buyoutAmount = tInfo.buyoutAmount,
					bidder = tInfo.bidder,
					timeLeft = tInfo.timeLeft,
					leading = tIsOwnGuid(tInfo.bidder),
				}
			end
		end
	end
	gBids.rows = tRows
	gBids.state = "done"
	if not tCursorDeeperThan(gBids.entry) then tRebuildAndFocus(gBids.entry) end
end

local function tBidRowLabel(aRow)
	local tParts = { aRow.name }
	if aRow.leading then
		tParts[#tParts + 1] = L["your bid is highest"]
	else
		tParts[#tParts + 1] = L["outbid"]
	end
	if aRow.bidAmount and aRow.bidAmount > 0 then
		tParts[#tParts + 1] = L["bid "]..tMoneyText(aRow.bidAmount)
	end
	if aRow.buyoutAmount and aRow.buyoutAmount > 0 then
		tParts[#tParts + 1] = L["buyout "]..tMoneyText(aRow.buyoutAmount)
	end
	local tLeft = tTimeLeftText(aRow)
	if tLeft ~= "" then tParts[#tParts + 1] = L["left: "]..tLeft end
	return table.concat(tParts, ", ")
end

local function tAppendBidsChildren(aParent)
	if gBids.entry ~= aParent then return end
	if gBids.state == "waiting" then
		local tW = SkuOptions:InjectMenuItems(aParent, {L["Warten"]}, SkuGenericMenuItem)
		tW.dynamic = false
		return
	end
	if #gBids.rows == 0 then
		local tNone = SkuOptions:InjectMenuItems(aParent, {L["No bids"]}, SkuGenericMenuItem)
		tNone.dynamic = false
		return
	end
	for _, tRow in ipairs(gBids.rows) do
		local tE = SkuOptions:InjectMenuItems(aParent, {tBidRowLabel(tRow)}, SkuGenericMenuItem)
		tE.dynamic = true
		tE.data = tRow
		tE.BuildChildren = function(self)
			self.children = {}
			local tData = self.data
			if tData.buyoutAmount and tData.buyoutAmount > 0 then
				local tBuy = SkuOptions:InjectMenuItems(self, {L["Kaufen"]..": "..tMoneyText(tData.buyoutAmount)}, SkuGenericMenuItem)
				tBuy.dynamic = false
				tBuy.actionInPlace = true   -- ENTER runs the own action; otherwise an isSelect ancestor (search) redirects ENTER to the search
				tBuy.OnAction = function() AHF:BuyItemAuction(tData.auctionID, tData.buyoutAmount, tData.name) end
			end
			-- Raising a bid you already lead is pointless; offer it only after being outbid.
			local tCanBid = false
			if not tData.leading then tCanBid = tAddBidLeaves(self, tData, tData.name) end
			if not tCanBid and not (tData.buyoutAmount and tData.buyoutAmount > 0) then
				local tNothing = SkuOptions:InjectMenuItems(self, {tData.leading
					and L["You are the highest bidder, nothing to do"]
					or L["No bid possible"]}, SkuGenericMenuItem)
				tNothing.dynamic = false
			end
		end
	end
end

function AHF:BuildBidsChildren(aSelf)
	if aSelf.ahfEntering then
		AHF:StartBidsQuery(aSelf)
	elseif gBids.entry ~= aSelf then
		aSelf.children = {}
		return
	end
	aSelf.children = {}
	tAppendBidsChildren(aSelf)
end

local gBidEventFrame = CreateFrame("Frame")
for _, tEvent in ipairs({ "BIDS_UPDATED", "BID_ADDED", "AUCTION_HOUSE_CLOSED" }) do
	if Sku.IsEventValid(tEvent) then gBidEventFrame:RegisterEvent(tEvent) end
end
gBidEventFrame:SetScript("OnEvent", function(self, aEvent, ...)
	if aEvent == "BIDS_UPDATED" then
		AHF:RefreshBids()
	elseif aEvent == "BID_ADDED" then
		-- only while the auction house is open (the event is also sent for the login bid list)
		if _G.AuctionHouseFrame and _G.AuctionHouseFrame.IsShown and _G.AuctionHouseFrame:IsShown() then
			tSay(L["Bid placed"])
		end
		if gBids.entry and gBids.state ~= "idle" then AHF:StartBidsQuery(gBids.entry) end
	elseif aEvent == "AUCTION_HOUSE_CLOSED" then
		gBids.state, gBids.entry, gBids.rows = "idle", nil, {}
	end
end)

function AHF:BuildSalesChildren(aSelf)
	aSelf.children = {}
	local tNew = SkuOptions:InjectMenuItems(aSelf, {L["Create new auction"]}, SkuGenericMenuItem)
	tNew.dynamic = true
	tNew.BuildChildren = tBuildSellList

	local tOwned = SkuOptions:InjectMenuItems(aSelf, {L["Current sales"]}, SkuGenericMenuItem)
	tOwned.dynamic = true
	tMarkEntering(tOwned)
	tOwned.BuildChildren = function(self)
		if self.ahfEntering then
			AHF:StartOwnedQuery(self)
		elseif gOwned.entry ~= self then
			self.children = {}
			return
		end
		self.children = {}
		tAppendOwnedChildren(self)
	end
end

local gSellEventFrame = CreateFrame("Frame")
for _, tEvent in ipairs({ "OWNED_AUCTIONS_UPDATED", "AUCTION_CANCELED", "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_POST_WARNING", "AUCTION_HOUSE_POST_ERROR", "AUCTION_MULTISELL_FAILURE", "AUCTION_HOUSE_CLOSED" }) do
	if Sku.IsEventValid(tEvent) then gSellEventFrame:RegisterEvent(tEvent) end
end
gSellEventFrame:SetScript("OnEvent", function(self, aEvent, ...)
	if aEvent == "OWNED_AUCTIONS_UPDATED" then
		AHF:RefreshOwned()
	elseif aEvent == "AUCTION_CANCELED" then
		tSay(L["Auction canceled"])
		if gOwned.entry then
			local tPos = SkuOptions.currentMenuPosition
			if tPos and tPos.parent and tPos.parent.parent == gOwned.entry then
				SkuOptions.currentMenuPosition = gOwned.entry
			end
			AHF:StartOwnedQuery(gOwned.entry)
		end
	elseif aEvent == "AUCTION_HOUSE_AUCTION_CREATED" then
		local tName = gSell.name or ""
		gSell.pending = nil
		tSay(tName..": "..L["Auction posted"])
		C_Timer.After(0.7, function()
			local tKeep = gSell.duration
			gSell = { duration = tKeep }
			if gSellList and SkuOptions.currentMenuPosition then
				local tPos, tDepth = SkuOptions.currentMenuPosition, 0
				while tPos and tPos ~= gSellList and tDepth < 10 do tPos = tPos.parent tDepth = tDepth + 1 end
				if tPos == gSellList then
					SkuOptions:RebuildNodeChildren(gSellList, true)
					if gSellList.children and gSellList.children[1] then
						SkuOptions.currentMenuPosition = gSellList.children[1]
						tVocalize()
					end
				end
			end
		end)
	elseif aEvent == "AUCTION_HOUSE_POST_WARNING" then
		local tText = _G.CONFIRM_AUCTION_POSTING_TEXT
		if type(tText) == "string" and tText ~= "" then tSay(tText) end
	elseif aEvent == "AUCTION_HOUSE_POST_ERROR" then
		gSell.pending = nil
		tRefreshSellLabels()
		tSay(L["Posting not possible"])
	elseif aEvent == "AUCTION_MULTISELL_FAILURE" then
		tSay(L["Multi-posting failed"])
	elseif aEvent == "AUCTION_HOUSE_CLOSED" then
		local tKeep = gSell.duration
		gSell = { duration = tKeep }
		gSellList = nil
		gOwned.state, gOwned.entry, gOwned.rows = "idle", nil, {}
	end
end)

function AHF:BuildSearchEntries(aSelf)
	-- Mirrors SkuCore/auctionHouse.lua's tNewMenuEntrysearch as closely as possible (same flags, same
	-- OnAction/BuildChildren shape), only the data underneath is the new API. That legacy search entry is proven
	-- for this "type a name, browse results, drill into one, buy" flow.
	local tSearchEntry = SkuOptions:InjectMenuItems(aSelf, {L["auctions by seach string"]}, SkuGenericMenuItem)
	tSearchEntry.dynamic = true
	tSearchEntry.isSelect = true
	tSearchEntry.noStepUpAfterSelect = true
	tSearchEntry.sorting = true
	tSearchEntry.OnAction = function()
		SkuOptions:EditBoxShow("", function()
			local tText = SkuOptionsEditBoxEditBox:GetText()
			if not tText or tText == "" then return end
			AHF:StartBrowse(tText, tSearchEntry)
			tRebuildAndFocus(tSearchEntry, true)
		end, nil)
		C_Timer.After(0.1, function()
			SkuOptions.Voice:OutputStringBTtts(L["enter search string now"], true, true, 0.1, nil, nil, nil, 1)
		end)
	end
	tSearchEntry.BuildChildren = function(self)
		self.children = {}
		local tEnter = SkuOptions:InjectMenuItems(self, {L["enter search string"]}, SkuGenericMenuItem)
		tEnter.dynamic = false
		tAppendBrowseResultChildren(self)
	end

	-- Category browse ("Auktionen nach Kategorie") - reuses Blizzard's OWN
	-- AuctionCategories tree (built by Blizzard_AuctionData.lua when the AH
	-- addon loads: Waffen/Ruestung/Handelswaren/... with real, localized
	-- names and classID/subClassID/inventoryType filters per node), rather
	-- than maintaining a separate category list. Every node (not just leaves)
	-- carries its own accumulated .filters, so browsing works at any depth
	-- ("all weapons" as well as "one-handed swords only").
	local tCategoryEntry = SkuOptions:InjectMenuItems(aSelf, {L["Auctions by category"]}, SkuGenericMenuItem)
	tCategoryEntry.dynamic = true
	tCategoryEntry.BuildChildren = function(self)
		self.children = {}
		if type(AuctionCategories) == "table" and #AuctionCategories > 0 then
			tBuildCategoryChildren(self, AuctionCategories)
		else
			local tNone = SkuOptions:InjectMenuItems(self, {L["AH_CategoriesLoading"]}, SkuGenericMenuItem)
			tNone.dynamic = false
		end
	end

	-- Filters (Blizzard: the filter menu next to the search bar): apply to name search and categories, saved settings.
	local tFilterEntry = SkuOptions:InjectMenuItems(aSelf, {L["Filters"]}, SkuGenericMenuItem)
	tFilterEntry.dynamic = true
	tFilterEntry.BuildChildren = function(self)
		self.children = {}
		local tF = AHF:GetFilter()
		local tYes, tNo = L["yes"], L["no"]
		local function tToggle(aLabel, aKey)
			local function tName() return aLabel..": "..(tF[aKey] and tYes or tNo) end
			tSettingLeaf(self, tName(), function(aLeaf)
				tF[aKey] = (not tF[aKey]) or nil
				aLeaf.name = tName()
			end)
		end
		tToggle(L["Usable only"], "usable")
		tToggle(L["Upgrades only"], "upgrades")
		tToggle(L["Uncollected only"], "uncollected")
		tToggle(L["Current expansion only"], "currentExp")
		tToggle(L["Exact name for name searches"], "exact")
		local function tQualName()
			return L["Minimum quality: "]
				..(((tF.minQuality or 1) > 1) and tQualityName(tF.minQuality) or L["any"])
		end
		tSettingLeaf(self, tQualName(), function(aLeaf)
			local tQ = (tF.minQuality or 1) + 1
			if tQ > 7 then tQ = 1 end
			tF.minQuality = (tQ > 1) and tQ or nil
			aLeaf.name = tQualName()
		end)
		local function tLevelLeaf(aLabel, aKey)
			local function tName() return aLabel..": "..(tF[aKey] or L["any"]) end
			tSettingLeaf(self, tName(), function(aLeaf)
				SkuOptions:EditBoxShow("", function()
					local tText = SkuOptionsEditBoxEditBox:GetText() or ""
					local tN = tonumber(tText:match("%d+"))
					if tN and tN >= 1 then
						tF[aKey] = math.floor(tN)
					elseif tText == "" or tN == 0 then
						tF[aKey] = nil
					else
						tSay(L["Number not understood"])
					end
					aLeaf.name = tName()
					tVocalize()
				end, nil)
				C_Timer.After(0.1, function()
					SkuOptions.Voice:OutputStringBTtts(L["Enter level, empty or 0 for any"], true, true, 0.1, nil, nil, nil, 1)
				end)
			end)
		end
		tLevelLeaf(L["Level from"], "minLevel")
		tLevelLeaf(L["Level up to"], "maxLevel")
		tSettingLeaf(self, L["Reset all filters"], function()
			local tS = SkuSettings:Sub("SkuCore", nil, "char")
			tS.ahfFilter = {}
			tSay(L["Filters reset"])
			tRebuildAndFocus(self, true)
		end)
	end

	-- Favourite items (Blizzard: the star in the search bar); only where the server supports them.
	if tFavoritesAvailable() then
		local tFavEntry = SkuOptions:InjectMenuItems(aSelf, {L["Favorites"]}, SkuGenericMenuItem)
		tFavEntry.dynamic = true
		tMarkEntering(tFavEntry)
		tFavEntry.BuildChildren = function(self)
			if gBrowse.entry ~= self then
				if not self.ahfEntering then self.children = {} return end
				AHF:StartFavorites(self)
			end
			self.children = {}
			tAppendBrowseResultChildren(self)
		end
	end
end

-- Root: Auctions > [search, category]; below it (same level) Sales > [new auction, current sales]
function AHF:MenuBuilder(aSelf)
	local tAuctionsEntry = SkuOptions:InjectMenuItems(aSelf, {L["Auctions"]}, SkuGenericMenuItem)
	tAuctionsEntry.dynamic = true
	tAuctionsEntry.BuildChildren = function(self)
		self.children = {}
		AHF:BuildSearchEntries(self)
	end

	local tSales = SkuOptions:InjectMenuItems(aSelf, {L["Sales"]}, SkuGenericMenuItem)
	tSales.dynamic = true
	tSales.BuildChildren = function(selfSales) AHF:BuildSalesChildren(selfSales) end

	-- Auctions the player has bid on (Blizzard: Auctions tab > Bids).
	local tBidsEntry = SkuOptions:InjectMenuItems(aSelf, {L["My bids"]}, SkuGenericMenuItem)
	tBidsEntry.dynamic = true
	tMarkEntering(tBidsEntry)
	tBidsEntry.BuildChildren = function(selfBids) AHF:BuildBidsChildren(selfBids) end
end
