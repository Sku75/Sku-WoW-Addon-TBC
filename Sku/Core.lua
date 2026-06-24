---@diagnostic disable: undefined-field, undefined-doc-name, undefined-doc-param

--[[
local oGetEngravingModeEnabled = C_Engraving.GetEngravingModeEnabled
C_Engraving.GetEngravingModeEnabled = function()
	--local oValue = oGetEngravingModeEnabled()
	return true
end

local oIsEngravingEnabled = C_Engraving.IsEngravingEnabled
C_Engraving.IsEngravingEnabled = function()
	--local oValue = oIsEngravingEnabled()
	return true
end
]]

local oIsInventorySlotEngravable = C_Engraving.IsInventorySlotEngravable
C_Engraving.IsInventorySlotEngravable = function(containerIndex, slotIndex)
	if containerIndex >= 0 then
		return oIsInventorySlotEngravable(containerIndex, slotIndex) --bool
	else
		return false
	end
end


--[[
local oGetRuneCategories = C_Engraving.GetRuneCategories
C_Engraving.GetRuneCategories = function(shouldFilter, ownedOnly)
	--local oValue = oGetRuneCategories(false, false)
	return {INVSLOT_LEGS, INVSLOT_FEET}
end

local oGetRunesForCategory = C_Engraving.GetRunesForCategory
C_Engraving.GetRunesForCategory = function(category, ownedOnly)
	--local oValue = oGetRunesForCategory(category, ownedOnly)
	return {
		[1] = {
		skillLineAbilityID = 48626,--", Type = "number", Nilable = false },
		itemEnchantmentID = 1,--", Type = "number", Nilable = false },
		name = "Rune of Furious Thunder", --", Type = "cstring", Nilable = false },
		iconTexture = 133816,--", Type = "number", Nilable = false },
		equipmentSlot = INVSLOT_LEGS,--", Type = "number", Nilable = false },
		level = 1, --", Type = "number", Nilable = false },
		learnedAbilitySpellIDs = {409999,},-- Type = "table", InnerType = "number", Nilable = false },
	},
	[2] = {
		skillLineAbilityID = 48626,--", Type = "number", Nilable = false },
		itemEnchantmentID = 168598,--", Type = "number", Nilable = false },
		name = "Rune of Furious Thunder", --", Type = "cstring", Nilable = false },
		iconTexture = 133816,--", Type = "number", Nilable = false },
		equipmentSlot = INVSLOT_LEGS,--", Type = "number", Nilable = false },
		level = 1, --", Type = "number", Nilable = false },
		learnedAbilitySpellIDs = {409999,},-- Type = "table", InnerType = "number", Nilable = false },
	},
}
end

SetCVar("alwaysShowRuneIcons", "1")

C_AddOns.LoadAddOn("Blizzard_EngravingUI")
]]
---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME = "Sku"
local ADDON_NAME = ...

Sku = {}
Sku.L = LibStub("AceLocale-3.0"):GetLocale("Sku", false)
Sku.Loc = Sku.L["locale"]
Sku.Locs = {"enUS", "deDE",}

Sku.LocsPartly = {["deDE"] = true, ["enUS"] = true, ["zhCN"] = true, ["ruRU"] = true,}
Sku.LocP = GetLocale()
if not Sku.LocsPartly[GetLocale()] then
	Sku.LocP = "enUS"
end

---------------------------------------------------------------------------------------------------------------------------------------
Sku.AudiodataPath = ""
if Sku.Loc == "deDE" then
	Sku.AudiodataPath = "SkuAudioData"
elseif Sku.Loc == "enUS" or Sku.Loc == "enGB" or Sku.Loc == "enAU" then
	Sku.AudiodataPath = "SkuAudioData_en"
end

---------------------------------------------------------------------------------------------------------------------------------------
Sku.testMode = false

---------------------------------------------------------------------------------------------------------------------------------------
-- tmp fixes for 11404 ptr
Sku.toc = select(4, GetBuildInfo())
if Sku.toc >= 20505 then
	Sku.isTBC = true
end

if Sku.toc > 11403 then
	PickupContainerItem = C_Container.PickupContainerItem
	GetContainerNumSlots = C_Container.GetContainerNumSlots
	GetContainerNumFreeSlots = C_Container.GetContainerNumFreeSlots
	UseContainerItem = C_Container.UseContainerItem
	GetContainerItemID = C_Container.GetContainerItemID
	GetItemCooldown = C_Container.GetItemCooldown
	GetContainerItemQuestInfo = function(bag, slot)
		local t = C_Container.GetContainerItemQuestInfo(bag, slot)
		return t.isQuestItem
	end
	GetContainerItemInfo = function(bag, slot)
		slot = slot or 0
		local t = C_Container.GetContainerItemInfo(bag, slot)
		if not t then
			return
		end		
		return t.iconFileID, t.stackCount, t.isLocked, t.quality, t.isReadable, t.hasLoot, t.hyperlink, t.isFiltered, t.hasNoValue, t.itemID, t.isBound
	end
	SocketContainerItem = C_Container.SocketContainerItem
	SplitContainerItem = C_Container.SplitContainerItem
	GetContainerItemLink = C_Container.GetContainerItemLink
	GetContainerItemCooldown = C_Container.GetContainerItemCooldown

	SetTracking = C_Minimap.SetTracking
	GetTrackingInfo = C_Minimap.GetTrackingInfo
	GetNumTrackingTypes = C_Minimap.GetNumTrackingTypes
end
---------------------------------------------------------------------------------------------------------------------------------------

Sku.IsEraSoD = false
if C_Engraving.IsEngravingEnabled() == true then
	Sku.IsEraSoD = true
end

---------------------------------------------------------------------------------------------------------------------------------------
Sku.metric = {}
debugprofilestart()
function Sku:MetricPoint(aText)
	Sku.metric[#Sku.metric + 1] = {aText, debugprofilestop()/1000}
end

---------------------------------------------------------------------------------------------------------------------------------------
-- General debug logging (dprint).
-- Two independent switches live under Sku.debug:
--   Sku.debug.print -> echo to the chat frame (the original dprint behaviour;
--                      a sighted developer reads the trace live in game).
--   Sku.debug.log   -> append to a persisted ring buffer in the SkuDebugLog
--                      SavedVariable, readable out-of-game after a /reload
--                      (no chat output -> no TTS spam).
-- Either, both, or neither may be on. With both off, dprint returns after a
-- single table+flag check and does NO further work, so the 400+ existing
-- dprint call sites stay free in normal play. Unlike SkuErrorLog:Log, this
-- path never calls debugstack and never builds per-event context, so it is
-- cheap even while enabled. Toggle via the SKU_KEY_DEBUGMODE keybind (cycles
-- the modes) or /skudebug for precise control.
Sku.debug = { print = false, log = false }

local DEBUGLOG_MAX = 2000  -- cap on persisted lines (ring buffer)

-- Render one dprint argument into a readable string. Tables are shallow-
-- serialised one level deep (k=v, ...) so the log stays informative without
-- the cost/size of a deep walk; nested tables collapse to "{...}".
local function tDebugArg(aVal)
	if type(aVal) ~= "table" then
		return tostring(aVal)
	end
	local tParts, tN = {}, 0
	for k, v in pairs(aVal) do
		tN = tN + 1
		if tN > 30 then
			tParts[#tParts + 1] = "..."
			break
		end
		local tv = type(v)
		if tv == "table" then
			v = "{...}"
		elseif tv == "string" then
			v = (#v > 120) and (v:sub(1, 120) .. "…") or v
		else
			v = tostring(v)
		end
		tParts[#tParts + 1] = tostring(k) .. "=" .. v
	end
	return "{" .. table.concat(tParts, ", ") .. "}"
end

local function tDebugLogAppend(...)
	if type(SkuDebugLog) ~= "table" then SkuDebugLog = {} end
	local tLog = SkuDebugLog
	tLog.lines = tLog.lines or {}
	tLog.seq   = (tLog.seq or 0) + 1
	local tN = select("#", ...)
	local tParts = {}
	for i = 1, tN do
		tParts[i] = tDebugArg((select(i, ...)))
	end
	tLog.lines[#tLog.lines + 1] = {
		seq = tLog.seq,
		t   = date("%H:%M:%S"),
		msg = table.concat(tParts, "  "),
	}
	-- Amortised trim: rebuild keeping the newest DEBUGLOG_MAX only every ~256
	-- overflows, so a chatty scan loop never pays an O(n) table.remove per line.
	if #tLog.lines > DEBUGLOG_MAX + 256 then
		local tKeep, tStart = {}, #tLog.lines - DEBUGLOG_MAX + 1
		for i = tStart, #tLog.lines do
			tKeep[#tKeep + 1] = tLog.lines[i]
		end
		tLog.lines = tKeep
	end
end

function dprint(...)
	local d = Sku.debug
	if not d or (not d.print and not d.log) then return end
	if d.print then
		print(...)
	end
	if d.log then
		tDebugLogAppend(...)
	end
end

-- /skudebug — control the two debug channels and the persisted log.
SLASH_SKUDEBUG1 = "/skudebug"
SlashCmdList["SKUDEBUG"] = function(aMsg)
	aMsg = (aMsg or ""):lower():match("^%s*(.-)%s*$")
	local d = Sku.debug or {}
	Sku.debug = d
	if aMsg == "print on" then d.print = true
	elseif aMsg == "print off" then d.print = false
	elseif aMsg == "log on" then d.log = true
	elseif aMsg == "log off" then d.log = false
	elseif aMsg == "on" then d.print, d.log = true, true
	elseif aMsg == "off" then d.print, d.log = false, false
	elseif aMsg == "clear" then
		if type(SkuDebugLog) == "table" then SkuDebugLog.lines = {} ; SkuDebugLog.seq = 0 end
		print("|cff80c0ffSkuDebug|r: log cleared.")
		return
	elseif aMsg == "show" then
		local tLines = (type(SkuDebugLog) == "table" and SkuDebugLog.lines) or {}
		local tStart = math.max(1, #tLines - 9)
		if #tLines == 0 then print("|cff80c0ffSkuDebug|r: log empty.") return end
		for i = tStart, #tLines do
			local e = tLines[i]
			print(string.format("#%s [%s] %s", tostring(e.seq), e.t or "?", e.msg or ""))
		end
		return
	elseif aMsg ~= "" then
		print("|cff80c0ffSkuDebug|r: usage: /skudebug on|off|print on|print off|log on|log off|clear|show")
	end
	print(string.format("|cff80c0ffSkuDebug|r: print=%s log=%s", tostring(d.print), tostring(d.log)))
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Performance monitoring
Sku.PerformanceStart = false
Sku.PerformanceData = {}
function Sku:Performance()
	if not _G["SkuPerformance"] then
		local f = _G["SkuPerformance"] or CreateFrame("Frame", "SkuPerformance", UIParent, BackdropTemplateMixin and "BackdropTemplate")
		local ttime = 0
		f:SetMovable(true)
		f:EnableMouse(true)
		f:SetClampedToScreen(true)
		f:RegisterForDrag("LeftButton")
		f:SetFrameStrata("DIALOG")
		f:SetFrameLevel(129)
		f:SetSize(450, 170)
		f:SetPoint("TOP", UIParent, "TOP")
		f:SetBackdrop({bgFile = [[Interface\ChatFrame\ChatFrameBackground]], edgeFile = "", tile = false, tileSize = 0, edgeSize = 32, insets = {left = 0, right = 0, top = 0, bottom = 0}})
		f:SetBackdropColor(0, 0, 0, 1)
		f:SetScript("OnDragStart", function(self) self:StartMoving() end)
		f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
		f:SetResizable(true)
      --f:SetResizeBounds(500, 500)

		local rb = CreateFrame("Button", "SkuPerformanceResizeButton", f)
		rb:SetPoint("BOTTOMRIGHT", -6, 7)
		rb:SetSize(16, 16)

		rb:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
		rb:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
		rb:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

		rb:SetScript("OnMouseDown", function(self, button)
			if button == "LeftButton" then
				f:StartSizing("BOTTOMRIGHT")
				self:GetHighlightTexture():Hide() -- more noticeable
			end
		end)
		rb:SetScript("OnMouseUp", function(self, button)
			f:StopMovingOrSizing()
			self:GetHighlightTexture():Show()
			f:SetWidth(f:GetWidth())

			for x = 1, 10 do
				local fs = _G["SkuPerformanceFSl"..x]
				fs:SetSize((f:GetWidth() / 3)*2, 200)
				local fs = _G["SkuPerformanceFSr"..x]
				fs:SetPoint("TOPLEFT", f, "TOPLEFT", f:GetWidth() / 2, -((x-1) * 15))
				fs:SetSize((f:GetWidth() / 3)*1, 200)
			end			
		end)

		local SkuPerformanceOnUpdateTime = 0
		f:SetScript('OnUpdate', function(self, time)
			if Sku.PerformanceStart ~= true then
				return
			end
			SkuPerformanceOnUpdateTime = SkuPerformanceOnUpdateTime + time
			if SkuPerformanceOnUpdateTime > 0.1 then
				local xs = 1
				for i, v in pairs(Sku.PerformanceData) do
					_G["SkuPerformanceFSl"..xs]:SetText(i)
					_G["SkuPerformanceFSr"..xs]:SetText(tostring(v))
					xs = xs + 1
				end

				SkuPerformanceOnUpdateTime = 0
			end
		end)

		for x = 1, 10 do
			local fs = f:CreateFontString("SkuPerformanceFSl"..x)
			fs:SetFontObject(SystemFont_Small)
			fs:SetTextColor(1, 1, 1, 1)
			fs:SetJustifyH("LEFT")
			fs:SetJustifyV("TOP")
			
			fs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -((x-1) * 15))
			fs:SetText("")
			fs:SetSize(f:GetWidth() / 2, 200)
			local fs = f:CreateFontString("SkuPerformanceFSr"..x)
			fs:SetFontObject(SystemFont_Small)
			fs:SetTextColor(1, 1, 1, 1)
			fs:SetJustifyH("LEFT")
			fs:SetJustifyV("TOP")
			fs:SetPoint("TOPLEFT", f, "TOPLEFT", f:GetWidth() / 2, -((x-1) * 15))
			fs:SetText("")
			fs:SetSize(f:GetWidth() / 2, 200)
		end

		_G["SkuPerformance"]:Show()
		Sku.PerformanceStart = true
		return
	end

	if _G["SkuPerformance"]:IsShown() == true then
		_G["SkuPerformance"]:Hide()
		Sku.PerformanceStart = false
	else
		_G["SkuPerformance"]:Show()
		Sku.PerformanceStart = true
	end
end