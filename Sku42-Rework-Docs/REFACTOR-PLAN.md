# Sku Refactor Plan

Living plan for modernizing Sku into a more flexible, maintainable, and
performant addon **without changing its behavior for the end user**. This is the
plan for the **Sku 42** rework, developed on the `sku42` branch in the
`Sku-TBC-42` worktree (the v41.x line continues on `main`). A roadmap to execute
incrementally — not a one-shot rewrite.

## How to use this document

- Six workstreams, tackled **one at a time** so we never juggle two
  half-migrated subsystems:
  1. Settings access layer  — fully specified below (ready to execute).
  2. Menu schema + registry  — investigated, design drafted (execute after W1).
  3. Performance profiling pass — investigated, candidates mapped (measure first).
  4. Modularization / boundaries — investigated; break the SkuCore god-object
     and the dependency cycles (execute after W1 + W2). See "Sequencing".
  5. Companion addons / asset packaging — investigated; rationalize the external
     audio addons (voice DB + beacons). Strategy is an early input to W1/W4.
  6. Documentation index + cleanup — POST-REWORK: build an LLM/doc index, then
     agent-batched high-level then low-level cleanup, each gated by your approval.
- Each workstream is independently shippable and behavior-preserving.
- Status legend used per task: `[ ]` not started, `[~]` in progress,
  `[x]` done, `[!]` blocked/needs decision.

## Guiding principles & hard constraints

- **Behavior must stay identical.** Sku is a daily-driver accessibility tool.
  No user-visible change in what is spoken, no change to keybinds, no change to
  the persisted `SkuOptionsDB` shape unless explicitly planned and migrated.
- **Screen-reader-only verification.** Every checkpoint must be verifiable
  without sighted inspection: luaparser syntax check, `/skudebug` ring traces,
  WVDebug captures (`/wdsku`, `/wdeval`, `/wdwatchsku`), deterministic
  before/after dumps of known values. No "look at the screen" steps.
- **Incremental & reversible.** Migrate module-by-module. Commit a checkpoint
  before each risky step. Old and new code paths coexist during a migration so
  a half-done module still runs.
- **Target client:** TBC Anniversary, Interface 11508. Don't assume retail-only
  APIs exist; verify on this client before relying on them.
- **Keep the contribution-back path clean.** Code changes live under `Sku/`.
  This planning doc and the rework docs live in `Sku42-Rework-Docs/` (outside
  `Sku/`) so they never enter the addon or an upstream patch.
- **Libraries stay on Ace3.** See "Library assessment" at the end: swapping the
  framework is high-cost / low-reward. The wins here are architectural, on top
  of Ace3, not a library change.

---

# Workstream 1 — Settings access layer  (READY TO EXECUTE)

## 1.1 Current state (measured)

- One SavedVariable, `SkuOptionsDB`, wrapped by AceDB-3.0 at
  `Sku/SkuZOptions/Core.lua:3525`:
  `SkuOptions.db = LibStub("AceDB-3.0"):New("SkuOptionsDB", defaults, true)`.
- Defaults are defined **per module** as `Module.defaults` (e.g.
  `Sku/SkuCore/Options.lua:759` `SkuCore.defaults = {...}`) and then stitched
  together by hand in `SkuOptions:OnInitialize()`
  (`Sku/SkuZOptions/Core.lua:3483-3515`) as
  `defaults.profile["SkuCore"] = SkuCore.defaults`, one `if Module then` block
  per module.
- Access is raw deep-path, everywhere. Measured occurrences (excluding `Libs/`):
  - `SkuOptions.db.profile[...]` — 1,429 occurrences
  - `SkuOptions.db.char[...]`   — 1,153 occurrences
  - `SkuOptions.db.global[...]` — 83 occurrences
  - Spread across **40 source files**.
- **No getter/setter layer exists** — confirmed by search; every read and write
  is an inline deep path like
  `SkuOptions.db.profile[MODULE_NAME].ressourceScanning.gasCollector[x]`.

## 1.2 Problems this causes

- **No single source of truth for the schema.** Defaults are scattered across
  the eight `Options.lua` files; some state is never in any defaults table and
  is initialized lazily at read time (`x = x or {}`).
- **`char` and `global` scopes have no declared defaults at all.** Only
  `defaults.profile` is registered (`Core.lua:3486-3514`); the 1,153 `db.char`
  reads and 83 `db.global` reads rely entirely on ad-hoc lazy init. This is the
  single biggest correctness smell in settings.
- **No encapsulation.** Renaming or restructuring any key means hand-editing
  every one of ~2,665 call sites; miss one and it silently desyncs.
- **profile vs char vs global is used inconsistently**, sometimes within one
  module, with no documented rule for which scope a setting belongs to.
- **Settings double as an implicit message bus** between modules (modules sync
  by reading each other's keys), so the schema is load-bearing coupling.

## 1.3 Target design

A thin facade over AceDB plus a **central schema registry**. The schema is the
keystone: it is the single source of truth for every setting's scope, default,
type, and (optionally) human label — and it is what Workstream 2 will later
read to auto-generate menu entries.

New module: `Sku/SkuZOptions/SkuSettings.lua` (loaded right after
`SkuZOptions/Core.lua` in the TOC). Global `SkuSettings` to match the existing
naming convention (a private namespace is a separate, later concern tracked in
Workstream 2's notes).

### Schema registry

Each module registers its settings once, declaratively:

```lua
SkuSettings:Register("SkuCore", {
  ["turnToUnit.speed"]              = { scope = "profile", default = 6,     type = "number" },
  ["turnToUnit.soundOnSuccess"]     = { scope = "profile", default = "sound-waterdrop5", type = "string" },
  ["readAllTooltips"]               = { scope = "profile", default = false, type = "boolean" },
  ["AuctionCurrentFilter.LevelMin"] = { scope = "char",    default = 1,     type = "number" },
  -- ...
})
```

- `scope` resolves profile / char / global so callers never name a scope again
  (kills the profile-vs-char confusion).
- The registry builds the AceDB `defaults` table for **all three scopes**, fixing
  the missing char/global defaults.
- `type` enables optional validation in `Set` (off by default, on under
  `/skudebug` to catch bad writes during migration).

### Accessor API

```lua
local v = SkuSettings:Get("SkuCore", "turnToUnit.speed")      -- read
SkuSettings:Set("SkuCore", "turnToUnit.speed", 8)             -- write
SkuSettings:Sub("SkuCore", "AuctionCurrentFilter")            -- returns the live subtable
                                                              -- (for hot loops / bulk access)
```

- `Get`/`Set` resolve scope from the schema, walk the dotted path, and (for
  `Set`) create intermediate tables as needed — replacing the `or {}` idiom.
- `Sub` returns the live table reference for code that must mutate many keys in
  a tight loop (e.g. scanners); this keeps a fast path so the layer never
  becomes a performance regression.
- Unknown keys: in debug mode, log a `dprint` warning (catches typos and
  un-migrated paths); in normal mode, fall back gracefully to the raw path so a
  missed key never breaks the user.

## 1.4 Migration strategy (incremental, non-breaking)

The layer wraps the **same** AceDB tables, so old raw paths and new accessor
calls read/write the identical storage. That lets us migrate one module at a
time with both styles coexisting.

- **Phase A — Introduce, don't migrate (lowest risk, no call-site edits).**
  - Add `SkuSettings.lua` with the registry + Get/Set/Sub.
  - Replace the eight hand-written `defaults.profile[X] = X.defaults` blocks in
    `Core.lua:3483-3515` with registry-driven assembly, and **add char/global
    defaults** derived from the schema. Net persisted shape unchanged.
  - Verify the persisted `SkuOptionsDB` is byte-identical before/after (see
    1.6). Ship this alone first.

- **Phase B — Migrate call sites, module by module, smallest first.**
  - Suggested order (low risk → high): SkuMob, SkuQuest, SkuAuras, SkuChat,
    SkuNav, then SkuCore last (it is the biggest, ~16 files).
  - Per module: convert raw deep paths to `Get`/`Set`/`Sub`. A regex codemod can
    assist (`SkuOptions.db.profile["X"].a.b` → `SkuSettings:Get("X","a.b")`),
    but reads vs writes and `or {}` init differ, so every change gets a human
    review + luaparser syntax check + in-game smoke test before commit.
  - Keep the raw-path fallback active so a not-yet-migrated key still works.

- **Phase C — Lock it down.**
  - Once all modules are migrated, turn on schema validation in `Set`
    permanently (reject/clamp out-of-type writes, log via `dprint`).
  - Remove the raw-path fallback; unknown key becomes a hard `dprint` error in
    debug builds.
  - The completed schema is then handed to Workstream 2 as the menu-generation
    source of truth.

## 1.5 Risks & watch-outs

- **AceDB strips default-equal values on logout.** Introducing defaults for
  `char`/`global` keys whose stored value equals the new default will cause
  AceDB to drop them from the saved file. That is correct/desired, but means a
  raw byte-diff of `SkuOptionsDB` will differ after a logout — compare
  *effective values*, not file bytes, past Phase A.
- **Lazy `or {}` sites that build structure on read.** Some code relies on the
  side effect of creating a subtable. `Set`/`Sub` must replicate that creation
  so behavior is preserved.
- **Hot paths.** Scanners (minimapScanner, gameWorldObjects, aq/aqCombat) read
  settings every tick. Use `Sub` to grab the subtable once, not `Get` per key
  per tick, to avoid added overhead. This overlaps with Workstream 3.
- **Profile switching.** AceDB fires `OnProfileChanged`; any cached `Sub`
  references must be re-fetched. The layer should invalidate caches on that
  callback (Sku already registers it at `Core.lua:3532`).

## 1.6 Verification (screen-reader-friendly)

- **Syntax gate:** after each file,
  `py -3 -c "from luaparser import ast; ast.parse(open('<file>', encoding='utf-8-sig').read()); print('OK')"`.
- **Before/after value dump:** pick ~15 representative keys across scopes; dump
  via `/wdeval` (WVDebug) pre- and post-migration and diff the printed values —
  must be identical.
- **Phase A storage check:** `/reload`, then compare the persisted
  `SkuOptionsDB` table in SavedVariables before vs after the defaults-assembly
  change (parse with `py -3`, brace-depth method per CLAUDE.md). Expect no
  change in Phase A.
- **Live behavior:** `/skudebug log on`, exercise the migrated module's menu
  (`/wdsku`), confirm reads/writes land via the ring trace; `/wdwatchsku` to
  confirm spoken output is unchanged.
- **Regression smoke:** one scripted pass per migrated module that sets a known
  value through the menu, `/reload`, reads it back.

## 1.7 Task checklist

- [x] A1. Add `Sku/SkuZOptions/SkuSettings.lua`; register it in `Sku.toc`.
  - Created at the planned path `SkuZOptions/SkuSettings.lua`, but TOC-loaded
    **early** (right after `SkuUtil.lua`, before all feature modules) rather than
    after `SkuZOptions/Core.lua` as originally sketched: the registry must exist
    before modules register their schema at load time, and the facade reads
    `SkuOptions.db` lazily (only at accessor call-time, always post-init), so
    early loading is safe. Lives on `ns.Settings` with a global `SkuSettings`
    alias (mirrors SkuUtil).
- [x] A2. Implement registry (`Register`) + `Get`/`Set`/`Sub` + dotted-path walk + lazy-create on `Set`.
  - `schema[module][dottedKey] = {scope, default, type}`. `Get` resolves scope
    from the schema, walks the dotted path, falls back to the schema default;
    `Set` creates intermediate tables (replaces `x = x or {}`) with optional
    off-by-default type validation; `Sub` returns the live subtable for hot
    loops. Unregistered keys `dprint`-warn in debug. Purely additive — no call
    site uses it yet, so behaviour is unchanged (Phase A "introduce, don't migrate").
- [x] A3. Extract the eight `Module.defaults` tables into the registry.
  - Registered each module's whole defaults **tree** (by reference) via
    `SkuSettings:RegisterModuleDefaults(M, "profile", M.defaults)` rather than
    hand-flattening into per-key schema entries. Reason: `SkuCore.defaults` is
    post-processed at load (loops add **numeric** keys like
    `ressourceScanning.miningNodes[1..N]`), so a flatten→rebuild to dotted string
    keys would corrupt it. By-reference is lossless for any contents.
  - The flat per-key `schema` (dotted keys for `Get`/`Set` scope + W2 menu gen)
    is therefore NOT mass-authored here; it is authored per module during Phase B
    as call sites migrate (lower risk, natural place to learn each key's default).
- [x] A4. Replace `Core.lua:3483-3515` hand-stitch with registry-driven defaults assembly.
  - The eight `defaults.profile[X] = X.defaults` lines are replaced by
    `RegisterModuleDefaults` + a single `SkuSettings:BuildDefaults(defaults)`
    before the AceDB `:New`. Output is byte-identical (same tables by reference);
    the `options.args[X] = X.options` AceConfig lines stay inline.
  - char/global defaults: the **mechanism** is in place (`RegisterModuleDefaults`
    accepts any scope; `BuildDefaults` only creates a scope subtable when it has
    registered defaults, so char/global stay absent = identical to today).
    POPULATING char/global defaults is deferred to Phase B per module — safely
    enumerating the ~1,236 char/global keys + their correct defaults requires the
    same per-module pass that migrates the call sites; doing it blind now would
    risk the "behaviour identical" constraint.
- [x] A5. Phase A verification: persisted `SkuOptionsDB` unchanged; checkpoint shipped.
  - luaparser-gated; in-game verified (load clean, `moduleDefaults` identity true,
    settings unchanged).
- [x] B1..Bn. Migrate call sites per module (SkuMob → SkuQuest → SkuAuras → SkuChat → SkuNav → SkuCore). **DONE + verified in-game (2026-06-26): all six modules exercised on v42, behaviour identical, zero regressions, no Lua errors captured.** ~2700 own-key call sites moved onto `SkuSettings:Sub` (scope-explicit where needed); cross-module reads (esp. `["SkuOptions"]`) intentionally left raw.
  - [x] **B1 SkuMob.** All of SkuMob's own-key access (43 sites: 27 in Core.lua,
    16 in Options.lua) moved off raw `SkuOptions.db.profile[MODULE_NAME]/["SkuMob"]`
    onto `SkuSettings:Sub("SkuMob")`. Chose the `Sub`-swap (uniform token
    replacement) over per-site `Get`/`Set` because `Sub` returns the *same live
    table*, so the swap is behaviour-identical for reads AND writes with no
    read/write ambiguity — ideal for SkuMob's combat-critical hot paths. The
    cross-module `["SkuOptions"].softTargeting` reads (35) were deliberately left
    raw — they belong to SkuOptions and migrate when it does. Flat schema for
    SkuMob's 9 keys authored via `SkuSettings:Register` (all profile scope) as the
    W2 source of truth. luaparser-gated.
  - [x] **B2 SkuQuest.** All 111 own-key sites (Core + Options) migrated to
    `Sub`. SkuQuest *mixes scopes* (75 profile + 36 char), so `SkuSettings:Sub`
    gained an optional **third arg `aScopeOverride`**: profile → `Sub("SkuQuest")`
    (schema/default scope), char → `Sub("SkuQuest", nil, "char")` (explicit —
    a whole-table char access has no single key for the schema to resolve scope
    from). Four char lazy-init idioms (`db.char[MODULE_NAME] = … or {}` ×3 and an
    `if not db.char[MODULE_NAME] then … = {} end` block) were special-cased: a
    blind swap would have produced `Sub(…) = {}` (assign-to-call syntax error), and
    they are redundant anyway since `Sub` auto-creates the section — replaced with
    a bare `Sub("SkuQuest", nil, "char")` call. Cross-module `["SkuNav"]` (68) and
    `["SkuOptions"]` (4) left raw. luaparser-gated; 0 `Sub(…)=` syntax errors.
  - [x] **B3 SkuAuras.** 84 own-key sites migrated to `Sub` (Core 22, Options 56,
    sharing 4; data/defaultAuras untouched). SkuAuras spans *three* scopes — char
    (79), global (4), profile (1) — all handled by the existing `aScopeOverride`:
    `Sub("SkuAuras")` / `Sub("SkuAuras", nil, "char")` / `Sub("SkuAuras", nil,
    "global")`. One char lazy-init idiom (`Core.lua:235`) special-cased as before.
    Cross-module `["SkuCore"]` (2) left raw. luaparser-gated; 0 `Sub(…)=` errors.
  - [x] **B4 SkuChat.** 287 own-key sites migrated (Core 187, Options 100).
    Scopes: profile + global. One global `or {}` ensure-exists idiom → bare `Sub`.
    Cross-module `["SkuOptions"]` (7) left raw. SkuChat/Core.lua trips luaparser
    on a PRE-EXISTING `"\]"` escape in `ShortenChannelName` (unrelated) — verified
    via neutralize-parse that baseline and current both parse, so no new errors.
  - [x] **B5 SkuNav.** 554 own-key sites migrated across 7 files. Scopes profile
    + global. Two special cases: a global guard-init block (`if not … then … = {}
    end`) → bare `Sub`, and a global ensure-exists `or {}` → bare `Sub`.
    Cross-module `["SkuOptions"]` (42) left raw. neutralize-parse clean.
  - [x] **B6 SkuCore.** 1320 own-key sites migrated across 31 files. Two findings
    made this the hardest: (1) SkuCore files do NOT all use `MODULE_NAME =
    "SkuCore"` — many sub-features store settings under their OWN key
    (`"AuctionHouse"`, `"RangeCheck"`, `"TurnToUnit"`, `"Socketing"`,
    `"dungeonBrowser"`, …; only 23/31 use `"SkuCore"`), so each file was migrated
    with ITS OWN module name (`db.X[MODULE_NAME]` → `Sub("<that file's name>", …)`);
    literal `["SkuCore"]` everywhere → `Sub("SkuCore", …)`. (2) Several `dprint`
    labels are STRING literals that spell out the db path — a byte-swap injected
    quotes and broke them, so the script now masks string literals before swapping
    (the 2 remaining raw paths are inside such labels — cosmetic). All 7 special
    cases (5 ensure-exists `or {}`, 2 guard-init `if not…then…={}` blocks) handled.
    Scopes char + profile + global. Cross-module reads kept raw: `["SkuOptions"]`
    99, `["SkuNav"]` 4, `["SkuAuras"]` 2. neutralize-parse clean; no assign-to-call.
  - [x] **B7 SkuOptions (SkuZOptions module).** The follow-up that finishes Phase B:
    259 own-key sites migrated across `SkuZOptions/Core.lua` (110), `Options.lua`
    (121), `SkuKeyBinds.lua` (25). All under module name `"SkuOptions"`
    (`[MODULE_NAME]` and `["SkuOptions"]` both resolve there, incl. SkuKeyBinds whose
    `MODULE_NAME="SkuOptions"`/`MODULE_PART="SkuKeyBinds"`). Scopes profile (248) +
    global (11), char 0 → `Sub("SkuOptions")` / `Sub("SkuOptions", nil, "global")`.
    Three global/profile lazy-init `or {}` idioms (Core 143/3907, SkuKeyBinds 243)
    special-cased to bare `Sub` calls. No string-literal path-labels here (unlike
    SkuCore), so no masking needed. Cross-module reads kept raw (71: `["SkuCore"]`
    41, `["SkuNav"]`/`["SkuChat"]` 11 each, `["SkuAuras"]` 6, `["SkuMob"]`/
    `["SkuAdventureGuide"]` 1 each) and the lone top-level `db.profile.testtext` left
    raw. luaparser-gated (all 3 parse); 0 assign-to-call; in-game smoke test pending.
  - **Phase B now fully complete (B1–B7).** Every module's own settings access —
    including SkuOptions itself — goes through `SkuSettings:Sub`. The remaining
    raw `["SkuOptions"]` paths are intentional **cross-module** reads inside OTHER
    modules (they read SkuOptions' table; `Sub` returns the same live storage, so
    they are behaviour-identical and need no change).
  - **Note on the flat schema:** authored for SkuMob (small/flat) as a demo, but
    DEFERRED for the larger modules (SkuQuest onward). The `Sub`-swap migration
    doesn't consume the flat per-key schema (scope is default/explicit), and
    hand-flattening large nested `defaults` trees (+ enumerating char/global
    defaults) is error-prone with no current consumer. Flat-schema authoring +
    char/global default population becomes a focused later pass (W2 prep).
- [ ] C1. Enable `Set` validation permanently; remove raw-path fallback.
- [ ] C2. Publish the finalized schema as the input contract for Workstream 2.

---

# Workstream 2 — Menu schema + registry  (INVESTIGATED — design drafted)

Headline conclusion: the biggest win here is **decoupling the user-facing menu
organization from the code/module structure.** Today the menu tree *is* the
module list (see 2.3), so re-organizing menus by purpose instead of by module is
brittle and expensive; after this workstream it becomes a data edit. The
boilerplate reduction is real but secondary.

Do not start coding until Workstream 1 is at least through Phase B; the menu
generator should consume the settings schema, so the two must not be in flight
together. The investigation below is complete enough to design against.

## 2.1 Current state (measured)

- All entries derive from one template, `SkuGenericMenuItem`
  (`Sku/SkuZOptions/templates.lua:62-470`). The full field contract:
  - **Data fields:** `name` (label, also the navigation match key), `type`
    (MENU_MENU=1/dropdown constants — set once, effectively vestigial after
    init), `parent`, `children`, `prev`, `next`, `isSelect` (terminal decision
    node), `isMultiselect`, `selectTarget` (node that collects the chosen value;
    defaults to self), `dynamic` (rebuild children on each visit), `filterable`
    (first-letter/text search), `noStepUpAfterSelect`, `macrotext` + `secureMacro`
    (run secured action on Enter via SecureActionButtonTemplate).
  - **Behavior hooks:** `OnEnter`/`OnLeave` (cursor land/leave; sound + secure
    macro binding), `OnSelect`/`OnPostSelect` (Enter handling; the execution
    core at `templates.lua:337-469`), `OnAction(self, cleanValue, parentName)`
    (the business-logic write), `OnPrev`/`OnNext`/`OnFirst`/`OnLast`/`OnBack`
    (arrow/home/end/escape navigation), `OnKey` (alphanumeric quick-jump),
    `BuildChildren` (the per-node factory; default no-op), `GetCurrentValue`
    (optional; pre-positions the cursor on the child whose name matches),
    `OnUpdate` (re-focus after a rebuild, `templates.lua:74-127`).
  - Likely-vestigial: `type` after init, the commented `ttsEngine`, the
    serialization-excluded `frame`.
- `InjectMenuItems(aParentMenu, aNewItems, aItemTemplate)`
  (`Sku/SkuZOptions/Core.lua:4149`): clones the template via the `MenuMT`
  `__add` metatable (`templates.lua:11-35`), sets `name`/`parent`, and — when a
  template is given — **wires the `prev`/`next` sibling chain centrally**
  (`Core.lua:4158-4161`). When `aItemTemplate` is nil it assigns a pre-made
  `children` array and does **not** wire the chain.
- **Linked-list maintenance is centralized for insertion** (only
  `InjectMenuItems` wires it). Removal/pruning is the asymmetric risk: at least
  the AH buy "gone/prune" flow and the sell re-anchor
  (`Core.lua` ~613-620 and `SkuCaptureSellState`/`SkuRestoreSellPosition`
  ~4322-4388) re-derive position by index/array rather than through a shared
  splice helper. Confirm the exact removal sites before refactoring.
- **No central registry.** When the menu first opens, the root is assembled by a
  hardcoded inline sequence in `Sku/SkuZOptions/Core.lua:1775-1808`: one
  `InjectMenuItems(SkuOptions.Menu, {L["...MenuEntry"]}, ...)` block per module
  (SkuNav, SkuMob, SkuChat, SkuQuest, SkuCore, SkuAuras) plus the Game-Options
  (1814) and Accessibility (1831) built-ins, each with `dynamic = true` and a
  `BuildChildren` that calls `Module:MenuBuilder(entry)`. The per-module
  `MenuBuilder` then hand-builds its subtree (e.g. `SkuZOptions/Options.lua:989`).
- **Estimated scale:** ~500-600 live menu nodes; the same ~6-line property block
  is repeated 50+ times across ~14 files.

## 2.2 Entry archetypes (the future declarative node types)

Every hand-built entry collapses into one of seven recurring shapes. Concrete
example sites:

- **Toggle** (on/off, Ein/Aus) — e.g. pet autocast `SkuCore/Options.lua:1614`.
  ~8-10 instances.
- **Numeric range** (1..N loop) — e.g. range checks `SkuCore/Options.lua:1663`.
  ~3-5 instances.
- **Enum select** (pick one of several) — e.g. chat message-type
  `SkuChat/Options.lua:660`. ~20+ instances.
- **Dynamic list** (BuildChildren loops live data) — e.g. bag items
  `SkuCore/Options.lua:1280`, plus friends/auctions/dungeons/spells/waypoints.
  ~15-20 instances.
- **Action/button** (Enter executes, no children) — e.g. delete tab
  `SkuChat/Options.lua:590`. ~30-40 instances.
- **Submenu container** (holds children only) — the most common; ~50-70.
- **Macro/secure** (`macrotext`+`secureMacro`) — pet/camera/keybind actions;
  ~10-15.

The first three (toggle, numeric range, enum select) are pure settings views:
their `OnAction`/`GetCurrentValue` just read/write one `SkuOptions.db` path. They
are the prime candidates for auto-generation from the Workstream 1 schema.

## 2.3 Problems this causes

- **The user-facing menu tree is hard-wired to the code/module structure — the
  biggest limitation.** The entire top level is built as one node per code
  module at `SkuZOptions/Core.lua:1775-1808`: `L["SkuNavMenuEntry"]` ->
  `SkuNav:MenuBuilder`, `L["SkuMobMenuEntry"]` -> `SkuMob:MenuBuilder`, ...
  `SkuCore`, `SkuAuras`. Each module's `MenuBuilder(parent)` then builds its
  entries under *that* parent, so a setting physically lives wherever its owning
  module's builder puts it. Grouping by purpose (e.g. one "Combat" menu drawing
  from SkuAuras + SkuCore + SkuMob) requires one module's closure to reach into
  and inject under a node another module owns, in the right load order, while
  hand-maintaining the sibling linked list.
  - **Evidence it is already painful:** the "Menü 7 / Barrierefreiheit"
    (Accessibility) grouping at `SkuZOptions/Core.lua:1822-1837` is a hand-built
    workaround — a wrapper node with placeholders, the Video-Options menu moved
    "1:1 one level deeper" by hand, sub-entries explicitly labelled
    `Verknüpfungen, KEIN Duplikat der Logik` ("links, NOT a duplicate of the
    logic") because they had to manually reference logic owned elsewhere, plus an
    in-code "RUECKBAU" (rollback) note and a separate concept doc. A purpose-based
    grouping needed a design document and undo instructions — that is the cost of
    fighting the module-coupled structure.
- **No declarative form.** A toggle takes a dynamic parent + a `BuildChildren`
  closure that injects two children, each with its own `OnAction` — many lines
  to express one boolean. The same boilerplate is copy-pasted per setting.
- **Settings and menu are two hand-kept copies.** Each toggle/enum re-encodes
  the db path, the value mapping, and the current-value read that already exist
  (or will, after Workstream 1) in the schema.
- **Module registration is hardcoded**, not a registry: a new module must be
  inserted into the inline root-assembly sequence in `SkuCore/Core.lua`, and the
  TOC load order must place it before SkuZOptions.
- **Removal/prune is an unguarded invariant.** Insertion wires `prev`/`next`
  centrally, but the removal paths re-derive position ad hoc; this is where
  "arrow navigation silently broke" bugs originate.

## 2.4 Target design

Keep `SkuGenericMenuItem` and `InjectMenuItems` as the **rendering layer**
(behavior-preserving), and add a thin **declarative layer** on top.

- **A node-spec format** — a plain table describing a menu node by archetype:
  ```lua
  { kind = "toggle",   label = L["Read all tooltips"], setting = "SkuCore.readAllTooltips" }
  { kind = "enum",     label = L["Quality"], setting = "SkuCore.AuctionCurrentFilter.Quality",
                       choices = QUALITY_CHOICES }
  { kind = "range",    label = L["Min level"], setting = "...", min = 1, max = 80 }
  { kind = "list",     label = L["Friends"], build = function(add) ... end }   -- dynamic
  { kind = "action",   label = L["Send"], run = function() ... end }
  { kind = "submenu",  label = L["Tabs"], children = { ... } | builder = fn }
  ```
- **A compiler** `SkuMenu:Build(parentEntry, specList)` that translates each
  spec into the existing template node via `InjectMenuItems`, attaching the
  right `OnAction`/`GetCurrentValue`/`BuildChildren` for the archetype. For
  `toggle`/`enum`/`range` with a `setting`, the handlers are generated from the
  Workstream 1 schema (read `SkuSettings:Get`, write `SkuSettings:Set`,
  current-value from the schema) — so settings and menu share one source.
- **Separate contribution from layout (the key decoupling).** Two distinct
  concerns that are fused today:
  - *Contribution:* a module declares its nodes under a stable id/key and owns
    their logic (`SkuMenu:Register("combat.auras", spec)`).
  - *Layout:* a central menu map declares *where in the user-facing tree* each
    id appears, independent of which module produced it. Re-organizing the menu
    (e.g. a "Combat" branch gathering `combat.auras` + `combat.softTarget` +
    `combat.mobs`) becomes editing the layout table — no code moves, no
    cross-module reach-in, no linked-list splicing, no logic duplication. This is
    what makes "Menü 7"-style groupings a data edit instead of a documented,
    rollback-noted code surgery. It also enables alternate layouts (by-purpose
    vs by-module) and user-reorderable menus.
- **A registry** `SkuMenu:RegisterModule(name, order, builderFn)` replacing the
  hardcoded root sequence (`SkuZOptions/Core.lua:1775-1808`); the root assembly
  iterates the registry/layout map. Adding a module becomes one registration
  call, no edit to the central assembly.
- **Central list helpers** `SkuMenu:Insert`/`SkuMenu:Remove` that own `prev`/`next`
  splicing for both add and remove, so no caller hand-maintains the chain.

This is additive: existing `MenuBuilder` closures keep working; modules migrate
to specs one menu at a time.

## 2.5 Migration strategy (incremental, non-breaking)

- **Phase A — Plumbing.** Add `SkuMenu` (compiler + registry + list helpers)
  alongside the current code; route the existing hardcoded root sequence through
  `RegisterModule` without changing the rendered tree.
- **Phase B — Convert archetypes, smallest menus first.** Replace hand-built
  toggle/enum/range entries with specs (these gain the most and are lowest
  risk). Then containers and action buttons. Dynamic lists last (most behavior
  to preserve).
- **Phase C — Schema-link.** Point generated handlers at `SkuSettings`; delete
  the now-redundant inline `OnAction`/`GetCurrentValue` for settings-backed nodes.
- **Phase D — Lock the invariant.** Make all removal paths go through
  `SkuMenu:Remove`; audit for any remaining hand `prev`/`next` writes.

## 2.6 Risks & watch-outs

- **Exact navigation semantics must be preserved** — Enter-sets-and-stays vs
  right-arrow-descends, `GetCurrentValue` cursor pre-positioning, `isSelect`
  vs `actionOnEnter`, `noStepUpAfterSelect`. The compiler must reproduce these
  per archetype exactly (see the `sku-menu-key-semantics` memory note).
- **Secure/macro entries** can only run from a hardware event; the compiler must
  keep `macrotext`/`secureMacro` on the actual template node (no wrapping that
  breaks the secure path).
- **Dynamic-list rebuild timing** (`self.children = {}` then `BuildChildren`,
  then `OnUpdate` re-focus) is subtle; convert these last and test focus
  restoration carefully.
- **Removal sites** are the highest-bug-risk area; enumerate them all before
  Phase D.

## 2.7 Verification (screen-reader-friendly)

- `/wdsku` and `/wdsku3` tree dumps of representative menus (one per archetype:
  a toggle, an enum, the AH filter tree, the friends dynamic list, a container)
  captured **before** and **after** each conversion — the `tree`, `spoken`, and
  `ttsFrameText` must match.
- `/wdwatchsku` while navigating the converted menu — the announced lines must be
  identical to baseline.
- luaparser syntax gate per file; in-game set-a-value-then-`/reload`-and-read-back
  smoke test per converted setting node.

## 2.8 Task checklist

- [x] M-A1. Add `SkuMenu` module (registry + layout map + Insert/Remove helpers); TOC-register **early** (after `SkuSettings.lua`, line 28) not after SkuZOptions — the registry must exist before the open handler calls it, and the renderer/builders resolve lazily at open time. `ns.Menu` + global `SkuMenu` alias (mirrors SkuUtil/SkuSettings). Provides `RegisterModule(id,{label,build})`, `SetRootLayout(ids)`, `InjectModuleEntry`/`AssembleRoot`, and central `Insert`/`Remove` sibling-list helpers (Remove additive, not yet wired into callers — that is M-D1). The toggle/enum/range **compiler is intentionally NOT built yet**: that capability already exists as `SkuOptions:IterateOptionsArgs` (auto-generates toggle/select/range/execute nodes from an AceConfig `options.args` table over a db subtable); a declarative archetype layer is deferred to M-B, shaped by the first real conversion rather than guessed now (W1's "no speculative layer without a consumer" lesson).
- [x] M-A2. Routed the hardcoded root sequence (was `SkuZOptions/Core.lua:1775-1820`: 6 module entries + Game Options) through `SkuMenu:AssembleRoot(SkuOptions.Menu)` driven by the registry + `rootLayout`. Behaviour-identical by construction: same 7 entries, same order, labels resolved at open time (incl. Game Options' locale-computed title), `dynamic = true` + `BuildChildren -> Module:MenuBuilder(entry)` reproduced, and one-at-a-time injection reproduces the original prev/next sibling chain exactly. The Accessibility ("Menue 7") grouping stays inline/untouched (a special hand-built grouping; folding it into the registry is a later step). luaparser-clean; in-game `/wdsku3` before/after pending.
- [~] M-A3. Decoupling mechanism IN PLACE: `SkuMenu.rootLayout` is a plain ordered id list, separate from the `RegisterModule` contributions — reordering the root is now a one-line data edit with no module-code change and no hand-maintained sibling chain. Default layout kept identical (behaviour-preserving). Full "re-home into a different branch" needs the layout map extended to nesting (all root entries are siblings today) — that arrives with M-B. The reorder can be demonstrated in-game by permuting `rootLayout` and diffing `/wdsku3`.
- [x] M-B1. Declarative node compiler added to `SkuMenu` (`Build(parent, specs)` /
  `BuildNode`), then generalized: kinds `list` (dynamic, `build`), `settings`
  (IterateOptionsArgs container), `submenu` (build closure or nested specs), `action`
  (leaf; `run`), plus a passthrough of optional flags/handlers (filterable, dynamic,
  isSelect, isMultiselect, noStepUpAfterSelect, macrotext, secureMacro,
  tooltip→textFull, onAction, onEnter, onLeave, getCurrentValue, onUpdate, onKey) so any
  hand-built entry reproduces exactly. toggle/enum/range are NOT separate kinds — they
  are the children `IterateOptionsArgs` already renders, so `settings` delegates. First
  conversion: **SkuMob:MenuBuilder**. **Key invariant:** `list`/`submenu` assign `build`
  DIRECTLY as `BuildChildren` so a colon-method build ref (e.g. `SkuCore.AuctionHouseMenuBuilder`)
  still receives `(entry, entry)` from `self:BuildChildren(self)` (a one-arg wrapper would
  nil out its `aParentEntry`).
- [x] M-B2. Converted the remaining top-level MenuBuilders to specs (one agent per file,
  strict behaviour-preserving rules, luaparser-gated, diff-reviewed): **SkuNav** (4 entries
  + a dead `if false` "Daten" block left in place), **SkuChat** (5), **SkuQuest** (3),
  **SkuCore** (14, incl. the 7 colon-method-ref submenus), **SkuAuras** (1; its "Options"
  left hand-built because it is `filterable=nil` and the `settings` kind would force it
  true), and **SkuCore:GameOptionsMenuBuilder** (node-by-node inside its runtime loop).
  Inner closures moved verbatim; order/flags preserved; no live refs to removed top-level
  locals. The `macro` archetype was not needed as a separate kind — macro entries are
  `action` specs carrying `macrotext`/`secureMacro` via the passthrough. luaparser-clean
  across all files; **one big in-game test pending** (navigate every module menu + Game
  Options; behaviour must be unchanged).
- [ ] M-C1. Link generated settings handlers to `SkuSettings` (depends on Workstream 1 Phase C); remove redundant inline handlers.
- [x] M-D1. Enumerated all node-removal / `prev`-`next` write sites. Finding: there is
  exactly ONE genuine menu-node *removal* — the AH buy-prune in
  `SkuCore/auctionHouse.lua` (`AuctionPruneListAuction`), which hand-spliced
  `prev`/`next` + `table.remove`d from `children`. Routed it through the central
  `SkuMenu:Remove(tEntry)` (behaviour-identical: same splice + remove, plus it nils the
  ghost's pointers); dropped the now-dead manual index loop; `tNeighbor` for the cursor
  re-position is still captured before removal. The OTHER `prev`/`next` writes are NOT
  removals and stay by design: `SkuZOptions/Core.lua` `InjectMenuItems` (the canonical
  central INSERTION wiring) and the text-filter **re-link** (`ApplyFilter`, ~3599-3628 /
  ~3678-3679) which rebuilds the whole visible chain over the filtered subset — a full
  re-link, not a per-node splice, so `SkuMenu:Remove` does not apply (a future
  `SkuMenu:Relink` could centralize it, but it has one behaviour-critical consumer and is
  out of M-D scope). The `linksHistory` `table.remove`s are breadcrumb history, not menu
  nodes. luaparser-clean; in-game test = an AH multi-buy where the last of a group goes
  "vergriffen" and is pruned (arrow up/down must skip the removed entry).

---

# Workstream 3 — Performance profiling pass  (INVESTIGATED — candidates mapped)

Static read-through is done; the hot-spot list below is **inferred from code,
not yet measured**. The rule stands: measure first, optimize only what the
baseline confirms.

## 3.1 Existing instrumentation (use this to measure)

- `Sku.MetricPoint()` via `debugprofilestop()` (`Core.lua:134-135`) + an
  on-screen performance OnUpdate (`Core.lua:314-329`, every 0.1s when enabled).
- `Sku.PerformanceData[name]` rolling averages already wired around the combat
  hot paths: ~25 `debugprofilestop()` probes in `SkuCore/aqCombat.lua` (lines
  253-832) and one around `EvaluateAllAuras` (`SkuAuras/Core.lua:832`,
  storage line 1248 currently commented out).
- So Sku already has a timing harness — the baseline work is mostly enabling and
  reading it, not building it.

## 3.2 Inventory (by category, with file:line)

- **OnUpdate handlers** — most self-throttle with an elapsed accumulator, a few
  run raw every frame:
  - `SkuCore/aq.lua:468` — health/power monitor, 50ms throttle but does 8-12
    deep `SkuOptions.db.char[...][talentSet]...` lookups per tick plus per-tick
    string concatenation (`aq.lua:512`). **Per-tick db churn — ties to W1 `Sub`.**
  - `SkuNav/Core.lua:2152` — waypoint drawing; `EnumerateActive` loops appear to
    run **every frame** (DrawAll gated to 0.2s, but the enumerator loops at
    2166/2195 are not obviously throttled) + per-frame tooltip/color table allocs
    (2172-2217). **Verify the throttle boundary.**
  - `SkuAuras/Core.lua:93` — aura eval, 0.25s; scans ~45 units (player/focus/
    target/pet/4 party/40 raid) each tick.
  - `SkuZOptions/utilities.lua` — 8 coroutine-driven builder OnUpdates (lines
    59/354/1000/1037/1118/1191/1292/1384) at 1-100ms; plus cursor-blink raw every
    frame (`Core.lua:5722`).
  - Low-risk/gated: `Core.lua:314`, `auctionHouse.lua:179/1612`,
    `SkuChat/Core.lua:2247` (5s), `visualAids.lua:294`, the SkuMM drag handlers.
- **Timers/tickers** — ~250 `C_Timer` calls, mostly one-shot UI nudges. Notable
  self-rescheduling: the AH `StrategyBuySearch` retry loop
  (`auctionHouse.lua:1669/1690/1731`, guarded by maxFails). Persistent ticker:
  `LibRangeCheck` `C_Timer.NewTicker(5, ...)` cache invalidation.
- **High-frequency events:**
  - `COMBAT_LOG_EVENT_UNFILTERED` registered **twice** — `aqCombat.lua:1215`
    (GUID-cached, cheap on hit; ~29-unit loop on cache miss via
    `aqCombatIsPartyOrRaidMember`) and `SkuAuras/Core.lua:799` → chains to
    `EvaluateAllAuras` which allocates a `tBuffList {}` and loops `UnitAura`
    1..40 per call. In raids CLEU fires 100s/sec. **Highest suspected cost.**
  - `UNIT_AURA` (`aq.lua:1577`), `UNIT_HEALTH` (`aq.lua:1263`, lean),
    `BAG_UPDATE` (`SkuCore/Core.lua:356`, can fire many times per vendor action).
- **Scanners** — mostly manual/bursty, not continuous: `minimapScanner.lua`
  (loops `Minimap:GetChildren`, tooltip lines, scan results — 239/421/524/585),
  `gameWorldObjects.lua` (DB-lookup loops, manual), `auctionHouse.lua:1648`
  (sorts 50-200+ results per search).
- **Load-time** — `aqCombat.lua:19-100` builds audio tables with 50+
  `string.format` and ~69 `table.insert` at file load; the gitignored
  `routedata_global_wotlk.lua` (~1.1M lines) and SkuDB asset tables load once at
  init (the dominant startup cost to confirm).
- **Allocation churn in hot paths** — `tBuffList {}` per CLEU
  (`SkuAuras/Core.lua:869`), per-result table per auction
  (`auctionHouse.lua:1653`), per-frame color/tooltip tables in nav OnUpdate,
  per-tick strings in aq monitor.

## 3.3 Top suspected hot spots (hypotheses, ranked)

1. `EvaluateAllAuras` on every CLEU — `SkuAuras/Core.lua:799/831` (alloc + 40-deep loop, raid-frequency).
2. `aq.lua` monitor OnUpdate — deep per-tick db lookups + string churn (`aq.lua:468-800`).
3. Nav drawing OnUpdate — possible per-frame enumerator loops + allocations (`SkuNav/Core.lua:2152-2269`).
4. `aqCombat` CLEU handler cache-miss path — 29-unit loop (`aqCombat.lua:1215`, `aqCombatIsPartyOrRaidMember`).
5. Menu coroutine OnUpdates + raw cursor blink (`SkuZOptions/utilities.lua` ×8, `Core.lua:5722`).
6. AH result processing — sort over 50-200+ rows + retry loop (`auctionHouse.lua:1648`).
7. LibRangeCheck OnUpdate + 5s cache ticker (`Libs/LibRangeCheck-3.0:4630/4620`).
8. Startup cost of `routedata_global_wotlk.lua` + SkuDB assets.

## 3.4 Approach

- **Measure first.** Enable `scriptProfile` (CVar) for `GetAddOnCPUUsage`, turn
  on `Sku.PerformanceData` (un-comment the aura store), and add temporary
  `dprint` timing breadcrumbs around the ranked suspects.
- **Baseline scenarios** (deterministic, logged): idle in town, solo combat,
  raid/heavy CLEU, navigating a route, AH search open, menu navigation.
- **Optimize only confirmed costs**, cheapest-fix first: hoist deep db reads to
  a cached `Sub` (W1 synergy), reuse scratch tables instead of per-event allocs,
  add/raise throttles where correctness allows, early-filter CLEU before work.
- **Regression guard:** re-run the baseline scenarios after each fix; compare
  logged `PerformanceData` numbers; no behavior change in what is spoken.

## 3.5 Verification (screen-reader-friendly)

- Numbers, not visuals: read `Sku.PerformanceData` / `GetAddOnCPUUsage` via
  `/wdeval` and `/skudebug` ring timings before vs after.
- `/wdwatchsku` to confirm announcements are unchanged after each optimization.

## 3.6 Task checklist

- [ ] P1. Enable measurement harness (scriptProfile, PerformanceData store, dprint timers); document how to read it.
- [ ] P2. Capture baselines for the six scenarios; record numbers in this file.
- [ ] P3. Confirm/replace the ranked hypotheses with measured costs.
- [ ] P4. Fix top confirmed costs cheapest-first; re-baseline after each; guard announcements unchanged.

---

# Workstream 4 — Modularization / boundaries  (INVESTIGATED — design drafted)

The headline conclusion: **splitting big files into smaller ones brings no
real gain — it is already done and it did not help.** `SkuCore` is already 24
files, yet it is still one object that every other module tangles with. The
gains come from introducing *boundaries*, not from moving code blocks.

## 4.1 Current state (measured)

- **God-object, not modules.** Ace3's real submodule system
  (`NewModule`/`GetModule`) is used **nowhere** (the only `GetModule` hits are
  AtlasLoot's external API). All 24 `SkuCore/*.lua` files attach functions to
  the single global `SkuCore` table — **352 `SkuCore:` method definitions** span
  unrelated features (mail, auction house, combat, sockets, dungeon browser,
  minimap scanner, junk/repair, dialog, ...).
- **Cyclic dependency graph with SkuCore as the hub.** Cross-module reference
  counts (caller folder -> referenced global, excluding self and the shared
  `SkuOptions`/`SkuDB` infrastructure):
  - SkuCore -> SkuChat 117, SkuNav 38, SkuDispatcher 89, SkuQuest 8, SkuAuras 6, SkuMob 1
  - SkuNav -> SkuQuest 26, SkuCore 7
  - SkuQuest -> SkuNav 91, SkuCore 5
  - SkuAuras -> SkuCore 14
  - SkuMob -> SkuCore 26
  - SkuChat -> SkuCore 14
  - This makes SkuCore <-> {Chat, Nav, Quest, Auras, Mob} all **mutual cycles**,
    plus SkuNav <-> SkuQuest. No module can be reasoned about, tested, or
    replaced in isolation.
- **No addon-private namespace** anywhere (`local name, ns = ...` is unused) —
  everything lives in `_G`.
- **SkuDispatcher is clean but underused** — it references only itself (good,
  pure infrastructure), but 89 of its inbound references come from SkuCore alone;
  other modules barely route through it.

## 4.2 The coupling is three distinct kinds (this is the key insight)

Not all the edges above are equal. Treat them differently:

- **(A) Misplaced utilities masquerading as coupling.** The large SkuCore->SkuChat
  edge (117) is **113 calls to `SkuChat:Unescape`** (defined at
  `SkuChat/Core.lua:2108`) — one stateless string helper that merely lives in the
  chat file. Extracting it to a shared util collapses that "cycle" almost
  entirely. Cheap, mechanical.
- **(B) Legitimate service calls — keep, just name them.** SkuQuest->SkuNav (91)
  is almost all clean, stateless geo/map queries: `GetBestMapForUnit`,
  `GetWaypointData`, `Distance`, `GetDirectionToAsString`, area/continent/uimap
  conversions. This is a real navigation service. The dependency is healthy; it
  only needs to be declared as a named interface, not broken.
- **(C) Shared mutable state read directly — the real rot.** Other modules reach
  straight into SkuCore's live fields: `SkuCore.inCombat` (24), `SkuCore.talentSet`
  (24), `SkuCore.isMoving` (8), `SkuCore.SkuRaidTargetIndex` (8),
  `openMenuAfterCombat`/`openMenuAfterMoving`, `GossipList`, ... State owned by one
  module is read all over the codebase. This is where the genuine gains are, and
  it is exactly what the underused dispatcher was meant to solve.

## 4.3 Real gains (why this is not cosmetic)

Breaking the cycles and the god-object delivers, concretely:
- A bug in auction code can no longer silently corrupt navigation/quests.
- Each feature becomes testable / disablable / replaceable in isolation.
- The regression blast-radius of any change shrinks dramatically.
- Clear ownership of state (one writer per field) removes a class of order-of-
  load and stale-state bugs.
- Parallel work on features stops stepping on a shared global table.

None of these come from file-splitting; all come from boundaries + contracts.

## 4.4 Target design

- **Addon-private namespace.** Adopt `local addonName, ns = ...` and hang shared
  internals off `ns` instead of `_G`; keep the public globals (`Sku`, module
  tables) as a thin published surface.
- **Extract misplaced utilities (category A)** into a `SkuUtil` lib
  (`Unescape` first). Mechanical, removes fake cycles immediately.
- **Name the legitimate services (category B).** Declare explicit interface
  tables, e.g. `SkuNav.Geo` (map/coord/direction queries) that SkuQuest depends
  on by contract; no behavior change, just an honest, stable surface.
- **Replace shared-state reads (category C)** with either:
  - a small **state/query service** (e.g. `SkuState:IsInCombat()`,
    `:GetTalentSet()`, `:IsMoving()`) with one writer, or
  - **dispatcher events** for change notifications (combat enter/leave, talent
    switch, movement start/stop) — finally using `SkuDispatcher` as intended.
- **Promote SkuCore's features to real submodules.** Use AceAddon
  `SkuCore:NewModule("AuctionHouse", ...)` etc., one feature at a time, so each
  feature owns its state and lifecycle instead of sharing the `SkuCore` table.

## 4.5 Migration strategy (incremental, never a big-bang)

SkuCore is the hub of every cycle, so a rewrite is the highest-risk move in the
codebase. Do it as a long series of small, independently-shippable extractions:

- **Phase A — Cheap foundation (low risk, do early).** Add the private namespace;
  extract `Unescape` and any other stateless misplaced utilities to `SkuUtil`.
  Verify nothing changed.
- **Phase B — Inventory and freeze the contracts.** Enumerate every category-B
  service edge and every category-C shared-state field (the lists in 4.1/4.2 are
  the starting point). Declare interface tables for B without changing callers.
- **Phase C — State service / events for category C.** Introduce `SkuState`
  and/or dispatcher events; migrate readers of each field one field at a time
  (combat, talentSet, isMoving, ...), removing the direct `SkuCore.<field>` read
  as each is covered.
- **Phase D — Promote features to submodules.** Convert SkuCore features to
  `NewModule` one at a time (start with the most self-contained: e.g.
  JunkAndRepair, mail, sockets), moving their state off the shared table.

## 4.6 Risks & watch-outs

- **Load order.** Real submodules and a namespace change touch `embeds.xml` /
  TOC ordering; get the load sequence right or globals are nil at use.
- **Hidden writers.** Before turning a field into a one-writer service, confirm
  there is genuinely one writer (grep writes vs reads); some fields may be
  written from several places today.
- **Secure/taint.** Moving code must not change which path runs from a hardware
  event (see the AH-buy hardware-event gating note); keep secure handlers intact.
- **This depends on W1 + W2 being done first** (see Sequencing) so two of the
  largest coupling channels are already gone before untangling the rest.

## 4.7 Verification (screen-reader-friendly)

- After each extraction: luaparser syntax gate; `/reload`; `/wdwatchsku` to
  confirm announcements are unchanged; `/skudebug` ring to confirm the feature's
  breadcrumbs still fire.
- Re-run the relevant feature's smoke test (e.g. open AH, run a combat scenario,
  navigate a route) and confirm identical spoken behavior.
- Track the cycle count going down: re-run the cross-module reference matrix
  (the grep in 4.1) after each phase; the off-diagonal counts should fall.

## 4.8 Task checklist

- [x] X-A1. Adopt `local addonName, ns = ...`; move shared internals off `_G`. (Phase-A scope: seam established.)
  - `Core.lua` previously did `local ADDON_NAME = ...`, discarding WoW's second
    addon vararg — the per-addon private table shared across every Sku file. Now
    captured as `ns` and exposed as `Sku.ns` so any module can reach it.
  - `SkuUtil` is the first resident: it lives on `ns.Util`, with the global
    `SkuUtil` kept as a thin published alias (zero call-site churn). This is the
    canonical pattern for future internal helpers (live on `ns`; add a global
    alias only if published).
  - Deliberately NOT done here: bulk-moving the existing published globals
    (`Sku`, `SkuCore`, `SkuChat`, … and frame-name globals) off `_G` — they are
    the published surface (~283 cross-refs + external addons like AtlasLoot/WVDebug
    reference them by name). That migration is incremental and belongs to W4
    Phases C/D (state service / submodules), not a Phase-A big-bang.
- [x] X-A2. Create `SkuUtil`; move `Unescape` (SkuChat/Core.lua:2108) + other stateless utils; repoint callers.
  - Added `Sku/SkuUtil.lua` (global `SkuUtil`, owns `escapes`/`escapesChat`
    + `SkuUtil:Unescape`), TOC-registered right after `Core.lua`. `SkuChat:Unescape`
    is now a thin delegating shim; all 125 `SkuChat:Unescape` call sites across 10
    files repointed to `SkuUtil:Unescape`; the `minimapScanner` load-order guard
    (`if SkuChat and SkuChat.Unescape`) removed since `SkuUtil` always loads first.
    This collapses the SkuCore→SkuChat fake cycle (was 117, ~113 of them Unescape).
  - Both **private local** duplicates also collapsed onto `SkuUtil`:
    `SkuCore/LocalMenu.lua` (`local function unescape` + its own `escapes`) — direct
    swap (identical save for SkuUtil's inert-on-TBC `|A.-|a`); and
    `SkuCore/gameWorldObjects.lua` (`local function Unescape`) — swapped via a
    `tostring(SkuUtil:Unescape(x))` wrapper to preserve its load-bearing contract
    that a nil tooltip line becomes the string `"nil"` (downstream compares `~= "nil"`).
    (The `Libs/SkuVoice-1.0` lib-local `Unescape` is a vendored lib — left as-is.)
- [x] X-B1. Enumerate category-B service edges; declare interface tables (start with `SkuNav.Geo`).
  - **Inventory method correction:** the 4.1/4.2 counts are *qualified member
    accesses* (`Target:method` / `Target.field`), NOT bare token greps. A bare
    `\bSkuNav\b` grep over SkuQuest gives 119 lines / 159 matches (comments,
    strings, the definition); counting only `SkuNav:`/`SkuNav.` accesses gives
    **exactly 91**, matching 4.1. Reproduce with `_members.py <caller> <target>`.
  - **SkuQuest→SkuNav (91)** decomposes into three services, not one:
    - *Geo* (stateless map/coord/area/direction): `GetBestMapForUnit`,
      `GetCurrentAreaId`, `GetAreaData`, `GetUiMapIdFromAreaId`,
      `GetAreaIdFromUiMapId`, `GetContinentNameFromContinentId`,
      `GetDirectionToAsString`, `Distance` (+ `GetDirectionTo` from SkuCore).
    - *Route/Waypoint* (`GetWaypointData2`, `SelectWP`, `EndFollowingWpOrRt`,
      `GetAllMetaTargetsFromWp5`, `getAnnotatedWaypointLabel`,
      `GetNearestWpsWithLinksToWp`, `GetAllLinkedWPsInRangeToCoords`,
      `GetNpcRoles`, `GetLayerText`, `GetNonAutoLevel`).
    - *Config/constants* read directly (`BeaconSoundSetNames`,
      `ClickClackSoundsets`, `MaxMetaWPs`, `MaxMetaEntryRange`,
      `BestRouteWeightedLengthModForMetaDistance`).
  - **`SkuNav.Geo` declared** (additive) at the end of `SkuNav/Core.lua`: a
    delegating facade — `function SkuNav.Geo:X(...) return SkuNav:X(...) end` for
    the 9 geo members above. Behaviour byte-identical, self-binding correct,
    multi-return preserved (`GetAreaData` returns 6). **No caller changed** —
    callers get repointed incrementally later in W4. Other consumer of these:
    SkuCore (`Core.lua`, `gameWorldObjects.lua`, `minimapScanner.lua`).
  - Route/Waypoint + the constants reads are the NEXT category-B interfaces
    (e.g. `SkuNav.Route`); deferred until there is a reason to formalize them
    (same "no speculative layer" discipline as W1/W2). Geo first because it is
    the cleanest, largest, purely-stateless slice.
- [x] X-B2. Enumerate category-C shared-state fields and confirm single-writer for each.
  - Method: `_writers.py <field…>` classifies every `SkuCore.<field>` occurrence
    across all source (excl. Libs/SkuDB/SkuAudioData) as write (LHS of a real
    `=`) vs read, per file. Results (sku42 HEAD, post-Phase-A):
  - **Single-writer, SAFE to wrap with a state service (Phase C):**
    - `inCombat` — 3 writes ALL in `SkuCore/Core.lua` (init + the combat
      enter/leave handler @2473/2479); 15 reader files, 51 reads. The prime
      `SkuState:IsInCombat()` + combat-event candidate.
    - `isMoving` — 3 writes ALL in `SkuCore/Core.lua` (init + @1173/1175);
      readers: SkuZOptions 6, SkuCore 4. Clean.
    - `talentSet` — written **once**, `SkuCore/Core.lua:38 = 1`. In this TBC
      build it is effectively a write-once constant; the ~591 "reads" are all
      table-key uses in `aq.lua`/`aqCombat.lua` (`SkuCore.aq[SkuCore.talentSet]`).
      Single-writer trivially; low migration value.
    - `SkuRaidTargetIndex` — 1 write, `SkuCore/aqCombat.lua:41` (table init; owner
      is aqCombat, NOT Core). Readers: SkuZOptions 8, aqCombat 5. Table contents
      mutated in place (identity stable).
  - **MULTI-writer — do NOT model as a one-writer field; use a dispatcher
    request/event instead (Phase C):**
    - `openMenuAfterCombat` — writers in BOTH `SkuCore/Core.lua` (3) AND
      `SkuZOptions/Core.lua` (6); only 1 reader (Core consumes it). It is a
      cross-module *command flag* ("open the menu once combat ends"), not state.
    - `openMenuAfterMoving` — same shape: writers in SkuCore (3) + SkuZOptions
      (7); 1 reader. Same dispatcher-event treatment.
  - **Single-owner + one defensive guard:**
    - `GossipList` — written in `SkuCore/Core.lua` (4×) plus a lazy-init guard
      `SkuCore.GossipList = SkuCore.GossipList or {}` in `SkuZOptions/Core.lua:5047`;
      5 reads in SkuZOptions. Treat SkuCore as owner; the guard folds away once a
      service owns init.
  - **Misfiled state (stored on SkuCore but owned elsewhere) — relocate, don't
    service-wrap:**
    - `pendingPetRename` — written AND read only by `SkuMob/Options.lua`. Belongs
      on SkuMob; move it there (trivial) rather than routing through SkuState.
  - **Shared read-only data tables (single init-writer; published data, not
    rot):** `Monitor` (aq.lua), `Keys` (data.lua), `outputSoundFiles` (Core.lua),
    `RaidTargetValues` (aqCombat.lua). Low risk; candidates for a data module
    later, not for the state service.
- [x] X-C1. Introduce `SkuState` / dispatcher events; migrate field readers one field at a time. (Pending the user's combined in-game smoke.)
  - **Ordering (from X-B2):** start with `inCombat` (single-writer, most readers
    → biggest decoupling win), then `isMoving`. Handle `openMenuAfter*` as
    dispatcher events (multi-writer command flags), not `SkuState` getters.
    `pendingPetRename` is a separate trivial relocation to SkuMob.
  - **DONE — `SkuState` created** (`Sku/SkuState.lua`, `ns.State` + global alias,
    TOC-loaded right after `SkuUtil.lua`): pure-infra query service, no load-time
    deps (SkuCore lookups happen at call time). Two accessors so far —
    `IsInCombat()` returns `SkuCore.inCombat`, `IsMoving()` returns
    `SkuCore.isMoving` (drop-in, identical boolean). Storage still lives on +
    is written only by SkuCore; this only removes the cross-module *reads* of
    SkuCore's field name. Canonical storage can move onto SkuState later without
    touching any reader.
  - **DONE — `inCombat` cross-module reads migrated** (24 reads, 8 files →
    `SkuState:IsInCombat()`): SkuMob/Core (7) + Options (1), SkuZOptions/Core (6)
    + templates (1), SkuQuest/Core (5), SkuChat/Core (2), SkuAuras/Core (1),
    SkuNav/Core (1). SkuCore's own internal reads left as direct field access (it
    owns the field; no cross-module reach there). Verified: clean identical-position
    diffs, luaparser OK on all (SkuChat via the pre-existing-escape neutralize trick,
    `_lintchat.py`), no `SkuCore.inCombat` left outside SkuCore/SkuState. **In-game
    smoke pending.**
  - **DONE — `isMoving` cross-module reads migrated** (4 real reads in
    SkuZOptions/Core → `SkuState:IsMoving()`; 2 `--dprint` comments left as
    historical). SkuCore-internal reads left direct.
  - **DONE — `openMenuAfter*` cross-module WRITES encapsulated.** These are
    SkuCore-owned deferred-action flags (`openMenuAfterCombat`/`openMenuAfterMoving`
    /`openMenuAfterPath`); only SkuCore's update loop reads/acts on them, but
    SkuZOptions used to set them by raw cross-module field writes. Added a
    byte-identical owner-side write API on SkuCore (`SetOpenMenuAfterCombat`,
    `SetOpenMenuAfterMoving`, `SetOpenMenuAfterPath`) and routed all SkuZOptions
    writes through it. Note: this is the *write-side* category-C fix — the fields
    are now private to SkuCore. The SkuZOptions→SkuCore *edge* remains (now method
    calls), but as a legitimate service call ("defer this menu-open"), not a raw
    field poke. A later dispatcher-event pass could drop the edge entirely if
    desired; not needed for the state-ownership goal. (Did NOT attempt to unify
    the per-site defer logic — the sites are asymmetric, e.g. the combat-defer at
    SkuZOptions/Core:1760 is commented out — so a control-flow rewrite was avoided
    in favour of the safe 1:1 encapsulation.)
  - **DONE — `pendingPetRename` relocated** off SkuCore onto SkuMob. It was
    read+written ONLY by SkuMob/Options.lua (just parked on the SkuCore table);
    all 5 sites now use `SkuMob.pendingPetRename`. Pure relocation, no behaviour
    change.
  - **Verification:** luaparser OK on every touched file; all diffs are clean
    identical-position swaps; full-tree scan confirms zero live cross-module raw
    read/write of `inCombat`/`isMoving`/`openMenuAfter*`/`pendingPetRename`
    remains (only inert `--dprint` comments). **One combined in-game smoke
    pending (user-run).** X-C1 complete pending that smoke.
- [~] X-D1. Promote SkuCore features to AceAddon submodules with runtime enable/disable, most self-contained first; move state off the shared table.
  - **DIRECTION (user decision):** the goal is **per-feature runtime on/off** so
    users can run only the parts they want (or coexist with other addons). So the
    target is AceAddon `NewModule` (real lifecycle: OnEnable arms, OnDisable tears
    down — clean on/off) PLUS state ownership, applied **consistently to most
    features** (even ones a mere setting could gate, e.g. JunkAndRepair, for a
    uniform model). This supersedes the earlier "sub-table only" plan.
  - **Framework (the template for every feature):**
    - `local M = SkuCore:NewModule("Feature")`; feature state lives as module
      upvalues / on `M`. `M:OnEnable()` registers events + sets up; `M:OnDisable()`
      tears down (true on/off).
    - **Persisted on/off:** a per-feature `enabled` flag under the "SkuCore"
      SkuSettings namespace (`moduleEnabled.<Feature>`, default true; no
      SavedVariables migration). On load, apply persisted disables at a point
      where settings exist (avoid reading settings in module `OnInitialize` —
      SkuCore's modules init before SkuOptions.db across addons; do it in OnEnable
      or a late apply-states pass). A generic **"Features" toggle menu** (built
      once for all modules) is the surfacing — follow-up after the mechanism is
      proven. A `SkuCore:SetModuleEnabled(name, bool)` helper flips live + persists.
    - **Main risk — init timing/order.** Feature init moves from the explicit
      ordered PLAYER_ENTERING_WORLD sequence (only ran on `isInitialLogin`!) to
      AceAddon auto-enable (every load, incl. /reload). Convert ONE feature at a
      time, test each; auto-enable only features with no ordering dependency, else
      keep an explicit init step.
  - **DONE (pilot, commit pending in-game smoke) — `JunkAndRepair` is now a real
    `SkuCore:NewModule`.** OnEnable arms the merchant frame (MERCHANT_SHOW/CLOSED),
    OnDisable stops selling + unregisters. Removed the explicit init call in
    PLAYER_ENTERING_WORLD. State lifted to module upvalues; selling logic
    unchanged. **Behaviour delta to verify:** junk-sell/repair now also re-arms
    after a /reload (the old isInitialLogin-only call did not). luaparser OK.
    Persisted enable-flag + Features menu NOT yet wired — test on/off for now via
    `SkuCore:GetModule("JunkAndRepair"):Disable()/:Enable()`.
  - **TODO next (same framework, ascending coupling):** `mail` (179),
    `Build_SocketingFrame`/sockets (656), then larger features; then wire the
    persisted enable-flag + generic Features toggle menu. Re-measure SkuCore
    method-count / inbound edges after each.
  - **BIGGER-SPLIT — target two-tier architecture (decided model; execute LATE).**
    The current top-level carving (Sku / SkuCore / SkuChat / SkuNav / SkuQuest /
    SkuAuras / SkuMob / SkuDispatcher / SkuZOptions) is grown, not designed. The
    agreed end-state model to re-chart toward:

    - **Tier 1 — always-on core / plumbing + UI (NOT toggleable).** The
      cross-cutting machinery every feature needs; it has no business being turned
      off. Members: the event dispatcher (SkuDispatcher), the settings layer
      (SkuSettings), the menu framework (SkuMenu / SkuZOptions), voice/TTS output
      (voiceOutput + SkuTTS/SkuVoice libs), error logging (ErrorLog/UIErrors),
      shared utils + runtime state (SkuUtil, SkuState). These live as submodules
      of a central core and load first. UI/menu functionality belongs HERE, not as
      a toggleable feature.
    - **Tier 2 — toggleable features (each an AceAddon submodule, on/off).**
      Auction house, mail, junk/repair, sockets, dungeon browser, damage meter,
      friends, quests, auras, mob/target, nav/beacons, minimap scanner, game
      world objects, equipment sets, dial targeting, turn-to-unit, etc. These are
      what the per-feature enable/disable framework (this workstream) governs.
    - **Tier 3 (selective) — promote a feature to its OWN top-level addon** ONLY
      where it clearly pays: data-heavy / standalone features that benefit from
      separate loading or shipping (the big DBs, nav data). Costly (separate
      SavedVariables, no shared state) — do NOT do it by default; justify per case.

    **Execution rule (important):** do NOT re-chart up front. Finish modularizing
    a healthy batch of Tier-2 features first; the module boundaries that emerge
    reveal the natural Tier-1/Tier-2 line and the few Tier-3 candidates. Only then
    physically move files / split addons, one move at a time, each verified. The
    classification above is the map to execute against when that time comes.
- [ ] X-V. Re-run the reference matrix after each phase; record the falling cycle counts here.
  - **Post-Phase-A baseline (qualified-access counts, the 4.1 method):**
    - SkuCore → SkuDispatcher 89, SkuNav 38, **SkuChat 3** (was 117 — Unescape
      extraction collapsed it; only `SetEditboxToCustom`×2 +
      `JoinOrLeaveSkuChatChannel`×1 remain), SkuQuest 8, SkuAuras 8, SkuMob 3.
    - SkuQuest → SkuNav 91, SkuCore 5.  SkuNav → SkuQuest 26, SkuCore 7.
    - SkuMob → SkuCore 26.  SkuAuras → SkuCore 14.  SkuChat → SkuCore 14.
    - The only Phase-A delta is the SkuCore→SkuChat collapse; everything else is
      unchanged (Phase A was additive). Re-run `_matrix.py` (token counts, fast
      trend) + `_members.py` (precise per-member) after each later phase.
  - **Post-Phase-C inbound-to-SkuCore drops (qualified accesses):**
    - SkuQuest → SkuCore **5 → 0** (fully decoupled; all were `inCombat` reads).
    - SkuMob → SkuCore **26 → 13** (`inCombat` ×8 + `pendingPetRename` removed).
    - SkuChat → SkuCore 14 → 12, SkuAuras → SkuCore 14 → 13, SkuNav → SkuCore
      7 → 6 (each lost its `inCombat` read).
    - SkuZOptions → SkuCore dropped its 6 `inCombat` + 4 `isMoving` reads; the
      `openMenuAfter*` writes became `SkuCore:Set*` calls (edge kept as a service
      call, fields now private). New healthy hub edges appeared into `SkuState`
      (combat/movement queries) — pure infra, no back-edges.
    - Remaining inbound-to-SkuCore category-C not yet migrated: `talentSet`
      (write-once constant; low value), the data tables (`Monitor`/`Keys`/
      `outputSoundFiles`/`RaidTargetValues`), `SkuRaidTargetIndex`, `GossipList`.

---

# Workstream 5 — Companion addons / asset packaging  (INVESTIGATED — strategy drafted)

Headline conclusion: **do NOT merge the audio into the core addon.** The
original split was driven by binary-audio size and per-language swappability,
and those reasons still hold strongly. The right move is the leaner version of
your fallback: keep binary audio in **data-only** companions, pull the *glue
code* out of them into Sku, and **rationalize the messy multi-addon beacon split
+ voice-pack naming drift** into a clean, well-defined set (target: 2 audio
companion families — voice + beacon — plus Sku core owning all code/index).

Scope note: only Sku's own audio companions are in scope (voice DB + beacons).
`SkuHealthAssets` and `SkuNavData` are out of scope — they are shared/extension
data, not Sku-proper.

## 5.1 Current state (measured)

External audio companion addons installed alongside Sku:

- **Beacon audio (in scope):**
  - `SkuBeaconSoundsets` — 99 MB, 8,780 mp3, just `Core.lua` + 2 lua. A **hard
    Dependency** of Sku (`Sku/Sku.toc:4 ## Dependencies: SkuBeaconSoundsets`).
  - `SkuCustomBeaconsEssential` — 20 MB, 4,526 mp3. TOC `Dependencies: Sku,
    SkuBeaconSoundsets` (reverse-depends on Sku).
  - `SkuCustomBeaconsAdditional` — 202 MB, 15,841 mp3. Same reverse dependency.
  - Beacon total: ~321 MB, ~29,000 mp3 files.
- **Voice database (in scope):**
  - `SkuAudioData_fast_de` installed — **470 MB, 98,483 mp3** (a single
    per-language voice pack). Sku selects the folder via `Sku.AudiodataPath`
    (`Sku/Core.lua:79-84`): `"SkuAudioData"` for deDE, `"SkuAudioData_en"` for
    English. Paths are then built as
    `Interface\AddOns\<AudiodataPath>\assets\audio\<file>.mp3` in
    `Libs/SkuVoice-1.0:1283`, `SkuMob/Core.lua:16-27,140`, `SkuCore/Core.lua`.
  - The **index** (`SkuAudioFileIndex`, `SkuAudioDataLenIndex`) lives **inside
    Sku** (`SkuAudioData/` module, version-controlled); only the mp3 payload is
    external.
- **Grand total external audio: ~790 MB across ~127,000 mp3 files** (~321 MB
  beacons + ~470 MB one voice pack). Each additional language pack adds hundreds
  of MB more.

## 5.2 Problems / why this needs rationalizing

- **Naming/path drift.** Code expects folders `SkuAudioData` / `SkuAudioData_en`,
  but the installed voice pack is `SkuAudioData_fast_de`. The selection logic and
  the shipped pack names have diverged — exactly the kind of confusion to fix.
- **Beacon audio is split across three addons** with a confusing **reverse
  dependency** (the custom packs depend on `Sku`), and the glue lives in each
  companion's `Core.lua` rather than in Sku.
- **Logic and data are mixed in the companions.** Each ships a `Core.lua`
  (registration/glue) next to its mp3s, so distribution and code are entangled —
  a code fix means re-touching a 99–202 MB addon.
- **The audio path is a de-facto scattered service** (`Sku.AudiodataPath` +
  hand-built `Interface\AddOns\...` strings across SkuVoice, SkuMob, SkuCore),
  with no single resolver.

## 5.3 How WoW loading works (the cost is distribution, NOT in-game load)

Crucial clarification, because it is easy to get backwards: **mp3/ogg files do
not "load" when the addon loads.** WoW only reads each addon's `.toc` and
executes the **Lua/XML files listed in it**; you cannot list an mp3 in a TOC.
Audio is referenced by *path* and played on demand via
`PlaySoundFile("Interface\\AddOns\\...\\x.mp3")` — WoW reads that one file from
disk at play time and discards it. The other ~127,000 files just sit on disk,
untouched, costing **zero load time and zero RAM** until something plays them.

Consequences:
- Bundling vs. separating the audio makes **no difference to in-game load/reload
  time or memory** — the mp3s are lazy either way.
- What actually costs time on every `/reload` (WoW has no incremental "changed
  code only" loader) is the TOC-listed Lua: `routedata_global_wotlk.lua`
  (~31 MB), the `SkuDB/assets` tables (~105 MB), the audio *index*
  (`SkuAudioFileIndex` — tiny vs. the mp3s it points at). That cost is identical
  regardless of where the mp3s live. (This is Workstream 3, not W5.)
- The only dev-side cost of bundling is **filesystem**, not WoW: git stats
  ~127k ignored files, backups/copies grow. Minor.

## 5.4 Why merging into core is still the wrong call (the honest assessment)

The reason is **distribution, not load**:
- Bundling ~790 MB of audio into the code addon means **every Sku release — even
  a one-line fix — re-ships ~790 MB** that users must re-download. Separate
  audio addons are downloaded once; code updates stay tiny.
- It breaks the **per-language swap** model (470 MB *per* voice pack — a user
  installs only their language) and would force the optional 202 MB `Additional`
  beacon set on everyone.
- The installer already treats companions as separately-versioned downloads
  pinned on an older tag (see the download-topology notes / `SkuInstall.json`),
  precisely so audio isn't re-fetched on a code patch. That benefit is real.
- **User-facing simplicity does not require bundling.** Sku already ships an
  installer, so a one-click install can fetch the companions automatically — you
  get the clean install UX *and* small code updates *and* the language model.
  Put the simplicity in the installer, not in the addon packaging.

So: **data stays external; code/index belongs in Sku.**

## 5.5 Target design

- **Two data-only companion families, plus Sku core owning all code:**
  - *Voice:* per-language voice packs with canonical, consistent names and a
    robust selection + fallback in one resolver (fixing the `_fast_de` /
    `SkuAudioData` / `_en` drift).
  - *Beacon:* consolidate `SkuBeaconSoundsets` + the two `SkuCustomBeacons*` into
    a clean tiering (e.g. one required core-beacon pack + one optional extended
    pack), with the dependency pointing the right way (data packs depend on Sku,
    Sku does not hard-require an optional pack).
- **Move companion glue/registration code into Sku.** Companions become pure mp3
  payload. Sku discovers installed packs **data-driven** (scan for known
  beacon/voice data addons and register their sets) instead of each pack shipping
  registration code.
- **One audio-path resolver** (a small service) replaces the scattered
  `Sku.AudiodataPath` string-building — and this is the same seam W4 will turn
  the voice output into a service, so design them together.

## 5.6 Where it sits / why it touches other steps

This is primarily a **strategy decision that must be made early**, because:
- **W1 (settings):** which voice pack and which beacon tiers are enabled are
  settings; the schema must reference the final companion layout.
- **W4 (modularization):** the voice output / audio-path resolution becomes a
  proper service; it should be built against the final packaging, not the current
  drifted one.

The **execution** (moving mp3s, renaming packs, updating the installer) is
distribution-only and behavior-preserving, so it can land late and independently
— but the *target layout* should be fixed before W1's audio settings and W4's
voice service are designed. Hence: decide W5 strategy early, execute W5 late.

## 5.7 Risks & watch-outs

- **Keep exact folder/path names** the resolver builds, or sounds silently fail
  to play. Add a missing-file log to catch regressions.
- **Don't break per-language packs** or force optional audio on all users.
- **Update the TOC `Dependencies`, load order, and `SkuInstall.json` / installer
  download topology** to match any rename/consolidation; re-version the data
  packs separately from core so code updates don't re-ship audio.
- **Behavior-preserving:** the same beacons/voice must play — verifiable by ear.

## 5.8 Verification (screen-reader-friendly)

- The user's "speak/play what you hear" channel: beacons and voice are audio, so
  confirm by listening that the same sounds play after repackaging.
- Add and watch a missing-audio log line (PlaySoundFile failure) via `/skudebug`
  so a wrong path surfaces deterministically rather than as silence.
- `/wdwatchsku` to confirm spoken output is unchanged.

## 5.9 Task checklist

- [ ] C-A1. Decide target packaging (recommend: Sku core owns all code+index; 2 data-only families — voice packs per-language, beacon sounds tiered).
- [ ] C-A2. Resolve the voice-pack naming/path drift; define canonical folder names + one resolver with fallback. (Early — input to W1/W4.)
- [ ] C-B1. Move companion glue/registration code into Sku; make companions pure data; switch to data-driven discovery of installed packs.
- [ ] C-B2. Consolidate the 3 beacon addons; fix dependency direction; update TOC deps + load order.
- [ ] C-B3. Update `SkuInstall.json` / installer download topology; re-version data packs independently of core.
- [ ] C-B4. Verify by ear (same sounds) + missing-file log clean.

---

# Workstream 6 — Documentation index + high/low-level cleanup  (POST-REWORK)

Runs **only after W1–W5 are complete**, so it documents and polishes the final
reworked architecture rather than the old one. Three phases, and **every code
change is gated by your explicit approval** — agents propose, you confirm or
discuss, then approved lists are executed. Behavior-preserving throughout;
cleanup is not feature change.

## 6.1 Phase A — Build the addon documentation index ("LLM index")

(Interpreting "lmn index" as an **LLM index** — a complete, agent-readable map
of the whole addon. Correct me if you meant something else.)

- A structured, addon-wide index: one entry per module and per file, capturing
  purpose, public API/exports, dependencies (in and out), key data structures,
  events subscribed/published, settings keys touched, entry points, and notable
  invariants.
- Stored in `Sku42-Rework-Docs/` (e.g. `INDEX.md` or a small `index/` tree) and
  kept as **living documentation** of the addon as a whole.
- Dual purpose: (1) human-facing documentation; (2) the **shared base context
  every cleanup agent reads**, so findings are consistent and deduplicated and
  no agent has to re-explore the codebase from scratch.
- Built after the rework so it reflects the final boundaries (W4 submodules,
  W2 menu registry, W1 settings schema, W5 audio layout).

## 6.2 Phase B — High-level cleanup (architectural, whole-addon)

- Scope: cross-file / cross-module structure. Hunt for big structures that
  remain awkward after the rework, bad coding practices that survived, and
  module/file **splits or merges that bring real gain** in addon or code quality
  — only where the gain is genuine, not cosmetic file-shuffling (per W4's lesson
  that splitting alone buys nothing).
- Output: a deduped, prioritized **findings list** — plain-text linear bullets
  (no tables — screen-reader reviewable), each item with rationale, affected
  files, risk, and rough effort.
- Gate: presented to you to confirm / discuss / drop before anything runs.

## 6.3 Phase C — Low-level cleanup (per-file)

- Scope: within each file. Find duplicated or near-duplicate methods, dead code,
  inconsistent naming/structure, unnecessary or redundant loops, repeated work,
  style inconsistencies, etc.
- Method and output: same as Phase B but batched **file-by-file**, against the
  index updated to reflect any Phase-B structural changes.
- Gate: same plain-text findings list for your approval before execution.

## 6.4 How the agent batching works

- **Fan out** review agents over a work-list (modules for B, files for C); each
  agent reads the index plus its batch and returns **structured findings**, not
  prose.
- **Synthesize:** merge, dedupe, rank; flag overlaps/conflicts between findings.
- **Approval gate (mandatory):** you review the linear list and confirm, edit, or
  drop items. Nothing is auto-applied.
- **Execute** approved items as a second batched pass — one coherent change-set
  at a time, behavior-preserving, with the standard verification (luaparser gate,
  `/reload`, `/wdwatchsku`, feature smoke tests) and a commit per group.
- The existing `/code-review` and `/simplify` skills and the Workflow
  orchestration are usable building blocks for each batch.

## 6.5 Order & why

- **Phase A before B/C:** agents need the index as their shared map.
- **B before C:** high-level splits/merges change which files exist, so do the
  structural work before per-file polishing (don't polish a file that is about
  to be split or merged).
- **Whole workstream last:** it operates on the finished, reworked code.

## 6.6 Risks & watch-outs

- **Approval gate is non-negotiable** — findings never auto-apply; you decide.
- **Keep the index in sync** as Phase B changes structure, so Phase C agents read
  current truth.
- **Findings must be plain-text linear lists** (screen-reader), never tables.
- **Guard against agent over-eagerness:** a "bad practice" claim must be
  justified against the index and a real gain, not a style preference; you
  arbitrate. Behavior must not change.

## 6.7 Task checklist

- [ ] D-A1. Build the documentation/LLM index (per-module + per-file map); store in `Sku42-Rework-Docs/`; verify coverage.
- [ ] D-B1. Batched high-level review against the index; produce a deduped, prioritized findings list.
- [ ] D-B2. Approval gate; then execute approved structural items, behavior-preserving, with verification + commits; update the index.
- [ ] D-C1. Batched per-file review against the updated index; produce a findings list.
- [ ] D-C2. Approval gate; then execute approved per-file items, with verification + commits.
- [ ] D-V. Keep the index maintained as the addon's living documentation.

---

# Sequencing — where each workstream sits in the chain

The order matters because the workstreams reduce each other's surface area.

1. **W4 Phase A first (cheap foundation, low risk):** private namespace +
   extract misplaced utilities. De-risks everything after it; no behavior change.
2. **W1 — Settings access layer.** Removes the "settings as implicit message bus"
   coupling and centralizes the schema. Foundational for both W2 and W4.
3. **W2 — Menu schema + registry.** Consumes W1's schema to auto-generate
   settings nodes; its registry removes the hardcoded menu root-assembly coupling
   (itself a modularization win). Run after W1 is through Phase B.
4. **W4 Phases B-D — the real modularization.** Break category-C shared state and
   promote features to submodules. Done now because W1 and W2 have already
   removed two of the largest coupling channels, leaving less to untangle.
   Strictly incremental, one field/feature at a time.
5. **W3 — Performance.** Can run last or interleave at any point; clean
   boundaries make profiling and targeted fixes easier, but it does not depend on
   the others. The one early tie-in: W1's cached `Sub` accessor is the fix for
   the per-tick db churn W3 identified, so that specific fix can land with W1.

W5 splits across the chain rather than occupying one slot:
- **W5 strategy decision — early, before W1's audio settings and W4's voice
  service.** Fix the target companion layout (canonical voice-pack names + one
  audio-path resolver, beacon consolidation) so W1's schema and W4's voice
  service are designed against the final shape, not the current drift.
- **W5 execution — last / independent.** Moving mp3s, renaming/consolidating
  packs, and updating the installer is distribution-only and behavior-preserving,
  so the heavy file work can land after the code workstreams.

6. **W6 — Documentation index + cleanup — strictly last.** Only after W1–W5 are
   done, since it documents and polishes the final architecture. Phase A (index)
   → Phase B (high-level cleanup) → Phase C (low-level cleanup), each agent-batched
   and gated by your approval before any change runs.

Rule throughout: one workstream (and within W4, one phase) in flight at a time,
each independently shippable and behavior-preserving.

---

# Library assessment (reference)

- **Foundation: Ace3** (AceAddon r12, AceEvent r4, AceDB r26, AceConfig r3,
  AceGUI r36, plus AceConsole/Comm/Locale/Serializer, CallbackHandler, LibStub).
  Also LibSharedMedia-3.0, LibRangeCheck-3.0, LibGearScore-1.0.
- **Sku's own libs:** SkuTTS-1.0, SkuVoice-1.0, SkuBeacon-1.0 (the screen-reader
  core — keep).
- **Verdict:** Ace3 is mature and current, not obsolete; it is the right
  foundation and runs fine on the Anniversary client. The "more modern"
  alternatives seen elsewhere (middleclass/InfoClass OOP, Blizzard's
  `EventRegistry`/`CallbackRegistryMixin`, the Settings API) are style/coupling
  choices, not a newer generation — and the Settings API is irrelevant since a
  blind user never uses the visual options panel. **Swapping the framework is
  high-cost / low-reward.** All planned wins are architectural, layered on top
  of Ace3.

## Cross-cutting issues (now folded into Workstream 4)

- **No private namespace** — everything is in `_G` (`Sku`, `SkuCore`, ...,
  plus frames by hardcoded name). Collision-prone; hides coupling. (W4 Phase A.)
- **SkuDispatcher is bypassed** — only ~15 custom `SKU_*` events flow through
  it while ~283 native events are registered directly; modules call each other's
  globals directly. (W4 Phase C uses it for shared-state change events.)
- **Frame-name coupling** — UI parts find each other via hardcoded global frame
  names. (Address opportunistically during W4 feature extraction.)
