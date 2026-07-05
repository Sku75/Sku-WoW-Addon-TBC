# Sku 42 — Known Issues

Running log of known issues, regressions, and gotchas for the Sku 42 rework.
Keep entries short and actionable. Move resolved items to a "Resolved" section
(with the commit/date that fixed them) rather than deleting, so we keep the
history.

## Format (per entry)

- **Title** — one line.
  - Symptom: what is observed (what is spoken / what breaks).
  - Repro: deterministic steps if known.
  - Suspected cause / area: file or workstream.
  - Status: open / investigating / workaround / blocked.

## Setup / environment gotchas (carried from the rework setup)

- **Shared SavedVariables with v41.** Same addon name + same account = same
  `Sku.lua` (`SkuOptionsDB`). v42's settings-schema rework (W1) can rewrite the
  saved settings v41 expects. Test v42 against the WTF backup / a copied account,
  or accept that v42 testing migrates the live settings. Never run both clients
  at once.
- **Symlink swap to test v42.** WoW loads the addon via the `AddOns\Sku` symlink.
  It currently points at the v41 tree (`...\Sku-TBC\Sku`). To test v42, repoint
  it (admin, `mklink /D`) at `...\Sku-TBC-42\Sku`, and point it back to test v41.

## Open issues (bugs)

Carried in from the v41 line / reported by the maintainer. German term kept with
an English gloss where the term is Sku-specific. Repro/area are best-guess until
investigated.

- **Arena queries not working** ("Arena Abfragen funktionieren noch nicht").
  - Symptom: arena-related queries / announcements do not function yet.
  - Repro: TBD (enter/query arena context).
  - Suspected area: arena data/query code (to be located).
  - Status: open.
- **Focus-key inconsistencies vs WoW's Focus** ("Inkonsistenzen mit WoWs Focus
  und der Sku-Implementation für Fokus-Tasten").
  - Symptom: Sku's focus-key implementation behaves inconsistently with WoW's
    native focus (focus target) system.
  - Repro: TBD (set/clear focus via WoW vs via Sku focus keys, compare).
  - Suspected area: `SkuCore/skuFocus.lua` and how it relates to WoW's focus.
    Good candidate to reconcile during W4 (state ownership / one writer).
  - Status: open.

## Code quality (deferred — documented, not scheduled)

Low-value cleanups left after W4. Recorded so they aren't rediscovered as
"surprises"; intentionally not fixed (cost/risk > benefit).

- **Geo callers not repointed onto `SkuNav.Geo`.** ~59 external calls still use
  `SkuNav:X` directly. The facade is declared (W4-B) but repointing gives ZERO
  coupling-metric change (still the token `SkuNav`) and adds a delegation call on
  hot geo paths (`Distance`, `GetCurrentAreaId`) — mild perf cost vs W3. Leave.
- **Last category-C read-only state on SkuCore.** `talentSet` (write-once const in
  TBC), `GossipList`, `SkuRaidTargetIndex` are still bare `SkuCore.<field>` reads
  cross-module. Benign single-owner read-only data; wrapping in services is churn
  for no real decoupling. Leave (revisit only if one becomes mutable).
- **`SetOpenMenuAfter*` is shared state, not an event.** SkuZOptions sets these via
  the SkuCore owner-API (already the clean form, W4-C). A dispatcher-event rewrite
  would obscure that it's persistent state SkuCore reads+clears, and the call sites
  are asymmetric (one commented out, Core.lua:1760). Leave as the owner-API edge.
- **Solo addons stay top-level AceAddons, not SkuCore submodules** (SkuChat / Nav /
  Quest / Auras / Mob). NOT just a cosmetic keyword: `NewAddon`→`NewModule` moves
  AceAddon **lifecycle ownership** (init/enable ordering) under SkuCore and forces
  `GetAddon`→`GetModule` at every resolver — real blast-radius on the 5 biggest,
  most-coupled units for no functional gain. They are ALREADY unified where it
  matters: own namespace + one Features menu + one toggle API; the dual-path
  knowledge is contained to `ModuleManager:ResolveToggleObject` (the `external`
  flag), so consumers treat all features uniformly. Treat THIS note as the answer
  to "wait, are these special?" — they're peers by design, managed identically.

## Feature requests / wishlist

Maintainer-requested features for the v42 line. Several overlap existing
workstreams (noted) — fold them in there when that workstream runs.

- **Shift+Enter / Ctrl+Enter for left- and right-click.** Keyboard bindings in
  menus to trigger a left-click (Shift+Enter) and right-click (Ctrl+Enter).
  Relates to W2 (menu action semantics) and secure-action handling.
- **Default macro to insert.** Provide a ready-made default macro the user can
  insert (e.g. into the macro UI) for common Sku actions — so a screen-reader
  user does not have to author secure macros by hand. Scope/contents TBD with
  the maintainer.
- **Quest button functionality.** Add quest-button functionality (a button /
  menu action to interact with quests — accept/turn-in/track). Relates to
  `SkuQuest`; exact behaviour TBD with the maintainer.
- **Loading times.** Reduce addon load/reload time. Relates to W3 (load-time cost
  of the big Lua data tables: `routedata_global_wotlk.lua`, `SkuDB/assets`).
- **Nicer-looking popups.** Improve popup appearance.
- **Menu rework.** Overhaul the menus — the core of W2 (declarative menu schema +
  registry, decoupled from module structure).
- **PLANNED: Blizzard-TTS language mixing (German/English auto-switch).** We
  play on an international server; English/German mixed content is constant.
  Plan: small Lua language detector (stopword lists + umlauts/ß signal) that
  sets the per-message voice automatically — the plumbing already exists
  (per-message `aVoice` override / `mSkuVoiceQueueBTTS_Voice` side-map built
  for per-channel chat voices). Bonus experiment: the dormant SAPI
  `<LANG LANGID>` tag code (`SkuVoice-1.0.lua:742`, `SapiLangIds` deDE=407 /
  enUS=409) might allow MID-sentence language switching, since `<silence>` /
  `<pitch>` tags already pass through. Depends on which voice backend WoW
  enumerates today (OneCore vs SAPI5 — under investigation 2026-07-05; SAPI5
  voices reportedly no longer appear in the voice list). Revisit when that is
  settled.
- **PLANNED (conditional): dual-language Sku voice databank loader.** If we
  generate a new sample databank (e.g. in the user's screen-reader voice),
  rework the audio-pack loader so the deDE and enUS banks can load SIDE BY
  SIDE: today both packs write the same globals (`SkuAudioFileIndex` /
  `SkuAudioDataLenIndex`, pack `Core.lua` overrides `Sku.AudiodataPath`), so
  only one language exists at runtime. Needed shape: per-language index
  tables + `SkuVoice:GetAudiodata` (SkuVoice-1.0.lua:1324) trying the
  detected-language bank first and the other bank as per-word fallback —
  word-level German/English mixing for the concatenative voice.

## Monitoring (external projects — re-check on request)

- **Syntherceptor (jcsteh) as future replacement for the bundled NVDA-SAPI voice.**
  Ask: "check the Syntherceptor monitor". SAPI5 voice DLL that forwards speech
  to NVDA (github.com/jcsteh/syntherceptor, installer at
  syntherceptor.jantrid.net, GPLv2, free, bundling permitted with GPL text +
  source link). As of 2026-07-05 NOT suitable for Sku; switch only when ALL of
  these are true (deliberately no workaround documentation here — public-comms
  decision of 2026-07-05):
  1. **Releases are Authenticode-signed.** Blizzard clients refuse to load
     unsigned SAPI engine DLLs (since ~Oct/Nov 2025), so upstream-signed
     releases are a hard requirement. Check: download the current installer
     from syntherceptor.jantrid.net, run `Get-AuthenticodeSignature` on the
     exe AND the inner `x64\syntherceptor.dll` — need Valid, not NotSigned.
     Also check `.github/workflows/build.yml` for a signing step (none as of
     2026-07-05) and the repo for signing-related issues/commits.
  2. **The game-interrupt problem is fixed on `main`.** As of 2026-07-05 every
     `Speak()` cancels NVDA speech AND utterances complete instantly
     (`GetOutputFormat` returns `SPDFID_Text`, no audio timing), so queued
     game TTS lines clip each other — only the last queued line is heard.
     Check: issue #1 closed, and/or experimental branches `ssml` /
     `cancelIfNewSite` merged; read `src/syntherceptor.cpp` `Speak()` — the
     "cancel speech before each utterance" hack must be gone, ideally replaced
     by the SSML-completion-callback approach.
  3. **Fit test against Sku's speech pattern before any switch:** rapid menu
     navigation must interrupt cleanly AND multi-line queued output (chat
     backlog, tooltip + menu breadcrumb) must NOT clip. Test with the normal
     Sku BTTS queue on a dev char.
  Nice-to-have signals: versioned releases instead of rolling snapshots (today
  a rolling "snapshots" tag — every update changes the DLL), game-related
  reports in the issue list, crash reports (a host-app-takedown crash class
  was fixed 2026-01, issues #2/#3).
  Alternative to re-check briefly at the same time: SAPIence
  (github.com/LeonarddeR/SAPIence, LGPL, Rust, same mechanism) — as of
  2026-07-05 zero releases/binaries, not a candidate yet.

## Resolved

- **Weapon/spell oil (Zauberöl) — applying to an equipped weapon threw a Lua
  error** — fixed 2026-06-30 (`SkuZOptions/Core.lua`, equipment-slot right-click
  handler). Using an oil starts a spell-TARGETING mode (`SpellIsTargeting()`,
  NOT a cursor item), so the old unequip path's `PickupInventoryItem` was
  `ADDON_ACTION_FORBIDDEN`. Right-click on an equipped item is now a three-path,
  build-time decision: (1) targeting active → secure `/click <Slot> RightButton`
  applies the oil/poison/stone/enchant; (2) item has an on-use effect
  (`GetItemSpell`) → secure `/use <slotID>` fires it; (3) plain gear → manual
  unequip to first free bag. All three confirmed in-game by the maintainer.
- **Dynamic updating of bag entries, values, etc.** — DONE (W2 live menus,
  2026-06-28). `liveName` leaf getters + `volatileChildren` lists + event-driven
  bag re-pin by stable identity (bagSlot→itemId) with a speak-when-settled gate,
  replacing stale snapshots without re-anchoring the menu.
- **SkuAuras "Optionen" submenu empty placeholder** — confirmed resolved by the
  maintainer 2026-06-30 (Auren → Optionen now has content / the dead entry is
  gone, following the W2/W7 menu rework).
- **v42 worktree was missing the gitignored runtime assets** — fixed by copying
  all 12,809 gitignored files (`SkuDB/assets/`, `routedata_global_wotlk.lua`,
  `audio/`, scattered binaries) from the v41 tree into `Sku-TBC-42\Sku\`
  (2026-06-25). The worktree is now runnable once the symlink points at it.
  Note: the large *external* audio companions (voice DB, beacons, ~790 MB) are
  separate installed addons and were not touched — see Workstream 5.
