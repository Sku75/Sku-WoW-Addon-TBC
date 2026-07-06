# SkuAudioData/assets/SkuAudioFileIndex.lua + SkuAudioData/assets/SkuAudioDataLenIndex.lua
- Purpose: Two large static lookup tables (thin generated data, no logic) that map Sku's spoken-string keys to pre-recorded audio files and those files to their playback durations. They are the backing store for pre-recorded ("integrated") voice output — the male/female localized clips for directions, movement states, UI words, etc. Both are single-assignment table literals (~3200 lines each); the values below describe their shape and consumer, not the data.

## Public API / exports
- `SkuAudioFileIndexIntegrated` (global) — maps a spoken string key → mp3 filename. Shape: `SkuAudioFileIndexIntegrated[<locale>][<key>] = "<file>.mp3"`. Top-level locales present: `deDE` and `enUS`. Keys are voice-prefixed strings like `["male-Nord"]`, `["male-Draußen"]`, `["male-Folgen beendet"]`.
- `SkuAudioDataLenIndexIntegrated` (global) — maps an mp3 filename → duration in seconds (float). Shape: `SkuAudioDataLenIndexIntegrated[<locale>][<file>.mp3] = <seconds>`. Same `deDE`/`enUS` top-level locales.

## Dependencies (outgoing)
- none (pure data literals; no requires, no APIs).

## Key data structures
- Both are two-level tables keyed first by WoW locale code (`deDE`, `enUS`), then by string-key (file index) or by filename (length index). The two are chained: consumer looks up a key in the file index to get a filename, then uses that filename in the length index.

## Events
- none

## Settings keys
- none

## Entry points
- Consumed by `Libs/SkuVoice-1.0/SkuVoice-1.0.lua` (~line 1297): `SkuAudioFileIndexIntegrated[Sku.Loc][aString]` resolves the clip file, and `SkuAudioDataLenIndexIntegrated[Sku.Loc][file]` resolves its length (used to time/queue TTS output). `Sku.Loc` selects the locale sub-table.

## Invariants & gotchas
- The two tables must stay in lockstep: every filename produced by the file index for a locale must have a matching duration entry in the length index for that same locale, or the length lookup returns nil.
- Locale coverage is `deDE` + `enUS` only; a `Sku.Loc` outside those yields a nil sub-table (callers must guard, as SkuVoice does with the `~= nil` check before use).
- Generated data — regenerate rather than hand-edit; keys embed the voice prefix (`male-`/`female-`) so a voice/gender change is a different key, not a table swap.
