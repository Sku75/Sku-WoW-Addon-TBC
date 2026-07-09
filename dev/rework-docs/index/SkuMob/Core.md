# SkuMob/Core.lua
- Purpose: SkuMob is the target/soft-target tracking module. It announces the current target (name, level, classification, reaction, raid marker, combat status, layer), plays quantized target-health "beep" sounds while attacking, and reacts to WoW soft-targeting (enemy/friend/interact) to pre-announce units. Runtime-toggleable AceAddon (W4 Phase D): OnEnable re-arms events + the 0.25s OnUpdate poller, OnDisable tears them down; the query/menu API stays defined either way.

## Public API / exports
- SkuMob (AceAddon "SkuMob"): the module table (global).
- SkuMob:OnInitialize / OnEnable / OnDisable — lifecycle; OnEnable arms events + creates SkuMobControl OnUpdate driver (0.25s tick: soft-interact match-locked update + OutputTargetHealth); OnDisable UnregisterAllEvents + clears the OnUpdate.
- SkuMob:OutputTargetHealth(aForce) — computes target HP bucketed to tens, speaks the numeric bucket via Voice:OutputString (used as an audio-index key into SkuMobDB.soundFiles conceptually); dedupes by lastAudioQ/lastTargetGuid.
- SkuMob:GetTtsAwareUnitName(aUnitId) — returns a TTS-friendly placeholder ("du selbst", "dein begleiter", "party N", "raid N") when vocalizePlayerNamePlaceholdersSkuTts is set, else UnitName.
- SkuMob:PLAYER_TARGET_CHANGED(event, aUnitId) — the big announcer (target/softenemy/softfriend/softinteract); builds the spoken string and routes to OutputString or OutputStringBTtts.
- Soft-target handlers: PLAYER_SOFT_ENEMY_CHANGED / PLAYER_SOFT_FRIEND_CHANGED / PLAYER_SOFT_INTERACT_CHANGED — gate on softTargeting settings, play configured sounds, delegate to PLAYER_TARGET_CHANGED for the name.
- SkuMob:QUEST_TURNED_IN — sets a 5s QuestTurnedIn flag and triggers SkuOptions:SendTrackingStatusUpdates.
- SkuMob:VARIABLES_LOADED — builds the InCombatSounds table (via local EnsureInCombatSounds).
- SkuMob:RefreshVisuals / PLAYER_ENTERING_WORLD — empty stubs.

## Dependencies (outgoing)
- SkuOptions.Voice:OutputString / OutputStringBTtts (voice output chokepoint), SkuOptions.db.profile["SkuOptions"].softTargeting.* and .soundChannels.SkuChannel.
- SkuSettings:Sub("SkuMob") (settings facade); SkuState:IsInCombat().
- SkuAuras.outputSoundFiles, SkuAudioFileIndex, Sku:AudioFile() (W5 voice-pack path resolver for InCombatSounds).
- SkuCore.RangeCheck:DoRangeCheck, SkuCore.RaidTargetValues, SkuCore.aqCombat:aqCombatGetSkuRaidTarget/aqCombatSetSkuRaidTarget.
- SkuNav:GetLayerText / GetNonAutoLevel; SkuDB.routedata (lazily built, guarded).
- Sku.L, Sku.AudiodataPath; WoW APIs: UnitHealth/UnitHealthMax/UnitGUID/UnitReaction/UnitThreatSituation/UnitDetailedThreatSituation/UnitClassification/GetRaidTargetIndex/GameTooltip:SetUnit/PlaySoundFile.

## Key data structures
- SkuMobDB (file-local): lastTargetGuid, nextAudioQ, lastAudioQ, soundFiles = { [0..100 by 10] + [L["dead"]] = mp3 path } keyed by HP bucket.
- SkuMob.InCombatSounds — { audioFilePath = friendlyName }, rebuilt by EnsureInCombatSounds from SkuAuras.outputSoundFiles; feeds the InCombatSound select option values.
- SkuMob.controlFrame — the SkuMobControl OnUpdate frame; SkuMob.interactTempDisabled — transient soft-interact suppression flag.

## Events
- Registered (RegisterSkuMobEvents, re-armed every OnEnable): VARIABLES_LOADED, PLAYER_TARGET_CHANGED, QUEST_TURNED_IN, PLAYER_SOFT_ENEMY_CHANGED, PLAYER_SOFT_FRIEND_CHANGED, PLAYER_SOFT_INTERACT_CHANGED. (PLAYER_ENTERING_WORLD registration commented out.)
- Timers: SkuMobControl OnUpdate 0.25s poller; C_Timer.After(0.01) in PLAYER_TARGET_CHANGED (lets combat monitor queue first); C_Timer.After(0.1) softinteract HP read; C_Timer.After(5) QUEST_TURNED_IN flag reset.
- No SkuDispatcher subscriptions here (uses raw AceEvent registration).

## Settings keys
- SkuSettings:Sub("SkuMob"): InCombatSound, vocalizePlayerNamePlaceholders, vocalizePlayerNamePlaceholdersSkuTts, dontVocalizePlayerReactionAndLevelInCombat, vocalizeRaidTargetOnly, repeatRaidTargetMarkers, autoSetSkuRaidTargetsToInCombatCreatures, enemyCombatStatusMode (all profile scope per Options schema).
- SkuOptions.db.profile["SkuOptions"].softTargeting.* (enemy/friend/interact enabled, sound, soundNoTarget, outputName, forPlayers/forPets/forPassive, muteInCombat, soundfor, unitNameFor, outputBTTS, matchLocked) — read directly, not through the facade.
- SkuOptions.db.profile["SkuOptions"].soundChannels.SkuChannel.

## Entry points
- No slash commands or keybinds. Drives SkuOptions:UpdateSoftTargetingSettings on target/soft-interact changes.

## Invariants & gotchas
- OutputTargetHealth's nextAudioQ/lastAudioQ dedup logic (lines ~97-111) is convoluted: it assigns hpPer to nextAudioQ, immediately re-checks, then speaks the numeric bucket — the SkuMobDB.soundFiles table is defined but the code passes the bucket NUMBER to OutputString, not the mapped file path (soundFiles may be effectively dead / superseded).
- PLAYER_TARGET_CHANGED reads softTargeting from SkuOptions.db directly while SkuMob's own keys go through SkuSettings:Sub — two settings access styles in one file.
- InCombatSounds is defined in BOTH Options.lua (base default) and rebuilt in Core (EnsureInCombatSounds); order-sensitive on SkuAuras/SkuAudioFileIndex availability.
- Layer-info read guards SkuDB.routedata existence (lazily built) — do not remove the guard.
