# Libs/SkuVoice-1.0/SkuVoice-1.0.lua (+ SkuVoice-1.0.xml)
- Purpose: The low-level voice/audio output engine of Sku, registered as LibStub library "SkuVoice-1.0" and exposed project-wide as SkuOptions.Voice. It owns two parallel output paths: a pre-recorded-clip queue (mSkuVoiceQueue, played via PlaySoundFile from the Sku audio index) and a Blizzard-TTS queue (mSkuVoiceQueueBTTS, spoken via C_VoiceChat.SpeakText). It normalises/segments text (SplitString / SplitStringBTTS), maps words to audio files, expands numbers into per-digit clip sequences, strips WoW markup, and drives everything from a single OnUpdate pump on SkuVoiceMainFrame. The .xml simply loads the .lua. Callers throughout the addon reach voice output through SkuOptions.Voice:OutputString / :OutputStringBTtts.
## Public API / exports
- SkuVoice:Create() — builds SkuVoiceMainFrame, registers VOICE_CHAT_TTS_PLAYBACK_FINISHED, installs the OnUpdate pump that services both queues; returns the lib.
- SkuVoice:OutputString(aString, aOverwrite/args-table, ...) — clip-based output: looks each word up in the audio index, expands numbers, queues audio files; falls back to OutputStringBTtts when allChatViaBlizzardTts is on; accepts a positional arg list OR a single options table as arg 2.
- SkuVoice:OutputStringBTtts(aString, aOverwrite/args-table, ..., aVoice) — Blizzard-TTS output: normalises text, appends to mSkuVoiceQueueBTTS with optional SSML tags, supports per-message voice override; routes back to OutputString when Blizzard TTS is disabled for that context.
- SkuVoice:CollectString(...) — near-duplicate of OutputString's parsing path but only records missing-audio counts (no playback); used to warm/audit the audio index.
- SkuVoice:StopOutputEmptyQueue(aBlizz, aSku) — stops sounds and clears one or both queues (respects neverResetQueues); default both true.
- SkuVoice:GetAudiodata(aString) — resolves a token to (file, path, length): tries integrated audio index first, then the installed voice pack via Sku:VoicePackAudioDir(); logs a miss via dprint.
- SkuVoice:GetLastPlayedString() / SkuVoice.LastPlayedString — last clip text actually played (verification hook).
- SkuVoice:UtilRound(aNumber, aInterval) — rounding helper for the number-to-clip decomposition.
- SkuVoice:CheckIgnore(aString) — true if the string matches the tLinkIgnoreList (suppresses link collection for menu chrome).
- SkuVoice:Release() — empty stub.
## Dependencies (outgoing)
- LibStub, AceLocale-3.0 ("Sku" locale) as L.
- Globals: SkuOptions (.db profile SkuChat/SkuOptions, .TTS, .Voice), Sku (Sku.Loc, Sku:IntegratedAudioDir(), Sku:VoicePackAudioDir()), SkuAudioFileIndex, SkuAudioDataLenIndex, SkuAudioFileIndexIntegrated, SkuAudioDataLenIndexIntegrated, dprint.
- WoW APIs: PlaySoundFile, StopSound, GetTime, C_VoiceChat.SpeakText / StopSpeakingText, IsMacClient, CreateFrame.
- SkuOptions.TTS:GetLinksTableFromString (SkuTTS) for link harvesting.
## Key data structures
- mSkuVoiceQueue — array of clip records: {text, file, wait, length, endTimestamp, soundHandle, doNotOverwrite, soundChannel, dnq, tombstone}. Serviced on the fTime>0.1 branch.
- mSkuVoiceQueueBTTS — array of plain final TTS strings, with sentinel "queuereset" markers to flush pending speech.
- mSkuVoiceQueueBTTS_Speaking — dedupe list of strings currently being spoken (cleared on playback-finished event).
- mSkuVoiceQueueBTTS_Voice — SIDE-map keyed by the exact final queue string -> 1-based voice index; keeps queue entries plain strings, consumed+cleared at dequeue.
- tEmojis / tGenderSuffixes / SapiLangIds / tLinkIgnoreList — static substitution and ignore tables.
## Events
- Frame SkuVoiceMainFrame registers VOICE_CHAT_TTS_PLAYBACK_FINISHED (pops mSkuVoiceQueueBTTS_Speaking[1]).
- OnUpdate pump: TTS branch every ~0.01s, clip branch every ~0.1s. No SkuDispatcher or AceComm here (this is a leaf lib).
## Settings keys
- profile SkuChat: neverResetQueues, WowTtsVoice, WowTtsSpeed, WowTtsVolume, WowTtsTags, allChatViaBlizzardTts.
- profile SkuOptions: useBlizzTtsInMenu, TTSSepPause, soundChannels.SkuChannel.
- realm.missingAudio[token] — per-token miss counter (written when a word has no clip).
## Entry points
- No slash commands / keybinds / secure buttons. Pure library; entry is via SkuOptions.Voice from every speaking module.
## Invariants & gotchas
- Two overloaded call conventions: arg 2 may be a boolean (aOverwrite) OR an options table that is destructured; every caller must pick one form consistently.
- mSkuVoiceQueueBTTS_Voice is keyed by the FINAL assembled string, so identical assembled text collides — the comment stresses keeping it a side-map so the "queuereset" sentinel and dedupe stay intact.
- Numbers >20000 or non-integers are silently dropped from speech (deliberate: hides auto-waypoint ids/coords) — see the tNumberTest guard in both output funcs.
- The `engine` code path in OutputString is entirely commented out; passing engine currently no-ops that branch. `StopAllOutputs` is fully commented out and references an undefined tValue.
- Mac vs non-Mac branches queue the same value into mSkuVoiceQueueBTTS (the if/else arms are identical) — dead divergence.
