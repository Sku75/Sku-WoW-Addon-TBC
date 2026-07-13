# WoW Login Tool v2 — AHK v2 driver over SkuLoginSense

The rework's thin driver (plan Phases 4+5): AutoHotkey v2, all glue-screen
sensing through `SkuLoginSense.exe` (out-of-process capture + fiducial
classification + Windows OCR), OCR-driven features:

- **Character menu announces real names** — "1: Xynayya, Stufe 36 Priesterin,
  Sturmwind" — and selects by clicking the OCR line's own bounding rect.
  No more 50x arrow-down scanning.
- **Realm switching reads the live realm list** (names, type, load) plus the
  language tabs — no hardcoded realm tables, works for all regions/languages.
- **Popups are OCR'd and spoken verbatim**, then dismissed via the fiducial
  button positions. The delete confirmation types the localized keyword
  (deDE/enEN/frFR/ruRU/esES; the client compares case-insensitively).
- Character creation still uses the per-gametype data.ini click positions.

## Keybinds (identical to v1)

- Up/Down/PgUp/PgDn — navigate the spoken menu (PgUp/PgDn = 10 steps)
- Right — descend / re-announce, Left — back up
- Enter — run the item's action (or confirm name entry / deletion)
- Escape — cancel character creation / deletion
- Alt+F1 — toggle pause <-> login mode, Alt+Esc — exit
- Ctrl+Alt+F2 — PrintScreen

## Files

- `START.ahk` — main script (AutoHotkey v2, run with AutoHotkey64.exe)
- `includes/` — log, json (parser), config (settings/localization/data.ini),
  sapi (speech; voice applied once, deliberate purge-vs-queue), sense
  (persistent SkuLoginSense repl child over anonymous pipes,
  CREATE_NO_WINDOW so no console steals focus from the game), ui
  (UI-coord + OCR-rect -> screen clicks), menu (menu engine + mode machine),
  flows (login init, char list/create/delete, realm switch, popup speak),
  keybinds
- `test_sense.ahk` — headless smoke test: loads config, senses the live
  client (no speech, no input), writes `test_sense_out.txt`. Run it after
  changes to the sense/config layers.

Shares `../data/` (settings.ini, data.ini, localization, soundfiles) with the
v1 tool, which stays intact as a fallback. Both write the same settings.ini
schema (v2 adds nothing v1 chokes on).

## Modes (same as v1)

-2 setup (first start: voice -> language -> region -> gametype), -1 paused,
0 in-game (play mode; Numpad7/8 camera helpers), 1 login menu. The 1 Hz mode
watcher uses two native pixel probes (window focus, Sku in-game corner
marker); everything else senses via the helper, throttled and on demand.

## Requirements

- AutoHotkey v2 (the installer ships it; dev machines: v2.0+)
- `SkuLoginSense.exe` — looked up at `helper\SkuLoginSense.exe` (packaged)
  or `helper\SkuLoginSense\bin\Release\net48\` (dev build)
- Windows 10/11 (Windows.Graphics.Capture + Windows.Media.Ocr)

## Known gaps (deliberate)

- Realm queue handling is disabled like in v1 (Anniversary realms have not
  shown queues; open question in the plan).
- Retail locked-race detection was not ported (Retail itself is an untested
  baseline for contributors - see the plan amendment).
- Realm lists longer than one page are not scroll-stitched yet; BC
  Anniversary tabs hold 1-3 realms.
