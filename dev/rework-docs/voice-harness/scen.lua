local H = dofile("harness.lua")
local V, at, say = H.V, H.at, H.say
local name = arg[3]
local S = {}
S.filter = function()
	say(0.00, "1 meter suedost objekt greifenei hinterland 9", true, {scope="menu"})
	say(0.30, "g r", true, {scope="menu"})
	say(0.55, "g r e", true, {scope="menu"})
	say(0.75, "g r e i", true, {scope="menu"})
	say(0.95, "g r e i f", true, {scope="menu"})
	say(2.00, "1 meter suedost objekt greifenei hinterland 9", true, {scope="menu"})
	at(3.00, function() V:EndScope("menu"); V:OutputStringBTtts("menue geschlossen", {overwrite=true, engine="blizz"}) end)
	H.run(12)
end
S.chatnav = function()
	say(0.0, "text: sobald jammal an nicht mehr ist habe ich die chance", true, {scope="menu"})
	say(0.8, "gilde farmica: moin", false)
	for i = 1, 12 do say(1.2 + i * 0.7, "menue zeile nummer " .. i .. " mit etwas text", true, {scope="menu"}) end
	H.run(30)
end
S.chatidle = function()
	say(0.0, "belohnungen plus", true)
	say(0.5, "gilde farmica: moin", false)
	say(0.6, "gilde knuffdich: wb", false)
	H.run(15)
end
S.endscope = function()
	say(0.00, "14 meter nord wegpunkt sturmwind", true, {scope="menu"})
	at(0.15, function() V:EndScope("menu"); V:OutputStringBTtts("menue geschlossen", {overwrite=true, engine="blizz"}) end)
	H.run(8)
end
S.echo = function()
	say(0.0, "sagen eingabefeld", true)
	local s = "hallo zusammen"
	for i = 1, #s do at(0.4 + i * 0.25, function() V:SpeakEcho(s:sub(i, i)) end) end
	at(0.4 + (#s + 1) * 0.25, function() V:CancelBttsOutput(); V:OutputStringBTtts("abgebrochen", {overwrite=true, engine="blizz"}) end)
	H.run(14)
end
S.multi = function()
	say(0.0, "questtext teil eins ist ein laengerer satz", true)
	say(0.0, "questtext teil zwei ist auch laenger", false)
	say(0.0, "questtext teil drei", false)
	H.run(15)
end
-- The stop-output key: ONE press must silence the playing line AND everything
-- still waiting behind it. Healthy: only "teil eins" is audible (cut short).
S.stopkey = function()
	say(0.0, "questtext teil eins ist ein laengerer satz", true)
	say(0.0, "questtext teil zwei ist auch laenger", false)
	say(0.0, "questtext teil drei", false)
	say(0.0, "questtext teil vier", false)
	at(0.8, function() V:StopOutputEmptyQueue(true, true) end)
	H.run(15)
end
-- A spammed key that raises the same UI error on every press, then a priority
-- line. Healthy = the error audible about once per its own duration (never one
-- copy per press) and NOT again after the priority line.
S.errspam = function()
	for i = 0, 29 do say(i * 0.1, "ihr habt kein ziel.", false) end
	say(3.2, "PRIO auktionator schildbuckel", true)
	H.run(20)
end
S.arrows = function()
	for i = 0, 9 do say(i * 0.12, "eintrag " .. i, true, {scope="menu"}) end
	H.run(6)
end
S.mix = function()
	for i = 1, 4 do say(0.0 + i * 0.01, "spam zeile " .. i, false) end
	say(1.0, "PRIO zauber wird gewirkt", true)
	H.run(20)
end
S.mixq = function()
	for i = 1, 4 do say(0.0 + i * 0.01, "spam zeile " .. i, false) end
	say(1.0, "PRIO ohne overwrite", false)
	H.run(20)
end
S.login = function()
	say(0.00, "questie das pirates day feiertag event ist aktiv", false)
	say(0.01, "questie das erntedankfest feiertag event ist aktiv", false)
	say(0.02, "questie das braufest feiertag event ist aktiv", false)
	say(0.05, "raena flinthammer", true)
	say(0.08, "raena flinthammer", true)
	H.run(20)
end
-- Speech that is not Sku's (another addon, a /run) lands in the client in the
-- middle of a typing burst. Healthy: no typed letter is audible after
-- "abgebrochen". Since the v43.7 tail cut the FREMD line itself is flagged
-- OUT-OF-ORDER LATE: tail cuts leave no natural FINISHED during the burst, so
-- the client keeps it parked until Sku goes idle. That one flag is expected.
S.foreign = function()
	say(0.0, "sagen eingabefeld", true)
	local s = "hallo zusammen"
	for i = 1, #s do at(0.4 + i * 0.25, function() V:SpeakEcho(s:sub(i, i)) end) end
	at(1.0, function() C_VoiceChat.SpeakText(0, "FREMD test kirsche von einem anderen addon") end)
	at(0.4 + (#s + 1) * 0.25, function() V:CancelBttsOutput(); V:OutputStringBTtts("abgebrochen", {overwrite=true, engine="blizz"}) end)
	H.run(16)
end
-- A secret value (a pet's health) spoken through SkuVoice:SpeakSecretText. Healthy = the text reaches the client
-- (here "77 percent" / "12 percent"), the queue marker word never does, a menu line before it is cut, a line after it
-- is audible, and only the newest of two quick calls is spoken. The harness has no secret values: plain strings
-- stand in, which exercises the same hand-over.
S.secret = function()
	say(0.0, "menue zeile nummer eins mit etwas text", true, {scope="menu"})
	at(0.6, function() V:SpeakSecretText("%d percent", 77) end)
	say(3.0, "menue zeile nummer zwei", true, {scope="menu"})
	at(5.0, function() V:SpeakSecretText("%d percent", 41) V:SpeakSecretText("%d percent", 12) end)
	say(8.0, "ende", true)
	H.run(14)
end
-- Point 17: a line with a word that has no recording. MW=1 turns the option on: the whole line must reach the client
-- (spoken by Blizzard's voice); MW=0 (the default): nothing reaches the client, the sound path takes it. A line whose
-- words all have a recording never reaches the client. The harness has no audio index, so GetAudiodata is stubbed.
S.missingword = function()
	SkuOptions.db.profile.SkuOptions.useBlizzTtsInMenu = false
	Sku.AudiodataPath = "x"
	SkuOptions.db.profile.SkuOptions.soundChannels = { SkuChannel = "Talking Head" }
	SkuAudioDataLenIndex, SkuAudioFileIndex = {}, {}
	SkuOptions.db.realm = {}
	local tOn = (os.getenv("MW") == "1")
	V:SetChatTtsProvider(function() return { WowTtsVoice = 1, WowTtsSpeed = 3, WowTtsVolume = 50, blizzTtsForMissingWords = tOn } end)
	V.GetAudiodata = function(self, w) if w == "hallo" or w == "welt" then return "a.mp3", "p/", 0.5 end end
	at(0.5, function() V:OutputString("hallo welt", true, true, 0.5) end)
	at(2.0, function() V:OutputString("hallo xyzname welt", true, true, 0.5) end)
	H.run(8)
end
S[name]()
H.report(name)
