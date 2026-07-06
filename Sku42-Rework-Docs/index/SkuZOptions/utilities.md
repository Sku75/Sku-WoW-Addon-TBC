# SkuZOptions/utilities.lua
- Purpose: Grab-bag of GLOBAL helper functions plus a large tail of one-off developer/data-migration tooling. The live, load-bearing part is small: item-link parsing, coroutine-sliced table serialization, 64-bit shift emulation, tooltip-text extraction, and the ubiquitous sorted-pairs iterator SkuSpairs. Roughly the second half of the file (lines ~230-1714) is dormant dev tooling for translating the German route/waypoint database to English (feeding the SkuTranslatedData SavedVariable) and for merging/scraping WotLK Questie data — invoked only manually via /script.

## Public API / exports
- SkuGetItemIdFromItemLink(aLink) — returns the itemId segment of an item link (strsplit-based).
- SkuTableToString(aTable, aCallback) — serializes a (string/number/boolean-only) table to a loadstring-able string, sliced over frames via a coroutine on SkuCoroutineControlFrame (one yield per 2500 entries); result delivered to aCallback("return {...}"). Used for bulk data (e.g. auction full scans).
- SkuStringToTable(aString) — loadstring + execute; inverse of the above.
- SkuU64join(hi, lo) / SkuU64split(x) / SkuU64lshift(x, n) / SkuU64rshift(x, n) — 64-bit shift emulation on top of the 32-bit bit library.
- TooltipLines_helper(...) — flattens a tooltip's FontString regions to one text blob; injects "Item Level: N" after line 1 and appends the item-quality string to the name when SkuOptions.db.profile.SkuCore.itemSettings.ShowItemQality is on; reads SkuScanningTooltip first, falls back to GameTooltip.
- SkuSpairs(t, order) — sorted-pairs iterator (keys sorted, optional comparator order(t, a, b)); used addon-wide.
- SkuTranslateStringDeToEn(aString) — translates a semicolon-separated German waypoint-name string to English by cascading lookups: tAdditionalTranslations (local fix-up table) -> SkuDB maps/areas -> NPC names (with a special hare/rabbit coordinate disambiguation) -> objects (weapon-crate fix) -> Glossary1 -> items -> spells -> quests; records misses in SkuTranslatedData.untranslatedTerms.
- SkuTranslatedData — GLOBAL SavedVariable table receiving translation results (DefaultWaypoints2, Links, Waypoints, Comments, objectResourceNames, untranslatedTerms).
- Dev-tool family (manual /script only, all global): SkuTranslateTest, SkuDefaultWp2DeToEn, SkuObjectResourceNamesDeToEn, SkuRtLinkDataDeToEnNEW, SkuRtWpDataDeToEnNEW, SkutmpTrans, SkutmpLinks (waypoint/link DE->EN + id-keyed conversions), SkuSwitchDataToLK (merge SkuDB.WotLK.* into the TBC tables then rebuild caches), getlocdata / getlocdataEN / comparenames (tooltip-scrape localization collectors, self-rescheduling via C_Timer.After), buildennames.
- Local-only: tprint (debug table printer, unused externally), GetElTime / GTT_CreatureInspect (elevator-timer GUID experiments; the tooltip hook is commented out but the GTT_CreatureInspectHooked global guard still runs).

## Dependencies (outgoing)
- bit library (band/bor/lshift/rshift), coroutine + a shared frame `SkuCoroutineControlFrame` (created on demand, OnUpdate pump).
- SkuDB (NpcData, itemDataTBC/objectDataTBC/questDataTBC + WotLK variants, itemLookup/objectLookup/questLookup, SpellDataTBC, ExternalMapID, InternalAreaTable, DefaultWaypoints, routedata, SessionRouteData, objectResourceNames).
- SkuNav (GetAreaData, CreateWaypointCache, LoadDefaultMapData, ClearWaypointsTemporary, LoadLinkDataFromProfile, UpdateQuickWP, GetCurrentAreaId), WaypointCache / WaypointCacheLookupAll globals.
- SkuQuest:BuildQuestZoneCache, SkuOptions.Glossary1 (data.lua), SkuOptions.db, SkuUtil:Unescape, Sku.L, Sku.Loc, dprint.
- WoW: GameTooltip / SkuScanningTooltip / GetDetailedItemLevelInfo / ITEM_QUALITY_COLORS, UnitGUID/GetServerTime, C_Timer, CreateFrame.

## Key data structures
- tAdditionalTranslations (local, ~300 entries) — hand-maintained DE->EN fix-up map for waypoint names and route comments; several literal duplicate keys (last-wins).
- SkuTranslatedData.* — output trees of the migration tools (SavedVariable; shape mirrors SkuDB route data keyed by translated names).
- SkuCoroutineControlFrame — ONE shared named frame reused by every coroutine pump in this file; whichever tool ran last owns its OnUpdate.

## Events
- No WoW event registrations; work is driven by OnUpdate scripts on SkuCoroutineControlFrame and C_Timer.After self-rescheduling loops (getlocdata/getlocdataEN/comparenames).

## Settings keys
- Read: SkuOptions.db.profile.SkuCore.itemSettings.ShowItemQality (TooltipLines_helper).
- Dev tools write: SkuOptions.db.profile["SkuNav"].tNames.deDE/enUS, SkuOptions.db.global["SkuNav"].IdWaypoints.

## Entry points
- None wired: everything below SkuSpairs is reached only by hand-typed /script calls (comments carry the /script lines). SkuTableToString/SkuStringToTable/TooltipLines_helper/SkuSpairs/SkuGetItemIdFromItemLink are called from other modules.

## Invariants & gotchas
- SkuTranslatedData is a SavedVariable (TOC): the migration tools deliberately persist their output for export; do not clear it casually.
- All coroutine pumps share the single SkuCoroutineControlFrame — running two tools concurrently (or SkuTableToString during a tool run) clobbers the other's OnUpdate. SkuTableToString (the only production user) must therefore never overlap another pump.
- SkuSwitchDataToLK line 1470 tests the global `aIsInitialLogin` which is never defined (always nil), so the LoadDefaultMapData branch always runs — dev tool, but note if reusing.
- SkuSpairs and TooltipLines_helper are hot-path utilities used across modules; renaming/moving them is a wide refactor.
- SkuGetItemIdFromItemLink uses strsplit("%:", link) — strsplit treats EACH character as a delimiter, so it splits on "%" too; works for item links only because "%" precedes each ":" is not the case — it survives by accident. Verify before reuse for other link shapes.

## Notable cleanup candidates
- ~1000 lines of dead one-off dev tooling (translation/migration/scrape functions) that could move to a dev-only file or be deleted.
- Eight near-identical copy-pasted coroutine-pump blocks (create frame + OnUpdate + completed flag).
- Global namespace leaks: `tcount` (lines 1498, 1612), GTT_CreatureInspectHooked, all dev functions global; duplicated local names (tSkuCoroutineControlFrameOnUpdateTimer/tCounter re-declared per section).
- tAdditionalTranslations has multiple duplicate string keys (e.g. "Hier auf das Schiff warten !", "Achtung: Questgeber bewegt sich!") — dead entries, last-wins.
