# Third-party libraries (`Sku/Libs/`)

Every folder under `Sku/Libs/` **except** Sku's own libs (`SkuVoice-1.0`,
`SkuBeacon-1.0`, `SkuTTS-1.0`, which are documented separately). Versions are
read from each lib's own header / `NewLibrary(MAJOR, MINOR)` line.

## Load path (who pulls each lib in)

- Most Ace3 libs load via `embeds.xml` (itself `<Include>`d from `Sku.toc`).
  Load order there: LibStub, AceAddon, CallbackHandler, AceConsole, AceGUI,
  AceDB, AceConfig, AceDBOptions, AceEvent, AceLocale, AceSerializer, AceComm,
  LibSharedMedia.
- `LibRangeCheck-3.0` and `LibGearScore-1.0` load **directly from `Sku.toc`**
  (lines 15 and 18), not through `embeds.xml`.

## The Ace3 framework libs

- **LibStub** — MAJOR "LibStub", MINOR 2. The tiny public-domain version stub
  every other lib registers through; loaded first in `embeds.xml`. Foundation of
  the whole Ace3 stack.
- **CallbackHandler-1.0** — revision `$Id: ...1186 2018-07-21...$`, MINOR 7. The
  callback/event dispatch engine that AceEvent, AceComm, LibSharedMedia, etc.
  are built on.
- **AceAddon-3.0** — MINOR 12. Addon-object template (OnInitialize / OnEnable /
  OnDisable lifecycle). Sku is an AceAddon; this is the backbone of every module.
- **AceEvent-3.0** — MINOR 4. Game-event registration and secure dispatch (wraps
  CallbackHandler). Underlies `SkuDispatcher` and every module that listens to
  WoW events.
- **AceConsole-3.0** — MINOR 7. Slash-command registration + arg parsing. Powers
  Sku's many `/sku...` commands.
- **AceDB-3.0** — MAJOR/MINOR 26. SavedVariables + profile/char/realm/namespace
  management. Backs `SkuOptionsDB` and the deeply nested `SkuOptions.db` settings.
- **AceDBOptions-3.0** — revision `$Id: ...1193 2018-08-02...$`, MINOR 15.
  Ready-made AceConfig options screen for managing AceDB profiles.
- **AceConfig-3.0** — MINOR 3, wrapper revision `$Id: ...1161 2017-08-12...$`.
  Registers options tables + binds them to slash commands. This is the folder
  that actually loads (see the duplicate note below). Bundles three sub-modules:
  `AceConfigCmd-3.0`, `AceConfigDialog-3.0`, `AceConfigRegistry-3.0`.
- **AceGUI-3.0** — MAJOR/MINOR 36. Widget toolkit AceConfigDialog builds its GUIs
  from; has a `widgets/` subfolder.
- **AceLocale-3.0** — MINOR 6, revision `$Id: ...1035 2011-07-09...$`. Localization
  with base-locale fallback (Sku ships enUS/deDE locales).
- **AceSerializer-3.0** — MINOR 5. Serializes tables/values to a comm-safe string;
  used with AceComm for addon-to-addon messaging (e.g. aura sharing).
- **AceComm-3.0** — MINOR 12. Unlimited-length addon-channel messaging with
  auto-split/rebuild; ships its own `ChatThrottleLib.lua`. Used for cross-client
  Sku features (aura/quest sharing).

## Standalone utility libs

- **LibSharedMedia-3.0** — Revision 114, MINOR 8020003 ("8.2.0 v3"), by Elkano.
  Shared registry of fonts/sounds/textures/etc. across addons; depends on LibStub
  + CallbackHandler.
- **LibRangeCheck-3.0** — MINOR 31, by mitch0 / WoWUIDev, MIT. Range checking via
  interact distances and spell ranges. Loaded directly from the TOC; backs
  `SkuCore/RangeCheck.lua`.
- **LibGearScore-1.0** — MAJOR "LibGearScore.1000", MINOR 6 (TOC version 1.0.r6,
  Interface 30400/Wrath), by Road-block, Limited BSD. Computes GearScore /
  average item level from inspect data. Loaded directly from the TOC.
  **Odd:** ships a self-contained copy of its own dependencies in a nested
  `Libs/` folder (`LibStub`, `CallbackHandler-1.0`) plus two TOCs
  (`LibGearScore-1.0.toc` and `..._Wrath.toc`) and a LICENSE — a standalone
  bundle dropped in whole, so it carries redundant copies of libs Sku already
  loads at the top level.

## Cleanup candidate: duplicate AceConfig folder

- **`_AceConfig-3.0`** — a near-complete second copy of AceConfig-3.0 (same
  MINOR 3, same wrapper revision 1161, same three sub-modules). It is **not
  loaded**: `embeds.xml` includes `Libs\AceConfig-3.0\AceConfig-3.0.xml`, and a
  repo-wide grep finds **zero** references to `_AceConfig`. `diff -rq` against the
  live `AceConfig-3.0` shows the folders are identical except for
  `AceConfigDialog-3.0/AceConfigDialog-3.0.lua`, which differs. This is dead
  weight — a leftover/backup of AceConfig that should be deleted (the `_` prefix
  looks like a manual "disable this copy" rename that was never cleaned up).
