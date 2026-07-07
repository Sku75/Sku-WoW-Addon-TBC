# Libs/SkuBeacon-1.0/SkuBeacon-1.0.lua (+ SkuBeacon-1.0.xml)
- Purpose: The audio-beacon navigation engine, registered as LibStub library "SkuBeacon-1.0". It plays directional/distance ping sounds toward world positions so a blind player can home in on a target by ear. Each beacon computes the clock-direction and distance from the player to a target position, picks a pre-baked mp3 named "<soundset>;<degree>;<distance>.mp3", and plays it on a dynamic ping rate; it also emits click/clack stereo cues when the player crosses the target bearing. A single OnUpdate loop on SkuBeaconLibControlFrame walks every registered beacon. The .xml just loads the .lua. Consumed mainly by SkuNav.
## Public API / exports
- SkuBeacon:Create(aReference) — creates the shared OnUpdate control frame + the red "SkriptRecognizerTurn" widget, registers a caller reference bucket; returns the lib.
- SkuBeacon:Release(aReference) — destroys all beacons for a reference and removes it from the repo.
- SkuBeacon:RegisterSoundSet(aBaseName, aPath, aDegreesStep, aMaxDistance, aFileName) — registers a directional soundset (file-name format documented inline).
- SkuBeacon:RegisterClickClackSoundSet(aFriendlyName, aInternalName, aPath, aClickFileName, aClackFileName) — registers a click/clack bearing-cross cue pair.
- SkuBeacon:GetSoundSets() / :GetClickClackSoundSets() — return the two soundset repos.
- [W6-B #18] SkuBeacon:RegisterTextInputFrame(aFrameName) — register a frame/editbox global name whose focus (or shown state, for non-editbox frames) suppresses the turn-widget key recognizer. Feature modules call this at their editbox CreateFrame (guarded LibStub call) instead of the lib hardcoding their names.
- SkuBeacon:CreateBeacon(aReference, aBeaconName, aSoundSet, aPosX, aPosY, aRate, aSilenceRange, aVolume, aClickSoundRange, aMaxDistance, aReachedCallback, aDistanceChangedCallback, aPingCallback, aClickSoundType) — defines a beacon (inactive) under a reference.
- SkuBeacon:UpdateBeacon(aReference, aBeaconName, aSoundSet, aPosX, aPosY, aRate, aSilenceRange, aVolume, aNoPingReset) — mutates position/rate/etc. of an existing beacon.
- SkuBeacon:DestroyBeacon(aReference, aBeaconName) — destroys one beacon or all beacons of a reference.
- SkuBeacon:GetBeacons(aReference) — returns an ipairs iterator over a reference's beacon names.
- SkuBeacon:StartBeacon / :StopBeacon(aReference, aBeaconName) — toggle a beacon's active flag (and the global tBeaconRunning).
- SkuBeacon:GetBeaconStatus(aReference, aBeaconName) — returns the active flag.
## Dependencies (outgoing)
- LibStub only for registration; otherwise pure WoW API.
- WoW APIs: UnitPosition("player"), GetPlayerFacing, PlaySoundFile, GetTime, CreateFrame, math.*.
- Globals it probes: SkuOptions:IsMenuOpen(), and the registered text-input frame globals (see gTextInputFrames) to suppress the turn widget while typing. [W6-B #18] only the two Blizzard globals (ChatFrame1EditBox, MacroFrame) are built-in defaults now; the 5 Sku editboxes (SkuAuctionConfirmEditBox, SkuOptionsEditBoxEditBox, SkuOptionsEditBoxPaste, SkuNavMMMainFrameEditBox, SkuNavMMMainEditBoxEditBox) register themselves via RegisterTextInputFrame at creation, so this lib no longer hardcodes feature-module frame names.
## Key data structures
- gBeaconRepo — dual-keyed: array of reference handles AND map reference->{array of beacon names + map name->beacon record}. Beacon record: {name, active, soundSet, posX, posY, rate, lastPing, silenceRange, volume, clickSoundRange, maxDistance, reachedCallback, distanceChangedCallback, pingCallback, clickSoundType, oldDistance}.
- gSoundsetRepo — dual-keyed array+map of soundsets: {path, degreesStep, maxDistance, fileName}.
- gClickClackSoundsetRepo — dual-keyed: {friendlyName, path, clickFileName, clackFileName}.
- CONST_DYNAME_PING_RATE1..7 — negative-int rate sentinels; each selects a distinct dynamic ping-rate + distance-compression formula in OnUpdate.
- [W6-B #18] gTextInputFrames — name→true set of text-input frame globals to suppress the turn widget for. Seeded with {ChatFrame1EditBox, MacroFrame}; extended via RegisterTextInputFrame. Built once at load, walked each OnUpdate tick (was a per-tick recreated list before).
## Events
- Frame SkuBeaconLibControlFrame drives everything via OnUpdate (throttled to ~0.05s). No WoW event registration, no SkuDispatcher, no AceComm, no timers.
## Settings keys
- none (reads no SkuOptions.db keys directly; behaviour is driven by per-beacon params passed in by callers).
## Entry points
- No slash commands/keybinds. SkuBeaconSkriptRecognizerTurn is a 1x2 px red TOOLTIP-strata texture widget shown/hidden by OnUpdate (a screen marker; hidden while any listed edit box has focus/is shown or the Sku menu is open).
## Invariants & gotchas
- Soundset mp3 file naming is a hard contract: "<soundsetName>;<degreeNumber>;<distanceNumber>.mp3" with degree in aDegreesStep increments and distance 1..aMaxDistance; a missing baked file just fails to play silently.
- gBeaconRepo mixes numeric-array entries and string-keyed entries in one table; ipairs walks only the array part while indexing uses the map part. [Bug 2 fix] DestroyBeacon now iterates the array BACKWARDS so its table.remove can't skip entries.
- [Bug 2 fix] OnUpdate: a nil GetDistance (transient nil UnitPosition — loading screens, instance transitions, taxi/vehicle) now SKIPS just that beacon this frame and keeps it alive, instead of the old DestroyBeacon+`return` that both tore down the homed-in beacon permanently AND starved every later beacon that tick. DestroyBeacon is now reserved for genuine end-of-life. (Severity was overstated HIGH: only fires on nil UnitPosition, never on normal world/flight play — user confirmed beacons tick fine on a flightmaster.)
- tPrevCleanedDirection is a single module-global shared across ALL beacons, so click/clack state is not per-beacon — multiple simultaneous click-cue beacons interfere.
- Debug() is gated by gDebugLevel (hardcoded 0); the many Debug(...) calls are effectively dead unless the local is edited.
- SKUBEACON_MINOR is 3 ([W6-B #18] bumped 2→3 for the RegisterTextInputFrame API) but there is still no oldminor upgrade/migration logic — a reload with an older instance loaded just re-runs the whole chunk.
