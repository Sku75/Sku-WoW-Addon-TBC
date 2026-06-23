# Sku (TBC) — Screen Reader Interface for World of Warcraft

Sku is a World of Warcraft addon that provides a complete screen-reader
interface, making the game accessible for blind and visually impaired players
(works with NVDA/JAWS). This repo is a **development workspace** for the TBC
Anniversary version (Interface 11508, currently v41.06).

## Origin & contribution model (read first)

- The upstream project is `Sku75/Sku-WoW-Addon-TBC` on GitHub, BUT that repo
  **does not track the addon source** — it only holds a GitHub Pages download
  page and install guides. The actual Lua source ships **only inside release
  ZIP assets** (e.g. `Sku-41.06.zip`).
- Because upstream has no source tree, a normal GitHub code PR is not currently
  possible. This repo was seeded by extracting the official `Sku-41.06.zip`.
- Contribution-back path: produce a clean diff/patch against the pristine
  release baseline and send it to the maintainer through their channel (GitHub
  issue, Discord, email). See "Git workflow" below.

## Git workflow

- Branch `upstream` = pristine, never-hand-edited imports of official releases.
  Tag per version (`v41.06`, ...). Re-import a new release here by extracting
  its zip over this branch and committing.
- Branch `main` = our development work, branched from `upstream`.
- **Layout note:** on `main` the addon source lives under the `Sku/` subfolder
  (see "Repo layout" below), but the `upstream` branch and the `v41.06` tag
  still have the source at the repo root (that's how the release zip is shaped).
- To generate a contribution patch, diff the upstream **root** tree against our
  `Sku/` **subtree** so the subfolder move adds no rename noise:
  `git diff v41.06 main:Sku` (for one path: `git diff v41.06:<path>
  main:Sku/<path>`). Patches are code-only by design. Avoid plain
  `git format-patch v41.06..main` now — it would drag in the giant move commit.
- No `origin` remote is configured yet — this is a local-only repo for now.

## Repo layout

- The repo root holds only `.git`, this `CLAUDE.md`, and the `Sku/` subfolder.
- **All addon source lives under `Sku/`** — that folder is the addon root
  (`Sku/Sku.toc`, `Sku/SkuCore/`, `Sku/Libs/`, etc.) and is what WoW's symlink
  points at (see "Running in-game"). Paths elsewhere in this doc are relative to
  `Sku/` unless stated otherwise.
- `Sku/.gitignore` and `Sku/.gitattributes` live alongside the source so their
  patterns stay anchored to the addon root (no edits needed after the move).

## Repo contents vs on-disk files

- `Sku/.gitignore` excludes bulky **binary assets** (`*.mp3`, `*.ogg`, fonts,
  images) and **large generated game-data tables** (`routedata_global_wotlk.lua`,
  everything under `SkuDB/assets/`). These remain on disk so the addon runs,
  but are not version-controlled (they are ~290 MB and rarely hand-edited).
- ~150 Lua/XML/TOC source files ARE tracked. When you need to edit an ignored
  data file, force-add it deliberately.
- `Sku/.gitattributes` forces LF so diffs stay clean against the upstream
  release.

## Running in-game

- `AddOns\Sku` is a **directory symbolic link** to this repo's `Sku/` subfolder
  (`C:\Users\fabia\Dev\Sku-TBC\Sku`), so edits here are live in WoW after a
  `/reload`. It targets `Sku/` (the addon root), not the repo root. (A real
  symlink, created with admin via `mklink /D` — the proven-working path here;
  recreate it the same way if a release re-import or move ever clears it.)
- The previously installed v41.04 is backed up at
  `AddOns\Sku.preDev-backup-v41.04`.
- Required companion addons (already installed separately, not in this repo):
  `SkuBeaconSoundsets` (a hard dependency in the TOC), plus `SkuNavData`,
  `SkuHealthAssets`, and the `SkuAudioData_*` language pack.

## Debugging (WVDebug helper addon)

The sibling addon `C:\Users\fabia\Dev\WVDebug` is a shared, dependency-free
debug helper that captures live UI/addon state into SavedVariables for
out-of-game reading. It loads automatically alongside Sku. See
`../WVDebug/README.md` for the full command list. The most useful for Sku:

- `/wdsku` — dump the current Sku menu (focused item, breadcrumb, siblings,
  children) **plus** what Sku would speak (`spoken`) and the last TTS reading
  frame text (`ttsFrameText`). This is the "what Sku shows the user" capture.
- `/wdsku3` — same idea but recursively expands the whole current level down 3
  levels into a `tree` (builds dynamic submenus on demand); use for a fuller
  tree dump.
- `/wdwatchsku` — toggle continuous logging of every line Sku announces (hooks
  `SkuOptions.Voice:OutputStringBTtts`/`:OutputString`).
- `/wdframes`, `/wdframe <Name>`, `/wdeval <expr>`, `/wdmenu`, `/wdwatcherrors`
  — addon-agnostic captures.

Read-back loop: run a command in game, `/reload` to flush, then read
`...\WTF\Account\1107979492#1\SavedVariables\WVDebug.lua` (`WVDebugData` =
latest, `WVDebugLog` = history).

### Reading SkuErrorLog (Sku's own breadcrumb/error log)

Sku writes its own structured log via `SkuErrorLog:Log(module, msg, tbl)`
(source `auction.scan` / `auction.buy` / `auction.event`, etc.; see
`SkuCore/ErrorLog.lua`). It persists in the **`SkuErrorLog` global inside
`...\SavedVariables\Sku.lua`** (not a file of its own). It has two stores —
**read the right one**:

- **`SkuErrorLog.recent`** — the **chronological** ring buffer (last 500
  events). Each entry is flat and ordered: `seq` (monotonic, the tiebreak when
  several events share a one-second `t`), `t`, `source`, `message`, `stackHead`
  (first stack frame only), `session`. **This is the store to read for a
  timeline.**
- **`SkuErrorLog.unique`** — deduplicated by message+top-stack fingerprint
  (`count`, `firstSeen`, `lastSeen`, full `stack`, `firstCtx`/`lastCtx`). Use it
  for "how often / first–last seen / full stack of a given message", **not** for
  ordering (chronology is lost, repeats merged). Note breadcrumbs embed payload
  numbers, so each is its own fingerprint — they fill the 250 cap without truly
  deduping.

The file is a multi-line Lua table (one field per line, records span ~8 lines),
so a single-line `grep` can't reconstruct a record — parse it with `py -3`
(Python 3, bare `python` is a Store stub) or read `recent` directly. In-game:
`/skulog show` (last 10, now prefixed with `#seq`), `/skulog export` (copyable
window), `/skulog clear`.

### Syntax-checking Lua edits

No `lua`/`luac` on PATH, but the `luaparser` Python package is installed —
syntax-check before a `/reload`:

```
py -3 -c "from luaparser import ast; ast.parse(open('Sku/SkuCore/auctionHouse.lua', encoding='utf-8-sig').read()); print('OK')"
```

Use `encoding='utf-8-sig'` — Sku's Lua files start with a UTF-8 BOM that the
parser otherwise errors on. This validates syntax only (not runtime/logic or WoW
API use), so it's a first gate, not a substitute for the in-game test.

## Architecture

Sku is built on **Ace3** (AceAddon, AceEvent, AceConfig, AceComm, etc., under
`Libs/`). Load order is defined in `Sku.toc`. SavedVariables:
`SkuOptionsDB`, `SkuTranslatedData`, `SkuErrorLog`.

Module folders (each typically has `Core.lua` + `Options.lua`):

- `SkuDispatcher/` — central event broker. Modules subscribe/publish here
  rather than wiring WoW events directly.
- `SkuCore/` — the bulk of features (one file per feature): `aq.lua` /
  `aqCombat.lua` (health & combat monitoring), `gameWorldObjects.lua`,
  `minimapScanner.lua`, `auctionHouse.lua`, `mail.lua`, `friends.lua`,
  `voiceOutput.lua`, `UIErrors.lua`, `DialTargeting.lua`, `turnToUnit.lua`,
  `equipmentSets.lua`, `Build_SocketingFrame.lua`, `dungeonBrowser.lua`, etc.
- `SkuDB/` — static game database (maps, creatures, items, quests, spells,
  objects, polygons, waypoints), split by content: base/TBC + `WotLK/` + `SoD/`.
  These are the large generated `assets/` tables (gitignored).
- `SkuNav/` — audio-beacon navigation (routes, waypoints, minimap nav `SkuMM`).
- `SkuQuest/` — quest tracking/announcement.
- `SkuAuras/` — aura/buff/debuff tracking, role detection, aura sharing.
- `SkuMob/` — target/mob tracking.
- `SkuChat/` — chat accessibility.
- `SkuZOptions/` — settings/menu system, voice config, keybinds
  (`SkuKeyBinds.lua`), templates, utilities (the menu-builder framework).
- `SkuAudioData/` — audio file index/length tables for voice output.
- `Libs/` — Ace3 plus Sku's own libs: `SkuTTS-1.0`, `SkuVoice-1.0`,
  `SkuBeacon-1.0`, `LibRangeCheck-3.0`, `LibGearScore-1.0`.

Settings live in deeply nested tables under `SkuOptionsDB` (e.g.
`SkuOptions.db.char[module]...`). The menu UI is generated by `SkuZOptions`.

## Relationship to WowVision

The sibling project `C:\Users\fabia\Dev\WowVision` is a separate accessibility
addon (different architecture: middleclass/InfoClass). Its `tbc/sku/` folder is
a **port** of some Sku features into WowVision — not the same codebase. Having
the real Sku source here side-by-side makes maintaining that port easier to
diff against.
