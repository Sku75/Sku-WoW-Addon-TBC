# Route link build: why it costs 1.2 s every login, and the plan to fix it

Date: 2026-08-19. Status: **tiers 1 + 3 implemented 2026-08-19, UNTESTED in
game** (see section 10 for what the implementation actually does and what the
data said about the plan's assumptions). Tier 2 and tier 4 are still open.
Written after the
hardcore-realm build-watchdog work (commits 528828a / 90556d6), which made the
cost visible: on a realm that throttles addon scripts the same build stretches
from ~2 s to 10 s of wall time, and the user sits on "Wegpunkte werden noch
geladen" for all of it.

Everything marked **measured** below was taken from the shipped data files or
from the running client. Everything marked **estimate** is a guess until step 0
is done. Do not act on an estimate as if it were a measurement.

## 0. The cost, and where it sits

**Measured** (`SkuDebugLog.wpcResult`, two completed builds on different realms):

```
async done = 1936.7 ms work  (phases ms: creatures 453  objects 38  custom 268  links 1179)   Era
async done = 1955.9 ms work  (phases ms: creatures 484  objects 42  custom 217  links 1213)   hardcore
```

The link phase is ~60% of the whole waypoint-cache build, and the build is the
last thing standing between login and usable navigation. The work is stable
across machines and realms (the two runs differ by 1%); only the wall time
varies, because the frame budget now backs off under load.

## 1. What actually runs today (SkuNav/Core.lua)

`tWpcPhase("links")` covers **four full passes**, not one:

1. `CheckAndUpdateProfileLinkData` (~line 1256) — walks every directed edge
   (~215k on TBC): drops edges whose endpoints are not in the cache, drops
   self-links, and adds the missing reverse edge so the graph is symmetric.
   Mutates `SkuDB.SessionRouteData.Links` in place.
2. The main loop in `LoadLinkDataFromProfile` (~line 1180) — walks them again to
   materialise `links = {byId = {...}, byName = {...}}` on each source record.
   **Every edge is stored twice**, once keyed by cache index and once by name.
3. `SaveLinkDataToProfile()` (~line 1332) — walks all ~50k cache records and
   re-derives `SessionRouteData.Links` back out of the cache, calling
   `WaypointCacheGetIdForName` once per edge.
4. `CleanupWaypoints` (~line 1232) — walks all ~50k records to delete custom
   waypoints that ended up with no links.

Two facts that shape everything below:

- **Nothing is persisted.** `SaveLinkDataToProfile` is a misleading name: it
  writes into the in-memory table and explicitly clears the profile field
  (`SkuSettings:Sub("SkuNav").Links = nil`). `SessionRouteData` is rebuilt from
  the shipped route files at every login. The TOC saves only `SkuOptionsDB`,
  `SkuTranslatedData`, `SkuErrorLog`, `SkuDebugLog`.
- **User edits are session-only.** `SkuNav:SetWaypoint` appends new waypoints to
  `SkuDB.SessionRouteData.Waypoints`, which is that same in-memory table, so a
  hand-made waypoint or link is gone after a relog unless exported through
  importExport (which sets `hasCustomMapData`). Quick and temp waypoints are the
  exception — they live in the settings. This may or may not be intended; it is
  recorded in KNOWN-ISSUES.md as a separate question. For this plan it means the
  link graph is a **pure function of the shipped data**, with no per-user delta
  to merge.

## 2. Measured facts about the graph

Decoded both shipped link tables (wpId packing per `SkuNav:BuildWpIdFromData`)
and mapped both endpoints of every edge to a continent through
`SkuDB.InternalAreaTable`:

- `Sku/SkuDB/assets/routedata_global.lua` (Era): 144,364 directed edges,
  **8** of them cross a continent border — 0.0055%.
- `Sku/routedata_global_wotlk.lua` (WotLK): 192,084 directed edges, **8** cross
  — 0.0042%.

Those 8 are not real crossings. All of them involve areaId 2657, and there are
**two** areas named "Valley of Bones": 2657 in Desolace (Kalimdor) and 3794 in
Hellfire Peninsula (Outland). Exactly two waypoints carry id 2657 while linking
into Hellfire Peninsula (3483) and Expedition Point (3815) — Outland waypoints
whose id was stamped with the Kalimdor area by whatever generated the file, a
name-collision artifact. **The genuine number of cross-continent links is zero.**

Boats and zeppelins do not contradict this: they are carried by waypoint
comments ("warte hier auf das Schiff…") plus a separate connected component on
each shore, not by graph edges.

Edge share per continent (source side), **measured**:

- Era file — Kalimdor 38.1%, Eastern Kingdoms 30.5%, Northrend 16.9%,
  Outland 14.2%, rest 0.3%.
- WotLK file — Kalimdor 28.8%, Outland 24.9%, Northrend 24.5%,
  Eastern Kingdoms 21.4%, rest 0.4%.

So wherever the player stands is roughly a **quarter** of the link work on TBC
(which runs the union of both link sets).

The consumers are already continent-scoped, which is what makes the reordering
in tier 3 cheap:

- `ListWaypoints2` — every waypoint list — *requires* a continent and defaults
  to the player's; without one it returns nothing.
- `GetAllLinkedWPsInRangeToCoords` iterates only
  `WaypointCacheLookupPerContintent[playerContinent]`.
- `GetAllMetaTargetsFromWp5` (the distance flood over `links.byId`) starts from
  the waypoint the player is on and cannot leave its connected component.

## 3. Step 0 — measure before touching anything

Split the single `links` phase counter into four (check / load / save /
cleanup). The phase machinery already exists (`tWpcPhase`), this is a handful of
lines and one login to read `SkuDebugLog.wpcResult`.

Everything in tier 1 is an *estimate* of where the 1179-1213 ms sits. Do not
spend a day optimising pass 3 on a guess.

## 4. Tier 1 — remove redundant work (bundle with tier 3)

Not a behaviour bug; the result is correct. It is the same data walked more
often than necessary.

- Skip pass 3 during the build. Let pass 1 set a dirty flag; on a normal login
  it changes nothing, so the whole re-derive can be skipped. (Runtime link
  edits — `SaveLinkDataToProfile(aWpName)` from the link/unlink paths — are
  unaffected, they take the named single-waypoint branch.)
- Fold pass 1 into pass 2: one walk over the edges instead of two.
- Pass 4 scans all ~50k records but only acts on `typeId == 1`. The custom pass
  already knows exactly which indices those are (~1.5k); collect them into a
  list during that pass and iterate the list.

**Estimate:** 500-800 ms off a ~1950 ms build. Confirm against step 0.

## 5. Tier 3 — build the player's continent first (bundle with tier 1)

Given section 2, this is a **reordering**, not lazy loading: the same total work
in the same coroutine, but the useful part lands first. It is the pattern the
creature and object passes already use ("Round dispatch: current continent
first", `CreateWaypointCache`).

1. Partition the edge walk by the source waypoint's continent — one
   `InternalAreaTable` lookup per link source (71-93k), negligible.
2. Player's continent first, then the rest.
3. Run the cleanup pass **per continent as that continent finishes**. This is
   the one real ordering constraint: it deletes custom waypoints that ended up
   with no links, and a not-yet-processed continent looks exactly like that.
4. Add a per-continent ready flag so the lists and the "still loading" hint stop
   waiting on the global `wpCacheReady`. Two consumers to touch:
   `SkuNav:InjectWpListEmptyHint` and `ListWaypoints2`. The progress percentage
   (`SkuNav:GetWaypointCacheProgressPct`) should report the player's continent
   reaching 100%, not the world.

Worst case if the partitioning is ever wrong: a continent's links arrive later
than intended. No data is lost and nothing is silently missing, because the full
build still completes in the same session.

## 6. Tier 2 — stop storing every edge twice (its own work item)

**Wanted, but deliberately NOT bundled with tiers 1 and 3.** Those two are
redundancy removal in one region of code; this one is a refactor with call-site
risk, and mixing them would make a bisect useless.

`links.byName` duplicates `links.byId`: 20 call sites use `byId`, 14 use
`byName`. Either derive the name on demand (id → record → name) or migrate the
14. Halves the table writes in the materialisation pass and shrinks the cache in
RAM, which matters on the weak machines this project targets.

Do it after tier 1+3 have landed and been verified in game, as a separate
commit.

## 7. Tier 4 — ship the links in the form the runtime wants (wanted, with hard safety rules)

**Goal.** 1.2 s of login work is worth removing; a lot of smaller wins were
fought for in the v42 load-perf work and they were audible. So tier 4 is on the
list — but only under the rules in 7.3, because the failure mode of getting it
wrong is "nobody can use the route data any more", which is far worse than a
slow login.

### 7.1 What it must NOT be

Not a second copy of the graph. A separate cache file (or SavedVariables blob)
holding ~215k edges would add 6-10 MB that WoW parses at every login, before the
addon runs, on the loading screen where nothing can yield — paying twice for the
same data. That kills the idea in that shape.

### 7.2 What it should be

**Change the form of the data that already ships, not add to it.** The generator
(offline, in `dev/`) rewrites the shipped route files so their `Links` section
is *already* pruned and symmetric — exactly the state pass 1 spends its time
producing. The file then declares what it is, e.g.
`SkuDB.routedata.global.LinksNormalized = "<generator version>"`, and the
runtime skips pass 1 when it recognises that marker.

Consequences to work through in the generator, not at runtime:

- **Symmetrisation adds edges.** The normalized file is bigger than today's, and
  the parse cost grows with it. **Open question, must be measured before
  committing to this tier:** run the normalization offline and report the size
  delta of both files. If the file grows enough that the extra parse eats the
  saving, tier 4 is not worth doing.
- **The TBC union breaks per-file purity.** On TBC the live graph is Era
  waypoints + the union of both link sets, and pruning depends on which
  waypoints exist — so "pruned" is not a property of one file in isolation (this
  is the stranding problem from ROUTE-PHASE-RESOLUTION.md). The generator has to
  produce the WotLK file already pruned against the Era waypoint set and
  symmetric over the union, and the Era file normalized for Era clients. Both
  declare their marker separately. This bakes a flavour rule into generated
  data and must be documented in the generator itself.

### 7.3 Safety rules — non-negotiable

The runtime must never *depend* on the artifact being correct.

1. **The live path stays, forever.** Pass 1 is never deleted, never allowed to
   rot. A missing, unrecognised or mismatching marker means: run it live, log one
   line, carry on. No error, no degraded navigation.
2. **The marker is a version, not a promise.** It names the generator version
   and the input identity. Anything the runtime does not recognise → live path.
3. **Verify once per version, in the background, after login.** The first login
   after an addon update runs the full live normalization anyway, *after* the
   user is already navigating, and compares it edge for edge against the shipped
   data. Result is recorded in SavedVariables ("verified" / "mismatch") keyed by
   addon version + marker. Later logins skip the verification and take the fast
   path. A mismatch disables the fast path permanently for that version, logs
   loudly, and speaks a warning.
4. **`/skucheck` gains the invariant** (per the standing rule that every
   regression fix adds its invariant there): "shipped links are normalized and
   match a live normalization".
5. **The release script guards the human.** `installer/release.ps1` refuses to
   publish if a route file is newer than the normalization stamped into it, so a
   maintainer who edits route data and forgets to regenerate cannot ship a stale
   marker. This is the rule that answers "one mistake by whoever maintains this
   next".
6. **Never lose data.** The generator only ever *adds* the reverse edges and
   removes edges the runtime would have removed anyway. If the two ever disagree
   the live result wins (rule 3).

### 7.4 What is left after tier 4

Pass 2 (materialising `byId`/`byName` into the live records) cannot be
precomputed — it references live cache indices — so it stays, halved by tier 2.
That is the floor for this build.

## 8. Order of work

1. Step 0 — split the phase counters, one login, read the numbers.
2. Tier 1 + tier 3 together (they touch the same four functions; doing them
   separately means reworking the same code twice). Verify in game, commit.
3. Tier 2 as its own change, its own commit.
4. Tier 4: first the offline measurement from 7.2 (file size delta). If it
   survives that, build the generator + the safety machinery from 7.3.

## 9. Side findings

- **Two mislabelled waypoints.** The two Outland waypoints carrying areaId 2657
  (section 2) sit in the Kalimdor continent bucket, so they are listed under
  Desolace and are invisible to a player standing in Hellfire Peninsula. Defect
  in the shipped route data, not in the code. Two waypoints, so not urgent.
- **User-created waypoints and links do not survive a relog** (section 1). Worth
  a deliberate decision: intended, or a gap?

## 10. What was implemented (2026-08-19, tiers 1 + 3) and what the data said

Before writing a line of code, every assumption in sections 1-5 was checked
against the shipped data with two new tools:

- `dev/rework-docs/analyze_link_build_assumptions.py` - duplicate names,
  asymmetric edges, cross-continent edges, inbound-only waypoints.
- `dev/rework-docs/simulate_link_build.py` - reimplements BOTH the old four
  passes and the new folded walk in Python over the real Era waypoints + the
  real TBC link union, and diffs the resulting cache and link table.

### 10.1 Assumptions that held

- **Nothing is persisted** (section 1). Confirmed in code: the only writer of
  the profile field clears it, and the export path (`ExportWpAndLinkData`) calls
  `SaveLinkDataToProfile()` itself, so skipping the re-derive during the build
  cannot cost an export anything.
- **Pass 3 is redundant.** Measured: 6 duplicate names among 50,699 live custom
  waypoints, and **not one of them is a link endpoint**, so the re-derive
  reproduces the table it was handed. The simulation confirms it end to end:
  old and new produce an **identical** cache (48,732 surviving waypoints, every
  `links.byId` equal) and an identical link table (50,170 sources / 93,906
  edges), for every choice of "player's continent".
- **Per-continent partitioning is safe** (section 5). Measured: 14
  cross-continent edges in the whole union (the Valley-of-Bones area-id
  collision from section 2), and **zero** waypoints that are reachable only by
  an inbound edge - so no waypoint can lose its links to the ordering.

### 10.2 Assumptions that did NOT hold

- **"Pass 4 only touches ~1.5k records."** Wrong: ~1,500 is the number of
  deleted *tombstones*, not of custom waypoints. There are **50,699** live
  custom records out of ~145k cache records. The index list still removes ~2/3
  of that scan, but it is not the 30x the plan implied.
- **"Pass 1 spends its time symmetrising."** Wrong: the shipped union is
  **already fully symmetric** - 0 missing reverse edges, 0 self links. What pass
  1 actually does is *pruning*: 45,951 of 96,121 sources are ids this cache does
  not know (the WotLK half of the union references waypoints the Era waypoint
  set never had), and 197,072 shipped edges come out as 93,906 live ones.
  **This rewrites tier 4's open question** (section 7.2): shipping the links
  already normalized would make the files *smaller*, not bigger - the symmetry
  half adds nothing and the pruning half removes half the edges. Still needs the
  flavour rule from 7.2 (the WotLK file must be pruned against the *Era*
  waypoint set) and every safety rule from 7.3.

### 10.3 The implementation

`SkuNav/Core.lua`:

- `LoadLinkDataFromProfile(aPlayerContinent)` is now ONE walk over the link
  table. `CheckAndUpdateProfileLinkData` is gone - its pruning happens in place
  while iterating (which Lua allows), and its symmetrisation is done by writing
  the reverse edge straight into the target record. That is what makes the fold
  order-independent, and it also fixes a latent bug: the old pass 1 inserted new
  KEYS into the very table it was iterating with `pairs`, which is undefined
  behaviour in Lua. The new walk collects those and applies them afterwards.
- The re-derive (`SaveLinkDataToProfile()`) is skipped during the build. The one
  case that would make it necessary - an endpoint whose name belongs to another
  record - is counted, and the re-derive runs if that count is ever non-zero.
- `CleanupWaypoints(aOnlyContinentId, aSkipContinentId)` walks the custom-record
  index list the custom pass collects (bucketed by continent) instead of all
  ~145k records, and falls back to the full scan for any caller that is not the
  current build.
- Tier 3: the walk runs the player's continent first, then the rest.
  `SkuNav.wpCacheContinentReady[continent]` flips as soon as that continent's
  links are materialized and cleaned; `InjectWpListEmptyHint`,
  `GetWaypointCacheProgressPct` and the push-refresh of a waiting menu level all
  go by it. Records deleted by the early cleanup are kept recoverable
  (`tWpcCleanupDeleted`) so a late cross-continent edge can put one back - it
  cannot happen with the shipped data, but a silently deleted waypoint is not a
  failure this build may risk.
- Plan step 0 (split the phase counter) is in: `SkuDebugLog.wpcResult` reports
  `linksCur`, `linksRest`, `linksClean` and `linksSave` instead of one `links`.

`SkuDBTools.lua`: `/skudbwpcheck` gained the invariant the new walk has to keep -
every `byId` entry has its `byName` twin, and every edge has its reverse edge.

### 10.4 What to check in game

- `SkuDebugLog.wpcResult`: the four new link phases, and the total against the
  ~1950 ms baseline.
- The waypoint lists must be usable as soon as the player's continent is done -
  `dprint` line "link build: player continent N ready".
- `/skudbwpcheck`: 0 errors (it now also checks link symmetry).
- Route navigation itself: pick a route, follow it, and check a zone that the
  union is known to be delicate about (EPL - see ROUTE-PHASE-RESOLUTION.md).

### 10.5 First in-game run (2026-08-19, 17:19 login)

```
async done = 2085.8 ms work  (phases ms:  creatures 739  objects 67  custom 351  linksCur 807  linksClean 121)
custom wp cache: 50434 added, 278 updated, 1564 deleted tombstones skipped
CleanupWaypoints: disconnected custom waypoints removed: 717  continent  all
link build: stale sources 10833  stale targets 6858  self links 0  reverse edges added 0
```

Correct: routes came up, navigation worked, and the push-refresh fired for a user
who was sitting on the "Wegpunkte werden noch geladen 57%" hint - the list was
announced 2 s later without touching a key.

Two things the run proved:

- **Tier 1 works.** Do NOT compare the total against the 1936 ms baseline: this
  run was simply a slower session (creatures 739 vs 453 for identical work). The
  honest comparison is within the run - the link phase went from 2.60x the
  creature pass to 1.26x, i.e. it was cut roughly in half. `reverse edges added
  0` also confirms in the live client what the offline analysis said: the
  shipped graph is already symmetric.
- **Tier 3 did not run at all** - `continent all` in the cleanup line and no
  `linksRest` phase mean `tWpcCurrentContinent` was nil. `SkuNav:GetCurrentAreaId`
  matches `GetMinimapZoneText()` against the area table, and the minimap zone
  text can still be empty when the build starts right off the SkuDB stream.
  **This is not new code failing - the two-round creature/object dispatch from
  2026-07-05 has been silently dead on login the whole time**, and nothing said
  so. Fixed by retrying the resolution before the link pass (and logging both
  the failure at build start and the late result), so the reordering happens
  where it matters most. Still to verify on the next login: a `linksRest` phase
  in `wpcResult` and `link build: player continent N ready` in the ring.

### 10.6 Second in-game run (17:28 login) - tier 3 alive, and what it cost

```
async done = 2316.0 ms work  (phases ms:  creatures 743  objects 77  custom 345  linksCur 450  linksRest 582  linksClean 119)
```

The continent retry works: two link rounds, the player's continent first. The
lists become usable after ~1615 ms of work instead of ~2316 ms - **~0.7 s
earlier**, which is the whole point of tier 3.

But the split cost real work: the link phase went 928 -> 1151 ms against the
17:19 run (comparable session - creatures 739 vs 743 for identical work). The
plan called the partitioning "one InternalAreaTable lookup per link source,
negligible"; measured it is **+223 ms**, because two filtered `pairs` rounds
resolve every one of the ~96k sources TWICE.

Fixed by walking the link table exactly once: round 1 parks each other-continent
source together with its already resolved canonical cache index in two flat
arrays, and round 2 iterates those - no second traversal and no second
resolution. ~72k numbers, transient. Re-verified with `simulate_link_build.py`:
still identical to the old four passes for every player continent.

### 10.7 Command consolidation (2026-08-19)

The verification tools moved into `/skucheck` as domains (`wp`, `db`, `mem`);
the old `/skudbwpcheck`, `/skudbcheck` and `/skudbmem` stay as aliases because
the dev docs name them. Reason: with three separate commands it was possible to
run "the check" and never touch the waypoint invariants - which is exactly what
happened during this session's testing. A bare `/skucheck` now includes the
waypoint sweep; `db` and `mem` are measurements and stay opt-in. All three log
their result into the SkuDebugLog ring as `skucheck ...` lines (the waypoint
violations too, which used to be readable only in SavedVariables), and `db` now
reports how many datasets changed against the previous capture.

### 10.8 Verified in game (2026-08-19) - TESTED OK

Final login of the session (17:42), with the single-traversal walk:

```
async done = 2191.3 ms work  (phases ms:  creatures 764  objects 74  custom 321  linksCur 414  linksRest 501  linksClean 117)
skucheck wp done: 146922 records checked, 0 violations (verlinkt 84384, Namensdubletten 57, Sitzung 0)
```

- **`/skucheck wp`: 0 violations** over 146,922 records, including the new
  invariants (every `byId` entry has its `byName` twin, every link has its
  reverse edge) across all 84,384 linked records.
- **The result does not depend on where the player stands.** Tested from three
  continents; the disconnected-custom cleanup always removes 717 in total, only
  the split moves: Kalimdor 108 + 609, Eastern Kingdoms 111 + 606, Outland
  21 + 696. `stale sources 10833 / stale targets 6858 / self links 0 / reverse
  edges added 0` is identical in every run, on any continent, and identical to
  the pre-tier-3 run.
- **Link phase over the session:** 928 ms (one round, tier 1 only) -> 1151 ms
  (naive two-round tier 3) -> 1032 ms (parked-source list). The ~100 ms that
  remain above the unpartitioned build are what tier 3 costs; it buys the
  player's own continent being ready ~0.7 s earlier, which is the wait the user
  actually sits through.
- No restore of a cleaned waypoint ever fired (the safety net for
  cross-continent inbound edges), as the offline analysis predicted.

## 11. Tier 4 re-evaluated after tiers 1+3 (2026-08-19) - RECOMMEND DROPPING IT

Section 7 asked for one measurement before committing to tier 4: the size delta
of the normalized files. Done, plus the two questions tier 1 changed
(`dev/rework-docs/analyze_tier4_payoff.py`, exact byte accounting, not estimates).

### 11.1 The headline saving is already banked

Tier 4's promise was "pass 1 becomes a no-op" - worth ~half the link phase when
pass 1 was a full separate walk. Tier 1 folded that pass INTO the materialisation
walk, so what pruning still costs at runtime is: one failed lookup for each of
the ~10,833 dead sources (their edges are never even iterated - the source entry
is dropped whole) and ~3 lookups for each of the 6,858 dead edges. Order of a few
milliseconds. **There is no runtime saving left for tier 4 to collect.**

### 11.2 The data saving is 1-2%

Shipped, both files together: 165,480 source lines and 336,448 edge lines,
13.6 MB of links inside 51 MB of route data. The runtime drops 6.5% of the
sources and a further 2.0% of the edges. Priced with the real per-line byte
costs, and bracketing the edges hanging below a dropped source between 1 and the
average fan-out of 2.0:

```
0.71 - 1.00 MB saved   = 5.2 - 7.4% of the links sections
                       = 1.4 - 2.0% of the shipped route data
```

### 11.3 And the generator would be harder than section 7.2 assumed

**47% of the link endpoints are not route waypoints.** Of 96,121 distinct source
ids in the TBC union, 45,033 are creature or object ids (Era file: 20,147
creature + 2,091 object sources; WotLK file: 39,451 + 5,329). Only 51,088 are
custom waypoints, and of those the Era waypoint list resolves all but 918.

So "pruned" cannot be decided from the route file at all - it depends on the
SkuDB creature and object tables, which are generated separately and change with
every data update, and even on a user SETTING (`showGatherWaypoints` decides
whether gather objects enter the cache, so an edge that is dead by default is
live for that user). The release-script guard from 7.3 would have to cover every
one of those files, and the generator would have to normalize against the UNION
of all configurations to stay safe.

**Verdict: not worth it.** A few ms of runtime, 1-2% of the data, in exchange for
an offline generator coupled to four generated datasets plus a user setting, a
per-version background verification, a `/skucheck` invariant and a release guard.
Tier 4 is dropped unless something changes the numbers.

### 11.4 The prize is next door, and it is much bigger

Measured this session, from the client's own metric point:

```
deferred build 'routes' construct = 736.7 ms, GC = 166 ms, 538 MB -> 439 MB
```

That is ~0.9 s of login - comparable to the whole link phase we just halved - and
**waypoints, not links, are 73% of the shipped route bytes** (37 of 51 MB; Era
14.9 MB waypoints / 4.6 MB links, WotLK 22.1 MB / 9.0 MB).

The WotLK file's waypoint half is built and then **explicitly thrown away**:
`LoadDefaultMapData` nils `SkuDBTMP.routedata.global.WaypointsNew`, `.Waypoints`,
`.WaypointLevels` and `.SequenceNumbers` right after merging the links (only the
links are the live union). On Era the whole WotLK file is unused. Grep confirms
the only other reader of `SkuDBTMP` is the memory tool.

So ~22 MB of the 51 MB is parsed, built into tables and dropped unread at every
TBC login, and ~31 MB at every Era login. Bytes-proportional that is **~320 ms on
TBC and ~450 ms on Era**, plus the transient memory behind the 538 -> 439 MB line.

Unlike tier 4 this needs no marker, no verification and no release guard: the
runtime would simply not build a table it nils moments later. The work is in the
file wrapper (`_wrap_deferred.py`) - emit the waypoint and link sections as
separate builders so the flavour can pick.

**Next measurement (instrumented 2026-08-19, read it on the next login):**
`Sku:EnsureData` now times each builder separately, so the metric point reads
`construct = X ms (SkuDBBuildRouteWotlk N  SkuDBBuildRouteGlobal M)`. That prices
the WotLK file exactly instead of by byte share.

## 12. Tier 2 done (2026-08-19) - links.byName removed

Every link was stored twice on every record: `byId` (target cache index ->
distance) and `byName` (target name -> distance). `byName` is gone; the 14 call
sites are migrated to `byId`.

What replaced it: `WaypointCacheGetIdForIndex(aIndex)`, the index-side twin of
`WaypointCacheGetIdForName`, next to it in SkuNav/Core.lua. Same semantics (temp
waypoints answer nil, SetWaypoint-created records compute their id from their
stored fields). The profile writer is now *cheaper* than before, not just
smaller: it used to turn every target name back into an id through
`WaypointCacheGetIdForName` (name -> lookup -> record -> id); from `byId` it
already has the record.

Call sites migrated:

- the link walk (2 writes per edge -> 1)
- `SaveLinkDataToProfile`, both branches
- `DeleteWpLink`, `CreateWpLink`, `UpdateWpLinks`
- `SetWaypoint` (the empty-links literal)
- `DeleteWaypoint`
- `SkuMM`'s two route-drawing passes - they key their frame table by NAME, so
  they resolve the target record and take its name

Three latent bugs died with it, all on lines this had to touch anyway:

1. `DeleteWaypoint` had a second loop over `byName` that only ever cleared the
   deleted waypoint's own entry against ITSELF, once per link - a self-link,
   which cannot exist. It did nothing except risk a nil index on
   `SessionRouteData.Links[ownId]`.
2. The surviving loop built its ids from `.areaid` (the field is `areaId`), so
   every id was computed with the default area 1 and the profile-side unlink
   silently missed. Fixed, and the write is guarded now.
3. `SaveLinkDataToProfile(aWpName)` indexed `Links[nil]` for a temp waypoint and
   called `pairs(nil)` for a record that had no links at all. Both guarded.

`/skucheck wp` keeps the same number of link invariants: the byName-twin check
is replaced by "every link points at the CANONICAL record for that name", which
is the property the walk actually relies on.

**Memory, before (this session's `/skucheck mem`, for the comparison after):**

```
SkuNav.WaypointCache   tables 535115  strings 1749425  stringBytes 18656261  numbers 1372231  est 149802 KB
```

Expect roughly 84k tables and ~190k string slots less (one `byName` table per
linked record, one key per directed edge); the estimator should drop by ~15-20
MB, real Lua memory by ~10 MB. Measure with `/skucheck mem` and compare the
`SkuNav.WaypointCache` line.

### 12.1 Tier 2 verified in game (2026-08-19 23:49) - TESTED OK

```
async done = 2143.4 ms work  (phases ms:  creatures 705  objects 84  custom 365  linksCur 411  linksRest 463  linksClean 115)
skucheck wp done: 146922 records checked, 0 violations (verlinkt 84384, Namensdubletten 57)
SkuNav.WaypointCache|464842|1524986|12846374|1228045|0|127619     (tables|strings|stringBytes|numbers|booleans|estKb)
```

Routes work, no errors, `/skucheck wp` clean - including the replacement
invariant (every link points at the canonical record for its name).

**Memory.** Against the recorded baseline
`535115|1749425|18656261|1372231|0|149802`:

```
tables       -70,273
strings     -224,439
stringBytes  -5.8 MB
estimate      -22 MB   (149.8 -> 127.6 MB)
```

Read that as a LOWER bound. The baseline capture is the July one (its
`WaypointCacheLookupAll` holds 144,766 names against today's 146,865 - the
2026-08-13 route data update added 2,099 waypoints), so today's cache is
carrying *more* data than the baseline and still measures 22 MB less. The
byName half itself was 84,384 tables plus one string key and one number value
per directed edge; `/skucheck wp` now counts those edges (`Kanten`), so the next
run pins the number exactly instead of inferring it from the deltas.

The link phase also came down a little, 1032 -> 989 ms, which is the second
write per edge disappearing.

### 12.2 The route builders, now measured separately

```
deferred build 'routes' construct = 729.8 ms (SkuDBBuildRouteWotlk 375  SkuDBBuildRouteGlobal 355), GC = 157 ms, 538 MB -> 438 MB
```

So section 11.4's estimate holds: the WotLK file costs **375 ms** at every
login, and 71% of its bytes are the waypoint half that `LoadDefaultMapData`
throws away unread - **~265 ms recoverable on TBC, the full 375 ms on Era**,
where the whole file is unused. That is now the biggest single item left in the
route-data path, and unlike tier 4 it needs no safety machinery.
