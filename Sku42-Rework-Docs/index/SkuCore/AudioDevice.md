# SkuCore/AudioDevice.lua
- Purpose: Accessible audio output-device switcher. WoW's device picker in the options panel is not screen-reader/keyboard accessible, so this module exposes the same functionality (list/select the sound output driver, e.g. speakers vs headset) as spoken slash commands. Implemented as a real AceAddon SUBMODULE of SkuCore (W4 Phase D) so it can be toggled on/off at runtime via the Features menu.

## Public API / exports
- `AudioDevice:OnEnable()` — arms the feature by installing the `/skuaudio` `/audio` slash entry (idempotent).
- `AudioDevice:OnDisable()` — no-op body; slash handler self-gates via IsEnabled().
- `SkuCore.AudioDevice` — published module handle.
- Locals (feature logic): `tSay` (speak via chat + optional direct TTS), `tGetDeviceCount`, `tGetDeviceName`, `tGetCurrentIndex`, `tRestartSound`, `tSetDevice`, `tListDevices`, `tCurrent`, `tFindAndSet`, `SkuAudioSlashHandler`.

## Dependencies (outgoing)
- `LibStub("AceAddon-3.0")` / `SkuCore:NewModule` — submodule creation.
- `SkuCore:RegisterToggleableModule` (ModuleManager) — makes it user-toggleable.
- WoW sound APIs: `Sound_GameSystem_GetNumOutputDrivers`, `Sound_GameSystem_GetOutputDriverNameByIndex`, `Sound_GameSystem_RestartSoundSystem`, `GetCVar`/`SetCVar` on `Sound_OutputDriverIndex`.
- `DEFAULT_CHAT_FRAME:AddMessage` (routes through SkuChat's reader), `SkuOptions.Voice:OutputStringB`/`OutputString` (direct TTS fallback).
- `Sku.L` for all spoken strings.

## Key data structures
- No persistent state. `tFindAndSet` builds a transient `tMatches` list of `{ idx, name }`.
- CVar `Sound_OutputDriverIndex` is 0-based; all iteration runs `0 .. count-1`.

## Events
- none (no WoW event registration; purely command-driven)

## Settings keys
- Feature enable flag lives in ModuleManager's `SkuSettings:Sub("SkuCore").moduleEnabled["AudioDevice"]` (profile). This file writes the WoW CVar `Sound_OutputDriverIndex` directly, not SkuSettings.

## Entry points
- Slash commands: `/skuaudio` and `/audio` (SLASH_SKUAUDIO1/2, `SlashCmdList["SKUAUDIO"]`). Subcommands: (none)=current+help, `list`, `current`, `set <N>`, `find <text>`, `restart`.
- Registered in Features menu as "Audiogerät" / "Audio device".

## Invariants & gotchas
- The SlashCmdList entry is installed once in OnEnable and never removed (SlashCmdList entries can't be cleanly removed); disable path relies on the `if not AudioDevice:IsEnabled() then return end` guard at the top of `SkuAudioSlashHandler`.
- Device index is 0-based throughout — `tSetDevice` validates `0 <= aIndex < count`; off-by-one risk if any caller assumes 1-based.
- All sound API calls are pcall-wrapped with graceful fallbacks (returns 0/"unbekannt"), so a missing API degrades quietly.
- `tSay` double-speaks by design: chat frame (for SkuChat pipeline) AND direct TTS — belt-and-braces; could double up if SkuChat also reads the same line in some configs.
