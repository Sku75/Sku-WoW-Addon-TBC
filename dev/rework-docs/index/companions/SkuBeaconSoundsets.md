# SkuBeaconSoundsets (companion addon — beacon sound pack)
- Installed at `Interface/AddOns/SkuBeaconSoundsets`. TOC version 20, Interface 11508. No `## Dependencies` line (it self-bootstraps LibStub + SkuBeacon at runtime).

## Purpose
- The **base beacon sound pack**: it supplies the directional/distance ping soundsets AND the click/clack bearing-cross cue pairs that `Libs/SkuBeacon-1.0` plays for audio navigation. Ships the four default beacons ("Beacon 1".."Beacon 4") and two click/clack sets. Historically this was a hard TOC dependency of Sku; as of W5 it no longer is (see companionPacks.lua) but it remains the canonical/default provider that most users need installed to hear any beacon at all.

## TOC metadata contract
- The TOC declares its content in two W5 metadata lines (semicolon-separated sets; `|`-separated fields; paths relative to the addon's `assets/` folder):
  - `## X-SkuBeaconClickClackSets: Beep|click|clickClackSoundset|clack.mp3|click.mp3 ; Click|beep|clickClackSoundset|click_fast.mp3|clack_fast.mp3`
    - fields: `<friendlyName>|<internalName>|<subfolder>|<clickFile>|<clackFile>`.
  - `## X-SkuBeaconSets: Beacon 1|Notification_soft_100|5|30|notification_soft_100 ; Beacon 2|probe_deep_1|5|30|probe_deep_1 ; Beacon 3|steel_gong|5|30|steel_gong ; Beacon 4|probe_mid_1|5|30|probe_mid_1`
    - fields: `<setName>|<subfolder>|<degreeStep>|<maxDistance>|<baseFileName>`.
- How Sku consumes it (`Sku/SkuCore/companionPacks.lua`, `RegisterBeaconPacks()` at `PLAYER_ENTERING_WORLD`): Sku enumerates every loadable addon, reads its `X-SkuBeaconSets` / `X-SkuBeaconClickClackSets` metadata, splits on `;` then `|`, validates (non-empty name, numeric step & maxDistance, non-empty file), and calls:
  - `SkuBeacon:RegisterSoundSet(setName, "Interface\\AddOns\\<addon>\\assets\\<subfolder>", step, maxDistance, baseFileName)`
  - `SkuBeacon:RegisterClickClackSoundSet(friendlyName, internalName, "Interface\\AddOns\\<addon>\\assets\\<subfolder>", clickFile, clackFile)`
- This is the **data-driven path** and is redundant with this pack's own `Core.lua` (below), which does the same registrations. Registration is idempotent (first-wins), so running both paths is harmless.

## Lua glue shipped
- `Core.lua` — a legacy self-registering glue frame: on `PLAYER_ENTERING_WORLD` it grabs `LibStub("SkuBeacon-1.0")` and calls `RegisterClickClackSoundSet` twice and `RegisterSoundSet` four times with exactly the values encoded in the TOC metadata, then `UnregisterAllEvents()`. This is why the pack works even on a Sku build that predates companionPacks.lua.
- `LibStub.lua` — a bundled public-domain LibStub v2 stub, so the pack can resolve `SkuBeacon-1.0` even in load orderings where Sku's own LibStub isn't guaranteed first. (No `## Dependencies` on the TOC, so it cannot rely on Sku's libs having loaded.)
- `README.md` (stub), `nul` (0-byte stray file), `CHANGELOG` — none load.
- TOC load list: just `Core.lua` (LibStub is pulled implicitly? — actually LibStub.lua is NOT in the TOC's file list; only `Core.lua` is listed). The `nul` file and `LibStub.lua` are on disk but the TOC only names `Core.lua`.

## Asset footprint
- Folder total: ~82 MB. 8,780 files, all `.mp3`, 0 ogg.
- Per soundset subfolder under `assets/`:
  - `Notification_soft_100/`: 2,194 files (baked `<name>;<degree>;<distance>.mp3` grid + 4 click/clack copies).
  - `probe_deep_1/`: 2,194 files.
  - `probe_mid_1/`: 2,194 files.
  - `steel_gong/`: 2,194 files.
  - `clickClackSoundset/`: 4 files (`click.mp3`, `clack.mp3`, `click_fast.mp3`, `clack_fast.mp3`).
- mp3s counted only, never enumerated.

## Invariants
- First-wins registration: `SkuBeacon:RegisterSoundSet` bails at `if gSoundsetRepo[aBaseName] then return end` (keyed by set name), and `RegisterClickClackSoundSet` bails at `if gClickClackSoundsetRepo[aInternalName] then return end` (keyed by internal name). So whichever path registers "Beacon 1" (or clickclack "click"/"beep") first wins; the second identical registration is a no-op. This is what makes the TOC-metadata path and the shipped `Core.lua` path safely coexist.
- Naming collision namespace: set names ("Beacon 1".."Beacon 4") and clickclack internal names ("click"/"beep") are the dedup keys. Other beacon packs MUST use different set names or they will be silently dropped by first-wins (Essential uses "Beacon 5/6", Additional "Beacon 7".."13").
- If SkuBeacon isn't present yet: both the `Core.lua` frame and companionPacks.lua guard `LibStub("SkuBeacon-1.0", true)` and quietly do nothing rather than erroring.
- If this addon is missing entirely: no beacon sounds register. Sku no longer hard-depends on it (companionPacks.lua removed the TOC dependency), so the client still loads; companionPacks.lua's 3-second post-login check finds an empty `GetSoundSets()` and announces once by voice: "Keine Beacon-Sounds gefunden. Bitte das Addon SkuBeaconSoundsets installieren." — a spoken nudge, not a load failure.
- Directional mp3 grid is a hard file-name contract with SkuBeacon (`<baseFileName>;<degree>;<distance>.mp3`, degree in `step` increments, distance 1..maxDistance); a missing baked file plays silently.
