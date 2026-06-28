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
-- WoW passes (addonName, privateNamespace) to every file of this addon; the
-- second value is one table shared across all Sku files. Sku historically
-- discarded it and put everything in _G. The Sku 42 rework (W4 Phase A) adopts
-- it as the addon-private namespace `ns` for internal-only state/helpers, while
-- the published API (Sku and the module tables) stays global. It is also exposed
-- as Sku.ns so any module holding `Sku` can reach it without re-reading `...`.
local ADDON_NAME, ns = ...
ns = ns or {}

Sku = {}
Sku.ns = ns
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
-- Sku 42 default: log ON (capture breadcrumbs to the SkuDebugLog ring every
-- session, so traces are available after a /reload without re-enabling), print
-- OFF (no chat echo / no TTS spam). Override per session via /skudebug.
Sku.debug = { print = false, log = true }

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

-- Write a one-off marker line into the ring with full date+time. Called when
-- logging is turned on, so a persisted-but-uncleared buffer shows an
-- unmistakable "this run starts here" divider — the ring is NOT cleared on
-- /reload and the flags reset to off each load, so without this stale lines
-- from an earlier session can be mistaken for fresh output.
function Sku:DebugLogMark(aText)
	tDebugLogAppend("=== " .. tostring(aText) .. "  " .. date("%Y-%m-%d %H:%M:%S") .. " ===")
end

-- /skudebug — control the two debug channels and the persisted log.
SLASH_SKUDEBUG1 = "/skudebug"
SlashCmdList["SKUDEBUG"] = function(aMsg)
	aMsg = (aMsg or ""):lower():match("^%s*(.-)%s*$")
	local d = Sku.debug or {}
	Sku.debug = d
	local tWasLog = d.log
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
	if d.log and not tWasLog then Sku:DebugLogMark("log enabled") end
	print(string.format("|cff80c0ffSkuDebug|r: print=%s log=%s", tostring(d.print), tostring(d.log)))
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Performance monitoring
Sku.PerformanceStart = false
Sku.PerformanceData = {}

-- Richer probe recorder. The legacy Sku.PerformanceData[name] holds only a noisy
-- 2-sample rolling figure ((old+new)/2), which can't confirm a small change.
-- Sku:Probe additionally tracks count / total / max / last per name in
-- Sku.PerfStats, and sets Sku.PerformanceData[name] to the TRUE running average
-- (total/count) so the on-screen frame and /skuperf stay populated. Cheap: a few
-- adds and one compare, no allocation after the first call per name. Use it for
-- probes we want to measure optimizations against; the other probe sites keep
-- the legacy EWMA write until/unless they need the same treatment.
Sku.PerfStats = {}
function Sku:Probe(aName, aMs)
	local s = Sku.PerfStats[aName]
	if not s then
		s = {count = 0, total = 0, max = 0, last = 0}
		Sku.PerfStats[aName] = s
	end
	s.count = s.count + 1
	s.total = s.total + aMs
	s.last = aMs
	if aMs > s.max then s.max = aMs end
	Sku.PerformanceData[aName] = s.total / s.count
end

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

---------------------------------------------------------------------------------------------------------------------------------------
-- Performance readout (screen-reader friendly)  [Workstream 3 / P1]
--
-- The on-screen SkuPerformance frame above is sighted-only. This block adds a
-- TEXT readout of the same data, plus load-time milestones and (optional)
-- per-addon CPU usage. Every line is written BOTH to the chat frame (live,
-- read by the screen reader) and to the persisted SkuDebugLog ring (read back
-- out-of-game after a /reload, like the rest of Sku's logging). All combat
-- probe numbers are milliseconds; load milestones are seconds since core load.
--
--   /skuperf            -- dump everything (load + combat + cpu, read-only)
--   /skuperf combat     -- Sku.PerformanceData probes, slowest first
--   /skuperf load       -- Sku.metric load-time milestones
--   /skuperf cpu        -- per-addon CPU usage (needs scriptProfile; enables it)
--   /skuperf reset      -- clear the rolling combat probe averages
--   /skuperf frame      -- toggle the old on-screen frame (sighted devs)
--
-- The combat probes (Sku.PerformanceData[...]) are reset to {} every load and
-- are NOT persisted, so read them in the same session you captured them (run
-- the scenario, then /skuperf combat). Load milestones ARE auto-persisted to
-- the ring at first PLAYER_ENTERING_WORLD, so "loading time" is always
-- captured without running a command.

-- Emit one line to chat AND the persisted ring (so it is readable live by the
-- screen reader and out-of-game after /reload, regardless of the dprint flag).
local function tPerfEmitChat(aLine)
	print(aLine)
	tDebugLogAppend(aLine)
end
-- Ring-only emitter for the silent auto-capture at login (no chat/TTS spam).
local function tPerfEmitQuiet(aLine)
	tDebugLogAppend(aLine)
end

-- Resolve the AddOn CPU APIs across client versions (modern clients moved
-- several AddOn APIs under C_AddOns; older ones keep the globals).
local function tUpdateAddOnCpu()
	if C_AddOns and C_AddOns.UpdateAddOnCPUUsage then C_AddOns.UpdateAddOnCPUUsage()
	elseif UpdateAddOnCPUUsage then UpdateAddOnCPUUsage() end
end
local function tGetAddOnCpu(aNameOrIndex)
	if C_AddOns and C_AddOns.GetAddOnCPUUsage then return C_AddOns.GetAddOnCPUUsage(aNameOrIndex) end
	if GetAddOnCPUUsage then return GetAddOnCPUUsage(aNameOrIndex) end
	return nil
end
local function tGetNumAddOns()
	if C_AddOns and C_AddOns.GetNumAddOns then return C_AddOns.GetNumAddOns() end
	if GetNumAddOns then return GetNumAddOns() end
	return 0
end
local function tGetAddOnName(aIndex)
	local f = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
	if not f then return nil end
	return (f(aIndex))  -- field 1 = name
end

function Sku:PerformanceDumpCombat(aEmit)
	aEmit = aEmit or tPerfEmitChat
	aEmit("|cff80c0ffSkuPerf|r combat probes (ms, slowest first):")
	local tRows = {}
	for k, v in pairs(Sku.PerformanceData) do
		tRows[#tRows + 1] = {k, tonumber(v) or 0}
	end
	if #tRows == 0 then
		aEmit("  (no data yet - run the scenario first, e.g. enter combat)")
		return
	end
	table.sort(tRows, function(a, b) return a[2] > b[2] end)
	for _, r in ipairs(tRows) do
		local s = Sku.PerfStats[r[1]]
		if s then
			-- Stable, measurable numbers: true average + how many calls, the
			-- worst single call, and the total time spent across the run.
			aEmit(string.format("  %.3f ms avg  %s  (n=%d, max=%.3f ms, total=%.1f ms)",
				r[2], r[1], s.count, s.max, s.total))
		else
			aEmit(string.format("  %.3f ms  %s", r[2], r[1]))
		end
	end
end

function Sku:PerformanceDumpLoad(aEmit)
	aEmit = aEmit or tPerfEmitChat
	aEmit("|cff80c0ffSkuPerf|r load milestones (seconds since core load):")
	if #Sku.metric == 0 then
		aEmit("  (no milestones captured)")
		return
	end
	for _, m in ipairs(Sku.metric) do
		aEmit(string.format("  %.3f s  %s", tonumber(m[2]) or 0, tostring(m[1])))
	end
end

-- aAllowEnable: only the explicit "/skuperf cpu" flips the scriptProfile CVar
-- (it needs a /reload to take effect); the catch-all dump stays read-only.
function Sku:PerformanceDumpCpu(aEmit, aAllowEnable)
	aEmit = aEmit or tPerfEmitChat
	if not tGetAddOnCpu(1) and not (GetCVar and GetCVar("scriptProfile")) then
		aEmit("|cff80c0ffSkuPerf|r CPU profiling API not available on this client.")
		return
	end
	local tEnabled = (GetCVar and GetCVar("scriptProfile") == "1")
	if not tEnabled then
		if aAllowEnable and SetCVar then
			SetCVar("scriptProfile", "1")
			aEmit("|cff80c0ffSkuPerf|r CPU profiling was OFF. Enabled scriptProfile - type /reload, then /skuperf cpu.")
		else
			aEmit("|cff80c0ffSkuPerf|r CPU profiling is OFF (run /skuperf cpu to enable, needs /reload).")
		end
		return
	end
	tUpdateAddOnCpu()
	aEmit("|cff80c0ffSkuPerf|r addon CPU usage (ms, cumulative this session, Sku family):")
	local tRows, tTotal = {}, 0
	for i = 1, tGetNumAddOns() do
		local tName = tGetAddOnName(i)
		local tUse = tGetAddOnCpu(i) or 0
		tTotal = tTotal + tUse
		if tName and tName:find("^Sku") then
			tRows[#tRows + 1] = {tName, tUse}
		end
	end
	table.sort(tRows, function(a, b) return a[2] > b[2] end)
	for _, r in ipairs(tRows) do
		aEmit(string.format("  %.1f ms  %s", r[2], r[1]))
	end
	aEmit(string.format("  %.1f ms  (all addons total)", tTotal))
end

SLASH_SKUPERF1 = "/skuperf"
SlashCmdList["SKUPERF"] = function(aMsg)
	aMsg = (aMsg or ""):lower():match("^%s*(.-)%s*$")
	if aMsg == "combat" then
		Sku:PerformanceDumpCombat()
	elseif aMsg == "load" then
		Sku:PerformanceDumpLoad()
	elseif aMsg == "cpu" then
		Sku:PerformanceDumpCpu(nil, true)
	elseif aMsg == "reset" then
		Sku.PerformanceData = {}
		Sku.PerfStats = {}
		tPerfEmitChat("|cff80c0ffSkuPerf|r combat probe averages cleared.")
	elseif aMsg == "frame" then
		Sku:Performance()
	elseif aMsg == "" or aMsg == "all" then
		Sku:PerformanceDumpLoad()
		Sku:PerformanceDumpCombat()
		Sku:PerformanceDumpCpu(nil, false)
	else
		print("|cff80c0ffSkuPerf|r usage: /skuperf [combat|load|cpu|reset|frame]")
	end
end

-- Load-time milestone capture. The single debugprofilestart() at the top of
-- this file anchors the session clock, so Sku:MetricPoint() records seconds
-- since core load. We stamp the two key startup events and auto-persist the
-- timeline to the ring once the world is ready (silent - no chat spam).
local tPerfLoadFrame = CreateFrame("Frame")
tPerfLoadFrame.tFirstPew = true
tPerfLoadFrame:RegisterEvent("PLAYER_LOGIN")
tPerfLoadFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
tPerfLoadFrame:SetScript("OnEvent", function(self, aEvent)
	if aEvent == "PLAYER_LOGIN" then
		Sku:MetricPoint("PLAYER_LOGIN")
	elseif aEvent == "PLAYER_ENTERING_WORLD" then
		if self.tFirstPew then
			self.tFirstPew = false
			Sku:MetricPoint("PLAYER_ENTERING_WORLD (first)")
			Sku:DebugLogMark("perf load milestones")
			Sku:PerformanceDumpLoad(tPerfEmitQuiet)
		end
	end
end)