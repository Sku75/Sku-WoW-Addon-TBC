-- Pawn integration: Addons > Pawn (status + Pawn's own tooltip switches) and
-- the Pawn additions to Sku's item tooltips (upgrade verdict below the item
-- name, signed attribute/DPS deltas on the matching lines, attributes the
-- equipped item has that the candidate lacks). Every Pawn call is guarded and
-- the tooltip pass is pcall-wrapped: without Pawn nothing is added.
-- Contributed by Yennesta (PR #19).
SkuCore.PawnIntegration = SkuCore.PawnIntegration or {}
local PawnIntegration = SkuCore.PawnIntegration
local L = Sku.L

local function IsPawnAvailable()
	return _G.PawnCommon and _G.PawnGetItemData
end

local function FormatSigned(aValue, aDecimals, aSuffix)
	local tSign = aValue < 0 and Sku.deEn("minus", "minus", "moins") or Sku.deEn("plus", "plus", "plus")
	local tNumber = string.format(aDecimals == 1 and "%.1f" or "%d", math.abs(aValue))
	return tSign.." "..tNumber..(aSuffix or "")
end

-- Append aSuffix to the first line of aText that contains aNeedle. The match is
-- case-insensitive: the global stat name ("Damage Per Second") and the tooltip
-- line ("(41.5 damage per second)") differ in case on enUS clients, and a
-- case-sensitive match silently dropped the DPS delta there.
local function AppendToLineContaining(aText, aNeedle, aSuffix)
	local tNeedle = string.lower(aNeedle)
	local tOut, tPos, tHit = {}, 1, false
	while true do
		local tBreak = string.find(aText, "\r\n", tPos, true)
		local tLine = string.sub(aText, tPos, (tBreak or (#aText + 1)) - 1)
		if not tHit and tNeedle ~= "" and string.find(string.lower(tLine), tNeedle, 1, true) then
			tLine = tLine..aSuffix
			tHit = true
		end
		tOut[#tOut + 1] = tLine
		if not tBreak then break end
		tPos = tBreak + 2
	end
	return table.concat(tOut, "\r\n"), tHit
end

function PawnIntegration:MenuBuilder()
	if not IsPawnAvailable() then
		SkuOptions:InjectMenuItems(self, {
			Sku.deEn("Pawn ist nicht installiert oder nicht aktiviert", "Pawn is not installed or enabled", "Pawn n'est pas installé ou activé")
		}, SkuGenericMenuItem)
		return
	end

	local tSettings = SkuSettings:Sub("SkuCore")
	local function tToggle(aLabel, aGet, aSet)
		local tEntry = SkuOptions:InjectMenuItems(self, {aLabel}, SkuGenericMenuItem)
		SkuOptions:MakeToggleNode(tEntry, {
			label = aLabel, onLabel = L["On"], offLabel = L["Off"],
			get = aGet, set = function(_, aValue) aSet(aValue) end,
		})
	end

	tToggle(Sku.deEn("Pawn in Sku-Tooltips", "Pawn in Sku tooltips", "Pawn dans les infobulles Sku"),
		function() return tSettings.pawnIntegrationEnabled end,
		function(aValue) tSettings.pawnIntegrationEnabled = aValue end)
	tToggle(Sku.deEn("Verbesserungen in Tooltips", "Upgrades in tooltips", "Améliorations dans les infobulles"),
		function() return PawnCommon.ShowUpgradesOnTooltips end,
		function(aValue) PawnCommon.ShowUpgradesOnTooltips = aValue end)
	tToggle(Sku.deEn("Nur Werte von Verbesserungen", "Values for upgrades only", "Valeurs des améliorations uniquement"),
		function() return PawnCommon.ShowValuesForUpgradesOnly end,
		function(aValue) PawnCommon.ShowValuesForUpgradesOnly = aValue end)
	tToggle(Sku.deEn("Verbesserungen nach Gegenstandsstufe", "Item-level upgrades", "Améliorations par niveau d'objet"),
		function() return PawnCommon.ShowItemLevelUpgrades end,
		function(aValue) PawnCommon.ShowItemLevelUpgrades = aValue end)
end

function PawnIntegration:AddTooltipData(aTextFull, aItemId)
	if not IsPawnAvailable() or type(aTextFull) ~= "table" then return aTextFull end

	-- Tooltip text can be requested repeatedly with Shift+Down. Work on a copy so
	-- Pawn annotations never accumulate in the menu node's original data.
	local tTextFull = {}
	for i, tSection in ipairs(aTextFull) do
		tTextFull[i] = tSection
	end

	local tOk, tErr = pcall(function()
		local tSettings = SkuSettings:Sub("SkuCore")
		if not tSettings.pawnIntegrationEnabled then return end
		local _, tLink = GetItemInfo(aItemId)
		local tItem = tLink and PawnGetItemData(tLink)
		if not tItem or not tItem.InvType then return end

		local tSlots = {}
		-- Pawn keeps PawnItemEquipLocToSlot1/2 private. Use its public lookup;
		-- referring to the private tables made every comparison stop here.
		local tSlot1, tSlot2
		if _G.PawnGetSlotsForItemType then
			tSlot1, tSlot2 = PawnGetSlotsForItemType(tItem.InvType)
		end
		if tSlot1 then tSlots[#tSlots + 1] = tSlot1 end
		if tSlot2 then tSlots[#tSlots + 1] = tSlot2 end
		if #tSlots == 0 then return end

		local tUpgradeLine
		local tEquippedLink
		if PawnCommon.ShowUpgradesOnTooltips ~= false and _G.PawnIsItemAnUpgrade then
			local tUpgrades = PawnIsItemAnUpgrade(tItem, true)
			if tUpgrades and tUpgrades[1] then
				local tUpgrade = tUpgrades[1]
				tEquippedLink = tUpgrade.ExistingItemLink
				tUpgradeLine = Sku.deEn("Verbesserung", "Upgrade", "Amélioration").." "
					..FormatSigned(100 * (tUpgrade.PercentUpgrade or 0), 1, " "..Sku.deEn("Prozent", "percent", "pour cent")).."; "
					..tostring(tUpgrade.LocalizedScaleName or tUpgrade.ScaleName or "Pawn")
			end
		end

		-- Pawn returns positive upgrades only. For weaker or equal items, calculate
		-- the percentage with the first visible Pawn scale.
		if not tUpgradeLine and _G.PawnGetSingleValueFromItem and _G.PawnIsScaleVisible then
			local tScaleNames = {}
			for tScaleName in pairs(PawnCommon.Scales or {}) do
				if PawnIsScaleVisible(tScaleName) then tScaleNames[#tScaleNames + 1] = tScaleName end
			end
			table.sort(tScaleNames)
			local tScaleName = tScaleNames[1]
			if tScaleName then
				local _, tNewValue = PawnGetSingleValueFromItem(tItem, tScaleName)
				local tOldComparisonValue
				for _, tSlot in ipairs(tSlots) do
					local tOldLink = GetInventoryItemLink("player", tSlot)
					local tOldItem = tOldLink and PawnGetItemData(tOldLink)
					local _, tOldValue = tOldItem and PawnGetSingleValueFromItem(tOldItem, tScaleName)
					if tOldValue and (not tOldComparisonValue or tOldValue < tOldComparisonValue) then
						tOldComparisonValue, tEquippedLink = tOldValue, tOldLink
					end
				end
				if tNewValue and tOldComparisonValue and tOldComparisonValue ~= 0 then
					local tPercent = 100 * (tNewValue - tOldComparisonValue) / tOldComparisonValue
				tUpgradeLine = (tPercent > 0 and Sku.deEn("Verbesserung", "Upgrade", "Amélioration")
						or Sku.deEn("Keine Verbesserung", "Not an upgrade", "Pas une amélioration"))
						.." "..FormatSigned(tPercent, 1, " "..Sku.deEn("Prozent", "percent", "pour cent")).."; "
						..tostring(PawnGetScaleLocalizedName and PawnGetScaleLocalizedName(tScaleName) or tScaleName)
				end
			end
		end

		if not tEquippedLink then
			for _, tSlot in ipairs(tSlots) do
				tEquippedLink = GetInventoryItemLink("player", tSlot)
				if tEquippedLink then break end
			end
		end
		if tUpgradeLine and type(tTextFull[1]) == "string" then
			local tFirstBreak = tTextFull[1]:find("\r\n", 1, true)
			if tFirstBreak then
				tTextFull[1] = tTextFull[1]:sub(1, tFirstBreak + 1)..tUpgradeLine.."\r\n"..tTextFull[1]:sub(tFirstBreak + 2)
			else
				tTextFull[1] = tTextFull[1].."\r\n"..tUpgradeLine
			end
		end

		local tGetStats = (_G.C_Item and _G.C_Item.GetItemStats) or _G.GetItemStats
		local tNewStats = tGetStats and tGetStats(tLink) or {}
		local tOldStats = tGetStats and tEquippedLink and tGetStats(tEquippedLink) or {}
		local tMissing = {}
		for tStat, tNewValue in pairs(tNewStats or {}) do
			local tOldValue = (tOldStats and tOldStats[tStat]) or 0
			local tDelta = tNewValue - tOldValue
			local tLabel = _G[tStat] or tStat
			for i, tSection in ipairs(tTextFull) do
				if type(tSection) == "string" then
					local tDecimals = tostring(tStat):find("DAMAGE_PER_SECOND", 1, true) and 1 or 0
					local tNew, tHit = AppendToLineContaining(tSection, tostring(tLabel), "; "..FormatSigned(tDelta, tDecimals))
					if tHit then
						tTextFull[i] = tNew
						break
					end
				end
			end
		end
		for tStat, tOldValue in pairs(tOldStats or {}) do
			if not tNewStats or not tNewStats[tStat] or tNewStats[tStat] == 0 then
				local tLabel = _G[tStat] or tStat
				tMissing[#tMissing + 1] = tostring(tLabel).." "..FormatSigned(-tOldValue)
			end
		end
		if #tMissing > 0 then
			table.sort(tMissing)
			local tMissingText = Sku.deEn("Fehlende Attribute", "Missing attributes", "Attributs manquants").."\r\n"..table.concat(tMissing, "\r\n")
			if type(tTextFull[1]) == "string" then
				tTextFull[1] = tTextFull[1].."\r\n"..tMissingText
			else
				tTextFull[#tTextFull + 1] = tMissingText
			end
		end
	end)
	if not tOk then
		dprint("PawnIntegration:AddTooltipData failed", tostring(tErr))
	end

	return tTextFull
end
