# SkuQuest/Options.lua
- Purpose: SkuQuest's options schema/defaults, the Questie integration layer, the quest-database query + spoken-detail builder, the route/waypoint submenu builder for quest targets, and the main quest menu (SkuQuest:MenuBuilder). This is the bulk of the quest UX: "Aktuelle Quests" (live log), "Gruppenmitglieder" (group members' quests via Questie comms), and "Questdatenbank" (all/by-zone/by-distance available quests), each descending into Annahme/Ziel/Abgabe/Route submenus.

## Public API / exports
- SkuQuest.options / SkuQuest.defaults + SkuSettings:Register("SkuQuest", {...}) — questMarkerBeacons.{availableQuests,currentQuests}.* schema (profile scope); beaconSoundSet/beaconType keep custom get/set (name<->id transform).
- Questie helpers (all pcall-wrapped, silent no-op when Questie absent): QuestieModule(name) (cached import), QuestieReady, IsEventActiveByDate, IsEventQuestInactive, IsQuestieUnavailable, GetDoableStatusText, GetGroupMemberQuests, GetGroupQuestProgressText, LoadEventHandler, WithinDates.
- Data/query: GetQuestStartZoneId, GetQuestDataStringFromDB(aQuestID, aZoneID) (builds the spoken section table: name/status/zone/level/objectives/races/classes/pre-quests/attributes/id), GetResultingWps (item/object/creature/waypoint -> WP lists), GetQuestTargetIds, GetTriggerEndWps, GetUnsortedAvailableQuestsTable (the big availability filter).
- Menu: SkuQuest:CreateQuestSubmenu(aParent, aQuestID) (public wrapper over local CreateQuestSubmenu), SkuQuest:MenuBuilder(aParentEntry) via SkuMenu:Build.

## Dependencies (outgoing)
- Questie (via _G.QuestieLoader:ImportModule): QuestieEvent (IsEventQuest/IsEventActiveForQuest/GetEventNameFor/eventDates), QuestieDB (IsDoableVerbose/DoableStates/GetQuest), QuestieComms.remoteQuestLogs, _G.Questie.started.
- SkuDB.questDataTBC/questKeys/questLookup/NpcData/objectDataTBC/objectKeys/objectLookup/itemDataTBC/itemKeys/itemLookup/InternalAreaTable/raceKeys/classKeys/QuestFlags/QuestFlagsFriendly; Sku:IsDataReady gating.
- SkuNav (huge surface: GetAreaData/GetCurrentAreaId/GetUiMapIdFromAreaId/GetAreaIdFromUiMapId/GetBestMapForUnit/GetWaypointData2/Distance/GetDirectionToAsString/GetContinentNameFromContinentId/GetNpcRoles/GetLayerText/GetNonAutoLevel/GetAllMetaTargetsFromWp5/GetAllLinkedWPsInRangeToCoords/GetNearestWpsWithLinksToWp/getAnnotatedWaypointLabel/SelectWP/EndFollowingWpOrRt, MaxMetaWPs/MaxMetaEntryRange/BestRouteWeightedLengthModForMetaDistance).
- SkuOptions.db.profile["SkuNav"].* (route/metapath following state), SkuOptions.BeaconLib, SkuOptions:InjectMenuItems/CloseMenu/SlashFunc, SkuOptions.Voice, SkuMenu:Build, SkuDispatcher, SkuSettings:Sub, SkuState.
- WoW: GetNumQuestLogEntries/GetQuestLogTitle/GetQuestLink, C_QuestLog.IsQuestFlaggedCompleted, GetFactionInfoByID, C_Map.GetWorldPosFromMapPos, C_DateAndTime, UnitPosition/UnitLevel/UnitClass/UnitRace/UnitFactionGroup, ChatFrame1EditBox, bit.band.

## Key data structures
- SkuQuest.questMarkerBeaconsTypeValues [-1..-7] (beacon behavior descriptions), questMarkerBeaconsDisableOnValues (referenced from Core).
- SkuQuest._questieModuleCache (name->module, never caches negative).
- tShowQuestsTable / tUnSortedTable / tIdTable (GetUnsortedAvailableQuestsTable outputs: distance-keyed available-quest lists).
- tResultWPs (GetResultingWps: unitGeneralName -> list of ";"-joined spawn descriptors).
- SkuSpairs (file-local sorted-pairs iterator, reused throughout).

## Events
- No WoW event registration here (handlers live in Core). SkuDispatcher:TriggerSkuEvent("SKU_ROUTE_STARTED") fired from Route OnAction.
- Timers: beacon-sample C_Timer.After(1) destroy; C_Timer.After(0.35) close menu after "An Chat schicken"; C_Timer.NewTimer(0.1) SlashFunc pre-quest navigation.

## Settings keys
- Registered (profile): questMarkerBeacons.availableQuests.* and .currentQuests.* (enabled, enableBeacons, enableClickClack, singlePing, beaconSoundSet, beaconType, beaconVolume, maxRange, chatNotification, disableOn, disableSeenForever, minLevel), showDifficultyColors, showGroupQuests.
- Reads SkuOptions.db.profile["SkuNav"].* for route following (metapathFollowing*, selectedWaypoint, routesMaxDistance, showGlobalDirectionInWaypointLists, routeRecording, beaconVolume, menuFollowTargetWaypoint).

## Entry points
- Menu: SkuQuest:MenuBuilder = Aktuelle Quests / Gruppenmitglieder (conditional) / Questdatenbank; leaf OnEnter sets currentMenuPosition.textFull, BuildChildren -> CreateQuestSubmenu (Annahme/Ziel/Abgabe/An Chat schicken/Pre Quests/Share). Route submenu (CreateRtWpSubmenu) offers Route / Closest route / Wegpunkt navigation into SkuNav metapaths.
- "An Chat schicken" injects a quest hyperlink into ChatFrame1EditBox (SkuPostQuestToChat).

## Invariants & gotchas
- Questie public functions are DOT functions — MUST be called with a dot/explicit first arg, NEVER colon (colon passes wrong self as questId — the original event-filter bug). Every call is pcall-wrapped and biases to SHOW on uncertainty. QuestieReady gates on Questie.started to avoid poisoning Questie's race/class doable cache (flag 255 window).
- GetResultingWps / GetUnsortedAvailableQuestsTable do unchecked chained DB indexing (itemDataTBC[id][...], NpcData.Data[id][...]) — protected only by the Sku:IsDataReady family gates at the top; removing those reintroduces the streamed-init BugSack crash (seen 2026-07-06).
- The availableQuests and currentQuests options subtrees are ~identical copy-paste (every node duplicated with only the storage path differing) — big consolidation candidate.
- CreateRtWpSubmenu is very large with three near-duplicate blocks (Route / Closest route / Wegpunkt), each rebuilding sorted waypoint lists via SkuSpairs; the "Route" and "Closest route" BuildChildren share most logic.
- GetUnsortedAvailableQuestsTable uses an undefined `is` variable in select(3, SkuNav:GetAertaData(is)) at lines ~2001/2018 (likely a latent bug — `is` is not in scope there); also `aAreaId` is referenced in GetResultingWps object branch but never defined (always nil).
- GetQuestDataStringFromDB indexes SkuDB.questLookup[...][aQuestID] unguarded in places; callers in the group-members path guard it, but the Questdatenbank path does not.
- SkuPostQuestToChat: manually-built |Hquest:|h links are server-filtered on Anniversary/TBC; only GetQuestLink(logIndex) yields a clickable link (tFromLog), else falls back to plaintext.
