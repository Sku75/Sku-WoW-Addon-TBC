# Sku.toc (+ embeds.xml)
- Purpose: The addon manifest and library-embed manifest that define WoW's file load order for Sku. `Sku.toc` declares interface version, title, SavedVariables, and the ordered list of Lua/XML files WoW parses at load; `embeds.xml` (referenced from the TOC) pulls in the Ace3 / LibStub library stack. Load order here is the authoritative dependency ordering for the entire addon.

## Public API / exports
- TOC metadata: `Interface: 11508` (TBC Anniversary), `Title: Sku v42.00`, `Version: 42.00`, `SavedVariables: SkuOptionsDB, SkuTranslatedData, SkuErrorLog, SkuDebugLog`.
- Not code — no functions. Exports are implicit: the ordered file list and the embedded libraries.

## Dependencies (outgoing)
- embeds.xml loads (in order): LibStub, AceAddon-3.0, CallbackHandler-1.0, AceConsole-3.0, AceGUI-3.0, AceDB-3.0, AceConfig-3.0, AceDBOptions-3.0, AceEvent-3.0, AceLocale-3.0, AceSerializer-3.0, AceComm-3.0, LibSharedMedia-3.0.
- Standalone libs loaded directly by the TOC (outside embeds.xml): LibRangeCheck-3.0, LibGearScore-1.0, and Sku's own SkuTTS-1.0 / SkuVoice-1.0 / SkuBeacon-1.0.
- Companion addons (not in this list, loaded separately): SkuBeaconSoundsets (hard TOC dependency elsewhere), SkuNavData, SkuHealthAssets, SkuAudioData_* language pack.

## Key data structures
- Load-order phases (top to bottom):
  1. `SkuPerfFileStamp.lua` — stamp harness first so it can measure everything after.
  2. SkuAudioData assets + Core (audio file index/length tables).
  3. `embeds.xml` — the Ace3 library stack.
  4. Standalone libs: LibRangeCheck, LibGearScore.
  5. Locales: `enUS.lua` then `deDE.lua`.
  6. `_psA` → `routedata_global_wotlk.lua` (~30MB) → `_psB` (WotLK route data, stamped).
  7. `Core.lua`, `SkuDeferredData.lua`, `SkuDBTools.lua` — addon core + DB tooling.
  8. `SkuUtil.lua`, `SkuState.lua`, then `SkuZOptions/SkuSettings.lua` + `SkuZOptions/SkuMenu.lua` (settings facade + menu registry loaded EARLY, before most modules that register into them).
  9. Sku libs: SkuTTS, SkuVoice, SkuBeacon.
  10. `SkuDispatcher/Core.lua` — central event broker.
  11. SkuChat (Core + Options).
  12. `SkuCore/` block — Core.lua + ModuleManager + ErrorLog first, then ~35 feature files (gameWorldObjects, minimapScanner, auctionHouse, mail, aq/aqCombat, dungeonBrowser, equipmentSets, combatMenuKeys, companionPacks, etc.). `SkuCore/lfg.lua` is commented out (Dungeon-Browser rebuilt).
  13. `_psC` → SkuDB block: `SkuDB/Core.lua` + assets (maps, waypoints, quests/creatures/items/objects/spells + *_fixes, polygons), `_psD` → `routedata_global.lua` (~18MB) → `_psE` → tasks, then WotLK assets, then SoD assets, `SkuDB/ChunkLoader.lua`, `_psF`.
  14. SkuMob (Core + Options).
  15. SkuNav (Core, specialNavigationTasks, Visited, SkuMM, data, Options, importExport).
  16. SkuQuest (Core + Options).
  17. SkuAuras (Core, defaultAuras, data, Options, sharing).
  18. `SkuZOptions/` tail: utilities, Core, data, templates, Options, SkuKeyBinds — the menu-builder framework loaded LAST so it sees all registered nodes.

## Events
- none (manifest files).

## Settings keys
- Declares the four SavedVariables scopes: `SkuOptionsDB` (AceDB settings), `SkuTranslatedData`, `SkuErrorLog`, `SkuDebugLog`. Actual keys are set by consumer modules.

## Entry points
- none directly; every module's entry points are wired by the files this manifest loads.

## Invariants & gotchas
- Ordering is load-bearing: SkuSettings + SkuMenu load before the SkuCore feature files that register into them; SkuZOptions core/templates/SkuKeyBinds load LAST so keybinds and menu templates see the full tree. Reordering can break registration or produce nil-reference load errors.
- The `_ps*` stamp stubs must stay bracketing the big route files and the SkuDB block, else the load-time attribution is meaningless.
- Two ~large route data files (`routedata_global_wotlk.lua`, `routedata_global.lua`) plus the SkuDB `assets/` tables are gitignored on disk (~290MB) but MUST be present in the TOC list for the addon to run.
- `SkuCore/lfg.lua` line is commented (`#`) — an intentional removal, not a load entry; ChunkLoader.lua at the end of the SkuDB block is the only non-asset SkuDB file after the data.
- Version string appears twice (`## Title` and `## Version`) — keep them in sync on release bumps.
