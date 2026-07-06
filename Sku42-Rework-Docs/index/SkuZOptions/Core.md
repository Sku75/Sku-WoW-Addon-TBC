# SkuZOptions/Core.lua

- Purpose: The heart of the Sku menu framework (about 6800 lines). Defines the `SkuOptions` AceAddon (AceConsole + AceEvent + AceComm) that owns the whole audio-menu system: AceDB setup (`SkuOptionsDB` via SkuSettings-built defaults), the invisible menu frames and keyboard dispatcher, the two secure click buttons, the in-combat modal capture frame, filtering/type-ahead, voice announcement of the focused entry, the GossipList-to-menu renderer for window mirroring (bags, merchant, equipment, talents ...), the AceConfig-options-to-menu renderer (`IterateOptionsArgs`), the /sku slash command, the quick-overview reader (Shift-Up/Down), soft-targeting CVars, wiki/tooltip link reading, loot-roll handling, group tracking comms and import/export of waypoint data. Almost every other module builds its menus through the functions in this file.
- Companion files: menu item templates and the `SkuOptions.MenuMT` metatable live in `SkuZOptions/templates.lua`; keybind storage/matching in `SkuZOptions/SkuKeyBinds.lua`; root layout registry in `SkuZOptions/SkuMenu.lua`; `SkuSpairs`/helpers in `SkuZOptions/utilities.lua`.

## Public API / exports

Addon object and embedded libs
- `SkuOptions` — AceAddon; embeds AceComm; carries `SkuOptions.TTS` (SkuTTS-1.0 reader frame), `SkuOptions.Voice` (SkuVoice-1.0, all speech), `SkuOptions.BeaconLib` (SkuBeacon-1.0), `SkuOptions.Serializer` (AceSerializer), `SkuOptions.RangeCheck` (LibRangeCheck-3.0), `SkuOptions.LGS` (LibGearScore).
- `SkuOptions.db` — the AceDB database (`SkuOptionsDB`), created in `OnInitialize`; profile callbacks wired to OnProfileChanged/Copied/Reset.

Lifecycle
- `SkuOptions:OnInitialize()` — registers every module's defaults via `SkuSettings:RegisterModuleDefaults(...,"profile",...)` + `BuildDefaults`, creates AceDB, registers slash commands and events, creates the control/main/menu frames.
- `SkuOptions:OnEnable()` — applies stored sound-channel/sound-setting CVars (with a -1 sentinel meaning "seed from current Blizzard CVars", and a 0-MasterVolume corruption guard), seeds `overviewPages` defaults. Early-returns in combat.
- `SkuOptions:OnDisable()` — empty.
- `SkuOptions:OnProfileChanged() / OnProfileCopied() / OnProfileReset()` — re-run PLAYER_ENTERING_WORLD of SkuChat/SkuNav, rebuild keybinds, pcall-OnEnable every module, announce by voice. Reset additionally wipes routes and rebuilds the waypoint cache via `SkuNav:LoadDefaultMapData(true)` (DB-rework lever E).

Menu open/close and state
- `SkuOptions:IsMenuOpen()` — `OnSkuOptionsMain` visible?
- `SkuOptions:CloseMenu()` — synthesizes an OPENMENU click to toggle closed.
- `SkuOptions:CreateMainFrame()` — builds `OnSkuOptionsMain` (see Entry points).
- `SkuOptions:CreateMenuFrame()` — builds `OnSkuOptionsMainOption1` key dispatcher + both secure buttons + `SkuMenuCapture` + `SkuCombatBlockProbe` (see Entry points).
- `SkuOptions:CreateControlFrame()` — `SkuOptionsControl` frame with a 0.1 s OnUpdate that auto-hides the TTS reader when Shift is released (and resets link state on the current node).

Menu construction API (used addon-wide)
- `SkuOptions:InjectMenuItems(aParentMenu, aNewItems, aItemTemplate)` — THE central node factory: `children + template` uses `MenuMT.__add` to clone the template, sets `.name`, `.parent` and wires the `.prev`/`.next` sibling chain; returns the last created node. Without a template it replaces `.children` wholesale.
- `SkuOptions:IterateOptionsArgs(aArgTable, aParentMenu, tProfileParentPath, aModule, aKeyPrefix, aIncludeHidden)` — renders an AceConfig-style options.args table into menu nodes (toggle/select/range/execute; groups recurse). W1-C/W2-MC1: when `aModule` is passed and a leaf has no inline get/set it becomes "schema-managed" (`skuManaged`) and reads/writes through `SkuSettings:Get/Set(module, keyPrefix..key)`. `forAudioMenu = false` entries are skipped unless `aIncludeHidden` (the W7 relocation lever; storage key stays identical).
- `SkuOptions:MenuBuilderLocal(aParentEntry)` — builds the "Local" window mirror from `SkuCore.GossipList` plus registered `SkuCore.localWindowContributors` (mail/AH/social); inserts an "Empty" placeholder when nothing is open.
- local `SkuIterateGossipList(list, parentMenu, tab)` — ~800-line renderer of GossipList entries into menu nodes; carries over textFull/itemId/bagSlot/bag/slot/liveName/directClickButton/onEnter; builds the click payloads (see lifecycle below) and the per-item context submenu (Kaufen with 20-stack buy ticker, Sockeln, Zerstören, split, Add Link to chat, auto-sell-junk marking, AH sell menu via `SkuCore:AuctionHouseBuildItemSellMenu`).
- `SkuOptions:ConfirmationDialog(aParent, onOkFunc, message, yesText, noText)` — injects a yes/no confirm submenu.
- `SkuOptions.CameraMenuBuilder(self)` — the Einstellungen -> Kamera menu (Sku-Standard lock vs free mode, distance/height/pitch/follow/UI-toggle/transition/over-shoulder/nameplates), persisting user values in `db.char["SkuCore"].cameraOptions`.

Filtering / type-ahead
- `SkuOptions:ApplyFilter(aFilterstring)` — sorting lists only: snapshots `parent.children` into file-local `tOldChildren`, builds a filtered list headed by a "Filter;<string>" pseudo-entry, rewires prev/next; empty string restores the snapshot.
- `SkuOptions:ClearFilter()` — drops the snapshot flag and empties `SkuOptions.Filterstring`.
- `SkuOptions:JumpToFilterMatch(aFilterstring)` — non-sorting lists: cursor jump to first match, list untouched.
- `SkuOptions:GetActiveFilterBase()` / `SkuOptions:RefreshActiveFilterView(aParent)` — live-filter support for growing lists (AH results): append into the snapshot base and rebuild the visible subset without moving the cursor.
- local `SkuMenuFilterMatch(aName, aFilterstring)` — shared normalized match predicate (lowercase, OBJECT-id and ;/# flattening, strips big/fractional numbers).

Voice announcement
- `SkuOptions:VocalizeCurrentMenuName(aReset, aReturnAsString)` — the single "speak the focused entry" path: runs `RefreshLiveName` (live values), pcall-runs `BuildChildren` (isolated so a builder error cannot silence the name), expands "Filter;..." spelling, splits `prefix#name`, prepends the sibling index when `vocalizeMenuNumbers` (unless `noMenuNumbers`), appends L["plus"] when `vocalizeSubmenus` and children exist; gated by the bag-settle suppress (`Sku.tBagAnnounceSuppress` / `tBagAnnounceForce`); mirrors the text to `SkuCore.VisualAids:VisualAidsLineBarSet`.
- `SkuOptions:VocalizeMultipartString(aStr, aReset, aWait, ...)` — thin wrapper around `Voice:OutputStringBTtts` (engine 2); large commented-out legacy per-segment audio-file path.
- `SkuOptions:StopSounds(aNumberOfSounds)` — plays Sku's own 1 s silence file on the Dialog channel and stops the N handles before it (NPC-greeting mute trick; no-op when `playNPCGreetings`).
- `SkuOptions:StartStopBackgroundSound(aStartStop, aSoundFile, aHandle)` — looped background sound per handle (menu-open ambience, minimap-warning purr) with self-rescheduling `C_Timer.NewTimer` of the file length from `SkuCore.BackgroundSoundFilesLen`.

Bag post-action confirm machinery (globals, called from secure macrotexts)
- `SkuCaptureSellState()` — global for `/script` in macros: before a `/use bag slot` runs, records path/index/bagSlot/itemId of the focused item into `Sku.tBagPostAction` with a 2.5 s deadline.
- `SkuBagConfirmRefresh()` — event-driven confirm (debounced from BAG_UPDATE in SkuCore): quiet `CheckFrames` rebuild, re-pin cursor by stable identity (bagSlot > itemId > origIdx via local `tPickBagTarget`), then a 0.3 s settle timer forces exactly one announce (`Sku.tBagAnnounceForce`).
- `SkuRestoreSellPosition()` — timed fallback that just calls SkuBagConfirmRefresh.
- `SkuBagIdleRefresh()` — silent re-sync used by auto-sell-junk; only acts when the cursor is inside the L["Local"] subtree.
- `SkuClearBagPostAction()` — cancels the whole pending confirm + timers; called when the user navigates during the settle window (input = settle signal).
- `SkuStepBackAndRefresh()` — global for macros: step cursor to parent, CheckFrames, then re-anchor to a still-attached ancestor if the node got orphaned (locals `tIsAttached`/`tFindAttachedAncestor`).

Info/reader features
- `SkuOptions:UpdateOverviewText(aPageId)` — builds the Shift-Up/Down quick-overview sections (raid, party+loot method, general incl. PvP/repair/money/bags/time/mail/hearthstone/XP/gearscore/NWB layer, buffs incl. tracking spells and weapon enchants, debuffs, skills, reputation, guild incl. roster-cache fallback, pet, cooldowns), ordered by `overviewPages[page].overviewSections[section].pos` (999 = hidden).
- `SkuOptions:AddExtraTooltipData(aTextFull, aItemId)` — normalizes textFull (string/function/table); the item-lookup rating branch is effectively vestigial (computes and discards).
- `SkuOptions:GetLinkFinalRedirectTarget(aLinkName)` / `FormatAndBuildSectionTable(...)` / `LoadLinkDataToTooltip(aLinkName, aDontAddToHistory)` — SkuDB.Wiki article reading: redirect resolution with cycle guard, wiki-markup formatting (bold/enum handling per `SkuAdventureGuide.formatEnumsInArticles`), section split on `=`-headings, feeds `SkuOptions.TTS`, maintains `linksHistory` for Shift-Backspace.
- `SkuOptions:GetCurrentRollItem()` — scans GroupLootFrame1..6 for the visible roll, enriches with AtlasLoot favorite priority; used by the roll keybinds and loot-roll events.
- `SkuOptions:PrintLastBugsackErrors(n)` — prints last n BugSack errors.
- `SkuOptions:UpdateSoftTargetingSettings(aKey)` — idempotent writer of the nine SoftTarget* CVars from `softTargeting` settings (local `tSetSoftTargetCVar` cache logs one from->to line per real change); combat-deferred via `SkuOptions.tSoftTargetDeferred` + a PLAYER_REGEN_ENABLED frame.

Misc utilities
- `SkuOptions:TableCopy(t, deep, seen)` — table copy skipping userdata/`frame`/key 0.
- `SkuOptions:Serialize(...) / Deserialize(s)` — AceSerializer passthroughs.
- `SkuOptions:EditBoxShow(aText, aOkScript, aMultilineFlag)` — shared scrollable edit box (export etc.); clears any leftover OnKeyDown on the SHARED edit box before reuse (mail-compose gotcha).
- `SkuOptions:EditBoxPasteShow(aText, aOkScript)` — 1-byte-max paste sink that reassembles pasted text from OnChar into `SkuOptionsTextBuffer` (lag-free mass paste).
- `SkuOptions:ImportWpAndLinkData()` / `ExportWpAndLinkData()` — waypoint/link (de)serialization into `SkuDB.SessionRouteData` (+ SequenceNumbers/WaypointLevels from `SkuDB.routedata["global"]`); import rebuilds the waypoint cache. A whole older ExportWpAndLinkData version sits in a block comment.
- `SkuOptions:ShowVisualMenu() / HideVisualMenu() / ShowVisualMenuSelectByPath(...)` — optional sighted-helper AceGUI TreeGroup mirror of the whole menu (setting `visualAudioMenu`).
- `SkuOptions:SendTrackingStatusUpdates(aStatusUpdate)` / `ProcessComm` / `OnCommReceived` — "Sku" AceComm group-status protocol (follow/interact/loot/ride/cast flags to raid/party/whisper tracking targets).
- `SkuOptions:DebugToChat(...)` — legacy chat logger gated by `SkuOptions.DebugToChatFlag` (default true).
- `nDCFAddMessage(...)` — GLOBAL replacement for `DEFAULT_CHAT_FRAME.AddMessage` that swallows "is no player with"-whisper errors and prunes `SkuOptions.TrackingTargets` / SkuFluegel targets.
- `SkuOptions:SlashFunc(input)` / `SlashFuncSkuChat` / `SlashFuncPquit` — see Entry points.
- Event methods: `PLAYER_ENTERING_WORLD`, `GUILD_ROSTER_UPDATE`, `START_LOOT_ROLL`, `CANCEL_LOOT_ROLL`, `LOOT_SLOT_CHANGED`.
- local `SkuItemHasSockets(aItemLink)` — GetItemStats EMPTY_SOCKET probe; currently unused (the Sockeln entries use direct Socket*Item calls).

## Dependencies (outgoing)

- Libs: AceAddon/AceEvent/AceConsole/AceComm/AceSerializer/AceDB/AceDBOptions/AceConfig/AceConfigDialog/AceGUI, SkuTTS-1.0, SkuVoice-1.0, SkuBeacon-1.0, LibRangeCheck-3.0, LibGearScore.1000, optional NovaWorldBuffs and BugSack.
- Sku modules: SkuSettings (facade for nearly all settings access), SkuMenu (`AssembleRoot` root layout), SkuState (`IsInCombat`/`IsMoving` gates), SkuCore (CheckFrames, GossipList, interactFramesList, localWindowContributors, Update*RootEntry, SetOpenMenuAfter*, Aq/aqCombat/DamageMeter/GameWorldObjects/Socketing/VisualAids/DungeonBrowser, AuctionHouseBuildItemSellMenu, talentSet, Debug), SkuNav (route/waypoint cache, CancelNavigationSilent, PLAYER_ENTERING_WORLD), SkuChat, SkuMob, SkuQuest, SkuAuras, SkuAdventureGuide, SkuDispatcher (one TriggerSkuEvent), SkuUtil (Unescape), SkuDB (Wiki, itemLookup, SessionRouteData, routedata, WotLK.enchantIDs, SpellDataTBC), SkuFluegel (optional).
- Cross-file globals it expects: `SkuGenericMenuItem` + `SkuOptions.MenuMT` (templates.lua), `SkuOptions:SkuKeyBindsMatchKey/SkuKeyBindsGetKeys/SkuKeyBindsUpdate/SkuKeyBindsResetBindings` (SkuKeyBinds.lua), `SkuSpairs` (utilities.lua), `TooltipLines_helper`, `SkuScanningTooltip`, `SkuEpochValueHelper`, `dprint`, `SkuLogCombat`, `Sku.L`/`Sku.Loc`/`Sku.debug`.
- WoW APIs (load-bearing): SetOverrideBindingClick/ClearOverrideBindings, CreateFrame (SecureActionButtonTemplate), EnableKeyboard/SetPropagateKeyboardInput, InCombatLockdown, PlaySound/PlaySoundFile/StopSound, C_CVar Get/SetCVar (sound + SoftTarget* + camera), C_Timer, GameTooltip scanning, container APIs (PickupContainerItem, GetContainerItemInfo, SplitContainerItem, DeleteCursorItem, SocketContainerItem/SocketInventoryItem), inventory APIs (PickupInventoryItem, UseInventoryItem via /click macros), raid/guild/faction/skill/spellbook info APIs, GroupLootFrame buttons, C_VoiceChat.SpeakText.

## Key data structures

- `SkuOptions.Menu` — the root menu array. Assembled once per session on first open by `SkuMenu:AssembleRoot`, then the inline "Barrierefreiheit" (Menue 7) entry is appended; dynamic root entries (Local, Spielmenü, Aktionsleisten) are spliced in/out on EVERY open by `SkuCore:Update*RootEntry` pcalls.
- `SkuOptions.currentMenuPosition` — the cursor: a reference to the focused menu node. The key dispatcher has a recovery guard that resets it to `Menu[1]` if a parallel error niled it.
- `SkuOptions.Filterstring`, file-local `tOldChildren` — type-ahead accumulator and the unfiltered-children snapshot while a sorting filter is active.
- `SkuOptions.MenuAccessKeysChars` / `MenuAccessKeysNumbers` — arrays of type-ahead keys; on menu open each value is ALSO written as a `[key] = key` hash entry into the same table (dual array+hash use).
- `Sku.tBagPostAction` — `{path, origIdx, bagSlot, itemId, deadline, lastName, announced}`; plus `Sku.tBagAnnounceSuppress` (timestamp gate) and `Sku.tBagAnnounceForce` (one-shot pass-through). `bagSlot` is the physical "bag:slot" string identity, `itemId` the item identity for the all-items view.
- `SkuOptions.guildOnlineCache` — array of preformatted guild-member lines, refreshed on GUILD_ROSTER_UPDATE and opportunistically in UpdateOverviewText (async roster workaround).
- `SkuOptions.TrackingTargets` — player names that pinged us via AceComm; `SkuStatus` fields (follow/interacting/looting/riding/casting) feed SendTrackingStatusUpdates.
- `SkuOptions.currentBackgroundSoundHandle` / `currentBackgroundSoundTimerHandle` — per-handle ("default", "map") sound + loop-timer registries.
- local `tSoftTargetCVarCache` — last-applied SoftTarget CVar values (no-op writer cache).
- `SkuDebugLog.blockProbe` — always-on 300-entry ring of ADDON_ACTION_BLOCKED/FORBIDDEN events (TEMP diagnostic, survives /skudebug off).

### Menu item lifecycle
- Nodes are cloned from `SkuGenericMenuItem` (templates.lua) via `MenuMT.__add` inside `InjectMenuItems`; identity fields: `name`, `parent`, `prev`/`next` (sibling linked list), `children` (array).
- A node with `dynamic = true` plus a `BuildChildren(self)` closure builds its submenu lazily: on descend (`OnSelect`), before vocalization (`VocalizeCurrentMenuName` pcalls it), and in SlashFunc path-walking when `#children == 0`.
- Behavior flags carried on nodes (set by the builders here): `sorting` (filter vs type-ahead-jump), `isSelect` + `GetCurrentValue` (pre-position cursor on current value), `OnAction(self, aValue, aName)` (leaf activate), `noStepUpAfterSelect`, `noMenuNumbers`, `textFull` (+ `itemId`, `links`, `linksSelected`, `linksHistory` for the reader), `RefreshLiveName` (live values), `OnEnter` (focus side effects, e.g. staging macrotext), `vocalizeAsIs`, `ttsEngine`.
- Click items (window mirror): `isClickItem = true`; ENTER = left click (`macrotext` on secure button 1, then insecure `OnLeftAction`), Ctrl+ENTER = right click (`rightMacrotext` on secure button 2, then `OnRightAction`), RIGHT arrow = context submenu via `BuildChildren`; `clickGate` (bag-bar slots need a held item); equipment slots get `/click <Slot>` macros with apply-state-aware fallbacks; `directAction = true` skips click semantics and fires `func` straight from ENTER (with error logging into SkuErrorLog and a step-back refresh).
- Navigation methods (`OnNext/OnPrev/OnSelect/OnBack/OnFirst/OnLast/OnKey/OnLeave/OnUpdate`) are template-provided (templates.lua), not defined here — this file only calls them.

### Voice announcement flow
- Every accepted keypress ends in `VocalizeCurrentMenuName` (unless ESC, Shift-reader keys, or the bag settle gate suppresses it) -> `VocalizeMultipartString` -> `SkuOptions.Voice:OutputStringBTtts(..., engine 2)`.
- Sounds: menu open = PlaySound(88) in Option1 OnShow; close = PlaySound(89) in OnHide (skipped during combat handoff via `tSuppressMenuCloseSound`); per-keystroke nav click = PlaySound(811), suppressed when `SkuOptions.tBoundaryHitThisKey` marks that OnNext/OnPrev already played the boundary sound 681.
- Menu open/close announcements go through OutputStringBTtts with overwrite=true so a stale in-flight item announcement is queue-reset first.

## Events

- AceEvent (SkuOptions:RegisterEvent): PLAYER_ENTERING_WORLD (comm registration, AddMessage hook install, pixel recognizer frames, wipes `db.global["SkuAuras"]`, soft-target apply, 3 s delayed guild-roster request), GUILD_ROSTER_UPDATE, START_LOOT_ROLL, CANCEL_LOOT_ROLL, LOOT_SLOT_CHANGED.
- Raw frames: `tSoftTargetRegenFrame` on PLAYER_REGEN_ENABLED (replay deferred soft-target writes); `SkuCombatBlockProbe` on ADDON_ACTION_BLOCKED/FORBIDDEN (always-on ring); `SkuMenuCapture` on PLAYER_ENTERING_WORLD (reset capture state, session marker).
- AceComm: prefix "Sku" (RegisterComm on login; SendCommMessage to RAID/PARTY/WHISPER in SendTrackingStatusUpdates; payload "index-value" strings).
- SkuDispatcher: publishes `SKU_SLASH_MENU_ITEM_SELECTED` (from `/sku menuselect`). No subscriptions here.
- Timers: `SkuOptionsControl` 0.1 s OnUpdate (TTS auto-hide); background-sound loop timers; bag confirm 0.2 s After + 0.3 s settle NewTimer; buy-in-stacks 0.25 s NewTicker; assorted 0.1/0.35/0.5 s refresh timers after click actions.

## Settings keys

- SkuSettings:Sub("SkuOptions") profile scope: `SkuKeyBinds` (whole keybind table, read everywhere), `backgroundSound`, `overviewPages[1..4].overviewSections[section].pos/locName`, `softTargeting.{force, matchLocked, enableDisableOutputInChat, enemy/friend/interact.{enabled, arc, range}}`, `allModules["MenuQuickSelect1..10"]` (saved menu paths), `vocalizeMenuNumbers`, `vocalizeSubmenus`, `soundChannels.{MasterVolume, SFXVolume, MusicVolume, AmbienceVolume, DialogVolume}`, `soundSettings.Sound_*`, `visualAudioMenu`.
- SkuSettings:Sub("SkuOptions", nil, "global"): `devmode`.
- SkuSettings:Sub("SkuCore"): `combatMenuOpen` (the /skucombatmenu opt-in, read at every combat gate).
- SkuOptions.db.profile: `["SkuChat"].WowTtsVoice/WowTtsSpeed/WowTtsVolume`, `["SkuChat"].chatSettings.audioOnNewMessage` (migrated from `.audio` in UpdateMovedAceDbProfileValues), `["SkuNav"].showSkuMM/showRoutesOnMinimap/Routes/beaconVolume`, `["SkuMob"].enemyCombatStatusMode`, `["SkuCore"].playNPCGreetings/doNotHideTooltip/readAllTooltips/interactMove`, `["SkuAdventureGuide"].formatEnumsInArticles`, `testtext` (debug write in FormatAndBuildSectionTable).
- SkuOptions.db.char["SkuCore"]: `aq[talentSet].{player,party,raid}.health*/combat.*` (monitor keybinds), `SellJunkCustomItemIds`, `alIntegration.favorites`, `cameraOptions.{skuStandard, preferFree, userValues}`.
- SkuOptions.db.global: `["SkuNav"].hasCustomMapData`, `["SkuAuras"]` (reset to {} on every login), `["SkuAuras"].log` (/sku record).

## Entry points

- Slash commands: `/sku` (`SlashFunc`; subcommands: version, devmode, errors, record start/stop, test (nameplate/camera test mode), invite, netstats, menuselect, mon, import, export, `L["short"]`+comma-path = open menu and walk to path, mmreset, chatcover, rdatareset, translate), `/skuchat` + `/sc` (SkuChat editbox), `/pquit` (LeaveParty), `/taop` (AceConfig options table).
- `SlashFunc` path-walking is BY LOCALIZED NAME (lowercased) — every window auto-open, quick-select slot and the Escape hook route through it, so renaming/moving a menu node needs a SlashFunc-path sweep (W7 gotcha).

### Frames and keyboard handling chain
- `OnSkuOptionsMain` (Button, off-screen) — the menu's root state frame. Its visibility IS "menu open". Permanent override bindings (bound at CreateMainFrame time, active always) route the global Sku hotkeys to its OnClick: OPENMENU, MENUQUICK1-10 and *SET, marker set/clear (SKUMARKERSET1-8, SKUMARKERCLEARALL), health monitor toggle, combat-monitor keys, soft-targeting toggles/output keys, DEBUGMODE (cycles Sku.debug), roll keys (ROLLNEED/GREED/PASS/INFO), QUESTSHARE (tooltip reader), TARGETHEALTH, STOPTTSOUTPUT, OPENDUNGEONBROWSER, plus SHIFT-UP/DOWN and CTRL-SHIFT-UP/DOWN (overview reader) and PAGEUP/PAGEDOWN redirects to Option1. Its OnClick: MENUQUICK4 = cancel-nav shortcut, MENUQUICK3 = action-bars menu, then hotkey feature dispatch, then the open/close toggle for OPENMENU — closing also force-closes every interact window (`SkuCore.interactFramesList` with a close-button exclude map, mail, auction).
- `OnSkuOptionsMainOption1` (Button, child) — THE key dispatcher. OnShow (out of combat only) binds ALL nav keys as override bindings on itself (arrows, HOME/END, BACKSPACE, ESCAPE, PAGEUP/DOWN, CTRL-RIGHT spell-name, SHIFT-reader keys) and binds every type-ahead char/number key onto UIParent; OnChar forwards typed characters into OnClick. OnClick(key) order: recovery guard -> boundary-flag reset -> PAGEUP/DOWN profession scrolling -> CTRL-RIGHT re-speak -> double-tap detection (skip-empty jump; disabled while combat menu active for mirror lockstep) -> logical key normalization (configured MENULEFTCLICK/MENURIGHTCLICK -> virtual ENTER/RCLICK) -> combat/moving defer gates -> type-ahead accumulation (sorting filter vs jump) -> nav-as-settle bag cancel -> UP/DOWN/LEFT/RIGHT/HOME/END/ENTER/RCLICK/BACKSPACE/ESCAPE dispatch to the node's On* methods -> PlaySound(811) -> TTS auto-hide -> VocalizeCurrentMenuName -> SHIFT-reader textFull handling. OnHide releases capture keyboard, clears overrides (self + UIParent), plays 89, force-closes craft/trade-skill/quest/taxi/gossip/popup frames and the quest log.

### Secure button setup
- `SecureOnSkuOptionsMainOption1` (SecureActionButtonTemplate, "AnyDown") — the ENTER button. OnShow binds all SKU_KEY_MENULEFTCLICK keys (fallback ENTER) to click it with FIXED virtual button "ENTER" (downstream stays key-agnostic). The focused node's `macrotext` is staged onto it by the generic OnEnter in templates.lua. PreClick snapshots `SkuOptions.tPreEnterApplyState` (SpellIsTargeting or GetCursorInfo) BEFORE the macro consumes it — the enchant/oil re-pickup fix. PostClick = Option1's OnClick (insecure dispatch after the secure action).
- `SecureOnSkuOptionsMainOption2` — twin for right click (SKU_KEY_MENURIGHTCLICK, virtual "RCLICK", stages `rightMacrotext`); same PreClick/PostClick pattern.
- Binding refresh on rebind runs the OnShow handlers again (guarded: no-op hidden or in combat).

### Combat menu capture
- `SkuMenuCapture` (plain Frame) — modal in-combat keyboard: override bindings are combat-blocked, but `EnableKeyboard` is not, so this non-secure frame consumes every key while the combat menu is logically open (propagate=false set once out of combat) and routes "MOD-KEY" strings into Option1's OnClick. Enabled from SlashFunc/OpenMenu-key/Option1-OnShow when `combatMenuOpen` opt-in is on and `Sku.combatSecureKeysBound` is not (Path A stand-down); tracked by `SkuOptions.combatMenuActive` (NOT frame visibility — the visual frame cannot Show in combat). ESC = logical close + keyboard release. Hard failsafe in OnKeyDown: any key while capture is not valid disables the keyboard immediately (sacrifices one key, can never lock the player out). Combat-end release is owned by SkuCore:PLAYER_REGEN_ENABLED; PLAYER_ENTERING_WORLD resets state here.
- `SkuCombatBlockProbe` — always-on ADDON_ACTION_BLOCKED/FORBIDDEN recorder into `SkuDebugLog.blockProbe` (marked TEMP, remove later).
- Hooks: `DEFAULT_CHAT_FRAME.AddMessage` replaced once at login with `nDCFAddMessage`.
- Other named frames created here: `SkuOptionsControl`, `SkuChatCover`, `SkuSkriptRecognizer`(+BottomLeft) (blue corner pixels for external tooling), `SkuOptionsEditBox`, `SkuOptionsEditBoxPaste`, AceGUI visual menu.

## Invariants & gotchas

- Root assembly is build-once (`#SkuOptions.Menu == 0` gate); dynamic root entries MUST be re-evaluated on every open AND before SlashFunc path-walks — both call sites exist, keep them in sync.
- The visual menu frame chain is PROTECTED (secure buttons are children of OnSkuOptionsMain): `Show()` is combat-blocked, so in combat the menu is headless — never gate combat behavior on `IsVisible`/`IsMenuOpen` alone; check `SkuOptions.combatMenuActive` too (SkuBagConfirmRefresh does).
- Secure macro staging and override rebinding only work OUT of combat; the logical-key normalization in the dispatcher must handle both the virtual names (ENTER/RCLICK from the secure buttons) and raw key names (from SkuMenuCapture in combat).
- PreClick apply-state snapshot (`tPreEnterApplyState`) is load-bearing for equipment-slot left/right actions; removing it re-introduces the enchant re-pickup bug.
- `SetPropagateKeyboardInput` is combat-restricted — SkuMenuCapture sets it exactly once out of combat; never toggle it in combat.
- Filter state lives in ONE file-local `tOldChildren` — only one filtered list can exist at a time; ApplyFilter un-filters before re-filtering, and anything replacing `parent.children` while filtered must go through GetActiveFilterBase/RefreshActiveFilterView.
- VocalizeCurrentMenuName pcalls BuildChildren on purpose (speak-the-name beats a complete submenu); don't "fix" that into a hard call.
- SlashFunc menu paths, quick-select slots and window auto-open couple to LOCALIZED entry names.
- BuyMerchantItem loop buys in 20-stacks via a NewTicker; PAGEDOWN/PAGEUP are consumed for profession-window scrolling while the menu is open.
- `MenuAccessKeysChars/Numbers` become array+hash hybrids after first open — `#` iteration still works but pairs-iteration over them sees the extra hash keys.
- File starts with a UTF-8 BOM; contains German umlauts — always read/parse with encoding utf-8-sig.
- `SkuOptions.db.global["SkuAuras"]` is wiped on every login here (aura log is session-scoped by design).
- The overview reader and the menu-item reader implement the same SHIFT-key handling twice (CreateMainFrame vs CreateMenuFrame OnClick) — behavior changes must be applied in both places.
