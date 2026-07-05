# Loading-time optimization — situation report and options (2026-07-05)

Companion to LOAD-PERF-NOTES.md (the W3 handoff). Sources: fresh code research
in this repo, plus deep-dives into Questie (installed source) and WowVision.
No tables in this doc by design (screen-reader formatting).

## TL;DR

- The mega-freeze is not caused by how MUCH data Sku ships but by HOW it ships:
  ~77 MB of SkuDB executes as real Lua table constructors during the loading
  screen. Questie ships even more raw data (228 MB on disk, ~6 MB active per
  flavor) but as inert string literals plus a compile-once binary cache in
  SavedVariables — near-zero login cost after the first run.
- Our /skuperf harness measures Sku's own controllable slice (~2.3 s at the
  time) honestly, but it never measured the full felt wall clock, other addons
  (DBM ~40 modules, Details, WeakAuras, AtlasLoot, Auctionator, Questie), the
  Blizzard world load, or the GC/memory pressure that lingers AFTER load.
  So "measured win" and "felt load time" were never the same quantity.
- The 2-3 s second freeze after the screen fades has three concrete suspects,
  all fixable: the SkuAuras list build at PLAYER_ENTERING_WORLD, the atomic
  route-DB loadstring landing at PEW on the /reload path, and the GC churn
  from the freshly allocated data tables (Questie explicitly forces a GC to
  avoid exactly this spike).
- Empty-list risk in the waypoints menu: REAL and confirmed. There is no
  readiness flag. A fast user gets a silently partial or empty list, and
  "Nahe Routen" stays empty until the very last step of the async build
  (link resolution) finishes.
- Recommended sequence: (1) one evening of honest A/B wall-clock measurement,
  (2) the cheap post-load-freeze fixes plus waypoint readiness/priority work,
  (3) the Questie-style DB rework in two phases. Details below.

## 1. What Sku does at loading today

Three phases. Numbers from LOAD-PERF-NOTES.md (2026-06-28 measurement) and
fresh code reading.

### Phase 1 — loading screen, file execution (~1.27 s measured, plus GC debt)
- Sku.toc force-loads 115 Lua files, 97.91 MB total. The bulk is SkuDB data
  executed as plain table constructors: WotLK creatures 7.5 MB, WotLK items
  7.3 MB, base creatures 5.6 MB, base items 5.4 MB, spells 5.1 MB, WotLK
  quests 4.9 MB, base quests 3.8 MB, objects 2.5+1.7 MB, and more.
  Roughly 77 MB of SkuDB actually executes (wiki.lua 27.7 MB and the Era tree
  are NOT in the TOC).
- The two route files (48 MB combined, ~100k waypoints) are already wrapped
  as deferred builders by the W3 codemod (_wrap_deferred.py) and do NOT
  execute here.
- Hidden cost not on our books: constructing those tables allocates a large
  Lua heap. The GC has to digest that during and after load. This is felt
  time that no stamp measures.

### Phase 2 — PLAYER_LOGIN, still behind the loading screen
- SkuNav:PLAYER_LOGIN -> LoadDefaultMapData -> Sku:EnsureData("routes"):
  one atomic loadstring of both route blobs, ~0.73 s, cannot be time-sliced
  (SkuNav/Core.lua:3227 -> 3274). Deliberately parked here so the loading
  screen hides it (fresh login only — see the /reload caveat below).
- Immediately after: a blocking loop that string.match-splits the "en§de"
  name of all 50,708 global waypoints (SkuNav/Core.lua:3276-3292).

### Phase 3 — PLAYER_ENTERING_WORLD and after (VISIBLE time)
- SkuAuras:PLAYER_ENTERING_WORLD builds its item/spell attribute lookup lists
  by iterating SkuDB.itemLookup and SpellDataTBC: ~0.32 s, atomic, right as
  the screen fades (SkuAuras/Core.lua:303-365).
- On /reload (no PLAYER_LOGIN), LoadDefaultMapData runs at PEW instead
  (SkuNav/Core.lua:3318) — meaning the 0.73 s route loadstring plus the 50k
  name-split loop land in VISIBLE time on every /reload.
- SkuNav:CreateWaypointCache(nil, true): the W3 win. ~3.36 s of work streamed
  in a coroutine at ~10 ms per frame, pumped once per frame via
  C_Timer.After(0, ...) (SkuNav/Core.lua:318-620). Takes ~6.5 s wall clock to
  finish; during that window the game runs but loses 10 ms every frame, which
  reads as sluggishness right after load.
- GC: no forced collection anywhere; the collector digests the login
  allocation spike incrementally over the first seconds of play.

## 2. What our measurement measures — and what it misses

The harness (/skuperf load, files, modules; auto-dumped to SkuDebugLog;
read by _readperf.py):
- Milestone timeline from Core.lua's debugprofilestart (Core.lua:141) through
  ADDON_LOADED, PLAYER_LOGIN, PEW, first frame after PEW.
- Per-file compile cost of the heavy data via the _psA.._psF stamp stubs
  using GetTimePreciseSec (advances during the loading screen).
- Per-Ace-module OnInitialize/OnEnable timing via the AceAddon hook.

What it does NOT capture — this is why the wins were not felt:
- Everything before Core.lua loads (Ace libs, SkuAudioData index, locales).
  Small, but unmeasured.
- Other addons' file parsing and their non-Ace event work. Only Ace OnEnable
  of other addons is visible, and only with scriptProfile on. This install
  runs DBM with ~40 modules, Details, WeakAuras, AtlasLoot, Auctionator,
  Questie and more. Details alone was ~1.8 s OnEnable in the notes.
- Blizzard's own world load between PLAYER_LOGIN and PEW: 0.6-4 s run-to-run
  variance per the notes — bigger than most of our wins, which is exactly why
  a 3-4 s measured improvement can vanish perceptually.
- GC and memory pressure after load (the inflated tables stay resident
  forever; nothing measures the collector's catch-up cost).
- The plain felt wall clock "press Enter at character screen -> can act".
  Notes put it at ~5-12 s total; our controllable measured share was ~2.3 s.

Conclusion the user already sensed: our numbers are correct but partial.
Before investing in the big rework, run the A/B protocol in section 6 once —
it produces the true blame split between Sku, the other addons, and Blizzard.

## 3. Why there is a NEW 2-3 s freeze after the loading screen

Three stacked causes, in likely order of contribution:
1. On /reload: the atomic 0.73 s route loadstring plus the 50k name-split
   loop moved into visible time (PEW path). On fresh login they hide behind
   the screen; on /reload they do not. If the second freeze is worse after
   /reload than after a fresh login, this is confirmed.
2. GC spike: the loading screen allocates hundreds of MB of tables; the
   incremental collector pays for it in the first seconds of play. Questie
   explicitly calls collectgarbage() at the end of init "to avoid a later
   lag spike" — we never do.
3. The waypoint-cache stream taxes every frame ~10 ms for ~6.5 s, on top of
   SkuAuras' 0.32 s atomic build at PEW and every other addon's PEW work.

## 4. What the role models actually do

### Questie (the data-heavy one — direct blueprint)
- DB files are giant STRING literals ("questData = [[return {...}]]"), not
  table constructors. Loading the file just stores a string: near-zero parse
  and zero table allocation at login.
- First login only: loadstring the strings, then transcode every record into
  a packed binary string plus an id->offset pointer map, both stored in
  SavedVariables (Questie.db.global.*Bin/*Ptrs). Cache key: addon version +
  UI locale + expansion. Every later login skips ALL of it — the raw strings
  are never even parsed again.
- Runtime reads are random-access: QuerySingle(id, key) seeks into the binary
  blob and decodes just the requested field via a skip map. The full database
  never exists as Lua tables in memory.
- All heavy work runs in a coroutine pumped by C_Timer.NewTicker(0, ...),
  yielding every 28-128 records, pausing entirely during combat
  (Modules/Libs/ThreadLib.lua, Database/compiler.lua, TICKS_PER_YIELD = 48).
- Readiness: Questie.started internally, Questie.API.isReady plus
  RegisterOnReady(callback) externally; every consumer bails early when not
  ready; staged chat progress ("[1/9] Loading database...") during the
  one-time compile.
- Cleanup: QuestieCleanup:Run() nils all raw data and calls collectgarbage()
  once at the end of init.
- Flavor gating via per-client .toc files: only the active flavor's DB files
  are ever loaded from disk.

### WowVision (the architecture one)
- Ships essentially no data (biggest Lua file is 60 KB of code); it consumes
  Sku's nav DB externally (OptionalDeps: Sku, reads _G.SkuNavData) and
  registers audio as file PATHS, never bytes.
- Two-phase enable: enable() does only cheap structural wiring (events, UI,
  commands), fullEnable()/onFullEnable() builds the expensive object graphs
  afterwards. Nothing heavy at file scope, ever.
- Post-login scans staggered with C_Timer.After tiers (0.01 s / 5 s / 10 s /
  40 s) instead of one big pass at PEW.
- All consumers guard on existence (self.root and ...), so half-initialized
  state is never announced. One shared OnUpdate frame with a built-in
  profiler.

## 5. The waypoints-menu questions, answered

Can a fast user hit empty lists for near points right now? YES — confirmed:
- All nav menus read the live, still-filling WaypointCache directly. There is
  no readiness flag anywhere (no SkuNav.loaded / dataReady), and no menu path
  calls EnsureWaypointCacheComplete. During the ~6.5 s async build a fast
  user gets a silently partial list or "Leere Liste".
- "Nahe Routen" is worst: it filters on links.byId, which is only populated
  by LoadLinkDataFromProfile — the LAST coroutine step. That list is
  guaranteed empty for the whole build, every login.
- Route search (GetAllMetaTargetsFromWp5) dereferences the start waypoint
  without a nil guard (SkuNav/Core.lua:804-807) — crash-safe in practice only
  because you can only select what the partial menu already listed.

Can we spread post-load loading further WITHOUT making the waypoints menu
unusable longer? Yes, via priority plus honesty rather than speed:
- Build order priority: current continent's creatures/objects first, then
  resolve links for the current continent, THEN stream the rest of the world.
  The near lists become correct for where the player stands within well under
  a second, and it stops mattering how long the rest takes. (The coroutine
  passes are confirmed freely re-orderable; only link resolution must follow
  the entries it links.)
- Readiness signal: set SkuNav.dataReady after link resolution; while the
  build runs, the near/route menus should say "Wegpunkte werden noch
  geladen" instead of pretending the list is empty, and volatileChildren
  already re-reads on navigation, so the list fills in live.
- With those two in place, the per-frame budget can even be LOWERED (10 ms ->
  3-5 ms) to kill the post-load sluggishness, because total build duration no
  longer hurts anyone.

## 6. Options, ranked

### Option 0 — measure the truth first (half an evening, do this before anything)
Establish the real felt numbers so the big investment targets the right half:
- Tiny stopwatch addon (loads first alphabetically, e.g. "!!LoadStopwatch"):
  stamps GetTimePreciseSec at its own file load and at first frame after PEW,
  speaks/prints the total and writes it to SavedVariables. Gives the true
  "loading screen + settle" wall clock per run.
- Four configurations, 3 runs each (variance!): everything off; only Sku
  family; everything except Sku family; everything on. That yields Sku's real
  share of the felt freeze versus DBM/Details/WeakAuras/Questie and Blizzard.
- One run with scriptProfile=1 and /skuperf addons for a full per-addon CPU
  ranking.
- Also record collectgarbage("count") at ADDON_LOADED / PEW / PEW+10 s to see
  the memory story (expected: several hundred MB from SkuDB).

### Option 1 — kill the post-load second freeze (small, days, high felt value)
- 1a. /reload path: on isReloadingUi, run EnsureData("routes") + the
  name-split loop as early as possible (start of reload's loading overlay)
  instead of at PEW; if it cannot be hidden, at least announce it ("Sku lädt
  Navigationsdaten") so the freeze is expected rather than mysterious.
- 1b. Chunk the SkuAuras PEW list build with the same coroutine pattern as
  the waypoint cache (it is a pure iteration; trivially sliceable).
- 1c. Chunk the 50k name-split loop the same way (also trivially sliceable).
- 1d. Forced collectgarbage("collect") once, at the end of login work while
  the screen is still up (Questie's trick), to convert the post-load GC churn
  into hidden time.
- 1e. Lower the waypoint-stream budget to 3-5 ms per frame once 1f exists.
- 1f. Waypoint readiness + priority (section 5): current-continent-first
  build order, dataReady flag, "wird geladen" announcement in near/route
  menus. This is also the answer to the empty-list problem and MUST accompany
  any further spreading.

### Option 2 — Questie-style DB rework, phase A: strings + streamed build
(medium effort, ~1-2 weeks incl. tooling; removes most of the loading-screen
freeze; memory unchanged)
- Regenerate every SkuDB asset file (creatures/items/spells/quests/objects,
  base + WotLK + SoD) from table constructors into string literals with
  builder functions, extending _wrap_deferred.py / the option-B chunker from
  LOAD-PERF-NOTES.md so each dataset is MANY small chunks (e.g. 500 records
  per builder) instead of one atomic loadstring.
- Stream all builders through one Questie-style init coroutine after login
  (ticker pump, combat pause, readiness flags per dataset via the existing
  Sku:EnsureData registry).
- Consumer audit required: today only "routes" is deferred; every consumer of
  NpcData/itemLookup/SpellDataTBC etc. assumes presence at file scope or
  OnEnable. Each needs either an EnsureData guard or to tolerate late data.
  This is the real cost of phase A — the data conversion itself is tooling.
- Also converts the route DB's 0.73 s atomic build into streamable chunks
  (the notes' option B), making it genuinely invisible on login AND /reload.

### Option 3 — Questie-style DB rework, phase B: compile-once binary cache
(large effort, several weeks; near-zero login cost forever AND cuts hundreds
of MB of resident memory)
- First login: parse the phase-A strings and transcode into packed binary
  blobs + pointer maps in SavedVariables, keyed by addon version + locale.
  Later logins never touch the raw data. Reads become QuerySingle-style
  random access; full-scan consumers (waypoint cache build) iterate the
  pointer map.
- Bonus with the same machinery: persist the FINISHED WaypointCache itself
  (serialized string blob in SavedVariables, keyed by version + locale), so
  the 3.36 s cache build also collapses to a one-time cost. Must be stored as
  a string blob, not a table — SavedVariables tables are themselves executed
  constructors at login and would re-import the original problem.
- Trade-offs: bespoke schema per record type; SavedVariables file grows by
  tens of MB (Questie accepts the same); logout write cost grows; corruption
  handling needed (cache-key mismatch -> recompile).

### Option 4 — LoadOnDemand split of SkuDB (NOT recommended alone)
Moving SkuDB into a LoadOnDemand sub-addon loaded after PEW just relocates
the same atomic table construction into visible time — strictly worse felt UX
unless combined with option 2/3 anyway. Only useful later as packaging (e.g.
shipping the DB separately like SkuAudioData_fast_de already is).

## 7. Recommended path

1. Option 0 now (one evening, mostly the user pressing reload with a
   stopwatch addon doing the timing).
2. Option 1 next — it directly removes the regression that made the current
   state feel WORSE, and 1f de-risks all further spreading.
3. Then commit to option 2, and treat option 3 as its second phase once the
   chunked-string pipeline and consumer guards exist.

## Addendum 2026-07-05 (same day, after implementation)

While implementing option 1 a better explanation for the post-load second
freeze surfaced: the "async" waypoint-cache build only time-sliced the
CREATURE pass. The object pass, the ~50k-record custom/route-waypoint pass,
and the whole link phase (CheckAndUpdateProfileLinkData, the resolution loop,
SaveLinkDataToProfile, CleanupWaypoints) each ran as ONE coroutine slice =
one frame each, in visible time after the screen fades. That matches a felt
2-3 s freeze shortly after loading far better than the GC theory alone.

Implemented (commits of 2026-07-05):
- All build passes and link helpers now yield cooperatively (~10 ms/frame);
  the yield helper is a no-op for their normal synchronous callers.
- Current-continent-first rounds inside the creature and object passes
  (append-only reordering, pass ORDER unchanged -> merge/link semantics
  identical). MetricPoint "current continent meta targets done" records the
  readiness latency.
- SkuNav.wpCacheReady flag + "Wegpunkte werden noch geladen" hint in all nine
  cache-derived nav list menus (instead of a silently wrong "Leere Liste");
  entry is non-actionable like the empty entry (templates.lua guard).
- Forced full GC at first PEW while the loading screen still covers it
  (MetricPoint "forced GC at PEW = X ms, A MB -> B MB").
- !!LoadStopwatch addon (loads first, measures t0 -> PEW -> first frame ->
  settle + frame-spike stats + Lua memory; /lsw; level-up sound when the
  30 s watch window ends), set-addon-config.ps1 (all/none/skuonly/nosku/
  restore, WoW must be closed), _read_stopwatch.py.

Deliberately NOT done yet (pending stopwatch data): SkuAuras PEW chunking
(runs behind the loading screen, wouldn't change felt time, risks half-built
aura lists), stream-budget lowering, /reload-path relocation (PLAYER_LOGIN
fires on /reload too, so the route build is already behind the overlay).
Options 2/3 (DB rework) declined by the user for now - too much subtle-
corruption risk without database experience.

## Key references
- LOAD-PERF-NOTES.md (W3 handoff), _wrap_deferred.py, _readperf.py (this folder)
- Sku/Core.lua:141,338-386,916-965 (perf harness), Sku/SkuDeferredData.lua
- Sku/SkuNav/Core.lua:318-620 (cache coroutine), 3217-3385 (login/PEW),
  2843-2869 (near list), Sku/SkuNav/Options.lua:384-499 (Nahe Routen)
- Sku/SkuAuras/Core.lua:303-365 (PEW build)
- Questie: Database/compiler.lua, Modules/QuestieInit.lua,
  Modules/Libs/ThreadLib.lua, Modules/QuestieCleanup.lua,
  Public/RegisterOnReady.lua
- WowVision: core/WowVision.lua, core/module/Module.lua:263-316,
  tbc/sku/connection.lua:482-572
