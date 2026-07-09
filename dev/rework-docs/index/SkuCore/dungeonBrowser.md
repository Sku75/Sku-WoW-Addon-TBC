# SkuCore/dungeonBrowser.lua

- Purpose: Accessible premade group finder ("Dungeon Browser") built on C_LFGList for TBC Anniversary. Two-phase menu: Phase A = pick roles + check dungeons (strictly level-filtered) + "Selbst anmelden" (creates ONE listing with the first selected dungeon as activity); Phase B = after listing, browse other searching players with invite/whisper per player. Opens/closes automatically with Blizzard's group-finder window (PVEFrame/LFGParentFrame OnShow/OnHide hooks). Implemented as AceAddon submodule `DungeonBrowser` of SkuCore (W4 Phase D toggleable), published handle `SkuCore.DungeonBrowser`. Contains extensive Anniversary-2.5.5 API-shape compatibility probing (multiple signatures per C_LFGList call) and a /who-based player-level cache because the LFG APIs return no levels on this build.

## Public API / exports
- `DungeonBrowser:DungeonBrowserDoEnroll()` — creates the C_LFGList listing from the saved selection/roles (MUST run in hardware-event context via macrotext; table-arg signature with 5-arg fallback), then two staged timers (0.7 s voiced rebuild, 1.6 s silent second pass) switch to Phase B.
- `DungeonBrowser:DungeonBrowserDoUnenroll()` — RemoveListing (also hardware-event gated) + idempotent B→A rebuild timers (0.7/1.6 s).
- Selection mutators (called from menu macrotext): `DungeonBrowserSetSelection(activityID, value)`, `DungeonBrowserDeselectAll()`, `DungeonBrowserToggleRole(role)`.
- `DungeonBrowser:DungeonBrowserBuildMenu(aParent)` — main builder; picks Phase A or B by `tIsListed()`.
- `DungeonBrowser:DungeonBrowserOpen()` — request activities, open Sku menu, lazily inject the top-level entry, SlashFunc-navigate to it, open Blizzard's LFG frame in parallel.
- `DungeonBrowser:DungeonBrowserToggle()` — close menu if open, else Open.
- `DungeonBrowser:DungeonBrowserRebuild()` / `:DungeonBrowserRebuildSilent()` — in-place rebuild of the top entry's children (clears childs/childsByName/numeric slots); Rebuild re-navigates + vocalizes, Silent preserves the cursor by name and stays quiet (used as the second pass so /who results land without interrupting the announcement).
- `DungeonBrowser:DungeonBrowserInit()` — installs the PVEFrame hooks (no menu injection here, see gotchas).
- Who-cache family: `DungeonBrowserQueueWho(name)`, `DungeonBrowserProcessWhoQueue()` (5 s flood throttle, self-rescheduling).
- `DungeonBrowser:OnEnable()` / `:OnDisable()` — arm/disarm driver-frame events, invite-watch events, LFG events, ticker.
- Globals for macrotext: `SkuCoreDungeonStepBack()` (re-announce current position after a toggle), `SkuCoreDungeonStepBackTo(activityID)` (re-pin cursor onto a saved dungeon-entry reference, retried at 0.05/0.20/0.40 s).
- Internal helper families: `tDB()` (settings accessor + role-format migration), `tGetActivityInfo(id)` (tolerant multi-API activity reader; Suggestion-level fields are the real min/max on 2.5.5), `tGetEligibleDungeons()` (aggregates categories 1-9, strict level filter), `tStartSearch()`/`tCollectSearchResults()` (multi-signature search + result normalization incl. isSelf detection and leader info), `tBuildPhaseA`/`tBuildPhaseB`, `tHookPVEFrame`/`tOpenBlizzardLFGFrame`, invite-popup suppression family (`tIsPartyInviteOpen`, `tFireOpen`/`tFireClose`, `tReevaluateMenuAfterInvite`, `tEnsureInvitePopupHooks`).

## Dependencies (outgoing)
- SkuZOptions menu framework: `SkuOptions:InjectMenuItems`, `SkuGenericMenuItem`, `SkuOptions.Menu` (direct top-level injection), `SkuOptions.currentMenuPosition` (direct cursor writes!), `SkuOptions:SlashFunc`, `:IsMenuOpen`, `:CloseMenu`, `OnSkuOptionsMain` OnClick to open the menu; menu-entry `.macrotext` mechanism for hardware-event context.
- SkuSettings facade (char scope), `SkuOptions.Voice:OutputStringBTtts`, `SkuCore:RegisterToggleableModule`, `dprint`, `Sku.L`.
- WoW APIs: C_LFGList (RequestAvailableActivities, GetAvailableActivities, GetActivityInfoTable/GetActivityInfo/GetActivityShortName/FullName, CreateListing, RemoveListing, GetActiveEntryInfo, Search, GetSearchResults, GetSearchResultInfo/MemberCounts/LeaderInfo/PlayerInfo/MemberInfo), C_FriendList.SendWho/GetWhoInfo/GetNumWhoResults, SetWhoToUi, C_PartyInfo.InviteUnit/InviteUnit, ChatFrame_OpenChat, UnitClass/UnitLevel/UnitName, C_Timer, CreateFrame, hooksecurefunc, HookScript.

## Key data structures
- Settings (char): `dungeonBrowser.selection[activityID]=true`, `dungeonBrowser.roles{TANK/HEALER/DAMAGER=true}` (migrated in `tDB()` from the old single `role` string, which is nil'ed).
- `CLASS_ROLES` [classToken] = allowed role list; `ROLE_NAMES` role→localized label.
- Activity info record from `tGetActivityInfo`: {id, name, shortName, minLevel, maxLevel, isHeroic} — defaults 0/999 when the API yields nothing; heroic detected by API flag or name pattern.
- Search-result record from `tCollectSearchResults`: {searchResultID, activityID, allActivities, name, leaderName, leaderLevel/Class/ClassLoc/Role, leaderTank/Healer/Damage, numTanks/Healers/Damage, maxTanks/..., isSelf, _displayActivities, _skip} — normalized from both the retail table form and the classic 14-value form.
- `tDungeonBrowserLevelCache[name]={level,class}` + `tDungeonBrowserWhoQueue` + `tDungeonBrowserWhoLastSent` — /who level workaround.
- `tDungeonBrowserDungeonEntries[activityID]=menuEntry` (Phase A cursor re-pin targets), `tDungeonBrowserPlayerEntries[leaderName]={entry,result}` (Phase B in-place label patching), `tDungeonBrowserBuildLabel(p)` (label builder stored on the module so the /who handler can reach it).
- Hook bookkeeping: `tDungeonBrowserHookedFrames`, `tDungeonBrowserHookedToggles`, `tInDungeonBrowserOpen` re-entrancy flag, `tDungeonBrowserPartyInviteActive` suppression flag.
- `DUNGEON_FRAME_CANDIDATES` = {PVEFrame, LFGParentFrame, GroupFinderFrame} — build-dependent container frames.

## Events
- File-scope anonymous frame (registered at LOAD, not managed by OnEnable/OnDisable): WHO_LIST_UPDATE + CHAT_MSG_SYSTEM — parses /who answers from system chat (`[Name] Stufe X Klasse` patterns) into the level cache and patches player labels in place; also calls `SetWhoToUi(false)` globally at file scope.
- `tInitFrame`: ADDON_LOADED (re-try PVEFrame hooks until all set) + PLAYER_ENTERING_WORLD (once → +2 s Init + LFG hooks); registered in OnEnable, unregistered in OnDisable.
- `tInviteWatchFrame`: PARTY_INVITE_REQUEST / PARTY_INVITE_CANCEL (suppression flag + StaticPopup OnHide hooks); OnEnable/OnDisable managed.
- `tLFGEventsFrame`: LFG_LIST_SEARCH_RESULTS_RECEIVED, LFG_LIST_SEARCH_RESULT_UPDATED, LFG_LIST_AVAILABLE_ACTIVITY_LIST_UPDATED, LFG_LIST_ACTIVE_ENTRY_UPDATE (drives menu OnUpdate refresh / phase switch); OnEnable/OnDisable managed.
- Hooks (permanent, bodies guarded by IsEnabled): HookScript OnShow/OnHide on the three container frames, hooksecurefunc on ToggleLFDParentFrame/TogglePVEFrame, HookScript OnHide on StaticPopup1-4.
- Timers: 0.7/1.6 s phase-transition passes, 5 s /who throttle chain, 0.05/0.20/0.40 s cursor re-pins, 0.3 s invite re-evaluation, 0.6+0.15 s refresh-button announce sequencing. The 10 s auto-refresh ticker is deliberately a no-op now.

## Settings keys
- `SkuSettings:Sub("SkuCore", nil, "char").dungeonBrowser.selection` and `.roles` (read/write, char; `.role` legacy string is migrated away).
- `SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_OPENMENU"].key` (read, to synthesize the menu-open click).
- Module on/off persisted by RegisterToggleableModule.

## Entry points
- Auto-open/close coupled to Blizzard's group-finder window: OnShow/OnHide + toggle-function hooks (whatever key/button the user bound, typically "I").
- Top-level Sku menu entry `L["DB_Label"]` — injected LAZILY into SkuOptions.Menu on first DungeonBrowserOpen (never at login, see gotchas).
- Menu-entry macrotext `/run SkuCore.DungeonBrowser:...` calls (enroll/unenroll/selection/role) — the hardware-event escape hatch; global step-back helpers `SkuCoreDungeonStepBack`/`SkuCoreDungeonStepBackTo`.
- Features menu toggle via RegisterToggleableModule.

## Invariants & gotchas
- `C_LFGList.CreateListing` and `RemoveListing` are hardware-event gated — they only work from macrotext/secure-button click chains; plain OnAction Lua calls get addon_action_blocked (the OnAction fallbacks exist only for audible diagnostics).
- Do NOT inject the top-level entry before the first menu open: SkuZOptions builds the standard root only when `#SkuOptions.Menu == 0`; early injection would suppress the entire default root (documented at tEnsureDungeonBrowserEntry and DungeonBrowserInit).
- On Anniversary 2.5.5 `GetActivityInfoTable` returns real levels only in `minLevelSuggestion`/`maxLevelSuggestion` (classic minLevel/maxLevel are always 0) — the strict level filter depends on reading the suggestion fields.
- /who has a strict ~5 s flood limit and `SetWhoToUi(true)` swallows the CHAT_MSG_SYSTEM reply — the file sets `SetWhoToUi(false)` globally and parses chat; keep the throttle chain.
- The refresh/rebuild paths must not fire OnUpdate when the user is in a DIFFERENT Sku menu (cursor/speech corruption) — every deferred rebuild walks `currentMenuPosition.parent` up to the browser container first; announce timing (0.15 s after OnUpdate's own 0.01 s vocalize) is deliberate Sapi-queue sequencing.
- Party/guild-invite popups briefly hide PVEFrame; the OnHide hook must stay suppressed via `tDungeonBrowserPartyInviteActive`/`tIsPartyInviteOpen` or the Sku menu closes permanently under the invite.
- hooksecurefunc/HookScript hooks are unremovable — every hook body must keep its `IsEnabled()` guard for the module toggle to mean anything.
- Multi-signature pcall probing (Search, CreateListing, GetSearchResultInfo, GetActivityInfo) is load-bearing build compatibility, not cruft.

## Cleanup candidates observed
- `tBuildPhaseB` status line reads `tDB().role` (the legacy field that the migration in `tDB()` nils) → the role part of "DB_StatusListedAs" is always "?"; should read the `roles` table.
- Auto-refresh ticker machinery is dead by design: `tStartRefreshTicker` is a documented no-op yet still receives a carefully built rebuild callback in DungeonBrowserBuildMenu; `tStopRefreshTicker`/the ticker field only cancel a ticker that is never created.
- Who-parse "Pattern 1" and "Pattern 2" (lines 814/817) are the identical regex — the second match can never add anything.
- The WHO_LIST_UPDATE/CHAT_MSG_SYSTEM parser frame is registered at file scope and is NOT unregistered by OnDisable (unlike every other event frame in the file) — the who-cache keeps running with the feature off.
- Phase A checks `dun.unknownLevel` for the level label, but `tGetActivityInfo` never sets that field (defaults 0/999 instead) — dead branch; also the guard in `tIsAnyDungeonContainerShown` (`if not (_G and _G.IsShown) and not _G then`) is a nonsensical always-false condition.
