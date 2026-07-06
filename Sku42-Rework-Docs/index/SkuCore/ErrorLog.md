# SkuCore/ErrorLog.lua
- Purpose: Standalone, dependency-free error-capture system. Chains onto the global Lua error handler and listens for LUA_WARNING / ADDON_ACTION_FORBIDDEN / ADDON_ACTION_BLOCKED, writing structured, deduplicated entries with rich per-error context into the SavedVariable global `SkuErrorLog` so they can be read out-of-game (WTF/.../SavedVariables/Sku.lua). Also bridges BugGrabber if present, throttles during combat, and offers a `/skulog` slash surface (show/clear/export/filter). This is the ERROR channel; general traces go to SkuDebugLog via dprint (Core.lua), not here.

## Public API / exports
- SkuErrorLog (global SavedVariable table) — the store itself plus two methods re-attached onto whatever table identity the SV restore produces:
- SkuErrorLog.Append(source, msg, stack) — low-level write (dedupe + recent ring + combat throttle + skuOnly filter).
- SkuErrorLog:Log(module, msg, extraTable) — hand-placed diagnostic entry; extra table is flattened to "k=v" pairs; source becomes "sku:<module>".
- Internal helper families (file-local): tSafeCall/tTruncate/tNow/tFirstStackLine/tFingerprint/tMentionsSku (formatting + fingerprinting), tBuildSessionInfo/tBuildContext (metadata capture), tEnsureStore/tRecordSession/tAppend (write path), tAttachMethods (SV-swap re-attach), tErrorHandler, tDumpSummary/tDumpRecent/tSerialize/tExportWindow (slash surface).

## Dependencies (outgoing)
- None on other Sku modules by design (zero-dependency). Optional soft reads: Sku.L (localization fallback via tL), SkuCore.talentSet, SkuOptions:IsMenuOpen / SkuOptions.currentMenuPosition (context capture only, all pcall-guarded).
- Optional bridge: _G.BugGrabber.RegisterCallback("BugGrabber_BugGrabbed").
- WoW APIs: geterrorhandler/seterrorhandler, debugstack, CreateFrame, GetBuildInfo, UnitName/UnitClass/GetRealmName/GetLocale, GetZoneText/GetSubZoneText/GetInstanceInfo, UnitAffectingCombat, GetTime, GetAddOnMetadata (or C_AddOns variant), DEFAULT_CHAT_FRAME, UIParent/DialogBoxFrame/UIPanelScrollFrameTemplate for the export window.

## Key data structures
- SkuErrorLog.unique — keyed by fingerprint (message[:400] + " || " + first stack line); entry = {source, lastSource, message, stack (full, truncated 4000), firstSeen, lastSeen, count, session, firstCtx, lastCtx}. Cap MAX_UNIQUE=250, evicts oldest firstSeen.
- SkuErrorLog.recent — chronological ring (cap MAX_RECENT=500): {seq (monotonic, survives sessions, resets only on /skulog clear), t, source, message, stackHead (first frame only), session}. THE store to read for a timeline.
- SkuErrorLog.sessions — last 20 login sessions (addon/client version, locale, player, realm, class); tSessionIndex tags entries.
- SkuErrorLog.counters — {total, dropped, seq}.
- SkuErrorLog.config — {skuOnly (default true: only log events mentioning "sku" in msg or stack), enabled}.
- Context table (per entry) — inCombat, zone/subzone/instance, talentSpec, activeGroup, target/targetGuid, menuOpen/menuNode/menuParent.
- Combat-throttle locals: COMBAT_MAX_PER_SEC=5, tCombatErrorCount/tCombatLastReset/tInCombat/tBugGrabberPaused.

## Events
- Frame SkuErrorLogEventFrame: PLAYER_LOGIN (record session, announce active, attach BugGrabber bridge), ADDON_ACTION_FORBIDDEN, ADDON_ACTION_BLOCKED, LUA_WARNING (registered under pcall — may not exist), PLAYER_REGEN_DISABLED/ENABLED (combat throttle on/off + pause/resume BugGrabber bridge), ADDON_LOADED (for "Sku": re-attach methods after SV restore).
- seterrorhandler chain: tErrorHandler logs then calls the previous handler.
- No SkuDispatcher usage (deliberate — must work stand-alone).

## Settings keys
- none (SkuOptions.db untouched; config lives inside SkuErrorLog.config itself).

## Entry points
- Slash: /skulog and /skuerror — subcommands "", show (last 10, #seq-prefixed), clear, export (copyable EditBox window SkuErrorLogExportFrame), all, skuonly, off, on.
- Global error handler chain + the event registrations above.
- Other modules call SkuErrorLog:Log(...) directly (e.g. the directAction catch; lfg, dualspec hold references).

## Invariants & gotchas
- SV-restore table swap (lines 271-298 + ADDON_LOADED handler): WoW replaces the `SkuErrorLog` table AFTER the file runs, orphaning methods attached at parse time. Append/Log are plain locals re-attached via tAttachMethods on ADDON_LOADED and again on PLAYER_LOGIN. Never attach state/methods only at file scope.
- /skulog clear must NOT replace the table (methods are bound to it and other modules hold references) — it empties the data fields in place. Keep that invariant.
- recent stores only stackHead; the full stack for the same message lives in unique[fp].stack — readers needing full stacks must go through unique.
- skuOnly filter defaults true: non-Sku errors are counted in counters.dropped, not stored.
- Combat throttle drops (not defers) beyond 5/sec, and the BugGrabber bridge is fully paused in combat — expect gaps in combat timelines.
- tFingerprint uses only the first stack line, which usually contains file:line of the error site; same message from two sites dedupes separately, but a message with an embedded varying value (e.g. a count) spams unique entries.
- MEMORY.md/CLAUDE.md direction: this file stays the original design — errors only; do not route general breadcrumbs here (use dprint).
