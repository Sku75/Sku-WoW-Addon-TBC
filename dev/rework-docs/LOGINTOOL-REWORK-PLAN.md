# WoW Login Tool — full rework plan (OCR-based)

Status: approved 2026-07-13, execution starts next session.
Source lives at `logintool/` (vendored from Duugu r1.16, GPL v3).
Full code review + validation happened 2026-07-13; this doc is the
execution contract so no context is lost between sessions.

## Hard rules (never violate)

- NEVER read or write WoW process memory, never inject into the game
  process. All sensing is out-of-process (window capture), all acting is
  synthetic input. This is the anti-ban design line.
- Offline/onboard only: Windows.Graphics.Capture + Windows.Media.Ocr
  (OS components), .NET Framework 4.8 (in-box). NO cloud services, NO
  self-contained .NET runtime (would add 60-90 MB for nothing).
- GPL v3 stays (LICENSE.txt), assets stay out of git (logintool/.gitignore).
- Every test procedure must be blind-verifiable: CLI output, logs, OCR
  probe pattern. Claude reads captures visually when a sighted check is
  genuinely needed (proven workflow: Read tool on the probe PNG).

## Validated facts (do not re-derive)

- Windows OCR reads the BC Anniversary 2.5.5 glue screens well. Proven on
  bundled screenshots (1920x1080) AND live capture (user display 2880x1800).
  Reads: char names/levels/zones, realm names/types/load, popup text,
  button labels, with per-line bounding rects.
- Font override works: `_anniversary_\Fonts\` with FRIZQT__/ARIALN/
  MORPHEUS/skurri TTFs is honored by the client (Atkinson Hyperlegible
  currently installed and visually confirmed active). The Fonts folder
  PRE-EXISTS with Blizzard *.slug data — never delete the folder, only our
  4 TTFs (install_wow_fonts.ps1 -Remove does this correctly).
- Remaining OCR failures are caused by the tool's OWN legacy fiducial
  textures: pure-white selection highlight (yellow-on-white unreadable) and
  pure-red buttons (yellow-on-red). Fix = fiducial redesign (Phase 3).
- The game logo is artwork, not font — irrelevant to OCR; screen identity
  comes from fiducials.
- Bot-risk delta of the new stack: none. WGC is the same OS API OBS and
  Discord use; OCR runs on our own image; helper exe is out-of-process like
  AutoHotkey.exe. Input side gets LESS bot-like (no more 50x arrow-down).
- data.ini quirks: UTF-16 LE (git attr -text). BC data exists ONLY as
  [BurningCrusade] + [BurningCrusade-EUR] (2 hardcoded realms:
  Thunderstrike PvE, Spineshatter PvP) + [BurningCrusade-EUR-deDE]
  (one realm tab "Jubiläum"). OCR removes the need for these realm tables.
- Load-bearing fiducial colors (from data.ini [BurningCrusade]):
  GenericRedButton 255,0,0; logos ~198,223-227,0-2; contract logo 50,57,0;
  contract addons 64,0,0; RealmSelectionTitleBackdrop 0,56,0;
  RealmSelectionListBackdrop 40,0,0; scrollbar 15,0,0; GenericBlue 0,0,255
  (in-game corners); delete popup backdrop 0,40,0 + editbox 3,17,3;
  IsWhiteUI >250,250,250 (selection highlight); greys 139,139,139.
- Known code bugs (from the review): SAPI PlayUtterance purges every
  utterance (Speak flag 3), voice-swap race around async speak, all SAPI
  errors swallowed, hardcoded output device substring "Headset" (sapi.ahk);
  delete-char keyword only auto-typed for deDE/enEN (menus.ahk ~603);
  main-menu item 9 built twice — region menu (menus.ahk 726-763) is dead,
  overwritten by addons menu (765-828); IsRealmQueue() hard-returns false.

## Phases

Work autonomously through phases; commit per phase (conventional commits,
push to main). Consolidate in-game testing into the marked checkpoints so
the user tests few times, not per-change.

### Phase 1 — v1 cleanup (small diffs, still AHK v1)
1. Remove the addons menu (menus.ahk 765-828) and AddonListAction
   (helpers.ahk 245-325) — the installer handles addon enabling now.
   Removing the addons block un-shadows the "select region" menu, which
   stays as item 9 (needed for multi-client/multi-region support).
2. ~~Strip to BurningCrusade-only~~ **AMENDED 2026-07-13 (user decision):
   keep compatibility with ALL clients** (Retail/Cata/Classic/BC/Era).
   gametypes.ini keeps all entries; Retail/Cata/Classic branches
   (UpdateFavoriteSlots, GetLockedRaces, GetNumberOfChars50Retail,
   customize clicks, per-gametype scrollbar math) stay in place as a
   minimal untested-but-present baseline so someone with a Retail install
   can contribute fixes later. Phase 5 OCR makes most per-client tables
   moot anyway (char/realm/popup data read live); only char-creation
   click positions remain per-gametype in data.ini.
3. SAPI fixes: set the tool voice ONCE (not per utterance — kills the
   voice-swap race); make purge-vs-queue deliberate (purge on nav
   keypresses, queue on sequential announcements); log SAPI exceptions to
   log.txt instead of swallowing; move gAudioOutputMatch ("Headset") into
   settings.ini with empty default = system default device.
4. Delete-keyword: cover frFR/ruRU/esES. The popup itself states the
   required word — interim: add the three keywords (verify in-client);
   final: Phase 5 OCRs the popup and types whatever it demands.
CHECKPOINT A (user, in-game): tool still works end to end in v1 on BC.

### Phase 2 — C# sensing helper (new: logintool/helper/, net48)
- Console exe `SkuLoginSense.exe`: finds the WoW window (WowClassic.exe
  main HWND), captures it via Windows.Graphics.Capture (WinRT interop from
  net48; GDI PrintWindow fallback), runs Windows.Media.Ocr, emits JSON to
  stdout: { screen: "<fiducial-derived id>", lines: [{text, x, y, w, h}],
  pixels: [probed fiducial colors] }.
- Modes: `sense` (one shot), `sense --region x,y,w,h`, `save <png>`
  (debug captures). Deterministic, testable from CLI without the game
  (--image <png> mode against logintool/data/screenshots/).
- Build with `dotnet build -c Release` targeting net48 (same toolchain as
  installer; do NOT use release.ps1 patterns that trip the classifier).
CHECKPOINT B (CLI only, no game needed): helper output correct on the
bundled screenshots; then one live run with WoW open.

### Phase 3 — fiducial texture redesign
- Prereq: BLP↔PNG tooling (open-source BLPConverter or similar, offline,
  bundleable into dev tooling — research first, this is the only unknown).
- Redesign the two OCR-hostile textures: selection highlight → dark
  background + thin unique-color border (fiducial in the border, text stays
  high-contrast); red buttons → keep unique marker color at corner/edge,
  readable text surface. Both double as low-vision readability wins.
- Add one unique flat marker color per glue screen at a stable,
  non-animated anchor so screen identity is one pixel probe per screen
  (current logo fiducials are half-broken on Anniversary: no yellow logo on
  char-select, char-create logo drifts ~10px with idle animation).
- Update data.ini colors + checks accordingly.
CHECKPOINT C (user + Claude reads capture): new textures in client, helper
identifies every screen, OCR reads the selected entry cleanly.

### Phase 4 — AHK v2 port of the thin driver
- Port ONLY the trimmed driver (hotkeys, menu tree, SAPI speech, mode
  logic); all sensing goes through SkuLoginSense. Closures replace the
  Func().Bind() workarounds; Maps replace the object-table pitfalls;
  proper try/catch replaces ErrorLevel loops.
- Keep keybind semantics identical (arrows/PgUp/PgDn/Enter/Esc, alt+f1,
  alt+esc, ctrl+alt+f2).
- Ship AutoHotkey v2 runtime: installer already embeds AHK v1 exe
  (LoginToolInstaller.cs EnsureRuntimeAndShortcut) — swap the embedded
  payload to the v2 exe, keep license file.

### Phase 5 — OCR-driven features (the payoff)
- Character menu announces REAL names: "Xynayya, Stufe 36 Priesterin,
  Sturmwind" instead of "Character 2". Selection by clicking the line's
  own bounding rect (no more 50x arrow-down scanning).
- Realm switching reads the live realm list (scroll + capture + stitch);
  removes the hardcoded EUR-deDE-only realm tables → all regions/languages
  work.
- Popups: OCR the text, speak it verbatim, find the button by its label.
  Delete-confirm types whatever keyword the popup demands.
- Char counting = one capture.
CHECKPOINT D (user, in-game): full flow — select char by name, enter
world, create char, delete char, switch realm.

### Phase 6 — packaging + installer + release
- Rebuild WoW-Login-Tool.zip from logintool/ (source + textures + helper
  exe + fonts + AHK v2 runtime note). Ship empty settings.ini (the r1.16
  zip shipped a pre-filled one — packaging bug, first-start setup should
  run).
- Installer (LoginToolInstaller.cs): add font-install step (port
  install_wow_fonts.ps1 logic to C#: copy 4 TTFs into <client>\Fonts\,
  never delete the folder), embed AHK v2 exe, bump Config.LoginToolTag,
  update docs/index.html links.
- Update readme.txt (remove Retail/Cata claims, new keys/features),
  CHANGELOG.md.

## Open questions (ask the user when relevant, don't block on them)

- What exactly is "NVDA SPI SR 2" (the NVDA/SAPI bug context from the
  original request)? Needed to confirm the Phase 1 SAPI fixes cover it.
- Do TBC Anniversary realms ever queue? (IsRealmQueue is disabled; if
  queues exist, reimplement via OCR of the queue popup text in Phase 5.)
- Exact delete keywords for frFR/ruRU/esES clients (Phase 5 makes this moot).

## Testing infrastructure already in place

- `logintool/fontprobe/font_probe.ps1` — countdown capture + OCR print
  (also -Image mode for offline runs against data/screenshots/).
- `logintool/fontprobe/install_wow_fonts.ps1` — font override on/off.
- Bundled screenshots in `logintool/data/screenshots/` are CURRENT client
  (2.5.5, Mar 31 2026) — regression test set for the helper's --image mode.
- Fonts are currently INSTALLED in the user's client.
