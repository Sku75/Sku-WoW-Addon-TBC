-- Offline harness for SkuVoice's BTTS path.
-- usage: luajit harness.lua <path to SkuVoice-1.0.lua> <sapi|bridge>
local libPath, mode = arg[1], arg[2] or "sapi"

local now = 1000 -- like GetTime() in game: never near zero
function GetTime() return now end
local logLines = {}
local quiet = false
function dprint(...)
	local t = {}
	for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
	logLines[#logLines + 1] = string.format("%7.3f  %s", now, table.concat(t, "  "))
end

local lib = {}
LibStub = setmetatable({
	NewLibrary = function(self, major) lib[major] = {}; return lib[major] end,
}, { __call = function(self, major)
	if major == "AceLocale-3.0" then
		return { GetLocale = function() return setmetatable({}, { __index = function(t, k) return k end }) end }
	end
	return lib[major]
end })

local frame = { scripts = {} }
function frame:RegisterEvent() end
function frame:SetScript(n, f) self.scripts[n] = f end
function CreateFrame() return frame end
UIParent = {}
function IsMacClient() return false end
function PlaySoundFile() return false end
function StopSound() end
SkuOptions = { TTS = { GetLinksTableFromString = function() end }, db = { profile = { SkuOptions = { useBlizzTtsInMenu = true } } } }
Sku = { AudiodataPath = "", L = {} }
gsub, strfind, strsub, strlen, strlower, strupper, format, tinsert, tremove, strtrim = string.gsub, string.find, string.sub, string.len, string.lower, string.upper, string.format, table.insert, table.remove, function(s) return (s:gsub('^%s+',''):gsub('%s+$','')) end
wipe = function(t) for k in pairs(t) do t[k] = nil end end

-- ---------------------------------------------------------------- client model
-- Real SAPI voice, as measured from captures:
--   * one utterance plays at a time
--   * SpeakText while idle -> STARTED after a start latency
--   * SpeakText while something plays or is pending -> PARKED
--   * natural end -> FINISHED 0.5 s after the audio end, THEN the oldest parked
--     utterance starts
--   * StopSpeakingText kills the PLAYING one silently (no events) and does NOT
--     pump the parked queue; a pending (accepted, unstarted) one is not touched
local nextId = 1
local playing, pending, parked = nil, nil, {}
local events = {}       -- {at=, name=, args=}
local heard = {}        -- {id, text, startedAt, handedAt, cut=}
local START_LAT = tonumber(os.getenv("LAT") or "0.12")
local function fire(at, name, ...) if mode == "mute" then return end events[#events + 1] = { at = at, name = name, args = { ... } } end
local function audioLen(text) return 0.45 + #text * 0.06 end
local function clean(s) return (s:gsub("<.->", ""):gsub("\194\160", ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function beginStart(u, at)
	pending = u
	u.startAt = at + START_LAT
end

-- ★The wedge (observed live 2026-09-21): StopSpeakingText called from INSIDE a
-- TTS event handler kills the client's whole TTS pipeline until restart -- no
-- further events for any voice, real voices silent.
local dispatching, wedged = false, false
C_VoiceChat = {}
function C_VoiceChat.SpeakText(voice, text)
	if wedged then nextId = nextId + 1; return end
	local u = { id = nextId, text = clean(text), handedAt = now }
	nextId = nextId + 1
	if mode == "bridge" then
		heard[#heard + 1] = { id = u.id, text = u.text, startedAt = now, handedAt = now }
		fire(now, "VOICE_CHAT_TTS_PLAYBACK_STARTED", u.id)
		fire(now, "VOICE_CHAT_TTS_PLAYBACK_FINISHED", u.id)
		return
	end
	if playing or pending then
		parked[#parked + 1] = u
	else
		beginStart(u, now)
	end
end
function C_VoiceChat.StopSpeakingText()
	if dispatching and not wedged then wedged = true; wedgedAt = now end
	if mode == "bridge" then return end
	if playing then
		playing.rec.cut = now
		playing = nil
		-- engine idle; parked queue is NOT pumped by a stop
	end
end

local function clientTick()
	if wedged then return end
	if pending and now >= pending.startAt then
		local u = pending
		pending = nil
		if playing then
			-- cannot happen in this model
			error("start while playing")
		end
		playing = u
		u.endAt = now + audioLen(u.text)
		u.rec = { id = u.id, text = u.text, startedAt = now, handedAt = u.handedAt }
		heard[#heard + 1] = u.rec
		fire(now, "VOICE_CHAT_TTS_PLAYBACK_STARTED", u.id)
		fire(now, "VOICE_CHAT_TTS_PLAYBACK_BOOKMARK", u.id, "Start")
	end
	if playing and not playing.ended and now >= playing.endAt then
		playing.ended = true
		fire(now, "VOICE_CHAT_TTS_PLAYBACK_BOOKMARK", playing.id, "End")
	end
	if playing and playing.ended and now >= playing.endAt + 0.5 then
		local u = playing
		playing = nil
		fire(now, "VOICE_CHAT_TTS_PLAYBACK_FINISHED", u.id)
		if #parked > 0 and not pending then
			local n = table.remove(parked, 1)
			pending = n
			n.startAt = now -- parked ones start on FINISHED
		end
	end
	-- (a stop leaves parked lines parked: measured, 489 sat 65 s until a natural FINISHED)
end

-- ---------------------------------------------------------------- load library
local f = assert(io.open(libPath, "rb"))
local src = f:read("*a"):gsub("^\239\187\191", "")
f:close()
assert(loadstring(src, "SkuVoice"))()
local V = lib["SkuVoice-1.0"]
V:Create()

local script = {}   -- {at=, fn=}
local T0 = now
local function at(t, fn) script[#script + 1] = { at = T0 + t, fn = fn } end
local function say(t, text, overwrite, opts)
	at(t, function()
		local o = opts or {}
		o.overwrite = overwrite
		o.engine = "blizz"
		V:OutputStringBTtts(text, o)
	end)
end

local function run(untilT)
	local dt = 1 / 60
	local si = 1
	table.sort(script, function(a, b) return a.at < b.at end)
	untilT = T0 + untilT
	while now < untilT do
		while script[si] and script[si].at <= now do script[si].fn(); si = si + 1 end
		clientTick()
		local i = 1
		while events[i] do
			local e = table.remove(events, 1)
			dispatching = true
			if not wedged then frame.scripts.OnEvent(frame, e.name, unpack(e.args)) end
			dispatching = false
		end
		frame.scripts.OnUpdate(frame, dt)
		now = now + dt
	end
end

local function report(title, checks)
	print("=== " .. title .. " [" .. mode .. "] ===")
	if wedged then print("  ★★ WEDGED: StopSpeakingText was called from inside a TTS event handler") end
	local maxStartedId, ooo, late = 0, 0, 0
	for _, h in ipairs(heard) do
		local d = h.startedAt - h.handedAt
		local flag = ""
		if h.id < maxStartedId then ooo = ooo + 1; flag = flag .. " OUT-OF-ORDER" end
		if d > 1.5 then late = late + 1; flag = flag .. " LATE" end
		if h.id > maxStartedId then maxStartedId = h.id end
		local dur = h.cut and (h.cut - h.startedAt) or nil
		print(string.format("  %6.2f  id=%-3d wait=%.2f %s [%s]%s", h.startedAt - T0, h.id, d,
			dur and string.format("cut@%.2fs", dur) or "full     ", h.text, flag))
	end
	print(string.format("  -> utterances handed=%d audible=%d out-of-order=%d late=%d parked-left=%d",
		nextId - 1, #heard, ooo, late, #parked))
	if checks then checks(heard) end
	if os.getenv("HLOG") then for _, l in ipairs(logLines) do print("      " .. l) end end
end

return { isWedged = function() return wedged end, V = V, at = at, say = say, run = run, report = report, heard = heard, setNow = function(t) now = t end }
