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

- **DB rework stages 0–2 (DB-RESTRUCTURE-PLAN.md).** Stage 0: verification
  toolkit — `_db_convert.py` (whitelist converter, verification built in),
  `_db_manifest.py` + `MANIFEST-DB.txt` (SHA-256 pins for the gitignored data
  files; all 34 pristine files byte-match the upstream-src blobs of commit
  22e81c0), in-game `/skudbcheck` (deterministic per-dataset fingerprint →
  `SkuDebugLog.dbCheck`, differ `_dbcheck.py`) and `/skudbmem` (subtree memory
  ranking → `SkuDebugLog.dbMem`, reader `_dbmem.py`), both in the new
  `SkuDBTools.lua`. Stage 1: `Sku:EnsureData` builder registry now pcalls every
  builder, sets ready only AFTER success (failure = spoken error + SkuErrorLog,
  never silently partial), nils each builder global and forces a GC — frees the
  ~48 MB of route source strings that stayed resident forever. Stage 2: the
  nine big data files (base+WotLK creatures/items/quests/objects + spells)
  converted to chunked string-literal builders (25 datasets, 471,132 records,
  955 chunks of ~500 records), built EAGERLY by the new
  `SkuDB/ChunkLoader.lua` at the end of the SkuDB TOC block — identical
  timing/semantics by design, pure format-risk retirement. Verified
  out-of-game: full interior byte reassembly against pristine `.bak`s, key
  sequence identity, literal-only content, luaparser full parse of all nine
  generated files, file-scope reference scan over the whole SkuDB block,
  deterministic regeneration. Data finding: `NpcData.Names.deDE` contains
  9,104 duplicate record keys (a second, partially-untranslated block;
  constructor last-wins semantics are preserved exactly by the ordered chunk
  merge). In-game fingerprint comparison (baseline vs converted) still
  pending — see the stage-2 test drill in DB-RESTRUCTURE-PLAN.md appendix.

- **Window builders — dropped the redundant Close/Cancel entries (5 windows).**
  Craft, Trade skill, Class trainer, Trade, and Pet stable each appended a
  Close/"Schließen"/Cancel button as the last menu entry (`SkuCore/LocalMenu.lua`
  builders `Build_CraftFrame`, `Build_TradeSkillFrame`, `Build_ClassTrainerFrame`,
  `Build_TradeFrame`, `Build_PetStableFrame`). Escape already closes each window,
  so the extra entry was pure noise for a keyboard/screen-reader user; removed all
  five to match the other windows (gossip/quest/bags/...) which never listed one.
  The windows' real action buttons (Create / Create-all / Train / Trade-accept /
  purchase) are untouched — those are context-gated on the Blizzard button's
  `IsEnabled()`/`IsVisible()`, so they correctly vanish when the action isn't
  available (nothing to train, enchant missing reagents), which is unchanged.
  In-game verified.

- **Character frame — flattened the single "Gegenstände" node under "Ausrüstung".**
  In `SkuCore:Build_CharacterFrame` (`SkuCore/LocalMenu.lua`) the equipment branch
  built "Ausrüstung" (`L["Equipment"]`) with exactly one child, "Gegenstände"
  (`L["Items"]`, `PaperDollItemsFrame`), whose `.childs` held the actual slot list.
  Removed that lone intermediate node: the slot list (`IterateChildren(
  PaperDollItemsFrame, 2)`, minus `GearManagerToggleButton`) now hangs directly
  under "Ausrüstung", so right-arrow lands straight on the first slot. The
  "Ausrüstung" node itself is unchanged; only its `childs` differ. **The in-combat
  character mirror needed no change** — it is built by `tWalk(aParentChilds, 0)`,
  which recurses whatever tree shape exists and detects equipment slots by the
  `^Character.+Slot$` key pattern (depth-independent), so the flattened tree yields
  a mirror one level shallower automatically; `/use <slotID>` arming + the
  Links/Rechtsklick submenus stay intact. In-game verified out of and in combat.

- **Quest frame — flattened the state node onto the quest name.** The quest
  dialog builder (`SkuCore:QuestFrame`, `SkuCore/LocalMenu.lua`) inserted one
  intermediate "state" grouping node — Details (accept) / Fortschritt (progress)
  / Abgabe (turn-in) / Auswahl (greeting) — with the actual quest content nested
  inside it, so the one-level window auto-descend (`CheckFrames`) landed on that
  bare state label instead of the quest text. Removed the intermediate node in
  all four panels so the content goes straight into the window, and folded the
  state onto the first line so the info is not lost: Detail → "Annehmen <quest
  name>", Progress → "Fortschritt <quest name>" (the `dtc[1]` title region),
  Reward → "Abgabe <quest name>", Greeting → greeting text then the selectable
  quest list. Auto-descend now lands directly on the quest text, one level
  shallower; the window node and multi-window nav are unchanged. Safe: those four
  `L[...]` state labels are referenced only by this builder (no SlashFunc
  path-by-label coupling). In-game verified.

- **W3 P1 — performance measurement enabled + made screen-reader readable.** The
  timing harness already existed (`Sku.PerformanceData` EWMA probes in
  `aqCombat.lua`/`aq.lua`, `Sku:MetricPoint`, the on-screen `Sku:Performance`
  frame) but was unusable for a blind user and partly dead: the on-screen frame
  is sighted-only and was never even reachable, `MetricPoint` was never called
  (no load timing captured), and the #1-suspect aura probe
  (`SkuAuras/Core.lua:1317` `EvaluateAllAuras`) was commented out. Changes (all
  additive, behaviour-preserving): (1) un-commented the aura probe; (2) wired
  `MetricPoint` at `PLAYER_LOGIN` + first `PLAYER_ENTERING_WORLD` and
  auto-persist the load timeline to the `SkuDebugLog` ring each session (silent,
  no TTS spam); (3) new `/skuperf` slash command — `combat` (PerformanceData,
  slowest first), `load` (MetricPoint milestones), `cpu` (per-addon
  `GetAddOnCPUUsage`, enables `scriptProfile` + asks for /reload), `reset`,
  `frame` (toggles the old sighted frame, now reachable) — every line goes to
  BOTH chat (live TTS) and the persisted ring (read back out-of-game after
  /reload). CPU APIs resolved across `C_AddOns.*`/global. No combat-path probe
  sites were churned (kept the existing EWMA writes); this is enable+readout
  only. luaparser-gated. **In-game test pending** (P2 baselines).

- **W1 Phase C — locked down (closes Workstream 1).** `SkuSettings.validate = true` permanently.
  Implemented LOG-ONLY (dprint), not reject/clamp — a screen-reader user must never silently lose
  a setting to a schema-type mismatch; a logged mismatch flags a schema fix. Dormant in normal play
  (emits only under /skudebug). The unknown-key→profile raw-path fallback is now unreachable through
  Get/Set (their only callers are the schema-managed menu nodes, all registered) but is KEPT for the
  `Sub` fast path (~2000 unregistered whole-subtable callers need it). C2: the per-module Register
  schemas are the published menu-generation contract, consumed by the W2 M-C1 engine — no separate
  artifact, the runtime registry IS the contract. Validation accuracy verified: a type-vs-default
  audit (`_mc1_typeaudit.py`) reports 0 mismatches across all 163 schema entries, so validation
  never false-positives on a correct option flip (it logs only genuine wrong-type writes).

- **W2-MC1 + W1-C: settings menus are now schema-managed (6 modules).** The menu engine
  `SkuOptions:IterateOptionsArgs` gained `aModule` + `aKeyPrefix`: a leaf option with NO
  inline get/set, under a module, is "schema-managed" — read/written via
  `SkuSettings:Get/Set(module, dottedKey)` (full nested storage path; scope/type/default
  from the schema). `SkuMenu` "settings" kind threads `aSpec.module`. Behaviour-preserving:
  nodes that keep get/set are byte-identical, so modules migrated one at a time.
  - **Pilot SkuMob** (commit 443e0c3, in-game verified): 7 nodes, schema-managed off the
    existing Register schema.
  - **Dotted-key engine upgrade** (b945ef3) for nested option groups.
  - **5 more menus, one commit each:** SkuQuest 23/27 (b28dbc6), SkuChat 17/18 (8f0b8a0),
    SkuNav 19/22 (6d5f145), SkuOptions 40 (5561d53), SkuCore 35 (03b97ac). Each authored a
    `SkuSettings:Register(module, {dottedKey={scope,type,default}})` schema — the W1-C/C2
    contract — and stripped the pure-storage closures (~134 nodes total).
  - **Conservative — KEPT inline (unchanged):** value-transform selects (beacon name↔id),
    side-effect handlers (C_CVar sound volumes, C_TTSSettings, sample beacons, route-data
    loads), and dynamic integer-keyed ressource toggles. OnAction hooks on stripped nodes
    preserved (engine fires them after the managed write). Menu nodes were all profile scope
    (char/global settings are data, not menu toggles). luaparser-gated all files.
  - Pending: one in-game test round of the 5 menus, then W1-C close-out (enable validation,
    drop the raw-path fallback, mark the schema published).

- **W4 Phase E — E3: coupling re-measured, collapse recorded (closes Workstream 4
  decoupling).** Read-only audit — re-ran `_matrix.py` (cross-module global-token
  reference grid) and `_members.py` (per-edge member breakdown) now that A–E2 are
  done, against the §4.1 baseline. No code changed.
  - **Two complementary metrics, both improved:**
    - *God-table def count* (the "is SkuCore still a god-object" metric):
      **352 → 237 (E1) → 138 (E1b) → 137 (E2)** `function SkuCore:` defs, −61%.
      This is where Phase E's win actually shows.
    - *Cross-module reference matrix* ("who reaches into whom", matching-lines
      metric, same as §4.1):
  - **Cycle rot collapsed (category A — the real win):**
    - **SkuCore → SkuChat: 117 → 13** — the single biggest edge, gone. Phase A
      `Unescape`→`SkuUtil` extraction (≈113 calls were one stateless string helper).
    - **SkuMob → SkuCore: 26 → 11** — Phase C state services (`SkuState:IsInCombat/
      IsMoving`) + `pendingPetRename` relocated off SkuCore.
    - **SkuQuest → SkuCore: 5 → 2**, SkuAuras → SkuCore 14 → 12, SkuChat → SkuCore
      14 → 12 — all down.
  - **Healthy service edges kept (category B — not rot, by design):**
    - **SkuQuest → SkuNav: 91 → 126** and **SkuCore → SkuNav: 38 → 47** *rose*
      (normal code growth). These are the legit stateless geo/map service calls
      (`GetBestMapForUnit`, `Distance`, area/continent conversions). The `SkuNav.Geo`
      facade is declared (Phase B) but callers are not yet repointed — a deferred,
      low-value cosmetic pass. The dependency is healthy; the plan said name it, not
      break it.
  - **Dispatcher routing rose on purpose:** **SkuCore → SkuDispatcher 89 → 121** (+
    other modules now route through it too: SkuNav 8, SkuChat 6, SkuAuras 2, SkuQuest
    1). The plan explicitly wanted MORE dispatcher use ("it is underused") — rising
    here is the intended decoupled-comms direction, not coupling.
  - **The matrix's blind spot (recorded for honesty):** the matrix counts the literal
    token `SkuCore`. Phase E moved 215 methods onto isolated module tables but external
    callers still reach features via the published handle `SkuCore.Feature:X`, which
    still contains "SkuCore". So the token-matrix UNDERSTATES E; the def-count is E's
    true metric. (Visible in `_members.py SkuZOptions SkuCore`: much of that 47-member,
    197-access edge is now calls THROUGH feature handles — `SkuCore.VisualAids` 18,
    `SkuCore.AtlasLootIntegration` 5, `SkuCore.Socketing` 4, `.GameWorldObjects` 3,
    `.Aq`/`.aqCombat`/`.GameOptions` — i.e. the menu reaching features by their public
    handle, the expected post-E shape, not raw internal pokes.)
  - **Largest residual edge: SkuZOptions → SkuCore (202 lines / 47 members)** — not in
    the §4.1 baseline (SkuZOptions wasn't measured then), recorded now as the post-W4
    baseline. Expected: the options/menu system is the universal consumer that builds
    UI for every feature. Its weight is menu plumbing (`CheckFrames` 31, `Debug` 16),
    the deferred-action service API (`SetOpenMenuAfter*` 17, the good kind), published
    feature handles (above), and a few un-migrated read-only state fields (`talentSet`
    22 = write-once const, `SkuRaidTargetIndex` 8, `GossipList` 8) noted in the plan as
    low-value category-C deferrals.
  - **Verdict:** every cyclic "rot" edge into SkuCore is down or eliminated; the
    god-table shrank 61%; remaining heavy edges are either the universal menu consumer
    or named geo/dispatcher services. Workstream 4's decoupling goal is met. Deferred
    follow-ups (all optional, recorded in the plan): repoint geo callers onto
    `SkuNav.Geo`; migrate the last read-only category-C state fields; a dispatcher-event
    pass to drop the `SetOpenMenuAfter*` edge.

- **W4 Phase E — E2: Core.lua slimmed, no toggleable-feature method left on `SkuCore`.**
  After E1b the god-table was already down to 137 `function SkuCore:` defs. E2 confirmed
  what legitimately stays core and relocated the one misplaced shared helper:
  - **`ConfirmButtonShow` relocated** auctionHouse.lua → Core.lua. It is a generic
    confirm/editbox popup used by **five** call sites across modules (equipmentSets,
    SkuMob rename, LocalMenu destroy-item, SkuZOptions, and the AH buy flow) via the
    public name `SkuCore:ConfirmButtonShow` — core plumbing, not an AuctionHouse method.
    Pure relocation: name unchanged (still `function SkuCore:`), all callers invoke it at
    runtime behind `if not SkuCore.ConfirmButtonShow` guards, Core.lua loads before every
    caller → zero caller edits, no load-order risk. Its two `SkuAuctionConfirm*Script`
    upvalues moved with it (file-local, only used inside the function). **auctionHouse.lua
    now has 0 `function SkuCore:` defs** — a fully self-namespaced feature file. Core.lua
    is now **106** defs, matching the plan's genuine-core target exactly.
  - **Dead `UNIT_POWER_UPDATE` Core.lua stub: already gone** (removed in the E1b load-order
    fix 10883b7); only an explanatory comment + the dispatcher registration line remain. No
    action needed in E2 beyond confirming.
  - **Genuine-core decision (what stays on `SkuCore`, 137 defs):** Core.lua 106 (lifecycle
    OnInitialize/OnEnable/OnDisable + PLAYER_ENTERING_WORLD etc., the keybinding plumbing,
    Debug/IterateChildren/Distance, and the always-on window/event hooks — nameplates, panic
    mode, autofollow/cast, taxi, gossip/merchant/trade/petstable frame handlers, game-menu),
    LocalMenu 20 (Blizzard-window accessibility menu builders — core UI), ModuleManager 6
    (the toggle registry — the manager itself), voiceOutput 2 (voice/TTS = Tier-1 always-on),
    Options 1 (`MenuBuilder`, the root menu). These are the lean managing-core surface, kept
    by design (= WowVision.base, kept thin) — NOT a code dump.
  - **Two `function SkuCore:` defs in feature files are intentional and KEPT:**
    `visualAids:UpdateNextCombatEnemyBinding` and `alIntegration:AtlasLootApplyKeyBinding`
    are one-line forwarding shims, because the `SkuKeyBinds` string-dispatch table resolves
    `{object="SkuCore", func="…"}` by name. The real methods live on the `VisualAids` /
    `AtlasLootIntegration` module tables; the shim just forwards. Same exception class as the
    E1 forwarder shims — accepted, not relocated.
  - luaparser OK on both changed files. In-game smoke pending (low risk: pure relocation,
    no name/caller/control-flow change).

- **W4 Phase E — E1b VERIFIED in-game (2026-06-28) + load-order fix.** All three
  extractions pass; behaviour unchanged. One regression was caught and fixed first
  (commit 10883b7): the aq codemod rewrote a DEAD empty `UNIT_POWER_UPDATE` stub in
  `SkuCore/Core.lua` to `function SkuCore.Aq:…`, but Core.lua loads before aq.lua, so
  `SkuCore.Aq` was nil there — the line threw at load and aborted the rest of Core.lua
  (~3000 lines), which is what produced the "errors on login + every frame while standing"
  report. Removed the dead stub (aq.lua's real handler always won). **Rule added for future
  extractions: grep `^function SkuCore\.<Handle>[:.]` tree-wide after each codemod — a
  duplicate method DEF in an earlier-loading file is a load-order crash.** Post-fix
  SkuErrorLog is clean (only the benign addon_action_blocked taint + intentional auction/
  dungeon diagnostics); no combat/aq/aqCombat/AuctionHouse error. The user's first-fight
  error is pre-existing and unrelated (not in any changed file, not even captured by SkuErrorLog).

- **W4 Phase E — E1b (hard-3), part 3 of 3: aq extracted — hard-3 COMPLETE.** The
  26 `function SkuCore:Monitor*`/`Aq*`/`UNIT_*`/`MIRROR_*` methods now live on the
  `Aq` module table; published handle `SkuCore.Aq` keeps external callers working.
  78 in-file + 8 cross-file rewrites across 4 files: Core.lua (Monitor*Health2Conti
  calls + the UNIT_POWER_UPDATE dispatcher reg/def), Options.lua (MonitorMenuBuilder),
  SkuZOptions (AqOnLogin, AqSlashHandler).
  - **Hybrid events (AuctionHouse pattern):** module gained the `AceEvent-3.0` mixin;
    the 7 AceEvent events (MIRROR_TIMER_START/STOP/PAUSE, UNIT_HEALTH, UNIT_POWER_FREQUENT,
    UNIT_POWER_UPDATE, UNIT_AURA) now register/unregister on `Aq`. The 6 group/roster
    callbacks + MonitorRaidRosterUpdate stay on `SkuDispatcher` (dot-ref values, reg+unreg
    rewritten in lockstep).
  - **`SkuCore.Monitor` STATE left in place** — the combat-monitor index
    `SkuCore.Monitor.UnitNumbersIndexedRaid` read by SkuAuras (Core.lua:1446+) is a *field*,
    not a method, so it was untouched and **SkuAuras needs no repoint** (the payoff of the
    state-stays decision). Built unconditionally as before, so a disabled Aq can't break SkuAuras.
  - **Pre-existing duplicate noted (not introduced):** `UNIT_POWER_UPDATE` is defined in BOTH
    aq.lua (real handler) and SkuCore/Core.lua:2062 (empty stub). TOC loads Core.lua before
    aq.lua, so aq's real handler has ALWAYS won — the Core.lua stub is dead code. The codemod
    moved BOTH defs onto the `Aq` table with identical load-order precedence, so behaviour is
    byte-identical (same as the E1 UNIT_SPELLCAST_INTERRUPTED core-stub-vs-handler case). Left
    as-is to preserve behaviour; a cleanup can delete the dead stub later.
  - Verified no aq method uses its own `self` to reach SkuCore. All 4 files luaparser-clean.
    **In-game health/power-monitor test pending.**

- **W4 Phase E — E1b (hard-3), part 2 of 3: aqCombat extracted.** The 23
  `function SkuCore:aqCombat*` methods now live on the `aqCombat` module table;
  published handle `SkuCore.aqCombat` keeps external callers working. 72 in-file
  + 10 cross-file/cross-module rewrites (codemod) across 5 files: TurnToUnit (3)
  + SkuMob (3) + SkuZOptions (2) call `aqCombatGetSkuRaidTarget`/`Set*`/`Clear*`,
  and aq.lua references `aqCombatMenuBuilder` (menu) + a commented `aqCombatOnInitialize`.
  - **No AceEvent change:** aqCombat owns no AceEvent registrations — all its WoW +
    `SKU_*` events route through `SkuDispatcher` (dot-ref function values). The codemod
    rewrote register AND unregister sides identically (`SkuCore.aqCombat_X` →
    `aqCombat.aqCombat_X`), so the callback-table keys stay matched. Dispatcher invokes
    callbacks as `cb(SkuDispatcher, event, ...)`, so `self` inside these handlers was
    already SkuDispatcher (never SkuCore) — relocating the method's table changes nothing.
  - **Safe by construction:** verified none of the 23 methods uses its own `self` to
    reach SkuCore (the 3 flagged are inner-closure frame `self` + menu-entry `self`).
  - The `SetRaidTarget` hooksecurefunc (can't be unhooked; IsEnabled-guarded) and the
    combat hot path are untouched apart from the table the methods hang on. All 5 files
    luaparser-clean. **In-game combat/raid-marker test pending.**

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
- **W3 load-time profiling — measure what makes the /reload freeze long.** All in
  `Sku/Core.lua`'s perf block, building on the existing `Sku:MetricPoint` clock
  and `/skuperf`. Two complementary views:
  * **GENERAL (all addons, not just Sku).** `/skuperf addons` ranks every addon by
    load CPU (needs `scriptProfile`; the command enables it and asks for a
    `/reload`, same recipe as `/skuperf cpu`). `/skuperf mem` ranks every addon by
    memory with **no setup** — a no-scriptProfile proxy for load weight. Both
    top-30 + an all-addons total.
  * **SKU (which module / which phase).** `/skuperf modules` reports per-module
    init+enable time, captured automatically by **wrapping
    `AceAddon:InitializeAddon`/`EnableAddon`** (no per-file instrumentation).
    InitializeAddon is non-recursive (clean per-module init); EnableAddon recurses
    into child modules, so a per-depth stack subtracts child time to report clean
    SELF time. AceAddon is shared by all Ace3 addons, so other addons' modules are
    timed too. Results in `Sku.PerfModules`, snapshotted to `Sku.PerfModulesLoad`
    at first PEW so post-login toggles can't skew the reading.
  * **Coarser timeline.** Added milestones `ADDON_LOADED (Sku files compiled)` (gap
    from `t0`/Core.lua = the file-load+compile cost where the big SkuDB tables are
    paid) and `first frame after PEW` via `C_Timer.After(0)` (≈ where the visible
    freeze ends).
  * **Auto-capture** at first PEW persists load + modules + mem (+ addons when
    scriptProfile is on) to the `SkuDebugLog` ring — readable out-of-game after a
    `/reload` with the generic `_readperf.py` (no parser change needed). New
    subcommands wired into `/skuperf` and `/skuperf all`. luaparser syntax-gated;
    in-game test pending.
- **W3 load-time: waypoint cache streamed off the freeze + route data deferred.**
  Full details and the diagnostic-tooling inventory live in `LOAD-PERF-NOTES.md`.
  Summary: `SkuNav:CreateWaypointCache` (the single biggest Sku login cost) now
  builds in a coroutine that yields ~10 ms/frame, streaming the whole ~3.36 s of
  work (creatures+objects+custom+links) *after* first-frame instead of blocking
  login (~1.5 s genuinely off the freeze; the rest, previously post-login timer
  chunks, now smoothed). PEW calls it async; all other callers stay synchronous.
  A signature bug (`aAsync` not declared) had made the whole thing a silent no-op
  until fixed. Also: route data files wrapped as deferred `loadstring` builders
  (`_wrap_deferred.py`) built on first nav use via a new `Sku:EnsureData` facade
  (`SkuDeferredData.lua`); a stale-link nil-index in `LoadLinkDataFromProfile`
  guarded (was silently aborting the coroutine tail). Findings: SkuQuest login
  DB-fix+merge is negligible (~14 ms, ruled out); the residual ~0.7 s route
  construct is an atomic `loadstring` not worth deferring as-is (options A/B/C in
  the notes). Diagnostics kept for future sessions (`/skuperf files|modules|
  addons|mem`, `SkuDebugLog.wpcResult`, the `_ps*` stubs).
