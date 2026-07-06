# SkuCore/companionPacks.lua
- Purpose: W5 data-driven registration of beacon-sound companion packs. Scans all installed addons' TOC metadata for `X-SkuBeaconSets` and `X-SkuBeaconClickClackSets` and registers the declared soundsets with the SkuBeacon library, removing Sku's hard TOC dependency on SkuBeaconSoundsets. Old packs with their own Core.lua keep working because SkuBeacon:RegisterSoundSet is first-wins. If no beacon sounds exist at all after login, a one-time voice hint tells the user to install SkuBeaconSoundsets.

## Public API / exports
- none (everything file-local: RegisterBeaconPacks + an anonymous event frame).

## Dependencies (outgoing)
- Libs/SkuBeacon-1.0 via LibStub (soft — silently skips if absent): RegisterSoundSet, RegisterClickClackSoundSet, GetSoundSets.
- SkuOptions.Voice:OutputStringBTtts (the missing-sounds announcement).
- dprint (SkuDebugLog breadcrumbs for each registered/bad entry).
- WoW APIs: C_AddOns.GetNumAddOns/GetAddOnInfo/GetAddOnMetadata (with legacy global fallbacks), C_Timer.After, CreateFrame.

## Key data structures
- TOC metadata formats (sets ";"-separated, fields "|"-separated, paths relative to the pack's assets folder):
- X-SkuBeaconSets entry: Name | subfolder | degree step (number) | max distance (number) | filename.
- X-SkuBeaconClickClackSets entry: display name | internal name | subfolder | click file | clack file.
- Registered path is built as "Interface\AddOns\<packName>\assets\<subfolder>".

## Events
- PLAYER_ENTERING_WORLD on an anonymous frame; unregisters itself immediately (one-shot), runs RegisterBeaconPacks.
- C_Timer.After(3 s) check for zero soundsets — delayed because legacy packs also register at PLAYER_ENTERING_WORLD, so both paths must have run first.

## Settings keys
- none.

## Entry points
- Event-driven only (PLAYER_ENTERING_WORLD); no slash commands, keybinds or menu nodes.

## Invariants & gotchas
- SkuBeacon:RegisterSoundSet is first-wins: a metadata pack and a legacy Core.lua pack declaring the same set is harmless, but the first registration decides the data — do not change to last-wins.
- The 3-second delay before the "no sounds" warning is load-order glue for legacy packs; shortening it produces false alarms.
- Malformed entries are skipped per-entry with a dprint breadcrumb (whole pack is not rejected); numeric fields are validated with tonumber.
- The "Keine Beacon-Sounds gefunden..." message is a hardcoded German literal, not routed through Sku.L.
