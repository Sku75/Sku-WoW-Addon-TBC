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

- **Auto-run deactivates half the addon** ("autolaufen deaktiviert das halbe
  Addon").
  - Symptom: turning on auto-run / auto-walk disables a large part of Sku's
    functionality.
  - Repro: TBD (enable auto-run, observe which features go silent).
  - Suspected area: movement state handling / `SkuCore.isMoving` and the
    open-menu-after-moving logic; possibly an input/keybind capture that swallows
    other handlers. Ties into W4 (shared movement state).
  - Status: open.
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
