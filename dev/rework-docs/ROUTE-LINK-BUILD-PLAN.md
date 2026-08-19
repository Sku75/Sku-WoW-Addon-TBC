# Route link build: why it costs 1.2 s every login, and the plan to fix it

Date: 2026-08-19. Status: **plan agreed, not started.** Written after the
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
