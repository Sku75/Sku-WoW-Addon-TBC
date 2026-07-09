# SkuCore/Core.lua

- Purpose: The heart of the SkuCore module (4400 lines). Creates the `SkuCore` AceAddon, registers all of SkuCore's SkuDispatcher event callbacks, runs the two central OnUpdate loops (target cycling / player-state announcements / stuck detection / deferred menu open), and implements the generic window-accessibility machinery: `CheckFrames` + `IterateChildren` turn any visible Blizzard interact frame into a Sku menu tree ("Local" menu). Also owns player-movement flag tracking (hooksecurefunc on all movement functions), combat enter/leave handling incl. the combat-menu handoff, login/first-run setup (CVars, profiles, bindings), the panic mode breadcrumb-beacon, WoW keybinding management helpers, and the shared confirm dialog. W4-E1b moved most feature methods off this file into namespaces; W4-E2 (slimming Core.lua further) is still open.

## Public API / exports
- `SkuCore` — the AceAddon object (AceConsole, AceEvent); also globals `SkuCoreDB`, `SkuCoreMovement`, `SkuStatus`, `CLASS_IDS`, `skudebuglevel`.
- `SkuCore:OnInitialize()` — registers ~45 SkuDispatcher event callbacks (see Events).
- `SkuCore:OnEnable()` — builds the secure CTRL-SHIFT-TAB target-cycle button, the `SkuCoreControl` OnUpdate loop, the `SkuCoreControlOption1` keybind-router button, and installs all movement hooksecurefunc hooks.
- `SkuCore:CheckFrames(aForceLocalRoot, aDontClose, aQuiet)` — THE central "render open Blizzard windows into the Local menu" pass; decides auto-descend vs Local root vs close, handles combat char-mirror special cases.
- `SkuCore:IterateChildren(t, tab)` — recursive visible-widget walker; extracts text (FontString/tooltip scan via SkuScanningTooltip), OnClick funcs, item ids/counts; returns the nested `childs` result table used by CheckFrames.
- `SkuCore:UpdateLocalRootEntry()` / `UpdateGameMenuRootEntry()` / `UpdateActionBarsRootEntry()` — idempotent splice-in/out of the three dynamic root menu entries (Local, Spielmenü, Aktionsleisten).
- `SkuCore:HasLocalContent()` / `AnyWindowContributorVisible()` — visibility predicates for the Local root.
- `SkuCore:ActionBarsShowHandler()` — Shift-F11 entry; `SkuCore:GameMenuShowHandler()` — Escape entry (via ToggleGameMenu hook).
- `SkuCore:PLAYER_REGEN_DISABLED/ENABLED` — combat enter/leave: menu handoff to headless SkuMenuCapture or close; restore visual menu after combat.
- `SkuCore:PLAYER_ENTERING_WORLD` — login/reload setup: combat-flag resync, default profiles, first-login CVar/binding setup, frame hooks, `PrimeCombatMirrors`.
- `SkuCore:PrimeBagMirror()` / `PrimeCombatMirrors()` — build combatBagTree/combatCharTree up front so the first combat of a session can /use items.
- `SkuCore:GENERIC_OnOpen/OnClose` — debounced Show/Hide hook targets for every interactFramesList frame.
- Event handler family (mostly thin): `PLAYER_STARTED_MOVING/STOPPED_MOVING`, `AUTOFOLLOW_BEGIN/END`, `UPDATE_STEALTH`, `PLAYER_CONTROL_LOST/GAINED` + `PLAYER_MOUNT_DISPLAY_CHANGED` (taxi announce), `UNIT_SPELLCAST_*` (casting state + bag-mutating-cast refresh), `BAG_UPDATE`/`BAG_UPDATE_DELAYED` (gated post-action bag confirm), `TRADE_SHOW/CLOSED/ACCEPT_UPDATE`, `PET_STABLE_*`, `GOSSIP_SHOW`, plus many empty stubs.
- Frame-hook handler family: `StaticPopup_Show/Hide`, `QuestFrame*Panel_OnShow/OnHide`, `QuestFrameGreetingPanel_OnShow/OnHide`, `TaxiFrame_OnShow/OnHide`, `TALENTFRAME_OnOpen/OnClose`, `GOSSIP_CLOSED`, `QUEST_DETAIL/FINISHED`, `MERCHANT_SHOW/CLOSED` — nearly all just call CheckFrames.
- `SkuCore:GossipFrameAvailableQuestsUpdate/ActiveQuestsUpdate/OptionsUpdate` — fill `SkuCore.tGossipList` from gossip API varargs.
- Movement/state helpers: `IsPlayerMoving()`, `Distance(sx,sy,dx,dy)`, `ResolveFollowLeader()`, `PlayerIsHunter()`, `CameraSkuStandardActive()` (camera-decoupling truth source), `UpdateInteractMove(aForceFlag)` (AutoInteract CVar + WorldFrame hooks).
- Deferred-open setters (W4 Phase C write API): `SetOpenMenuAfterCombat/Moving/Path(aValue)`.
- Panic mode: `PanicModeStart()`, `PanicModeCollectData()`, `PanicModeStartStopBackgroundSound()` (dead, see gotchas).
- Nameplates: `NAME_PLATE_UNIT_ADDED/REMOVED`, `IsNamePlateVisible(name)`, `GetNamePlateFrameForUnit(unit)`, `PingNameplates()`, `PLAYER_TARGET_CHANGED` (test-mode visual plates).
- WoW binding management: `CheckBound(key)`, `GetBinding(index)`, `SetBinding/SetBinding2(key, cmd)`, `DeleteBinding/DeleteBinding2(cmd)`, `SaveBindings()`, `LoadBindings()`, `ResetBindings(aToWowDefaults)` (applies `SkuCore.Keys.SkuDefaultBindings` from data.lua).
- `SkuCore:ConfirmButtonShow(aText, aOkScript, aEscScript)` — shared editbox/confirm dialog (SkuAuctionConfirm frame), used by AH buy, equipmentSets, mob rename, destroy-item, SkuZOptions.
- `SkuCore:ScheduleMenuFlashRecheck()` — delayed close of the menu when a triggering frame was only a login flash.
- `SkuCore:ItemName_helper(aText)` — short/long text split for menu items; `SkuCore:StartStopGameMenuBackgroundSound()` — retired whale-song, now only stops lingering handles.
- `SkuCore:Debug(text, clear)` — legacy on-screen debug panel (SkuDebug frame).
- Internal helper families: `splitString` (audio-key tokenizer), `CleanUpGossipList` (money-frame collapse, FontString prefixing), `tPlayZoneAudio`/`tCheckZoneNow` (indoor/outdoor announce), `GetTableID`.

## Dependencies (outgoing)
- SkuDispatcher (all event registration), SkuOptions (Voice:OutputString/OutputStringBTtts, SlashFunc, Menu, InjectMenuItems, CloseMenu, IsMenuOpen, SkuKeyBindsMatchKey, BeaconLib, RangeCheck lib handle, TTS, StopSounds, SendTrackingStatusUpdates, VocalizeCurrentMenuName), SkuSettings facade, SkuMenu (Remove), SkuGenericMenuItem.
- SkuCore sibling namespaces/files: MinimapScanner, GameWorldObjects, TurnToUnit, Aq, RangeCheck, AuctionHouse, VisualAids, Friends, GameOptions, Socketing, Build_BagsFrame/Build_CharacterFrame (windows.lua/builders), combatMenuKeys (CombatMenuKeysBindNow/Clear), SkuCore.Keys (data.lua), SkuCore.ScanObjects/ScanTypes (data.lua).
- Other addons/modules: SkuNav (Distance, GetDirectionTo, NavigationModeWoCoordinates_ON_MOVEMENT, GetBeaconSoundSetName, MM draw helpers), SkuQuest (UpdateZoneAvailableQuestList), SkuMob (CreateAndUpdateSkuMenuFrame), SkuUtil (Unescape), SkuDB.objectLookup, SkuAudioFileIndex, Sku.L, dprint, globals `TooltipLines_helper`, `SkuBagConfirmRefresh`, `SkuCaptureSellState`, `SkuLogCombat`, `SkuMenuCapture`, `OnSkuOptionsMain`.
- WoW APIs (load-bearing): hooksecurefunc (movement + frame Show/Hide), SetOverrideBindingClick/ClearOverrideBindings, SetBinding/GetBinding/SaveBindings/LoadBindings, C_Timer, C_CVar/SetCVar, InCombatLockdown, UnitPosition/C_Map, GetCursorInfo, PlaySoundFile/StopSound, GameTooltip + hidden SkuScanningTooltip, UIParentLoadAddOn("Blizzard_CraftUI").

## Key data structures
- `SkuCoreMovement` — `.Flags` (MoveForward/Backward, StrafeL/R, Ascend, Descend, AutoRun, IsTurningOrAutorunningOrStrafing, FollowUnit, PitchUp/Down) set by hooksecurefunc; `.LastPosition{x,y}`, `.counter`, `.FollowStuck{counter,lastGap,baseLibMin,...}` (follow-collision state).
- `SkuStatus` — player-state machine: `zoneType` (nil|"indoor"|"outdoor"), plus timestamps/flags for swimming, submerged, ghost, dead, running/walking, follow (+followUnitId/followUnitName/followEndFlag), riding, flying, stealth, afk, rest, casting, fallingSound/fallingSoundJump.
- `SkuCore.interactFramesList` (array of frame names to hook) + `interactFramesListManual` (frameName → custom builder fn, e.g. Build_BagsFrame, GossipFrame, Build_SocketingFrame) + `interactFramesListHooked` (dedupe map).
- `SkuCore.localWindowContributors` — W7 list {frame, label fn, build fn} for MailFrame/AuctionFrame/FriendsFrame/QuestLogFrame rendered as Local children.
- `SkuCore.GossipList` — the CheckFrames result: per open frame {frameName, RoC, type, obj, textFirstLine, textFull, childs, itemId, func, click, stackSize...} nested tree consumed by the menu builder.
- `SkuCore.outputSoundFiles` — sound-key → "aura;sound#label" display map (aura sound picker).
- Local lookup tables for IterateChildren: `friendlyFrameNames`, `friendlyFrameNamesParts`, `tButtonsWoFontstrings`, `blockedWidgetStrings`, `validTypes`.
- Deferred flags: `SkuCore.inCombat`, `isMoving`, `openMenuAfterCombat/Moving/Path`, `gameMenuActive`, `actionBarsMenuActive`; `tBagMutatingCastSpells` ({[13262]=true} disenchant).
- Panic-mode locals: `tPanicData` (breadcrumb points, max ~500 yd), beacon name "SkuPanicBeacon".

## Events
- SkuDispatcher registrations (OnInitialize): UNIT_SPELLCAST_START (twice), PLAYER_ENTERING_WORLD, PLAYER_LEAVING_WORLD, PLAYER_LOGIN, VARIABLES_LOADED, PLAYER_REGEN_DISABLED/ENABLED, QUEST_LOG_UPDATE, PLAYER_CONTROL_LOST/GAINED, PLAYER_MOUNT_DISPLAY_CHANGED, PLAYER_DEAD, AUTOFOLLOW_BEGIN/END, PLAYER_UPDATE_RESTING, UPDATE_STEALTH, ITEM_UNLOCKED, ITEM_LOCK_CHANGED, BAG_UPDATE, BAG_UPDATE_DELAYED (gated), UNIT_POWER_UPDATE (→SkuCore.Aq), UNIT_HAPPINESS, PLAYER_TARGET_CHANGED, CURRENT_SPELL_CAST_CHANGED, UNIT_SPELLCAST_* (channel start/stop/update, delayed, failed, failed_quiet, interrupted→UIErrors, stop, succeeded), NAME_PLATE_CREATED/UNIT_ADDED/UNIT_REMOVED, PLAYER_STARTED/STOPPED_MOVING, GOSSIP_SHOW, ACTIVE_TALENT_GROUP_CHANGED, PLAYER_TALENT_UPDATE, TRADE_SHOW/CLOSED/ACCEPT_UPDATE, PET_STABLE_SHOW/CLOSED/UPDATE. PLAYER_EQUIPMENT_CHANGED / MERCHANT_UPDATE deliberately NOT registered (breaks merchant nav).
- Raw frame events: file-scope `tZoneEventFrame` registers ZONE_CHANGED_INDOORS/ZONE_CHANGED/ZONE_CHANGED_NEW_AREA/PLAYER_ENTERING_WORLD → indoor/outdoor re-check at +0.3/+0.8/+2.0 s.
- OnUpdate loops: SkuCoreSecureTabButton (every 0.1 s: interactMove, range check, nameplate target macro rewrite); SkuCoreControl (every frame: trainer filter, popup auto-confirm, pet happiness, fall sound; every 0.15 s: panic collect, lazy frame hooks, cursor announce, player-state announces, stuck sound, follow-collision, deferred menu open).
- Timers: panic ticker 0.1 s; many one-shot C_Timer.After (zone checks, bag confirm 0.15 s, prime 0.5 s, login CVar setups at 5/6/10/15/120 s, flash recheck 0.3 s).

## Settings keys
- SkuSettings:Sub("SkuCore") profile scope: `interactMove`, `clickClackRange`, `followCollision`, `readAllTooltips`, `doNotHideTooltip`, `autoFollow`, `fallSettings.soundOutput/.delay/.voiceOutput/.ignoreJumps`, `classes.hunter.petHappyness`, `ressourceScanning.notifyOnRessources` (rw via keybind), `UIErrors` (migration rewrite), `trainerSkillsUnavailableDisabled` (w), `combatMenuOpen`.
- SkuSettings:Sub("SkuCore", nil, "char"): `cameraOptions{skuStandard, preferFree, userValues}` (rw), `scanConfigs[n].objects/.type`, `turnToUnit.targetSelection.key1-6`, `AuctionCurrentFilter` (init), `IsFirstCharLogin` (rw).
- SkuSettings:Sub("SkuCore", nil, "global"): `IsFirstAccountLogin` (rw).
- SkuOptions.db.profile["SkuOptions"]: `localActive` (gates CheckFrames), `SkuKeyBinds[...]` (read for override binds), `soundChannels.SkuChannel`.
- SkuOptions.db.factionrealm["SkuCore"]: `AuctionDB`, `AuctionDBHistory` (init). SkuOptions.db.char["SkuAuras"] (init). SkuOptions.db profiles: creates the four "Standard profil" profiles on first login.

## Entry points
- Keybinds routed through SkuCoreControlOption1 OnClick: SKU_KEY_TURNTOUNIT1-6, SKU_KEY_TURNTOUNITTURN180, SKU_KEY_DOMONITORPARTYHEALTH2CONTI, SKU_KEY_TARGETDISTANCE, SKU_KEY_GROUPMEMBERSRANGECHECK, SKU_KEY_PANICMODE, SKU_KEY_MOUSEFINDER, SKU_KEY_SCANCONTINUE, SKU_KEY_SCAN1-8, SKU_KEY_NOTIFYONRESOURCES, SKU_KEY_MMSCANWIDE/NARROW; plus raw SHIFT-UP/DOWN + CTRL-SHIFT-UP/DOWN (TTS line/section nav). Bindings are set as override binds in the button's OnHide (i.e. active while the Sku menu is closed) and cleared in OnShow.
- Secure button `SkuCoreSecureTabButton` — CTRL-SHIFT-TAB override, macrotext retargeting for untargetable starting-area units.
- Menu nodes: dynamic root entries "Local" (isLocalRoot), "Spielmenü" (isGameMenuRoot), "Aktionsleisten" (isActionBarsRoot) — spliced in/out on demand; window contributors render under Local.
- Blizzard hooks: hooksecurefunc on ~20 movement functions + ToggleRun + StartAutoRun/StopAutoRun; Show/Hide of every interactFramesList frame (twice: OnEnable lazy loop + PLAYER_ENTERING_WORLD 1 s timer), StaticPopup1-5, QuestFrame Progress/Detail/Greeting panels, TaxiFrame, GameMenuFrame Show/Hide, `ToggleGameMenu` (Escape → Spielmenü), GameTooltip OnShow (object announce), WorldFrame OnMouseDown/Up (interactMove).
- Global `PriceDropdown` no-op stub (Anniversary Blizzard_AuctionUI localization crash workaround, lines 27-37).

## Invariants & gotchas
- CheckFrames is async (inner C_Timer.After(0.01)) and re-queues itself while moving; everything downstream (auto-descend rules 1-3, popup branches, combat capture flags) lives inside that deferred closure.
- IterateChildren only sees VISIBLE frames — the combat character mirror must force-Show CharacterFrame first, and CheckFrames is the single chokepoint that hides it again when the mirror is left (line ~3791).
- Menu handoff on combat start MUST hide the visual frame directly (`OnSkuOptionsMain:Hide()`), NOT via CloseMenu — CloseMenu resets currentMenuPosition and speaks "closed" (lines 2857-2873). The capture frame is only enabled when secure nav keys are NOT bound (they would eat the keys).
- `SkuCore.inCombat` is Sku's own flag and lags InCombatLockdown() at combat start — nameplateShowFriends SetCVar additionally checks InCombatLockdown() to avoid ADDON_ACTION_BLOCKED (line ~1193); PLAYER_ENTERING_WORLD re-syncs the flag for login-into-combat.
- openMenuAfter* flags are cleared right after login (spurious stamps from control-frame OnShow) — genuine defers happen later.
- The indoor/outdoor announce deliberately bypasses the voice queue (direct PlaySoundFile via tPlayZoneAudio) and uses IsOutdoors() as sole source ("not outdoors" = indoor) because IsIndoors() is unreliable on TBC Anniversary.
- BAG_UPDATE/BAG_UPDATE_DELAYED handlers are gated on `Sku.tBagPostAction` — they must stay no-ops outside a bag-action window or merchant/flight-master navigation breaks (same reason PLAYER_EQUIPMENT_CHANGED/MERCHANT_UPDATE stay unregistered).
- GENERIC_OnOpen/OnClose honor `SkuCore._suppressGenericFrameHooks` (silent mirror-prime) and a 0.1 s debounce flag; do not bypass.
- Override bindings on SkuCoreControlOption1 follow an inverted Show/Hide convention (OnHide binds, OnShow clears) — the frame being hidden means "menu closed, hotkeys active".
- `splitString`/menu paths couple to localized labels (SlashFunc path-by-label): renaming "Local"/"Spielmenü"/window friendly names breaks CheckFrames re-anchor and auto-descend.
- File starts with a UTF-8 BOM (all Sku Lua files); parse with utf-8-sig.
