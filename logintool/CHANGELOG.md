# WoW Logintool

> **Bekannter Stand — Serverwechsel: Fix unbestätigt.**
> Beim Serverwechsel trat auf, dass ein Enter auf einem Realm den ausgewählten
> Charakter einloggte statt den Server zu wechseln, und dass ein offener
> Realm-Dialog für einen Verbindungsabbruch gehalten wurde. Beides ist behoben
> (Dialog-Prüfung vor jedem Klick auf eine gespeicherte Position; der
> Login-Marker zählt nur noch, wenn weder Realm-Dialog noch Charakterauswahl
> den Bildschirm beanspruchen) — **die Fixes sind jedoch noch nicht am
> laufenden Client getestet.** Charakterauswahl, Erstellen und Löschen sind
> getestet und laufen.

## V2 (unreleased — OCR rework)

Full rework, developed in [Sku75/Sku-WoW-Addon-TBC](https://github.com/Sku75/Sku-WoW-Addon-TBC)
under `logintool/` (see `dev/rework-docs/LOGINTOOL-REWORK-PLAN.md`).

- New V2 driver (AutoHotkey v2) + `SkuLoginSense.exe` sensing helper:
  Windows.Graphics.Capture window capture + Windows.Media.Ocr, fully
  offline and out-of-process (never reads game memory, never injects).
- Character menu announces real names/levels/classes/zones.
- The character list is counted with the arrow keys before the main menu
  appears, the way r1.x did it: a realm holds up to 50 characters while only
  nine slots are visible, so reading the visible section alone dropped every
  character below the fold — the menu numbered the topmost *visible* character
  as 1 and logging in picked the wrong one. Characters out of sight are
  selected with the arrow keys instead of a click, and the walk leaves the
  game's own selection on character 1, matching the menu numbering.
  - The selection highlight is matched by its colour shape (little red, some
    green, strong blue) instead of r1.x's exact texture value: the redesigned
    bar renders anywhere from 0,40,120 to 22,69,152 along its length, so the
    old ±5 window around the texture value never matched it.
  - Both list behaviours are handled: the selection wrapping around past the
    last character (2.5.6, and what r1.x assumed) and stopping at the end.
  - OCR lines that do not sit on the list's left edge are dropped — a sliver
    of background art came back as a line of its own and became the "name" of
    character 1. A block whose first line is the level line is re-read once
    rather than announced as "Stufe 39 Priester".
- Counting a 14-character realm takes ~5 s (r1.x: ~12 s). Two things pay for
  that: probing the nine slots reads one copy of the slot column instead of
  36 single screen pixels (600 ms → 17 ms per keypress — a screen pixel read
  is a compositor round trip, which dwarfed the OCR), and a step ends as soon
  as the highlight has moved instead of always sleeping out the settle time.
  Sensing during the walk OCRs only the character panel (`--region`).
- Race and class names are localized again. Localization keys are matched
  case-insensitively, the way AutoHotkey v1 matched object keys: data.ini asks
  for `human`/`warrior` while the localization files answer with
  `Human==Mensch`/`Warrior==Krieger`, and a v2 Map compares case-sensitively by
  default — so all 19 race and class names fell back to the raw English key in
  every language and every game type. The translations were there all along.
- `flows.ahk` carries a UTF-8 BOM. Without it AutoHotkey reads a UTF-8 file as
  ANSI, which turned the delete keyword `LÖSCHEN` into `LÃ–SCHEN` (and the
  Russian `УДАЛИТЬ` into mojibake): the client rejected the typed word, so
  deleting a character could not be confirmed. The same corruption hit the
  realm-name filter, which stripped umlauts instead of keeping them.
- The delete prompts name the keyword in capitals ("LÖSCHEN wurde in
  Großbuchstaben eingetragen…"), since the field is case-sensitive in practice.
  All five localization files carry the reworded prompts (LÖSCHEN / DELETE /
  EFFACER / BORRAR / УДАЛИТЬ) and the new announcements (list rebuild, unknown
  screen, list may be incomplete) — the tool no longer types the keyword
  itself, so a prompt that still said "press enter to confirm" would have
  walked French, Spanish and Russian users into a failed deletion.
- The character screen is no longer mistaken for the creation screen. The
  helper recognizes the creation screen partly by darkness at a fixed point,
  but that point sits on the 3D scene behind the UI - which is the selected
  character's starting zone. A night elf's zone is dark enough (measured 3,2,4
  against 0,0,0 on the real creation screen) to fire the marker, so the helper
  reported charselect AND charcreate at once and settled on charcreate. The
  tool then escaped out of the "creation screen", which opened WoW's own menu -
  a screen it does not know, so it fell silent right after announcing login
  mode. On the real creation screen charselect is never set, so it now settles
  the tie (`IsCharCreateScreen`, sense.ahk). This hit every night elf, not just
  newly created ones.
- A creation in progress is left alone. Tabbing away and back re-initialized
  the tool, which escaped out of the creation screen the user was naming a
  character on, and then waited 30 s for a creation that could no longer
  finish - indistinguishable from a hang.
- The tool never goes silent. On a screen it has no marker for - WoW's own
  menu is the common one - it used to do nothing at all, which leaves a blind
  user unable to tell "thinking" from "dead"; it now says so and names the way
  out (close the dialog, Alt+F1 twice). Pressing Alt+F1 twice on such a screen
  was silent for the same reason and now answers too.
- A list that could not be counted says so ("may be incomplete") instead of
  presenting the nine visible characters as the whole realm.
- Every count is announced ("the character list is being rebuilt") - after
  login, creating, deleting and realm switching alike - so the seconds of
  silence are explained. The walk no longer beeps; the announcement replaces it.
  Wait beeps remain where the tool waits without an announcement (for the
  creation screen, for the realm dialog).
- Rebuilding the menu waits for the character highlight instead of walking a
  screen that is still busy. Five call sites could hit a screen that was not
  ready - a dialog still covering the list, or the list still being drawn - and
  each silently fell back to the visible section.
- Cancelling a creation no longer re-counts the whole list: nothing changed, so
  the walk was seconds wasted.
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
- Menu navigation interrupts the screen reader again when the voice is
  SAPI2SR. That voice is a bridge, not a synthesizer: it hands the text to
  NVDA and returns, so SAPI's queue is already empty and SVSFPurgeBeforeSpeak
  purges nothing while NVDA reads every queued entry — arrowing down three
  characters spoke all three (with a real voice such as Hedda the same purge
  interrupts correctly). Purging announcements now call NVDA's own
  cancelSpeech, via the controller client that ships with SAPI2SR. Queued
  announcements (SayQueued) are untouched, as are real voices.
- Addons menu removed (the Sku installer handles addon enabling);
  "select region" restored as menu item 9.
- Legacy v1 tool retained as fallback (`START.ahk`).

## [r1.16](https://github.com/Duugu/WoW-Login-Tool/tree/r1.16) (2025-02-17)
[Full Changelog](https://github.com/Duugu/WoW-Login-Tool/compare/r1.15...r1.16) [Previous Releases](https://github.com/Duugu/WoW-Login-Tool/releases)

- 	r1.16 		- Fixed a bug with character creation on Classic Era.  
