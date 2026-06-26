# Sku 42 — Changelog

Changelog for the Sku 42 rework line, developed on the `sku42` branch in the
`Sku-TBC-42` worktree. This is the fundamentally-reworked successor to the
v41.x line (which continues independently on `main`).

The addon keeps the name **Sku** and the folder name **Sku** — v42 is a new
version, not a separate addon. It therefore shares the `SkuOptionsDB`
SavedVariables with v41 when run under the same account; never run v41 and v42
at the same time, and a WTF backup was taken before the rework began
(`C:\Users\fabia\Dev\WTF-backup-_anniversary_-preSku42-2026-06-25`).

Versioning: v42 starts at **42.00**. The in-game version is read from
`Sku/Sku.toc` (`## Version`) via `GetAddOnMetadata` — there is no hardcoded
version constant in Lua, so bumping the TOC is sufficient.

## Format

Newest entry on top. One bullet per change, grouped under a version heading.
Reference the refactor workstreams (W1 settings, W2 menu, W3 performance,
W4 modularization) from `REFACTOR-PLAN.md` where relevant.

## Unreleased (42.00 — in progress)

- **W2 Phase D — node removal centralized through `SkuMenu:Remove` (M-D1).**
  Enumerated every menu-node removal / `prev`-`next` write site. There is exactly ONE
  genuine node *removal*: the AH buy-prune in `SkuCore/auctionHouse.lua`
  (`AuctionPruneListAuction`), which hand-spliced `prev`/`next` and `table.remove`d the
  entry from `children`. Routed it through the central `SkuMenu:Remove(tEntry)`
  (behaviour-identical splice + remove); dropped the now-dead manual index loop;
  `tNeighbor` (cursor re-position) still captured before removal. Everything else that
  writes `prev`/`next` is NOT a removal and stays: `InjectMenuItems` (central insertion)
  and the text-filter re-link in `ApplyFilter` (rebuilds the whole filtered chain — a
  re-link, not a splice). This closes the "removal is an unguarded invariant" gap that
  caused the "arrow navigation skips onto a ghost entry" bug class. luaparser-clean;
  in-game test = an AH multi-buy where the last of a duplicate group is pruned.

- **W2 Phase B — all remaining module MenuBuilders converted to specs (M-B2).**
  In one batch (fan-out, one agent per file, strict behaviour-preservation rules,
  each luaparser-gated and diff-reviewed): SkuNav, SkuChat, SkuQuest, SkuCore, and
  SkuAuras `:MenuBuilder`, plus `SkuCore:GameOptionsMenuBuilder`, now express their
  TOP-LEVEL entries as `SkuMenu:Build` specs. Inner BuildChildren/OnAction closures
  were moved VERBATIM into spec `build`/`onAction` fields; order, names, count,
  conditions, and every flag are reproduced exactly. Counts: SkuCore 14 entries,
  SkuChat 5, SkuNav 4 (+ a dead `if false` "Daten" block left in place), SkuQuest 3,
  SkuAuras 1 (its "Options" left hand-built on purpose — see below), GameOptions
  built node-by-node inside its runtime loop.
  - **Compiler generalized first** (`submenu` + `action` kinds, and a passthrough of
    optional flags/handlers — filterable, dynamic, isSelect, isMultiselect,
    noStepUpAfterSelect, macrotext, secureMacro, tooltip→textFull, onAction, onEnter,
    onLeave, getCurrentValue, onUpdate, onKey) so any hand-built entry reproduces
    exactly.
  - **Critical fix:** `list`/`submenu` now assign `build` DIRECTLY as `BuildChildren`
    (not wrapped in a one-arg closure). The renderer invokes `self:BuildChildren(self)`
    = two args `(entry, entry)`; SkuCore has 7 entries whose build is a colon-method
    reference (`SkuCore.AuctionHouseMenuBuilder`, …) needing `aParentEntry` as its
    second positional — a one-arg wrapper would have passed it `nil` and broken those
    submenus. Direct assignment matches the original hand-assignment exactly.
  - **Fidelity notes:** the `settings` kind forces `filterable=true` when omitted, so
    a settings container that was NOT filterable (SkuAuras "Options", `filterable=nil`)
    is left hand-built rather than converted. SkuChat had an accidental BOM added by
    the edit — stripped back to match the original (no BOM). All files luaparser-clean;
    no live references to removed top-level locals. **One big in-game test pending**
    (navigate every module's menu + Game Options; behaviour must be unchanged).

- **W2 Phase B started — declarative node compiler + first conversion (M-B1).**
  Added `SkuMenu:Build(parent, specs)` / `BuildNode`: a flat list of node SPECS
  compiles into template nodes via the existing renderer, so a `MenuBuilder` can
  be expressed as data instead of repeated hand-written `InjectMenuItems` blocks.
  Two kinds so far (added only as conversions need them — no speculative kinds):
  `list` (dynamic container, `build=fn(entry)`, rebuilt each visit) and `settings`
  (named container populated from an AceConfig `options.args` + db subtable via the
  existing `IterateOptionsArgs`). toggle/enum/range are deliberately NOT separate
  kinds — they are the children `IterateOptionsArgs` already renders, so `settings`
  delegates to it (preserving their exact nav semantics by reuse). First real
  conversion: **SkuMob:MenuBuilder** is now a `SkuMenu:Build` spec (Target menu =
  `list`, Options = `settings`) — behaviour-identical (same entries, order,
  dynamic/filterable flags, same IterateOptionsArgs call). Both files
  luaparser-clean; in-game verified at the W2-A stage, M-B1 `/wdsku3` before/after
  pending. Next: convert more module menus (M-B2), adding `submenu`/`action`/`macro`
  kinds as each is first needed.

- **W2 Phase A — menu registry + layout decoupling (M-A1, M-A2; M-A3 mechanism).**
  New `Sku/SkuZOptions/SkuMenu.lua` (`ns.Menu`, global `SkuMenu`, TOC-loaded right
  after `SkuSettings.lua`). It makes the ROOT menu data-driven: a **registry** of
  module contributions (`RegisterModule(id, {label, build})`) plus a **layout**
  list (`rootLayout`) deciding what appears at root and in what order. The old
  hardcoded inline sequence in `SkuZOptions/Core.lua` (6 module entries + Game
  Options, ~46 lines) is replaced by one `SkuMenu:AssembleRoot(SkuOptions.Menu)`
  call. Behaviour-identical by construction — same 7 entries, same order, labels
  resolved at open time (incl. Game Options' locale-computed title), `dynamic` +
  `BuildChildren -> Module:MenuBuilder(entry)` reproduced, and one-at-a-time
  injection reproduces the original prev/next sibling chain. Also ships central
  `Insert`/`Remove` sibling-list helpers (Remove additive, for the later M-D
  removal-path cleanup). The Accessibility ("Menue 7") grouping stays inline and
  untouched. The toggle/enum/range "compiler" the plan sketched is deliberately
  NOT built here — that capability already exists as `IterateOptionsArgs`; a
  declarative archetype layer is deferred to M-B, shaped by the first real
  conversion (avoiding a speculative layer with no consumer, per W1's lesson).
  Both files luaparser-clean. **Decoupling proven by construction:** reordering
  the root is now a one-line edit to `rootLayout` with no module-code change.
  In-game `/wdsku3` before/after verification pending (open the menu, confirm the
  7 top entries appear in the same order and each descends into the same subtree).

- **W1 Phase B — SkuOptions migrated (B7); Phase B now fully complete.** The
  follow-up that closes out Phase B: the SkuZOptions module's OWN settings access
  (259 sites — Core 110, Options 121, SkuKeyBinds 25) moved off raw
  `SkuOptions.db.<scope>[MODULE_NAME]/["SkuOptions"]` onto `SkuSettings:Sub`.
  Scopes profile (248) + global (11), char 0; three lazy-init `or {}` idioms
  special-cased to bare `Sub` calls. No path-in-string labels here (unlike
  SkuCore), so no masking needed. The 71 cross-module reads inside these files
  (`["SkuCore"]`, `["SkuNav"]`, …) and the lone top-level `db.profile.testtext`
  stay raw by design. All three files luaparser-clean; 0 assign-to-call; clean
  248/248 one-for-one diff. In-game smoke test pending (exercise the options /
  voice-config / keybind menus). With B7, every module's own settings access —
  SkuOptions included — now goes through the facade; the only remaining raw
  `["SkuOptions"]` paths are intentional cross-module reads in OTHER modules.
  - Remaining W1 work: **Phase C** (C1 validation + remove raw-path fallback, C2
    publish the schema) is blocked on the flat per-key schema, which was
    deliberately deferred to W2 prep (no consumer until the menu generator). The
    natural next step is therefore **W2 Phase A** plumbing, authoring the flat
    schema lazily as W2's archetype conversions consume it.

- **W1 Phase B COMPLETE and verified in-game (2026-06-26).** All six modules
  (SkuMob, SkuQuest, SkuAuras, SkuChat, SkuNav, SkuCore — ~2700 own-key call
  sites) migrated onto `SkuSettings:Sub`. Exercised on v42: SkuChat (chat /
  channels), SkuNav (waypoints / routes / beacons), SkuCore (menu, auction house
  + filters, mail, vendor junk-sell / repair, equipment sets, scanning, combat) —
  **behaviour identical to before, zero regressions, no Lua errors captured.**
  Settings access for these modules now goes through the SkuSettings facade;
  cross-module `["SkuOptions"]` reads remain raw by design.
  - Remaining W1 work (next session): **Phase C** — turn on `Set` type validation
    permanently, remove the raw-path fallback, and publish the finalised schema as
    the input contract for Workstream 2. Also still open: migrating SkuOptions'
    OWN settings access (the SkuZOptions module) and authoring the flat per-key
    schema for the larger modules (deferred during Phase B).

- **W1 Phase B — SkuCore migrated (B6); Phase B (B1–B6) complete.** 1320 own-key
  settings accesses migrated across 31 files. SkuCore's files do NOT all share one
  namespace: many sub-features (`AuctionHouse`, `RangeCheck`, `TurnToUnit`,
  `Socketing`, `dungeonBrowser`, …) store settings under their OWN `MODULE_NAME`
  key, so each file was migrated with its own name; literal `["SkuCore"]` →
  `Sub("SkuCore", …)`. The migration script now masks string literals first,
  because some `dprint` labels spell out the db path verbatim and a naive swap
  injected quotes (the 2 remaining raw paths are inside such cosmetic labels). All
  7 special cases (ensure-exists + guard-init) handled; three scopes. Cross-module
  `["SkuOptions"]`/`["SkuNav"]`/`["SkuAuras"]` reads kept raw. neutralize-parse
  clean. In-game smoke test for B4–B6 pending (one batched cycle).

- **W1 Phase B — SkuNav migrated (B5).** 554 own-key settings accesses migrated
  across 7 files. Scopes profile + global; a global guard-init block and a global
  ensure-exists idiom special-cased to bare `Sub` calls. Cross-module
  `["SkuOptions"]` reads stay raw. neutralize-parse clean; in-game test batched
  with B4/B6.

- **W1 Phase B — SkuChat migrated (B4).** 287 own-key settings accesses migrated
  to `SkuSettings:Sub` (Core 187, Options 100). Scopes profile + global; one
  global ensure-exists idiom special-cased. Cross-module `["SkuOptions"]` reads
  stay raw. Verified via neutralize-parse (SkuChat/Core.lua has a pre-existing
  `"\]"` escape that trips luaparser, unrelated to this change). In-game test
  pending (batched with B5/B6).

- **Debug logging default changed for v42.** `Sku.debug` now defaults to
  `{ print = false, log = true }` (`Core.lua`) instead of both off. The
  `SkuDebugLog` ring captures breadcrumbs every session automatically (readable
  after a `/reload` without re-enabling), while chat `print` stays off (no TTS
  spam). `/skudebug` still overrides per session. Note: the project `CLAUDE.md`
  and `sku-logging-system` memory still say "both default OFF" — stale for v42.

- **W1 Phase B — SkuAuras migrated (B3).** 84 own-key settings accesses migrated
  to `SkuSettings:Sub` (Core 22, Options 56, sharing 4). SkuAuras spans three
  scopes — char (79), global (4), profile (1) — all handled by the existing
  scope-override arg (`Sub("SkuAuras")` / `…, nil, "char"` / `…, nil, "global"`).
  One char lazy-init idiom special-cased. Cross-module `["SkuCore"]` reads stay
  raw. luaparser-gated; behaviour-preserving; in-game smoke test pending.

- **W1 Phase B — SkuQuest migrated (B2).** All 111 of SkuQuest's own-key settings
  accesses migrated to `SkuSettings:Sub`. SkuQuest mixes scopes (75 profile + 36
  char), so `Sub` gained an optional third arg `aScopeOverride`: profile →
  `Sub("SkuQuest")`, char → `Sub("SkuQuest", nil, "char")` (a whole-table char
  access has no single key for the schema to resolve scope). Four char lazy-init
  idioms (`db.char[MODULE_NAME] = … or {}` and an `if not … then … = {} end`
  block) were special-cased — a blind swap would have created `Sub(…) = {}`
  (assign-to-call syntax error), and they are redundant since `Sub` auto-creates
  the section. Cross-module `["SkuNav"]`/`["SkuOptions"]` reads stay raw.
  luaparser-gated; behaviour-preserving; in-game smoke test pending. (Flat per-key
  schema authoring is deferred for the larger modules — see REFACTOR-PLAN.)

- **W1 Phase B — SkuMob migrated (B1).** All 43 of SkuMob's own-key settings
  accesses (27 in Core.lua, 16 in Options.lua) moved off raw
  `SkuOptions.db.profile[MODULE_NAME]/["SkuMob"]` onto `SkuSettings:Sub("SkuMob")`
  — a uniform token swap that is behaviour-identical for reads and writes (Sub
  returns the same live table), chosen over per-site Get/Set for SkuMob's
  combat-critical hot paths. The 35 cross-module `["SkuOptions"].softTargeting`
  reads stay raw (they migrate with SkuOptions). SkuMob's 9 keys are declared in
  the flat schema via `SkuSettings:Register` (all profile scope). luaparser-gated;
  behaviour-preserving by construction; in-game smoke test pending.

- **W1 Phase A started — `SkuSettings` facade added (A1 + A2).** New
  `SkuZOptions/SkuSettings.lua` (on `ns.Settings`, global alias `SkuSettings`),
  TOC-loaded early (after `SkuUtil.lua`). Provides a schema registry
  (`Register`) and `Get`/`Set`/`Sub` accessors over the existing single AceDB
  (`SkuOptions.db`): scope resolved from the schema, dotted-path walk,
  intermediate-table creation on `Set` (replacing the `x = x or {}` idiom),
  off-by-default type validation, and `dprint` warnings on unregistered keys.
  Purely additive — nothing calls it yet, so behaviour is unchanged. Next:
  author the schema from the eight `Module.defaults` tables (A3) and swap the
  hand-written `OnInitialize` defaults stitch for registry-driven assembly +
  char/global defaults (A4), verifying the persisted `SkuOptionsDB` is unchanged.
- **W1 Phase A — registry-driven defaults assembly (A3 + A4).** Added
  `SkuSettings:RegisterModuleDefaults(module, scope, tree)` + `:BuildDefaults()`.
  `SkuOptions:OnInitialize` now registers each module's whole `defaults` tree (by
  reference) and calls `BuildDefaults(defaults)` before the AceDB `:New`, instead
  of the eight inline `defaults.profile[X] = X.defaults` lines. Output is
  byte-identical (by-reference assembly is lossless — `SkuCore.defaults` has
  numeric keys added by load-time loops, so a flatten/rebuild was deliberately
  avoided). The `options.args[X]` AceConfig assignments stay inline. char/global
  defaults: mechanism ready, but population (and the flat per-key schema) is
  deferred to Phase B per module — enumerating ~1,236 char/global keys safely
  needs the same per-module pass that migrates call sites. luaparser-gated;
  behaviour-preserving by construction; in-game smoke test pending.

- Worktree `Sku-TBC-42` created on branch `sku42` from the v41.06 baseline
  (commit 5670b60); TOC bumped to 42.00.
- Refactor plan moved here as `REFACTOR-PLAN.md`; rework docs separated from the
  v41 tree under `Sku42-Rework-Docs/`.
- Copied the gitignored runtime assets (12,809 files, ~140 MB) into the worktree
  so v42 is runnable once the symlink points at it.
- Added **Workstream 5** to the plan (companion-addon / asset packaging) after
  auditing the external audio addons: ~790 MB across ~127,000 mp3 (beacons
  `SkuBeaconSoundsets` 99 MB + `SkuCustomBeacons*` 222 MB; voice
  `SkuAudioData_fast_de` 470 MB). Conclusion: do not merge audio into core; keep
  data-only companions, move glue code into Sku, rationalize the beacon split and
  voice-pack naming drift.
- Added **Workstream 6** (post-rework): build an LLM/documentation index of the
  whole addon, then agent-batched high-level (architectural) and low-level
  (per-file) cleanup, each producing a plain-text findings list gated by explicit
  approval before execution.
- **W4 Phase A (X-A2) started — `SkuUtil` extraction.** Added a new
  dependency-free `Sku/SkuUtil.lua` (global `SkuUtil`) loaded right after
  `Core.lua`, and moved the stateless `Unescape` string helper into it
  (`SkuUtil:Unescape`, byte-identical logic + the `escapes`/`escapesChat`
  tables). `SkuChat:Unescape` is kept as a thin delegating shim for safety;
  all 125 `SkuChat:Unescape` call sites across 10 files were repointed to
  `SkuUtil:Unescape`, and the `minimapScanner` `if SkuChat and SkuChat.Unescape`
  load-order guard was removed (SkuUtil always loads first). Behavior-preserving;
  collapses the largest *fake* cross-module cycle (SkuCore→SkuChat). luaparser
  syntax-gated; in-game smoke test **passed** (2026-06-26, v42 live via the
  symlink): no behaviour change — item tooltips, chat, and gossip/quest-giver
  windows spoken unchanged, and `/wdeval SkuUtil:Unescape(...)` resolved and
  stripped link markup (confirming `SkuUtil` loads and works). The two
  private-local `Unescape` duplicates were also collapsed onto `SkuUtil`:
  `LocalMenu` (direct swap) and `gameWorldObjects` (via a `tostring(...)` wrapper
  that preserves its nil→`"nil"` contract the downstream `~= "nil"` checks rely
  on). `SkuChat:Unescape` and `SkuUtil:Unescape` are now the only `Unescape`
  definitions besides the vendored `SkuVoice-1.0` lib-local. (X-A2 complete.)
- **W4 Phase A (X-A1) — addon-private namespace adopted.** `Core.lua` now
  captures WoW's second addon vararg (the per-addon shared table it previously
  discarded) as `ns` and exposes it as `Sku.ns`. `SkuUtil` becomes the first
  resident — it lives on `ns.Util` with the global `SkuUtil` kept as a thin
  published alias (no call-site churn), establishing the pattern for future
  internal-only helpers. The published API (`Sku` + module tables) intentionally
  stays global; bulk `_G`→`ns` migration is deferred to W4 Phases C/D. luaparser
  syntax-gated; behavior-preserving. **W4 Phase A is now complete (X-A1 + X-A2).**
