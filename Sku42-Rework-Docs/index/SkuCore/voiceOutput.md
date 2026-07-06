# SkuCore/voiceOutput.lua
- Purpose: Small compatibility shim that keeps Blizzard's built-in TTS (`C_VoiceChat.SpeakText`) on the SAME audio output device as the rest of the game sound. WoW has two separate output-driver CVars — `Sound_OutputDriverIndex` (PlaySoundFile/music/SFX) and `Sound_VoiceChatOutputDriverIndex` (voice chat + SpeakText) — so without a sync Blizzard's TTS voice can land on speakers while every other Sku output goes to the headset. This file globally wraps `C_VoiceChat.SpeakText` to sync the voice-chat driver to the main driver immediately before each speak call. Note: this is about Blizzard's OWN TTS voice, distinct from Sku's own SkuVoice/SkuTTS pipeline.

## Public API / exports
- `SkuCore:SyncVoiceChatOutputDriver()` — copy `Sound_OutputDriverIndex` into `Sound_VoiceChatOutputDriverIndex` when they differ (pcall-guarded).
- `SkuCore:VoiceOutputOnInitialize()` — initial sync + install the SpeakText wrapper, then retry both on a staggered timer schedule (0.1/0.5/1/2/5 s).
- Locals: `tGetCVar`, `tSetCVar` (C_CVar with GetCVar/SetCVar fallback), `tInstallSpeakPatch` (idempotent global wrapper installer).

## Dependencies (outgoing)
- `C_VoiceChat.SpeakText` — globally wrapped; original stashed at `C_VoiceChat._origSpeakText`.
- `C_CVar.GetCVar`/`SetCVar` with `GetCVar`/`SetCVar` global fallbacks.
- `C_Timer.After` — retry scheduling.
- CVars `Sound_OutputDriverIndex`, `Sound_VoiceChatOutputDriverIndex`.

## Key data structures
- `tSpeakPatchInstalled` (file-local bool) — guards single install of the wrapper.

## Events
- Timers: five one-shot `C_Timer.After` calls (0.1, 0.5, 1, 2, 5 s) re-attempting patch install + sync (belt-and-braces against load-order/API-availability races).

## Settings keys
- none (writes WoW CVars directly, not SkuSettings)

## Entry points
- Global hook: monkey-patches `_G.C_VoiceChat.SpeakText` for the whole session.
- `SkuCore:VoiceOutputOnInitialize` is the entry the addon calls during init (invoked from SkuCore init elsewhere).

## Invariants & gotchas
- The wrapper is a permanent global replacement; `_origSpeakText` is the only handle to the real function. If another addon also wraps SpeakText, ordering matters.
- Retry-timer approach means the patch may install late (up to 5 s) if `C_VoiceChat` isn't ready at init — early SpeakText calls could bypass the sync.
- The pre-call sync body inside the wrapper (lines 68-74) duplicates `SyncVoiceChatOutputDriver` logic inline rather than calling it — minor copy-paste, could delegate.
- Everything is pcall-wrapped, so failures are silent (no logging via dprint/SkuErrorLog).
