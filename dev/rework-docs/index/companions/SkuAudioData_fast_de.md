# SkuAudioData_fast_de (companion addon — voice pack)
- Installed at `Interface/AddOns/SkuAudioData_fast_de` (outside this repo; ships only inside its own release zip). TOC version 3, Interface 11508, `## Dependencies: Sku`.

## Purpose
- A **voice pack**: the pre-recorded German (deDE) TTS audio corpus Sku speaks the UI with. It ships ~98k baked `.mp3` clips under `assets/audio/` plus two Lua lookup tables that map a spoken token to its file name and playback length. The `_fast_de` variant is the sped-up German set — it declares an extra playback-speed offset so words play faster than the integrated fallback voice. Without a voice pack installed Sku falls back to its own tiny integrated audio dir (`Sku/SkuAudioData/assets/audio/<Loc>/`); the pack is what makes full-sentence speech available.

## TOC metadata contract
- The TOC carries two W5 voice-pack metadata lines that Sku reads directly (no glue needed):
  - `## X-SkuVoicePack-Locale: deDE` — the client locale this pack serves.
  - `## X-SkuVoicePack-ExtraSpeed: -20` — optional per-pack speed offset stored into `Sku.AudiodataExtraSpeed`.
- How Sku consumes it (`Sku/Core.lua`, lines ~95-130, runs at Sku load time because TOC metadata is readable for not-yet-loaded addons): Sku enumerates every installed addon whose name matches `^SkuAudioData` and scores each candidate for the wanted locale (`Sku.Loc`, with enGB/enAU folded to enUS):
  - score 3 `"metadata"` — has `X-SkuVoicePack-Locale` matching the client locale (this pack's path).
  - score 2 `"legacy name"` — no metadata, but the addon name is a hardcoded legacy pack (`SkuAudioData`→deDE, `SkuAudioData_en`→enUS).
  - score 1 `"name suffix"` — falls back to the trailing `_de`/`_en` suffix on the addon name.
  - Highest score for the matching locale wins; the winner's folder name is stored in `Sku.AudiodataPath` and a human-readable `Sku.AudiodataPathInfo` (e.g. `"SkuAudioData_fast_de (metadata)"`), and its `X-SkuVoicePack-ExtraSpeed` (if numeric) into `Sku.AudiodataExtraSpeed`.
- The single resolver `Sku:VoicePackAudioDir()` returns `Interface\AddOns\<Sku.AudiodataPath>\assets\audio\` on every call (re-reads the field so a later legacy override still wins). `Sku:AudioFile(name)` prefixes it. `Libs/SkuVoice-1.0` then looks each spoken token up in the global `SkuAudioFileIndex` / `SkuAudioDataLenIndex` tables this pack loaded, and plays `VoicePackAudioDir()..fileName`.

## Lua glue shipped
- `Core.lua` (a legacy-style override, still shipped and still honored):
  ```lua
  if Sku.Loc == "deDE" then
    Sku.AudiodataPath = "SkuAudioData_fast_de"
    Sku.AudiodataExtraSpeed = -20
  end
  ```
  This is the pre-W5 mechanism. It loads AFTER Sku (TOC `Dependencies: Sku`) and hard-overwrites `Sku.AudiodataPath`, so it wins over the metadata scorer regardless of score. The new metadata lines make this glue redundant for metadata-aware Sku, but it is kept so the pack still works against older Sku builds that lack the scorer.
- `assets/SkuAudioFileIndex.lua` (~4.7 MB) — defines the global `SkuAudioFileIndex = { ["<token>"] = "<file>.mp3", ... }` (spoken-string → mp3 name).
- `assets/SkuAudioDataLenIndex.lua` (~3.8 MB) — defines the global `SkuAudioDataLenIndex = { ["<file>.mp3"] = <seconds>, ... }` (mp3 name → clip length, used to schedule the next queued clip). Note these are the NON-integrated globals (the `*Integrated` variants belong to Sku's bundled fallback voice).
- TOC load order: `assets\SkuAudioFileIndex.lua`, `assets\SkuAudioDataLenIndex.lua`, `Core.lua`.

## Asset footprint
- Folder total: ~271 MB.
- `assets/audio/`: 98,483 `.mp3` files (flat directory), 0 ogg.
- Two Lua index tables in `assets/`: `SkuAudioFileIndex.lua` ~4.7 MB, `SkuAudioDataLenIndex.lua` ~3.8 MB (~8.5 MB of tracked-style Lua, though it ships in the zip, not this repo).
- All mp3 assets are gitignored-by-policy binary blobs; only counted here, never enumerated.

## Invariants
- Selection is deterministic and metadata-first: the `metadata`(3) > `legacy name`(2) > `name suffix`(1) fallback order means a pack that declares `X-SkuVoicePack-Locale` always beats an equally-named legacy/suffix guess for the same locale; ties never happen (strictly `>` on distinct scores, and only one pack per locale is expected).
- Legacy `Core.lua` override wins last: because it runs after Sku and unconditionally assigns `Sku.AudiodataPath`, a shipped `Core.lua` overrides the scorer's choice for its locale. Keep the two in agreement (both point at `SkuAudioData_fast_de` here) or drop the glue on metadata-aware Sku to avoid surprise.
- If NO `SkuAudioData*` pack matches the locale: `Sku.AudiodataPath` stays `""`, `VoicePackAudioDir()` returns `nil`, `AudioFile()` returns `nil`, and `SkuVoice` cannot resolve pack clips — Sku falls back to the bundled integrated audio (`SkuAudioFileIndexIntegrated[Sku.Loc]`). No crash, just the smaller built-in voice.
- The mp3 naming and the two index globals are a hard contract with `SkuVoice-1.0`: a token present in `SkuAudioFileIndex` but missing an on-disk mp3 (or missing a length entry) fails to speak that token silently rather than erroring.
