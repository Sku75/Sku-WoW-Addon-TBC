---------------------------------------------------------------------------------------------------------------------------------------
-- Rolling on group loot on WoW Forever.
-- The classic code announces a roll from Blizzard's loot frames (GroupLootFrame1..6) and clicks their buttons. On Forever that
-- gives nothing: the frames are not visible yet when START_LOOT_ROLL fires, the buttons sit in .LootButtonContainer, and AceEvent
-- hands the event name over first, so the roll ID of the classic handler is the text "START_LOOT_ROLL". Here everything goes
-- through the roll ID and the game's own loot functions (the ones Blizzard's GroupLootFrame uses: GetLootRollItemInfo,
-- GetActiveLootRollIDs, RollOnLoot), and the confirmation of a bound item through CONFIRM_LOOT_ROLL.
-- The functions are called from the classic code in SkuZOptions/Core.lua behind Sku.isForever; nothing changes elsewhere.
---------------------------------------------------------------------------------------------------------------------------------------
if not Sku.isForever then return end

local L = Sku.L

local tActiveRolls = {}   -- [rollID] = GetTime() of START_LOOT_ROLL, for the case GetActiveLootRollIDs says nothing
local tRolled = {}        -- [rollID] = true once Sku has answered it
local tPendingConfirm     -- { id, type, at } of the roll waiting for CONFIRM_LOOT_ROLL

SkuCore.RollForever = {}
local RollForever = SkuCore.RollForever

-- What the game tells about one roll; nil while it does not know the item yet.
local function tRollItem(aRollID)
	if not aRollID then return nil end
	local _, tName, tCount, tQuality, tBindOnPickUp, tCanNeed, tCanGreed, _, _, _, _, _, tCanTransmog = GetLootRollItemInfo(aRollID)
	if not tName then return nil end
	local tLink = GetLootRollItemLink and GetLootRollItemLink(aRollID)
	local tType, tSubType, tBindType, tItemQuality
	if tLink then
		local _, _, tQ, _, _, tT, tS, _, _, _, _, _, _, tB = C_Item.GetItemInfo(tLink)
		tItemQuality, tType, tSubType, tBindType = tQ, tT, tS, tB
	end
	local tQualityIndex = tQuality or tItemQuality
	local tBind = (tBindType and SkuOptions.BindTypeStrings[tBindType]) or (tBindOnPickUp and L["BOP"]) or ""
	-- AtlasLoot favorites, as in the classic announcement
	local tFavorite = ""
	local tInvType = tLink and C_Item.GetItemInventoryTypeByID(tLink)
	local tAl = SkuCore.AtlasLootIntegration
	if tInvType and tAl and tAl.favoriteSlots and tAl.favoriteSlots[tInvType] and tAl.favoriteSlots[tInvType][1] then
		local tList = SkuOptions.db.char["SkuCore"].alIntegration.favorites[tInvType]
		for q = 1, #(tList or {}) do
			if tList[q] == tLink then
				tFavorite = L["Prio"].." "..q.." "..L["in AtlasLoot favorites for"].." "..tAl.GetSlotLabel(tAl.favoriteSlots[tInvType][1])
			end
		end
	end
	return {
		name = tName, count = tCount or 1,
		quality = (tQualityIndex and _G["ITEM_QUALITY"..tQualityIndex.."_DESC"]) or "",
		type = tType or "", subtype = tSubType or "", bind = tBind,
		itemId = tLink, rollId = aRollID, alFavoriteString = tFavorite,
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

-- The roll that counts now: the oldest one not answered yet, else the newest.
local function tCurrentRollID()
	local tList = {}
	for _, tID in ipairs(GetActiveLootRollIDs() or {}) do tList[#tList + 1] = tID end
	if #tList == 0 then
		for tID, tTime in pairs(tActiveRolls) do
			if GetTime() - tTime < 180 then tList[#tList + 1] = tID end
		end
		table.sort(tList)
	end
	for _, tID in ipairs(tList) do
		if not tRolled[tID] then return tID end
	end
	return tList[#tList]
end

-- Roll ID and item data of the current roll, or nil.
function RollForever.Current()
	local tID = tCurrentRollID()
	local tItem = tID and tRollItem(tID)
	if tItem then return tID, tItem end
	return nil, nil
end

-- The game may not know the item when the roll starts: ask again a few times.
local function tAnnounce(aRollID, aTry)
	local tItem = tRollItem(aRollID)
	if not tItem then
		if aTry < 6 then
			C_Timer.After(0.4, function() tAnnounce(aRollID, aTry + 1) end)
		else
			SkuOptions.Voice:OutputStringBTtts(L["Roll on"].." "..L["item"], true, true, 0.3, true, nil, nil, 2)
		end
		return
	end
	SkuOptions.nextRollFrameNumber = aRollID
	-- Rolls often start in the same second as another announcement ("combat end" when the boss dies). A line that overwrites the
	-- queue at that moment cuts this one before it is spoken, so it waits a moment and queues behind what is playing.
	local tText = tRollText(tItem)
	C_Timer.After(1.2, function()
		SkuOptions.Voice:OutputStringBTtts(tText, false, true, 0.3, true, nil, nil, 2)
	end)
end

function RollForever.OnStart(aRollID)
	if not aRollID then return end
	tActiveRolls[aRollID] = GetTime()
	tRolled[aRollID] = nil
	tAnnounce(aRollID, 0)
end

function RollForever.OnCancel(aRollID)
	if not aRollID then return end
	tActiveRolls[aRollID] = nil
	tRolled[aRollID] = nil
end

-- aKind: "need" | "greed" | "pass". Runs from a key press.
function RollForever.Roll(aKind)
	local tID, tItem = RollForever.Current()
	if not tID then
		SkuOptions.Voice:OutputString(L["no roll open"], true, true, 0.3, true)
		return
	end
	local tRollType, tSpoken
	if aKind == "need" then
		if not tItem.canNeed then
			SkuOptions.Voice:OutputString(L["need not possible"], true, true, 0.3, true)
			return
		end
		tRollType, tSpoken = 1, L["Need rolled"]
	elseif aKind == "greed" then
		if tItem.canGreed then
			tRollType = 2
		elseif tItem.canTransmog then
			tRollType = 4
		else
			SkuOptions.Voice:OutputString(L["greed not possible"], true, true, 0.3, true)
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
	-- A bound item asks for a confirmation: CONFIRM_LOOT_ROLL answers it, the popup click is the same fallback the classic roll keys use.
	C_Timer.After(0.5, function()
		local tPopup = _G["StaticPopup1"]
		if tPopup and tPopup:IsVisible() and tPopup.which == "CONFIRM_LOOT_ROLL" and _G["StaticPopup1Button1"] then
			_G["StaticPopup1Button1"]:Click()
		end
	end)
end

-- Reads the roll's item like the tooltip key does: Blizzard's tooltip data of the roll, then the equipped items for comparison.
function RollForever.ReadTooltip(aRollID, aItem)
	local tData = C_TooltipInfo.GetLootRollItem(aRollID)
	if not tData and aItem.itemId then tData = C_TooltipInfo.GetHyperlink(aItem.itemId) end
	local tOut = {}
	for _, tLine in ipairs(tData and tData.lines or {}) do
		local tLeft, tRight = tLine.leftText, tLine.rightText
		if type(tLeft) == "string" and not Sku.IsSecret(tLeft) and tLeft ~= "" and not string.find(tLeft, "Open Issue Report", 1, true) then
			if type(tRight) == "string" and not Sku.IsSecret(tRight) and tRight ~= "" then tLeft = tLeft.." "..tRight end
			tOut[#tOut + 1] = tLeft
		end
	end
	if #tOut == 0 then
		SkuOptions.Voice:OutputString(L["no tooltip available"], true, true, 0.3, true)
		return
	end
	SkuOptions.TooltipReaderText = { SkuUtil:Unescape(table.concat(tOut, "\r\n")) }
	local tSections = aItem.itemId and SkuCore:getItemComparisnSections(aItem.itemId, {})
	for i, tSection in ipairs(tSections or {}) do
		local tHeader = #tSections > 1 and L["currently equipped"].." "..i.."\r\n" or L["currently equipped"].."\r\n"
		table.insert(SkuOptions.TooltipReaderText, i + 1, tHeader..tSection)
	end
	SkuOptions.TTS:Output(SkuOptions.TooltipReaderText, 1000)
	SkuOptions.TTS:PreviousLine()
end

-- A bound item: the game asks once more, this answers it (registered in SkuZOptions/Core.lua).
function RollForever.OnConfirm(aRollID, aRollType)
	if tPendingConfirm and tPendingConfirm.id == aRollID and GetTime() - tPendingConfirm.at < 10 then
		ConfirmLootRoll(aRollID, aRollType or tPendingConfirm.type)
	end
end
