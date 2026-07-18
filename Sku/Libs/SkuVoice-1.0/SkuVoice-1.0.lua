local SkuVoice_MAJOR, SkuVoice_MINOR = "SkuVoice-1.0", 1
local SkuVoice, oldminor = LibStub:NewLibrary(SkuVoice_MAJOR, SkuVoice_MINOR)

--local L = Sku.L
local L = LibStub("AceLocale-3.0"):GetLocale("Sku", false)

if not SkuVoice then return end -- No upgrade needed

-- Blizzard-TTS params provider (W6-B #12): the audio engine no longer reaches
-- into SkuChat's saved-settings schema by string key. SkuChat registers a
-- provider via SkuVoice:SetChatTtsProvider that returns the current param table
-- (fields WowTtsVoice/WowTtsSpeed/WowTtsVolume/neverResetQueues/
-- allChatViaBlizzardTts); the engine only ever calls that. Falls back to sane
-- defaults if no provider is registered yet.
local mChatTtsProvider
local mChatTtsDefaults = { WowTtsVoice = 1, WowTtsSpeed = 3, WowTtsVolume = 50, neverResetQueues = false, allChatViaBlizzardTts = false }
local function ChatTts()
	return (mChatTtsProvider and mChatTtsProvider()) or mChatTtsDefaults
end
function SkuVoice:SetChatTtsProvider(aFn)
	mChatTtsProvider = aFn
end

local tGenderSuffixes = {
	["frau"] = "mann",
	["in"] = "",
	}

local tEmojis = {
	[":%-%)"] = L["Emoji"].." "..L["Smile"],
	[":%)"] = L["Emoji"].." "..L["Smile"],
	[":%]"] = L["Emoji"].." "..L["Smile"],
	[":>"] = L["Emoji"].." "..L["Smile"],
	["%^%^"] = L["Emoji"].." "..L["Smile"],
	[":%-d"] = L["Emoji"].." "..L["Laughing"],
	[":d"] = L["Emoji"].." "..L["Laughing"],
	["xd"] = L["Emoji"].." "..L["Laughing"],
	["Xd"] = L["Emoji"].." "..L["Laughing"],
	[":%-%("] = L["Emoji"].." "..L["Sad"],
	[":%("] = L["Emoji"].." "..L["Sad"],
	[":%-%*"] = L["Emoji"].." "..L["Kiss"],
	[":%*"] = L["Emoji"].." "..L["Kiss"],
	[":%-P"] = L["Emoji"].." "..L["Tongue sticking out"],
	[":p"] = L["Emoji"].." "..L["Tongue sticking out"],
	[":%-/"] = L["Emoji"].." "..L["Skeptical"],
	[":/"] = L["Emoji"].." "..L["Skeptical"],
	[":\\"] = L["Emoji"].." "..L["Skeptical"],
	[":%-|"] = L["Emoji"].." "..L["Straight face"],
	[":|"] = L["Emoji"].." "..L["Straight face"],
	[":%-x"] = L["Emoji"].." "..L["Sealed lips"],
	[":x"] = L["Emoji"].." "..L["Sealed lips"],
	[":%-#"] = L["Emoji"].." "..L["Sealed lips"],
	[":#"] = L["Emoji"].." "..L["Sealed lips"],
	[";%-%)"] = L["Emoji"].." "..L["Wink"],
	[";%)"] = L["Emoji"].." "..L["Wink"],
}	


local SapiLangIds = {
	["deDE"] = 407,
	["enUS"] = 409,
	["enAU"] = 409,
	}

---------------------------------------------------------------------------------------------------------
SkuVoice.LastPlayedString = ""
SkuVoice.TutorialPlaying = 0
--setmetatable(mSkuVoiceQueue, SkuNav.PrintMT)

---------------------------------------------------------------------------------------------------------

local mSkuVoiceQueue = {}
local mSkuVoiceQueueBTTS = {}
-- Dedup guard for the Blizzard-TTS path: the set of lines Sku has handed to
-- C_VoiceChat.SpeakText and believes are still playing, so an identical line
-- queued while the first is speaking isn't spoken twice. Each entry is a table
-- {text=, at=}: `at` is GetTime() at hand-off so a wedged entry (its
-- FINISHED/FAILED never fired) can be force-expired (see tBttsSpeakingTtl). Was
-- a flat list of strings; became tables so the guard can self-heal instead of
-- suppressing every future identical line forever.
local mSkuVoiceQueueBTTS_Speaking = {}
-- Max seconds a line stays flagged "speaking" before the pump force-clears it.
-- Pure self-heal net for a dropped FINISHED/FAILED — set well above any real
-- utterance so it never clips legitimate playback, only breaks a permanent wedge.
local tBttsSpeakingTtl = 12
-- Per-message Blizzard-TTS voice override. Keyed by the FINAL assembled queue
-- string (the exact value stored in mSkuVoiceQueueBTTS), value = a 1-based menu
-- index into SkuChat.WowTtsVoices (same domain as the global WowTtsVoice
-- setting). Kept as a SIDE-map on purpose so the queue entries stay plain
-- strings — the "queuereset" sentinel and the dedupe-by-text logic are
-- untouched. nil (no entry) => fall back to the global voice. See
-- OutputStringBTtts (writes) and the OnUpdate dequeue (reads+clears).
local mSkuVoiceQueueBTTS_Voice = {}

-- BTTS cache-buster (WoW 12.0 engine): the new client caches synthesized audio
-- by text and, on a repeat, REPLAYS the cached audio without re-invoking the
-- voice. For a real voice (Hedda) that replay is audible; for an out-of-band
-- screen-reader bridge (NVDA/SAPI2SR) the cached audio is silent AND the bridge
-- is never called, so already-spoken lines go silent on revisit. Appending a
-- cycling run of U+200B ZERO WIDTH SPACE (invisible, not spoken by NVDA) makes
-- each utterance's text unique -> every SpeakText is a cache MISS -> the voice
-- is always invoked. Only applied to the Blizzard-TTS (SpeakText) path.
local mBttsCacheBust = 0
local function BttsCacheBust(aString)
	mBttsCacheBust = (mBttsCacheBust % 64) + 1
	-- Two things:
	-- 1) Leading U+00A0 NO-BREAK SPACE (C2 A0): quest text is spoken as several
	--    separate queued utterances; each is assembled with a LEADING space that
	--    XML normalization trims, so NVDA glues a punctuation-less header to the
	--    next utterance's first word ("questtext"+"vor" -> "questtextvor"). U+00A0
	--    is not XML whitespace, so it survives trimming and keeps the word
	--    boundary at the seam, without being spoken.
	-- 2) Trailing <bookmark> tag: WoW's 12.0 audio cache replays cached (silent)
	--    audio for the bridge on repeats; a cycling bookmark makes each string
	--    unique -> cache miss. SAPI parses it out as metadata (inaudible) and our
	--    engine patch strips it anyway.
	return "\194\160" .. aString .. string.format('<bookmark mark="skc%d"/>', mBttsCacheBust)
end

function SkuVoice:Create()
	local f = CreateFrame("Frame", "SkuVoiceMainFrame", UIParent)
	f:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FINISHED")
	-- BTTS diag: also watch STARTED/FAILED so we can see whether WoW's TTS
	-- engine actually accepts each utterance and whether FINISHED still fires
	-- (if FINISHED stops firing, the dedup list never clears and playback stalls).
	f:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_STARTED")
	f:RegisterEvent("VOICE_CHAT_TTS_SPEAK_TEXT_UPDATE")
	-- BTTS diag: the new (patch 12.0.0) TTS engine wraps utterances with
	-- boundary bookmarks; a real SAPI voice consumes them silently, but a
	-- SAPI->screenreader bridge voice speaks the mark names ("start"/"end").
	-- Log the bookmark event to capture the exact mark names as proof.
	pcall(function() f:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_BOOKMARK") end)
	-- FAILED is the third event the queue MUST watch (per the WoW-Vision hint):
	-- some voices / the SAPI->screenreader bridge FAIL an utterance instead of
	-- FINISHING it. Without draining on FAILED the entry stuck in the dedup guard
	-- forever, so every later identical line was dropped ("skips newly incoming").
	f:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FAILED")
	f:SetScript("OnEvent", function(self, aEventName, ...)
		if aEventName == "VOICE_CHAT_TTS_PLAYBACK_FINISHED" or aEventName == "VOICE_CHAT_TTS_PLAYBACK_FAILED" then
			if dprint then dprint("BTTS event "..aEventName, ...) end
			-- Drain the oldest speaking entry on BOTH end and fail (FIFO — the
			-- guard's only job is short-lived dedup, so oldest-out is good enough;
			-- the TTL sweep backstops any out-of-order or missing event).
			if mSkuVoiceQueueBTTS_Speaking[1] then
				table.remove(mSkuVoiceQueueBTTS_Speaking, 1)
			end
		elseif aEventName == "VOICE_CHAT_TTS_PLAYBACK_STARTED" then
			if dprint then dprint("BTTS event STARTED", ...) end
		elseif aEventName == "VOICE_CHAT_TTS_SPEAK_TEXT_UPDATE" then
			if dprint then dprint("BTTS event SPEAK_TEXT_UPDATE", ...) end
		elseif aEventName == "VOICE_CHAT_TTS_PLAYBACK_BOOKMARK" then
			if dprint then dprint("BTTS event BOOKMARK", ...) end
		end
	end)
	local fTime = 0
	local fTimeBTTS = 0
	local tLastWait = -1
	f:SetScript("OnUpdate", function(self, time)

		fTimeBTTS = fTimeBTTS + time
		if fTimeBTTS > 0.01 then
			fTimeBTTS = 0
			-- Self-heal: drop any speaking entry whose FINISHED/FAILED never
			-- arrived (dropped by some voices / the bridge). Without this a wedged
			-- entry suppresses every future identical line via the dedup below.
			local tNow = GetTime()
			local tSweep = true
			while tSweep do
				tSweep = false
				for z = 1, #mSkuVoiceQueueBTTS_Speaking do
					if (tNow - mSkuVoiceQueueBTTS_Speaking[z].at) > tBttsSpeakingTtl then
						if dprint then dprint("BTTS SPEAKING-EXPIRE", "text=["..tostring(mSkuVoiceQueueBTTS_Speaking[z].text).."]") end
						table.remove(mSkuVoiceQueueBTTS_Speaking, z)
						tSweep = true
						break
					end
				end
			end
			local tLastReset
			for x = 1, #mSkuVoiceQueueBTTS do
				if mSkuVoiceQueueBTTS[x] == "queuereset" then
					tLastReset = x
				end
			end
			if tLastReset then
				for x = 1, tLastReset - 1 do
					--print("  Q R: ", x, mSkuVoiceQueueBTTS[1])
					table.remove(mSkuVoiceQueueBTTS, 1)
				end
			end
			-- BTTS diag (lag/stall hunt): surface a growing backlog. If the queue
			-- or the "currently speaking" dedup set climbs, the dequeue is stalling
			-- (FINISHED not clearing / lower-layer not draining).
			if dprint and (#mSkuVoiceQueueBTTS > 4 or #mSkuVoiceQueueBTTS_Speaking > 3) then
				dprint("BTTS DEPTH", "queue="..#mSkuVoiceQueueBTTS, "speaking="..#mSkuVoiceQueueBTTS_Speaking, "wait="..tostring(tLastWait))
			end
			if #mSkuVoiceQueueBTTS > 0 then
				--print("           ", tLastWait, mSkuVoiceQueueBTTS[1])
				local tValue = mSkuVoiceQueueBTTS[1]
				if tValue == "queuereset" then
						table.remove(mSkuVoiceQueueBTTS, 1)
						if ChatTts().neverResetQueues ~= true then
							if dprint then dprint("BTTS queuereset -> StopSpeakingText") end
							C_VoiceChat.StopSpeakingText()
						end
						mSkuVoiceQueueBTTS_Speaking = {}
						tLastWait = 0.10
				else
					if #mSkuVoiceQueueBTTS > 1 or tLastWait <= 0 then
						table.remove(mSkuVoiceQueueBTTS, 1)
						local tIsAlreadySpeakingThat
						for z = 1, #mSkuVoiceQueueBTTS_Speaking do
							--print(z, mSkuVoiceQueueBTTS_Speaking[z].text)
							if mSkuVoiceQueueBTTS_Speaking[z].text == tValue then
								tIsAlreadySpeakingThat = true
							end
						end
						if not tIsAlreadySpeakingThat then
							table.insert(mSkuVoiceQueueBTTS_Speaking, {text = tValue, at = GetTime()})
							-- Per-message voice override (nil => global voice). Same
							-- 1-based domain as WowTtsVoice, so the "- 1" API convention
							-- is identical whether the voice is per-channel or global.
							local tVoiceIndex = mSkuVoiceQueueBTTS_Voice[tValue] or ChatTts().WowTtsVoice
							-- BTTS diag: the EXACT string + params handed to WoW.
							if dprint then dprint("BTTS SpeakText", "voice="..tostring(tVoiceIndex - 1), "speed="..tostring(ChatTts().WowTtsSpeed), "vol="..tostring(ChatTts().WowTtsVolume), "text=["..tostring(tValue).."]") end
							-- Patch 12.0.0 (ported to the Anniversary client) REMOVED the
							-- `destination` arg from C_VoiceChat.SpeakText and added an
							-- optional `overlap`. New signature:
							--   SpeakText(voiceID, text, rate, volume [, overlap])
							-- The old call passed the now-dead destination (4) here, which
							-- shifted rate/volume by one and let the old volume land in the
							-- new `overlap` slot (truthy => overlap on). That mangled call
							-- made the engine speak "start"/"end" around every utterance and
							-- ignored the user's speed/volume. Proven on-client: Enum.
							-- VoiceTtsDestination is now nil and a clean 4-arg call speaks
							-- with no boundary words. overlap is omitted (defaults false) so
							-- Sku keeps driving its own queue without overlapping speech.
							C_VoiceChat.SpeakText(tVoiceIndex - 1, BttsCacheBust(tValue), ChatTts().WowTtsSpeed, ChatTts().WowTtsVolume)
						else
							-- BTTS diag: a queued line was DROPPED because an identical
							-- string is still flagged "speaking" (FINISHED never cleared it).
							-- Repeated drops here == the "goes silent" symptom.
							if dprint then dprint("BTTS DEDUP-SKIP", "speaking="..#mSkuVoiceQueueBTTS_Speaking, "text=["..tostring(tValue).."]") end
						end
						mSkuVoiceQueueBTTS_Voice[tValue] = nil
						--print("tLastWait = 0")
						tLastWait = 0.1
					else
						--print("tLastWait = 0.06")
						tLastWait = tLastWait - time

					end
				end
			end
		end

		fTime = fTime + time
		if fTime > 0.1 then
			fTime = 0
			--play everything that is not flagged for queuing (wait == true)
			for i = 1, table.getn(mSkuVoiceQueue) do
				if mSkuVoiceQueue[i].wait == false and not mSkuVoiceQueue[i].soundHandle then
					local willPlay, soundHandle = PlaySoundFile(mSkuVoiceQueue[i].file, mSkuVoiceQueue[i].soundChannel)
					if willPlay then
						SkuVoice.LastPlayedString = mSkuVoiceQueue[i].text
						mSkuVoiceQueue[i].soundHandle = soundHandle
						mSkuVoiceQueue[i].endTimestamp = GetTime() + mSkuVoiceQueue[i].length
					end
				end
			end

			--play everything that is flagged for dnq
			for i = 1, table.getn(mSkuVoiceQueue) do
				if mSkuVoiceQueue[i].dnq == true and not mSkuVoiceQueue[i].soundHandle then
					local willPlay, soundHandle = PlaySoundFile(mSkuVoiceQueue[i].file, mSkuVoiceQueue[i].soundChannel)
					if willPlay then
						SkuVoice.LastPlayedString = mSkuVoiceQueue[i].text
						mSkuVoiceQueue[i].soundHandle = soundHandle
						mSkuVoiceQueue[i].endTimestamp = GetTime() + mSkuVoiceQueue[i].length
					end
				end
			end		

			--check if there is something finished and should be tombstoned
			for i = 1, table.getn(mSkuVoiceQueue) do
				if mSkuVoiceQueue[i].soundHandle then
					if (GetTime() - mSkuVoiceQueue[i].endTimestamp) > 0 then
						mSkuVoiceQueue[i].tombstone = true
					end
				end
			end

			-- delete everything that is tombstoned
			local tIt = true
			while tIt == true do
				tIt = false
				for i, v in pairs(mSkuVoiceQueue) do
					if v.tombstone == true then
						--stop it first; just to be sure
						if v.soundHandle then
							StopSound(v.soundHandle, 0)
						end
						table.remove(mSkuVoiceQueue, i)
						tIt = true
					end
				end
			end

			--check if next could be played
			local tPlayNext = true
			for i = 1, table.getn(mSkuVoiceQueue) do
				if mSkuVoiceQueue[i].soundHandle and mSkuVoiceQueue[i].dnq ~= true then
					--is playing; check remaining time modifyed  by pause setting
					local tRemainingTime = (GetTime() - mSkuVoiceQueue[i].endTimestamp) + (mSkuVoiceQueue[i].length - (mSkuVoiceQueue[i].length * (SkuOptions.db.profile["SkuOptions"].TTSSepPause / 100)))
					if tRemainingTime < 0 then
						--nope
						tPlayNext = false
					end
				end
			end

			--it can play
			for i = 1, table.getn(mSkuVoiceQueue) do
				if not mSkuVoiceQueue[i].soundHandle and mSkuVoiceQueue[i].tombstone ~= true and tPlayNext == true and mSkuVoiceQueue[i].wait ~= false then
					local willPlay, soundHandle = PlaySoundFile(mSkuVoiceQueue[i].file, mSkuVoiceQueue[i].soundChannel)
					if willPlay then
						SkuVoice.LastPlayedString = mSkuVoiceQueue[i].text
						mSkuVoiceQueue[i].soundHandle = soundHandle
						mSkuVoiceQueue[i].endTimestamp = GetTime() + mSkuVoiceQueue[i].length
						tPlayNext = false
					else
						--there's something quite wrong with that entry
						mSkuVoiceQueue[i].tombstone = true
					end
				end
			end

		end

	end)

	return SkuVoice
end

---------------------------------------------------------------------------------------------------------
function SkuVoice:UtilRound(aNumber, aInterval)
	return (aInterval * math.floor( 10 * aNumber / aInterval ) / 10)
end

---------------------------------------------------------------------------------------------------------------------------------------
local function SplitStringBTTS(aString)
	--dprint("split:", aString, SkuAudioFileIndex[aString])
	if SkuAudioFileIndex[aString] then
		return aString
	end
	if aString == nil then
		return ""
	end

	if aString == "" then
		return aString
	end

	for i, v in pairs(tEmojis) do
		aString = string.gsub(aString, i, v)
	end
	
	aString = string.gsub(aString, "\r\n", ";")
	aString = string.gsub(aString, "\r", ";")
	aString = string.gsub(aString, "\n", ";")
	aString = string.gsub(aString, "\"", ";")
	--aString = string.gsub(aString, "\"", ";backslash;")
	if Sku.Loc == "deDE" then
		aString = string.gsub(aString, "'", ";")
	end
	--aString = string.gsub(aString, "%.", L[";punkt;"])
	aString = string.gsub(aString, ",", ";")
	--aString = string.gsub(aString, "%?", L[";fragezeichen;"])
	--aString = string.gsub(aString, "!", L[";ausrufungszeichen;"])
	aString = string.gsub(aString, "|", ";")
	aString = string.gsub(aString, "%[", ";")
	aString = string.gsub(aString, "%]", ";")
	aString = string.gsub(aString, "%+", ";")
	aString = string.gsub(aString, "%*", ";")
	aString = string.gsub(aString, "#", ";")
	aString = string.gsub(aString, "%-", ";")
	--aString = string.gsub(aString, ":", L[";doppelpunkt;"])
	--aString = string.gsub(aString, "&", ";und;")
	--aString = string.gsub(aString, "%%", L[";prozent;"])
	aString = string.gsub(aString, "/", L[";slash;"])
	aString = string.gsub(aString, "\\", ";\\;")
	--aString = string.gsub(aString, "%(", L[";klammer;"])
	--aString = string.gsub(aString, "%)", L[";klammer;"])
	--aString = string.gsub(aString, "=", L[";gleich;"])
	aString = string.gsub(aString, "<", L[";spitze;klammer;"])
	aString = string.gsub(aString, ">", L[";spitze;klammer;"])
	aString = string.gsub(aString, "	", ";")
	aString = string.gsub(aString, "  ", " ")
	aString = string.gsub(aString, " ", " ")
	aString = string.gsub(aString, ";;", ";")
	aString = string.lower(aString)

	if string.sub(aString, string.len(aString)) == ";" then
		aString = string.sub(aString, 1, string.len(aString)-1)
	end
	return aString
end

local function SplitString(aString)
	--dprint("split:", aString, SkuAudioFileIndex[aString])
	if SkuAudioFileIndex[aString] then
		return aString
	end
	if aString == nil then
		return ""
	end

	if aString == "" then
		return aString
	end
	aString = string.gsub(aString, "\r\n", ";")
	aString = string.gsub(aString, "\r", ";")
	aString = string.gsub(aString, "\n", ";")
	aString = string.gsub(aString, "\"", ";")
	--aString = string.gsub(aString, "\"", ";backslash;")
	if Sku.Loc == "deDE" then
		aString = string.gsub(aString, "'", ";")
	end
	aString = string.gsub(aString, "%.", L[";punkt;"])
	aString = string.gsub(aString, ",", ";")
	aString = string.gsub(aString, "%?", L[";fragezeichen;"])
	aString = string.gsub(aString, "!", L[";ausrufungszeichen;"])
	aString = string.gsub(aString, "|", ";")
	aString = string.gsub(aString, "%[", ";")
	aString = string.gsub(aString, "%]", ";")
	aString = string.gsub(aString, "%+", ";")
	aString = string.gsub(aString, "%*", ";")
	aString = string.gsub(aString, "#", ";")
	aString = string.gsub(aString, "%-", ";")
	aString = string.gsub(aString, ":", L[";doppelpunkt;"])
	aString = string.gsub(aString, "&", ";und;")
	aString = string.gsub(aString, "%%", L[";prozent;"])
	aString = string.gsub(aString, "/", L[";slash;"])
	aString = string.gsub(aString, "\\", ";\\;")
	aString = string.gsub(aString, "%(", L[";klammer;"])
	aString = string.gsub(aString, "%)", L[";klammer;"])
	aString = string.gsub(aString, "=", L[";gleich;"])
	aString = string.gsub(aString, "<", L[";spitze;klammer;"])
	aString = string.gsub(aString, ">", L[";spitze;klammer;"])
	aString = string.gsub(aString, "	", ";")
	aString = string.gsub(aString, "  ", " ")
	aString = string.gsub(aString, " ", ";")
	aString = string.gsub(aString, ";;", ";")
	aString = string.lower(aString)

	if string.sub(aString, string.len(aString)) == ";" then
		aString = string.sub(aString, 1, string.len(aString)-1)
	end
	return aString
end

---------------------------------------------------------------------------------------------------------------------------------------
local function Unescape(aString)
	local tResult = tostring(aString)
	tResult = gsub(tResult, "|n", ";") -- Remove color start.
	tResult = gsub(tResult, "|c........", "") -- Remove color start.
	tResult = gsub(tResult, "|r", "") -- Remove color end.
	tResult = gsub(tResult, "|H.-|h(.-)|h", "%1") -- Remove links.
	tResult = gsub(tResult, "|T.-|t", "") -- Remove textures.
	tResult = gsub(tResult, "{.-}", "") -- Remove raid target icons.
	return tResult
end

---------------------------------------------------------------------------------------------------------
function SkuVoice:GetLastPlayedString()
	return SkuVoice.LastPlayedString
end

---------------------------------------------------------------------------------------------------------
local tLinkIgnoreList = {
	L["Link History"],
	L["SkuNavMenuEntry"],
	L["SkuMobMenuEntry"],
	L["SkuChatMenuEntry"],
	L["SkuQuestMenuEntry"],
	L["SkuCoreMenuEntry"],
	L["SkuAurasMenuEntry"],
	L["SkuOptionsMenuEntry"],
	L["Links:"],
	L["Links"],
	L["Link History"],
	L["All entries"],
	L[" (Redirected from "],
	L["Links"],
	L["Wiki"],
	L["Options"],
	L["Parent quest"],
	L["Quests"],
	L["Close"],
	L["Loot roll"],
	L["Inspect"],
	L["Quest"],
	L["Taxi"],
	L["Gossip"],
	L["Merchant"],
	L["Popup 1"],
	L["Popup 2"],
	L["Popup 3"],
	L["Pet Stable"],
	L["Mail"],
	L["Bag 1"],
	L["Bag 2"],
	L["Bag 3"],
	L["Bag 4"],
	L["Bag 5"],
	L["Bag 6"],
	L["Dropdown List 2"],
	L["Dropdown List 1"],
	L["Talents"],
	L["Send Mail"],
	L["Auction house"],
	L["Class Trainer"],
	L["Character"],
	L["Reputation"],
	L["Skills"],
	L["Honor"],
	L["Bagnon Taschen"],
	L["Spellbook"],
	L["Player Talents"],
	L["Friends"],
	L["Trade"],
	L["Game Menu"],
	L["Bagnon Bank"],
	L["Bagnon Guild"],
	L["Bank"],
	L["Guild Bank"],
	L["Panel"],
	L["Sub panel"],
	L["Details"],
	L["Details panel"],
	L["Sub panel"],
	L["Rewards"],
	L["Money"],
	L["Attributes"],
	L["Resistance"],
	L["Items"],
	L["Progress"],
	L["Container"],
	L["Text"],
	L["Button"],
	L["Sent"],
	L["Send failed"],
	L["Enter text and press ENTER key"],
	L["Recepient missing"],
	L["Topic missing"],
	L["Auto follow"],
	L["Hunter"],
	L["Notice on pet starving"],
	L["Left Multi Bar"],
	L["Right Multi Bar"],
	L["Bottom Multi Bar Left"],
	L["Bottom Multi Bar Right"],
	L["Main Action Bar"],
	L["Pet Action Bar"],
	L["Stance Action Bar"],
	L["Macros"],
	L["Menu empty"],
	L["Assign nothing"],
	L["Macro"],
	L["Key"],
}
function SkuVoice:CheckIgnore(aString)
	for i, v in pairs(tLinkIgnoreList) do
		if aString == v then
			return true
		end
		if string.find(v, aString) then
			return true
		end
	end
end

---------------------------------------------------------------------------------------------------------
-- [W6-B #19] Shared number-to-audio tokenizer for the two live speech paths
-- (OutputStringBTtts and OutputString). Appends the audio tokens for ONE
-- already-split, numeric field into aStrings. Was copy-pasted (and drifted) in
-- both paths plus the now-deleted dead CollectString. aMode preserves the two
-- paths' historically DIFFERENT number handling verbatim:
--   "btts"  (Blizzard-TTS path): skips fields containing "." or "," and does
--           NOT tokenize floats (Blizzard TTS voices decimals itself); a value
--           above 13000 is dropped (no audio file for it).
--   "audio" (Sku audio-file path): tokenizes a float as integer + Komma +
--           fraction; a value above 13000 falls through the rounding ladder.
-- The float difference is deliberate; the >13000 divergence is legacy and kept
-- as-is here (behavior-preserving) - a future by-ear pass may unify it.
function SkuVoice:TokenizeNumberToAudio(aToken, aStrings, aVocalizeAsIs, aMode)
	if not aVocalizeAsIs then
		if aMode == "btts" and (string.find(tostring(aToken), "%.") or string.find(tostring(aToken), ",")) then
			return
		end
		local tFloatNumber = string.format("%.1f", tonumber(aToken))
		if tonumber(tFloatNumber) < 1000000 then
			if (tFloatNumber - string.format("%d", tFloatNumber)) > 0 then
				--float
				if aMode == "audio" then
					local tIVal = string.format("%d", tFloatNumber)
					local tFVal = string.format("%d", string.format("%.1f", (tFloatNumber - tIVal) * 10))
					table.insert(aStrings, tIVal)
					table.insert(aStrings, L["Komma"])
					table.insert(aStrings, tFVal)
				end
				-- "btts": the decimal is left for Blizzard TTS to voice, not tokenized
			else
				--int
				local tNumber = math.floor(tonumber(aToken))
				if tNumber == 0 then
					table.insert(aStrings, 0)
				else
					local tRemaining = tNumber
					if tNumber > 13000 and aMode == "btts" then
						--no audio available: drop it
						tRemaining = 0
						tNumber = 0
					end
					if tNumber > 999 then
						local tRound = SkuVoice:UtilRound(tRemaining, 10000)
						table.insert(aStrings, tRound)
						tRemaining = tRemaining - tRound
					end
					if tRemaining > 99 then
						local tRound = SkuVoice:UtilRound(tRemaining, 1000)
						table.insert(aStrings, tRound)
						tRemaining = tRemaining - tRound
					end
					if tRemaining > 0 then
						table.insert(aStrings, tRemaining)
					end
				end
			end
		end
	else
		for z = 1, string.len(aToken) do
			table.insert(aStrings, string.sub(aToken, z, z))
		end
	end
end

---------------------------------------------------------------------------------------------------------
function SkuVoice:OutputStringBTtts(aString, aOverwrite, aWait, aLength, aDoNotOverwrite, aIsMulti, aSoundChannel, engine, aSpell, aVocalizeAsIs, aInstant, aDnQ, aIgnoreLinks, aIsTutorial, aVoice)
	if not aString then
		return
	end

	--changing to a new approach with passing a table of arguments instead of a lot of values, but still need to update that everywhere
	if type(aOverwrite) == "table" then
		aWait = aOverwrite.wait
		aLength = aOverwrite.length
		aDoNotOverwrite = aOverwrite.doNotOverwrite
		aIsMulti = aOverwrite.isMulti
		aSoundChannel = aOverwrite.soundChannel
		engine = aOverwrite.engine
		aSpell = aOverwrite.spell
		aVocalizeAsIs = aOverwrite.vocalizeAsIs
		aInstant = aOverwrite.instant
		aDnQ = aOverwrite.dnQ
		aIgnoreLinks = aOverwrite.ignoreLinks
		aIsTutorial = aOverwrite.isTutorial
		-- Optional per-message Blizzard-TTS voice (1-based index into
		-- SkuChat.WowTtsVoices). Attached to the queued string below so the
		-- dequeue can pick it instead of the global voice.
		aVoice = aOverwrite.voice
		aOverwrite = aOverwrite.overwrite
	end

	--SkuNav:NavigationModeWoCoordinatesCheckTaskTrigger(aString)

	--strip object numbers
	aString = string.gsub(aString, L["OBJECT"]..";%d+;", L["OBJECT"]..";")


	if SkuVoice:CheckIgnore(aString) then
		aIgnoreLinks = true
	end

	if SkuOptions.db.profile["SkuOptions"].useBlizzTtsInMenu ~= true and not engine and ChatTts().allChatViaBlizzardTts ~= true then
		SkuVoice:OutputString(aString, aOverwrite, aWait, aLength, aDoNotOverwrite, aIsMulti, aSoundChannel, engine, aSpell, aVocalizeAsIs, aInstant, aDnQ, aIgnoreLinks)
		return
	end

	aDnQ = aDnQ or false

	if aVocalizeAsIs then
		aString = string.gsub(aString, "%-", "minus ")
	end


	-- Ellipsis: leave "..." raw so NVDA/SAPI apply their own pronunciation. (The
	-- old code expanded it into three localized "period" word-tokens, so a
	-- screen-reader received the literal words "Punkt Punkt Punkt" instead of an
	-- ellipsis and never got to apply its ellipsis rule. This is the Blizzard-TTS
	-- path only; the audio-file TTS returns earlier and keeps its own handling.)

	local tString = ""
	if aSpell == true then
		aString = string.lower(aString)
		for tChr in aString:gmatch("[\33-\127\192-\255]?[\128-\191]*") do
			tString = tString..tChr..";"
		end
		while string.find(tString, ";;") do
			tString = string.gsub(tString, ";;", ";")
		end
		aString = tString
	end


	-- don't vocalize numbers > 20000 or floats
	-- that is for the unique auto wp ids and the coords; we don't want hear them, but we still need them in the wp names
	if not aVocalizeAsIs then
		local tNumberTest = tonumber(aString)
		if tNumberTest then
			local tFloat = math.floor(tNumberTest)
			if (tNumberTest > 20000) or (tNumberTest - tFloat > 0) then
				return
			end
		end
	end

	--empty the queue
	if aOverwrite == true and ChatTts().neverResetQueues ~= true then
		mSkuVoiceQueueBTTS[#mSkuVoiceQueueBTTS + 1] = "queuereset"
		--print("ADD RESET TO QUEUE")
		--[[
		local tIt = true
		while tIt == true do
			tIt = false
			for i, v in pairs(mSkuVoiceQueue) do
				if v.doNotOverwrite ~= true then
					--stop it first; just to be sure
					if v.soundHandle then
						StopSound(v.soundHandle, 0)
					end
					table.remove(mSkuVoiceQueue, i)
					tIt = true
				end
			end
		end
		]]
--[[
		if IsMacClient() == true then
			C_VoiceChat.StopSpeakingText()
		else
			print("C_VoiceChat.StopSpeakingText()")
			C_VoiceChat.StopSpeakingText()
		end
]]
	end

	--remove escape markup
	while string.find(aString, "|n") do
		aString = string.gsub(aString, "|n", ";")
	end
	while string.find(aString, "|") do
		aString = string.gsub(aString, "|", " ")
	end

	aString = Unescape(aString)
	aString = aString:gsub("\"", "")

	local tStrings = {}
	if (string.find(aString, "sound-") or string.find(aString, "male%-")) then
		table.insert(tStrings, aString)
	else
		aString = string.lower(aString)
		aString= SplitStringBTTS(aString)

		local sep, tSplittedString = ";", {}
		if type(aString) == "string" then
			local pattern = string.format("([^%s]+)", sep)
			aString:gsub(pattern, function(c) tSplittedString[#tSplittedString+1] = c end)
		else
			tSplittedString = {aString}
		end

		for x = 1, #tSplittedString do
			if tonumber(tSplittedString[x]) then
				SkuVoice:TokenizeNumberToAudio(tSplittedString[x], tStrings, aVocalizeAsIs, "btts")
			else
				table.insert(tStrings, tSplittedString[x])
			end
		end
	end

	local tFinalStringForBTts = ""
	local tFinalStringForBTtsMac = ""

	for x = 1, #tStrings do
		-- §01 is a pause/separation marker. Render it as a comma: a NATURAL
		-- prosodic pause that also keeps words apart on every voice. (The old
		-- WowTtsTags "on" path emitted <silence msec="100"/> instead, which felt
		-- robotic on real SAPI voices and — because a screen-reader bridge can't
		-- honor a silence fragment — dropped the separator entirely and merged
		-- words on NVDA. That setting is removed; the Sku audio-file TTS keeps its
		-- own §01 handling elsewhere.)
		tStrings[x] = string.gsub(tStrings[x], "§01", ', ')

		--unmask bnet names
		tStrings[x] = string.gsub(tStrings[x], "$skuk1", "|K")
		tStrings[x] = string.gsub(tStrings[x], "$skuk2", "|k")

		tStrings[x] = string.gsub(tStrings[x], "§", " ")
		--dprint(" final",x, tStrings[x])

		if (string.find(tStrings[x], "sound%-") or string.find(tStrings[x], "male%-")) then
			--dprint("  FIND SOUND", tStrings[x])
			SkuVoice:OutputString(tStrings[x], aOverwrite, aWait, aLength, aDoNotOverwrite, aIsMulti, aSoundChannel, engine, aSpell, aVocalizeAsIs, aInstant, aDnQ, aIgnoreLinks) -- for strings with lookup in string index
		else
			if (string.find(tStrings[x], "aura;sound")) then
				--tFinalStringForBTts = tFinalStringForBTts..'<silence msec="500"/>'..tStrings[x]
			end

			-- Join segments with a real space so every voice (real SAPI + bridge)
			-- gets a genuine word boundary. (Was <silence> under WowTtsTags on.)
			tFinalStringForBTts = tFinalStringForBTts..' '..tStrings[x]
			tFinalStringForBTtsMac = tFinalStringForBTtsMac.." "..tStrings[x]

		end

		--[[
		aWait = aWait or false
		aDoNotOverwrite = aDoNotOverwrite or false
		aSoundChannel
		aDnQ
		]]
	end

	if aVocalizeAsIs then
		tFinalStringForBTts = aString
		tFinalStringForBTtsMac = aString
	end

	--tFinalStringForBTts = '<voice required="Language='..SapiLangIds[Sku.Loc]..'">'..tFinalStringForBTts..'</LANG>'
	--tFinalStringForBTts = '<LANG LANGID="'..SapiLangIds[Sku.Loc]..'">'..tFinalStringForBTts..'</LANG>'
	-- (dropped the '<pitch middle="0">' wrapper: middle=0 is neutral, a no-op.)

	tFinalStringForBTts = string.gsub(tFinalStringForBTts, ";", " ")
	tFinalStringForBTtsMac = string.gsub(tFinalStringForBTtsMac, ";", " ")

	if IsMacClient() == true then
		if aInstant then
			mSkuVoiceQueueBTTS[#mSkuVoiceQueueBTTS + 1] = tFinalStringForBTtsMac
		else
			mSkuVoiceQueueBTTS[#mSkuVoiceQueueBTTS + 1] = tFinalStringForBTtsMac
		end
		if aVoice then
			mSkuVoiceQueueBTTS_Voice[tFinalStringForBTtsMac] = aVoice
		end
		if not aIgnoreLinks then
			SkuOptions.TTS:GetLinksTableFromString(tFinalStringForBTtsMac, "")
		end
	else
		if aInstant then
			mSkuVoiceQueueBTTS[#mSkuVoiceQueueBTTS + 1] = tFinalStringForBTts
		else
			mSkuVoiceQueueBTTS[#mSkuVoiceQueueBTTS + 1] = tFinalStringForBTts
		end
		if aVoice then
			mSkuVoiceQueueBTTS_Voice[tFinalStringForBTts] = aVoice
		end

		if not aIgnoreLinks then
			SkuOptions.TTS:GetLinksTableFromString(tFinalStringForBTts, "")
		end

		--print(tFinalStringForBTts)
	end



end

---------------------------------------------------------------------------------------------------------
---@param aString string
---@param aOverwrite boolean
---@param aWait boolean
function SkuVoice:OutputString(aString, aOverwrite, aWait, aLength, aDoNotOverwrite, aIsMulti, aSoundChannel, engine, aSpell, aVocalizeAsIs, aInstant, aDnQ, aIgnoreLinks, aIsTutorial, aAudioFile) -- for strings with lookup in string index
	if not aString then
		return
	end

	--print("OutputString", aString)

	if type(aOverwrite) == "table" then
		aWait = aOverwrite.wait
		aLength = aOverwrite.length
		aDoNotOverwrite = aOverwrite.doNotOverwrite
		aIsMulti = aOverwrite.isMulti
		aSoundChannel = aOverwrite.soundChannel
		engine = aOverwrite.engine
		aSpell = aOverwrite.spell
		aVocalizeAsIs = aOverwrite.vocalizeAsIs
		aInstant = aOverwrite.instant
		aDnQ = aOverwrite.dnQ
		aIgnoreLinks = aOverwrite.ignoreLinks
		aIsTutorial = aOverwrite.isTutorial
		aAudioFile = aOverwrite.audioFile
		aOverwrite = aOverwrite.overwrite
	end
	
	--we need to skip checks, etc. for sounds to get better performance on aura output
	local tIsSound
	if string.sub(aString, 1, 6) == "sound-" then
		tIsSound = true
	end

	-- [SOUND-PROBE] TEMPORARY diagnostic: log every sound-* asset played (e.g.
	-- sound-off2, sound-on3_1) with a short caller stack, so we can see exactly
	-- which feature fires the "follow/off" ping on menu open. Gated behind the
	-- Sku.debug.log flag (dprint). Remove this block (grep SOUND-PROBE) when done.
	if tIsSound and dprint then
		dprint("[SOUND-PROBE] sound", aString, debugstack(2, 3, 0))
	end

	if not tIsSound then
		if SkuVoice:CheckIgnore(aString) then
			aIgnoreLinks = true
		end

		aDnQ = aDnQ or false

		local tString = ""
		if aSpell == true then
			aString = string.lower(aString)
			for tChr in aString:gmatch("[\33-\127\192-\255]?[\128-\191]*") do
				tString = tString..tChr..";"
			end
			while string.find(tString, ";;") do
				tString = string.gsub(tString, ";;", ";")
			end
			aString = tString
		end


		if not (string.find(aString, "sound%-") or string.find(aString, "male%-") or string.find(aString, "brian%-") or string.find(aString, "emma%-")) and ChatTts().allChatViaBlizzardTts == true then
			SkuVoice:OutputStringBTtts(aString, aOverwrite, aWait, aLength, aDoNotOverwrite, aIsMulti, aSoundChannel, engine, aSpell, aVocalizeAsIs, aInstant, aDnQ, aIgnoreLinks) -- for strings with lookup in string index
			return
		end


		aSoundChannel = aSoundChannel or SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel or "Talking Head"

		aIsMulti = aIsMulti or false
		if string.find(aString, ";") then
			aIsMulti = true
		end

		if not aString or not SkuAudioDataLenIndex or not SkuAudioFileIndex then
			return
		end
		if aString == "" then
			return
		end
	else
		aSoundChannel = aSoundChannel or SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel or "Talking Head"
	end

	-- [W6-B #20 / Bug 4] the engine (force-Blizzard-TTS) branch here was fully
	-- commented out, so a truthy `engine` fell through to an empty `then` and
	-- SILENTLY MUTED the caller. OutputString is the Sku audio-file path; the
	-- Blizzard-TTS force path lives in OutputStringBTtts. Dropped the dead guard
	-- so this always runs the real audio output (behavior-preserving: callers
	-- reach here with engine falsy today; a truthy engine now plays audio
	-- instead of muting).
	do
		if not tIsSound then
			-- don't vocalize numbers > 20000 or floats
			-- that is for the unique auto wp ids and the coords; we don't want hear them, but we still need them in the wp names
			if not aVocalizeAsIs then
				local tNumberTest = tonumber(aString)
				if tNumberTest then
					local tFloat = math.floor(tNumberTest)
					if (tNumberTest > 20000) or (tNumberTest - tFloat > 0) then
						return
					end
				end
			end
		end

		--empty the queue
		if aOverwrite == true then
			--[[
			for i = 1, table.getn(mSkuVoiceQueue) do
				if mSkuVoiceQueue[i] then
					if mSkuVoiceQueue[i].soundHandle then
						StopSound(mSkuVoiceQueue[i].soundHandle)
					end
				end
			end
			mSkuVoiceQueue = {}
			]]
			local tIt = true
			while tIt == true do
				tIt = false
				for i, v in pairs(mSkuVoiceQueue) do
					if v.doNotOverwrite ~= true or v.text == aString then
						--stop it first; just to be sure
						if v.soundHandle then
							StopSound(v.soundHandle, 0)
						end
						--mSkuVoiceQueue[i] = nil
						table.remove(mSkuVoiceQueue, i)
						tIt = true
					end
				end
			end
		end

		if not tIsSound then
			while string.find(aString, "|n") do
				aString = string.gsub(aString, "|n", ";")
			end
			while string.find(aString, "|") do
				aString = string.gsub(aString, "|", " ")
			end

			aString = Unescape(aString)
			aString = aString:gsub("\"", "")

			--collect links
			if not aIgnoreLinks then
				SkuOptions.TTS:GetLinksTableFromString(aString:gsub(";", " "), "")
			end
		end

		local tStrings = {}
		if (string.find(aString, "sound-") or string.find(aString, "male%-") or string.find(aString, "brian%-") or string.find(aString, "emma%-")) then
			local a, b = string.find(aString, "sound-")
			if not b then
				a, b = string.find(aString, "male%-")
				if not b then
					a, b = string.find(aString, "brian%-")
					if not b then
						a, b = string.find(aString, "emma%-")
					end
				end
			end
			if b == nil then
				table.insert(tStrings, aString)
			else
				local tSplittedString = {}
				local pattern = string.format("([^%s]+)", ";")
				aString:gsub(pattern, function(c) tSplittedString[#tSplittedString+1] = c end)
				for x = 1, #tSplittedString do
					table.insert(tStrings, tSplittedString[x])
				end
			end
		else
			aString = string.lower(aString)
			aString = SplitString(aString)

			local sep, tSplittedString = ";", {}
			if type(aString) == "string" then
				local pattern = string.format("([^%s]+)", sep)
				aString:gsub(pattern, function(c) tSplittedString[#tSplittedString+1] = c end)
			else
				tSplittedString = {aString}
			end

			for x = 1, #tSplittedString do
				if tonumber(tSplittedString[x]) then
					SkuVoice:TokenizeNumberToAudio(tSplittedString[x], tStrings, aVocalizeAsIs, "audio")
				else
					table.insert(tStrings, tSplittedString[x])
				end
			end
		end

		for x = 1, #tStrings do
			local tFile, tPath, tLength

			if not tIsSound then
				if tStrings[x] == "§01" then
					tStrings[x] = "sound-silence0.1"
				end
				tFile, tPath, tLength = SkuVoice:GetAudiodata(tostring(tStrings[x]))

				if tFile == nil then
					local tModString = string.lower(tostring(tStrings[x]))
					tFile, tPath, tLength = SkuVoice:GetAudiodata(tModString)
				end
				if tFile == nil then
					local tModString = string.upper(string.sub(tostring(tStrings[x]),1,1))..string.sub(tostring(tStrings[x]),2)
					tFile, tPath, tLength = SkuVoice:GetAudiodata(tModString)
				end
				--dprint(tStrings[x], "tFile", tFile)

				if tFile == nil then
					local tModString = string.lower(tostring(tStrings[x]))
					for i, v in pairs(tGenderSuffixes) do
						if string.sub(tModString, string.len(tModString) - string.len(i) + 1) == i then
							tFile, tPath, tLength = SkuVoice:GetAudiodata(string.sub(tModString, 1, string.len(tModString) - string.len(i))..v)
						end
					end
				end

				if tFile == nil then
					tFile, tPath, tLength = SkuVoice:GetAudiodata("sound-audiofehltbeep")
					if SkuOptions.db then
						if SkuOptions.db.realm.missingAudio == nil then
							SkuOptions.db.realm.missingAudio = {}
						end
						if not SkuOptions.db.realm.missingAudio[tStrings[x]] then
							SkuOptions.db.realm.missingAudio[tStrings[x]] = 1
						else
							SkuOptions.db.realm.missingAudio[tStrings[x]] = SkuOptions.db.realm.missingAudio[tStrings[x]] + 1
						end
					end
				end
			else
				tFile, tPath, tLength = SkuVoice:GetAudiodata(tStrings[x])
			end

			if aAudioFile ~= nil then
				tFile = aAudioFile
			end

			if tFile then
				if tFile ~= "" then
					tLength = tLength or aLength

					--if isMulti == true then
						--tLength = tLength - ((100 - tonumber(SkuOptions.db.profile["SkuOptions"].TTSSepPause)) / 100) -- - 0.15
					--end

					if aAudioFile == nil then
						tFile = tPath..tFile
					end
					aOverwrite = aOverwrite or false
					aWait = aWait or false
					tLength = tLength or 0
					if x == 1 then
						--[[if overwrite == true then
							for i = 1, table.getn(SkuVoiceQueue) do
								if SkuVoiceQueue[i].soundHandle then
									StopSound(SkuVoiceQueue[i].soundHandle)
								end
							end
							SkuVoiceQueue = {}
						end]]
					end
					if x > 1 then
						aWait = true
					end

					if aInstant == true then
						table.insert(mSkuVoiceQueue, 0 + x, {
							["text"] = tStrings[x],
							["file"] = tFile,
							["wait"] = aWait,
							["length"] = tLength,
							["endTimestamp"] = 0,
							["soundHandle"] = nil,
							["doNotOverwrite"] = aDoNotOverwrite or false,
							["soundChannel"] = aSoundChannel,
							["dnq"] = aDnQ,
						})
					else
						table.insert(mSkuVoiceQueue, {
							["text"] = tStrings[x],
							["file"] = tFile,
							["wait"] = aWait,
							["length"] = tLength,
							["endTimestamp"] = 0,
							["soundHandle"] = nil,
							["doNotOverwrite"] = aDoNotOverwrite or false,
							["soundChannel"] = aSoundChannel,
							["dnq"] = aDnQ,
						})
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------
function SkuVoice:StopOutputEmptyQueue(aBlizz, aSku)
	if ChatTts().neverResetQueues == true then
		return
	end

	if not aBlizz and not aSku then
		aBlizz, aSku = true, true
	end
	if aSku then
		for i = 1, table.getn(mSkuVoiceQueue) do
			if mSkuVoiceQueue[i] then
				if mSkuVoiceQueue[i].soundHandle then
					StopSound(mSkuVoiceQueue[i].soundHandle)
				end
			end
		end
		mSkuVoiceQueue = {}
	end
	if aBlizz then
		mSkuVoiceQueueBTTS_Speaking = {}
		C_VoiceChat.StopSpeakingText()
	end
end
-- [W6-B #20] dead SkuVoice:StopAllOutputs removed (was entirely inside a
-- --[[ ]] block, never defined, referenced an undefined tValue, called nowhere).
---------------------------------------------------------------------------------------------------------
function SkuVoice:Release()

end

---------------------------------------------------------------------------------------------------------
function SkuVoice:GetAudiodata(aString)
	tFile = nil
	tPath = nil
	tLen = nil
	
	if SkuAudioFileIndexIntegrated[Sku.Loc][aString] ~= nil then
		tFile = SkuAudioFileIndexIntegrated[Sku.Loc][aString]
		tPath = Sku:IntegratedAudioDir()
		tLen = SkuAudioDataLenIndexIntegrated[Sku.Loc][SkuAudioFileIndexIntegrated[Sku.Loc][aString]]
	end

	if tFile == nil then
		-- W5: Pfad über den Resolver; ohne installiertes Sprachpaket (Dir nil oder
		-- Index nil) bleibt tFile nil und der Aufrufer fällt auf TTS zurück.
		local tPackDir = Sku:VoicePackAudioDir()
		if tPackDir and SkuAudioFileIndex and SkuAudioFileIndex[aString] ~= nil then
			tFile = SkuAudioFileIndex[aString]
			tPath = tPackDir
			tLen = SkuAudioDataLenIndex[SkuAudioFileIndex[aString]]
		end
	end

	if tFile == nil then
		dprint("GetAudiodata: no audio file for:", aString)
	end

	return tFile, tPath, tLen
end

