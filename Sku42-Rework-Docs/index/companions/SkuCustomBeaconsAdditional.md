# SkuCustomBeaconsAdditional (companion addon — extra beacon sounds)
- Installed at `Interface/AddOns/SkuCustomBeaconsAdditional`. TOC version 30, Interface 11508, `## Dependencies: Sku, SkuBeaconSoundsets`.

## Purpose
- An **optional add-on beacon pack** that extends the base set with seven more directional soundsets, "Beacon 7" through "Beacon 13". Purely additive into the shared `SkuBeacon-1.0` repo. The larger sibling of SkuCustomBeaconsEssential (7 sets vs 2); together the three packs give up to 13 selectable beacon voices.

## TOC metadata contract
- One W5 metadata line:
  - `## X-SkuBeaconSets: Beacon 7|beacon7|5|30|beacon7 ; Beacon 8|beacon8|5|30|beacon8 ; Beacon 9|beacon9|5|30|beacon9 ; Beacon 10|beacon10|5|30|beacon10 ; Beacon 11|beacon11|5|30|beacon11 ; Beacon 12|beacon12|5|30|beacon12 ; Beacon 13|beacon13|5|30|beacon13`
  - fields per set: `<setName>|<subfolder>|<degreeStep>|<maxDistance>|<baseFileName>`.
- No `X-SkuBeaconClickClackSets`.
- Consumed by `Sku/SkuCore/companionPacks.lua` `RegisterBeaconPacks()` at `PLAYER_ENTERING_WORLD`: splits the seven `;`-separated sets, validates each, and calls `SkuBeacon:RegisterSoundSet("Beacon N", "Interface\\AddOns\\SkuCustomBeaconsAdditional\\assets\\beaconN", 5, 30, "beaconN")` for N=7..13. The shipped `Core.lua` registers the same seven; first-wins makes the overlap a no-op.

## Lua glue shipped
- `Core.lua` — legacy self-registering frame: on `PLAYER_ENTERING_WORLD`, `LibStub("SkuBeacon-1.0")` then seven `RegisterSoundSet` calls (beacon7..beacon13) with the exact TOC values, then `UnregisterAllEvents()`.
- `LibStub.lua` — bundled public-domain LibStub v2 stub (on disk; not in the TOC file list, which names only `Core.lua`).
- Real `## Dependencies: Sku, SkuBeaconSoundsets` guarantees load ordering after both.

## Asset footprint
- Folder total: ~159 MB. All `.mp3`.
- Per soundset subfolder under `assets/` (each 2,263 files): `beacon7/`, `beacon8/`, `beacon9/`, `beacon10/`, `beacon11/`, `beacon12/`, `beacon13/` — 7 × 2,263.
- mp3s counted only, never enumerated.

## Invariants
- First-wins registration keyed by set name; "Beacon 7".."Beacon 13" are disjoint from the base pack ("1".."4") and Essential ("5"/"6"), so all thirteen coexist. The contiguous-integer naming is the coordination contract across the three packs — a duplicate set name would be silently dropped.
- TOC hard-depends on SkuBeaconSoundsets: WoW won't load this addon if the base pack is absent, so it effectively only ever runs alongside the base pack. Its seven sets are self-contained under its own `assets/`.
- If this addon is missing: "Beacon 7".."13" aren't offered; base + Essential beacons unaffected; no impact on Sku load (Sku doesn't depend on it).
- Same `<baseFileName>;<degree>;<distance>.mp3` grid contract with SkuBeacon; missing baked files play silently.
