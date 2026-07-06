# SkuCore/DialTargeting.lua
- Purpose: "Dial targeting" — lets the player target party/raid members by typing their subgroup+slot on the numpad (NUMPAD digits build a two-key code, decode to a raid roster slot, secure-target it). Built entirely on secure handler frames so the actual `/target` fires from a hardware click during combat. A user-toggleable AceAddon submodule (`SkuCore.DialTargeting`).

## Public API / exports
- `DialTargeting:OnEnable()` / `OnDisable()` — arm (defaults + init + resolve state) / disarm (unregister callbacks + disable bindings).
- `DialTargeting:DialTargetingOnLogin()` — seed dialTargeting settings defaults.
- `DialTargeting:DialTargetingOnInitialize()` — create the three secure frames once, wire refs, register callbacks.
- `DialTargeting:DialTargetingRegisterCallbacks()` / `DialTargetingUnregisterCallbacks()` — (un)subscribe the 6 group/roster dispatcher events.
- `DialTargeting:DialTargetingGetCurrentRoster()` — read back the roster stored in secure-frame attributes as a [group][slot]=name table.
- `DialTargeting:DialTargetingRosterUpdate()` — repopulate secure-frame unitNameSlot attributes + override bindings from GetRaidRosterInfo, branching raid/raid10/party.
- `DialTargeting:DialTargetingEnable()` / `DialTargetingDisable()` — install/tear down numpad override bindings; both defer to PLAYER_REGEN_ENABLED if in combat.
- `DialTargeting:DialTargeting_EndableDisable()` — decide enable vs disable from group type + user setting (note: "Endable" misspelling).
- `DialTargeting:DialTargeting_PLAYER_ENTERING_WORLD / _PARTY_LEADER_CHANGED / _GROUP_FORMED / _GROUP_JOINED / _GROUP_LEFT / _GROUP_ROSTER_UPDATE` — dispatcher handlers.
- `DialTargeting:DialTargetingMenuBuilder()` — build the 3 settings submenus (Enabled scope, Key Sound, Single key in raids up to 10).

## Dependencies (outgoing)
- SkuDispatcher, SkuSettings:Sub("SkuCore").dialTargeting, SkuOptions.db.profile.SkuOptions.soundChannels, SkuOptions:InjectMenuItems/SkuGenericMenuItem, SkuCore.inCombat, Sku.L.
- Secure templates: SecureHandlerStateTemplate, SecureActionButtonTemplate, SecureHandlerClickTemplate; RegisterStateDriver, SecureHandlerWrapScript, SecureHandlerExecute, Set/ClearOverrideBindingClick, SetBindingClick (in-snippet).
- WoW: GetRaidRosterInfo, UnitInRaid/UnitInParty, UnitName, PlaySoundFile, MAX_RAID_MEMBERS.

## Key data structures
- Secure-frame attributes on SkuSecureTargetingFrame: enabled, groupType ("raid"/"raid10"/"party"/nil), unit, playername, and unitNameSlotGG-SS (per group 01-10, slot 01-05) = member name.
- SkuSecureTargetingToggleHandler attribute `lastButton` = the first pressed numpad button (empty when idle).

## Events
- SkuDispatcher subscriptions: PLAYER_ENTERING_WORLD, PARTY_LEADER_CHANGED, GROUP_FORMED, GROUP_JOINED, GROUP_LEFT, GROUP_ROSTER_UPDATE; plus PLAYER_REGEN_ENABLED (one-shot, for combat deferral of Enable/Disable/RosterUpdate).
- State driver "targetstate" ([@target,exists]) resets bindings after a raid target.

## Settings keys
- SkuSettings:Sub("SkuCore").dialTargeting: enabled (Off/Party/Raid/Party and Raid), keySound (No sound/On first/On second/On first and second key), singleKeyinRaid10 (On/Off).

## Entry points
- Numpad override bindings NUMPAD0-9, NUMPADPLUS (Button100 = cancel path), NUMPADDECIMAL (Button99 = target none). Menu nodes via DialTargetingMenuBuilder. Feature toggle via RegisterToggleableModule. Toggles visibility of SkuSkriptRecognizer frames.

## Invariants & gotchas
- Secure frames must be created only once and never recreated in combat — OnInitialize early-returns to just re-register callbacks if SkuSecureTargetingFrame already exists.
- All roster mutations and binding changes are gated on `SkuCore.inCombat` and deferred to PLAYER_REGEN_ENABLED; breaking that guard causes protected-frame taint/errors.
- The party branch skips the player and only fills unitNameSlot01-*; a large commented-out debug print block sits at lines 320-328.
- Repeated near-identical raid/raid10/party binding-setup blocks (lines 251-336) are a copy-paste cleanup candidate.
- Six dispatcher handlers all dprint the wrong label ("DialTargeting_PARTY_LEADER_CHANGED") regardless of actual event.
