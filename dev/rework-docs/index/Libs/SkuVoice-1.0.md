# Libs/SkuVoice-1.0/SkuVoice-1.0.lua (+ SkuVoice-1.0.xml)
- Purpose: The low-level voice/audio output engine of Sku, registered as LibStub library "SkuVoice-1.0" and exposed project-wide as SkuOptions.Voice. It owns two parallel output paths: a pre-recorded-clip queue (mSkuVoiceQueue, played via PlaySoundFile from the Sku audio index) and a Blizzard-TTS queue (mSkuVoiceQueueBTTS, spoken via C_VoiceChat.SpeakText). It normalises/segments text (SplitString / SplitStringBTTS), maps words to audio files, expands numbers into per-digit clip sequences, strips WoW markup, and drives everything from a single OnUpdate pump on SkuVoiceMainFrame. The .xml simply loads the .lua. Callers throughout the addon reach voice output through SkuOptions.Voice:OutputString / :OutputStringBTtts.
## Public API / exports
- SkuVoice:Create() — builds SkuVoiceMainFrame, registers VOICE_CHAT_TTS_PLAYBACK_FINISHED, installs the OnUpdate pump that services both queues; returns the lib.
- SkuVoice:OutputString(aString, aOverwrite/args-table, ...) — clip-based output: looks each word up in the audio index, expands numbers, queues audio files; falls back to OutputStringBTtts when allChatViaBlizzardTts is on; accepts a positional arg list OR a single options table as arg 2.
- SkuVoice:OutputStringBTtts(aString, aOverwrite/args-table, ..., aVoice) — Blizzard-TTS output: normalises text, appends to mSkuVoiceQueueBTTS with optional SSML tags, supports per-message voice override; routes back to OutputString when Blizzard TTS is disabled for that context.
- [W6-B #12] SkuVoice:SetChatTtsProvider(aFn) — the config seam that decouples this lib from SkuChat's settings namespace: SkuChat calls it in OnEnable passing a function that returns its live TTS param table (WowTtsVoice/Speed/Volume/Tags, neverResetQueues, allChatViaBlizzardTts). Internal `ChatTts()` (module-local) returns `(mChatTtsProvider and mChatTtsProvider()) or mChatTtsDefaults`; all ~17 former `SkuOptions.db.profile["SkuChat"].WowTts*` reads now go through it. Zero behaviour change (provider returns the same live Sub table).
- [W6-B #19] SkuVoice:TokenizeNumberToAudio(aToken, aStrings, aVocalizeAsIs, aMode) — the shared number-to-audio-word decomposition, called by both live output paths (OutputStringBTtts with mode "btts", OutputString with mode "audio"). Extracted from the two copy-pasted blocks; `aMode` preserves their intentional divergence (float handling + the >13000 integer ladder). The dead uncalled third copy `CollectString` was DELETED in #19.
- SkuVoice:StopOutputEmptyQueue(aBlizz, aSku) — stops sounds and clears one or both queues (respects neverResetQueues); default both true.
- SkuVoice:GetAudiodata(aString) — resolves a token to (file, path, length): tries integrated audio index first, then the installed voice pack via Sku:VoicePackAudioDir(); logs a miss via dprint.
- SkuVoice:GetLastPlayedString() / SkuVoice.LastPlayedString — last clip text actually played (verification hook).
- SkuVoice:UtilRound(aNumber, aInterval) — rounding helper for the number-to-clip decomposition.
- SkuVoice:CheckIgnore(aString) — true if the string matches the tLinkIgnoreList (suppresses link collection for menu chrome).
- SkuVoice:Release() — empty stub.
## Dependencies (outgoing)
- LibStub, AceLocale-3.0 ("Sku" locale) as L.
- Globals: SkuOptions (.db profile SkuOptions only now — the SkuChat TTS params come via the #12 provider seam, not a direct read; plus .TTS, .Voice), Sku (Sku.Loc, Sku:IntegratedAudioDir(), Sku:VoicePackAudioDir()), SkuAudioFileIndex, SkuAudioDataLenIndex, SkuAudioFileIndexIntegrated, SkuAudioDataLenIndexIntegrated, dprint.
- [W6-B #12] SkuChat TTS settings NO LONGER read directly — supplied by whatever SkuChat pushes via SetChatTtsProvider (falls back to mChatTtsDefaults if no provider registered, e.g. SkuChat disabled).
- WoW APIs: PlaySoundFile, StopSound, GetTime, C_VoiceChat.SpeakText / StopSpeakingText, IsMacClient, CreateFrame.
- SkuOptions.TTS:GetLinksTableFromString (SkuTTS) for link harvesting.
## Key data structures
- mSkuVoiceQueue — array of clip records: {text, file, wait, length, endTimestamp, soundHandle, doNotOverwrite, soundChannel, dnq, tombstone}. Serviced on the fTime>0.1 branch.
- mSkuVoiceQueueBTTS — array of plain final TTS strings, with sentinel "queuereset" markers to flush pending speech.
- mSkuVoiceQueueBTTS_Speaking — dedupe list of strings currently being spoken (cleared on playback-finished event).
- mSkuVoiceQueueBTTS_Voice — SIDE-map keyed by the exact final queue string -> 1-based voice index; keeps queue entries plain strings, consumed+cleared at dequeue.
- tEmojis / tGenderSuffixes / SapiLangIds / tLinkIgnoreList — static substitution and ignore tables.
- [W6-B #12] mChatTtsProvider (module-local; the registered getter fn) + mChatTtsDefaults (fallback param table used when no provider is set) — see ChatTts()/SetChatTtsProvider above.
## Events
- Frame SkuVoiceMainFrame registers VOICE_CHAT_TTS_PLAYBACK_FINISHED (pops mSkuVoiceQueueBTTS_Speaking[1]).
- OnUpdate pump: TTS branch every ~0.01s, clip branch every ~0.1s. No SkuDispatcher or AceComm here (this is a leaf lib).
## Settings keys
- profile SkuChat: neverResetQueues, WowTtsVoice, WowTtsSpeed, WowTtsVolume, WowTtsTags, allChatViaBlizzardTts — [W6-B #12] no longer read from AceDB here; delivered by the SkuChat-registered provider (the field names are unchanged, they just arrive via ChatTts()).
- profile SkuOptions: useBlizzTtsInMenu, TTSSepPause, soundChannels.SkuChannel (still read directly).
- realm.missingAudio[token] — per-token miss counter (written when a word has no clip).
## Entry points
- No slash commands / keybinds / secure buttons. Pure library; entry is via SkuOptions.Voice from every speaking module.
## Invariants & gotchas
- Two overloaded call conventions: arg 2 may be a boolean (aOverwrite) OR an options table that is destructured; every caller must pick one form consistently.
- mSkuVoiceQueueBTTS_Voice is keyed by the FINAL assembled string, so identical assembled text collides — the comment stresses keeping it a side-map so the "queuereset" sentinel and dedupe stay intact.
- Numbers >20000 or non-integers are silently dropped from speech (deliberate: hides auto-waypoint ids/coords) — see the tNumberTest guard in both output funcs. The number-to-audio decomposition itself is now the single SkuVoice:TokenizeNumberToAudio (#19); the >13000 integer ladder still diverges by mode ("btts" vs "audio"), preserved verbatim pending a by-ear decision to unify.
- [W6-B #20] the dead `if engine then` guard in OutputString was replaced by a plain `do` block (Bug 4 fold-in: a truthy engine into OutputString no longer silently mutes). The fully-commented `StopAllOutputs` (referenced an undefined tValue, called nowhere) was DELETED.
- Mac vs non-Mac branches queue the same value into mSkuVoiceQueueBTTS (the if/else arms are identical) — dead divergence.
