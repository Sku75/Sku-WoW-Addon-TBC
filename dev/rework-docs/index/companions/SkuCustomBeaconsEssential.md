# SkuCustomBeaconsEssential (companion addon — extra beacon sounds)
- Installed at `Interface/AddOns/SkuCustomBeaconsEssential`. TOC version 30, Interface 11508, `## Dependencies: Sku, SkuBeaconSoundsets`.

## Purpose
- An **optional add-on beacon pack** that extends the base set with two more directional soundsets, "Beacon 5" and "Beacon 6". Purely additive: it registers into the same `SkuBeacon-1.0` repo alongside SkuBeaconSoundsets. "Essential" = the smaller/recommended extra pack (2 sets), vs "Additional" (7 sets). Users pick beacon voices in Sku's nav settings from whatever sets are registered.

## TOC metadata contract
- One W5 metadata line:
  - `## X-SkuBeaconSets: Beacon 5|beacon5|5|30|beacon5 ; Beacon 6|beacon6|5|30|beacon6`
  - fields per set: `<setName>|<subfolder>|<degreeStep>|<maxDistance>|<baseFileName>`.
- No `X-SkuBeaconClickClackSets` (it ships no click/clack cues).
- Consumed identically to SkuBeaconSoundsets: `Sku/SkuCore/companionPacks.lua` `RegisterBeaconPacks()` (at `PLAYER_ENTERING_WORLD`) reads `X-SkuBeaconSets`, validates fields, and calls `SkuBeacon:RegisterSoundSet("Beacon 5", "Interface\\AddOns\\SkuCustomBeaconsEssential\\assets\\beacon5", 5, 30, "beacon5")` (and likewise "Beacon 6"). The shipped `Core.lua` also registers the same two, first-wins makes the duplication a no-op.

## Lua glue shipped
- `Core.lua` — legacy self-registering frame: on `PLAYER_ENTERING_WORLD`, `LibStub("SkuBeacon-1.0")` then two `RegisterSoundSet` calls for beacon5/beacon6 with the exact TOC values, then `UnregisterAllEvents()`.
- `LibStub.lua` — bundled public-domain LibStub v2 stub (on disk; not listed in the TOC's file list, which names only `Core.lua`). Belt-and-braces so `SkuBeacon-1.0` resolves regardless of load order.
- TOC has a real `## Dependencies: Sku, SkuBeaconSoundsets`, so it loads after both — this is the stronger guarantee than the bundled stub.

## Asset footprint
- Folder total: ~15 MB. All `.mp3`.
- Per soundset subfolder under `assets/`:
  - `beacon5/`: 2,263 files.
  - `beacon6/`: 2,263 files.
- mp3s counted only, never enumerated.

## Invariants
- First-wins registration keyed by set name: "Beacon 5"/"Beacon 6" don't collide with the base pack's "Beacon 1".."4" or Additional's "Beacon 7".."13", so all coexist. If some other pack registered "Beacon 5" first, this one's would be silently dropped — the naming scheme (contiguous integers) is the de-facto coordination between the three beacon packs.
- Depends on SkuBeaconSoundsets in the TOC but that dependency is now about ordering/expectation, not sounds — its own two sets are self-contained under its own `assets/`. If SkuBeaconSoundsets were absent, WoW would mark this addon as missing-dependency and not load it (TOC hard dep), so in practice it only runs when the base pack is present.
- If this addon is missing: "Beacon 5"/"Beacon 6" simply aren't offered; base beacons still work. No load impact on Sku (Sku doesn't depend on it).
- Same `<baseFileName>;<degree>;<distance>.mp3` grid contract with SkuBeacon; missing baked files play silently.
