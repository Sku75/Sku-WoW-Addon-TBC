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

- **Weapon/spell oil (Zauberöl) not working** ("Zauberöl auftreten geht noch
  nicht").
  - Symptom: applying / detecting / announcing weapon oil (Zauberöl) does not
    work yet.
  - Repro: TBD (apply a weapon oil, expect detection/announcement).
  - Suspected area: weapon-enchant / aura tracking (`SkuAuras`, the `AURA_*`
    weapon-buff + enchant-expiration code).
  - Status: open.
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

- **SkuAuras "Optionen" submenu is an empty placeholder.**
  - Symptom: navigating Auren → Optionen enters a menu with no children — nothing
    to read; feels like "can't enter the options".
  - Repro: Sku menu → Auren → Optionen.
  - Cause: `SkuAuras.options.args` is `{}` (never populated), so the
    `IterateOptionsArgs(SkuAuras.options.args, …)` call in `SkuAuras:MenuBuilder`
    builds 0 children. Pre-existing (present on v41); NOT caused by the W1 settings
    migration — confirmed during B3 testing (no Lua error logged, `/wdsku` shows
    the entry with numChildren=0).
  - Status: open (pre-existing). Either remove the dead entry or populate it with
    the real SkuAuras toggles. Candidate for W2 (menu rework) / W6 cleanup.

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
- **Dynamic updating of bag entries, values, etc.** Live-refresh menu entries
  (bag contents, numeric values) instead of stale snapshots. Relates to W2
  (dynamic-list refresh) — note the deliberately-removed BAG_UPDATE auto-refresh
  (`SkuCore/Core.lua`) that previously caused re-anchoring problems; design a
  targeted refresh that does not re-anchor the menu.
- **Loading times.** Reduce addon load/reload time. Relates to W3 (load-time cost
  of the big Lua data tables: `routedata_global_wotlk.lua`, `SkuDB/assets`).
- **Nicer-looking popups.** Improve popup appearance.
- **Menu rework.** Overhaul the menus — the core of W2 (declarative menu schema +
  registry, decoupled from module structure).

## Resolved

- **v42 worktree was missing the gitignored runtime assets** — fixed by copying
  all 12,809 gitignored files (`SkuDB/assets/`, `routedata_global_wotlk.lua`,
  `audio/`, scattered binaries) from the v41 tree into `Sku-TBC-42\Sku\`
  (2026-06-25). The worktree is now runnable once the symlink points at it.
  Note: the large *external* audio companions (voice DB, beacons, ~790 MB) are
  separate installed addons and were not touched — see Workstream 5.
