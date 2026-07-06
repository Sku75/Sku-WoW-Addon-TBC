# W5 — Companion-addon packaging: metadata contract + maintainer proposal

Status 2026-07-06: Sku-side code SHIPPED and IN-GAME VERIFIED (detection,
resolver, discovery, soft dependency): audio by ear unchanged,
`Sku.AudiodataPathInfo` = "SkuAudioData_fast_de (metadata)",
`#GetSoundSets()` = 13 (WVDebug evals, 2026-07-06 18:36). Pack-side changes
are OPTIONAL and backward compatible — old packs keep working unchanged. This
file is the contract for future pack releases and the proposal to the
maintainer.

## What Sku now does

### Voice packs (SkuAudioData*)

- At load, Sku enumerates installed addons whose folder name starts with
  `SkuAudioData` and picks the one matching the client locale. Match sources,
  strongest first:
  1. TOC metadata `## X-SkuVoicePack-Locale: deDE` (plus optional
     `## X-SkuVoicePack-ExtraSpeed: -20`)
  2. Known legacy names (`SkuAudioData` = deDE, `SkuAudioData_en` = enUS)
  3. Folder-name suffix heuristic (`*_de` = deDE, `*_en` = enUS)
- The chosen folder lands in `Sku.AudiodataPath` (same variable as before). A
  legacy pack whose own `Core.lua` overrides `Sku.AudiodataPath` still wins —
  it loads after Sku, exactly as today.
- Why detection at load time matters: it fixes consumers that build paths while
  Sku is loading (previously they baked in the locale guess before the pack's
  glue could run).
- Central resolver in `Sku/Core.lua`: `Sku:VoicePackAudioDir()`,
  `Sku:IntegratedAudioDir()`, `Sku:AudioFile(name)`. Path lookup only — no
  play/stop/queue logic, so simultaneous voice + beacon + aura audio is
  unaffected. `Sku.AudiodataPathInfo` says which pack was picked and why.

### Beacon packs

- `SkuCore/companionPacks.lua` scans ALL installed addons for these TOC fields
  and registers the sets itself at PLAYER_ENTERING_WORLD (sets separated by
  `;`, fields by `|`, folders relative to the pack's `assets\` dir):

```
## X-SkuBeaconSets: <name>|<subfolder>|<degreesStep>|<maxDistance>|<fileName> ; ...
## X-SkuBeaconClickClackSets: <friendlyName>|<internalName>|<subfolder>|<clickFile>|<clackFile> ; ...
```

- `SkuBeacon:RegisterSoundSet` is first-wins, so a pack that ships BOTH the
  metadata and its old `Core.lua` glue registers once with identical data —
  safe transition, no flag day.
- `Sku.toc` no longer hard-depends on `SkuBeaconSoundsets`. If after login no
  beacon soundsets are registered at all, Sku announces it by voice instead of
  refusing to load.

## Proposal to the maintainer (pack-side, optional)

1. Add the metadata lines above to the four companion TOCs (exact lines for
   the current packs are already applied to the local installs here and can be
   copied verbatim).
2. In the NEXT pack releases, drop `Core.lua` + `LibStub.lua` from the beacon
   packs and drop `Core.lua` from voice packs that carry the metadata — the
   packs become pure mp3 payload + TOC + (voice only) index files.
3. Keep the big voice index (`SkuAudioFileIndex` / `SkuAudioDataLenIndex`)
   inside the voice pack — index and payload must travel together (this was
   already the case and is the right design).
4. NOT proposed to execute: merging/renaming the 3 beacon addons into 2 tiers.
   After review the glue was ~30 lines total; the consolidation would be a
   321 MB re-distribution for mostly cosmetic gain. If ever done anyway,
   `SkuInstall.json` / installer topology must follow (W5 checklist C-B3).

## In-game verification (screen-reader friendly)

1. `/skudebug log on`, then `/reload`.
2. Voice: menu speech should sound exactly as before (voice files, not TTS).
   `/wdeval Sku.AudiodataPathInfo` should say `SkuAudioData_fast_de (metadata)`.
3. Beacons: set a beacon, listen — same sounds as before. In the debug log,
   expect `companionPacks: beacon set Beacon 1 … Beacon 13` and two
   `clickclack set` lines (from the TOC metadata, since discovery runs before
   the packs' own glue).
4. Click-tone menu (SkuNav → Ton für Klick bei Beacons) should list Beep/Click
   — now reliably (the 41.05 race is fixed at the source).
5. Speech cutoff when navigating the menu still works (silence-file trick now
   uses Sku's own `silence_1s.mp3`).
6. `/wdeval #LibStub("SkuBeacon-1.0"):GetSoundSets()` should return 13.
