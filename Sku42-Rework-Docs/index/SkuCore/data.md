# SkuCore/data.lua
- Purpose: Pure static-data module for SkuCore. Defines localized constant tables used across the addon: minimap/world scan profiles, scan-object type list, the full default keybinding map, key-name localization, error/range-check sound file maps, sound-channel constants, and background ambience sound files with lengths. No functions, no logic — just table literals assigned onto `SkuCore.*` and two globals (`SKU_CONSTANTS`, and localized `SkuCore.Errors.Sounds`). Sits at the bottom of the dependency tree; other SkuCore files read these tables.

## Public API / exports
- `SkuCore.ScanTypes` — 7 scan profiles (name/desc + horizontal/vertical step geometry) for the object scanner.
- `SkuCore.ScanObjects` — index->string list of scannable object categories (corpses, creatures, herbs, veins, bobber, etc.).
- `SkuCore.Keys.SkuDefaultBindings` — the default keybinding map, grouped by BINDING_HEADER_* section; each action has `index` and optional `key1`/`key2`.
- `SkuCore.Keys.LocNames` — key-token -> localized display name (uses Blizzard KEY_* globals plus a few L[] entries).
- `SkuCore.Errors.Sounds` — locale-gated (deDE vs enUS/enGB/enAU) map of error sound file paths -> spoken labels; includes a `["voice"]` = vocalized sentinel.
- `SkuCore.RangeCheckSounds` — file path -> label map for range-check beep selection.
- `SKU_CONSTANTS.SOUNDCHANNELS` — global; WoW sound channel key -> localized name (Master/SFX/Music/Ambience/Dialog/Talking Head).
- `SkuCore.BackgroundSoundFiles` — background ambience filename -> localized label.
- `SkuCore.BackgroundSoundFilesLen` — background filename -> length in seconds.

## Dependencies (outgoing)
- `Sku.L` (localization table) — every label goes through `L[...]`.
- `Sku.Loc` — locale gate selecting the deDE vs enUS branch of `Errors.Sounds`.
- Blizzard global constants: `CTRL_KEY_TEXT`, `KEY_*` family (KEY_BACKSPACE, KEY_NUMPAD0..9, etc.).
- Assumes `SkuCore` addon table already exists (does not create it).

## Key data structures
- `SkuDefaultBindings`: nested `[headerName][actionName] = { index=<n>, key1=?, key2=? }`. `index` = Blizzard binding order index; `-1` used for shapeshift buttons. Several sections commented out (RAID_TARGET, VEHICLE, some INTERFACE/LFG entries).
- `ScanTypes[n]`: `{ name, desc, hStepSizeDeg, hStepsMax, vMoveSpeed, vStepsMax, hStart }`.

## Events
- none

## Settings keys
- none (constant data only)

## Entry points
- none (no slash/keybind/menu registration here; the binding data is consumed elsewhere, e.g. SkuKeyBinds)

## Invariants & gotchas
- `BackgroundSoundFilesLen` (lines 1234-1257): many entries use a COMMA where a decimal point was clearly intended, e.g. `["benny_hill.mp3"] = 238,8`. In a Lua table constructor `238,8` parses as TWO array-positional values (238 then 8), so the intended `238.8` length is silently lost and the key gets no value — a real bug for every comma-form entry (benny_hill, chor1/2/4, entspannungsmusik, gewitter, nachts_im_wald, wald, walgesang, slowreggaet). Dot-form entries (chor3, catpurrwaterdrop, creaking-wood, etc.) are correct.
- `Errors.Sounds` only exists for deDE/enUS/enGB/enAU — other locales leave it nil; consumers must nil-guard.
- Large commented-out blocks (Marlene/Hans voiced error packs, RAID_TARGET, VEHICLE bindings) are dead but intentionally kept as reference.
- deDE and enUS `Errors.Sounds` branches are near-identical (only the commented voiced-pack paths differ) — copy-paste duplication.
