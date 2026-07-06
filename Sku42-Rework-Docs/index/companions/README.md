# Companion addons — topology

Sku ships as a core addon plus a family of **companion addons** installed separately in `Interface/AddOns/` (they live outside this repo — each has its own release zip). They are data addons: pre-baked audio corpora that Sku's libraries play. This folder indexes the four real ones the live install carries.

## The four indexed companions

### Voice pack (speech audio)
- **SkuAudioData_fast_de** — the deDE sped-up voice pack: ~98k baked mp3 clips + two Lua index tables (`SkuAudioFileIndex`, `SkuAudioDataLenIndex`) that let `SkuVoice-1.0` speak full UI strings. Locale-selected via `X-SkuVoicePack-Locale`/`X-SkuVoicePack-ExtraSpeed` metadata (scored in `Sku/Core.lua`) with a legacy `Core.lua` override. Optional but effectively required for real speech — without any `SkuAudioData*` pack Sku falls back to its small bundled integrated voice.

### Beacon sound packs (navigation audio)
- **SkuBeaconSoundsets** — the base/default beacon pack: directional soundsets "Beacon 1".."4" + the click/clack bearing cues. Registered into `SkuBeacon-1.0` either from its `X-SkuBeaconSets`/`X-SkuBeaconClickClackSets` TOC metadata (via `Sku/SkuCore/companionPacks.lua`) or its own shipped `Core.lua`. **No longer a hard TOC dependency of Sku** (W5 removed it); if absent, Sku still loads and speaks a one-time voice nudge to install it, but no beacon sounds play.
- **SkuCustomBeaconsEssential** — optional extra pack, sets "Beacon 5"/"Beacon 6". Hard TOC-depends on Sku + SkuBeaconSoundsets.
- **SkuCustomBeaconsAdditional** — optional extra pack, sets "Beacon 7".."Beacon 13". Hard TOC-depends on Sku + SkuBeaconSoundsets.

## Hard-requirement vs optional
- **Sku core**: does NOT hard-require any of these four (the old TOC dependency on SkuBeaconSoundsets was dropped in W5). The client loads with none installed.
- **In practice required for a usable experience**: a voice pack (a `SkuAudioData*` matching the locale) for speech, and SkuBeaconSoundsets for any beacon navigation audio.
- **Genuinely optional**: SkuCustomBeaconsEssential and SkuCustomBeaconsAdditional — extra beacon voices only. Each hard TOC-depends on Sku + SkuBeaconSoundsets, so WoW won't load them unless the base pack is present.

## Shared mechanisms
- **Metadata-driven registration (W5)**: beacon packs declare their sets in TOC `X-SkuBeaconSets` / `X-SkuBeaconClickClackSets`; voice packs declare `X-SkuVoicePack-Locale` / `X-SkuVoicePack-ExtraSpeed`. Sku reads these centrally (`companionPacks.lua` for beacons, `Core.lua` scorer for voice) so a new pack needs no glue code.
- **Legacy Core.lua glue still honored**: every pack also ships a self-registering `Core.lua` (and beacon packs bundle a LibStub stub). Registration is first-wins/idempotent, so the metadata path and the legacy path coexist harmlessly. This keeps the packs working on Sku builds that predate the W5 metadata readers.
- **First-wins soundset keys**: `SkuBeacon:RegisterSoundSet`/`RegisterClickClackSoundSet` dedup by set name / internal name; the contiguous "Beacon 1..13" integer naming is the de-facto coordination that keeps the three beacon packs from colliding.

## Deliberately NOT indexed here
- **SkuNavData** and **SkuHealthAssets** exist in the wider Sku companion ecosystem but are **WowVision extensions** (the sibling accessibility project), not part of this Sku documentation index. They are intentionally excluded from the W6 companion index.
