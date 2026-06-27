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

- **W4 Phase E — E1b (hard-3), part 1 of 3: AuctionHouse extracted.** The 49
  `function SkuCore:Auction*`/`Strategy*`/`AUCTION_*` methods now live on the
  `AuctionHouse` module table (`function AuctionHouse:Method`); the published
  handle `SkuCore.AuctionHouse` IS that table, so external callers use
  `SkuCore.AuctionHouse:Method`. Done with a reviewable codemod
  (`_e1b_codemod.py`: rename in-file `SkuCore`→`AuctionHouse`, cross-file
  `SkuCore`→`SkuCore.AuctionHouse`, for the file's own method names only;
  ConfirmButtonShow excluded). 169 in-file + 8 cross-file rewrites across 6 files.
  - **Safe by construction:** verified (`_e1b_analyze.py`) that NOT ONE AuctionHouse
    method uses its own `self` to touch SkuCore — every `self` is an inner-closure
    frame/event-handler param or a comment — so relocating the method's table cannot
    change behaviour regardless of how each is called (dispatcher/AceEvent self is
    unchanged; menu-builder self stays the entry).
  - **Event ownership moved (Mail pattern):** module gained the `AceEvent-3.0` mixin;
    the 5 `AUCTION_*` events now register/unregister on `AuctionHouse` (was
    `SkuCore:RegisterEvent`), matching the handlers that moved to the module. The
    hardware-event-gated `PlaceAuctionBid` secure-buy path + its teardown are
    byte-for-byte unchanged (only the table they hang on changed).
  - **`ConfirmButtonShow` deliberately KEPT on `SkuCore`** — it is a generic confirm-
    dialog helper called by 4 OTHER modules (equipmentSets, LocalMenu, SkuMob,
    SkuZOptions), not an AH feature method; moving it would invent fake coupling.
    It is the one remaining `function SkuCore:` def in auctionHouse.lua (a shared
    helper to relocate in E2, analogous to E1's forwarder-shim exceptions).
  - **Feature STATE left on `SkuCore.<field>`** (QueryData/AuctionScan/StratBuy/…,
    incl. the cross-module-read `SkuCore.AuctionHouseOpen`): the methods reference it
    explicitly as globals so it keeps working untouched, and moving the scattered,
    partly cross-module state belongs to the state-service pass (category C / step 5),
    not this method-extraction. Documented as an intentional E1b scope boundary.
  - All 6 changed files luaparser-clean (SkuChat/Core.lua's failure is the PRE-EXISTING
    `"\]"` escape at L2111 in ShortenChannelName — baseline and current fail at the
    identical point, my edits at L2467/2560 add nothing). **In-game AH test pending**
    (bundled with the aq/aqCombat tests at the end of E1b).

- **W4 Phase E — E1: 20 features extracted off the SkuCore god-table.** Sequential
  per-feature namespace extraction (one agent at a time to avoid shared caller-file
  conflicts): every feature's `function SkuCore:X` methods + `SkuCore.<field>` state
  moved onto its own module table, all callers repointed via the published handle
  `SkuCore.<Feature>`. Features: Macro, DamageMeter, DialogKey, Socketing, GameOptions,
  Friends, UIErrors, VisualAids, DungeonBrowser, TurnToUnit, MinimapScanner,
  GameWorldObjects, SkuFocus, DialTargeting, AtlasLootIntegration, RangeCheck (plus
  DualSpecProbe/AudioDevice/UpdateCheck/EquipmentSets which were already clean). Result:
  the SkuCore method-table dropped from ~352 to **237** `function SkuCore:` defs; the 20
  extracted features now contribute ~0 (only 2 intentional forwarder shims remain). All
  22 changed files luaparser-clean; **verified in-game — all gates passed, behaviour
  unchanged, error log clean.**
  - Notable fixes the agents caught: a missing `SkuCore.UIErrors` published handle + a
    `UNIT_SPELLCAST_INTERRUPTED` double-definition collision (core stub vs UIErrors
    handler — dispatcher callback repointed to the handle); and a latent TurnToUnit bug
    where `SkuCore.TurnToUnit` (handle) and the state table were two separate tables
    (now unified onto the module).
  - Patterns established: AceEvent-3.0 mixin added to modules that owned WoW events
    (Friends, UIErrors, GameWorldObjects, AtlasLootIntegration) so they register/
    unregister on their own table; AceConsole-3.0 mixin for MinimapScanner's chat
    commands; **forwarder shims** (`function SkuCore:X() return Module:X() end`) for the
    two keybinds whose dispatch (`_G[object][func]`) only resolves single-level globals
    (VisualAids next-combat-enemy, AtlasLoot keybind); live macrotext `/run` strings are
    real call sites and were repointed (Socketing, DungeonBrowser).
  - **Remaining (W4-E): the hard-3** — AuctionHouse (50), aq (26), aqCombat (23) still
    define ~99 methods on the SkuCore table; extract next with extra care (combat
    hot-path, AH hardware-event buy + secure teardown, the SkuAuras coupling). Then E2
    (assess what legitimately stays core: Core.lua manager + LocalMenu Tier-1 +
    voiceOutput) and E3 (record final coupling).

- **W4 Phase E — E0 pilot: Mail namespace extraction.** First feature moved OFF the
  shared `SkuCore` god-table onto its own module namespace: 12 `SkuCore:Mail*` methods
  → `Mail:` (module table), the `Mail` module gained the AceEvent-3.0 mixin (events
  registered/unregistered on `Mail` itself), and the 7 external callers in
  `SkuCore/Options.lua` were repointed to the published handle `SkuCore.Mail:`. No
  feature state to move (already file-upvalues). Behaviour byte-identical; both files
  luaparser-clean; verified in-game (mailbox read + send work, error log clean). This
  proves the W4-E recipe. Gotchas captured for the mass rollout: always pass the
  explicit AceEvent handler-name; auto-detect duplicate `function SkuCore:X` defs;
  grep each method tree-wide incl. dynamic `SkuCore[...]` dispatch; flag `SkuCore.<field>`
  state that crosses module boundaries; AceEvent dispatch order is not guaranteed
  (watch combat handlers in aq).

- **W4 Phase D — X-D3 Rework B-step-2 (5 standalone addons made toggleable).**
  Extended the toggle framework in `SkuCore/ModuleManager.lua` to handle TOP-LEVEL
  AceAddons as well as SkuCore submodules: `RegisterToggleableAddon` + a
  `ResolveToggleObject` helper that resolves either `SkuCore:GetModule` (submodule)
  or `LibStub("AceAddon-3.0"):GetAddon` (top-level addon); `SetModuleEnabled` /
  `ApplyModuleEnabledStates` updated to use it (with a Disable-if-already-enabled
  fallback for addons that loaded before SkuCore, e.g. SkuChat). SkuChat, SkuNav,
  SkuQuest, SkuMob, SkuAuras are registered centrally (they can't all self-register —
  some load before SkuCore). Then each got a REAL OnDisable teardown + re-armable
  OnEnable (event registration moved OnInitialize→OnEnable; OnDisable does
  UnregisterAllEvents + stops OnUpdate frames + clears SetOverrideBindings + hides UI;
  hooksecurefunc bodies IsEnabled-guarded; SkuAuras rebuilds its PEW-built attribute
  data on mid-session enable). All cross-addon QUERY methods stay callable when
  disabled (SkuNav.Geo etc.) — disabling only disarms lifecycle. All 6 files
  luaparser-clean. Default ON, so default behaviour unchanged. In-game smoke pending
  (bundled with the W4-E pilot test).
  - **Architecture decision recorded:** adopt a UNIFIED module model (every feature a
    module with its OWN namespace, a lean SkuCore as lifecycle manager/registry,
    cross-module comms via SkuState/SkuNav.Geo/SkuDispatcher — never reaching into
    another feature's table). SkuDispatcher stays (comms plane, distinct from the
    lifecycle plane) and should be used MORE. See REFACTOR-PLAN W4 Phase E.

- **W4 Phase D — X-D3 Rework B-step-1 (AuctionHouse, aq, aqCombat promoted).**
  The three higher-risk SkuCore features are now runtime-toggleable AceAddon
  submodules (same behaviour-safe recipe as Rework A). **AuctionHouse** OnDisable does
  full teardown: stops the SkuCoreSecureTabButtonAuctions watchdog ticker, unregisters
  the 5 AUCTION_* events, runs AuctionSecureBuyTeardown (clears the Enter-key buy
  override bindings, cancels the safety timer); the hardware-event PlaceAuctionBid path
  is byte-for-byte untouched. **aq** (health/power) + **aqCombat** (combat/threat) with
  the SkuAuras coupling made safe: SkuCore.Monitor.UnitNumbersIndexedRaid is built
  unconditionally (file scope + Aq:OnInitialize) and never nilled, so disabling aq can't
  break SkuAuras; aq's 5 RoleCheckerGetUnitRole calls are guarded so a future-disabled
  SkuAuras can't break aq; and the internal aqCombatOnLogin call was removed from
  AqOnLogin (aqCombat self-enables in TOC order — no double-init). Core.lua reconciled:
  6 calls removed (Aq/aqCombat/AuctionHouse OnInitialize + OnLogin); the SkuCore feature
  init sequence is now empty except VoiceOutput (Tier-1). All 4 files luaparser-clean.
  **Verified in-game (2026-06-27): works as intended, SkuErrorLog clean of Lua errors**
  (only intentional auction/dungeon diagnostic breadcrumbs + the pre-existing benign
  addon_action_blocked taint class). Added `_readerrlog.py` (screen-reader-friendly live
  SkuErrorLog reader). Remaining for Rework B-step-2: top-level-addon toggle framework +
  OnDisable for SkuMob/SkuNav/SkuQuest/SkuChat/SkuAuras + the SkuAuras side of the aq
  coupling.

- **W4 Phase D — X-D2 modularization map + X-D3 Rework A (21 features promoted).**
  Produced the modularization map from a 33-agent feature inventory and recorded the
  two-tier classification + risk-ranked checklist in `REFACTOR-PLAN.md` (X-D2). Then
  executed **Rework A**: 21 SkuCore features promoted to runtime-toggleable AceAddon
  submodules in one fan-out batch (one agent per feature file) — EquipmentSets,
  Macro, DamageMeter, DualSpecProbe, AudioDevice, DialogKey, Mail, UpdateCheck,
  Socketing, Friends, TurnToUnit, VisualAids, UIErrors, DungeonBrowser, SkuFocus,
  DialTargeting, MinimapScanner, GameWorldObjects, RangeCheck, AtlasLootIntegration,
  GameOptions. Behaviour-safe recipe: existing `SkuCore:Method` definitions and
  `SkuCore.field` state stay in place; only the lifecycle moves into OnEnable (arm) /
  OnDisable (real teardown), with `IsEnabled` no-op guards on public entry points so
  a disabled feature is safe without editing external callers. `Core.lua` reconciled
  centrally: 18 dead `*OnInitialize`/`*OnLogin`/`*OnEnable` calls removed; the
  Aq/aqCombat/AuctionHouse/VoiceOutput calls kept (Rework B / Tier-1). Each feature
  self-registers via `SkuCore:RegisterToggleableModule`, so the Features menu now
  lists all 22 (incl. JunkAndRepair). Uniform behaviour delta: features re-arm on
  every /reload instead of only initial login (proven harmless by the pilot). All
  files luaparser-clean. **Verified in-game (2026-06-27): all 3 test gates passed**
  — clean load (no Lua errors), Features-menu toggle on/off + persistence across
  /reload, and secure/shared-state spot-checks (SkuFocus, DialTargeting, RangeCheck,
  MinimapScanner+GameWorldObjects, Mail, UIErrors, DialogKey). Decisions this pass:
  1a (Rework A first, one test), 2a (keep the 5 standalone addons top-level, toggle
  in place — not re-parented), 3a (real OnDisable + guards with the promotion), 4
  (LocalMenu stays Tier-1/non-toggleable — toggling the menu would lock the user out;
  UIErrors + UpdateCheck are toggleable).

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
