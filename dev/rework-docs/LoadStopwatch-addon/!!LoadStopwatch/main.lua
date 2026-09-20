-- !!LoadStopwatch - wall-clock login/reload measurement (Sku 42 rework tooling).
--
-- Measures what the perf harness inside Sku cannot: the TOTAL felt time from
-- the very first addon file executing (this one - the !! prefix makes it load
-- before everything else) until the game has actually settled after the
-- loading screen, including every other addon, Blizzard's world load, and the
-- post-load GC/stutter phase.
--
-- What it records per login//reload (one flat summary string per run, appended
-- to LoadStopwatchDB.runs, newest last, capped at 100):
--   * mode (login / reload / world)  * time to PLAYER_ENTERING_WORLD
--   * time to the first rendered frame after PEW
--   * "settled" = offset of the LAST frame longer than 100 ms within the 30 s
--     watch window after PEW (the felt end of the post-load stutter)
--   * spike counts (>50 / >100 / >250 ms frames) and the worst frame
--   * whole-UI Lua memory at PEW and at the end of the watch window
--   * number of loaded addons
--   * file load time per addon family (Sku*, WowVision*) and the three slowest
--     single addons. Addons load one after another, so the gap between two
--     ADDON_LOADED events is the later addon's file time (parse + run + saved
--     variables). This frame registers first, so an addon's OWN ADDON_LOADED
--     work (Ace OnInitialize) lands in the NEXT addon's gap - the family sums
--     absorb that, single numbers are approximate. OnEnable/PLAYER_LOGIN work
--     of all addons plus Blizzard's world load is the "login phase" number.
-- When the watch window ends it prints the summary line and speaks the result
-- through Sku or WowVision, whichever is loaded (no sound: the speech is the
-- "measurement done" signal).
--
-- Slash commands: /lsw (last run), /lsw all, /lsw clear.
-- Out-of-game reader: Sku42-Rework-Docs\_read_stopwatch.py

local tT0 = GetTimePreciseSec()

local WATCH_SECONDS = 30
local MAX_RUNS = 100

local tPewAt, tFirstFrameAt
local tMode = "world"
local tMemAtPewMb
local tDone = false

-- frame-time monitor state (all offsets relative to PEW)
local tLastTick
local tSpikes50, tSpikes100, tSpikes250 = 0, 0, 0
local tWorstGap, tWorstAt = 0, 0
local tLastBigAt = 0

local function tNumAddOns()
	local tGetNum = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
	local tIsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	if not tGetNum or not tIsLoaded then return -1 end
	local tCount = 0
	for i = 1, tGetNum() do
		if tIsLoaded(i) then tCount = tCount + 1 end
	end
	return tCount
end

local function tPrint(aText)
	if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99LSW|r " .. aText) end
end

-- Speak through Sku or WowVision, whichever is loaded, so the result is audible.
local function tSpeak(aText)
	if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputString then
		pcall(function() SkuOptions.Voice:OutputString(aText, false, true, 0.3) end)
	elseif WowVision and WowVision.speak then
		pcall(function() WowVision:speak(aText) end)
	end
end

-- per-addon file load times (see header)
local tLastLoadedAt = tT0
local tAddonTimes = {}
local tFamilies = { { "Sku", "^sku" }, { "WowVision", "^wowvision" } }

local function tFamilyTime(aPattern)
	local tSum, tCount = 0, 0
	for _, tEntry in ipairs(tAddonTimes) do
		if string.find(string.lower(tEntry[1]), aPattern) then
			tSum = tSum + tEntry[2]
			tCount = tCount + 1
		end
	end
	return tSum, tCount
end

local function tAddonSummary()
	local tParts = {}
	for _, tFamily in ipairs(tFamilies) do
		local tSum, tCount = tFamilyTime(tFamily[2])
		if tCount > 0 then
			tParts[#tParts + 1] = string.format("%s files %.2fs (%d addons)", tFamily[1], tSum, tCount)
		end
	end
	local tSorted = {}
	for i, tEntry in ipairs(tAddonTimes) do tSorted[i] = tEntry end
	table.sort(tSorted, function(a, b) return a[2] > b[2] end)
	local tTop = {}
	for i = 1, math.min(3, #tSorted) do
		tTop[i] = string.format("%s %.2fs", tSorted[i][1], tSorted[i][2])
	end
	tParts[#tParts + 1] = "slowest: " .. table.concat(tTop, ", ")
	tParts[#tParts + 1] = string.format("login phase %.1fs", tPewAt - tLastLoadedAt)
	return table.concat(tParts, " | ")
end

local function tFinishRun()
	if tDone then return end
	tDone = true
	local tMemNowMb = collectgarbage("count") / 1024
	local tSummary = string.format(
		"%s | %s | to PEW %.1fs | first frame %.1fs | settled +%.1fs | spikes 50/100/250ms: %d/%d/%d | worst %.0fms at +%.1fs | lua mem %.0f->%.0f MB | addons %d",
		date("%Y-%m-%d %H:%M:%S"), tMode,
		tPewAt - tT0, tFirstFrameAt - tT0,
		tLastBigAt,
		tSpikes50, tSpikes100, tSpikes250,
		tWorstGap * 1000, tWorstAt,
		tMemAtPewMb or -1, tMemNowMb,
		tNumAddOns())
	tSummary = tSummary .. " | " .. tAddonSummary()
	LoadStopwatchDB = LoadStopwatchDB or {}
	LoadStopwatchDB.runs = LoadStopwatchDB.runs or {}
	local tRuns = LoadStopwatchDB.runs
	tRuns[#tRuns + 1] = tSummary
	while #tRuns > MAX_RUNS do table.remove(tRuns, 1) end
	tPrint(tSummary)
	local tSpoken = string.format("Messung fertig. Bis erste Frame %.1f Sekunden, beruhigt nach weiteren %.1f Sekunden.",
		tFirstFrameAt - tT0, tLastBigAt)
	for _, tFamily in ipairs(tFamilies) do
		local tSum, tCount = tFamilyTime(tFamily[2])
		if tCount > 0 then
			tSpoken = tSpoken .. string.format(" %s Dateien %.1f Sekunden.", tFamily[1], tSum)
		end
	end
	tSpeak(tSpoken)
end

local tMonitor = CreateFrame("Frame")
tMonitor:Hide()
tMonitor:SetScript("OnUpdate", function(self)
	local tNow = GetTimePreciseSec()
	if not tFirstFrameAt then
		tFirstFrameAt = tNow
		tLastTick = tNow
		return
	end
	local tGap = tNow - tLastTick
	tLastTick = tNow
	local tOffset = tNow - tPewAt
	if tGap > 0.05 then tSpikes50 = tSpikes50 + 1 end
	if tGap > 0.10 then
		tSpikes100 = tSpikes100 + 1
		tLastBigAt = tOffset
	end
	if tGap > 0.25 then tSpikes250 = tSpikes250 + 1 end
	if tGap > tWorstGap then
		tWorstGap = tGap
		tWorstAt = tOffset
	end
	if tOffset >= WATCH_SECONDS then
		self:Hide()
		tFinishRun()
	end
end)

local tEvents = CreateFrame("Frame")
tEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
tEvents:RegisterEvent("ADDON_LOADED")
tEvents:SetScript("OnEvent", function(self, aEvent, aIsInitialLogin, aIsReloadingUi)
	if aEvent == "ADDON_LOADED" then
		if tPewAt then return end -- load-on-demand addons later in the session do not count
		local tNow = GetTimePreciseSec()
		tAddonTimes[#tAddonTimes + 1] = { tostring(aIsInitialLogin), tNow - tLastLoadedAt } -- first event arg = addon name
		tLastLoadedAt = tNow
		return
	end
	if tPewAt then return end -- only the first PEW of this session
	tPewAt = GetTimePreciseSec()
	if aIsInitialLogin then tMode = "login" elseif aIsReloadingUi then tMode = "reload" end
	tMemAtPewMb = collectgarbage("count") / 1024
	tMonitor:Show()
end)

SLASH_LOADSTOPWATCH1 = "/lsw"
SlashCmdList["LOADSTOPWATCH"] = function(aArg)
	aArg = string.lower(aArg or "")
	local tRuns = LoadStopwatchDB and LoadStopwatchDB.runs
	if aArg == "clear" then
		if LoadStopwatchDB then LoadStopwatchDB.runs = {} end
		tPrint("runs cleared")
	elseif aArg == "all" then
		if not tRuns or #tRuns == 0 then tPrint("no runs recorded") return end
		for i = 1, #tRuns do tPrint(tRuns[i]) end
	else
		if not tRuns or #tRuns == 0 then tPrint("no runs recorded") return end
		tPrint(tRuns[#tRuns])
		tSpeak(tRuns[#tRuns])
	end
end
