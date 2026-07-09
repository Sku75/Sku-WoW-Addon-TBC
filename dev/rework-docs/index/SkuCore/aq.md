# SkuCore/aq.lua

- Purpose: The health & power monitor ("Aq") — the largest SkuCore feature. It continuously and event-driven announces player/pet health, player power, party/raid member health (pitch-graded per-unit mp3 samples, "health2 pitch style"), dispellable debuffs (magic/curse/poison/disease) for player/party/raid, and mirror timers (breath/fatigue) as percent read-outs. Since W4 Phase D/E it is a real AceAddon submodule of SkuCore (`SkuCore.Aq`), user-toggleable at runtime, with all former `SkuCore:Monitor*`/`Aq*`/`UNIT_*` methods moved onto the module table. It also builds the whole "Monitor" settings menu tree and delegates the Combat submenu to aqCombat.

## Public API / exports
- `Aq` = `SkuCore:NewModule("Aq", "AceEvent-3.0")`, published as `SkuCore.Aq` (external callers use `SkuCore.Aq:Method`).
- `Aq:OnInitialize()` — unconditionally (re)builds `SkuCore.Monitor.UnitNumbersIndexedRaid` (read by SkuAuras even while Aq is off).
- `Aq:OnEnable()` / `Aq:OnDisable()` — arm/disarm lifecycle: OnEnable runs AqOnInitialize + AqOnLogin; OnDisable stops the OnUpdate driver and unregisters all 7 AceEvents + 6 dispatcher callbacks.
- `Aq:AqOnInitialize()` — creates the control frame, registers AceEvents and SkuDispatcher callbacks.
- `Aq:AqOnLogin()` — settings migration (flat aq → aq[1]/aq[2] talent sets) plus nil-guard default seeding for every aq setting key (both talent sets).
- `Aq:AqSlashHandler(aFieldsTable)` — slash-command toggles (player/pet health, power, debuffs, party health/debuffs, follow-target set, roles reset/print).
- `Aq:MonitorPartyHealth2Conti()` / `Aq:MonitorRaidHealth2Conti()` — force a full announced health pass (external trigger, e.g. keybind); guarded by `Aq:IsEnabled()`.
- `Aq:MonitorRaidRosterUpdate()` — rebuilds `tDTRaidRoster` (raidN unit → stable subgroup-position number); defers itself to `PLAYER_REGEN_ENABLED` while in combat.
- Dispatcher callback family: `Aq:Monitor_PLAYER_ENTERING_WORLD` (3 delayed roster updates at 5/15/25 s), `Monitor_PARTY_LEADER_CHANGED`, `Monitor_GROUP_FORMED`, `Monitor_GROUP_JOINED`, `Monitor_GROUP_LEFT`, `Monitor_GROUP_ROSTER_UPDATE` — all funnel into MonitorRaidRosterUpdate when in a raid.
- AceEvent handlers: `Aq:UNIT_HEALTH` (player/pet event output + party/raid health2 event filtering & queueing, incoming-heals factoring), `Aq:UNIT_POWER_UPDATE` (player power event output), `Aq:UNIT_POWER_FREQUENT` (registered but body is a no-op), `Aq:UNIT_AURA` (debuff-type counting per unit into tAuraRepo + event announcements), `Aq:MIRROR_TIMER_START/STOP/PAUSE` (mirror-bar tracking).
- `Aq:UnitIsInUnitGroup(aFilter, aUnitID)` — returns a unit-id list for filter "player"/"playerpet"/"party"/"partyandpets"/"raid"/"raidandpets".
- Output layer (all raw `PlaySoundFile` of pre-rendered mp3s): `Aq:MonitorOutputPlayerStatus(statusTable, vol, instancesOnly, voice)`, `Aq:MonitorOutputPartyPercent(...)` (legacy chord style, only referenced from commented-out code), `Aq:MonitorOutputPartyPercent2(unitNumber, vol, pitch)`, `Aq:MonitorOutputRaidPercent2(...)` (maps via tDTRaidRoster), `Aq:MonitorOutputPlayerPercent(value, vol, instancesOnly, voice, prefix)` (with StopSound of previous handle + "ice cream" easter-egg lines).
- `Aq:MonitorMenuBuilder()` — builds the entire Monitor settings menu (Global / player / Pet / Party / Raid / Combat); despite colon declaration it is called as a menu BuildChildren, so `self` is the menu node.
- Internal helper families: `ttimeMonParty2QueueAdd` / `ttimeMonRaid2QueueAdd` (queue insert with prio-output, dead/full extra sounds), `monitorPartyHealth2ContiOutput` / `monitorRaidHealth2ContiOutput` (continuous passes), `GetUnitsRaidSubgroup`, `AqCreateControlFrame` (the OnUpdate driver), `MonitorSpellMenuBuilder` (ignored/not-ignored debuff picker, iterates ALL of SkuDB.SpellDataTBC).
- Globals created: `SkuCore.Monitor.UnitNumbersIndexedRaid`, `SkuCore.aq` + `SkuCore.aq.mirrorBars`, and `tDTRaidRoster` (an accidental global, no `local`).

## Dependencies (outgoing)
- SkuSettings facade: everything reads/writes `SkuSettings:Sub("SkuCore", nil, "char").aq[SkuCore.talentSet]...` (char scope).
- SkuCore: `SkuCore.talentSet` (1/2 index), `SkuCore.inCombat`, `SkuCore:RegisterToggleableModule` (ModuleManager), `SkuCore.aqCombat.aqCombatMenuBuilder` (Combat submenu delegation).
- SkuDispatcher (RegisterEventCallback/UnregisterEventCallback) for group/roster events + one-shot PLAYER_REGEN_ENABLED deferral.
- SkuAuras: `RoleCheckerGetUnitRole(guid)` for auto role detection (defensively guarded on presence + IsEnabled), `RoleCheckerResetData()` from the slash handler.
- SkuZOptions menu framework: `SkuOptions:InjectMenuItems`, `SkuGenericMenuItem`, `SkuOptions.currentMenuPosition`, menu-item contract (dynamic/sorting/isSelect/GetCurrentValue/OnAction/BuildChildren/OnEnter/selectTarget).
- Voice/audio: `SkuOptions.Voice:OutputStringBTtts` (mirror bars only); everything else is direct `PlaySoundFile("Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\aq\\...")` on channel `SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel`.
- SkuDB: `SkuDB.SpellDataTBC` + `SkuDB.spellKeys` (+ `Sku.Loc`) for the debuff ignore-list picker.
- Misc: Ace3 (AceAddon/AceEvent via LibStub), `Sku.L`, `Sku.PerformanceData`, `dprint`, `SkuSpairs`, `MAX_RAID_MEMBERS`.
- WoW APIs: UnitHealth/UnitHealthMax, UnitPower/UnitPowerMax/UnitPowerType, UnitGUID/UnitName/UnitClass, UnitDebuff, UnitGetIncomingHeals, UnitInRaid/UnitInParty, UnitPlayerOrPetInParty/Raid, UnitIsPlayer, GetRaidRosterInfo, GetMirrorTimerProgress, PlaySoundFile/StopSound, C_Timer.After, IsInInstance, GetTime, debugprofilestop, CreateFrame.

## Key data structures
- Settings tree (char): `aq[q]` for q = 1,2 (talent set) with branches `player{health, power, debuffs}`, `pet{health}`, `party{health2, debuffs}` (+ legacy `party.health` only in commented code), `raid{health2, debuffs}`, `global{numberFirst, numberOnly}`. Common per-branch keys: enabled, instancesOnly, silentOn100and0, continouslyTimer/StartAt/StartAfter/Volume, eventVolume, steps, voice (index into tVoices), types/ignored (debuffs), outputStyle. health2 extras: factorInIncomingHeals, roleAssigments (unit index → role id, 0 = auto), continouslyStartAt[roleId], eventOutputFilters[roleId][filterId], prioOutput[roleId], addDeadOn0Percent, addSoundOn100Percent, outputQueueDelay, unitsAndSubgroupsSelection (raid, localized "Subgroup N"/"Main Tank" keys), prevHealth (per-unit {absolute, steps, lastOutput} — cached INSIDE the persisted settings tree).
- `ttimeMonParty2Queue` / `ttimeMonRaid2Queue` — arrays of `{tUnitNumber, tVolume, tPitch, lenght}` (note the load-bearing misspelling `lenght`), drained one entry per interval by the OnUpdate driver; special tUnitNumber values "dead" and "full".
- `tAuraRepo[subR][unitGUID][debuffType] = {count, start}` where subR is "player"/"party"/"raid" — current dispellable-debuff state per unit.
- `tDTRaidRoster` (GLOBAL): `["raid"..x] = ((subgroup-1)*5)+positionInSubgroup` — the stable "unit number" spoken for raid members; rebuilt out-of-combat only.
- `SkuCore.aq.mirrorBars[timerName] = {name, value, maxValue, scale, paused, pausedDuration, label, stepPct, prevStepPct}`.
- `SkuCore.Monitor.UnitNumbersIndexedRaid[x] = "raid"..x` — public index consumed by SkuAuras.
- Static tables: `tVoices` (Justin/Kimberly/Kevin → mp3 dir), `tPowerTypes` (NOTHING/MANA/RAGE/ENERGY/RUNIC_POWER), `tRoles` (Tanks/Healers/Damagers/No role/Main Tank), `tDebuffTypes`/`tDebuffTypesShort`, `tEventOutputFilters` (minAbsoluteSincePrevEvent id 1, minStepsSincePrevEvent id 2, per-role defaults), `tSounds` (percent → health_N.mp3 buckets, legacy).
- Module-local pause/prev state: tHealthMonitorPause, tPowerMonitorPause, t*DebuffsMonitorPause, tPrevHpPer/tPrevPwrPer/tPrevHpPetPer + direction flags + tPrevNumberToUtterance* (event dedup).

## Events
- AceEvent (registered in AqOnInitialize, unregistered in OnDisable): MIRROR_TIMER_START, MIRROR_TIMER_STOP, MIRROR_TIMER_PAUSE, UNIT_HEALTH, UNIT_POWER_FREQUENT (no-op handler), UNIT_POWER_UPDATE, UNIT_AURA.
- SkuDispatcher callbacks: PLAYER_ENTERING_WORLD, PARTY_LEADER_CHANGED, GROUP_FORMED, GROUP_JOINED, GROUP_LEFT, GROUP_ROSTER_UPDATE; plus a conditional one-shot PLAYER_REGEN_ENABLED → MonitorRaidRosterUpdate when a roster update arrives in combat.
- OnUpdate driver on frame `SkuCoreAqControl` (reused via _G): drains both health2 queues, samples mirror bars every 0.05 s, runs the continuous player/pet health, player power, player/party/raid debuff and party/raid health2 timers; accumulates `Sku.PerformanceData["aq onupdate"]`.
- C_Timer.After used for: delayed roster updates (5/15/25 s), event-pause windows (continouslyTimer), staggered debuff announcements, 0.25 s power output delay, menu re-render after voice change.

## Settings keys
- `SkuSettings:Sub("SkuCore", nil, "char").aq` — the whole monitor tree (char scope), talent-set indexed [1]/[2]; see Key data structures for the full branch list. Written extensively by AqOnLogin (defaults), the menu OnAction closures, and the slash handler. `aq[ts].party.health2.prevHealth` / `raid.health2.prevHealth` are runtime caches persisted into this tree. `aq[ts].player.health.iceCreamBought` (easter egg flag). `aq[ts].combat.friendly.oorUnitName` written by the slash "combat follow target" branch (the combat branch itself is owned by aqCombat.lua).
- Read: `SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel` (output channel).

## Entry points
- Slash: `Aq:AqSlashHandler` (wired from the central Sku slash dispatcher; fields like "aq player health", "aq party roles reset", "aq combat follow target").
- Menu: `Aq:MonitorMenuBuilder` is the BuildChildren of the Monitor menu node (registered elsewhere, SkuZOptions); the last entry "Combat" delegates BuildChildren to `SkuCore.aqCombat.aqCombatMenuBuilder`.
- Module toggle: `SkuCore:RegisterToggleableModule("Aq", ...)` → Features/Module menu + persisted on/off.
- External triggers: `Aq:MonitorPartyHealth2Conti` / `Aq:MonitorRaidHealth2Conti` (keybind-style force output); `SkuCore.Monitor.UnitNumbersIndexedRaid` consumed by SkuAuras.
- No secure buttons, no Blizzard hooks in this file.

## Invariants & gotchas
- `Aq:OnInitialize` must keep rebuilding `SkuCore.Monitor.UnitNumbersIndexedRaid` even when the module will be disabled — SkuAuras reads it unconditionally; never move that into OnEnable.
- Do NOT call aqCombat init from `AqOnLogin` — aqCombat is its own self-enabling module (W4 Phase D); calling it would double-init (comment at line 1266).
- All settings access is talent-set indexed via `SkuCore.talentSet`; the migration at the top of AqOnLogin (lines 900-905) converts old flat trees by aliasing the SAME table into aq[1] and aq[2] — both sets then share one table for migrated users.
- The queue-entry field is spelled `lenght` everywhere (producers and the OnUpdate consumer) — renaming one side breaks output pacing.
- `MonitorMenuBuilder` and `MonitorSpellMenuBuilder` run with `self` = menu node (BuildChildren contract), not the Aq module, despite the colon declaration.
- Audio is hardcoded `PlaySoundFile` paths under `SkuCore/assets/audio/aq/` (per-voice, per-volume, per-pitch pre-rendered mp3 filenames) — NOT routed through Sku:AudioFile()/voice-pack resolution; filename scheme (`jus_<unit>_<vol>_<pitch>.mp3`) is data, not code.
- `prevHealth` per-unit caches live inside the persisted char settings; stale values survive /reload by design (lastOutput/steps dedup).
- Aq state deliberately stays on `SkuCore.*` fields (SkuCore.Monitor, SkuCore.aq) so SkuAuras and others need no repoint — moving state onto the module is an explicitly deferred later pass (header comment).
- File starts with a UTF-8 BOM (parse with encoding='utf-8-sig').
