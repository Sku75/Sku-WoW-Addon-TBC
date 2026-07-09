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
-- When the watch window ends it plays the level-up sound (audible "measurement
-- done" signal even with no other addon enabled) and prints the summary line.
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

-- Speak through Sku when it is loaded, so the result is audible in Sku runs.
local function tSpeak(aText)
	if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputString then
		pcall(function() SkuOptions.Voice:OutputString(aText, false, true, 0.3) end)
	end
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
	LoadStopwatchDB = LoadStopwatchDB or {}
	LoadStopwatchDB.runs = LoadStopwatchDB.runs or {}
	local tRuns = LoadStopwatchDB.runs
	tRuns[#tRuns + 1] = tSummary
	while #tRuns > MAX_RUNS do table.remove(tRuns, 1) end
	pcall(PlaySound, 888, "Master") -- level-up jingle = "measurement finished"
	tPrint(tSummary)
	tSpeak(string.format("Messung fertig. Bis erste Frame %.1f Sekunden, beruhigt nach weiteren %.1f Sekunden.",
		tFirstFrameAt - tT0, tLastBigAt))
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
tEvents:SetScript("OnEvent", function(self, aEvent, aIsInitialLogin, aIsReloadingUi)
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
