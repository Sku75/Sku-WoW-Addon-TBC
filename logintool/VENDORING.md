# WoW Login Tool — vendoring notes

Vendored 2026-07-13 from the `WoW-Login-Tool.zip` asset on release `v41.03`
of this repo (upstream origin: Duugu/WoW-Login-Tool, release r1.16,
2025-02-17, GPL v3 — see LICENSE.txt). This folder is now the maintained
source; the upstream repo is not tracked.

What is tracked vs. on-disk only:

- Tracked: `START.ahk`, `data/includes/*.ahk` (all logic), `data/*.ini`
  (config + the coordinate/color tables; `data.ini` is UTF-16 LE, marked
  `-text`), `data/localization/*.txt`, `data/soundfiles/` (tiny), docs.
- On disk but gitignored (ship in the release zip instead):
  `CopyTheContentOfThisFolderToInterface/` (~44 MB login-screen textures),
  `data/screenshots/` (~26 MB reference screenshots, current BC Anniversary
  client 2.5.5), `data/localization/translations.xlsx`.
- Excluded from vendoring entirely: `.claude/`, `log.txt` (runtime log).

Quirk carried over from the zip: `data/settings.ini` ships with a saved
setup (BurningCrusade / EUR / deDE / Hedda voice) instead of empty, so a
fresh install skips the first-start setup and starts pre-configured for
German BC Anniversary. Kept as-is for fidelity; revisit when packaging.

Known state at vendoring time: AutoHotkey v1.1; a rework is planned
(WGC window capture + Windows OCR in a small .NET helper, BC-only trim,
AHK v2). See the code review in the dev docs before large edits.
