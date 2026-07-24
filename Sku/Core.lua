---@diagnostic disable: undefined-field, undefined-doc-name, undefined-doc-param


local oIsInventorySlotEngravable = C_Engraving.IsInventorySlotEngravable
C_Engraving.IsInventorySlotEngravable = function(containerIndex, slotIndex)
	if containerIndex >= 0 then
		return oIsInventorySlotEngravable(containerIndex, slotIndex) --bool
	else
		return false
	end
end


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

-- [v42.08] frFR aufgenommen: der Minimap-/Boden-Ressourcenscanner hat jetzt native
-- franzoesische Knotennamen (SkuCore/minimapScanner.lua), daher darf Sku.LocP auf einem
-- frFR-Client "frFR" bleiben (statt auf enUS zurueckzufallen), damit die frFR-Namen greifen.
Sku.LocsPartly = {["deDE"] = true, ["enUS"] = true, ["zhCN"] = true, ["ruRU"] = true, ["frFR"] = true,}
Sku.LocP = GetLocale()
if not Sku.LocsPartly[GetLocale()] then
	Sku.LocP = "enUS"
end

---------------------------------------------------------------------------------------------------------------------------------------
-- W5: Sprachpaket-Erkennung. Statt fest verdrahteter Ordnernamen je Locale werden
-- die installierten SkuAudioData*-Addons aufgezählt und das zur Client-Sprache
-- passende gewählt. Neue Pakete deklarieren sich per TOC-Metadaten
-- (## X-SkuVoicePack-Locale, optional ## X-SkuVoicePack-ExtraSpeed) und brauchen
-- dann keinen eigenen Glue-Code mehr; Alt-Pakete mit eigenem Core.lua laden nach
-- Sku und überschreiben Sku.AudiodataPath weiterhin selbst (gewinnt wie bisher).
-- Muss beim Laden von Sku laufen (TOC-Metadaten sind auch für noch nicht geladene
-- Addons lesbar), damit Ladezeit-Verbraucher schon den richtigen Pfad sehen.
Sku.AudiodataPath = ""
Sku.AudiodataPathInfo = "no voice pack found for "..tostring(Sku.Loc)
do
	local tGetNum = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
	local tGetInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
	local tGetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local tLegacyPackLocales = {["SkuAudioData"] = "deDE", ["SkuAudioData_en"] = "enUS",}
	local tSuffixLocales = {["de"] = "deDE", ["en"] = "enUS",}
	local tWantedLoc = Sku.Loc
	if tWantedLoc == "enGB" or tWantedLoc == "enAU" then tWantedLoc = "enUS" end
	local tBest, tBestScore, tBestHow = nil, 0, nil
	for i = 1, tGetNum() do
		local tName, _, _, tLoadable = tGetInfo(i)
		if tName and tLoadable and string.find(tName, "^SkuAudioData") then
			local tLoc = tGetMeta(tName, "X-SkuVoicePack-Locale")
			local tScore, tHow = 3, "metadata"
			if not tLoc then
				tLoc, tScore, tHow = tLegacyPackLocales[tName], 2, "legacy name"
			end
			if not tLoc then
				tLoc, tScore, tHow = tSuffixLocales[string.match(tName, "_(%a+)$") or ""], 1, "name suffix"
			end
			if tLoc == tWantedLoc and tScore > tBestScore then
				tBest, tBestScore, tBestHow = tName, tScore, tHow
			end
		end
	end
	if tBest then
		Sku.AudiodataPath = tBest
		Sku.AudiodataPathInfo = tBest.." ("..tBestHow..")"
		local tExtraSpeed = tonumber(tGetMeta(tBest, "X-SkuVoicePack-ExtraSpeed") or "")
		if tExtraSpeed then
			Sku.AudiodataExtraSpeed = tExtraSpeed
		end
	end
end

-- W5: zentraler Audio-Pfad-Resolver — die einzigen Stellen, die Sprachdatei-Pfade
-- zusammensetzen. Liest Sku.AudiodataPath bei jedem Aufruf, damit ein späterer
-- Override durch Alt-Paket-Glue weiterhin greift. Reine Pfad-Auflösung: Kanäle,
-- Queues und Sound-Handles bleiben Sache der Aufrufer.
function Sku:VoicePackAudioDir()
	if Sku.AudiodataPath == "" then return nil end
	return [[Interface\AddOns\]]..Sku.AudiodataPath..[[\assets\audio\]]
end

function Sku:IntegratedAudioDir()
	return [[Interface\AddOns\Sku\SkuAudioData\assets\audio\]]..Sku.Loc..[[\]]
end

function Sku:AudioFile(aFileName)
	local tDir = Sku:VoicePackAudioDir()
	if not tDir or not aFileName then return nil end
	return tDir..aFileName
end

---------------------------------------------------------------------------------------------------------------------------------------
Sku.testMode = false

---------------------------------------------------------------------------------------------------------------------------------------
-- tmp fixes for 11404 ptr
Sku.toc = select(4, GetBuildInfo())
if Sku.toc >= 20505 then
	Sku.isTBC = true
end

-- Classic Era (1.15.x) detection — the central flag for the unified Era/TBC build.
-- Era's interface is 11xxx and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC; TBC Anniversary
-- is 20xxx / WOW_PROJECT_BURNING_CRUSADE_CLASSIC. Use the project constant as the
-- primary signal with a numeric fallback so gating is correct even if the constant
-- is ever absent. Gate any TBC-content-only feature (e.g. gem socketing) on this.
Sku.isEra = ((WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC) or (Sku.toc > 0 and Sku.toc < 20000)) and true or false

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

-- [SOUND-PROBE] TEMPORARY diagnostic: log every PlaySound(kitId) call with a
-- short caller stack, so we can confirm whether the built-in menu open/close
-- swoosh (SoundKit 88 / 89) is actually fired on open -- and whether it still
-- produces audio in the current client. Gated behind the Sku.debug.log flag via
-- dprint. Blizzard also calls PlaySound a lot, so clear the ring and do one open
-- for a clean capture. Remove this block (grep SOUND-PROBE) when done.
if not Sku._soundProbeHooked and type(hooksecurefunc) == "function" then
	Sku._soundProbeHooked = true
	hooksecurefunc("PlaySound", function(aKit)
		dprint("[SOUND-PROBE] PlaySound", tostring(aKit), debugstack(2, 2, 0))
	end)
end

-- Write a one-off marker line into the ring with full date+time. Called when
-- logging is turned on, so a persisted-but-uncleared buffer shows an
-- unmistakable "this run starts here" divider — the ring is NOT cleared on
-- /reload and the flags reset to off each load, so without this stale lines
-- from an earlier session can be mistaken for fresh output.
function Sku:DebugLogMark(aText)
	tDebugLogAppend("=== " .. tostring(aText) .. "  " .. date("%Y-%m-%d %H:%M:%S") .. " ===")
end

-- Always-on combat-trace ring (independent of the Sku.debug flags), living in
-- SkuDebugLog.combatTrace. SkuDebugLog.blockProbe only catches taint BLOCKS
-- (ADDON_ACTION_BLOCKED/FORBIDDEN); but Sku's combat problem is mostly SELF-
-- deactivation -- code that voluntarily bails/defers because of combat and never
-- reaches a protected call, so nothing is ever blocked to capture. This ring
-- records those decision points (tag + detail + live combat flag) so a single
-- test cycle shows exactly where Sku turns itself off in combat, and -- once the
-- restriction is relaxed -- that the read path now runs. Ring of 300; read it
-- from SkuDebugLog.combatTrace after a /reload.
function SkuLogCombat(aTag, aDetail)
	if type(SkuDebugLog) ~= "table" then SkuDebugLog = {} end
	local tRing = SkuDebugLog.combatTrace or {}
	SkuDebugLog.combatTrace = tRing
	tRing[#tRing + 1] = {
		t = date("%H:%M:%S"),
		tag = tostring(aTag),
		detail = (aDetail ~= nil) and tostring(aDetail) or "",
		combat = (InCombatLockdown and InCombatLockdown()) and 1 or 0,
	}
	while #tRing > 300 do table.remove(tRing, 1) end
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

---------------------------------------------------------------------------------------------------------------------------------------
-- Per-module load timing  [Workstream 3 / load profiling]
--
-- Sku is built from ~10 AceAddon addons plus their sub-modules. AceAddon routes
-- every one of them through AceAddon:InitializeAddon (OnInitialize, fired at the
-- ADDON_LOADED sweep) and AceAddon:EnableAddon (OnEnable, fired at PLAYER_LOGIN).
-- We wrap those two so each addon/module's load cost is timed automatically - no
-- need to hand-instrument every file. InitializeAddon is non-recursive, so its
-- number is clean per addon. EnableAddon recurses into child modules, so we keep
-- a tiny per-depth stack and subtract child time to report a clean SELF figure
-- (plus the inclusive total). Results: Sku.PerfModules[name] = {init=, enableSelf=,
-- enableTotal=}. AceAddon is shared by ALL Ace3 addons in the client, so this also
-- captures other addons' modules (their OnEnable all runs at the single
-- PLAYER_LOGIN after Sku loaded) - useful for the general picture. We snapshot the
-- table at first PLAYER_ENTERING_WORLD into Sku.PerfModulesLoad so later
-- enable/disable toggles can't overwrite the load-time reading.
Sku.PerfModules = Sku.PerfModules or {}
do
	local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
	if AceAddon and not Sku._perfHookedAce then
		Sku._perfHookedAce = true

		local function tModRec(aName)
			local r = Sku.PerfModules[aName]
			if not r then r = {init = 0, enableSelf = 0, enableTotal = 0}; Sku.PerfModules[aName] = r end
			return r
		end

		local tOrigInit = AceAddon.InitializeAddon
		AceAddon.InitializeAddon = function(self, aAddon)
			local tName = (type(aAddon) == "table" and aAddon.name) or tostring(aAddon)
			local t0 = debugprofilestop()
			tOrigInit(self, aAddon)
			local dt = debugprofilestop() - t0
			if dt < 0 then dt = 0 end
			tModRec(tName).init = dt
		end

		-- EnableAddon recurses into child modules; keep per-depth child-time
		-- accumulators so each entry reports SELF time (total minus children).
		local tEnableStack = {}
		local tOrigEnable = AceAddon.EnableAddon
		AceAddon.EnableAddon = function(self, aAddon)
			local tName = (type(aAddon) == "string" and aAddon)
				or (type(aAddon) == "table" and aAddon.name) or tostring(aAddon)
			local tDepth = #tEnableStack + 1
			tEnableStack[tDepth] = 0
			local t0 = debugprofilestop()
			local tRet = tOrigEnable(self, aAddon)
			local tTotal = debugprofilestop() - t0
			if tTotal < 0 then tTotal = 0 end
			local tChild = tEnableStack[tDepth] or 0
			tEnableStack[tDepth] = nil
			if tDepth > 1 then
				tEnableStack[tDepth - 1] = (tEnableStack[tDepth - 1] or 0) + tTotal
			end
			local tSelf = tTotal - tChild
			if tSelf < 0 then tSelf = 0 end
			local r = tModRec(tName)
			r.enableTotal = tTotal
			r.enableSelf = tSelf
			return tRet
		end
	end
end

function Sku:Performance()
	if not _G["SkuPerformance"] then
		local f = CreateFrame("Frame", "SkuPerformance", UIParent, BackdropTemplateMixin and "BackdropTemplate")
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
--   /skuperf            -- dump everything (load + modules + combat + addons + mem, read-only)
--   /skuperf load       -- Sku.metric load-time milestones (the coarse freeze timeline)
--   /skuperf files      -- per-file load time from the _ps*.lua TOC stubs (which data file is slow)
--   /skuperf modules    -- per Sku module/addon init+enable time (what in Sku is slow)
--   /skuperf addons     -- ALL addons by load CPU, slowest first (needs scriptProfile; enables it)
--   /skuperf mem        -- ALL addons by memory, largest first (no setup; a load-cost proxy)
--   /skuperf combat     -- Sku.PerformanceData probes, slowest first
--   /skuperf cpu        -- Sku-family CPU usage (needs scriptProfile; enables it)
--   /skuperf reset      -- clear the rolling combat probe averages
--   /skuperf frame      -- toggle the old on-screen frame (sighted devs)
--
-- TWO views answer "why is my login slow":
--   * the GENERAL picture -> /skuperf addons (CPU) or /skuperf mem (no setup):
--     which of ALL your addons cost the most at load.
--   * the SKU picture -> /skuperf modules + /skuperf load: which Sku module and
--     which load phase (file-load -> login -> first frame) cost the most.
-- Both are auto-captured to the SkuDebugLog ring at first PEW (read back after a
-- /reload), so the load story is always recorded without typing a command.
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

-- Per-file load time (TEMPORARY measurement) from the SkuFileLoadStamps harness
-- (SkuPerfFileStamp.lua + the _ps*.lua TOC stubs). Each line is the gap between
-- two consecutive stamps = the load time (parse + table construction) of the TOC
-- files between them. This is how we attribute the file-load freeze to the big
-- route files. Negative numbers mean GetTimePreciseSec was unavailable and the
-- fallback clock straddled Core.lua's debugprofilestart reset - ignore those.
function Sku:PerformanceDumpFiles(aEmit)
	aEmit = aEmit or tPerfEmitChat
	aEmit("|cff80c0ffSkuPerf|r per-file load time (seconds, gaps between TOC stamps):")
	local s = SkuFileLoadStamps
	if not s or #s < 2 then
		aEmit("  (no file stamps - measurement stubs not loaded)")
		return
	end
	for i = 2, #s do
		aEmit(string.format("  %.3f s  %s  ->  %s", (s[i][2] or 0) - (s[i-1][2] or 0), tostring(s[i-1][1]), tostring(s[i][1])))
	end
	aEmit(string.format("  %.3f s  TOTAL stamped span", (s[#s][2] or 0) - (s[1][2] or 0)))
end

-- Per-module load timing from the AceAddon init/enable hook. Reads the PEW
-- snapshot when present (the load-time picture) so post-login toggles don't skew
-- it; otherwise the live table. Ranked by init+enableSelf (the work charged to
-- THAT module). Capped to the top 30 so the chat/ring stays readable.
function Sku:PerformanceDumpModules(aEmit)
	aEmit = aEmit or tPerfEmitChat
	local tSrc = Sku.PerfModulesLoad or Sku.PerfModules
	aEmit("|cff80c0ffSkuPerf|r module load timing (ms, slowest first, top 30):")
	local tRows = {}
	for k, v in pairs(tSrc) do
		tRows[#tRows + 1] = {k, (v.enableSelf or 0) + (v.init or 0), v}
	end
	if #tRows == 0 then
		aEmit("  (no module timing captured - hook not installed?)")
		return
	end
	table.sort(tRows, function(a, b) return a[2] > b[2] end)
	for i = 1, math.min(30, #tRows) do
		local v = tRows[i][3]
		aEmit(string.format("  %.1f ms  %s  (init=%.1f, enable=%.1f)",
			tRows[i][2], tRows[i][1], v.init or 0, v.enableSelf or 0))
	end
end

-- All-addon load cost (CPU ms) - the "what is slowing my login in general" view.
-- Needs scriptProfile (same gate/recipe as the Sku-family CPU dump). The number
-- is cumulative-this-session, but the auto-snapshot runs at first PEW so it then
-- reflects load-time execution. Top 30 plus an all-addons total.
function Sku:PerformanceDumpAddons(aEmit, aAllowEnable)
	aEmit = aEmit or tPerfEmitChat
	local tEnabled = (GetCVar and GetCVar("scriptProfile") == "1")
	if not tEnabled then
		if aAllowEnable and SetCVar then
			SetCVar("scriptProfile", "1")
			aEmit("|cff80c0ffSkuPerf|r CPU profiling was OFF. Enabled scriptProfile - type /reload, then /skuperf addons.")
		else
			aEmit("|cff80c0ffSkuPerf|r all-addon CPU needs scriptProfile (run /skuperf addons to enable, needs /reload).")
		end
		return
	end
	tUpdateAddOnCpu()
	aEmit("|cff80c0ffSkuPerf|r all-addon load CPU (ms, slowest first, top 30):")
	local tRows, tTotal = {}, 0
	for i = 1, tGetNumAddOns() do
		local tUse = tGetAddOnCpu(i) or 0
		tTotal = tTotal + tUse
		tRows[#tRows + 1] = {tGetAddOnName(i) or ("#" .. i), tUse}
	end
	table.sort(tRows, function(a, b) return a[2] > b[2] end)
	for i = 1, math.min(30, #tRows) do
		aEmit(string.format("  %.1f ms  %s", tRows[i][2], tRows[i][1]))
	end
	aEmit(string.format("  %.1f ms  (all %d addons total)", tTotal, #tRows))
end

-- All-addon memory footprint (KB) - a no-setup proxy for "heavy" addons. This is
-- memory, not time, but a large footprint usually tracks a large load cost, and
-- unlike the CPU view it needs no scriptProfile/reload. Top 30 plus a total.
function Sku:PerformanceDumpMem(aEmit)
	aEmit = aEmit or tPerfEmitChat
	local tUpdate = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
	local tGet = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
	if not tGet then
		aEmit("|cff80c0ffSkuPerf|r addon memory API not available on this client.")
		return
	end
	if tUpdate then tUpdate() end
	aEmit("|cff80c0ffSkuPerf|r all-addon memory (KB, largest first, top 30):")
	local tRows, tTotal = {}, 0
	for i = 1, tGetNumAddOns() do
		local tKb = tGet(i) or 0
		tTotal = tTotal + tKb
		tRows[#tRows + 1] = {tGetAddOnName(i) or ("#" .. i), tKb}
	end
	table.sort(tRows, function(a, b) return a[2] > b[2] end)
	for i = 1, math.min(30, #tRows) do
		aEmit(string.format("  %.0f KB  %s", tRows[i][2], tRows[i][1]))
	end
	aEmit(string.format("  %.0f KB  (all %d addons total)", tTotal, #tRows))
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
	elseif aMsg == "files" then
		Sku:PerformanceDumpFiles()
	elseif aMsg == "modules" then
		Sku:PerformanceDumpModules()
	elseif aMsg == "addons" then
		Sku:PerformanceDumpAddons(nil, true)
	elseif aMsg == "mem" then
		Sku:PerformanceDumpMem()
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
		Sku:PerformanceDumpFiles()
		Sku:PerformanceDumpModules()
		Sku:PerformanceDumpCombat()
		Sku:PerformanceDumpAddons(nil, false)
		Sku:PerformanceDumpMem()
	else
		print("|cff80c0ffSkuPerf|r usage: /skuperf [load|files|modules|combat|addons|mem|cpu|reset|frame]")
	end
end

--------------------------------------------------------------------------------
-- /skufollowprobe (/sfp) — TEMP diagnostic for the planned "stuck while
-- following" collision feature. For the unit you are currently following (or
-- target / party1 as a fallback) it reports which distance/position signals
-- THIS client actually returns, then samples them for ~5s at the collision-loop
-- cadence (0.15s) so we can see whether they move while the leader walks and you
-- stand still. Answers the open questions: does UnitPosition/UnitDistanceSquared
-- work out in the world AND inside instances, how coarse is LibRangeCheck, and
-- can we tell "leader moving + me pinned" apart. All samples go to the
-- SkuDebugLog ring via dprint (log is ON by default in Sku 42); read them back
-- from ...\SavedVariables\Sku.lua after a /reload. Delete once validated.
--------------------------------------------------------------------------------
local function tSkuFollowProbeResolveUnit()
	-- 1) live follow token if Sku already resolved one
	if SkuStatus and SkuStatus.follow and SkuStatus.follow ~= 0 then
		if SkuStatus.followUnitId and SkuStatus.followUnitId ~= "" and UnitExists(SkuStatus.followUnitId) then
			return SkuStatus.followUnitId, "followUnitId"
		end
		-- 2) resolve by follow name across raid/party
		local tName = SkuStatus.followUnitName
		if tName and tName ~= "" then
			for x = 1, 40 do if UnitName("raid"..x) == tName then return "raid"..x, "followName" end end
			for x = 1, 5 do if UnitName("party"..x) == tName then return "party"..x, "followName" end end
		end
	end
	-- 3) fallbacks so the probe is useful even when not following
	if UnitExists("target") then return "target", "target" end
	if UnitExists("party1") then return "party1", "party1" end
	return nil, "none"
end

-- UnitPosition returns two planar coords + z + instanceID; x/y order is
-- irrelevant here since we only ever take Euclidean deltas/distances.
local function tSkuFollowProbePos(aUnit)
	if type(UnitPosition) == "function" and aUnit then
		local a, b = UnitPosition(aUnit)
		if a and b then return a, b end
	end
	return nil, nil
end

local function tSkuFollowProbeDist(aUnit)
	if type(UnitDistanceSquared) == "function" and aUnit then
		local d2, checked = UnitDistanceSquared(aUnit)
		if checked and d2 then return math.sqrt(d2), checked end
		return nil, checked
	end
	return nil, nil
end

-- GetRange returns two range-bracket bounds. Print them raw/ordered: Sku's own
-- RangeCheck.lua labels the returns in the opposite order to the LibRangeCheck
-- doc, so we don't trust either name here.
local function tSkuFollowProbeLib(aUnit)
	if SkuOptions and SkuOptions.RangeCheck and SkuOptions.RangeCheck.GetRange and aUnit then
		local ok, r1, r2 = pcall(function() return SkuOptions.RangeCheck:GetRange(aUnit) end)
		if ok then return r1, r2 end
	end
	return nil, nil
end

local tSkuFollowProbeFrame
local function tSkuFollowProbeStart()
	if Sku and Sku.debug then Sku.debug.log = true end   -- ensure samples persist to the ring

	local tUnit, tHow = tSkuFollowProbeResolveUnit()
	local _, tInstType = IsInInstance()

	local pa, pb = tSkuFollowProbePos("player")
	local ua, ub = tUnit and tSkuFollowProbePos(tUnit) or nil, nil
	if tUnit then ua, ub = tSkuFollowProbePos(tUnit) end
	local tDist, tDChecked = nil, nil
	if tUnit then tDist, tDChecked = tSkuFollowProbeDist(tUnit) end
	local tR1, tR2 = nil, nil
	if tUnit then tR1, tR2 = tSkuFollowProbeLib(tUnit) end
	local tInRange, tRChecked
	if type(UnitInRange) == "function" and tUnit then tInRange, tRChecked = UnitInRange(tUnit) end

	dprint("=== SkuFollowProbe START ===")
	dprint("instance", tostring(tInstType), "unit", tostring(tUnit), "via", tHow,
		"name", tUnit and tostring((UnitName(tUnit))) or "-",
		"isPlayer", tUnit and tostring((UnitIsPlayer(tUnit))) or "-",
		"inParty", tUnit and tostring((UnitInParty(tUnit))) or "-",
		"inRaid", tUnit and tostring((UnitInRaid(tUnit))) or "-")
	dprint("player UnitPosition", tostring(pa), tostring(pb))
	dprint("unit UnitPosition", tostring(ua), tostring(ub))
	dprint("UnitDistanceSquared yd", tostring(tDist), "checked", tostring(tDChecked),
		"UnitInRange", tostring(tInRange), "checked", tostring(tRChecked))
	dprint("LibRangeCheck GetRange raw", tostring(tR1), tostring(tR2))

	-- audible one-shot summary (deDE)
	local tSpeak
	if not tUnit then
		tSpeak = "Probe. Kein Zielunit."
	else
		tSpeak = "Probe. "..tHow.." "..(UnitName(tUnit) or "?")..". "
			.."Position "..(ua and "ja" or "nein")..". "
			.."Distanz "..(tDist and tostring(math.floor(tDist*10)/10) or "nein")..". "
			.."Lib "..(tR1 and tostring(tR1) or "nein").." bis "..(tR2 and tostring(tR2) or "nein")
	end
	if SkuOptions and SkuOptions.Voice then SkuOptions.Voice:OutputString(tSpeak, true, true, 0.2) end

	if not tUnit then return end

	-- 5s sampler at the collision-loop cadence
	tSkuFollowProbeFrame = tSkuFollowProbeFrame or CreateFrame("Frame")
	local tElapsed, tAcc, tN = 0, 0, 0
	local tLpa, tLpb = pa, pb
	local tLua, tLub = ua, ub
	local tLDist = tDist
	tSkuFollowProbeFrame:SetScript("OnUpdate", function(self, time)
		tElapsed = tElapsed + time
		tAcc = tAcc + time
		if tAcc < 0.15 then return end
		tAcc = 0
		tN = tN + 1
		local cpa, cpb = tSkuFollowProbePos("player")
		local cua, cub = tSkuFollowProbePos(tUnit)
		local cdist = tSkuFollowProbeDist(tUnit)
		local myDelta = (cpa and tLpa) and math.sqrt((cpa-tLpa)^2 + (cpb-tLpb)^2) or nil
		local ldDelta = (cua and tLua) and math.sqrt((cua-tLua)^2 + (cub-tLub)^2) or nil
		local gapDelta = (cdist and tLDist) and (cdist - tLDist) or nil
		local mr1, mr2 = tSkuFollowProbeLib(tUnit)
		dprint("sample", tN,
			"myDelta", myDelta and tostring(math.floor(myDelta*1000)/1000) or "-",
			"leaderDelta", ldDelta and tostring(math.floor(ldDelta*1000)/1000) or "-",
			"dist", cdist and tostring(math.floor(cdist*100)/100) or "-",
			"gapDelta", gapDelta and tostring(math.floor(gapDelta*100)/100) or "-",
			"lib", tostring(mr1), tostring(mr2))
		tLpa, tLpb = cpa or tLpa, cpb or tLpb
		tLua, tLub = cua or tLua, cub or tLub
		tLDist = cdist or tLDist
		if tElapsed >= 5 then
			self:SetScript("OnUpdate", nil)
			dprint("=== SkuFollowProbe END, samples="..tN.." ===")
			if SkuOptions and SkuOptions.Voice then
				SkuOptions.Voice:OutputString("Probe fertig, "..tN.." Samples", true, true, 0.2)
			end
		end
	end)
end

SLASH_SKUFOLLOWPROBE1 = "/skufollowprobe"
SLASH_SKUFOLLOWPROBE2 = "/sfp"
SlashCmdList["SKUFOLLOWPROBE"] = function()
	tSkuFollowProbeStart()
end

--------------------------------------------------------------------------------
-- /skucollisionprobe (/scp [seconds]) — TEMP diagnostic for a planned
-- DUNGEON-CAPABLE self-collision ("walked into a wall") feature. Fall detection
-- works in instances because IsFalling() is a physics STATE, not a coordinate;
-- the open question here is whether GetUnitSpeed("player") gives an equally
-- coordinate-free "am I actually moving" signal -- i.e. does currentSpeed
-- collapse to ~0 while a forward/strafe/autorun key is still held against a
-- wall, or does it keep reporting the intended run speed? Sku already tracks the
-- INTENT (SkuCoreMovement.Flags.MoveForward/MoveBackward/StrafeLeft/StrafeRight/
-- AutoRun, from the MoveForwardStart-style hooks); this samples that intent
-- against GetUnitSpeed + IsFalling at the collision-loop cadence (0.15s) so we
-- can see the mismatch. UnitPosition delta is logged too as an OUTDOOR
-- cross-check (it goes nil in instances -- that dead column is exactly the point
-- GetUnitSpeed has to cover). All samples go to the SkuDebugLog ring via dprint;
-- read them back from ...\SavedVariables\Sku.lua after a /reload. Default 8s,
-- optional arg clamps to 3..30s. Delete once validated.
--
-- How to read it: walk straight into a wall for a few seconds, then run freely
-- for a few more, /reload, and compare. If the WALL segment shows currentSpeed
-- (and ratio) near 0 while intent stays "true", the feature is just a rewire of
-- the existing coord-based self-collision block onto GetUnitSpeed for instances.
--------------------------------------------------------------------------------
-- Translational movement intent only (deliberately NOT pure turning: turning in
-- place is not a collision and Flags.IsTurningOrAutorunningOrStrafing conflates
-- it). Returns a bool + a compact "which keys" string for the log.
local function tSkuCollisionProbeIntent()
	local f = SkuCoreMovement and SkuCoreMovement.Flags or {}
	local tSet = {}
	if f.MoveForward == true then tSet[#tSet + 1] = "F" end
	if f.MoveBackward == true then tSet[#tSet + 1] = "B" end
	if f.StrafeLeft == true then tSet[#tSet + 1] = "L" end
	if f.StrafeRight == true then tSet[#tSet + 1] = "R" end
	if f.AutoRun == true then tSet[#tSet + 1] = "A" end
	return #tSet > 0, (#tSet > 0 and table.concat(tSet, "") or "-")
end

local tSkuCollisionProbeFrame
local function tSkuCollisionProbeStart(aSeconds)
	if Sku and Sku.debug then Sku.debug.log = true end   -- ensure samples persist to the ring

	local tDuration = tonumber(aSeconds) or 8
	if tDuration < 3 then tDuration = 3 elseif tDuration > 30 then tDuration = 30 end

	local _, tInstType = IsInInstance()
	local cur, run = GetUnitSpeed("player")
	local pa, pb = tSkuFollowProbePos("player")   -- reuse the follow probe's UnitPosition helper

	dprint("=== SkuCollisionProbe START ===")
	dprint("instance", tostring(tInstType), "duration", tDuration,
		"swimming", tostring(IsSwimming()), "falling", tostring(IsFalling()),
		"onTaxi", tostring(UnitOnTaxi and UnitOnTaxi("player")),
		"UnitPosition", (pa and "live" or "dead"))
	dprint("speed@start current", tostring(cur), "run", tostring(run))

	if SkuOptions and SkuOptions.Voice then
		SkuOptions.Voice:OutputString("Kollisionsprobe. "..tDuration.." Sekunden. Jetzt gegen eine Wand laufen.", true, true, 0.2)
	end

	-- Sampler at the collision-loop cadence. Logs, each tick: current/run speed,
	-- their ratio (the "fraction of max speed actually achieved" -- ~1 free, ~0
	-- head-on wall, mid = sliding), IsFalling, the intent keys, and the outdoor
	-- UnitPosition delta as a truth check on GetUnitSpeed.
	tSkuCollisionProbeFrame = tSkuCollisionProbeFrame or CreateFrame("Frame")
	local tElapsed, tAcc, tN = 0, 0, 0
	local tLpa, tLpb = pa, pb
	tSkuCollisionProbeFrame:SetScript("OnUpdate", function(self, time)
		tElapsed = tElapsed + time
		tAcc = tAcc + time
		if tAcc < 0.15 then return end
		tAcc = 0
		tN = tN + 1
		local ccur, crun = GetUnitSpeed("player")
		local tRatio = (crun and crun > 0) and (ccur / crun) or nil
		local tIntent, tKeys = tSkuCollisionProbeIntent()
		local cpa, cpb = tSkuFollowProbePos("player")
		local myDelta = (cpa and tLpa) and math.sqrt((cpa - tLpa)^2 + (cpb - tLpb)^2) or nil
		dprint("sample", tN,
			"cur", ccur and tostring(math.floor(ccur * 100) / 100) or "-",
			"run", crun and tostring(math.floor(crun * 100) / 100) or "-",
			"ratio", tRatio and tostring(math.floor(tRatio * 100) / 100) or "-",
			"intent", tostring(tIntent), "keys", tKeys,
			"falling", tostring(IsFalling()),
			"posDelta", myDelta and tostring(math.floor(myDelta * 1000) / 1000) or "-")
		tLpa, tLpb = cpa or tLpa, cpb or tLpb
		if tElapsed >= tDuration then
			self:SetScript("OnUpdate", nil)
			dprint("=== SkuCollisionProbe END, samples="..tN.." ===")
			if SkuOptions and SkuOptions.Voice then
				SkuOptions.Voice:OutputString("Kollisionsprobe fertig, "..tN.." Samples", true, true, 0.2)
			end
		end
	end)
end

SLASH_SKUCOLLISIONPROBE1 = "/skucollisionprobe"
SLASH_SKUCOLLISIONPROBE2 = "/scp"
SlashCmdList["SKUCOLLISIONPROBE"] = function(aMsg)
	tSkuCollisionProbeStart(aMsg)
end

-- Load-time milestone capture. The single debugprofilestart() at the top of
-- this file anchors the session clock, so Sku:MetricPoint() records seconds
-- since core load. We stamp the two key startup events and auto-persist the
-- timeline to the ring once the world is ready (silent - no chat spam).
local tPerfLoadFrame = CreateFrame("Frame")
tPerfLoadFrame.tFirstPew = true
tPerfLoadFrame:RegisterEvent("ADDON_LOADED")
tPerfLoadFrame:RegisterEvent("PLAYER_LOGIN")
tPerfLoadFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
tPerfLoadFrame:SetScript("OnEvent", function(self, aEvent, aArg1)
	if aEvent == "ADDON_LOADED" then
		-- Fires once all of Sku's files have loaded+compiled+run their top-level
		-- chunks. The gap from t0 (Core.lua load) to here is the file-load cost -
		-- where the giant SkuDB data tables are paid.
		if aArg1 == "Sku" and not self.tStampedSku then
			self.tStampedSku = true
			Sku:MetricPoint("ADDON_LOADED (Sku files compiled)")
		end
	elseif aEvent == "PLAYER_LOGIN" then
		Sku:MetricPoint("PLAYER_LOGIN")
	elseif aEvent == "PLAYER_ENTERING_WORLD" then
		if self.tFirstPew then
			self.tFirstPew = false
			Sku:MetricPoint("PLAYER_ENTERING_WORLD (first)")
			-- Freeze the per-module timing now, before any later enable/disable
			-- toggle can overwrite the load-time reading.
			Sku.PerfModulesLoad = {}
			for k, v in pairs(Sku.PerfModules) do
				Sku.PerfModulesLoad[k] = {init = v.init, enableSelf = v.enableSelf, enableTotal = v.enableTotal}
			end
			-- [Load-perf 2026-07-05] Force a full GC now, while the loading screen
			-- still covers us: file load and the route build leave hundreds of MB
			-- of garbage, and letting the incremental GC digest that AFTER the
			-- screen fades was part of the post-load stutter (same trick as
			-- Questie's QuestieCleanup: collectgarbage at the end of init).
			local tGcT0 = debugprofilestop()
			local tGcBeforeKb = collectgarbage("count")
			collectgarbage("collect")
			Sku:MetricPoint(string.format("forced GC at PEW = %.0f ms, %.0f MB -> %.0f MB", debugprofilestop() - tGcT0, tGcBeforeKb / 1024, collectgarbage("count") / 1024))
			-- One frame later control has returned to the user, so this stamp marks
			-- roughly where the visible /reload freeze ends. Auto-persist the whole
			-- load story to the ring (silent - no chat/TTS spam).
			-- [Load-perf 2026-07-05] Do NOT write this capture into the ring:
			-- chatty login diagnostics (the link-consistency phase used to log
			-- one line per stale link, thousands per login) flood the ring and
			-- the trim silently evicted the capture. Store it in a dedicated
			-- eviction-proof field instead (same pattern as
			-- SkuDebugLog.wpcResult): SkuDebugLog.loadPerf, overwritten each
			-- load, read out-of-game via _readperf.py.
			local function tCapture()
				if type(SkuDebugLog) ~= "table" then SkuDebugLog = {} end
				local tOut = { "=== load perf capture  " .. date("%Y-%m-%d %H:%M:%S") .. " ===" }
				local function tEmit(aLine) tOut[#tOut + 1] = aLine end
				Sku:PerformanceDumpLoad(tEmit)
				Sku:PerformanceDumpFiles(tEmit)
				Sku:PerformanceDumpModules(tEmit)
				Sku:PerformanceDumpMem(tEmit)
				if GetCVar and GetCVar("scriptProfile") == "1" then
					Sku:PerformanceDumpAddons(tEmit, false)
				end
				SkuDebugLog.loadPerf = tOut
			end
			if C_Timer and C_Timer.After then
				C_Timer.After(0, function()
					Sku:MetricPoint("first frame after PEW")
					tCapture()
				end)
			else
				tCapture()
			end
		end
	end
end)