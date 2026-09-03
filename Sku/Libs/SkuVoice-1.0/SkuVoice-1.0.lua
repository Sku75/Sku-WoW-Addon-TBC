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
	["frFR"] = 1036, -- [v42.09 i18n] only read by the commented-out SSML wrapper
	                 -- below, but it is indexed as SapiLangIds[Sku.Loc], so it
	                 -- would nil out the moment that code is revived.
	}

---------------------------------------------------------------------------------------------------------
SkuVoice.LastPlayedString = ""
SkuVoice.TutorialPlaying = 0
--setmetatable(mSkuVoiceQueue, SkuNav.PrintMT)

---------------------------------------------------------------------------------------------------------

local mSkuVoiceQueue = {}
-- [v43.0] Set by every OutputString append to mSkuVoiceQueue; makes the audio
-- pump run its body on the NEXT frame instead of waiting for its 0.1 s cadence.
--
-- The pump body was gated on `fTime > 0.1` only, and OutputString never plays
-- anything itself, so a freshly queued sound waited a uniformly distributed
-- 0-100 ms (~50 ms average) before PlaySoundFile was even called -- on EVERY Sku
-- sound, aura beeps included. Nothing about the queue's ORDER or its play rules
-- changes here: the same five passes run in the same sequence, they just stop
-- waiting for the tick. Latency floor becomes one frame (~16 ms at 60 fps),
-- which is what WeakAuras achieves by calling PlaySoundFile straight from its
-- event handler.
local mQueueDirty = false
-- [v43.0] Same-frame cursor for aInstant FRONT-inserts (aura word outputs).
-- Every instant insert this frame goes to mInstantInsertPos+1, so an aura
-- firing several output fields (one OutputString call each) keeps its fields in
-- SPOKEN order — the old `0 + x` position made every later call land at
-- position 1 and reversed the fields. Frame identity via GetTime() (constant
-- within a frame); nothing removes queue entries between the synchronous calls
-- of one evaluation pass (the pump and its tombstone sweep run in OnUpdate),
-- except the aOverwrite clear inside OutputString itself, which re-clamps the
-- cursor right after it runs.
local mInstantInsertPos = 0
local mInstantInsertTime = -1
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
-- [v43.2] "This line was caused by a key the user just pressed." Same side-map
-- shape as the voice override above, and for the same reason: the queue entries
-- must stay plain strings.
--
-- It exists because the back-to-back duplicate guard (tBttsDupWindow, below)
-- cannot tell two identical strings apart by looking at them, and the two cases
-- it has to separate mean OPPOSITE things:
--   * a menu node re-announced by a redundant CheckFrames/restage pass -- nobody
--     asked for it, suppress it (that is what the guard was written for);
--   * the same node announced again because the user pressed a key -- they asked
--     for it, speaking it is the whole point.
-- No timing window separates those; only the producer knows. So the ONE keypress
-- funnel (SkuZOptions/Core.lua, the menu key handler) tags its announce and the
-- guard never suppresses a tagged line. Every other producer stays untagged and
-- keeps exactly today's behaviour.
--
-- Keyed by TEXT, like the voice map, and inheriting the same known weakness: if
-- two producers emit the identical string and only one tagged it, the tag
-- applies to whichever entry dequeues. The failure that causes is a redundant
-- repeat being spoken instead of suppressed -- i.e. it degrades to the
-- pre-v43.2 behaviour, never to silence. That is the right direction to fail in,
-- which is why it is not worth a parallel structured queue.
local mSkuVoiceQueueBTTS_UserAction = {}

-- [v42.13] Pump pacing state, hoisted out of SkuVoice:Create's closure so
-- SkuVoice:CancelBttsOutput (below) can arm the same hold the queuereset branch
-- uses. Semantics unchanged; see the long comment in Create.
--   tNextSpeakAt: GetTime() before which no new utterance may be handed to
--                 C_VoiceChat.SpeakText.
--   tLastStopAt:  GetTime() of the last StopSpeakingText this pump issued.
local tNextSpeakAt = 0
local tLastStopAt = 0

-- [v43.2] Back-to-back duplicate guard -- the one dedup that also works on the
-- screen-reader bridge.
--
-- The existing dedup (mSkuVoiceQueueBTTS_Speaking, below) asks "is an identical
-- string still playing?" and is drained by VOICE_CHAT_TTS_PLAYBACK_FINISHED. With
-- a real SAPI voice that set stays populated for the whole utterance, so the guard
-- works. With the NVDA/SAPI2SR bridge the client hands the text over and fires
-- STARTED + FINISHED in the SAME frame, so the set is ALWAYS empty by the time the
-- next line arrives: on the bridge that dedup can never fire at all.
--
-- What that costs, measured over a 95-minute capture (1512 utterances): 95 of them
-- were an exact repeat of the line immediately before, inside one second -- the
-- focused menu node re-announced by a redundant CheckFrames/restage pass. Each
-- repeat is preceded by its own "queuereset", i.e. a StopSpeakingText, and a stop
-- DOES reach NVDA. So the audible result is: line starts, gets cut mid-word,
-- restarts, gets cut again -- and if any link in that chain drops the resend (WoW
-- 12.0 also caches synthesized audio by text) the user is left in silence with
-- nothing to replace it. That is the "arrow press reads nothing and it stays quiet"
-- report.
--
-- The guard compares only against the utterance handed over IMMEDIATELY before, so
-- it cannot eat a real re-read: arrowing down and back up puts a different line in
-- between and resets the marker. Only a literal back-to-back repeat is dropped, and
-- the reset in front of it is dropped WITH it -- suppressing the text alone would
-- still cancel the line that is currently being spoken and leave nothing behind.
local tLastHandedText = nil
local tLastHandedAt = 0
local tLastHandedStarted = false
local tBttsDupWindow = 1.0

-- [v43.2] The pump's two holds, named so they sit in ONE place and can be read
-- back by /skudebug tts.
--
-- WHY A HOLD EXISTS AT ALL -- the thing that is easy to get backwards: it does
-- NOT keep utterances apart. Separation comes from the client, which is handed
-- each line with `overlap` false and speaks them in order. Remove the holds and
-- speech does not merge into one blob; what breaks is the opposite.
--
-- A screen reader's own API takes the interrupt as part of the speak call --
-- Speak(text, interrupt) -- so replacing what is playing is ONE atomic
-- operation and needs no pacing anywhere. C_VoiceChat has no such parameter:
-- SpeakText(voiceID, text, rate, volume [, overlap]) cannot cancel, and
-- StopSpeakingText is a separate ASYNCHRONOUS call with no completion signal.
-- So Sku has to emulate one atomic operation with two racing ones, and
-- tBttsPostStopHold is the gap that stops the stop from landing on -- and
-- killing -- the very line it was issued to make room for. That race is real
-- and measured: see the comment at the queuereset branch below.
--
-- tBttsPostSpeakHold is the weaker of the two. It only ever delays a LONE queued
-- line (the `#queue > 1` bypass skips it otherwise) and its one real effect is
-- coalescing: while a line waits, a newer overwrite can prune it before it is
-- ever spoken. Inherited from the audio-file pump, where the same cadence has a
-- genuine clip-sequencing job that does not apply here.
--
-- ★MEASURED 2026-08-29, and 0.1 STAYS. Both numbers were inherited from the
-- audio-file pump and had never been checked, so they were measured properly
-- (gap histogram, see tAuditGap): one session run at `/skudebug tts hold 0 0`,
-- 233 handovers, 191 of them following a stop. Result:
--
--   0-9 ms:    2 samples, 0 lost
--   10-19 ms: 85 samples, 1 LOST      <- the async-stop race, exactly here
--   20-29 ms: 93 samples, 0 lost
--   30-39 ms:  7 samples, 0 lost
--   40-49 ms:  3 samples, 0 lost
--
-- Three things came out of that, all worth keeping written down:
--
-- 1. Setting the hold to 0 does NOT produce a 0 ms gap -- it produces ~10-30 ms
--    (93% of samples). The real floor is the pump's own `fTimeBTTS > 0.01` gate
--    plus the fact that a queuereset and its text are handled in SEPARATE pump
--    passes. The hold is not what creates the gap; it only widens it.
-- 2. So removing the hold saves ~80 ms per interrupted announcement, not 100.
--    Play-tested at 0: the reporter could not tell the difference. 80 ms of
--    speech-onset latency is below the perceptual threshold here, with the
--    bridge's own startup on top of it.
-- 3. The price of those 80 ms is the one loss above -- 1 in 233 handovers, where
--    two sessions at 0.1 s lost 0 in 358. For a screen-reader user a silently
--    dropped announcement is far worse than latency nobody can feel.
--
-- Hence: keep 0.1. Not because it was inherited, but because an imperceptible
-- gain is not worth a rare silent loss. Do not reopen without new evidence --
-- `/skudebug tts` reproduces the measurement.
local tBttsPostStopHold = 0.10
local tBttsPostSpeakHold = 0.10

-- [v43.2] Handover audit for tuning the two holds above. Counters only, no
-- strings kept; read with /skudebug tts, reset with /skudebug tts reset.
--   handed:        utterances passed to C_VoiceChat.SpeakText
--   started:       PLAYBACK_STARTED events received
--   superseded:    handed, then deliberately cancelled by a stop before playback
--                  began. NORMAL -- it is what fast arrowing and "typing cancels
--                  the announcement" look like from here. Informational only.
--   lost:          ★THE number. Handed, NOT superseded, and still no STARTED
--                  after tBttsAuditLostAfter. Nothing cancelled it and it never
--                  played -- i.e. the async stop landed on it. That, and only
--                  that, says tBttsPostStopHold is too short.
--   failed:        PLAYBACK_FAILED -- a refusal with a known cause, never `lost`
--   dupSuppressed: back-to-back duplicates dropped by the guard
--   userAction:    repeats spared because a keypress asked for them
--   echo:          characters handed over through the typing fast lane
--
-- ★The distinction is the whole point, and the first version of this audit got
-- it wrong: it counted every handover that had not started yet when the next one
-- arrived. In a real capture all three hits were benign -- two correct supersedes
-- (arrow pressed again, typing started) and one echo character that was NOT
-- cancelled at all and played perfectly well, because the echo path issues no
-- stop between characters and the client simply queues both. A figure that
-- counts normal operation cannot justify changing a safety hold.
local tBttsStats = {handed = 0, started = 0, superseded = 0, lost = 0, failed = 0, dupSuppressed = 0, userAction = 0, echo = 0}
-- Is there a handover still waiting for its PLAYBACK_STARTED?
local tAuditPendingHandover = false
local tAuditPendingText = nil
local tAuditPendingAt = 0
-- Was a StopSpeakingText issued since that handover? Only then can a missing
-- STARTED be blamed on a cancel rather than on the client still warming up.
local tAuditStopSinceHandover = false

-- [v43.2] ★Gap histogram -- the instrument that answers the hold question by
-- MEASURING instead of by bisecting hold values until something breaks.
--
-- For every handover that a stop cleared the way for, this records how long
-- after that stop the utterance was actually handed over, and whether it then
-- played. Buckets are 10 ms wide, index 11 = 100 ms and above. Read off
-- directly: the shortest bucket that still shows 0 lost is the shortest safe
-- hold. One session gives the whole curve.
--
-- ★It only samples gaps the holds ALLOW, so at the shipped 0.1 s everything
-- lands in bucket 11 and the curve is empty. To measure the short end you have
-- to let handovers go earlier: /skudebug tts hold 0 0.
local tAuditGap = {}
for i = 1, 11 do tAuditGap[i] = {n = 0, lost = 0} end
-- Bucket of the handover currently awaiting its STARTED, or nil when no stop
-- preceded it. nil ALSO means "do not time this one out" -- see the lost check.
local tAuditPendingBucket = nil
-- How long a handover may stay silent before it counts as lost. Generously above
-- any real start latency: STARTED is the START of playback, not its end, and on
-- the bridge it arrives in the handover frame.
local tBttsAuditLostAfter = 0.5

-- [v43.2] Typing-echo fast lane.
--
-- A typed character has the opposite requirements to an announcement: it must be
-- audible NOW, it is one character long, and pressing the same key twice is the
-- user saying something, never a redundant repeat. Routing it through the normal
-- queue cost it ~0.2s (batching + post-stop hold, serialized) and fed it to a
-- dedup guard that swallowed every doubled letter.
--
-- So it gets its own single slot, drained by the same OnUpdate:
--   * ONE slot, newest wins -- a held key or a paste coalesces at frame
--     resolution instead of producing hundreds of utterances;
--   * no queuereset, so consecutive characters never stop each other. The stop
--     is issued ONCE, when typing starts and something else is still audible;
--   * never writes tLastHandedText, so the duplicate guard cannot see it.
local tEchoSlotText = nil
local tEchoSlotDueAt = 0
local tEchoSlotVoice = nil
-- Handover delay for the echo slot. Not pacing -- it is the same post-stop race
-- as above, and only applies to the FIRST character of a burst (the one that
-- carries a stop). Subsequent characters go out on the next frame.
local tEchoHandoverDelay = 0.02
-- Was the last thing handed to the client a typed character? This is what "am I
-- still inside the same typing burst?" is decided on -- and therefore whether a
-- character has to stop anything at all.
local tLastHandoverWasEcho = false

-- BTTS cache-buster (WoW 12.0 engine): the new client caches synthesized audio
-- by text and, on a repeat, REPLAYS the cached audio without re-invoking the
-- voice. For a real voice (Hedda) that replay is audible; for an out-of-band
-- screen-reader bridge (NVDA/SAPI2SR) the cached audio is silent AND the bridge
-- is never called, so already-spoken lines go silent on revisit. Appending a
-- cycling run of an invisible character makes each utterance's text unique ->
-- every SpeakText is a cache MISS -> the voice is always invoked. Only applied
-- to the Blizzard-TTS (SpeakText) path. See the body for WHICH character, and
-- why a cycling <bookmark> is NOT enough.
-- [v43.3] The run length is counted PER TEXT, not globally. It used to be one
-- session-wide counter cycling 1..64, which meant any line repeated exactly 64
-- handovers after itself went out byte-identical and hit the cache again. That
-- is not a corner case: measured over a 50-minute capture, 27 of 1307 handovers
-- collided that way -- "menue geschlossen", "annehmen", "buffs" and single typed
-- characters among them, i.e. exactly the short lines a user revisits all
-- evening. Keyed by text, a line only reuses a run after 64 repeats OF ITSELF;
-- in that same capture the most-repeated string occurred 36 times and NOTHING
-- collided. Same cap, same character, same maximum padding -- only the counter
-- moved.
local BTTS_CACHEBUST_MAX = 64
-- The table is bounded, not an LRU: a plain wipe once it grows past this. The
-- wipe is harmless because a re-seen text does NOT restart at 1 -- see the
-- seeding in the else branch below, which is what keeps a wipe from colliding
-- every text with its own first use.
local BTTS_CACHEBUST_KEYS_MAX = 512
local mBttsCacheBustSeen = {}
local mBttsCacheBustKeys = 0
-- Rotation point handed to a text the first time it is seen (see below).
local mBttsCacheBustSeed = 0
local function BttsCacheBust(aString)
	if mBttsCacheBustKeys >= BTTS_CACHEBUST_KEYS_MAX then
		mBttsCacheBustSeen = {}
		mBttsCacheBustKeys = 0
	end
	local tRun = mBttsCacheBustSeen[aString]
	if tRun then
		tRun = (tRun % BTTS_CACHEBUST_MAX) + 1
	else
		-- A text seen for the FIRST time starts at the global rotation point, not
		-- at 1. Measured on the same capture: restarting every text at 1 made the
		-- table wipe collide each text with its own first use and scored WORSE
		-- than the global counter this replaces (80 collisions vs 27). Seeded,
		-- the capture collides ZERO times -- at 512 keys, at 2048, or unbounded.
		mBttsCacheBustSeed = (mBttsCacheBustSeed % BTTS_CACHEBUST_MAX) + 1
		tRun = mBttsCacheBustSeed
		mBttsCacheBustKeys = mBttsCacheBustKeys + 1
	end
	mBttsCacheBustSeen[aString] = tRun
	-- Two things:
	-- 1) Leading U+00A0 NO-BREAK SPACE (C2 A0): quest text is spoken as several
	--    separate queued utterances; each is assembled with a LEADING space that
	--    XML normalization trims, so NVDA glues a punctuation-less header to the
	--    next utterance's first word ("questtext"+"vor" -> "questtextvor"). U+00A0
	--    is not XML whitespace, so it survives trimming and keeps the word
	--    boundary at the seam, without being spoken.
	-- 2) Trailing run of U+00A0 -- the actual cache-buster.
	--
	--    [v43.2] The cycling <bookmark mark="skcN"/> that used to do this job does
	--    NOT do it. Proven from a capture: alternating between a filtered list's
	--    single hit and the filter row above it, every utterance got its own
	--    bookmark (skc9, skc11, skc13 ... not one repeat), and the hit still went
	--    silent after a few passes while Sku kept getting a clean SpeakText +
	--    STARTED + FINISHED for each press. The client parses the markup off and
	--    keys its audio cache on the SPOKEN text, so a varying bookmark is
	--    invisible to it. The ORIGINAL buster (a cycling run of zero-width
	--    characters) varied real character data and therefore worked; swapping it
	--    for a bookmark to protect NVDA's prosody silently reintroduced the exact
	--    bug it had been written to fix.
	--
	--    So vary real character data again, but place it AFTER the last word where
	--    it cannot colour the prosody of anything: a run of 1..64 U+00A0, counted
	--    per text (see BTTS_CACHEBUST_MAX above). Trailing
	--    whitespace is inaudible, and U+00A0 is not XML whitespace -- the very
	--    property point 1 already relies on -- so the client's XML normalization
	--    cannot trim it back off and collapse the variants into one cache key.
	--
	--    The bookmark stays: it costs nothing, the patched engine strips it, and it
	--    still busts the key on any client that DOES hash the raw string.
	--
	--    [v43.3] Except on macOS: that client's engine does not parse the markup
	--    off and speaks it literally ("bookmark skc..."), reported in PR #17. The
	--    NBSP run above is the real buster and varies per repeat, so withholding
	--    the bookmark there loses nothing.
	if IsMacClient and IsMacClient() then
		return "\194\160" .. aString .. string.rep("\194\160", tRun)
	end
	return "\194\160" .. aString .. string.rep("\194\160", tRun) .. string.format('<bookmark mark="skc%d"/>', tRun)
end

-- [v43.2] The ONE place an utterance reaches the client. The normal queue and the
-- typing fast lane both go through here, so the audit counters can never disagree
-- with what was actually spoken.
--
-- Patch 12.0.0 (ported to the Anniversary client) REMOVED the `destination` arg
-- from C_VoiceChat.SpeakText and added an optional `overlap`. New signature:
--   SpeakText(voiceID, text, rate, volume [, overlap])
-- The old call passed the now-dead destination (4) here, which shifted
-- rate/volume by one and let the old volume land in the new `overlap` slot
-- (truthy => overlap on). That mangled call made the engine speak "start"/"end"
-- around every utterance and ignored the user's speed/volume. Proven on-client:
-- Enum.VoiceTtsDestination is now nil and a clean 4-arg call speaks with no
-- boundary words. overlap is omitted (defaults false) so Sku keeps driving its
-- own sequencing without overlapping speech.
local function BttsHandOver(aText, aVoiceIndex, aIsEcho)
	if tAuditPendingHandover and tAuditStopSinceHandover then
		-- Deliberately cancelled before it played. Normal; counted for context
		-- only. Without a stop in between nothing was cancelled -- the client just
		-- queues both and speaks them in turn -- so that case is not counted at all.
		tBttsStats.superseded = tBttsStats.superseded + 1
		if dprint then dprint("BTTS SUPERSEDED", "cancelled before playback",
			"text=["..tostring(tAuditPendingText).."]") end
	end
	tAuditPendingHandover = true
	tAuditPendingText = aText
	tAuditPendingAt = GetTime()
	-- ★A handover is only expected to start PROMPTLY when a stop cleared the way
	-- for it. Without one it is queued behind whatever is still speaking, and
	-- waiting a second or three for its turn is correct behaviour, not a loss.
	-- Measured proof that this matters: two lines flagged lost at the 0.1 s hold
	-- were both simply queued behind a playing utterance -- one of them got its
	-- STARTED right after the one in front finished, the other was cancelled by
	-- the user's next keypress. Neither was a loss, and the first version of this
	-- check called both of them one.
	if tAuditStopSinceHandover then
		local tGap = tAuditPendingAt - tLastStopAt
		local tBucket = math.floor(tGap * 100) + 1
		if tBucket < 1 then tBucket = 1 end
		if tBucket > 11 then tBucket = 11 end
		tAuditPendingBucket = tBucket
	else
		tAuditPendingBucket = nil
	end
	tAuditStopSinceHandover = false
	tLastHandoverWasEcho = (aIsEcho == true)
	tBttsStats.handed = tBttsStats.handed + 1
	if aIsEcho then tBttsStats.echo = tBttsStats.echo + 1 end
	if dprint then dprint("BTTS SpeakText", aIsEcho and "echo" or "queue",
		"voice="..tostring(aVoiceIndex - 1), "speed="..tostring(ChatTts().WowTtsSpeed),
		"vol="..tostring(ChatTts().WowTtsVolume), "text=["..tostring(aText).."]") end
	C_VoiceChat.SpeakText(aVoiceIndex - 1, BttsCacheBust(aText), ChatTts().WowTtsSpeed, ChatTts().WowTtsVolume)
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
			-- [v43.2] A FAILED utterance never reached the voice, so the duplicate
			-- guard must not treat it as "the user already heard this".
			if aEventName == "VOICE_CHAT_TTS_PLAYBACK_FAILED" then
				tLastHandedStarted = false
				-- A refusal is a non-start with a KNOWN cause, so it must not be
				-- counted as the async-stop race the `lost` figure is measuring.
				tBttsStats.failed = tBttsStats.failed + 1
				tAuditPendingHandover = false
			end
			-- Drain the oldest speaking entry on BOTH end and fail (FIFO — the
			-- guard's only job is short-lived dedup, so oldest-out is good enough;
			-- the TTL sweep backstops any out-of-order or missing event).
			if mSkuVoiceQueueBTTS_Speaking[1] then
				table.remove(mSkuVoiceQueueBTTS_Speaking, 1)
			end
		elseif aEventName == "VOICE_CHAT_TTS_PLAYBACK_STARTED" then
			if dprint then dprint("BTTS event STARTED", ...) end
			-- [v43.2] Playback of the line we last handed over really began. Only then
			-- may a back-to-back repeat of it be dropped -- an utterance cancelled
			-- BEFORE its STARTED (the async-stop race documented in the pump) must
			-- still be allowed through again, or suppressing it would CAUSE silence.
			tLastHandedStarted = true
			tBttsStats.started = tBttsStats.started + 1
			tAuditPendingHandover = false
			-- It survived the gap it was handed over at: one sample for the curve.
			if tAuditPendingBucket then
				tAuditGap[tAuditPendingBucket].n = tAuditGap[tAuditPendingBucket].n + 1
				tAuditPendingBucket = nil
			end
		elseif aEventName == "VOICE_CHAT_TTS_SPEAK_TEXT_UPDATE" then
			if dprint then dprint("BTTS event SPEAK_TEXT_UPDATE", ...) end
		elseif aEventName == "VOICE_CHAT_TTS_PLAYBACK_BOOKMARK" then
			if dprint then dprint("BTTS event BOOKMARK", ...) end
		end
	end)
	local fTime = 0
	local fTimeBTTS = 0
	-- [v42.12] Wall-clock pacing instead of a per-frame countdown.
	--
	-- tNextSpeakAt is the GetTime() before which no new utterance may be handed to
	-- C_VoiceChat.SpeakText. The old code kept a `tLastWait` countdown and
	-- subtracted ONE frame's delta per pump run -- but the pump body only runs
	-- when fTimeBTTS > 0.01, so above ~100 fps it subtracted a fraction of the
	-- time that had really elapsed and the intended 0.1 s hold stretched to
	-- 0.2-0.3 s of real time. Since a queuereset deletes whatever line is still
	-- waiting, a longer hold means MORE lost announcements: the bug got worse the
	-- higher your framerate. A deadline is framerate-independent and identical to
	-- the old behaviour at 60 fps.
	-- (tNextSpeakAt / tLastStopAt are file-locals now -- see their declaration
	-- above; SkuVoice:CancelBttsOutput needs to arm the same hold.)
	f:SetScript("OnUpdate", function(self, time)

		-- [v43.2] Did a handover go silent? Nothing superseded it (a supersede
		-- clears the flag at the next handover) and no STARTED arrived -- so the
		-- async stop landed on it and the user heard nothing. This is the ONE
		-- figure that says tBttsPostStopHold is too short; everything else in the
		-- audit is context. Checked here because it needs a clock, not an event:
		-- the whole failure is that no event ever comes.
		-- ★Only handovers that a stop cleared the way for (tAuditPendingBucket set)
		-- are timed out. One that is queued behind a playing utterance is SUPPOSED
		-- to wait, and timing it out reports a loss where the client is merely
		-- taking its turn -- which is exactly what the first version did.
		if tAuditPendingHandover and tAuditPendingBucket
			and (GetTime() - tAuditPendingAt) > tBttsAuditLostAfter then
			tAuditPendingHandover = false
			tBttsStats.lost = tBttsStats.lost + 1
			tAuditGap[tAuditPendingBucket].n = tAuditGap[tAuditPendingBucket].n + 1
			tAuditGap[tAuditPendingBucket].lost = tAuditGap[tAuditPendingBucket].lost + 1
			if dprint then dprint("BTTS LOST", "handed but never played",
				"gapBucket="..tostring((tAuditPendingBucket - 1) * 10).."ms",
				"postStopHold="..tostring(tBttsPostStopHold),
				"text=["..tostring(tAuditPendingText).."]") end
			tAuditPendingBucket = nil
		end

		-- [v43.2] Typing fast lane, drained BEFORE the 0.01s pump gate and before
		-- the queue below: a typed character has to reach the voice on the frame it
		-- is due, not a pump tick later. One slot, so a character typed while the
		-- previous one is still waiting simply replaces it -- that is the coalescing
		-- a held key and a paste need, at frame resolution.
		if tEchoSlotText then
			local tNowEcho = GetTime()
			if tNowEcho >= tEchoSlotDueAt then
				local tText = tEchoSlotText
				local tVoice = tEchoSlotVoice
				tEchoSlotText = nil
				tEchoSlotVoice = nil
				BttsHandOver(tText, tVoice or ChatTts().WowTtsVoice, true)
			end
		end

		fTimeBTTS = fTimeBTTS + time
		if fTimeBTTS > 0.01 and #mSkuVoiceQueueBTTS == 0 and #mSkuVoiceQueueBTTS_Speaking == 0 then
			-- Idle: nothing queued and nothing in flight. Skip the TTL sweep, the
			-- queuereset scan and the dequeue entirely -- that is the overwhelmingly
			-- common case and it otherwise ran ~100 times a second for nothing.
			fTimeBTTS = 0
		elseif fTimeBTTS > 0.01 then
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
					-- [v43.2] Drop the side-map entry with the string it belongs to, so
					-- a superseded line cannot leave a stale user-action tag behind for
					-- the next identical string to inherit.
					local tDropped = mSkuVoiceQueueBTTS[1]
					if tDropped and tDropped ~= "queuereset" then
						mSkuVoiceQueueBTTS_UserAction[tDropped] = nil
					end
					table.remove(mSkuVoiceQueueBTTS, 1)
				end
			end
			-- BTTS diag (lag/stall hunt): surface a growing backlog. If the queue
			-- or the "currently speaking" dedup set climbs, the dequeue is stalling
			-- (FINISHED not clearing / lower-layer not draining).
			if dprint and (#mSkuVoiceQueueBTTS > 4 or #mSkuVoiceQueueBTTS_Speaking > 3) then
				dprint("BTTS DEPTH", "queue="..#mSkuVoiceQueueBTTS, "speaking="..#mSkuVoiceQueueBTTS_Speaking, "wait="..tostring(tNextSpeakAt - tNow))
			end
			if #mSkuVoiceQueueBTTS > 0 then
				local tValue = mSkuVoiceQueueBTTS[1]
				if tValue == "queuereset" then
					-- [v43.2] Peek one entry ahead: OutputStringBTtts enqueues the reset
					-- and its text together in a single call, so a reset sitting at the
					-- head with its own text right behind it is exactly the "overwrite
					-- with the same line again" case. (Anything queued in front of the
					-- LAST reset was already dropped by the tLastReset scan above, so if
					-- we are here this pair is the tail of the queue.) Drop both: no
					-- stop, no resend, the line already playing simply runs to its end.
					local tPeek = mSkuVoiceQueueBTTS[2]
					-- [v43.2] A line the user's own keypress produced is never a
					-- redundant repeat -- they asked for it again. Only untagged
					-- (rebuild-driven) repeats are suppressed. See
					-- mSkuVoiceQueueBTTS_UserAction.
					local tPeekIsUserAction = tPeek and mSkuVoiceQueueBTTS_UserAction[tPeek] == true
					if tPeek and tPeek ~= "queuereset" and tLastHandedText and tLastHandedStarted
						and tPeek == tLastHandedText and (tNow - tLastHandedAt) < tBttsDupWindow
						and not tPeekIsUserAction then
						table.remove(mSkuVoiceQueueBTTS, 1)
						table.remove(mSkuVoiceQueueBTTS, 1)
						mSkuVoiceQueueBTTS_Voice[tPeek] = nil
						mSkuVoiceQueueBTTS_UserAction[tPeek] = nil
						tBttsStats.dupSuppressed = tBttsStats.dupSuppressed + 1
						if dprint then dprint("BTTS DUP-SUPPRESS", "reset+text", "age="..string.format("%.2f", tNow - tLastHandedAt), "text=["..tostring(tPeek).."]") end
					else
						-- Count a rescue only when the guard WOULD have suppressed this
						-- line -- same three conditions as the branch above. Without the
						-- age and started checks it also counted repeats that were
						-- outside the window anyway (measured: ages of 2.0 s and 3.3 s),
						-- which overstates what the tag is actually buying.
						if tPeekIsUserAction and tPeek == tLastHandedText and tLastHandedStarted
							and (tNow - tLastHandedAt) < tBttsDupWindow then
							tBttsStats.userAction = tBttsStats.userAction + 1
							if dprint then dprint("BTTS DUP-ALLOW", "user action", "age="..string.format("%.2f", tNow - tLastHandedAt), "text=["..tostring(tPeek).."]") end
						end
						table.remove(mSkuVoiceQueueBTTS, 1)
						if ChatTts().neverResetQueues ~= true then
							-- [v42.12] Suppress a provably redundant stop.
							--
							-- StopSpeakingText is only meaningful while Sku believes an
							-- utterance is in flight (mSkuVoiceQueueBTTS_Speaking non-empty).
							-- During an announce flood -- fast menu/soft-target scrolling, a
							-- mail or chat burst -- resets arrive faster than lines are
							-- spoken, so this branch used to fire 15-20 stops per second with
							-- nothing playing. The client processes StopSpeakingText
							-- asynchronously, so a trailing one lands on the NEXT utterance
							-- and cancels it before playback starts: 14 of 580 SpeakText calls
							-- in a captured session never produced a PLAYBACK_STARTED, all
							-- clustered inside those floods. That is how the LAST line of a
							-- fast scroll went missing and left the user in silence until
							-- some other UI action produced a fresh announcement.
							--
							-- The skip is deliberately narrow: only when Sku has nothing
							-- flagged as speaking AND a stop was already issued within the
							-- last 0.15 s. With a real SAPI voice the speaking flag stays set
							-- for the whole utterance, so a cancel that actually has something
							-- to cancel is NEVER skipped -- combat cancellation semantics are
							-- unchanged. An isolated announce also still stops exactly as
							-- before; only the redundant repeats inside a burst are dropped.
							if #mSkuVoiceQueueBTTS_Speaking > 0 or (tNow - tLastStopAt) > 0.15 then
								if dprint then dprint("BTTS queuereset -> StopSpeakingText") end
								C_VoiceChat.StopSpeakingText()
								tLastStopAt = tNow
								tAuditStopSinceHandover = true
							elseif dprint then
								dprint("BTTS queuereset -> stop suppressed (nothing in flight)")
							end
						end
						mSkuVoiceQueueBTTS_Speaking = {}
						tNextSpeakAt = tNow + tBttsPostStopHold
						-- A stop that really fired cancelled whatever was playing, so an
						-- identical line arriving after it must be allowed through again.
						tLastHandedText = nil
						-- [v43.2] A real announcement supersedes a typed character that has
						-- not gone out yet -- otherwise the stale letter would be spoken
						-- after the line that replaced it.
						tEchoSlotText = nil
						tEchoSlotVoice = nil
					end
				else
					if #mSkuVoiceQueueBTTS > 1 or tNow >= tNextSpeakAt then
						table.remove(mSkuVoiceQueueBTTS, 1)
						local tIsAlreadySpeakingThat
						for z = 1, #mSkuVoiceQueueBTTS_Speaking do
							--print(z, mSkuVoiceQueueBTTS_Speaking[z].text)
							if mSkuVoiceQueueBTTS_Speaking[z].text == tValue then
								tIsAlreadySpeakingThat = true
							end
						end
						-- [v43.2] Same guard for a repeat that arrives WITHOUT a reset in
						-- front of it (aOverwrite false). Nothing is cancelled here, so the
						-- only effect is that the identical line is not queued a second time
						-- behind itself.
						local tIsBackToBackDup = false
						-- [v43.2] Never suppress a line the user's own keypress asked
						-- for -- see mSkuVoiceQueueBTTS_UserAction.
						local tIsUserAction = mSkuVoiceQueueBTTS_UserAction[tValue] == true
						if not tIsAlreadySpeakingThat and tLastHandedText and tLastHandedStarted
							and tValue == tLastHandedText and (tNow - tLastHandedAt) < tBttsDupWindow then
							if tIsUserAction then
								tBttsStats.userAction = tBttsStats.userAction + 1
								if dprint then dprint("BTTS DUP-ALLOW", "user action", "age="..string.format("%.2f", tNow - tLastHandedAt), "text=["..tostring(tValue).."]") end
							else
								tIsBackToBackDup = true
								tBttsStats.dupSuppressed = tBttsStats.dupSuppressed + 1
								if dprint then dprint("BTTS DUP-SUPPRESS", "no-reset", "age="..string.format("%.2f", tNow - tLastHandedAt), "text=["..tostring(tValue).."]") end
							end
						end
						if not tIsAlreadySpeakingThat and not tIsBackToBackDup then
							table.insert(mSkuVoiceQueueBTTS_Speaking, {text = tValue, at = GetTime()})
							-- Per-message voice override (nil => global voice). Same
							-- 1-based domain as WowTtsVoice, so the "- 1" API convention
							-- is identical whether the voice is per-channel or global.
							local tVoiceIndex = mSkuVoiceQueueBTTS_Voice[tValue] or ChatTts().WowTtsVoice
							BttsHandOver(tValue, tVoiceIndex, false)
							-- [v43.2] Marker for the back-to-back duplicate guard. Set from the
							-- handover, NOT from a playback event: on the bridge the events are
							-- useless for this (see tBttsDupWindow).
							tLastHandedText = tValue
							tLastHandedAt = tNow
							tLastHandedStarted = false
						elseif tIsBackToBackDup then
							-- already logged above as DUP-SUPPRESS
						else
							-- BTTS diag: a queued line was DROPPED because an identical
							-- string is still flagged "speaking" (FINISHED never cleared it).
							-- Repeated drops here == the "goes silent" symptom.
							if dprint then dprint("BTTS DEDUP-SKIP", "speaking="..#mSkuVoiceQueueBTTS_Speaking, "text=["..tostring(tValue).."]") end
						end
						mSkuVoiceQueueBTTS_Voice[tValue] = nil
						mSkuVoiceQueueBTTS_UserAction[tValue] = nil
						tNextSpeakAt = tNow + tBttsPostSpeakHold
					end
				end
			end
		end

		fTime = fTime + time
		-- [v43.0] A "cadence" run is the original every-0.1 s run. A dirty run is the
		-- extra one on the frame right after something was queued: it may only START
		-- sounds, never END them (see the tombstone gate below), and it deliberately
		-- does NOT reset fTime, so the 0.1 s cadence keeps its own clock exactly as
		-- before.
		local tCadence = (fTime > 0.1)
		if #mSkuVoiceQueue == 0 then
			-- [v42.12] Idle: the audio-file queue is empty, so all five passes below
			-- plus the pairs() tombstone sweep are no-ops. Skip them.
			-- [v43.0] Also drop a stale dirty flag: StopOutputEmptyQueue can wipe the
			-- queue between the append and this frame, and the flag must not survive
			-- into the next unrelated append.
			if tCadence then fTime = 0 end
			mQueueDirty = false
		elseif tCadence or mQueueDirty then
			if tCadence then fTime = 0 end
			mQueueDirty = false
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

			-- [v43.0] CADENCE ONLY. The tombstone sweep ends a sound at its DECLARED
			-- length and the removal below hard-StopSounds it, but the declared lengths
			-- in SkuAudioDataLenIndex sit slightly under the real file durations (e.g.
			-- sound-brass1 declares 0.32 s, the file is 0.34 s). Running this on the
			-- extra dirty frame too would land the stop right on the declared time
			-- instead of up to 100 ms late, i.e. it would start clipping the last ~20 ms
			-- of a clip's tail -- inaudible on a beep, but not on a word's final
			-- consonant. The dirty run has no business ending sounds anyway, so the
			-- end-of-sound timing stays EXACTLY as it was.
			if tCadence then
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
			end

			-- [v43.0] Aura SOUND outputs jump the TTSSepPause hold -- but only one at
			-- a time.
			--
			-- TTSSepPause (default 85) is the word-to-word pacing knob for Sku's
			-- audio-file speech: a queued clip may only start once the playing clip is
			-- 85% done, which is what keeps concatenated word clips from slurring. That
			-- rule is right for words and wrong for a one-shot aura beep, because the
			-- hold scales with the length of whatever happens to be playing in front of
			-- it (a 1.36 s sound in front = a 1.15 s wait for the beep).
			--
			-- So an aura sound starts immediately -- EXCEPT when another aura sound is
			-- still playing. Two aura sounds on top of each other are indistinguishable,
			-- which for a screen-reader interface is worse than a late one, so the
			-- second aura sound falls back to the normal queued path and keeps today's
			-- separation exactly.
			--
			-- Deliberately NOT changed: aura sounds still BLOCK whatever is queued
			-- behind them (they are not excluded from the tPlayNext scan below), so
			-- speech queued after an aura sound waits as it does today. Only the
			-- follower direction is relaxed.
			--
			-- "Still playing" is tested against the clock, NOT against whether the
			-- tombstone sweep above has removed the entry -- because that sweep is
			-- cadence-only, so on a dirty frame a finished aura sound can still be
			-- sitting in the queue with its handle set. Without the endTimestamp test a
			-- finished predecessor would keep blocking, and item 2's whole win would only
			-- materialise on cadence frames.
			local tNow = GetTime()
			local tAuraSoundPlaying = false
			for i = 1, table.getn(mSkuVoiceQueue) do
				local v = mSkuVoiceQueue[i]
				if v.auraSound == true and v.soundHandle and v.tombstone ~= true and tNow < v.endTimestamp then
					tAuraSoundPlaying = true
					break
				end
			end
			if tAuraSoundPlaying ~= true then
				for i = 1, table.getn(mSkuVoiceQueue) do
					local v = mSkuVoiceQueue[i]
					if v.auraSound == true and not v.soundHandle and v.tombstone ~= true then
						local willPlay, soundHandle = PlaySoundFile(v.file, v.soundChannel)
						if willPlay then
							SkuVoice.LastPlayedString = v.text
							v.soundHandle = soundHandle
							v.endTimestamp = GetTime() + v.length
						else
							--there's something quite wrong with that entry
							v.tombstone = true
						end
						break
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
	if SkuAudioFileIndex and SkuAudioFileIndex[aString] then
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
	if SkuAudioFileIndex and SkuAudioFileIndex[aString] then
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
		-- [v42.13] plain find (4th arg true). aString is CALLER text, not a
		-- pattern: the live typing echo passes single typed characters through
		-- here, so "(" threw "unfinished capture" and "%" threw "malformed
		-- pattern", and the whole spoken line was lost inside the caller's
		-- pcall. A substring test is what this check always meant.
		if string.find(v, aString, 1, true) then
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
-- aUserAction: this line is the direct consequence of a key the user just
-- pressed. Only the menu's keypress funnel sets it; it exempts the line from the
-- back-to-back duplicate guard (see mSkuVoiceQueueBTTS_UserAction).
function SkuVoice:OutputStringBTtts(aString, aOverwrite, aWait, aLength, aDoNotOverwrite, aIsMulti, aSoundChannel, engine, aSpell, aVocalizeAsIs, aInstant, aDnQ, aIgnoreLinks, aIsTutorial, aVoice, aUserAction)
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
		aUserAction = aOverwrite.userAction
		aOverwrite = aOverwrite.overwrite
	end

	--SkuNav:NavigationModeWoCoordinatesCheckTaskTrigger(aString)

	--strip object numbers
	aString = string.gsub(aString, L["OBJECT"]..";%d+;", L["OBJECT"]..";")


	if SkuVoice:CheckIgnore(aString) then
		aIgnoreLinks = true
	end

	-- [v42.09 i18n] `and Sku.AudiodataPath ~= ""` is REQUIRED here, not optional.
	--
	-- These two functions delegate to each other, and the pair is only safe
	-- because the conditions are exact negations: OutputString hands over when
	-- allChatViaBlizzardTts is true, and this branch hands back when it is not.
	-- Adding the no-voice-pack trigger to OutputString alone broke that symmetry
	-- and produced infinite mutual recursion - 177 stack overflows in a single
	-- session on a client with no pack (SkuChat/Core.lua:3039). The audio path
	-- cannot be the fallback for a client that has no audio to play.
	if SkuOptions.db.profile["SkuOptions"].useBlizzTtsInMenu ~= true and not engine
		and ChatTts().allChatViaBlizzardTts ~= true and Sku.AudiodataPath ~= "" then
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
	aString = Unescape(aString)

	while string.find(aString, "|") do
		aString = string.gsub(aString, "|", " ")
	end

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
		if aUserAction then
			mSkuVoiceQueueBTTS_UserAction[tFinalStringForBTtsMac] = true
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
		if aUserAction then
			mSkuVoiceQueueBTTS_UserAction[tFinalStringForBTts] = true
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
-- aAuraSound: marks the entry as a one-shot aura SOUND, which lets it skip the
-- TTSSepPause hold while no other aura sound is playing (see the pump). Only the
-- generated aura sound outputs in SkuAuras/data.lua set it; word/text outputs
-- must NOT, or a multi-word aura output would play its words on top of itself.
function SkuVoice:OutputString(aString, aOverwrite, aWait, aLength, aDoNotOverwrite, aIsMulti, aSoundChannel, engine, aSpell, aVocalizeAsIs, aInstant, aDnQ, aIgnoreLinks, aIsTutorial, aAudioFile, aAuraSound) -- for strings with lookup in string index
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
		aAuraSound = aOverwrite.auraSound
		aOverwrite = aOverwrite.overwrite
	end
	
	--we need to skip checks, etc. for sounds to get better performance on aura output
	local tIsSound
	if string.sub(aString, 1, 6) == "sound-" then
		tIsSound = true
	end

	-- [SOUND-PROBE] removed (v42.12). Same reason as the PlaySound probe in
	-- Sku/Core.lua: the guard tested `dprint` (always defined), not the log flag,
	-- and debugstack(2, 3, 0) was evaluated before dprint could bail -- so every
	-- ping, beacon and nav click paid a full stack walk even with logging off.

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


		-- [v42.09 i18n] Second trigger for this existing delegation: a client with
		-- NO voice pack for its language. Without it the audio path can only ever
		-- reach the "sound-audiofehltbeep" fallback for anything that is not an
		-- identifier, so a French user would hear a beep for every mob, zone and
		-- item name. Routing the whole string to TTS gives them the real French
		-- text instead.
		--
		-- Gated per CLIENT (is a pack installed), never per STRING. A per-string
		-- test would switch queues line by line: the audio and TTS queues are
		-- independent and cannot be coordinated, so target announcements would
		-- start colliding with chat for German and English users. As written,
		-- anyone with a matching pack keeps today's behaviour exactly, beeps
		-- included - those stay a useful "recording missing from the pack" signal
		-- and are still counted in SkuOptions.db.realm.missingAudio.
		--
		-- Note this is deliberately Sku.AudiodataPath (chosen by Sku.Loc), NOT
		-- Sku.LocAudio: a voice pack is keyed by words in its OWN language, so an
		-- English pack on a French client would match nothing AND suppress this
		-- fallback. Sku.LocAudio stays confined to the integrated index, which is
		-- keyed by identifiers ("male-Nord") rather than words.
		if not (string.find(aString, "sound%-") or string.find(aString, "male%-") or string.find(aString, "brian%-") or string.find(aString, "emma%-")) and (ChatTts().allChatViaBlizzardTts == true or Sku.AudiodataPath == "") then
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
			-- [v43.0] The clear may have removed entries below this frame's
			-- instant cursor; clamp so later instant inserts stay contiguous.
			if mInstantInsertTime == GetTime() and mInstantInsertPos > #mSkuVoiceQueue then
				mInstantInsertPos = #mSkuVoiceQueue
			end
		end

		if not tIsSound then
			while string.find(aString, "|n") do
				aString = string.gsub(aString, "|n", ";")
			end
			aString = Unescape(aString)

			while string.find(aString, "|") do
				aString = string.gsub(aString, "|", " ")
			end

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
						-- [v43.0] Cursor instead of `0 + x` — see mInstantInsertPos.
						if mInstantInsertTime ~= GetTime() then
							mInstantInsertTime = GetTime()
							mInstantInsertPos = 0
						end
						mInstantInsertPos = mInstantInsertPos + 1
						table.insert(mSkuVoiceQueue, mInstantInsertPos, {
							["text"] = tStrings[x],
							["file"] = tFile,
							["wait"] = aWait,
							["length"] = tLength,
							["endTimestamp"] = 0,
							["soundHandle"] = nil,
							["doNotOverwrite"] = aDoNotOverwrite or false,
							["soundChannel"] = aSoundChannel,
							["dnq"] = aDnQ,
							["auraSound"] = aAuraSound or false,
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
							["auraSound"] = aAuraSound or false,
						})
					end
					-- [v43.0] Wake the pump on the next frame (see mQueueDirty).
					mQueueDirty = true
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
-- [v42.11] Two small read/trim helpers on the Blizzard-TTS queue, for the LIVE
-- typing echo (SkuOptions:EditBoxShow). That echo appends ONE utterance per typed
-- character (append, not overwrite -- otherwise fast typing loses characters), and
-- a voice that needs ~0.4 s per character cannot keep up with 4-5 keystrokes per
-- second. Without a cap the backlog grew unbounded and kept reading the typed text
-- back minutes after the edit box was gone ("it repeats the letters I entered a
-- while after the mail was sent").
--
-- TrimBttsQueue only drops entries that are still WAITING in Sku's own queue --
-- nothing that was already handed to C_VoiceChat.SpeakText -- so it never cuts a
-- word in half. It therefore also ignores `neverResetQueues`: that setting is about
-- not interrupting speech in progress (StopSpeakingText), which this does not do.
function SkuVoice:GetBttsQueueDepth()
	return #mSkuVoiceQueueBTTS
end

---@param aKeep number|nil how many of the NEWEST pending entries to keep (default 0)
function SkuVoice:TrimBttsQueue(aKeep)
	aKeep = aKeep or 0
	local tDrop = #mSkuVoiceQueueBTTS - aKeep
	for _ = 1, tDrop do
		local tValue = mSkuVoiceQueueBTTS[1]
		if tValue then
			mSkuVoiceQueueBTTS_Voice[tValue] = nil
		end
		table.remove(mSkuVoiceQueueBTTS, 1)
	end
end

---------------------------------------------------------------------------------------------------------
-- [v42.13] HARD cancel of the Blizzard-TTS path: drop everything Sku still has
-- queued AND stop what the client is already speaking.
--
-- Why TrimBttsQueue was not enough for the typing echo. The pump dequeues
-- WITHOUT waiting for playback whenever more than one entry is pending
-- (`#mSkuVoiceQueueBTTS > 1` bypasses the 0.1 s pacing), so a burst of queued
-- lines is handed to C_VoiceChat.SpeakText within a few frames. From that
-- moment the backlog lives in the CLIENT's TTS queue, where Sku's own queue is
-- empty and TrimBttsQueue has nothing left to drop -- which is exactly why
-- typed characters kept being read out long after the edit box was gone.
-- Stopping playback is the only thing that reaches that backlog.
--
-- Deliberately ignores `neverResetQueues`: that setting keeps ROUTINE
-- announcements from cutting each other off. This is not routine output -- it
-- is "the input field the echo belonged to no longer exists", and leaving the
-- letters running is the bug the setting's owner is complaining about too.
--
-- Arms the pump's own post-stop hold (0.15 s) so the announcement a caller
-- makes right after cancelling (a confirmation, "Cancelled") cannot be eaten by
-- this stop landing asynchronously on the NEXT utterance.
function SkuVoice:CancelBttsOutput()
	for x = #mSkuVoiceQueueBTTS, 1, -1 do
		local tValue = mSkuVoiceQueueBTTS[x]
		if tValue then
			mSkuVoiceQueueBTTS_Voice[tValue] = nil
			mSkuVoiceQueueBTTS_UserAction[tValue] = nil
		end
		mSkuVoiceQueueBTTS[x] = nil
	end
	mSkuVoiceQueueBTTS_Speaking = {}
	-- [v43.2] A pending typed character must not survive a hard cancel either.
	tEchoSlotText = nil
	tEchoSlotVoice = nil
	tLastHandoverWasEcho = false
	local tNow = GetTime()
	tLastStopAt = tNow
	tNextSpeakAt = tNow + 0.15
	-- [v43.2] A hard cancel really did silence the line, so the confirmation a caller
	-- speaks right after must never be swallowed as a back-to-back duplicate of it.
	tLastHandedText = nil
	if dprint then dprint("BTTS CancelBttsOutput -> StopSpeakingText") end
	pcall(function() C_VoiceChat.StopSpeakingText() end)
	tAuditStopSinceHandover = true
end

---------------------------------------------------------------------------------------------------------
-- [v43.2] Speak ONE typed character (or a short key-feedback string) with the
-- lowest latency this API allows.
--
-- Why it does not go through OutputStringBTtts: an announcement and a keystroke
-- want opposite things. The queue path batches, paces, overwrites-by-stop and
-- dedups -- correct for a menu line, and four separate ways to swallow or delay a
-- letter. The measured cost was ~0.2s per character (a 0.1s producer-side batch
-- and the 0.1s post-stop hold, serialized), doubled letters eaten by the
-- back-to-back guard, and a StopSpeakingText per keystroke whose async landing
-- killed the NEXT letter.
--
-- What happens here instead:
--   * ONE slot. A character typed while the previous one is still waiting simply
--     replaces it, so a held key or a paste can never produce a burst of
--     utterances -- the coalescing the old 0.1s batch existed for, at frame
--     resolution instead.
--   * The stop is issued ONCE, on the first character of a burst, where it has
--     something real to interrupt (the field's own announce). Consecutive
--     characters never stop each other: the client sequences them itself, and a
--     stop between two letters can only cut the first or kill the second.
--   * tLastHandedText is never written, so the duplicate guard cannot see typed
--     characters at all. Pressing the same key twice is the user saying
--     something, never a redundant repeat.
---@param aText string one character, or a short spoken key name ("Leerzeichen")
---@param aVoice number|nil optional 1-based voice index, same domain as WowTtsVoice
function SkuVoice:SpeakEcho(aText, aVoice)
	if type(aText) ~= "string" or aText == "" then
		return
	end
	local tNow = GetTime()
	if tLastHandoverWasEcho ~= true then
		-- First character of a burst: whatever is audible now is superseded by it.
		-- Clear the queue too, or a menu line already waiting would be spoken on
		-- top of the typing.
		for x = #mSkuVoiceQueueBTTS, 1, -1 do
			local tValue = mSkuVoiceQueueBTTS[x]
			if tValue then
				mSkuVoiceQueueBTTS_Voice[tValue] = nil
				mSkuVoiceQueueBTTS_UserAction[tValue] = nil
			end
			mSkuVoiceQueueBTTS[x] = nil
		end
		mSkuVoiceQueueBTTS_Speaking = {}
		tLastStopAt = tNow
		-- The stop really silenced that line, so an identical one arriving later
		-- must be allowed through again.
		tLastHandedText = nil
		if dprint then dprint("BTTS echo burst start -> StopSpeakingText") end
		pcall(function() C_VoiceChat.StopSpeakingText() end)
		tAuditStopSinceHandover = true
		-- Only THIS character waits, and only for the stop to land -- the same
		-- race tBttsPostStopHold covers, but the echo pays it once per burst
		-- rather than once per keystroke.
		tEchoSlotDueAt = tNow + tEchoHandoverDelay
	else
		-- Mid-burst: due now, i.e. the very next frame.
		tEchoSlotDueAt = 0
	end
	tLastHandoverWasEcho = true
	tEchoSlotText = aText
	tEchoSlotVoice = aVoice
end

---------------------------------------------------------------------------------------------------------
-- [v43.2] Drop a typed character that has not gone out yet. Does NOT stop
-- anything already speaking -- the caller decides that (SkuOptions' tEchoStop
-- uses CancelBttsOutput when it wants the hard cancel).
function SkuVoice:CancelEcho()
	tEchoSlotText = nil
	tEchoSlotVoice = nil
	tLastHandoverWasEcho = false
end

---------------------------------------------------------------------------------------------------------
-- [v43.2] Handover audit, for tuning tBttsPostStopHold / tBttsPostSpeakHold
-- against real play instead of the inherited 0.1s guess. See /skudebug tts.
---@return table stats, number postStopHold, number postSpeakHold, number dupWindow, table gapHistogram
function SkuVoice:GetBttsStats()
	return {
		handed = tBttsStats.handed,
		started = tBttsStats.started,
		superseded = tBttsStats.superseded,
		lost = tBttsStats.lost,
		failed = tBttsStats.failed,
		dupSuppressed = tBttsStats.dupSuppressed,
		userAction = tBttsStats.userAction,
		echo = tBttsStats.echo,
	}, tBttsPostStopHold, tBttsPostSpeakHold, tBttsDupWindow, tAuditGap
end

---------------------------------------------------------------------------------------------------------
function SkuVoice:ResetBttsStats()
	tBttsStats.handed = 0
	tBttsStats.started = 0
	tBttsStats.superseded = 0
	tBttsStats.lost = 0
	tBttsStats.failed = 0
	tBttsStats.dupSuppressed = 0
	tBttsStats.userAction = 0
	tBttsStats.echo = 0
	for i = 1, 11 do
		tAuditGap[i].n = 0
		tAuditGap[i].lost = 0
	end
end

---------------------------------------------------------------------------------------------------------
-- [v43.2] Session-only override of the pump's two holds, so a value can be tried
-- and measured without a rebuild. Deliberately NOT persisted: a wrong number here
-- costs speech, and it must never outlive the session that set it.
---@param aPostStop number|nil seconds after a StopSpeakingText before a line may be handed over
---@param aPostSpeak number|nil seconds after a handover before a LONE queued line may follow
function SkuVoice:SetBttsHolds(aPostStop, aPostSpeak)
	if type(aPostStop) == "number" and aPostStop >= 0 and aPostStop <= 1 then
		tBttsPostStopHold = aPostStop
	end
	if type(aPostSpeak) == "number" and aPostSpeak >= 0 and aPostSpeak <= 1 then
		tBttsPostSpeakHold = aPostSpeak
	end
end

---------------------------------------------------------------------------------------------------------
function SkuVoice:Release()

end

---------------------------------------------------------------------------------------------------------
function SkuVoice:GetAudiodata(aString)
	-- [v43.0] These three were assigned WITHOUT `local`, so every call wrote three
	-- globals (and left them set for the next caller to trip over). Verified safe to
	-- localise: OutputString captures the return values into its own locals, and
	-- SkuBeacon's same-named tFile is a proper local -- nothing anywhere read the
	-- leaked globals.
	local tFile = nil
	local tPath = nil
	local tLen = nil

	-- [v42.09 i18n] Two fixes here, both pre-existing bugs exposed by adding a
	-- third client language:
	--
	-- 1. Sku.LocAudio instead of Sku.Loc, and an existence guard. The
	--    integrated index only has deDE and enUS sub-tables, so on any other
	--    client locale the old `SkuAudioFileIndexIntegrated[Sku.Loc][aString]`
	--    indexed a nil table and threw.
	-- 2. Case-insensitive retry. The enUS index stores these identifiers
	--    lowercased ("male-drinnen") while callers pass them capitalised
	--    ("male-Drinnen"). SkuVoice:OutputString happens to retry lowercased,
	--    but direct GetAudiodata callers do not - which is why
	--    SkuCore's tPlayZoneAudio inside/outside announcement has been silently
	--    dead on English clients. Retrying here fixes every direct caller at once.
	local tIndex = SkuAudioFileIndexIntegrated and SkuAudioFileIndexIntegrated[Sku.LocAudio]
	local tLenIndex = SkuAudioDataLenIndexIntegrated and SkuAudioDataLenIndexIntegrated[Sku.LocAudio]
	if tIndex and aString ~= nil then
		local tKey = aString
		if tIndex[tKey] == nil then
			local tLower = string.lower(tostring(aString))
			if tIndex[tLower] ~= nil then tKey = tLower end
		end
		if tIndex[tKey] ~= nil then
			tFile = tIndex[tKey]
			tPath = Sku:IntegratedAudioDir()
			tLen = tLenIndex and tLenIndex[tIndex[tKey]]
		end
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

