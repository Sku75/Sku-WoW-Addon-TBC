---------------------------------------------------------------------------------------------------------------------------------------
-- Rolling on group loot: the roll announcement, the need / greed / pass keys, the roll info key and the item's tooltip on
-- the quest share key.
-- Everything goes through the roll ID and the game's loot functions, the calls Blizzard's own roll frames make
-- (GetActiveLootRollIDs, GetLootRollItemInfo, RollOnLoot, ConfirmLootRoll), so every client runs the same path. Sku used to
-- read Blizzard's GroupLootFrame1..6 and click their buttons, which only ever called RollOnLoot; on WoW Forever those frames
-- are not shown yet when START_LOOT_ROLL fires and their buttons sit in .LootButtonContainer.
-- The events are registered by SkuOptions (SkuZOptions/Core.lua), which hands them on to the functions here.
---------------------------------------------------------------------------------------------------------------------------------------
local L = Sku.L
local GetItemInfo = Sku.Compat.GetItemInfo

SkuCore.LootRoll = {}
local LootRoll = SkuCore.LootRoll

local tRolled = {}        -- [rollID] = true once Sku has answered it, until CANCEL_LOOT_ROLL ends the roll
local tPendingConfirm     -- { id, type, at } of the last roll Sku made, for CONFIRM_LOOT_ROLL

-- What the game tells about one roll; nil while it does not know the item yet.
local function tRollItem(aRollID)
	local _, tName, tCount, tQuality, tBindOnPickUp, tCanNeed, tCanGreed, _, _, _, _, _, tCanTransmog = GetLootRollItemInfo(aRollID)
	if not tName then return nil end
	local tLink = GetLootRollItemLink(aRollID)
	local tType, tSubType, tBindType
	if tLink then
		local _, _, _, _, _, tT, tS, _, _, _, _, _, _, tB = GetItemInfo(tLink)
		tType, tSubType, tBindType = tT, tS, tB
	end
	-- AtlasLoot favorites
	local tFavorite = ""
	local tInvType = tLink and C_Item.GetItemInventoryTypeByID(tLink)
	local tAl = SkuCore.AtlasLootIntegration
	if tInvType and tAl and tAl.favoriteSlots and tAl.favoriteSlots[tInvType] and tAl.favoriteSlots[tInvType][1] then
		local tList = SkuOptions.db.char["SkuCore"].alIntegration.favorites[tInvType] or {}
		for q = 1, #tList do
			if tList[q] == tLink then
				tFavorite = L["Prio"].." "..q.." "..L["in AtlasLoot favorites for"].." "..tAl.GetSlotLabel(tAl.favoriteSlots[tInvType][1])
			end
		end
	end
	return {
		name = tName, count = tCount or 1, link = tLink,
		quality = (tQuality and _G["ITEM_QUALITY"..tQuality.."_DESC"]) or "",
		type = tType or "", subtype = tSubType or "", alFavoriteString = tFavorite,
		bind = (tBindType and SkuOptions.BindTypeStrings[tBindType]) or (tBindOnPickUp and L["BOP"]) or "",
		-- canTransmog only exists on WoW Forever (nil elsewhere)
		canNeed = tCanNeed and true or false, canGreed = tCanGreed and true or false, canTransmog = tCanTransmog and true or false,
	}
end

local function tRollText(aItem)
	local tParts = { L["Roll on"].." "..aItem.name }
	if aItem.count > 1 then tParts[#tParts + 1] = aItem.count.." "..L["STRAT_Pieces"] end
	for _, tValue in ipairs({ aItem.alFavoriteString, aItem.quality, aItem.bind, aItem.type, aItem.subtype }) do
		if tValue ~= "" then tParts[#tParts + 1] = tValue end
	end
	if not aItem.canNeed then tParts[#tParts + 1] = L["need not possible"] end
	return table.concat(tParts, ", ")
end

-- The roll the keys act on: the oldest open one Sku has not answered yet. aAnyOpen: else the newest open one, so the info
-- and tooltip keys still read an item after rolling on it, until the roll ends.
local function tCurrentRollID(aAnyOpen)
	local tIDs = GetActiveLootRollIDs() or {}
	table.sort(tIDs)
	for _, tID in ipairs(tIDs) do
		if not tRolled[tID] then return tID end
	end
	if aAnyOpen then return tIDs[#tIDs] end
end

-- The game may not know the item when the roll starts: ask again a few times.
local function tAnnounce(aRollID, aTry)
	local tItem = tRollItem(aRollID)
	if not tItem then
		if aTry < 6 then
			C_Timer.After(0.4, function() tAnnounce(aRollID, aTry + 1) end)
		else
			SkuOptions.Voice:OutputStringBTtts(L["Roll on"].." "..L["item"], false, true, 0.3, true, nil, nil, 2)
		end
		return
	end
	-- Rolls often start in the same second as another announcement ("combat end" when the boss dies). A line that overwrites the
	-- queue at that moment cuts this one before it is spoken, so it waits a moment and queues behind what is playing.
	local tText = tRollText(tItem)
	C_Timer.After(1.2, function()
		SkuOptions.Voice:OutputStringBTtts(tText, false, true, 0.3, true, nil, nil, 2)
	end)
end

function LootRoll.OnStart(aRollID)
	tRolled[aRollID] = nil
	tAnnounce(aRollID, 0)
end

function LootRoll.OnCancel(aRollID)
	tRolled[aRollID] = nil
	if tPendingConfirm and tPendingConfirm.id == aRollID then tPendingConfirm = nil end
end

-- A bound item: the game asks once more (Blizzard shows its CONFIRM_LOOT_ROLL popup and hides it again when the roll ends);
-- the key press already was the answer.
function LootRoll.OnConfirm(aRollID, aRollType)
	if tPendingConfirm and tPendingConfirm.id == aRollID and GetTime() - tPendingConfirm.at < 10 then
		ConfirmLootRoll(aRollID, aRollType or tPendingConfirm.type)
	end
end

-- aKind: "need" | "greed" | "pass". Runs from a key press.
function LootRoll.Roll(aKind)
	local tID = tCurrentRollID()
	local tItem = tID and tRollItem(tID)
	if not tItem then
		SkuOptions.Voice:OutputStringBTtts(L["no roll open"], true, true, 0.3, true, nil, nil, 2)
		return
	end
	local tRollType, tSpoken
	if aKind == "need" then
		if not tItem.canNeed then
			SkuOptions.Voice:OutputStringBTtts(L["need not possible"], true, true, 0.3, true, nil, nil, 2)
			return
		end
		tRollType, tSpoken = 1, L["Need rolled"]
	elseif aKind == "greed" then
		-- like Blizzard's greed key on Forever: greed if possible, else transmog
		if tItem.canGreed then
			tRollType = 2
		elseif tItem.canTransmog then
			tRollType = 4
		else
			SkuOptions.Voice:OutputStringBTtts(L["greed not possible"], true, true, 0.3, true, nil, nil, 2)
			return
		end
		tSpoken = L["Greed rolled"]
	else
		tRollType, tSpoken = 0, L["Pass rolled"]
	end
	tPendingConfirm = { id = tID, type = tRollType, at = GetTime() }
	RollOnLoot(tID, tRollType)
	tRolled[tID] = true
	SkuOptions.Voice:OutputString(tSpoken, true, true, 0.3, true)
	-- several items at once: the next one is announced
	local tNext = tCurrentRollID()
	local tNextItem = tNext and tRollItem(tNext)
	if tNextItem then
		SkuOptions.Voice:OutputStringBTtts(tRollText(tNextItem), false, true, 0.3, true, nil, nil, 2)
	end
end

function LootRoll.SpeakInfo()
	local tID = tCurrentRollID(true)
	local tItem = tID and tRollItem(tID)
	if not tItem then
		SkuOptions.Voice:OutputStringBTtts(L["no roll open"], true, true, 0.3, true, nil, nil, 2)
		return
	end
	SkuOptions.Voice:OutputStringBTtts(tRollText(tItem), true, true, 0.3, true, nil, nil, 2)
end

-- The tooltip of the open roll's item plus the equipped items for comparison, in the reading frame. False when no roll is open.
function LootRoll.ReadTooltip()
	local tID = tCurrentRollID(true)
	local tItem = tID and tRollItem(tID)
	if not tItem then return false end
	local tText
	if Sku.isForever then
		-- the scanning tooltip cannot show the item there; the roll's tooltip data can
		local tLines = SkuCore:TooltipDataLines(C_TooltipInfo.GetLootRollItem(tID) or (tItem.link and C_TooltipInfo.GetHyperlink(tItem.link)))
		tText = tLines and table.concat(tLines, "\r\n")
	elseif tItem.link then
		SkuUtil:ResetScanningTooltip()
		SkuScanningTooltip:SetHyperlink(tItem.link)
		SkuScanningTooltip:Show()
		local tLines = TooltipLines_helper(SkuScanningTooltip:GetRegions())
		if tLines ~= "asd" and tLines ~= "" then tText = tLines end
	end
	tText = tText and SkuUtil:Unescape(tText)
	if not tText or tText == "" then
		SkuOptions.Voice:OutputStringBTtts(L["No tooltip available"], true, true, 0.3, true, nil, nil, 2)
		return true
	end
	SkuOptions.TooltipReaderText = { tText }
	local tSections = tItem.link and SkuCore:getItemComparisnSections(tItem.link, {})
	for i, tSection in ipairs(tSections or {}) do
		local tHeader = #tSections > 1 and L["currently equipped"].." "..i.."\r\n" or L["currently equipped"].."\r\n"
		table.insert(SkuOptions.TooltipReaderText, i + 1, tHeader..tSection)
	end
	SkuOptions.TTS:Output(SkuOptions.TooltipReaderText, 1000)
	SkuOptions.TTS:PreviousLine()
	return true
end
