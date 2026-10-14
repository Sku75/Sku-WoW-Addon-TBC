---------------------------------------------------------------------------------------------------------------------------------------
-- Character stats on WoW Forever.
-- Blizzard's character window there is a retail-style stats window: the categories are in PAPERDOLL_STATCATEGORIES and every
-- value has an updateFunc in PAPERDOLL_STATINFO. The old widgets (CharacterStatFrame1.., PlayerStatFrameLeft1) that
-- Build_CharacterFrame reads on the other clients do not exist, and neither does NUM_RESISTANCE_TYPES.
-- So the values are read through exactly these Blizzard tables: every updateFunc writes into a private, invisible stat frame
-- (Label, Value, tooltip, ...), from which Sku takes name, value and tooltip. A value that cannot be read (secret values in
-- combat, or a stat the character does not have) is left out instead of taking the whole menu down.
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

-- Reads ONE value. Returns its name ("Label: value") and tooltip, or nil when the value is not shown.
-- updateFunc and showFunc are Blizzard's: they can throw while their data is secret (combat), which is the one
-- reason for the pcall here.
local function tReadStat(aStatKey, aUnit, aId, aHideAt, aReadTooltip)
	local tInfo = PAPERDOLL_STATINFO[aStatKey]
	if not tInfo or not tInfo.updateFunc then return nil end
	local f = tScratchFrame()
	f.onEnterFunc, f.UpdateTooltip, f.tooltip, f.tooltip2, f.tooltip3, f.numericValue = nil, nil, nil, nil, nil, nil
	f.Label:SetText("")
	f.Value:SetText("")
	f:Show()
	local tOk, tNumeric = pcall(tInfo.updateFunc, f, aUnit, aId)
	local tShown = f:IsShown()
	f:Hide()
	if not tOk or not tShown then return nil end
	if aHideAt ~= nil and not Sku.IsSecret(tNumeric) and tNumeric == aHideAt then return nil end
	local tLabel, tValue = f.Label:GetText(), f.Value:GetText()
	if not tLabel or tLabel == "" then return nil end
	tLabel = tLabel:gsub("%s*[:：]%s*$", "")
	local tName = SkuUtil:Unescape(tLabel .. ": " .. (tValue or ""))
	f:Show()
	local tFull = aReadTooltip(f)
	f:Hide()
	return tName, tFull
end

local function tAddStat(aNode, aStatKey, aUnit, aId, aHideAt, aReadTooltip)
	local tLive = function() return tReadStat(aStatKey, aUnit, aId, aHideAt, aReadTooltip) end
	local tName, tFull = tLive()
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
	for _, tCat in ipairs(PAPERDOLL_STATCATEGORIES) do
		if tCat.unit == "player" and tCat.stats then
			local tCatName = SkuUtil:Unescape(tostring(tCat.categoryName or ""))
			local tCatNode = {
				frameName = "", RoC = "Child", type = "Button", textFirstLine = tCatName, textFull = "",
				childs = {},
			}
			for _, tStat in ipairs(tCat.stats) do
				local tShow = true
				if tStat.showFunc then
					local tOk, tRes = pcall(tStat.showFunc)
					tShow = tOk and tRes and true or false
				end
				if tShow then
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
	for _, tKey in ipairs({ "HOLY_RESIST", "FIRE_RESIST", "NATURE_RESIST", "FROST_RESIST", "SHADOW_RESIST", "ARCANE_RESIST" }) do
		tAddStat(aResistanceNode, tKey, "player", nil, nil, aReadTooltip)
	end
end
