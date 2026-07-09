# SAPI2SR engine patch — WoW 12.0 TTS compatibility

Binary patches to `sapi2sr_engine.dll` (the NVDA↔SAPI bridge voice) so it works
with WoW's post-12.0 TTS engine. Base build: `SAPI2SR-Setup-1.0.0.0`
(x64 orig Authenticode PE hash `250418EF…`). Patches authored + verified via
Ghidra 12.0.4 headless + capstone (see `../../scratchpad/patch_x64_v2.py`).

Target function: `Sapi2SrTtsEngine::Speak` (`ISpTTSEngine::Speak`) at RVA
`0x9540` (VA `0x180009540`, x64), found via RTTI vtable `Sapi2SrTtsEngine::vftable`
slot 3.

## Patch A — drop bookmark fragments (fixes the spoken "start/end")

WoW 12.0 wraps every utterance in SAPI boundary **bookmarks named `start`/`end`**.
The stock engine's fragment loop concatenates *every* fragment's text without
checking `SPVSTATE.eAction`, so it speaks the bookmark *names*. A compliant SAPI
voice consumes bookmarks silently; a real voice (Hedda) never spoke them.

Fix: in the fragment loop (`0x1800097f5`, walks `SPVTEXTFRAG` via `pNext`,
reads `pTextStart`@`+0x50` / `ulTextLen`@`+0x58`), skip fragments whose
`State.eAction`@`+0x08` == `SPVA_Bookmark` (3). Implemented as a 5-byte `jmp` to
a code cave in `.text` zero-padding (VA `0x1800168f2`) that does
`cmp dword [rsi+8],3 / je <skip 0x18000986d> / <redo clobbered mov r9,[rsi+0x50];
test r9,r9> / jmp back 0x1800097fc`. **Validated**: reproduced the bug and its
absence outside WoW via PowerShell `SAPI.SpVoice` with `<bookmark>` SSML.

## Patch B — route speakSsml → speakText (attempted repeat fix, kept, harmless)

For XML utterances with no replacement rule the engine calls backend vtable slot 3
(`nvdaController_speakSsml`) at `0x180009ba1` (`FF 50 18` → `call [rax+0x18]`);
slot 2 (`nvdaController_speakText`) is at `0x180009bc6`. Changed the one byte
`0x18`→`0x10` at `0x180009ba1+2` to force speakText. **This did NOT fix the repeat
bug** (see below) but is harmless (plain text is fine for a screen-reader bridge)
and left in place. Patched x64 PE hash: `A7F300BA…` (pinned in
`sku-nvda-voice-sign.ps1`).

## The remaining "repeats go silent" problem (NOT yet properly solved)

Symptom: with the NVDA/SAPI2SR voice, a line spoken once is silent on every
revisit; new lines always speak; survives `/reload`; Hedda is fine.

Localisation (all bench-tested):
- Sku Lua queue is healthy — `SpeakText`+`STARTED`+`FINISHED` fire for every
  repeat, no dedup-skip.
- Raw NVDA (`nvdaController_speakText`/`speakSsml`, ± `cancelSpeech`, repeats) —
  always speaks. So not NVDA, not SAPI2SR's forwarding.
- Only reproduces through the full **WoW → SAPI → SAPI2SR → NVDA** chain, and
  only with the bridge voice (Hedda works).

Leading theory: **WoW's 12.0 engine caches synthesized audio by text and replays
it on repeats without re-invoking the voice.** A real voice's cached audio is
audible; the out-of-band bridge returns empty audio AND isn't re-called on a
cache hit → silence.

Current workaround (addon side, `SkuVoice-1.0.lua` `BttsCacheBust`): append a
cycling run of U+200B to each `SpeakText` string so every utterance is a cache
miss. **Works but hacky** — the zero-width spaces perturb NVDA prosody. TODO:
find the exact WoW cache mechanism / a CVar to disable it, or a
prosody-neutral unique token (word-joiner U+2060? trailing spaces if WoW doesn't
trim them for the cache key).
