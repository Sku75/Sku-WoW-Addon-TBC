# SkuQuest/Core.lua
- Purpose: SkuQuest is the quest tracking + accessible quest-log module. It intercepts ToggleQuestLog to read/navigate the quest log via Sku's menu/TTS, speaks quest details (title/level/objectives/rewards/text) for the selected quest, monitors objective progress (success sounds), builds quest->zone and quest->waypoint caches, and drives on-map "quest marker beacons" (audio beacons + chat notifications for available and turn-in-ready quests). Runtime-toggleable (W4 Phase D): lifecycle armed in OnEnable, torn down in OnDisable; query/data API stays callable while disabled for SkuNav/SkuChat/SkuCore.

## Public API / exports
- SkuQuest (AceAddon): module table (global).
- Lifecycle: RegisterQuestEvents (re-armable event registration), OnInitialize (creates SkuQuestControl frame), OnEnable (arms events, installs ToggleQuestLog hook once, creates SkuQuestMain/SkuQuestMainOption1 driver frames, re-runs deferred setup), OnDisable (UnregisterAllEvents, cancel timers, clear override bindings, hide frames).
- Quest-log navigation: OnSkuQuestUP / OnSkuQuestDOWN / OnSkuQuestAbandon / OnSkuQuestPush (share), ToggleQuestLogHook (opens Sku menu via SlashFunc when quest log shows; IsEnabled-guarded).
- Reading: GetTTSText(aQuestID) — returns section table for tooltip (used by menu OnEnter); ShowForTTS(aQuestID) — near-duplicate that also pushes to SkuOptions.TTS:Output + speaks; GetQuestTitlesList; CheckQuestProgress(aSilent) — objective-change detection + success sounds.
- Caches/data API: BuildQuestZoneCache (QuestZoneCache quest->areaIds), GetAllQuestWps + QuestWpCache, UpdateAllQuestObjects + questObjects + GetAllQuestObjects, UpdateZoneAvailableQuestList(aForce) — main beacon driver.
- Deferred setup helpers: SetupBeaconSoundSetOptions, ScheduleDeferredSetup, LoadEventHandler (defined in Options.lua).
- Event handlers: QUEST_LOG_UPDATE, UPDATE_FACTION, UNIT_QUEST_LOG_CHANGED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD, VARIABLES_LOADED, QUEST_ACCEPTED/REMOVED/TURNED_IN, ZONE_CHANGED[_NEW_AREA/_INDOORS].

## Dependencies (outgoing)
- SkuDB.questDataTBC / questKeys / questLookup / NpcData / objectDataTBC / objectKeys / itemDataTBC / itemKeys / itemLookup / objectLookup / InternalAreaTable / routedata; Sku:IsDataReady("skudb.<family>") gating (quests/creatures/objects/items).
- SkuOptions.Voice:OutputString/OutputStringBTtts, SkuOptions.TTS (PreviousLine/NextLine/Section, Output, IsVisible), SkuOptions:SlashFunc/CloseMenu/SkuKeyBindsMatchKey, SkuOptions.BeaconLib (CreateBeacon/StartBeacon/DestroyBeacon/GetBeaconStatus/GetSoundSets).
- SkuSettings:Sub("SkuQuest" [, nil, "char"]) and Sub("SkuCore"); SkuNav (GetBestMapForUnit, GetWaypointData2, Distance, GetDirectionToAsString, GetLayerText, GetNonAutoLevel, BeaconSoundSetNames, ClickClackSoundsets), SkuState:IsInCombat, SkuDispatcher, SkuCore:ScheduleMenuFlashRecheck, SkuLogCombat.
- WoW quest APIs: GetNumQuestLogEntries, GetQuestLogTitle, GetQuestLogLeaderBoard, GetNumQuestLeaderBoards, SelectQuestLogEntry, GetQuestLogQuestText, GetQuestLogRewardMoney/Rewards/Choices, ToggleQuestLog/ExpandQuestHeader, QuestLogFrame, C_QuestLog.IsQuestFlaggedCompleted, GameTooltip.

## Key data structures
- SkuQuest.QuestZoneCache = { [questID] = { [areaId]=areaId } } (built by BuildQuestZoneCache, keyed 1..100000 scan).
- SkuQuest.QuestWpCache = { [wpName]=true }; SkuQuest.questObjects = { [objectName]=objectId }.
- SkuQuest.activeBeacons = { availableQuests={}, currentQuests={} } keyed by floor(x)..floor(y) name; activeBeaconsTmpIgnore/-Chat (per-zone reset), activeBeaconsOldUiMapId.
- SkuQuest.SelectedQuest (1-based quest-log cursor); MenuAccessKeysNumbers "1".."9"; racesFriendly / classesFriendly / SkuDB.QuestFlagsFriendly (localized lookup); EnumItemQuality.
- Deferred handles: SkuQuestSoundSetTimer (+0.01s), SkuQuestDeferredSetupTimer (+40s), SkuQuestToggleQuestLogHooked (one-shot).

## Events
- WoW events (RegisterQuestEvents, re-armed each OnEnable): VARIABLES_LOADED, QUEST_LOG_UPDATE, UPDATE_FACTION, UNIT_QUEST_LOG_CHANGED, PLAYER_ENTERING_WORLD, PLAYER_LOGIN, QUEST_ACCEPTED, QUEST_REMOVED, QUEST_TURNED_IN, ZONE_CHANGED_NEW_AREA, ZONE_CHANGED, ZONE_CHANGED_INDOORS.
- Hook: hooksecurefunc("ToggleQuestLog", SkuQuest.ToggleQuestLogHook) — installed once in OnEnable, cannot be removed (IsEnabled-guarded).
- SkuDispatcher: TriggerSkuEvent("SKU_ROUTE_STARTED") (in Options route actions).
- Timers: +0.01s sound-set option build, +40s deferred LoadEventHandler+list update, 10s PLAYER_ENTERING_WORLD_flag reset (PLAYER_LOGIN), 0.1s SlashFunc-open, 0.01s aForce list-rebuild recurse, 5s (SkuMob) unrelated.
- Beacon callbacks (reached/distance-changed/ping) per beacon via BeaconLib.

## Settings keys
- SkuSettings:Sub("SkuQuest", nil, "char"): CheckQuestProgressList (per-char objective snapshot), questMarkerBeacons.activeBeaconsIgnore (seen-forever set).
- SkuSettings:Sub("SkuQuest") (profile): questMarkerBeacons.availableQuests/currentQuests.{enabled, enableBeacons, enableClickClack, singlePing, beaconSoundSet, beaconType, beaconVolume, maxRange, chatNotification, disableOn, disableSeenForever, minLevel}. (Schema in Options.lua.)
- SkuSettings:Sub("SkuCore").combatMenuOpen (combat opt-in gate for quest-log nav).

## Entry points
- Keybind: SKU_KEY_QUESTABANDON (matched in SkuQuestMainOption1 OnClick); CTRL-Q override binding opens/closes quest log (SkuQuestMain); SHIFT-UP/DOWN, CTRL-SHIFT-UP/DOWN, UP/DOWN, ESCAPE, 1-9 handled on SkuQuestMainOption1.
- Secure/driver frames: SkuQuestMain (CTRL-Q toggle), SkuQuestMainOption1 (nav + ESCAPE override binding).
- Hooks ToggleQuestLog to descend into the Sku menu ("Local"/"SkuQuestMenuEntry").

## Invariants & gotchas
- GetTTSText and ShowForTTS are ~95% duplicated (two copies of the reward/objective/section-building logic, differing mainly in the QuestLogItem widget names: QuestLogItem vs QuestInfoRewardsFrameQuestInfoItem, and whether they push to TTS/speak). Prime consolidation candidate.
- The reward EnumerateTooltipLines_helper closure is copy-pasted 4 times (numRewards + numChoices, in each of the two functions).
- CheckQuestProgress is called with a stray 2nd arg in QUEST_LOG_UPDATE/UPDATE_FACTION (SkuSettings:Sub(...).CheckQuestProgressList) that the function ignores — leftover signature drift.
- All cross-family DB reads (GetAllQuestWps/BuildQuestZoneCache/UpdateZoneAvailableQuestList) rely on Sku:IsDataReady gating (DB rework stage 3) to avoid nil-chain crashes during streamed init — do NOT remove the guards.
- BuildQuestZoneCache scans questID 1..100000 linearly every call. GetCreatureArea/GetObjectArea are file-local and mutate QuestZoneCache in place.
- PLAYER_ENTERING_WORLD calls CheckQuestProgress twice back-to-back (line 1110-1111) — looks like an accidental duplicate.
- doQuestMarkerBeacons + UpdateZoneAvailableQuestList carry heavy nested SkuSettings:Sub reads inside per-beacon callbacks (re-read every distance change).
