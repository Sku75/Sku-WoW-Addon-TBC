# WoW Login Tool

## r2.0 (unreleased — OCR rework)

Full rework, developed in [Sku75/Sku-WoW-Addon-TBC](https://github.com/Sku75/Sku-WoW-Addon-TBC)
under `logintool/` (see `dev/rework-docs/LOGINTOOL-REWORK-PLAN.md`).

- New v2 driver (AutoHotkey v2) + `SkuLoginSense.exe` sensing helper:
  Windows.Graphics.Capture window capture + Windows.Media.Ocr, fully
  offline and out-of-process (never reads game memory, never injects).
- Character menu announces real names/levels/classes/zones; selection
  clicks the recognized OCR entry directly.
- Realm switching reads the live realm list (all regions/languages);
  hardcoded realm tables removed.
- Popups spoken verbatim; delete confirmation types the localized keyword
  (deDE/enEN/frFR/ruRU/esES).
- Fiducial texture redesign: dark-red buttons, dark-blue selection bar,
  unique char-create marker — OCR-readable and low-vision friendly.
- Readable font override (Atkinson Hyperlegible, OFL) in `fonts\`.
- SAPI: voice applied once (no swap race), deliberate purge-vs-queue,
  configurable output device (`gAudioOutputMatch` in settings.ini),
  errors logged.
- Addons menu removed (the Sku installer handles addon enabling);
  "select region" restored as menu item 9.
- Legacy v1 tool retained as fallback (`START.ahk`).

## [r1.16](https://github.com/Duugu/WoW-Login-Tool/tree/r1.16) (2025-02-17)
[Full Changelog](https://github.com/Duugu/WoW-Login-Tool/compare/r1.15...r1.16) [Previous Releases](https://github.com/Duugu/WoW-Login-Tool/releases)

- 	r1.16 		- Fixed a bug with character creation on Classic Era.  
