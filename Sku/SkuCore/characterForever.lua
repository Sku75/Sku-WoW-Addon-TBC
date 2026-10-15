---------------------------------------------------------------------------------------------------------------------------------------
-- Character stats on WoW Forever.
-- Blizzard's character window there is a retail-style stats window: the categories are in PAPERDOLL_STATCATEGORIES and every
-- value has an updateFunc in PAPERDOLL_STATINFO. The old widgets (CharacterStatFrame1.., PlayerStatFrameLeft1) that
-- Build_CharacterFrame reads on the other clients do not exist, and neither does NUM_RESISTANCE_TYPES.
-- So the values are read through exactly these Blizzard tables: every updateFunc writes into a private, invisible stat frame
-- (Label, Value, tooltip, ...), from which Sku takes name, value and tooltip. While the game keeps unit stats secret
-- (in combat, C_Secrets.ShouldUnitStatsBeSecret) nothing is read: the updateFuncs would throw on the secret numbers.
---------------------------------------------------------------------------------------------------------------------------------------
if not Sku.isForever then return end

local L = Sku.L

local tScratch

local function tScratchFrame()
	if tScratch then return tScratch end
	tScratch = CreateFrame("Frame", nil, UIParent)
	tScratch:SetSize(10, 10)
	tScratch:SetAlpha(0)
	tScratch.Label = tScratch:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	tScratch.Value = tScratch:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	tScratch.Background = tScratch:CreateTexture(nil, "BACKGROUND")
	tScratch.Icon = tScratch:CreateTexture(nil, "ARTWORK")
	tScratch:SetScript("OnEnter", function(self)
		if self.onEnterFunc then
			self:onEnterFunc()
		else
			PaperDollStatTooltip(self)
		end
	end)
	tScratch:Hide()
	return tScratch
end

local function tNotReadableNode(aChilds)
	local tText = L["not readable in combat"]
	table.insert(aChilds, tText)
	aChilds[tText] = { frameName = "", RoC = "Child", type = "Text", textFirstLine = tText, textFull = "", childs = {} }
end

-- Reads ONE value. Returns its name ("Label: value"), tooltip and label, or nil when the value is not shown.
local function tReadStat(aStatKey, aUnit, aId, aHideAt, aReadTooltip)
	local tInfo = PAPERDOLL_STATINFO[aStatKey]
	if not tInfo or not tInfo.updateFunc then return nil end
	local f = tScratchFrame()
	f.onEnterFunc, f.UpdateTooltip, f.tooltip, f.tooltip2, f.tooltip3, f.numericValue = nil, nil, nil, nil, nil, nil
	f.Label:SetText("")
	f.Value:SetText("")
	f:Show()
	-- Blizzard's updateFunc on a frame that is not Blizzard's own: a throw leaves this one stat out, logged
	local tOk, tNumeric = pcall(tInfo.updateFunc, f, aUnit, aId)
	local tShown = f:IsShown()
	f:Hide()
	if not tOk then
		dprint("charstats", aStatKey, "updateFunc failed", tNumeric)
		return nil
	end
	if not tShown then return nil end
	if aHideAt ~= nil and not Sku.IsSecret(tNumeric) and tNumeric == aHideAt then return nil end
	local tLabel, tValue = f.Label:GetText(), f.Value:GetText()
	if Sku.IsSecret(tLabel) or Sku.IsSecret(tValue) then
		dprint("charstats", aStatKey, "secret label or value")
		return nil
	end
	if not tLabel or tLabel == "" then return nil end
	tLabel = tLabel:gsub("%s*[:：]%s*$", "")
	local tName = SkuUtil:Unescape(tLabel .. ": " .. (tValue or ""))
	f:Show()
	local tFull = aReadTooltip(f)
	f:Hide()
	return tName, tFull, tLabel
end

local function tAddStat(aNode, aStatKey, aUnit, aId, aHideAt, aReadTooltip)
	local tName, tFull, tLabel = tReadStat(aStatKey, aUnit, aId, aHideAt, aReadTooltip)
	-- the entry stays in the menu when a fight starts: it then says so instead of keeping the last value
	local tLive = function()
		if C_Secrets.ShouldUnitStatsBeSecret() then return SkuUtil:Unescape(tLabel .. ": " .. L["not readable in combat"]) end
		return tReadStat(aStatKey, aUnit, aId, aHideAt, aReadTooltip)
	end
	if tName and not aNode.childs[tName] then
		table.insert(aNode.childs, tName)
		aNode.childs[tName] = {
			frameName = "", RoC = "Child", type = "Button",
			textFirstLine = tName, textFull = tFull or "", childs = {},
			liveName = tLive,
		}
	end
end

-- The categories of the window (Attributes, Offense, Defense, ...) as nodes below aParentStats.
-- aReadTooltip(frame): the tooltip text of a stat frame (a local helper of Build_CharacterFrame).
function SkuCore:BuildForeverCharacterStats(aParentStats, aReadTooltip)
	if C_Secrets.ShouldUnitStatsBeSecret() then
		tNotReadableNode(aParentStats)
		return
	end
	for _, tCat in ipairs(PAPERDOLL_STATCATEGORIES) do
		if tCat.unit == "player" and tCat.stats then
			local tCatName = SkuUtil:Unescape(tostring(tCat.categoryName or ""))
			local tCatNode = {
				frameName = "", RoC = "Child", type = "Button", textFirstLine = tCatName, textFull = "",
				childs = {},
			}
			for _, tStat in ipairs(tCat.stats) do
				if not tStat.showFunc or tStat.showFunc() then
					tAddStat(tCatNode, tStat.stat, "player", tStat.id, tStat.hideAt, aReadTooltip)
				end
			end
			if #tCatNode.childs > 0 then
				table.insert(aParentStats, tCatName)
				aParentStats[tCatName] = tCatNode
			end
		end
	end
end

-- The resistances stand in no category of Blizzard's window, but in PAPERDOLL_STATINFO. aResistanceNode: the
-- "Resistances" node of Build_CharacterFrame.
function SkuCore:BuildForeverResistances(aResistanceNode, aReadTooltip)
	if C_Secrets.ShouldUnitStatsBeSecret() then
		tNotReadableNode(aResistanceNode.childs)
		return
	end
	for _, tKey in ipairs({ "HOLY_RESIST", "FIRE_RESIST", "NATURE_RESIST", "FROST_RESIST", "SHADOW_RESIST", "ARCANE_RESIST" }) do
		tAddStat(aResistanceNode, tKey, "player", nil, nil, aReadTooltip)
	end
end
