# Waypoint-cache memory analysis (stage-4 follow-up)

Date: 2026-07-06. Follow-up to DB-RESTRUCTURE-PLAN.md "Stage 4 results".
Question examined: is the WaypointCache's 221 MB (a) duplicate/stale data,
(b) simply a lot of legitimate data, or (c) something else — and what does
that mean for stage 5 vs the cache-slimming lever?

## Verdict up front

- It is NOT duplicate or stale data. All 144,766 entries are real and unique:
  ~94k auto-generated NPC/object spawn waypoints + 50,708 manual/route
  waypoints (counted in `SkuDB/assets/routedata_global.lua`), ~215k directed
  links. The stage-4 wording "duplicated subtables/per-entry copies" was
  wrong on that point.
- It is ALSO not "just a lot of data". The information content per waypoint
  is tiny — roughly 90-110 bytes (a packed wpId, two world coords, the name
  string). What costs is the REPRESENTATION: each waypoint spends
  ~1.1-1.3 KB of Lua structure to store those ~100 bytes. Overhead factor
  ~10x. 145k waypoints x ~1.2 KB is where the 221 MB figure comes from.
- Consequence: nothing needs deleting, and slimming is possible without
  losing a single waypoint, link, or comment — by changing the SHAPE, not
  the content. Realistic honest saving: ~65-70 MB from the cache itself,
  ~100-125 MB including the dead route-tree halves (lever E below).
- Stage-5 no-go stands (numbers at the end).

## Measured facts (/skudbmem capture 2026-07-06 09:45, plus file counts)

- WaypointCache subtree: 221.3 MB estimate, 597,459 tables, 3,034,108 string
  SLOTS (27.8 MB per-slot text), 2,190,878 numbers.
- Lookup tables on top of that: WaypointCacheLookupPerContintent 13.4 MB,
  WaypointCacheLookupCacheNameForId 13.4 MB, WaypointCacheLookupAll 13.4 MB,
  WaypointCacheLookupIdForCacheIndex 4.4 MB. Together ~44.6 MB.
- Entry count: 144,766 (= LookupAll string count; = IdForCacheIndex
  289,646 numbers / 2).
- Sources: 50,708 waypoint records in the TBC route file
  (`SkuDB/assets/routedata_global.lua`, 18.5 MB source), 49,533 in the WotLK
  file (`routedata_global_wotlk.lua`, 29.7 MB source); the remaining ~94k
  cache entries are generated from NpcData/objectDataTBC spawns at build
  time.
- Unique name text is only ~6.0 MB (that is what each name-keyed lookup
  table shows: 144.8k names, ~43 bytes average). The cache subtree's
  "27.8 MB text" is the per-slot counting artifact of the crude cost model:
  the 15 field-name key strings (name, role, typeId, ...) are interned ONCE
  by Lua but were counted 145k times. Real string memory in the whole
  complex: ~7 MB.
- Per-entry averages that the stage-4 note quoted: 4.13 tables, 20.96 string
  slots, 15.13 numbers per waypoint. Decomposition below shows these are
  fully explained by the record shape — no mystery copies.

## Anatomy of one cache entry (Lua 5.1 x64: ~40 B per hash slot, ~60-70 B
## per table header; numbers live inside slots, they are not heap objects)

A creature/object waypoint record (SkuNav/Core.lua:467 and :537) has 15 hash
fields: name, role, typeId, dbIndex, spawn, contintentId, areaId, uiMapId,
worldX, worldY, createdAt, createdBy, size, spawnNr, links. Custom waypoints
(:617) swap spawnNr for comments. Cost per entry:

- record table: 15 fields round up to a 16-slot hash part = ~640 B + header
  ≈ ~710 B
- links wrapper `{byId = nil, byName = nil}`: the constructor PRESIZES two
  hash slots even though both values are nil = ~150 B — allocated for all
  145k entries, although only the ~50k route waypoints ever get links
- four lookup entries elsewhere (LookupAll, CacheNameForId,
  IdForCacheIndex, PerContinent): ~160 B plus power-of-two rounding
- the unique name string: ~83 B average
- for linked waypoints: byId + byName tables, each link stored TWICE
  (index→distance and name→distance)
- for custom waypoints: the comments tree (aliases the SessionRouteData
  subtable, so it is double-counted between the 221 MB and the 72 MB lines)

Total ≈ 1.1-1.3 KB per waypoint. Cross-check against the capture:
- tables: 145k records + 145k link wrappers + ~100k byId/byName + ~150k
  comment subtables ≈ 540-600k ✓ (597,459 measured)
- numbers: 11 per auto record x 94k + 10 per custom x 50.7k + 3 per directed
  link x ~215k ≈ 2.19M ✓ (2,190,878 measured)
- string slots: 15 keys + name + role + createdBy per record + name in 3
  lookups ≈ 21 ✓ (20.96 measured)

Because the cost model inflates interned strings, the REAL heap cost of the
cache complex is more like ~150-180 MB (cache) + lookups — still by far the
dominant single consumer, but the honest base for savings math below.

## The redundancy is per-FIELD, not per-ENTRY

Of the 15 record fields, only four carry information:
- worldX, worldY — the payload
- name — needed as menu text and lookup key (~43 B unique text)
- links — real topology (route waypoints only)

Everything else is constant, duplicated, or derivable:
- createdAt = GetTime() at build — the SAME value on all 145k entries, zero
  information
- createdBy = "SkuNav" constant (custom wps: from route data)
- size = 1 constant
- spawnNr = duplicate of spawn
- typeId, dbIndex, spawn, areaId — all four are bit-packed inside the wpId
  that BuildWpIdFromData already computes for every entry (and
  GetWpDataFromId already exists to decode it)
- uiMapId, contintentId — functions of areaId (GetUiMapIdFromAreaId,
  InternalAreaTable)
- role — a substring of name (keep it anyway; as an interned shared string
  it is nearly free once the hash bucket has room, see lever A)

Also relevant: nothing in the addon iterates `pairs()` over a cache RECORD
(checked; only links.byId/byName are iterated), so derived fields can be
served by a shared `__index` metatable transparently — every existing field
READ keeps working, and code that WRITES a field (worldX updates, createdBy
on newly created wps) simply shadows the default, which is correct behavior.

## Slimming levers, ranked (savings in REAL bytes, not cost-model MB)

### A. Slim the record + shared __index metatable — ~44 MB, low risk
Store only: name, wpId, worldX, worldY, role, plus links/comments where
present. 5-7 fields fit an 8-slot hash part: ~390 B instead of ~710 B.
A single shared metatable derives typeId/dbIndex/spawn/areaId (decode wpId),
uiMapId/contintentId (via areaId), createdAt/createdBy/size/spawnNr
(constants/dupe). No consumer sweep needed for reads; writes shadow.
Touch points: the three record constructors in CreateWaypointCache, plus
CreateWaypoint/UpdateWaypoint paths (Core.lua ~3670-3770) that build records
elsewhere. Watch item: SkuMM reads tWP.spawnNr (derived — fine).

### B. Lazy links wrapper — ~14-21 MB, low-medium risk
Stop pre-allocating `{byId=nil, byName=nil}` for all 145k entries; ~94k
auto waypoints never get links. Either create the wrapper lazily in
LoadLinkDataFromProfile (it already assigns .links.byName = {} — make it
assign the whole wrapper), and give the metatable an `__index` fallback that
returns a shared read-only empty wrapper for `.links` reads (safe ONLY if
the one write site creates the real wrapper first — verify no other write
sites; grep found assignments only in the loader and constructors).

### C. Drop the byName/byId double storage of links — ~5-8 MB, medium risk
Every directed link is stored twice (~215k x 2). byName is derivable from
byId via the record names. Consumers use byName heavily in the meta-path
search, so this needs either an accessor or perf care. Cheapest lever per
risk is NOT this one — defer.

### D. Derive WaypointCacheLookupCacheNameForId — ~7 MB, low risk
name→wpId is exactly LookupAll(name→index) composed with record.wpId (once
lever A stores wpId). Replace the table with a small function; it is
rebuilt/patched in only a few places (CreateWaypointCache, link loader).
Note: replacing PerContinent's name VALUES with `true` saves nothing real —
strings are interned; the slot costs the same. Skip that.

### E. Free the dead route-tree halves — ~40-55 MB, medium risk (route land)
On the TBC client LoadDefaultMapData wires SessionRouteData.Waypoints to
SkuDB.routedata.global.Waypoints but SessionRouteData.Links to
SkuDBTMP.routedata.global.Links (Core.lua:3426-3435). Consequence:
- SkuDBTMP.routedata.global.Waypoints/WaypointsNew (49,533 records, the
  bulk of SkuDBTMP's 61.2 MB) is never read on TBC
- SkuDB.routedata.global.Links is only read by the one-time wotlkMapReset
  branch (Core.lua:3462) and custom-map-data resets
Nil-ing both after wiring (keeping the reset paths working, e.g. re-run the
builder on demand via Sku:EnsureData) frees roughly 40-55 MB. This touches
the plan's route landmines (SessionRouteData aliasing, login merge order) —
needs its own consumer audit before implementation, including the
SkuDBTMP.SessionRouteData read mentioned at Core.lua:2694.

## Totals and the stage-5 comparison

- Levers A+B+D: ~65-70 MB real, all inside SkuNav/Core.lua, no format
  change, no SavedVariables contact, verifiable with the existing
  fingerprint tool plus a cache-diff capture (records compare equal
  field-by-field through the metatable).
- Plus lever E: ~100-125 MB real total from the nav complex.
- Stage 5 (binary codec for the five phase-B datasets) addresses a
  cost-model 150-200 MB — but those trees are number-heavy (numbers are
  real 16-B slots, less inflation), so real maybe 120-160 MB — for weeks of
  codec work, golden vectors, SavedVariables cache machinery, and format
  risk. The cache levers reach a comparable order of magnitude in days,
  in-place, revertible per lever.
- Decision CONFIRMED: stage 5 stays no-go. Implement A first (biggest,
  safest), then B+D, then audit E separately.

Secondary benefit: ~300k fewer table allocations at login shortens the
async cache build and reduces GC pressure (the load-perf report identified
Sku's heap size as the GC-stall multiplier).

## Lever A implemented (2026-07-06, in-game test PENDING)

Changes (all in `Sku/SkuNav/Core.lua` + `Sku/SkuDBTools.lua`):
- `WpRecordMT` shared metatable + `WpDerivedFields` near the cache locals:
  derives dbIndex/spawn (wpId decode via GetWpDataFromId), spawnNr (=spawn),
  uiMapId (GetUiMapIdFromAreaId, memoized), contintentId (InternalAreaTable),
  createdAt (build-time constant `tWpCacheBuildTime`), createdBy ("SkuNav"),
  size (1), role (""). comments has deliberately NO default (SkuMM/Options
  materialize their own table; a shared default would be cross-mutated).
- The three build constructors now store only: name, typeId, areaId, wpId,
  worldX, worldY, links (+role on creatures, +comments/createdBy/size/
  contintentId on customs ONLY when they differ from the defaults). All are
  <= 8 fields = 8 hash slots (was 15-16 fields = 16 slots).
- Custom pass: tWpId hoisted before the record; the old fallback
  `comments = {deDE={},enUS={}}` per custom wp is GONE (readers all guard,
  audited); contintentId stored only if it disagrees with the areaId-derived
  one (protects odd route data).
- SetWaypoint's user-created records keep storing all fields (few, and it
  writes them explicitly anyway) but get the metatable for derived reads.
- Field-read audit results the design rests on: nothing iterates pairs()
  over a cache record; ListWaypoints2's hot loop reads typeId/uiMapId →
  typeId+areaId stay STORED (free, the 8-slot bucket had room), uiMapId
  derive is one memoized lookup; `.areaid` (lowercase) reads in the
  link-update paths are a PRE-EXISTING nil-read quirk and behave identically.
- Known intentional micro-changes: custom records' spawnNr now answers 1
  (was nil; only read for typeId 2), createdAt is the build start time (was
  per-record GetTime() during the same build; nothing compares it), custom
  comments may be nil (was empty table; all readers guard).

Verification:
- `/skudbwpcheck` (new, SkuDBTools.lua): background-sliced walk of all
  records; reads every legacy field THROUGH the metatable with type checks,
  wpId round-trip via the derived dbIndex/spawn against BuildWpIdFromData,
  and consistency of all four lookup tables. Persists SkuDebugLog.wpCheck;
  out-of-game reader `_wpcheck.py` prints PASS/FAIL plus counters.
- Test drill: /reload → wait for "Sku Datenbank bereit" and the waypoint
  cache (no "Wegpunkte werden noch geladen" hint) → `/skudbwpcheck` (expect
  "0 Fehler") → `/skudbmem` (expect the SkuNav.WaypointCache line well below
  221 MB) → route smoke test: select a waypoint, follow a metapath, open a
  waypoint list menu, check a custom wp's comments entry → /reload →
  `py -3 _wpcheck.py` and `py -3 _dbmem.py 8`, BugGrabber/SkuErrorLog clean.

## Lever A first in-game results (2026-07-06, same day)

- User-tested: functionality fine (routes, menus, waypoint use).
- /skudbmem: SkuNav.WaypointCache 221.3 -> 153.7 MB (cost-model metric).
  String slots 3.03M -> 1.81M, number slots 2.19M -> 1.37M — exactly the
  dropped per-record fields; table count unchanged as designed (records,
  links wrappers, and comment aliases still exist). Matches the ~45 MB
  real-bytes prediction for lever A alone.
- /skudbwpcheck: 144,823 records walked, 0 sessionRecords, 0 commentsNil
  (every route waypoint carries an lComments alias — the dropped fallback
  table never fired), 3,653 records with stored overrides (real
  createdBy/size/contintentId from route data — the shadowing works).
- 118 reported "Fehler" were ALL one pre-existing data quirk, NOT a lever-A
  break: 59 waypoints named after trigger NPCs (dozens of distinct npcIds
  all called "Luftüberwachung", no subname) share identical waypoint names,
  so the name-keyed lookups can only point at one of each pair — exactly as
  in every previous version (last-wins). Verified in
  SkuDB/assets/creatures.lua (ids 2614, 2615, 21974, 21993, 21996-22003,
  22063, 22065, 22066, ...). The checker now classifies these as a
  dupNames counter (name -> id -> a record CARRYING that name is the real
  invariant); expect 0 Fehler + ~59 Namensdubletten on re-run.

## Readiness gap fixed (same day)

User report: "Sku Datenbank bereit" is spoken, but Shift-F10 still answers
"Wegpunkte werden noch geladen". Cause: the spoken line belongs to the SkuDB
chunk stream; the waypoint-cache build (which ends with the link load that
routes need) starts mid-stream and ran its ~3.0 s of sliced work at a flat
10 ms/frame — 5-10 s of wall time beyond the announcement. Two changes:
- tWpcYield now uses the same budget heuristic as the chunk stream
  (30 ms/frame for the first 8 s after the build starts, then 10 ms) —
  the ~3 s of work fits inside the generous window, cutting the tail to
  roughly a third.
- When the async build completes, Sku now speaks "Wegpunkte und Routen
  bereit" (new locale string, deDE/enUS), so "Datenbank bereit" (menus/DB)
  and navigation readiness are separately announced instead of guessed.
Genuinely-earlier partial readiness (current-continent waypoints + partial
link load before the world rounds) was considered and parked: the link
loader's cleanup pass deletes links whose endpoints are missing, so running
it against a half-built cache would destroy cross-continent route data —
needs its own careful design, lever-B-adjacent.

## Open items before implementation

- Grep-audit ALL write sites to cache records (assignments to record fields
  outside the constructors) so lever A's field list is complete.
- Confirm no serializer walks a cache record with next()/pairs() (none
  found; re-check SkuZOptions export paths).
- Lever B: enumerate every `.links` write site (found: constructors,
  LoadLinkDataFromProfile:762, SetWaypointLinks area ~3895).
- Lever E: consumer audit of SkuDBTMP.* and routedata.global.Links,
  including the wotlkMapReset and custom-map-data branches.
- After each lever: /skudbcheck fingerprint (data unchanged) + /skudbmem
  re-capture (memory delta) + a route-follow smoke test in game.
