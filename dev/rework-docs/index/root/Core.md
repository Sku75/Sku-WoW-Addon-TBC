# Core.lua
- Purpose: The addon bootstrap and the very first Sku code file in the TOC (after the audio index and the wotlk route data). Creates the global `Sku` table and the addon-private namespace `ns` (exposed as `Sku.ns`), resolves the AceLocale locale, detects/selects the installed SkuAudioData voice pack (W5), provides the central audio-path resolver, installs client-version compat shims for the Container/Minimap APIs, and hosts the whole debug/performance infrastructure: `dprint` + the persisted SkuDebugLog ring, `SkuLogCombat`, `/skudebug`, `/skuperf` with its dump family, the AceAddon per-module load-timing hook, load-milestone capture at ADDON_LOADED/PLAYER_LOGIN/PEW (incl. forced GC and the eviction-proof `SkuDebugLog.loadPerf` capture), and the TEMP `/skufollowprobe` diagnostic.

## Public API / exports
- `Sku` (global table) — the addon root; every later file hangs members off it.
- `Sku.ns` — addon-private namespace (the `...` second vararg), shared across all Sku files (W4 Phase A).
- `Sku.L` / `Sku.Loc` / `Sku.Locs` / `Sku.LocsPartly` / `Sku.LocP` — AceLocale table, active locale string, supported locale lists (LocP falls back to enUS for unsupported client locales).
- `Sku.AudiodataPath` / `Sku.AudiodataPathInfo` / `Sku.AudiodataExtraSpeed` — detected voice-pack addon folder name, how it was picked (metadata / legacy name / name suffix), optional extra TTS speed from TOC metadata. Detection runs at file load in a do-block (lines 97-130) by enumerating `SkuAudioData*` addons and reading `## X-SkuVoicePack-Locale`.
- `Sku:VoicePackAudioDir()` — returns `Interface\AddOns\<pack>\assets\audio\` or nil when no pack; re-reads AudiodataPath every call so legacy pack glue that overrides it later still wins.
- `Sku:IntegratedAudioDir()` — path to the small in-addon SkuAudioData assets for the current locale.
- `Sku:AudioFile(aFileName)` — the one path-join chokepoint for voice-pack files (nil-safe).
- `Sku.toc` / `Sku.isTBC` / `Sku.IsEraSoD` / `Sku.testMode` — client build number, TBC flag (toc >= 20505), SoD flag (via C_Engraving), test flag.
- `Sku.metric` + `Sku:MetricPoint(aText)` — load-time milestone list, seconds since the `debugprofilestart()` at the top of this file.
- `Sku.debug = {print=, log=}` + `dprint(...)` (global) — the general logger; appends to the `SkuDebugLog.lines` ring (cap 2000, amortised trim). Sku42 default: log ON, print OFF.
- `Sku:DebugLogMark(aText)` — writes a dated `=== ... ===` divider line into the ring.
- `SkuLogCombat(aTag, aDetail)` (global) — always-on combat-decision trace into `SkuDebugLog.combatTrace` (ring 300), independent of the Sku.debug flags.
- `Sku.PerformanceData` / `Sku.PerfStats` + `Sku:Probe(aName, aMs)` — combat/runtime probe recorder (count/total/max/last, true running average).
- `Sku.PerfModules` / `Sku.PerfModulesLoad` — per-AceAddon-module init/enable timings from the AceAddon hook; snapshotted at first PEW.
- `Sku:Performance()` — legacy sighted-only on-screen perf frame (creates/toggles the `SkuPerformance` frame).
- `Sku:PerformanceDumpCombat/Load/Files/Modules/Addons/Mem/Cpu(aEmit[, aAllowEnable])` — text readouts of all perf data, each emitting to chat + the SkuDebugLog ring (or a custom emitter).
- Internal helper families: `tDebugArg`/`tDebugLogAppend` (log rendering), `tPerfEmit*`, `tUpdateAddOnCpu`/`tGetAddOnCpu`/`tGetNumAddOns`/`tGetAddOnName` (C_AddOns compat), `tSkuFollowProbe*` (TEMP follow diagnostic sampler).

## Dependencies (outgoing)
- LibStub, AceLocale-3.0 (locale), AceAddon-3.0 (hooked for module timing).
- WoW APIs: C_AddOns/GetAddOnInfo+Metadata (voice-pack detection), C_Engraving (SoD detection + one live override), C_Container/C_Minimap (compat shims), GetBuildInfo, debugprofilestart/stop, collectgarbage, C_Timer.After, CreateFrame, GetCVar/SetCVar (scriptProfile), UnitPosition/UnitDistanceSquared/UnitInRange (follow probe).
- Call-time (not load-time): SkuOptions.Voice (probe announcements), SkuOptions.RangeCheck (LibRangeCheck via SkuCore/RangeCheck), SkuStatus (follow state), SkuFileLoadStamps (from SkuPerfFileStamp.lua).

## Key data structures
- `SkuDebugLog` (SavedVariable, shared with SkuPerfFileStamp/SkuDBTools consumers): `.lines` = ring of `{seq, t="HH:MM:SS", msg}`; `.seq` monotonic; `.combatTrace` = ring of `{t, tag, detail, combat 0/1}`; `.loadPerf` = dedicated eviction-proof array of capture lines overwritten each load.
- `Sku.metric` — array of `{text, secondsSinceCoreLoad}`.
- `Sku.PerfStats[name]` = `{count, total, max, last}`; `Sku.PerformanceData[name]` = true running average (total/count).
- `Sku.PerfModules[name]` = `{init, enableSelf, enableTotal}` (ms); `PerfModulesLoad` = frozen copy at first PEW.

## Events
- Anonymous `tPerfLoadFrame` registers ADDON_LOADED (stamps "Sku files compiled" once for arg1=="Sku"), PLAYER_LOGIN, PLAYER_ENTERING_WORLD (first PEW: freeze module timings, forced full GC behind the loading screen, C_Timer.After(0) "first frame" stamp + silent loadPerf capture).
- Hooks (not events): `AceAddon.InitializeAddon` and `AceAddon.EnableAddon` wrapped once (`Sku._perfHookedAce` guard) — times EVERY Ace3 addon in the client, with a per-depth stack to compute enable SELF time.
- Follow probe: OnUpdate sampler at 0.15 s cadence for ~5 s.

## Settings keys
- none (Sku.debug and all perf state are plain runtime fields; only the `scriptProfile` CVar is read/written).

## Entry points
- Slash: `/skudebug` (on/off/print/log/clear/show), `/skuperf` (load/files/modules/combat/addons/mem/cpu/reset/frame/all), `/skufollowprobe` + `/sfp` (TEMP).
- Blizzard-global overrides at load: `C_Engraving.IsInventorySlotEngravable` wrapped (returns false for negative container indices); on toc > 11403 the DEPRECATED globals `PickupContainerItem`, `GetContainerNumSlots`, `GetContainerNumFreeSlots`, `UseContainerItem`, `GetContainerItemID`, `GetItemCooldown`, `GetContainerItemQuestInfo`, `GetContainerItemInfo`, `SocketContainerItem`, `SplitContainerItem`, `GetContainerItemLink`, `GetContainerItemCooldown`, `SetTracking`, `GetTrackingInfo`, `GetNumTrackingTypes` are (re)defined in _G as C_Container/C_Minimap wrappers — visible to ALL addons.
- SKU_KEY_DEBUGMODE keybind (defined elsewhere) cycles the same Sku.debug flags.

## Invariants & gotchas
- MUST stay the first non-data Sku code file: `Sku = {}` wipes anything stamped on Sku before it runs (that is why SkuFileLoadStamps is a standalone global), and everything after assumes Sku/dprint exist.
- `debugprofilestart()` at line 198 RESETS the shared profile clock mid-load — SkuPerfFileStamp deliberately uses GetTimePreciseSec to survive this; do not add another debugprofilestart elsewhere.
- Voice-pack detection must run at Sku load time (TOC metadata is readable for not-yet-loaded addons); legacy packs with own glue override `Sku.AudiodataPath` AFTER Sku loads and must keep winning — hence resolvers re-read the field per call, never cache.
- `dprint` must stay cheap when off (single flag check, no debugstack); the ring is NOT cleared on /reload while the flags reset each load — the `=== log enabled ===` marker is the session divider.
- loadPerf capture deliberately bypasses the ring (chatty login diagnostics evicted it before); keep dedicated SkuDebugLog fields for anything that must survive ring trim.
- The AceAddon hook times all Ace3 addons client-wide; keep the `Sku._perfHookedAce` once-guard and never error inside the wrappers.
