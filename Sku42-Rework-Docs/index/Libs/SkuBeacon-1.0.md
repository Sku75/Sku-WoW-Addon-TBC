# Libs/SkuBeacon-1.0/SkuBeacon-1.0.lua (+ SkuBeacon-1.0.xml)
- Purpose: The audio-beacon navigation engine, registered as LibStub library "SkuBeacon-1.0". It plays directional/distance ping sounds toward world positions so a blind player can home in on a target by ear. Each beacon computes the clock-direction and distance from the player to a target position, picks a pre-baked mp3 named "<soundset>;<degree>;<distance>.mp3", and plays it on a dynamic ping rate; it also emits click/clack stereo cues when the player crosses the target bearing. A single OnUpdate loop on SkuBeaconLibControlFrame walks every registered beacon. The .xml just loads the .lua. Consumed mainly by SkuNav.
## Public API / exports
- SkuBeacon:Create(aReference) — creates the shared OnUpdate control frame + the red "SkriptRecognizerTurn" widget, registers a caller reference bucket; returns the lib.
- SkuBeacon:Release(aReference) — destroys all beacons for a reference and removes it from the repo.
- SkuBeacon:RegisterSoundSet(aBaseName, aPath, aDegreesStep, aMaxDistance, aFileName) — registers a directional soundset (file-name format documented inline).
- SkuBeacon:RegisterClickClackSoundSet(aFriendlyName, aInternalName, aPath, aClickFileName, aClackFileName) — registers a click/clack bearing-cross cue pair.
- SkuBeacon:GetSoundSets() / :GetClickClackSoundSets() — return the two soundset repos.
- SkuBeacon:CreateBeacon(aReference, aBeaconName, aSoundSet, aPosX, aPosY, aRate, aSilenceRange, aVolume, aClickSoundRange, aMaxDistance, aReachedCallback, aDistanceChangedCallback, aPingCallback, aClickSoundType) — defines a beacon (inactive) under a reference.
- SkuBeacon:UpdateBeacon(aReference, aBeaconName, aSoundSet, aPosX, aPosY, aRate, aSilenceRange, aVolume, aNoPingReset) — mutates position/rate/etc. of an existing beacon.
- SkuBeacon:DestroyBeacon(aReference, aBeaconName) — destroys one beacon or all beacons of a reference.
- SkuBeacon:GetBeacons(aReference) — returns an ipairs iterator over a reference's beacon names.
- SkuBeacon:StartBeacon / :StopBeacon(aReference, aBeaconName) — toggle a beacon's active flag (and the global tBeaconRunning).
- SkuBeacon:GetBeaconStatus(aReference, aBeaconName) — returns the active flag.
## Dependencies (outgoing)
- LibStub only for registration; otherwise pure WoW API.
- WoW APIs: UnitPosition("player"), GetPlayerFacing, PlaySoundFile, GetTime, CreateFrame, math.*.
- Globals it probes: SkuOptions:IsMenuOpen(), and named edit-box/frame globals (SkuAuctionConfirmEditBox, SkuOptionsEditBoxEditBox/Paste, SkuNavMM* edit boxes, ChatFrame1EditBox, MacroFrame) to suppress the turn widget while typing.
## Key data structures
- gBeaconRepo — dual-keyed: array of reference handles AND map reference->{array of beacon names + map name->beacon record}. Beacon record: {name, active, soundSet, posX, posY, rate, lastPing, silenceRange, volume, clickSoundRange, maxDistance, reachedCallback, distanceChangedCallback, pingCallback, clickSoundType, oldDistance}.
- gSoundsetRepo — dual-keyed array+map of soundsets: {path, degreesStep, maxDistance, fileName}.
- gClickClackSoundsetRepo — dual-keyed: {friendlyName, path, clickFileName, clackFileName}.
- CONST_DYNAME_PING_RATE1..7 — negative-int rate sentinels; each selects a distinct dynamic ping-rate + distance-compression formula in OnUpdate.
## Events
- Frame SkuBeaconLibControlFrame drives everything via OnUpdate (throttled to ~0.05s). No WoW event registration, no SkuDispatcher, no AceComm, no timers.
## Settings keys
- none (reads no SkuOptions.db keys directly; behaviour is driven by per-beacon params passed in by callers).
## Entry points
- No slash commands/keybinds. SkuBeaconSkriptRecognizerTurn is a 1x2 px red TOOLTIP-strata texture widget shown/hidden by OnUpdate (a screen marker; hidden while any listed edit box has focus/is shown or the Sku menu is open).
## Invariants & gotchas
- Soundset mp3 file naming is a hard contract: "<soundsetName>;<degreeNumber>;<distanceNumber>.mp3" with degree in aDegreesStep increments and distance 1..aMaxDistance; a missing baked file just fails to play silently.
- gBeaconRepo mixes numeric-array entries and string-keyed entries in one table; ipairs walks only the array part while indexing uses the map part — deleting during ipairs (DestroyBeacon does table.remove inside ipairs) can skip entries.
- OnUpdate `return`s (not `break`s) out of the whole pump when GetDistance yields nil for one beacon (calls DestroyBeacon then returns) — starves all later beacons that tick.
- tPrevCleanedDirection is a single module-global shared across ALL beacons, so click/clack state is not per-beacon — multiple simultaneous click-cue beacons interfere.
- Debug() is gated by gDebugLevel (hardcoded 0); the many Debug(...) calls are effectively dead unless the local is edited.
- SKUBEACON_MINOR is 2 but there is no oldminor upgrade/migration logic — a reload with an older instance loaded just re-runs the whole chunk.
