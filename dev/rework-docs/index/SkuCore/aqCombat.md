# SkuCore/aqCombat.lua
- Purpose: The combat monitor — spoken/sound notifications about hostile and friendly units during combat for a blind player: threat warnings, target-of-target, enemy casts, enemies entering/leaving combat (absolute counts and a live "relative number in combat" counter), unit deaths, party deaths, and out-of-range party members. Also owns the "Sku raid target" system (a Sku-private raid-marker repo keyed by GUID, independent of the game's 8 icons). W4 Phase D AceAddon submodule (aqCombat) so the whole monitor toggles on/off; heavy state lives on SkuCore (threatTable, inOutCombatQueue, SkuRaidTargetRepo). The large tail of the file is the settings menu builder.

## Public API / exports
- aqCombat (SkuCore.aqCombat) — the published module handle (AceAddon submodule).
- aqCombat:OnEnable() / OnDisable() — arm/disarm: (un)register dispatcher callbacks + the two control OnUpdate frames; OnEnable also seeds settings defaults.
- aqCombat:aqCombatOnInitialize() — creates control frames, registers all SkuDispatcher callbacks, installs the SetRaidTarget hook.
- aqCombat:aqCombatOnLogin() — seeds all aq[1] and aq[2] combat settings defaults (idempotent).
- aqCombat:aqCombatGetSkuRaidTarget(guid) — returns the Sku raid-marker index for a GUID (plus true if dead-repo). Called by TurnToUnit + SkuMob.
- aqCombat:aqCombatSetSkuRaidTarget(guid, id) — set/clear/auto-assign a Sku raid marker.
- aqCombat:aqCombatClearSkuRaidTargets() — wipe both repos.
- aqCombat:aqCombatCheckGameRaidTargets() — clears Sku markers for units that got a real game raid icon.
- aqCombat:aqCombatCreatureGuidToUnitId / aqCombatGroupGuidToUnitId / aqCombatGroupNameToUnitId — GUID/name → unitId resolvers over the party/raid unit-token lists.
- aqCombat:aqCombatIsPartyOrRaidMember(unitId, guid) — cached membership resolver; returns the matching unit token.
- aqCombat:aqCombat_CREATURE_ADDED_TO_COMBAT / _CREATURE_REMOVED_FROM_COMBAT — mutate threatTable + inOutCombatQueue.
- aqCombat:aqCombatMenuBuilder() — builds the entire combat-monitor settings submenu.
- SkuCoreAqCombatGetVoiceString(str, tbl) — GLOBAL template expander (${...} substitution + number-only/nameplate/low-volume rewrites).
- Event handlers (dispatcher targets): aqCombat_COMBAT_LOG_EVENT_UNFILTERED, aqCombat_SKU_UNIT_DIED, aqCombat_SKU_SPELL_CAST_START, aqCombat_PLAYER_ENTERING_WORLD, aqCombat_PLAYER_REGEN_DISABLED, aqCombat_PLAYER_REGEN_ENABLED, aqCombatPLAYER_TARGET_CHANGED, aqCombat_GROUP_ROSTER_UPDATE.

## Dependencies (outgoing)
- SkuDispatcher — RegisterEventCallback/UnregisterEventCallback (central broker for all this module's events).
- SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet] — the entire combat settings tree; also SkuSettings:Sub("SkuCore").combatMenuOpen (profile).
- SkuCore.talentSet (active talent-set index 1/2), SkuCore.aq.combat state, SkuCore.threatTable, SkuCore.inOutCombatQueue.
- SkuOptions.Voice:OutputString/OutputStringBTtts/StopOutputEmptyQueue; SkuOptions:InjectMenuItems, currentMenuPosition, RangeCheck:GetRange; SkuGenericMenuItem; SkuSpairs.
- SkuDB.NpcData (Keys.rank, Data[npcId]) for elite classification fallback.
- Sku.L, Sku.PerformanceData (profiling accumulators).
- WoW: UnitGUID, UnitName, UnitClassification, UnitDetailedThreatSituation, UnitExists, UnitIsEnemy, UnitIsDeadOrGhost, UnitIsOtherPlayersPet, GetRaidTargetIndex, SetRaidTarget (hooked), GetSpellInfo, CombatLogGetCurrentEventInfo, GetTimePreciseSec, debugprofilestop, C_Timer.After, strsplit, hooksecurefunc.

## Key data structures
- SkuCore.threatTable[creatureGUID] — false = left combat, else table with .name/.lastUpdate and [partyGUID]={isTanking,wasTanking,status,scaledPercentage,rawPercentage,threatValue,lastUpdate}.
- SkuCore.inOutCombatQueue = {current=int, combatIn=[guid]=partyUnitId, combatOut=[guid]=true} — the entering/leaving counter queue.
- SkuCore.SkuRaidTargetRepo / SkuRaidTargetRepoDead — [guid]=iconIndex (Sku-private markers, live vs dead).
- SkuCore.RaidTargetValues[1..8] (name+color), SkuCore.SkuRaidTargetIndex[1..8] (assignment order remap).
- tAllPartyRaidUnits / tUnitsToTestOnGameRaidTargets — precomputed unit-token lists (player/pet/party/raid/nameplate/target chains).
- Caches: aqCombatIsPartyOrRaidMemberCache, tUnitClassificationCache, tAqCombatGetUnitIndexFromUnitGUIDCache, tGUIDCache{creatures,nonCreatures}.
- Setting entries shape: {value, sound, voiceOutput="${sound};..."} — sound is a template key into aqCombatAudioOutputs.

## Events
- SkuDispatcher subscriptions (registered in aqCombatOnInitialize, torn down in OnDisable): COMBAT_LOG_EVENT_UNFILTERED, SKU_UNIT_DIED, SKU_SPELL_CAST_START, PLAYER_ENTERING_WORLD, RAID_TARGET_UPDATE, PLAYER_REGEN_DISABLED, PLAYER_REGEN_ENABLED, PLAYER_TARGET_CHANGED, GROUP_ROSTER_UPDATE, GROUP_FORMED, GROUP_JOINED (last three share aqCombat_GROUP_ROSTER_UPDATE).
- Two named OnUpdate frames: SkuCoreaqCombatControl (threat scan + OOR + threat warnings, throttled by updateRate) and SkuCoreaqCombatQueueControl (entering/leaving counters + stale-sweep).
- hooksecurefunc("SetRaidTarget") — installed once; on iconIndex 0 assigns a Sku marker.
- Timers: C_Timer.After 0.5 (tAddHelper deferred threat sample), 0.2/0.01/1.0 (menu sound preview), 0.001 (menu OOR-unit refresh).
- No AceComm.

## Settings keys
- All under SkuSettings char scope aq[talentSet].combat.*:
  - top: enabled, updateRate (1-20), voice (1/2), notificationVolume (1/2), voiceVolume (1/2).
  - combat.hostile.*: ignoreNonElite, threatOutputTot{value,sound}, threatWarningNotFirstHigherThan, threatWarningIsFirstSecondHigherThan, threatWarningInterval, warnIfTargetSwitchingToParty/ToYou, yourTargetCasting, allEnemiesCasting, minimumCastDuration, deathsIgnoreUnitsNotInCombat, outputDeadUnits, unitsAddedToCombat, unitsLeavingCombat, shortUnitsAddedOrLeavingToCombatMessages (unused/commented UI), relativeNumberUnitsInCombat.
  - combat.friendly.*: partyDead, partyDeadCount, outOfRangeEnabled, ignoreDeadPartyPets, oorAt, oorUnitName, oorInterval.
- SkuSettings:Sub("SkuCore").combatMenuOpen (profile) — the in-combat menu toggle, mirrors /skucombatmenu.
- SkuCore.aqCombatSetRaidTargetHooked / SkuCore.aqCombatCheckThreat — runtime flags (not persisted).

## Entry points
- Feature toggle node in Features/Module menu (label "Kampf-Monitor"/"Combat monitor").
- aqCombatMenuBuilder() builds the whole combat settings submenu (Sku menu in combat, Enabled, Update rate, Voice, volumes, Hostile{Threat/Casting/Deaths/Units in combat}, Friendly{deaths/pets/distance}).
- hooksecurefunc on the game's SetRaidTarget.

## Invariants & gotchas
- Dead/undefined variable bug: in the control-frame threat-warning branch, SkuCoreAqCombatOutput is called with `{unit1 = tAllPartyRaidUnits[x]}` at lines ~582/587/606/611, but `x` is not defined in that scope (leftover from a removed loop) — unit1 is nil in those warnings.
- The two counter branches in SkuCoreaqCombatQueueControl (relativeNumberUnitsInCombat vs unitsAddedToCombat/unitsLeavingCombat, lines ~685-767 and ~768-860) are near-duplicate copy-paste of the same combatIn value==4/3/2 iteration; prime consolidation target.
- aqCombatUNIT_THREAT_LIST_UPDATE and aqCombatUNIT_THREAT_SITUATION_UPDATE (lines ~1212-1243) are fully commented-out no-op bodies and never registered — dead code.
- aqCombat_PLAYER_ENTERING_WORLD is empty yet still registered/unregistered.
- threatTable entries flip to `false` to mean "left combat" (not nil) — iteration code must type-check (`type(v)=="table"`) before indexing; the stale-sweep (tStaleThreshold=6s) exists because evade/leash/off-screen deaths produce no UNIT_DIED, and PLAYER_REGEN_ENABLED force-announces a final "0" for the same reason.
- SetRaidTarget hook and SkuRaidTargetRepo can never be unhooked; disable is IsEnabled-guarded only.
- OnEnable calls both aqCombatOnInitialize (idempotent: dispatcher keys by function, frames reused via _G, hook install-once guard) and aqCombatOnLogin every load; safe but re-runs default-seeding each time.
- SkuCoreAqCombatGetVoiceString is a bare global (no local/module scope) — namespace leak.
- Heavy per-tick work (UnitGUID over up to ~350 unit tokens each pass) gated by updateRate; performance-sensitive, all wrapped in Sku.PerformanceData timers.
