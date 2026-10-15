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
-- Menu: Auctions > [search by name, by category, filters, favorites]; Sales > [new auction, current sales]; Bids.
-- Browse: name search or category tree (Blizzard's own AuctionCategories), cheapest price and quantity per item.
-- Detail: an item's auctions with tooltip, buyout and bid below buyout; a commodity has one quantity and one Buy for the
--   cheapest pieces (two-step price quote), its price steps only inform; favorites.
-- Sell: pick an item from the bags, quantity, duration, price, deposit, market price hint, post (with the posting warning).
-- Own auctions: list, cancel. Own bids: list, buy out, bid again after being outbid.
-- Calls documented as HasRestrictions (PlaceBid, StartCommoditiesPurchase, PostItem, PostCommodity, ConfirmPostItem,
-- ConfirmPostCommodity, CancelAuction) run directly from a menu action, i.e. from a real key press.
-- ConfirmCommoditiesPurchase has no restriction; it runs from a key press as well, like Blizzard's Buy Now button.
-- Full scan (ReplicateItems) and the prices of browse results feed Sku's auction price history (see FULL SCAN).
-- =====================================================================

if not Sku or not Sku.isForever then return end

local L = Sku.L
local GetCoinText = Sku.Compat.GetCoinText

SkuCore.AuctionHouseForever = SkuCore.AuctionHouseForever or {}
local AHF = SkuCore.AuctionHouseForever

-- ---------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------
-- Browse = the result list of a name search, a category or the favorites (one row per distinct item).
local gBrowse = { state = "idle", results = {}, entry = nil }
-- Detail = the individual listings of ONE item, opened by drilling into a
-- browse row.
local gDetail = { state = "idle", itemKey = nil, isCommodity = false, results = {}, entry = nil }
-- CommodityBuy = the two-step quote/confirm dance StartCommoditiesPurchase
-- requires (see Blizzard's own Blizzard_AuctionHouseBuyDialog.lua).
local gCommodityBuy = { itemID = nil, quantity = nil, unitPrice = nil, totalPrice = nil, entry = nil }
-- Sell = the draft of the item being put up for auction (see SELL below). Replaced as a whole for another item;
-- the chosen duration carries over.
local gSell = { duration = nil }
-- A Sku post on its way to the server. gSell.posting alone also covers a post waiting for its confirmation
-- (gSell.pending), which has sent nothing yet.
local function tPostInFlight()
	return gSell.posting and not gSell.pending
end

local function tMoneyText(aCopper)
	return GetCoinText(aCopper, " ")
end

-- Shared small helpers (used by browse, detail, bids, sell and own auctions below).
local function tSay(aText)
	SkuOptions.Voice:OutputStringBTtts(aText, false, true, 0.2)
end

-- Time left of an auction: exact seconds when the server sends them, else Blizzard's band
-- (AuctionHouseTimeLeftBand 0..3: short .. very long).
local function tTimeLeftText(aInfo)
	local tSec = aInfo.timeLeftSeconds
	if tSec and tSec > 0 then
		if tSec >= 3600 then return math.floor(tSec / 3600 + 0.5)..L[" Stunden"] end
		return math.max(1, math.floor(tSec / 60 + 0.5))..L[" Minuten"]
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

-- A menu leaf whose ENTER runs aOnAction(leaf) in place (buy, bid, value toggles, "load more", ...). actionInPlace:
-- otherwise an isSelect ancestor (the name search) takes ENTER over for its own action.
local function tSettingLeaf(aParent, aName, aOnAction)
	local tE = SkuOptions:InjectMenuItems(aParent, {aName}, SkuGenericMenuItem)
	tE.dynamic = false
	tE.actionInPlace = true
	tE.OnAction = aOnAction
	return tE
end

local function tIsOwnGuid(aGuid)
	return aGuid ~= nil and aGuid == Sku.SafeGUID("player")
end

local function tVocalize()
	SkuOptions:VocalizeCurrentMenuName()
end

-- Coin unit words: L["AHF_MoneyUnitsGold"], ...Silver, ...Copper hold a comma-separated word list per language
-- ("g,gold"), each list also carries the letters of the example in the prompts ("12g 5s 3k").
local gMoneyUnits
local function tMoneyUnit(aWord)
	if not gMoneyUnits then
		gMoneyUnits = {}
		for tKey, tCopper in pairs({ AHF_MoneyUnitsGold = 10000, AHF_MoneyUnitsSilver = 100, AHF_MoneyUnitsCopper = 1 }) do
			for tUnit in L[tKey]:lower():gmatch("[^,%s]+") do gMoneyUnits[tUnit] = tCopper end
		end
	end
	return gMoneyUnits[aWord]
end

-- "1.5" or "1,5" times aMult as whole copper; nil when that is not a whole copper amount.
local function tNumberTimes(aNum, aMult)
	local tInt, tFrac = aNum:match("^(%d+)%.?(%d*)$")
	if not tInt then return nil end
	local tScale = 10 ^ #tFrac
	local tFracCopper = (tonumber(tFrac) or 0) * aMult
	if tFracCopper % tScale ~= 0 then return nil end
	return tonumber(tInt) * aMult + tFracCopper / tScale
end

-- Money typed by the player, in copper; nil = not understood. A bare number is gold ("75", "1.5" = 1 gold
-- 50 silver). Otherwise number+unit groups: "12g 5s 3k", "1,5 g", "2 gold 50 silver". "." and "," are decimal
-- marks. Refused: a number without its unit ("2g50", "12 gold 5"), a unit given twice, exponents ("1e3"),
-- fractions of a copper, zero. Without copper values on the server the amount is rounded to whole silver.
local function tParseMoney(aText)
	local tS = aText:lower():gsub(",", "."):match("^%s*(.-)%s*$")
	local tTotal
	if tS:find("^%d+%.?%d*$") then
		tTotal = tNumberTimes(tS, 10000)
	else
		tTotal = 0
		local tPos, tSeen = 1, {}
		while tTotal and tPos <= #tS do
			local tNum, tWord, tNext = tS:match("^(%d+%.?%d*)%s*(%a+)%s*()", tPos)
			local tMult = tWord and tMoneyUnit(tWord)
			if not tMult or tSeen[tMult] then return nil end
			tSeen[tMult] = true
			local tPart = tNumberTimes(tNum, tMult)
			tTotal = tPart and (tTotal + tPart)
			tPos = tNext
		end
	end
	if not tTotal or tTotal <= 0 then return nil end
	if not C_AuctionHouse.SupportsCopperValues() then tTotal = math.max(100, math.floor(tTotal / 100 + 0.5) * 100) end
	return tTotal
end

-- A whole number of pieces, at least 1; nil = not understood.
local function tParseQuantity(aText)
	local tN = tonumber(aText:match("^%s*(%d+)%s*$"))
	if tN and tN >= 1 then return tN end
end

-- Asks for a value in the edit box, reads it with aParse and hands the result to aApply, then reads the menu
-- position again. aParse returns nil for input it does not understand: then only aFailText is said. Only the
-- answer is read here - anything protected (bids, buying, posting) happens afterwards in a separate menu action
-- from a real key press.
local function tAskValue(aPrompt, aParse, aFailText, aApply)
	SkuOptions:EditBoxShow("", function()
		local tText = SkuOptionsEditBoxEditBox:GetText()
		if tText ~= "" then
			local tValue = aParse(tText)
			if tValue == nil then
				tSay(aFailText)
				return
			end
			aApply(tValue)
		end
		tVocalize()
	end, nil)
	C_Timer.After(0.1, function()
		SkuOptions.Voice:OutputStringBTtts(aPrompt, true, true, 0.1, nil, nil, nil, 1)
	end)
end

-- A money amount ("12g 5s 3k", "1.5" = 1 gold 50 silver), handed to aApply in copper.
local function tAskMoney(aPrompt, aApply)
	tAskValue(aPrompt, tParseMoney, L["Amount not understood"], aApply)
end

-- The child of aEntry on the way down to the cursor, and how many levels below aEntry the cursor stands (1 = on
-- that child). nil when the cursor is not below aEntry.
local function tCursorChildOf(aEntry)
	local tChild, tDepth = SkuOptions.currentMenuPosition, 1
	while tChild and tChild.parent ~= aEntry do
		tChild, tDepth = tChild.parent, tDepth + 1
	end
	return tChild, tDepth
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
	local tChild = tCursorChildOf(aEntry)
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
-- An error in the original OnPostSelect propagates to the key handler unchanged; the
-- next-frame clear removes the flag in that case too.
local function tMarkEntering(aNode)
	local tOrig = aNode.OnPostSelect or SkuGenericMenuItem.OnPostSelect
	aNode.OnPostSelect = function(self, ...)
		self.ahfEntering = true
		C_Timer.After(0, function() self.ahfEntering = nil end)
		tOrig(self, ...)
		self.ahfEntering = nil
	end
end

-- The only child of a node that builds its children on entering only (see tMarkEntering) and was merely landed
-- on: the menu announces "plus" only for a node with children, and entering rebuilds the children through
-- OnPostSelect, which replaces the placeholder.
local function tPlaceholderChild(aNode)
	aNode.children = {}
	local tPlaceholder = SkuOptions:InjectMenuItems(aNode, {L["Warten"]}, SkuGenericMenuItem)
	tPlaceholder.dynamic = false
end

-- For a node that shows the answer of a query in aState (gBrowse or gDetail): entering it runs
-- aStart unless the node's own query is current; a failed query runs again. Returns true when
-- the node has something to show. When it was only landed on, the node gets the placeholder
-- child and false comes back.
local function tQueryOnEnter(aNode, aState, aStart)
	local tMine = aState.entry == aNode and aState.state ~= "idle"
	if aNode.ahfEntering and (not tMine or aState.state == "failed") then
		aStart()
		return true
	end
	if tMine then return true end
	tPlaceholderChild(aNode)
	return false
end

-- ---------------------------------------------------------------------
-- Throttled queries. Auction house queries go through the client's throttled message system;
-- one sent while IsThrottledMessageSystemReady is false is queued or dropped by the client
-- (AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED / _DROPPED). So a query is parked in
-- aState.pendingSend and sent on AUCTION_HOUSE_THROTTLED_SYSTEM_READY, oldest first, one per
-- ready signal (a sent query uses up the throttle again).
-- aState: the query's state table (gBrowse, gDetail, gOwned, gBids, the sell draft for its market
-- lookup). Only for queries that are not protected: a parked call runs from an event, not from a key press.
-- ---------------------------------------------------------------------
local gThrottleWaiting = {}

local function tSendThrottled(aState, aSend, ...)
	if C_AuctionHouse.IsThrottledMessageSystemReady() then
		aState.pendingSend = nil
		aSend(...)
		return
	end
	dprint("ahf", "query parked until the throttle is ready")
	aState.pendingSend = { send = aSend, args = { n = select("#", ...), ... } }
	for _, tState in ipairs(gThrottleWaiting) do
		if tState == aState then return end
	end
	gThrottleWaiting[#gThrottleWaiting + 1] = aState
end

local function tSendParked()
	while gThrottleWaiting[1] and C_AuctionHouse.IsThrottledMessageSystemReady() do
		local tState = table.remove(gThrottleWaiting, 1)
		local tPending = tState.pendingSend
		if tPending then
			tState.pendingSend = nil
			tPending.send(unpack(tPending.args, 1, tPending.args.n))
		end
	end
end

-- No answer in time: the list says the query was never sent (throttle busy) or never answered,
-- instead of staying on "Warten" or claiming "no results". aState.answered (results arrived, item
-- names still loading) shows what is known. A newer query (generation) cancels the timeout.
local function tFailOnTimeout(aState, aSeconds)
	local tGen = aState.generation
	C_Timer.After(aSeconds, function()
		if aState.generation ~= tGen or aState.state ~= "waiting" then return end
		if aState.answered then
			aState.state = "done"
		else
			aState.failText = aState.pendingSend and L["AH_QueryBusy"] or L["STRAT_SearchTimeout"]
			aState.state = "failed"
			dprint("ahf", "query timeout:", aState.failText)
		end
		aState.pendingSend = nil
		tRebuildAndFocus(aState.entry)
	end)
end

-- ---------------------------------------------------------------------
-- BROWSE (search by name OR by category - both are just a browse query with
-- different fields set: a name search sets searchString, a category browse
-- sets itemClassFilters with an empty searchString. Same result shape, same
-- state, same result-list UI either way.)
-- ---------------------------------------------------------------------
-- aSend (optional): replaces the plain SendBrowseQuery call, e.g. SearchForFavorites - the
-- answer arrives through the same browse events and is read the same way. aQuery is aSend's
-- argument: the query table for SendBrowseQuery, the sorts for SearchForFavorites.
function AHF:StartBrowseQuery(aQuery, aEntry, aSend)
	gBrowse.state = "waiting"
	gBrowse.answered = nil
	gBrowse.results = {}
	gBrowse.seenBefore = nil
	gBrowse.entry = aEntry
	gBrowse.failText = nil
	gBrowse.filterSummary = nil
	gBrowse.generation = (gBrowse.generation or 0) + 1
	tSendThrottled(gBrowse, aSend or C_AuctionHouse.SendBrowseQuery, aQuery)
	tFailOnTimeout(gBrowse, 10)
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

-- Blizzard's default sort orders (Blizzard_AuctionHouseFrame.lua, InitAuctionHouseSortsBySearchContext):
-- browse and favorites by price, then name; an item's listings by buyout, then bid; commodities unsorted.
local AHF_BROWSE_SORTS = {
	{ sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
	{ sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = false },
}
local AHF_ITEM_SORTS = {
	{ sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false },
	{ sortOrder = Enum.AuctionHouseSortOrder.Bid, reverseSort = false },
}

-- Sets filters and level range like Blizzard's search bar: AUCTION_HOUSE_DEFAULT_FILTERS (all item
-- qualities on) with the player's choices applied, every active filter in the array, level 0 = any.
-- aIsName: name search (the exact-name filter only applies there).
function AHF:ApplyFilterToQuery(aQuery, aIsName)
	local f = AHF:GetFilter()
	local E = Enum.AuctionHouseFilter
	local tOn = CopyTable(AUCTION_HOUSE_DEFAULT_FILTERS)
	if f.usable then tOn[E.UsableOnly] = true end
	if f.upgrades then tOn[E.UpgradesOnly] = true end
	if f.uncollected then tOn[E.UncollectedOnly] = true end
	if f.currentExp then tOn[E.CurrentExpansionOnly] = true end
	if f.exact and aIsName then tOn[E.ExactMatch] = true end
	for i = 1, (f.minQuality or 1) - 1 do
		tOn[E[AHF_QUALITY_FILTERS[i]]] = false
	end
	local tList = {}
	for tFilter, tActive in pairs(tOn) do
		if tActive then tList[#tList + 1] = tFilter end
	end
	aQuery.filters = tList
	aQuery.minLevel = f.minLevel or 0
	aQuery.maxLevel = f.maxLevel or 0
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
	local tQuery = { searchString = aSearchText, sorts = AHF_BROWSE_SORTS, itemClassFilters = {} }
	AHF:ApplyFilterToQuery(tQuery, true)
	AHF:StartBrowseQuery(tQuery, aEntry)
	gBrowse.filterSummary = AHF:FilterSummary()
end

-- The player's favourite items (Blizzard: the star in the search bar). Same result shape as a
-- name search, so it feeds the same list.
function AHF:StartFavorites(aEntry)
	AHF:StartBrowseQuery(AHF_BROWSE_SORTS, aEntry, C_AuctionHouse.SearchForFavorites)
end

-- aFilters: one category's accumulated {classID, subClassID, inventoryType}
-- list (see AuctionCategories in the menu section below) - every level of
-- the category tree carries its own, from the leaf up to the top category.
function AHF:StartCategoryBrowse(aFilters, aEntry)
	local tQuery = { searchString = "", itemClassFilters = aFilters, sorts = AHF_BROWSE_SORTS }
	AHF:ApplyFilterToQuery(tQuery, false)
	AHF:StartBrowseQuery(tQuery, aEntry)
	gBrowse.filterSummary = AHF:FilterSummary()
end

-- Re-reads the full current browse result set. GetBrowseResults returns the whole set, so
-- "…UPDATED" (full refresh) and "…ADDED" (next page) both funnel here.
-- While Sku's own query is still parked (pendingSend), every browse answer belongs to someone
-- else's query, e.g. the favorites query Blizzard's AuctionHouseFrame sends on show.
function AHF:RefreshBrowseResults()
	if gBrowse.state ~= "waiting" and gBrowse.state ~= "done" then return end
	if gBrowse.pendingSend then return end
	local tRaw = C_AuctionHouse.GetBrowseResults()
	-- Blizzard's list: no rows and HasFullBrowseResults = "no results"; no rows and not full = still pending.
	if #tRaw == 0 and not C_AuctionHouse.HasFullBrowseResults() then return end
	gBrowse.answered = true
	AHF:FeedBrowsePrices(tRaw)
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
			-- Name not cached yet: ITEM_KEY_ITEM_INFO_RECEIVED fires once the server answers
			-- and runs this refresh again.
			tStillPending = true
		end
	end
	gBrowse.results = tRows
	-- Names still loading: the list is rebuilt once, when the last one is in.
	if tStillPending then
		gBrowse.state = "waiting"
		return
	end
	gBrowse.state = "done"
	tRebuildAndFocus(gBrowse.entry)
	gBrowse.seenBefore = nil
end

-- ---------------------------------------------------------------------
-- DETAIL (individual listings of one item, after drilling into a browse row)
-- ---------------------------------------------------------------------
function AHF:StartDetail(aRow, aEntry)
	gDetail.state = "waiting"
	gDetail.itemKey = aRow.itemKey
	gDetail.seenBefore = nil
	gDetail.isCommodity = aRow.isCommodity
	gDetail.name = aRow.name
	gDetail.results = {}
	-- A commodity's quantity to buy; Blizzard's buy display starts at 1 as well.
	gDetail.buyQty = 1
	gDetail.buyLoading = nil
	gDetail.buyRefreshing = nil
	gCommodityBuy.notice = nil
	gDetail.entry = aEntry
	gDetail.failText = nil
	gDetail.generation = (gDetail.generation or 0) + 1
	if aRow.isCommodity then
		tSendThrottled(gDetail, C_AuctionHouse.SendSearchQuery, aRow.itemKey, {}, false)
	else
		local f = AHF:GetFilter()
		tSendThrottled(gDetail, C_AuctionHouse.SendSearchQuery, aRow.itemKey, AHF_ITEM_SORTS, false, f.minLevel or 0, f.maxLevel or 0)
	end
	tFailOnTimeout(gDetail, 6)
end

-- After a purchase: the open listings again, through the throttle and with the same sorts, as Blizzard's
-- RefreshSearchResults. The answer updates the list in place (state stays "done"); the identities keep the cursor.
-- Returns true when the query went out (or waits for the throttle).
function AHF:RequeryDetail(aItemID)
	if gDetail.state ~= "done" or not gDetail.itemKey or gDetail.itemKey.itemID ~= aItemID then return false end
	if gDetail.isCommodity then
		tSendThrottled(gDetail, C_AuctionHouse.SendSearchQuery, gDetail.itemKey, {}, false)
	else
		local f = AHF:GetFilter()
		tSendThrottled(gDetail, C_AuctionHouse.SendSearchQuery, gDetail.itemKey, AHF_ITEM_SORTS, false, f.minLevel or 0, f.maxLevel or 0)
	end
	return true
end

function AHF:RefreshDetailResults(aItemID)
	if (gDetail.state ~= "waiting" and gDetail.state ~= "done") or not gDetail.itemKey then return end
	-- Not sent yet: an answer now belongs to another query for the same item.
	if gDetail.pendingSend then return end
	if aItemID and aItemID ~= gDetail.itemKey.itemID then return end
	-- One row per result (GetNum*SearchResults), not per piece: the *Quantity functions count
	-- the pieces for sale, thousands for a common herb.
	local tRows = {}
	if gDetail.isCommodity then
		local tItemID = gDetail.itemKey.itemID
		local tNum = C_AuctionHouse.GetNumCommoditySearchResults(tItemID)
		if tNum == 0 and not C_AuctionHouse.HasFullCommoditySearchResults(tItemID) then return end
		for i = 1, tNum do
			local tResult = C_AuctionHouse.GetCommoditySearchResultInfo(tItemID, i)
			if tResult then
				tRows[#tRows + 1] = {
					unitPrice = tResult.unitPrice,
					quantity = tResult.quantity,
					isOwn = tResult.containsOwnerItem,
				}
			end
		end
	else
		local tNum = C_AuctionHouse.GetNumItemSearchResults(gDetail.itemKey)
		if tNum == 0 and not C_AuctionHouse.HasFullItemSearchResults(gDetail.itemKey) then return end
		for i = 1, tNum do
			local tResult = C_AuctionHouse.GetItemSearchResultInfo(gDetail.itemKey, i)
			if tResult then
				tRows[#tRows + 1] = {
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
	gDetail.results = tRows
	gDetail.state = "done"
	local tWasLoading = gDetail.buyLoading or gDetail.buyRefreshing
	-- The fresh offers after an ended purchase (AHF:EndCommodityBuy): its reason was spoken, the Buy leaf now
	-- carries the current price instead.
	if gDetail.buyRefreshing then
		gDetail.buyRefreshing = nil
		gCommodityBuy.notice = nil
	end
	tRebuildAndFocus(gDetail.entry)
	gDetail.seenBefore = nil
	-- The rows a commodity's Buy leaf waited for are in: a cursor on that leaf hears its price now.
	local tPos = SkuOptions.currentMenuPosition
	if tWasLoading and not gDetail.buyLoading and tPos and tPos.skuIdentity == "commodity:buy" then tSay(tPos.name) end
end

-- ---------------------------------------------------------------------
-- BUY - regular (non-commodity) item: buyout is a single protected call (PlaceBid with the buyout amount),
-- made directly from the key press (OnAction).
-- ---------------------------------------------------------------------
-- Sku's own buyout or bid in flight. The server answers a buyout with AUCTION_HOUSE_PURCHASE_COMPLETED(auctionID),
-- a bid with BID_ADDED, a refusal of either with AUCTION_HOUSE_SHOW_ERROR (the events Blizzard's BUYOUT_AUCTION
-- popup waits for). Nothing is spoken when the call goes out: the answer is the result.
local gItemPurchase = { auctionID = nil, name = nil, isBuyout = false }
-- Sku's cancel on its way to the server: {data = the row's data, leaf = its cancel leaf}. The server
-- answers with AUCTION_CANCELED or refuses with AUCTION_HOUSE_SHOW_ERROR (see AHF:OnShowError).
local gCancel = nil

-- A refusal from a key press. The key handler vocalizes the focused leaf right after its OnAction and cuts off any
-- line spoken before, so the reason goes into the leaf's name. Without a leaf the reason is spoken, named by aName.
local function tRefuse(aLeaf, aName, aText)
	if aLeaf then
		aLeaf.ahfBaseName = aLeaf.ahfBaseName or aLeaf.name
		aLeaf.name = aLeaf.ahfBaseName..";"..aText
	else
		tSay((aName and (aName..": ") or "")..aText)
	end
end

-- aLeaf: the menu leaf whose key press runs this (see tRefuse).
function AHF:BuyItemAuction(aAuctionID, aBuyoutAmount, aName, aLeaf)
	if GetMoney() < aBuyoutAmount then
		tRefuse(aLeaf, aName, L["Nicht genug Geld"])
		return
	end
	gItemPurchase.auctionID, gItemPurchase.name, gItemPurchase.isBuyout = aAuctionID, aName, true
	dprint("ahf", "buyout", aAuctionID, aBuyoutAmount)
	C_AuctionHouse.PlaceBid(aAuctionID, aBuyoutAmount)
end

function AHF:OnItemPurchaseCompleted(aAuctionID)
	if aAuctionID ~= gItemPurchase.auctionID then return end
	gItemPurchase.auctionID = nil
	tSay((gItemPurchase.name and (gItemPurchase.name..": ") or "")..L["Purchase complete"])
	-- The bought auction leaves the detail list: fresh listings, as Blizzard's RefreshSearchResults after a purchase.
	for _, tRow in ipairs(gDetail.results) do
		if tRow.auctionID == aAuctionID then
			AHF:RequeryDetail(gDetail.itemKey.itemID)
			return
		end
	end
end

-- ---------------------------------------------------------------------
-- BUY - commodity: StartCommoditiesPurchase (quote) -> COMMODITY_PRICE_UPDATED
-- (the quoted price becomes the item's summary leaf) -> ConfirmCommoditiesPurchase (second real
-- keypress). Mirrors Blizzard's own Blizzard_AuctionHouseBuyDialog.lua flow.
-- StartCommoditiesPurchase is HasRestrictions and runs from a key press;
-- ConfirmCommoditiesPurchase has no restriction and runs from the Confirm key press.
-- ---------------------------------------------------------------------
-- Blizzard_AuctionHouseBuyDialog.lua: a quoted unit price above preview * 1.05 counts as "price unavailable".
local MAXIMUM_PREVIEW_PRICE_DIFFERENTIAL = 1.05

-- What the commodity's Buy leaf buys: gDetail.buyQty pieces, priced by Blizzard's
-- AuctionHouseUtil.AggregateSearchResultsByQuantity over the rows loaded so far (cheapest first, never the player's own
-- pieces). When those rows do not cover the quantity and the server has more, the next rows are asked for, as
-- Blizzard's list does while the selection reaches its end, and nil comes back: COMMODITY_SEARCH_RESULTS_ADDED
-- rebuilds the detail and this runs again. With every row loaded the quantity is cut to what other players offer.
-- Returns the quantity, the total price and the highest unit price paid; 0 when other players offer nothing.
local function tCommodityPreview()
	-- The offers are being reloaded after an ended purchase: the loaded rows are the old ones.
	if gDetail.buyRefreshing then return nil end
	local tItemID = gDetail.itemKey.itemID
	local tQty, tTotal, tNum = AuctionHouseUtil.AggregateSearchResultsByQuantity(tItemID, gDetail.buyQty)
	gDetail.buyLoading = nil
	if tQty < gDetail.buyQty then
		-- RequestMoreCommoditySearchResults returns true when the result is already complete.
		if not C_AuctionHouse.HasFullCommoditySearchResults(tItemID) and not C_AuctionHouse.RequestMoreCommoditySearchResults(tItemID) then
			gDetail.buyLoading = true
			return nil
		end
		if tQty == 0 then
			gDetail.buyQty = 1
			return 0
		end
		gDetail.buyQty = tQty
		tQty, tTotal, tNum = AuctionHouseUtil.AggregateSearchResultsByQuantity(tItemID, tQty)
	end
	-- The last row the aggregation reached is the last one it took pieces from.
	return tQty, tTotal, C_AuctionHouse.GetCommoditySearchResultInfo(tItemID, tNum).unitPrice
end

-- The most the quantity can be: what other players offer once every row is loaded, before that the server's piece
-- count (GetCommoditySearchResultsQuantity, the cap of Blizzard's list).
local function tCommodityOffered()
	local tItemID = gDetail.itemKey.itemID
	if C_AuctionHouse.HasFullCommoditySearchResults(tItemID) then
		return (AuctionHouseUtil.AggregateSearchResultsByQuantity(tItemID, math.huge))
	end
	return C_AuctionHouse.GetCommoditySearchResultsQuantity(tItemID)
end

local function tCommodityQuantityLabel()
	return L["Quantity: "]..gDetail.buyQty..L[" of at most "]..tCommodityOffered()
end

-- ", up to <price> each" when the pieces do not all cost the same.
local function tUpToText(aQty, aTotal, aHigh)
	if aTotal < aHigh * aQty then return ", "..string.format(L["up to %s each"], tMoneyText(aHigh)) end
	return ""
end

-- aQty, aTotal, aHigh: tCommodityPreview's answer.
local function tCommodityBuyLabel(aQty, aTotal, aHigh)
	local tText = L["Kaufen"]..": "
	if not aQty then
		return tText..gDetail.buyQty.." "..L["STRAT_Pieces"]..";"..(gDetail.buyRefreshing and L["Reloading the offers"] or L["Loading more auctions"])
	end
	if aQty == 0 then return tText..AUCTION_HOUSE_TOOLTIP_TITLE_NONE_AVAILABLE end
	return tText..aQty.." "..L["STRAT_Pieces"]..", "..tMoneyText(aTotal)..tUpToText(aQty, aTotal, aHigh)
end

-- The child of the detail entry with aIdentity. Looked up, not kept: tRebuildAndFocus's re-pin keeps the old node of
-- the cursor's leaf in place of the new one.
local function tDetailChild(aIdentity)
	for _, tChild in ipairs(gDetail.entry.children) do
		if tChild.skuIdentity == aIdentity then return tChild end
	end
end

-- New names for the Quantity and Buy leaves after the quantity changed. Returns the Buy leaf and tCommodityPreview's
-- answer.
local function tCommodityRelabel()
	local tQty, tTotal, tHigh = tCommodityPreview()
	local tBuy = tDetailChild("commodity:buy")
	tBuy.name = tCommodityBuyLabel(tQty, tTotal, tHigh)
	tBuy.ahfBaseName = nil
	tDetailChild("commodity:quantity").name = tCommodityQuantityLabel()
	return tBuy, tQty, tTotal, tHigh
end

-- aTotal, aHigh: the preview (tCommodityPreview). aLeaf: the Buy leaf whose key press runs this (see tRefuse).
-- Returns true when the quote was requested.
function AHF:StartCommodityBuy(aItemID, aQuantity, aTotal, aHigh, aEntry, aName, aLeaf)
	if GetMoney() < aTotal then
		tRefuse(aLeaf, aName, L["Nicht genug Geld"])
		return false
	end
	-- One quote at a time: the server refuses a second one (ItemHasQuote) while the first is open.
	if gCommodityBuy.itemID then C_AuctionHouse.CancelCommoditiesPurchase() end
	gCommodityBuy.itemID = aItemID
	gCommodityBuy.quantity = aQuantity
	gCommodityBuy.unitPrice = nil
	gCommodityBuy.totalPrice = nil
	gCommodityBuy.summary = nil
	gCommodityBuy.notice = nil
	gCommodityBuy.confirming = false
	gCommodityBuy.preview = { total = aTotal, high = aHigh }
	gCommodityBuy.entry = aEntry
	gCommodityBuy.name = aName
	gCommodityBuy.generation = (gCommodityBuy.generation or 0) + 1
	local tGen = gCommodityBuy.generation
	dprint("ahf", "commodity quote", aItemID, aQuantity, aTotal)
	C_AuctionHouse.StartCommoditiesPurchase(aItemID, aQuantity)
	-- Ended already (an answer during the call): the Buy leaf is in place and carries the reason.
	if not gCommodityBuy.itemID then return false end
	-- If the game does not answer with a price, do not hang silently.
	C_Timer.After(4, function()
		if gCommodityBuy.itemID and gCommodityBuy.generation == tGen and not gCommodityBuy.unitPrice then
			AHF:EndCommodityBuy(L["No price confirmation from the game. Please try again."])
		end
	end)
	return true
end

-- Ends Sku's commodity purchase the way Blizzard's buy dialog closes (AuctionHouseBuyDialogMixin:OnHide): drops the
-- quote and sends the item's search again so the prices are current. The cursor goes to the Buy leaf, which reads
-- aReason and "reloading the offers" and is spoken right away: most ends arrive as server events, not after a key
-- press, and the cursor may sit on a leaf of the same identity, which a rebuild re-pins silently. When the fresh
-- offers are in (AHF:RefreshDetailResults) the leaf drops the reason and is spoken again with the current price, so
-- Enter buys at that price. Does nothing when no purchase of Sku's is running. aFromKey: called from a key press,
-- whose handler vocalizes the cursor itself.
function AHF:EndCommodityBuy(aReason, aFromKey)
	if not gCommodityBuy.itemID then return end
	local tItemID, tEntry = gCommodityBuy.itemID, gCommodityBuy.entry
	dprint("ahf", "commodity buy end", tItemID, aReason)
	C_AuctionHouse.CancelCommoditiesPurchase()
	gCommodityBuy.itemID = nil
	gCommodityBuy.confirming = false
	gCommodityBuy.notice = aReason
	-- Set before the query: its answer clears it.
	local tToken = {}
	gDetail.buyRefreshing = tToken
	if not AHF:RequeryDetail(tItemID) then gDetail.buyRefreshing = nil end
	tRebuildAndFocus(tEntry, true, true)
	local tBuy = tEntry == gDetail.entry and tDetailChild("commodity:buy")
	if tBuy then SkuOptions.currentMenuPosition = tBuy end
	if not aFromKey then tVocalize() end
	if not gDetail.buyRefreshing then
		gCommodityBuy.notice = nil
		return
	end
	-- No answer: the leaf must not stay on "reloading" (tFailOnTimeout's span for a detail query).
	C_Timer.After(6, function()
		if gDetail.buyRefreshing ~= tToken then return end
		gDetail.buyRefreshing = nil
		gCommodityBuy.notice = nil
		tRebuildAndFocus(gDetail.entry)
		local tPos = SkuOptions.currentMenuPosition
		if tPos and tPos.skuIdentity == "commodity:buy" then tSay(tPos.name) end
	end)
end

-- The quote. Checked like Blizzard's buy dialog: more than 5% above the preview ends the purchase. Otherwise the item
-- shows one summary leaf (price and every warning) with the cursor on it, and Confirm second, so a second Enter
-- pressed too early only repeats the summary.
function AHF:OnCommodityPriceUpdated(aUnitPrice, aTotalPrice)
	if not gCommodityBuy.itemID or gCommodityBuy.confirming then return end
	local tPreview = gCommodityBuy.preview
	local tPreviewUnit = tPreview.total / gCommodityBuy.quantity
	if aUnitPrice > tPreviewUnit * MAXIMUM_PREVIEW_PRICE_DIFFERENTIAL then
		AHF:EndCommodityBuy(string.format(L["Purchase cancelled: the unit price is now %s instead of %s, more than 5 percent above the listings"],
			tMoneyText(aUnitPrice), tMoneyText(math.ceil(tPreviewUnit))))
		return
	end
	gCommodityBuy.unitPrice = aUnitPrice
	gCommodityBuy.totalPrice = aTotalPrice
	-- Several price levels (e.g. only 1 piece at 19, the second costs 21): the highest unit price of the preview.
	local tParts = { string.format(L["%s: %s pieces, total price %s"], gCommodityBuy.name or "", gCommodityBuy.quantity, tMoneyText(aTotalPrice))
		..tUpToText(gCommodityBuy.quantity, tPreview.total, tPreview.high) }
	-- Someone bought or posted since the listings were read.
	if aTotalPrice ~= tPreview.total then
		tParts[#tParts + 1] = string.format(L["The price changed since it was listed: expected %s, now %s."],
			tMoneyText(tPreview.total), tMoneyText(aTotalPrice))
	end
	if GetMoney() < aTotalPrice then tParts[#tParts + 1] = L["Nicht genug Geld"] end
	tParts[#tParts + 1] = L["Confirm or cancel?"]
	gCommodityBuy.summary = table.concat(tParts, ";")
	tRebuildAndFocus(gCommodityBuy.entry, true)
end

-- aLeaf: the Confirm leaf; aGeneration: the purchase it was built for, so a leaf left over from an earlier quote
-- never confirms a newer one.
function AHF:ConfirmCommodityBuy(aLeaf, aGeneration)
	if not gCommodityBuy.itemID or not gCommodityBuy.unitPrice or gCommodityBuy.generation ~= aGeneration then
		aLeaf.name = L["No purchase is waiting for confirmation"]
		return
	end
	-- In flight: the leaf already says so; repeat presses do nothing until SUCCEEDED or FAILED.
	if gCommodityBuy.confirming then return end
	if C_AuctionHouse.GetQuoteDurationRemaining() == 0 then
		AHF:EndCommodityBuy(L["Purchase cancelled: the price quote has expired"], true)
		return
	end
	if GetMoney() < gCommodityBuy.totalPrice then
		tRefuse(aLeaf, nil, L["Nicht genug Geld"])
		return
	end
	gCommodityBuy.confirming = true
	aLeaf.name = L["Purchasing"]
	dprint("ahf", "commodity confirm", gCommodityBuy.itemID, gCommodityBuy.quantity, gCommodityBuy.totalPrice)
	C_AuctionHouse.ConfirmCommoditiesPurchase(gCommodityBuy.itemID, gCommodityBuy.quantity)
end

-- ---------------------------------------------------------------------
-- Menu
-- ---------------------------------------------------------------------
-- Tooltip text of an auction house item (read with Shift+Down etc.). The same source as Blizzard's
-- AuctionHouseUtil.SetAuctionHouseTooltip: the listing's link when it has one (without the vendor price), else the
-- item key with its required level. nil while the item is not cached; the data is requested then.
local function tAhItemTooltipText(aItemKey, aLink)
	local tLines = SkuCore:TooltipDataLines(aLink and C_TooltipInfo.GetHyperlink(aLink, nil, nil, true)
		or C_TooltipInfo.GetItemKey(aItemKey.itemID, aItemKey.itemLevel, aItemKey.itemSuffix, C_AuctionHouse.GetItemKeyRequiredLevel(aItemKey)))
	if not tLines or SkuUtil:IsRetrievingItemInfo(tLines[1]) then
		C_Item.RequestLoadItemDataByID(aItemKey.itemID)
		return nil
	end
	-- The tooltip data carries neither quality nor item level. Like the other tooltips in Sku: the quality behind the
	-- name (per setting) and, for equipment, the item level as the second line.
	local tKeyInfo = C_AuctionHouse.GetItemKeyInfo(aItemKey)
	if SkuSettings:Sub("SkuCore").itemSettings.ShowItemQality == true then
		local tQualityText = aLink and SkuUtil:ItemQualityString(aLink) or (tKeyInfo and _G["ITEM_QUALITY"..tKeyInfo.quality.."_DESC"])
		if tQualityText then tLines[1] = tLines[1].." ("..tQualityText..")" end
	end
	if tKeyInfo and tKeyInfo.isEquipment then
		local tLevel = aLink and SkuUtil:ItemLevel(aLink) or aItemKey.itemLevel
		if tLevel then table.insert(tLines, 2, L["Item Level"]..": "..tLevel) end
	end
	return SkuUtil:Unescape(table.concat(tLines, "\r\n"))
end

-- Sets the tooltip text on the menu entry (built on reading) and the item reference for the comparison with the equipped item.
local function tSetAhTooltip(aEntry, aItemKey, aLink)
	aEntry.itemId = aLink or aItemKey.itemID
	aEntry.textFirstLine = aEntry.name
	aEntry.textFull = function()
		local tText = tAhItemTooltipText(aItemKey, aLink)
		if tText and tText ~= "" then return { tText } end
		return { L["No tooltip available"] }
	end
end

local function tBrowseRowLabel(aRow)
	local tPriceText = tMoneyText(aRow.minPrice)
	if aRow.totalQuantity > 1 then
		return aRow.name.." - "..L["from "]..tPriceText..", "
			..aRow.totalQuantity.." "..L["for sale"]
	end
	return aRow.name.." - "..tPriceText
end

-- The commodity confirm step: replaces the item's level while a quote is open (Blizzard's buy dialog covers its window
-- the same way), so the cursor lands on the quote summary, then Confirm and Cancel. Declared before
-- tBuildDetailChildren, which calls it: a local function is only visible below its declaration.
local function tBuildCommodityConfirmChildren(aParentEntry)
	aParentEntry.children = {}
	-- The first leaf (waiting, or the summary) does nothing on ENTER but read itself again: an Enter pressed while the
	-- quote arrives must not land on Confirm.
	-- Confirm and Cancel act only on the purchase they were built for, never on a newer one.
	local tGen = gCommodityBuy.generation
	if not gCommodityBuy.unitPrice then
		tSettingLeaf(aParentEntry, L["Warten"], function() end)
	else
		tSettingLeaf(aParentEntry, gCommodityBuy.summary, function() end)
		tSettingLeaf(aParentEntry, gCommodityBuy.confirming and L["Purchasing"] or (L["Confirm: "]..tMoneyText(gCommodityBuy.totalPrice)), function(aLeaf)
			AHF:ConfirmCommodityBuy(aLeaf, tGen)
		end)
	end
	-- Cancel is there while waiting for the quote too: leaving must never keep a quote open.
	tSettingLeaf(aParentEntry, L["Abbrechen"], function(aLeaf)
		if not gCommodityBuy.itemID or gCommodityBuy.generation ~= tGen then
			tRefuse(aLeaf, nil, L["No purchase is waiting for confirmation"])
			return
		end
		-- Blizzard disables Cancel while the purchase is in flight.
		if gCommodityBuy.confirming then
			tRefuse(aLeaf, nil, L["Purchasing"])
			return
		end
		AHF:EndCommodityBuy(L["Abgebrochen"], true)
	end)
end

-- Bid on a regular auction. A bid at or above the buyout price is a buyout (Blizzard's own
-- bid dialog does the same). Runs inside a menu action, i.e. from a real key press.
function AHF:PlaceItemBid(aRow, aAmount, aName, aLeaf)
	if aRow.isOwn then
		tRefuse(aLeaf, aName, L["That is your own auction"])
		return
	end
	if aRow.buyoutAmount and aRow.buyoutAmount > 0 and aAmount >= aRow.buyoutAmount then
		AHF:BuyItemAuction(aRow.auctionID, aRow.buyoutAmount, aName, aLeaf)
		return
	end
	if tIsOwnGuid(aRow.bidder) then
		tRefuse(aLeaf, aName, L["your bid is highest"])
		return
	end
	if aRow.minBid and aAmount < aRow.minBid then
		tRefuse(aLeaf, aName, L["The bid is too low, at least "]..tMoneyText(aRow.minBid))
		return
	end
	if GetMoney() < aAmount then
		tRefuse(aLeaf, aName, L["Nicht genug Geld"])
		return
	end
	gItemPurchase.auctionID, gItemPurchase.name, gItemPurchase.isBuyout = aRow.auctionID, aName, false
	dprint("ahf", "bid", aRow.auctionID, aAmount)
	C_AuctionHouse.PlaceBid(aRow.auctionID, aAmount)
end

-- The three bid leaves shared by the item detail and "My bids": bid the minimum, set an
-- own amount, place that amount. Setting and placing are separate leaves so the protected
-- PlaceBid always runs from its own real key press. aData: {auctionID, minBid, buyoutAmount,
-- isOwn, bidder, customBid}. Returns true when bidding is possible at all: not while the player holds the
-- highest bid (Blizzard's AuctionHouseBidFrameMixin:SetPrice disables bidding then).
local function tAddBidLeaves(aParent, aData, aName)
	if not (aData.minBid and aData.minBid > 0) or tIsOwnGuid(aData.bidder) then return false end
	tSettingLeaf(aParent, L["Bid the minimum: "]..tMoneyText(aData.minBid), function(aLeaf)
		AHF:PlaceItemBid(aData, aData.minBid, aName, aLeaf)
	end)
	local tCustomPlace
	tSettingLeaf(aParent, L["Set your own bid"], function()
		tAskMoney(L["Enter bid, for example 12g 5s 3k"], function(aAmount)
			aData.customBid = aAmount
			tCustomPlace.name = L["Place your bid: "]..tMoneyText(aAmount)
			tCustomPlace.ahfBaseName = nil
		end)
	end)
	tCustomPlace = tSettingLeaf(aParent, aData.customBid
		and (L["Place your bid: "]..tMoneyText(aData.customBid))
		or L["Place your bid, set it first"],
		function(aLeaf)
			if not aData.customBid then
				tRefuse(aLeaf, aName, L["Set a bid first"])
				return
			end
			AHF:PlaceItemBid(aData, aData.customBid, aName, aLeaf)
		end)
	return true
end

-- Favourites (Blizzard: the star next to an item, AuctionHouseFavoriteButtonBaseMixin). Only offered where the
-- server supports them. Like the star, a full list takes no new favourite; the refusal is said with the entry the
-- key handler reads back after ENTER.
local gFavoritesChanged = nil
local function tAddFavoriteLeaf(aParent, aItemKey)
	if not C_AuctionHouse.FavoritesAreAvailable() then return end
	local tLeaf = SkuOptions:InjectMenuItems(aParent, {L["Favorites"]}, SkuGenericMenuItem)
	tLeaf.skuIdentity = "favorite"
	SkuOptions:MakeToggleNode(tLeaf, {
		onLabel = L["Yes"],
		offLabel = L["No"],
		get = function() return C_AuctionHouse.IsFavoriteItem(aItemKey) end,
		set = function(_, aNew)
			C_AuctionHouse.SetFavoriteItem(aItemKey, aNew)
			gFavoritesChanged = true
		end,
		canChange = function(self)
			if C_AuctionHouse.IsFavoriteItem(aItemKey) or not C_AuctionHouse.HasMaxFavorites() then return true end
			self.ahfFull = true
			return false
		end,
	})
	local tRefresh = tLeaf.RefreshLiveName
	tLeaf.RefreshLiveName = function(self)
		tRefresh(self)
		if self.ahfFull then
			self.ahfFull = nil
			self.name = self.name..";"..L["Your favorites list is full"]
		end
	end
end

-- Stable row identities for tRebuildAndFocus's re-pin and for "load more".
local function tListingIdentity(aRow)
	return "auction:"..aRow.auctionID
end

local function tBrowseIdentity(aItemKey)
	return "browse:"..aItemKey.itemID..":"..aItemKey.itemLevel..":"..aItemKey.itemSuffix..":"..aItemKey.battlePetSpeciesID
end

-- Before "load more": the identities already listed, so the first new row gets the cursor.
local function tIdentitySet(aRows, aIdentity)
	local tSet = {}
	for _, tRow in ipairs(aRows) do tSet[aIdentity(tRow)] = true end
	return tSet
end

-- A commodity's level: Quantity, Buy (the game buys the cheapest pieces of other players, whichever price one is on),
-- then the price steps as information. Every leaf has an identity, so a refresh of the rows keeps the cursor.
local function tBuildCommodityChildren(aParent)
	local tItemID = gDetail.itemKey.itemID
	-- The Buy label first: the preview can cut the quantity the Quantity label shows.
	local tQty, tTotal, tHigh = tCommodityPreview()
	-- The Buy leaf carries the reason a purchase just ended (AHF:EndCommodityBuy).
	local tBuyName = (gCommodityBuy.notice and (gCommodityBuy.notice..";") or "")..tCommodityBuyLabel(tQty, tTotal, tHigh)
	local tQuantity = tSettingLeaf(aParent, tCommodityQuantityLabel(), function()
		local tMax = tCommodityOffered()
		tAskValue(L["Enter quantity, at most "]..tMax, tParseQuantity, L["Quantity not understood"], function(aN)
			gDetail.buyQty = math.min(aN, tMax)
			tCommodityRelabel()
		end)
	end)
	tQuantity.skuIdentity = "commodity:quantity"
	-- Loading or nothing offered: the leaf, read again after Enter, says so; Enter while loading asks for the rows again.
	local tBuy = tSettingLeaf(aParent, tBuyName, function(aLeaf)
		local _, tQ, tT, tH = tCommodityRelabel()
		if tQ and tQ > 0 and AHF:StartCommodityBuy(tItemID, tQ, tT, tH, aParent, gDetail.name, aLeaf) then
			tRebuildAndFocus(aParent, true, true)
		end
	end)
	tBuy.skuIdentity = "commodity:buy"
	tBuy.ahfPrimary = true
	tSetAhTooltip(tBuy, gDetail.itemKey, nil)
	local tListed = 0
	for _, tRow in ipairs(gDetail.results) do
		tListed = tListed + tRow.quantity
		local tLabel = string.format(L["%s pieces at %s each"], tRow.quantity, tMoneyText(tRow.unitPrice))
		if tRow.isOwn then tLabel = tLabel..", "..L["your own auction"] end
		-- Enter = Blizzard's click on a price row: every piece of other players up to this price, then the Buy leaf.
		local tRowLeaf = tSettingLeaf(aParent, tLabel, function(aLeaf)
			local tUpTo = AuctionHouseUtil.AggregateCommoditySearchResultsByMaxPrice(tItemID, tRow.unitPrice)
			if tUpTo == 0 then
				tRefuse(aLeaf, nil, L["That is your own auction"])
				return
			end
			gDetail.buyQty = tUpTo
			SkuOptions.currentMenuPosition = tCommodityRelabel()
		end)
		tRowLeaf.skuIdentity = "commodity:"..tRow.unitPrice
		tSetAhTooltip(tRowLeaf, gDetail.itemKey, nil)
	end
	-- The rows come cheapest first; the ones not loaded yet are only counted.
	if not C_AuctionHouse.HasFullCommoditySearchResults(tItemID) then
		local tMore = C_AuctionHouse.GetCommoditySearchResultsQuantity(tItemID) - tListed
		if tMore > 0 then
			local tE = SkuOptions:InjectMenuItems(aParent, {string.format(L["%s more pieces at the same or higher prices"], tMore)}, SkuGenericMenuItem)
			tE.dynamic = false
			tE.skuIdentity = "commodity:more"
		end
	end
end

local function tBuildDetailChildren(aParentEntry)
	aParentEntry.children = {}
	if gDetail.state == "waiting" then
		local tW = SkuOptions:InjectMenuItems(aParentEntry, {L["Warten"]}, SkuGenericMenuItem)
		tW.dynamic = false
		return
	end
	if gDetail.state == "failed" then
		local tFail = SkuOptions:InjectMenuItems(aParentEntry, {gDetail.failText}, SkuGenericMenuItem)
		tFail.dynamic = false
		return
	end
	if gDetail.isCommodity and gCommodityBuy.itemID == gDetail.itemKey.itemID then
		tBuildCommodityConfirmChildren(aParentEntry)
		return
	end
	tAddFavoriteLeaf(aParentEntry, gDetail.itemKey)
	if #gDetail.results == 0 then
		local tNone = SkuOptions:InjectMenuItems(aParentEntry, {L["AH_NoResults"]}, SkuGenericMenuItem)
		tNone.dynamic = false
		tNone.ahfPrimary = true
		return
	end
	if gDetail.isCommodity then
		tBuildCommodityChildren(aParentEntry)
		return
	end
	-- Every row starts with the item name: "2x Buyout 24 Copper" alone does not say which item
	-- it is. gDetail.name is the browse row's name, which exists for every row.
	local tNamePrefix = gDetail.name..": "
	local tPrimarySet = false
	for _, tRow in ipairs(gDetail.results) do
		local tBody = tRow.buyoutAmount and (L["Buyout "]..tMoneyText(tRow.buyoutAmount))
			or (L["Bid from "]..tMoneyText(tRow.minBid or tRow.bidAmount or 0))
		if tRow.quantity > 1 then tBody = tRow.quantity.."x "..tBody end
		if tIsOwnGuid(tRow.bidder) then
			tBody = tBody..", "..L["your bid is highest"]
		end
		local tLeft = tTimeLeftText(tRow)
		if tLeft ~= "" then tBody = tBody..", "..L["left: "]..tLeft end
		if tRow.isOwn then tBody = tBody..", "..L["your own auction"] end
		local tLabel = tNamePrefix..tBody
		local tRowEntry = SkuOptions:InjectMenuItems(aParentEntry, {tLabel}, SkuGenericMenuItem)
		tRowEntry.dynamic = true
		tRowEntry.data = tRow
		tRowEntry.skuIdentity = tListingIdentity(tRow)
		tSetAhTooltip(tRowEntry, gDetail.itemKey, tRow.itemLink)
		if not tPrimarySet and not (gDetail.seenBefore and gDetail.seenBefore[tRowEntry.skuIdentity]) then
			tRowEntry.ahfPrimary = true
			tPrimarySet = true
		end
		tRowEntry.BuildChildren = function(self)
			self.children = {}
			local tData = self.data
			if tData.isOwn then
				local tOwn = SkuOptions:InjectMenuItems(self, {L["That is your own auction"]}, SkuGenericMenuItem)
				tOwn.dynamic = false
				return
			end
			if tData.buyoutAmount then
				tSettingLeaf(self, L["Kaufen"]..": "..tMoneyText(tData.buyoutAmount), function(aLeaf)
					AHF:BuyItemAuction(tData.auctionID, tData.buyoutAmount, gDetail.name, aLeaf)
				end)
			end
			-- Bidding below the buyout (Blizzard: the bid box next to the buyout button).
			local tHasBid = tAddBidLeaves(self, tData, gDetail.name)
			if not tData.buyoutAmount and not tHasBid then
				local tNoBuyout = SkuOptions:InjectMenuItems(self, {tIsOwnGuid(tData.bidder)
					and L["You are the highest bidder, nothing to do"]
					or L["Neither buyout nor bid possible"]}, SkuGenericMenuItem)
				tNoBuyout.dynamic = false
			end
		end
	end
	-- "Load more": the server hands out results in pages (HasFullItemSearchResults is false until all are in).
	if not C_AuctionHouse.HasFullItemSearchResults(gDetail.itemKey) then
		tSettingLeaf(aParentEntry, L["Load more auctions, so far "]..#gDetail.results, function(aLeaf)
			-- true: the result is complete, nothing more will arrive.
			if C_AuctionHouse.RequestMoreItemSearchResults(gDetail.itemKey) then
				aLeaf.name = L["Keine weiteren passenden Auktionen verfügbar"]
				return
			end
			gDetail.seenBefore = tIdentitySet(gDetail.results, tListingIdentity)
			aLeaf.name = L["Loading more auctions"]
		end)
	end
end

-- One browse row (name search, category or favorites): {itemKey, name, isCommodity,
-- minPrice, totalQuantity} -> drills into the live detail/buy step.
local function tInjectItemRow(aParentEntry, aRow)
	local tRowEntry = SkuOptions:InjectMenuItems(aParentEntry, {tBrowseRowLabel(aRow)}, SkuGenericMenuItem)
	tRowEntry.dynamic = true
	tRowEntry.data = aRow
	tRowEntry.skuIdentity = tBrowseIdentity(aRow.itemKey)
	tSetAhTooltip(tRowEntry, aRow.itemKey, nil)
	tMarkEntering(tRowEntry)
	tRowEntry.BuildChildren = function(selfRow)
		if tQueryOnEnter(selfRow, gDetail, function() AHF:StartDetail(selfRow.data, selfRow) end) then
			tBuildDetailChildren(selfRow)
		end
	end
	return tRowEntry
end

-- Appends the current gBrowse state (waiting / no results / result rows)
-- to aParentEntry - does NOT clear children first, so the caller can put its
-- own leaves (e.g. the name search's "enter search string") before it.
local function tAppendBrowseResultChildren(aParentEntry)
	-- gBrowse holds ONE result set shared by name search and every category
	-- node. Only the node that started the current query may show it, else the
	-- search list shows category results and vice versa.
	if gBrowse.entry ~= aParentEntry then return end
	-- The first state leaf or result row is ahfPrimary: when an answer arrives, the cursor goes
	-- there and not to the name search's own "enter search string" leaf. After "load more" it is
	-- the first row that was not listed before.
	if gBrowse.state == "waiting" then
		-- The active filters are part of the waiting leaf: a separate announcement would be cut off
		-- by the vocalization of this leaf.
		local tName = L["Warten"]
		if gBrowse.filterSummary then tName = tName..";"..L["Filters active: "]..gBrowse.filterSummary end
		local tW = SkuOptions:InjectMenuItems(aParentEntry, {tName}, SkuGenericMenuItem)
		tW.dynamic = false
		tW.ahfPrimary = true
	elseif gBrowse.state == "failed" then
		local tFail = SkuOptions:InjectMenuItems(aParentEntry, {gBrowse.failText}, SkuGenericMenuItem)
		tFail.dynamic = false
		tFail.ahfPrimary = true
	elseif gBrowse.state == "done" then
		if #gBrowse.results == 0 then
			local tNone = SkuOptions:InjectMenuItems(aParentEntry, {L["AH_NoResults"]}, SkuGenericMenuItem)
			tNone.dynamic = false
			tNone.ahfPrimary = true
		else
			local tPrimarySet = false
			for _, tRow in ipairs(gBrowse.results) do
				local tRowEntry = tInjectItemRow(aParentEntry, tRow)
				if not tPrimarySet and not (gBrowse.seenBefore and gBrowse.seenBefore[tRowEntry.skuIdentity]) then
					tRowEntry.ahfPrimary = true
					tPrimarySet = true
				end
			end
			-- More results on the server (HasFullBrowseResults is false until all pages are in).
			if not C_AuctionHouse.HasFullBrowseResults() then
				tSettingLeaf(aParentEntry, L["Load more results, so far "]..#gBrowse.results, function(aLeaf)
					gBrowse.seenBefore = tIdentitySet(gBrowse.results, function(aRow) return tBrowseIdentity(aRow.itemKey) end)
					C_AuctionHouse.RequestMoreBrowseResults()
					aLeaf.name = L["Loading more results"]
				end)
			end
		end
	end
end

-- Builds one menu level of Blizzard's own AuctionCategories tree (Camelot/Blizzard_AuctionData.lua).
-- Appends to aParentEntry.children without clearing them; the callers clear first. A category with
-- subcategories lists them and then "Everything in <category>".
local function tBuildCategoryChildren(aParentEntry, aCategoryList)
	for _, tCat in ipairs(aCategoryList) do
		-- The WoW Token category is no item search: Blizzard opens its token frame there or hides it.
		if not tCat:HasFlag("WOW_TOKEN_FLAG") then
			local tCatEntry = SkuOptions:InjectMenuItems(aParentEntry, {tCat.name}, SkuGenericMenuItem)
			tCatEntry.dynamic = true
			tCatEntry.data = tCat
			tMarkEntering(tCatEntry)
			tCatEntry.BuildChildren = function(self)
				if self.data.subCategories and #self.data.subCategories > 0 then
					self.children = {}
					-- Subcategories first, "Everything in" last: going right into Weapons lands on
					-- One-Handed/Two-Handed/..., not on a result list.
					tBuildCategoryChildren(self, self.data.subCategories)
					-- A category holds the filters of all its descendants (AuctionCategoryMixin:AddFilter
					-- adds each filter to the parents too), so "Everything in Weapons" is one browse.
					if self.data.filters and #self.data.filters > 0 then
						local tAll = SkuOptions:InjectMenuItems(self, {L["Everything in "]..self.data.name}, SkuGenericMenuItem)
						tAll.dynamic = true
						tMarkEntering(tAll)
						tAll.BuildChildren = function(selfAll)
							selfAll.children = {}
							if tQueryOnEnter(selfAll, gBrowse, function() AHF:StartCategoryBrowse(self.data.filters, selfAll) end) then
								tAppendBrowseResultChildren(selfAll)
							end
						end
					end
				else
					self.children = {}
					if tQueryOnEnter(self, gBrowse, function() AHF:StartCategoryBrowse(self.data.filters or {}, self) end) then
						tAppendBrowseResultChildren(self)
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- SELL + OWN AUCTIONS (the Sales entry). Mirrors Blizzard's own
-- ItemSellFrame/CommoditiesSellFrame flow: PostItem/PostCommodity (protected,
-- must run from a real keypress) returns needsConfirmation; then
-- AUCTION_HOUSE_POST_WARNING -> ConfirmPostItem/ConfirmPostCommodity with the
-- same args. Item prices are per item/auction, commodity prices per unit
-- (Blizzard's GetTotalPrice multiplies by quantity). Max quantity =
-- C_AuctionHouse.GetAvailablePostCount(itemLocation).
-- ---------------------------------------------------------------------
local gSellList = nil
local gOwned = { state = "idle", rows = {}, entry = nil, generation = 0 }

-- Blizzard's sell frame: duration index 1..3, kept in the CVar its dropdown uses.
local function tGetDuration()
	gSell.duration = gSell.duration or tonumber(GetCVar("auctionHouseDurationDropdown"))
	return gSell.duration
end

local function tDurationText(aIndex)
	return ({ AUCTION_DURATION_ONE, AUCTION_DURATION_TWO, AUCTION_DURATION_THREE })[aIndex]
end

local function tDepositAmount()
	if not gSell.loc then return 0 end
	local tDeposit
	if gSell.isCommodity then
		tDeposit = C_AuctionHouse.CalculateCommodityDeposit(gSell.itemID, tGetDuration(), gSell.quantity)
	else
		tDeposit = C_AuctionHouse.CalculateItemDeposit(gSell.loc, tGetDuration(), gSell.quantity)
	end
	-- depositCost is documented as nilable.
	return tDeposit or 0
end

local function tMoneyOrNone(aAmount)
	if aAmount and aAmount > 0 then return tMoneyText(aAmount) end
	return L["STRAT_NotSet"]
end

local function tQuantityLabel()
	return L["Quantity: "]..gSell.quantity.." ("..L["at most "]..gSell.maxQuantity..")"
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
	local tTotal = gSell.buyout and gSell.buyout > 0 and (gSell.buyout * gSell.quantity) or nil
	return L["Total price for the quantity: "]..tMoneyOrNone(tTotal)
end
local function tBidLabel()
	return L["Starting bid, optional: "]..tMoneyOrNone(gSell.bid)
end
local function tDepositLabel()
	-- Blizzard's UpdateDeposit: without copper values the deposit is shown rounded up to whole silver.
	local tDeposit = tDepositAmount()
	if not C_AuctionHouse.SupportsCopperValues() then tDeposit = math.ceil(tDeposit / COPPER_PER_SILVER) * COPPER_PER_SILVER end
	local tText = L["Deposit: "]..tMoneyText(tDeposit)
	if gSell.buyout and gSell.buyout > 0 and gSell.quantity > 1 then
		tText = tText..", "..L["total price "]..tMoneyText(gSell.buyout * gSell.quantity)
	end
	return tText
end
-- The post leaf is read again right after Enter, so what the last post attempt has to say (gSell.postNote) is
-- part of its name until the draft changes.
local function tPostLabel()
	local tLabel = gSell.pending and L["Confirm: post with warning"] or L["Post auction"]
	if gSell.postNote then return gSell.postNote..";"..tLabel end
	return tLabel
end

-- Market price hint while selling: Blizzard's sell frames query the item (AuctionHouseFrame:QueryItem) and fill
-- the price from the cheapest listing; here the cheapest buyout / unit price is offered as the new price on the
-- next Enter.
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
	if gSell.marketState == "failed" then
		return (gSell.marketFailText and (gSell.marketFailText..";") or "")..L["Could not get the market price. Enter asks again"]
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

-- As Blizzard's sell frames: equipment is searched without item level and suffix (ConvertItemSellItemKey) through
-- SendSellSearchQuery, everything else through SendSearchQuery, sorted cheapest first, owner items not separated.
-- The results are read with the same key.
function AHF:StartMarketQuery()
	if not gSell.loc or gSell.marketState == "waiting" then return end
	local tKey = C_AuctionHouse.GetItemKeyFromItem(gSell.loc)
	local tKeyInfo = C_AuctionHouse.GetItemKeyInfo(tKey)
	local tEquipment = tKeyInfo and tKeyInfo.isEquipment
	if tEquipment then tKey.itemLevel, tKey.itemSuffix = 0, 0 end
	-- Blizzard's GetBestEntry compares equipment by item level, except green items and pets.
	gSell.marketItemLevel = tEquipment and not tKeyInfo.isPet
		and C_Item.GetItemQuality(gSell.loc) ~= Enum.ItemQuality.Uncommon
		and C_Item.GetCurrentItemLevel(gSell.loc) or nil
	gSell.marketState = "waiting"
	gSell.marketLowest, gSell.marketFailText = nil, nil
	gSell.marketKey = tKey
	local tSorts = gSell.isCommodity and { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } } or AHF_ITEM_SORTS
	tSendThrottled(gSell, tEquipment and C_AuctionHouse.SendSellSearchQuery or C_AuctionHouse.SendSearchQuery, tKey, tSorts, false)
	-- No answer is not "no offers": the lookup is reported as failed.
	local tDraft = gSell
	C_Timer.After(6, function()
		if gSell == tDraft and gSell.marketState == "waiting" then
			gSell.marketState, gSell.pendingSend = "failed", nil
			tRefreshSellLabels()
			tSay(tMarketLabel())
		end
	end)
end

-- Called from the search result events (see Events at the end of the file).
function AHF:OnSellMarketResult(aIsCommodity, aItemID)
	if gSell.marketState ~= "waiting" or not gSell.marketKey then return end
	if aItemID and aItemID ~= gSell.marketKey.itemID then return end
	if aIsCommodity ~= gSell.isCommodity then return end
	local tLowest
	if aIsCommodity then
		-- Commodity results always come cheapest first (Blizzard reads row 1).
		local tR = C_AuctionHouse.GetCommoditySearchResultInfo(gSell.marketKey.itemID, 1)
		tLowest = tR and tR.unitPrice
	else
		-- Bid-only listings have no buyout; for equipment only the draft's item level counts. All loaded rows are
		-- read, a matching row can sit behind cheaper rows of other item levels.
		local tKey, tLevel = gSell.marketKey, gSell.marketItemLevel
		for i = 1, C_AuctionHouse.GetNumItemSearchResults(tKey) do
			local tR = C_AuctionHouse.GetItemSearchResultInfo(tKey, i)
			if tR.buyoutAmount and (not tLevel or tR.itemKey.itemLevel == tLevel)
				and (not tLowest or tR.buyoutAmount < tLowest) then
				tLowest = tR.buyoutAmount
			end
		end
		if not tLowest and not C_AuctionHouse.HasFullItemSearchResults(tKey) then
			-- More listings arrive with ITEM_SEARCH_RESULTS_ADDED.
			C_AuctionHouse.RequestMoreItemSearchResults(tKey)
			return
		end
	end
	gSell.marketState = "done"
	gSell.marketLowest = tLowest
	tRefreshSellLabels()
	tSay(tMarketLabel())
end

-- True while aLoc still holds the item with aGuid. Bag slots change under the menu (sorting, looting, moving), so
-- the draft is tied to the item's GUID and checked before every use.
local function tSameItem(aLoc, aGuid)
	return C_Item.DoesItemExist(aLoc) and C_Item.GetItemGUID(aLoc) == aGuid
end

-- Makes the item aGuid in aBag/aSlot the draft. Returns "ready", "loading" (item data not loaded yet) or "moved"
-- (the slot no longer holds that item). The draft of the same item is kept.
function AHF:SelectSellItem(aBag, aSlot, aGuid)
	local tLoc = ItemLocation:CreateFromBagAndSlot(aBag, aSlot)
	if not tSameItem(tLoc, aGuid) then
		if gSell.guid == aGuid then gSell = { duration = gSell.duration } end
		return "moved"
	end
	if gSell.guid == aGuid and gSell.bag == aBag and gSell.slot == aSlot and not gSell.posted then return "ready" end
	local tStatus = C_AuctionHouse.GetItemCommodityStatus(tLoc)
	if tStatus == Enum.ItemCommodityStatus.Unknown then return "loading" end
	local tInfo = C_Container.GetContainerItemInfo(aBag, aSlot)
	local tMax = math.max(1, C_AuctionHouse.GetAvailablePostCount(tLoc))
	local tKeepDuration = gSell.duration
	gSell = {
		guid = aGuid, bag = aBag, slot = aSlot, loc = tLoc, itemID = tInfo.itemID, name = tInfo.itemName,
		isCommodity = (tStatus == Enum.ItemCommodityStatus.Commodity), maxQuantity = tMax,
		quantity = 1, duration = tKeepDuration,
	}
	-- Blizzard's commodity sell frame starts with the whole stack.
	if gSell.isCommodity then gSell.quantity = math.min(tMax, tInfo.stackCount) end
	return "ready"
end

-- Every change to the draft drops a pending confirmation: it was given for the old values, and confirming it
-- would post those. Its post sent nothing, so Sku owns no post any more.
local function tDraftChanged()
	if gSell.pending then gSell.posting = nil end
	gSell.pending, gSell.postError = nil, nil
	gSell.postNote = nil
	tRefreshSellLabels()
end

local function tPostNote(aText)
	gSell.postNote = aText
	tRefreshSellLabels()
end

-- The server refused Sku's post (AUCTION_HOUSE_POST_ERROR, or AUCTION_HOUSE_SHOW_ERROR through AHF:OnShowError).
-- The reason goes into the post leaf; inside the key press the key handler reads that leaf again, otherwise it is
-- spoken here.
function AHF:OnPostRefused(aText)
	gSell.pending, gSell.posting, gSell.postError = nil, nil, true
	gSell.refusedAt = GetTime()
	tPostNote(gSell.name..": "..aText)
	if not gSell.inPostCall then tSay(gSell.postNote) end
end

-- tAskValue for a draft value: the sell leaves are relabelled before the cursor's leaf is read again.
local function tAskSell(aPrompt, aParse, aFailText, aApply)
	tAskValue(aPrompt, aParse, aFailText, function(aValue)
		aApply(aValue)
		tDraftChanged()
	end)
end

-- "0" clears the starting bid.
local function tParseBid(aText)
	if aText:match("^%s*0+%s*$") then return 0 end
	return tParseMoney(aText)
end

function AHF:PostDraft()
	if not gSell.loc then return end
	if not tSameItem(gSell.loc, gSell.guid) then
		tPostNote(gSell.name..": "..L["The item has moved or is gone, open the list again"])
		gSell = { duration = gSell.duration }
		return
	end
	if gSell.pending then
		local tP = gSell.pending
		gSell.pending = nil
		gSell.posting = true
		gSell.multisellExpected = not gSell.isCommodity and tP[3] > 1
		if gSell.isCommodity then
			C_AuctionHouse.ConfirmPostCommodity(SafeUnpack(tP))
		else
			C_AuctionHouse.ConfirmPostItem(SafeUnpack(tP))
		end
		tPostNote(gSell.name..": "..L["Confirmed, posting"])
		return
	end
	-- Blizzard's CanPostItem: an item needs a starting bid or a buyout, a commodity its unit price (it has no bid).
	if not gSell.buyout and not gSell.bid then
		tPostNote(L["Set a price first"])
		return
	end
	if gSell.bid and gSell.buyout and gSell.bid >= gSell.buyout then
		tPostNote(L["The starting bid must be below the buyout price"])
		return
	end
	if GetMoney() < tDepositAmount() then
		tPostNote(L["Not enough money for the deposit"])
		return
	end
	if not C_AuctionHouse.IsThrottledMessageSystemReady() then
		tPostNote(L["Please wait a moment and try again"])
		return
	end
	-- Protected: called straight from the key press. Without a needed confirmation the auction is on its way;
	-- AUCTION_HOUSE_AUCTION_CREATED or an error event reports the outcome. A needed confirmation is what
	-- Blizzard's AUCTION_HOUSE_POST_WARNING popup asks for; the next Enter on this leaf gives it.
	-- gSell.posting: Sku owns this post (see the StaticPopup_Show hook below).
	local tDuration, tQuantity = tGetDuration(), gSell.quantity
	local tNeeds, tArgs
	gSell.posting, gSell.postError, gSell.inPostCall = true, nil, true
	-- Several items (not commodities) are posted one auction each: AUCTION_MULTISELL_* report that.
	gSell.multisellExpected = not gSell.isCommodity and tQuantity > 1
	if gSell.isCommodity then
		tArgs = SafePack(gSell.loc, tDuration, tQuantity, gSell.buyout)
		tNeeds = C_AuctionHouse.PostCommodity(SafeUnpack(tArgs))
	else
		tArgs = SafePack(gSell.loc, tDuration, tQuantity, gSell.bid, gSell.buyout)
		tNeeds = C_AuctionHouse.PostItem(SafeUnpack(tArgs))
	end
	gSell.inPostCall = nil
	if gSell.postError then return end
	if tNeeds then
		gSell.pending = tArgs
		tPostNote(gSell.name..": "..CONFIRM_AUCTION_POSTING_TEXT)
	else
		tPostNote(nil)
	end
end

local function tBuildSellItemChildren(aParent)
	aParent.children = {}
	local tLeaves = {}
	gSell.leaves = tLeaves
	if gSell.maxQuantity > 1 then
		tLeaves.quantity = tSettingLeaf(aParent, tQuantityLabel(), function()
			tAskSell(L["Enter amount"], tParseQuantity, L["Quantity not understood"], function(aN)
				gSell.quantity = math.min(aN, gSell.maxQuantity or 1)
			end)
		end)
	end
	tLeaves.duration = tSettingLeaf(aParent, tDurationLabel(), function()
		gSell.duration = (tGetDuration() % 3) + 1
		SetCVar("auctionHouseDurationDropdown", gSell.duration)
		tDraftChanged()
	end)
	tLeaves.price = tSettingLeaf(aParent, tPriceLabel(), function()
		tAskSell(L["Enter price, for example 12g 5s 3k"], tParseMoney, L["Price not understood"], function(aCopper)
			gSell.buyout = aCopper
		end)
	end)
	tLeaves.market = tSettingLeaf(aParent, tMarketLabel(), function()
		if gSell.marketState == "done" and gSell.marketLowest then
			gSell.buyout = gSell.marketLowest
			tDraftChanged()
			return
		end
		AHF:StartMarketQuery()
		tRefreshSellLabels()
	end)
	if gSell.maxQuantity > 1 then
		tLeaves.total = tSettingLeaf(aParent, tTotalLabel(), function()
			tAskSell(L["Enter the total price for the chosen quantity, for example 5g"], tParseMoney, L["Price not understood"], function(aTotal)
				local tPer = math.max(1, math.floor(aTotal / (gSell.quantity or 1) + 0.5))
				if not C_AuctionHouse.SupportsCopperValues() then tPer = math.max(100, math.floor(tPer / 100 + 0.5) * 100) end
				gSell.buyout = tPer
			end)
		end)
	end
	if not gSell.isCommodity then
		tLeaves.bid = tSettingLeaf(aParent, tBidLabel(), function()
			tAskSell(L["Enter starting bid, or 0 to clear"], tParseBid, L["Amount not understood"], function(aCopper)
				gSell.bid = aCopper > 0 and aCopper or nil
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
	for tBag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for tSlot = 1, C_Container.GetContainerNumSlots(tBag) do
			local tInfo = C_Container.GetContainerItemInfo(tBag, tSlot)
			if tInfo then
				local tLoc = ItemLocation:CreateFromBagAndSlot(tBag, tSlot)
				if C_AuctionHouse.IsSellItemValid(tLoc, false) then
					local tGuid = C_Item.GetItemGUID(tLoc)
					tAny = true
					local tName = tInfo.itemName
					if tInfo.stackCount > 1 then tName = tName.." x"..tInfo.stackCount end
					local tE = SkuOptions:InjectMenuItems(aSelf, {tName}, SkuGenericMenuItem)
					tE.dynamic = true
					tE.skuIdentity = "sellitem:"..tGuid
					tMarkEntering(tE)
					tE.BuildChildren = function(self)
						if not self.ahfEntering then tPlaceholderChild(self) return end
						local tState = AHF:SelectSellItem(tBag, tSlot, tGuid)
						if tState ~= "ready" then
							self.children = {}
							local tW = SkuOptions:InjectMenuItems(self, {tState == "moved"
								and L["The item has moved or is gone, open the list again"]
								or L["Item data still loading, please open again in a moment"]}, SkuGenericMenuItem)
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

-- The sell list follows the bags (BAG_UPDATE_DELAYED); a cursor on a row stays on its item (skuIdentity). Inside a
-- draft the list is left alone, except after that draft's item was posted: then the cursor goes back to the
-- item's row (row 1 when the whole stack is gone). Returns true when it moved the cursor out of the draft.
local function tFollowBags()
	if not gSellList then return false end
	local tRow, tDepth = tCursorChildOf(gSellList)
	if not tRow then return false end
	local tMoved = false
	if tDepth >= 2 then
		if not (gSell.posted and tRow.skuIdentity == "sellitem:"..gSell.guid) then return false end
		SkuOptions.currentMenuPosition = tRow
		tMoved = true
	end
	if gSell.posted then gSell = { duration = gSell.duration } end
	tRebuildAndFocus(gSellList, false, true)
	return tMoved
end

-- End of a Sku post (created, multisell done or failed): one utterance, with the new cursor position when the
-- cursor had to leave the posted draft.
local function tPostFinished(aText)
	gSell.posting, gSell.pending, gSell.multisell, gSell.multisellExpected = nil, nil, nil, nil
	gSell.posted = true
	if tFollowBags() then
		tSay(aText..";"..SkuOptions.currentMenuPosition.name)
	else
		tSay(aText)
	end
end

-- ---- Own auctions and own bids ----------------------------------------
-- Both are lists the server sends on request: QueryOwnedAuctions -> OWNED_AUCTIONS_UPDATED, QueryBids -> BIDS_UPDATED.
-- A list (gOwned, gBids) has a state (idle, waiting, done, failed), its rows, the menu entry showing it and the
-- function sending its query.

-- Rebuilds the entry showing aList, unless the cursor stands inside one of its rows: that row's entries would be
-- replaced under the cursor. A cursor on a row stays on that auction (skuIdentity), wherever the new list puts it.
-- aList.notice (set by an event before the list was asked again) is spoken here, joined with the entry the cursor
-- lands on: spoken before, the rebuild would cut it off.
local function tShowList(aList)
	local tNotice = aList.notice
	aList.notice = nil
	local tRow, tDepth = tCursorChildOf(aList.entry)
	if tRow and tDepth >= 2 then
		if tNotice then tSay(tNotice) end
		return
	end
	tRebuildAndFocus(aList.entry, false, tNotice ~= nil)
	if tNotice then
		local tPos = SkuOptions.currentMenuPosition
		tSay((tPos and tPos.parent == aList.entry) and (tNotice..";"..tPos.name) or tNotice)
	end
end

local function tSendListQuery(aList)
	aList.send()
	local tGen = aList.generation
	C_Timer.After(6, function()
		if aList.generation == tGen and aList.state == "waiting" then
			dprint("ahf", "list query unanswered", aList.name)
			aList.state = "failed"
			tShowList(aList)
		end
	end)
end

-- The old rows go at once: until the answer is in, the list says "Warten", never shows rows of an earlier query.
-- The query goes out through tSendThrottled. No answer within 6 seconds of sending = failed.
local function tStartListQuery(aList, aEntry)
	aList.state = "waiting"
	aList.failText = nil
	aList.entry = aEntry
	aList.rows = {}
	aList.namePending = nil
	aList.generation = aList.generation + 1
	tSendThrottled(aList, tSendListQuery, aList)
end

-- Item name of an owned auction or a bid: from its link, else from its item key. Not cached yet: Blizzard's
-- "Retrieving item information", and the list is read again on ITEM_KEY_ITEM_INFO_RECEIVED.
local function tListItemName(aList, aInfo)
	local tName = aInfo.itemLink and aInfo.itemLink:match("%[(.-)%]")
	if not tName then
		local tKeyInfo = C_AuctionHouse.GetItemKeyInfo(aInfo.itemKey)
		tName = tKeyInfo and tKeyInfo.itemName
	end
	if tName then return tName end
	aList.namePending = true
	return RETRIEVING_ITEM_INFO
end

-- Reads a list after its update event. aRead(i) returns the row for entry i, or nil.
local function tReadList(aList, aNum, aRead)
	if aList.state == "idle" or not aList.entry then return end
	aList.namePending = nil
	local tRows = {}
	for i = 1, aNum do
		local tRow = aRead(i)
		if tRow then tRows[#tRows + 1] = tRow end
	end
	aList.rows = tRows
	aList.state = "done"
	tShowList(aList)
end

-- BuildChildren of the entry showing aList: entering it sends the query; merely landing on it leaves the
-- placeholder, unless it is the entry already showing the list.
-- aAddRow(aParent, aRow) adds the entry of one row.
local function tBuildListEntry(aList, aSelf, aEmptyText, aAddRow)
	if aSelf.ahfEntering then
		tStartListQuery(aList, aSelf)
	elseif aList.entry ~= aSelf then
		tPlaceholderChild(aSelf)
		return
	end
	aSelf.children = {}
	local tText = (aList.state == "waiting" and L["Warten"])
		or (aList.state == "failed" and (aList.failText or L["No answer from the server, open the list again"]))
		or (#aList.rows == 0 and aEmptyText)
	if tText then
		local tE = SkuOptions:InjectMenuItems(aSelf, {tText}, SkuGenericMenuItem)
		tE.dynamic = false
		return
	end
	for _, tRow in ipairs(aList.rows) do aAddRow(aSelf, tRow) end
end

-- ---- Own auctions ---------------------------------------------------
gOwned.name = "owned"
gOwned.send = function() C_AuctionHouse.QueryOwnedAuctions({}) end

-- AUCTION_CANCELED: the list is asked again, as Blizzard's auctions tab does. A cursor on the cancel entry goes up to
-- its row, which the new list no longer has.
function AHF:OnAuctionCanceled()
	gCancel = nil
	if not gOwned.entry then
		tSay(L["Auction canceled"])
		return
	end
	local tRow, tDepth = tCursorChildOf(gOwned.entry)
	if tRow and tDepth >= 2 then SkuOptions.currentMenuPosition = tRow end
	gOwned.notice = L["Auction canceled"]
	tStartListQuery(gOwned, gOwned.entry)
end

function AHF:RefreshOwned()
	tReadList(gOwned, C_AuctionHouse.GetNumOwnedAuctions(), function(i)
		local tInfo = C_AuctionHouse.GetOwnedAuctionInfo(i)
		if not tInfo then return nil end
		return { info = tInfo, name = tListItemName(gOwned, tInfo) }
	end)
end

local function tOwnedRowLabel(aRow)
	local tI = aRow.info
	local tSold = tI.status == Enum.AuctionStatus.Sold
	local tParts = { aRow.name }
	if tI.quantity > 1 then tParts[#tParts + 1] = tI.quantity.."x" end
	if tSold then
		tParts[#tParts + 1] = L["sold"]
		if tI.buyoutAmount and tI.buyoutAmount > 0 then tParts[#tParts + 1] = tMoneyText(tI.buyoutAmount) end
	else
		if tI.buyoutAmount and tI.buyoutAmount > 0 then
			tParts[#tParts + 1] = L["buyout "]..tMoneyText(tI.buyoutAmount)
		end
		if tI.bidAmount and tI.bidAmount > 0 then
			tParts[#tParts + 1] = L["Gebot "]..tMoneyText(tI.bidAmount)
			if tI.bidder then tParts[#tParts + 1] = L["by "]..tI.bidder end
		end
		local tLeft = tTimeLeftText(tI)
		if tLeft ~= "" then tParts[#tParts + 1] = L["left: "]..tLeft end
	end
	return table.concat(tParts, ", ")
end

-- The server refused Sku's cancel: the reason goes in front of the row's cancel leaf, which offers the cancel again.
-- An event without a key press behind it, so the reason is spoken as well.
function AHF:OnCancelRefused(aText)
	local tC = gCancel
	gCancel = nil
	tC.data.cancelSent, tC.data.cancelArmed = nil, nil
	tC.data.cancelNote = aText
	tC.leaf.name = aText..";"..L["Cancel auction"]
	tSay(tC.data.name..": "..aText)
end

local function tAddOwnedRow(aParent, aRow)
	local tE = SkuOptions:InjectMenuItems(aParent, {tOwnedRowLabel(aRow)}, SkuGenericMenuItem)
	tE.dynamic = true
	tE.data = aRow
	tE.skuIdentity = "auction:"..aRow.info.auctionID
	tE.BuildChildren = function(self)
		self.children = {}
		local tI = self.data.info
		if tI.status == Enum.AuctionStatus.Sold then
			local tS = SkuOptions:InjectMenuItems(self, {L["Sold, the money arrives by mail"]}, SkuGenericMenuItem)
			tS.dynamic = false
			return
		end
		-- ENTER asks first (with the cost, like Blizzard's CANCEL_AUCTION popup), ENTER again cancels. A row cancels
		-- once: the server's answer (AUCTION_CANCELED) asks for the list again; a refusal (AHF:OnCancelRefused) puts
		-- its reason in front of this leaf and the cancel can be asked for again.
		local tData = self.data
		tData.cancelArmed = nil
		tSettingLeaf(self, tData.cancelSent and L["Cancel sent"]
			or ((tData.cancelNote and (tData.cancelNote..";") or "")..L["Cancel auction"]), function(aLeaf)
			if tData.cancelSent then
				aLeaf.name = L["Cancel sent"]
			elseif not tData.cancelArmed then
				tData.cancelArmed = true
				tData.cancelNote = nil
				local tCost = C_AuctionHouse.GetCancelCost(tI.auctionID)
				aLeaf.name = L["Really cancel? Press Enter again"]
					..(tCost > 0 and (", "..L["Cost"].." "..tMoneyText(tCost)) or "")
			else
				tData.cancelSent = true
				gCancel = { data = tData, leaf = aLeaf }
				C_AuctionHouse.CancelAuction(tI.auctionID)
				aLeaf.name = L["Cancel sent"]
			end
		end)
	end
end

-- ---- My bids (Blizzard: Auctions tab > Bids) -------------------------------
-- Auctions the player has bid on. QueryBids -> BIDS_UPDATED -> GetBidInfo(i). A row says whether
-- the player is still the highest bidder or was outbid, and offers buyout / raising the bid.
local gBids = { name = "bids", state = "idle", rows = {}, entry = nil, generation = 0 }
-- Like Blizzard's QueryAll(AllBids): the auctions in g_activeBidAuctionIDs (Blizzard_AuctionHouseUI's saved bid
-- list, kept up to date on BIDS_UPDATED) are sent along, so auctions the player was outbid on come back as well.
gBids.send = function() C_AuctionHouse.QueryBids({}, g_activeBidAuctionIDs) end

function AHF:RefreshBids()
	tReadList(gBids, C_AuctionHouse.GetNumBids(), function(i)
		local tInfo = C_AuctionHouse.GetBidInfo(i)
		if not tInfo then return nil end
		return {
			name = tListItemName(gBids, tInfo),
			auctionID = tInfo.auctionID,
			bidAmount = tInfo.bidAmount,
			minBid = tInfo.minBid,
			buyoutAmount = tInfo.buyoutAmount,
			bidder = tInfo.bidder,
			timeLeft = tInfo.timeLeft,
			leading = tIsOwnGuid(tInfo.bidder),
		}
	end)
end

local function tBidRowLabel(aRow)
	local tParts = { aRow.name }
	if aRow.leading then
		tParts[#tParts + 1] = L["your bid is highest"]
	else
		tParts[#tParts + 1] = L["outbid"]
	end
	if aRow.bidAmount and aRow.bidAmount > 0 then
		tParts[#tParts + 1] = L["Gebot "]..tMoneyText(aRow.bidAmount)
	end
	if aRow.buyoutAmount and aRow.buyoutAmount > 0 then
		tParts[#tParts + 1] = L["buyout "]..tMoneyText(aRow.buyoutAmount)
	end
	local tLeft = tTimeLeftText(aRow)
	if tLeft ~= "" then tParts[#tParts + 1] = L["left: "]..tLeft end
	return table.concat(tParts, ", ")
end

local function tAddBidRow(aParent, aRow)
	local tE = SkuOptions:InjectMenuItems(aParent, {tBidRowLabel(aRow)}, SkuGenericMenuItem)
	tE.dynamic = true
	tE.data = aRow
	tE.skuIdentity = "auction:"..aRow.auctionID
	tE.BuildChildren = function(self)
		self.children = {}
		local tData = self.data
		if tData.buyoutAmount and tData.buyoutAmount > 0 then
			tSettingLeaf(self, L["Kaufen"]..": "..tMoneyText(tData.buyoutAmount), function(aLeaf)
				AHF:BuyItemAuction(tData.auctionID, tData.buyoutAmount, tData.name, aLeaf)
			end)
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

function AHF:BuildBidsChildren(aSelf)
	tBuildListEntry(gBids, aSelf, L["No bids"], tAddBidRow)
end

function AHF:BuildSalesChildren(aSelf)
	aSelf.children = {}
	local tNew = SkuOptions:InjectMenuItems(aSelf, {L["Neue Auktion"]}, SkuGenericMenuItem)
	tNew.dynamic = true
	tNew.BuildChildren = tBuildSellList

	local tOwned = SkuOptions:InjectMenuItems(aSelf, {L["Current sales"]}, SkuGenericMenuItem)
	tOwned.dynamic = true
	tMarkEntering(tOwned)
	tOwned.BuildChildren = function(self)
		tBuildListEntry(gOwned, self, L["No current sales"], tAddOwnedRow)
	end
end

-- Blizzard's AuctionHouseFrame answers AUCTION_HOUSE_POST_WARNING / _ERROR with its own popup. Its Accept confirms
-- only a post made in Blizzard's sell frame, so for a Sku post it would do nothing: the popup is closed again.
-- Only for Sku's own post: while Sku owns it (gSell.posting, also while its confirmation is pending), or in the
-- frame in which AHF:OnPostRefused ended it (GetTime() is the same for every handler of one event, whichever of
-- Sku's and Blizzard's runs first). A post made in Blizzard's window keeps its popups.
hooksecurefunc("StaticPopup_Show", function(aWhich)
	if (gSell.posting or gSell.refusedAt == GetTime()) and (aWhich == "AUCTION_HOUSE_POST_WARNING" or aWhich == "AUCTION_HOUSE_POST_ERROR") then
		StaticPopup_Hide(aWhich)
	end
end)

function AHF:BuildSearchEntries(aSelf)
	-- Same flags and OnAction/BuildChildren shape as the search entry in SkuCore/auctionHouse.lua (tNewMenuEntrysearch):
	-- ENTER on its "enter search string" leaf runs the entry's OnAction (isSelect), which opens the edit box; the
	-- results follow that leaf.
	local tSearchEntry = SkuOptions:InjectMenuItems(aSelf, {L["auctions by seach string"]}, SkuGenericMenuItem)
	tSearchEntry.dynamic = true
	tSearchEntry.isSelect = true
	tSearchEntry.noStepUpAfterSelect = true
	tSearchEntry.sorting = true
	tSearchEntry.OnAction = function()
		SkuOptions:EditBoxShow("", function()
			local tText = SkuOptionsEditBoxEditBox:GetText()
			if tText == "" then return end
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

	-- Category browse: Blizzard's own AuctionCategories tree, with localized names and classID/subClassID/inventoryType
	-- filters per node. Blizzard_AuctionData.lua fills it when Blizzard_AuctionHouseUI loads, and this menu exists only
	-- while AuctionHouseFrame is shown, so the tree is always complete here. Every node (not just leaves) carries its
	-- own accumulated .filters, so browsing works at any depth ("all weapons" as well as "one-handed swords only").
	local tCategoryEntry = SkuOptions:InjectMenuItems(aSelf, {L["Auctions by category"]}, SkuGenericMenuItem)
	tCategoryEntry.dynamic = true
	tCategoryEntry.BuildChildren = function(self)
		self.children = {}
		tBuildCategoryChildren(self, AuctionCategories)
	end

	-- Filters (Blizzard: the filter menu next to the search bar): apply to name search and categories, saved settings.
	local tFilterEntry = SkuOptions:InjectMenuItems(aSelf, {L["Filters"]}, SkuGenericMenuItem)
	tFilterEntry.dynamic = true
	tFilterEntry.BuildChildren = function(self)
		self.children = {}
		local tF = AHF:GetFilter()
		local function tToggle(aLabel, aKey)
			local tLeaf = SkuOptions:InjectMenuItems(self, {aLabel}, SkuGenericMenuItem)
			SkuOptions:MakeToggleNode(tLeaf, {
				onLabel = L["Yes"],
				offLabel = L["No"],
				get = function() return tF[aKey] end,
				set = function(_, aNew) tF[aKey] = aNew or nil end,
			})
		end
		tToggle(L["Nur benutzbare"], "usable")
		tToggle(L["Upgrades only"], "upgrades")
		tToggle(L["Uncollected only"], "uncollected")
		tToggle(L["Current expansion only"], "currentExp")
		tToggle(L["Exact name for name searches"], "exact")
		local function tQualName()
			return L["Minimum quality: "]
				..(((tF.minQuality or 1) > 1) and tQualityName(tF.minQuality) or L["Any"])
		end
		tSettingLeaf(self, tQualName(), function(aLeaf)
			local tQ = (tF.minQuality or 1) + 1
			if tQ > 7 then tQ = 1 end
			tF.minQuality = (tQ > 1) and tQ or nil
			aLeaf.name = tQualName()
		end)
		local function tLevelLeaf(aLabel, aKey)
			local function tName() return aLabel..": "..(tF[aKey] or L["Any"]) end
			tSettingLeaf(self, tName(), function(aLeaf)
				SkuOptions:EditBoxShow("", function()
					local tText = SkuOptionsEditBoxEditBox:GetText()
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
	if C_AuctionHouse.FavoritesAreAvailable() then
		local tFavEntry = SkuOptions:InjectMenuItems(aSelf, {L["Favorites"]}, SkuGenericMenuItem)
		tFavEntry.dynamic = true
		tFavEntry.ahfFavorites = true
		tMarkEntering(tFavEntry)
		tFavEntry.BuildChildren = function(self)
			self.children = {}
			if tQueryOnEnter(self, gBrowse, function() AHF:StartFavorites(self) end) then
				tAppendBrowseResultChildren(self)
			end
		end
	end

	AHF:BuildFullScanEntry(aSelf)
end

-- Root: Auctions > [search, category, filters, favorites]; Sales > [new auction, current sales]; Bids.
function AHF:MenuBuilder(aSelf)
	local tAuctionsEntry = SkuOptions:InjectMenuItems(aSelf, {L["Auktionen"]}, SkuGenericMenuItem)
	tAuctionsEntry.dynamic = true
	tAuctionsEntry.BuildChildren = function(self)
		self.children = {}
		AHF:BuildSearchEntries(self)
	end

	local tSales = SkuOptions:InjectMenuItems(aSelf, {L["Verkäufe"]}, SkuGenericMenuItem)
	tSales.dynamic = true
	tSales.BuildChildren = function(selfSales) AHF:BuildSalesChildren(selfSales) end

	-- Auctions the player has bid on (Blizzard: Auctions tab > Bids).
	local tBidsEntry = SkuOptions:InjectMenuItems(aSelf, {L["Gebote"]}, SkuGenericMenuItem)
	tBidsEntry.dynamic = true
	tMarkEntering(tBidsEntry)
	tBidsEntry.BuildChildren = function(selfBids) AHF:BuildBidsChildren(selfBids) end
end

-- AUCTION_HOUSE_SHOW_ERROR carries only the error code, and Blizzard shows it only in UIErrorsFrame (no
-- UI_ERROR_MESSAGE, so Sku never hears it there). It answers Sku's own buyout or bid in flight first, then a
-- commodity purchase, then a post sent to the server (a post waiting for its confirmation sent nothing), then a
-- cancel, else a query still waiting: browse, detail, own auctions, bids or the sell draft's market price.
function AHF:OnShowError(aError)
	local tText = AuctionHouseUtil.GetErrorText(aError)
	dprint("ahf", "SHOW_ERROR", aError, tText)
	if gItemPurchase.auctionID then
		gItemPurchase.auctionID = nil
		if tText == "" then tText = gItemPurchase.isBuyout and L["Purchase failed"] or L["Bid failed"] end
		tSay((gItemPurchase.name and (gItemPurchase.name..": ") or "")..tText)
		return
	end
	if gCommodityBuy.itemID then
		AHF:EndCommodityBuy(tText ~= "" and tText or L["Purchase failed"])
		return
	end
	if tPostInFlight() then
		AHF:OnPostRefused(tText ~= "" and tText or AUCTION_POSTING_ERROR_TEXT)
		return
	end
	if gCancel then
		AHF:OnCancelRefused(tText ~= "" and tText or ERR_AUCTION_DATABASE_ERROR)
		return
	end
	-- A rejected query: the error becomes the waiting leaf, so the rebuild reads it out. A query still parked
	-- (pendingSend) was not sent, the error is not its answer.
	local tFailText = tText ~= "" and tText or ERR_AUCTION_DATABASE_ERROR
	local tFailed = false
	for _, tState in ipairs({ gBrowse, gDetail }) do
		if tState.state == "waiting" and not tState.pendingSend then
			tState.state = "failed"
			tState.failText = tFailText
			tRebuildAndFocus(tState.entry)
			tFailed = true
		end
	end
	for _, tList in ipairs({ gOwned, gBids }) do
		if tList.state == "waiting" and not tList.pendingSend then
			tList.state = "failed"
			tList.failText = tFailText
			tShowList(tList)
			tFailed = true
		end
	end
	if gSell.marketState == "waiting" and not gSell.pendingSend then
		gSell.marketState = "failed"
		gSell.marketFailText = tFailText
		tRefreshSellLabels()
		tSay(tMarketLabel())
		tFailed = true
	end
	if not tFailed and tText ~= "" then tSay(tText) end
end

-- ---------------------------------------------------------------------
-- FULL SCAN and price feed (the price lines of bag tooltips and chat item links, the sell price suggestion).
-- The legacy full scan (QueryAuctionItems getAll) does not exist on Forever. C_AuctionHouse.ReplicateItems asks the
-- server for every auction of the realm; REPLICATE_ITEM_LIST_UPDATE says the list is in; GetNumReplicateItems and
-- GetReplicateItemInfo(i) read it. The prices go into the price store of SkuCore/auctionHouse.lua
-- (AuctionIngestPriceData), the one every price reader uses. A browse result feeds the current prices of its items
-- the same way (AHF:FeedBrowsePrices).
-- ReplicateItems sends the whole auction list in one answer; on a busy server that answer can disconnect the client.
-- The server answers it once per 15 minutes; the menu entry uses the legacy full scan's cooldown
-- (AuctionLastFullScanTime, AuctionFullScanCooldownRemaining).
-- The list is read from an OnUpdate within a time budget per frame and the position is kept per row, so a frame the
-- client's script limit cuts short loses nothing and the next frame goes on.
-- A row without hasAllInfo waits for its item data (C_Item.RequestLoadItemDataByID -> ITEM_DATA_LOAD_RESULT) and is
-- read again then. FULLSCAN_ITEM_GRACE seconds after the last load the waiting rows are read as they are, so the scan
-- always ends.
-- ---------------------------------------------------------------------
local FULLSCAN_FRAME_MS = 15
local FULLSCAN_ANSWER_TIMEOUT = 120
local FULLSCAN_ITEM_GRACE = 10
local FULLSCAN_SPEAK_EVERY = 10

-- state: idle, waiting (for the server's list), reading (the rows), loading (rows waiting for their item data).
local gScan = { state = "idle" }
local gScanFrame = CreateFrame("Frame")
gScanFrame:Hide()

-- Adds one price point per kind (bid, buyout) in copper per unit to aPriceData, AuctionBuildPriceData's shape
-- ([itemID] = { [1] = bids, [2] = buyouts }). A price of 0 is no price (no buyout, or no bid on a commodity).
local function tAddPrices(aPriceData, aItemID, aCount, aMinBid, aBuyout)
	if aCount == 0 or aItemID == 0 or (aMinBid == 0 and aBuyout == 0) then return end
	local tBucket = aPriceData[aItemID]
	if not tBucket then
		tBucket = { [1] = {}, [2] = {} }
		aPriceData[aItemID] = tBucket
	end
	if aMinBid > 0 then tBucket[1][#tBucket[1] + 1] = math.max(1, math.floor(aMinBid / aCount)) end
	if aBuyout > 0 then tBucket[2][#tBucket[2] + 1] = math.max(1, math.floor(aBuyout / aCount)) end
end

-- Reads row i of the replicate list into the scan. aDefer: a row whose item data is not loaded yet is not read but
-- returned as its item ID.
local function tReadReplicateRow(i, aDefer)
	local _, _, tCount, _, _, _, _, tMinBid, _, tBuyout, _, _, _, _, _, _, tItemID, tHasAllInfo = C_AuctionHouse.GetReplicateItemInfo(i)
	if aDefer and not tHasAllInfo then return tItemID end
	tAddPrices(gScan.priceData, tItemID, tCount, tMinBid, tBuyout)
end

local function tReadDeferred(aItemID)
	local tRows = gScan.deferred[aItemID]
	if not tRows then return end
	gScan.deferred[aItemID] = nil
	for _, i in ipairs(tRows) do tReadReplicateRow(i) end
	gScan.deferredRows = gScan.deferredRows - #tRows
end

local function tScanPercent()
	return math.floor((gScan.index - gScan.deferredRows) * 100 / gScan.total)
end

-- The menu entry's name carries the scan's state.
local function tFullScanLabel()
	if gScan.state == "waiting" then return L["Full scan started"] end
	if gScan.state ~= "idle" then return L["full scan"]..", "..tScanPercent()..L[" Prozent"] end
	local tRemain = SkuCore.AuctionHouse:AuctionFullScanCooldownRemaining()
	if tRemain > 0 then return L["full scan"].." "..L["Ready in"].." "..tRemain..L[" Minuten"] end
	return L["start full scan"]
end

local function tStopScan()
	gScan.pendingSend = nil
	gScanFrame:Hide()
	gScan = { state = "idle" }
end

local function tFinishScan()
	local tPriceData, tAuctions = gScan.priceData, gScan.total
	tStopScan()
	local tItems = 0
	for _ in pairs(tPriceData) do tItems = tItems + 1 end
	SkuCore.AuctionHouse:AuctionIngestPriceData(tPriceData, true)
	dprint("ahf", "full scan done:", tAuctions, "auctions,", tItems, "items")
	tSay(L["Full scan completed"]..";"..tAuctions.." "..L["Auktionen"]..";"..L["AHF_FullScanItems"]:format(tItems))
end

gScanFrame:SetScript("OnUpdate", function(_, aElapsed)
	local tScan = gScan
	tScan.elapsed = tScan.elapsed + aElapsed
	if tScan.state == "waiting" then
		if tScan.elapsed >= FULLSCAN_ANSWER_TIMEOUT then
			dprint("ahf", "full scan: no answer")
			tStopScan()
			tSay(L["full scan"]..";"..L["STRAT_SearchTimeout"])
			return
		end
	else
		local tStart = debugprofilestop()
		while tScan.index < tScan.total and debugprofilestop() - tStart < FULLSCAN_FRAME_MS do
			local i = tScan.index + 1
			local tWaitFor = tReadReplicateRow(i, true)
			if tWaitFor then
				local tRows = tScan.deferred[tWaitFor]
				if not tRows then
					tRows = {}
					tScan.deferred[tWaitFor] = tRows
					C_Item.RequestLoadItemDataByID(tWaitFor)
				end
				tRows[#tRows + 1] = i
				tScan.deferredRows = tScan.deferredRows + 1
			end
			tScan.index = i
		end
		while tScan.loaded[1] and debugprofilestop() - tStart < FULLSCAN_FRAME_MS do
			tReadDeferred(table.remove(tScan.loaded))
		end
		if tScan.index >= tScan.total then
			if tScan.state == "reading" then
				tScan.state = "loading"
				tScan.lastLoad = tScan.elapsed
			end
			if tScan.deferredRows == 0 then
				tFinishScan()
				return
			end
			if not tScan.givenUp and tScan.elapsed - tScan.lastLoad >= FULLSCAN_ITEM_GRACE then
				tScan.givenUp = true
				dprint("ahf", "full scan: item data missing, read as it is:", tScan.deferredRows, "rows")
				for tItemID in pairs(tScan.deferred) do tScan.loaded[#tScan.loaded + 1] = tItemID end
			end
		end
	end
	if tScan.elapsed - tScan.spokenAt >= FULLSCAN_SPEAK_EVERY then
		tScan.spokenAt = tScan.elapsed
		if tScan.state == "waiting" then
			tSay(L["full scan"]..", "..math.floor(tScan.elapsed)..L[" Sekunden"])
		else
			tSay(tFullScanLabel())
		end
	end
end)

-- From the menu entry's key press. The key handler reads the entry right after, so its name says what happened.
function AHF:StartFullScan(aLeaf)
	if gScan.state == "idle" and SkuCore.AuctionHouse:AuctionFullScanCooldownRemaining() == 0 then
		gScan = {
			state = "waiting", elapsed = 0, spokenAt = 0, index = 0, total = 0, priceData = {},
			deferred = {}, deferredRows = 0, loaded = {}, lastLoad = 0,
		}
		SkuSettings:Sub("SkuCore", nil, "char").AuctionLastFullScanTime = GetServerTime()
		tSendThrottled(gScan, C_AuctionHouse.ReplicateItems)
		gScanFrame:Show()
		dprint("ahf", "full scan started")
	end
	aLeaf.name = tFullScanLabel()
end

function AHF:OnReplicateListUpdate()
	if gScan.state ~= "waiting" then return end
	gScan.total = C_AuctionHouse.GetNumReplicateItems()
	-- An empty answer: the list is not in yet; the next update or the answer timeout ends the wait.
	if gScan.total == 0 then return end
	gScan.state = "reading"
	dprint("ahf", "full scan: list in,", gScan.total, "auctions")
end

function AHF:OnItemDataLoaded(aItemID)
	if gScan.state == "idle" or not gScan.deferred[aItemID] then return end
	gScan.loaded[#gScan.loaded + 1] = aItemID
	gScan.lastLoad = gScan.elapsed
end

-- Closing the auction house ends the scan; what was read so far is dropped.
function AHF:AbortFullScan()
	if gScan.state == "idle" then return end
	dprint("ahf", "full scan aborted: auction house closed")
	tStopScan()
	tSay(L["full scan"]..";"..L["Abgebrochen"])
end

function AHF:BuildFullScanEntry(aParent)
	local tLeaf = tSettingLeaf(aParent, tFullScanLabel(), function(aLeaf) AHF:StartFullScan(aLeaf) end)
	tLeaf.OnEnter = function(self) self.name = tFullScanLabel() end
end

-- A browse result's cheapest price per item (minPrice: per unit for commodities, the cheapest listing otherwise)
-- replaces the current prices of those items. Rows of one item with different item levels give several prices.
function AHF:FeedBrowsePrices(aRows)
	local tPriceData = {}
	for i = 1, #aRows do
		tAddPrices(tPriceData, aRows[i].itemKey.itemID, 1, 0, aRows[i].minPrice)
	end
	SkuCore.AuctionHouse:AuctionIngestPriceData(tPriceData, false)
end

-- ---------------------------------------------------------------------
-- Events. One own frame, independent of SkuCore.AuctionHouse's AceEvent mixin, so the legacy module's event set
-- (auctionHouse.lua) stays untouched.
-- ---------------------------------------------------------------------
-- ITEM_KEY_ITEM_INFO_RECEIVED fires once per item name, hundreds of times for a big result: the lists still
-- waiting for names are read again once per frame.
local gNamesQueued = false
local function tNamesWanted()
	return (gBrowse.state == "waiting" and gBrowse.answered) or gOwned.namePending or gBids.namePending
end
local function tReadNamedLists()
	gNamesQueued = false
	if gBrowse.state == "waiting" and gBrowse.answered then AHF:RefreshBrowseResults() end
	if gOwned.namePending then AHF:RefreshOwned() end
	if gBids.namePending then AHF:RefreshBids() end
end

local function tOnItemSearchResults(aItemKey)
	AHF:RefreshDetailResults(aItemKey.itemID)
	AHF:OnSellMarketResult(false, aItemKey.itemID)
end

local function tOnCommoditySearchResults(aItemID)
	AHF:RefreshDetailResults(aItemID)
	AHF:OnSellMarketResult(true, aItemID)
end

local gEventHandlers = {
	AUCTION_HOUSE_THROTTLED_SYSTEM_READY = tSendParked,
	AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = function() AHF:RefreshBrowseResults() end,
	AUCTION_HOUSE_BROWSE_RESULTS_ADDED = function() AHF:RefreshBrowseResults() end,
	AUCTION_HOUSE_BROWSE_FAILURE = function()
		-- The server could not run the query. Blizzard's result list shows ERR_AUCTION_DATABASE_ERROR
		-- for it; an empty result is a results event with no rows, not this.
		if gBrowse.state == "waiting" and not gBrowse.pendingSend then
			gBrowse.state = "failed"
			gBrowse.failText = ERR_AUCTION_DATABASE_ERROR
			tRebuildAndFocus(gBrowse.entry)
		end
	end,
	ITEM_KEY_ITEM_INFO_RECEIVED = function()
		if gNamesQueued or not tNamesWanted() then return end
		gNamesQueued = true
		C_Timer.After(0, tReadNamedLists)
	end,
	ITEM_SEARCH_RESULTS_UPDATED = tOnItemSearchResults,
	ITEM_SEARCH_RESULTS_ADDED = tOnItemSearchResults,
	COMMODITY_SEARCH_RESULTS_UPDATED = tOnCommoditySearchResults,
	COMMODITY_SEARCH_RESULTS_ADDED = tOnCommoditySearchResults,
	COMMODITY_PRICE_UPDATED = function(aUnitPrice, aTotalPrice) AHF:OnCommodityPriceUpdated(aUnitPrice, aTotalPrice) end,
	COMMODITY_PRICE_UNAVAILABLE = function() AHF:EndCommodityBuy(L["Price unavailable"]) end,
	COMMODITY_PURCHASE_SUCCEEDED = function()
		-- Blizzard's buy display goes back to quantity 1 after a purchase.
		if gCommodityBuy.itemID then gDetail.buyQty = 1 end
		AHF:EndCommodityBuy(L["Purchase complete"])
	end,
	COMMODITY_PURCHASE_FAILED = function() AHF:EndCommodityBuy(L["Purchase failed"]) end,
	AUCTION_HOUSE_SHOW_ERROR = function(aError) AHF:OnShowError(aError) end,
	AUCTION_HOUSE_PURCHASE_COMPLETED = function(aAuctionID) AHF:OnItemPurchaseCompleted(aAuctionID) end,
	BID_ADDED = function()
		-- The one confirmation of a bid. Only while the auction house window is shown: Blizzard's own frames listen
		-- to BID_ADDED only then. The bid list already holds the new bid, so it is read again, not asked for again
		-- (Blizzard: AuctionHouseAuctionsFrameMixin, BidsList:DirtyScrollFrame).
		if not gItemPurchase.isBuyout then gItemPurchase.auctionID = nil end
		if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
			tSay(L["Gebot abgegeben"])
			AHF:RefreshBids()
		end
	end,
	BIDS_UPDATED = function() AHF:RefreshBids() end,
	-- After a favourite was added or removed here, an open favourites list asks the server again once the server
	-- has stored the change, so going back to the list shows it as it is now.
	AUCTION_HOUSE_FAVORITES_UPDATED = function()
		if not gFavoritesChanged then return end
		gFavoritesChanged = nil
		if gBrowse.entry and gBrowse.entry.ahfFavorites then AHF:StartFavorites(gBrowse.entry) end
	end,
	OWNED_AUCTIONS_UPDATED = function() AHF:RefreshOwned() end,
	AUCTION_CANCELED = function() AHF:OnAuctionCanceled() end,
	AUCTION_HOUSE_AUCTION_CREATED = function()
		-- Fires once per auction, also for posts made in Blizzard's own window; a multisell ends with its own events.
		if not tPostInFlight() or gSell.multisellExpected then return end
		tPostFinished(gSell.name..": "..L["Auction posted"])
	end,
	AUCTION_MULTISELL_START = function(aTotal)
		if tPostInFlight() then gSell.multisell = { created = 0, total = aTotal } end
	end,
	-- Only the end of a multisell is spoken: progress lines would talk over the menu for as long as it runs.
	AUCTION_MULTISELL_UPDATE = function(aCreated, aTotal)
		local tM = gSell.multisell
		if not tM then return end
		tM.created, tM.total = aCreated, aTotal
		if tM.created >= tM.total then
			tPostFinished(gSell.name..": "..L["Auction %d of %d posted"]:format(tM.total, tM.total))
		end
	end,
	AUCTION_MULTISELL_FAILURE = function()
		if not gSell.multisell and not gSell.multisellExpected then return end
		local tM = gSell.multisell
		local tText = gSell.name..": "..L["Multi-posting failed"]
		if tM and tM.created > 0 then tText = tText..";"..L["Auction %d of %d posted"]:format(tM.created, tM.total) end
		tPostFinished(tText)
	end,
	AUCTION_HOUSE_POST_ERROR = function()
		-- Blizzard's error popup has only OK: the post cannot be confirmed.
		if not tPostInFlight() then return end
		AHF:OnPostRefused(AUCTION_POSTING_ERROR_TEXT)
	end,
	BAG_UPDATE_DELAYED = function() tFollowBags() end,
	REPLICATE_ITEM_LIST_UPDATE = function() AHF:OnReplicateListUpdate() end,
	ITEM_DATA_LOAD_RESULT = function(aItemID) AHF:OnItemDataLoaded(aItemID) end,
	AUCTION_HOUSE_CLOSED = function()
		-- As Blizzard's buy dialog and sell frame on hide: an open quote is dropped, a running multisell stopped.
		if gCommodityBuy.itemID then C_AuctionHouse.CancelCommoditiesPurchase() end
		if gSell.multisell then C_AuctionHouse.CancelSell() end
		AHF:AbortFullScan()
		gCommodityBuy.itemID, gItemPurchase.auctionID, gCancel = nil, nil, nil
		for _, tState in ipairs({ gBrowse, gDetail, gOwned, gBids }) do
			tState.state, tState.entry, tState.pendingSend = "idle", nil, nil
		end
		gBrowse.results, gDetail.results, gDetail.itemKey = {}, {}, nil
		gOwned.rows, gOwned.notice, gBids.rows = {}, nil, {}
		gSell = { duration = gSell.duration }
		gSellList = nil
		wipe(gThrottleWaiting)
	end,
}

local gEventFrame = CreateFrame("Frame")
for tEvent in pairs(gEventHandlers) do
	if Sku.IsEventValid(tEvent) then gEventFrame:RegisterEvent(tEvent) end
end
gEventFrame:SetScript("OnEvent", function(_, aEvent, ...)
	gEventHandlers[aEvent](...)
end)
