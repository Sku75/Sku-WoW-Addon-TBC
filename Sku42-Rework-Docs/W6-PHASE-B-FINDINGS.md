# W6 Phase B — high-level cleanup findings

## EXECUTION STATUS (updated 2026-07-07) — read this first on a cold start

This started as an approval gate; much of it is now executed. Progress is logged
in memory note `sku42-w6-cleanup` and in the git log (commits prefixed `W6-B`).
Per-finding status:

- DONE & in-game verified: the "step-up after setting a value" core fix (was the
  real felt bug — stay on the entry, step-up now opt-in via `stepUpAfterSelect`).
- DONE, committed, awaiting by-ear verify: #1, #2, #3, #4, #5, #6, #7, #8, #9,
  #10, #11 (Tier 1+2); #12 (SkuVoice←SkuChat provider seam); #14 (foundation:
  id-first SlashFunc + FindAncestorById + root-entry ids; migrations: Macro &
  friends re-pins, SkuAuras aura-manage path de-localized); #16 (SkuNav.Geo
  extracted to SkuNav/Geo.lua + 61 callers repointed); SkuBeacon Bug 2 + the
  table.remove-in-ipairs quirk.
- FALSE POSITIVE (no change): Bug 1 (quick-select defaults resolve fine via the
  locale table; slot 3 has a dedicated handler).
- DECLINED as unsafe: #13 (SkuAdventureGuide is NOT loaded — not in Sku.toc — so
  moving the wiki reader into it would break the live link path; corollary: #6 is
  currently inert but harmless).
- DELIBERATELY DEFERRED with reason: the "Local"-window descend-by-label paths
  (stable labels, dynamic window nodes, higher risk than reward).
- DONE, committed, awaiting by-ear + instance-/reload verify: **#15**
  (ChunkLoader readiness registry, the risky one). Inverted: added
  `Sku:RegisterBuildStep{name,after,once,run}` + a generic scheduler
  `SkuDBRunReadySteps` in ChunkLoader (runs each step after every family and
  once at the end, firing it the moment its `after` families are ready). The
  three hardcoded tails moved into their owning modules — SkuNav's wpc trigger
  (once=false, self-guards on wpcPendingArgs, keeps the late-request safety
  net), SkuQuest's quest tail (after all four families, ctx.yield between the
  pcall'd sub-steps), SkuAuras's value lists (after items+spells). Budget:
  unified via `Sku:RegisterBuildWorker(name, isAliveFn)` +
  `Sku:BuildFrameBudgetMs()` (150 / live-worker count) — each side owns its own
  liveness probe, so neither names the other's coroutine. The yield-across-pcall
  landmine is preserved (steps pcall their own work, ctx.yield only at top
  level). Behavior-preserving; only harmless timing shift = the quest tail now
  fires after the items family instead of after spells (verified no spell dep in
  BuildQuestZoneCache/UpdateAllQuestObjects). Registry infra lives in
  SkuDeferredData.lua (loads before all consumers).
- DONE, committed, awaiting by-ear verify: #17 (SkuDispatcher per-callback
  error isolation) — wrapped the bare `callbackFunc(...)` in the dispatch loop
  (SkuDispatcher/Core.lua:63) with `pcall` so one subscriber's error no longer
  aborts the loop and starves the later SkuCore-family callbacks; logs once to
  SkuErrorLog("skuDispatcher") + dprint and continues. Behavior-preserving on
  the happy path.
- DONE, committed, awaiting by-ear verify: #18 (SkuBeacon text-input-frame
  registration API — Sku frames now register at creation, only Blizzard globals
  are lib defaults; MINOR bumped 2→3), #19 (deleted dead CollectString + extracted
  shared SkuVoice:TokenizeNumberToAudio for the two live paths, behavior-preserving
  via a "btts"/"audio" mode — the >13000 integer-ladder divergence kept as-is,
  not unified, pending a by-ear decision), #20 (removed dead StopAllOutputs comment
  block; the OutputString dead `if engine then` guard → plain `do` block; SkuTTS
  font paths SkuCore→Sku), Bug 3 (SkuAuras/sharing.lua tDeepCopy delegates to the
  widget-safe SkuUtil.TableCopy), Bug 4 (folded into #20's OutputString engine fix —
  a truthy engine no longer silently mutes).
- STILL OPEN (not started): the #14 leftover "Local"-window label paths
  (deliberately deferred). SkuAdventureGuide: LEAVE the code in (removed for perf,
  may never be re-added; harmless to keep). That closes the Phase-B/C review.

Original approval-gate text follows.

---

Status: (historical) AWAITING YOUR APPROVAL. Nothing here is applied. Produced by a 9-
dimension architectural review (each reviewer verified claims against real
source, not just the index) + a synthesis pass that deduped, ranked, and split
off suspected bugs. 33 raw findings became 20 ranked cleanups, 4 suspected bugs
(handled on a separate track — they change behavior), and 8 dropped candidates.

How to use this: read the numbered list, then tell me per item (or per tier)
keep / drop / discuss. Approved items execute in a later batched pass, one
coherent change-set per commit, behavior-preserving, with luaparser + /reload +
"speak what you hear" verification. The bugs are a SEPARATE decision because
fixing them is not behavior-preserving.

All 20 cleanups are behavior-preserving. "phase B" = architectural (this
workstream). "phase C" = a per-file item that surfaced here but belongs in the
Phase C pass. Risk/effort are the reviewer's estimates.

---

## Tier 1 — low-risk small wins (safe to batch together)

### 1. Delete the dead Libs/_AceConfig-3.0 duplicate  [dead-code, risk low, effort small]
- Now: `Libs/_AceConfig-3.0` is a second copy of AceConfig-3.0 that nothing
  loads — embeds.xml only includes `Libs/AceConfig-3.0`, no TOC line, no XML
  include, repo-wide grep for `_AceConfig` returns zero hits. Identical to the
  live lib except one file, same MINOR/rev. ~104K of stale fork.
- Gain: pure ballast gone; removes the trap of someone editing the dead copy.
- Do: delete the directory. No TOC/embeds change needed.

### 2. Remove no-op SkuAudioData/Core.lua — also fixes a hidden frame collision  [dead-code, risk low, effort small]
- Now: the file does nothing (creates a frame, unregisters its own events on
  first fire). Worse, its frame is mis-named `SkuCoreaqCombatControl`
  (copy-paste) and it loads at Sku.toc line 10 BEFORE SkuCore, so it creates
  that global first. `SkuCore/aqCombat.lua:431` then does
  `_G["SkuCoreaqCombatControl"] or CreateFrame(...)`, so aqCombat's real combat
  control frame is silently the leftover audio-data frame, not its own.
- Gain: drops a dead file AND removes a real hidden global-name collision so
  aqCombat owns its frame.
- Do: delete the file + its TOC line 10; aqCombat builds its own frame on first
  use. Verify: login + a combat cycle, threat output still works.

### 3. Consolidate the four+ divergent TableCopy deep-copy helpers into SkuUtil  [duplication, risk low, effort small]
- Now: the widget-safe deep-copy `TableCopy(t, deep, seen)` is byte-identical
  in three places (SkuAuras/Core.lua:282, SkuAuras/Options.lua:17, the
  MenuMT.__add closure at SkuZOptions/templates.lua:13 — re-created every __add
  on the hot menu path) plus public `SkuOptions:TableCopy`
  (SkuZOptions/Core.lua:4299). All share the subtle safety-critical skip
  (`type(v)~='userdata' and k~='frame' and k~=0`) that avoids copying live frame
  refs. A fifth variant `tDeepCopy` (SkuAuras/sharing.lua:28) has DIVERGED — it
  omits the skip (see Bug 3).
- Gain: the frame-skip is safety-critical and subtle; a fix in one copy misses
  the others, and sharing.lua already drifted. SkuUtil is the W4 home, loads
  before every module.
- Do: add `SkuUtil:TableCopy`; repoint the three locals + SkuOptions:TableCopy
  to delegate. Decide the sharing.lua switch explicitly (Bug 3).

### 4. Move the waypoint TitleBuilder out of the generic menu template into SkuNav  [entanglement, risk low, effort small]
- Now: `templates.lua` is the generic menu-node prototype inherited by EVERY
  node, yet it holds `SkuOptions:BuildMenuSegment_TitleBuilder` (lines 598-786,
  ~24% of the file) — a SkuNav-domain waypoint-naming submenu reaching into
  SkuNav, SkuQuest, SkuDB internals and Glossary1. It has exactly ONE caller
  (SkuNav/Options.lua:528).
- Gain: removes the heaviest cross-module coupling from the file every menu node
  inherits; templates.lua stops depending on SkuDB/SkuNav/SkuQuest internals.
- Do: relocate the function to SkuNav, update the one call site. (The internal
  alphabetical-list duplication ~727-749 vs ~760-779 is a Phase C follow-up.)

### 5. Move shared coin/time formatters into SkuUtil  [entanglement, risk low, effort small]
- Now: `SkuGetCoinText` and `SkuEpochValueHelper` are file-scope globals in
  SkuCore/auctionHouse.lua (1451, 1479) but are general formatters used
  cross-module (SkuGetCoinText by LocalMenu.lua; SkuEpochValueHelper by
  friends.lua and SkuZOptions/Core.lua). No AH dependency, yet their existence
  is tied to a toggleable feature module loading.
- Gain: correct ownership; removes the implicit "AH file must load first".
- Do: move both to SkuUtil (names unchanged = zero caller edits). Grep-confirm
  no shadowing definition first.

### 6. Migrate SkuAdventureGuide onto the W1/W2 settings pattern  [consistency, risk low, effort small]
- Now: the only module that skipped W1/W2. Core.lua:229/234 reads raw
  db.global/db.profile paths; Options.lua has 13 inline get/set closures, never
  calls SkuSettings:Register, and builds its menu with the legacy 3-arg
  IterateOptionsArgs (line 181, aModule=nil, so every node hits the
  non-skuManaged fallback). Its defaults ARE already registered.
- Gain: closes the last gap in an otherwise uniform settings surface; ~5 keys.
  Behavior identical (all profile scope except seenLinksHistory = global, which
  Sub's scope-override handles).
- Do: add SkuSettings:Register, delete the inline closures, pass Sub +
  module name at line 181, convert the two Core reads. Verify: toggle each
  Wiki>Options entry + /reload.

---

## Tier 2 — low-risk, small-to-medium (still safe, a bit more surface)

### 7. Relocate route import/export to SkuNav; reconcile the dead importExport.lua  [split-or-merge, risk low, effort medium]
- Now: `SkuOptions:ImportWpAndLinkData`/`:ExportWpAndLinkData`
  (SkuZOptions/Core.lua:6609, 6723) serialize SkuNav's SessionRouteData — pure
  SkuNav route logic stranded in the menu framework (a big older Export also
  sits dead in a block comment 6675-6714). Meanwhile SkuNav/importExport.lua
  (53 lines) is dead: the seed's "owns SkuNav's AceAddon" claim is FALSE
  (Core.lua creates SkuNav first at TOC line 127; importExport loads LAST at
  133, so its NewAddon is a no-op), and its only content `tConvert()` is never
  called and iterates a never-assigned global. Real callers: SkuNav/Options.lua
  1236/1248 and SkuZOptions/Core.lua 253/257.
- Gain: puts route (de)serialization where the data model lives; only 4 call
  sites.
- Do: move both functions into SkuNav (either give importExport.lua real
  purpose, or move to SkuNav/Core.lua and delete importExport.lua + its TOC
  line 133); repoint the 4 sites; drop the dead commented Export + tConvert.
  Verify: a route import/export + a nav action.

### 8. Remove the dead per-read TTS-engine selector (aEngine / ttsEngine)  [dead-code, risk low, effort medium]
- Now: SkuTTS threads an `aEngine` param through 9 public methods into
  ReadLineNumber/ReadLinkNumber, but at both leaves the consuming branch is
  commented out (SkuTTS-1.0.lua:361-365, 196-200), so output ALWAYS goes through
  Blizzard TTS. The value comes from `currentMenuPosition.ttsEngine` at ~16
  sites in SkuZOptions/Core.lua + 4 in SkuChat/Core.lua; the only non-nil set is
  SkuCore/Options.lua:1838/1901 (=2). The whole surface switches nothing.
- Gain: deletes ~25 dead arg-passes + 9 signature slots; makes the single
  speech path explicit instead of advertising a choice that does nothing.
- Do: drop the commented branches (keep engine=1), remove the param from the 9
  methods + forwards, delete the ttsEngine args + the `=2` assignments. Verify:
  read a tooltip/wiki line-by-line (unchanged speech).

### 9. Freeze and document ONE menu-construction style  [consistency, risk low, effort small]
- Now: two styles coexist — imperative InjectMenuItems (1053 calls across 27
  files) vs declarative SkuMenu:BuildNode/Build (~6 sites), and even those build
  bodies drop straight back to IterateOptionsArgs/InjectMenuItems. A mid-flight
  W2 "later phase" ambition.
- Gain: expanding the declarative layer buys almost nothing; the real cost is
  ambiguity for contributors. The fix is a DECISION, near-zero code.
- Do: document BuildNode/Build as the composition SHELL with IterateOptionsArgs
  as the leaf renderer — one paragraph in SkuMenu.lua's header. Do NOT convert
  the 1000+ existing calls.

### 10. Close the RegisterModule "move into owning modules" TODO as won't-do  [split-or-merge, risk low, effort small]
- Now: SkuMenu.lua:270-275 has a TODO to scatter the ~11 centralized root-menu
  RegisterModule calls into their owning modules. Builders resolve lazily by
  global name at open time, so scattering gains nothing and makes "what is the
  root, in what order" un-greppable. One real inconsistency: ModuleManager.lua:163
  registers "Features" from outside SkuMenu.lua.
- Gain: doing the TODO is the cosmetic file-shuffling you dislike; centralization
  keeps the root layout one reviewable manifest.
- Do: replace the TODO with a rationale that centralization is intentional;
  optionally move the Features registration in for consistency. (Collapsing the
  same-file resolveLabel/specLabel dup is Phase C.)

### 11. Correct the SkuDispatcher "central broker" doc; do NOT normalize raw events  [consistency, risk low, effort small]
- Now: CLAUDE.md presents SkuDispatcher as the mandatory event broker, but the
  reality is a deliberate hybrid: the dispatcher fan-out is used ONLY by the
  SkuCore object family (because several SkuCore sub-files must subscribe to the
  same event, which one AceEvent object can't), plus SKU_* custom events as the
  real cross-module bus. Every other module registers its WoW events directly
  via its own AceEvent object — idiomatic Ace3.
- Gain: forcing ~15 modules through one dispatcher would be negative-gain churn.
  The only defect is the stale doc/mental-model, which risks a contributor
  "fixing" the correct raw registrations.
- Do: amend the CLAUDE.md line + the index to describe the deliberate hybrid.
  No source change.

---

## Tier 3 — medium architectural (worth doing, more surface)

### 12. Break SkuVoice-1.0's direct dependency on SkuChat's settings schema  [entanglement, risk low, effort medium]
- Now: SkuVoice-1.0 (a LibStub library, the low-level audio engine) reads a
  feature module's saved settings directly —
  `SkuOptions.db.profile['SkuChat'].WowTtsVoice/Speed/Volume/Tags/...` at ~10
  sites plus SkuChat.WowTtsVoices. A rename of SkuChat's TTS keys breaks the
  voice engine silently (string key, no failure signal).
- Gain: a reusable lib should not reach up into a feature's config namespace.
  Decoupling makes SkuVoice depend only on params handed to it.
- Do: give SkuVoice a config seam it owns — SkuChat pushes TTS params via
  `SkuVoice:SetBlizzTtsParams{...}` on load + on settings change. Verify:
  menu-TTS + per-channel-voice paths still speak.

> UPDATE 2026-07-06 — DECLINED as UNSAFE during execution. SkuAdventureGuide is
> NOT loaded: it has no line in Sku.toc (and never did, per `git log -S`), is not
> a separate installed addon, and every reference to it is guarded with
> `if SkuAdventureGuide then` — so the `SkuAdventureGuide` global is nil in the
> current build. The three reader functions live in SkuZOptions/Core.lua (always
> loaded) precisely because the module is optional; their LIVE callers are the
> TTS link-follow keys in SkuZOptions (Core.lua 1784/1799/2926/2940), which fire
> for any tooltip with links. Moving them into the unloaded module would make
> `SkuOptions:LoadLinkDataToTooltip` et al. undefined and break live link
> reading. The reviewer's premise (the module "owns" the feature) was wrong.
> Corollary: finding #6's SkuAdventureGuide settings migration is currently inert
> (that file never executes) — harmless, but SkuAdventureGuide is effectively dead
> code pending a maintainer decision (re-add to the TOC to enable it, or remove).

### 13. Consolidate the wiki article-reader into SkuAdventureGuide  [split-or-merge, risk medium, effort medium]
- Now: the wiki "read an article" engine (GetLinkFinalRedirectTarget,
  FormatAndBuildSectionTable, LoadLinkDataToTooltip) lives in
  SkuZOptions/Core.lua:3326-3519, but the wiki MODULE is SkuAdventureGuide. Its
  menu builder already calls UP into SkuOptions:GetLinkFinalRedirectTarget etc.,
  so the feature bounces across two files. Other callers: the TTS link-follow
  keys in SkuZOptions (Core.lua 1784/1799/2926/2940).
- Gain: consolidates the whole wiki feature into its owner; SkuZOptions/Core
  sheds ~193 lines of a foreign concern; removes the cross-module cycle.
- Do: move the three functions to SkuAdventureGuide; repoint ~6 call sites
  (runtime calls, so load order is fine). Verify: read a wiki article + follow a
  link by ear.

---

## Tier 4 — large architectural DECISIONS (design first, do incrementally, gate each)

### 14. Give menu nodes a stable id; stop navigating by localized label + fixed depth  [entanglement, risk medium, effort large]
- Now: the menu has no language-independent node identity, and two fragile
  idioms recur. (a) DESCEND-BY-LABEL: SkuOptions:SlashFunc walks a comma path
  matching only `fields[x]==lower(node.name)`; a miss is a SILENT no-op. ~18
  call sites pass localized-label paths, some baked as a single localization key
  encoding a whole path (e.g. `L[",SkuAuras,Auren,Auren verwalten,"]`) that must
  be hand-synced across locales. (b) UP-WALK-BY-FIXED-DEPTH:
  `.parent.parent(.parent)` reaches in ~20 SkuAuras/Options sites plus Macro,
  friends, aq, LocalMenu. SkuAuras:217 already found the better pattern (walk up
  to a node with a known internalName) but never generalized it.
- Gain: this is the known W7 fragility and it is NOT hypothetical — W7 already
  broke live paths (see Bug 1, the four dead quick-select defaults). A label
  miss is silent and the user is blind, so breakage is invisible except by ear.
  Removes a whole class of locale-fragile breakage. Honest caveat: with W7
  stable, most payoff is future-safety + killing latent dead paths, not many
  live breakages today.
- Do (INCREMENTAL, not big-bang): (a) add an optional stable `id` on
  SkuGenericMenuItem, set for the handful of STRUCTURAL ANCHOR paths (root
  entries carry their SkuMenu registry id); (b) make SlashFunc match id first,
  label second (pure superset, zero migration pressure); add NavigateToId;
  (c) migrate the ~15 static-path sites to id paths one module at a time,
  verified by ear; (d) add node:FindAncestorById(id) to replace fixed-depth
  reaches. Bug 1 can be fixed immediately as part of step (a)/(c).

### 15. Invert ChunkLoader's hardcoded feature-build tails to a readiness registry (+ unify the frame budget)  [entanglement, risk medium, effort large]
- Now: SkuDB/ChunkLoader.lua (the low-level DB streamer) hardcodes and drives
  three feature modules' post-login build tails by reaching into their internals
  — SkuNav:CreateWaypointCache + wpcPendingArgs, four SkuQuest build calls,
  SkuAuras:BuildAttributeValueLists + attributeListsPending — an upward
  inversion where the DB layer knows quest/aura/nav construction order and
  private pending-flags. Coupled to this, the 150/75 ms build budget lives twice
  (ChunkLoader SkuDBBudgetMs 90-94 and SkuNav tWpcBudgetMs 476-488), each peeking
  at the other's private coroutine/flag.
- Gain: the deepest entanglement in the load path — adding/renaming any
  per-module build step means editing the DB loader. Inverting it (families
  publish "ready"; each module registers its own build step) restores ownership
  and makes ChunkLoader a generic scheduler.
- Do: DESIGN item, not a naive extract. HARD CONSTRAINT: each step must run
  frame-sliced inside the master coroutine with SkuDBMaybeYield between pcall'd
  sub-steps (Lua 5.1 can't yield across pcall — this exact thing caused the
  2026-07-06 reload crash). Add `Sku:RegisterBuildStep(afterFamilies, fn)`;
  keep the all-four-families guard for the quest tail + per-family failure
  isolation; add a shared budget arbiter so neither side names the other's
  coroutine. Gate behind the measurement tooling + reload/instance re-test.

### 16. Extract SkuNav's geo/map service into its own file and repoint callers  [split-or-merge, risk medium, effort large]
- Now: SkuNav/Core.lua (4540 lines) fuses the beacon-nav runtime with a
  stateless geo/map-math service (GetWorldCoordinatesFromZone, GetCurrentAreaId,
  GetAreaData, area/UiMap id conversions, GetDirectionTo, Distance, etc.). W4
  already declared a `SkuNav.Geo` delegate facade (Core.lua:4532-4540) but
  deferred extraction AND repointing. This geo service is the addon's single
  largest inter-module edge: SkuQuest→SkuNav = 126 qualified accesses (W4 E3
  audit, the biggest), plus SkuCore/SkuMob. Today SkuQuest depends on the whole
  beacon engine just to ask "what area am I in".
- Gain: real ONLY if callers are repointed to SkuNav.Geo — moving functions
  while callers still write `SkuNav:GetAreaData` buys almost nothing (W4's
  split-alone lesson). Done fully it gives the biggest coupling a stateless,
  testable boundary.
- Do: DECISION. Option 1 (full): move the ~10 geo fns + inlined mapData to a new
  SkuNav/Geo.lua, keep thin SkuNav: forwarders, repoint SkuQuest/SkuCore/SkuMob
  (the 126 sites are the bulk of the risk). Option 2 (low-risk): extract the
  file only, keep SkuNav: names — but that's cosmetic unless callers move. Keep
  wpId codec + WaypointCache-touching helpers in Core.

---

## Small extra (Phase B, low risk)

### 17. Add per-callback error isolation to the SkuDispatcher dispatch loop  [bad-practice, risk low, effort small]
- Now: the per-event closure (SkuDispatcher/Core.lua:61-68) calls each callback
  with a bare `callbackFunc(...)` inside `for ... in pairs(...)`. If one raises,
  the loop aborts and every later callback silently never runs for that dispatch
  — one faulty subscriber can suppress unrelated SkuCore-family features
  (health, combat, focus, dial-targeting) until reload. (Reviewer verified the
  two adjacent seed concerns are NOT defects: arg-shape is identical across the
  WoW and SKU_ paths, and the fire-once mid-iteration Unregister is Lua-legal.)
- Gain: the one genuine dispatcher fragility; xpcall overhead is negligible
  (hot per-frame UNIT_HEALTH/UNIT_POWER register raw in aq.lua, not here).
- Do: wrap the call in xpcall routing to SkuErrorLog/dprint. Behavior-preserving
  on the happy path.

---

## Deferred to Phase C (surfaced here, but per-file — do in the C pass)

### 18. SkuBeacon: registration API instead of hardcoded editbox names  [entanglement, risk low, effort small]
- SkuBeacon-1.0 suppresses its key recognizer while typing by walking a
  hardcoded list of feature-module frame globals (SkuAuctionConfirmEditBox,
  SkuOptionsEditBox*, SkuNavMM*, ChatFrame1EditBox, MacroFrame — lines 102-110).
  A low-level lib thus knows auction/options/nav/macro frame names.
- Do (Phase C): add SkuBeacon:RegisterTextInputFrame(name); modules register
  their editbox at load; keep Blizzard globals as built-in defaults.

### 19. De-duplicate the number-to-audio tokenizer in SkuVoice; drop dead CollectString  [duplication, risk medium, effort medium]
- The number-to-audio-word block is copy-pasted three times in SkuVoice-1.0
  (OutputStringBTtts ~600-655, OutputString ~965-1011, CollectString ~1168-1208)
  and they have DIVERGED. CollectString has ZERO callers (dead, carrying a stale
  copy).
- Do (Phase C): delete CollectString (pure win); extract
  SkuVoice:TokenizeNumberToAudio for the two live paths. The float branch differs
  intentionally (Blizzard TTS voices decimals) — confirm a >13000 number by ear
  before committing (the integer ladder diverged accidentally).

### 20. Sweep residual half-deleted scaffolding in the audio libs  [dead-code, risk low, effort small]
- SkuVoice StopAllOutputs is entirely inside a `--[[ ]]` block (never defined,
  references undefined tValue, called nowhere); the OutputString `if engine then`
  body is commented out leaving a live dead guard; SkuTTS font paths (18-19)
  point at a non-existent `Interface\AddOns\SkuCore\Libs\SkuTTS-1.0\fonts\...`
  (harmless — LSM falls back; affects only the sighted debug pane).
- Do (Phase C): delete the commented StopAllOutputs + dead OutputString branch;
  correct the SkuTTS font path to `...\Sku\Libs\SkuTTS-1.0\fonts\...`.

---

## Suspected BUGS (SEPARATE track — fixing them changes behavior, decide apart from cleanup)

### Bug 1 — FALSE POSITIVE (verified 2026-07-06 during execution, no fix made)
- Original claim: all four default MenuQuickSelect keybinds are dead after the W7
  root rename, because the default paths start with "SkuNav"/"SkuCore".
- Verification result: NOT a bug. The reviewer read the path KEY but missed two
  layers of indirection:
  1. The defaults are `L["SkuNav,..."]`, and the locale table maps those keys to
     the CURRENT labels: deDE.lua:2364-2366 resolve slots 1/2/4 to
     "Navigation,Wegpunkt,Auswählen,Aktuelle Karte Entfernung" /
     "Navigation,Route,Route folgen,Ziele Entfernung" / "Navigation,Alles
     abwählen" (enUS to the English equivalents). Every deep segment exists in
     the live SkuNav menu (L["Waypoint"]="Wegpunkt", L["Auswählen"],
     L["Aktuelle Karte Entfernung"], L["Route"], L["Route folgen"],
     L["Ziele Entfernung"], L["Deselect all"]="Alles abwählen"). So slots 1/2/4
     resolve to valid current paths and fire through the generic loop
     (SkuZOptions/Core.lua:2180-2185).
  2. Slot 3 (SKU_KEY_MENUQUICK3) is intercepted at SkuZOptions/Core.lua:1335-1340
     — it calls SkuCore:ActionBarsShowHandler() and `return`s BEFORE the generic
     firing loop, so the stale "Core,Aktionsleisten" default string is never
     used. The comment there (1328-1334) explicitly documents this as the W7
     replacement for that stale path.
- Only residue (cosmetic, not fixed): slot 3's stored default string is now dead
  data (never read) and would look meaningless if a user opened the
  MenuQuickSelect3 setting. Harmless; left as-is pending a decision. The id-based
  navigation (cleanup #14) is still the durable hardening for this whole class.

### Bug 2 (HIGH). SkuBeacon OnUpdate: a transient nil player position permanently destroys the beacon and starves later beacons
- The single OnUpdate pump (SkuBeacon-1.0.lua:146-159) reads UnitPosition("player")
  per beacon; GetDistance returns nil when a coord is nil; on nil it does
  `DestroyBeacon(...); return`. Two defects: (1) the `return` exits the WHOLE
  OnUpdate, so every remaining beacon that frame is skipped — one bad reading
  silences the others; (2) UnitPosition legitimately returns nil during loading
  screens, instance transitions and taxi/vehicle rides, so a transient state
  permanently tears down the beacon the player was homing in on, and it never
  comes back. Compounding: DestroyBeacon does table.remove inside ipairs (487),
  which can skip entries.
- Fix: on nil distance skip just this beacon this frame (keep it alive); reserve
  DestroyBeacon for genuine end-of-life; make the removal index-safe. This is the
  core audio-nav engine for a blind player — test carefully.

### Bug 3 (MEDIUM). SkuAuras/sharing.lua tDeepCopy can retain live frame refs in aura snapshots
- The divergent `tDeepCopy` (sharing.lua:28) does a plain recursive copy WITHOUT
  the frame/userdata/slot-0 skip the widget-safe TableCopy uses everywhere else.
  It snapshots aura config tables (sharing.lua:73/137) — the same tables other
  paths copy WITH the skip. So a shared/persisted aura snapshot can carry live
  frame references, potentially serializing/leaking widget handles into saved
  config.
- Fix: switch to the widget-safe copy (surfaced by cleanup #3 — decide the switch
  explicitly rather than folding it in silently).

### Bug 4 (LOW). SkuVoice OutputString / OutputStringBTtts handle `engine` inconsistently — latent silent mute
- The twin functions treat the same 8th positional `engine` param differently:
  OutputStringBTtts uses it as a live force-Blizzard-TTS flag; OutputString's
  `if engine then` body (831-869) is commented out, leaving a live
  `if engine then --[[dead]] else`. A caller reaching OutputString with a truthy
  engine would be silently muted. The guard at :507 keeps engine falsy on the
  normal path today, so it does not fire — but it is a latent trap.
- Fix: make OutputString's engine handling consistent with OutputStringBTtts (or
  remove the dead branch). Overlaps cleanups #8 and #20.

---

## Considered and DROPPED (recorded so Phase C doesn't re-litigate)

- Split the other large files (SkuCore/Core, auctionHouse, aq, LocalMenu): none
  clears the W4 "splitting alone buys nothing" bar. auctionHouse is deliberately
  single-file with documented section ordering; aq is one cohesive monitor;
  LocalMenu is uniform Build_* mirrors; Core.lua is already W4-reduced to genuine
  always-on core. ("The file is big" is not a reason.)
- Mass-convert the remaining 268 raw SkuOptions.db.profile reads to
  SkuSettings:Sub: cosmetic — verified those are overwhelmingly cross-module
  reads into a FOREIGN namespace with no fragile `x = x or {}` idiom to remove.
  The one genuine own-settings straggler is SkuAdventureGuide (cleanup #6). The
  real entanglement subset (SkuQuest driving SkuNav's live metapath, utilities
  reading SkuNav.tNames) is an accessor-API problem handled by the entanglement
  items, not a Sub rename.
- templates.lua OnEnter hardcodes three feature sound-preview domains: marginal;
  fold in opportunistically only if cleanup #4 is already touching templates.lua.
- Replace inline `GetLocale()=="deDE"` label ternaries with Sku.L keys: 37
  occurrences across 29 files, all display correctly today (ships deDE+enUS);
  belongs to a single localization cleanup, not a menu task. Phase C at most.
- voiceOutput.lua SpeakText monkey-patch dedupe / AudioDevice merge: the global
  SpeakText wrap is the correct design (catches Blizzard/other-addon calls a
  SkuVoice-internal sync would miss) — must NOT be churned. Only a 7-line inline
  dedupe remains; Phase C at most.
- Remove the perf per-file-stamp scaffolding (SkuPerfFileStamp.lua + six
  _ps*.lua): removable one-shot, but still wired and working and degrades
  gracefully. Load profiling shipped 2026-07-05 so it is likely closable — but
  this is a maintainer go/no-go on a working tool, not a defect. (Ask me if you
  want it pulled.)
- Remove SkuDBTools.lua: 516 isolated lines of re-runnable DB-verification
  tooling (mirrors /skuperf) — recommended KEEP as a dormant diagnostic. Delete
  only if the DB layout is declared frozen.
- Remove SkuCore/DualSpecProbe.lua: seed was WRONG — it is a user-toggleable
  shipped feature ("Dualspec-Test", /skuspec) that helps blind users on custom
  TBC servers find their dual-spec switch mechanism. KEEP.
